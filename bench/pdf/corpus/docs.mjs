// Documents modelled on the PDF guide (docs/en/pdf/*.md, docs/examples/pdf*.mjs) plus the scaled stress
// documents. Every input uses only what both bm-engine/pdf and takumi-pdf accept with the same meaning: HTML or
// node trees, the same font bytes registered under the same family / weight / style, images passed as bytes
// (`images`), the takumi-pdf option names (size, margin, header, footer, pages, outline, metadata, lang, pdfa,
// tagged, attachments, viewport).
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";
import { ROOT } from "../lib/tools.mjs";

const F = path.join(ROOT, "assets", "fonts");
const RF = path.join(ROOT, "ref", "takumi", "assets", "fonts");
const font = (name, file, weight = 400, style = "normal", dir = F) => ({ name, path: path.join(dir, file), weight, style });
export const INTER = [font("Inter", "Inter-Regular.ttf"), font("Inter", "Inter-Bold.ttf", 700), font("Inter", "Inter-Italic.ttf", 400, "italic")];
const NOTO_TC = font("Noto Sans TC", "noto-sans/NotoSansTC-VariableFont_wght.woff2", 400, "normal", RF);
const ARABIC = font("Scheherazade New", "sil/scheherazade-new-v17-arabic-regular.woff2", 400, "normal", RF);
const EMOJI = font("Twemoji Mozilla", "twemoji/TwemojiMozilla-colr.woff2", 400, "normal", RF);
const asset = (f) => new Uint8Array(readFileSync(path.join(ROOT, "bench", "assets", f)));
const SVG_LOGO = new TextEncoder().encode(`<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#be123c"/><stop offset="1" stop-color="#1d4ed8"/></linearGradient></defs>
  <rect x="6" y="6" width="108" height="108" rx="24" fill="url(#g)"/><circle cx="60" cy="60" r="28" fill="#fff" fill-opacity="0.85"/>
  <path d="M40 62 L55 76 L82 46" stroke="#0f172a" stroke-width="8" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>`);

const DATE = "2026-11-12";
const FOOTER = `<div style="font: 10px Inter; color: #64748b; display: flex; justify-content: space-between; padding: 0 48px">
      <span>ACME Studio · billing@acme.example</span><span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span></div>`;
const money = (n) => "$" + n.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");

function invoiceHtml(items = [["Design system audit", 1, 1200], ["Component library (24 components)", 24, 85], ["Accessibility review", 1, 640], ["Hosting, 12 months", 12, 19]]) {
  const subtotal = items.reduce((s, [, q, p]) => s + q * p, 0); const tax = Math.round(subtotal * 0.1);
  return `<style>
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
   <div class="meta"><div><b>Billed to</b><br>Northwind Traders<br>12 Harbour Street<br>Seattle, WA</div>
     <div class="num"><b>Issued</b> 2026-11-12<br><b>Due</b> 2026-12-12</div></div>
   <table>
     <thead><tr><th>Description</th><th class="num">Qty</th><th class="num">Unit price</th><th class="num">Amount</th></tr></thead>
     <tbody>${items.map(([d, q, p]) => `<tr><td>${d}</td><td class="num">${q}</td><td class="num">${money(p)}</td><td class="num">${money(q * p)}</td></tr>`).join("")}</tbody>
     <tfoot>
       <tr class="total"><td colspan="3" class="num">Subtotal</td><td class="num">${money(subtotal)}</td></tr>
       <tr class="total"><td colspan="3" class="num">Tax 10%</td><td class="num">${money(tax)}</td></tr>
       <tr class="total"><td colspan="3" class="num">Total due</td><td class="num">${money(subtotal + tax)}</td></tr>
     </tfoot>
   </table>`;
}
const INVOICE_OPTS = { size: "a4", margin: { top: 48, right: 48, left: 48 }, footer: FOOTER, lang: "en", metadata: { title: "Invoice INV-2026-0042", authors: ["ACME Studio"], creationDate: DATE } };

const reportRows = (n) => Array.from({ length: n }, (_, k) => {
  const units = 40 + ((k * 37) % 160);
  return `<tr><td>Store ${String(k + 1).padStart(3, "0")}</td><td>${["North", "South", "East", "West"][k % 4]}</td><td class="num">${units}</td><td class="num">${(units * 12.5).toFixed(2)}</td></tr>`;
}).join("");
const REPORT_HTML = `<style>
     body { font-family: Inter; font-size: 11px; color: #0f172a; }
     h1 { font-size: 22px; margin: 0 0 4px; } p { margin: 0 0 16px; color: #475569; }
     table { width: 100%; border-collapse: collapse; }
     thead th { background: #0f172a; color: white; text-align: left; padding: 5px 6px; }
     td { padding: 4px 6px; border-bottom: 1px solid #e2e8f0; }
     tbody tr:nth-child(even) td { background: #f8fafc; } .num { text-align: right; }
   </style>
   <h1>Quarterly sales by store</h1><p>Q3 2026 · all regions</p>
   <table><thead><tr><th>Store</th><th>Region</th><th class="num">Units</th><th class="num">Revenue</th></tr></thead><tbody>${reportRows(70)}</tbody></table>`;

const TICKET = {
  type: "container",
  style: { display: "flex", width: "100%", fontFamily: "Inter", color: "#0f172a", backgroundColor: "#fff1f2", border: "2px solid #be123c", borderRadius: 16 },
  children: [
    { type: "container", style: { display: "flex", flexDirection: "column", gap: 6, padding: 24, flexGrow: 1 }, children: [
      { type: "text", text: "ADMIT ONE", style: { fontSize: 12, fontWeight: 700, color: "#be123c", letterSpacing: 2 } },
      { type: "text", text: "Zig & WebAssembly Meetup", style: { fontSize: 24, fontWeight: 700 } },
      { type: "text", text: "Fri 4 Dec 2026 · 18:30 · Hall B", style: { fontSize: 14 } },
      { type: "text", text: "Ada Lovelace · Seat C-12", style: { fontSize: 14, color: "#475569" } },
    ] },
    { type: "container", style: { display: "flex", alignItems: "center", justifyContent: "center", width: 120, borderLeft: "2px dashed #be123c" },
      children: [{ type: "text", text: "No. 0815", style: { fontSize: 16, fontWeight: 700, transform: "rotate(-90deg)" } }] },
  ],
};

const LOREM = "Paged output flows content across pages the way a browser prints: text wraps at the page width, a line that does not fit moves to the next page, and the header and footer bands repeat on every page with their counters filled in.";
const paragraphs = (n, prefix = "Paragraph") => Array.from({ length: n }, (_, k) => `<p>${prefix} ${k + 1}. ${LOREM}</p>`).join("");

const LINKS_HTML = `<style>body{font-family:Inter;font-size:12px;color:#0f172a} h1{font-size:24px} h2{font-size:18px} h3{font-size:14px} a{color:#1d4ed8}</style>
  <h1 id="top">Links and outline</h1>
  <p>Jump to <a href="#details">the details</a>, to <a href="#appendix">the appendix</a>, or visit <a href="https://example.com/docs">example.com/docs</a> and <a href="mailto:hello@example.com">write to us</a>.</p>
  ${paragraphs(8)}
  <h2 id="details">Details</h2>${paragraphs(10, "Detail")}
  <h3 id="sub">A subsection</h3>${paragraphs(6, "Sub")}
  <h2 id="appendix">Appendix</h2>${paragraphs(8, "Appendix")}<p><a href="#top">Back to the top</a></p>`;

const IMAGES_HTML = `<div style="display:flex;flex-direction:column;gap:12px;font-family:Inter;font-size:12px;color:#0f172a;padding:24px">
  <div style="font-size:20px;font-weight:700">Images</div>
  <div style="display:flex;gap:12px;align-items:flex-start">
    <img src="photo.jpg" style="width:240px;height:160px;object-fit:cover;border-radius:12px">
    <img src="avatar.png" style="width:120px;height:120px;border-radius:60px">
    <img src="logo.svg" style="width:120px;height:120px">
    <img src="icon.png" style="width:48px;height:48px">
  </div>
  <div style="width:100%;height:140px;background-image:url(cover.jpg);background-size:cover;border-radius:8px"></div>
</div>`;
const IMAGES = () => [{ src: "photo.jpg", data: asset("photo.jpg") }, { src: "avatar.png", data: asset("avatar.png") }, { src: "icon.png", data: asset("icon.png") }, { src: "cover.jpg", data: asset("cover.jpg") }, { src: "logo.svg", data: SVG_LOGO }];

const EFFECTS_HTML = `<div style="display:flex;flex-wrap:wrap;gap:24px;padding:32px;background:#f8fafc;font-family:Inter;width:100%;height:100%">
  <div style="width:200px;height:120px;border-radius:16px;background-image:linear-gradient(135deg,#ff5f6d,#3a1c71);box-shadow:0 10px 30px rgba(15,23,42,.35)"></div>
  <div style="width:200px;height:120px;border-radius:60px;background-image:radial-gradient(circle,#fddb92,#4481eb)"></div>
  <div style="width:200px;height:120px;background-image:conic-gradient(from 0deg,red,yellow,lime,cyan,blue,magenta,red);border:4px solid #0f172a"></div>
  <div style="width:200px;height:120px;background:#fff;border-radius:12px;box-shadow:inset 0 0 0 6px #1d4ed8, 6px 6px 0 0 #0f172a;display:flex;align-items:center;justify-content:center;font-size:20px;font-weight:700;color:#1d4ed8">Shadow</div>
  <div style="width:200px;height:120px;background:#22c55e;opacity:.6;border-radius:20px;transform:rotate(-6deg)"></div>
  <div style="width:200px;height:120px;background-image:repeating-linear-gradient(45deg,#0f172a 0,#0f172a 8px,#f8fafc 8px,#f8fafc 16px);border-radius:8px"></div>
  <div style="font-size:40px;font-weight:700;background-image:linear-gradient(90deg,#be123c,#1d4ed8);color:transparent;background-clip:text">Gradient text</div>
</div>`;

const INTL_HTML = `<main style="display:flex;flex-direction:column;gap:10px;font-family:Inter;font-size:16px;color:#141414;padding:24px">
  <h1 style="font-size:24px;margin:0">International text</h1>
  <p lang="ar" dir="rtl" style="font-family:'Scheherazade New';font-size:22px;margin:0">مرحبا بالعالم، هذا نص عربي من اليمين إلى اليسار مع أرقام 123.</p>
  <p lang="zh" style="font-family:'Noto Sans TC';margin:0">繁體中文的段落，測試字型子集與換行。直骨今海真令説器。</p>
  <p style="margin:0">Mixed: Hello <span lang="ar" dir="rtl" style="font-family:'Scheherazade New'">سلام</span> world and 你好.</p>
  <p style="font-family:Inter,'Twemoji Mozilla';margin:0">Emoji: 🎉 🚀 ✅ 👩‍💻 🇻🇳</p>
</main>`;

const TAGGED_HTML = `<main style="display:flex;flex-direction:column;font-family:Inter;font-size:13px;color:#141414">
  <h1>Accessible report</h1>
  <p>This document is tagged: headings, paragraphs, lists, a table, a link and an image with alternative text.</p>
  <h2>Findings</h2>
  <ul><li>First finding</li><li>Second finding</li></ul>
  <table style="border-collapse:collapse"><thead><tr><th style="border:1px solid #999;padding:4px">Quarter</th><th style="border:1px solid #999;padding:4px">Total</th></tr></thead>
  <tbody><tr><td style="border:1px solid #999;padding:4px">Q1</td><td style="border:1px solid #999;padding:4px">1 200</td></tr><tr><td style="border:1px solid #999;padding:4px">Q2</td><td style="border:1px solid #999;padding:4px">1 450</td></tr></tbody></table>
  <p>More at <a href="https://example.com/report">example.com/report</a>.</p>
  <img src="icon.png" alt="Company logo" style="width:48px;height:48px">
</main>`;
const ATTACH = { name: "factur-x.xml", data: `<invoice total="4519"/>`, mimeType: "application/xml", description: "Factur-X invoice data", relationship: "alternative", modificationDate: DATE };
const FACTUR_X = { name: "Factur-X PDF/A Extension", prefix: "fx", namespace: "urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#", properties: [{ name: "DocumentFileName", value: "factur-x.xml", description: "name of the embedded XML invoice file" }] };

/** A stress document of `pages` A4 pages: per page a heading, paragraphs, a 14-row table and an image. */
export function stressHtml(pages) {
  const sec = (k) => `<section style="break-after:page">
    <h2 style="font-size:18px;margin:0 0 6px">Section ${k + 1}</h2>
    <div style="display:flex;gap:12px"><img src="icon.png" style="width:64px;height:64px"><p style="margin:0;flex:1">${LOREM} ${LOREM}</p></div>
    <table style="width:100%;border-collapse:collapse;margin:8px 0;font-size:10px"><thead><tr><th style="text-align:left;border-bottom:2px solid #0f172a">Item</th><th style="text-align:right;border-bottom:2px solid #0f172a">Qty</th><th style="text-align:right;border-bottom:2px solid #0f172a">Amount</th></tr></thead>
    <tbody>${Array.from({ length: 14 }, (_, r) => `<tr><td style="border-bottom:1px solid #e2e8f0">Line ${k * 14 + r + 1}</td><td style="text-align:right;border-bottom:1px solid #e2e8f0">${(r * 7 + k) % 23 + 1}</td><td style="text-align:right;border-bottom:1px solid #e2e8f0">${money(((r * 37 + k * 11) % 997) + 0.5)}</td></tr>`).join("")}</tbody></table>
    <p style="margin:0">${LOREM}</p></section>`;
  return `<div style="font-family:Inter;font-size:11px;color:#0f172a">${Array.from({ length: pages }, (_, k) => sec(k)).join("")}</div>`;
}
export const STRESS_PAGES = [1, 10, 100, 500];

export function docsCorpus() {
  const base = (id, o) => ({ id: "docs/" + id, group: "docs", fonts: INTER, pdfa: null, tagged: null, ...o, viewport: !!o.viewport });
  const docs = [
    base("invoice", { source: () => invoiceHtml(), options: () => ({ ...INVOICE_OPTS }) }),
    base("report-repeating-header", { source: () => REPORT_HTML, options: () => ({ size: "a5", margin: { top: 36, right: 36, left: 36 }, footer: `<div style="display:flex;justify-content:center;column-gap:4px;font-family:Inter;font-size:9px;color:#64748b"><span>Page</span><span class="pageNumber"></span><span>of</span><span class="totalPages"></span></div>`, outline: true }) }),
    base("ticket", { source: () => TICKET, options: () => ({ viewport: { width: 560 } }), viewport: true }),
    base("multipage-text", { source: () => `<div style="font-family:Inter;font-size:12px;line-height:1.5;color:#0f172a"><h1>Multi-page text</h1>${paragraphs(60)}</div>`, options: () => ({ size: "letter", margin: 56 }) }),
    base("headers-footers", { source: () => `<div style="font-family:Inter;font-size:12px;color:#0f172a">${paragraphs(45)}</div>`, options: () => ({ size: "a4", header: `<div style="font:10px Inter;color:#475569;padding:0 40px;display:flex;justify-content:space-between"><span>Quarterly report</span><span>Confidential</span></div>`, footer: `<div style="font:10px Inter;color:#475569;text-align:center">Page <span class="pageNumber"></span> / <span class="totalPages"></span></div>`, pages: { first: { header: false }, even: { footer: `<div style="font:10px Inter;color:#be123c;text-align:left;padding:0 40px">Even page <span class="pageNumber" ></span></div>` } } }) }),
    base("links-outline", { source: () => LINKS_HTML, options: () => ({ size: "a5", outline: true, lang: "en", metadata: { title: "Links and outline", description: "Internal and external links, bookmarks", authors: ["bm-engine bench"], keywords: ["links", "outline"], creator: "bench/pdf", creationDate: DATE } }) }),
    base("images", { source: () => IMAGES_HTML, options: () => ({ size: "a4", images: IMAGES() }) }),
    base("images-viewport", { source: () => IMAGES_HTML, options: () => ({ viewport: { width: 640, height: 420 }, images: IMAGES() }), viewport: true }),
    base("effects", { source: () => EFFECTS_HTML, options: () => ({ viewport: { width: 720, height: 360 } }), viewport: true }),
    base("intl-rtl-cjk-emoji", { fonts: [...INTER, ARABIC, NOTO_TC, EMOJI].filter((f) => existsSync(f.path)), source: () => INTL_HTML, options: () => ({ size: "a5", lang: "en" }) }),
    base("tagged-ua1", { tagged: "ua1", source: () => TAGGED_HTML, options: () => ({ size: "a4", tagged: "ua1", lang: "en", images: [{ src: "icon.png", data: asset("icon.png") }], metadata: { title: "Accessible report", creationDate: DATE } }) }),
    base("tagged-ua2-pdfa4", { tagged: "ua2", pdfa: "4", source: () => TAGGED_HTML, options: () => ({ size: "a4", pdfa: "4", tagged: "ua2", lang: "en", images: [{ src: "icon.png", data: asset("icon.png") }], metadata: { title: "Accessible report", creationDate: DATE } }) }),
    base("attachments", { source: () => invoiceHtml(), options: () => ({ ...INVOICE_OPTS, attachments: [{ ...ATTACH }, { name: "notes.txt", data: "Plain attachment", mimeType: "text/plain" }] }) }),
  ];
  for (const level of ["2b", "2u", "2a", "3b", "3u", "3a", "4", "4f"]) {
    const attach = level.startsWith("3") || level === "4f";
    docs.push(base(`invoice-pdfa-${level}`, { pdfa: level, tagged: /a$/.test(level) ? true : null, source: () => invoiceHtml(), options: () => ({ ...INVOICE_OPTS, pdfa: level, metadata: { ...INVOICE_OPTS.metadata, ...(attach ? { xmp: [FACTUR_X] } : {}) }, ...(attach ? { attachments: [{ ...ATTACH }] } : {}) }) }));
  }
  return docs;
}

export function stressCorpus(pages = STRESS_PAGES) {
  return pages.map((n) => ({ id: `stress/${n}p`, group: "stress", pages: n, fonts: INTER, pdfa: null, tagged: null, viewport: false,
    source: () => stressHtml(n), options: () => ({ size: "a4", margin: 40, images: [{ src: "icon.png", data: asset("icon.png") }], footer: `<div style="font:9px Inter;text-align:center;color:#64748b">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>` }) }));
}
