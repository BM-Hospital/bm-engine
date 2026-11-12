# Native Node.js addon

`bm-engine` on Node.js (and Bun / Deno, which use the same `node` export condition) can run the engine as a
native Node-API addon instead of WebAssembly. It is the same Zig source, the same public API (`js/engine.mjs`
is the only implementation of it) and the same output, byte for byte; it is faster, and the asynchronous
methods really run off the main thread.

```js
import { Renderer, backend } from "bm-engine"; // backend: "native" when the addon is installed, else "wasm"
const r = new Renderer();
r.registerFont(font);
const png = await r.render(node, { width: 1200, height: 630 }); // on a libuv pool thread
```

Contents: [selection and fallback](#selection-and-fallback) · [architecture](#architecture) ·
[adding an output kind](#adding-an-output-kind-eg-pdf) · [threading](#threading) · [memory](#memory) ·
[stack](#stack) · [bit-identical output](#bit-identical-output) · [building](#building) · [packaging](#packaging) ·
[what is verified](#what-is-verified) · [limits](#limits-and-known-gaps)

## Selection and fallback

| import | Node.js / Bun / Deno | browsers, workerd, edge |
| --- | --- | --- |
| `bm-engine` | native addon if it loads, **else wasm, automatically and silently** | wasm (`js/index.mjs`, never sees the loader) |
| `bm-engine/native` | native addon, or the import throws | not available |
| `bm-engine/core`, `/standard`, `/full` | always wasm (`/full` = the same feature set as native) | wasm |

`bm-engine/wasm` already names the raw `.wasm` file, so "wasm on Node, no matter what" is spelled
`bm-engine/full` (or the environment variable below); no new subpath was added for it.

Environment variables (read once, when `bm-engine` is imported):

| variable | effect |
| --- | --- |
| `BM_ENGINE_BACKEND=wasm` | never try the addon |
| `BM_ENGINE_BACKEND=native` | require it: the import throws `bm-engine: BM_ENGINE_BACKEND=native, but the native addon is not available (<why>)` |
| `BM_ENGINE_NATIVE_PATH=<file.node>` | the only place the addon is looked for (a missing or unloadable file means wasm) |
| `BM_WASM`, `BM_PROFILE` | name a wasm binary, as before; they also select the wasm backend unless `BM_ENGINE_BACKEND=native` |

Where the addon is looked for (`js/native.mjs`, nothing in it throws): `$BM_ENGINE_NATIVE_PATH`; else a
checkout's `native/dist/<name>/bm-engine.<name>.node`; else `require("bm-engine-<name>")`, the per-platform
package whose `main` is the `.node` file (see [packaging](#packaging) for how this survives bundlers). `<name>` is one of

    win32-x64-msvc   win32-arm64-msvc   darwin-x64   darwin-arm64
    linux-x64-gnu    linux-x64-musl     linux-arm64-gnu   linux-arm64-musl

On Linux the C library is detected (`/etc/alpine-release`, then `process.report`'s `glibcVersionRuntime` /
shared objects, then `/usr/bin/ldd`); if the detected variant does not load, the other one is tried. An addon
whose `abi` export differs from `NATIVE_ABI` in `js/native.mjs` is ignored (a stale platform package can not
be half-used).

What differs for the user between the backends: `backend`; `init()` / `initSync()` are no-ops natively (they
resolve to the addon's exports); `memoryBytes()` is the addon's live allocation instead of the wasm memory
size; `loadWoff()` (`bm-engine/woff`) has nothing to load natively and returns `{ builtIn: true }`, and the
addon's WOFF decoder also serves the wasm `core` entry in the same process. Nothing else.

## Architecture

```
js/index.mjs, core.mjs, ...   js/node.mjs ──────────► js/native.mjs ── require ──► bm-engine.<name>.node
        │ createBinding()          │ createBinding(undefined, nativeBackend(addon))        │ src/native.zig
        ▼                          ▼                                                       │   N-API glue, threads
   js/engine.mjs: Renderer, option marshalling, fonts, prepare, ...  (ONE implementation)  │ src/native/ops.zig
        │                                                                                  │   operation table
        ▼ backend.run(handle, op, arg0, arg1, input, options, attachments, text)           ▼
   wasm backend (in engine.mjs): bm_* exports      native backend (native.mjs): addon.run / addon.runAsync
        ▼                                                                                  ▼
   src/wasm.zig ───────────────────────────► src/render.zig (the engine) ◄─────────────────┘
```

`js/engine.mjs` no longer touches wasm exports outside one block, the *backend*:

```
name                 "wasm" | "native"
ready()              false until usable (wasm before init)
has(op)              whether the build provides the operation
create() -> handle   a renderer;  destroy(handle)
run(handle, op, arg0, arg1, input, options, attachments, text) -> Uint8Array | string
runAsync?(...)       -> Promise of the same; optional (native only)
memoryBytes()
```

One engine *operation* = the op name, two integers, two texts and a list of binary attachments in; bytes out.
`attachments` is a flat array of `[key, bytes, flags, width, height]` groups; for rendering operations they
are the call's image sources (`flags` bit 0: raw RGBA of `width` x `height`, bit 1: premultiplied). The
`Renderer` methods build a *job* (`#call`, `#animation`: validation, JSON, attachments) and hand it to `#run`
(calling thread) or `#runAsync` (the backend's `runAsync` when it has one). The wasm backend performs exactly
the export calls the binding made before the refactoring, so nothing changes for wasm users.

Why this shape and not "the addon exposes the wasm export table over native memory": the wasm protocol is a
conversation (clear images, put image, put image, render, read result, release) over one linear memory. It
can not be handed to a worker thread as a unit, and two overlapping conversations on one renderer would
corrupt each other. A job is self-contained, so it can be snapshotted and executed anywhere.

The addon's JS-visible surface (internal; versioned by `abi`):

```
abi, features, ops: { name: index }
create() -> handle (an external; GC frees it)      destroy(handle)
run(handle | null, opIndex, arg0, arg1, input, options, attachments) -> Uint8Array
runAsync(...same...) -> Promise<Uint8Array>
memoryBytes()        tune(stackMode, stackBytes, maxBytes, zeroedBuffers)   // test hook; js/native.mjs sets zeroedBuffers on V8
```

`arg1` of an async `render` call is a size hint: the byte length of the raw frame when `format` is `"raw"` and
both `width` and `height` are given (0 otherwise; `js/engine.mjs` computes it). See [memory](#memory).

## Adding an output kind (e.g. PDF)

Nothing in the N-API glue, the loader or the threading changes. Three small additions:

1. **Zig, `src/native/ops.zig`**: one entry in `table` and its function. `Call` gives the renderer (already
   locked, on a thread with enough stack), the two integers, `input`, `options` and the attachments; the
   function sets `c.result`.

   ```zig
   .{ .name = "pdf", .images = true, .run = pdf },
   .{ .name = "pdfMeasure", .images = true, .run = pdfMeasure },

   fn pdf(c: *Call) Error!void {
       c.result = try c.r.?.renderPdf(sourceKind(c), c.input, c.options);
   }
   ```

   `images = true` registers the attachments as image sources (what `#putImage` / `#putRgba` queue) before
   the call and clears them after it. A result that lives in the renderer (arena / canvas) is copied out and
   `releaseResult()` is called for you; for a result allocated with `c.gpa` set `c.owned = true`. Errors:
   return `error.OutOfMemory` or `error.Invalid` (message: `r.err`, or `c.err`).
   The table index is not ABI: JavaScript reads `addon.ops`.

2. **JS, the wasm backend in `js/engine.mjs`** (`backend.run`): map the op to the wasm export. For an export
   with the `(handle, kind, source, options)` signature it is one entry in `SOURCE_OPS`:

   ```js
   const SOURCE_OPS = { ..., pdf: ["bm_render_pdf"], pdfMeasure: ["bm_measure_pdf"] };
   ```

3. **JS, the public method in `js/engine.mjs`**: build the job and run it. Ported from the wasm-only version
   of `renderPdf`, the body keeps using `#prepareSource`, `#putImage` and `#stringify` unchanged (they now
   queue attachments instead of writing into wasm memory); only the tail changes:

   ```js
   #callPdf(which, node, options) {
     ...                                   // validation, requireFeature("pdf"), as before
     const [json, kind] = this.#prepareSource(node, options, () => (text = this.#pdfOptionsText(options)));
     return { op: which === "render" ? "pdf" : "pdfMeasure", kind, text: json, opts: text, atts: this.#atts };
   }
   renderPdfSync(node, options = {}) { return this.#run(this.#callPdf("render", node, options)); }
   async renderPdf(node, options = {}) {
     [node, options] = unwrap(node, options, "render");
     return this.#runAsync(this.#callPdf("render", node, await this.#extras(options)));
   }
   measurePdfSync(node, options = {}) { return JSON.parse(this.#run(this.#callPdf("measure", node, options), true)); }
   ```

   (`#run(job, true)` returns the result decoded as text.) There is no `#takeBytes` / `#takeString` /
   `copyInString` / `check(status)` in a method any more: that is the wasm backend's business.

A feature that is compiled out natively shows up as a missing bit in `features` (same `feature_bits` as wasm),
so `requireFeature("pdf")` keeps working; an op name the addon does not have makes the native backend throw
`bm-engine: <op> is not supported by this native build`. To ship PDF in the addon, enable the feature for the
native build (`zig build native -Dpdf=true`, or in `scripts/build-native.mjs`) and add its fixtures to
`bench/native-identity.mjs`.

## Threading

* `*Sync` methods, `registerFont`, `unregisterFont`, `clearFonts`: on the calling thread.
* `render`, `renderAsDataUrl`, `renderSvg`, `measure`, `renderAnimation`: `addon.runAsync` copies the inputs
  (strings, option JSON, every attachment) into native memory **at the call**, creates a promise and a
  `napi_create_async_work`; the engine runs in the libuv pool, the promise is settled back on the JS thread.
  Later changes to the caller's buffers (including transferring or detaching them) cannot affect the render.
  `fonts` / lazy `images` options are resolved on the JS thread first, as before.
* The engine has **no global mutable state** (the Windows binary's whole `.data` section is 280 bytes: the
  host function table and the allocation counter; the wasm-only page allocator is not compiled in). A
  `Renderer` owns everything it mutates: arena, scratch, glyph / shape / image caches, font collection.
* A renderer is not re-entrant, so calls on **one** renderer are serialised:
  async calls go through a per-renderer FIFO in the addon (only one of them occupies a pool thread at a
  time, the others wait in the addon, not in libuv's queue), and sync calls take the renderer's mutex (a sync
  call made while an async one is executing waits for it). Completion order = call order.
* **Different renderers run in parallel**, up to the pool size (`UV_THREADPOOL_SIZE`, default 4). For
  parallel throughput create one renderer per concurrent job (a small pool of renderers with the same fonts).
  A shared-font context pool inside one renderer was not built: the font collection mutates during rendering
  (variable-font instance cache, eviction counters, shape plans keyed by face id), so sharing it would need
  either locks in the text hot path or a redesign of those caches.
* Lifetime: the JS handle is an N-API external with a finalizer; each pending job holds a reference to the
  native handle. `free()` marks the handle closed and frees the engine renderer immediately, or, if a job is
  executing, as soon as that job completes; jobs still queued behind it reject with
  `bm-engine: renderer has been freed`. Dropping the last JS reference while jobs are pending is fine: they
  complete, then the memory is released. Environment teardown (worker termination) cancels what is queued.
* Worker threads: the addon is context-aware (exports `napi_register_module_v1`, no static registration);
  per-environment state lives in N-API instance data. Any number of workers can load it concurrently.

## Memory

* Allocator: the C library's `malloc` (Linux, macOS), the process heap (`HeapAlloc`) on Windows, where no C
  runtime is linked at all. Per-render memory is the engine's own bump arena on top, as in wasm.
* Each renderer's allocator counts its bytes and is capped (4 GiB, the wasm address-space size): beyond it
  the engine reports `out of memory` exactly as the wasm build does instead of exhausting the machine. The
  engine's own limits (canvas size, animation bytes, ...) are shared code and apply unchanged.
* The count is reported to V8 with `napi_adjust_external_memory`, so garbage collection sees the fonts and
  caches behind a dropped `Renderer` and collects them without an explicit `free()`.
* `memoryBytes()` = bytes currently allocated through the addon in the process (0 after everything is freed).
* Results are ordinary `Uint8Array`s on an `ArrayBuffer` V8 allocated (transferable, no finalizer). An encoded
  result is copied into it once. A **raw frame is not copied at all** where that is possible: the renderer
  paints it straight into the result's buffer (`Renderer.raw_target` in `src/render.zig`, `Exec.rawTarget` in
  `src/native.zig`). Sync calls create the `ArrayBuffer` during the call, once layout knows the size. Async
  calls cannot touch V8 from the pool thread, so `runAsync` creates the buffer before queueing the job when the
  size hint says how large the frame will be, and the job paints into it (nothing in JS can see the buffer
  before the promise settles). Without a hint, with a wrong one, or for a sync call that had to move to a
  helper thread, the frame is painted into zeroed process memory and copied once on the JS thread. On V8 the
  new buffer is known to be zero-filled, so the canvas is not even cleared; other engines clear it first
  (`tune(0, 0, 0, 1 | 2)`).
  External buffers (`napi_create_external_arraybuffer`) were **not** used for this: Node.js marks them
  untransferable (a `postMessage` transfer list would throw), their finalizers only run when the event loop
  turns (a loop of `renderSync` calls would accumulate every frame), and hosts with the V8 sandbox reject them.
* All failures become JS exceptions / promise rejections with the wasm build's messages.

## Stack

The engine recurses once per nesting level in several phases. The depth is bounded by shared limits
(`render.max_node_depth` = 512 node levels, the layout engine's own 512, the JSON / CSS / selector / SVG
parsers' caps), which were sized for the 1 MiB wasm stack. Natively the frames are a different size and a
stack overflow is a dead process rather than a catchable trap, and the thread a call arrives on is not ours:
the main thread (8 MiB on most systems, less after deep JS recursion), a libuv pool thread (libuv sizes them
from `RLIMIT_STACK`; other hosts may not), a worker thread (4 MiB by default, configurable down), secondary
threads on macOS (512 KiB) or musl (128 KiB) when created with default attributes.

So every engine call first asks how much stack the calling thread has left
(`GetCurrentThreadStackLimits`; `pthread_getattr_np`, with `RLIMIT_STACK` for the initial thread;
`pthread_get_stackaddr_np` / `pthread_get_stacksize_np`). With at least `stack_need` = **3 MiB** left it
runs inline. Otherwise, or when the bounds cannot be determined, it runs on a temporary thread created with
exactly that much stack (`CreateThread` / `pthread_create`), and the caller waits. The measured worst case over the
deepest accepted inputs is 768 KiB on x86-64 (see [what is verified](#what-is-verified)).

## Bit-identical output

Same source, same algorithms; what could differ between wasm32 and a 64-bit native target, and what is done
about it:

* **Floating point.** Zig compiles in strict float mode: no fast-math flags, and no `contract` flag, so LLVM
  may not fuse `a * b + c` on any target. x86-64 is built for *x86-64-v2* (`build.zig` fixes the CPU
  level whatever `-Dcpu` or the host says): SSE4.2, no AVX, no FMA instruction exists to fuse into.
  arm64 has FMA in its baseline, so `scripts/build-native.mjs` scans every arm64 artifact's code for fused
  multiply-add instructions (`fmadd`/`fmsub`/`fnmadd`/`fnmsub`, `fmla`/`fmls`) and requires exactly the explicit
  ones: two `std.math.lerp` calls (`@mulAdd`, in the wavy text-decoration code), which are fused on *every*
  target by definition (in software on wasm and x86-64). `--explain-fused` lists them by function. In
  addition the addon checks at load time, with volatile operands, that scalar and vector `a * b + c` round
  twice on the machine it runs on; if not it refuses to register and JavaScript falls back to wasm.
* **Math library.** `sin`, `cos`, `exp`, `log`, `pow`, ... are Zig's `std.math` / compiler-rt code inside the
  binary on every target. `floor`, `ceil`, `trunc`, `round` and `fmod`, which LLVM turns into C library calls
  where the CPU lacks an instruction, are provided by `src/native/libm.zig` (strong, hidden symbols; integer
  bit manipulation) so that no target binds them to its platform libm. The build script fails any artifact
  that imports a math function.
* **Pointer width.** No output-relevant code depends on `usize` width, pointer values or allocation addresses
  (hash maps are keyed by content; nothing iterates in address order): the fixture and fuzz comparisons below
  are the evidence.
* **Float to int conversions, NaN payloads, min/max of signed zeros** differ between wasm, x86-64 and arm64
  only for out-of-range / NaN inputs; they are covered empirically on x86-64 by the comparisons below and are
  not executed on arm64 here (see limits).

## Building

```
zig build native -Dtarget=<zig triple> [-Dnative-optimize=fast|safe|small|debug] [-Dnative-strip=false]
    -> zig-out/native/bm-engine.<name>.node

npm run build:native                       all eight targets -> native/dist/<name>/bm-engine.<name>.node
node scripts/build-native.mjs --target=linux-x64-musl,darwin-arm64
node scripts/build-native.mjs --verify-only
node scripts/build-native.mjs --explain-fused
```

Everything cross-compiles from one machine with Zig 0.17 alone: no node-gyp, no node headers (the `napi_*`
functions are declared in `src/native/napi.zig`), no C or C++ compiler, no SDKs. `native/dist/` is build
output (git-ignored) with a `manifest.json` (sizes, hashes, verification facts).

| name | zig target | how Node-API symbols are bound |
| --- | --- | --- |
| `win32-x64-msvc`, `win32-arm64-msvc` | `x86_64-windows-gnu`, `aarch64-windows-gnu` | looked up at registration with `GetProcAddress` in the host executable, then `node.dll` / `libnode.dll` |
| `linux-x64-gnu`, `linux-arm64-gnu` | `*-linux-gnu.2.17` | undefined symbols in the shared object |
| `linux-x64-musl`, `linux-arm64-musl` | `*-linux-musl` (dynamic) | undefined symbols in the shared object |
| `darwin-x64`, `darwin-arm64` | `x86_64-macos.10.15`, `aarch64-macos.11.0` | flat (dynamic) lookup binds, `-undefined dynamic_lookup` |

Windows notes. The package name says `msvc` (the npm convention for "Windows"); the DLL is built with Zig's
`windows-gnu` target *without any C runtime*, so it imports `kernel32.dll` only and does not care which CRT
the host uses. There is no import of `node.exe` and no `.def` / import library: an import library pins the
host's file name, which breaks renamed executables and embedders (the reason node-gyp ships a delay-load
hook). Looking the functions up in the running process covers `node.exe` under any name, Electron and
runtimes that export Node-API from their own executable; a host that exports it from some other DLL is not
found, the addon then fails to register and `bm-engine` falls back to wasm. Zig's start code adds a few
harmless exports (`DllMainCRTStartup`, `_tls_*`) and an empty TLS directory; the addon uses no thread-local
storage.

CPU level. x86-64 artifacts need an x86-64-v2 CPU (SSE4.2 / SSSE3 / POPCNT: Intel since Nehalem 2008, AMD since
Bulldozer 2011). With the SSE2-only baseline the pixel and codec loops were slower than the wasm build, whose
SIMD V8 compiles with whatever the CPU has. The addon checks CPUID first thing when it registers; on an older
CPU registration fails and `bm-engine` runs the wasm build. arm64 artifacts use the architecture baseline.

Optimisation mode: ReleaseFast (see the numbers below). It has no bounds or overflow checks, like the
shipped wasm (ReleaseSmall): the protection against hostile input is the engine's limits plus the stack
handling above, exercised by the fuzzers below.

## Packaging

npm layout (napi-rs style; maintainer procedure: [docs/en/publishing.md](en/publishing.md)):

| package | contents | selection |
| --- | --- | --- |
| `bm-engine` | `js/`, the wasm files, typings; no `.node` | `optionalDependencies`: the 8 below, each at exactly the same version |
| `bm-engine-<name>` (8) | `bm-engine.<name>.node` (= `main`), README, licenses | `os` / `cpu` / `libc` (`["glibc"]` / `["musl"]` on Linux), so a package manager installs only the matching one |

* `npm run build:npm` (`scripts/npm-platform-packages.mjs`) writes `npm/<name>/`: `package.json` and `README.md`
  (committed, generated from the root `package.json`), the `.node` (checked against `native/dist/manifest.json`)
  and the license files (git-ignored). `--check` (part of `npm run verify`) fails when a platform
  `package.json` or an optional dependency is not at the root version; `npm run version:set -- x.y.z`
  updates the root, the optional dependencies, `package-lock.json` and the platform packages together.
* `engines.node` of the platform packages is the Node-API 6 range `>=10.20.0 <11 || >=12.17.0 <13 || >=14.0.0`:
  every function in the `Api` struct of `src/native/napi.zig` is Node-API 1 except `napi_set_instance_data`
  (Node-API 6), and registration is by the `napi_register_module_v1` symbol. The main package requires
  Node 18 (`engines`), which is the effective floor; only Node 26 was executed.
* Loading (`js/native.mjs`): `BM_ENGINE_NATIVE_PATH` and the checkout path are opened with `process.dlopen` (no
  module request for bundlers to see). The platform package is `require("bm-engine-<name>")` with one literal
  name per platform on `createRequire(import.meta.url)` in the same function, the form `@vercel/nft` traces
  (Next.js + webpack with `serverExternalPackages`: the package lands in standalone output), each marked
  `/* webpackIgnore: true */ /* turbopackIgnore: true */` so that bundlers leave it to run time (Turbopack
  otherwise fails the build on the 7 packages that are not installed). Turbopack's own tracing honours the
  comment as well, hence `outputFileTracingIncludes` in the Next.js guide. In a CommonJS bundle without
  `import.meta.url` the require is based on `__filename`, then on the working directory.
* WebAssembly on Node (`js/wasm-file.mjs`, used by every Node entry): the file next to the module (a literal
  `new URL("./bm_engine.wasm", import.meta.url)`, so bundlers that emit such assets keep working), then
  `createRequire(...).resolve("bm-engine/full.wasm")`, then `<cwd>/node_modules/bm-engine/js/`; the error when
  all fail names `serverExternalPackages` / `--external:bm-engine` / `BM_WASM`.
* `"./<x>.wasm?module"` exports: Turbopack (Next.js Edge) matches the `exports` key including the query.
* `npm run test:pack` generates and packs the platform packages and installs them with npm `overrides` (the
  registry stand-in): only the host's package is installed, native output = wasm output, wasm fallback for
  `--omit=optional` / a missing / corrupted / wrong-arch / other-OS binary / a force-installed foreign
  package, `BM_ENGINE_BACKEND`, `bm-engine/native`, worker threads, esbuild node bundles, no loader in browser
  bundles. `.github/workflows/release.yml` (never executed) runs the native tests on every platform before
  publishing.

## What is verified

The tools (results land in `bench/out/native-*.json` and `native/dist/manifest.json`):

| tool | what |
| --- | --- |
| `node scripts/build-native.mjs` | per artifact, without running it: container format and CPU; `napi_register_module_v1` exported; the undefined `napi_*` symbols (ELF, Mach-O) / lookup names (PE) are exactly the `Api` struct of `src/native/napi.zig`; Mach-O binds them by flat lookup and everything else to libSystem; only `libc.so.6` / `libpthread.so.0` / ... or musl's `libc.so` or `/usr/lib/libSystem.B.dylib` or `kernel32.dll` needed; highest required glibc symbol version <= 2.17; no math function imported; no thread-local storage segment; no executable stack; arm64 Mach-O ad-hoc signed; arm64 fused multiply-add count |
| `node bench/native-identity.mjs` | every fixture of the benchmark suite through both backends: raw RGBA, PNG, JPEG, WebP, measure JSON, SVG, plus animations (WebP / APNG / GIF), ICO, HTML, image attachments, WOFF2, error messages; native async against native sync |
| `node bench/native-tests.mjs` (`npm run test:native`) | each case in a child process: `concurrency`, `eventloop`, `free`, `gc`, `errors`, `fallback`, `workers`, `libm`, `stack`, `fuzz-tree` / `fuzz-inline` / `fuzz-table` (the existing probes, run against the addon through `bench/lib/native-hooks.mjs`), `fuzz-diff` (mutated HTML / JSON / CSS / SVG / images / fonts through both backends, outcomes compared), `perf`, `cold` |

Only the artifact of the host platform can be executed by these tools. The others are compiled and
structurally verified; they still need one run of `native-identity.mjs` and `native-tests.mjs` on their
platform (CI) before they are trusted.

Results when this was written (Windows 11 x64, Node 26, Intel i3-10100, 4 cores / 8 threads, other work
running on the machine; `win32-x64-msvc` is the only artifact that was executed):

| | |
| --- | --- |
| artifacts | 8 / 8 compile and pass the structural checks; 1.6 MB (arm64) to 2.1 MB (x64), 0.95 to 1.1 MB gzip |
| identity | 250 fixtures, 1810 comparisons (637 MB of output), 0 mismatches |
| differential fuzz | 17 800 mutated inputs (HTML, JSON trees, CSS, SVG, images, fonts): same bytes or same error on both backends, 0 crashes; plus the three existing fuzz probes (16 900 inputs) without a crash |
| libm | 5 functions x f32 / f64 x 2^20 values, bit-exact |
| stack | 61 deepest-allowed / hostile inputs: the smallest stack on which all behave is 768 KiB (512-level trees, PNG path); guaranteed: 3072 KiB |
| concurrency | 200 concurrent `render()` on one renderer and across 8 renderers: all correct; 8 renderers on the default pool of 4 are 2.8x faster than the same work synchronously |
| event loop | a 6 s animation render: longest delay of a 1 ms timer 30 ms natively (415 ticks) against 11.5 s on wasm (0 ticks, the whole render) |
| memory | 4000 renderers with 1 MB of fonts each created and dropped without `free()`: RSS flat at 68 to 69 MB, 9.6 MB live in the addon; with `free()` 0 live; 0 after the final GC |
| workers | 8 workers loading at once render the main thread's bytes; 100 workers terminated mid-render, no crash |
| speed (sync; geometric mean over the 250 fixtures of each fixture's median time) | raw RGBA 0.51 ms against 0.85 ms for the wasm build (1.67x), PNG 1.05 ms against 1.56 ms (1.47x); per fixture 1.25x to 2.78x for raw and 1.20x to 2.22x for PNG (native is faster on 250/250); absolute times moved by up to about 15 % between passes, the ratios by about 1 % |
| optimisation modes | ReleaseFast 1.26x, ReleaseSafe 1.00x, ReleaseSmall 0.60x the wasm build (raw, measured before the move to x86-64-v2); ReleaseFast is what ships |
| cold start | process start to first 1200x630 PNG to exit (median of 30): 99.9 ms native, 168.4 ms wasm, 68.6 ms for an empty Node process (31.3 ms and 99.9 ms above it) |

## Limits and known gaps

* One renderer does not render two things at once (see threading); use several renderers.
* An async call copies its attachments (image bytes) when it is made; many queued calls with large images
  hold that many copies until they run.
* A render cannot be cancelled once it is executing (`signal` is checked before the call, as in wasm).
* arm64 and the non-Windows targets have not been executed by the author of this change: their
  correctness rests on shared source, the structural checks, and the load-time floating-point guard.
* Hosts that export Node-API neither from the executable nor from `node.dll` / `libnode.dll` (Windows) do not
  get the addon (wasm fallback).
