# Tables and floats

[English](tables.md) · [Tiếng Việt](../../vi/image/tables.md)

bm-render lays out tables with a CSS table layout algorithm and supports
CSS floats with text flowing around them. Both are optional features of the **standard** and **full**
profiles (`features.tables`, `features.floats`); on `core` a table lays out as plain blocks and `float`
is ignored. This page shows HTML tables and the equivalent node trees, column sizing, spans, borders,
captions and alignment, then floats and `clear`, and ends with what is approximate. All examples are
sections of `docs/examples/tables.mjs` in the repository and were rendered by it.

- [Setup](#setup)
- [An HTML table](#an-html-table)
- [Tables from node trees](#tables-from-node-trees)
- [Row and column spans, captions](#row-and-column-spans-captions)
- [Borders: separate and collapse](#borders-separate-and-collapse)
- [Column widths and table-layout](#column-widths-and-table-layout)
- [Vertical alignment in cells](#vertical-alignment-in-cells)
- [Other table properties](#other-table-properties)
- [Floats](#floats)
- [On the core profile](#on-the-core-profile)
- [What is approximate](#what-is-approximate)

## Setup

Tables need `standard` or `full`, so the examples import `bm-render/standard`:

<!-- @example tables#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render/standard"; // tables and floats need standard or full

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

## An HTML table

The easiest way to build a table is an HTML source. The elements `table`, `caption`, `colgroup`,
`col`, `thead`, `tbody`, `tfoot`, `tr`, `td` and `th` get Chromium's user-agent styles (`th` is bold
and centred, cells have 1 px padding, `td` is vertically centred, a table has `border-spacing: 2px`),
and a `style` block can restyle them with any selector, including `:nth-child()` for zebra rows. A
`tbody` is implied when you write `tr` directly inside `table`.

<!-- @example tables#html-table -->
```js
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
```

![An invoice table with a grey header, zebra rows, right-aligned numbers and a bold total row](/img/guide/tables-html-table.png)

Things to notice:

- `width: 100%` on the table makes it fill its container; without a width a table shrinks to fit its
  content, like in a browser.
- `style="width:60px"` on a header cell sets the width of that column; the remaining space goes to the
  columns without a width.
- `colspan="2"` in the footer row spans the first two columns.
- Text inherits from the `div` (`font-family: Inter`): HTML input has no default font, so set
  `font-family` somewhere (see [Fonts](./fonts.md)).

## Tables from node trees

Without HTML, set `display: "table"`, `"table-row"` and `"table-cell"` (also `"table-row-group"`,
`"table-header-group"`, `"table-footer-group"`, `"table-column"`, `"table-column-group"`,
`"table-caption"` and `"inline-table"`) on containers. Missing wrappers are generated as in CSS, so
`table` → `table-row` → `table-cell` is enough:

<!-- @example tables#node-table -->
```js
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
```

![A three-column table built from containers with display table, table-row and table-cell](/img/guide/tables-node-table.png)

::: tip colspan and rowspan in node trees
Spans are HTML attributes, not CSS properties. In a node tree set them through `attributes` together
with the matching `tagName`, for example
`{ type: "container", tagName: "td", attributes: { colspan: "2" }, ... }`, or use an HTML source,
which is simpler.
:::

## Row and column spans, captions

`rowspan` and `colspan` work on `td` and `th`. A `caption` is laid out above the table (or below with
`caption-side: bottom`) and is as wide as the table. `br` breaks a line inside a cell.

<!-- @example tables#spans -->
```js
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
```

![A timetable with a two-row workshop cell, a two-column planning cell and a three-column lunch row](/img/guide/tables-spans.png)

## Borders: separate and collapse

By default borders are *separate*: every cell draws its own border box and `border-spacing` (default
2 px from the user-agent style in HTML, 0 for node trees) leaves gaps between them. `border-spacing`
takes one value or a horizontal and a vertical value. With `border-collapse: collapse` neighbouring
cells share borders; when two borders meet, the wider one wins (the 3 px blue border of cell A below),
following Chromium's conflict resolution.

<!-- @example tables#collapse -->
```js
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
```

![The same 2 × 2 table with separate borders, with border-spacing 8px 4px and with collapsed borders](/img/guide/tables-collapse.png)

Row, row-group, column and column-group backgrounds paint behind their cells (cell D's yellow is a cell
background; the first column in the next example is coloured by a `col`).

## Column widths and table-layout

With the default `table-layout: auto`, column widths come from the content: each column gets at least
its minimum content width (its longest word) and the rest of the table width is shared out according
to the content's preferred widths. A width on a cell or on a `col` is a request, but never below the
minimum content width.

With `table-layout: fixed` (which needs a table `width`), widths come from the `col` elements and the
first row only, the content is ignored, and content that does not fit overflows its cell:

<!-- @example tables#layout-fixed -->
```js
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
```

![Auto layout widens the first column for a long word; fixed layout keeps it at 80 px and the word overflows](/img/guide/tables-layout-fixed.png)

In the auto table, the first column is wider than its requested 80 px because
"supercalifragilistic" cannot break; in the fixed table it stays at 80 px and the word spills into
the next cell, exactly as Chromium does. Percentages (`width: 30%`) are relative to the table width.

## Vertical alignment in cells

`vertical-align` on a cell places its content: `top`, `middle` (the default for `td` / `th` in HTML),
`bottom` and `baseline` (the first lines of all baseline cells in a row line up):

<!-- @example tables#valign -->
```js
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
```

![Five cells aligned top, middle, bottom and two baseline cells with different font sizes](/img/guide/tables-valign.png)

## Other table properties

These were checked with small probe renders while writing this page:

| Property / feature | Behaviour |
|:--|:--|
| `caption-side: bottom` | caption below the table |
| `empty-cells: hide` | with separate borders, cells with no content draw no border or background |
| `visibility: collapse` on a row | the row and its space are removed |
| `thead` / `tfoot` | header groups are placed first and footer groups last, whatever the source order |
| `display: inline-table` | the table sits on a line like an inline-block |
| `direction: rtl` / `dir="rtl"` on a table | the first column is on the right ([below](#rtl-tables)) |

## RTL tables

`dir="rtl"` on a `<table>` (or `direction: "rtl"` on a `display: "table"` node) mirrors the column order,
as in browsers:

<!-- @example tables#rtl -->
```js
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
```

![A table whose first column is on the right: 3rd column, 2nd column, 1st column from left to right](/img/guide/tables-rtl.png)

## Floats

`float: left | right` takes a box out of the normal flow and lets the following inline content wrap
around it; `clear: left | right | both` moves a block below earlier floats. The float's container must be
a block container (`display: "block"`), because flex and grid items never float. Line boxes beside a
float are shortened and lines below it use the full width again:

<!-- @example tables#float -->
```js
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
```

![A round picture floated left with a paragraph wrapping around it and a cleared box below](/img/guide/tables-float.png)

Floats on both sides, written as HTML:

<!-- @example tables#float-right -->
```js
const floatRight = renderer.renderSync(
  `<div style="padding:16px;background:white;height:100%;font-family:Inter;font-size:15px;line-height:1.5">
     <div style="float:right;width:120px;height:70px;margin:0 0 6px 12px;background:#a7f3d0;border-radius:8px"></div>
     <div style="float:left;width:50px;height:50px;margin:0 10px 0 0;background:#bfdbfe;border-radius:25px"></div>
     Two floats on opposite sides: the paragraph flows in the space between them, then re-widens once both
     floats have ended. Floats inside HTML input behave the same as in node trees.
   </div>`,
  { width: 420, height: 160 },
);
```

![A paragraph flowing between a float on the left and one on the right](/img/guide/tables-float-right.png)

In most card layouts flexbox is the better tool; floats are useful for exactly this text-wrapping
effect (an avatar or a pull quote inside an article), and for rendering existing HTML that uses them.

## On the core profile

`core` has no table or float code. `display: table*` lays out like `display: block` and `float` /
`clear` are ignored, without an error. This is easy to observe with `measure()`:

<!-- @example tables#core-fallback -->
```js
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
```

If your inputs may contain tables (for example user-provided HTML, which needs `standard` anyway), use
`standard` or `full` and check `features.tables` / `features.floats` at startup.

## What is approximate

See [CSS support](css-support.md#layout) for the available table and float features and their minimum profile.

- Paint order of floats follows CSS 2.1 Appendix E in PNG / JPEG / WebP / raw output: a float paints
  after the backgrounds of in-flow blocks and before in-flow inline content (text), so text that
  overlaps a float (for example with negative margins) is drawn on top. `renderSvg` still paints floats
  after all in-flow content.
- `line-clamp` and `-webkit-box` next to floats.
- `text-wrap: balance / pretty` beside floats works for a single float at the start of the paragraph;
  other arrangements fall back to greedy wrapping.
- Tables are not split across pages (there is no paged output).

See also: [Styles → layout modes](./styles.md), [HTML and Tailwind](./html-and-tailwind.md).
