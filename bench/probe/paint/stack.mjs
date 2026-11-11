// BM_WASM=<wasm> node probe/paint/stack.mjs [format=raw]
// Shadow-stack high-water mark per nesting level: the stack region below the initial
// __stack_pointer (STACK_KIB, default 1024) is filled with a pattern before a render and scanned afterwards.
import { readFileSync } from "node:fs";
const bytes = readFileSync(process.env.BM_WASM);
const wmod = new WebAssembly.Module(bytes);
const names = WebAssembly.Module.exports(wmod).map((e) => e.name);
if (!names.includes("__stack_pointer")) { console.log("no __stack_pointer export; exports:", names.join(" ")); process.exit(0); }
const STACK = +(process.env.STACK_KIB || 1024) * 1024;
const fmt = process.argv[2] || "raw";
let seq = 0;
async function run(depth, wrapStyle, leaf) {
  const bm = await import("../../../js/index.mjs?i=" + seq++);
  const ex = bm.initSync(wmod);
  const r = new bm.Renderer();
  r.registerFont({ data: readFileSync("../assets/fonts/Inter-Regular.ttf") });
  const hb = ex.__stack_pointer.value, de = hb - STACK;
  let n = leaf;
  for (let i = 0; i < depth; i++) n = { type: "container", style: wrapStyle(i), children: [n] };
  const warm = () => r.renderSync(n, { width: 400, height: 300, format: fmt });
  try { warm(); } catch (e) { return "ERR " + String(e.message).slice(0, 50); }
  const mem = new Uint8Array(ex.memory.buffer);
  const lo = Math.max(de, hb - (8 << 20));
  // leave the live part of the stack alone: nothing is live between calls, so the whole region is free
  mem.fill(0xa5, lo, hb);
  warm();
  const m2 = new Uint8Array(ex.memory.buffer);
  let p = lo; while (p < hb && m2[p] === 0xa5) p++;
  return hb - p;
}
const leaf = { type: "text", text: "Deep text", style: { fontWeight: 700, textDecoration: "underline" } };
const plain = () => ({ display: "flex", padding: 0.5, backgroundColor: "#eee" });
const heavy = (i) => ({ display: i % 3 === 0 ? "grid" : i % 3 === 1 ? "flex" : "block", padding: 0.5, overflow: i % 5 === 0 ? "hidden" : "visible", borderRadius: 3, border: "1px solid red", borderLeftColor: "blue", boxShadow: "0 0 4px #000, inset 0 0 3px red", backgroundImage: "linear-gradient(red, blue)", outline: "1px dashed green" });
const fxs = (i) => ({ ...heavy(i), opacity: i % 4 === 0 ? 0.9 : 1, clipPath: i % 6 === 1 ? "inset(0)" : "none", transform: i % 7 === 0 ? "rotate(1deg)" : "none", mixBlendMode: i % 9 === 2 ? "multiply" : "normal" });
const allfx = (i) => ({ ...heavy(i), opacity: 0.97, clipPath: "inset(0)" });
for (const [name, st] of [["plain", plain], ["heavy", heavy], ["effects", fxs], ["allfx", allfx]]) {
  const a = await run(10, st, leaf), b = await run(110, st, leaf);
  console.log(name.padEnd(8), "depth 10:", a, "bytes; depth 110:", b, "bytes; per level:", typeof a === "number" && typeof b === "number" ? ((b - a) / 100).toFixed(0) : "n/a");
}
