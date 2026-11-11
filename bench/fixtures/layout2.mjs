// Phase 2 layout features: tables (HTML colspan/rowspan attributes, border-collapse, captions, fixed layout),
// floats (float / clear / BFC roots), atomic inline boxes (inline-block badges and buttons on lines, vertical-align)
// and grid template areas / named lines. HTML-string `node`s are parsed by both engines; `opts` are forwarded.
import { asset } from "./_h.mjs";

const FONT = "font-family: Inter;";
const imgs = () => [
  { src: "img://avatar", data: asset("avatar.png") }, // 400x400 PNG
  { src: "img://icon", data: asset("icon.png") }, // 128x128 PNG
];

const page = (css, body, extra = "") => `<style>
  .page { ${FONT} width: 100%; height: 100%; background: #fff; color: #0f172a; padding: 24px; ${extra} }
  ${css}
</style><div class="page">${body}</div>`;

// ------------------------------------------------------------------------------------------------ tables
const tableCss = `
  table { font-size: 16px; }
  th, td { padding: 6px 10px; }
  th { background: #e2e8f0; }
  .num { text-align: right; }
`;
const tables = [
  {
    id: "layout2-table-auto", feature: "table", title: "auto table layout: header row, text cells, border-collapse, caption", width: 600, height: 300,
    node: page(tableCss + `
      table { border-collapse: collapse; border: 2px solid #334155; }
      td, th { border: 1px solid #94a3b8; }
      caption { font-weight: 700; padding-bottom: 6px; color: #1d4ed8; }
    `, `<table>
      <caption>Quarterly results</caption>
      <thead><tr><th>Region</th><th>Q1</th><th>Q2</th><th>Total</th></tr></thead>
      <tbody>
        <tr><td>North America</td><td class="num">120</td><td class="num">135</td><td class="num">255</td></tr>
        <tr><td>Europe</td><td class="num">98</td><td class="num">101</td><td class="num">199</td></tr>
        <tr><td>Asia Pacific and the rest of the world</td><td class="num">7</td><td class="num">1 040</td><td class="num">1 047</td></tr>
      </tbody>
    </table>`),
  },
  {
    id: "layout2-table-spans", feature: "table", title: "colspan / rowspan from HTML attributes, border-spacing, vertical-align", width: 600, height: 320,
    node: page(tableCss + `
      table { border-spacing: 6px; background: #f1f5f9; }
      td { background: #bfdbfe; }
      .tall { background: #fde68a; vertical-align: top; }
      .mid { background: #bbf7d0; vertical-align: middle; }
      .bot { background: #fecaca; vertical-align: bottom; }
    `, `<table>
      <tr><td colspan="3">colspan 3 across the whole table</td></tr>
      <tr><td rowspan="3" class="tall">rowspan 3, top</td><td>b</td><td rowspan="2" class="mid">rowspan 2, middle</td></tr>
      <tr><td>c with a longer text</td></tr>
      <tr><td colspan="2" class="bot">colspan 2, bottom</td></tr>
    </table>`),
  },
  {
    id: "layout2-table-fixed", feature: "table", title: "table-layout: fixed, width 100%, percent column widths, caption at the bottom", width: 600, height: 260,
    node: page(tableCss + `
      table { table-layout: fixed; width: 100%; border-collapse: collapse; }
      td, th { border: 1px solid #64748b; overflow: hidden; }
      caption { caption-side: bottom; font-size: 13px; color: #64748b; padding-top: 4px; }
      .w20 { width: 20%; } .w50 { width: 50%; }
    `, `<table>
      <caption>fixed layout: the first row decides the column widths</caption>
      <tr><th class="w20">Key</th><th class="w50">Description</th><th>Value</th></tr>
      <tr><td>alpha</td><td>first entry with a description that wraps onto two lines</td><td class="num">1.5</td></tr>
      <tr><td>beta</td><td>second</td><td class="num">22</td></tr>
    </table>`),
  },
  {
    id: "layout2-table-percent", feature: "table", title: "auto layout with percent cell widths and a fixed-width column", width: 600, height: 220,
    node: page(tableCss + `
      table { width: 80%; border-collapse: separate; border-spacing: 0; border: 3px solid #0f766e; }
      td { border-bottom: 1px solid #99f6e4; }
      .a { width: 25%; background: #ccfbf1; } .b { width: 120px; background: #f0fdfa; }
    `, `<table>
      <tr><td class="a">25%</td><td class="b">120px</td><td>auto takes the rest</td></tr>
      <tr><td class="a">x</td><td class="b">y</td><td>z</td></tr>
    </table>`),
  },
];

// ------------------------------------------------------------------------------------------------ floats
const floats = [
  {
    id: "layout2-float-image", feature: "float", title: "image floated left with a paragraph beside it (text shorter than the float)", width: 600, height: 240, images: imgs(),
    node: page(`
      .card { display: block; background: #f8fafc; border: 1px solid #cbd5e1; padding: 16px; }
      .card img { float: left; width: 96px; height: 96px; margin-right: 16px; border-radius: 12px; }
      .card p { margin: 0; font-size: 18px; line-height: 1.4; }
    `, `<div class="card"><img src="img://avatar"><p>Jane Doe is a designer who loves typography, grids and small details.</p></div>`),
  },
  {
    id: "layout2-float-clear", feature: "float", title: "left and right floats, clear: both footer", width: 600, height: 260,
    node: page(`
      .l { float: left; width: 140px; height: 90px; background: #f97316; }
      .r { float: right; width: 180px; height: 130px; background: #8b5cf6; }
      .mid { display: block; font-size: 16px; }
      .foot { clear: both; display: block; height: 30px; background: #0ea5e9; }
    `, `<div class="l"></div><div class="r"></div><div class="mid">Between two floats.</div><div class="foot"></div>`, "display: block;"),
  },
  {
    id: "layout2-float-bfc", feature: "float", title: "flow-root / overflow:hidden containers grow to contain their floats", width: 600, height: 260,
    node: page(`
      .box { margin-bottom: 12px; padding: 8px; background: #e0f2fe; border: 2px solid #0369a1; }
      .fr { display: flow-root; } .oh { display: block; overflow: hidden; }
      .f { float: left; width: 80px; height: 60px; margin-right: 8px; background: #0284c7; }
      .g { float: right; width: 50px; height: 80px; background: #f43f5e; }
    `, `<div class="box fr"><div class="f"></div><div class="f"></div><div class="g"></div></div><div class="box oh"><div class="f"></div><div class="g"></div></div>`, "display: block;"),
  },
  {
    id: "layout2-float-wrap", feature: "float", title: "paragraph longer than the float (lines below the float widen again in the oracle)", width: 600, height: 260,
    node: page(`
      .f { float: left; width: 120px; height: 60px; margin: 0 12px 6px 0; background: #22c55e; }
      p { margin: 0; font-size: 16px; line-height: 1.5; }
    `, `<div class="f"></div><p>The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. How vexingly quick daft zebras jump! Sphinx of black quartz, judge my vow. The five boxing wizards jump quickly.</p>`, "display: block;"),
  },
];

// ------------------------------------------------------------------------------------------------ inline-block
const badgeCss = `
  .p { display: block; font-size: 18px; line-height: 1.6; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 9999px; background: #dbeafe; color: #1e40af; font-size: 14px; }
  .btn { display: inline-block; padding: 8px 16px; margin: 4px; border-radius: 8px; background: #111827; color: #fff; font-size: 16px; }
`;
const inlineBlocks = [
  {
    id: "layout2-ib-badges", feature: "inline-block", title: "inline-block badges inside a centred paragraph", width: 600, height: 200,
    node: page(badgeCss, `<div class="p" style="text-align: center">Released <span class="badge">v2.0</span> with <span class="badge">tables</span> and <span class="badge">floats</span> today</div>`),
  },
  {
    id: "layout2-ib-wrap", feature: "inline-block", title: "inline-block buttons wrapping in a narrow block", width: 600, height: 260,
    node: page(badgeCss + ".narrow { width: 320px; background: #f1f5f9; }", `<div class="p narrow"><span class="btn">Home</span><span class="btn">Products</span><span class="btn">Pricing</span><span class="btn">Documentation</span><span class="btn">Blog</span><span class="btn">Contact us</span></div>`),
  },
  {
    id: "layout2-ib-valign", feature: "inline-block", title: "vertical-align top / middle / bottom / baseline of inline boxes and images", width: 600, height: 220, images: imgs(),
    node: page(`
      .p { display: block; font-size: 20px; background: #f8fafc; }
      .b { display: inline-block; width: 40px; background: #fb7185; }
      .h1 { height: 70px; } .h2 { height: 30px; }
      img { width: 48px; height: 48px; }
    `, `<div class="p">x<span class="b h1" style="vertical-align: top"></span>top<span class="b h2" style="vertical-align: middle"></span>middle<span class="b h2" style="vertical-align: bottom"></span>bottom<img src="img://icon">base<img src="img://icon" style="vertical-align: middle">mid</div>`),
  },
  {
    id: "layout2-ib-json", feature: "inline-block", title: "JSON tree: block container with text, inline-block and inline-flex children", width: 600, height: 160,
    node: { type: "container", style: { display: "block", width: "100%", height: "100%", padding: 24, backgroundColor: "#fff", fontFamily: "Inter", fontSize: 20 }, children: [
      { type: "text", text: "Status: " },
      { type: "container", style: { display: "inline-block", padding: "4px 12px", backgroundColor: "#dcfce7", borderRadius: 6, color: "#166534" }, children: [{ type: "text", text: "online" }] },
      { type: "text", text: " since " },
      { type: "container", style: { display: "inline-flex", alignItems: "center", gap: 6, padding: "4px 12px", backgroundColor: "#fef3c7", borderRadius: 6 }, children: [
        { type: "container", style: { display: "block", width: 10, height: 10, borderRadius: 5, backgroundColor: "#d97706" } }, { type: "text", text: "09:41" }] },
    ] },
  },
];

// ------------------------------------------------------------------------------------------------ grid areas
const cell = (cls, label) => `<div class="${cls}">${label}</div>`;
const gridAreas = [
  {
    id: "layout2-grid-areas", feature: "grid-areas", title: "holy-grail layout with grid-template-areas", width: 600, height: 360,
    node: page(`
      .g { display: grid; height: 100%; gap: 8px; grid-template-columns: 120px 1fr 100px; grid-template-rows: 50px 1fr 40px;
           grid-template-areas: "head head head" "nav main side" "foot foot foot"; font-size: 16px; color: #fff; }
      .g > div { padding: 8px; border-radius: 6px; }
      .h { grid-area: head; background: #1e293b; } .n { grid-area: nav; background: #475569; } .m { grid-area: main; background: #2563eb; }
      .s { grid-area: side; background: #7c3aed; } .f { grid-area: foot; background: #0f766e; }
    `, `<div class="g">${cell("f", "footer")}${cell("m", "main")}${cell("h", "header")}${cell("s", "aside")}${cell("n", "nav")}</div>`),
  },
  {
    id: "layout2-grid-named-lines", feature: "grid-areas", title: "named lines in track lists ([full-start] [content-start] ...), implicit area from -start/-end lines, span name", width: 600, height: 300,
    node: page(`
      .g { display: grid; height: 100%; row-gap: 8px; grid-template-columns: [full-start] 40px [content-start] 1fr [mid] 1fr [content-end] 40px [full-end];
           grid-template-rows: [r] 60px [r] 60px [r] 60px [r]; background: #f1f5f9; font-size: 14px; }
      .g > div { padding: 6px; color: #fff; }
      .a { grid-column: full-start / full-end; grid-row: r; background: #be123c; }
      .b { grid-column: content-start / mid; grid-row: 2; background: #0369a1; }
      .c { grid-column: mid / span content-end; grid-row: 2 / 3; background: #15803d; }
      .d { grid-column: content; grid-row: 3; background: #a16207; }
    `, `<div class="g">${cell("a", "full")}${cell("b", "content-start / mid")}${cell("c", "mid / span content-end")}${cell("d", "content (implicit area)")}</div>`),
  },
  {
    id: "layout2-grid-areas-auto", feature: "grid-areas", title: "areas mixed with auto-placed items; areas define the explicit grid", width: 600, height: 300,
    node: page(`
      .g { display: grid; height: 100%; gap: 6px; grid-template-areas: "a a b" "a a c"; grid-auto-rows: 70px; grid-template-columns: repeat(3, 1fr); font-size: 14px; }
      .g > div { background: #94a3b8; padding: 4px; }
      .x { grid-area: a; background: #f59e0b; } .y { grid-area: c; background: #10b981; }
    `, `<div class="g">${cell("x", "area a")}${cell("", "1")}${cell("y", "area c")}${cell("", "2")}${cell("", "3")}${cell("", "4")}</div>`),
  },
];

export default [...tables, ...floats, ...inlineBlocks, ...gridAreas];
