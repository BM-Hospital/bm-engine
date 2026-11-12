// Independent PDF rasterisers, each returning straight RGBA8 over white:
//   pdfium   @hyzyla/pdfium (PDFium compiled to wasm; Chrome's PDF engine)
//   mupdf    mupdf (Artifex's official MuPDF wasm build)
//   pdfjs    pdf.js (Firefox's PDF engine) drawing on @napi-rs/canvas (Skia)
// rasterise(name, bytes, pageIndex, dpi) -> { width, height, rgba, warnings }. A page of W x H pt at `dpi` is
// round(W * dpi / 72) x round(H * dpi / 72) px (96 dpi: one pixel per CSS px, the size of bm's image render).
import { createRequire } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { PDF_DIR } from "./tools.mjs";
import { renderPage as pdfjsRender, pageCount as pdfjsPages } from "./pdfjs.mjs";

const require = createRequire(path.join(PDF_DIR, "package.json"));
export const RASTERISERS = ["pdfium", "mupdf", "pdfjs"];

let pdfiumLib, mupdfLib;
async function pdfium() {
  if (!pdfiumLib) {
    const { PDFiumLibrary } = await import(pathToFileURL(require.resolve("@hyzyla/pdfium")).href);
    pdfiumLib = await PDFiumLibrary.init();
  }
  return pdfiumLib;
}
async function mupdf() { return (mupdfLib ??= await import(pathToFileURL(require.resolve("mupdf")).href)); }

/** Captures console output (mupdf.js prints its warnings there). */
async function capture(fn) {
  const lines = [];
  const orig = { log: console.log, warn: console.warn, error: console.error };
  const grab = (...a) => lines.push(a.map(String).join(" "));
  console.log = grab; console.warn = grab; console.error = grab;
  try { return { value: await fn(), lines }; } finally { Object.assign(console, orig); }
}

function overWhite(rgba) {
  for (let i = 0; i < rgba.length; i += 4) {
    const a = rgba[i + 3];
    if (a === 255) continue;
    const f = a / 255;
    rgba[i] = Math.round(rgba[i] * f + 255 * (1 - f)); rgba[i + 1] = Math.round(rgba[i + 1] * f + 255 * (1 - f)); rgba[i + 2] = Math.round(rgba[i + 2] * f + 255 * (1 - f)); rgba[i + 3] = 255;
  }
  return rgba;
}

/** Cached open documents (one at a time per rasteriser: corpus PDFs are processed one after the other). */
const open = { pdfium: null, mupdf: null };
async function docFor(name, bytes) {
  const o = open[name];
  if (o && o.bytes === bytes) return o.doc;
  if (o) { try { o.doc.destroy(); } catch {} }
  let doc;
  if (name === "pdfium") doc = await (await pdfium()).loadDocument(new Uint8Array(bytes));
  else { const m = await mupdf(); doc = m.Document.openDocument(new Uint8Array(bytes), "application/pdf"); }
  open[name] = { bytes, doc };
  return doc;
}

export async function pageCountOf(name, bytes) {
  if (name === "pdfjs") return pdfjsPages(bytes);
  const doc = await docFor(name, bytes);
  return name === "pdfium" ? doc.getPageCount() : doc.countPages();
}

export async function rasterise(name, bytes, pageIndex, dpi) {
  const scale = dpi / 72;
  if (name === "pdfjs") {
    const r = await pdfjsRender(bytes, pageIndex, dpi / 72);
    return { width: r.width, height: r.height, rgba: overWhite(r.rgba), warnings: r.warnings };
  }
  const { value, lines } = await capture(async () => {
    const doc = await docFor(name, bytes);
    if (name === "pdfium") {
      const page = doc.getPage(pageIndex);
      const r = await page.render({ scale, colorSpace: "RGBA", transparent: false });
      return { width: r.width, height: r.height, rgba: overWhite(new Uint8Array(r.data)) };
    }
    const m = await mupdf();
    const page = doc.loadPage(pageIndex);
    const pix = page.toPixmap(m.Matrix.scale(scale, scale), m.ColorSpace.DeviceRGB, false, true);
    const w = pix.getWidth(), h = pix.getHeight(), n = pix.getNumberOfComponents(), stride = pix.getStride();
    const px = pix.getPixels();
    const rgba = new Uint8Array(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const s = y * stride + x * n, d = (y * w + x) * 4;
      rgba[d] = px[s]; rgba[d + 1] = px[s + 1]; rgba[d + 2] = px[s + 2]; rgba[d + 3] = 255;
    }
    pix.destroy?.(); page.destroy?.();
    return { width: w, height: h, rgba };
  });
  return { ...value, warnings: lines };
}

export function closeAll() { for (const k of Object.keys(open)) { try { open[k]?.doc.destroy(); } catch {} open[k] = null; } }
