// Largest heavy-fit / table depth that renders + measures on a given build (bisection).
// Usage (from bench/): BM_WASM=<wasm> node probe/layout2/deepbisect.mjs
import { readFileSync } from "node:fs";
const wmod = new WebAssembly.Module(readFileSync(process.env.BM_WASM));
let seq = 0;
async function ok(node, phase) {
  const bm = await import("../../../js/index.mjs?b=" + seq++);
  bm.initSync(wmod);
  const r = new bm.Renderer();
  r.registerFont({ data: readFileSync("../assets/fonts/Inter-Regular.ttf") });
  try {
    if (phase !== "measure") r.renderSync(node, { width: 400, height: 300, format: "png" });
    if (phase !== "render") r.measureSync(node, { width: 400, height: 300 });
    return true;
  } catch (e) { return false; }
}
const heavy = (i) => ({ display: i % 3 === 0 ? "grid" : i % 3 === 1 ? "flex" : "block", padding: 0.5, opacity: i % 16 === 0 ? 0.9 : 1, overflow: i % 5 === 0 ? "hidden" : "visible", borderRadius: 3, border: "1px solid red", borderLeftColor: "blue", boxShadow: "0 0 4px #000, inset 0 0 3px red", backgroundImage: "linear-gradient(red, blue)", transform: i % 7 === 0 ? "rotate(1deg)" : "none", margin: -1.5 });
const leaf = { type: "text", text: "Deep text with shadow", style: { fontWeight: 700, fontStyle: "italic", textDecoration: "underline", boxShadow: "0 0 5px red" } };
const fit = (d) => { let n = leaf; for (let i = 0; i < d; i++) n = { type: "container", style: heavy(i), children: [n] }; return n; };
const plain = (d) => { let n = { type: "text", text: "x" }; for (let i = 0; i < d; i++) n = { type: "container", style: { display: "block" }, children: [n] }; return n; };
async function maxDepth(make, phase) {
  let lo = 1, hi = 511;
  if (await ok(make(hi), phase)) return hi;
  while (lo + 1 < hi) { const m = (lo + hi) >> 1; if (await ok(make(m), phase)) lo = m; else hi = m; }
  return lo;
}
for (const phase of ["both", "render", "measure"]) console.log("heavy-fit", phase, await maxDepth(fit, phase), "| plain block", phase, await maxDepth(plain, phase));
