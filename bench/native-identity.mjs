// Byte identity of the native addon against the wasm build, on every fixture of the benchmark suite.
//
//   node native-identity.mjs [--filter=<regex>] [--wasm=<file>] [--native=<file.node>] [--no-async] [--no-pdf] [--quiet]
//
// Both backends run in this process through the same public API (js/engine.mjs): the full-profile wasm
// (js/bm_engine.wasm, or --wasm) and the addon (js/native.mjs lookup, or --native). For every fixture:
//   raw RGBA, PNG, JPEG (q85), WebP          renderSync, compared byte for byte
//   measure                                  JSON text
//   renderSvg                                the SVG text
//   native render() (thread pool)            raw, against the native sync result
// plus animations (WebP / APNG / GIF), ICO, HTML sources, image attachments and WOFF2 registration.
// PDF (unless --no-pdf): the pdf-profile wasm (js/bm_engine.pdf.wasm) against the addon's PDF output
// (js/native.mjs `nativePdfBinding`, what `bm-engine/pdf` uses on Node):
//   every 5th fixture as a one-page PDF (viewport), every 10th paged with header / footer bands and tagged,
//   measurePdf, native renderPdf() (thread pool) against the native sync result;
//   tagged / PDF/A / PDF/UA / attachments / links / outline / metadata / page-range variants and errors;
//   image renders through the pdf bindings against the full wasm (the pdf feature must not change an image);
//   and, each in a child process on the native backend with every PDF call replayed on wasm
//   (bench/lib/pdf-identity-hook.mjs): docs/examples/pdf*.mjs, scripts/pdf-test.mjs, scripts/pdf-compare.mjs
//   (takumi-pdf's fixtures; the last two when ref/takumi is present).
// An error counts as identical only when both backends throw the same message. Exit code 1 on any mismatch.
// Results: out/native-identity.json.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { selectCases } from "./fixtures/index.mjs";
import { fontsFor } from "./lib/fonts.mjs";
import { renderOpts } from "./lib/pipeline.mjs";

const BENCH = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(BENCH, "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
if (args.native) process.env.BM_ENGINE_NATIVE_PATH = path.resolve(String(args.native));

const { createBinding } = await import(pathToFileURL(path.join(ROOT, "js", "engine.mjs")).href);
const wasmFile = args.wasm ? path.resolve(String(args.wasm)) : path.join(ROOT, "js", "bm_engine.wasm");
const wasm = createBinding();
wasm.initSync(readFileSync(wasmFile));
const native = await import(pathToFileURL(path.join(ROOT, "js", "node-native.mjs")).href);
if (native.backend !== "native" || wasm.backend !== "wasm") throw new Error("backend mix-up");
for (const [k, v] of Object.entries(wasm.features)) if (native.features[k] !== v) throw new Error(`feature ${k}: wasm ${v}, native ${native.features[k]}`);

const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 16);
const pools = { wasm: new Map(), native: new Map() };
function rendererFor(which, families) {
  const key = families ? families.join(",") : "*";
  const pool = pools[which];
  if (!pool.has(key)) {
    const r = new (which === "wasm" ? wasm : native).Renderer();
    for (const f of fontsFor(families)) r.registerFont({ name: f.name, data: new Uint8Array(readFileSync(f.path)), weight: f.weight, style: f.style });
    pool.set(key, r);
  }
  return pool.get(key);
}

/** Runs `fn` and returns { bytes } (strings as UTF-8) or { error }. */
function attempt(fn) {
  try {
    const v = fn();
    return { bytes: typeof v === "string" ? Buffer.from(v, "utf8") : Buffer.from(v.buffer, v.byteOffset, v.byteLength) };
  } catch (e) {
    return { error: String(e && e.message) };
  }
}

const mismatches = [];
const counts = { compared: 0, identical: 0, bothError: 0, bytes: 0 };
function compare(id, what, a, b) {
  counts.compared++;
  if (a.error !== undefined || b.error !== undefined) {
    if (a.error === b.error) { counts.identical++; counts.bothError++; return true; }
    mismatches.push({ id, what, wasm: a.error !== undefined ? "error: " + a.error : `${a.bytes.length} bytes`, native: b.error !== undefined ? "error: " + b.error : `${b.bytes.length} bytes` });
    return false;
  }
  counts.bytes += a.bytes.length;
  if (a.bytes.length === b.bytes.length && a.bytes.equals(b.bytes)) { counts.identical++; return true; }
  let first = 0;
  const n = Math.min(a.bytes.length, b.bytes.length);
  while (first < n && a.bytes[first] === b.bytes[first]) first++;
  let diff = 0;
  for (let i = 0; i < n; i++) if (a.bytes[i] !== b.bytes[i]) diff++;
  mismatches.push({ id, what, wasm: `${a.bytes.length} bytes ${sha(a.bytes)}`, native: `${b.bytes.length} bytes ${sha(b.bytes)}`, firstDiffAt: first, differingBytes: diff });
  return false;
}

/** The same call on both backends. */
function both(id, what, families, fn) {
  return compare(id, what, attempt(() => fn(rendererFor("wasm", families))), attempt(() => fn(rendererFor("native", families))));
}

const cases = selectCases(args.filter);
const t0 = performance.now();
let asyncChecked = 0;
for (const k of cases) {
  const before = mismatches.length;
  for (const format of ["raw", "png", "jpeg", "webp"]) both(k.id, format, k.fonts, (r) => r.renderSync(k.node, renderOpts(k, format)));
  both(k.id, "measure", k.fonts, (r) => JSON.stringify(r.measureSync(k.node, renderOpts(k, "raw"))));
  both(k.id, "svg", k.fonts, (r) => r.renderSvgSync(k.node, renderOpts(k, "raw")));
  if (!args["no-async"]) {
    // the thread-pool path must give what the calling-thread path gives
    const r = rendererFor("native", k.fonts);
    const sync = attempt(() => r.renderSync(k.node, renderOpts(k, "raw")));
    let pooled;
    try { const v = await r.render(k.node, renderOpts(k, "raw")); pooled = { bytes: Buffer.from(v.buffer, v.byteOffset, v.byteLength) }; }
    catch (e) { pooled = { error: String(e && e.message) }; }
    compare(k.id, "native async vs sync raw", sync, pooled);
    asyncChecked++;
  }
  if (!args.quiet) console.error(`${mismatches.length === before ? "ok  " : "DIFF"} ${k.id}`);
}

// ---- beyond the fixtures: the remaining outputs and input paths ------------------------------------------
if (!args.filter) {
  const anim = cases.filter((k) => k.feature === "animation");
  const byTree = new Map();
  for (const k of anim) { const key = k.id.replace(/-t\d+$/, ""); if (!byTree.has(key)) byTree.set(key, k); }
  for (const [key, k] of byTree) {
    for (const format of ["webp", "apng", "gif"]) {
      both(key, "animation " + format, k.fonts, (r) => r.renderAnimationSync({ scenes: [{ node: k.node, durationMs: 400 }, { node: k.node, durationMs: 200 }], width: 200, height: 100, fps: 10, format, css: k.opts.css }));
    }
  }
  const small = cases.find((k) => k.id === "card-og") ?? cases[0];
  both(small.id, "ico 64x64", small.fonts, (r) => r.renderSync(small.node, { ...renderOpts(small, "ico"), width: 64, height: 64 }));
  both(small.id, "ico too large (error)", small.fonts, (r) => r.renderSync(small.node, { ...renderOpts(small, "ico"), width: 400, height: 300 }));
  both(small.id, "dpr 2", small.fonts, (r) => r.renderSync(small.node, { ...renderOpts(small, "raw"), devicePixelRatio: 2 }));
  both(small.id, "data url", small.fonts, (r) => r.renderAsDataUrlSync(small.node, renderOpts(small, "png")));
  const html = "<style>.c{display:flex;gap:8px;padding:12px;background:linear-gradient(90deg,#fde68a,#f0abfc)} b{color:#1d4ed8}</style>" +
    "<div class=c><p style='font-family:Inter;font-size:22px'>Hello <b>native</b> &amp; wasm éè 😀</p><table><tr><td>1<td>2</table></div>";
  for (const format of ["raw", "png"]) both("html", format, undefined, (r) => r.renderSync(html, { width: 480, height: 200, format }));
  both("html", "measure", undefined, (r) => JSON.stringify(r.measureSync(html, { width: 480, height: 200 })));
  both("html", "svg", undefined, (r) => r.renderSvgSync(html, { width: 480, height: 200 }));
  both("json-text", "raw", undefined, (r) => r.renderSync({ json: JSON.stringify(small.node) }, renderOpts(small, "raw")));
  // image attachments: encoded bytes as `src`, raw RGBA (straight and premultiplied), the `images` option
  const png = rendererFor("wasm", small.fonts).renderSync(small.node, { ...renderOpts(small, "png"), width: 120, height: 63 });
  const rgba = new Uint8Array(16 * 16 * 4).map((_, i) => (i * 37 + (i >> 3)) & 255);
  const imgTree = (src) => ({ type: "container", style: { display: "flex", width: 300, height: 200, backgroundColor: "#eee", gap: 8 }, children: [{ type: "image", src, style: { width: 140, height: 100 } }, { type: "image", src: "pic", width: 64, height: 64 }] });
  const images = [{ src: "pic", data: png }, { src: "unused", data: rgba }];
  both("images", "encoded src", undefined, (r) => r.renderSync(imgTree(png), { width: 300, height: 200, format: "raw", images }));
  both("images", "rgba src", undefined, (r) => r.renderSync(imgTree({ width: 16, height: 16, data: rgba }), { width: 300, height: 200, format: "png", images }));
  both("images", "premultiplied rgba src", undefined, (r) => r.renderSync(imgTree({ width: 16, height: 16, data: rgba, premultiplied: true }), { width: 300, height: 200, format: "raw", images }));
  both("images", "rgba wrong length (error)", undefined, (r) => r.renderSync(imgTree({ width: 16, height: 15, data: rgba }), { width: 300, height: 200, images }));
  both("images", "rgba zero height (error)", undefined, (r) => r.renderSync(imgTree({ width: 16, height: 0, data: rgba }), { width: 300, height: 200, images }));
  both("images", "svg output with images", undefined, (r) => r.renderSvgSync(imgTree(png), { width: 300, height: 200, images }));
  both("images", "Buffer src", undefined, (r) => r.renderSync(imgTree(Buffer.from(png)), { width: 300, height: 200, format: "raw", images }));
  // error messages
  both("errors", "invalid JSON", undefined, (r) => r.renderSync({ json: "{nope" }, {}));
  both("errors", "invalid options", undefined, (r) => r.renderSync(small.node, { format: "bmp" }));
  both("errors", "lone surrogate text", undefined, (r) => r.renderSync({ type: "text", text: "a\ud800b", style: { fontFamily: "Inter" } }, { width: 100, height: 40, format: "raw" }));
  both("errors", "animation without scenes", undefined, (r) => r.renderAnimationSync({ scenes: [], width: 10, height: 10, fps: 10 }));
  both("errors", "bad font", undefined, (r) => JSON.stringify(r.registerFont(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]))));
  both("errors", "empty font", undefined, (r) => JSON.stringify(r.registerFont(new Uint8Array(0))));
  both("fonts", "unregister unknown", undefined, (r) => String(r.unregisterFont("No Such Family")));
  // WOFF2: decoded inside the engine on both; then the same text must render the same
  try {
    const { default: wawoff2 } = await import("wawoff2");
    const woff2 = new Uint8Array(await wawoff2.compress(readFileSync(path.join(ROOT, "assets", "fonts", "Inter-Regular.ttf"))));
    const run = (B) => {
      const r = new B.Renderer();
      try {
        const fams = JSON.stringify(r.registerFont({ name: "W2", data: woff2 }));
        const px = r.renderSync({ type: "text", text: "WOFF2 parity", style: { fontFamily: "W2", fontSize: 30 } }, { width: 260, height: 50, format: "raw" });
        return fams + sha(px);
      } finally { r.free(); }
    };
    compare("woff2", "register + render", attempt(() => run(wasm)), attempt(() => run(native)));
  } catch (e) {
    console.error("woff2 check skipped:", e && e.message);
  }
}

// ---- PDF -----------------------------------------------------------------------------------------------
const pdfStats = { fixtures: 0, compared: 0, asyncChecked: 0, scripts: [] };
if (!args["no-pdf"]) {
  const before = counts.compared;
  const { nativePdfBinding, nativeError } = await import(pathToFileURL(path.join(ROOT, "js", "native.mjs")).href);
  const npdf = nativePdfBinding();
  if (!npdf) throw new Error("the native addon has no PDF output: " + nativeError());
  const wpdf = createBinding();
  wpdf.initSync(readFileSync(path.join(ROOT, "js", "bm_engine.pdf.wasm")));
  if (!wpdf.features.pdf || !npdf.features.pdf || native.features.pdf) throw new Error("pdf feature mix-up");
  for (const [k, v] of Object.entries(wpdf.features)) if (npdf.features[k] !== v) throw new Error(`pdf binding feature ${k}: wasm ${v}, native ${npdf.features[k]}`);
  pools.wpdf = new Map();
  pools.npdf = new Map();
  const pdfRenderer = (which, families) => {
    const key = families ? families.join(",") : "*";
    const pool = pools[which];
    if (!pool.has(key)) {
      const r = new (which === "wpdf" ? wpdf : npdf).Renderer();
      for (const f of fontsFor(families)) r.registerFont({ name: f.name, data: new Uint8Array(readFileSync(f.path)), weight: f.weight, style: f.style });
      pool.set(key, r);
    }
    return pool.get(key);
  };
  const bothPdf = (id, what, families, fn) => compare(id, what, attempt(() => fn(pdfRenderer("wpdf", families))), attempt(() => fn(pdfRenderer("npdf", families))));
  const band = (text) => ({ type: "container", style: { display: "flex", justifyContent: "space-between", width: "100%", fontSize: 9, color: "#555", fontFamily: "Inter" },
    children: [{ type: "text", text }, { type: "container", tagName: "span", className: "pageNumber" }, { type: "container", tagName: "span", className: "totalPages" }] });
  // (the fixtures' CSS and image options apply; the size becomes the viewport / the page)
  const pdfOpts = (k, extra) => { const { width, height, format: _f, devicePixelRatio: _d, quality: _q, ...rest } = renderOpts(k, "raw"); return { ...rest, uncoveredText: "blank", ...extra(width, height) }; };
  const step = args.filter ? 1 : 5;
  for (let i = 0; i < cases.length; i += step) {
    const k = cases[i];
    const b0 = mismatches.length;
    pdfStats.fixtures++;
    const vp = pdfOpts(k, (width, height) => ({ viewport: { width, height } }));
    bothPdf(k.id, "pdf viewport", k.fonts, (r) => r.renderPdfSync(k.node, vp));
    bothPdf(k.id, "pdf measure", k.fonts, (r) => JSON.stringify(r.measurePdfSync(k.node, vp)));
    // (the pdf feature compiled in must leave the image path alone: the pdf-profile wasm and the addon's pdf
    // binding against the full wasm)
    const img = attempt(() => rendererFor("wasm", k.fonts).renderSync(k.node, renderOpts(k, "raw")));
    compare(k.id, "image on the pdf wasm vs full wasm", img, attempt(() => pdfRenderer("wpdf", k.fonts).renderSync(k.node, renderOpts(k, "raw"))));
    compare(k.id, "image on the native pdf binding vs full wasm", img, attempt(() => pdfRenderer("npdf", k.fonts).renderSync(k.node, renderOpts(k, "raw"))));
    if (i % (2 * step) === 0) {
      const paged = pdfOpts(k, () => ({ size: "a5", landscape: i % (4 * step) === 0, margin: { top: 40, bottom: 40, left: 24, right: 24 }, header: band(k.id), footer: band("bm-engine"),
        tagged: true, metadata: { title: k.id, authors: ["bench"], creationDate: "2026-01-02T03:04:05Z" } }));
      bothPdf(k.id, "pdf paged tagged", k.fonts, (r) => r.renderPdfSync(k.node, paged));
    }
    if (!args["no-async"]) {
      const r = pdfRenderer("npdf", k.fonts);
      const sync = attempt(() => r.renderPdfSync(k.node, vp));
      let pooled;
      try { const v = await r.renderPdf(k.node, vp); pooled = { bytes: Buffer.from(v.buffer, v.byteOffset, v.byteLength) }; }
      catch (e) { pooled = { error: String(e && e.message) }; }
      compare(k.id, "native async vs sync pdf", sync, pooled);
      pdfStats.asyncChecked++;
    }
    if (!args.quiet) console.error(`${mismatches.length === b0 ? "ok  " : "DIFF"} pdf ${k.id}`);
  }
  if (!args.filter) {
    // a long document: pagination, links, anchors, outline, lists, tables, RTL, attachments, conformance levels
    const para = "The quick brown fox jumps over the lazy dog; sphinx of black quartz, judge my vow. ";
    const doc = "<style>body{font-family:Inter;font-size:13px;line-height:1.5} h1{font-size:24px;break-before:page} h2{font-size:17px} " +
      "table{border-collapse:collapse;width:100%} td,th{border:1px solid #94a3b8;padding:4px 6px} thead{background:#e2e8f0} .rtl{direction:rtl} " +
      ".f{float:right;width:120px;height:80px;background:#bae6fd;margin:0 0 8px 8px} .ind{text-indent:2em} .sc{font-variant-caps:small-caps} " +
      ".el{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;width:180px} @page{margin:48px}</style>" +
      "<h1 id=a>Alpha</h1><p class=ind>" + para.repeat(12) + "<a href='https://example.com/x?y=1'>a link</a> and <a href='#c'>see Gamma (page <span class=targetPageNumber></span>)</a>.</p>" +
      "<div class=f></div><p>" + para.repeat(8) + "</p><ol start=3><li>one<li value=9>nine<ul><li>nested <b>bold</b></ul><li>ten</ol>" +
      "<h2 id=b>Beta</h2><p class=sc>Small Caps Text " + para + "</p><p class=el>" + para + "</p>" +
      "<p class=rtl>\u05e9\u05dc\u05d5\u05dd \u05e2\u05d5\u05dc\u05dd abc 123 <span style='background:#fde68a;padding:0 4px'>\u0645\u0631\u062d\u0628\u0627</span> " + para + "</p>" +
      "<table><thead><tr><th>#<th>Name<th>Value</thead><tbody>" + Array.from({ length: 60 }, (_, i) => `<tr><td>${i}<td>row ${i} \u{1F600}<td>${(i * 37) % 101}</tr>`).join("") + "</tbody></table>" +
      "<h1 id=c>Gamma</h1><p>A <span style='border:1px solid red'>span with <div style='background:#eee'>a block inside</div> an inline</span> box.</p>" +
      "<table class=rtl><tr><td>\u05d0<td>\u05d1<td>\u05d2</table><p>" + para.repeat(30) + "</p>";
    const meta = { title: "Identity", authors: ["A", "B"], description: "d", keywords: ["k1", "k2"], creator: "bench", language: "en", creationDate: "2026-03-04T05:06:07Z" };
    const files = [{ name: "data.xml", data: new TextEncoder().encode("<a>1</a>"), mimeType: "application/xml", description: "payload" }, { name: "note.txt", data: "plain text", mimeType: "text/plain" }];
    const variants = {
      "a4": { size: "a4" },
      "letter landscape bands": { size: "letter", landscape: true, margin: { top: "auto", bottom: 36, left: 30, right: 30 }, header: band("header"), footer: "<div style='font:9px Inter;text-align:center'>page <span class=pageNumber></span> / <span class=totalPages></span></div>" },
      "viewport": { viewport: { width: 640 } },
      "metadata outline": { size: "a4", metadata: meta, outline: true },
      "tagged": { size: "a4", tagged: true, metadata: meta, lang: "en" },
      "tagged ua1": { size: "a4", tagged: "ua1", metadata: meta, lang: "en" },
      "pdfa 2b": { size: "a4", pdfa: "2b", metadata: meta },
      "pdfa 2a": { size: "a4", pdfa: "2a", metadata: meta, lang: "en" },
      "pdfa 3b attachments": { size: "a4", pdfa: "3b", metadata: meta, attachments: files },
      "pdfa 4 ua2": { size: "a4", pdfa: "4", tagged: "ua2", metadata: meta, lang: "en" },
      "attachments": { size: "a5", attachments: files },
      "page ranges": { size: "a5", pageRanges: [1, { from: 3, to: 4 }] },
      "first page rules": { size: "a5", header: band("h"), pages: { first: { header: false } }, backgroundColor: "#fffbeb" },
      "css variables": { size: "a5", css: "p{color:var(--ink)}", cssVariables: { ink: "#1d4ed8" } },
      "error: viewport + size": { viewport: { width: 100 }, size: "a4" },
      "error: bad size": { size: "a99" },
      "error: pdfa 2b attachments": { pdfa: "2b", attachments: files },
      "error: bad date": { metadata: { creationDate: "yesterday" } },
    };
    for (const [name, o] of Object.entries(variants)) {
      bothPdf("pdf-doc", name, undefined, (r) => r.renderPdfSync(doc, { uncoveredText: "blank", ...o }));
      if (!name.startsWith("error")) bothPdf("pdf-doc", name + " (measure)", undefined, (r) => JSON.stringify(r.measurePdfSync(doc, { uncoveredText: "blank", ...o })));
    }
    bothPdf("pdf-doc", "uncovered text (error)", undefined, (r) => r.renderPdfSync("<p style='font-family:Inter'>\u{10FFFD} \u6f22</p>", {}));
    bothPdf("pdf-doc", "blur filter (error)", undefined, (r) => r.renderPdfSync("<p style='filter:blur(2px)'>x</p>", { uncoveredText: "blank" }));
    // (the fixes of the pdf-bugs branch: no font at all, a content-sized page of no height, paint phases,
    // overflow markers, image-rendering)
    compare("pdf-doc", "no font registered (error)", attempt(() => new wpdf.Renderer().renderPdfSync("<p>Hello</p>", {})), attempt(() => new npdf.Renderer().renderPdfSync("<p>Hello</p>", {})));
    bothPdf("pdf-doc", "content-sized page of no height (error)", undefined, (r) => r.renderPdfSync("<div></div>", { viewport: { width: 300 } }));
    bothPdf("pdf-doc", "content-sized page, fractional height", undefined, (r) => r.renderPdfSync("<div style='height:10.2px;margin:5px'></div>", { viewport: { width: 300 } }));
    bothPdf("pdf-doc", "paint phases", undefined, (r) => r.renderPdfSync("<style>body{font-family:Inter}</style><div style='background:#eee'><p style='background:#cfc'>flow text</p>" +
      "<div style='float:left;width:90px;height:40px;margin-top:-30px;background:#f00'>float</div><div style='overflow:hidden;height:30px'>clipped <span style='display:inline-block;width:20px;height:10px;background:#0f0'></span> text" +
      "<div style='float:right;width:30px;height:30px;background:#00f'></div></div><div style='display:flex'><div style='background:#ff0'>item</div></div>" +
      "<div style='position:relative;margin-top:-10px;background:#0ff'>positioned</div></div>", { viewport: { width: 300 }, uncoveredText: "blank" }));
    bothPdf("pdf-doc", "overflow markers", undefined, (r) => r.renderPdfSync("<style>div{font-family:Inter;width:120px;white-space:nowrap;overflow:hidden}</style><div style='text-overflow:ellipsis'>Hello wonderful world</div>" +
      "<div style='text-overflow:\"[more]\"'>Hello wonderful world</div><div style='white-space:normal;line-clamp:2'>Hello wonderful world of text that goes on and on</div>", { viewport: { width: 200 }, uncoveredText: "blank" }));
    bothPdf("pdf-doc", "image-rendering pixelated", undefined, (r) => r.renderPdfSync({ type: "image", src: "pic", style: { width: 64, height: 64, imageRendering: "pixelated" } }, { viewport: { width: 80, height: 80 }, images: [{ src: "pic", data: rendererFor("wasm").renderSync({ type: "container", style: { width: 4, height: 4, backgroundColor: "red" } }, { width: 4, height: 4 }) }] }));
    const small = cases.find((k) => k.id === "card-og") ?? cases[0];
    const png = rendererFor("wasm", small.fonts).renderSync(small.node, { ...renderOpts(small, "png"), width: 120, height: 63 });
    bothPdf("pdf-doc", "images", undefined, (r) => r.renderPdfSync({ type: "container", style: { display: "flex", gap: 8 }, children: [{ type: "image", src: png, style: { width: 140, height: 100 } }, { type: "image", src: "pic", width: 64, height: 64 }] },
      { viewport: { width: 300, height: 200 }, images: [{ src: "pic", data: png }] }));
    compare("pdf-doc", "renderPdf on the image entries (error)", attempt(() => rendererFor("wasm").renderPdfSync(doc, {})), attempt(() => rendererFor("native").renderPdfSync(doc, {})));
    // every PDF call of the existing scripts, replayed (child processes on the native backend)
    const hook = pathToFileURL(path.join(BENCH, "lib", "pdf-identity-hook.mjs")).href;
    const scripts = readdirSync(path.join(ROOT, "docs", "examples")).filter((f) => /^pdf.*\.mjs$/.test(f)).map((f) => [path.join("docs", "examples", f)]);
    if (existsSync(path.join(ROOT, "ref", "takumi", "assets", "fonts"))) {
      scripts.push([path.join("scripts", "pdf-test.mjs"), "--no-build"]);
      if (existsSync(path.join(ROOT, "ref", "takumi", "takumi-pdf", "tests", "fixtures-generated"))) scripts.push([path.join("scripts", "pdf-compare.mjs")]);
    } else console.error("pdf scripts skipped: ref/takumi is not present");
    mkdirSync(path.join(BENCH, "out"), { recursive: true });
    for (const [script, ...rest] of scripts) {
      const outFile = path.join(BENCH, "out", "pdf-identity-child.json");
      rmSync(outFile, { force: true });
      const r = spawnSync(process.execPath, ["--import", hook, path.join(ROOT, script), ...rest], { cwd: ROOT, encoding: "utf8", maxBuffer: 1 << 28,
        env: { ...process.env, BM_ENGINE_BACKEND: "native", BM_PDF_IDENTITY_OUT: outFile } });
      const id = script.split(path.sep).join("/");
      let res = null;
      try { res = JSON.parse(readFileSync(outFile, "utf8")); } catch {}
      rmSync(outFile, { force: true });
      if (r.status !== 0 || !res) {
        counts.compared++;
        mismatches.push({ id, what: "script on the native backend", native: `exit ${r.status}: ${String(r.stderr || r.stdout).trim().split("\n").slice(-3).join(" | ").slice(0, 400)}`, wasm: "-" });
        continue;
      }
      counts.compared += res.compared;
      counts.identical += res.identical;
      counts.bothError += res.bothError;
      counts.bytes += res.bytes;
      for (const m of res.mismatches) mismatches.push({ id, ...m });
      pdfStats.scripts.push({ script: id, compared: res.compared, identical: res.identical, calls: res.calls });
      if (!args.quiet) console.error(`${res.mismatches.length ? "DIFF" : "ok  "} ${id}: ${res.compared} PDF calls replayed on wasm`);
    }
  }
  pdfStats.compared = counts.compared - before;
}

const ms = performance.now() - t0;
for (const pool of Object.values(pools)) for (const r of pool.values()) r.free();
const out = { date: new Date().toISOString(), node: process.version, platform: `${process.platform}-${process.arch}`, wasm: path.relative(ROOT, wasmFile), fixtures: cases.length, ...counts, asyncChecked, pdf: pdfStats, mismatches };
mkdirSync(path.join(BENCH, "out"), { recursive: true });
writeFileSync(path.join(BENCH, "out", "native-identity.json"), JSON.stringify(out, null, 1));
console.log(`native vs wasm: ${cases.length} fixtures, ${counts.compared} comparisons, ${counts.identical} identical (${counts.bothError} of them the same error on both), ` +
  `${mismatches.length} mismatches, ${(counts.bytes / 1e6).toFixed(1)} MB compared, ${(ms / 1000).toFixed(1)} s` +
  (args["no-pdf"] ? "" : `; PDF: ${pdfStats.fixtures} fixtures + variants + ${pdfStats.scripts.length} scripts replayed = ${pdfStats.compared} of the comparisons`));
for (const m of mismatches.slice(0, 40)) console.log("  MISMATCH", JSON.stringify(m));
process.exit(mismatches.length ? 1 : 0);
