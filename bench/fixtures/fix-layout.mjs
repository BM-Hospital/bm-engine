// Layout correctness fixtures (branch fix-layout): direction: rtl in flex / grid / table / block layout,
// block-in-inline, float paint order, text-indent, inline box edges in bidi lines, text-wrap: balance
// with inline boxes / floats. Every case is compared against takumi like the rest of the suite.
// Behaviours where takumi itself deviates from Chrome (display: contents, percentage padding / margin of
// inline boxes) are NOT here: see bench/probe/fix-layout/chrome-check.mjs.
// HTML-string `node`s are parsed by both engines.

const page = (css, body, extra = "") => `<style>
  .page { font-family: Inter; width: 100%; height: 100%; background: #fff; color: #0f172a; padding: 12px; font-size: 14px; box-sizing: border-box; ${extra} }
  p { margin: 0 0 10px; }
  .b { width: 50px; height: 24px; background: #38bdf8; }
  .b:nth-child(2) { background: #f97316; width: 70px }
  .b:nth-child(3) { background: #22c55e; width: 40px }
  ${css}
</style><div class="page">${body}</div>`;
const three = `<div class="b"></div><div class="b"></div><div class="b"></div>`;
const B = (s) => `<div class="b" style="${s}"></div>`;

// ------------------------------------------------------------------------------------------------ direction: rtl
const rtlCss = `
  .f { display: flex; direction: rtl; background: #eee; margin-bottom: 5px; }
  .g { display: grid; direction: rtl; background: #eee; margin-bottom: 5px; }
  .a { position: absolute; width: 20px; height: 14px; background: #000; }
`;
const rtl = [
  {
    id: "fix-layout-rtl-flex", feature: "rtl", title: "direction: rtl flex rows: main axis from the right, row-reverse, justify-content, margins, padding, flex-grow, relative offsets", width: 420, height: 300,
    node: page(rtlCss, `
      <div class="f" style="padding:4px 30px 4px 6px;border-left:8px solid #000;border-right:2px solid red">${three}</div>
      <div class="f" style="justify-content:center;gap:7px">${B("margin-left:20px")}${B("margin-right:13px")}${B("")}</div>
      <div class="f" style="justify-content:left">${three}</div>
      <div class="f" style="justify-content:flex-end">${three}</div>
      <div class="f" style="justify-content:start;flex-direction:row-reverse">${three}</div>
      <div class="f" style="justify-content:space-between;padding-inline-start:20px">${B("margin-inline-start:10px")}${B("")}${B("")}</div>
      <div class="f">${B("flex:1")}${B("flex:2;position:relative;left:6px;top:3px")}${B("")}</div>
      <div class="f" style="width:333px">${B("flex:1")}${B("flex:1")}${B("flex:1")}${B("flex:1")}${B("flex:1")}${B("flex:1")}${B("flex:1")}</div>
    `),
  },
  {
    id: "fix-layout-rtl-flex-wrap-abs", feature: "rtl", title: "rtl flex: wrapping, column direction (cross axis from the right), wrap-reverse, absolutely positioned children (static position, physical and logical insets)", width: 420, height: 300,
    node: page(rtlCss, `
      <div class="f" style="flex-direction:column;height:54px;flex-wrap:wrap;align-content:flex-start">${three}${three}</div>
      <div class="f" style="flex-direction:column;align-items:flex-end">${B("align-self:start")}${B("")}${B("align-self:center")}</div>
      <div class="f" style="flex-wrap:wrap-reverse;width:130px">${three}${three}</div>
      <div class="f" style="position:relative;height:36px;padding:0 10px 0 30px">${B("")}<div class="a"></div><div class="a" style="left:4px;top:20px;background:red"></div><div class="a" style="inset-inline-start:4px;top:20px;background:blue"></div></div>
      <div style="position:relative;border:3px solid #999;padding:5px 5px 5px 40px"><div class="f" style="height:36px;padding-right:25px;justify-content:center">${B("")}<div class="a"></div><div class="a" style="left:4px;top:20px;background:red"></div><div class="a" style="right:4px;top:26px;background:blue;margin-right:9px"></div></div></div>
    `),
  },
  {
    id: "fix-layout-rtl-grid-block", feature: "rtl", title: "rtl grid (column order, spans, justify-items / justify-self, auto-flow column) and rtl block containers (over-constrained children at the right, auto margins, logical margin / padding / border)", width: 420, height: 300,
    node: page(rtlCss + `.g > div { width: auto } .x { direction: rtl; background: #eee; margin-bottom: 5px }`, `
      <div class="g" style="grid-template-columns:60px 100px 1fr;gap:4px;padding:0 20px 0 4px">${three}<div class="b" style="grid-column:1 / span 2"></div>${B("justify-self:start;width:20px")}</div>
      <div class="g" style="grid-template-columns:repeat(3,70px);justify-content:end;justify-items:end">${B("width:30px")}${B("width:30px;margin-left:5px")}${B("width:30px;justify-self:left")}</div>
      <div class="g" style="grid-auto-flow:column;grid-auto-columns:40px;justify-content:space-between">${three}</div>
      <div class="x">${B("")}${B("margin-right:10px")}${B("margin-left:auto")}${B("margin:0 auto")}${B("margin-inline-start:25px")}${B("position:relative;right:5px;left:9px")}</div>
      <div class="x"><div style="padding-inline-start:30px;border-inline-start:4px solid red;background:#ddd;width:200px">logical edges</div></div>
    `),
  },
  {
    id: "fix-layout-rtl-table", feature: "rtl", title: "rtl tables: columns right to left (dir attribute and direction), colspan / rowspan, captions, column backgrounds, border-spacing, collapsed borders with per-side widths and styles", width: 420, height: 330,
    node: page(`td, th { border: 1px solid #333; padding: 3px 6px } table { margin-bottom: 8px } .c { border-collapse: collapse }`, `
      <table dir="rtl"><tr><td>one</td><td>two longer</td><td>3</td></tr><tr><td colspan="2">span</td><td>x</td></tr><tr><td rowspan="2">rs</td><td>b</td><td>c</td></tr><tr><td>e</td><td>f</td></tr></table>
      <table style="direction:rtl;width:300px;border:3px solid red;border-left-width:12px;padding:2px 2px 2px 20px;border-spacing:6px 2px"><caption>caption</caption><colgroup><col style="background:#fde047"><col span="2" style="background:#bae6fd"></colgroup><tr><th>h1</th><th>h2</th><th>h3</th></tr><tr><td style="border-left:5px solid blue">one</td><td>two longer</td><td>3</td></tr></table>
      <table class="c" dir="rtl"><tr><td>one</td><td style="border-left:6px solid red;border-right:3px dashed blue">two longer</td><td>3</td></tr><tr><td colspan="2" style="border-bottom:4px double green">span</td><td>x</td></tr></table>
      <table class="c" dir="rtl" style="border:5px solid #f97316;border-left:9px solid #22c55e;width:260px"><tr><td>a</td><td style="border:3px solid #000">b</td><td>c</td></tr><tr style="border-bottom:4px solid purple"><td rowspan="2" style="border-right:7px solid #06b6d4">d</td><td>e</td><td>f</td></tr><tr><td>g</td><td style="border-left-style:hidden">h</td></tr></table>
    `),
  },
  {
    id: "fix-layout-rtl-node-dir", feature: "rtl", title: "node `dir` field: rtl flex container with logical padding / margin and an ltr child container", width: 300, height: 100,
    node: { type: "container", dir: "rtl", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#fff", gap: 6, paddingInlineStart: 20 }, children: [
      { type: "container", style: { width: 50, height: 30, backgroundColor: "#38bdf8", marginInlineStart: 10 } },
      { type: "container", style: { width: 50, height: 30, backgroundColor: "#f97316" } },
      { type: "container", dir: "ltr", style: { display: "flex", width: 80, height: 30, backgroundColor: "#eee" }, children: [{ type: "container", style: { width: 20, height: 20, backgroundColor: "#000" } }] }] },
  },
];

export default [rtl].flat();
