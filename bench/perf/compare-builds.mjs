// Renders every fixture with two wasm builds and reports output differences (raw pixels) and PNG size totals.
//   node bench/perf/compare-builds.mjs <old bm_engine.wasm> [<new bm_engine.wasm>]     (new: js/bm_engine.wasm)
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ROOT_DIR } from "../lib/assets.mjs";
import { fontsFor } from "../lib/fonts.mjs";
import { ALL_CASES } from "../fixtures/index.mjs";
import { renderOpts } from "../lib/pipeline.mjs";

const [oldFile, newFile = path.join(ROOT_DIR, "js", "bm_engine.wasm")] = process.argv.slice(2);
const { createBinding } = await import(pathToFileURL(path.join(ROOT_DIR, "js", "engine.mjs")).href);
const mk = (f) => { const b = createBinding(); b.initSync(readFileSync(f)); return b; };
const A = mk(oldFile), B = mk(newFile);
const fonts = new Map();
const rOf = (b, k) => { const r = new b.Renderer(); for (const f of fontsFor(k.fonts)) { if (!fonts.has(f.path)) fonts.set(f.path, new Uint8Array(readFileSync(f.path))); r.registerFont({ name: f.name, data: fonts.get(f.path), weight: f.weight, style: f.style }); } return r; };
let diffRaw = 0, diffPng = 0, pngA = 0, pngB = 0, n = 0;
const eq = (x, y) => x.length === y.length && Buffer.compare(Buffer.from(x.buffer, x.byteOffset, x.byteLength), Buffer.from(y.buffer, y.byteOffset, y.byteLength)) === 0;
for (const k of ALL_CASES) {
  const ra = rOf(A, k), rb = rOf(B, k);
  let a, b, pa, pb;
  try { a = ra.renderSync(k.node, renderOpts(k, "raw")); b = rb.renderSync(k.node, renderOpts(k, "raw")); pa = ra.renderSync(k.node, renderOpts(k, "png")); pb = rb.renderSync(k.node, renderOpts(k, "png")); } catch (e) { console.log(k.id, "error", e.message); continue; }
  n++;
  if (!eq(a, b)) { diffRaw++; let d = 0, mx = 0; for (let i = 0; i < Math.min(a.length, b.length); i++) if (a[i] !== b[i]) { d++; mx = Math.max(mx, Math.abs(a[i] - b[i])); } console.log(`RAW DIFFERS ${k.id}: ${d} bytes, max channel difference ${mx}${a.length !== b.length ? ", sizes differ" : ""}`); }
  if (!eq(pa, pb)) diffPng++;
  pngA += pa.length; pngB += pb.length;
  ra.free(); rb.free();
}
console.log(`${n} fixtures: raw output differs on ${diffRaw}; PNG files differ on ${diffPng}; PNG bytes total ${pngA} -> ${pngB} (${((pngB / pngA - 1) * 100).toFixed(3)} %)`);
