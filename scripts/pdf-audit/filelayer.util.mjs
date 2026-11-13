// Helpers shared by the file-layer audit probes (conformance / tagging / links / metadata / fonts / file).
// Not a probe file (run.mjs only imports *.probe.mjs).
import { Name, Ref, fmt, pdfText, errNorm, isSerdeMessage } from "./lib.mjs";

/**
 * The error message, or "ok". bm-engine prefixes every message with "bm-engine: " (js/engine.mjs); the prefix is removed here so
 * that the rest of the text is compared (the prefix itself is checked once, by file.error-prefix).
 */
export const outcome = (r) => (r ? (r.error ? "ERR: " + String(r.error).replace(/^bm-engine: /, "") : "ok") : null);

/**
 * The outcomes of both engines, `[bm, takumi]`, for `t.same(label, ...outcomes(bm, ref))`. As lib.mjs `sameError`
 * does for the API probes: takumi-pdf's wasm glue prefix `Error: ` is dropped, and when takumi's message is one serde
 * (or the wasm-bindgen glue) generates for a value of the wrong shape, an implementation detail of the Rust options
 * types rather than takumi-pdf's API, bm only has to reject too (both become "ERR: <type error>").
 */
export function outcomes(bm, ref) {
  const a = outcome(bm);
  const b = ref ? (ref.error ? "ERR: " + errNorm(ref.error) : "ok") : null;
  if (a && b && a.startsWith("ERR: ") && b.startsWith("ERR: ") && isSerdeMessage(b)) return ["ERR: <type error>", "ERR: <type error>"];
  return [a, b];
}

/** XMP packet text of a described render (the catalog /Metadata stream), or null. */
export function xmp(d) {
  if (!d || d.error) return null;
  const o = d.pdf.obj(d.catalog.Metadata);
  return o && o.data ? o.data.toString("utf8") : null;
}

/** XMP with the ids (hashes of the bytes) and the producer replaced, for comparison. */
export function xmpNorm(d, { producer = true } = {}) {
  let s = xmp(d);
  if (s == null) return null;
  s = s.replace(/(<xmpMM:(?:InstanceID|DocumentID)>)[^<]*/g, "$1ID").replace(/(<stEvt:instanceID>)[^<]*/g, "$1ID");
  if (producer) s = s.replace(/(<pdf:Producer>)[^<]*/g, "$1PRODUCER");
  return s;
}

/** Info dictionary with the producer replaced. */
export const infoNorm = (d) => (!d || d.error ? null : d.info.Producer !== undefined ? { ...d.info, Producer: "PRODUCER" } : d.info);

/** Catalog entries as canonical text (small values resolved, big trees as R). */
export function catalogText(d, keys) {
  if (!d || d.error) return null;
  const out = {};
  const shallow = new Set(["Pages", "StructTreeRoot", "Metadata", "Outlines"]);
  for (const k of keys || Object.keys(d.catalog).sort()) if (d.catalog[k] !== undefined) out[k] = deep(d, d.catalog[k], 0, shallow.has(k) ? 0 : 3);
  return out;
}

/** Canonical text of a value with references resolved `depth` levels deep. */
export function deep(d, v, level = 0, depth = 3) {
  if (v instanceof Ref) {
    if (level >= depth) return "R";
    const o = d.pdf.objs.get(v.n);
    if (!o) return "R(missing)";
    return (o.raw ? "stream" : "") + deep(d, o.dict, level + 1, depth);
  }
  if (v instanceof Name) return "/" + v.s;
  if (Array.isArray(v)) return "[" + v.map((x) => deep(d, x, level, depth)).join(" ") + "]";
  if (v && v.hex !== undefined) return "<" + v.hex + ">";
  if (v && v.str !== undefined) return "(" + v.str + ")";
  if (v && typeof v === "object") return "<<" + Object.keys(v).map((k) => "/" + k + " " + (k === "Parent" || k === "P" || k === "Pg" ? "R" : k === "Length" ? "N" : deep(d, v[k], level, depth))).join(" ") + ">>";
  return fmt(v);
}

/** Summary of the file structure: header, binary marker, xref kind, object streams, filters per stream kind. */
export function fileShape(d) {
  if (!d || d.error) return null;
  const s = d.pdf.source;
  const nl = s.indexOf("\n");
  const second = s.slice(nl + 1, s.indexOf("\n", nl + 1));
  const streams = [...d.pdf.objs.values()].filter((o) => o.raw);
  const kind = (o) => {
    const t = o.dict.Type instanceof Name ? o.dict.Type.s : ""; const st = o.dict.Subtype instanceof Name ? o.dict.Subtype.s : "";
    if (t || st) return (t || "-") + "/" + (st || "-");
    if (o.dict.N !== undefined && o.dict.Range) return "icc";
    if (o.dict.Length1 !== undefined) return "fontfile";
    return "content-or-other";
  };
  const filt = (o) => (o.dict.Filter instanceof Name ? o.dict.Filter.s : Array.isArray(o.dict.Filter) ? o.dict.Filter.map((f) => f.s).join("+") : "none");
  const kinds = {};
  for (const o of streams) { const k = kind(o) + ":" + filt(o); kinds[k] = (kinds[k] || 0) + 1; }
  return {
    header: s.slice(0, nl),
    binaryMarker: Buffer.from(second, "latin1").toString("hex"),
    xrefStream: /\/Type\s*\/XRef/.test(s),
    xrefTable: /\nxref\r?\n/.test(s),
    trailerKeyword: /\ntrailer/.test(s),
    objStm: d.typed("ObjStm").length,
    linearized: /\/Linearized/.test(s.slice(0, 2048)),
    encrypt: d.pdf.trailer.Encrypt !== undefined,
    streamKinds: Object.fromEntries(Object.entries(kinds).sort()),
    trailerKeys: Object.keys(d.pdf.trailer).filter((k) => !["Length", "W", "Index", "Filter", "DecodeParms"].includes(k)).sort(),
    objectCount: d.pdf.objs.size,
    eof: s.slice(-6).replace(/\r/g, ""),
  };
}

/** The two /ID strings. */
export function fileId(d) {
  if (!d || d.error) return null;
  const id = d.pdf.trailer.ID;
  return Array.isArray(id) ? id.map((x) => pdfText(x)) : null;
}

/** Font dictionaries (Type0 + descendant + descriptor, Type3) in canonical, object-number-free form. */
export function fontShape(d, { tag = true } = {}) {
  if (!d || d.error) return null;
  const out = [];
  const normTag = (s) => (typeof s === "string" && tag ? s.replace(/^[A-Z]{6}\+/, "TAGTAG+") : s);
  for (const o of d.typed("Font")) {
    const f = o.dict; const sub = f.Subtype instanceof Name ? f.Subtype.s : "";
    if (sub === "Type0") {
      const dl = d.pdf.resolve(f.DescendantFonts);
      const desc = d.pdf.resolve(dl[0]);
      const fd = d.pdf.resolve(desc.FontDescriptor) || {};
      const ff = ["FontFile", "FontFile2", "FontFile3"].find((k) => fd[k] !== undefined);
      const ffo = ff ? d.pdf.obj(fd[ff]) : null;
      const tu = f.ToUnicode ? d.pdf.obj(f.ToUnicode) : null;
      out.push({
        subtype: sub, baseFont: normTag(f.BaseFont && f.BaseFont.s), encoding: fmt(f.Encoding),
        cidSubtype: desc.Subtype && desc.Subtype.s, cidBaseFont: normTag(desc.BaseFont && desc.BaseFont.s),
        cidSystemInfo: fmt(d.pdf.resolve(desc.CIDSystemInfo)), cidToGid: fmt(desc.CIDToGIDMap), dw: desc.DW, w: fmt(d.pdf.resolve(desc.W)),
        descriptor: Object.fromEntries(Object.entries(fd).filter(([k]) => !/^FontFile|^CIDSet$/.test(k)).map(([k, v]) => [k, k === "FontName" ? normTag(v.s) : fmt(v)])),
        cidSet: fd.CIDSet !== undefined,
        fontFile: ff, fontFileSubtype: ffo && ffo.dict.Subtype ? ffo.dict.Subtype.s : null, fontFileKeys: ffo ? Object.keys(ffo.dict).sort().join(",") : null,
        fontProgram: ffo ? sfntShape(ffo.data) : null,
        toUnicode: tu ? cmapPairs(tu.data.toString("latin1")) : null,
        toUnicodeText: tu ? tu.data.toString("latin1").replace(/[A-Z]{6}\+/g, "TAGTAG+") : null,
        rawBaseFont: f.BaseFont && f.BaseFont.s,
      });
    } else if (sub === "Type3") {
      const tu = f.ToUnicode ? d.pdf.obj(f.ToUnicode) : null;
      const cp = d.pdf.resolve(f.CharProcs) || {};
      out.push({
        subtype: sub, name: f.Name ? normTag(f.Name.s) : null, fontBBox: fmt(f.FontBBox), fontMatrix: fmt(f.FontMatrix), firstChar: f.FirstChar, lastChar: f.LastChar,
        widths: fmt(d.pdf.resolve(f.Widths)), encoding: deep(d, f.Encoding, 0, 2),
        descriptor: f.FontDescriptor ? Object.fromEntries(Object.entries(d.pdf.resolve(f.FontDescriptor)).map(([k, v]) => [k, k === "FontName" ? normTag(v.s) : fmt(v)])) : null,
        charProcs: Object.keys(cp).sort().map((k) => { const s = d.pdf.obj(cp[k]); return k + ": " + (s && s.data ? s.data.toString("latin1").replace(/\s+/g, " ").trim().slice(0, 3000) : "?"); }),
        resources: f.Resources ? Object.keys(d.pdf.resolve(f.Resources) || {}).sort().join(",") : null,
        toUnicode: tu ? cmapPairs(tu.data.toString("latin1")) : null,
      });
    } else if (sub !== "CIDFontType2" && sub !== "CIDFontType0") out.push({ subtype: sub, dict: fmt(f) });
  }
  return out.sort((a, b) => JSON.stringify([a.subtype, a.baseFont, a.w, a.widths]).localeCompare(JSON.stringify([b.subtype, b.baseFont, b.w, b.widths])));
}

/** bfchar / bfrange pairs of a ToUnicode CMap: "cid>hex" list. */
export function cmapPairs(text) {
  const out = [];
  for (const m of text.matchAll(/beginbfchar([\s\S]*?)endbfchar/g)) for (const p of m[1].matchAll(/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>/g)) out.push(p[1].toUpperCase() + ">" + p[2].toUpperCase());
  for (const m of text.matchAll(/beginbfrange([\s\S]*?)endbfrange/g)) for (const p of m[1].matchAll(/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<[0-9A-Fa-f]*>|\[[^\]]*\])/g)) out.push("range " + p[1].toUpperCase() + ".." + p[2].toUpperCase() + ">" + p[3].toUpperCase().replace(/\s+/g, ""));
  return out;
}

/** Shape of an embedded font program: sfnt table tags + numGlyphs, or a bare CFF header. */
export function sfntShape(buf) {
  if (!buf || buf.length < 12) return null;
  const tag = buf.toString("latin1", 0, 4);
  if (tag === "\x00\x01\x00\x00" || tag === "OTTO" || tag === "true") {
    const n = buf.readUInt16BE(4); const tables = {};
    for (let i = 0; i < n; i++) { const o = 12 + i * 16; tables[buf.toString("latin1", o, o + 4)] = { off: buf.readUInt32BE(o + 8), len: buf.readUInt32BE(o + 12) }; }
    const maxp = tables.maxp ? buf.readUInt16BE(tables.maxp.off + 4) : null;
    const os2 = tables["OS/2"] ? buf.readUInt16BE(tables["OS/2"].off + 8) : null;
    return { container: tag === "OTTO" ? "OTTO" : "sfnt", tables: Object.keys(tables).sort().join(" "), numGlyphs: maxp, fsType: os2 };
  }
  if (buf[0] === 1 && buf[1] === 0) return { container: "bare CFF", hdrSize: buf[2] };
  return { container: "unknown " + buf.toString("hex", 0, 4) };
}

/** Link (and other) annotations per page in canonical text (rect rounded to 2 decimals). */
export function annots(d, { round = 100 } = {}) {
  if (!d || d.error) return null;
  return d.pdf.pages.map((p) => {
    const list = d.pdf.resolve(p.dict.Annots) || [];
    return list.map((r) => {
      const a = d.pdf.resolve(r); const o = {};
      for (const [k, v] of Object.entries(a)) {
        if (k === "P") { o[k] = "R"; continue; }
        if (k === "StructParent") { o[k] = "n"; continue; }
        if (k === "Rect" || k === "QuadPoints") { o[k] = d.pdf.resolve(v).map((x) => Math.round(x * round) / round).join(" "); continue; }
        if (k === "Dest") { o[k] = destText(d, v); continue; }
        if (k === "Contents") { o[k] = pdfText(v); continue; }
        o[k] = deep(d, v, 0, 2);
      }
      return o;
    });
  });
}

export function destText(d, v) {
  const x = d.pdf.resolve(v);
  if (Array.isArray(x)) {
    const pageIndex = x[0] instanceof Ref ? d.pdf.pages.findIndex((p) => p.ref.n === x[0].n) : -1;
    const first = x[0] instanceof Ref ? (pageIndex >= 0 ? "page" + pageIndex : "struct:" + structLabel(d, x[0])) : fmt(x[0]);
    return "[" + first + " " + x.slice(1).map((y) => (typeof y === "number" ? String(Math.round(y * 100) / 100) : fmt(y))).join(" ") + "]";
  }
  if (x && x.D) return "<<D " + destText(d, x.D) + (x.SD ? " SD " + destText(d, x.SD) : "") + ">>";
  return fmt(x);
}
function structLabel(d, ref) { const e = d.pdf.resolve(ref); return e && e.S ? e.S.s + (e.ID ? "#" + pdfText(e.ID) : "") : "?"; }

/** Outline tree as nested text. */
export function outlineText(d) {
  if (!d || d.error) return null;
  if (!d.catalog.Outlines) return "(none)";
  const root = d.pdf.resolve(d.catalog.Outlines);
  const walk = (ref, depth) => {
    const out = [];
    let cur = ref;
    while (cur) {
      const it = d.pdf.resolve(cur);
      const extra = Object.keys(it).filter((k) => !["Title", "Parent", "Prev", "Next", "First", "Last", "Count", "Dest", "A", "SE"].includes(k)).sort().map((k) => k + "=" + fmt(it[k])).join(",");
      out.push("  ".repeat(depth) + JSON.stringify(pdfText(it.Title)) + " count=" + (it.Count ?? "-") + " dest=" + (it.Dest ? destText(d, it.Dest) : it.A ? deep(d, it.A, 0, 1) : "-") + (it.SE ? " SE=" + structLabel(d, it.SE) : "") + (extra ? " " + extra : ""));
      if (it.First) out.push(...walk(it.First, depth + 1));
      cur = it.Next;
    }
    return out;
  };
  return ["root count=" + (root.Count ?? "-") + " keys=" + Object.keys(root).sort().join(","), ...(root.First ? walk(root.First, 1) : [])];
}

/** Embedded files: filespec dictionaries + stream dictionaries + data, canonical. */
export function attachmentsText(d) {
  if (!d || d.error) return null;
  const names = d.catalog.Names ? d.pdf.resolve(d.catalog.Names) : null;
  const ef = names && names.EmbeddedFiles ? d.pdf.resolve(names.EmbeddedFiles) : null;
  const out = { hasNames: !!names, namesKeys: names ? Object.keys(names).sort().join(",") : null, efKeys: ef ? Object.keys(ef).sort().join(",") : null, af: d.catalog.AF ? d.pdf.resolve(d.catalog.AF).length : null, files: [] };
  const arr = ef && ef.Names ? d.pdf.resolve(ef.Names) : [];
  for (let i = 0; i + 1 < arr.length; i += 2) {
    const spec = d.pdf.resolve(arr[i + 1]);
    const so = spec.EF ? d.pdf.obj(d.pdf.resolve(spec.EF).F) : null;
    out.files.push({
      key: pdfText(arr[i]),
      spec: Object.fromEntries(Object.entries(spec).map(([k, v]) => [k, k === "EF" ? Object.keys(d.pdf.resolve(v)).join(",") : k === "F" || k === "UF" || k === "Desc" ? pdfText(v) : fmt(v)])),
      stream: so ? Object.fromEntries(Object.entries(so.dict).map(([k, v]) => [k, k === "Length" ? "N" : k === "Params" ? deep(d, v, 0, 1) : fmt(v)])) : null,
      data: so ? so.data.toString("latin1").slice(0, 200) : null,
      rawLen: so ? so.raw.length : null,
    });
  }
  return out;
}

export const DATE = "2026-08-06T01:02:03";
export const META = { title: "Audit document", creationDate: DATE };
/** A valid 2x2 RGB PNG. */
export const PNG1 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP4z8DAAMIM////ZwAAHu8E/KPItPcAAAAASUVORK5CYII=";

/**
 * `t.same` for long texts (or JSON-able values): on a difference the failure shows the text around the first differing
 * character instead of the first 300 characters (lib.mjs's `t.same` truncates both sides at 300).
 */
export function sameText(t, what, a, b) {
  if (!t.hasRef) return t.same(what, a, b);
  const x = typeof a === "string" ? a : JSON.stringify(a); const y = typeof b === "string" ? b : JSON.stringify(b);
  if (x === y) return t.ok(true, what);
  let i = 0; const n = Math.min((x || "").length, (y || "").length);
  while (i < n && x[i] === y[i]) i++;
  const from = Math.max(0, i - 60);
  return t.ok(false, `${what}: first difference at ${i}: bm …${JSON.stringify((x || "").slice(from, i + 160))} vs takumi …${JSON.stringify((y || "").slice(from, i + 160))}`);
}

/**
 * Compares two canonical texts whose decimal numbers may differ by `tol` (link rectangles follow glyph advances, which
 * differ in the 5th significant digit between the two shapers): the texts must be equal after replacing every number by
 * `#`, and the numbers pairwise within `tol`.
 */
export function sameWithin(t, what, a, b, tol = 0.02) {
  if (!t.hasRef) return t.same(what, a, b);
  const x = typeof a === "string" ? a : JSON.stringify(a); const y = typeof b === "string" ? b : JSON.stringify(b);
  const num = /-?\d+\.\d+|(?<![\w.#-])-?\d+(?![\w.])/g;
  const nx = (x || "").match(num) || []; const ny = (y || "").match(num) || [];
  if ((x || "").replace(num, "#") !== (y || "").replace(num, "#") || nx.length !== ny.length) return sameText(t, what, x, y);
  const bad = nx.findIndex((v, i) => Math.abs(Number(v) - Number(ny[i])) > tol);
  if (bad < 0) return t.ok(true, what);
  return t.ok(false, `${what}: number ${bad} differs by more than ${tol}: bm ${nx[bad]} vs takumi ${ny[bad]} (bm …${JSON.stringify(x.slice(Math.max(0, x.indexOf(nx[bad]) - 80), x.indexOf(nx[bad]) + 60))})`);
}
