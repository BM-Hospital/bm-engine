// The tagged-PDF part of scripts/pdf-compare.mjs: the structure tree, the parent tree, the ID tree,
// /StructParents and /Tabs per page, as canonical text (object numbers replaced by what they point
// at: a structure element by its path of roles, a page by its index, an annotation by its index
// in its page's /Annots), so two files compare equal when they tag the same content the same way.

/** Canonical structure parts of a parsed PDF (`parsePdf` of pdf-compare.mjs). */
export function structureParts(pdf, { Name, Ref }) {
  const objs = [...pdf.objs.values()];
  const catalogObj = objs.find((o) => o.dict && o.dict.Type instanceof Name && o.dict.Type.s === "Catalog");
  const cat = catalogObj ? catalogObj.dict : {};
  const pageIndex = new Map(pdf.pages.map((p, i) => [p.ref instanceof Ref ? p.ref.n : -1, i]));
  const annotIndex = new Map();
  pdf.pages.forEach((p, i) => {
    const list = Array.isArray(p.dict.Annots) ? p.dict.Annots : pdf.resolve(p.dict.Annots) || [];
    list.forEach((r, k) => { if (r instanceof Ref) annotIndex.set(r.n, `p${i + 1}#${k}`); });
  });
  const text = (v) => {
    if (v && v.hex !== undefined) {
      const b = Buffer.from(v.hex, "hex");
      if (b[0] === 0xfe && b[1] === 0xff) { let o = ""; for (let i = 2; i + 1 < b.length; i += 2) o += String.fromCharCode((b[i] << 8) | b[i + 1]); return o; }
      return b.toString("latin1");
    }
    if (v && v.str !== undefined) return v.str;
    return String(v);
  };
  const fmt = (v) => (typeof v === "number" ? String(v) : v instanceof Name ? "/" + v.s : Array.isArray(v) ? "[" + v.map(fmt).join(" ") + "]" : v instanceof Ref ? "R" : v && typeof v === "object" && v.hex === undefined && v.str === undefined ? "<<" + Object.entries(v).map(([k, x]) => "/" + k + " " + fmt(x)).join(" ") + ">>" : JSON.stringify(text(v)));
  const page = (r) => (r instanceof Ref && pageIndex.has(r.n) ? `p${pageIndex.get(r.n) + 1}` : "p?");
  const rootRef = cat.StructTreeRoot;
  const root = pdf.resolve(rootRef);
  const out = { tree: "(no structure tree)", parents: "", roots: "" };
  const pages = pdf.pages.map((p, i) => `page ${i + 1}: StructParents ${p.dict.StructParents ?? "-"} Tabs ${p.dict.Tabs ? fmt(p.dict.Tabs) : "-"}`).join("\n");
  const markInfo = cat.MarkInfo ? fmt(pdf.resolve(cat.MarkInfo)) : "-";
  if (!root) { out.roots = `MarkInfo ${markInfo}\n${pages}`; return out; }
  // element paths and the tree text
  const paths = new Map();
  const lines = [];
  const walk = (ref, path, depth) => {
    if (depth > 200) return;
    const d = pdf.resolve(ref) || {};
    if (ref instanceof Ref) paths.set(ref.n, path);
    const attrs = [];
    if (d.NS) { const ns = pdf.resolve(d.NS) || {}; attrs.push(`NS=${text(ns.NS)}`); }
    for (const k of ["ID", "T", "Lang", "Alt", "E", "ActualText"]) if (d[k] !== undefined) attrs.push(`${k}=${JSON.stringify(text(d[k]))}`);
    if (d.A !== undefined) attrs.push(`A=${fmt(pdf.resolve(d.A))}`);
    const kids = d.K === undefined ? [] : Array.isArray(d.K) ? d.K : [d.K];
    const leaves = [];
    let i = 0;
    for (const k of kids) {
      if (typeof k === "number") { leaves.push(`mcid ${page(d.Pg)}:${k}`); continue; }
      if (k instanceof Ref) {
        const kd = pdf.resolve(k) || {};
        if (kd.Type instanceof Name && kd.Type.s === "StructElem" || kd.S !== undefined) continue;
      }
      const kd = pdf.resolve(k) || {};
      if (kd.Type instanceof Name && kd.Type.s === "MCR") leaves.push(`mcid ${page(kd.Pg ?? d.Pg)}:${kd.MCID}`);
      else if (kd.Type instanceof Name && kd.Type.s === "OBJR") leaves.push(`annot ${kd.Obj instanceof Ref ? annotIndex.get(kd.Obj.n) || "?" : "?"}`);
      else leaves.push(`? ${fmt(kd)}`);
    }
    lines.push(`${"  ".repeat(depth)}${d.S ? d.S.s : "?"}${attrs.length ? " " + attrs.join(" ") : ""}${leaves.length ? " [" + leaves.join(", ") + "]" : ""}`);
    for (const k of kids) {
      if (!(k instanceof Ref)) continue;
      const kd = pdf.resolve(k) || {};
      if (kd.S === undefined) continue;
      walk(k, `${path}/${kd.S.s}[${i++}]`, depth + 1);
    }
  };
  const top = Array.isArray(root.K) ? root.K : root.K !== undefined ? [root.K] : [];
  top.forEach((r, i) => walk(r, `${(pdf.resolve(r) || {}).S ? pdf.resolve(r).S.s : "?"}[${i}]`, 0));
  out.tree = lines.join("\n");
  // the parent tree, resolved to element paths
  const nums = (pdf.resolve(root.ParentTree) || {}).Nums || [];
  const pt = [];
  for (let k = 0; k + 1 < nums.length; k += 2) {
    const v = nums[k + 1];
    const arr = pdf.resolve(v);
    if (Array.isArray(arr)) pt.push(`${nums[k]}: [${arr.map((r) => (r instanceof Ref ? paths.get(r.n) || "?" : fmt(r))).join(", ")}]`);
    else pt.push(`${nums[k]}: ${v instanceof Ref ? paths.get(v.n) || "?" : fmt(v)}`);
  }
  out.parents = pt.join("\n");
  const ids = (pdf.resolve(root.IDTree) || {}).Names || [];
  const idl = [];
  for (let k = 0; k + 1 < ids.length; k += 2) idl.push(`${text(ids[k])} -> ${ids[k + 1] instanceof Ref ? paths.get(ids[k + 1].n) || "?" : "?"}`);
  const annots = [];
  pdf.pages.forEach((p, i) => {
    const list = Array.isArray(p.dict.Annots) ? p.dict.Annots : pdf.resolve(p.dict.Annots) || [];
    list.forEach((r, k) => { const a = pdf.resolve(r) || {}; annots.push(`annot p${i + 1}#${k}: StructParent ${a.StructParent ?? "-"} Contents ${a.Contents !== undefined ? JSON.stringify(text(a.Contents)) : "-"}`); });
  });
  const roleMap = root.RoleMap ? fmt(pdf.resolve(root.RoleMap)) : "-";
  const nsl = (pdf.resolve(root.Namespaces) || []).map((r) => { const n = pdf.resolve(r) || {}; return `${text(n.NS)}${n.RoleMapNS ? " " + Object.keys(pdf.resolve(n.RoleMapNS)).join(",") : ""}`; });
  out.roots = [`MarkInfo ${markInfo}`, `RoleMap ${roleMap}`, `Namespaces [${nsl.join(" | ")}]`, `ParentTreeNextKey ${root.ParentTreeNextKey ?? "-"}`, `IDTree [${idl.join(", ")}]`, pages, ...annots].join("\n");
  return out;
}
