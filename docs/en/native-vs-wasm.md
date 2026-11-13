# Native addon vs WebAssembly

[English](native-vs-wasm.md) · [Tiếng Việt](../vi/native-vs-wasm.md)

On Node.js, bm-engine runs either as a native Node-API addon or as WebAssembly. Both are compiled from the
same Zig source, expose the same API and produce the same bytes. This page explains which one you get, when
to choose the other, how the native backend uses threads, and how both compare with takumi's native and wasm
builds on the 250-fixture benchmark suite. Installation: [Getting started](./getting-started.md).
How the platform packages are built and published: [Publishing](./publishing.md).

## Which backend to use

| Where your code runs | Backend | How |
|:--|:--|:--|
| Node.js, Bun, Deno (servers, CLIs, build scripts) | **native**, with an automatic fallback to wasm | `import { Renderer, backend } from "bm-engine"`; `backend` is `"native"` or `"wasm"` |
| Browsers, Web Workers | wasm (the only option) | `bm-engine` resolves to the wasm build there |
| Cloudflare Workers, Vercel / Netlify Edge, Deno Deploy and other edge runtimes | wasm (the only option) | same import |
| Node.js, but you want wasm anyway (for example to reproduce a browser render bit for bit, or on a host whose addon has not been tested yet) | wasm | `import ... from "bm-engine/full"` or `BM_ENGINE_BACKEND=wasm` |
| Node.js, Bun, Deno, and you want PDF output | **native**, with an automatic fallback to the wasm `pdf` profile | `import { PdfRenderer, backend } from "bm-engine/pdf"`; see [PDF output](./pdf/native-and-wasm.md#native-backend-on-nodejs) |
| Node.js, and you want an error rather than a silent fallback | native | `import ... from "bm-engine/native"` or `BM_ENGINE_BACKEND=native` |

The fallback is silent: if no addon is installed for the platform, if the CPU is older than x86-64-v2
(SSE4.2), or if the addon fails its load-time floating-point check, `bm-engine` loads the wasm build and
everything keeps working, only slower and with async calls on the main thread. Log `backend` once at startup
if you need to know.

`bm-engine/pdf` follows the same rules: on Node.js it uses the addon when it is installed and otherwise the wasm
`pdf` profile, produces identical PDF bytes on both, and runs its async methods on the libuv thread pool when native.
`bm-engine` itself exposes no PDF on either backend, although the addon binary contains the PDF writer.

## Results at a glance

<!-- native-bench:highlights -->
- **bm-native vs bm-wasm (sync):** raw 0.61× the wasm time [0.62× / 0.61× / 0.61×] (faster on 250/250 fixtures), PNG 0.67× [0.68× / 0.68× / 0.67×] (faster on 250/250).
- **bm-native vs takumi-native, both async:** raw 0.55× [0.55× / 0.55× / 0.55×] (bm faster on 244/250, per fixture 0.12×–1.20×), PNG 0.54× [0.55× / 0.55× / 0.54×] (bm faster on 227/250, per fixture 0.23×–2.54×). With bm's sync API: raw 0.53×, PNG 0.57×. Below 1× = bm-native takes less time; in brackets the same ratio in each pass.
- **CPU time per image (both async):** PNG 1.98 ms bm-native vs 3.20 ms takumi-native (1.73 vs 1.98 cores busy during a render); raw 1.30 vs 1.41 ms. takumi-native runs parts of one render (PNG deflate segments, blur, WebP, animation frames) on its own rayon thread pool; bm renders one image on one thread (bm-native sync: 0.87 cores for PNG).
- **takumi's own two builds:** takumi-native takes 0.72× the time of takumi-wasm for raw and 0.55× for PNG.
- **Identity:** bm-native and bm-wasm produced the same bytes in 2626/2626 comparisons over 250 fixtures (802 MB; 0 mismatches).
- **Noise:** the absolute raw / PNG geomeans moved by up to 4.70 % between passes (the load from other processes changed during the run), while the engine-to-engine ratios, measured interleaved inside each pass, moved by at most 1.50 %. Read the ratios; treat absolute milliseconds as ±2.35 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Metric | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — sync API | 0.45 ±2.15 % | 0.74 ±2.15 % | no sync API | — |
| raw RGBA, geomean ms — async API | 0.47 ±2.25 % | — | 0.86 ±2.10 % | 1.19 ±2.35 % |
| PNG, geomean ms — sync API | 0.95 ±1.95 % | 1.41 ±1.55 % | no sync API | — |
| PNG, geomean ms — async API | 0.90 ±2.30 % | — | 1.66 ±1.55 % | 3.03 ±1.65 % |
| CPU time per PNG render, mean ms (cores used) | 1.00 (0.87 cores) | 1.30 (0.76 cores) | 3.20 (1.98 cores) | 2.84 (0.81 cores) |
| PNG file size, geomean vs takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start over empty Node, median / p95 ms | 21.8 / 45.5 | 75.5 / 93.0 | 46.2 / 69.2 | 185 / 249 |
| RSS after 1 → 10 suite passes, MiB | 90.7 → 91.4 | 127 → 150 | 118 → 124 | 138 → 172 |
| Peak RSS, one 4000×4000 PNG, MiB | 140 | 146 | 133 | 148 |
| Event loop: max 1 ms-timer delay, heavy 2400×2400 render, ms | 211 (sync) · 1.20 (async) | 401 (sync) · 392 (async) | 13.4 (async) | 746 (async) |
| Event loop: same, 60-frame animation, ms | 438 (sync) · 1.10 (async) | 848 (sync) · 873 (async) | 11.5 (async) | 1 848 (async) |
| Throughput, og card PNG, 4 concurrent, images/s (best config) | 372 (many K=8, UV 4) | 263 (pool K=4) | 298 (many K=2, UV 8) | 173 (pool K=8) |
| Throughput, 8 concurrent, images/s (best config) | 408 (many K=8, UV 8) | 291 (pool K=8) | 336 (one, UV 8) | 202 (pool K=8) |

Geomeans over the 250 fixtures every engine rendered; ± = half the range of the 3 passes' geomeans relative to their median; ⚠ = more than 10 % range. Cold start: median / p95 of 30 fresh processes minus the empty-Node median. Event-loop, memory and throughput are single runs; on the throughput rows ⚠ = other processes used more than one core on average during that stage.
<!-- /native-bench:summary -->

How to read it:

- **sync / async.** bm-engine has both `renderSync` (on the calling thread) and `render` (natively: on the libuv
  thread pool). takumi-native only has an async `render`, so the fair comparison with it is the *async* row;
  the sync row shows what bm-native costs without the thread hop. On wasm, `render` is the same work as
  `renderSync` on the main thread, so bm-wasm is timed through `renderSync` and takumi-wasm through its
  public `render`.
- **Wall time vs CPU time.** takumi-native runs parts of a single render (PNG deflate segments, blur, WebP,
  animation frames) on its own rayon thread pool, so one of its renders can keep several cores busy. bm-native
  renders one image on one thread. The CPU row shows the difference: when the machine is busy serving many
  requests, CPU per image matters more than the latency of a single render.
- **PNG** times depend on the encoder's effort, which neither engine lets you set; compare them together with
  the file sizes ([format table](#formats-and-encoders)).

## Threading model

What runs where with the native backend:

- `renderSync`, `measureSync`, `renderSvgSync`, `renderAnimationSync`, `registerFont`: on the calling thread.
  They block the event loop for the duration of the call, exactly like the wasm build.
- `render`, `renderAsDataUrl`, `renderSvg`, `measure`, `renderAnimation`: the inputs are copied, then the
  engine runs on a **libuv thread-pool thread** and the promise settles on the JavaScript thread. The event
  loop keeps serving requests while a render is in progress ([event-loop table](#event-loop)).
- **One renderer handles one call at a time.** Calls on the same `Renderer` are queued in order
  (first in, first out). To render in parallel, create several renderers (each with its fonts registered) and
  spread the work over them:

```js
import { Renderer } from "bm-engine";

const fonts = [/* { name, data, weight, style } ... */];
const renderers = Array.from({ length: 4 }, () => {
  const r = new Renderer();
  for (const f of fonts) r.registerFont(f);
  return r;
});
let next = 0;
export function renderPng(node, options) {
  const r = renderers[next++ % renderers.length]; // round robin
  return r.render(node, options); // runs on the libuv pool, does not block the event loop
}
```

- **Parallelism is capped by the libuv pool**, `UV_THREADPOOL_SIZE`, **4 by default**. The same pool also
  serves `fs`, `dns.lookup`, `crypto` and `zlib`. To render on more threads, set it in the environment before
  Node starts, e.g. `UV_THREADPOOL_SIZE=8 node server.js` (setting `process.env.UV_THREADPOOL_SIZE` inside the
  program only works if nothing has used the pool yet). More renderers than pool threads do not help.
- Different renderers share no state (each owns its fonts, caches and memory), so they never wait for each
  other. The addon can be loaded in
  `worker_threads` too, but on the native backend a pool of renderers in one thread does the same job without
  workers.
- With the **wasm** backend, async methods run on the main thread; parallelism needs a `worker_threads`
  pool with one engine instance per worker ([recipe](./image/recipes.md#worker-threads-pool)). This is also what
  the benchmark measures for bm-wasm and takumi-wasm.

### Throughput under concurrency

<!-- native-bench:throughput -->
| Engine | Setup | UV_THREADPOOL_SIZE | N=1 | N=2 | N=4 | N=8 | N=16 |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 1 client, sequential | 4 | 109 |  |  |  |  |
| bm-wasm | 1 client, sequential | — | 72.3 |  |  |  |  |
| takumi-native | 1 client, sequential | 4 | 123 |  |  |  |  |
| takumi-wasm | 1 client, sequential | — | 45.6 |  |  |  |  |
| bm-native | 1 renderer, async | 4 | 104 (0.96×, 96 %) | 106 (0.98×, 98 %) | 104 (0.96×, 96 %) | 105 (0.96×, 96 %) | 105 (0.97×, 97 %) |
| bm-native | 2 renderers, async | 4 | 104 (0.95×, 95 %) | 194 (1.79×, 89 %) | 197 (1.82×, 91 %) | 205 (1.89×, 94 %) | 200 (1.84×, 92 %) |
| bm-native | 4 renderers, async | 4 | 101 (0.93×, 93 %) | 197 (1.81×, 91 %) | 371 (3.42×, 85 %) | 367 (3.39×, 85 %) | 359 (3.31×, 83 %) |
| bm-native | 8 renderers, async | 4 | 99.6 (0.92×, 92 %) | 198 (1.82×, 91 %) | 372 (3.43×, 86 %) | 369 (3.40×, 85 %) | 366 (3.38×, 84 %) |
| bm-native | 1 renderer, async | 8 | 103 (0.95×, 95 %) | 106 (0.97×, 97 %) | 105 (0.96×, 96 %) | 104 (0.95×, 95 %) | 106 (0.97×, 97 %) |
| bm-native | 2 renderers, async | 8 | 104 (0.95×, 95 %) | 195 (1.79×, 90 %) | 197 (1.82×, 91 %) | 199 (1.84×, 92 %) | 202 (1.86×, 93 %) |
| bm-native | 4 renderers, async | 8 | 103 (0.95×, 95 %) | 197 (1.81×, 91 %) | 360 (3.32×, 83 %) | 371 (3.42×, 85 %) | 356 (3.28×, 82 %) |
| bm-native | 8 renderers, async | 8 | 104 (0.96×, 96 %) | 198 (1.82×, 91 %) | 365 (3.36×, 84 %) | 408 (3.76×, 47 %) | 406 (3.74×, 47 %) |
| takumi-native | 1 renderer, async | 4 | 130 (1.06×, 106 %) | 210 (1.71×, 85 %) | 296 (2.40×, 60 %) | 296 (2.40×, 60 %) | 298 (2.42×, 60 %) |
| takumi-native | 1 renderer, async | 8 | 129 (1.04×, 104 %) | 209 (1.69×, 85 %) | 273 (2.21×, 55 %) | 336 (2.72×, 34 %) | 338 (2.74×, 34 %) |
| takumi-native | 2 renderers, async | 4 | 132 (1.07×, 107 %) | 212 (1.72×, 86 %) | 298 (2.41×, 121 %) | 293 (2.38×, 119 %) | 300 (2.43×, 122 %) |
| takumi-native | 4 renderers, async | 4 | 132 (1.07×, 107 %) | 212 (1.72×, 86 %) | 295 (2.39×, 60 %) | 298 (2.42×, 60 %) | 264 (2.14×, 54 %) |
| takumi-native | 2 renderers, async | 8 | 131 (1.06×, 106 %) | 211 (1.71×, 85 %) | 298 (2.42×, 121 %) | 327 (2.65×, 133 %) | 305 (2.47×, 124 %) |
| takumi-native | 4 renderers, async | 8 | 130 (1.06×, 106 %) | 210 (1.70×, 85 %) | 294 (2.38×, 60 %) | 333 (2.70×, 68 %) | 324 (2.63×, 66 %) |
| bm-wasm | worker pool, 1 worker | — | 70.5 (0.98×, 98 %) | 67.8 (0.94×, 94 %) | 69.9 (0.97×, 97 %) | 71.1 (0.98×, 98 %) | 71.0 (0.98×, 98 %) |
| bm-wasm | worker pool, 2 workers | — | 69.0 (0.95×, 95 %) | 137 (1.89×, 95 %) | 137 (1.90×, 95 %) | 139 (1.92×, 96 %) | 137 (1.89×, 95 %) |
| bm-wasm | worker pool, 4 workers | — | 70.7 (0.98×, 98 %) | 138 (1.91×, 95 %) | 263 (3.64×, 91 %) | 249 (3.45×, 86 %) | 263 (3.63×, 91 %) |
| bm-wasm | worker pool, 8 workers | — | 70.7 (0.98×, 98 %) | 138 (1.91×, 95 %) | 236 (3.27×, 82 %) | 291 (4.03×, 50 %) | 309 (4.27×, 53 %) |
| takumi-wasm | worker pool, 1 worker | — | 46.0 (1.01×, 101 %) | 46.4 (1.02×, 102 %) | 47.0 (1.03×, 103 %) | 47.4 (1.04×, 104 %) | 47.1 (1.03×, 103 %) |
| takumi-wasm | worker pool, 2 workers | — | 44.5 (0.98×, 98 %) | 90.3 (1.98×, 99 %) | 88.9 (1.95×, 97 %) | 92.4 (2.03×, 101 %) | 91.8 (2.01×, 101 %) |
| takumi-wasm | worker pool, 4 workers | — | 46.1 (1.01×, 101 %) | 91.3 (2.00×, 100 %) | 170 (3.72×, 93 %) | 174 (3.82×, 96 %) | 179 (3.92×, 98 %) |
| takumi-wasm | worker pool, 8 workers | — | 46.4 (1.02×, 102 %) | 90.1 (1.98×, 99 %) | 173 (3.80×, 95 %) | 202 (4.43×, 55 %) | 213 (4.67×, 58 %) |

Images per second; in brackets the speed-up over the same engine's sequential single-client rate (first rows) and the scaling efficiency = speed-up / min(N, threads that can render different images at once, 8 logical CPUs); a bm renderer counts as 1, K renderers as min(K, UV_THREADPOOL_SIZE), takumi-native's renderer as UV_THREADPOOL_SIZE, a worker pool as K. card-og 1200x630 PNG, closed loop: N clients each with one request in flight; 2000 ms per point after a warm-up. CPU busy during the stage: 42.8 % mean (other processes ≈ 0.90 cores).
<!-- /native-bench:throughput -->

## Output identity

The two backends produce the **same bytes**: on every fixture of the benchmark suite, raw RGBA, PNG, JPEG,
WebP, SVG and `measure` output, animations (WebP / APNG / GIF), ICO, HTML sources, image attachments, WOFF2
fonts and error messages are compared byte for byte (`node bench/native-identity.mjs`), and native async
results are compared with native sync results. A server can switch backends (or fall back) without any
visible change in its images or caches. The guarantee is tested on Windows x64 only so far; see the platform
table.

<!-- native-bench:equiv -->
| Engine vs takumi-wasm (250 fixtures, raw RGBA) | identical | equivalent | close | different | error/unsupported |
|:--|--:|--:|--:|--:|--:|
| bm-native | 81 | 169 | 0 | 0 | 0 |
| bm-wasm | 81 | 169 | 0 | 0 | 0 |
| takumi-native | 250 | 0 | 0 | 0 | 0 |

| Same engine, two builds | raw RGBA byte-identical | PNG file byte-identical |
|:--|--:|--:|
| bm-native = bm-wasm | 250/250 | 250/250 |
| takumi-native = takumi-wasm | 250/250 | 250/250 |

`bench/native-identity.mjs`: 250 fixtures, 2626 comparisons (raw, PNG, JPEG, WebP, measure, SVG, animations, ICO, HTML, images, WOFF2, error messages, native async vs sync), 2626 identical (121 of them the same error message on both), 0 mismatches, 802 MB compared.
<!-- /native-bench:equiv -->

Against takumi the comparison is the one used since phase 1 (takumi-wasm is the reference; "identical" = every
byte equal, "equivalent" = SSIM ≥ 0.99 and at most 0.5 % of pixels differ). The native build changes nothing
there: both bm backends get the same verdicts.

## Platform support

| Platform package | Target | Status |
|:--|:--|:--|
| `bm-engine-win32-x64-msvc` | Windows x64 | **Executed**: identity suite, native test suite and this benchmark ran on it |
| `bm-engine-win32-arm64-msvc` | Windows on Arm | cross-compiled and structurally verified; **never run** |
| `bm-engine-linux-x64-gnu` | Linux x64, glibc ≥ 2.17 | cross-compiled and structurally verified; **never run** |
| `bm-engine-linux-x64-musl` | Linux x64, musl (Alpine) | cross-compiled and structurally verified; **never run** |
| `bm-engine-linux-arm64-gnu` | Linux arm64, glibc ≥ 2.17 | cross-compiled and structurally verified; **never run** |
| `bm-engine-linux-arm64-musl` | Linux arm64, musl | cross-compiled and structurally verified; **never run** |
| `bm-engine-darwin-x64` | macOS Intel, 10.15+ | cross-compiled and structurally verified; **never run** |
| `bm-engine-darwin-arm64` | macOS Apple silicon, 11+ | cross-compiled and structurally verified; **never run** |

"Structurally verified" means the build script checked each file without running it: file format and CPU,
the exported registration function, exactly the expected Node-API imports, no other library dependencies than
the C library (or `kernel32.dll`), no imported math functions, and (arm64) the count of fused multiply-add
instructions. Until the identity and test suites have run on a platform, treat its addon as untested; on any
platform the wasm build remains available (`bm-engine/full`) and is what `bm-engine` falls back to.

### Sizes

<!-- native-bench:sizes -->
| File | Target | KiB | gzip -9 KiB | brotli KiB | Status |
|:--|--:|--:|--:|--:|--:|
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 3 327 | 1 765 | 1 389 | executed (this benchmark) |
| `bm-engine.win32-arm64-msvc.node` | `aarch64-windows-gnu` | 2 627 | 1 577 | 1 179 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-x64-gnu.node` | `x86_64-linux-gnu.2.17` | 3 185 | 1 720 | 1 361 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-x64-musl.node` | `x86_64-linux-musl` | 3 185 | 1 720 | 1 362 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-arm64-gnu.node` | `aarch64-linux-gnu.2.17` | 2 634 | 1 579 | 1 180 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-arm64-musl.node` | `aarch64-linux-musl` | 2 633 | 1 579 | 1 180 | cross-compiled, structurally verified, never executed |
| `bm-engine.darwin-x64.node` | `x86_64-macos.10.15` | 3 175 | 1 719 | 1 360 | cross-compiled, structurally verified, never executed |
| `bm-engine.darwin-arm64.node` | `aarch64-macos.11.0` | 2 652 | 1 536 | 1 128 | cross-compiled, structurally verified, never executed |
| bm wasm `core` | wasm32 | 490 | 229 | 195 |  |
| bm wasm `standard` | wasm32 | 937 | 465 | 399 |  |
| bm wasm `full` | wasm32 | 1 144 | 560 | 471 |  |
| bm wasm `WOFF add-on` | wasm32 | 84.4 | 67.8 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Native addons from `native/dist/manifest.json` (built 2026-11-13 with Zig 0.17.1, ReleaseFast). Each user downloads one addon (the optional package for their platform) plus the wasm fallback that ships in the main package.
<!-- /native-bench:sizes -->

## Event loop

<!-- native-bench:eventloop -->
| Job | Engine | API | job ms | CPU ms | max timer delay ms | p99 delay ms | timer ticks |
|:--|--:|--:|--:|--:|--:|--:|--:|
| heavy | bm-native | sync | 211 | 219 | 211 | 211 | 1 |
| heavy | bm-native | async | 247 | 500 | 1.20 | 1.10 | 248 |
| heavy | bm-wasm | sync | 401 | 579 | 401 | 401 | 1 |
| heavy | bm-wasm | async (runs on the main thread) | 391 | 563 | 392 | 392 | 1 |
| heavy | takumi-native | async | 242 | 671 | 13.4 | 2.00 | 231 |
| heavy | takumi-wasm | async (runs on the main thread) | 745 | 814 | 746 | 746 | 1 |
| anim | bm-native | sync | 437 | 437 | 438 | 438 | 1 |
| anim | bm-native | async | 448 | 875 | 1.10 | 1.00 | 450 |
| anim | bm-wasm | sync | 848 | 1 015 | 848 | 848 | 1 |
| anim | bm-wasm | async (runs on the main thread) | 872 | 1 031 | 873 | 873 | 1 |
| anim | takumi-native | async | 367 | 2 141 | 11.5 | 8.90 | 312 |
| anim | takumi-wasm | async (runs on the main thread) | 1 848 | 2 218 | 1 848 | 1 848 | 1 |

heavy = one 2400x2400 PNG: gradient, 24 cards with large blurred box-shadows, every third with filter: blur(6px), text; anim = renderAnimation: 60 frames (2 s at 30 fps) of 800x420 lossless WebP, 12 shadowed, blurred, rotated discs (a static scene). A 1 ms `setInterval` records the gap between its ticks while the call runs. A setImmediate chain keeps the loop from sleeping, because an idle Node loop on Windows wakes on the 15.6 ms system clock and the timer would otherwise never show less than ~16 ms. A call that blocks the loop shows one tick whose delay is the whole call. CPU ms is the whole process during the call, including the setImmediate chain on the main thread (about one core whenever the loop is free).
<!-- /native-bench:eventloop -->

## Cold start

<!-- native-bench:cold -->
| Engine | wall median | wall p95 | over Node, median | over Node, p95 | import | registerFont | first PNG |
|:--|--:|--:|--:|--:|--:|--:|--:|
| empty Node (baseline) | 49.1 | 68.5 | 0 | 0 | — | — | — |
| bm-native | 71.0 | 94.7 | 21.8 | 45.5 | 4.70 | 0.34 | 17.9 |
| bm-wasm | 125 | 142 | 75.5 | 93.0 | 7.10 | 2.43 | 65.4 |
| takumi-native | 95.4 | 118 | 46.2 | 69.2 | 23.1 | 0.92 | 20.2 |
| takumi-wasm | 234 | 298 | 185 | 249 | 33.7 | 3.29 | 146 |

ms. 30 runs per engine, engines interleaved; spawn node -> import the engine as a user does -> registerFont(Inter Regular) -> 1200x630 og card PNG -> exit; wall = parent clock spawn to exit. The import / registerFont / first-PNG columns are medians measured inside the child. CPU busy during the stage: 33.3 % mean (other processes ≈ 1.20 cores). ⚠ Other processes used about 1.20 of the machine's cores on average during this stage, so these figures (scaling above all) understate what an idle machine gives; re-run on a quiet machine before quoting them.
<!-- /native-bench:cold -->

## Memory

<!-- native-bench:memory -->
| Engine | RSS after setup | RSS after pass 1 → 10 | engine memory 1 → N | JS heap 1 → N | peak RSS, suite | peak RSS 4000×4000 PNG (growth) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 63.2 | 90.7 → 91.4 | 31.6 → 31.6 | 6.40 → 6.50 | 183 | 140 (85.6) |
| bm-wasm | 75.4 | 127 → 150 | 63.8 → 86.8 | 6.60 → 6.70 | 247 | 146 (88.9) |
| takumi-native | 67.0 | 118 → 124 | — → — | 6.60 → 6.70 | 199 | 133 (74.5) |
| takumi-wasm | 83.5 | 138 → 172 | 71.5 → 71.5 | 7.40 → 7.50 | 237 | 148 (83.3) |

MiB, after a forced GC. One process per engine; every fixture rendered to raw and PNG (async API) per pass, one renderer per font set. Engine memory: bm-native = bytes allocated by the addon (`memoryBytes()`), bm-wasm / takumi-wasm = the wasm linear memory, takumi-native = not exposed. Empty Node: 41.5 MiB RSS. "Growth" = peak RSS minus the RSS just before the 4000×4000 render.
<!-- /native-bench:memory -->

## Render time

<!-- native-bench:speed -->
| Format (fixtures) | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| raw (250) | 0.45 ±2.15 % | 0.47 ±2.25 % | 0.74 ±2.15 % | 0.86 ±2.10 % | 1.19 ±2.35 % |
| png (250) | 0.95 ±1.95 % | 0.90 ±2.30 % | 1.41 ±1.55 % | 1.66 ±1.55 % | 3.03 ±1.65 % |
| jpeg (3) | 11.1 ±2.90 % | 11.3 ±2.40 % | 18.3 ±1.95 % | 17.5 ±2.45 % | 24.2 ±2.50 % |
| webp (3) | 8.71 ±3.15 % | 8.87 ±2.65 % | 12.4 ±2.55 % | 66.6 ±2.20 % | 15.8 ±2.35 % |
| raw, without known-gaps | 0.47 | 0.48 | 0.76 | 0.87 | 1.21 |
| png, without known-gaps | 0.97 | 0.92 | 1.44 | 1.69 | 3.07 |
| raw, per pass | 0.46 / 0.47 / 0.45 | 0.47 / 0.48 / 0.46 | 0.74 / 0.76 / 0.73 | 0.86 / 0.89 / 0.85 | 1.19 / 1.23 / 1.17 |
| png, per pass | 0.96 / 0.98 / 0.94 | 0.91 / 0.94 / 0.90 | 1.42 / 1.45 / 1.41 | 1.67 / 1.70 / 1.65 | 3.04 / 3.11 / 3.01 |

Geometric mean of the per-fixture median render time, ms. jpeg (quality 85) and webp (lossless; takumi-wasm uses a different WebP encoder from takumi-native, see the format table) are timed on three fixtures only.
<!-- /native-bench:speed -->

<!-- native-bench:cpu -->
| Variant | raw: wall / CPU ms / cores | PNG: wall / CPU ms / cores |
|:--|--:|--:|
| bm-native sync | 0.41 / 0.38 / 0.91 | 1.16 / 1.00 / 0.87 |
| bm-native async | 0.46 / 1.30 / 2.81 | 1.15 / 1.98 / 1.73 |
| bm-wasm sync | 0.66 / 0.51 / 0.77 | 1.71 / 1.30 / 0.76 |
| takumi-native async | 0.78 / 1.41 / 1.80 | 1.61 / 3.20 / 1.98 |
| takumi-wasm | 1.06 / 0.78 / 0.73 | 3.50 / 2.84 / 0.81 |

Mean over every timed render of the suite (not a geomean): wall time per render, process CPU time (all threads) spent during it, and their ratio. A ratio above 1 means one render kept more than one core busy.
<!-- /native-bench:cpu -->

Where bm-native is furthest ahead of and behind takumi-native (both async):

<!-- native-bench:best-worst -->
**raw — bm-native's 10 best**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-jpeg-fit` | 1.37 | 1.45 | 11.9 | 1.30 | 0.12× |
| `pfx-bg-blend` | 0.69 | 0.71 | 3.70 | 0.92 | 0.19× |
| `pfx-bg-clip-text` | 0.42 | 0.41 | 1.81 | 1.07 | 0.23× |
| `gap-background-clip-text` | 0.27 | 0.30 | 1.30 | 1.28 | 0.23× |
| `fix-text-emoji-spacing` | 0.13 | 0.14 | 0.52 | 1.72 | 0.26× |
| `fix-text-emoji-wrap` | 0.12 | 0.13 | 0.48 | 1.66 | 0.26× |
| `fix-text-emoji-zwj` | 0.13 | 0.13 | 0.48 | 2.46 | 0.27× |
| `fix-text-emoji-flags-skin` | 0.12 | 0.12 | 0.41 | 2.05 | 0.29× |
| `fix-text-emoji-keycap-vs` | 0.12 | 0.12 | 0.39 | 2.31 | 0.31× |
| `radial-shapes` | 1.97 | 1.99 | 6.30 | 1.26 | 0.32× |

**raw — bm-native's 10 worst**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `fix-text-paint-order` | 0.77 | 0.80 | 0.67 | 2.24 | 1.20× |
| `abs-zorder` | 1.38 | 1.42 | 1.20 | 1.76 | 1.19× |
| `pfx-text-stroke` | 0.83 | 0.83 | 0.75 | 1.31 | 1.12× |
| `pfx-svg-background` | 0.66 | 0.65 | 0.61 | 2.75 | 1.08× |
| `radius-uniform-percorner` | 1.07 | 1.10 | 1.07 | 1.46 | 1.03× |
| `radius-pill-circle` | 1.09 | 1.07 | 1.06 | 3.75 | 1.01× |
| `flex-wrap-gap` | 1.34 | 1.37 | 1.42 | 1.78 | 0.97× |
| `flex-row-column` | 1.09 | 1.07 | 1.12 | 1.55 | 0.96× |
| `tw-structural` | 0.64 | 0.66 | 0.69 | 2.94 | 0.95× |
| `radius-elliptical` | 1.07 | 1.10 | 1.15 | 1.60 | 0.95× |

**png — bm-native's 10 best**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `colors-solid-bg` | 0.20 | 0.19 | 0.82 | 1.30 | 0.23× |
| `gap-oklch-color` | 0.18 | 0.17 | 0.72 | 0.83 | 0.24× |
| `anim-kf-option-t500` | 0.19 | 0.17 | 0.64 | 1.12 | 0.27× |
| `pfx-visibility` | 0.26 | 0.23 | 0.84 | 0.72 | 0.28× |
| `anim-alternate-t100` | 0.18 | 0.17 | 0.59 | 1.23 | 0.29× |
| `anim-opacity-t900` | 0.17 | 0.16 | 0.55 | 1.31 | 0.29× |
| `anim-opacity-t500` | 0.17 | 0.16 | 0.55 | 1.76 | 0.29× |
| `anim-alternate-t1100` | 0.18 | 0.17 | 0.58 | 1.53 | 0.29× |
| `anim-opacity-t250` | 0.17 | 0.16 | 0.54 | 1.79 | 0.30× |
| `anim-alternate-t700` | 0.17 | 0.17 | 0.56 | 1.91 | 0.30× |

**png — bm-native's 10 worst**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-photo-bg` | 28.5 | 28.7 | 11.3 | 4.33 | 2.54× |
| `card-blog` | 18.9 | 19.1 | 11.8 | 2.51 | 1.62× |
| `radial-spotlight-small` | 4.14 | 4.14 | 2.62 | 2.80 | 1.58× |
| `img-radius-clip` | 14.6 | 14.7 | 9.53 | 2.69 | 1.54× |
| `stress-3000x2000-card` | 52.6 | 53.6 | 39.6 | 2.88 | 1.35× |
| `fx-text-shadow` | 2.67 | 2.67 | 2.03 | 3.35 | 1.32× |
| `img-intrinsic-size` | 1.76 | 1.83 | 1.40 | 2.38 | 1.31× |
| `img-png-fit` | 11.2 | 11.3 | 8.65 | 1.75 | 1.31× |
| `card-og` | 9.61 | 9.70 | 7.50 | 2.49 | 1.29× |
| `pfx-mix-blend` | 2.70 | 2.72 | 2.15 | 4.14 | 1.27× |
<!-- /native-bench:best-worst -->

### Where bm-native loses, and why

What the measurements show (the diagnostic table below is part of every run; anything not backed by it is marked
as a hypothesis):

- **`filter: blur()` is much slower in bm-engine, on both backends.** In the animation scene, removing the
  blur filter brings bm's frame time below takumi's, and the blur alone accounts for almost all of bm's time;
  takumi's blur is cheap. That one effect is why the 60-frame animation in the event-loop table takes far longer
  in bm (takumi-native additionally renders frames in parallel). *Hypothesis, not profiled:* bm's filter pass
  works on a much larger area than the blurred element. This is an engine issue, not a native-vs-wasm one.
- **Large raw frames with little content.** The worst raw fixtures against takumi-native are 1200×630 frames
  with simple boxes. An empty frame shows the same gap: bm's fixed per-pixel cost of producing raw output
  (clear, alpha conversion, copy out) is higher than takumi-native's, and with bm's **async** API it grows
  further with the frame size, while PNG output (small result) shows no async penalty. *Hypothesis:* the async
  path copies or freshly allocates the multi-megabyte result once more. Either way it only matters for `raw`.
- **PNG of large, photo-like images.** takumi-native deflates a PNG in several segments on several cores (the
  "takumi cores" column of the worst-PNG table is well above 1 for most of those fixtures); bm encodes on one thread.
  bm still uses less CPU per PNG overall (CPU row of the summary), and its files are smaller on average.
- **WebP** is the other way round: takumi-native's lossless WebP (libwebp, per takumi's source) is several times
  slower than bm's, with smaller files on flat images and larger ones on photos (format table).

<!-- native-bench:diagnose -->
| Empty white frame | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| 300×200 raw | 0.10 | 0.11 | 0.18 | 0.22 | 0.29 |
| 300×200 png | 0.15 | 0.12 | 0.18 | 0.45 | 0.53 |
| 1200×630 raw | 0.70 | 0.70 | 0.97 | 0.78 | 1.09 |
| 1200×630 png | 1.11 | 0.69 | 1.24 | 2.94 | 4.88 |
| 2400×1260 raw | 2.50 | 2.66 | 4.50 | 2.77 | 4.91 |
| 2400×1260 png | 4.60 | 4.32 | 5.78 | 10.3 | 19.3 |

| Animation scene, one 800×420 raw frame | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| shadow + blur (as animated) | 6.85 | 6.87 | 12.9 | 16.9 | 30.1 |
| shadow only | 2.18 | 2.13 | 4.10 | 4.86 | 7.78 |
| blur only | 2.15 | 2.14 | 3.80 | 3.53 | 6.12 |
| neither | 0.93 | 0.96 | 1.50 | 1.30 | 2.04 |

Median ms, variants interleaved (40 iterations for the empty frames, fewer for the scene). An empty frame draws nothing, so its time is the per-pixel cost every frame pays (canvas clear, alpha conversion, copying the result out) plus, for PNG, encoding a flat image. The scene is the one of the event-loop animation: 12 rotated 60×60 discs with `box-shadow: 0 8px 30px` and `filter: blur(2px)`.
<!-- /native-bench:diagnose -->

### Formats and encoders

<!-- native-bench:formats -->
| Fixture | Format | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|--:|
| `lingrad-angles` | raw | 2.13 ms · 2 953 KiB | 2.22 ms · 2 953 KiB | 3.81 ms · 2 953 KiB | 4.47 ms · 2 953 KiB | 6.53 ms · 2 953 KiB |
| `lingrad-angles` | png | 6.49 ms · 32.6 KiB | 6.40 ms · 32.6 KiB | 9.84 ms · 32.6 KiB | 7.78 ms · 102 KiB | 34.6 ms · 102 KiB |
| `lingrad-angles` | jpeg | 11.0 ms · 52.2 KiB | 11.3 ms · 52.2 KiB | 18.7 ms · 52.2 KiB | 17.8 ms · 52.3 KiB | 24.0 ms · 52.3 KiB |
| `lingrad-angles` | webp | 7.02 ms · 28.9 KiB | 7.27 ms · 28.9 KiB | 10.4 ms · 28.9 KiB | 109 ms · 22.8 KiB | 15.3 ms · 169 KiB |
| `img-photo-bg` | raw | 1.17 ms · 2 953 KiB | 1.24 ms · 2 953 KiB | 1.66 ms · 2 953 KiB | 3.76 ms · 2 953 KiB | 5.89 ms · 2 953 KiB |
| `img-photo-bg` | png | 28.5 ms · 511 KiB | 28.7 ms · 511 KiB | 39.9 ms · 511 KiB | 11.3 ms · 513 KiB | 53.4 ms · 513 KiB |
| `img-photo-bg` | jpeg | 10.6 ms · 55.1 KiB | 10.8 ms · 55.1 KiB | 17.2 ms · 55.1 KiB | 17.6 ms · 55.2 KiB | 24.2 ms · 55.2 KiB |
| `img-photo-bg` | webp | 13.6 ms · 367 KiB | 13.8 ms · 367 KiB | 19.2 ms · 367 KiB | 160 ms · 414 KiB | 20.7 ms · 470 KiB |
| `card-flat-ui` | raw | 2.68 ms · 2 953 KiB | 2.68 ms · 2 953 KiB | 4.45 ms · 2 953 KiB | 3.65 ms · 2 953 KiB | 6.72 ms · 2 953 KiB |
| `card-flat-ui` | png | 5.39 ms · 23.1 KiB | 5.31 ms · 23.1 KiB | 8.40 ms · 23.1 KiB | 6.48 ms · 25.3 KiB | 19.2 ms · 25.3 KiB |
| `card-flat-ui` | jpeg | 11.6 ms · 48.9 KiB | 11.8 ms · 48.9 KiB | 19.1 ms · 48.9 KiB | 17.1 ms · 49.0 KiB | 24.5 ms · 49.0 KiB |
| `card-flat-ui` | webp | 6.91 ms · 18.5 KiB | 6.96 ms · 18.5 KiB | 9.66 ms · 18.5 KiB | 16.8 ms · 13.4 KiB | 12.6 ms · 27.6 KiB |

Median time and output size. JPEG: quality 85 for every engine. WebP: lossless for every engine (no `quality`); takumi-native encodes with libwebp, takumi-wasm with the `image-webp` crate (hence its larger files). PNG: no engine exposes a compression level; each uses its default encoder effort (bm: its own deflate; takumi: `png` + `zlib-rs`, choosing between level 7 / no filter and level 3 / adaptive filter on a sample, deflating in up to 8 segments in parallel on the native build), so PNG times are compared together with file sizes.
<!-- /native-bench:formats -->

Per category, per fixture, the methodology and the noise record: [the full report](../BENCHMARK.md)
(Vietnamese) and `docs/results-native.json`.

## Test conditions and how to reproduce

<!-- native-bench:env -->
| Item | Value |
|:--|:--|
| Machine | Intel(R) Core(TM) i3-10100 CPU @ 3.60GHz, 8 logical CPUs, 7.80 GiB, win32 10.0.26200 x64 |
| Node.js | v26.13.0 (V8 14.6.202.34-node.40, N-API 10, libuv 1.52.1) |
| bm-engine | 0.1.0, git `e5c535cbbf` (main, 3 modified tracked files) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 3 327 KiB, Zig 0.17.1, ReleaseFast, sha256 `1d5ff5ea0a4f` |
| bm-wasm | `js/bm_engine.wasm` (full profile), 1 144 KiB, sha256 `a7e1528586ac` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Run | 2026-11-13 04:23 UTC, full mode, 250 fixtures, 16.0 min; CPU busy before the run: 5.00 % |
<!-- /native-bench:env -->

```sh
node bench/run-native.mjs           # everything: JSON, Markdown, and the tables on this page
node bench/run-native.mjs --quick   # a short smoke run
node bench/native-identity.mjs      # only the native == wasm byte comparison
```

The run writes `bench/out/native/results-native.json` and `NATIVE.md`, copies the JSON to
`docs/results-native.json` and rewrites the tables of this page (and of the benchmark pages) between their
`native-bench` marker comments, so no number on this page is typed by hand. The machine was shared with
other build and test jobs while it ran; the noise record is in the full report.
