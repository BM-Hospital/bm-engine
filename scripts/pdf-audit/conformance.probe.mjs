// PDF/A and PDF/UA: validator matrix, versions, what each level writes, and every validation error reachable from HTML.
import { probe, font, INTER } from "./lib.mjs";
import { outcome, xmpNorm, catalogText, fileShape, infoNorm, deep, META, DATE, PNG1 as one } from "./filelayer.util.mjs";

const PDFA = [undefined, "2a", "2b", "2u", "3a", "3b", "3u", "4", "4f"];
const TAGGED = [false, true, "ua1", "ua2"];
const DOC = `<html lang="en"><body><h1>Title</h1><p>Hello <a href="https://example.com/">link</a></p><img alt="A dot" width="8" height="8" src="${one}"></body></html>`;

probe("conformance.matrix.complete-input", "pdfa x tagged matrix (36 cases) with title+lang+date: success / error text, version, XMP, catalog, Info, file shape, structure", async (t) => {
  for (const pdfa of PDFA) for (const tagged of TAGGED) {
    const r = await t.both(DOC, { pdfa, tagged, lang: "en", metadata: META });
    const id = `pdfa=${pdfa ?? "none"} tagged=${tagged}`;
    t.same(id + " outcome", outcome(r.bm), outcome(r.ref));
    if (r.ref && !r.bm.error && !r.ref.error) {
      t.same(id + " version", r.bm.version, r.ref.version);
      t.same(id + " xmp", xmpNorm(r.bm), xmpNorm(r.ref));
      t.same(id + " catalog", catalogText(r.bm), catalogText(r.ref));
      t.same(id + " info", infoNorm(r.bm), infoNorm(r.ref));
      t.same(id + " file shape", fileShape(r.bm), fileShape(r.ref));
      t.same(id + " structure", r.bm.structure, r.ref.structure);
    }
  }
});

probe("conformance.matrix.bare-input", "pdfa x tagged matrix (36 cases) with NO metadata / lang: error text and error count", async (t) => {
  for (const pdfa of PDFA) for (const tagged of TAGGED) {
    const r = await t.both(`<h1>Title</h1><p>Hello</p>`, { pdfa, tagged });
    t.same(`pdfa=${pdfa ?? "none"} tagged=${tagged} outcome`, outcome(r.bm), outcome(r.ref));
  }
});

probe("conformance.matrix.metadata-no-date", "pdfa x tagged matrix with metadata.title but no creationDate (MissingDocumentDate)", async (t) => {
  for (const pdfa of PDFA) for (const tagged of TAGGED) {
    const r = await t.both(`<h1>Title</h1><p>Hello</p>`, { pdfa, tagged, metadata: { title: "T" } });
    t.same(`pdfa=${pdfa ?? "none"} tagged=${tagged} outcome`, outcome(r.bm), outcome(r.ref));
  }
});

probe("conformance.matrix.lang-only", "pdfa x tagged matrix with lang but no metadata (tagged output sets metadata with lang -> date checked)", async (t) => {
  for (const pdfa of PDFA) for (const tagged of TAGGED) {
    const r = await t.both(`<h1>Title</h1><p>Hello</p>`, { pdfa, tagged, lang: "en" });
    t.same(`pdfa=${pdfa ?? "none"} tagged=${tagged} outcome`, outcome(r.bm), outcome(r.ref));
  }
});

probe("conformance.invalid-level", "unknown pdfa / tagged values (1a, 1b, 4e, ua3): error text", async (t) => {
  for (const o of [{ pdfa: "1b" }, { pdfa: "1a" }, { pdfa: "4e" }, { pdfa: "A2B" }, { pdfa: 2 }, { tagged: "ua3" }, { tagged: "UA1" }, { tagged: 1 }, { pdfa: "" }, { pdfa: null }, { tagged: null }]) {
    const r = await t.both(`<p>x</p>`, { ...o, metadata: META });
    t.same(JSON.stringify(o), outcome(r.bm), outcome(r.ref));
    if (r.ref) t.note(`${JSON.stringify(o)} => bm: ${outcome(r.bm)} | takumi: ${outcome(r.ref)}`);
  }
});

// Each case: [name, html, options]. Compared on outcome text (the error count is in the message).
const UA1 = { tagged: "ua1", lang: "en", metadata: META };
const nest = (style, n) => `<div style='${style}'>`.repeat(n) + "x" + "</div>".repeat(n);
const CASES = [
  ["NoDocumentTitle ua1", `<h1>T</h1>`, { tagged: "ua1", lang: "en", metadata: { creationDate: DATE } }],
  ["NoDocumentTitle ua1 empty title", `<h1>T</h1>`, { tagged: "ua1", lang: "en", metadata: { title: "", creationDate: DATE } }],
  ["NoDocumentTitle not checked by 2a", `<h1>T</h1>`, { pdfa: "2a", lang: "en", metadata: { creationDate: DATE } }],
  ["NoDocumentLanguage 2a", `<h1>T</h1>`, { pdfa: "2a", metadata: META }],
  ["NoDocumentLanguage 3a", `<h1>T</h1>`, { pdfa: "3a", metadata: META }],
  ["NoDocumentLanguage ua1 allowed", `<h1>T</h1>`, { tagged: "ua1", metadata: META }],
  ["NoDocumentLanguage ua2", `<h1>T</h1>`, { tagged: "ua2", metadata: META }],
  ["NoDocumentLanguage 2b allowed", `<h1>T</h1>`, { pdfa: "2b", metadata: META }],
  ["lang on <html> only (not options.lang) 2a", `<html lang="en"><body><h1>T</h1></body></html>`, { pdfa: "2a", metadata: META }],
  ["lang on <html> only ua2", `<html lang="en"><body><h1>T</h1></body></html>`, { tagged: "ua2", metadata: META }],
  ["invalid lang tag", `<h1>T</h1>`, { tagged: "ua2", lang: "not a lang!", metadata: META }],
  ["empty lang", `<h1>T</h1>`, { tagged: "ua2", lang: "", metadata: META }],
  ["MissingDocumentDate 2b with metadata", `<p>x</p>`, { pdfa: "2b", metadata: { title: "T" } }],
  ["MissingDocumentDate 2b without metadata, tagged false", `<p>x</p>`, { pdfa: "2b", tagged: false }],
  ["MissingDocumentDate 2b without metadata, tagged true, no lang", `<p>x</p>`, { pdfa: "2b" }],
  ["MissingDocumentDate 4 lang untagged", `<p>x</p>`, { pdfa: "4", tagged: false, lang: "en" }],
  ["MissingDocumentDate ua1 allowed", `<h1>x</h1>`, { tagged: "ua1", lang: "en", metadata: { title: "T" } }],
  ["MissingAltText img without alt ua1", `<h1>T</h1><img src="${one}" width="8" height="8">`, UA1],
  ["MissingAltText two imgs without alt ua1 (dedupe)", `<h1>T</h1><img src="${one}" width="8" height="8"><img src="${one}" width="9" height="9">`, UA1],
  ["MissingAltText img without alt 2a", `<h1>T</h1><img src="${one}" width="8" height="8">`, { pdfa: "2a", lang: "en", metadata: META }],
  ["MissingAltText img without alt 2b allowed", `<h1>T</h1><img src="${one}" width="8" height="8">`, { pdfa: "2b", lang: "en", metadata: META }],
  ["MissingAltText img without alt 4 allowed", `<h1>T</h1><img src="${one}" width="8" height="8">`, { pdfa: "4", lang: "en", metadata: META }],
  ["img alt='' is an artifact ua1", `<h1>T</h1><img alt="" src="${one}" width="8" height="8">`, UA1],
  ["img alt=' ' (space) ua1", `<h1>T</h1><img alt=" " src="${one}" width="8" height="8">`, UA1],
  ["figure without img alt ua1", `<h1>T</h1><figure><img src="${one}" width="8" height="8"><figcaption>cap</figcaption></figure>`, UA1],
  ["svg inline without title ua1", `<h1>T</h1><svg width="10" height="10"><rect width="10" height="10" fill="red"/></svg>`, UA1],
  ["MissingHeadingTitle: heading with only an image ua1", `<h1><img alt="x" src="${one}" width="8" height="8"></h1>`, UA1],
  ["MissingHeadingTitle: heading with only whitespace span ua1", `<h1><span> </span></h1><p>x</p>`, UA1],
  ["MissingHeadingTitle: empty h1 ua1", `<h1></h1><p>x</p>`, UA1],
  ["MissingHeadingTitle allowed by 2a", `<h1><img alt="x" src="${one}" width="8" height="8"></h1>`, { pdfa: "2a", lang: "en", metadata: META }],
  ["MissingDocumentOutline: no headings ua1", `<p>x</p>`, UA1],
  ["MissingDocumentOutline: no headings ua2", `<p>x</p>`, { tagged: "ua2", lang: "en", metadata: META }],
  ["MissingDocumentOutline: no headings ua1 outline:true", `<p>x</p>`, { ...UA1, outline: true }],
  ["outline:false with headings ua1 (forced on)", `<h1>x</h1>`, { ...UA1, outline: false }],
  ["MissingDocumentOutline: empty document ua1", ``, UA1],
  ["MissingDocumentOutline: heading only in header band ua1", `<p>x</p>`, { ...UA1, size: "A4", header: `<h1>Band</h1>` }],
  ["MissingAnnotationAltText: untagged link 2b", `<p><a href="https://e.com/">x</a></p>`, { pdfa: "2b", tagged: false, metadata: META }],
  ["link in tagged 2a", `<p><a href="https://e.com/">x</a></p>`, { pdfa: "2a", lang: "en", metadata: META }],
  ["link in repeated thead ua1 (repeated fragment: annotation without alt)", `<h1>T</h1><table><thead><tr><th><a href="https://e.com/">h</a></th></tr></thead><tbody>${"<tr><td>row</td></tr>".repeat(80)}</tbody></table>`, { ...UA1, size: "A5" }],
  ["link in repeated thead 2a", `<h1>T</h1><table><thead><tr><th><a href="https://e.com/">h</a></th></tr></thead><tbody>${"<tr><td>row</td></tr>".repeat(80)}</tbody></table>`, { pdfa: "2a", lang: "en", metadata: META, size: "A5" }],
  ["link in header band ua1", `<h1>T</h1><p>x</p>`, { ...UA1, size: "A4", header: `<a href="https://e.com/">band</a>` }],
  ["link in header band 2a", `<h1>T</h1><p>x</p>`, { pdfa: "2a", lang: "en", metadata: META, size: "A4", header: `<a href="https://e.com/">band</a>` }],
  ["MissingTagging: 2a tagged false", `<p>x</p>`, { pdfa: "2a", tagged: false, lang: "en", metadata: META }],
  ["ContainsPostScript: conic gradient 2b", `<div style="width:100px;height:100px;background:conic-gradient(red,blue)"></div>`, { pdfa: "2b", metadata: META }],
  ["ContainsPostScript: conic gradient 4 allowed", `<div style="width:100px;height:100px;background:conic-gradient(red,blue)"></div>`, { pdfa: "4", metadata: META }],
  ["ContainsPostScript: repeating-linear-gradient 2b", `<div style="width:100px;height:100px;background:repeating-linear-gradient(red,blue 10px)"></div>`, { pdfa: "2b", metadata: META }],
  ["ContainsPostScript: repeating-radial-gradient 3b", `<div style="width:100px;height:100px;background:repeating-radial-gradient(red,blue 10px)"></div>`, { pdfa: "3b", metadata: META }],
  ["ContainsPostScript: two conic gradients (dedupe) 2b", `<div style="width:100px;height:100px;background:conic-gradient(red,blue)"></div><div style="width:50px;height:50px;background:conic-gradient(green,blue)"></div>`, { pdfa: "2b", metadata: META }],
  ["ContainsPostScript ua1 allowed", `<h1>T</h1><div style="width:100px;height:100px;background:conic-gradient(red,blue)"></div>`, UA1],
  ["Transparency allowed 2b", `<div style="opacity:.5;width:50px;height:50px;background:red"></div>`, { pdfa: "2b", metadata: META }],
  ["TooLongString: 40000-char title 2b", `<p>x</p>`, { pdfa: "2b", metadata: { title: "t".repeat(40000), creationDate: DATE } }],
  ["TooLongString: 40000-char title 4 allowed", `<p>x</p>`, { pdfa: "4", metadata: { title: "t".repeat(40000), creationDate: DATE } }],
  ["TooLongString: 40000-char title none", `<p>x</p>`, { metadata: { title: "t".repeat(40000), creationDate: DATE } }],
  ["TooLongString: 20000-char non-ASCII title 2b (UTF-16 doubles)", `<p>x</p>`, { pdfa: "2b", metadata: { title: "é".repeat(20000), creationDate: DATE } }],
  ["TooLongString: 32767-char title 2b (at limit)", `<p>x</p>`, { pdfa: "2b", metadata: { title: "t".repeat(32767), creationDate: DATE } }],
  ["TooLongString: 32768-char title 2b (over limit)", `<p>x</p>`, { pdfa: "2b", metadata: { title: "t".repeat(32768), creationDate: DATE } }],
  ["TooLongString: 40000-char link URI 2b", `<p><a href="https://e.com/${"a".repeat(40000)}">x</a></p>`, { pdfa: "2b", metadata: META }],
  ["TooLongString: 40000-char alt 2a", `<h1>T</h1><img alt="${"a".repeat(40000)}" src="${one}" width="8" height="8">`, { pdfa: "2a", lang: "en", metadata: META }],
  ["TooLongString: 40000-char heading 3b outline", `<h1>${"a ".repeat(20000)}</h1>`, { pdfa: "3b", outline: true, metadata: META }],
  ["TooLongString: 40000-char attachment description 3b", `<p>x</p>`, { pdfa: "3b", metadata: META, attachments: [{ name: "a.txt", data: "x", mimeType: "text/plain", description: "d".repeat(40000) }] }],
  ["TooLongName: 140-char mime 3b", `<p>x</p>`, { pdfa: "3b", metadata: META, attachments: [{ name: "a.txt", data: "x", mimeType: "text/" + "p".repeat(140), description: "d" }] }],
  ["TooLongName: 140-char mime 4f allowed", `<p>x</p>`, { pdfa: "4f", metadata: META, attachments: [{ name: "a.txt", data: "x", mimeType: "text/" + "p".repeat(140), description: "d" }] }],
  ["TooHighQNestingLevel: 40 nested clips 2b", nest("overflow:hidden;padding:1px", 40), { pdfa: "2b", metadata: META }],
  ["TooHighQNestingLevel: 40 nested opacity 2b", nest("opacity:.9;padding:1px", 40), { pdfa: "2b", metadata: META }],
  ["TooHighQNestingLevel: 40 nested transforms 3u", nest("transform:rotate(1deg);padding:1px", 40), { pdfa: "3u", metadata: META }],
  ["TooHighQNestingLevel: 40 nested clips 4 allowed", nest("overflow:hidden;padding:1px", 40), { pdfa: "4", metadata: META }],
  ["TooHighQNestingLevel: 40 nested clips ua1 allowed", "<h1>T</h1>" + nest("overflow:hidden;padding:1px", 40), UA1],
  ["TooHighQNestingLevel: 26 nested clips 2b", nest("overflow:hidden;padding:1px", 26), { pdfa: "2b", metadata: META }],
  ["TooHighQNestingLevel: 14 nested clips 2b", nest("overflow:hidden;padding:1px", 14), { pdfa: "2b", metadata: META }],
  ["UnicodePrivateArea: U+E000 text 2a", `<h1>T</h1><p>ab</p>`, { pdfa: "2a", lang: "en", metadata: META, uncoveredText: "blank" }],
  ["UnicodePrivateArea: U+E000 text 4", `<p>ab</p>`, { pdfa: "4", metadata: META, uncoveredText: "blank" }],
  ["UnicodePrivateArea: U+E000 text 2u", `<p>ab</p>`, { pdfa: "2u", metadata: META, uncoveredText: "blank" }],
  ["InvalidCodepointMapping: U+FEFF text 2u", `<p>a﻿b</p>`, { pdfa: "2u", metadata: META, uncoveredText: "blank" }],
  ["InvalidCodepointMapping: U+FEFF text ua1", `<h1>a﻿b</h1>`, { ...UA1, uncoveredText: "blank" }],
  ["InvalidCodepointMapping: U+FEFF text 2b allowed", `<p>a﻿b</p>`, { pdfa: "2b", metadata: META, uncoveredText: "blank" }],
  ["soft hyphen / ZWJ / ZWSP / NBSP text 2u", `<p>soft­hy zero​width join‍er nb sp</p>`, { pdfa: "2u", metadata: META, uncoveredText: "blank" }],
  ["tab and control chars 2u", `<pre>a\tb\u0001c</pre>`, { pdfa: "2u", metadata: META, uncoveredText: "blank" }],
  ["ContainsNotDefGlyph: placeholder 2b", `<p>a中b</p>`, { pdfa: "2b", metadata: META, uncoveredText: "placeholder" }],
  ["ContainsNotDefGlyph: placeholder ua1", `<h1>a中b</h1>`, { ...UA1, uncoveredText: "placeholder" }],
  ["ContainsNotDefGlyph: placeholder ua2", `<h1>a中b</h1>`, { tagged: "ua2", lang: "en", metadata: META, uncoveredText: "placeholder" }],
  ["placeholder 3a + ua1 (which standard is named)", `<h1>a中b</h1>`, { pdfa: "3a", tagged: "ua1", lang: "en", metadata: META, uncoveredText: "placeholder" }],
  ["placeholder 4f + ua2", `<h1>a中b</h1>`, { pdfa: "4f", tagged: "ua2", lang: "en", metadata: META, uncoveredText: "placeholder" }],
  ["uncovered error default 2b", `<p>a中b</p>`, { pdfa: "2b", metadata: META }],
  ["uncovered blank 2b", `<p>a中b</p>`, { pdfa: "2b", metadata: META, uncoveredText: "blank" }],
  ["uncovered blank 2u (blank leaves no glyph)", `<p>a中b</p>`, { pdfa: "2u", metadata: META, uncoveredText: "blank" }],
  ["uncovered blank ua1", `<h1>a中b</h1>`, { ...UA1, uncoveredText: "blank" }],
  ["several errors at once: 2a no lang, img no alt, no date", `<h1>T</h1><img src="${one}" width="8" height="8"><p><a href="https://e.com">l</a></p>`, { pdfa: "2a", metadata: { title: "T" } }],
  ["several errors at once: ua1 no title, img no alt, heading without title", `<h1><img src="${one}" width="8" height="8"></h1>`, { tagged: "ua1" }],
  ["both validators prohibit the same error (3a+ua1 img no alt)", `<h1>T</h1><img src="${one}" width="8" height="8">`, { pdfa: "3a", tagged: "ua1", lang: "en", metadata: META }],
];

for (const [name, html, options] of CASES) {
  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60);
  probe("conformance.validation." + slug, "validation: " + name, async (t) => {
    const r = await t.both(html, options);
    t.same("outcome", outcome(r.bm), outcome(r.ref));
    if (r.ref) t.note(`takumi: ${outcome(r.ref)}`);
  });
}

probe("conformance.output-intent", "OutputIntents + ICC profile bytes per PDF/A level; ICCBased colour spaces instead of DeviceRGB", async (t) => {
  for (const pdfa of ["2b", "3u", "4", "4f"]) {
    const r = await t.both(`<p style="color:#123456;background:#eee">x</p><div style="width:20px;height:20px;background:linear-gradient(red,blue)"></div>`, { pdfa, metadata: META });
    if (!t.same(pdfa + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) continue;
    const oi = (d) => deep(d, d.catalog.OutputIntents, 0, 2);
    t.same(pdfa + " OutputIntents", oi(r.bm), oi(r.ref));
    const icc = (d) => [...d.pdf.objs.values()].filter((o) => o.raw && o.dict.N !== undefined && !o.dict.Type).map((o) => ({ n: o.dict.N, range: JSON.stringify(o.dict.Range), filter: String(o.dict.Filter), bytes: o.data.toString("hex") }));
    t.same(pdfa + " ICC profile streams", icc(r.bm), icc(r.ref));
    const cs = (d) => (d.content(0).match(/\/[A-Za-z0-9]+ (?:cs|CS)\b|\b(?:rg|RG|g|G|k|K)\b/g) || []).map((x) => x.replace(/\/\w+ /, "/N ")).join(" ");
    t.same(pdfa + " colour operators", cs(r.bm), cs(r.ref));
  }
});

probe("conformance.page-dictionary", "page dictionary per level: /Tabs, /Group, /StructParents, boxes", async (t) => {
  for (const o of [{}, { tagged: false }, { pdfa: "2b" }, { pdfa: "2a", lang: "en" }, { tagged: "ua1", lang: "en" }, { tagged: "ua2", lang: "en" }, { pdfa: "4f", tagged: "ua2", lang: "en" }]) {
    const r = await t.both(`<h1>T</h1><p>Hello <a href="https://example.com/">link</a></p><div style="opacity:.5">o</div>`, { ...o, metadata: META });
    if (!t.same(JSON.stringify(o) + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) continue;
    const pg = (d) => d.pdf.pages.map((p) => Object.fromEntries(Object.entries(p.dict).filter(([k]) => !["Parent", "Contents", "Resources", "Annots"].includes(k)).map(([k, v]) => [k, deep(d, v, 0, 1)])));
    t.same(JSON.stringify(o) + " page dict", pg(r.bm), pg(r.ref));
  }
});

probe("conformance.fonts.restricted-license", "RestrictedLicense (OS/2 fsType & 0xF == 2): refused under PDF/A / PDF/UA, embedded otherwise", async (t) => {
  // Inter-Regular with fsType patched to 2 (restricted licence embedding).
  const src = Buffer.from(font(INTER));
  const n = src.readUInt16BE(4);
  let patched = null;
  for (let i = 0; i < n; i++) { const o = 12 + i * 16; if (src.toString("latin1", o, o + 4) === "OS/2") { patched = Buffer.from(src); patched.writeUInt16BE(2, src.readUInt32BE(o + 8) + 8); } }
  t.ok(!!patched, "patched font built");
  const f = [{ name: "Restricted", data: new Uint8Array(patched) }];
  for (const o of [{}, { pdfa: "2b" }, { pdfa: "4" }, { tagged: "ua1", lang: "en" }, { pdfa: "3a", tagged: "ua1", lang: "en" }]) {
    const r = await t.both(`<h1 style="font-family:Restricted">Title</h1>`, { ...o, metadata: META }, { fonts: f });
    t.same(JSON.stringify(o), outcome(r.bm), outcome(r.ref));
    if (r.ref) t.note(`${JSON.stringify(o)} => bm: ${outcome(r.bm)} | takumi: ${outcome(r.ref)}`);
  }
});

probe("conformance.validation.error-count-per-glyph", "krilla counts one error per distinct (font, glyph, codepoint): several PUA / invalid codepoints / restricted fonts -> N errors", async (t) => {
  const src = Buffer.from(font(INTER)); const n = src.readUInt16BE(4);
  const restricted = (from) => { const b = Buffer.from(font(from)); const k = b.readUInt16BE(4); for (let i = 0; i < k; i++) { const o = 12 + i * 16; if (b.toString("latin1", o, o + 4) === "OS/2") b.writeUInt16BE(2, b.readUInt32BE(o + 8) + 8); } return new Uint8Array(b); };
  t.ok(n > 0, "font read");
  const cases = [
    ["two PUA codepoints, pdf/a-4", `<p>a\uE000b\uE001c\uE002</p>`, { pdfa: "4", metadata: META, uncoveredText: "blank" }, undefined],
    ["same PUA codepoint twice, pdf/a-4", `<p>\uE000 and \uE000</p>`, { pdfa: "4", metadata: META, uncoveredText: "blank" }, undefined],
    ["PUA + invalid codepoint, pdf/a-2a", `<h1>T</h1><p>\uE000 \uFEFF</p>`, { pdfa: "2a", lang: "en", metadata: META, uncoveredText: "blank" }, undefined],
    ["U+FEFF after two different letters, pdf/a-2u", `<p>a\uFEFF b\uFEFF</p>`, { pdfa: "2u", metadata: META, uncoveredText: "blank" }, undefined],
    ["PUA in two fonts, pdf/a-4", `<p>\uE000</p><p style="font-family:Roboto">\uE000</p>`, { pdfa: "4", metadata: META, uncoveredText: "blank" }, [INTER, "assets/fonts/Roboto-Regular.ttf"]],
    ["two restricted fonts, pdf/a-2b", `<p style="font-family:R1">one</p><p style="font-family:R2">two</p>`, { pdfa: "2b", metadata: META }, [{ name: "R1", data: restricted(INTER) }, { name: "R2", data: restricted("assets/fonts/Roboto-Regular.ttf") }]],
    ["two conic gradients + restricted font + no date, pdf/a-2b", `<p style="font-family:R1">one</p><div style="width:50px;height:50px;background:conic-gradient(red,blue)"></div>`, { pdfa: "2b", metadata: { title: "T" } }, [{ name: "R1", data: restricted(INTER) }]],
  ];
  for (const [name, html, o, fonts] of cases) {
    const r = await t.both(html, o, fonts ? { fonts } : undefined);
    t.same(name, outcome(r.bm), outcome(r.ref));
    if (r.ref) t.note(`${name} => bm: ${outcome(r.bm)} | takumi: ${outcome(r.ref)}`);
  }
});
