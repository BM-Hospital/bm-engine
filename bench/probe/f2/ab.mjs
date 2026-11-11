// A/B of two bm builds against takumi for one fixture: how many pixels moved closer to / farther from the oracle.
// Usage (from bench/): node probe/f2/ab.mjs <case-id> <wasm A> <wasm B> [--extra=<fixture file>] [--list]
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ALL_CASES } from "../../fixtures/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import tk from "../../engines/takumi-wasm.mjs";
const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const extra = process.argv.find((a) => a.startsWith("--extra="))?.slice(8);
let cases = ALL_CASES;
if (extra) cases = cases.concat((await import(pathToFileURL(path.resolve(extra)).href)).default);
const k = cases.find((c) => c.id === args[0]);
const o = { width: k.width, height: k.height, format: "raw", devicePixelRatio: 1 }; if (k.images) o.images = k.images;
const t = await tk.create({ fonts: fontsFor(k.fonts) });
const T = new Uint8Array(await t.render(k.node, o));
async function bmRender(wasm) {
  // a fresh module instance per build (the JS glue keeps one wasm per module instance)
  const m = await import(pathToFileURL(path.resolve("../js/index.mjs")).href + "?" + encodeURIComponent(wasm));
  m.initSync(readFileSync(wasm));
  const r = new m.Renderer();
  for (const f of fontsFor(k.fonts)) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
  return new Uint8Array(r.renderSync(k.node, o));
}
const A = await bmRender(args[1]), B = await bmRender(args[2]);
let closer = 0, farther = 0, same = 0, changed = 0, sa = 0, sb = 0;
for (let i = 0; i < T.length; i += 4) {
  let da = 0, db = 0, ch = false;
  for (let c = 0; c < 4; c++) { da += Math.abs(T[i + c] - A[i + c]); db += Math.abs(T[i + c] - B[i + c]); if (A[i + c] !== B[i + c]) ch = true; }
  sa += da; sb += db;
  if (!ch) { same++; continue; }
  changed++;
  if (db < da) closer++; else if (db > da) farther++;
  if (process.argv.includes("--list") && db > da) console.log((i / 4) % k.width, Math.floor(i / 4 / k.width), "tk", [...T.subarray(i, i + 4)].join(","), "A", [...A.subarray(i, i + 4)].join(","), "B", [...B.subarray(i, i + 4)].join(","));
}
console.log(k.id, "changed px", changed, "closer to takumi", closer, "farther", farther, "sum|diff| A", sa, "B", sb);
