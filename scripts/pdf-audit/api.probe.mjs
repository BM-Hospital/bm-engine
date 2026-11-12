// JS API surface probes: every option of takumi-pdf's `render` / `measure`, its default, its validation and the error
// message, compared with the published takumi-pdf package (dts-header.d.ts / export.ts / options.rs / metadata.rs).
import { bmMod, refMod, probe, sameError, squash, font, INTER, pngRgba, noProducer } from "./lib.mjs";

const P = (n) => Array.from({ length: n }, (_, i) => `<p>Line ${String(i + 1).padStart(3, "0")}</p>`).join("");
const DOC = `<div>${P(120)}</div>`;

/** One case per option value: both engines must agree on success (pages, boxes, text) or on the error message. */
function matrix(id, feature, source, cases, extra) {
  probe(id, feature, async (t) => {
    for (const [label, options] of cases) {
      const r = await t.both(source, options, extra);
      if (!r.ref) { t.ok(true, label); t.same(label, 0, 0); continue; }
      if (sameError(t, label, r.bm, r.ref)) continue;
      t.same(`${label}: pages`, r.bm.pages.length, r.ref.pages.length);
      t.same(`${label}: boxes`, r.bm.pages.map((p) => p.media), r.ref.pages.map((p) => p.media));
      t.same(`${label}: text`, r.bm.textPages.map(squash), r.ref.textPages.map(squash));
    }
  });
}

// ---- exports ---------------------------------------------------------------------------------------------------

probe("api.exports", "module exports (render, measure, prepare, PdfRenderer, Prepared, primitives)", async (t) => {
  for (const name of ["render", "measure", "prepare", "PdfRenderer", "Prepared", "PageNumber", "TotalPages", "TargetPageNumber"]) {
    t.ok(typeof bmMod[name] === "function", `bm exports ${name}`);
    if (refMod) t.ok(typeof refMod[name] === "function" || name.endsWith("Pages") || name.endsWith("Number"), `takumi exports ${name}`);
  }
  if (refMod) t.note("takumi-pdf exports: " + Object.keys(refMod).sort().join(", "));
  t.note("bm-engine/pdf exports: " + Object.keys(bmMod).sort().join(", "));
  const r = new bmMod.PdfRenderer();
  for (const m of ["render", "measure", "prepare", "registerFont", "unregisterFont", "clearFonts", "free"]) t.ok(typeof r[m] === "function", `PdfRenderer#${m}`);
  t.ok(typeof r[Symbol.dispose] === "function", "PdfRenderer[Symbol.dispose]");
  r.free();
});

// ---- page geometry ------------------------------------------------------------------------------------------------

matrix("api.size.presets", "size: preset names (case-insensitive) and explicit dimensions", DOC, [
  ...["a3", "a4", "a5", "b4", "b5", "jis-b4", "jis-b5", "ledger", "legal", "letter"].map((s) => [`size ${s}`, { size: s }]),
  ["size A4 upper", { size: "A4" }],
  ["size Letter mixed", { size: "Letter" }],
  ["size dims", { size: { width: 400, height: 300 } }],
  ["default", {}],
]);

matrix("api.size.invalid", "size: validation errors", "<p>x</p>", [
  ["unknown name", { size: "tabloid" }],
  ["empty name", { size: "" }],
  ["zero", { size: { width: 0, height: 100 } }],
  ["negative", { size: { width: -10, height: 100 } }],
  ["missing height", { size: { width: 100 } }],
  ["number", { size: 5 }],
  ["null", { size: null }],
  ["string dims", { size: { width: "100", height: "100" } }],
  ["huge", { size: { width: 1e9, height: 1e9 } }],
  ["extra key", { size: { width: 200, height: 200, depth: 3 } }],
]);

matrix("api.landscape", "landscape", DOC, [
  ["landscape a4", { landscape: true }],
  ["landscape false", { landscape: false }],
  ["landscape dims", { size: { width: 300, height: 500 }, landscape: true }],
  ["landscape letter", { size: "letter", landscape: true }],
  ["landscape string", { landscape: "yes" }],
  ["landscape 1", { landscape: 1 }],
  ["landscape null", { landscape: null }],
]);

matrix("api.margin", "margin: number, auto, per side, validation", DOC, [
  ["0", { margin: 0 }],
  ["24", { margin: 24 }],
  ["auto", { margin: "auto" }],
  ["sides", { margin: { top: 100, right: 10, bottom: 50, left: 10 } }],
  ["partial sides", { margin: { top: 200 } }],
  ["side auto", { margin: { top: "auto", bottom: 10 } }],
  ["empty object", { margin: {} }],
  ["negative", { margin: -20 }],
  ["too large", { margin: 600 }],
  ["string", { margin: "10px" }],
  ["AUTO upper", { margin: "AUTO" }],
  ["null", { margin: null }],
  ["array", { margin: [1, 2, 3, 4] }],
  ["unknown side", { margin: { top: 10, inner: 3 } }],
  ["tiny page auto", { size: { width: 90, height: 90 } }],
  ["one inch page", { size: { width: 96, height: 96 } }],
]);

matrix("api.viewport", "viewport: fixed, content height, exclusivity with paged options", `<div style="width:100%"><p>One</p><p>Two</p></div>`, [
  ["fixed", { viewport: { width: 400, height: 300 } }],
  ["auto height", { viewport: { width: 302 } }],
  ["fractional", { viewport: { width: 300.7, height: 200.4 } }],
  ["zero width", { viewport: { width: 0, height: 100 } }],
  ["zero height", { viewport: { width: 100, height: 0 } }],
  ["negative", { viewport: { width: -5, height: 100 } }],
  ["missing width", { viewport: { height: 100 } }],
  ["null height", { viewport: { width: 200, height: null } }],
  ["with size", { viewport: { width: 200, height: 100 }, size: "a4" }],
  ["with landscape false", { viewport: { width: 200, height: 100 }, landscape: false }],
  ["with margin", { viewport: { width: 200, height: 100 }, margin: 0 }],
  ["with header", { viewport: { width: 200, height: 100 }, header: "<p>h</p>" }],
  ["with footer false", { viewport: { width: 200, height: 100 }, footer: false }],
  ["with pages", { viewport: { width: 200, height: 100 }, pages: {} }],
  ["with pageRanges", { viewport: { width: 200, height: 100 }, pageRanges: [1] }],
  ["with backgroundColor", { viewport: { width: 200, height: 100 }, backgroundColor: "red" }],
  ["string", { viewport: "200x100" }],
  ["huge", { viewport: { width: 100000, height: 100000 } }],
]);

matrix("api.viewport.empty", "viewport: empty documents", "", [
  ["empty html fixed", { viewport: { width: 200, height: 100 } }],
  ["empty html auto height", { viewport: { width: 200 } }],
  ["empty html paged", {}],
]);

matrix("api.pageRanges", "pageRanges: forms and validation", DOC, [
  ["single", { pageRanges: [2] }],
  ["span", { pageRanges: [{ from: 2, to: 3 }] }],
  ["open from", { pageRanges: [{ to: 2 }] }],
  ["open to", { pageRanges: [{ from: 3 }] }],
  ["mixed", { pageRanges: [1, { from: 3 }] }],
  ["overlap", { pageRanges: [1, 1, { from: 1, to: 2 }] }],
  ["empty object", { pageRanges: [{}] }],
  ["empty list", { pageRanges: [] }],
  ["zero", { pageRanges: [0] }],
  ["backwards", { pageRanges: [{ from: 3, to: 1 }] }],
  ["beyond", { pageRanges: [99] }],
  ["zero to", { pageRanges: [{ from: 1, to: 0 }] }],
  ["negative", { pageRanges: [-1] }],
  ["fraction", { pageRanges: [1.5] }],
  ["string", { pageRanges: ["1-2"] }],
  ["not array", { pageRanges: 2 }],
  ["null", { pageRanges: null }],
]);

matrix("api.backgroundColor", "backgroundColor: CSS colours and validation", "<p>x</p>", [
  ["named", { backgroundColor: "red" }],
  ["hex", { backgroundColor: "#0a0b0c" }],
  ["rgba", { backgroundColor: "rgba(10, 20, 30, 0.5)" }],
  ["transparent", { backgroundColor: "transparent" }],
  ["currentColor", { backgroundColor: "currentColor" }],
  ["oklch", { backgroundColor: "oklch(60% 0.2 30)" }],
  ["invalid", { backgroundColor: "notacolor" }],
  ["empty", { backgroundColor: "" }],
  ["number", { backgroundColor: 5 }],
  ["null", { backgroundColor: null }],
  ["var", { backgroundColor: "var(--x)" }],
]);

probe("api.backgroundColor.paint", "backgroundColor: one page-sized fill under everything", async (t) => {
  const r = await t.both("<p>x</p>", { backgroundColor: "#102030", size: { width: 200, height: 200 } });
  if (r.ref && !r.bm.error && !r.ref.error) {
    const fill = (s) => (s.match(/[\d. ]+ rg\s+[\d. -]+ re\s+f/g) || []).map((x) => x.replace(/\s+/g, " ").trim());
    t.same("fill ops", fill(r.bm.content(0)), fill(r.ref.content(0)));
  } else t.same("renders", r.bm.error, r.ref && r.ref.error);
});

// ---- bands and page rules -----------------------------------------------------------------------------------------

const BAND = `<div style="display:flex;width:100%;justify-content:center;font-size:10px">Band <span class="pageNumber"></span>/<span class="totalPages"></span></div>`;
matrix("api.bands", "header / footer / pages: inputs and validation", DOC, [
  ["footer html", { footer: BAND }],
  ["header html", { header: BAND }],
  ["both", { header: `<p>Head</p>`, footer: BAND }],
  ["footer node", { footer: { type: "container", children: [{ type: "text", text: "Foot" }] } }],
  ["footer false", { footer: false }],
  ["footer true", { footer: true }],
  ["footer number", { footer: 5 }],
  ["footer null", { footer: null }],
  ["footer empty string", { footer: "" }],
  ["pages first off", { header: `<p>Head</p>`, pages: { first: { header: false } } }],
  ["pages last", { footer: BAND, pages: { last: { footer: `<p>Last</p>` } } }],
  ["pages odd even", { pages: { odd: { header: `<p>Odd</p>` }, even: { header: `<p>Even</p>` } } }],
  ["pages first beats odd", { pages: { first: { header: `<p>First</p>` }, odd: { header: `<p>Odd</p>` }, last: { header: `<p>Last</p>` } } }],
  ["pages without default", { pages: { last: { footer: `<p>Only last</p>` } } }],
  ["pages unknown rule", { pages: { middle: { header: `<p>x</p>` } } }],
  ["pages unknown field", { pages: { first: { body: `<p>x</p>` } } }],
  ["pages array", { pages: [] }],
  ["pages string", { pages: "first" }],
  ["pages rule string", { pages: { first: "x" } }],
  ["pages rule null", { pages: { first: null } }],
  ["pages band true", { pages: { first: { header: true } } }],
  ["tall band auto margin", { footer: `<div style="height:120px;width:100%">Tall</div>` }],
  ["band taller than page", { size: { width: 300, height: 300 }, footer: `<div style="height:400px">Too tall</div>` }],
  ["band with numeric margin", { margin: 10, footer: BAND }],
]);

// ---- metadata ---------------------------------------------------------------------------------------------------

probe("api.metadata", "metadata: Info dictionary + XMP, validation of dates and schemas", async (t) => {
  const cases = [
    ["none", {}],
    ["title", { metadata: { title: "Tïtle ✓" } }],
    ["all", { lang: "en-GB", metadata: { title: "T", description: "D", authors: ["A One", "B Two"], keywords: ["k1", "k2"], creator: "C", creationDate: "2026-08-06T01:02:03" } }],
    ["date only", { metadata: { creationDate: "2026-08-06" } }],
    ["date Z", { metadata: { creationDate: "2026-08-06T01:02:03Z" } }],
    ["bad date", { metadata: { creationDate: "2026-02-30" } }],
    ["bad date format", { metadata: { creationDate: "06/08/2026" } }],
    ["date number", { metadata: { creationDate: 20260806 } }],
    ["empty authors", { metadata: { authors: [], keywords: [] } }],
    ["authors string", { metadata: { authors: "A" } }],
    ["unknown key", { metadata: { subject: "S" } }],
    ["metadata string", { metadata: "x" }],
    ["metadata null", { metadata: null }],
    ["xmp", { metadata: { creationDate: "2026-01-01", xmp: [{ name: "Factur-X PDF/A Extension", prefix: "fx", namespace: "urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#", properties: [{ name: "DocumentFileName", value: "factur-x.xml", description: "The name of the embedded XML document" }] }] } }],
    ["xmp bad prefix", { metadata: { xmp: [{ name: "n", prefix: "1x", namespace: "urn:x", properties: [] }] } }],
    ["xmp bad namespace", { metadata: { xmp: [{ name: "n", prefix: "x", namespace: "has space", properties: [] }] } }],
    ["xmp empty namespace", { metadata: { xmp: [{ name: "n", prefix: "x", namespace: "", properties: [] }] } }],
    ["xmp bad property", { metadata: { xmp: [{ name: "n", prefix: "x", namespace: "urn:x", properties: [{ name: "a b", value: "v", description: "d" }] }] } }],
    ["xmp missing field", { metadata: { xmp: [{ prefix: "x", namespace: "urn:x", properties: [] }] } }],
    ["xmp property missing description", { metadata: { xmp: [{ name: "n", prefix: "x", namespace: "urn:x", properties: [{ name: "a", value: "v" }] }] } }],
    ["lang only", { lang: "ja" }],
    ["lang invalid", { lang: "not a lang!!" }],
    ["lang empty", { lang: "" }],
    ["lang number", { lang: 5 }],
  ];
  for (const [label, options] of cases) {
    const r = await t.both("<h1>Doc</h1><p>x</p>", options);
    if (!r.ref) { t.same(label, 0, 0); continue; }
    if (sameError(t, label, r.bm, r.ref)) continue;
    const strip = (o) => Object.fromEntries(Object.entries(o).filter(([k]) => !/Date$/.test(k) || options.metadata?.creationDate).map(([k, v]) => [k, noProducer(v)]));
    t.same(`${label}: Info`, strip(r.bm.info), strip(r.ref.info));
    const xmp = (d) => { const o = d.typed("Metadata")[0]; return o ? noProducer(o.data.toString("utf8")).replace(/\d{4}-\d\d-\d\dT[\d:]+Z?/g, options.metadata?.creationDate ? "$&" : "DATE").replace(/uuid:[0-9a-f-]+|xmp\.(d|i)id:[\w-]+/g, "ID") : null; };
    t.same(`${label}: XMP`, xmp(r.bm), xmp(r.ref));
    t.same(`${label}: catalog /Lang`, r.bm.catalog.Lang, r.ref.catalog.Lang);
  }
});

matrix("api.outline", "outline option", `<h1>One</h1><p>a</p><h2>Two</h2><h3>Three</h3><h1>Four</h1>`, [
  ["on", { outline: true }],
  ["off", { outline: false }],
  ["string", { outline: "yes" }],
  ["null", { outline: null }],
]);

probe("api.outline.tree", "outline: /Outlines entries equal", async (t) => {
  const r = await t.both(`<h1>One</h1><p>a</p><h2>Two</h2><h3>Three</h3><h1>Four</h1><h4>Skip</h4>`, { outline: true });
  if (r.ref && !r.bm.error && !r.ref.error) t.same("outline", r.bm.interchange.outline, r.ref.interchange.outline);
  else t.same("renders", r.bm.error, r.ref && r.ref.error);
});

// ---- conformance option matrix ---------------------------------------------------------------------------------------

probe("api.pdfa.tagged.matrix", "pdfa x tagged: every combination succeeds or fails with the same message", async (t) => {
  const meta = { lang: "en", metadata: { title: "T", creationDate: "2026-01-01" } };
  for (const pdfa of [undefined, "2a", "2b", "2u", "3a", "3b", "3u", "4", "4f", "1b", "4e", "A2B", 2, true]) {
    for (const tagged of [undefined, false, true, "ua1", "ua2", "UA1", "ua3", 1, null]) {
      const options = { ...meta, outline: true };
      if (pdfa !== undefined) options.pdfa = pdfa;
      if (tagged !== undefined) options.tagged = tagged;
      const r = await t.both(`<h1>Doc</h1><p>Body</p>`, options);
      const label = `pdfa=${JSON.stringify(pdfa)} tagged=${JSON.stringify(tagged)}`;
      if (!r.ref) { t.same(label, 0, 0); continue; }
      if (sameError(t, label, r.bm, r.ref)) continue;
      t.same(`${label}: version`, r.bm.version, r.ref.version);
      t.same(`${label}: struct tree`, !!r.bm.catalog.StructTreeRoot, !!r.ref.catalog.StructTreeRoot);
      t.same(`${label}: output intent`, !!r.bm.catalog.OutputIntents, !!r.ref.catalog.OutputIntents);
    }
  }
});

probe("api.attachments", "attachments: fields, validation, conformance gating", async (t) => {
  const meta = { lang: "en", metadata: { title: "T", creationDate: "2026-01-01" } };
  const file = { name: "a.xml", data: "<a/>", mimeType: "application/xml", description: "An XML file", relationship: "alternative", modificationDate: "2026-02-03T04:05:06" };
  const cases = [
    ["text data", { attachments: [{ name: "a.txt", data: "hello" }] }],
    ["bytes", { attachments: [{ name: "a.bin", data: new Uint8Array([1, 2, 3, 4]) }] }],
    ["full", { attachments: [file] }],
    ["two", { attachments: [file, { ...file, name: "b.xml" }] }],
    ["duplicate", { attachments: [file, file] }],
    ["bad mime", { attachments: [{ ...file, mimeType: "xml" }] }],
    ["bad mime chars", { attachments: [{ ...file, mimeType: "a/b c" }] }],
    ["bad relationship", { attachments: [{ ...file, relationship: "other" }] }],
    ["bad date", { attachments: [{ ...file, modificationDate: "yesterday" }] }],
    ["no name", { attachments: [{ data: "x" }] }],
    ["no data", { attachments: [{ name: "x" }] }],
    ["data number", { attachments: [{ name: "x", data: 5 }] }],
    ["empty name", { attachments: [{ name: "", data: "x" }] }],
    ["empty data", { attachments: [{ name: "e.txt", data: "" }] }],
    ["not array", { attachments: file }],
    ["null", { attachments: null }],
    ["empty list", { attachments: [] }],
    ["unicode name", { attachments: [{ name: "résumé ✓.txt", data: "x", description: "Dëscription" }] }],
    ...["2b", "2a", "2u", "3b", "3a", "3u", "4", "4f"].map((p) => [`pdfa ${p} full`, { ...meta, pdfa: p, attachments: [file] }]),
    ...["3b", "4f"].map((p) => [`pdfa ${p} bare`, { ...meta, pdfa: p, attachments: [{ name: "a.txt", data: "x" }] }]),
    ["pdfa 3b no date, metadata date", { ...meta, pdfa: "3b", attachments: [{ name: "a.txt", data: "x", mimeType: "text/plain", description: "d" }] }],
    ["pdfa 3b no dates at all", { lang: "en", metadata: { title: "T" }, pdfa: "3b", attachments: [{ name: "a.txt", data: "x", mimeType: "text/plain", description: "d" }] }],
    ["pdfa 2b empty list", { ...meta, pdfa: "2b", attachments: [] }],
    ["ua1 attachment", { ...meta, tagged: "ua1", attachments: [{ name: "a.txt", data: "x" }] }],
  ];
  for (const [label, options] of cases) {
    const r = await t.both("<h1>Doc</h1><p>x</p>", options);
    if (!r.ref) { t.same(label, 0, 0); continue; }
    if (sameError(t, label, r.bm, r.ref)) continue;
    t.same(`${label}: files`, r.bm.interchange.files, r.ref.interchange.files);
  }
});

matrix("api.uncoveredText", "uncoveredText: error / placeholder / blank and the standards that forbid the placeholder", `<p>Latin 漢字 text ✓</p>`, [
  ["default", {}],
  ["error", { uncoveredText: "error" }],
  ["placeholder", { uncoveredText: "placeholder" }],
  ["blank", { uncoveredText: "blank" }],
  ["invalid", { uncoveredText: "skip" }],
  ["upper", { uncoveredText: "Blank" }],
  ["null", { uncoveredText: null }],
  ["placeholder + 2b", { uncoveredText: "placeholder", pdfa: "2b", lang: "en", metadata: { title: "T", creationDate: "2026-01-01" } }],
  ["placeholder + 4", { uncoveredText: "placeholder", pdfa: "4", lang: "en", metadata: { title: "T", creationDate: "2026-01-01" } }],
  ["placeholder + ua1", { uncoveredText: "placeholder", tagged: "ua1", outline: true, lang: "en", metadata: { title: "T", creationDate: "2026-01-01" } }],
  ["placeholder + ua2", { uncoveredText: "placeholder", tagged: "ua2", outline: true, lang: "en", metadata: { title: "T", creationDate: "2026-01-01" } }],
  ["blank + 2b", { uncoveredText: "blank", pdfa: "2b", lang: "en", metadata: { title: "T", creationDate: "2026-01-01" } }],
  ["viewport default", { viewport: { width: 300, height: 100 } }],
]);

// ---- layout resources ----------------------------------------------------------------------------------------------

matrix("api.css", "css: string, list, object rules, cssVariables", `<p class="a">Styled</p>${P(60)}`, [
  ["string", { css: "p { font-size: 40px }" }],
  ["list", { css: ["p { font-size: 40px }", ".a { font-size: 80px }"] }],
  ["empty list", { css: [] }],
  ["object rule", { css: [{ selector: "p", style: { fontSize: 40 } }] }],
  ["number", { css: 5 }],
  ["null", { css: null }],
  ["invalid css text", { css: "p { font-size: }}}} @@@" }],
  ["cssVariables", { css: "p { font-size: var(--size) }", cssVariables: { "--size": "40px" } }],
  ["cssVariables no prefix", { css: "p { font-size: var(--size) }", cssVariables: { size: "40px" } }],
  ["cssVariables number", { css: "p { font-size: var(--size) }", cssVariables: { size: 40 } }],
  ["cssVariables array", { cssVariables: [] }],
  ["stylesheets alias", { stylesheets: ["p { font-size: 40px }"] }],
  ["@page in css", { css: "@page { size: 300px 300px; margin: 10px }" }],
  ["media print", { css: "@media print { p { font-size: 40px } } @media screen { p { font-size: 80px } }" }],
]);

matrix("api.fontFamilies", "fontFamilies: per-render fallback chain", `<p>Fallback text</p><p style="font-family: Nope">Other</p>`, [
  ["names", { fontFamilies: ["Inter"] }],
  ["unknown", { fontFamilies: ["Nope"] }],
  ["empty", { fontFamilies: [] }],
  ["string", { fontFamilies: "Inter" }],
  ["numbers", { fontFamilies: [1, 2] }],
  ["generic", { fontFamilies: ["sans-serif"] }],
]);

probe("api.fonts.option", "fonts option: bytes, descriptors, and no registered font", async (t) => {
  const html = `<p style="font-family: Custom">Custom family</p><p>Default family</p>`;
  for (const [label, fonts, extra] of [
    ["bytes", [font(INTER)], {}],
    ["descriptor", [{ name: "Custom", data: font(INTER) }], {}],
    ["descriptor weight/style", [{ name: "Custom", data: font(INTER), weight: 700, style: "italic" }], {}],
    ["unicodeRange", [{ name: "Custom", data: font(INTER), unicodeRange: [[0x41, 0x5a]] }], {}],
    ["empty list", [], {}],
    ["bad bytes", [new Uint8Array([1, 2, 3, 4])], {}],
    ["bad entry", [5], {}],
    ["not array", "Inter", {}],
  ]) {
    const r = await t.both(html, { fonts, ...extra }, { fonts: [] });
    if (!r.ref) { t.same(label, 0, 0); continue; }
    if (sameError(t, label, r.bm, r.ref)) continue;
    t.same(`${label}: text`, r.bm.textPages.map(squash), r.ref.textPages.map(squash));
    const names = (d) => d.typed("Font").map((o) => String(o.dict.BaseFont).replace(/^\/[A-Z]{6}\+/, "")).sort();
    t.same(`${label}: fonts`, names(r.bm), names(r.ref));
  }
});

probe("api.images.option", "images option: sources by URL, data URIs, missing images", async (t) => {
  const png = Buffer.from(pngRgba(2, 2));
  const html = `<img src="https://example.test/a.png" width="40" height="40"><p>after</p>`;
  for (const [label, src, options] of [
    ["provided", html, { images: [{ src: "https://example.test/a.png", data: new Uint8Array(png) }] }],
    ["missing", html, {}],
    ["wrong key", html, { images: [{ src: "https://example.test/b.png", data: new Uint8Array(png) }] }],
    ["data uri", `<img src="data:image/png;base64,${png.toString("base64")}" width="40" height="40">`, {}],
    ["garbage bytes", html, { images: [{ src: "https://example.test/a.png", data: new Uint8Array([1, 2, 3]) }] }],
    ["not array", html, { images: 5 }],
    ["entry without data", html, { images: [{ src: "https://example.test/a.png" }] }],
    ["background url missing", `<div style="width:50px;height:50px;background-image:url(https://example.test/bg.png)"></div>`, {}],
  ]) {
    const r = await t.both(src, { viewport: { width: 200, height: 100 }, ...options });
    if (!r.ref) { t.same(label, 0, 0); continue; }
    if (sameError(t, label, r.bm, r.ref)) continue;
    const imgs = (d) => d.subtyped("Image").map((o) => `${o.dict.Width}x${o.dict.Height}`).sort();
    t.same(`${label}: image XObjects`, imgs(r.bm), imgs(r.ref));
  }
});

probe("api.signal", "signal: an aborted signal rejects render / measure / prepare", async (t) => {
  for (const method of ["render", "measure", "prepare"]) {
    const run = async (mod) => {
      const c = new AbortController(); c.abort();
      const r = new mod.PdfRenderer();
      try { await r[method]("<p>x</p>", { signal: c.signal }); return "(no error)"; } catch (e) { return `${e.name}`; } finally { r.free(); }
    };
    const a = await run(bmMod);
    t.ok(a !== "(no error)", `bm ${method} rejects on an aborted signal (${a})`);
    if (refMod) t.same(`${method}: error name`, a, await run(refMod)); else t.same(method, 0, 0);
  }
});

probe("api.unknown.options", "unknown / misspelled top-level options", async (t) => {
  for (const options of [{ sizee: "a4" }, { pageSize: "a5" }, { format: "a5" }, { printBackground: true }, { scale: 2 }, { devicePixelRatio: 2 }, { width: 100, height: 100 }, { producer: "X" }]) {
    const r = await t.both("<p>x</p>", options);
    const label = JSON.stringify(options);
    if (!r.ref) { t.same(label, 0, 0); continue; }
    if (sameError(t, label, r.bm, r.ref)) continue;
    t.same(`${label}: boxes`, r.bm.pages.map((p) => p.media), r.ref.pages.map((p) => p.media));
    t.same(`${label}: producer`, r.bm.info.Producer === "X", r.ref.info.Producer === "X");
  }
});

probe("api.options.nonobject", "options that are not objects", async (t) => {
  for (const options of [null, 5, "a4", [], true]) {
    const r = await t.both("<p>x</p>", options);
    const label = JSON.stringify(options);
    if (!r.ref) { t.same(label, 0, 0); continue; }
    t.same(`${label}: outcome`, r.bm.error ? "error" : "renders", r.ref.error ? "error" : "renders");
  }
});

// ---- input kinds -------------------------------------------------------------------------------------------------

probe("api.input.kinds", "input kinds: HTML, node tree, { json }, Tailwind `tw`, <style>, invalid inputs", async (t) => {
  const tree = { type: "container", style: { display: "flex", flexDirection: "column" }, children: [{ type: "text", text: "Node text" }, { type: "container", tw: "flex text-[30px] font-bold", children: [{ type: "text", text: "Tailwind" }] }] };
  const cases = [
    ["html", "<h1>Title</h1><p>Para</p>"],
    ["html with style element", "<style>.x{font-size:50px}</style><p class=x>Styled</p>"],
    ["html tw attribute", `<div tw="flex text-[30px]">TW</div>`],
    ["html class utilities", `<div class="text-[30px] font-bold">TW</div>`],
    ["node tree", tree],
    ["json source", { json: JSON.stringify(tree) }],
    ["text node root", { type: "text", text: "Just text" }],
    ["image node no src", { type: "image", src: "" }],
    ["empty string", ""],
    ["whitespace", "   "],
    ["null", null],
    ["undefined", undefined],
    ["number", 5],
    ["array", [tree]],
    ["unknown node type", { type: "widget" }],
    ["bad json", { json: "{" }],
    ["plain text", "just words, no tags"],
    ["full document", "<!doctype html><html lang=fr><head><title>Doc title</title><style>p{font-size:30px}</style></head><body><p>Body</p></body></html>"],
  ];
  for (const [label, source] of cases) {
    const r = await t.both(source, { size: { width: 400, height: 300 } });
    if (!r.ref) { t.same(label, 0, 0); continue; }
    if (sameError(t, label, r.bm, r.ref)) continue;
    t.same(`${label}: pages`, r.bm.pages.length, r.ref.pages.length);
    t.same(`${label}: text`, r.bm.textPages.map(squash), r.ref.textPages.map(squash));
    t.same(`${label}: Info`, { ...r.bm.info, Producer: 0, CreationDate: 0, ModDate: 0 }, { ...r.ref.info, Producer: 0, CreationDate: 0, ModDate: 0 });
    t.same(`${label}: /Lang`, r.bm.catalog.Lang, r.ref.catalog.Lang);
  }
});

// ---- measure --------------------------------------------------------------------------------------------------------

probe("api.measure", "measure(): page options (band layout, three-digit counters) vs viewport", async (t) => {
  const band = `<div style="display:flex;font-size:10px">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>`;
  const cases = [
    ["band a4", band, { size: "a4" }],
    ["band default", band, {}],
    ["band landscape", band, { size: "a4", landscape: true }],
    ["band viewport", band, { viewport: { width: 300, height: 200 } }],
    ["band viewport auto", band, { viewport: { width: 300 } }],
    ["fixed box", `<div style="width:100px;height:40px"></div>`, { size: "a4" }],
    ["paragraph", `<p>${"word ".repeat(200)}</p>`, { size: "a5" }],
    ["with margin (ignored)", band, { size: "a4", margin: 100 }],
    ["with header (rejected?)", band, { size: "a4", header: "<p>x</p>" }],
    ["viewport + size", band, { viewport: { width: 300 }, size: "a4" }],
    ["unknown size", band, { size: "nope" }],
    ["empty", "", { size: "a4" }],
  ];
  for (const [label, source, options] of cases) {
    const a = await t.bm(source, options, { method: "measure" });
    const b = await t.ref(source, options, { method: "measure" });
    if (!b) { t.ok(!a.error || true, label); t.same(label, 0, 0); continue; }
    if (sameError(t, label, a, b)) continue;
    const round = (v) => ({ width: Math.round(v.width * 100) / 100, height: Math.round(v.height * 100) / 100 });
    t.same(`${label}: size`, round(a.value), round(b.value));
  }
});

// ---- prepare ---------------------------------------------------------------------------------------------------------

probe("api.prepare", "prepare(): handle accepted by render / measure; output-only options at render time", async (t) => {
  const run = async (mod) => {
    const r = new mod.PdfRenderer();
    const out = {};
    try {
      await (r.registerFont(font(INTER)));
      const p = await r.prepare("<h1>Doc</h1><p>Prepared body</p>", { size: "a5", footer: `<p>Foot <span class="pageNumber"></span></p>` });
      out.isPrepared = p instanceof mod.Prepared;
      const bytes = await r.render(p, { metadata: { title: "Prepared title" }, outline: true });
      const s = Buffer.from(bytes).toString("latin1");
      out.box = /\/MediaBox\s*\[([^\]]+)\]/.exec(s)?.[1];
      out.hasOutline = /\/Outlines/.test(s);
      try { const m = await r.measure(p); out.measure = { w: Math.round(m.width), h: Math.round(m.height) }; } catch (e) { out.measure = "error: " + e.message; }
    } catch (e) { out.error = e.message; } finally { r.free(); }
    return out;
  };
  const a = await run(bmMod);
  t.ok(!a.error, "bm prepare + render" + (a.error ? ": " + a.error : ""));
  if (refMod) t.same("prepared render", a, await run(refMod)); else t.same("prepare", 0, 0);
});

probe("api.prepare.fetch", "prepare(): fetches the remote images the document draws (images.fetch)", async (t) => {
  const png = Buffer.from(pngRgba(2, 2));
  const run = async (mod) => {
    const r = new mod.PdfRenderer();
    const asked = [];
    const fetchFn = async (url) => { asked.push(String(url && url.url ? url.url : url)); return new Response(png, { status: 200, headers: { "content-type": "image/png" } }); };
    try {
      await r.registerFont(font(INTER));
      const p = await r.prepare(`<img src="https://example.test/logo.png" width="20" height="20"><div style="width:30px;height:30px;background-image:url(https://example.test/bg.png)"></div><p>x</p>`, { viewport: { width: 200, height: 100 }, images: { fetch: fetchFn } });
      const bytes = await r.render(p);
      return { asked: asked.sort(), images: (Buffer.from(bytes).toString("latin1").match(/\/Subtype\s*\/Image/g) || []).length > 0 };
    } catch (e) { return { asked: asked.sort(), error: e.message }; } finally { r.free(); }
  };
  const a = await run(bmMod);
  if (refMod) t.same("fetched urls and embedded images", a, await run(refMod)); else t.same("prepare fetch", 0, 0);
});

// ---- renderer lifecycle ------------------------------------------------------------------------------------------------

probe("api.renderer.fonts", "PdfRenderer: registerFont result, unregisterFont, clearFonts, fontCacheMaxBytes", async (t) => {
  const run = async (mod) => {
    const out = {};
    const r = new mod.PdfRenderer({ fontCacheMaxBytes: 1 << 20 });
    try {
      const reg = await r.registerFont(font(INTER));
      out.registered = reg.map((f) => ({ name: f.name, faces: f.faces.map((x) => ({ weight: x.weight, style: x.style, width: x.width, index: x.index })) }));
      const named = await r.registerFont({ name: "Alias", data: font(INTER), weight: 300 });
      out.named = named.map((f) => ({ name: f.name, faces: f.faces.length }));
      out.unregisterKnown = r.unregisterFont("Alias");
      out.unregisterUnknown = r.unregisterFont("Nope");
      r.clearFonts();
      try { await r.render(`<p style="font-family: Inter">Zażółć</p>`, { viewport: { width: 200, height: 50 } }); out.afterClear = "renders"; } catch (e) { out.afterClear = e.message; }
    } catch (e) { out.error = e.message; } finally { r.free(); }
    return out;
  };
  const a = await run(bmMod);
  t.ok(!a.error, "bm renderer font methods" + (a.error ? ": " + a.error : ""));
  if (refMod) t.same("font registry behaviour", a, await run(refMod)); else t.same("fonts", 0, 0);
});

probe("api.determinism", "the same input twice gives the same bytes (with and without creationDate)", async (t) => {
  for (const options of [{}, { metadata: { title: "T", creationDate: "2026-01-01" } }, { pdfa: "2b", lang: "en", metadata: { title: "T", creationDate: "2026-01-01" } }]) {
    const a = await t.bm("<h1>Doc</h1><p>Body</p>", options); const b = await t.bm("<h1>Doc</h1><p>Body</p>", options);
    t.ok(!a.error && !b.error && Buffer.compare(Buffer.from(a.bytes), Buffer.from(b.bytes)) === 0, `bm deterministic for ${JSON.stringify(options)}`);
    const c = await t.ref("<h1>Doc</h1><p>Body</p>", options); const d = await t.ref("<h1>Doc</h1><p>Body</p>", options);
    if (c && !c.error) t.note(`takumi deterministic for ${JSON.stringify(options)}: ${Buffer.compare(Buffer.from(c.bytes), Buffer.from(d.bytes)) === 0}`);
    if (c && !c.error && !a.error) t.same(`/ID for ${JSON.stringify(options)}`, a.interchange.ids, c.interchange.ids);
  }
});

probe("api.primitives", "PageNumber / TotalPages / TargetPageNumber: class hooks and format", async (t) => {
  const { PageNumber, TotalPages, TargetPageNumber } = bmMod;
  const a = PageNumber({ format: "lower-roman", className: "x" });
  t.ok(a.className === "pageNumber lower-roman x", "PageNumber className joins hook, format and className");
  t.ok(TotalPages().className === "totalPages", "TotalPages class hook");
  const tp = TargetPageNumber({ href: "#a" });
  t.ok(tp.tagName === "a" && tp.children[0].className === "targetPageNumber", "TargetPageNumber with href wraps a link");
  if (refMod) {
    const b = refMod.PageNumber({ format: "lower-roman", className: "x" });
    t.same("PageNumber className", a.className, b.props.className);
    t.same("TargetPageNumber element", { tag: tp.tagName, child: tp.children[0].className }, (() => { const e = refMod.TargetPageNumber({ href: "#a" }); return { tag: e.type, child: e.props.children.props.className }; })());
    t.note("takumi's primitives are React elements (they go through fromJsx); bm-engine's are node objects");
  }
  // the hooks render the same numbers in a footer band, per counter style
  const styles = ["decimal", "decimal-leading-zero", "lower-roman", "upper-roman", "lower-alpha", "lower-latin", "upper-alpha", "upper-latin", "lower-greek"];
  for (const s of styles) {
    const r = await t.both(DOC, { size: "a5", footer: `<p>N <span class="pageNumber ${s}"></span> T <span class="totalPages ${s}"></span></p>` });
    if (!r.ref) { t.same(s, 0, 0); continue; }
    if (sameError(t, s, r.bm, r.ref)) continue;
    t.same(`${s}: text`, r.bm.textPages.map(squash), r.ref.textPages.map(squash));
  }
});
