// Random tables (spans, collapsed borders of every style, col / colgroup, captions, collapsed rows / columns,
// stray boxes, lone rows / cells, nesting) rendered by bm only: no trap, no non-"bm-engine:" error.
// Usage (from bench/): BM_WASM=<ReleaseSafe wasm> node probe/f2/tablefuzz.mjs [seed=1] [n=800]
import fs, { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer();
r.registerFont({ name: "Inter", data: readFileSync("../assets/fonts/Inter-Regular.ttf") });
let seed = +(process.argv[2] || 1) >>> 0;
const N = +(process.argv[3] || 800);
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
const ri = (n) => Math.floor(rnd() * n);
const pick = (a) => a[ri(a.length)];
const styles = ["none", "hidden", "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset"];
const col = () => pick(["#f00", "#00f", "rgba(0,128,0,.5)", "transparent", "currentColor", "#000"]);
const border = () => `${pick(["0", "1px", "2px", "3.5px", "7px", "40px", "1e9px", "thin"])} ${pick(styles)} ${col()}`;
const bg = () => pick(["", "", "background:#fde68a;", "background:rgba(255,0,0,.3);", "background:linear-gradient(90deg,#f00,#00f);", "background:radial-gradient(#fff,#000) no-repeat 3px 4px / 50% 20px;"]);
const decl = () => {
  let s = bg();
  if (rnd() < 0.5) s += `border:${border()};`;
  if (rnd() < 0.2) s += `border-${pick(["top", "left", "right", "bottom"])}:${border()};`;
  if (rnd() < 0.15) s += `visibility:${pick(["collapse", "hidden", "visible"])};`;
  if (rnd() < 0.15) s += `padding:${ri(12)}px;`;
  if (rnd() < 0.1) s += `border-radius:${ri(30)}px;`;
  if (rnd() < 0.1) s += `box-shadow:${pick(["", "inset "])}0 0 ${ri(8)}px #000;`;
  if (rnd() < 0.08) s += `opacity:${rnd().toFixed(2)};`;
  if (rnd() < 0.08) s += `transform:rotate(${ri(40)}deg);`;
  if (rnd() < 0.08) s += `position:${pick(["relative", "absolute"])};z-index:${ri(3) - 1};`;
  if (rnd() < 0.08) s += `width:${pick(["10px", "50%", "300px", "0", "1e7px"])};`;
  if (rnd() < 0.08) s += `height:${pick(["10px", "50%", "300px", "0"])};`;
  if (rnd() < 0.05) s += `display:${pick(["none", "block", "table-cell", "table-row", "table", "inline-table", "table-caption", "table-column", "table-row-group", "flex"])};`;
  if (rnd() < 0.05) s += `empty-cells:${pick(["hide", "show"])};`;
  if (rnd() < 0.05) s += `overflow:hidden;`;
  return s;
};
function table(depth) {
  const rows = ri(6), cols = 1 + ri(6);
  let s = `<table style="${decl()}${rnd() < 0.5 ? "border-collapse:collapse;" : `border-spacing:${ri(9)}px ${ri(9)}px;`}${rnd() < 0.2 ? "table-layout:fixed;width:100%;" : ""}${rnd() < 0.2 ? "empty-cells:hide;" : ""}">`;
  if (rnd() < 0.3) s += `<caption style="${decl()}${rnd() < 0.5 ? "caption-side:bottom;" : ""}">cap</caption>`;
  if (rnd() < 0.4) { s += `<colgroup style="${decl()}"${rnd() < 0.3 ? ` span="${ri(5)}"` : ""}>`; for (let i = ri(4); i > 0; i--) s += `<col style="${decl()}"${rnd() < 0.3 ? ` span="${pick([0, 1, 2, 3, 1000, 99999])}"` : ""}>`; s += "</colgroup>"; }
  if (rnd() < 0.3) s += `<col style="${decl()}">`;
  const sec = () => { let o = ""; for (let y = 0; y < rows; y++) { o += `<tr style="${decl()}">`; for (let x = 0; x < cols; x++) { if (rnd() < 0.1) { o += `<div style="${decl()}">stray</div>`; continue; } o += `<${pick(["td", "td", "th"])} style="${decl()}"${rnd() < 0.2 ? ` colspan="${pick([0, 1, 2, 3, 7, 1000, 70000])}"` : ""}${rnd() < 0.2 ? ` rowspan="${pick([0, 1, 2, 3, 9, 65534, 70000])}"` : ""}>${rnd() < 0.15 ? "" : rnd() < 0.1 && depth < 3 ? table(depth + 1) : "c" + ri(99)}</td>`; } o += "</tr>"; } return o; };
  for (let k = ri(3); k >= 0; k--) { const tag = pick(["thead", "tbody", "tbody", "tfoot", ""]); s += tag ? `<${tag} style="${decl()}">${sec()}</${tag}>` : sec(); }
  if (rnd() < 0.1) s += `<div style="${decl()}">loose</div>`;
  return s + "</table>";
}
const lone = () => pick([`<div style="display:table-row;${decl()}border-collapse:collapse"><div style="display:table-cell;${decl()}">a</div><span>x</span><div style="display:table-cell;${decl()}">b</div></div>`, `<div style="display:table-row-group;${decl()}"><div style="display:table-row;${decl()}"><div style="display:table-cell;${decl()}">a</div></div></div>`, `<div style="display:table-cell;${decl()}">alone</div>`, `<div style="display:table-column;${decl()}"></div>`]);
let ok = 0; const errs = {};
for (let i = 0; i < N; i++) {
  const s0 = seed;
  const html = `<div style="font-family:Inter;font-size:${8 + ri(12)}px;width:100%;height:100%;background:#fff;${pick(["", "display:flex;", "display:grid;", "padding:9.3px;"])}">${rnd() < 0.2 ? lone() : ""}${table(0)}${rnd() < 0.3 ? table(0) : ""}</div>`;
  const t0 = performance.now();
  try { r.renderSync(html, { width: pick([1, 40, 300, 640]), height: pick([1, 60, 240]), format: "raw" }); ok++; }
  catch (e) {
    const m = String(e.message || e);
    if (!m.startsWith("bm-engine:")) { console.log("TRAP at seed state", s0, "case", i, m.slice(0, 200)); console.log(html.slice(0, 3000)); process.exit(1); }
    const k = m.replace(/property .*/, "property …").slice(0, 80); errs[k] = (errs[k] || 0) + 1;
  }
  const dt = performance.now() - t0;
  if (dt > 1500) { console.log("SLOW case", i, "seed state", s0, Math.round(dt), "ms"); if (process.env.SLOW_DUMP) fs.writeFileSync(process.env.SLOW_DUMP, html); }
}
console.log("ok", ok, "rejected", N - ok, errs);
