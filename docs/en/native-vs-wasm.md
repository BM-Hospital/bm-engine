# Native addon vs WebAssembly

[English](native-vs-wasm.md) · [Tiếng Việt](../vi/native-vs-wasm.md)

On Node.js, bm-engine runs either as a native Node-API addon or as WebAssembly. Both are compiled from the
same Zig source, expose the same API and produce the same bytes. This page explains which one you get, when
to choose the other, how the native backend uses threads, and how both compare with takumi's native and wasm
builds on the 200-fixture benchmark suite. Installation: [Getting started](./getting-started.md).
How the platform packages are built and published: [Publishing](./publishing.md).

## Which backend to use

| Where your code runs | Backend | How |
|:--|:--|:--|
| Node.js, Bun, Deno (servers, CLIs, build scripts) | **native**, with an automatic fallback to wasm | `import { Renderer, backend } from "bm-engine"`; `backend` is `"native"` or `"wasm"` |
| Browsers, Web Workers | wasm (the only option) | `bm-engine` resolves to the wasm build there |
| Cloudflare Workers, Vercel / Netlify Edge, Deno Deploy and other edge runtimes | wasm (the only option) | same import |
| Node.js, but you want wasm anyway (for example to reproduce a browser render bit for bit, or on a host whose addon has not been tested yet) | wasm | `import ... from "bm-engine/full"` or `BM_ENGINE_BACKEND=wasm` |
| Node.js, and you want an error rather than a silent fallback | native | `import ... from "bm-engine/native"` or `BM_ENGINE_BACKEND=native` |

The fallback is silent: if no addon is installed for the platform, if the CPU is older than x86-64-v2
(SSE4.2), or if the addon fails its load-time floating-point check, `bm-engine` loads the wasm build and
everything keeps working, only slower and with async calls on the main thread. Log `backend` once at startup
if you need to know.

## Results at a glance

<!-- native-bench:highlights -->
- **bm-native vs bm-wasm (sync):** raw 0.76× the wasm time [0.77× / 0.75× / 0.80×] (faster on 192/200 fixtures), PNG 0.67× [0.68× / 0.67× / 0.68×] (faster on 200/200).
- **bm-native vs takumi-native, both async:** raw 0.89× [0.90× / 0.88× / 0.95×] (bm faster on 136/200, per fixture 0.22×–2.78×), PNG 0.68× [0.67× / 0.65× / 0.66×] (bm faster on 170/200, per fixture 0.28×–2.21×). With bm's sync API: raw 0.69×, PNG 0.66×. Below 1× = bm-native takes less time; in brackets the same ratio in each pass.
- **CPU time per image (both async):** PNG 3.29 ms bm-native vs 5.28 ms takumi-native (1.11 vs 1.45 cores busy during a render); raw 2.25 vs 2.30 ms. takumi-native runs parts of one render (PNG deflate segments, blur, WebP, animation frames) on its own rayon thread pool; bm renders one image on one thread (bm-native sync: 0.88 cores for PNG).
- **takumi's own two builds:** takumi-native takes 0.69× the time of takumi-wasm for raw and 0.48× for PNG.
- **Identity:** bm-native and bm-wasm produced the same bytes in 1457/1457 comparisons over 200 fixtures (586 MB; 0 mismatches).
- **Noise:** the absolute raw / PNG geomeans moved by up to 40.1 % between passes (the load from other processes changed during the run), while the engine-to-engine ratios, measured interleaved inside each pass, moved by at most 17.9 %. Read the ratios; treat absolute milliseconds as ±20.1 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Metric | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — sync API | 0.96 ±7.00 % ⚠ | 1.26 ±5.20 % ⚠ | no sync API | — |
| raw RGBA, geomean ms — async API | 1.25 ±20.1 % ⚠ | — | 1.40 ±15.3 % ⚠ | 2.02 ±6.45 % ⚠ |
| PNG, geomean ms — sync API | 1.80 ±5.85 % ⚠ | 2.67 ±5.50 % ⚠ | no sync API | — |
| PNG, geomean ms — async API | 1.83 ±11.8 % ⚠ | — | 2.71 ±11.1 % ⚠ | 5.63 ±5.45 % ⚠ |
| CPU time per PNG render, mean ms (cores used) | 2.46 (0.88 cores) | 3.19 (0.78 cores) | 5.28 (1.45 cores) | 7.29 (0.85 cores) |
| PNG file size, geomean vs takumi | 0.78× | 0.78× | 1.00× | 1.00× |
| Cold start over empty Node, median / p95 ms | 28.6 / 75.5 | 96.5 / 139 | 60.2 / 83.8 | 238 / 282 |
| RSS after 1 → 10 suite passes, MiB | 91.9 → 93.4 | 126 → 126 | 147 → 160 | 132 → 161 |
| Peak RSS, one 4000×4000 PNG, MiB | 146 | 149 | 137 | 151 |
| Event loop: max 1 ms-timer delay, heavy 2400×2400 render, ms | 299 (sync) · 3.90 (async) | 700 (sync) · 604 (async) | 15.3 (async) | 1 095 (async) |
| Event loop: same, 60-frame animation, ms | 5 376 (sync) · 6.50 (async) | 10 866 (sync) · 9 086 (async) | 30.1 (async) | 2 563 (async) |
| Throughput, og card PNG, 4 concurrent, images/s (best config) | 177 (many K=4, UV 4) ⚠ | 119 (pool K=8) ⚠ | 170 (many K=2, UV 4) ⚠ | 78.5 (pool K=4) ⚠ |
| Throughput, 8 concurrent, images/s (best config) | 247 (many K=8, UV 8) ⚠ | 157 (pool K=8) ⚠ | 200 (one, UV 8) ⚠ | 88.9 (pool K=8) ⚠ |

Geomeans over the 200 fixtures every engine rendered; ± = half the range of the 3 passes' geomeans relative to their median; ⚠ = more than 10 % range. Cold start: median / p95 of 30 fresh processes minus the empty-Node median. Event-loop, memory and throughput are single runs; on the throughput rows ⚠ = other processes used more than one core on average during that stage.
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
  pool with one engine instance per worker ([recipe](./recipes.md#worker-threads-pool)). This is also what
  the benchmark measures for bm-wasm and takumi-wasm.

### Throughput under concurrency

<!-- native-bench:throughput -->
| Engine | Setup | UV_THREADPOOL_SIZE | N=1 | N=2 | N=4 | N=8 | N=16 |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 1 client, sequential | 4 | 58.9 |  |  |  |  |
| bm-wasm | 1 client, sequential | — | 37.1 |  |  |  |  |
| takumi-native | 1 client, sequential | 4 | 75.2 |  |  |  |  |
| takumi-wasm | 1 client, sequential | — | 26.6 |  |  |  |  |
| bm-native | 1 renderer, async | 4 | 63.8 (1.08×, 108 %) | 64.2 (1.09×, 109 %) | 66.3 (1.13×, 113 %) | 68.6 (1.16×, 116 %) | 70.7 (1.20×, 120 %) |
| bm-native | 2 renderers, async | 4 | 68.9 (1.17×, 117 %) | 116 (1.97×, 99 %) | 98.0 (1.66×, 83 %) | 99.9 (1.70×, 85 %) | 106 (1.79×, 90 %) |
| bm-native | 4 renderers, async | 4 | 66.1 (1.12×, 112 %) | 108 (1.83×, 91 %) | 177 (3.00×, 75 %) | 188 (3.20×, 80 %) | 168 (2.86×, 71 %) |
| bm-native | 8 renderers, async | 4 | 59.0 (1.00×, 100 %) | 92.0 (1.56×, 78 %) | 159 (2.70×, 68 %) | 160 (2.71×, 68 %) | 150 (2.55×, 64 %) |
| bm-native | 1 renderer, async | 8 | 62.0 (1.05×, 105 %) | 63.8 (1.08×, 108 %) | 64.2 (1.09×, 109 %) | 63.4 (1.08×, 108 %) | 53.6 (0.91×, 91 %) |
| bm-native | 2 renderers, async | 8 | 68.4 (1.16×, 116 %) | 105 (1.79×, 89 %) | 116 (1.97×, 99 %) | 71.8 (1.22×, 61 %) | 109 (1.85×, 93 %) |
| bm-native | 4 renderers, async | 8 | 70.5 (1.20×, 120 %) | 106 (1.81×, 90 %) | 173 (2.93×, 73 %) | 189 (3.20×, 80 %) | 201 (3.41×, 85 %) |
| bm-native | 8 renderers, async | 8 | 69.7 (1.18×, 118 %) | 101 (1.72×, 86 %) | 154 (2.62×, 65 %) | 247 (4.19×, 52 %) | 220 (3.74×, 47 %) |
| takumi-native | 1 renderer, async | 4 | 94.0 (1.25×, 125 %) | 121 (1.60×, 80 %) | 158 (2.10×, 52 %) | 164 (2.18×, 55 %) | 166 (2.21×, 55 %) |
| takumi-native | 1 renderer, async | 8 | 87.9 (1.17×, 117 %) | 123 (1.64×, 82 %) | 158 (2.10×, 52 %) | 200 (2.66×, 33 %) | 205 (2.73×, 34 %) |
| takumi-native | 2 renderers, async | 4 | 87.0 (1.16×, 116 %) | 102 (1.36×, 68 %) | 170 (2.26×, 113 %) | 178 (2.37×, 119 %) | 177 (2.35×, 118 %) |
| takumi-native | 4 renderers, async | 4 | 77.4 (1.03×, 103 %) | 126 (1.68×, 84 %) | 167 (2.22×, 56 %) | 176 (2.34×, 58 %) | 173 (2.30×, 57 %) |
| takumi-native | 2 renderers, async | 8 | 87.9 (1.17×, 117 %) | 133 (1.76×, 88 %) | 163 (2.17×, 109 %) | 183 (2.44×, 122 %) | 184 (2.45×, 123 %) |
| takumi-native | 4 renderers, async | 8 | 81.3 (1.08×, 108 %) | 97.5 (1.30×, 65 %) | 161 (2.13×, 53 %) | 182 (2.42×, 60 %) | 180 (2.39×, 60 %) |
| bm-wasm | worker pool, 1 worker | — | 41.6 (1.12×, 112 %) | 42.3 (1.14×, 114 %) | 42.3 (1.14×, 114 %) | 42.8 (1.15×, 115 %) | 40.5 (1.09×, 109 %) |
| bm-wasm | worker pool, 2 workers | — | 48.7 (1.31×, 131 %) | 80.6 (2.17×, 109 %) | 77.0 (2.08×, 104 %) | 69.6 (1.88×, 94 %) | 70.7 (1.91×, 95 %) |
| bm-wasm | worker pool, 4 workers | — | 40.9 (1.10×, 110 %) | 80.8 (2.18×, 109 %) | 116 (3.12×, 78 %) | 123 (3.31×, 83 %) | 114 (3.08×, 77 %) |
| bm-wasm | worker pool, 8 workers | — | 43.3 (1.17×, 117 %) | 68.1 (1.84×, 92 %) | 119 (3.22×, 80 %) | 157 (4.22×, 53 %) | 166 (4.49×, 56 %) |
| takumi-wasm | worker pool, 1 worker | — | 21.4 (0.80×, 80 %) | 23.9 (0.90×, 90 %) | 27.8 (1.05×, 105 %) | 27.1 (1.02×, 102 %) | 29.7 (1.12×, 112 %) |
| takumi-wasm | worker pool, 2 workers | — | 28.4 (1.07×, 107 %) | 53.0 (1.99×, 100 %) | 50.5 (1.90×, 95 %) | 49.6 (1.86×, 93 %) | 54.3 (2.04×, 102 %) |
| takumi-wasm | worker pool, 4 workers | — | 27.5 (1.03×, 103 %) | 44.2 (1.66×, 83 %) | 78.5 (2.95×, 74 %) | 84.3 (3.17×, 79 %) | 87.3 (3.28×, 82 %) |
| takumi-wasm | worker pool, 8 workers | — | 27.7 (1.04×, 104 %) | 50.7 (1.91×, 95 %) | 72.6 (2.73×, 68 %) | 88.9 (3.34×, 42 %) | 95.8 (3.60×, 45 %) |

Images per second; in brackets the speed-up over the same engine's sequential single-client rate (first rows) and the scaling efficiency = speed-up / min(N, threads that can render different images at once, 8 logical CPUs); a bm renderer counts as 1, K renderers as min(K, UV_THREADPOOL_SIZE), takumi-native's renderer as UV_THREADPOOL_SIZE, a worker pool as K. card-og 1200x630 PNG, closed loop: N clients each with one request in flight; 2000 ms per point after a warm-up. CPU busy during the stage: 98.4 % mean (other processes ≈ 6.17 cores). ⚠ Other processes used about 6.17 of the machine's cores on average during this stage, so these figures (scaling above all) understate what an idle machine gives; re-run on a quiet machine before quoting them.
<!-- /native-bench:throughput -->

## Output identity

The two backends produce the **same bytes**: on every fixture of the benchmark suite, raw RGBA, PNG, JPEG,
WebP, SVG and `measure` output, animations (WebP / APNG / GIF), ICO, HTML sources, image attachments, WOFF2
fonts and error messages are compared byte for byte (`node bench/native-identity.mjs`), and native async
results are compared with native sync results. A server can switch backends (or fall back) without any
visible change in its images or caches. The guarantee is tested on Windows x64 only so far; see the platform
table.

<!-- native-bench:equiv -->
| Engine vs takumi-wasm (200 fixtures, raw RGBA) | identical | equivalent | close | different | error/unsupported |
|:--|--:|--:|--:|--:|--:|
| bm-native | 74 | 126 | 0 | 0 | 0 |
| bm-wasm | 74 | 126 | 0 | 0 | 0 |
| takumi-native | 200 | 0 | 0 | 0 | 0 |

| Same engine, two builds | raw RGBA byte-identical | PNG file byte-identical |
|:--|--:|--:|
| bm-native = bm-wasm | 200/200 | 200/200 |
| takumi-native = takumi-wasm | 200/200 | 200/200 |

`bench/native-identity.mjs`: 200 fixtures, 1457 comparisons (raw, PNG, JPEG, WebP, measure, SVG, animations, ICO, HTML, images, WOFF2, error messages, native async vs sync), 1457 identical (8 of them the same error message on both), 0 mismatches, 586 MB compared.
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
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 2 010 | 1 077 | 880 | executed (this benchmark) |
| `bm-engine.win32-arm64-msvc.node` | `aarch64-windows-gnu` | 1 570 | 954 | 743 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-x64-gnu.node` | `x86_64-linux-gnu.2.17` | 1 901 | 1 041 | 856 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-x64-musl.node` | `x86_64-linux-musl` | 1 900 | 1 041 | 856 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-arm64-gnu.node` | `aarch64-linux-gnu.2.17` | 1 571 | 955 | 743 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-arm64-musl.node` | `aarch64-linux-musl` | 1 571 | 955 | 742 | cross-compiled, structurally verified, never executed |
| `bm-engine.darwin-x64.node` | `x86_64-macos.10.15` | 1 901 | 1 040 | 855 | cross-compiled, structurally verified, never executed |
| `bm-engine.darwin-arm64.node` | `aarch64-macos.11.0` | 1 594 | 929 | 712 | cross-compiled, structurally verified, never executed |
| bm wasm `core` | wasm32 | 454 | 212 | 180 |  |
| bm wasm `standard` | wasm32 | 878 | 435 | 374 |  |
| bm wasm `full` | wasm32 | 1 100 | 538 | 453 |  |
| bm wasm `WOFF add-on` | wasm32 | 84.2 | 67.7 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Native addons from `native/dist/manifest.json` (built 2026-11-12 with Zig 0.17.1, ReleaseFast). Each user downloads one addon (the optional package for their platform) plus the wasm fallback that ships in the main package.
<!-- /native-bench:sizes -->

## Event loop

<!-- native-bench:eventloop -->
| Job | Engine | API | job ms | CPU ms | max timer delay ms | p99 delay ms | timer ticks |
|:--|--:|--:|--:|--:|--:|--:|--:|
| heavy | bm-native | sync | 298 | 297 | 299 | 299 | 1 |
| heavy | bm-native | async | 333 | 687 | 3.90 | 1.50 | 331 |
| heavy | bm-wasm | sync | 700 | 890 | 700 | 700 | 1 |
| heavy | bm-wasm | async (runs on the main thread) | 603 | 797 | 604 | 604 | 1 |
| heavy | takumi-native | async | 301 | 735 | 15.3 | 2.00 | 286 |
| heavy | takumi-wasm | async (runs on the main thread) | 1 095 | 1 297 | 1 095 | 1 095 | 1 |
| anim | bm-native | sync | 5 374 | 5 031 | 5 376 | 5 376 | 1 |
| anim | bm-native | async | 5 820 | 11 172 | 6.50 | 1.80 | 5749 |
| anim | bm-wasm | sync | 10 866 | 10 453 | 10 866 | 10 866 | 1 |
| anim | bm-wasm | async (runs on the main thread) | 9 086 | 9 234 | 9 086 | 9 086 | 1 |
| anim | takumi-native | async | 414 | 2 204 | 30.1 | 22.6 | 257 |
| anim | takumi-wasm | async (runs on the main thread) | 2 562 | 2 938 | 2 563 | 2 563 | 1 |

heavy = one 2400x2400 PNG: gradient, 24 cards with large blurred box-shadows, every third with filter: blur(6px), text; anim = renderAnimation: 60 frames (2 s at 30 fps) of 800x420 lossless WebP, 12 shadowed, blurred, rotated discs (a static scene). A 1 ms `setInterval` records the gap between its ticks while the call runs. A setImmediate chain keeps the loop from sleeping, because an idle Node loop on Windows wakes on the 15.6 ms system clock and the timer would otherwise never show less than ~16 ms. A call that blocks the loop shows one tick whose delay is the whole call. CPU ms is the whole process during the call, including the setImmediate chain on the main thread (about one core whenever the loop is free). ⚠ Other processes used about 5.40 of the machine's cores on average during this stage, so these figures (scaling above all) understate what an idle machine gives; re-run on a quiet machine before quoting them.
<!-- /native-bench:eventloop -->

## Cold start

<!-- native-bench:cold -->
| Engine | wall median | wall p95 | over Node, median | over Node, p95 | import | registerFont | first PNG |
|:--|--:|--:|--:|--:|--:|--:|--:|
| empty Node (baseline) | 66.5 | 86.7 | 0 | 0 | — | — | — |
| bm-native | 95.1 | 142 | 28.6 | 75.5 | 6.50 | 0.44 | 22.9 |
| bm-wasm | 163 | 205 | 96.5 | 139 | 8.90 | 3.20 | 85.1 |
| takumi-native | 127 | 150 | 60.2 | 83.8 | 29.5 | 0.97 | 27.2 |
| takumi-wasm | 305 | 348 | 238 | 282 | 46.7 | 4.18 | 187 |

ms. 30 runs per engine, engines interleaved; spawn node -> import the engine as a user does -> registerFont(Inter Regular) -> 1200x630 og card PNG -> exit; wall = parent clock spawn to exit. The import / registerFont / first-PNG columns are medians measured inside the child. CPU busy during the stage: 82.7 % mean (other processes ≈ 5.24 cores). ⚠ Other processes used about 5.24 of the machine's cores on average during this stage, so these figures (scaling above all) understate what an idle machine gives; re-run on a quiet machine before quoting them.
<!-- /native-bench:cold -->

## Memory

<!-- native-bench:memory -->
| Engine | RSS after setup | RSS after pass 1 → 10 | engine memory 1 → N | JS heap 1 → N | peak RSS, suite | peak RSS 4000×4000 PNG (growth) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 65.6 | 91.9 → 93.4 | 28.2 → 28.2 | 7.20 → 6.20 | 218 | 146 (85.8) |
| bm-wasm | 67.0 | 126 → 126 | 60.4 → 60.4 | 7.40 → 6.40 | 223 | 149 (87.6) |
| takumi-native | 67.5 | 147 → 160 | — → — | 7.40 → 6.40 | 190 | 137 (74.9) |
| takumi-wasm | 73.1 | 132 → 161 | 67.2 → 67.2 | 7.10 → 7.20 | 224 | 151 (82.9) |

MiB, after a forced GC. One process per engine; every fixture rendered to raw and PNG (async API) per pass, one renderer per font set. Engine memory: bm-native = bytes allocated by the addon (`memoryBytes()`), bm-wasm / takumi-wasm = the wasm linear memory, takumi-native = not exposed. Empty Node: 48.2 MiB RSS. "Growth" = peak RSS minus the RSS just before the 4000×4000 render.
<!-- /native-bench:memory -->

## Render time

<!-- native-bench:speed -->
| Format (fixtures) | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| raw (200) | 0.96 ±7.00 % ⚠ | 1.25 ±20.1 % ⚠ | 1.26 ±5.20 % ⚠ | 1.40 ±15.3 % ⚠ | 2.02 ±6.45 % ⚠ |
| png (200) | 1.80 ±5.85 % ⚠ | 1.83 ±11.8 % ⚠ | 2.67 ±5.50 % ⚠ | 2.71 ±11.1 % ⚠ | 5.63 ±5.45 % ⚠ |
| jpeg (3) | 17.3 ±13.1 % ⚠ | 17.5 ±12.7 % ⚠ | 30.2 ±13.7 % ⚠ | 26.8 ±16.9 % ⚠ | 40.7 ±14.2 % ⚠ |
| webp (3) | 11.3 ±15.1 % ⚠ | 11.8 ±19.1 % ⚠ | 18.2 ±16.3 % ⚠ | 93.5 ±14.3 % ⚠ | 23.3 ±17.2 % ⚠ |
| raw, without known-gaps | 0.99 | 1.30 | 1.31 | 1.44 | 2.08 |
| png, without known-gaps | 1.86 | 1.90 | 2.76 | 2.78 | 5.76 |
| raw, per pass | 1.00 / 0.88 / 1.02 | 1.35 / 1.12 / 1.67 | 1.31 / 1.18 / 1.29 | 1.51 / 1.29 / 1.75 | 2.09 / 1.88 / 2.15 |
| png, per pass | 1.87 / 1.66 / 1.83 | 1.97 / 1.68 / 2.15 | 2.77 / 2.47 / 2.69 | 2.96 / 2.59 / 3.24 | 5.89 / 5.25 / 5.88 |

Geometric mean of the per-fixture median render time, ms. jpeg (quality 85) and webp (lossless; takumi-wasm uses a different WebP encoder from takumi-native, see the format table) are timed on three fixtures only.
<!-- /native-bench:speed -->

<!-- native-bench:cpu -->
| Variant | raw: wall / CPU ms / cores | PNG: wall / CPU ms / cores |
|:--|--:|--:|
| bm-native sync | 1.10 / 0.98 / 0.89 | 2.80 / 2.46 / 0.88 |
| bm-native async | 1.59 / 2.25 / 1.42 | 2.96 / 3.29 / 1.11 |
| bm-wasm sync | 1.42 / 1.21 / 0.86 | 4.07 / 3.19 / 0.78 |
| takumi-native async | 1.71 / 2.30 / 1.34 | 3.63 / 5.28 / 1.45 |
| takumi-wasm | 2.31 / 1.85 / 0.80 | 8.56 / 7.29 / 0.85 |

Mean over every timed render of the suite (not a geomean): wall time per render, process CPU time (all threads) spent during it, and their ratio. A ratio above 1 means one render kept more than one core busy.
<!-- /native-bench:cpu -->

Where bm-native is furthest ahead of and behind takumi-native (both async):

<!-- native-bench:best-worst -->
**raw — bm-native's 10 best**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `pfx-bg-blend` | 1.03 | 1.15 | 5.25 | 0.78 | 0.22× |
| `img-jpeg-fit` | 2.49 | 3.54 | 15.3 | 0.92 | 0.23× |
| `pfx-bg-clip-text` | 0.68 | 0.82 | 2.84 | 1.14 | 0.29× |
| `gap-background-clip-text` | 0.47 | 0.57 | 1.96 | 1.35 | 0.29× |
| `anim-delay-fill-t0` | 0.29 | 0.40 | 0.95 | 0.64 | 0.42× |
| `opacity-with-radius-shadow` | 1.22 | 1.33 | 2.85 | 1.32 | 0.47× |
| `radial-spotlight-small` | 0.75 | 0.95 | 2.02 | 1.13 | 0.47× |
| `radial-shapes` | 3.48 | 4.56 | 8.75 | 1.21 | 0.52× |
| `radial-at-position` | 4.18 | 5.41 | 10.3 | 1.18 | 0.53× |
| `anim-color-t2000` | 0.27 | 0.31 | 0.58 | 2.33 | 0.54× |

**raw — bm-native's 10 worst**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `radius-uniform-percorner` | 3.13 | 4.88 | 1.75 | 0.92 | 2.78× |
| `sizing-aspect-ratio` | 2.32 | 3.98 | 1.71 | 0.93 | 2.34× |
| `radius-pill-circle` | 2.76 | 4.99 | 2.16 | 1.75 | 2.31× |
| `radius-elliptical` | 2.79 | 4.14 | 1.85 | 1.42 | 2.24× |
| `sizing-minmax` | 2.01 | 2.65 | 1.26 | 0.95 | 2.10× |
| `flex-row-column` | 2.19 | 2.89 | 1.38 | 1.24 | 2.09× |
| `abs-zorder` | 3.09 | 4.04 | 2.02 | 0.70 | 2.00× |
| `flex-grow-shrink-basis` | 1.74 | 2.79 | 1.42 | 2.08 | 1.96× |
| `css-media-layer` | 1.26 | 1.99 | 1.02 | 3.43 | 1.95× |
| `tw-responsive` | 1.27 | 1.84 | 0.96 | 2.01 | 1.92× |

**png — bm-native's 10 best**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `pseudo-attr` | 1.00 | 1.04 | 3.71 | 0.93 | 0.28× |
| `layout2-float-clear` | 0.82 | 0.78 | 2.13 | 1.36 | 0.37× |
| `abs-in-flow` | 0.63 | 0.59 | 1.54 | 0.78 | 0.39× |
| `css-important-var` | 1.28 | 1.31 | 3.33 | 0.85 | 0.39× |
| `anim-color-t300` | 0.44 | 0.41 | 1.04 | 1.29 | 0.40× |
| `anim-color-t700` | 0.45 | 0.42 | 1.05 | 0.96 | 0.40× |
| `anim-color-t2000` | 0.44 | 0.42 | 1.04 | 1.75 | 0.41× |
| `colors-solid-bg` | 0.59 | 0.57 | 1.39 | 2.10 | 0.41× |
| `overflow-nested` | 0.69 | 0.68 | 1.65 | 1.13 | 0.41× |
| `flex-nested-small` | 0.49 | 0.50 | 1.19 | 0.96 | 0.42× |

**png — bm-native's 10 worst**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-photo-bg` | 39.0 | 38.8 | 17.6 | 2.97 | 2.21× |
| `img-intrinsic-size` | 2.73 | 2.72 | 1.62 | 3.53 | 1.68× |
| `card-blog` | 22.2 | 24.2 | 15.6 | 2.70 | 1.55× |
| `fx-text-shadow` | 3.75 | 3.86 | 2.53 | 2.87 | 1.52× |
| `img-png-fit` | 17.8 | 17.7 | 12.0 | 1.51 | 1.47× |
| `pfx-mix-blend` | 4.13 | 4.15 | 2.85 | 0.78 | 1.46× |
| `img-radius-clip` | 20.8 | 19.3 | 13.3 | 1.90 | 1.46× |
| `card-og` | 13.7 | 14.7 | 10.4 | 2.73 | 1.42× |
| `radial-spotlight-small` | 6.48 | 6.53 | 5.05 | 1.99 | 1.29× |
| `pfx-drop-shadow` | 3.48 | 3.46 | 2.69 | 1.32 | 1.28× |
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
| 300×200 raw | 0.16 | 0.24 | 0.18 | 0.27 | 0.38 |
| 300×200 png | 0.34 | 0.31 | 0.45 | 0.63 | 0.84 |
| 1200×630 raw | 1.61 | 2.53 | 1.55 | 1.05 | 1.64 |
| 1200×630 png | 3.03 | 2.80 | 4.36 | 4.31 | 8.20 |
| 2400×1260 raw | 6.42 | 11.0 | 6.20 | 3.31 | 7.71 |
| 2400×1260 png | 10.9 | 10.2 | 15.1 | 13.0 | 27.5 |

| Animation scene, one 800×420 raw frame | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| shadow + blur (as animated) | 73.2 | 74.5 | 145 | 18.8 | 35.9 |
| shadow only | 2.60 | 2.77 | 4.73 | 5.55 | 8.72 |
| blur only | 66.1 | 66.8 | 124 | 3.96 | 7.60 |
| neither | 1.46 | 1.92 | 1.76 | 1.52 | 2.22 |

Median ms, variants interleaved (40 iterations for the empty frames, fewer for the scene). An empty frame draws nothing, so its time is the per-pixel cost every frame pays (canvas clear, alpha conversion, copying the result out) plus, for PNG, encoding a flat image. The scene is the one of the event-loop animation: 12 rotated 60×60 discs with `box-shadow: 0 8px 30px` and `filter: blur(2px)`.
<!-- /native-bench:diagnose -->

### Formats and encoders

<!-- native-bench:formats -->
| Fixture | Format | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|--:|
| `lingrad-angles` | raw | 4.43 ms · 2 953 KiB | 7.89 ms · 2 953 KiB | 6.75 ms · 2 953 KiB | 9.07 ms · 2 953 KiB | 11.4 ms · 2 953 KiB |
| `lingrad-angles` | png | 10.7 ms · 32.6 KiB | 11.1 ms · 32.6 KiB | 16.5 ms · 32.6 KiB | 12.3 ms · 102 KiB | 58.1 ms · 102 KiB |
| `lingrad-angles` | jpeg | 18.9 ms · 52.2 KiB | 17.7 ms · 52.2 KiB | 33.7 ms · 52.2 KiB | 27.9 ms · 52.3 KiB | 42.0 ms · 52.3 KiB |
| `lingrad-angles` | webp | 11.6 ms · 28.9 KiB | 10.9 ms · 28.9 KiB | 16.9 ms · 28.9 KiB | 168 ms · 22.8 KiB | 25.9 ms · 169 KiB |
| `img-photo-bg` | raw | 2.53 ms · 2 953 KiB | 3.59 ms · 2 953 KiB | 3.01 ms · 2 953 KiB | 5.69 ms · 2 953 KiB | 10.4 ms · 2 953 KiB |
| `img-photo-bg` | png | 39.0 ms · 511 KiB | 38.8 ms · 511 KiB | 52.2 ms · 511 KiB | 17.6 ms · 513 KiB | 76.6 ms · 513 KiB |
| `img-photo-bg` | jpeg | 14.5 ms · 55.1 KiB | 15.5 ms · 55.1 KiB | 24.4 ms · 55.1 KiB | 23.7 ms · 55.2 KiB | 38.1 ms · 55.2 KiB |
| `img-photo-bg` | webp | 16.6 ms · 367 KiB | 16.2 ms · 367 KiB | 27.1 ms · 367 KiB | 219 ms · 414 KiB | 26.6 ms · 470 KiB |
| `card-flat-ui` | raw | 4.47 ms · 2 953 KiB | 4.51 ms · 2 953 KiB | 6.29 ms · 2 953 KiB | 5.31 ms · 2 953 KiB | 8.98 ms · 2 953 KiB |
| `card-flat-ui` | png | 8.26 ms · 23.1 KiB | 8.80 ms · 23.1 KiB | 12.3 ms · 23.1 KiB | 9.57 ms · 25.3 KiB | 28.1 ms · 25.3 KiB |
| `card-flat-ui` | jpeg | 19.0 ms · 48.9 KiB | 19.5 ms · 48.9 KiB | 33.5 ms · 48.9 KiB | 29.1 ms · 49.0 KiB | 42.1 ms · 49.0 KiB |
| `card-flat-ui` | webp | 7.48 ms · 18.5 KiB | 9.30 ms · 18.5 KiB | 13.1 ms · 18.5 KiB | 22.2 ms · 13.4 KiB | 18.3 ms · 27.6 KiB |

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
| bm-engine | 0.1.0, git `987ef16d8d` (native, 5 modified tracked files) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 2 010 KiB, Zig 0.17.1, ReleaseFast, sha256 `0da5c5eda3b0` |
| bm-wasm | `js/bm_engine.wasm` (full profile), 1 100 KiB, sha256 `1bf382cb6985` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Run | 2026-11-12 08:36 UTC, full mode, 200 fixtures, 17.5 min; CPU busy before the run: 97.2 % |
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
