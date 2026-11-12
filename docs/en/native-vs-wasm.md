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
| Node.js, Bun, Deno, and you want PDF output | **native**, with an automatic fallback to the wasm `pdf` profile | `import { PdfRenderer, backend } from "bm-engine/pdf"`; see [PDF output](./pdf.md#native-backend-on-nodejs) |
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
- **bm-native vs bm-wasm (sync):** raw 0.60× the wasm time [0.60× / 0.59× / 0.60×] (faster on 250/250 fixtures), PNG 0.68× [0.68× / 0.68× / 0.68×] (faster on 250/250).
- **bm-native vs takumi-native, both async:** raw 0.55× [0.55× / 0.55× / 0.55×] (bm faster on 244/250, per fixture 0.13×–1.21×), PNG 0.56× [0.56× / 0.58× / 0.56×] (bm faster on 227/250, per fixture 0.23×–2.28×). With bm's sync API: raw 0.50×, PNG 0.56×. Below 1× = bm-native takes less time; in brackets the same ratio in each pass.
- **CPU time per image (both async):** PNG 2.32 ms bm-native vs 3.81 ms takumi-native (1.47 vs 1.78 cores busy during a render); raw 1.42 vs 1.71 ms. takumi-native runs parts of one render (PNG deflate segments, blur, WebP, animation frames) on its own rayon thread pool; bm renders one image on one thread (bm-native sync: 0.91 cores for PNG).
- **takumi's own two builds:** takumi-native takes 0.75× the time of takumi-wasm for raw and 0.56× for PNG.
- **Identity:** bm-native and bm-wasm produced the same bytes in 1810/1810 comparisons over 250 fixtures (637 MB; 0 mismatches).
- **Noise:** the absolute raw / PNG geomeans moved by up to 33.4 % between passes (the load from other processes changed during the run), while the engine-to-engine ratios, measured interleaved inside each pass, moved by at most 3.70 %. Read the ratios; treat absolute milliseconds as ±16.7 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Metric | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — sync API | 0.51 ±15.5 % ⚠ | 0.85 ±16.1 % ⚠ | no sync API | — |
| raw RGBA, geomean ms — async API | 0.56 ±15.7 % ⚠ | — | 1.02 ±15.3 % ⚠ | 1.36 ±15.8 % ⚠ |
| PNG, geomean ms — sync API | 1.05 ±14.6 % ⚠ | 1.56 ±15.0 % ⚠ | no sync API | — |
| PNG, geomean ms — async API | 1.06 ±16.7 % ⚠ | — | 1.89 ±14.5 % ⚠ | 3.36 ±15.8 % ⚠ |
| CPU time per PNG render, mean ms (cores used) | 1.42 (0.91 cores) | 1.78 (0.77 cores) | 3.81 (1.78 cores) | 4.08 (0.86 cores) |
| PNG file size, geomean vs takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start over empty Node, median / p95 ms | 31.3 / 69.2 | 99.9 / 138 | 50.9 / 97.5 | 238 / 304 |
| RSS after 1 → 10 suite passes, MiB | 94.7 → 96.0 | 132 → 156 | 102 → 139 | 140 → 176 |
| Peak RSS, one 4000×4000 PNG, MiB | 143 | 149 | 135 | 151 |
| Event loop: max 1 ms-timer delay, heavy 2400×2400 render, ms | 227 (sync) · 1.50 (async) | 455 (sync) · 473 (async) | 7.30 (async) | 819 (async) |
| Event loop: same, 60-frame animation, ms | 476 (sync) · 1.20 (async) | 969 (sync) · 954 (async) | 21.6 (async) | 2 072 (async) |
| Throughput, og card PNG, 4 concurrent, images/s (best config) | 312 (many K=4, UV 4) ⚠ | 233 (pool K=4) ⚠ | 270 (one, UV 8) ⚠ | 137 (pool K=8) ⚠ |
| Throughput, 8 concurrent, images/s (best config) | 402 (many K=8, UV 8) ⚠ | 270 (pool K=8) ⚠ | 316 (one, UV 8) ⚠ | 180 (pool K=8) ⚠ |

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
  pool with one engine instance per worker ([recipe](./recipes.md#worker-threads-pool)). This is also what
  the benchmark measures for bm-wasm and takumi-wasm.

### Throughput under concurrency

<!-- native-bench:throughput -->
| Engine | Setup | UV_THREADPOOL_SIZE | N=1 | N=2 | N=4 | N=8 | N=16 |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 1 client, sequential | 4 | 92.1 |  |  |  |  |
| bm-wasm | 1 client, sequential | — | 62.2 |  |  |  |  |
| takumi-native | 1 client, sequential | 4 | 115 |  |  |  |  |
| takumi-wasm | 1 client, sequential | — | 38.5 |  |  |  |  |
| bm-native | 1 renderer, async | 4 | 89.1 (0.97×, 97 %) | 97.9 (1.06×, 106 %) | 98.9 (1.07×, 107 %) | 98.9 (1.07×, 107 %) | 98.8 (1.07×, 107 %) |
| bm-native | 2 renderers, async | 4 | 96.6 (1.05×, 105 %) | 188 (2.04×, 102 %) | 191 (2.08×, 104 %) | 185 (2.01×, 101 %) | 182 (1.98×, 99 %) |
| bm-native | 4 renderers, async | 4 | 97.5 (1.06×, 106 %) | 189 (2.05×, 102 %) | 312 (3.39×, 85 %) | 312 (3.38×, 85 %) | 314 (3.41×, 85 %) |
| bm-native | 8 renderers, async | 4 | 96.9 (1.05×, 105 %) | 183 (1.99×, 99 %) | 309 (3.36×, 84 %) | 309 (3.35×, 84 %) | 305 (3.31×, 83 %) |
| bm-native | 1 renderer, async | 8 | 97.3 (1.06×, 106 %) | 101 (1.09×, 109 %) | 98.0 (1.06×, 106 %) | 100 (1.09×, 109 %) | 98.9 (1.07×, 107 %) |
| bm-native | 2 renderers, async | 8 | 97.9 (1.06×, 106 %) | 189 (2.05×, 102 %) | 187 (2.03×, 102 %) | 184 (1.99×, 100 %) | 190 (2.06×, 103 %) |
| bm-native | 4 renderers, async | 8 | 97.2 (1.06×, 106 %) | 184 (1.99×, 100 %) | 299 (3.25×, 81 %) | 274 (2.97×, 74 %) | 301 (3.26×, 82 %) |
| bm-native | 8 renderers, async | 8 | 96.9 (1.05×, 105 %) | 184 (2.00×, 100 %) | 312 (3.39×, 85 %) | 402 (4.36×, 55 %) | 416 (4.51×, 56 %) |
| takumi-native | 1 renderer, async | 4 | 124 (1.08×, 108 %) | 198 (1.71×, 86 %) | 264 (2.29×, 57 %) | 272 (2.36×, 59 %) | 267 (2.32×, 58 %) |
| takumi-native | 1 renderer, async | 8 | 123 (1.07×, 107 %) | 198 (1.72×, 86 %) | 270 (2.34×, 59 %) | 316 (2.74×, 34 %) | 303 (2.63×, 33 %) |
| takumi-native | 2 renderers, async | 4 | 124 (1.07×, 107 %) | 197 (1.71×, 85 %) | 264 (2.29×, 114 %) | 265 (2.30×, 115 %) | 267 (2.32×, 116 %) |
| takumi-native | 4 renderers, async | 4 | 123 (1.07×, 107 %) | 197 (1.71×, 85 %) | 231 (2.01×, 50 %) | 236 (2.04×, 51 %) | 220 (1.91×, 48 %) |
| takumi-native | 2 renderers, async | 8 | 108 (0.93×, 93 %) | 177 (1.53×, 77 %) | 238 (2.06×, 103 %) | 298 (2.59×, 129 %) | 311 (2.70×, 135 %) |
| takumi-native | 4 renderers, async | 8 | 124 (1.08×, 108 %) | 190 (1.64×, 82 %) | 259 (2.25×, 56 %) | 314 (2.73×, 68 %) | 287 (2.49×, 62 %) |
| bm-wasm | worker pool, 1 worker | — | 62.2 (1.00×, 100 %) | 68.1 (1.09×, 109 %) | 68.3 (1.10×, 110 %) | 68.1 (1.09×, 109 %) | 68.6 (1.10×, 110 %) |
| bm-wasm | worker pool, 2 workers | — | 67.9 (1.09×, 109 %) | 130 (2.09×, 105 %) | 129 (2.08×, 104 %) | 130 (2.10×, 105 %) | 131 (2.10×, 105 %) |
| bm-wasm | worker pool, 4 workers | — | 67.9 (1.09×, 109 %) | 123 (1.97×, 99 %) | 233 (3.74×, 94 %) | 217 (3.49×, 87 %) | 228 (3.67×, 92 %) |
| bm-wasm | worker pool, 8 workers | — | 64.5 (1.04×, 104 %) | 113 (1.81×, 91 %) | 193 (3.10×, 78 %) | 270 (4.34×, 54 %) | 260 (4.18×, 52 %) |
| takumi-wasm | worker pool, 1 worker | — | 39.4 (1.02×, 102 %) | 41.1 (1.07×, 107 %) | 41.1 (1.07×, 107 %) | 41.0 (1.06×, 106 %) | 42.2 (1.10×, 110 %) |
| takumi-wasm | worker pool, 2 workers | — | 40.6 (1.05×, 105 %) | 81.5 (2.12×, 106 %) | 80.8 (2.10×, 105 %) | 81.9 (2.13×, 106 %) | 81.3 (2.11×, 106 %) |
| takumi-wasm | worker pool, 4 workers | — | 42.4 (1.10×, 110 %) | 82.3 (2.14×, 107 %) | 134 (3.48×, 87 %) | 134 (3.49×, 87 %) | 132 (3.43×, 86 %) |
| takumi-wasm | worker pool, 8 workers | — | 41.9 (1.09×, 109 %) | 83.0 (2.16×, 108 %) | 137 (3.55×, 89 %) | 180 (4.68×, 58 %) | 188 (4.88×, 61 %) |

Images per second; in brackets the speed-up over the same engine's sequential single-client rate (first rows) and the scaling efficiency = speed-up / min(N, threads that can render different images at once, 8 logical CPUs); a bm renderer counts as 1, K renderers as min(K, UV_THREADPOOL_SIZE), takumi-native's renderer as UV_THREADPOOL_SIZE, a worker pool as K. card-og 1200x630 PNG, closed loop: N clients each with one request in flight; 2000 ms per point after a warm-up. CPU busy during the stage: 56.8 % mean (other processes ≈ 2.14 cores). ⚠ Other processes used about 2.14 of the machine's cores on average during this stage, so these figures (scaling above all) understate what an idle machine gives; re-run on a quiet machine before quoting them.
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

`bench/native-identity.mjs`: 250 fixtures, 1810 comparisons (raw, PNG, JPEG, WebP, measure, SVG, animations, ICO, HTML, images, WOFF2, error messages, native async vs sync), 1810 identical (8 of them the same error message on both), 0 mismatches, 637 MB compared.
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
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 2 083 | 1 120 | 914 | executed (this benchmark) |
| bm wasm `core` | wasm32 | 487 | 228 | 194 |  |
| bm wasm `standard` | wasm32 | 934 | 463 | 398 |  |
| bm wasm `full` | wasm32 | 1 140 | 558 | 470 |  |
| bm wasm `WOFF add-on` | wasm32 | 84.2 | 67.7 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Native addons from `native/dist/manifest.json` (built 2026-11-12 with Zig 0.17.1, ReleaseFast). Each user downloads one addon (the optional package for their platform) plus the wasm fallback that ships in the main package.
<!-- /native-bench:sizes -->

## Event loop

<!-- native-bench:eventloop -->
| Job | Engine | API | job ms | CPU ms | max timer delay ms | p99 delay ms | timer ticks |
|:--|--:|--:|--:|--:|--:|--:|--:|
| heavy | bm-native | sync | 227 | 218 | 227 | 227 | 1 |
| heavy | bm-native | async | 235 | 469 | 1.50 | 1.00 | 236 |
| heavy | bm-wasm | sync | 455 | 688 | 455 | 455 | 1 |
| heavy | bm-wasm | async (runs on the main thread) | 473 | 750 | 473 | 473 | 1 |
| heavy | takumi-native | async | 262 | 796 | 7.30 | 2.50 | 253 |
| heavy | takumi-wasm | async (runs on the main thread) | 819 | 968 | 819 | 819 | 1 |
| anim | bm-native | sync | 476 | 484 | 476 | 476 | 1 |
| anim | bm-native | async | 544 | 1 064 | 1.20 | 1.10 | 545 |
| anim | bm-wasm | sync | 969 | 1 219 | 969 | 969 | 1 |
| anim | bm-wasm | async (runs on the main thread) | 954 | 1 094 | 954 | 954 | 1 |
| anim | takumi-native | async | 409 | 2 156 | 21.6 | 13.2 | 286 |
| anim | takumi-wasm | async (runs on the main thread) | 2 072 | 2 360 | 2 072 | 2 072 | 1 |

heavy = one 2400x2400 PNG: gradient, 24 cards with large blurred box-shadows, every third with filter: blur(6px), text; anim = renderAnimation: 60 frames (2 s at 30 fps) of 800x420 lossless WebP, 12 shadowed, blurred, rotated discs (a static scene). A 1 ms `setInterval` records the gap between its ticks while the call runs. A setImmediate chain keeps the loop from sleeping, because an idle Node loop on Windows wakes on the 15.6 ms system clock and the timer would otherwise never show less than ~16 ms. A call that blocks the loop shows one tick whose delay is the whole call. CPU ms is the whole process during the call, including the setImmediate chain on the main thread (about one core whenever the loop is free). ⚠ Other processes used about 2.95 of the machine's cores on average during this stage, so these figures (scaling above all) understate what an idle machine gives; re-run on a quiet machine before quoting them.
<!-- /native-bench:eventloop -->

## Cold start

<!-- native-bench:cold -->
| Engine | wall median | wall p95 | over Node, median | over Node, p95 | import | registerFont | first PNG |
|:--|--:|--:|--:|--:|--:|--:|--:|
| empty Node (baseline) | 68.6 | 101 | 0 | 0 | — | — | — |
| bm-native | 99.9 | 138 | 31.3 | 69.2 | 6.20 | 0.36 | 21.7 |
| bm-wasm | 168 | 207 | 99.9 | 138 | 10.1 | 3.18 | 85.0 |
| takumi-native | 120 | 166 | 50.9 | 97.5 | 28.9 | 0.98 | 22.5 |
| takumi-wasm | 306 | 373 | 238 | 304 | 42.3 | 3.97 | 188 |

ms. 30 runs per engine, engines interleaved; spawn node -> import the engine as a user does -> registerFont(Inter Regular) -> 1200x630 og card PNG -> exit; wall = parent clock spawn to exit. The import / registerFont / first-PNG columns are medians measured inside the child. CPU busy during the stage: 76.7 % mean (other processes ≈ 4.78 cores). ⚠ Other processes used about 4.78 of the machine's cores on average during this stage, so these figures (scaling above all) understate what an idle machine gives; re-run on a quiet machine before quoting them.
<!-- /native-bench:cold -->

## Memory

<!-- native-bench:memory -->
| Engine | RSS after setup | RSS after pass 1 → 10 | engine memory 1 → N | JS heap 1 → N | peak RSS, suite | peak RSS 4000×4000 PNG (growth) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 67.2 | 94.7 → 96.0 | 31.6 → 31.6 | 7.50 → 6.40 | 186 | 143 (85.8) |
| bm-wasm | 75.0 | 132 → 156 | 65.1 → 88.1 | 6.60 → 6.70 | 253 | 149 (89.3) |
| takumi-native | 70.4 | 102 → 139 | — → — | 7.70 → 6.70 | 201 | 135 (74.8) |
| takumi-wasm | 86.0 | 140 → 176 | 71.5 → 71.5 | 7.40 → 7.50 | 237 | 151 (83.6) |

MiB, after a forced GC. One process per engine; every fixture rendered to raw and PNG (async API) per pass, one renderer per font set. Engine memory: bm-native = bytes allocated by the addon (`memoryBytes()`), bm-wasm / takumi-wasm = the wasm linear memory, takumi-native = not exposed. Empty Node: 45.0 MiB RSS. "Growth" = peak RSS minus the RSS just before the 4000×4000 render.
<!-- /native-bench:memory -->

## Render time

<!-- native-bench:speed -->
| Format (fixtures) | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| raw (250) | 0.51 ±15.5 % ⚠ | 0.56 ±15.7 % ⚠ | 0.85 ±16.1 % ⚠ | 1.02 ±15.3 % ⚠ | 1.36 ±15.8 % ⚠ |
| png (250) | 1.05 ±14.6 % ⚠ | 1.06 ±16.7 % ⚠ | 1.56 ±15.0 % ⚠ | 1.89 ±14.5 % ⚠ | 3.36 ±15.8 % ⚠ |
| jpeg (3) | 13.5 ±19.9 % ⚠ | 13.2 ±17.9 % ⚠ | 21.7 ±24.1 % ⚠ | 19.5 ±15.1 % ⚠ | 28.4 ±25.3 % ⚠ |
| webp (3) | 10.1 ±21.2 % ⚠ | 9.95 ±22.0 % ⚠ | 13.9 ±26.9 % ⚠ | 73.9 ±23.4 % ⚠ | 17.8 ±24.3 % ⚠ |
| raw, without known-gaps | 0.52 | 0.57 | 0.87 | 1.04 | 1.38 |
| png, without known-gaps | 1.07 | 1.08 | 1.59 | 1.92 | 3.41 |
| raw, per pass | 0.52 / 0.64 / 0.48 | 0.56 / 0.69 / 0.51 | 0.87 / 1.07 / 0.79 | 1.03 / 1.26 / 0.94 | 1.37 / 1.71 / 1.28 |
| png, per pass | 1.07 / 1.32 / 1.01 | 1.07 / 1.36 / 1.00 | 1.57 / 1.96 / 1.49 | 1.89 / 2.33 / 1.78 | 3.37 / 4.29 / 3.23 |

Geometric mean of the per-fixture median render time, ms. jpeg (quality 85) and webp (lossless; takumi-wasm uses a different WebP encoder from takumi-native, see the format table) are timed on three fixtures only.
<!-- /native-bench:speed -->

<!-- native-bench:cpu -->
| Variant | raw: wall / CPU ms / cores | PNG: wall / CPU ms / cores |
|:--|--:|--:|
| bm-native sync | 0.53 / 0.55 / 1.05 | 1.56 / 1.42 / 0.91 |
| bm-native async | 0.60 / 1.42 / 2.35 | 1.58 / 2.32 / 1.47 |
| bm-wasm sync | 0.87 / 0.69 / 0.79 | 2.31 / 1.78 / 0.77 |
| takumi-native async | 1.02 / 1.71 / 1.67 | 2.14 / 3.81 / 1.78 |
| takumi-wasm | 1.40 / 1.10 / 0.79 | 4.77 / 4.08 / 0.86 |

Mean over every timed render of the suite (not a geomean): wall time per render, process CPU time (all threads) spent during it, and their ratio. A ratio above 1 means one render kept more than one core busy.
<!-- /native-bench:cpu -->

Where bm-native is furthest ahead of and behind takumi-native (both async):

<!-- native-bench:best-worst -->
**raw — bm-native's 10 best**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-jpeg-fit` | 1.68 | 1.67 | 13.4 | 1.43 | 0.12× |
| `pfx-bg-blend` | 0.75 | 0.89 | 5.07 | 1.04 | 0.18× |
| `pfx-bg-clip-text` | 0.43 | 0.48 | 2.28 | 0.93 | 0.21× |
| `gap-background-clip-text` | 0.34 | 0.38 | 1.62 | 1.05 | 0.23× |
| `fix-text-emoji-wrap` | 0.13 | 0.14 | 0.55 | 1.10 | 0.25× |
| `fix-text-emoji-zwj` | 0.16 | 0.17 | 0.66 | 2.21 | 0.26× |
| `fix-text-emoji-spacing` | 0.14 | 0.15 | 0.54 | 1.14 | 0.27× |
| `fix-text-emoji-keycap-vs` | 0.13 | 0.13 | 0.42 | 1.90 | 0.32× |
| `radial-spotlight-small` | 0.45 | 0.49 | 1.50 | 2.02 | 0.33× |
| `fix-text-emoji-flags-skin` | 0.12 | 0.14 | 0.42 | 1.52 | 0.33× |

**raw — bm-native's 10 worst**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `fix-text-paint-order` | 0.82 | 0.87 | 0.71 | 1.17 | 1.21× |
| `abs-zorder` | 2.09 | 1.78 | 1.51 | 1.08 | 1.18× |
| `pfx-text-stroke` | 0.77 | 0.83 | 0.73 | 1.43 | 1.14× |
| `radius-elliptical` | 1.49 | 1.53 | 1.37 | 0.82 | 1.12× |
| `pfx-svg-background` | 0.69 | 0.75 | 0.71 | 3.19 | 1.05× |
| `sizing-padding-margin` | 1.01 | 1.22 | 1.21 | 1.72 | 1.01× |
| `sizing-aspect-ratio` | 0.95 | 1.08 | 1.09 | 2.73 | 1.00× |
| `radius-pill-circle` | 1.57 | 1.77 | 1.84 | 1.07 | 0.96× |
| `borders-with-radius` | 0.77 | 0.87 | 0.92 | 0.87 | 0.95× |
| `flex-row-column` | 1.11 | 1.16 | 1.23 | 1.77 | 0.94× |

**png — bm-native's 10 best**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `colors-solid-bg` | 0.25 | 0.28 | 1.22 | 2.54 | 0.23× |
| `gap-oklch-color` | 0.22 | 0.22 | 0.88 | 1.27 | 0.25× |
| `anim-opacity-t250` | 0.23 | 0.22 | 0.78 | 2.33 | 0.28× |
| `pfx-visibility` | 0.30 | 0.32 | 1.12 | 1.36 | 0.29× |
| `anim-kf-option-t500` | 0.20 | 0.20 | 0.69 | 1.75 | 0.30× |
| `anim-alternate-t700` | 0.19 | 0.19 | 0.64 | 1.11 | 0.30× |
| `anim-opacity-t1500` | 0.19 | 0.17 | 0.57 | 0.88 | 0.30× |
| `anim-alternate-t1100` | 0.19 | 0.20 | 0.62 | 2.39 | 0.32× |
| `anim-two-anims-t400` | 0.25 | 0.24 | 0.76 | 1.13 | 0.32× |
| `anim-opacity-t900` | 0.22 | 0.21 | 0.66 | 1.52 | 0.32× |

**png — bm-native's 10 worst**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | takumi cores | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-photo-bg` | 30.8 | 30.5 | 13.4 | 3.52 | 2.28× |
| `card-blog` | 20.0 | 20.1 | 12.5 | 2.50 | 1.61× |
| `img-intrinsic-size` | 2.06 | 2.54 | 1.69 | 2.96 | 1.50× |
| `img-radius-clip` | 17.4 | 17.6 | 12.0 | 2.02 | 1.46× |
| `radial-spotlight-small` | 4.37 | 4.51 | 3.17 | 2.57 | 1.42× |
| `fx-text-shadow` | 2.67 | 2.76 | 2.07 | 4.04 | 1.33× |
| `pfx-mix-blend` | 2.91 | 3.06 | 2.31 | 1.30 | 1.33× |
| `stress-3000x2000-card` | 57.9 | 56.5 | 45.1 | 1.80 | 1.25× |
| `img-png-fit` | 11.8 | 12.1 | 9.63 | 1.79 | 1.25× |
| `fix-css-image-rendering-modes` | 5.25 | 5.46 | 4.41 | 3.18 | 1.24× |
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
| 300×200 raw | 0.13 | 0.14 | 0.22 | 0.28 | 0.41 |
| 300×200 png | 0.22 | 0.15 | 0.19 | 0.47 | 0.56 |
| 1200×630 raw | 0.73 | 0.77 | 1.14 | 0.92 | 1.18 |
| 1200×630 png | 1.08 | 0.72 | 1.30 | 3.14 | 5.17 |
| 2400×1260 raw | 2.60 | 2.98 | 5.16 | 2.96 | 5.88 |
| 2400×1260 png | 4.84 | 4.96 | 6.11 | 11.0 | 20.4 |

| Animation scene, one 800×420 raw frame | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| shadow + blur (as animated) | 7.16 | 7.19 | 14.3 | 17.9 | 32.3 |
| shadow only | 2.17 | 2.24 | 4.37 | 5.08 | 8.11 |
| blur only | 2.22 | 2.30 | 4.01 | 3.78 | 6.60 |
| neither | 0.97 | 1.00 | 1.59 | 1.38 | 2.16 |

Median ms, variants interleaved (40 iterations for the empty frames, fewer for the scene). An empty frame draws nothing, so its time is the per-pixel cost every frame pays (canvas clear, alpha conversion, copying the result out) plus, for PNG, encoding a flat image. The scene is the one of the event-loop animation: 12 rotated 60×60 discs with `box-shadow: 0 8px 30px` and `filter: blur(2px)`.
<!-- /native-bench:diagnose -->

### Formats and encoders

<!-- native-bench:formats -->
| Fixture | Format | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|--:|
| `lingrad-angles` | raw | 2.64 ms · 2 953 KiB | 3.02 ms · 2 953 KiB | 4.85 ms · 2 953 KiB | 4.97 ms · 2 953 KiB | 7.18 ms · 2 953 KiB |
| `lingrad-angles` | png | 7.68 ms · 32.6 KiB | 7.28 ms · 32.6 KiB | 11.6 ms · 32.6 KiB | 9.17 ms · 102 KiB | 39.1 ms · 102 KiB |
| `lingrad-angles` | jpeg | 12.4 ms · 52.2 KiB | 13.3 ms · 52.2 KiB | 23.8 ms · 52.2 KiB | 20.4 ms · 52.3 KiB | 27.4 ms · 52.3 KiB |
| `lingrad-angles` | webp | 9.23 ms · 28.9 KiB | 8.91 ms · 28.9 KiB | 12.1 ms · 28.9 KiB | 126 ms · 22.8 KiB | 17.2 ms · 169 KiB |
| `img-photo-bg` | raw | 1.34 ms · 2 953 KiB | 1.39 ms · 2 953 KiB | 2.06 ms · 2 953 KiB | 4.01 ms · 2 953 KiB | 6.67 ms · 2 953 KiB |
| `img-photo-bg` | png | 30.8 ms · 511 KiB | 30.5 ms · 511 KiB | 46.3 ms · 511 KiB | 13.4 ms · 513 KiB | 58.8 ms · 513 KiB |
| `img-photo-bg` | jpeg | 16.4 ms · 55.1 KiB | 14.0 ms · 55.1 KiB | 21.3 ms · 55.1 KiB | 20.3 ms · 55.2 KiB | 31.7 ms · 55.2 KiB |
| `img-photo-bg` | webp | 15.9 ms · 367 KiB | 14.7 ms · 367 KiB | 20.7 ms · 367 KiB | 183 ms · 414 KiB | 25.0 ms · 470 KiB |
| `card-flat-ui` | raw | 2.92 ms · 2 953 KiB | 3.14 ms · 2 953 KiB | 5.63 ms · 2 953 KiB | 3.95 ms · 2 953 KiB | 7.41 ms · 2 953 KiB |
| `card-flat-ui` | png | 5.69 ms · 23.1 KiB | 5.78 ms · 23.1 KiB | 8.90 ms · 23.1 KiB | 7.25 ms · 25.3 KiB | 20.8 ms · 25.3 KiB |
| `card-flat-ui` | jpeg | 12.2 ms · 48.9 KiB | 12.4 ms · 48.9 KiB | 20.2 ms · 48.9 KiB | 17.9 ms · 49.0 KiB | 26.4 ms · 49.0 KiB |
| `card-flat-ui` | webp | 6.96 ms · 18.5 KiB | 7.51 ms · 18.5 KiB | 10.7 ms · 18.5 KiB | 17.5 ms · 13.4 KiB | 13.2 ms · 27.6 KiB |

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
| bm-engine | 0.1.0, git `ef21c5674b` (integ, 4 modified tracked files) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 2 083 KiB, Zig 0.17.1, ReleaseFast, sha256 `ec92d1feb24f` |
| bm-wasm | `js/bm_engine.wasm` (full profile), 1 140 KiB, sha256 `7a7e363d2c98` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Run | 2026-11-12 11:03 UTC, full mode, 250 fixtures, 16.6 min; CPU busy before the run: 53.5 % |
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
