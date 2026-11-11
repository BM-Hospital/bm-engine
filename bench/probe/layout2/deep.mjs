// Nesting-depth probe (extends probe/deep.mjs): heavy alternating grid/flex/block chains with shadows, clips,
// opacity, gradients, transforms and a text leaf; block chains with an inline-block at every level (line
// containers add layout levels); table > row > cell chains. Each run renders (png) AND measures.
// Usage (from bench/): BM_WASM=<dir>/bin/bm_engine.wasm node probe/layout2/deep.mjs [depths...]
import { readFileSync } from "node:fs";
const wmod = new WebAssembly.Module(readFileSync(process.env.BM_WASM));
let seq = 0;
async function run(node) {
  const bm = await import("../../../js/index.mjs?i=" + seq++);
  bm.initSync(wmod);
  const r = new bm.Renderer();
  r.registerFont({ data: readFileSync("../assets/fonts/Inter-Regular.ttf") });
  try {
    const o = r.renderSync(node, { width: 400, height: 300, format: "png" });
    r.measureSync(node, { width: 400, height: 300 });
    return "ok " + o.length;
  } catch (e) {
    if (process.env.DEEP_TRACE) console.log(String(e.stack).split("\n").slice(0, 40).join("\n"));
    return "ERR " + String(e.message || e).slice(0, 70);
  }
}
const heavy = (i) => ({ display: i % 3 === 0 ? "grid" : i % 3 === 1 ? "flex" : "block", padding: 0.5, opacity: i % 16 === 0 ? 0.9 : 1, overflow: i % 5 === 0 ? "hidden" : "visible", borderRadius: 3, border: "1px solid red", borderLeftColor: "blue", boxShadow: "0 0 4px #000, inset 0 0 3px red", backgroundImage: "linear-gradient(red, blue)", transform: i % 7 === 0 ? "rotate(1deg)" : "none" });
const leaf = { type: "text", text: "Deep text with shadow", style: { fontWeight: 700, fontStyle: "italic", textDecoration: "underline", boxShadow: "0 0 5px red" } };
const chain = (depth, wrap) => { let n = leaf; for (let i = 0; i < depth; i++) n = wrap(i, n); return n; };
// (the plain chain drifts 1.5 px per level and leaves the canvas, so the painter culls the deep part;
// heavyFit cancels the drift with negative margins so that every level is painted)
const heavyFit = (d) => chain(d, (i, n) => ({ type: "container", style: { ...heavy(i), margin: -1.5 }, children: [n] }));
const heavyChain = (d) => chain(d, (i, n) => ({ type: "container", style: heavy(i), children: [n] }));
// block > inline-block > block > ... (every inline-block sits in an anonymous line container)
const ibChain = (d) => chain(d, (i, n) => ({ type: "container", style: { display: i % 2 ? "inline-block" : "block", padding: 0.5, border: "1px solid green" }, children: [{ type: "text", text: "x " }, n] }));
// table > tr > td > table > ... (3 node levels per table)
const tableChain = (tables) => {
  let n = leaf;
  for (let i = 0; i < tables; i++) n = { type: "container", style: { display: "table", borderCollapse: i % 2 ? "collapse" : "separate", borderSpacing: 1, border: "1px solid red" }, children: [{ type: "container", style: { display: "table-row" }, children: [{ type: "container", style: { display: "table-cell", padding: 0.5, border: "1px solid blue", verticalAlign: "middle" }, children: [n] }] }] };
  return n;
};
const depths = process.argv.slice(2).map(Number);
for (const d of depths.length ? depths : [128, 200, 300, 400, 500, 511]) console.log("heavy", d, await run(heavyChain(d)));
for (const d of depths.length ? depths : [128, 200, 300, 400, 500, 511]) console.log("heavy-fit", d, await run(heavyFit(d)));
for (const d of depths.length ? depths : [128, 255, 400, 510]) console.log("inline-block", d, await run(ibChain(d)));
for (const t of [50, 100, 170]) console.log("tables", t, "(" + t * 3 + " levels)", await run(tableChain(t)));
