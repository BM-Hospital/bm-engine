// Nesting-depth probe for inline formatting contexts: chains of inline-blocks inside text, of floats declared
// inside paragraphs, of nested spans with edges, and of inline-blocks inside spans; each renders (png) + measures.
// A trap (stack overflow -> memory corruption) must never happen: deep inputs either work or fail cleanly.
//   BM_WASM=<ReleaseSafe build, -Dstrip=false> node probe/layout3/deep.mjs [depths...]
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
    return (e instanceof WebAssembly.RuntimeError ? "TRAP " : "ERR ") + String(e.message || e).slice(0, 70);
  }
}
const rep = (n, open, close, core) => open.repeat(n) + core + close.repeat(n);
const cases = {
  // text > inline-block > text > inline-block ... (each inline-block is an object of the paragraph around it)
  "inline-block in text": (d) => rep(d, `<span style="display:inline-block;padding:0.5px;border:1px solid green">x `, ` y</span>`, "core"),
  // a float inside the text of a float inside the text ... (placed from inside the line breaker)
  "float in text": (d) => rep(d, `<span style="float:left;padding:0.5px;border:1px solid red">a `, ` b</span>`, "core"),
  // nested inline boxes with edges (one paragraph, d open boxes)
  "nested spans": (d) => rep(d, `<span style="padding:0 1px;border:1px solid blue;vertical-align:1px">s `, ` e</span>`, "core"),
  // inline-block inside a span inside an inline-block ...
  "span > inline-block": (d) => rep(d, `<span style="padding:0 1px;background:#eee"><span style="display:inline-block;border:1px solid green">x `, ` y</span></span>`, "core"),
};
const depths = process.argv.slice(2).map(Number);
for (const [name, mk] of Object.entries(cases)) {
  for (const d of depths.length ? depths : [50, 100, 150, 200, 250, 300, 400, 510]) console.log(name.padEnd(22), String(d).padStart(4), await run(`<div style="font-family:Inter;font-size:10px;width:400px">${mk(d)}</div>`));
}
