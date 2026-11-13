// Examples for docs/{en,vi}/pdf/api.md (PDF API reference). Run: node docs/examples/run-all.mjs pdf-api
import "./_lib.mjs";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
const pageCount = (b) => (latin1(b).match(/\/Type\/Page[^s]/g) || []).length;
const mediaBox = (b) => /\/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]/.exec(latin1(b)).slice(1).map(Number);
/** Text of a PDF via pdftotext when it is installed (null otherwise). */
function text(bytes) {
  const dir = mkdtempSync(join(tmpdir(), "bm-pdf-api-"));
  try {
    writeFileSync(join(dir, "in.pdf"), bytes);
    const r = spawnSync("pdftotext", ["-q", "-enc", "UTF-8", join(dir, "in.pdf"), join(dir, "out.txt")]);
    return r.status === 0 ? readFileSync(join(dir, "out.txt"), "utf8").replace(/\f/g, "").trim() : null;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// #region exports
import * as pdfEntry from "bm-engine/pdf";

pdfEntry.profile;      // "pdf"
pdfEntry.features.pdf; // true (and every other feature of the full profile)
pdfEntry.backend;      // "native" with the platform package on Node.js, else "wasm"
// #endregion
assert.equal(pdfEntry.profile, "pdf");
assert.equal(pdfEntry.features.pdf, true);
assert.ok(["native", "wasm"].includes(pdfEntry.backend));
assert.deepEqual(Object.keys(pdfEntry).sort(), [
  "PageNumber", "PdfRenderer", "Prepared", "Renderer", "TargetPageNumber", "TotalPages", "backend", "default", "features",
  "init", "initSync", "measure", "prepare", "profile", "render", "setGlyphCacheMaxBytes", "setWoffDecoder", "wasmUrl",
]);
assert.ok(pdfEntry.wasmUrl().href.endsWith("bm_engine.pdf.wasm"));

// #region renderer
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
const families = pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
// [{ name: "Inter", faces: [{ weight: 400, style: "normal", width: 100, index: 0 }], weight: 400, style: "normal" }]
pdf.loadFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") }); // loadFont = registerFont
// #endregion
assert.deepEqual(families, [{ name: "Inter", faces: [{ weight: 400, style: "normal", width: 100, index: 0 }], weight: 400, style: "normal" }]);

// #region render
const html = `<h1 style="font-family: Inter">Invoice 2041</h1><p style="font-family: Inter">Due in 30 days.</p>`;
const bytes = await pdf.render(html);      // Promise<Uint8Array>, paged A4
const same = pdf.renderSync(html);         // Uint8Array
new TextDecoder().decode(bytes.subarray(0, 5)); // "%PDF-"
// #endregion
assert.equal(latin1(bytes.subarray(0, 5)), "%PDF-");
assert.equal(same.length, bytes.length);
assert.deepEqual(mediaBox(bytes).map((v) => Math.round(v * 100) / 100), [595.28, 841.89]);
const t1 = text(bytes);
if (t1 !== null) assert.match(t1, /Invoice 2041/);

// #region sources
const fromTree = await pdf.render({ type: "text", text: "From a node tree", style: { fontFamily: "Inter" } });
const fromJson = await pdf.render({ json: '{"type":"text","text":"From JSON text","style":{"fontFamily":"Inter"}}' });
// #endregion
assert.equal(pageCount(fromTree), 1);
assert.equal(pageCount(fromJson), 1);

// #region measure
const block = `<div style="height: 120px; font-family: Inter">Band</div>`;
await pdf.measure(block, { size: "a4" });                    // { width: 793, height: 120 }: full A4 width in CSS px
await pdf.measure(block, { size: "letter", landscape: true }); // { width: 1056, height: 120 }
await pdf.measure(block, { viewport: { width: 300 } });      // { width: 300, height: 120 }
pdf.measureSync(block);                                      // A4 by default; margins never change the result
// #endregion
assert.deepEqual(await pdf.measure(block, { size: "a4" }), { width: 793, height: 120 });
assert.deepEqual(await pdf.measure(block, { size: "letter", landscape: true }), { width: 1056, height: 120 });
assert.deepEqual(await pdf.measure(block, { viewport: { width: 300 } }), { width: 300, height: 120 });
assert.deepEqual(pdf.measureSync(block), { width: 793, height: 120 });

// #region prepare
const prepared = await pdf.prepare(html, { size: "a5" });
const a5 = await pdf.render(prepared, { margin: 24 }); // options merge over the prepare() options: A5, 24 px margins
// #endregion
assert.deepEqual(mediaBox(a5).map(Math.round), [420, 595]);

// #region module-level
import { render, measure } from "bm-engine/pdf";

const plain = await render(`<div style="width: 200px; height: 100px; background: #0ea5e9"></div>`, {
  viewport: { width: 200 },
});
const withFont = await render(`<p style="font-family: Inter">Hello</p>`, {
  fonts: [{ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") }], // registered before the render
});
await measure(`<div style="width: 200px; height: 100px"></div>`, { viewport: { width: 200 } }); // { width: 200, height: 100 }
// #endregion
assert.deepEqual(mediaBox(plain), [150, 75]);
const t2 = text(withFont);
if (t2 !== null) assert.equal(t2, "Hello");
assert.deepEqual(await measure(`<div style="width: 200px; height: 100px"></div>`, { viewport: { width: 200 } }), { width: 200, height: 100 });
// fonts passed in `fonts` stay registered on the shared renderer
const later = text(await render(`<p style="font-family: Inter">Later</p>`));
if (later !== null) assert.equal(later, "Later");

// #region no-fonts
const empty = new PdfRenderer(); // no font registered at all
let noFont;
try {
  await empty.render(`<p>Hello</p>`);
} catch (e) {
  noFont = e.message;
}
// bm-engine: No font is registered to draw H (U+0048), e (U+0065), l (U+006C), o (U+006F). bm-engine bundles
// no font: register one with registerFont or the fonts option.
// #endregion
assert.equal(noFont, "bm-engine: No font is registered to draw H (U+0048), e (U+0065), l (U+006C), o (U+006F). bm-engine bundles no font: register one with registerFont or the fonts option.");
// uncoveredText "blank" asks for nothing to be drawn: the render goes on without text
const blank = await empty.render(`<p>Hello</p>`, { uncoveredText: "blank" });
assert.equal(pageCount(blank), 1);
const t3 = text(blank);
if (t3 !== null) assert.equal(t3, "");
empty.free();

// #region sync-fonts
const viaSync = new PdfRenderer().renderSync(`<p style="font-family: Inter">Hello</p>`, {
  fonts: [{ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") }],
});
// the sync methods register `fonts` given as bytes as well; a URL or a lazy `data()` loader needs the async render
// #endregion
const t4 = text(viaSync);
if (t4 !== null) assert.equal(t4, "Hello");

// #region renderer-methods
import { Renderer } from "bm-engine/pdf";

const r = new Renderer();
const viaRenderer = await r.renderPdf(`<div style="width: 40px; height: 40px; background: red"></div>`, {
  viewport: { width: 40 },
});
r.measurePdfSync(`<div style="width: 40px; height: 40px"></div>`, { viewport: { width: 40 } }); // { width: 40, height: 40 }
// #endregion
assert.deepEqual(mediaBox(viaRenderer), [30, 30]);
assert.deepEqual(r.measurePdfSync(`<div style="width: 40px; height: 40px"></div>`, { viewport: { width: 40 } }), { width: 40, height: 40 });
r.free();

// #region counters
import { PageNumber, TotalPages, TargetPageNumber } from "bm-engine/pdf";

PageNumber({ format: "upper-roman", style: { color: "#64748b" } });
// { type: "container", tagName: "span", style: { color: "#64748b" }, className: "pageNumber upper-roman" }
TotalPages();
// { type: "container", tagName: "span", className: "totalPages" }
TargetPageNumber({ href: "#totals" });
// { type: "container", tagName: "a", attributes: { href: "#totals" },
//   children: [{ type: "container", tagName: "span", className: "targetPageNumber" }] }
// #endregion
assert.deepEqual(PageNumber({ format: "upper-roman", style: { color: "#64748b" } }),
  { type: "container", tagName: "span", style: { color: "#64748b" }, className: "pageNumber upper-roman" });
assert.deepEqual(TotalPages(), { type: "container", tagName: "span", className: "totalPages" });
assert.deepEqual(TargetPageNumber({ href: "#totals" }),
  { type: "container", tagName: "a", attributes: { href: "#totals" }, children: [{ type: "container", tagName: "span", className: "targetPageNumber" }] });
assert.deepEqual(TargetPageNumber(), { type: "container", tagName: "span", className: "targetPageNumber" });

// #region counters-footer
const report = Array.from({ length: 60 }, (_, k) => `<p>Line ${k + 1}</p>`).join("");
const numbered = await pdf.render(`<div style="font-family: Inter">${report}</div>`, {
  footer: {
    type: "container",
    style: { display: "flex", justifyContent: "center", columnGap: 4, fontFamily: "Inter", fontSize: 10 },
    children: [{ type: "text", text: "Page" }, PageNumber(), { type: "text", text: "of" }, TotalPages()],
  },
}); // "Page 1 of 3", "Page 2 of 3", ... (flex items: the gap makes the spaces)
// #endregion
const t5 = text(numbered);
assert.ok(pageCount(numbered) >= 2);
if (t5 !== null) assert.match(t5, new RegExp(`Page ?1 ?of ?${pageCount(numbered)}`));

// #region fonts-admin
pdf.unregisterFont("Inter");   // true: the family was registered
pdf.unregisterFont("Missing"); // false
pdf.clearFonts();              // removes every registered font
// #endregion
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
assert.equal(pdf.unregisterFont("Inter"), true);
assert.equal(pdf.unregisterFont("Missing"), false);
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });

// #region free
{
  using scoped = new PdfRenderer(); // freed at the end of the block ([Symbol.dispose])
  scoped.renderSync(`<div style="width: 10px; height: 10px"></div>`, { viewport: { width: 10 } });
}
const done = new PdfRenderer();
done.free();
// done.renderSync(...) now throws "bm-engine: renderer has been freed"
// #endregion
assert.throws(() => done.renderSync(`<p>x</p>`), { message: "bm-engine: renderer has been freed" });

// #region abort
const controller = new AbortController();
controller.abort();
try {
  await pdf.render(html, { signal: controller.signal });
} catch (e) {
  e.name; // "AbortError" (a DOMException): the render did not start
}
// #endregion
await assert.rejects(pdf.render(html, { signal: controller.signal }), { name: "AbortError" });

// #region errors
const messageOf = async (options, source = html) => {
  try {
    await pdf.render(source, options);
    return "ok";
  } catch (e) {
    return e.message;
  }
};
await messageOf({ size: "tabloid" });
// bm-engine: unknown page size: tabloid
await messageOf({ margin: "1in" });
// bm-engine: invalid margin: expected a number or "auto"
await messageOf({ viewport: { width: 300 }, size: "a4" });
// bm-engine: viewport is mutually exclusive with the paged options (size, landscape, margin, header, footer, pages, pageRanges)
await messageOf({ pageRanges: [{ from: 5, to: 2 }] });
// bm-engine: Page range is invalid: 5-2. Pages are numbered from 1.
await messageOf({ pdfa: "1b" });
// bm-engine: unknown variant `1b`, expected one of `2a`, `3a`, `2b`, `2u`, `3b`, `3u`, `4`, `4f`
await messageOf({ backgroundColor: "paper" });
// bm-engine: backgroundColor is not a color: paper
await messageOf({ sise: "a4" });
// "ok": an unknown option name is ignored
// #endregion
const ERRORS = [
  [{ size: "tabloid" }, "bm-engine: unknown page size: tabloid"],
  [{ size: { width: 10 } }, "bm-engine: invalid size: expected a preset name or { width, height }"],
  [{ margin: "1in" }, 'bm-engine: invalid margin: expected a number or "auto"'],
  [{ size: { width: 40, height: 40 }, margin: 20 }, "bm-engine: Page size must be finite and larger than zero"],
  [{ landscape: "yes" }, "bm-engine: invalid landscape: expected a boolean"],
  [{ viewport: { width: 300 }, size: "a4" }, "bm-engine: viewport is mutually exclusive with the paged options (size, landscape, margin, header, footer, pages, pageRanges)"],
  [{ viewport: { height: 300 } }, "bm-engine: invalid viewport: width is required"],
  [{ viewport: { width: 0 } }, "bm-engine: Page size must be finite and larger than zero"],
  [{ header: 5 }, "ok"], // (a number band is written as text, as takumi-pdf-js does)
  [{ pages: { middle: {} } }, "bm-engine: unknown page rule: middle"],
  [{ pages: { first: { body: "x" } } }, "bm-engine: unknown field of pages.first: body"],
  [{ pageRanges: 3 }, "bm-engine: invalid pageRanges: expected an array of page numbers or { from, to } spans"],
  [{ pageRanges: [0] }, "bm-engine: Page range is invalid: 0. Pages are numbered from 1."],
  [{ pageRanges: [{ from: 5, to: 2 }] }, "bm-engine: Page range is invalid: 5-2. Pages are numbered from 1."],
  [{ pageRanges: [{ from: 5 }] }, "bm-engine: The page ranges select none of the document's 1 pages"],
  [{ pdfa: "1b" }, "bm-engine: unknown variant `1b`, expected one of `2a`, `3a`, `2b`, `2u`, `3b`, `3u`, `4`, `4f`"],
  [{ tagged: "ua3" }, "bm-engine: data did not match any variant of untagged enum TaggedInput"],
  [{ uncoveredText: "skip" }, "bm-engine: unknown uncoveredText: skip"],
  [{ outline: "yes" }, "bm-engine: invalid outline: expected a boolean"],
  [{ lang: 5 }, "bm-engine: invalid lang: expected a string"],
  [{ backgroundColor: 5 }, "bm-engine: invalid backgroundColor: expected a string"],
  [{ backgroundColor: "paper" }, "bm-engine: backgroundColor is not a color: paper"],
  [{ cssVariables: "x" }, "bm-engine: invalid cssVariables: expected an object of strings"],
  [{ cssVariables: { accent: 1 } }, "bm-engine: invalid cssVariables: expected a string"],
  [{ metadata: "x" }, "bm-engine: invalid metadata: expected an object"],
  [{ metadata: { creationDate: "2026/01/01" } }, "bm-engine: invalid creationDate: expected YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS"],
  [{ attachments: {} }, "bm-engine: attachments takes an array"],
  [{ attachments: [{ data: "x" }] }, "bm-engine: missing field `name`"],
  [{ attachments: [{ name: "a.txt", data: 5 }] }, "bm-engine: attachment data must be bytes or a string: a.txt"],
  [{ attachments: [{ name: "a.txt", data: "x", relationship: "parent" }] }, "bm-engine: unknown variant `parent`, expected one of `source`, `data`, `alternative`, `supplement`, `unspecified`"],
  [{ attachments: [{ name: "a.txt", data: "x", mimeType: "plain" }] }, "bm-engine: Attachment mime type is not a type/subtype pair: plain"],
  [{ sise: "a4" }, "ok"],
];
for (const [options, expected] of ERRORS) assert.equal(await messageOf(options), expected, JSON.stringify(options));
// errors that depend on the document
assert.equal(await messageOf({}, `<p style="font-family: Inter">日</p>`),
  "bm-engine: No font the text can use draws 日 (U+65E5). Check each font's unicodeRange and the font-family stack, or register a font that draws them.");
assert.equal(await messageOf({}, `<p style="font-family: Inter; filter: blur(2px)">x</p>`), "bm-engine: A PDF cannot draw filter: blur(2px)");

// #region viewport-empty
let emptyViewport;
try {
  await pdf.render(`<div></div>`, { viewport: { width: 300 } }); // nothing to give the page a height
} catch (e) {
  emptyViewport = e.message;
}
// bm-engine: Page size must be finite and larger than zero
// #endregion
assert.equal(emptyViewport, "bm-engine: Page size must be finite and larger than zero");

// #region other-builds
import { Renderer as FullRenderer } from "bm-engine/full";

let unsupported;
try {
  new FullRenderer().renderPdfSync(`<p>x</p>`);
} catch (e) {
  unsupported = e.message;
}
// bm-engine: renderPdf is not supported by this build (use the pdf build: import from "bm-engine/pdf")
// #endregion
assert.equal(unsupported, 'bm-engine: renderPdf is not supported by this build (use the pdf build: import from "bm-engine/pdf")');

pdf.free();
console.log(`pdf-api: ok (backend ${pdfEntry.backend}, pdftotext ${t1 === null ? "missing" : "used"})`);
