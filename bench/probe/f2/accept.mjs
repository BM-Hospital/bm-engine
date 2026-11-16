// Which inline style values takumi accepts vs bm (THROWS / pixel difference of a small render).
// Usage (from bench/): BM_WASM=<wasm> node probe/f2/accept.mjs [regex]
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_render.wasm"));
const B = new bm.Renderer(), T = new TR();
const o = { width: 120, height: 80, format: "raw" };
const re = new RegExp(process.argv[2] || ".");
const cases = [];
const box = (style) => ({ type: "container", style: { width: "100%", height: "100%", backgroundColor: "#fff", padding: 20, display: "flex" }, children: [{ type: "container", style: { width: 60, height: 30, backgroundColor: "#9cf", ...style } }] });
for (const v of ["auto", "solid", "dashed", "none", "hidden", "double", "groove", "inset"]) cases.push([`outlineStyle: ${v}`, box({ outlineWidth: 3, outlineColor: "#f00", outlineStyle: v })]);
for (const v of ["auto", "3px auto red", "auto red", "3px solid red", "red", "3px", "solid", "3px auto", "medium auto", "auto 3px #00f"]) cases.push([`outline: ${v}`, box({ outline: v })]);
for (const v of ["auto", "red"]) cases.push([`outlineColor: ${v}`, box({ outline: "3px solid blue", outlineColor: v })]);
const flex = (cs, is) => ({ type: "container", style: { width: "100%", height: "100%", backgroundColor: "#fff", display: "flex", ...cs }, children: [{ type: "container", style: { width: 150, height: 100, flexShrink: 0, backgroundColor: "#9cf", ...is } }] });
for (const v of ["safe center", "unsafe center", "center", "safe end", "unsafe end", "safe", "center safe", "safe flex-end", "safe space-between", "safe stretch", "safe baseline", "first baseline", "last baseline", "safe first baseline"]) {
  cases.push([`justifyContent: ${v}`, flex({ justifyContent: v })]);
  cases.push([`alignItems: ${v}`, flex({ alignItems: v })]);
  cases.push([`alignSelf: ${v}`, flex({}, { alignSelf: v })]);
  cases.push([`alignContent: ${v}`, flex({ alignContent: v, flexWrap: "wrap" })]);
}
for (const v of ["safe center", "unsafe center", "safe center unsafe end", "center safe end"]) {
  cases.push([`placeItems: ${v}`, flex({ display: "grid", placeItems: v })]);
  cases.push([`placeContent: ${v}`, flex({ display: "grid", placeContent: v, gridTemplateColumns: "150px", gridTemplateRows: "100px" })]);
  cases.push([`placeSelf: ${v}`, flex({ display: "grid" }, { placeSelf: v })]);
  cases.push([`justifyItems: ${v}`, flex({ display: "grid" }, { justifySelf: v })]);
}
for (const [label, node] of cases) {
  if (!re.test(label)) continue;
  let a, b, ea = "", eb = "";
  try { a = new Uint8Array(await T.render(node, o)); } catch (e) { ea = "THROWS"; }
  try { b = B.renderSync(node, o); } catch (e) { eb = "THROWS"; }
  let d = -1;
  if (a && b) { d = 0; for (let i = 0; i < a.length; i += 4) if (Math.abs(a[i] - b[i]) > 8 || Math.abs(a[i + 1] - b[i + 1]) > 8 || Math.abs(a[i + 2] - b[i + 2]) > 8) d++; }
  const ok = ea === eb && d <= 0;
  console.log(ok ? "ok  " : "DIFF", label.padEnd(40), "takumi", (ea || "ok").padEnd(7), "bm", (eb || "ok").padEnd(7), d >= 0 ? `diffpx ${d}` : "");
}
