// Robustness probe for svg_out: deep nesting (every level a transformed, clipped, translucent
// group with a backdrop filter at the bottom), a large text-heavy document, and invalid input.
//   node probe/svgout/deep.mjs [--wasm path]
import { readFileSync } from "node:fs";
import path from "node:path";
import { FONTS } from "../../lib/fonts.mjs";

const SCRATCH = "C:/Users/admini/AppData/Local/Temp/claude/46c8b6142d3c6b7e/eb762129-eac5-46a2-aaef-1b224d61f7d8/scratchpad/svgout";
const i = process.argv.indexOf("--wasm");
const wasmPath = i > 0 ? process.argv[i + 1] : path.join(SCRATCH, "svgtest.wasm");
const enc = new TextEncoder(), dec = new TextDecoder();
const W = new WebAssembly.Instance(new WebAssembly.Module(readFileSync(wasmPath)), {}).exports;
const mem = () => new Uint8Array(W.memory.buffer);
const copyIn = (bytes) => { const p = W.bm_alloc(bytes.length || 1); mem().set(bytes, p); return [p, bytes.length]; };
const str = (s) => copyIn(enc.encode(s));
const R = W.bm_renderer_new();
for (const f of FONTS.slice(0, 2)) { const [p, n] = copyIn(new Uint8Array(readFileSync(f.path))); const [np, nn] = str(f.name); W.bm_register_font(R, p, n, np, nn, f.weight, 0); }
function svg(node, opts) {
  const [sp, sn] = str(typeof node === "string" ? node : node.raw ?? JSON.stringify(node)); const [op, on] = str(JSON.stringify(opts));
  const t0 = performance.now();
  const st = W.bm_render_svg(R, typeof node === "string" ? 1 : 0, sp, sn, op, on);
  const ms = performance.now() - t0;
  if (st) { const p = W.bm_svg_err_ptr(R), n = W.bm_svg_err_len(R); return { error: dec.decode(mem().slice(p, p + n)), ms }; }
  const p = W.bm_result_ptr(R), n = W.bm_result_len(R);
  return { text: dec.decode(mem().slice(p, p + n)), ms };
}
const check = (name, r, pred) => console.log(name.padEnd(40), r.error ? "error: " + r.error : (pred(r.text) ? "ok" : "BAD"), r.text ? r.text.length + " bytes" : "", r.ms.toFixed(2) + " ms");

// 1. deep nesting (the DOM accepts 128 levels)
for (const depth of [100, 127, 200]) {
  let node = { type: "container", style: { width: 10, height: 10, backgroundColor: "red", backdropFilter: "blur(2px)", outline: "1px solid blue" } };
  for (let d = 0; d < depth; d++) node = { type: "container", style: { padding: 1, overflow: "hidden", opacity: 0.99, transform: "rotate(1deg)", borderRadius: 3, border: "1px dashed #333", boxShadow: "0 1px 2px #000" }, children: [node, { type: "text", text: "x" }] };
  const r = svg(node, { width: 600, height: 600 });
  check(`deep nesting ${depth}`, r, (t) => t.startsWith("<svg") && t.endsWith("</svg>\n") && (t.match(/<g/g) ?? []).length === (t.match(/<\/g>/g) ?? []).length);
}
// 2. large document
{
  const kids = [];
  for (let k = 0; k < 2000; k++) kids.push({ type: "text", text: "Lorem ipsum dolor sit amet " + k, style: { fontSize: 12, textDecoration: "underline", textShadow: "0 1px 2px #000" } });
  const r = svg({ type: "container", style: { display: "flex", flexWrap: "wrap", width: 1200 }, children: kids }, { width: 1200, height: 2000 });
  check("2000 text nodes", r, (t) => t.endsWith("</svg>\n"));
}
// 3. invalid input still fails cleanly
check("invalid JSON (expect error)", svg({ raw: "{" }, { width: 10, height: 10 }), () => false);
console.log("renderer still usable:", svg({ type: "container", style: { width: 5, height: 5, backgroundColor: "#0f0" } }, { width: 5, height: 5 }).text?.includes("#0f0"));
