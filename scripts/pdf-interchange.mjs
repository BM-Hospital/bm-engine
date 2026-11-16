// The interchange part of scripts/pdf-compare.mjs: link annotations, destinations, the outline, the
// Info dictionary, the XMP packet, the file /ID, embedded files and the catalog entries, each as
// canonical text, compared between bm-render's file and takumi-pdf's golden.
//
// Normalised away (classes reported, not compared):
//   * the producer (bm-render writes "bm-render", the goldens "takumi-pdf fixture"): Info /Producer
//     and XMP pdf:Producer;
//   * the instance id (a hash of the file bytes so far: differs whenever any byte differs) and a
//     document id equal to it; a document id derived from the metadata (title + authors) is compared;
//   * object numbers (destinations are compared as page index + XYZ numbers).
// Numbers compare within 0.01 (layout float noise). The structure tree, the parent tree, the ID
// tree, /StructParent(s), /Contents of tagged annotations, /Tabs and /MarkInfo are compared through
// scripts/pdf-structure.mjs (parts `struct`, `parents`, `tagroot`).
import { structureParts } from "./pdf-structure.mjs";

/** Canonical interchange parts of a parsed PDF (`parsePdf` of pdf-compare.mjs). */
export function interchangeParts(pdf, { Name, Ref }) {
  const objs = [...pdf.objs.values()];
  const catalogObj = objs.find((o) => o.dict && o.dict.Type instanceof Name && o.dict.Type.s === "Catalog");
  const cat = catalogObj ? catalogObj.dict : {};
  const pageIndex = new Map(pdf.pages.map((p, i) => [p.ref instanceof Ref ? p.ref.n : -1, i]));
  const fmt = (v) => (typeof v === "number" ? String(Math.round(v * 1000) / 1000) : v instanceof Name ? "/" + v.s : Array.isArray(v) ? "[" + v.map(fmt).join(" ") + "]" : v && v.hex !== undefined ? "<" + v.hex + ">" : v && v.str !== undefined ? "(" + v.str + ")" : v instanceof Ref ? "R" : v === null ? "null" : typeof v === "object" ? "<<" + Object.entries(v).map(([k, x]) => "/" + k + " " + fmt(x)).join(" ") + ">>" : String(v));
  const text = (v) => {
    if (v && v.hex !== undefined) {
      const b = Buffer.from(v.hex, "hex");
      if (b[0] === 0xfe && b[1] === 0xff) { let o = ""; for (let i = 2; i + 1 < b.length; i += 2) o += String.fromCharCode((b[i] << 8) | b[i + 1]); return o; }
      return b.toString("latin1");
    }
    if (v && v.str !== undefined) return v.str;
    return v === undefined ? "-" : fmt(v);
  };
  const dest = (d) => {
    const arr = Array.isArray(d) ? d : pdf.resolve(d);
    if (!Array.isArray(arr)) return "dest?";
    const p = arr[0] instanceof Ref ? pageIndex.get(arr[0].n) : undefined;
    return `p${p === undefined ? "?" : p + 1} ${arr.slice(1).map(fmt).join(" ")}`;
  };
  // annotations, per page (/StructParent and /Contents: the structure part)
  const annots = pdf.pages.map((p, i) => {
    const list = Array.isArray(p.dict.Annots) ? p.dict.Annots : pdf.resolve(p.dict.Annots) || [];
    return list.map((r) => {
      const a = pdf.resolve(r) || {};
      const target = a.Dest !== undefined ? "Dest " + dest(a.Dest) : a.A ? "A " + fmt(pdf.resolve(a.A)) : "-";
      const extra = Object.keys(a).filter((k) => !["Type", "Subtype", "Rect", "Border", "Dest", "A", "F", "StructParent", "Contents"].includes(k));
      return `page ${i + 1}: ${fmt(a.Type)}${fmt(a.Subtype)} Rect ${fmt(a.Rect)} Border ${fmt(a.Border)} F ${fmt(a.F)} ${target}${extra.length ? " +" + extra.join(",") : ""}`;
    });
  }).flat();
  // the outline tree
  const outline = [];
  const root = pdf.resolve(cat.Outlines);
  if (root) {
    outline.push(`Outlines Count ${fmt(root.Count)}`);
    const walk = (ref, depth) => {
      let guard = 0;
      while (ref && guard++ < 1000) {
        const it = pdf.resolve(ref) || {};
        outline.push(`${"  ".repeat(depth)}${JSON.stringify(text(it.Title))} Count ${fmt(it.Count)} -> ${it.Dest !== undefined ? dest(it.Dest) : it.A ? fmt(pdf.resolve(it.A)) : "-"}`);
        if (it.First) walk(it.First, depth + 1);
        ref = it.Next;
      }
    };
    walk(root.First, 1);
  }
  // Info (producer normalised)
  const infoObj = objs.find((o) => o.dict && !Array.isArray(o.dict) && o.dict.Producer !== undefined);
  const info = infoObj ? Object.entries(infoObj.dict).filter(([k]) => k !== "Producer").map(([k, v]) => `${k}=${JSON.stringify(text(v))}`).join(" ") + ` Producer=${infoObj.dict.Producer !== undefined ? "set" : "-"}` : "(no Info)";
  // XMP and the file id
  const meta = pdf.obj(cat.Metadata);
  const trailer = objs.find((o) => o.dict && o.dict.Type instanceof Name && o.dict.Type.s === "XRef");
  const id = trailer && Array.isArray(trailer.dict.ID) ? trailer.dict.ID.map(text) : [];
  let xmp = meta && meta.data ? meta.data.toString("utf8") : "(no XMP)";
  const derived = id.length === 2 && id[0] !== id[1];
  xmp = xmp.replace(/<pdf:Producer>[^<]*<\/pdf:Producer>/, "<pdf:Producer>PRODUCER</pdf:Producer>");
  if (id[1]) xmp = xmp.split(id[1]).join("INSTANCE");
  if (id[0] && derived) xmp = xmp.split(id[0]).join("DOCID:" + id[0]);
  const ids = derived ? `document id derived: ${id[0]}` : "document id = instance id";
  // catalog entries (MarkInfo: the structure part)
  const catalog = Object.entries(cat).filter(([k]) => !["Type", "Pages", "MarkInfo"].includes(k)).map(([k, v]) => {
    if (k === "Lang") return `Lang=${JSON.stringify(text(v))}`;
    if (k === "Names") { const n = pdf.resolve(v); return `Names{${Object.keys(n).map((t) => `${t}:[${((pdf.resolve(n[t]) || {}).Names || []).filter((x) => !(x instanceof Ref)).map(text).join(",")}]`).join(" ")}}`; }
    if (k === "AF") return `AF[${(pdf.resolve(v) || []).length}]`;
    if (k === "ViewerPreferences") return `ViewerPreferences${fmt(pdf.resolve(v))}`;
    return k;
  }).join(" ");
  // embedded files
  const files = [];
  const names = cat.Names ? pdf.resolve(pdf.resolve(cat.Names).EmbeddedFiles) : null;
  if (names && Array.isArray(names.Names)) {
    for (let k = 0; k + 1 < names.Names.length; k += 2) {
      const spec = pdf.resolve(names.Names[k + 1]) || {};
      const ef = pdf.resolve(spec.EF) || {};
      const st = pdf.obj(ef.F);
      const sd = st ? st.dict : {};
      const params = pdf.resolve(sd.Params) || {};
      files.push(`${text(names.Names[k])}: F=${JSON.stringify(text(spec.F))} UF=${JSON.stringify(text(spec.UF))} EF=${Object.keys(ef).join(",")} AFRelationship=${fmt(spec.AFRelationship)} Desc=${JSON.stringify(text(spec.Desc))} | stream Subtype=${fmt(sd.Subtype)} Filter=${fmt(sd.Filter)} Size=${fmt(params.Size)} ModDate=${text(params.ModDate)} bytes=${st && st.data ? st.data.toString("hex") : "-"}`);
    }
  }
  const st = structureParts(pdf, { Name, Ref });
  return { annots: annots.join("\n"), outline: outline.join("\n"), info, xmp, ids, catalog, files: files.join("\n"), struct: st.tree, parents: st.parents, tagroot: st.roots };
}

const NUM = /-?\d*\.?\d+/g;
function close(a, b) {
  if (a === b) return true;
  if (a.replace(NUM, "#") !== b.replace(NUM, "#")) return false;
  const x = a.match(NUM) || []; const y = b.match(NUM) || [];
  return x.length === y.length && x.every((v, i) => Math.abs(+v - +y[i]) <= 0.01);
}

/** Per part: "same" | "close" | "differ". */
export function compareInterchange(mine, gold) {
  const out = {};
  for (const k of Object.keys(gold)) out[k] = mine[k] === gold[k] ? "same" : close(mine[k], gold[k]) ? "close" : "differ";
  return out;
}

/** Prints part `k` of both files (verbose / named runs). */
export function printInterchange(k, mine, gold) {
  const ind = (s) => "     " + s.replace(/\n/g, "\n     ").slice(0, 4000);
  console.log(`   ${k} bm:\n${ind(mine[k])}`);
  console.log(`   ${k} takumi:\n${ind(gold[k])}`);
}

const stream = (head, sections, tail) => `<div style="display: flex; flex-direction: column; width: 100%; font-size: 14px; color: #141414;">${head}${sections.map(([i, t, n]) => `<div id="${i}" style="display: flex; flex-direction: column; break-before: page;"><h2 style="font-size: 18px; margin: 0;">${t}</h2>${Array.from({ length: n }, (_, k) => `<div>${t}, line ${k + 1}</div>`).join("")}</div>`).join("")}${tail}</div>`;
const STREAM_PAGE = { size: { width: 320, height: 240 }, margin: 24 };

/** The link / outline / metadata / attachment fixtures of tests/pdf_fixtures.rs not in pdf-compare.mjs's list. */
export const INTERCHANGE_FIXTURES = [
  { name: "stream-forward-link", page: { ...STREAM_PAGE, outline: true }, html: stream(`<a href="#last" style="display: flex;">Jump to the last section</a>
      <a href="#missing" style="display: flex;">Nowhere</a>
      <h1 id="first" style="font-size: 22px; margin: 0;">First</h1>`, [["middle", "Middle", 4], ["later", "Later", 4], ["last", "Last", 4]], `<a href="#first" style="display: flex;">Back to the top</a>`) },
  { name: "stream-tagged-outline", page: { ...STREAM_PAGE, outline: true, tagged: true }, html: stream(`<h1 style="font-size: 22px; margin: 0;">Report</h1>
      <a href="https://example.com/report" style="display: flex;">Online</a>
      <a href="mailto:report@example.com" style="display: flex;">Write to us</a>`, [["one", "One", 6], ["two", "Two", 6], ["three", "Three", 6]], `<a href="https://example.com/end" style="display: flex;">The end</a>`) },
  { name: "invoice-pdfa-3b-attachment", page: { size: "a4", margin: { top: 36, right: 36, bottom: "auto", left: 36 }, footerFile: "invoice-footer.html", pdfa: "3b",
    metadata: { title: "Invoice", creationDate: "2026-08-06", xmp: [{ name: "Factur-X PDF/A Extension", prefix: "fx", namespace: "urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#", properties: [{ name: "DocumentFileName", value: "factur-x.xml", description: "name of the embedded XML invoice file" }] }] },
    attachments: [{ name: "factur-x.xml", data: `<invoice total="1290"/>`, mimeType: "application/xml", description: "Factur-X invoice data", relationship: "alternative" }] }, htmlFile: "invoice.html" },
];
