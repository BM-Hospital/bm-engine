// Examples for docs/{en,vi}/performance.md. Regions are copied into the pages by sync-docs.mjs.
// Timings printed here are for checking the examples only; the docs quote docs/en/benchmark.md instead.
import { saver } from "./_lib.mjs";
const save = saver("performance");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

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
// #endregion
save("card", renderCard("Reuse one renderer", "fonts are parsed once, glyphs stay cached"));

// #region timing
const t0 = performance.now();
renderCard("First render", "pays for glyph rasterisation");
const t1 = performance.now();
for (let i = 0; i < 20; i++) renderCard("First render", "pays for glyph rasterisation");
const t2 = performance.now();
console.log(`first: ${(t1 - t0).toFixed(1)} ms, then: ${((t2 - t1) / 20).toFixed(1)} ms per render`);
// #endregion

// #region raw-vs-png
const node = { type: "container", style: { width: "100%", height: "100%", backgroundImage: "radial-gradient(circle, #fde68a, #f97316)" } };
const rawPixels = renderer.renderSync(node, { width: 600, height: 315, format: "raw" }); // no encoding step
const pngFile = renderer.renderSync(node, { width: 600, height: 315 });                  // + PNG compression
console.log(rawPixels.length, pngFile.length); // 756000 (600 * 315 * 4) vs 21334 bytes for this gradient
// #endregion
console.log("raw/png", rawPixels.length, pngFile.length);

// #region images
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
// #endregion
save("images", second);

// #region memory
console.log(renderer.memoryBytes());     // wasm linear memory of this entry, in bytes
renderer.renderSync(node, { width: 3000, height: 2000, format: "raw" });
console.log(renderer.memoryBytes());     // grew for the big canvas ...
renderCard("Back to normal", "small canvas");
console.log(renderer.memoryBytes());     // ... and stays that size: wasm memory never shrinks
// #endregion

// #region free
{
  using temp = new Renderer();           // explicit resource management: temp.free() at the end of the block
  temp.registerFont(readFileSync("assets/fonts/Roboto-Regular.ttf"));
  temp.renderSync({ type: "text", text: "one-off", style: { fontFamily: "Roboto" } }, { width: 100, height: 30 });
}
const other = new Renderer();
other.free();                            // same thing by hand; methods throw "renderer has been freed" afterwards
// #endregion

// #region prepare
// Resolve async inputs (lazy images, font loaders) once, render many variants from the handle.
const prepared = await renderer.prepare(withPhoto("Prepared"), {
  width: 600, height: 315,
  images: [{ src: "hero", data: async () => photo }], // e.g. () => fetch(url).then((r) => r.arrayBuffer())
});
const asPng = renderer.renderSync(prepared);
const asJpeg = renderer.renderSync(prepared, { format: "jpeg", quality: 80 });
console.log(asPng.length, asJpeg.length);
// #endregion

// #region pool
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
// #endregion
save("pool-card", cards[7]);

// #region features
import { features } from "bm-engine";

// Fail fast at startup if the loaded profile cannot render your templates.
for (const need of ["css", "tw", "html"]) {
  if (!features[need]) throw new Error(`bm-engine profile lacks "${need}": import bm-engine/standard or /full`);
}
// #endregion
