// Examples for docs/{en,vi}/image/tables.md. Run: node docs/examples/run-all.mjs tables
import { saver } from "./_lib.mjs";
import assert from "node:assert/strict";
import * as core from "bm-engine/core";
const save = saver("tables");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine/standard"; // tables and floats need standard or full

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
// #endregion

// #region html-table
const invoice = renderer.renderSync(
  `<style>
     body, div { font-family: Inter; font-size: 16px; color: #0f172a; }
     table { width: 100%; border-collapse: collapse; }
     th, td { padding: 8px 12px; border-bottom: 1px solid #cbd5e1; }
     th { text-align: left; background: #e2e8f0; }
     td.num, th.num { text-align: right; }
     tbody tr:nth-child(even) { background: #f8fafc; }
     tfoot td { font-weight: bold; border-bottom: none; }
   </style>
   <div style="padding:20px;background:white;height:100%">
     <table>
       <thead><tr><th>Item</th><th class="num" style="width:60px">Qty</th><th class="num" style="width:100px">Price</th></tr></thead>
       <tbody>
         <tr><td>Wireframe kit</td><td class="num">3</td><td class="num">$45.00</td></tr>
         <tr><td>Icon pack (Vietnamese edition: Tiếng Việt)</td><td class="num">1</td><td class="num">$19.00</td></tr>
         <tr><td>Font licence</td><td class="num">2</td><td class="num">$120.00</td></tr>
       </tbody>
       <tfoot><tr><td colspan="2">Total</td><td class="num">$184.00</td></tr></tfoot>
     </table>
   </div>`,
  { width: 560, height: 230 },
);
// #endregion
save("html-table", invoice);

// #region node-table
const cell = (text, style = {}) => ({
  type: "container", style: { display: "table-cell", padding: "6px 10px", border: "1px solid #94a3b8", ...style },
  children: [{ type: "text", text }],
});
const row = (...cells) => ({ type: "container", style: { display: "table-row" }, children: cells });
const nodeTable = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", padding: 16, width: "100%", height: "100%", backgroundColor: "white", fontFamily: "Inter", fontSize: 15 },
    children: [{
      type: "container",
      style: { display: "table", borderCollapse: "collapse" },
      children: [
        row(cell("Profile", { fontWeight: 700 }), cell("Tables", { fontWeight: 700 }), cell("Floats", { fontWeight: 700 })),
        row(cell("core"), cell("laid out as block"), cell("ignored")),
        row(cell("standard"), cell("yes"), cell("yes")),
        row(cell("full"), cell("yes"), cell("yes")),
      ],
    }],
  },
  { width: 400, height: 170 },
);
// #endregion
save("node-table", nodeTable);

// #region rtl
// dir="rtl" (or direction: rtl) puts the first column on the right. The text inside the cells is
// still laid out left to right on standard; on full it is right-aligned too (text-align: start).
const rtlTable = renderer.renderSync(
  `<div style="padding:16px;background:white;height:100%;font-family:Inter;font-size:15px">
     <table dir="rtl" style="border-collapse:collapse;width:100%">
       <tr><th>1st column</th><th>2nd column</th><th>3rd column</th></tr>
       <tr><td>A</td><td>B</td><td>C</td></tr>
     </table>
   </div>
   <style>th, td { border: 1px solid #94a3b8; padding: 6px 10px; text-align: start } th { background: #e2e8f0 }</style>`,
  { width: 400, height: 110 },
);
// #endregion
save("rtl", rtlTable);

// #region spans
const spans = renderer.renderSync(
  `<style>
     table { border-collapse: collapse; font-family: Inter; font-size: 15px; }
     td, th { border: 2px solid #475569; padding: 6px 12px; text-align: center; }
     th { background: #dbeafe; }
     caption { font-weight: bold; padding-bottom: 6px; }
   </style>
   <div style="padding:16px;background:white;height:100%">
     <table>
       <caption>Timetable</caption>
       <tr><th></th><th>Mon</th><th>Tue</th><th>Wed</th></tr>
       <tr><th>09:00</th><td rowspan="2" style="background:#fef3c7">Workshop<br>(2 h)</td><td colspan="2" style="background:#dcfce7">Planning</td></tr>
       <tr><th>10:00</th><td>Review</td><td>Demo</td></tr>
       <tr><th>11:00</th><td colspan="3" style="background:#fce7f3">Lunch for everyone</td></tr>
     </table>
   </div>`,
  { width: 420, height: 220 },
);
// #endregion
save("spans", spans);

// #region collapse
const table = (style) => `
  <table style="font-family:Inter;font-size:14px;${style}">
    <tr><td style="border:3px solid #2563eb;padding:6px">A</td><td style="border:1px solid #64748b;padding:6px">B</td></tr>
    <tr><td style="border:1px solid #64748b;padding:6px">C</td><td style="border:1px solid #64748b;padding:6px;background:#fde68a">D</td></tr>
  </table>`;
const collapse = renderer.renderSync(
  `<div style="display:flex;gap:28px;padding:16px;background:white;height:100%;align-items:flex-start;font-family:Inter;font-size:13px">
     <div>separate (default)${table("border:2px solid #0f172a")}</div>
     <div>border-spacing: 8px 4px${table("border:2px solid #0f172a;border-spacing:8px 4px")}</div>
     <div>collapse${table("border:2px solid #0f172a;border-collapse:collapse")}</div>
   </div>`,
  { width: 520, height: 130 },
);
// #endregion
save("collapse", collapse);

// #region layout-fixed
const columns = (layout) => `
  <table style="width:360px;table-layout:${layout};border-collapse:collapse;font-family:Inter;font-size:14px">
    <colgroup><col style="width:80px;background:#e0f2fe"><col><col style="width:30%"></colgroup>
    <tr><td>id</td><td>A long description that wraps onto several lines</td><td>status</td></tr>
    <tr><td>supercalifragilistic</td><td>short</td><td>ok</td></tr>
  </table>`;
const fixed = renderer.renderSync(
  `<style>td { border: 1px solid #64748b; padding: 4px 6px; vertical-align: top; }</style>
   <div style="display:flex;flex-direction:column;gap:10px;padding:16px;background:white;height:100%;font-family:Inter;font-size:13px">
     <span>table-layout: auto</span>${columns("auto")}
     <span>table-layout: fixed</span>${columns("fixed")}
   </div>`,
  { width: 400, height: 290 },
);
// #endregion
save("layout-fixed", fixed);

// #region valign
const valign = renderer.renderSync(
  `<style>td { border: 1px solid #94a3b8; width: 90px; height: 70px; padding: 4px; font-family: Inter; font-size: 14px; }</style>
   <div style="padding:16px;background:white;height:100%">
     <table style="border-collapse:collapse">
       <tr>
         <td style="vertical-align:top">top</td>
         <td style="vertical-align:middle">middle (default)</td>
         <td style="vertical-align:bottom">bottom</td>
         <td style="vertical-align:baseline;font-size:28px">Ag</td>
         <td style="vertical-align:baseline">baseline</td>
       </tr>
     </table>
   </div>`,
  { width: 520, height: 120 },
);
// #endregion
save("valign", valign);

// #region float
const avatar = renderer.renderSync(
  { type: "container", style: { width: "100%", height: "100%", borderRadius: 40, backgroundImage: "linear-gradient(135deg,#f97316,#db2777)" } },
  { width: 80, height: 80 },
);
const floated = renderer.renderSync(
  {
    type: "container",
    style: { display: "block", padding: 16, width: "100%", height: "100%", backgroundColor: "white", fontFamily: "Inter", fontSize: 15, lineHeight: 1.5 },
    children: [
      { type: "image", src: avatar, style: { float: "left", width: 80, height: 80, marginRight: 12, marginBottom: 4 } },
      { type: "text", text: "Floats take a box out of the normal flow and let the following text wrap around it. " +
        "Line boxes beside the float are shortened, and lines below it use the full width again, just like in a browser. " +
        "Use clear to start a block below every float." },
      { type: "container", style: { display: "block", clear: "both", marginTop: 8, padding: 8, backgroundColor: "#f1f5f9" },
        children: [{ type: "text", text: "clear: both starts below the float." }] },
    ],
  },
  { width: 420, height: 230 },
);
// #endregion
save("float", floated);

// #region float-right
const floatRight = renderer.renderSync(
  `<div style="padding:16px;background:white;height:100%;font-family:Inter;font-size:15px;line-height:1.5">
     <div style="float:right;width:120px;height:70px;margin:0 0 6px 12px;background:#a7f3d0;border-radius:8px"></div>
     <div style="float:left;width:50px;height:50px;margin:0 10px 0 0;background:#bfdbfe;border-radius:25px"></div>
     Two floats on opposite sides: the paragraph flows in the space between them, then re-widens once both
     floats have ended. Floats inside HTML input behave the same as in node trees.
   </div>`,
  { width: 420, height: 160 },
);
// #endregion
save("float-right", floatRight);

// #region core-fallback
const coreRenderer = new core.Renderer();
const probe = {
  type: "container", style: { display: "table" },
  children: [{ type: "container", style: { display: "table-row" }, children: [
    { type: "container", style: { display: "table-cell", width: 50, height: 20 } },
    { type: "container", style: { display: "table-cell", width: 50, height: 20 } },
  ] }],
};
const onCore = coreRenderer.measureSync(probe, { width: 200, height: 100 });
const onStandard = renderer.measureSync(probe, { width: 200, height: 100 });
// core: the cells stack like blocks; standard: they sit side by side in one row
console.log(onCore.children[0].children.map((c) => c.transform.slice(4)));     // [[0, 0], [0, 20]]
console.log(onStandard.children[0].children.map((c) => c.transform.slice(4))); // [[0, 0], [50, 0]]
// #endregion
const cpos = onCore.children[0].children.map((c) => c.transform.slice(4));
const spos = onStandard.children[0].children.map((c) => c.transform.slice(4));
console.log("core", JSON.stringify(cpos), "standard", JSON.stringify(spos), onCore.width, onCore.height, onStandard.width, onStandard.height);
