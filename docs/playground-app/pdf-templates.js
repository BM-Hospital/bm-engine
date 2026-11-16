// PDF-mode templates of the playground (loaded only in PDF mode). Each sets the source kind + text, css and a
// partial of the PDF options panel (`pdf`, merged over the panel defaults of app.js). `pages` is the page count
// the automated test expects (bench/browser/playground-test.mjs); `images` adds entries to the images panel.
// Only the default fonts of the playground are used (Inter, Noto Sans): the engine bundles no font.
import { AVATAR_SRC, AVATAR_B64 } from "./templates.js";

const J = (o) => JSON.stringify(o, null, 2);
const avatarImg = () => [{ src: AVATAR_SRC, mime: "image/png", b64: AVATAR_B64 }];
const pageFooter = `<div style="font: 10px Inter; color: #64748b; display: flex; justify-content: space-between; padding: 0 40px">
  <span>{left}</span><span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span>
</div>`;
const footer = (left) => pageFooter.replace("{left}", left);

// ---------------------------------------------------------------------------------------------- invoice
const items = [
  ["Design system audit", 1, 1800], ["Component library (32 components)", 32, 140], ["Accessibility review", 1, 950],
  ["PDF report templates", 4, 420], ["Hosting, 12 months", 12, 35], ["Support hours", 18, 85],
];
const money = (n) => "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2 });
const subtotal = items.reduce((s, [, q, p]) => s + q * p, 0);
const invoice = `<style>
  body { font-family: Inter; color: #0f172a; font-size: 12px; }
  .head { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 28px; }
  .brand { font-size: 22px; font-weight: 700; color: #be123c; }
  h1 { font-size: 28px; margin: 0 0 4px; }
  .muted { color: #64748b; }
  .parties { display: flex; gap: 48px; margin-bottom: 24px; }
  .parties b { display: block; margin-bottom: 4px; }
  table { width: 100%; border-collapse: collapse; }
  th { text-align: left; background: #f1f5f9; padding: 8px; font-weight: 600; }
  td { padding: 8px; border-bottom: 1px solid #e2e8f0; }
  .num { text-align: right; }
  .totals { margin-left: auto; width: 260px; margin-top: 16px; }
  .totals div { display: flex; justify-content: space-between; padding: 4px 0; }
  .grand { border-top: 2px solid #0f172a; font-weight: 700; font-size: 15px; margin-top: 4px; padding-top: 8px !important; }
  .note { margin-top: 32px; padding: 12px 14px; background: #fff1f2; border-left: 4px solid #be123c; }
</style>
<div class="head">
  <div><div class="brand">ACME Studio</div><div class="muted">12 Nguyen Hue, District 1, Ho Chi Minh City</div></div>
  <div style="text-align: right"><h1>Invoice</h1><div class="muted">No. 2026-017 · Issued 31 Jan 2026 · Due 2 Mar 2026</div></div>
</div>
<div class="parties">
  <div><b>Bill to</b>Northwind Traders<br>480 Market Street<br>San Francisco, CA 94104</div>
  <div><b>Project</b>Website relaunch<br>PO 77-1029</div>
</div>
<table>
  <thead><tr><th>Description</th><th class="num">Qty</th><th class="num">Unit price</th><th class="num">Amount</th></tr></thead>
  <tbody>
${items.map(([d, q, p]) => `    <tr><td>${d}</td><td class="num">${q}</td><td class="num">${money(p)}</td><td class="num">${money(q * p)}</td></tr>`).join("\n")}
  </tbody>
</table>
<div class="totals">
  <div><span>Subtotal</span><span>${money(subtotal)}</span></div>
  <div><span>VAT 10%</span><span>${money(subtotal * 0.1)}</span></div>
  <div class="grand"><span>Total due</span><span>${money(subtotal * 1.1)}</span></div>
</div>
<div class="note">Pay by bank transfer to IBAN VN00 0000 1234 5678 within 30 days. Thank you for your business!</div>`;

// ---------------------------------------------------------------------------------------------- article
const para = [
  "Paged output is a different problem from a single image. Content flows from one page to the next, and every break is a decision: between two blocks, inside a paragraph between two lines, or never inside an element marked as unbreakable.",
  "The engine lays the document out once at the page width, then cuts it into pages. A paragraph that would leave a single line at the bottom of a page moves as a whole when orphans forbid it, and a line alone at the top of the next page is avoided by widows.",
  "Headings stay with the text that follows them: break-after avoid keeps a heading off the bottom of a page. Images, tables and figures are placed whole when they fit on a fresh page.",
  "Because the text is real text, readers can select it, search it and copy it, and screen readers can read it in order when the PDF is tagged.",
];
const sections = ["Why pages are different", "Breaking paragraphs", "Keeping headings with text", "Tables and images", "Text that stays text", "What the outline shows"];
const article = `<style>
  body { font-family: Inter; color: #1e293b; font-size: 12.5px; line-height: 1.6; }
  h1 { font-size: 26px; line-height: 1.2; margin: 0 0 6px; color: #0f172a; }
  h2 { font-size: 16px; margin: 22px 0 6px; color: #be123c; break-after: avoid; }
  .lede { font-size: 14px; color: #475569; margin-bottom: 18px; }
  p { margin: 0 0 10px; text-align: justify; orphans: 3; widows: 3; }
</style>
<h1>Typesetting pages with bm-render</h1>
<p class="lede">An article that runs over several A5 pages: headings become bookmarks (outline), and orphans / widows keep at least three lines of a paragraph together at each break.</p>
${sections.map((h, i) => `<h2>${i + 1}. ${h}</h2>\n${[0, 1, 2, 3].map((k) => `<p>${para[(i + k) % para.length]}</p>`).join("\n")}`).join("\n")}`;

// ---------------------------------------------------------------------------------------------- report
const regions = ["North", "South", "East", "West", "Central"];
const products = ["Starter", "Team", "Business", "Enterprise"];
const rows = Array.from({ length: 64 }, (_, k) => {
  const units = 40 + ((k * 37) % 160), price = [19, 49, 99, 249][k % 4];
  return `    <tr><td>${2026}-${String(1 + (k % 12)).padStart(2, "0")}</td><td>${regions[k % 5]}</td><td>${products[k % 4]}</td><td class="num">${units}</td><td class="num">${(units * price).toLocaleString("en-US")}</td></tr>`;
});
const report = `<style>
  body { font-family: Inter; font-size: 11px; color: #0f172a; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .muted { color: #64748b; margin-bottom: 14px; }
  table { width: 100%; border-collapse: collapse; }
  thead th { background: #be123c; color: #ffffff; text-align: left; padding: 6px 8px; }
  td { padding: 5px 8px; border-bottom: 1px solid #e2e8f0; }
  tbody tr:nth-child(even) td { background: #f8fafc; }
  tfoot td { font-weight: 700; border-top: 2px solid #0f172a; }
  .num { text-align: right; }
</style>
<h1>Quarterly sales report</h1>
<div class="muted">64 rows on US Letter landscape: the table header (thead) is drawn again at the top of every page.</div>
<table>
  <thead><tr><th>Month</th><th>Region</th><th>Plan</th><th class="num">Units</th><th class="num">Revenue (USD)</th></tr></thead>
  <tbody>
${rows.join("\n")}
  </tbody>
  <tfoot><tr><td colspan="3">Continued totals per page are in the appendix</td><td class="num">-</td><td class="num">-</td></tr></tfoot>
</table>`;

// ---------------------------------------------------------------------------------------------- ticket (Tailwind, one custom-size page)
const tt = (tw, text) => ({ type: "text", tw, style: { fontFamily: "Inter" }, text });
const ticket = J({
  type: "container", tw: "flex w-full h-full bg-white", children: [
    { type: "container", tw: "flex flex-col justify-between grow p-8 bg-rose-700", children: [
      { type: "container", tw: "flex flex-col gap-1", children: [
        tt("text-sm font-semibold tracking-widest text-rose-200", "ZIG DAYS 2026 · ADMIT ONE"),
        tt("text-4xl font-bold text-white", "Rendering without a browser"),
        tt("text-lg text-rose-100", "Keynote · Hall A · Saigon Exhibition Center"),
      ] },
      { type: "container", tw: "flex gap-10", children: [
        { type: "container", tw: "flex flex-col", children: [tt("text-xs text-rose-200", "DATE"), tt("text-xl font-semibold text-white", "14 Mar 2026")] },
        { type: "container", tw: "flex flex-col", children: [tt("text-xs text-rose-200", "DOORS"), tt("text-xl font-semibold text-white", "09:00")] },
        { type: "container", tw: "flex flex-col", children: [tt("text-xs text-rose-200", "SEAT"), tt("text-xl font-semibold text-white", "C-14")] },
      ] },
    ] },
    { type: "container", tw: "flex flex-col items-center justify-center w-48 gap-3 border-l-4 border-dashed border-rose-200", children: [
      { type: "container", tw: "w-28 h-28 rounded-lg bg-slate-900", children: [] },
      tt("text-sm font-semibold text-slate-700", "No. 004217"),
    ] },
  ],
});

// ---------------------------------------------------------------------------------------------- accessible (PDF/UA-1)
const accessible = `<style>
  body { font-family: Inter; font-size: 13px; line-height: 1.55; color: #0f172a; }
  h1 { font-size: 24px; margin: 0 0 8px; }
  h2 { font-size: 16px; margin: 18px 0 6px; }
  figure { margin: 12px 0; display: flex; gap: 14px; align-items: center; }
  figcaption { color: #475569; }
  ul { margin: 0; padding-left: 20px; }
  .rule { height: 6px; border-radius: 3px; background: linear-gradient(90deg, #be123c, #f59e0b); margin: 10px 0 16px; }
</style>
<div style="display: flex; align-items: center; gap: 10px; color: #64748b"><img src="${AVATAR_SRC}" alt="" width="28" height="28" style="border-radius: 14px"><span>bm-render · Annual summary 2026</span></div>
<h1>Accessible annual summary</h1>
<div class="rule"></div>
<p>This document is rendered with <b>tagged: "ua1"</b>: the engine writes a structure tree (headings, paragraphs, lists, figures) and validates it against PDF/UA-1, which needs a title, a language, and alternate text for every informative image.</p>
<h2>Our team</h2>
<figure>
  <img src="${AVATAR_SRC}" alt="Portrait of Minh Anh, head of engineering" width="72" height="72" style="border-radius: 36px">
  <figcaption>Minh Anh leads the rendering team. The portrait has alternate text; the small badge at the top is decorative (alt="") and is written as an artifact.</figcaption>
</figure>
<h2>Highlights</h2>
<ul>
  <li>Real, selectable text in reading order</li>
  <li>Bookmarks generated from the headings</li>
  <li>Document language and title in the metadata</li>
</ul>
<p>Remove the alt attribute of the portrait, or clear the title, and render again to see the validation error.</p>`;

// ---------------------------------------------------------------------------------------------- Vietnamese / multi-script
const vt = (text, style = {}) => ({ type: "text", text, style: { fontFamily: "Inter", fontSize: 14, color: "#1f2937", ...style } });
const vietnamese = J({
  type: "container", style: { display: "flex", flexDirection: "column", gap: 10 }, children: [
    vt("Xin chào Việt Nam", { fontSize: 34, fontWeight: 700, color: "#9f1239" }),
    vt("Tiếng Việt có sáu thanh: ngang, huyền, sắc, hỏi, ngã, nặng. Chữ trong PDF là chữ thật: bôi chọn, tìm kiếm và sao chép được.", { fontSize: 15, lineHeight: 1.6 }),
    vt("Ắ Ằ Ẳ Ẵ Ặ Ấ Ầ Ẩ Ẫ Ậ Ế Ề Ể Ễ Ệ Ố Ồ Ổ Ỗ Ộ Ớ Ờ Ở Ỡ Ợ Ứ Ừ Ử Ữ Ự Đ", { fontSize: 18, fontWeight: 600, color: "#be123c" }),
    vt("ắ ằ ẳ ẵ ặ ấ ầ ẩ ẫ ậ ế ề ể ễ ệ ố ồ ổ ỗ ộ ớ ờ ở ỡ ợ ứ ừ ử ữ ự đ", { fontSize: 18 }),
    vt("Ελληνικά: Καλημέρα κόσμε, η γρήγορη καφέ αλεπού.", { fontSize: 15, fontFamily: "Noto Sans" }),
    vt("Русский: Съешь же ещё этих мягких французских булок.", { fontSize: 15, fontFamily: "Noto Sans" }),
    vt("Français, Deutsch, Español: déjà vu, Größe, mañana.", { fontSize: 15 }),
    { type: "container", style: { display: "flex", gap: 18, alignItems: "baseline", marginTop: 8 }, children: [
      vt("Mỏng", { fontSize: 22 }), vt("Vừa", { fontSize: 22, fontWeight: 600 }), vt("Đậm", { fontSize: 22, fontWeight: 700 }),
      vt("Noto Sans: Phở bò Hà Nội", { fontSize: 20, fontFamily: "Noto Sans", fontWeight: 700, color: "#0f766e" }),
    ] },
    vt("Chữ Hán, Ả Rập hay emoji cần font riêng: tải font lên ở mục Font. Với uncoveredText = \"error\" (mặc định), ký tự không font nào vẽ được sẽ làm render báo lỗi.", { fontSize: 12, color: "#64748b", marginTop: 12, lineHeight: 1.5 }),
  ],
});

// ---------------------------------------------------------------------------------------------- links + anchors
const chapters = [["install", "Installing"], ["render", "Rendering a document"], ["publish", "Publishing"]];
const links = `<style>
  body { font-family: Inter; font-size: 13px; line-height: 1.6; color: #0f172a; }
  h1 { font-size: 26px; margin: 0 0 12px; }
  h2 { font-size: 20px; margin: 0 0 8px; color: #be123c; }
  a { color: #be123c; }
  .toc { display: flex; flex-direction: column; gap: 6px; margin: 14px 0 20px; }
  .toc div { display: flex; justify-content: space-between; border-bottom: 1px dotted #94a3b8; }
  .chapter { break-before: page; }
</style>
<h1>Handbook</h1>
<p>Internal links jump to an <b>id</b> in the document; the page numbers in the table of contents come from <b>targetPageNumber</b>. External links open in the browser: <a href="https://github.com/">github.com</a>.</p>
<div class="toc">
${chapters.map(([id, t]) => `  <div><a href="#${id}">${t}</a><a href="#${id}"><span class="targetPageNumber"></span></a></div>`).join("\n")}
</div>
${chapters.map(([id, t], i) => `<div class="chapter">
  <h2 id="${id}">${i + 1}. ${t}</h2>
  <p>This chapter starts on page <span class="pageNumber"></span> of <span class="totalPages"></span>. ${i < chapters.length - 1 ? `Next: <a href="#${chapters[i + 1][0]}">${chapters[i + 1][1]}</a> on page <a href="#${chapters[i + 1][0]}"><span class="targetPageNumber"></span></a>.` : `Back to the <a href="#top">top</a>.`}</p>
  <p>Every heading is also a bookmark because the outline option is on.</p>
</div>`).join("\n")}`.replace("<h1>Handbook</h1>", '<h1 id="top">Handbook</h1>');

/** @type {{id:string,title:{en:string,vi:string},kind:"json"|"html"|"tw",source:string,css?:string,pdf:object,pages:number,images?:Function,hint?:{en:string,vi:string}}[]} */
export const pdfTemplates = [
  { id: "invoice", title: { en: "Invoice (table, totals, page footer)", vi: "Hoá đơn (bảng, tổng tiền, footer số trang)" }, kind: "html", source: invoice, pages: 1,
    pdf: { size: "a4", mt: "40", mr: "40", ml: "40", footer: footer("ACME Studio · Invoice 2026-017"), title: "Invoice 2026-017", author: "ACME Studio", lang: "en" } },
  { id: "article", title: { en: "Article (A5, outline, widows/orphans)", vi: "Bài viết (A5, outline, widows/orphans)" }, kind: "html", source: article, pages: 4,
    pdf: { size: "a5", mt: "", mr: "36", mb: "", ml: "36", header: `<div style="font: 9px Inter; color: #94a3b8; padding: 0 36px">Typesetting pages with bm-render</div>`, footer: footer("bm-render"), plainFirst: true, outline: true, title: "Typesetting pages with bm-render", author: "bm-render", lang: "en" },
    hint: { en: "Headings become bookmarks (outline on). The first page has no header or footer (pages.first).", vi: "Tiêu đề trở thành bookmark (bật outline). Trang đầu không có header, footer (pages.first)." } },
  { id: "report", title: { en: "Report (repeating table header)", vi: "Báo cáo (header bảng lặp lại)" }, kind: "html", source: report, pages: 4,
    pdf: { size: "letter", landscape: true, mr: "40", ml: "40", header: `<div style="font: 9px Inter; color: #64748b; padding: 0 40px; display: flex; justify-content: space-between"><span>Northwind · Q1 2026</span><span>Confidential</span></div>`, footer: footer("Quarterly sales report"), title: "Quarterly sales report", lang: "en" } },
  { id: "ticket", title: { en: "Event ticket (Tailwind, one custom page)", vi: "Vé sự kiện (Tailwind, một trang tuỳ chỉnh)" }, kind: "tw", source: ticket, pages: 1,
    pdf: { layout: "viewport", vw: "720", vh: "260", title: "Ticket 004217", lang: "en" } },
  { id: "accessible", title: { en: "Accessible document (PDF/UA-1, alt text)", vi: "Tài liệu truy cập được (PDF/UA-1, alt text)" }, kind: "html", source: accessible, pages: 1, images: avatarImg,
    pdf: { size: "a4", mr: "48", ml: "48", tagged: "ua1", lang: "en", title: "Accessible annual summary", author: "bm-render", outline: true },
    hint: { en: "tagged: \"ua1\" validates PDF/UA-1. Remove the portrait's alt or the title to see the engine's validation error.", vi: "tagged: \"ua1\" kiểm tra PDF/UA-1. Xoá alt của ảnh chân dung hoặc tiêu đề để xem lỗi kiểm tra của engine." } },
  { id: "vietnamese", title: { en: "Vietnamese and multi-script text", vi: "Tiếng Việt và nhiều hệ chữ" }, kind: "json", source: vietnamese, pages: 1,
    pdf: { size: "a5", mr: "36", ml: "36", lang: "vi", title: "Xin chào Việt Nam" } },
  { id: "links", title: { en: "Links, anchors, table of contents", vi: "Liên kết, anchor, mục lục" }, kind: "html", source: links, pages: 4,
    pdf: { size: "a5", mr: "36", ml: "36", footer: footer("Handbook"), outline: true, title: "Handbook", lang: "en" },
    hint: { en: "Click the table of contents in the preview: internal links jump to the chapter; targetPageNumber prints its page.", vi: "Bấm vào mục lục trong bản xem trước: liên kết nội bộ nhảy tới chương; targetPageNumber in số trang của chương." } },
];
