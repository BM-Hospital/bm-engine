// Ad-hoc acceptance / pixel checks of single style declarations vs takumi.
// Usage (from bench/): BM_WASM=<wasm> node probe/f2/accept2.mjs '<prop>: <value>' ['<prop>: <value>; <prop>: <value>' ...]
// Without arguments runs the built-in list (border / outline `auto` forms).
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
const B = new bm.Renderer(), T = new TR();
const o = { width: 120, height: 80, format: "raw" };
const builtin = [
  "border: auto", "border: auto solid red", "border: 3px solid red", "border: solid red", "border: solid auto red", "border: 5px auto solid red", "border: auto 5px solid red",
  "borderWidth: auto", "borderTopWidth: auto", "borderTop: auto solid red", "borderStyle: auto", "borderColor: auto",
  "outline: auto", "outline: 3px auto red", "outline: auto 3px solid red", "outline: 3px solid red auto", "outline: solid red", "outline: auto solid red",
  "outlineWidth: auto", "outlineWidth: auto; outlineStyle: solid", "outlineStyle: auto", "outlineColor: auto", "outlineOffset: auto",
  "outline: 3px solid red; outlineStyle: auto", "outline: thick double #00f", "outline: medium", "outline: none", "outline: 0",
];
const list = process.argv.length > 2 ? process.argv.slice(2) : builtin;
for (const decl of list) {
  const style = { width: 60, height: 30, backgroundColor: "#9cf" };
  for (const d of decl.split(";")) { const i = d.indexOf(":"); style[d.slice(0, i).trim()] = d.slice(i + 1).trim(); }
  const node = { type: "container", style: { width: "100%", height: "100%", backgroundColor: "#fff", padding: 20, display: "flex" }, children: [{ type: "container", style }] };
  let a, b, ea = "", eb = "";
  try { a = new Uint8Array(await T.render(node, o)); } catch (e) { ea = "THROWS"; }
  try { b = B.renderSync(node, o); } catch (e) { eb = "THROWS"; }
  let d = -1;
  if (a && b) { d = 0; for (let i = 0; i < a.length; i += 4) if (Math.abs(a[i] - b[i]) > 8 || Math.abs(a[i + 1] - b[i + 1]) > 8 || Math.abs(a[i + 2] - b[i + 2]) > 8) d++; }
  console.log(ea === eb && d <= 0 ? "ok  " : "DIFF", decl.padEnd(46), "takumi", (ea || "ok").padEnd(7), "bm", (eb || "ok").padEnd(7), d >= 0 ? `diffpx ${d}` : "");
}
