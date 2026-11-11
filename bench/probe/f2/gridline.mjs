// Grid line grammar vs takumi: which <grid-line> forms are accepted (inline style: throws; stylesheet: dropped)
// and where the item lands. Usage (from bench/): BM_WASM=<wasm> node probe/f2/gridline.mjs
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
const B = new bm.Renderer(), T = new TR();
const o = { width: 400, height: 50 };
const f = (m) => { const k = m.children[0]; return `x=${k.transform[4]} w=${k.width} y=${k.transform[5]} h=${k.height}`; };
const cols = "[x-start a] 10px [a] 20px [x-end a] 30px [a] 40px [y] 50px [y]";
async function one(label, node) {
  let a, b;
  try { a = f(await T.measure(node, o)); } catch (e) { a = "THROWS " + String(e.message || e).slice(0, 60); }
  try { b = f(B.measureSync(node, o)); } catch (e) { b = "THROWS " + String(e.message || e).slice(0, 60); }
  console.log((a === b || (a.startsWith("THROWS") && b.startsWith("THROWS")) ? "ok  " : "DIFF"), label.padEnd(46), "takumi", a.padEnd(28), "bm", b);
}
const vals = ["x", "a", "2 a", "a 2", "-1 a", "span a", "span 2 a", "span a 2", "a span 2", "2 span", "span 2", "span", "0", "auto", "x / span 2", "2 / a", "2 / 3 a", "a / a", "2 / span a", "nope", "1 / nope", "span 0", "span -1", "2 2", "a b", "auto / a", "y", "-1", "-2 / -1", "x / y", "1.5", "2.9 / 4.2", "0 / 2", "2 / 0", "0 / 0", "1 / span y", "span y / 6", "span 70000", "65537", "-70000", "span 2 / span 3", "1 / 2 / 3", "span 1.5", "2 /", "/ 2", "calc(1 + 1)", "2px", "50%", "AUTO", "SPAN 2", "auto 2", "span auto", "span span"];
for (const v of ["0", "0 / 0", "-1", "2 / 0", "nope", "span 3"]) await one(`no-template gridColumn: ${v}`, { type: "container", style: { display: "grid", width: 400, gridAutoColumns: "20px" }, children: [{ type: "container", style: { gridColumn: v, height: 10 } }, { type: "container", style: { height: 10 } }] });
for (const v of vals) {
  await one(`inline gridColumn: ${v}`, { type: "container", style: { display: "grid", gridTemplateColumns: cols, gridTemplateRows: "10px", width: 400 }, children: [{ type: "container", style: { gridColumn: v, height: 10 } }] });
  await one(`sheet  grid-column: ${v}`, `<style>.g{display:grid;grid-template-columns:${cols};grid-template-rows:10px;width:400px}.i{height:10px;grid-column:${v}}</style><div class="g"><div class="i"></div></div>`.replace(/^/, ""));
}
for (const [k, v] of [["gridColumnStart", "2 a"], ["gridColumnEnd", "span 2 a"], ["gridColumnStart", "a"], ["gridColumnEnd", "a"], ["gridArea", "x"], ["gridArea", "1 / x"], ["gridArea", "1 / 2 a"], ["gridArea", "1 / a / 2"], ["gridRow", "x"], ["gridRowStart", "span 2 a"]])
  await one(`inline ${k}: ${v}`, { type: "container", style: { display: "grid", gridTemplateColumns: cols, gridTemplateRows: "10px", width: 400 }, children: [{ type: "container", style: { [k]: v, height: 10 } }] });
