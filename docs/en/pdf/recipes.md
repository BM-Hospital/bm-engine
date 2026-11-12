# PDF recipes

[English](recipes.md) · [Tiếng Việt](../../vi/pdf/recipes.md)

Three complete documents built with `bm-engine/pdf`: a one-page invoice with a numbered footer, a
multi-page report whose table header repeats on every page, and a ticket printed on a single page of
its own size. Each recipe is a section of `docs/examples/pdf-recipes.mjs` in the repository and was
executed by it; the script also checks the result (page count, page size, and the text of every page
as `pdftotext` extracts it). The generated files are linked below each recipe so you can open the real
PDF.

The images on this page are **previews**: screenshots of the generated PDF in Microsoft Edge's built-in
PDF viewer (headless Edge 157, `bench/browser/pdf-previews.mjs`), not output of bm-engine's image
renderer. The PDF itself is vector text and graphics.

- [Setup](#setup)
- [Invoice](#invoice)
- [Report with a repeated table header](#report-with-a-repeated-table-header)
- [Ticket on one page](#ticket-on-one-page)
- [Going further](#going-further)

## Setup

Create one `PdfRenderer` and register the fonts once; every recipe below reuses it. bm-engine ships no
font, and a document whose text needs a character no registered font has fails to render (see
[Fonts in PDF](fonts.md)).

<!-- @example pdf-recipes#setup -->
```js
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer, PageNumber, TotalPages } from "bm-engine/pdf";

const pdf = new PdfRenderer(); // create once, reuse for every document
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

## Invoice

An A4 invoice from HTML and a stylesheet. The table is an ordinary HTML table, the totals are its
`<tfoot>`, and the footer band carries the page number and the page count. Leaving `bottom` out of
`margin` keeps that side `"auto"`, which makes the bottom margin as tall as the footer needs
([Headers, footers and page counters](headers-footers.md#margins-and-bands)). `lang` and `metadata`
fill the document language and properties ([Metadata](links-metadata.md#metadata)).

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

![Preview of the invoice PDF: a red title "Invoice INV-2026-0042", billing details, a four-row table with totals ($4,519.00 due) and a footer "Page 1 of 1"](/img/guide/recipe-invoice.png)

*Preview: screenshot of the generated PDF in Microsoft Edge's PDF viewer.* The file:
[recipe-invoice.pdf](/pdf/examples/recipe-invoice.pdf) (one A4 page, about 25 KiB with the two subset
Inter fonts). `pdftotext` extracts "Total due $4,519.00" and "Page 1 of 1" from it.

Longer invoices need nothing extra: the rows flow onto the next page and the footer counts the pages.
Put `break-inside: avoid` on a block that must not be cut, such as the totals or a payment slip
([Pagination](pagination.md#keeping-things-together)).

## Report with a repeated table header

A table longer than a page continues on the next one, and its `<thead>` is drawn again at the top of
every page (a `<tfoot>` would repeat at the bottom). This report has 70 rows on A5 pages; the footer is
a node tree built with `PageNumber()` and `TotalPages()`, and `outline: true` turns the `h1` into a
bookmark ([Bookmarks](links-metadata.md#bookmarks)).

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

![Preview of the first two pages of the report PDF: the dark table header row appears at the top of both pages, and the footers read "Page 1 of 4" and "Page 2 of 4"](/img/guide/recipe-report.png)

*Preview: the first two of four pages, screenshot of the generated PDF in Microsoft Edge's PDF viewer.*
The file: [recipe-report.pdf](/pdf/examples/recipe-report.pdf) (four A5 pages, about 40 KiB). The
example checks with `pdftotext` that every page starts with the header row "Store Region Units
Revenue" and ends with "Page *n* of 4". More on how tables break: [Pagination](pagination.md#tables).

## Ticket on one page

`viewport` renders the whole document on one page of the given width, with no margins, bands or page
breaks; without a `height` the page is as tall as the content. That is the form for tickets, badges and
labels. The source here is a node tree, the same format the image renderer takes.

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

![Preview of the ticket PDF: a pink card with a red border, "ADMIT ONE", "Zig & WebAssembly Meetup", date, seat, and a stub with the number "No. 0815" rotated by 90 degrees behind a dashed line](/img/guide/recipe-ticket.png)

*Preview: screenshot of the generated PDF in Microsoft Edge's PDF viewer.* The file:
[recipe-ticket.pdf](/pdf/examples/recipe-ticket.pdf) (one page of 420 x 111 pt: 560 CSS px wide, as tall
as the card; about 19 KiB).

## Going further

- Serve these documents from an HTTP endpoint: [Serving PDFs from a framework](frameworks.md).
- Page sizes, margins and `@page` rules: [Page size and viewport](page-size-and-viewport.md) and
  [Pagination](pagination.md#page-rules).
- Archival or accessible invoices (PDF/A-3 with an attached XML file, PDF/UA):
  [Accessibility and archival](accessibility.md) and [Attachments](links-metadata.md#attachments).
- Recipes for image output (OG cards, caching, worker pools): [Image recipes](../image/recipes.md).
