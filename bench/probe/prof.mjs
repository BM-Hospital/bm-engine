import { readFileSync } from "node:fs";
import * as bm from "../../js/index.mjs";
import { ALL_CASES } from "../fixtures/index.mjs";
import { fontsFor } from "../lib/fonts.mjs";
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer();
for (const f of fontsFor()) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
const c = ALL_CASES.find((k) => k.id === process.argv[2]);
const fmt = process.argv[3] || "raw";
const o = { width: c.width, height: c.height, images: c.images, format: fmt };
const t0 = performance.now(); let n = 0;
while (performance.now() - t0 < 3000) { r.renderSync(c.node, o); n++; }
console.log(c.id, fmt, ((performance.now() - t0) / n).toFixed(3), "ms");
