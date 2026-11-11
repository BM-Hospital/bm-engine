// Tailwind alignment / outline classes that reach the changed style grammar: child position vs takumi.
// Usage (from bench/): BM_WASM=<wasm> node probe/f2/twalign.mjs
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
const B = new bm.Renderer(), T = new TR();
const o = { width: 100, height: 60 };
const f = (m) => { const k = m.children[0]; return `${k.transform[4]},${k.transform[5]} ${k.width}x${k.height}`; };
const parent = ["", "items-center", "items-baseline", "items-baseline-last", "items-end-safe", "items-center-safe", "justify-center", "justify-center-safe", "justify-end-safe", "justify-normal", "justify-stretch", "justify-baseline", "content-center", "content-normal", "content-baseline", "content-center-safe", "justify-items-center", "justify-items-normal", "justify-items-center-safe", "place-content-center", "place-content-baseline", "place-content-center-safe", "place-items-center", "place-items-baseline", "place-items-end-safe"];
const child = ["self-auto", "self-center", "self-baseline", "self-baseline-last", "self-end-safe", "self-center-safe", "justify-self-auto", "justify-self-center", "justify-self-end-safe", "place-self-auto", "place-self-center", "place-self-end-safe", "self-center self-auto", "col-span-2", "col-start-2", "col-[2]", "col-[span_2]", "row-[1/3]", "col-auto", "col-span-full"];
for (const disp of ["flex", "grid grid-cols-[140px] grid-rows-[90px]"]) {
  for (const c of parent) {
    const node = { type: "container", tw: `${disp} flex-wrap w-[100px] h-[60px] ${c}`, children: [{ type: "container", tw: "w-[140px] h-[90px] shrink-0" }] };
    let a, b;
    try { a = f(await T.measure(node, o)); } catch { a = "THROWS"; }
    try { b = f(B.measureSync(node, o)); } catch { b = "THROWS"; }
    console.log(a === b ? "ok  " : "DIFF", `${disp.split(" ")[0]} parent ${c}`.padEnd(40), "takumi", a.padEnd(18), "bm", b);
  }
  for (const c of child) {
    const node = { type: "container", tw: `${disp} w-[100px] h-[60px] items-end justify-items-end`, children: [{ type: "container", tw: `w-[140px] h-[90px] shrink-0 ${c}` }] };
    let a, b;
    try { a = f(await T.measure(node, o)); } catch { a = "THROWS"; }
    try { b = f(B.measureSync(node, o)); } catch { b = "THROWS"; }
    console.log(a === b ? "ok  " : "DIFF", `${disp.split(" ")[0]} child ${c}`.padEnd(40), "takumi", a.padEnd(18), "bm", b);
  }
}
