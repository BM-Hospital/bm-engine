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
