// A/B pixel check between two bm builds over every fixture (or argv[2] filter): lists cases whose output differs.
// Usage (from bench/): node probe/layout2/ab.mjs <a.wasm> <b.wasm> [filter]
import { readFileSync } from "node:fs";
import { ALL_CASES } from "../../fixtures/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
const mk = async (p, i) => {
  const bm = await import("../../../js/index.mjs?ab=" + i);
  bm.initSync(readFileSync(p));
  const r = new bm.Renderer();
  for (const f of fontsFor()) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
  return r;
};
const A = await mk(process.argv[2], 1), B = await mk(process.argv[3], 2);
const re = new RegExp(process.argv[4] || ".");
let same = 0;
for (const k of ALL_CASES.filter((c) => re.test(c.id))) {
  const o = { width: k.width, height: k.height, format: "raw", ...(k.images ? { images: k.images } : {}), ...(k.opts || {}) };
  let a, b;
  try { a = A.renderSync(k.node, o); } catch (e) { a = "ERR " + e.message; }
  try { b = B.renderSync(k.node, o); } catch (e) { b = "ERR " + e.message; }
  if (typeof a === "string" || typeof b === "string") { if (a !== b) console.log(k.id, "A:", String(a).slice(0, 60), "B:", String(b).slice(0, 60)); else same++; continue; }
  let n = 0;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) n++;
  if (n) console.log(k.id, "bytes differ:", n); else same++;
}
console.log("identical:", same);
