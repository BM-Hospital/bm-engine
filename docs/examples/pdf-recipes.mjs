// Examples for docs/{en,vi}/pdf/recipes.md. Run: node docs/examples/run-all.mjs pdf-recipes
// Writes the PDFs the page links to (docs/public/pdf/examples/recipe-*.pdf); their previews come from
// `node bench/browser/pdf-previews.mjs recipe-invoice recipe-report recipe-ticket` (screenshots of Edge's PDF viewer).
import "./_lib.mjs";
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync as save } from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
const pageCount = (b) => (latin1(b).match(/\/Type\/Page[^s]/g) || []).length;
const mediaBoxes = (b) => [...latin1(b).matchAll(/\/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]/g)].map((m) => [Math.round(m[1]), Math.round(m[2])]);
/** Text of page n (1-based) as poppler's pdftotext extracts it; null when pdftotext is not installed. */
function pageText(bytes, n) {
  const file = path.join(os.tmpdir(), "bm-pdf-recipes-example.pdf");
  save(file, bytes);
  const r = spawnSync("pdftotext", ["-f", String(n), "-l", String(n), "-layout", file, "-"], { encoding: "utf8" });
  return r.error ? null : r.stdout.replace(/\s+/g, " ").trim();
}
const says = (bytes, n, s) => { const t = pageText(bytes, n); if (t !== null) assert.ok(t.includes(s), `page ${n} should contain "${s}": ${t}`); };
const outDir = path.join("docs", "public", "pdf", "examples");
mkdirSync(outDir, { recursive: true });

// #region setup
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer, PageNumber, TotalPages } from "bm-engine/pdf";

const pdf = new PdfRenderer(); // create once, reuse for every document
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
// #endregion

// #region invoice
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
// #endregion
save(path.join(outDir, "recipe-invoice.pdf"), invoice);
assert.equal(pageCount(invoice), 1);
assert.deepEqual(mediaBoxes(invoice), [[595, 842]]);
says(invoice, 1, "Total due");
says(invoice, 1, "Total due $4,519.00");
says(invoice, 1, "Page 1 of 1");

// #region report
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
// #endregion
save(path.join(outDir, "recipe-report.pdf"), report);
const reportPages = pageCount(report);
assert.ok(reportPages >= 3, `report pages ${reportPages}`);
for (let n = 1; n <= reportPages; n++) {
  says(report, n, "Store Region Units Revenue");
  says(report, n, `Page ${n} of ${reportPages}`);
}

// #region ticket
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
// #endregion
save(path.join(outDir, "recipe-ticket.pdf"), ticket);
assert.equal(pageCount(ticket), 1);
assert.equal(mediaBoxes(ticket)[0][0], 420); // 560 CSS px = 420 pt
says(ticket, 1, "Zig & WebAssembly Meetup");

for (const f of ["invoice.pdf", "report.pdf", "ticket.pdf"]) (await import("node:fs")).rmSync(f); // keep the repo clean
console.log("pdf-recipes: ok", { invoice: invoice.length, report: report.length, reportPages, ticket: ticket.length, ticketBox: mediaBoxes(ticket)[0] });
