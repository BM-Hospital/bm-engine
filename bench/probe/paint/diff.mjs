// BM_WASM=<wasm> node probe/paint/diff.mjs <case-id> [threshold=1] [max=12] [--extra=<fixture file>]
// Renders one fixture with takumi and bm and lists the first differing pixels (+ histogram of |diff|).
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import * as bm from "../../../js/index.mjs";
import { ALL_CASES } from "../../fixtures/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import tk from "../../engines/takumi-wasm.mjs";
const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const extra = process.argv.find((a) => a.startsWith("--extra="))?.slice(8);
let cases = ALL_CASES;
if (extra) cases = cases.concat((await import(pathToFileURL(path.resolve(extra)).href)).default);
const k = cases.find((c) => c.id === args[0]);
const thr = +(args[1] || 1), max = +(args[2] || 12);
bm.initSync(readFileSync(process.env.BM_WASM || new URL("../../../zig-out/bin/bm_render.wasm", import.meta.url)));
const r = new bm.Renderer();
for (const f of fontsFor(k.fonts)) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
const t = await tk.create({ fonts: fontsFor(k.fonts) });
const o = { width: k.width, height: k.height, format: "raw", devicePixelRatio: 1 }; if (k.images) o.images = k.images;
const A = new Uint8Array(await t.render(k.node, o)), B = new Uint8Array(r.renderSync(k.node, o));
let n = 0, total = 0; const hist = {};
let bx0 = 1e9, by0 = 1e9, bx1 = -1, by1 = -1;
for (let y = 0; y < k.height; y++) for (let x = 0; x < k.width; x++) {
  const i = (y * k.width + x) * 4; let d = 0; for (let c = 0; c < 4; c++) d = Math.max(d, Math.abs(A[i + c] - B[i + c]));
  if (d > 0) { total++; hist[d] = (hist[d] || 0) + 1; bx0 = Math.min(bx0, x); by0 = Math.min(by0, y); bx1 = Math.max(bx1, x); by1 = Math.max(by1, y); }
  if (d >= thr && n < max) { n++; console.log(x, y, "takumi", [...A.subarray(i, i + 4)].join(","), "bm", [...B.subarray(i, i + 4)].join(",")); }
}
console.log("differing px", total, "bbox", bx0, by0, bx1, by1, "hist", JSON.stringify(hist));
