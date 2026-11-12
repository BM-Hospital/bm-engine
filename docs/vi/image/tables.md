# Bảng và float

[English](../../en/image/tables.md) · [Tiếng Việt](tables.md)

bm-engine dàn trang bảng bằng bản port thuật toán bảng của takumi (tức là của Chromium) và hỗ trợ float
của CSS với chữ chảy vòng quanh. Cả hai là tính năng tùy chọn của profile **standard** và **full**
(`features.tables`, `features.floats`); trên `core`, bảng được dàn như các block thường và `float` bị bỏ
qua. Trang này trình bày bảng HTML và cây node tương đương, cách tính chiều rộng cột, span, viền, caption
và căn chỉnh, sau đó là float và `clear`, và kết thúc bằng những chỗ còn gần đúng. Mọi ví dụ là các đoạn
của `docs/examples/tables.mjs` trong repository và hình là do chính nó render.

- [Chuẩn bị](#chuẩn-bị)
- [Một bảng HTML](#một-bảng-html)
- [Bảng từ cây node](#bảng-từ-cây-node)
- [Gộp hàng, gộp cột, caption](#gộp-hàng-gộp-cột-caption)
- [Viền: separate và collapse](#viền-separate-và-collapse)
- [Chiều rộng cột và table-layout](#chiều-rộng-cột-và-table-layout)
- [Căn dọc trong ô](#căn-dọc-trong-ô)
- [Các thuộc tính bảng khác](#các-thuộc-tính-bảng-khác)
- [Float](#float)
- [Trên profile core](#trên-profile-core)
- [Những gì còn gần đúng](#những-gì-còn-gần-đúng)

## Chuẩn bị

Bảng cần `standard` hoặc `full`, nên các ví dụ import `bm-engine/standard`:

<!-- @example tables#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine/standard"; // tables and floats need standard or full

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

## Một bảng HTML

Cách dễ nhất để dựng bảng là dùng source HTML. Các phần tử `table`, `caption`, `colgroup`, `col`,
`thead`, `tbody`, `tfoot`, `tr`, `td` và `th` nhận style user-agent của Chromium (`th` in đậm và căn
giữa, ô có padding 1 px, `td` căn giữa theo chiều dọc, bảng có `border-spacing: 2px`), và một khối
`style` có thể style lại chúng bằng bất kỳ selector nào, kể cả `:nth-child()` để tô hàng xen kẽ. Khi bạn
viết `tr` trực tiếp trong `table`, một `tbody` được tự thêm vào.

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

![Bảng hóa đơn có hàng tiêu đề xám, hàng xen kẽ màu, số căn phải và hàng tổng in đậm](/img/guide/tables-html-table.png)

Điểm cần chú ý:

- `width: 100%` trên bảng làm nó lấp đầy container; không có chiều rộng thì bảng co lại vừa nội dung,
  như trong trình duyệt.
- `style="width:60px"` trên ô tiêu đề đặt chiều rộng cho cột đó; phần còn lại chia cho các cột không có
  chiều rộng.
- `colspan="2"` ở hàng footer gộp hai cột đầu.
- Chữ kế thừa từ `div` (`font-family: Inter`): đầu vào HTML không có font mặc định, nên hãy đặt
  `font-family` ở đâu đó (xem [Font](./fonts.md)).

## Bảng từ cây node

Không dùng HTML thì đặt `display: "table"`, `"table-row"` và `"table-cell"` (và `"table-row-group"`,
`"table-header-group"`, `"table-footer-group"`, `"table-column"`, `"table-column-group"`,
`"table-caption"`, `"inline-table"`) cho các container. Các lớp bọc bị thiếu được tự sinh như trong CSS,
nên `table` → `table-row` → `table-cell` là đủ:

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

![Bảng ba cột dựng từ các container với display table, table-row và table-cell](/img/guide/tables-node-table.png)

::: tip colspan và rowspan trong cây node
Span là thuộc tính HTML, không phải thuộc tính CSS. Trong cây node, hãy đặt chúng qua `attributes` cùng
với `tagName` tương ứng, ví dụ `{ type: "container", tagName: "td", attributes: { colspan: "2" }, ... }`,
hoặc dùng source HTML cho đơn giản.
:::

## Gộp hàng, gộp cột, caption

`rowspan` và `colspan` dùng được trên `td` và `th`. `caption` được đặt phía trên bảng (hoặc phía dưới với
`caption-side: bottom`) và rộng bằng bảng. `br` xuống dòng bên trong ô.

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

![Thời khóa biểu với ô workshop chiếm hai hàng, ô planning chiếm hai cột và hàng ăn trưa chiếm ba cột](/img/guide/tables-spans.png)

## Viền: separate và collapse

Mặc định viền ở chế độ *separate*: mỗi ô vẽ khung viền riêng và `border-spacing` (mặc định 2 px từ style
user-agent trong HTML, 0 với cây node) để lại khe giữa các ô. `border-spacing` nhận một giá trị, hoặc một
giá trị ngang và một giá trị dọc. Với `border-collapse: collapse`, các ô kề nhau dùng chung viền; khi hai
viền gặp nhau, viền dày hơn thắng (viền xanh 3 px của ô A bên dưới), theo cách giải quyết xung đột của
Chromium.

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

![Cùng một bảng 2 × 2 với viền separate, với border-spacing 8px 4px và với viền collapse](/img/guide/tables-collapse.png)

Nền của hàng, nhóm hàng, cột và nhóm cột được vẽ phía sau các ô của chúng (màu vàng của ô D là nền ô;
cột đầu trong ví dụ tiếp theo được tô bởi một `col`).

## Chiều rộng cột và table-layout

Với `table-layout: auto` mặc định, chiều rộng cột lấy từ nội dung: mỗi cột được ít nhất chiều rộng nội
dung tối thiểu (từ dài nhất) và phần còn lại của bảng được chia theo chiều rộng mong muốn của nội dung.
Chiều rộng đặt trên ô hay trên `col` chỉ là yêu cầu, và không bao giờ nhỏ hơn chiều rộng nội dung tối
thiểu.

Với `table-layout: fixed` (cần bảng có `width`), chiều rộng chỉ lấy từ các phần tử `col` và hàng đầu
tiên, nội dung bị bỏ qua, và nội dung không vừa sẽ tràn ra khỏi ô:

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

![Layout auto nới cột đầu cho một từ dài; layout fixed giữ cột 80 px và từ bị tràn](/img/guide/tables-layout-fixed.png)

Ở bảng auto, cột đầu rộng hơn 80 px được yêu cầu vì "supercalifragilistic" không ngắt được; ở bảng fixed
nó giữ 80 px và từ đó tràn sang ô bên cạnh, đúng như Chromium. Phần trăm (`width: 30%`) tính theo chiều
rộng bảng.

## Căn dọc trong ô

`vertical-align` trên ô đặt vị trí nội dung: `top`, `middle` (mặc định cho `td` / `th` trong HTML),
`bottom` và `baseline` (dòng đầu tiên của mọi ô baseline trong một hàng thẳng hàng với nhau):

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

![Năm ô căn top, middle, bottom và hai ô baseline có cỡ chữ khác nhau](/img/guide/tables-valign.png)

## Các thuộc tính bảng khác

Những mục này đã được kiểm tra bằng các lần render thử nhỏ khi viết trang này:

| Thuộc tính / tính năng | Hành vi |
|:--|:--|
| `caption-side: bottom` | caption nằm dưới bảng |
| `empty-cells: hide` | với viền separate, ô không có nội dung không vẽ viền và nền |
| `visibility: collapse` trên một hàng | hàng đó và khoảng trống của nó bị bỏ đi |
| `thead` / `tfoot` | nhóm header luôn đặt đầu và nhóm footer luôn đặt cuối, bất kể thứ tự trong source |
| `display: inline-table` | bảng nằm trên dòng giống một inline-block |
| `direction: rtl` / `dir="rtl"` trên bảng | cột đầu nằm bên phải ([bên dưới](#rtl-tables)) |

## Bảng RTL {#rtl-tables}

`dir="rtl"` trên `<table>` (hoặc `direction: "rtl"` trên node `display: "table"`) đảo thứ tự cột, như
trình duyệt và takumi:

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

![Một bảng có cột đầu ở bên phải: 3rd column, 2nd column, 1st column từ trái sang phải](/img/guide/tables-rtl.png)

## Float

`float: left | right` đưa một box ra khỏi luồng bình thường và cho nội dung inline phía sau chảy vòng
quanh nó; `clear: left | right | both` đẩy một block xuống dưới các float trước đó. Container chứa float
phải là block container (`display: "block"`), vì item của flex và grid không bao giờ float. Các dòng bên
cạnh float được rút ngắn và các dòng bên dưới lại dùng hết chiều rộng:

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

![Ảnh tròn float trái, đoạn văn chảy vòng quanh và một box đã clear ở bên dưới](/img/guide/tables-float.png)

Float ở cả hai bên, viết bằng HTML:

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

![Đoạn văn chảy giữa một float bên trái và một float bên phải](/img/guide/tables-float-right.png)

Với đa số layout dạng thẻ, flexbox là công cụ tốt hơn; float hữu ích đúng cho hiệu ứng chữ chảy vòng
này (avatar hay trích dẫn nổi bật trong bài viết), và khi render HTML có sẵn dùng float.

## Trên profile core

`core` không có mã cho bảng và float. `display: table*` được dàn như `display: block`, còn `float` /
`clear` bị bỏ qua, không báo lỗi. Có thể thấy dễ dàng bằng `measure()`:

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

Nếu đầu vào có thể chứa bảng (ví dụ HTML do người dùng cung cấp, vốn đã cần `standard`), hãy dùng
`standard` hoặc `full` và kiểm tra `features.tables` / `features.floats` lúc khởi động.

## Những gì còn gần đúng

Theo [Hỗ trợ CSS](./css-support.md#layout) và benchmark: bảng tương đương takumi trên cả 8 fixture bảng
và 339 trên 352 trường hợp oracle layout; float đạt 138 / 138 trường hợp oracle. Các hạn chế đã biết trong
0.1.0:

- Thứ tự vẽ float theo CSS 2.1 Phụ lục E trong đầu ra PNG / JPEG / WebP / raw: float được vẽ sau nền
  của các block trong luồng và trước nội dung inline trong luồng (chữ), nên chữ chồng lên float (ví dụ
  khi dùng margin âm) được vẽ đè lên trên. `renderSvg` vẫn vẽ float sau toàn bộ nội dung trong luồng.
- `line-clamp` và `-webkit-box` cạnh float.
- `text-wrap: balance / pretty` cạnh float dùng được với một float duy nhất ở đầu đoạn; các cách sắp
  xếp khác quay về cách ngắt dòng tham lam.
- Bảng không được chia qua nhiều trang (không có đầu ra phân trang).

Xem thêm: [Style → các chế độ layout](./styles.md), [HTML và Tailwind](./html-and-tailwind.md).
