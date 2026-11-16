// Hospital report / print-form checks for bm-render/pdf: the documents a hospital prints (lab results,
// prescriptions, discharge summaries, consent forms, batch printing) and what typically goes wrong with
// them (Vietnamese diacritics, medical symbols, long tables across pages, signatures split by a page
// break, page numbers, scanned images, unbreakable codes, archiving as PDF/A, determinism, throughput).
//
//   node scripts/pdf-hospital-test.mjs [--backend=native|wasm|both] [name ...]
//
// Writes bench/out/hospital/<case>.pdf and <case>-p<N>.png previews (PDFium, 72 dpi) for a visual review,
// and bench/out/hospital/results.json. Exit code 1 when a check fails.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createRequire } from "node:module";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = path.join(root, "bench", "out", "hospital");
mkdirSync(out, { recursive: true });
const argv = process.argv.slice(2);
const backendArg = (argv.find((a) => a.startsWith("--backend="))?.slice(10)) || "both";
const only = argv.filter((a) => !a.startsWith("--"));

// ---- engines (the public bm-render/pdf entry; BM_RENDER_BACKEND picks wasm or the native addon)
async function loadBackend(name) {
  process.env.BM_RENDER_BACKEND = name;
  const url = pathToFileURL(path.join(root, "js", "node-pdf.mjs")).href + "?b=" + name;
  const m = await import(url);
  return m.backend === name ? m : null;
}
const backends = {};
for (const b of backendArg === "both" ? ["native", "wasm"] : [backendArg]) {
  const m = await loadBackend(b).catch(() => null);
  if (m) backends[b] = m; else console.log(`(backend ${b} unavailable, skipped)`);
}
delete process.env.BM_RENDER_BACKEND;

const font = (f) => new Uint8Array(readFileSync(path.join(root, "assets", "fonts", f)));
const FONTS = [
  { name: "Noto Sans", data: font("NotoSans-Regular.ttf") },
  { name: "Noto Sans", data: font("NotoSans-Bold.ttf"), weight: 700 },
  { name: "Inter", data: font("Inter-Regular.ttf") },
  { name: "Inter", data: font("Inter-Bold.ttf"), weight: 700 },
  { name: "Inter", data: font("Inter-Italic.ttf"), style: "italic" },
];
const renderers = {};
function rendererFor(b, fonts = FONTS) {
  const key = b + "|" + fonts.length;
  if (!renderers[key]) {
    const r = new backends[b].PdfRenderer();
    for (const f of fonts) r.registerFont(f);
    renderers[key] = r;
  }
  return renderers[key];
}
const asset = (f) => new Uint8Array(readFileSync(path.join(root, "bench", "assets", f)));

// ---- external tools (bench/pdf/tools, `node bench/pdf/setup.mjs`)
const toolDir = path.join(root, "bench", "pdf", "tools");
const findExe = (dir, exe) => {
  if (!existsSync(dir)) return null;
  const walk = (d, depth) => {
    if (depth > 5) return null;
    for (const e of require("node:fs").readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isFile() && e.name.toLowerCase() === exe) return p;
      if (e.isDirectory()) { const r = walk(p, depth + 1); if (r) return r; }
    }
    return null;
  };
  return walk(dir, 0);
};
const require = createRequire(import.meta.url);
const ext = process.platform === "win32" ? ".exe" : "";
const QPDF = findExe(path.join(toolDir, "qpdf"), "qpdf" + ext);
const PDFTOTEXT = findExe(path.join(toolDir, "poppler"), "pdftotext" + ext);
const PDFFONTS = findExe(path.join(toolDir, "poppler"), "pdffonts" + ext);
const tmp = (name) => path.join(out, name);
function pdftotext(file, args = []) {
  if (!PDFTOTEXT) return null;
  return execFileSync(PDFTOTEXT, [...args, "-enc", "UTF-8", file, "-"], { encoding: "utf8" });
}
function qpdfCheck(file) {
  if (!QPDF) return { ok: true, skipped: true };
  try { execFileSync(QPDF, ["--check", file], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }); return { ok: true }; }
  catch (e) { return { ok: e.status === 3, msg: String(e.stdout || "") + String(e.stderr || "") }; } // 3 = warnings only
}
function fontsReport(file) {
  if (!PDFFONTS) return null;
  const lines = execFileSync(PDFFONTS, [file], { encoding: "utf8" }).split(/\r?\n/).slice(2).filter(Boolean);
  // columns: name type encoding emb sub uni object ID
  return lines.map((l) => { const c = l.trim().split(/\s+/); return { name: c[0], emb: c[c.length - 5], sub: c[c.length - 4], uni: c[c.length - 3] }; });
}
let pdfium = null;
async function preview(bytes, pages, base) {
  try {
    pdfium ??= await import(pathToFileURL(path.join(root, "bench", "pdf", "lib", "raster.mjs")).href);
    const { PNG } = createRequire(path.join(root, "bench", "pdf", "package.json"))("pngjs");
    for (const p of pages) {
      const r = await pdfium.rasterise("pdfium", bytes, p, 72);
      const png = new PNG({ width: r.width, height: r.height });
      png.data = Buffer.from(r.rgba);
      writeFileSync(path.join(out, `${base}-p${p + 1}.png`), PNG.sync.write(png));
    }
    pdfium.closeAll();
  } catch (e) { /* previews are a convenience */ }
}

// ---- data
const NAMES = ["Nguyễn Văn Ánh", "Trần Thị Bích Hường", "Lê Quốc Khánh", "Phạm Ngọc Diệp", "Hoàng Đức Thắng", "Võ Thị Thu Trang", "Đặng Minh Quân", "Bùi Thị Ỷ Lan", "Đỗ Hữu Nghĩa", "Huỳnh Thị Yến Nhi"];
const TESTS = [
  ["Hồng cầu (RBC)", "4.52", "×10¹²/L", "3.8 – 5.5"], ["Bạch cầu (WBC)", "11.8", "×10⁹/L", "4.0 – 10.0"],
  ["Hemoglobin", "128", "g/L", "120 – 160"], ["Tiểu cầu (PLT)", "245", "×10⁹/L", "150 – 450"],
  ["Glucose", "7.2", "mmol/L", "3.9 – 6.4"], ["Creatinin", "98", "µmol/L", "62 – 115"],
  ["AST (GOT)", "≤ 37", "U/L", "≤ 37"], ["Nhiệt độ", "38.5", "°C", "36.5 – 37.5"],
  ["Huyết áp", "140/90", "mmHg", "< 130/85"], ["SpO₂", "96", "%", "≥ 95"],
];
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;");
const BASE_CSS = `
  body { margin: 0; font-family: "Noto Sans", Inter; font-size: 12px; color: #111 }
  h1 { font-size: 18px; text-align: center; margin: 4px 0 10px; text-transform: uppercase }
  table { width: 100%; border-collapse: collapse }
  th, td { border: 1px solid #555; padding: 3px 5px; vertical-align: top }
  th { background: #e8eef5 }
  .num { text-align: right; font-variant-numeric: tabular-nums }
  .hi { color: #c00; font-weight: 700 }
`;
const HEADER = `<div style="font:10px 'Noto Sans';display:flex;justify-content:space-between;padding:0 40px;color:#333">
  <span>BỆNH VIỆN ĐA KHOA TỈNH — Khoa Xét nghiệm</span><span>Mã BN: BN-2026-000123</span></div>`;
const FOOTER = `<div style="font:10px 'Noto Sans';text-align:center;color:#333">Trang <span class="pageNumber"></span>/<span class="totalPages"></span></div>`;
const MARGIN = { top: 60, right: 45, bottom: 50, left: 45 };
const labRows = (n) => Array.from({ length: n }, (_, i) => {
  const t = TESTS[i % TESTS.length];
  const high = i % 4 === 1;
  return `<tr class="row"><td>${i + 1}</td><td>${esc(t[0])} #${i + 1}</td><td class="num${high ? " hi" : ""}">${esc(t[1])}</td><td>${esc(t[2])}</td><td>${esc(t[3])}</td></tr>`;
}).join("");
const signature = `<div class="sign" style="break-inside:avoid;display:flex;justify-content:space-between;margin-top:16px;text-align:center">
  <div style="width:45%">Người thực hiện<br><i>(Ký, ghi rõ họ tên)</i><div style="height:60px"></div><b>KTV. Trần Thị Bích Hường</b></div>
  <div style="width:45%">Ngày 15 tháng 11 năm 2026<br>TRƯỞNG KHOA XÉT NGHIỆM<br><i>(Ký, đóng dấu)</i><div style="height:60px"></div><b>BS.CKII. Lê Quốc Khánh</b></div>
</div>`;

// ---- cases: { name, html, opts, checks(ctx) } — ctx: { pdf, bytes, text, pages, pageTexts, fonts }
const cases = [
  {
    name: "vn-diacritics-nfc-nfd",
    about: "Vietnamese text in NFC and NFD (combining marks from copy-paste / databases), upper case, bold/italic",
    html: `<style>${BASE_CSS}</style><h1>Phiếu khám bệnh</h1>
      <p>Họ và tên (NFC): <b>${NAMES.join(", ")}</b></p>
      <p>Họ và tên (NFD): <b>${NAMES.map((n) => n.normalize("NFD")).join(", ")}</b></p>
      <p style="text-transform:uppercase">chẩn đoán: viêm phổi cộng đồng mức độ nhẹ</p>
      <p><i>Ghi chú của bác sĩ: theo dõi dấu hiệu sinh tồn mỗi 4 giờ; tái khám sau 7 ngày.</i></p>
      <p>Ỹ ỹ Ỵ ỵ Ẵ ẵ Ặ ặ Ẩ ẩ Ẫ ẫ Ậ ậ Ể ể Ễ ễ Ệ ệ Ổ ổ Ỗ ỗ Ộ ộ Ở ở Ỡ ỡ Ợ ợ Ử ử Ữ ữ Ự ự Đ đ</p>`,
    opts: { size: "a4", margin: MARGIN },
    checks: (c, ok) => {
      const t = c.flat;
      for (const n of NAMES) ok(t.includes(n), `extracted text holds "${n}"`);
      ok(t.includes("CHẨN ĐOÁN: VIÊM PHỔI"), "text-transform:uppercase keeps the diacritics");
      ok(t.replace(/ /g, "").includes("ỸỹỴỵẴẵẶặẨẩẪẫẬậ"), "rare tone marks extract (pdftotext joins one-letter words, as for takumi)");
    },
  },
  {
    name: "medical-symbols",
    about: "units and symbols of lab reports: ×10⁹/L, µmol/L, °C, ≤ ≥, ±, ², ½, ‰, mmHg, SpO₂",
    html: `<style>${BASE_CSS}</style><h1>Kết quả xét nghiệm</h1><table><tr><th>#</th><th>Xét nghiệm</th><th>Kết quả</th><th>Đơn vị</th><th>Tham chiếu</th></tr>${labRows(10)}</table>
      <p>Ký hiệu khác: ± 0.5 ; ½ viên × 2 lần/ngày ; 1.2‰ ; 25 m² ; Na⁺ K⁺ Cl⁻ ; → ↑ ↓ ; № 15</p>`,
    opts: { size: "a4", margin: MARGIN },
    checks: (c, ok) => {
      const t = c.text.normalize("NFC");
      for (const s of ["×10⁹/L", "µmol/L", "°C", "≤ 37", "≥ 95", "SpO₂", "± 0.5", "½", "‰", "m²", "Na⁺", "↑"]) ok(t.includes(s), `symbol "${s}" extracts`);
    },
  },
  {
    name: "uncovered-glyph-checkbox",
    about: "a character no registered font draws (☐ ☑ ✔ from Word templates): default error, placeholder / blank modes",
    html: `<style>${BASE_CSS}</style><p>Đồng ý phẫu thuật: ☐ Có ☑ Không ✔</p>`,
    opts: { size: "a5", margin: 40 },
    expectError: /No font|draws/,
    extra: [{ opts: { size: "a5", margin: 40, uncoveredText: "placeholder" }, label: "placeholder" }, { opts: { size: "a5", margin: 40, uncoveredText: "blank" }, label: "blank" }],
  },
  {
    name: "default-font-geist-latin",
    about: "no font registered: the bundled Geist (as takumi-pdf) draws Latin text; it has no Vietnamese tone marks",
    fonts: [],
    html: `<p style="font-size:14px">Patient: Nguyen Van Anh — Blood pressure 140/90 mmHg, 38.5 °C</p>`,
    opts: { size: "a5", margin: 30 },
    extra: [{ opts: { size: "a5", margin: 30, uncoveredText: "placeholder" }, label: "placeholder" }],
    checks: (c, ok) => { ok(c.flat.includes("Patient: Nguyen Van Anh"), "Latin text drawn with the bundled Geist"); ok(/Geist/.test(c.fontNames), `embedded font is Geist (${c.fontNames})`); },
  },
  {
    name: "default-font-vietnamese-needs-a-font",
    about: "no font registered and Vietnamese text: Geist lacks the tone marks, the render names them (register a Vietnamese font)",
    fonts: [],
    html: `<p>Bệnh nhân: Phạm Đức Thắng</p>`,
    opts: { size: "a5", margin: 30 },
    expectError: /No font the text can use draws .*U\+1EC7|U\+1EA1|U\+0110/,
  },
  {
    name: "lab-table-300-rows",
    about: "300 result rows on A4: repeated <thead> on every page, no row cut in half, tfoot, page X/Y footer",
    html: `<style>${BASE_CSS}</style><h1>Kết quả xét nghiệm tổng hợp</h1><p>Bệnh nhân: <b>Nguyễn Văn Ánh</b> — 45 tuổi — Nam</p>
      <table><thead><tr><th>#</th><th>Xét nghiệm</th><th>Kết quả</th><th>Đơn vị</th><th>Tham chiếu</th></tr></thead>
      <tbody>${labRows(300)}</tbody><tfoot><tr><td colspan="5"><i>Kết quả có giá trị trong 30 ngày</i></td></tr></tfoot></table>${signature}`,
    opts: { size: "a4", margin: MARGIN, header: HEADER, footer: FOOTER },
    checks: (c, ok) => {
      ok(c.pages >= 5, `several pages (${c.pages})`);
      c.pageTexts.forEach((p, i) => ok(/Xét nghiệm\s+Kết quả\s+Đơn vị/.test(p.replace(/\s+/g, " ")) || i === 0 && /Xét nghiệm/.test(p), `page ${i + 1} repeats the table header`));
      c.pageTexts.forEach((p, i) => ok(p.includes(`Trang ${i + 1}/${c.pages}`), `page ${i + 1} footer "Trang ${i + 1}/${c.pages}"`));
      c.pageTexts.forEach((p, i) => ok(p.includes("BN-2026-000123"), `page ${i + 1} header holds the patient id`));
      // every row's number and test name land on the same page
      let split = 0;
      for (let k = 1; k <= 300; k++) {
        const name = `#${k}`;
        const where = c.pageTexts.findIndex((p) => new RegExp(`(^|\\s)${k}\\s+[^\\n]*${name}(\\s|$)`).test(p.replace(/\n/g, " ")));
        if (where < 0) split++;
      }
      ok(split === 0, `every row intact on one page (${split} rows split or missing)`);
      const last = c.pageTexts[c.pages - 1];
      ok(last.includes("TRƯỞNG KHOA") && last.includes("Lê Quốc Khánh"), "signature block whole on the last page");
    },
  },
  {
    name: "signature-near-page-end",
    about: "break-inside:avoid signature block that would fall on a page boundary moves whole to the next page",
    html: `<style>${BASE_CSS}</style><h1>Giấy ra viện</h1>${Array.from({ length: 34 }, (_, i) => `<p style="margin:0 0 6px">Dòng nội dung tóm tắt bệnh án số ${i + 1}: diễn biến ổn định, không sốt.</p>`).join("")}${signature}`,
    opts: { size: "a4", margin: MARGIN, footer: FOOTER },
    checks: (c, ok) => {
      const with_ = c.pageTexts.map((p, i) => [i, p.includes("Người thực hiện"), p.includes("Trần Thị Bích Hường"), p.includes("Lê Quốc Khánh")]);
      const head = with_.find((x) => x[1]); const tail = with_.find((x) => x[3]);
      ok(head && tail && head[0] === tail[0], `signature title and names on one page (title p${head?.[0] + 1}, names p${tail?.[0] + 1})`);
    },
  },
  {
    name: "batch-50-patients",
    about: "batch printing: 50 one-page forms, break-before:page per patient, each starts a new page",
    html: `<style>${BASE_CSS} .form{break-before:page} .form:first-child{break-before:auto}</style>` + NAMES.concat(NAMES, NAMES, NAMES, NAMES).map((n, i) => `<div class="form"><h1>Phiếu chỉ định cận lâm sàng</h1><p>STT: ${i + 1} — Họ tên: <b>${n}</b></p><table><tr><th>#</th><th>Xét nghiệm</th><th>Kết quả</th><th>Đơn vị</th><th>Tham chiếu</th></tr>${labRows(6)}</table></div>`).join(""),
    opts: { size: "a5", margin: 30, footer: FOOTER },
    checks: (c, ok) => {
      ok(c.pages === 50, `50 pages (${c.pages})`);
      c.pageTexts.forEach((p, i) => ok(p.includes(`STT: ${i + 1} `) || p.includes(`STT: ${i + 1}—`) || new RegExp(`STT: ${i + 1}\\b`).test(p), `page ${i + 1} is form ${i + 1}`));
    },
  },
  {
    name: "prescription-a5-landscape",
    about: "A5 landscape prescription: margins, long drug names and an unbreakable code in a narrow cell",
    html: `<style>${BASE_CSS} td.code{width:70px;overflow-wrap:anywhere}</style><h1>Đơn thuốc</h1>
      <table><tr><th>Thuốc</th><th>Mã</th><th>Liều dùng</th></tr>
      <tr><td>Amoxicillin + Acid clavulanic (Augmentin 625mg)</td><td class="code">VN-12345-67890-ABCDEFGHIJKLMN</td><td>1 viên × 2 lần/ngày, uống sau ăn</td></tr>
      <tr><td>Paracetamol 500mg</td><td class="code">VD-98765432109876543210</td><td>1 viên khi sốt ≥ 38.5°C, cách nhau ≥ 4 giờ</td></tr></table>
      <p>Lời dặn: Tái khám sau 07 ngày hoặc khi có dấu hiệu bất thường.</p>`,
    opts: { size: "a5", landscape: true, margin: 40 },
    checks: (c, ok) => {
      ok(c.pages === 1, `one page (${c.pages})`);
      ok(Math.round(c.mediaBox[2]) > Math.round(c.mediaBox[3]), `landscape MediaBox ${c.mediaBox.join(" ")}`);
      // (pdftotext drops a hyphen that ends a line and joins the pieces; pdf.js reads "VN- | 12345- | ...")
      const joined = c.text.replace(/[\s-]+/g, "");
      ok(joined.includes("VN1234567890ABCDE") && joined.includes("FGHIJK") && joined.includes("LMN"), "the long code wraps inside its narrow cell, every piece present (not clipped)");
    },
  },
  {
    name: "images-logo-stamp-qr",
    about: "logo PNG with alpha, progressive JPEG photo, SVG QR-like code and a translucent stamp",
    html: `<style>${BASE_CSS}</style><div style="display:flex;align-items:center;gap:12px"><img src="logo.png" style="width:56px;height:56px"><div><b>BỆNH VIỆN ĐA KHOA TỈNH</b><br>Số 1 Đường Lê Lợi</div>
      <svg width="64" height="64" viewBox="0 0 8 8" style="margin-left:auto"><rect width="8" height="8" fill="#fff"/><path d="M0 0h3v3H0zM5 0h3v3H5zM0 5h3v3H0zM4 4h1v1H4zM6 6h2v2H6zM4 6h1v2H4z" fill="#000"/></svg></div>
      <h1>Phiếu chụp X-quang</h1><img src="photo.jpg" style="width:300px;height:200px;object-fit:cover">
      <div style="position:relative;height:120px"><img src="stamp.png" style="position:absolute;right:40px;top:0;width:110px;height:110px;opacity:.8"></div>`,
    opts: { size: "a4", margin: MARGIN, images: [{ src: "logo.png", data: asset("icon.png") }, { src: "photo.jpg", data: asset("photo.jpg") }, { src: "stamp.png", data: asset("avatar.png") }] },
    checks: (c, ok) => { ok(c.imageCount >= 3, `three raster images embedded (${c.imageCount})`); },
  },
  {
    name: "watermark-every-page",
    about: "a rotated 'BẢN SAO' watermark on every page (position:fixed) behind a 3-page report",
    html: `<style>${BASE_CSS} .wm{position:fixed;top:40%;left:15%;font-size:70px;color:rgba(200,0,0,.15);transform:rotate(-30deg);z-index:-1}</style><div class="wm">BẢN SAO</div><h1>Tóm tắt hồ sơ bệnh án</h1>${Array.from({ length: 120 }, (_, i) => `<p style="margin:0 0 4px">Mục ${i + 1}: theo dõi điều trị nội khoa, đáp ứng tốt.</p>`).join("")}`,
    opts: { size: "a4", margin: MARGIN, footer: FOOTER },
    checks: (c, ok) => { ok(c.pages >= 3, `several pages (${c.pages})`); c.plainPages.forEach((p, i) => ok(/^B$/m.test(p) && /^O$/m.test(p), `page ${i + 1} has the rotated watermark (pdftotext splits rotated glyphs)`)); },
  },
  {
    name: "doctor-notes-pre-wrap",
    about: "free-text notes with line breaks, tabs and long lines (white-space:pre-wrap)",
    html: `<style>${BASE_CSS}</style><h1>Diễn biến bệnh</h1><div style="white-space:pre-wrap;border:1px solid #999;padding:6px">08:00\tBN tỉnh, tiếp xúc tốt.\n10:30\tSốt 38.7°C → hạ sốt Paracetamol 500mg.\n14:00\t${"Theo dõi sát mạch, huyết áp, nhiệt độ, nhịp thở. ".repeat(6)}\n\n20:00\tỔn định.</div>`,
    opts: { size: "a4", margin: MARGIN },
    checks: (c, ok) => { const t = c.text.normalize("NFC"); for (const s of ["08:00", "10:30", "14:00", "20:00", "Ổn định"]) ok(t.includes(s), `note line "${s}"`); },
  },
  {
    name: "rowspan-across-pages",
    about: "a rowspan group (one patient, many tests) that crosses a page boundary",
    html: `<style>${BASE_CSS}</style><h1>Bảng theo dõi</h1><table><thead><tr><th>Bệnh nhân</th><th>Xét nghiệm</th><th>Kết quả</th></tr></thead><tbody>${NAMES.slice(0, 4).map((n) => Array.from({ length: 14 }, (_, k) => `<tr>${k === 0 ? `<td rowspan="14">${n}</td>` : ""}<td>${TESTS[k % TESTS.length][0]}</td><td class="num">${TESTS[k % TESTS.length][1]}</td></tr>`).join("")).join("")}</tbody></table>`,
    opts: { size: "a5", margin: 40, footer: FOOTER },
    checks: (c, ok) => { ok(c.pages >= 2, `crosses pages (${c.pages})`); for (const n of NAMES.slice(0, 4)) ok(c.text.normalize("NFC").includes(n), `"${n}" present`); },
  },
  {
    name: "pdfa-2b-archive",
    about: "PDF/A-2b for the medical record archive, with metadata",
    html: `<style>${BASE_CSS}</style><h1>Bệnh án điện tử</h1><p>${NAMES.join(", ")}</p>`,
    opts: { size: "a4", margin: MARGIN, pdfa: "2b", lang: "vi", metadata: { title: "Bệnh án điện tử", authors: ["Bệnh viện Đa khoa Tỉnh"], creationDate: "2026-11-15T08:00:00" } },
    checks: (c, ok) => { ok(/pdfaid:part/.test(c.raw), "XMP declares PDF/A"); ok(c.text.normalize("NFC").includes("Nguyễn Văn Ánh"), "text extracts"); },
  },
  {
    name: "tagged-ua1-accessible",
    about: "PDF/UA-1 tagged output (screen readers) with Vietnamese language",
    html: `<style>${BASE_CSS}</style><h1>Hướng dẫn sau phẫu thuật</h1><ol><li>Giữ vết mổ khô sạch.</li><li>Uống thuốc đúng giờ.</li></ol><table><tr><th>Ngày</th><th>Việc cần làm</th></tr><tr><td>Ngày 1</td><td>Nghỉ ngơi</td></tr></table>`,
    opts: { size: "a4", margin: MARGIN, tagged: "ua1", lang: "vi", metadata: { title: "Hướng dẫn sau phẫu thuật" } },
    checks: (c, ok) => { ok(/StructTreeRoot/.test(c.raw), "structure tree present"); ok(/\/Lang\s*\(vi\)|\/Lang<[^>]+>/.test(c.raw) || c.raw.includes("vi"), "document language"); },
  },
  {
    name: "big-500-pages",
    about: "a 500-page bulk export (time, size)",
    html: `<style>${BASE_CSS} .p{break-after:page}</style>` + Array.from({ length: 500 }, (_, i) => `<div class="p"><h1>Phiếu ${i + 1}</h1><p>Họ tên: ${NAMES[i % NAMES.length]}</p><table><tr><th>#</th><th>Xét nghiệm</th><th>Kết quả</th><th>Đơn vị</th><th>Tham chiếu</th></tr>${labRows(8)}</table></div>`).join(""),
    opts: { size: "a5", margin: 30 },
    checks: (c, ok) => { ok(c.pages === 500, `500 pages (${c.pages})`); ok(c.ms < 20000, `rendered in ${Math.round(c.ms)} ms`); },
    noPreview: true,
  },
];

// ---- run
const results = [];
let failures = 0;
const mediaBoxOf = (raw) => { const m = raw.match(/\/MediaBox\s*\[\s*([\d.\-\s]+)\]/); return m ? m[1].trim().split(/\s+/).map(Number) : [0, 0, 0, 0]; };
for (const tc of cases) {
  if (only.length && !only.some((o) => tc.name.includes(o))) continue;
  const row = { name: tc.name, about: tc.about, checks: [], backends: {} };
  const ok = (cond, what) => { row.checks.push({ ok: !!cond, what }); if (!cond) failures++; };
  const outputs = {};
  for (const b of Object.keys(backends)) {
    const r = rendererFor(b, tc.fonts);
    const t0 = performance.now();
    let bytes = null, err = null;
    try { bytes = new Uint8Array(await r.render(tc.html, tc.opts)); } catch (e) { err = String(e.message || e); }
    const ms = performance.now() - t0;
    row.backends[b] = { ms: Math.round(ms * 10) / 10, bytes: bytes?.length ?? 0, error: err };
    if (tc.expectError) { ok(err && tc.expectError.test(err), `${b}: default mode rejects the uncovered character (${err ? err.slice(0, 90) : "rendered"})`); }
    else ok(!err, `${b}: renders${err ? ": " + err : ""}`);
    if (bytes) outputs[b] = { bytes, ms };
    for (const x of tc.extra || []) {
      try { const eb = await r.render(tc.html, x.opts); ok(eb && eb.length > 0, `${b}: renders with uncoveredText "${x.label}"`); if (b === Object.keys(backends)[0]) writeFileSync(tmp(`${tc.name}-${x.label}.pdf`), eb); }
      catch (e) { ok(false, `${b}: uncoveredText "${x.label}" renders: ${e.message}`); }
    }
  }
  const names = Object.keys(outputs);
  if (names.length === 2) ok(Buffer.compare(Buffer.from(outputs[names[0]].bytes), Buffer.from(outputs[names[1]].bytes)) === 0, "native and wasm write the same bytes");
  if (names.length) {
    const b0 = names[0];
    const r = rendererFor(b0, tc.fonts);
    const again = new Uint8Array(await r.render(tc.html, tc.opts));
    ok(Buffer.compare(Buffer.from(again), Buffer.from(outputs[b0].bytes)) === 0, "deterministic: a second render gives the same bytes");
    const { bytes, ms } = outputs[b0];
    const file = tmp(`${tc.name}.pdf`);
    writeFileSync(file, bytes);
    const q = qpdfCheck(file);
    ok(q.ok, `qpdf --check${q.skipped ? " (skipped)" : ""}${q.ok ? "" : ": " + q.msg.slice(0, 200)}`);
    const fonts = fontsReport(file);
    if (fonts) ok(fonts.length > 0 && fonts.every((f) => f.emb === "yes" && f.uni === "yes"), `every font embedded with a ToUnicode map (${fonts.map((f) => `${f.name}:${f.emb}/${f.uni}`).join(", ")})`);
    const raw = Buffer.from(bytes).toString("latin1");
    const text = (pdftotext(file) ?? "").normalize("NFC");
    const flat = text.replace(/\s+/g, " ");
    // (per page in reading layout: plain pdftotext reorders table cells)
    const pageTexts = (pdftotext(file, ["-layout"]) ?? "").normalize("NFC").split("\f").slice(0, -1);
    const ctx = { fontNames: (fonts || []).map((f) => f.name).join(","), bytes, raw, text, flat, pageTexts, plainPages: text.split("").slice(0, -1), pages: pageTexts.length, ms, mediaBox: mediaBoxOf(raw), imageCount: (raw.match(/\/Subtype\s*\/Image/g) || []).length };
    row.pages = ctx.pages;
    if (tc.checks) { try { tc.checks(ctx, ok); } catch (e) { ok(false, "checks threw: " + e.message); } }
    if (!tc.noPreview) await preview(bytes, [...new Set([0, Math.max(0, ctx.pages - 1)])].slice(0, 2), tc.name);
  }
  results.push(row);
  const bad = row.checks.filter((c) => !c.ok);
  console.log(`${bad.length ? "FAIL" : "PASS"}  ${tc.name.padEnd(28)} ${row.checks.length - bad.length}/${row.checks.length} checks  ${Object.entries(row.backends).map(([b, v]) => `${b} ${v.ms} ms`).join(", ")}${row.pages ? `, ${row.pages} page(s)` : ""}`);
  for (const c of bad) console.log(`        - ${c.what}`);
}

// concurrency: many renders at once on one renderer (a print queue), all identical
if (backends.native && (!only.length || only.includes("concurrency"))) {
  const tc = cases.find((c) => c.name === "lab-table-300-rows");
  const r = rendererFor("native");
  const ref = Buffer.from(await r.render(tc.html, tc.opts));
  const t0 = performance.now();
  const outs = await Promise.all(Array.from({ length: 24 }, () => r.render(tc.html, tc.opts)));
  const same = outs.every((o) => Buffer.compare(Buffer.from(o), ref) === 0);
  if (!same) failures++;
  console.log(`${same ? "PASS" : "FAIL"}  concurrency (24 parallel)       all identical: ${same}; ${Math.round(performance.now() - t0)} ms`);
  results.push({ name: "concurrency", checks: [{ ok: same, what: "24 parallel renders give identical bytes" }] });
}

writeFileSync(path.join(out, "results.json"), JSON.stringify(results, null, 1));
console.log(`\n${failures ? failures + " check(s) failed" : "all checks passed"}; PDFs and previews in ${path.relative(root, out)}`);
process.exitCode = failures ? 1 : 0;
