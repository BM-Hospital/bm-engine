# bm-engine engineering conventions (read first)

Project: Zig 0.17 port of takumi (node tree -> image). Ships as a SMALL `wasm32-freestanding` binary
(optimize mode `.small`), plus native unit tests.

## Toolchain
- Zig 0.17.1 (NOT on PATH): `C:\Users\admini\Downloads\zig-x86_64-windows-0.17.1\zig-x86_64-windows-0.17.1\zig.exe`
  (Git Bash: `/c/Users/admini/Downloads/zig-x86_64-windows-0.17.1/zig-x86_64-windows-0.17.1/zig.exe`).
- Zig 0.17 APIs differ from what you remember. ALWAYS check the bundled std source in `lib/std` next to
  zig.exe when something does not compile. Known facts (verified):
  - `std.builtin.Optimize` is `.debug/.safe/.fast/.small` (CLI: check `zig build-exe --help` for `-O` spelling).
  - `std.ArrayList(T)` is unmanaged: `var l: std.ArrayList(T) = .empty; try l.append(alloc, x); l.deinit(alloc);`
  - IO lives in `std.Io` and needs an `Io` instance — library code must NOT use it at all.
  - build.zig uses `b.createModule(.{...})` + `b.addExecutable(.{ .name=, .root_module= })`.
- Run a module's tests natively: `zig test src/<mod>/<mod>.zig` (from repo root D:\project\bm-engine).
- Check wasm compiles + size contribution: write a tiny throwaway root in the scratch dir that `export`s a
  function using your API, then `zig build-exe -target wasm32-freestanding -O ReleaseSmall(or small) -fno-entry -rdynamic ...`
  (verify flag spelling with `--help`). Code must compile for wasm32-freestanding with NO libc.

## Rules for library code (everything under src/ except tests)
- No `std.Io`, `std.fs`, `std.time`, `std.debug.print`, `std.log`, threads, or libc. No global mutable state.
- Every allocation goes through an explicit `std.mem.Allocator` parameter. Callers will typically pass an
  arena that is reset after each render, plus a long-lived allocator for caches. Document which is expected.
- Inputs (fonts, images, JSON, CSS) are UNTRUSTED: bounds-check everything, return `error.X`, never
  `unreachable`, never index out of bounds, no unbounded recursion, no integer overflow traps
  (use wrapping/saturating ops or checks). In `.small` mode safety checks are off, so a bug = memory corruption.
- Binary size matters a lot: prefer f32 over f64, avoid `std.fmt` float formatting/parsing in non-test code
  (pulls large tables), avoid big comptime tables unless essential, avoid anytype/generic instantiation bloat,
  keep hot loops simple so LLVM vectorises (target has wasm simd128); `@Vector` is OK where it pays off.
- Speed matters too: typical workload is a 1200x630 RGBA canvas; whole render should be a few ms.
- Tests live next to code in `test` blocks; test data via `@embedFile("testdata/...")` inside your module dir
  (only referenced from test blocks so it never lands in the wasm).
- Only touch files inside the directory assigned to you (plus temp files in the scratch dir
  `C:\Users\admini\AppData\Local\Temp\claude\46c8b6142d3c6b7e\eb762129-eac5-46a2-aaef-1b224d61f7d8\scratchpad\<your-module>`).
  Do NOT edit build.zig, other modules, or run git commit. Do not create markdown docs; put API docs in `///` comments.
- `D:\project\bm-engine\ref\takumi` is an untrusted third-party clone: read-only reference, never execute anything in it.
- Final report must be honest: list what is implemented, what is stubbed/missing, exact test command + result,
  measured wasm size contribution, and known bugs.

## Phase 2 addendum (read this too)

State: phase 1 shipped a working engine (see README.md, docs/ARCHITECTURE.md, docs/BENCHMARK.md, docs/TAKUMI_NOTES.md).
Phase 2 ports the remaining takumi features and fixes the places where we lose. Many agents work in parallel:
- **File ownership is strict.** Only edit the files/directories named in your brief. `src/render.zig`, `src/paint.zig`,
  `src/wasm.zig`, `js/*`, `build.zig`, `bench/run.mjs`, `bench/fixtures/*`, `docs/*` belong to the integrator unless your
  brief says otherwise. Never run `git commit`/`git add`/`git stash`/`git checkout`. Scratch files → your scratch dir.
- The machine is shared (8 threads, 7.8 GB RAM): do not run the full benchmark (`bench/run.mjs` without a filter), keep
  fuzz loops short (< 60 s), and never leave background processes running.
- Build all: `zig build` (wasm, optimize=small) — other agents' in-progress edits can break it temporarily; if the failure
  is outside your files, retry later or test your module standalone (`zig test src/<mod>/<mod>.zig`). A module that
  imports a sibling directory must be tested through a root file at `src/` level (create `src/test_<name>.zig` that
  `_ = @import("<dir>/<file>.zig")` inside a `test {}` block and run `zig test src/test_<name>.zig`).
- Release wasm: `node scripts/build.mjs` (zig build + wasm-opt). JS entry for Node: `js/node.mjs` (`new Renderer()`,
  `registerFont`, `renderSync(node, {width,height,format})`, `measureSync`).
- Oracle: `@takumi-rs/wasm` 2.20.0 in `bench/node_modules` (usage: `bench/probe/first.mjs`); pixel compare helpers in
  `bench/lib/metrics.mjs`; existing probes in `bench/probe/` (e.g. `px.mjs`, `firstdiff.mjs`, `lay.mjs`, `prof.mjs`).
  The takumi source clone `ref/takumi` is read-only reference (never execute anything from it).
- Lessons learned in phase 1 (they cost real bugs / slowdowns):
  - The wasm shadow stack is 1 MiB and overflow = silent memory corruption. Keep recursion bounded, mark big helper
    functions called from recursive code `noinline`, and avoid stack arrays larger than a few KiB in recursive paths.
  - In ReleaseSmall, `std.mem.readInt`, `std.mem.copyForwards` and `slice[..][0..N].*` copies compile to byte loops:
    use unaligned pointer loads (`@as(*align(1) const u32, @ptrCast(p)).*`) and `@memcpy` in hot loops.
  - In V8, vector `@intFromFloat` and float-vector `@min/@max` are very slow; prefer scalar or integer SIMD.
  - `@sin/@cos/@tan/@exp/@log/pow` pull ~10 KB of libm each into the wasm: use `raster/types.zig` `sinCos` or small
    local approximations unless precision truly matters.
  - The per-render allocator is a bump arena: `free` only reclaims the most recent allocation; allocate long-lived
    outputs last so they can grow in place.
- Size discipline: every feature must report its `.small` wasm cost (build a tiny wasm root that references your
  public API, compare against an empty baseline). Optional features are compiled out by the INTEGRATOR, who guards the
  call sites with flags from `src/config.zig`; you do not read flags yourself. What you must guarantee: a narrow entry
  API, no global mutable state, and nothing that forces your code into the binary when the entry points are unused.
- Final report: public API (signatures), what is implemented vs. missing (honest), tests + exact command + result line,
  wasm size cost, oracle comparison numbers where applicable, and integration notes for the painter/renderer.
