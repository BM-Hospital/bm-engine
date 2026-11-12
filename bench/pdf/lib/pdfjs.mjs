// pdf.js (pdfjs-dist, legacy build, in Node) as an independent parser: everything a viewer reads from a PDF,
// reduced to plain JSON for validate.mjs's semantic comparison, plus every warning pdf.js prints.
//
//   inspect(bytes) -> { warnings[], pages: [{ w, h, text, links: [{ url | destPage, rect }], structRoles }], outline,
//                       attachments, metadata: { info, xmp }, markInfo, lang, structTree }
//   renderPage(bytes, pageIndex, scale) -> { width, height, rgba }   (pdf.js canvas renderer via @napi-rs/canvas)
import { createRequire } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { PDF_DIR } from "./tools.mjs";

const require = createRequire(path.join(PDF_DIR, "package.json"));
let pdfjs;
async function lib() {
  if (!pdfjs) {
    pdfjs = await import(pathToFileURL(require.resolve("pdfjs-dist/legacy/build/pdf.mjs")).href);
  }
  return pdfjs;
}
const STD_FONTS = () => pathToFileURL(path.join(path.dirname(require.resolve("pdfjs-dist/package.json")), "standard_fonts") + path.sep).href;

/** Runs fn while capturing everything pdf.js logs (its warn() / info() go to console.log). */
async function capture(fn) {
  const lines = [];
  const orig = { log: console.log, warn: console.warn, error: console.error };
  const grab = (...a) => lines.push(a.map(String).join(" "));
  console.log = grab; console.warn = grab; console.error = grab;
  try { return { value: await fn(), lines }; } catch (e) { return { error: e, lines }; } finally { Object.assign(console, orig); }
}

const r1 = (v) => Math.round(v * 10) / 10;
const norm = (s) => s.replace(/\s+/g, " ").trim();

export async function inspect(bytes, { structure = true } = {}) {
  const pj = await lib();
  const res = await capture(async () => {
    // no standard font data: a warning about it would reveal a non-embedded font
    const task = pj.getDocument({ data: new Uint8Array(bytes), verbosity: 1, isEvalSupported: false, useSystemFonts: false, disableFontFace: true, stopAtErrors: false });
    const doc = await task.promise;
    const out = { numPages: doc.numPages, pages: [] };
    const destPage = async (dest) => {
      try {
        const d = typeof dest === "string" ? await doc.getDestination(dest) : dest;
        if (!d) return null;
        return d[0] && typeof d[0] === "object" ? await doc.getPageIndex(d[0]) : typeof d[0] === "number" ? d[0] : null;
      } catch { return null; }
    };
    for (let i = 1; i <= doc.numPages; i++) {
      const page = await doc.getPage(i);
      const [x0, y0, x1, y1] = page.view;
      const tc = await page.getTextContent({ includeMarkedContent: false });
      const text = norm(tc.items.map((it) => (it.str ?? "") + (it.hasEOL ? " " : "")).join(""));
      const ann = await page.getAnnotations();
      const links = [];
      for (const a of ann) {
        if (a.subtype !== "Link") continue;
        links.push({ url: a.url ?? a.unsafeUrl ?? null, destPage: a.dest != null ? await destPage(a.dest) : null, rect: a.rect.map(r1) });
      }
      const p = { w: r1(x1 - x0), h: r1(y1 - y0), text, links, otherAnnotations: ann.filter((a) => a.subtype !== "Link").map((a) => a.subtype) };
      if (structure) {
        try { p.structTree = simplifyStruct(await page.getStructTree()); } catch (e) { p.structTreeError = String(e.message || e); }
      }
      out.pages.push(p);
      page.cleanup();
    }
    const ol = await doc.getOutline();
    const walkOl = async (items) => Promise.all((items || []).map(async (it) => ({ title: it.title, page: it.dest ? await destPage(it.dest) : null, url: it.url ?? null, items: await walkOl(it.items) })));
    out.outline = await walkOl(ol);
    const att = await doc.getAttachments();
    out.attachments = att ? Object.values(att).map((a) => ({ name: a.filename, bytes: a.content?.length ?? null, description: a.description ?? null })) : [];
    const md = await doc.getMetadata();
    const info = md.info || {};
    out.metadata = {
      version: info.PDFFormatVersion ?? null, title: info.Title ?? null, author: info.Author ?? null, subject: info.Subject ?? null, keywords: info.Keywords ?? null,
      creator: info.Creator ?? null, producer: info.Producer ?? null, creationDate: info.CreationDate ?? null, language: info.Language ?? null,
      isLinearized: !!info.IsLinearized, xmp: md.metadata ? Object.fromEntries([...md.metadata.getAll ? Object.entries(md.metadata.getAll()) : []].filter(([k]) => /pdfaid|pdfuaid|dc:title|dc:creator|pdf:producer|xmp:creatortool/i.test(k))) : null,
    };
    out.markInfo = await doc.getMarkInfo().catch(() => null);
    out.permissions = await doc.getPermissions().catch(() => null);
    await task.destroy();
    return out;
  });
  if (res.error) return { error: String(res.error?.message ?? res.error), warnings: res.lines };
  return { ...res.value, warnings: res.lines };
}

/** The structure tree as nested role names (alt text / lang kept), content leaves dropped. */
function simplifyStruct(node) {
  if (!node) return null;
  if (node.type === "content" || node.type === "object" || node.type === "annotation") return null;
  const kids = (node.children || []).map(simplifyStruct).filter(Boolean);
  const s = { role: node.role };
  if (node.alt) s.alt = node.alt;
  if (node.lang) s.lang = node.lang;
  if (kids.length) s.kids = kids;
  return s;
}

/** Renders one page with pdf.js onto an @napi-rs/canvas canvas. */
export async function renderPage(bytes, pageIndex, scale) {
  const pj = await lib();
  const res = await capture(async () => {
    const task = pj.getDocument({ data: new Uint8Array(bytes), verbosity: 1, isEvalSupported: false, standardFontDataUrl: STD_FONTS() });
    const doc = await task.promise;
    const page = await doc.getPage(pageIndex + 1);
    const vp = page.getViewport({ scale });
    const w = Math.round(vp.width), h = Math.round(vp.height);
    const { createCanvas } = require("@napi-rs/canvas");
    const canvas = createCanvas(w, h);
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#ffffff"; ctx.fillRect(0, 0, w, h);
    await page.render({ canvasContext: ctx, canvas, viewport: vp, background: "#ffffff" }).promise;
    const data = ctx.getImageData(0, 0, w, h).data;
    await task.destroy();
    return { width: w, height: h, rgba: new Uint8Array(data.buffer, data.byteOffset, data.byteLength) };
  });
  if (res.error) throw res.error;
  return { ...res.value, warnings: res.lines };
}

export async function pageCount(bytes) {
  const pj = await lib();
  const res = await capture(async () => { const t = pj.getDocument({ data: new Uint8Array(bytes), verbosity: 0 }); const d = await t.promise; const n = d.numPages; await t.destroy(); return n; });
  return res.value ?? 0;
}
