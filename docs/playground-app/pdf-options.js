// The PDF options panel of the playground <-> `PdfRenderOptions` (js/pdf-types.d.mts). Pure functions, no DOM:
// app.js builds every render from them, the "Copy code" snippet prints the same object, and the automated test
// imports this module in Node.js to render the PDF templates outside the browser.
//
// Panel state (all strings / booleans, as the form holds them; an empty number field means "not set"):
//   layout "paged" | "viewport"; size (PageSizeName | "custom"), cw / ch (custom size, CSS px), landscape;
//   mt / mr / mb / ml (margin sides, empty = "auto"); vw / vh (viewport, empty height = fit the content);
//   header / footer (HTML, or a node tree as JSON), plainFirst (pages.first draws neither band); pageRanges
//   ("1, 3-5, 7-"); bg (backgroundColor); title / author / subject / keywords / lang / creationDate; outline;
//   tagged ("true" | "false" | "ua1" | "ua2"); pdfa ("" | Pdfa); uncovered (UncoveredText).

/** `PageSizeName` of the typings, in the order the select lists them. */
export const PAGE_SIZES = ["a4", "letter", "a5", "a3", "legal", "ledger", "b4", "b5", "jis-b4", "jis-b5"];
/** `Pdfa` of the typings. */
export const PDFA_LEVELS = ["2a", "2b", "2u", "3a", "3b", "3u", "4", "4f"];
/** `UncoveredText` of the typings. */
export const UNCOVERED = ["error", "placeholder", "blank"];
/** `tagged` values the typings allow with each `pdfa` level (`ConformanceOptions`); "true" is the default. */
export function allowedTagged(pdfa) {
  switch (pdfa) {
    case "2a": case "3a": return ["true", "ua1"];
    case "2b": case "2u": case "3b": case "3u": return ["true", "false", "ua1"];
    case "4": case "4f": return ["true", "false", "ua2"];
    default: return ["true", "false", "ua1", "ua2"];
  }
}

export const defaultPdf = () => ({
  layout: "paged", size: "a4", cw: "600", ch: "800", landscape: false, mt: "", mr: "", mb: "", ml: "", vw: "600", vh: "",
  header: "", footer: "", plainFirst: false, pageRanges: "", bg: "",
  title: "", author: "", subject: "", keywords: "", lang: "", creationDate: "", outline: false,
  tagged: "true", pdfa: "", uncovered: "error",
});

const EN = {
  badNumber: "Not a number: {v}", badBand: "{which} is not valid JSON: {msg}", badRanges: "Page ranges: cannot read \"{v}\" (write e.g. 1, 3-5, 7-)",
};
const fmt = (t, key, vars) => { let s = t ? t(key, vars) : EN[key]; if (s === key) s = EN[key]; for (const [k, v] of Object.entries(vars || {})) s = s.replaceAll(`{${k}}`, v); return s; };

function num(v, t) {
  const s = String(v ?? "").trim();
  if (!s) return undefined;
  const n = Number(s);
  if (!Number.isFinite(n)) throw new Error(fmt(t, "badNumber", { v: s }));
  return n;
}
/** A band field: empty -> undefined, `{...}` -> node tree (JSON), anything else -> HTML string. */
export function band(text, which, t) {
  const s = String(text ?? "").trim();
  if (!s) return undefined;
  if (s.startsWith("{")) {
    try { return JSON.parse(s); } catch (e) { throw new Error(fmt(t, "badBand", { which, msg: e.message })); }
  }
  return s;
}
/** "1, 3-5, 7-, -2" -> [1, { from: 3, to: 5 }, { from: 7 }, { to: 2 }] (`PageRange[]`). Range checks are the engine's. */
export function parseRanges(text, t) {
  const s = String(text ?? "").trim();
  if (!s) return undefined;
  return s.split(/[,;\s]+/).filter(Boolean).map((tok) => {
    if (/^\d+$/.test(tok)) return Number(tok);
    const m = /^(\d*)-(\d*)$/.exec(tok);
    if (!m || (!m[1] && !m[2])) throw new Error(fmt(t, "badRanges", { v: tok }));
    const r = {};
    if (m[1]) r.from = Number(m[1]);
    if (m[2]) r.to = Number(m[2]);
    return r;
  });
}
const list = (s) => String(s ?? "").split(",").map((x) => x.trim()).filter(Boolean);

/** Panel state -> `PdfRenderOptions` without the resources (`css`, `images`; see withResources). Throws on input
 *  the panel cannot express; every other check (sizes, conformance, ...) is left to the engine, whose message the
 *  playground shows verbatim. */
export function buildPdfOptions(p, t) {
  const o = {};
  if (p.layout === "viewport") {
    o.viewport = { width: num(p.vw, t) ?? 600 };
    const h = num(p.vh, t);
    if (h !== undefined) o.viewport.height = h;
  } else {
    o.size = p.size === "custom" ? { width: num(p.cw, t) ?? 0, height: num(p.ch, t) ?? 0 } : p.size || "a4";
    if (p.landscape) o.landscape = true;
    const sides = [p.mt, p.mr, p.mb, p.ml].map((v) => num(v, t));
    if (sides.every((v) => v !== undefined) && sides.every((v) => v === sides[0])) o.margin = sides[0];
    else if (sides.some((v) => v !== undefined)) {
      o.margin = {};
      ["top", "right", "bottom", "left"].forEach((k, i) => { if (sides[i] !== undefined) o.margin[k] = sides[i]; });
    }
    const header = band(p.header, "header", t), footer = band(p.footer, "footer", t);
    if (header !== undefined) o.header = header;
    if (footer !== undefined) o.footer = footer;
    if (p.plainFirst && (header !== undefined || footer !== undefined)) {
      o.pages = { first: {} };
      if (header !== undefined) o.pages.first.header = false;
      if (footer !== undefined) o.pages.first.footer = false;
    }
    const ranges = parseRanges(p.pageRanges, t);
    if (ranges) o.pageRanges = ranges;
  }
  if (String(p.bg ?? "").trim()) o.backgroundColor = p.bg.trim();
  if (String(p.lang ?? "").trim()) o.lang = p.lang.trim();
  const md = {};
  if (String(p.title ?? "").trim()) md.title = p.title.trim();
  if (list(p.author).length) md.authors = list(p.author);
  if (String(p.subject ?? "").trim()) md.description = p.subject.trim();
  if (list(p.keywords).length) md.keywords = list(p.keywords);
  if (String(p.creationDate ?? "").trim()) md.creationDate = p.creationDate.trim();
  if (Object.keys(md).length) o.metadata = md;
  if (p.outline) o.outline = true;
  if (p.tagged === "false") o.tagged = false;
  else if (p.tagged === "ua1" || p.tagged === "ua2") o.tagged = p.tagged;
  if (p.pdfa) o.pdfa = p.pdfa;
  if (p.uncovered && p.uncovered !== "error") o.uncoveredText = p.uncovered;
  return o;
}

/** The subset `measure()` takes (`PdfMeasureOptions`): page geometry or the viewport, plus layout resources. */
export function measureOptions(o) {
  const m = {};
  for (const k of ["viewport", "size", "landscape", "css", "images", "lang"]) if (o[k] !== undefined) m[k] = o[k];
  return m;
}

/** Adds the playground's resources: the CSS panel and the images panel ({ src, b64 }). */
export function withResources(o, { css, images, bytesOf }) {
  const r = { ...o };
  if (css && css.trim()) r.css = [css];
  if (images && images.length) r.images = images.map((im) => ({ src: im.src, data: bytesOf(im) }));
  return r;
}

/** The source of a render: an HTML string, or the node tree of the JSON / Tailwind editor. */
export function parseSource(kind, text, t) {
  if (kind === "html") return text;
  try { return JSON.parse(text); } catch (e) { throw new Error(t ? t("invalidJson", { msg: e.message }) : "Invalid JSON: " + e.message); }
}

const ident = (s) => /^[A-Za-z_$][\w$]*$/.test(s) ? s : JSON.stringify(s);
/** JS object literal (unquoted keys where possible), indented like the snippet. */
function lit(v, ind = "") {
  if (Array.isArray(v)) {
    if (!v.length) return "[]";
    if (v.every((x) => x === null || typeof x !== "object")) return "[" + v.map((x) => JSON.stringify(x)).join(", ") + "]";
    return "[\n" + v.map((x) => ind + "  " + lit(x, ind + "  ")).join(",\n") + ",\n" + ind + "]";
  }
  if (v && typeof v === "object") {
    const e = Object.entries(v).filter(([, x]) => x !== undefined);
    if (!e.length) return "{}";
    const one = "{ " + e.map(([k, x]) => `${ident(k)}: ${lit(x, ind)}`).join(", ") + " }";
    if (one.length <= 100 && !one.includes("\n")) return one;
    return "{\n" + e.map(([k, x]) => `${ind}  ${ident(k)}: ${lit(x, ind + "  ")}`).join(",\n") + ",\n" + ind + "}";
  }
  return JSON.stringify(v);
}
const tpl = (s) => "`" + s.replace(/\\/g, "\\\\").replace(/`/g, "\\`").replace(/\$\{/g, "\\${") + "`";

/** A runnable Node.js ES module that reproduces the current render with `PdfRenderer` from "bm-engine/pdf".
 *  fonts: [{ file, name?, weight?, style?, builtin }] (built-in = the playground's default fonts, which live in
 *  the bm-engine repository under assets/fonts/; uploaded files are read from the working directory). */
export function pdfSnippet({ kind, text, css, p, images = [], fonts = [] }) {
  const o = buildPdfOptions(p);
  const src = kind === "html" ? tpl(text) : lit(JSON.parse(text));
  const out = [
    "// bm-engine PDF playground export: node render-pdf.mjs  (npm install bm-engine; Node.js 20+)",
    "import { readFileSync, writeFileSync } from \"node:fs\";",
    "import { PdfRenderer } from \"bm-engine/pdf\";",
    "",
    "const pdf = new PdfRenderer();",
    "// bm-engine bundles no font. The playground's default fonts are in the bm-engine repository (assets/fonts/);",
    "// point these paths at your own copies.",
  ];
  for (const f of fonts) {
    const path = f.builtin ? `assets/fonts/${f.file}` : f.file;
    out.push(f.name
      ? `pdf.registerFont({ name: ${JSON.stringify(f.name)}, data: readFileSync(${JSON.stringify(path)}), weight: ${f.weight ?? 400}, style: ${JSON.stringify(f.style ?? "normal")} });`
      : `pdf.registerFont(readFileSync(${JSON.stringify(path)}));`);
  }
  out.push("", `const source = ${src};`, "");
  const lines = Object.entries(o).map(([k, v]) => `  ${ident(k)}: ${lit(v, "  ")},`);
  if (css && css.trim()) lines.push(`  css: [${tpl(css)}],`);
  if (images.length) {
    lines.push("  images: [");
    for (const im of images) lines.push(`    { src: ${JSON.stringify(im.src)}, data: Buffer.from(${JSON.stringify(im.b64)}, "base64") },`);
    lines.push("  ],");
  }
  const optText = lines.length ? "{\n" + lines.join("\n") + "\n}" : "{}";
  out.push(`const bytes = await pdf.render(source, ${optText});`, "writeFileSync(\"bm-engine.pdf\", bytes);", "console.log(`bm-engine.pdf: ${bytes.length} bytes`);", "");
  return out.join("\n");
}

/** Pages of a PDF file without a parser: counts the page objects (`/Type /Page`, not `/Pages`). bm-engine writes
 *  them uncompressed; when a writer hides them in object streams this returns 0 and the caller says "unknown". */
export function countPages(bytes) {
  const s = new TextDecoder("latin1").decode(bytes);
  return (s.match(/\/Type\s*\/Page(?![s\w])/g) || []).length;
}
