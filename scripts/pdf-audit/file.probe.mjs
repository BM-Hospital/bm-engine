// The PDF file layer: header, versions, cross-reference, object streams, stream filters, object order, trailer,
// features krilla has but takumi does not reach (page labels, boxes, ...), and the error prefix.
import { probe, Name, fmt } from "./lib.mjs";
import { outcome, outcomes, fileShape, fileId, catalogText, deep, sameText, META, PNG1 } from "./filelayer.util.mjs";

const RICH = `<html lang="en"><body><h1 id="top">Title</h1><p>Hello <a href="https://example.com/">link</a> and <a href="#top">top</a></p>
<img alt="dot" width="20" height="20" src="${PNG1}"><div style="width:60px;height:20px;background:linear-gradient(90deg,red,blue);opacity:.5"></div>
<ul><li>one</li><li>two</li></ul><table><thead><tr><th>h</th></tr></thead><tbody><tr><td>c</td></tr></tbody></table></body></html>`;

const OPTS = [
  ["default", {}],
  ["untagged", { tagged: false }],
  ["outline", { outline: true }],
  ["metadata", { lang: "en", metadata: { ...META, authors: ["A"] } }],
  ["pdfa-2b", { pdfa: "2b", metadata: META }],
  ["pdfa-3a", { pdfa: "3a", lang: "en", metadata: META }],
  ["ua1", { tagged: "ua1", lang: "en", metadata: META }],
  ["pdfa-4", { pdfa: "4", metadata: META }],
  ["pdfa-4f-ua2", { pdfa: "4f", tagged: "ua2", lang: "en", metadata: META }],
  ["ua2", { tagged: "ua2", lang: "en", metadata: META }],
  ["paged A4", { size: "A4", outline: true }],
];

probe("file.shape", "header version + binary marker, xref stream vs table, object streams, filters per stream kind, trailer keys, object count", async (t) => {
  for (const [name, o] of OPTS) {
    const r = await t.both(RICH, o);
    if (!t.same(name + " outcome", ...outcomes(r.bm, r.ref)) || !r.ref || r.bm.error) continue;
    sameText(t, name + " file shape", fileShape(r.bm), fileShape(r.ref));
    if (name === "default") t.note("takumi shape: " + JSON.stringify(fileShape(r.ref)));
  }
});

/** The sequence of objects in file order as kind labels (the order krilla's chunk container writes them in). */
function objectOrder(d) {
  const label = (o) => {
    const x = o.dict;
    if (Array.isArray(x)) return "array";
    if (!x || typeof x !== "object") return typeof x;
    const ty = x.Type instanceof Name ? x.Type.s : ""; const st = x.Subtype instanceof Name ? x.Subtype.s : "";
    if (ty || st) return (ty || "") + (st ? ":" + st : "") + (o.raw ? "*" : "");
    if (x.S instanceof Name && x.P) return "StructElem?" + x.S.s;
    if (x.FunctionType !== undefined) return "Function" + x.FunctionType;
    if (x.ShadingType !== undefined) return "Shading" + x.ShadingType;
    if (x.Title && x.Parent) return "OutlineItem";
    return (o.raw ? "stream{" : "dict{") + Object.keys(x).filter((k) => k !== "Length").sort().join(",") + "}";
  };
  return [...d.pdf.objs.values()].sort((a, b) => a.n - b.n).map((o) => (o.inObjStm ? "~" : "") + label(o));
}

probe("file.object-order", "object numbering / order of object kinds through the file (krilla chunk order), objects inside object streams", async (t) => {
  for (const [name, o] of OPTS) {
    const r = await t.both(RICH, o);
    if (!r.ref || r.bm.error || r.ref.error) { t.same(name + " outcome", ...outcomes(r.bm, r.ref)); continue; }
    sameText(t, name + " object order", objectOrder(r.bm).join(" | "), objectOrder(r.ref).join(" | "));
  }
});

probe("file.bytes.identical-outside-fonts", "byte comparison of the whole file after cutting font programs, ids and the producer", async (t) => {
  // A document without text has no font: the file should be byte-identical up to /Producer and the two ids.
  for (const [name, html, o] of [
    ["boxes only", `<div style="width:100px;height:50px;background:#f00;border:2px solid #00f"></div>`, { tagged: false }],
    ["boxes only, tagged", `<div style="width:100px;height:50px;background:#f00;border:2px solid #00f"></div>`, {}],
    ["boxes only, pdf/a-2b", `<div style="width:100px;height:50px;background:#f00"></div>`, { pdfa: "2b", metadata: META }],
    ["boxes only, pdf/a-4", `<div style="width:100px;height:50px;background:#f00"></div>`, { pdfa: "4", metadata: META }],
    ["empty document", ``, {}],
    ["empty document A4", ``, { size: "A4" }],
  ]) {
    const r = await t.both(html, o);
    if (!t.same(name + " outcome", ...outcomes(r.bm, r.ref)) || !r.ref || r.bm.error) continue;
    // every object in file order: number, dictionary as written, and the DECODED stream data (the deflate implementations
    // differ, so compressed bytes are not comparable); ids, the producer and stream lengths are normalised
    const prod = (s) => s.replace(/\/Producer ?\([^)]*\)/, "/Producer(P)");
    const norm = (d) => {
      const ids = fileId(d) || [];
      let out = d.pdf.source.slice(0, d.pdf.source.indexOf("1 0 obj"));
      for (const o of [...d.pdf.objs.values()].sort((x, y) => x.n - y.n)) {
        if (o.dict && o.dict.Type instanceof Name && o.dict.Type.s === "XRef") { out += "XREF"; continue; }
        let body = prod(fmt(o.dict).replace(/\/Length \d+/, "/Length N"));
        let data = o.data ? o.data.toString("latin1").replace(/<pdf:Producer>[^<]*/g, "<pdf:Producer>P") : "";
        for (const id of ids) { data = data.split(id).join("ID"); body = body.split(id).join("ID"); }
        out += "\n" + o.n + (o.inObjStm ? "~" : "") + " obj " + body + (o.raw ? " stream[" + data + "]" : "");
      }
      return out;
    };
    sameText(t, name + " objects (decoded streams; producer, ids, lengths normalised)", norm(r.bm), norm(r.ref));
    const direct = (d) => [...d.pdf.objs.values()].filter((o) => !o.raw && !o.inObjStm).map((o) => { const m = new RegExp("(?:^|\n)" + o.n + " 0 obj\n([^]*?)\nendobj").exec(d.pdf.source); return m ? prod(m[1]) : "? object " + o.n + " not found"; }).join("\n");
    t.ok(!direct(r.bm).includes("not found"), name + ": every bm object located in the file");
    sameText(t, name + " raw bytes of every non-stream object (token spacing, number formatting)", direct(r.bm), direct(r.ref));
  }
});
function xmpProducer(d) { const o = d.pdf.obj(d.catalog.Metadata); return o ? (o.data.toString("utf8").match(/<pdf:Producer>([^<]*)/) || [])[1] || "" : ""; }

probe("file.xref", "cross-reference stream dictionary (/W /Index /Size /Root /Info /ID, predictor) and startxref", async (t) => {
  for (const [name, o] of [["1.7", {}], ["2.0", { tagged: "ua2", lang: "en", metadata: META }], ["a-4 (no Info)", { pdfa: "4", metadata: META }]]) {
    const r = await t.both(RICH, o);
    if (!r.ref || r.bm.error || r.ref.error) { t.same(name + " outcome", ...outcomes(r.bm, r.ref)); continue; }
    const x = (d) => { const tr = d.pdf.trailer; return Object.fromEntries(Object.entries(tr).map(([k, v]) => [k, k === "ID" ? "ids" : k === "Length" || k === "Size" ? "n" : k === "Index" ? "[" + v.length + "]" : deep(d, v, 0, 0)])); };
    t.same(name + " xref stream dictionary", x(r.bm), x(r.ref));
    const tail = (d) => d.pdf.source.slice(d.pdf.source.lastIndexOf("endstream")).replace(/\d+/g, "N").replace(/\r/g, "");
    t.same(name + " file tail", tail(r.bm), tail(r.ref));
    t.same(name + " Size == object count + 1", r.bm.pdf.trailer.Size === Math.max(...r.bm.pdf.objs.keys()) + 1, r.ref.pdf.trailer.Size === Math.max(...r.ref.pdf.objs.keys()) + 1);
  }
});

probe("file.objstm", "object streams: which objects go in (struct elements only), /N /First, how many per stream", async (t) => {
  const big = `<h1>T</h1>` + Array.from({ length: 450 }, (_, i) => `<p>para ${i} <b>b</b> <i>i</i></p>`).join("");
  for (const [name, html, o] of [["small tagged", RICH, {}], ["450 paragraphs (several object streams?)", big, { size: "A4" }], ["untagged", RICH, { tagged: false }]]) {
    const r = await t.both(html, o);
    if (!r.ref || r.bm.error || r.ref.error) { t.same(name + " outcome", ...outcomes(r.bm, r.ref)); continue; }
    const s = (d) => ({ streams: d.typed("ObjStm").map((x) => ({ n: x.dict.N, filter: String(x.dict.Filter), extends: x.dict.Extends !== undefined })), inside: [...new Set([...d.pdf.objs.values()].filter((x) => x.inObjStm).map((x) => (x.dict && x.dict.Type instanceof Name ? x.dict.Type.s : x.dict && x.dict.S ? "StructElem" : "other")))].sort(), count: [...d.pdf.objs.values()].filter((x) => x.inObjStm).length });
    sameText(t, name + " object streams", s(r.bm), s(r.ref));
  }
});

probe("file.streams.filters", "which streams are Flate'd: content, XMP (never), ToUnicode, font file, ICC, images, attachments; /Length direct", async (t) => {
  const r = await t.both(RICH, { pdfa: "3b", metadata: META, attachments: [{ name: "a.txt", data: "hello ".repeat(100), mimeType: "text/plain", description: "d" }] });
  if (!t.same("outcome", ...outcomes(r.bm, r.ref)) || !r.ref || r.bm.error) return;
  sameText(t, "stream kinds and filters", fileShape(r.bm).streamKinds, fileShape(r.ref).streamKinds);
  const direct = (d) => [...d.pdf.objs.values()].filter((o) => o.raw).every((o) => typeof o.dict.Length === "number");
  t.same("every /Length is a direct integer", direct(r.bm), direct(r.ref));
  const zl = (d) => [...new Set([...d.pdf.objs.values()].filter((o) => o.raw && String(o.dict.Filter) === "/FlateDecode").map((o) => o.raw.toString("hex", 0, 2)))].sort();
  t.same("zlib headers (compression level marker)", zl(r.bm), zl(r.ref));
  // a tiny content stream: compressed even when that makes it bigger?
  const s = await t.both(`<div style="width:1px;height:1px;background:red"></div>`, { tagged: false });
  if (s.ref && !s.bm.error) t.same("tiny content stream filter", s.bm.pdf.obj(s.bm.pdf.pages[0].dict.Contents).dict.Filter + "", s.ref.pdf.obj(s.ref.pdf.pages[0].dict.Contents).dict.Filter + "");
});

probe("file.streams.sizes", "decoded content stream equivalence (compressed sizes are implementation-dependent)", async (t) => {
  const r = await t.both(`<p>${"The quick brown fox jumps over the lazy dog. ".repeat(60)}</p>`, { size: "A4" });
  if (!r.ref || r.bm.error || r.ref.error) { t.same("outcome", ...outcomes(r.bm, r.ref)); return; }
  const c = (d) => { const o = d.pdf.obj(d.pdf.pages[0].dict.Contents); return { raw: o.raw.length, data: o.data.length }; };
  t.same("content stream decoded length", c(r.bm).data, c(r.ref).data);
  t.note(`compressed length is not a parity criterion: bm ${JSON.stringify(c(r.bm))} | takumi ${JSON.stringify(c(r.ref))}; file size bm ${r.bm.bytes.length} | takumi ${r.ref.bytes.length}`);
});

probe("file.catalog.unreachable", "krilla features takumi does not reach: /PageLabels, /PageMode, /PageLayout, /OpenAction, /AcroForm, /OCProperties, boxes, /Rotate, /UserUnit, /Thumb, encryption, linearization", async (t) => {
  for (const [name, html, o] of [["single", RICH, {}], ["paged + ranges", `<p>a</p><p style="break-before:page">b</p><p style="break-before:page">c</p>`, { size: "A4", pageRanges: [{ from: 2, to: 3 }], outline: true }], ["landscape", `<p>a</p>`, { size: "A4", landscape: true }]]) {
    const r = await t.both(html, o);
    if (!t.same(name + " outcome", ...outcomes(r.bm, r.ref)) || !r.ref || r.bm.error) continue;
    t.same(name + " catalog keys", Object.keys(r.bm.catalog).sort(), Object.keys(r.ref.catalog).sort());
    const pk = (d) => d.pdf.pages.map((p) => Object.keys(p.dict).sort().join(","));
    t.same(name + " page keys", pk(r.bm), pk(r.ref));
    const absent = (d) => ["PageLabels", "PageMode", "PageLayout", "OpenAction", "AcroForm", "OCProperties", "Perms", "Collection"].filter((k) => d.catalog[k] !== undefined);
    t.same(name + " absent catalog entries", absent(r.bm), absent(r.ref));
    t.same(name + " pages tree", deep(r.bm, r.bm.catalog.Pages, 0, 1).replace(/\[(R ?)+\]/, (m) => "[" + m.split("R").length + "]"), deep(r.ref, r.ref.catalog.Pages, 0, 1).replace(/\[(R ?)+\]/, (m) => "[" + m.split("R").length + "]"));
  }
});

probe("file.version.selection", "what selects the PDF version: only pdfa / tagged (1.7 default, 2.0 for A-4 / UA-2); no `version` option", async (t) => {
  for (const o of [{}, { version: "1.4" }, { pdfVersion: "2.0" }, { pdfa: "2b", metadata: META }, { pdfa: "4", metadata: META }, { tagged: "ua2", lang: "en", metadata: META }, { tagged: "ua1", lang: "en", metadata: META }]) {
    const r = await t.both(`<h1>T</h1>`, o);
    if (!t.same(JSON.stringify(o) + " outcome", ...outcomes(r.bm, r.ref)) || !r.ref || r.bm.error) continue;
    t.same(JSON.stringify(o) + " header", r.bm.pdf.source.slice(0, 8), r.ref.pdf.source.slice(0, 8));
    t.same(JSON.stringify(o) + " catalog /Version", String(r.bm.catalog.Version), String(r.ref.catalog.Version));
  }
});

probe("file.pdf20.differences", "PDF 2.0 output (UA-2 / A-4): no /ProcSet, no Info text fields, /Namespaces, MarkInfo without /Suspects, AF", async (t) => {
  for (const [name, o] of [["1.7", {}], ["ua2", { tagged: "ua2", lang: "en", metadata: META }], ["a-4", { pdfa: "4", metadata: META }]]) {
    const r = await t.both(RICH, o);
    if (!r.ref || r.bm.error || r.ref.error) { t.same(name + " outcome", ...outcomes(r.bm, r.ref)); continue; }
    const res = (d) => deep(d, d.pdf.pages[0].dict.Resources, 0, 1).replace(/\/(\w+) R/g, "/$1 R");
    sameText(t, name + " page resources", res(r.bm), res(r.ref));
    sameText(t, name + " catalog", catalogText(r.bm), catalogText(r.ref));
    sameText(t, name + " structure roots", r.bm.structure.roots, r.ref.structure.roots);
  }
});

probe("file.error-prefix", "error message prefix: bm-render prepends `bm-render: ` to every message; takumi-pdf throws the bare PdfError text", async (t) => {
  const r = await t.both(`<p>x</p>`, { pdfa: "2b", metadata: { title: "T" } });
  t.ok(!!r.bm.error, "bm fails without creationDate under PDF/A-2b");
  if (r.ref) {
    t.note(`bm: ${JSON.stringify(r.bm.error)} (${r.bm.errorName}) | takumi: ${JSON.stringify(r.ref.error)} (${r.ref.errorName})`);
    t.same("error text without engine-specific prefix", String(r.bm.error).replace(/^bm-render: /, ""), r.ref.error);
    t.same("error class name", r.bm.errorName, r.ref.errorName);
  }
});
