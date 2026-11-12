// Document metadata: Info dictionary, XMP packet, /Lang, /ViewerPreferences, /ID, custom XMP schemas, dates, attachments.
import { probe } from "./lib.mjs";
import { outcome, xmp, xmpNorm, catalogText, infoNorm, fileId, attachmentsText, deep, sameText, META, DATE } from "./filelayer.util.mjs";

const HTML = `<h1>Title</h1><p>Hello</p>`;

/** Compares outcome, Info, XMP, catalog and /ID relation for one option set. */
async function meta(t, id, options, html = HTML) {
  const r = await t.both(html, options);
  if (!t.same(id + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) return r;
  t.same(id + " info", infoNorm(r.bm), infoNorm(r.ref));
  t.same(id + " raw Info object", rawInfo(r.bm), rawInfo(r.ref));
  sameText(t, id + " xmp", xmpNorm(r.bm), xmpNorm(r.ref));
  t.same(id + " catalog", catalogText(r.bm), catalogText(r.ref));
  t.same(id + " XMP stream dict", xmpDict(r.bm), xmpDict(r.ref));
  t.same(id + " /ID shape", idShape(r.bm), idShape(r.ref));
  return r;
}
/** The Info dictionary as written (string encoding included), producer replaced. */
function rawInfo(d) {
  const i = d.pdf.trailer.Info;
  if (!i) return null;
  return deep(d, i, 0, 1).replace(/\/Producer \((?:[^()\\]|\\.)*\)/, "/Producer (P)");
}
const xmpDict = (d) => { const o = d.pdf.obj(d.catalog.Metadata); return o ? Object.fromEntries(Object.entries(o.dict).map(([k, v]) => [k, k === "Length" ? "N" : String(v)])) : null; };
/** [document id == instance id, lengths, xmp ids equal the trailer ids]. */
function idShape(d) {
  const id = fileId(d); const x = xmp(d) || "";
  const doc = (x.match(/<xmpMM:DocumentID>([^<]*)/) || [])[1]; const inst = (x.match(/<xmpMM:InstanceID>([^<]*)/) || [])[1];
  return id ? { same: id[0] === id[1], len: id.map((s) => s.length), xmpDoc: doc === id[0], xmpInst: inst === id[1], base64: id.every((s) => /^[A-Za-z0-9+/=]+$/.test(s)) } : null;
}

probe("metadata.none", "no metadata, no lang: Info (/Producer only?), XMP, catalog", async (t) => {
  await meta(t, "tagged default", {});
  await meta(t, "tagged false", { tagged: false });
});

probe("metadata.producer", "/Producer and pdf:Producer text: `takumi-pdf <version>` vs bm's; `producer` option from JS", async (t) => {
  const r = await t.both(HTML, {});
  if (r.ref && !r.bm.error) {
    t.note(`Producer: bm ${JSON.stringify(r.bm.info.Producer)} | takumi ${JSON.stringify(r.ref.info.Producer)}`);
    t.ok(/^bm-engine|^takumi-pdf/.test(r.bm.info.Producer || ""), "bm writes a /Producer");
    t.same("pdf:Producer equals /Producer", (xmp(r.bm).match(/<pdf:Producer>([^<]*)/) || [])[1] === r.bm.info.Producer, (xmp(r.ref).match(/<pdf:Producer>([^<]*)/) || [])[1] === r.ref.info.Producer);
  }
  const p = await t.both(HTML, { producer: "ACME Writer 1.0" });
  t.same("producer option outcome", outcome(p.bm), outcome(p.ref));
  if (p.ref && !p.bm.error && !p.ref.error) {
    t.same("producer option honoured (Info /Producer == option)", p.bm.info.Producer === "ACME Writer 1.0", p.ref.info.Producer === "ACME Writer 1.0");
    t.note(`producer option: bm ${JSON.stringify(p.bm.info.Producer)} | takumi ${JSON.stringify(p.ref.info.Producer)}`);
  }
});

probe("metadata.info.all-fields", "title / description / authors / keywords / creator / creationDate -> Info + XMP", async (t) => {
  await meta(t, "all", { lang: "en", metadata: { title: "Annual report 2026", description: "Consolidated results", authors: ["Acme Inc.", "Bob"], keywords: ["annual report", "2026"], creator: "acme-reporting", creationDate: DATE } });
  await meta(t, "date only (YYYY-MM-DD)", { metadata: { creationDate: "2026-08-06" } });
  await meta(t, "date with Z", { metadata: { creationDate: "2026-08-06T23:59:59Z" } });
  await meta(t, "single author", { metadata: { authors: ["Solo"] } });
  await meta(t, "title + authors (document id from title+authors)", { metadata: { title: "T", authors: ["A"] } });
  await meta(t, "empty strings and arrays", { metadata: { title: "", description: "", authors: [], keywords: [], creator: "" } });
  await meta(t, "empty author / keyword items", { metadata: { authors: ["", "B"], keywords: ["", "k"] } });
  await meta(t, "empty metadata object", { metadata: {} });
  await meta(t, "pdf 2.0 (ua2): Info without text fields, dc:creator as a list", { tagged: "ua2", lang: "en", metadata: { title: "T2", description: "D", authors: ["A", "B"], keywords: ["k1", "k2"], creator: "C", creationDate: DATE } });
  await meta(t, "pdf 2.0 (ua2) no date: Info dictionary present?", { tagged: "ua2", lang: "en", metadata: { title: "T2" } });
  await meta(t, "pdf/a-4: no Info", { pdfa: "4", lang: "en", metadata: { title: "T2", authors: ["A", "B"], creationDate: DATE } });
  await meta(t, "pdf/a-2b history", { pdfa: "2b", metadata: { title: "T", creator: "Tool & Co <x>", creationDate: DATE } });
  await meta(t, "pdf/a-3a + ua1", { pdfa: "3a", tagged: "ua1", lang: "en-US", metadata: { title: "T", creationDate: DATE } });
});

probe("metadata.info.encoding", "non-ASCII / special characters in Info strings and XMP (PDFDocEncoding vs UTF-16BE, XML escaping)", async (t) => {
  await meta(t, "latin-1", { metadata: { title: "Café déjà vu", authors: ["Zoë"], keywords: ["naïve"], description: "x © y" } });
  await meta(t, "cjk + emoji (surrogates)", { metadata: { title: "報告書 😀", authors: ["山田"], creator: "ツール" } });
  await meta(t, "xml specials", { metadata: { title: `A & B <c> "d" 'e'`, description: "x]]>y", creator: "<![CDATA[z]]>", keywords: ["a&b", "c<d"] } });
  await meta(t, "pdf string specials", { metadata: { title: "paren ( unbalanced \\ back ) ) (", description: "line1\nline2\ttab\rcr", creator: "(balanced (nested))" } });
  await meta(t, "control chars and DEL", { metadata: { title: "a\u0001b\u007Fc\u0000d", description: " nbsp ls" } });
  await meta(t, "leading BOM-like / PDFDoc bytes", { metadata: { title: "þÿ looks like a BOM", description: "\u0080\u009F C1" } });
  await meta(t, "keywords with commas", { metadata: { keywords: ["a, b", "c"], authors: ["Doe, John", "Roe, Jane"] } });
});

probe("metadata.date.invalid", "creationDate validation: accepted forms and error text", async (t) => {
  for (const d of ["2026-08-06", "2026-08-06T01:02:03", "2026-08-06T01:02:03Z", "2028-02-29", "2026-02-30", "2026-13-01", "26-08-06", "2026-8-6", "2026-08-06 01:02:03", "2026-08-06T01:02", "2026-08-06T24:00:00", "2026-08-06T01:02:03+02:00", "2026-08-06T01:02:03.123", "", "today", "0000-01-01", "9999-12-31T23:59:59"]) {
    const r = await t.both(HTML, { metadata: { creationDate: d } });
    t.same(JSON.stringify(d) + " outcome", outcome(r.bm), outcome(r.ref));
    if (r.ref && !r.bm.error && !r.ref.error) t.same(JSON.stringify(d) + " dates", [r.bm.info.CreationDate, r.bm.info.ModDate], [r.ref.info.CreationDate, r.ref.info.ModDate]);
  }
  for (const d of [new Date(Date.UTC(2026, 7, 6, 1, 2, 3)), 1786000000000, null]) {
    const r = await t.both(HTML, { metadata: { creationDate: d } });
    t.same("non-string " + String(d) + " outcome", outcome(r.bm), outcome(r.ref));
  }
});

probe("metadata.lang", "lang -> catalog /Lang, dc:language, structure root /Lang; element lang attributes", async (t) => {
  for (const lang of ["en", "en-US", "zh-Hant-TW", "de-CH-1996", "x-private", "EN", "en_US", "i-klingon", "e", "toolongsubtagxx"]) {
    const r = await t.both(HTML, { lang });
    if (!t.same(lang + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) continue;
    t.same(lang + " catalog /Lang", deep(r.bm, r.bm.catalog.Lang), deep(r.ref, r.ref.catalog.Lang));
    t.same(lang + " xmp", xmpNorm(r.bm), xmpNorm(r.ref));
    t.same(lang + " structure", r.bm.structure, r.ref.structure);
  }
  const cases = [
    ["html lang attribute only", `<html lang="fr"><body><p>Bonjour</p></body></html>`, {}],
    ["html lang + options.lang", `<html lang="fr"><body><p>Bonjour</p></body></html>`, { lang: "en" }],
    ["lang untagged", `<p>x</p>`, { lang: "en", tagged: false }],
    ["element lang attributes", `<p>English <span lang="de">Deutsch</span></p><p lang="ja">日本語なし</p><div lang="fr"><p>Bonjour</p><ul><li>un</li></ul></div><h1 lang="es">Hola</h1>`, { lang: "en", uncoveredText: "blank" }],
    ["element lang, no document lang", `<p lang="de">Deutsch</p>`, {}],
    ["xml:lang attribute", `<p xml:lang="de">Deutsch</p>`, { lang: "en" }],
  ];
  for (const [name, html, o] of cases) {
    const r = await t.both(html, o);
    if (!t.same(name + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) continue;
    t.same(name + " catalog /Lang", deep(r.bm, r.bm.catalog.Lang), deep(r.ref, r.ref.catalog.Lang));
    t.same(name + " xmp", xmpNorm(r.bm), xmpNorm(r.ref));
    t.same(name + " structure", r.bm.structure, r.ref.structure);
  }
});

probe("metadata.viewer-preferences", "/ViewerPreferences /DisplayDocTitle (UA only), no /PageMode, /PageLayout, /Direction", async (t) => {
  for (const o of [{ metadata: { title: "T" } }, { tagged: "ua1", lang: "en", metadata: { title: "T" } }, { tagged: "ua2", lang: "en", metadata: { title: "T" } }, { pdfa: "2a", lang: "en", metadata: META }, { outline: true, metadata: { title: "T" } }]) {
    const r = await t.both(`<html dir="rtl"><body><h1>T</h1></body></html>`, o);
    if (!t.same(JSON.stringify(o) + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) continue;
    t.same(JSON.stringify(o) + " catalog keys", Object.keys(r.bm.catalog).sort(), Object.keys(r.ref.catalog).sort());
    t.same(JSON.stringify(o) + " ViewerPreferences", deep(r.bm, r.bm.catalog.ViewerPreferences), deep(r.ref, r.ref.catalog.ViewerPreferences));
  }
});

probe("metadata.id.determinism", "document /ID: same input twice -> identical bytes; id rules (title+authors -> document id; else instance id)", async (t) => {
  for (const [name, o] of [["no metadata", {}], ["title only", { metadata: { title: "T" } }], ["title+authors", { metadata: { title: "T", authors: ["A"] } }], ["with date", { metadata: META }], ["pdfa 2b", { pdfa: "2b", metadata: META }]]) {
    const a = await t.both(HTML, o); const b = await t.both(HTML, o);
    if (a.bm.error) { t.ok(false, name + ": bm error " + a.bm.error); continue; }
    t.ok(Buffer.compare(Buffer.from(a.bm.bytes), Buffer.from(b.bm.bytes)) === 0, name + ": bm renders identical bytes twice");
    if (a.ref && !a.ref.error) {
      t.same(name + ": deterministic", Buffer.compare(Buffer.from(a.bm.bytes), Buffer.from(b.bm.bytes)) === 0, Buffer.compare(Buffer.from(a.ref.bytes), Buffer.from(b.ref.bytes)) === 0);
      t.same(name + ": /ID shape", idShape(a.bm), idShape(a.ref));
      t.same(name + ": CreationDate present", [a.bm.info.CreationDate, a.bm.info.ModDate], [a.ref.info.CreationDate, a.ref.info.ModDate]);
    }
  }
  // the document id of title+authors depends only on (version, title, authors): equal for two different bodies
  const x = await t.both(`<p>one</p>`, { metadata: { title: "T", authors: ["A"] } }); const y = await t.both(`<p>two different</p>`, { metadata: { title: "T", authors: ["A"] } });
  if (x.ref && !x.bm.error) {
    t.same("title+authors: document id stable across contents", fileId(x.bm)[0] === fileId(y.bm)[0], fileId(x.ref)[0] === fileId(y.ref)[0]);
    t.same("title+authors: instance id differs across contents", fileId(x.bm)[1] !== fileId(y.bm)[1], fileId(x.ref)[1] !== fileId(y.ref)[1]);
    // the document id is krilla's SipHash of ("PDF 1.7", title, authors): identical in both engines when the hash is ported
    t.same("title+authors: document id value", fileId(x.bm)[0], fileId(x.ref)[0]);
  }
});

const FX = { name: "Factur-X PDF/A Extension", prefix: "fx", namespace: "urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#", properties: [
  { name: "DocumentFileName", value: "factur-x.xml", description: "The name of the embedded XML document" },
  { name: "DocumentType", value: "INVOICE", description: "The type of the hybrid document" },
  { name: "Version", value: "1.0", description: "The version of the standard" },
  { name: "ConformanceLevel", value: "EN 16931", description: "The conformance level" }] };

probe("metadata.xmp.custom-schema", "metadata.xmp custom schemas: properties + PDF/A extension schema description, per level", async (t) => {
  for (const o of [{}, { pdfa: "3b" }, { pdfa: "2u" }, { pdfa: "4f" }, { tagged: "ua1", lang: "en" }, { tagged: "ua2", lang: "en" }, { pdfa: "3a", tagged: "ua1", lang: "en" }, { pdfa: "4", tagged: "ua2", lang: "en" }])
    await meta(t, "fx " + JSON.stringify(o), { ...o, metadata: { ...META, xmp: [FX] } });
  await meta(t, "two schemas", { pdfa: "3b", metadata: { ...META, xmp: [FX, { name: "Other", prefix: "ot", namespace: "http://example.com/ns/other/", properties: [{ name: "Key", value: "v & <w>", description: "d \"q\"" }] }] } });
  await meta(t, "schema without properties", { pdfa: "3b", metadata: { ...META, xmp: [{ name: "Empty", prefix: "em", namespace: "http://example.com/ns/empty/", properties: [] }] } });
  await meta(t, "empty xmp list", { pdfa: "3b", metadata: { ...META, xmp: [] } });
  await meta(t, "same prefix twice", { metadata: { ...META, xmp: [FX, FX] } });
  await meta(t, "prefix clashing with a built-in (pdf)", { pdfa: "2b", metadata: { ...META, xmp: [{ name: "Clash", prefix: "pdf", namespace: "http://example.com/ns/clash/", properties: [{ name: "Thing", value: "v", description: "d" }] }] } });
  await meta(t, "non-ASCII values and names", { pdfa: "3b", metadata: { ...META, xmp: [{ name: "Schéma", prefix: "é", namespace: "http://example.com/ns/é/", properties: [{ name: "Propriété", value: "valeur 😀", description: "déscription" }] }] } });
  await meta(t, "empty name / value / description", { pdfa: "3b", metadata: { ...META, xmp: [{ name: "", prefix: "p", namespace: "urn:x", properties: [{ name: "A", value: "", description: "" }] }] } });
});

probe("metadata.xmp.invalid-schema", "InvalidXmpSchema: prefix / property name / namespace that cannot be XML (error text)", async (t) => {
  const bad = [
    ["empty prefix", { name: "N", prefix: "", namespace: "urn:x", properties: [] }],
    ["prefix starting with digit", { name: "N", prefix: "1x", namespace: "urn:x", properties: [] }],
    ["prefix with colon", { name: "N", prefix: "a:b", namespace: "urn:x", properties: [] }],
    ["prefix with space", { name: "N", prefix: "a b", namespace: "urn:x", properties: [] }],
    ["prefix underscore start (valid)", { name: "N", prefix: "_a-b.c", namespace: "urn:x", properties: [] }],
    ["prefix xml (reserved, valid name)", { name: "N", prefix: "xml", namespace: "urn:x", properties: [] }],
    ["empty namespace", { name: "N", prefix: "p", namespace: "", properties: [] }],
    ["namespace with space", { name: "N", prefix: "p", namespace: "urn:a b", properties: [] }],
    ["namespace with quote", { name: "N", prefix: "p", namespace: "urn:a\"b", properties: [] }],
    ["namespace with apostrophe", { name: "N", prefix: "p", namespace: "urn:a'b", properties: [] }],
    ["namespace with <", { name: "N", prefix: "p", namespace: "urn:a<b", properties: [] }],
    ["namespace with &", { name: "N", prefix: "p", namespace: "urn:a&b", properties: [] }],
    ["namespace with NBSP (unicode whitespace)", { name: "N", prefix: "p", namespace: "urn:a b", properties: [] }],
    ["property name empty", { name: "N", prefix: "p", namespace: "urn:x", properties: [{ name: "", value: "v", description: "d" }] }],
    ["property name with space", { name: "N", prefix: "p", namespace: "urn:x", properties: [{ name: "a b", value: "v", description: "d" }] }],
    ["property name starting with -", { name: "N", prefix: "p", namespace: "urn:x", properties: [{ name: "-a", value: "v", description: "d" }] }],
    ["second schema invalid", FX, { name: "N", prefix: "", namespace: "urn:x", properties: [] }],
    ["missing properties field", { name: "N", prefix: "p", namespace: "urn:x" }],
    ["missing description field", { name: "N", prefix: "p", namespace: "urn:x", properties: [{ name: "A", value: "v" }] }],
    ["missing name field", { prefix: "p", namespace: "urn:x", properties: [] }],
  ];
  for (const [name, ...schemas] of bad) {
    const r = await t.both(HTML, { metadata: { title: "T", xmp: schemas } });
    t.same(name + " outcome", outcome(r.bm), outcome(r.ref));
    if (r.ref) t.note(`${name} => takumi: ${outcome(r.ref)}`);
  }
});

// ---------------------------------------------------------------------------------------------- attachments

const ATT = { name: "factur-x.xml", data: "<invoice>é</invoice>", mimeType: "application/xml", description: "Factur-X invoice data", relationship: "alternative" };

async function att(t, id, options) {
  const r = await t.both(HTML, options);
  if (!t.same(id + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) return r;
  t.same(id + " attachments", attachmentsText(r.bm), attachmentsText(r.ref));
  t.same(id + " catalog", catalogText(r.bm, ["Names", "AF", "Type", "MarkInfo", "Lang"]), catalogText(r.ref, ["Names", "AF", "Type", "MarkInfo", "Lang"]));
  return r;
}

probe("metadata.attachments.basic", "attachments: /EmbeddedFiles name tree, filespec (/F /UF /EF /Desc /AFRelationship), stream (/Subtype /Params /Size /ModDate), /AF", async (t) => {
  await att(t, "one, no pdfa", { attachments: [ATT] });
  await att(t, "one, no pdfa, with date", { metadata: META, attachments: [ATT] });
  await att(t, "own modificationDate", { metadata: META, attachments: [{ ...ATT, modificationDate: "2025-01-02T03:04:05" }] });
  await att(t, "minimal (name+data only)", { attachments: [{ name: "a.bin", data: new Uint8Array([0, 1, 2, 255]) }] });
  for (const rel of ["source", "data", "alternative", "supplement", "unspecified"]) await att(t, "relationship " + rel + " 3b", { pdfa: "3b", metadata: META, attachments: [{ ...ATT, relationship: rel }] });
  await att(t, "relationship default 3b", { pdfa: "3b", metadata: META, attachments: [{ name: "a.txt", data: "x", mimeType: "text/plain", description: "d" }] });
  await att(t, "several, name order (z before a)", { attachments: [{ ...ATT, name: "z.xml" }, { ...ATT, name: "a.xml" }, { ...ATT, name: "M.xml" }] });
  await att(t, "non-ASCII name", { attachments: [{ ...ATT, name: "rechnung-ü-日本.xml", description: "Beschreibung ü" }] });
  await att(t, "name with path and specials", { attachments: [{ ...ATT, name: "dir/sub\\file (1).xml" }] });
  await att(t, "empty data", { attachments: [{ ...ATT, data: "" }] });
  await att(t, "empty description / empty name", { attachments: [{ ...ATT, name: "", description: "" }] });
  await att(t, "pdf 2.0 (ua2): AF + AFRelationship by version", { tagged: "ua2", lang: "en", metadata: META, attachments: [ATT] });
  await att(t, "4f", { pdfa: "4f", metadata: META, attachments: [ATT] });
  await att(t, "4f without attachments: empty EmbeddedFiles tree", { pdfa: "4f", metadata: META });
  await att(t, "3a + ua1", { pdfa: "3a", tagged: "ua1", lang: "en", metadata: META, attachments: [ATT] });
  await att(t, "same bytes under two names", { attachments: [{ ...ATT, name: "one.xml" }, { ...ATT, name: "two.xml" }] });
});

probe("metadata.attachments.compression", "attachment stream filter: compressed when it helps? (text, incompressible bytes, tiny data)", async (t) => {
  const rnd = new Uint8Array(4096); let s = 12345; for (let i = 0; i < rnd.length; i++) { s = (s * 1103515245 + 12345) >>> 0; rnd[i] = s >>> 24; }
  for (const [name, data] of [["compressible text 8k", "abcdefgh".repeat(1024)], ["random 4k", rnd], ["tiny", "x"], ["png signature (already compressed type)", new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, ...rnd.subarray(0, 600)])]]) {
    const r = await t.both(HTML, { attachments: [{ name: "f.bin", data, mimeType: "application/octet-stream" }] });
    if (!t.same(name + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) continue;
    const f = (d) => { const a = attachmentsText(d).files[0]; return { filter: a.stream.Filter || null, size: a.stream.Params, sub: a.stream.Subtype }; };
    t.same(name + " filter / params", f(r.bm), f(r.ref));
    t.same(name + " encoded length", attachmentsText(r.bm).files[0].rawLen, attachmentsText(r.ref).files[0].rawLen);
  }
});

probe("metadata.attachments.errors", "attachment errors: duplicate name, invalid mime type, invalid date, per-level validation (exact text)", async (t) => {
  const cases = [
    ["duplicate name", { attachments: [ATT, ATT] }],
    ["duplicate name, different data", { attachments: [ATT, { ...ATT, data: "other" }] }],
    ["names differing by case", { attachments: [ATT, { ...ATT, name: "FACTUR-X.XML" }] }],
    ["mime without slash", { attachments: [{ ...ATT, mimeType: "xml" }] }],
    ["mime with parameters", { attachments: [{ ...ATT, mimeType: "text/plain; charset=utf-8" }] }],
    ["mime empty", { attachments: [{ ...ATT, mimeType: "" }] }],
    ["mime with three parts", { attachments: [{ ...ATT, mimeType: "a/b/c" }] }],
    ["mime with star", { attachments: [{ ...ATT, mimeType: "text/*" }] }],
    ["mime with underscore", { attachments: [{ ...ATT, mimeType: "application/x_y" }] }],
    ["mime uppercase + dot + plus (valid)", { attachments: [{ ...ATT, mimeType: "Application/vnd.ms-excel+XML" }] }],
    ["invalid modificationDate", { attachments: [{ ...ATT, modificationDate: "yesterday" }] }],
    ["unknown relationship", { attachments: [{ ...ATT, relationship: "other" }] }],
    ["relationship capitalised", { attachments: [{ ...ATT, relationship: "Alternative" }] }],
    ["missing name", { attachments: [{ data: "x" }] }],
    ["missing data", { attachments: [{ name: "a" }] }],
    ["data as number array", { attachments: [{ name: "a", data: [1, 2, 3] }] }],
    ["data as ArrayBuffer", { attachments: [{ name: "a", data: new Uint8Array([1, 2, 3]).buffer }] }],
    ["attachments not an array", { attachments: ATT }],
    ["invalid mime AND duplicate (which error first)", { attachments: [ATT, { ...ATT, mimeType: "bad" }] }],
    ["invalid mime AND invalid xmp schema (which error first)", { metadata: { xmp: [{ name: "N", prefix: "", namespace: "urn:x", properties: [] }] }, attachments: [{ ...ATT, mimeType: "bad" }] }],
  ];
  for (const [name, o] of cases) {
    const r = await t.both(HTML, o);
    t.same(name + " outcome", outcome(r.bm), outcome(r.ref));
    if (r.ref) t.note(`${name} => takumi: ${outcome(r.ref)}`);
  }
  // per level: full attachment / no mime / no description / no date at all
  const full = ATT; const noMime = { name: "a.xml", data: "x", description: "d" }; const noDesc = { name: "a.xml", data: "x", mimeType: "text/xml" }; const bare = { name: "a.xml", data: "x" };
  for (const pdfa of [undefined, "2a", "2b", "2u", "3a", "3b", "3u", "4", "4f"]) for (const tagged of [true, "ua1", "ua2"]) {
    if ((tagged === "ua2" && pdfa && !pdfa.startsWith("4")) || (tagged === "ua1" && pdfa && pdfa.startsWith("4"))) continue;
    for (const [an, a, md] of [["full", full, META], ["no mime", noMime, META], ["no description", noDesc, META], ["bare", bare, META], ["full, no document date", full, { title: "T" }], ["full, own date, no document date", { ...full, modificationDate: "2026-01-01" }, { title: "T" }], ["two bare", [bare, { ...bare, name: "b.xml" }], META]]) {
      const r = await t.both(`<h1>T</h1>`, { pdfa, tagged, lang: "en", metadata: md, attachments: Array.isArray(a) ? a : [a] });
      t.same(`pdfa=${pdfa ?? "none"} tagged=${tagged} ${an}`, outcome(r.bm), outcome(r.ref));
    }
  }
});
