// Cold-start probe, one fresh process per run (spawned by bench/run-native.mjs).
//
//   node native/cold-child.mjs <engine|none> <card.json> <font.ttf>
//
// The card JSON and the font bytes are read before the clock starts (for "none" too, so the empty-Node
// baseline does the same file reads). Then: import the engine the way a user does -> register one font ->
// render the 1200x630 og card to PNG -> print one JSON line -> exit. The parent times spawn-to-exit.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const [engine, cardPath, fontPath] = process.argv.slice(2);
const card = JSON.parse(readFileSync(cardPath, "utf8"));
if (card.images?.length) card.options.images = card.images.map((i) => ({ ...i, data: new Uint8Array(Buffer.from(i.data, "base64")) }));
const font = new Uint8Array(readFileSync(fontPath));
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const t0 = performance.now();
let backend = engine, out = { length: 0 }, t1 = t0, t2 = t0;
if (engine !== "none") {
  let r;
  if (engine === "bm-native" || engine === "bm-wasm") {
    // what `import "bm-engine"` resolves to on Node (js/node.mjs); the wasm run sets BM_ENGINE_BACKEND=wasm
    const m = await import(pathToFileURL(path.join(ROOT, "js", "node.mjs")).href);
    backend = "bm-" + m.backend;
    r = new m.Renderer();
  } else if (engine === "takumi-native") {
    const m = await import("@takumi-rs/core");
    r = new m.Renderer();
  } else if (engine === "takumi-wasm") {
    const dir = path.join(ROOT, "bench", "node_modules", "@takumi-rs", "wasm");
    const m = await import(pathToFileURL(path.join(dir, "dist", "export.mjs")).href);
    m.initSync({ module: readFileSync(path.join(dir, "pkg", "takumi_wasm_bg.wasm")) });
    r = new m.Renderer();
  } else throw new Error("unknown engine " + engine);
  t1 = performance.now();
  await r.registerFont({ name: "Inter", data: font, weight: 400, style: "normal" });
  t2 = performance.now();
  out = await r.render(card.node, card.options);
}
const t3 = performance.now();
const c = process.cpuUsage();
console.log(JSON.stringify({ backend, importMs: t1 - t0, fontMs: t2 - t1, renderMs: t3 - t2, totalMs: t3 - t0, sinceProcessStartMs: t3, bytes: out.length, cpuMs: (c.user + c.system) / 1000 }));
process.exit(0);
