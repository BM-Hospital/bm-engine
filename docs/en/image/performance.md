# Performance

[English](performance.md) · [Tiếng Việt](../../vi/image/performance.md)

bm-render is fast by default — a typical card renders in a few milliseconds — but a few habits decide
whether a server spends its time rendering or re-parsing fonts, decoding the same photo, and growing
memory it can never give back. This page collects them: reuse one renderer, register fonts once,
understand cold start, pick the smallest profile, use raw output when you post-process, let the image
cache work, keep memory flat, and spread work over worker threads. Numbers come from the project's
benchmark ([summary](../benchmark.md), [full report](../../BENCHMARK.md)); the code is
`docs/examples/performance.mjs` and runs as shown.

## Create the renderer once

A `Renderer` owns the registered fonts, a glyph cache and a decoded-image cache. Creating one is cheap;
**registering fonts is not** (the bytes are copied into wasm memory and parsed), and the caches are
what make the second render faster than the first. Create the renderer at module load, register fonts
once, and reuse it for every request:

<!-- @example performance#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render";

// Create the renderer and register fonts ONCE, at module load, and reuse them for every request.
const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

export function renderCard(title, subtitle) {
  return renderer.renderSync(
    {
      type: "container",
      style: { display: "flex", flexDirection: "column", justifyContent: "flex-end", gap: 8, width: "100%", height: "100%",
               padding: 40, fontFamily: "Inter", backgroundImage: "linear-gradient(160deg, #0f172a, #1e3a8a)" },
      children: [
        { type: "text", text: title, style: { fontSize: 44, fontWeight: 700, color: "white", lineClamp: 2 } },
        { type: "text", text: subtitle, style: { fontSize: 22, color: "#93c5fd" } },
      ],
    },
    { width: 600, height: 315 },
  );
}
```

![A card rendered by the shared renderer](/img/guide/performance-card.png)

::: warning Do not create a renderer per request
Every renderer keeps its own copy of its fonts and its own caches, and wasm memory never shrinks.
A renderer per request multiplies font parsing and memory; if you really need a temporary one, free it
(see [Memory](#memory)).
:::

## Cold start

On Node.js the `bm-render` entries read and instantiate their binary synchronously **on import**, so
the first `new Renderer()` can follow immediately. Cold start is the sum of instantiating the module,
registering fonts and the first render (which also fills the glyph cache) — 78.1 ms in total for the
og-card fixture in the benchmark.

- In serverless functions, do the import, `new Renderer()` and `registerFont` at **module scope**, not
  inside the handler, so warm invocations skip them.
- Register only the font files you use. Every face costs its file size in wasm memory and parsing time;
  a variable font replaces several static weights.
- Edge runtimes (Cloudflare Workers) get a precompiled `WebAssembly.Module`; call `initSync(module)` at
  module scope and create the renderer lazily (see [Getting started](../getting-started.md#edge-runtimes-deno-bun)).

## Warm renders

The first render with a given font and size rasterises glyphs; later renders reuse them from the glyph
cache (8 MiB per renderer). To see the difference on your machine:

<!-- @example performance#timing -->
```js
const t0 = performance.now();
renderCard("First render", "pays for glyph rasterisation");
const t1 = performance.now();
for (let i = 0; i < 20; i++) renderCard("First render", "pays for glyph rasterisation");
const t2 = performance.now();
console.log(`first: ${(t1 - t0).toFixed(1)} ms, then: ${((t2 - t1) / 20).toFixed(1)} ms per render`);
```

The output depends on the machine, so it is not quoted here; expect the first render to be the slowest
and the following ones to settle.

## Choose the smallest profile

The three binaries differ in download size and in what they can do, not in speed for the features they
share:

| Profile | wasm raw / brotli | Use it for |
|:--|--:|:--|
| `bm-render/core` | 489.6 / 195.3 KiB | node trees with inline styles, static TTF, PNG / JPEG images |
| `bm-render/standard` | 936.5 / 398.6 KiB | + stylesheets, Tailwind, HTML, SVG, WOFF2, variable / CFF fonts, effects, tables, floats |
| `bm-render/full` (and `bm-render` on Node) | 1 143.6 / 470.8 KiB | + bidi / complex scripts, colour emoji, animation, `renderSvg`, ICO, lossy WebP input |

Size matters in browsers and on edge runtimes with a script-size limit; on a Node server the difference
is a few hundred KiB read once at startup. Check the loaded profile at startup instead of discovering a
missing feature on the first request:

<!-- @example performance#features -->
```js
import { features } from "bm-render";

// Fail fast at startup if the loaded profile cannot render your templates.
for (const need of ["css", "tw", "html"]) {
  if (!features[need]) throw new Error(`bm-render profile lacks "${need}": import bm-render/standard or /full`);
}
```

Details in [Profiles and size](../profiles-and-size.md).

## Raw or encoded output

Encoding is a large part of a render: in the benchmark the geometric mean is 0.64 ms for `raw` and
1.33 ms for PNG. If you are going to process the pixels anyway (compare images, composite them, hand
them to a `<canvas>` or a video encoder), ask for `raw` and skip the encoder:

<!-- @example performance#raw-vs-png -->
```js
const node = { type: "container", style: { width: "100%", height: "100%", backgroundImage: "radial-gradient(circle, #fde68a, #f97316)" } };
const rawPixels = renderer.renderSync(node, { width: 600, height: 315, format: "raw" }); // no encoding step
const pngFile = renderer.renderSync(node, { width: 600, height: 315 });                  // + PNG compression
console.log(rawPixels.length, pngFile.length); // 756000 (600 * 315 * 4) vs 21334 bytes for this gradient
```

Raw buffers are big (`width × height × 4` bytes), so do not send them over the network or keep many in
memory. For the trade-offs between PNG, JPEG and WebP see [Output formats](./formats.md).

## Images

- **Decoding is cached.** Each renderer caches decoded (and resized) images by content, up to 96 MiB;
  the cache is cleared when it grows beyond that. The same logo or background in every card is decoded
  once.
- **Bytes are copied per render.** The encoded bytes of every `images` entry the source references are
  copied into wasm memory on each call (entries the source does not mention are skipped), so huge source
  files cost a copy every time even when the decode is cached.
- **Size your images.** A decoded image may have at most 24 megapixels (larger ones are not drawn), and
  decoding a 12-megapixel camera photo to show it at 600 × 315 wastes time and up to 48 MB of cache.
  Resize big photos once, before they reach the renderer.

<!-- @example performance#images -->
```js
// Decoded images are cached per renderer by content, so the same logo / photo is decoded once.
// The bytes themselves are copied into wasm memory on every render that references them.
const photo = renderer.renderSync(
  { type: "container", style: { width: "100%", height: "100%", backgroundImage: "conic-gradient(from 45deg, #22d3ee, #a855f7, #f43f5e, #22d3ee)" } },
  { width: 1600, height: 1000 },
); // stands in for a large photo
const withPhoto = (title) => ({
  type: "container",
  style: { display: "flex", alignItems: "flex-end", width: "100%", height: "100%", padding: 32,
           backgroundImage: "url(hero)", backgroundSize: "cover" },
  children: [{ type: "text", text: title, style: { fontFamily: "Inter", fontWeight: 700, fontSize: 40, color: "white" } }],
});
const images = [{ src: "hero", data: photo }];

let start = performance.now();
renderer.renderSync(withPhoto("first"), { width: 600, height: 315, images });   // decodes and resizes the PNG
const firstMs = performance.now() - start;
start = performance.now();
const second = renderer.renderSync(withPhoto("second"), { width: 600, height: 315, images }); // cache hit
console.log(`first ${firstMs.toFixed(1)} ms, second ${(performance.now() - start).toFixed(1)} ms`);
```

![Card with a cached background image](/img/guide/performance-images.png)

The second render does not decode the 1600 × 1000 PNG again; on the test machine it was several times
faster than the first (your numbers will differ).

### Resolve async inputs once with `prepare`

When image bytes or fonts arrive asynchronously, `prepare()` resolves them once and returns a handle
that any number of renders can reuse, each with its own options:

<!-- @example performance#prepare -->
```js
// Resolve async inputs (lazy images, font loaders) once, render many variants from the handle.
const prepared = await renderer.prepare(withPhoto("Prepared"), {
  width: 600, height: 315,
  images: [{ src: "hero", data: async () => photo }], // e.g. () => fetch(url).then((r) => r.arrayBuffer())
});
const asPng = renderer.renderSync(prepared);
const asJpeg = renderer.renderSync(prepared, { format: "jpeg", quality: 80 });
console.log(asPng.length, asJpeg.length);
```

`prepare` never downloads anything; fetch the bytes yourself (see [Images](./images.md)).

## Memory

All renderers of one entry share one WebAssembly linear memory, and **WebAssembly memory can grow but
never shrink**. bm-render reuses memory between renders (a per-render arena, fixed-budget caches), so a
steady workload plateaus: 11.6 MiB of wasm memory after 50 og-card renders in the benchmark. What makes it grow is the largest thing you ever rendered:

<!-- @example performance#memory -->
```js
console.log(renderer.memoryBytes());     // wasm linear memory of this entry, in bytes
renderer.renderSync(node, { width: 3000, height: 2000, format: "raw" });
console.log(renderer.memoryBytes());     // grew for the big canvas ...
renderCard("Back to normal", "small canvas");
console.log(renderer.memoryBytes());     // ... and stays that size: wasm memory never shrinks
```

In the phase-1 benchmark the instance ended the whole run, which includes a 3000 × 2000 canvas, at
65.8 MiB. Rules of thumb:

- One canvas is `width × height × 4` bytes, plus layers for effects such as opacity groups, filters and
  masks. A 3000 × 2000 canvas is 24 MB before any layer.
- Keep occasional giant renders out of the instance that serves everyday traffic — run them in a separate
  worker, which you can terminate to get the memory back.
- Fixed budgets per renderer: decoded images up to 96 MiB, glyph masks up to 8 MiB. The constructor
  options `cacheMaxBytes` / `fontCacheMaxBytes` are accepted accepted for API compatibility; ignored and ignored.
- `renderer.memoryBytes()` (or `Renderer.memoryBytes()`) reports the current size; log it if you
  suspect growth.

Freeing a renderer returns its fonts and caches to the wasm allocator, where later work reuses them —
the linear memory itself stays the same size:

<!-- @example performance#free -->
```js
{
  using temp = new Renderer();           // explicit resource management: temp.free() at the end of the block
  temp.registerFont(readFileSync("assets/fonts/Roboto-Regular.ttf"));
  temp.renderSync({ type: "text", text: "one-off", style: { fontFamily: "Roboto" } }, { width: 100, height: 30 });
}
const other = new Renderer();
other.free();                            // same thing by hand; methods throw "renderer has been freed" afterwards
```

## Big canvases and high DPI

Cost grows with the number of output pixels: rasterising, compositing and encoding all touch every
pixel. A 2× render (`devicePixelRatio: 2` with a doubled canvas) has four times the pixels of a 1×
render. Limits: 16 384 px per side and 40 megapixels per canvas (`canvas too large`).

- Render at the size you will display; let the browser scale down only when you need crisp 2× output.
- Large blurs (`filter: blur()`, big `box-shadow` blur radii, `backdrop-filter`) and many stacked
  opacity / blend layers are the expensive effects; flat colours, borders and text are cheap.
- For thumbnails, render small directly rather than rendering big and downscaling.

## Concurrency: worker pools

::: tip Native backend on Node.js
With the native backend (used by `import "bm-render"` on Node.js when the addon for the platform is
installed), the async methods (`render()`, `measure()`, ...) run on the libuv thread pool and do not block
the event loop. Parallelism there comes from several `Renderer` instances (one call at a time each) and
the size of that pool, `UV_THREADPOOL_SIZE`, rather than from worker threads. See
[Native vs WebAssembly → Threading model](../native-vs-wasm.md) for the details and the
measured throughput. The rest of this section applies to the wasm backend.
:::

The engine is single-threaded and `render` is synchronous: one render blocks the thread that calls it.
The async methods (`render()`, `measure()`, ...) only exist for API compatibility and for resolving
async options — they do not move work off the thread. To use several cores, run one bm-render instance
per worker thread. Each worker imports bm-render (getting its own wasm instance and memory) and
registers its own fonts:

<!-- @example _performance-worker#worker -->
```js
// render-worker.mjs: one wasm instance + one renderer per worker, fonts registered once.
import { parentPort } from "node:worker_threads";
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

parentPort.on("message", ({ id, node, options }) => {
  try {
    const bytes = renderer.renderSync(node, options);
    parentPort.postMessage({ id, bytes }, [bytes.buffer]); // transfer, do not copy
  } catch (err) {
    parentPort.postMessage({ id, error: err.message });
  }
});
```

The main thread hands out jobs and gets the encoded bytes back (transferred, not copied):

<!-- @example performance#pool -->
```js
import { Worker } from "node:worker_threads";
import { availableParallelism } from "node:os";

class RenderPool {
  #idle = [];
  #queue = [];
  #jobs = new Map();
  #nextId = 0;
  constructor(size) {
    for (let i = 0; i < size; i++) {
      const worker = new Worker(new URL("./_performance-worker.mjs", import.meta.url));
      worker.on("message", ({ id, bytes, error }) => {
        const job = this.#jobs.get(id);
        this.#jobs.delete(id);
        error ? job.reject(new Error(error)) : job.resolve(bytes);
        this.#idle.push(worker);
        this.#pump();
      });
      this.#idle.push(worker);
    }
  }
  render(node, options) {
    return new Promise((resolve, reject) => {
      const id = this.#nextId++;
      this.#jobs.set(id, { resolve, reject });
      this.#queue.push({ id, node, options });
      this.#pump();
    });
  }
  #pump() {
    while (this.#idle.length && this.#queue.length) this.#idle.pop().postMessage(this.#queue.shift());
  }
  close() {
    return Promise.all(this.#idle.map((w) => w.terminate()));
  }
}

const pool = new RenderPool(Math.min(4, availableParallelism()));
const cards = await Promise.all(
  ["one", "two", "three", "four", "five", "six", "seven", "eight"].map((n) =>
    pool.render(
      { type: "container",
        style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#0f766e" },
        children: [{ type: "text", text: `Card ${n}`, style: { fontFamily: "Inter", fontSize: 32, color: "white" } }] },
      { width: 300, height: 120 },
    ),
  ),
);
console.log(cards.length, "PNGs rendered on", Math.min(4, availableParallelism()), "threads");
await pool.close();
```

![One of the eight cards rendered by the pool](/img/guide/performance-pool-card.png)

- Size the pool by cores (`availableParallelism()`), not by request count; each worker costs its own
  wasm memory plus fonts.
- Renderers, `Prepared` handles and font registrations cannot be shared between workers; send node
  trees (plain data) in and bytes out.
- In browsers the same pattern works with Web Workers: render off the main thread so the page stays
  responsive. This was not run here; the Node version above was.

## Browser tips

- **Serve `.wasm` as `application/wasm`** so `init()` can use streaming compilation
  (`WebAssembly.instantiateStreaming`); with another content type it falls back to downloading the whole
  file first, which still works. In the benchmark's headless Edge run, streaming compile + instantiate
  took 20.4 ms.
- **Cache the binary.** The file names do not change between releases of the same version, so serve
  them with long-lived caching tied to the package version (or let your bundler fingerprint them).
- **Load the smallest profile** that covers your templates — the download is 180 KiB (core) to 454 KiB
  (full) with brotli.
- **Initialise early** (`await init()` when the app starts, not on the first click) and keep one
  renderer for the page's lifetime.
- **Render in a Web Worker** if renders happen while the user interacts with the page.

See [Getting started](index.md#browser-without-a-bundler) for loading the binary in browsers
and bundlers.

## Checklist

- [ ] One long-lived `Renderer` per font set; fonts registered once, at startup.
- [ ] The smallest profile that covers your inputs; `features` checked at startup.
- [ ] `raw` when you post-process pixels; JPEG / WebP / PNG chosen per content.
- [ ] Images resized before rendering; the same bytes reused so the decode cache hits.
- [ ] No per-request renderers; giant canvases isolated in their own worker.
- [ ] A worker pool sized by CPU cores when you need throughput.
