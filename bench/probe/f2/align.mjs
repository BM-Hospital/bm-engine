// Alignment keyword matrix vs takumi: acceptance (inline style) and the position of an overflowing child
// (so `safe` / `unsafe` show). Usage (from bench/): BM_WASM=<wasm> node probe/f2/align.mjs [--all]
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_render.wasm"));
const B = new bm.Renderer(), T = new TR();
const o = { width: 100, height: 60 };
const all = process.argv.includes("--all");
const kws = ["normal", "auto", "stretch", "start", "end", "flex-start", "flex-end", "self-start", "self-end", "flow-start", "flow-end", "center", "left", "right", "baseline", "first baseline", "last baseline", "space-between", "space-around", "space-evenly", "legacy", "legacy center", "anchor-center"];
const pos = ["start", "end", "flex-start", "flex-end", "self-start", "self-end", "flow-start", "flow-end", "center", "left", "right", "stretch", "baseline", "space-between", "normal", "auto"];
const vals = [...kws, ...pos.map((k) => "safe " + k), ...pos.map((k) => "unsafe " + k), "safe", "center safe", "safe safe center", "safe unsafe center"];
const props = ["justifyContent", "alignContent", "alignItems", "alignSelf", "justifyItems", "justifySelf"];
const f = (m) => { const k = m.children[0]; return `${k.transform[4]},${k.transform[5]} ${k.width}x${k.height}`; };
let ok = 0, bad = 0;
for (const disp of ["flex", "grid"]) for (const p of props) for (const v of vals) {
  const onChild = p === "alignSelf" || p === "justifySelf";
  const cs = { display: disp, width: 100, height: 60, ...(disp === "grid" ? { gridTemplateColumns: "140px", gridTemplateRows: "90px" } : { flexWrap: p === "alignContent" ? "wrap" : "nowrap" }), ...(onChild ? {} : { [p]: v }) };
  const is = { width: 140, height: 90, flexShrink: 0, ...(onChild ? { [p]: v } : {}) };
  const node = { type: "container", style: cs, children: [{ type: "container", style: is }] };
  let a, b;
  try { a = f(await T.measure(node, o)); } catch { a = "THROWS"; }
  try { b = f(B.measureSync(node, o)); } catch { b = "THROWS"; }
  if (a === b) ok++; else bad++;
  if (a !== b || all) console.log(a === b ? "ok  " : "DIFF", disp, `${p}: ${v}`.padEnd(34), "takumi", a.padEnd(18), "bm", b);
}
console.log(JSON.stringify({ ok, bad }));
