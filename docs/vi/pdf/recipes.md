# Công thức PDF

[English](../../en/pdf/recipes.md) · [Tiếng Việt](recipes.md)

Ba tài liệu hoàn chỉnh dựng bằng `bm-engine/pdf`: một hoá đơn một trang có footer đánh số trang, một báo
cáo nhiều trang có phần đầu bảng lặp lại ở mọi trang, và một tấm vé in trên đúng một trang có kích thước
của chính nó. Mỗi công thức là một đoạn của `docs/examples/pdf-recipes.mjs` trong repository và đã được
chính file đó chạy; script còn kiểm tra kết quả (số trang, khổ trang và chữ của từng trang do `pdftotext`
trích ra). Bên dưới mỗi công thức có liên kết tới tệp đã tạo để bạn mở PDF thật.

Các hình trên trang này là **ảnh xem trước**: ảnh chụp PDF đã tạo trong trình xem PDF có sẵn của
Microsoft Edge (Edge 157 headless, `bench/browser/pdf-previews.mjs`), không phải đầu ra của bộ render ảnh
của bm-engine. Bản thân PDF là chữ và đồ hoạ vector.

- [Chuẩn bị](#chuẩn-bị)
- [Hoá đơn](#hoá-đơn)
- [Báo cáo có phần đầu bảng lặp lại](#báo-cáo-có-phần-đầu-bảng-lặp-lại)
- [Vé trên một trang](#vé-trên-một-trang)
- [Đi xa hơn](#đi-xa-hơn)

## Chuẩn bị

Tạo một `PdfRenderer` và đăng ký font một lần; mọi công thức bên dưới dùng lại nó. bm-engine không kèm
font nào, và tài liệu có chữ cần một ký tự mà không font đã đăng ký nào có sẽ render thất bại (xem
[Font trong PDF](fonts.md)).

<!-- @example pdf-recipes#setup -->
```js
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer, PageNumber, TotalPages } from "bm-engine/pdf";

const pdf = new PdfRenderer(); // create once, reuse for every document
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

## Hoá đơn

Một hoá đơn khổ A4 dựng từ HTML và một stylesheet. Bảng là bảng HTML bình thường, phần tổng tiền nằm
trong `<tfoot>`, còn băng footer mang số trang và tổng số trang. Bỏ `bottom` khỏi `margin` thì cạnh đó
giữ giá trị `"auto"`, nhờ vậy lề dưới cao vừa đủ cho footer
([Header, footer và bộ đếm trang](headers-footers.md#lề-và-band)). `lang` và `metadata` điền ngôn ngữ và
thuộc tính của tài liệu ([Metadata](links-metadata.md#metadata)).

<!-- @example pdf-recipes#invoice -->
```js
const items = [
  ["Design system audit", 1, 1200],
  ["Component library (24 components)", 24, 85],
  ["Accessibility review", 1, 640],
  ["Hosting, 12 months", 12, 19],
];
const money = (n) => n.toLocaleString("en-US", { style: "currency", currency: "USD" });
const subtotal = items.reduce((s, [, qty, price]) => s + qty * price, 0);
const tax = Math.round(subtotal * 0.1);

const invoice = await pdf.render(
  `<style>
     body { font-family: Inter; font-size: 12px; color: #0f172a; }
     h1 { font-size: 26px; margin: 0; color: #be123c; }
     .meta { display: flex; justify-content: space-between; margin: 24px 0; }
     table { width: 100%; border-collapse: collapse; }
     th { text-align: left; border-bottom: 2px solid #0f172a; padding: 6px 4px; }
     td { border-bottom: 1px solid #e2e8f0; padding: 6px 4px; }
     .num { text-align: right; }
     .total td { border: none; font-weight: 700; }
   </style>
   <h1>Invoice INV-2026-0042</h1>
   <div class="meta">
     <div><b>Billed to</b><br>Northwind Traders<br>12 Harbour Street<br>Seattle, WA</div>
     <div class="num"><b>Issued</b> 2026-11-12<br><b>Due</b> 2026-12-12</div>
   </div>
   <table>
     <thead><tr><th>Description</th><th class="num">Qty</th><th class="num">Unit price</th><th class="num">Amount</th></tr></thead>
     <tbody>
       ${items.map(([d, q, p]) => `<tr><td>${d}</td><td class="num">${q}</td><td class="num">${money(p)}</td><td class="num">${money(q * p)}</td></tr>`).join("")}
     </tbody>
     <tfoot>
       <tr class="total"><td colspan="3" class="num">Subtotal</td><td class="num">${money(subtotal)}</td></tr>
       <tr class="total"><td colspan="3" class="num">Tax 10%</td><td class="num">${money(tax)}</td></tr>
       <tr class="total"><td colspan="3" class="num">Total due</td><td class="num">${money(subtotal + tax)}</td></tr>
     </tfoot>
   </table>`,
  {
    size: "a4",
    margin: { top: 48, right: 48, left: 48 }, // bottom: "auto", sized to the footer
    footer: `<div style="font: 10px Inter; color: #64748b; display: flex; justify-content: space-between; padding: 0 48px">
      <span>ACME Studio · billing@acme.example</span>
      <span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span>
    </div>`,
    lang: "en",
    metadata: { title: "Invoice INV-2026-0042", authors: ["ACME Studio"], creationDate: "2026-11-12" },
  },
);
writeFileSync("invoice.pdf", invoice);
```

![Ảnh xem trước PDF hoá đơn: tiêu đề đỏ "Invoice INV-2026-0042", thông tin thanh toán, bảng bốn dòng kèm tổng tiền ($4,519.00 phải trả) và footer "Page 1 of 1"](/img/guide/recipe-invoice.png)

*Ảnh xem trước: ảnh chụp PDF đã tạo trong trình xem PDF của Microsoft Edge.* Tệp:
[recipe-invoice.pdf](/pdf/examples/recipe-invoice.pdf) (một trang A4, khoảng 25 KiB cùng hai font Inter
đã subset). `pdftotext` trích được "Total due $4,519.00" và "Page 1 of 1" từ tệp này.

Hoá đơn dài hơn không cần thêm gì: các dòng chảy sang trang sau và footer tự đếm trang. Đặt
`break-inside: avoid` cho khối không được cắt đôi, chẳng hạn phần tổng tiền hay phiếu thanh toán
([Phân trang](pagination.md#giữ-các-phần-đi-cùng-nhau)).

## Báo cáo có phần đầu bảng lặp lại

Bảng dài hơn một trang sẽ tiếp tục sang trang sau, và `<thead>` của nó được vẽ lại ở đầu mỗi trang (còn
`<tfoot>` thì lặp lại ở cuối trang). Báo cáo này có 70 dòng trên các trang A5; footer là một cây node dựng
bằng `PageNumber()` và `TotalPages()`, và `outline: true` biến `h1` thành một bookmark
([Bookmark](links-metadata.md#bookmark)).

<!-- @example pdf-recipes#report -->
```js
const rows = Array.from({ length: 70 }, (_, k) => {
  const units = 40 + ((k * 37) % 160);
  return `<tr><td>Store ${String(k + 1).padStart(3, "0")}</td><td>${["North", "South", "East", "West"][k % 4]}</td>
    <td class="num">${units}</td><td class="num">${(units * 12.5).toFixed(2)}</td></tr>`;
}).join("");

const report = await pdf.render(
  `<style>
     body { font-family: Inter; font-size: 11px; color: #0f172a; }
     h1 { font-size: 22px; margin: 0 0 4px; }
     p { margin: 0 0 16px; color: #475569; }
     table { width: 100%; border-collapse: collapse; }
     thead th { background: #0f172a; color: white; text-align: left; padding: 5px 6px; }
     td { padding: 4px 6px; border-bottom: 1px solid #e2e8f0; }
     tbody tr:nth-child(even) td { background: #f8fafc; }
     .num { text-align: right; }
   </style>
   <h1>Quarterly sales by store</h1>
   <p>Q3 2026 · all regions</p>
   <table>
     <thead><tr><th>Store</th><th>Region</th><th class="num">Units</th><th class="num">Revenue</th></tr></thead>
     <tbody>${rows}</tbody>
   </table>`,
  {
    size: "a5",
    margin: { top: 36, right: 36, left: 36 },
    footer: {
      type: "container",
      style: { display: "flex", justifyContent: "center", columnGap: 4, fontFamily: "Inter", fontSize: 9, color: "#64748b" },
      children: [{ type: "text", text: "Page" }, PageNumber(), { type: "text", text: "of" }, TotalPages()],
    },
    outline: true,
  },
);
writeFileSync("report.pdf", report);
// the <thead> row is drawn again at the top of every page the table continues on
```

![Ảnh xem trước hai trang đầu của PDF báo cáo: hàng tiêu đề bảng màu tối xuất hiện ở đầu cả hai trang, footer ghi "Page 1 of 4" và "Page 2 of 4"](/img/guide/recipe-report.png)

*Ảnh xem trước: hai trên bốn trang đầu tiên, ảnh chụp PDF đã tạo trong trình xem PDF của Microsoft Edge.*
Tệp: [recipe-report.pdf](/pdf/examples/recipe-report.pdf) (bốn trang A5, khoảng 40 KiB). Ví dụ dùng
`pdftotext` để kiểm tra rằng trang nào cũng bắt đầu bằng hàng tiêu đề "Store Region Units Revenue" và kết
thúc bằng "Page *n* of 4". Bảng được ngắt trang thế nào: [Phân trang](pagination.md#bảng).

## Vé trên một trang

`viewport` render toàn bộ tài liệu lên một trang có chiều rộng cho trước, không lề, không băng, không ngắt
trang; không có `height` thì trang cao đúng bằng nội dung. Đây là cách làm vé, thẻ đeo và nhãn. Nguồn ở đây
là một cây node, cùng định dạng mà bộ render ảnh nhận.

<!-- @example pdf-recipes#ticket -->
```js
const ticket = await pdf.render(
  {
    type: "container",
    style: {
      display: "flex", width: "100%", fontFamily: "Inter", color: "#0f172a",
      backgroundColor: "#fff1f2", border: "2px solid #be123c", borderRadius: 16,
    },
    children: [
      {
        type: "container",
        style: { display: "flex", flexDirection: "column", gap: 6, padding: 24, flexGrow: 1 },
        children: [
          { type: "text", text: "ADMIT ONE", style: { fontSize: 12, fontWeight: 700, color: "#be123c", letterSpacing: 2 } },
          { type: "text", text: "Zig & WebAssembly Meetup", style: { fontSize: 24, fontWeight: 700 } },
          { type: "text", text: "Fri 4 Dec 2026 · 18:30 · Hall B", style: { fontSize: 14 } },
          { type: "text", text: "Ada Lovelace · Seat C-12", style: { fontSize: 14, color: "#475569" } },
        ],
      },
      {
        type: "container",
        style: {
          display: "flex", alignItems: "center", justifyContent: "center", width: 120,
          borderLeft: "2px dashed #be123c",
        },
        children: [{ type: "text", text: "No. 0815", style: { fontSize: 16, fontWeight: 700, transform: "rotate(-90deg)" } }],
      },
    ],
  },
  { viewport: { width: 560 } }, // one page, 560 px wide, as tall as the ticket
);
writeFileSync("ticket.pdf", ticket);
```

![Ảnh xem trước PDF vé: một thẻ màu hồng viền đỏ, "ADMIT ONE", "Zig & WebAssembly Meetup", ngày giờ, chỗ ngồi, và phần cuống có số "No. 0815" xoay 90 độ sau một đường nét đứt](/img/guide/recipe-ticket.png)

*Ảnh xem trước: ảnh chụp PDF đã tạo trong trình xem PDF của Microsoft Edge.* Tệp:
[recipe-ticket.pdf](/pdf/examples/recipe-ticket.pdf) (một trang 420 x 111 pt: rộng 560 CSS px, cao bằng
tấm thẻ; khoảng 19 KiB).

## Đi xa hơn

- Trả các tài liệu này từ một HTTP endpoint: [Trả PDF từ framework](frameworks.md).
- Khổ giấy, lề và quy tắc `@page`: [Khổ giấy và viewport](page-size-and-viewport.md) và
  [Phân trang](pagination.md#quy-tắc-trang).
- Hoá đơn lưu trữ hoặc dễ truy cập (PDF/A-3 kèm tệp XML đính kèm, PDF/UA):
  [Khả năng truy cập và lưu trữ](accessibility.md) và [Tệp đính kèm](links-metadata.md#tệp-đính-kèm).
- Công thức cho đầu ra ảnh (thẻ OG, cache, worker pool): [Công thức cho ảnh](../image/recipes.md).
