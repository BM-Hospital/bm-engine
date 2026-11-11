import { readFileSync } from "node:fs";
const wmod = new WebAssembly.Module(readFileSync(process.env.BM_WASM)); let seq = 0;
async function run(depth, leafStyle, wrapStyle) {
  const bm = await import("../../js/index.mjs?i=" + seq++); bm.initSync(wmod);
  const r = new bm.Renderer();
  r.registerFont({ data: readFileSync("../assets/fonts/Inter-Regular.ttf") });
  let n = { type: "text", text: "Deep text with shadow", style: leafStyle };
  for (let i = 0; i < depth; i++) n = { type: "container", style: wrapStyle(i), children: [n] };
  try { const o = r.renderSync(n, { width: 400, height: 300, format: "png" }); r.measureSync(n, { width: 400, height: 300 }); return "ok " + o.length; } catch (e) { return "ERR " + String(e.message).slice(0, 60); }
}
const heavy = (i) => ({ display: i % 3 === 0 ? "grid" : i % 3 === 1 ? "flex" : "block", padding: 0.5, opacity: i % 16 === 0 ? 0.9 : 1, overflow: i % 5 === 0 ? "hidden" : "visible", borderRadius: 3, border: "1px solid red", borderLeftColor: "blue", boxShadow: "0 0 4px #000, inset 0 0 3px red", backgroundImage: "linear-gradient(red, blue)", transform: i % 7 === 0 ? "rotate(1deg)" : "none" });
for (const d of [20, 60, 100, 126, 127, 140]) console.log("depth", d, await run(d, { fontWeight: 700, fontStyle: "italic", textDecoration: "underline", boxShadow: "0 0 5px red" }, heavy));
