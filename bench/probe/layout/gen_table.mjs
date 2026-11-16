// Generates src/layout/testdata/oracle_table.json: table trees + takumi's (Blink LayoutNG port) layout results.
// Usage: node --no-warnings gen_table.mjs [name-filter]      (run from bench/probe/layout)
//
// Fixture format as gen.mjs: {name, vp:[w,h], node:{style, children}, expect:{x,y,w,h,children}}.
//  * spans: style keys `colSpan` / `rowSpan` (cells) and `colSpan` (= `span` of a column / column group). takumi
//    reads them from HTML attributes, so the oracle gets tagName td / col / colgroup + attributes.
//  * takumi materialises anonymous table boxes (row groups, rows, cells, tables around stray parts) as extra
//    nodes of its result; bm-render keeps them virtual. `expect` only has the REAL nodes: the anonymous levels
//    are skipped here by replaying takumi's fix-up (layout/table/parts.rs) on the fixture tree.
//  * display:none children, columns and column groups (which takumi hides) are recorded as {none:true}.
import { Renderer } from "@takumi-rs/wasm/node";
import { writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const r = new Renderer();

// ---------------------------------------------------------------- oracle plumbing
export const toTakumi = (n) => {
  const { colSpan, rowSpan, ...style } = n.style || {};
  const o = { type: "container", style, children: (n.children || []).map(toTakumi) };
  if (colSpan !== undefined || rowSpan !== undefined) {
    const d = style.display;
    o.tagName = d === "table-cell" ? "td" : d === "table-column-group" ? "colgroup" : "col";
    o.attributes = {};
    if (colSpan !== undefined) o.attributes[d === "table-cell" ? "colspan" : "span"] = String(colSpan);
    if (rowSpan !== undefined) o.attributes.rowspan = String(rowSpan);
  }
  return o;
};

const SECTION = ["table-row-group", "table-header-group", "table-footer-group"];
const COLS = ["table-column", "table-column-group"];
const ROLE = { table: "table", "inline-table": "table", "table-row": "row", "table-column-group": "colgroup", "table-column": "col" };
for (const s of SECTION) ROLE[s] = "section";
const ACCEPTS = {
  table: (d) => d === "table-caption" || COLS.includes(d) || SECTION.includes(d),
  section: (d) => d === "table-row",
  row: (d) => d === "table-cell",
  colgroup: (d) => d === "table-column",
  col: () => false,
};
const WRAPPER = { table: "table-row-group", section: "table-row", row: "table-cell" };
const isPart = (d) => d !== undefined && d.startsWith("table-");
const disp = (n) => (n.style || {}).display;
const anon = (display, children) => ({ anon: true, style: { display }, children });

// takumi's fix_up_table_children / wrap_orphan_table_parts
function fixedChildren(n) {
  const kids = (n.children || []).filter((c) => disp(c) !== "none");
  const role = ROLE[disp(n)];
  const out = [];
  let run = [];
  if (role) {
    const flush = () => { if (run.length && WRAPPER[role]) out.push(anon(WRAPPER[role], run)); run = []; };
    for (const k of kids) {
      if (ACCEPTS[role](disp(k))) { flush(); out.push(k); } else if (WRAPPER[role]) run.push(k);
    }
    flush();
    return out;
  }
  if (["flex", "grid", "inline-flex", "inline-grid"].includes(disp(n)) || !kids.some((k) => isPart(disp(k)))) return kids;
  const flush = () => { if (run.length) out.push(anon("table", run)); run = []; };
  for (const k of kids) {
    if (isPart(disp(k))) run.push(k); else { flush(); out.push(k); }
  }
  flush();
  return out;
}

// maps takumi's result `m` (which has the anonymous boxes) onto the real nodes
function collect(n, m, map) {
  const kids = fixedChildren(n);
  if (kids.length !== m.children.length) throw new Error(`child count mismatch at ${disp(n)}: ${kids.length} vs ${m.children.length}`);
  if (!n.anon) map.set(n, m);
  kids.forEach((k, i) => collect(k, m.children[i], map));
}
function expectOf(n, map) {
  const m = map.get(n);
  if (!m || disp(n) === "none" || COLS.includes(disp(n))) return { x: 0, y: 0, w: 0, h: 0, none: true };
  const kids = (n.children || []).map((k) => expectOf(k, map));
  return { x: m.transform[4], y: m.transform[5], w: m.width, h: m.height, ...(kids.length ? { children: kids } : {}) };
}
export async function oracle(node, vp) {
  const m = await r.measure(toTakumi(node), { width: vp[0], height: vp[1] });
  const map = new Map();
  collect(node, m, map);
  return expectOf(node, map);
}
export async function oracleRaw(node, vp) {
  return r.measure(toTakumi(node), { width: vp[0], height: vp[1] });
}

// ---------------------------------------------------------------- builders
const cases = [];
export const c = (style, ...children) => ({ style, children });
export const F = (style, ...ch) => c({ display: "flex", ...style }, ...ch);
export const B = (style, ...ch) => c({ display: "block", ...style }, ...ch);
export const G = (style, ...ch) => c({ display: "grid", ...style }, ...ch);
export const T = (style, ...ch) => c({ display: "table", ...style }, ...ch);
export const TR = (style, ...ch) => c({ display: "table-row", ...style }, ...ch);
export const TD = (style, ...ch) => c({ display: "table-cell", ...style }, ...ch);
export const TB = (style, ...ch) => c({ display: "table-row-group", ...style }, ...ch);
export const TH = (style, ...ch) => c({ display: "table-header-group", ...style }, ...ch);
export const TF = (style, ...ch) => c({ display: "table-footer-group", ...style }, ...ch);
export const CAP = (style, ...ch) => c({ display: "table-caption", ...style }, ...ch);
export const COL = (style, ...ch) => c({ display: "table-column", ...style }, ...ch);
export const CG = (style, ...ch) => c({ display: "table-column-group", ...style }, ...ch);
export const box = (w, h, extra = {}) => B({ width: w, height: h, ...extra });
// "text-like" content: a wrapping flex row of fixed boxes (min-content = widest box, max-content = sum)
export const words = (n, w = 30, h = 10, extra = {}) => F({ flexWrap: "wrap", ...extra }, ...Array.from({ length: n }, () => F({ width: w, height: h, flexShrink: 0 })));
// border-spacing, border-collapse and caption-side are inherited in CSS but per-node in bm-render's Style (the
// integrator resolves inheritance): make the inherited values explicit in the fixture.
const INHERITED = ["borderSpacing", "borderCollapse", "captionSide"];
function inherit(n, from = {}) {
  const own = {};
  for (const k of INHERITED) {
    if (n.style[k] !== undefined) own[k] = n.style[k];
    else if (from[k] !== undefined) own[k] = n.style[k] = from[k];
  }
  n.children.forEach((k) => inherit(k, own));
  return n;
}
export { inherit };
const add = (name, node, vp = [400, 300]) => cases.push({ name, vp, node: inherit(node) });
const bd = (w) => ({ borderWidth: w, borderStyle: "solid" });

// ---------------------------------------------------------------- automatic layout
add("auto/basic", T({}, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))), TR({}, TD({}, box(70, 10)), TD({}, box(20, 15)))));
add("auto/words-shrink", B({ width: 200 }, T({}, TR({}, TD({}, words(5)), TD({}, words(9, 20))))));
add("auto/words-min", B({ width: 60 }, T({}, TR({}, TD({}, words(5)), TD({}, words(9, 20))))));
add("auto/words-three", B({ width: 250 }, T({}, TR({}, TD({}, words(4, 40)), TD({}, words(6, 25)), TD({}, box(50, 10))), TR({}, TD({}, words(2, 60)), TD({}, words(8, 10)), TD({}, words(3))))));
add("auto/odd-widths", B({ width: 201 }, T({}, TR({}, TD({}, words(7, 33.3)), TD({}, words(5, 21.7)), TD({}, words(9, 17))))));
add("auto/cell-padding-border", T({}, TR({}, TD({ padding: 5, ...bd(2) }, box(40, 20)), TD({ padding: "1px 7px", ...bd(1) }, box(60, 30)))));
add("auto/cell-pct-padding", B({ width: 300 }, T({ width: 200 }, TR({}, TD({ padding: "10%" }, box(40, 20)), TD({}, box(60, 30))))));
for (const sp of [4, "6px 2px", "0 9px", 2.5]) add(`spacing/${String(sp).replace(/ /g, "_")}`, T({ borderSpacing: sp }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))), TR({}, TD({}, box(30, 10)), TD({}, box(20, 15)))));
add("spacing/sections", T({ borderSpacing: 5 }, TH({}, TR({}, TD({}, box(40, 20)))), TB({}, TR({}, TD({}, box(30, 10))), TR({}, TD({}, box(30, 10)))), TB({}), TF({}, TR({}, TD({}, box(20, 10))))));
add("table/padding-border-margin", B({ width: 300 }, T({ padding: 7, ...bd(3), margin: "5px 9px", borderSpacing: 2 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), box(10, 10)));
add("table/padding-pct", B({ width: 300 }, T({ padding: "5%" }, TR({}, TD({}, box(40, 20))))));
add("table/content-box", B({ width: 300 }, T({ width: 150, height: 80, padding: 7, ...bd(3), boxSizing: "content-box" }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));
add("table/root-width", T({ width: 250 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))));
add("table/root-pct", T({ width: "50%", height: "50%" }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))));
add("table/inline-table", F({ width: 300, alignItems: "flex-start" }, c({ display: "inline-table" }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));

// ---------------------------------------------------------------- table width
for (const w of [50, 150, 333, "100%", "60%"]) add(`width/table-${w}`, B({ width: 300 }, T({ width: w }, TR({}, TD({}, words(3)), TD({}, words(6)), TD({}, box(20, 10))))));
add("width/min-width", B({ width: 300 }, T({ minWidth: 200 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));
add("width/max-width", B({ width: 300 }, T({ maxWidth: 80 }, TR({}, TD({}, words(4)), TD({}, words(6))))));
add("width/max-width-below-min", B({ width: 300 }, T({ maxWidth: 40 }, TR({}, TD({}, words(4)), TD({}, words(6))))));
add("width/width-and-max", B({ width: 300 }, T({ width: 250, maxWidth: 150 }, TR({}, TD({}, words(4)), TD({}, words(6))))));
add("width/overflow-parent", B({ width: 100 }, T({}, TR({}, TD({}, box(80, 20)), TD({}, box(90, 30))))));
add("width/spacing-pct", B({ width: 300 }, T({ width: "100%", borderSpacing: 6, padding: 4, ...bd(1) }, TR({}, TD({}, words(3)), TD({}, words(6))))));
for (const [i, ws] of [[40, null], [null, 100], [40, 100], [200, 200], ["30%", null], ["30%", "50%"], ["70%", "60%"], ["50%", 80]].entries())
  add(`width/cells-${i}`, B({ width: 300 }, T({ width: 260 }, TR({}, TD(ws[0] === null ? {} : { width: ws[0] }, words(3)), TD(ws[1] === null ? {} : { width: ws[1] }, words(6))), TR({}, TD({}, box(25, 10)), TD({}, box(35, 10))))));
for (const [i, ws] of [[40, null], ["30%", null], ["30%", 80], ["20%", "20%"]].entries())
  add(`width/cells-auto-${i}`, B({ width: 300 }, T({}, TR({}, TD(ws[0] === null ? {} : { width: ws[0] }, words(3)), TD(ws[1] === null ? {} : { width: ws[1] }, words(6)), TD({}, words(2, 40))))));
add("width/cell-min-max", B({ width: 300 }, T({}, TR({}, TD({ minWidth: 100 }, words(3)), TD({ maxWidth: 50 }, words(6)), TD({ width: 30, minWidth: 60 }, box(10, 10)), TD({ width: 100, maxWidth: 45 }, box(10, 10))))));
add("width/cell-content-box", B({ width: 300 }, T({}, TR({}, TD({ width: 50, padding: 6, ...bd(2), boxSizing: "content-box" }, box(10, 10)), TD({ width: 50, padding: 6, ...bd(2) }, box(10, 10))))));
add("width/cell-width-below-content", T({}, TR({}, TD({ width: 20 }, box(50, 10)), TD({ width: 90 }, box(20, 10)))));
add("width/same-col-constraints", T({}, TR({}, TD({ width: 80 }, box(10, 10)), TD({}, box(20, 10))), TR({}, TD({}, words(5)), TD({ width: "40%" }, box(20, 10))), TR({}, TD({ width: 60 }, box(10, 10)), TD({ width: "25%" }, box(20, 10)))));
add("width/pct-over-100", B({ width: 300 }, T({ width: 280 }, TR({}, TD({ width: "60%" }, box(10, 10)), TD({ width: "70%" }, box(20, 10)), TD({ width: "30%" }, box(20, 10)), TD({}, box(20, 10))))));
add("width/pct-intrinsic", B({ width: 300 }, T({}, TR({}, TD({ width: "25%" }, box(40, 10)), TD({}, box(60, 10))))));
add("width/pct-intrinsic-flex", F({ width: 300 }, T({}, TR({}, TD({ width: "25%" }, box(40, 10)), TD({}, box(60, 10))))));
add("width/pct-all", B({ width: 300 }, T({}, TR({}, TD({ width: "40%" }, box(40, 10)), TD({ width: "60%" }, box(30, 10))))));
add("width/above-max-fixed-only", B({ width: 300 }, T({ width: 280 }, TR({}, TD({ width: 40 }, box(10, 10)), TD({ width: 100 }, box(20, 10))))));
add("width/above-max-pct-only", B({ width: 300 }, T({ width: 280 }, TR({}, TD({ width: "20%" }, box(10, 10)), TD({ width: "30%" }, box(20, 10))))));
add("width/empty-cells", B({ width: 300 }, T({ width: 200 }, TR({}, TD({}), TD({}, box(20, 10)), TD({})))));
add("width/empty-col", B({ width: 300 }, T({ width: 200, borderSpacing: 4 }, TR({}, TD({ colSpan: 2 }, box(30, 10)), TD({}, box(20, 10))), TR({}, TD({}, box(10, 10))))));

// ---------------------------------------------------------------- colspan
add("colspan/basic", T({}, TR({}, TD({ colSpan: 2 }, box(100, 20))), TR({}, TD({}, box(30, 20)), TD({}, box(40, 20)))));
add("colspan/narrow", T({}, TR({}, TD({ colSpan: 2 }, box(20, 20))), TR({}, TD({}, box(30, 20)), TD({}, box(40, 20)))));
add("colspan/three", B({ width: 300 }, T({ borderSpacing: 3 }, TR({}, TD({ colSpan: 3 }, words(8))), TR({}, TD({}, box(30, 20)), TD({ colSpan: 2 }, words(5))), TR({}, TD({}, box(10, 10)), TD({}, box(15, 10)), TD({}, box(20, 10))))));
add("colspan/width", T({}, TR({}, TD({ colSpan: 2, width: 200 }, box(20, 20)), TD({}, box(10, 10))), TR({}, TD({}, box(30, 20)), TD({ width: 50 }, box(40, 20)), TD({}, box(10, 10)))));
add("colspan/pct", B({ width: 300 }, T({ width: "100%" }, TR({}, TD({ colSpan: 2, width: "60%" }, box(20, 20)), TD({}, box(10, 10))), TR({}, TD({}, box(30, 20)), TD({}, box(60, 20)), TD({}, box(10, 10))))));
add("colspan/pct-partial", B({ width: 300 }, T({ width: "100%" }, TR({}, TD({ colSpan: 3, width: "80%" }, box(20, 20)), TD({}, box(10, 10))), TR({}, TD({ width: "20%" }, box(30, 20)), TD({}, box(60, 20)), TD({}, box(20, 20)), TD({}, box(10, 10))))));
add("colspan/beyond", T({}, TR({}, TD({}, box(30, 20)), TD({ colSpan: 5 }, box(100, 20))), TR({}, TD({}, box(30, 20)), TD({}, box(40, 20)))));
add("colspan/only", T({ borderSpacing: 2 }, TR({}, TD({ colSpan: 3 }, box(90, 20)))));
add("colspan/words", B({ width: 180 }, T({}, TR({}, TD({ colSpan: 2 }, words(10))), TR({}, TD({}, words(3)), TD({}, words(4, 20))))));
add("colspan/mixed-rows", B({ width: 300 }, T({}, TR({}, TD({}, box(20, 10)), TD({ colSpan: 2 }, box(120, 10))), TR({}, TD({ colSpan: 2 }, box(110, 10)), TD({}, box(20, 10))), TR({}, TD({}, box(10, 10)), TD({}, box(10, 10)), TD({}, box(10, 10))))));
add("colspan/zero", T({}, TR({}, TD({ colSpan: 0 }, box(100, 20)), TD({}, box(10, 10))), TR({}, TD({}, box(30, 20)), TD({}, box(40, 20)))));

// ---------------------------------------------------------------- table-layout: fixed
add("fixed/basic", B({ width: 300 }, T({ tableLayout: "fixed", width: 240 }, TR({}, TD({ width: 60 }, box(10, 10)), TD({}, words(9)), TD({}, box(200, 10))), TR({}, TD({ width: 200 }, box(100, 10)), TD({}, box(5, 5)), TD({}, box(5, 5))))));
add("fixed/auto-width", B({ width: 300 }, T({ tableLayout: "fixed" }, TR({}, TD({ width: 60 }, box(10, 10)), TD({}, words(9))))));
add("fixed/pct", B({ width: 300 }, T({ tableLayout: "fixed", width: "100%" }, TR({}, TD({ width: "25%" }, box(10, 10)), TD({}, words(9)), TD({ width: 50 }, box(200, 10))))));
add("fixed/over", B({ width: 300 }, T({ tableLayout: "fixed", width: 200 }, TR({}, TD({ width: 150 }, box(10, 10)), TD({ width: 150 }, box(10, 10))))));
add("fixed/under", B({ width: 300 }, T({ tableLayout: "fixed", width: 200 }, TR({}, TD({ width: 50 }, box(10, 10)), TD({ width: 30 }, box(10, 10))))));
add("fixed/pct-over", B({ width: 300 }, T({ tableLayout: "fixed", width: 200 }, TR({}, TD({ width: "80%" }, box(10, 10)), TD({ width: "60%" }, box(10, 10)), TD({}, box(10, 10))))));
add("fixed/colspan", B({ width: 300 }, T({ tableLayout: "fixed", width: 240, borderSpacing: 3 }, TR({}, TD({ colSpan: 2, width: 100 }, box(10, 10)), TD({}, box(10, 10))), TR({}, TD({}, box(10, 10)), TD({}, box(10, 10)), TD({}, box(10, 10))))));
add("fixed/colspan-pct", B({ width: 300 }, T({ tableLayout: "fixed", width: 240 }, TR({}, TD({ colSpan: 2, width: "50%" }, box(10, 10)), TD({ colSpan: 3 }, box(10, 10))))));
add("fixed/cols", B({ width: 300 }, T({ tableLayout: "fixed", width: 240 }, COL({ width: 100 }), COL({ width: "20%" }), TR({}, TD({ width: 10 }, box(10, 10)), TD({}, box(10, 10)), TD({}, box(10, 10))))));
add("fixed/zero-width", B({ width: 300 }, T({ tableLayout: "fixed", width: 240 }, TR({}, TD({ width: 0 }, box(10, 10)), TD({ width: 60 }, box(10, 10)), TD({}, box(10, 10))))));
add("fixed/padding-content-box", B({ width: 300 }, T({ tableLayout: "fixed", width: 240, padding: 5, ...bd(2) }, TR({}, TD({ width: "30%", padding: 8, boxSizing: "content-box" }, box(10, 10)), TD({ width: 40, padding: 8, boxSizing: "content-box" }, box(10, 10)), TD({}, box(10, 10))))));
add("fixed/odd", B({ width: 300 }, T({ tableLayout: "fixed", width: 200 }, TR({}, TD({}, box(10, 10)), TD({}, box(10, 10)), TD({}, box(10, 10))))));
add("fixed/min-content-narrow", B({ width: 300 }, T({ tableLayout: "fixed", width: 30 }, TR({}, TD({ width: 60 }, box(10, 10)), TD({}, box(50, 10))))));

// ---------------------------------------------------------------- columns
add("cols/width", T({}, COL({ width: 80 }), COL({ width: 30 }), TR({}, TD({}, box(20, 20)), TD({}, box(60, 20)))));
add("cols/span", T({}, COL({ width: 50, colSpan: 2 }), COL({}), TR({}, TD({}, box(20, 20)), TD({}, box(10, 20)), TD({}, box(10, 20)))));
add("cols/group", T({}, CG({ width: 60 }, COL({}), COL({ width: 20 })), CG({ width: 45, colSpan: 2 }), TR({}, TD({}, box(20, 20)), TD({}, box(10, 20)), TD({}, box(10, 20)), TD({}, box(10, 20)))));
add("cols/pct", B({ width: 300 }, T({ width: "100%" }, COL({ width: "50%" }), COL({}), COL({ width: "10%" }), TR({}, TD({}, box(20, 20)), TD({}, box(10, 20)), TD({}, box(10, 20))))));
add("cols/extra", T({}, COL({ width: 50 }), COL({ width: 60 }), COL({ width: 70 }), COL({}), TR({}, TD({}, box(20, 20)), TD({}, box(10, 20)))));
add("cols/min-width", T({}, COL({ minWidth: 90 }), COL({ width: 10, minWidth: 40 }), TR({}, TD({}, box(20, 20)), TD({}, box(10, 20)))));
add("cols/only", T({}, COL({ width: 50 }), COL({ width: 60 })));
add("cols/cell-vs-col", T({}, COL({ width: 80 }), COL({ width: 80 }), TR({}, TD({ width: 120 }, box(20, 20)), TD({ width: 30 }, box(10, 20)))));

// ---------------------------------------------------------------- border-collapse
const C = { borderCollapse: "collapse" };
add("collapse/uniform", T({ ...C, ...bd(2) }, TR({}, TD(bd(2), box(40, 20)), TD(bd(2), box(60, 30))), TR({}, TD(bd(2), box(30, 10)), TD(bd(2), box(20, 15)))));
add("collapse/odd", T({ ...C, ...bd(1) }, TR({}, TD(bd(1), box(40, 20)), TD(bd(1), box(60, 30))), TR({}, TD(bd(1), box(30, 10)), TD(bd(1), box(20, 15)))));
add("collapse/mixed", T({ ...C, ...bd(6) }, TR({}, TD(bd(2), box(40, 20)), TD(bd(10), box(60, 30))), TR({}, TD(bd(4), box(30, 10)), TD(bd(1), box(20, 15)))));
add("collapse/table-only", T({ ...C, ...bd(8) }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))), TR({}, TD({}, box(30, 10)), TD({}, box(20, 15)))));
add("collapse/cells-only", T(C, TR({}, TD(bd(3), box(40, 20)), TD(bd(5), box(60, 30))), TR({}, TD(bd(7), box(30, 10)), TD({}, box(20, 15)))));
const sides = (t, r, b, l) => ({ borderTopWidth: t, borderRightWidth: r, borderBottomWidth: b, borderLeftWidth: l, borderStyle: "solid" });
add("collapse/sides", T({ ...C, ...sides(2, 0, 0, 4) }, TR({}, TD(sides(0, 6, 0, 0), box(40, 20)), TD(sides(0, 0, 8, 0), box(60, 30))), TR({}, TD(sides(3, 0, 0, 0), box(30, 10)), TD({}, box(20, 15)))));
add("collapse/rows-sections", T(C, TH({ ...bd(6) }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), TB({}, TR(bd(4), TD({}, box(30, 10)), TD({}, box(20, 15))), TR({}, TD(bd(2), box(30, 10)), TD({}, box(20, 15))))));
add("collapse/cols", T(C, COL(bd(4)), CG(bd(8), COL({}), COL(bd(2))), TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)), TD({}, box(20, 30))), TR({}, TD({}, box(30, 10)), TD({}, box(20, 15)), TD({}, box(20, 30)))));
add("collapse/spans", T({ ...C, ...bd(2) }, TR({}, TD({ ...bd(6), colSpan: 2 }, box(40, 20)), TD({ ...bd(2), rowSpan: 2 }, box(60, 30))), TR({}, TD(bd(4), box(30, 10)), TD(bd(8), box(20, 15)))));
add("collapse/padding-ignored", B({ width: 300 }, T({ ...C, ...bd(4), padding: 20, borderSpacing: 9 }, TR({}, TD({ ...bd(2), padding: 3 }, box(40, 20)), TD(bd(2), box(60, 30))))));
add("collapse/width", B({ width: 300 }, T({ ...C, ...bd(4), width: 200 }, TR({}, TD(bd(2), words(3)), TD(bd(6), words(5))))));
add("collapse/content-box", B({ width: 300 }, T({ ...C, ...bd(4), width: 200, height: 60, padding: 10, boxSizing: "content-box" }, TR({}, TD(bd(2), words(3)), TD(bd(6), words(5))))));
add("collapse/fixed", B({ width: 300 }, T({ ...C, ...bd(4), width: 200, tableLayout: "fixed" }, TR({}, TD({ ...bd(2), width: 50 }, words(3)), TD(bd(6), words(5))))));
add("collapse/anon", T({ ...C, ...bd(6) }, box(40, 20), TR(bd(2), box(30, 30), TD(bd(4), box(10, 10)))));
add("collapse/empty", B({ width: 300 }, T({ ...C, ...bd(6), padding: 5 }), box(10, 10)));
add("collapse/odd-mix", T({ ...C, ...bd(3) }, TR({}, TD(bd(1), box(40, 20)), TD(bd(5), box(60, 30)), TD(bd(7), box(10, 10)))));
add("collapse/caption", T({ ...C, ...bd(6) }, CAP({}, box(30, 10)), TR({}, TD(bd(2), box(40, 20)))));
add("collapse/colspan-beyond", T({ ...C, ...bd(2) }, TR({}, TD({ ...bd(6), colSpan: 4 }, box(40, 20))), TR({}, TD(bd(4), box(30, 10)), TD(bd(8), box(20, 15)))));

// ---------------------------------------------------------------- heights
add("height/row", T({}, TR({ height: 50 }, TD({}, box(40, 20)), TD({}, box(60, 30))), TR({ height: 5 }, TD({}, box(30, 10)))));
add("height/cell", T({}, TR({}, TD({ height: 50 }, box(40, 20)), TD({}, box(60, 30))), TR({}, TD({ height: 5, padding: 4 }, box(30, 10)), TD({ height: 30, padding: 4, boxSizing: "content-box" }, box(30, 10)))));
add("height/cell-min-max-ignored", T({}, TR({}, TD({ minHeight: 50 }, box(40, 20)), TD({ maxHeight: 10 }, box(60, 30)))));
for (const h of [100, 37, 201]) add(`height/table-${h}`, T({ height: h }, TR({}, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10))), TR({}, TD({}, box(40, 30)))));
add("height/table-spacing-border", T({ height: 150, borderSpacing: 4, padding: 3, ...bd(2) }, TR({}, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10)))));
add("height/table-constrained-rows", T({ height: 150 }, TR({ height: 30 }, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10))), TR({}, TD({ height: 20 }, box(40, 10)))));
add("height/table-all-constrained", T({ height: 150 }, TR({ height: 30 }, TD({}, box(40, 20))), TR({ height: 10 }, TD({}, box(40, 10)))));
add("height/table-empty-rows", T({ height: 150 }, TR({}, TD({}, box(40, 20))), TR({}, TD({})), TR({}), TR({ height: 10 }, TD({}))));
add("height/table-only-empty-rows", T({ height: 90, width: 50 }, TR({}, TD({})), TR({}, TD({})), TR({ height: 0 }, TD({}))));
add("height/table-pct-rows", T({ height: 200 }, TR({ height: "50%" }, TD({}, box(40, 20))), TR({ height: "20%" }, TD({}, box(40, 10))), TR({}, TD({}, box(40, 10)))));
add("height/table-pct-cells", T({ height: 200 }, TR({}, TD({ height: "30%" }, box(40, 20)), TD({ height: "60%" }, box(40, 20))), TR({}, TD({}, box(40, 10)))));
add("height/table-pct-over", T({ height: 200 }, TR({ height: "70%" }, TD({}, box(40, 20))), TR({ height: "70%" }, TD({}, box(40, 10)))));
add("height/pct-rows-auto-table", T({}, TR({ height: "50%" }, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10)))));
add("height/sections", T({ height: 220 }, TH({}, TR({}, TD({}, box(40, 20)))), TB({}, TR({}, TD({}, box(40, 10))), TR({}, TD({}, box(40, 30)))), TB({ height: 50 }, TR({}, TD({}, box(40, 10)))), TF({}, TR({}, TD({}, box(40, 10))))));
add("height/sections-pct", T({ height: 220 }, TH({ height: "20%" }, TR({}, TD({}, box(40, 20)))), TB({ height: "50%" }, TR({}, TD({}, box(40, 10))), TR({}, TD({}, box(40, 30)))), TB({}, TR({}, TD({}, box(40, 10))))));
add("height/sections-no-body", T({ height: 120 }, TH({}, TR({}, TD({}, box(40, 20)))), TF({ height: 30 }, TR({}, TD({}, box(40, 10))))));
add("height/section-fixed", T({}, TB({ height: 100 }, TR({}, TD({}, box(40, 10))), TR({ height: "25%" }, TD({}, box(40, 10))), TR({}, TD({}, box(40, 30)))), TB({ height: 5 }, TR({}, TD({}, box(40, 10))))));
add("height/min-height", T({ minHeight: 100 }, TR({}, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10)))));
add("height/max-height", T({ height: 200, maxHeight: 80 }, TR({}, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10)))));
add("height/max-height-below-content", T({ maxHeight: 20 }, TR({}, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10)))));
add("height/pct-table", B({ width: 300, height: 200 }, T({ height: "50%" }, TR({}, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10))))));
add("height/pct-table-indefinite", B({ width: 300 }, T({ height: "50%" }, TR({}, TD({}, box(40, 20))), TR({}, TD({}, box(40, 10))))));
add("height/pct-child", T({ height: 120 }, TR({}, TD({}, B({ height: "50%", width: 20 })), TD({}, box(30, 40)))));
add("height/pct-child-auto", T({}, TR({}, TD({}, B({ height: "50%", width: 20 })), TD({}, box(30, 40)))));
add("height/pct-child-cell-height", T({}, TR({}, TD({ height: 80 }, B({ height: "50%", width: 20 })), TD({}, box(30, 40)))));
add("height/pct-child-baseline", T({ height: 120 }, TR({}, TD({}, B({ height: "50%", width: 20 }), box(10, 10)), TD({}, box(30, 40)), TD({ padding: 5 }, box(10, 10)))));
add("height/fractional", T({ height: 100 }, TR({}, TD({}, box(40, 20.3))), TR({}, TD({}, box(40, 10.7))), TR({}, TD({}, box(40, 30.1)))));

// ---------------------------------------------------------------- rowspan
add("rowspan/basic", T({}, TR({}, TD({ rowSpan: 2 }, box(40, 20)), TD({}, box(60, 30))), TR({}, TD({}, box(30, 10)))));
add("rowspan/tall", T({ borderSpacing: 2 }, TR({}, TD({ rowSpan: 2 }, box(40, 120)), TD({}, box(60, 30))), TR({}, TD({}, box(30, 10)))));
add("rowspan/tall-three", T({}, TR({}, TD({ rowSpan: 3 }, box(40, 100)), TD({}, box(60, 30))), TR({}, TD({}, box(30, 10))), TR({}, TD({}, box(30, 20)))));
add("rowspan/empty-rows", T({}, TR({}, TD({ rowSpan: 3 }, box(40, 100)), TD({}, box(60, 30))), TR({}), TR({})));
add("rowspan/only-empty", T({}, TR({}, TD({ rowSpan: 3 }, box(40, 100))), TR({}), TR({})));
add("rowspan/nested-spans", T({}, TR({}, TD({ rowSpan: 3 }, box(40, 150)), TD({ rowSpan: 2 }, box(20, 90)), TD({}, box(60, 10))), TR({}, TD({}, box(30, 10))), TR({}, TD({}, box(30, 20)), TD({}, box(30, 20)))));
add("rowspan/originating", T({}, TR({}, TD({ rowSpan: 3 }, box(40, 150)), TD({}, box(60, 10))), TR({}, TD({ rowSpan: 2 }, box(30, 10)), TD({}, box(5, 5))), TR({}, TD({}, box(30, 20)))));
add("rowspan/colspan", T({}, TR({}, TD({ rowSpan: 2, colSpan: 2 }, box(90, 70)), TD({}, box(60, 10))), TR({}, TD({}, box(30, 10))), TR({}, TD({}, box(30, 20)), TD({}, box(30, 20)), TD({}, box(30, 20)))));
add("rowspan/beyond-section", T({}, TB({}, TR({}, TD({ rowSpan: 5 }, box(40, 80)), TD({}, box(60, 10))), TR({}, TD({}, box(30, 10)))), TB({}, TR({}, TD({}, box(30, 20)), TD({}, box(30, 20))))));
add("rowspan/height", T({}, TR({}, TD({ rowSpan: 2, height: 100 }, box(40, 20)), TD({}, box(60, 30))), TR({}, TD({}, box(30, 10)))));
add("rowspan/valign", T({}, TR({}, TD({ rowSpan: 2, verticalAlign: "middle" }, box(40, 20)), TD({}, box(60, 30)), TD({ rowSpan: 2, verticalAlign: "bottom" }, box(10, 10))), TR({}, TD({}, box(30, 40)))));
add("rowspan/baseline", T({}, TR({}, TD({ rowSpan: 2 }, box(40, 20)), TD({ padding: 10 }, box(60, 30)), TD({}, box(10, 10))), TR({}, TD({}, box(30, 40)))));
add("rowspan/table-height", T({ height: 200 }, TR({}, TD({ rowSpan: 2 }, box(40, 20)), TD({}, box(60, 30))), TR({}, TD({}, box(30, 10))), TR({}, TD({}, box(30, 10)))));
add("rowspan/skip-cols", T({}, TR({}, TD({}, box(10, 10)), TD({ rowSpan: 2 }, box(20, 20)), TD({}, box(30, 10)), TD({ rowSpan: 3 }, box(15, 15))), TR({}, TD({}, box(11, 10)), TD({}, box(31, 10))), TR({}, TD({}, box(12, 10)), TD({}, box(22, 10)), TD({}, box(32, 10)))));
add("rowspan/constrained-rows", T({}, TR({ height: 20 }, TD({ rowSpan: 3 }, box(40, 150)), TD({}, box(60, 10))), TR({}, TD({}, box(30, 10))), TR({ height: 30 }, TD({}, box(30, 20)))));

// ---------------------------------------------------------------- vertical-align
for (const va of ["top", "middle", "bottom", "baseline"]) {
  add(`valign/${va}`, T({}, TR({}, TD({ verticalAlign: va }, box(40, 21)), TD({}, box(60, 50)), TD({ verticalAlign: va, padding: "3px 0 8px" }, box(10, 10)))));
  add(`valign/${va}-row-height`, T({}, TR({ height: 81 }, TD({ verticalAlign: va }, box(40, 20)), TD({ verticalAlign: va, padding: 5, ...bd(2) }, box(10, 10), box(10, 12)))));
}
add("valign/baseline-padding", T({}, TR({}, TD({ padding: "20px 0 0" }, box(40, 20)), TD({ padding: "0 0 15px" }, box(60, 30)), TD({}, box(10, 10)), TD({ ...bd(4) }, box(10, 10)))));
add("valign/baseline-flex", T({}, TR({}, TD({}, words(3, 20, 12)), TD({}, F({ alignItems: "flex-end", height: 40 }, F({ width: 10, height: 10 }), F({ width: 10, height: 25 }))), TD({}, box(10, 30)), TD({ padding: 6 }, words(2, 20, 8)))));
add("valign/baseline-wrapped", B({ width: 120 }, T({}, TR({}, TD({}, words(6, 20, 12)), TD({}, words(2, 20, 30)), TD({}, box(10, 5))))));
add("valign/baseline-nested-table", T({}, TR({}, TD({}, T({}, TR({}, TD({ padding: 4 }, box(10, 10))), TR({}, TD({}, box(10, 30))))), TD({}, box(20, 5)), TD({ padding: 9 }, box(20, 5)))));
add("valign/baseline-empty-cells", T({}, TR({}, TD({ padding: 9 }), TD({}, box(20, 30)), TD({ padding: "0 0 4px" }))));
add("valign/all-empty", T({ width: 60 }, TR({ height: 40 }, TD({ padding: 9 }), TD({ padding: "0 0 4px" }))));
add("valign/mixed", T({}, TR({}, TD({ verticalAlign: "top" }, box(10, 10)), TD({ verticalAlign: "middle" }, box(10, 15)), TD({ verticalAlign: "bottom" }, box(10, 20)), TD({}, box(10, 25)), TD({ padding: "13px 0" }, box(10, 31)))));
add("valign/middle-odd", T({}, TR({ height: 50.5 }, TD({ verticalAlign: "middle" }, box(10, 11)))));
add("valign/margins", T({}, TR({ height: 60 }, TD({ verticalAlign: "bottom" }, box(10, 10, { marginBottom: 7 }), box(10, 10, { marginTop: 12, marginBottom: 5 })), TD({}, box(10, 10, { marginTop: 9 })))));

// ---------------------------------------------------------------- captions
add("caption/top", T({}, CAP({}, box(50, 10)), TR({}, TD({}, box(120, 20)))));
add("caption/bottom", T({}, CAP({ captionSide: "bottom" }, box(50, 10)), TR({}, TD({}, box(120, 20)))));
add("caption/wide", B({ width: 300 }, T({}, CAP({}, box(200, 10)), TR({}, TD({}, box(60, 20)), TD({}, box(20, 20))))));
add("caption/words", B({ width: 300 }, T({}, CAP({}, words(12)), TR({}, TD({}, box(60, 20)), TD({}, box(20, 20))))));
add("caption/multi", T({ ...bd(2), padding: 3, borderSpacing: 2 }, CAP({ captionSide: "bottom", margin: 4 }, box(50, 10)), CAP({ margin: "3px 6px" }, box(50, 10)), TR({}, TD({}, box(120, 20))), CAP({ padding: 2, ...bd(1) }, box(30, 10)), CAP({ captionSide: "bottom" }, box(30, 12))));
add("caption/width-margin", T({}, CAP({ width: 40, margin: "0 auto" }, box(20, 10)), CAP({ width: 40, marginLeft: "auto" }, box(20, 10)), CAP({ width: "50%", marginRight: "auto" }, box(20, 10)), TR({}, TD({}, box(120, 20)))));
add("caption/only", B({ width: 300 }, T({}, CAP({}, box(50, 10))), box(5, 5)));
add("caption/only-padded", B({ width: 300 }, T({ padding: 40 }, CAP({}, box(50, 10))), box(5, 5)));
add("caption/table-height", T({ height: 100 }, CAP({}, box(50, 10)), TR({}, TD({}, box(120, 20))), CAP({ captionSide: "bottom" }, box(50, 15))));
add("caption/table-width", B({ width: 300 }, T({ width: 200 }, CAP({}, words(12)), TR({}, TD({}, box(60, 20))))));
add("caption/margin-pct", B({ width: 300 }, T({ width: 200 }, CAP({ margin: "5%" }, box(20, 10)), TR({}, TD({}, box(60, 20))))));

// ---------------------------------------------------------------- header / footer groups
add("groups/order", T({}, TF({}, TR({}, TD({}, box(40, 10)))), TB({}, TR({}, TD({}, box(50, 20)))), TH({}, TR({}, TD({}, box(60, 30))))));
add("groups/multiple", T({ borderSpacing: 2 }, TF({}, TR({}, TD({}, box(40, 10)))), TF({}, TR({}, TD({}, box(41, 11)))), TB({}, TR({}, TD({}, box(50, 20)))), TH({}, TR({}, TD({}, box(60, 30)))), TH({}, TR({}, TD({}, box(61, 31))))));
add("groups/rowspan-per-section", T({}, TH({}, TR({}, TD({ rowSpan: 3 }, box(10, 50)), TD({}, box(60, 10)))), TB({}, TR({}, TD({}, box(50, 20)), TD({}, box(50, 20)))), TF({}, TR({}, TD({}, box(50, 20))))));
add("groups/empty-sections", T({ borderSpacing: 4 }, TB({}), TB({}, TR({}, TD({}, box(50, 20)))), TB({ height: 30 }), TB({}, TR({})), TF({})));
add("groups/baseline-footer-first", F({ alignItems: "baseline", width: 300 }, T({}, TF({}, TR({}, TD({}, box(40, 10)))), TB({}, TR({}, TD({ padding: 6 }, box(50, 20))))), box(10, 40)));

// ---------------------------------------------------------------- visibility: collapse
add("vcollapse/row", T({ borderSpacing: 2 }, TR({}, TD({}, box(20, 20))), TR({ visibility: "collapse" }, TD({}, box(30, 25))), TR({}, TD({}, box(20, 20)))));
add("vcollapse/first-row", T({ borderSpacing: 2 }, TR({ visibility: "collapse" }, TD({}, box(30, 25))), TR({}, TD({}, box(20, 20))), TR({}, TD({}, box(20, 20)))));
add("vcollapse/section", T({}, TB({ visibility: "collapse" }, TR({}, TD({}, box(30, 25))), TR({}, TD({}, box(30, 25)))), TB({}, TR({}, TD({}, box(20, 20))))));
add("vcollapse/row-table-height", T({ height: 100, borderSpacing: 2 }, TR({}, TD({}, box(20, 20))), TR({ visibility: "collapse" }, TD({}, box(30, 25))), TR({}, TD({}, box(20, 20)))));
add("vcollapse/rowspan", T({}, TR({}, TD({ rowSpan: 3 }, box(20, 90)), TD({}, box(20, 20))), TR({ visibility: "collapse" }, TD({}, box(30, 25))), TR({}, TD({}, box(20, 20)))));
add("vcollapse/col", T({ borderSpacing: 2 }, COL({}), COL({ visibility: "collapse" }), COL({}), TR({}, TD({}, box(20, 20)), TD({}, box(30, 20)), TD({}, box(40, 20))), TR({}, TD({ colSpan: 2 }, box(60, 10)), TD({}, box(10, 10)))));
add("vcollapse/row-valign", T({}, TR({ visibility: "collapse" }, TD({ verticalAlign: "middle", ...bd(2) }, box(10, 8)), TD({ verticalAlign: "bottom" }, box(10, 14)), TD({}, box(10, 5))), TR({}, TD({}, box(20, 20)))));
add("vcollapse/col-content-wraps", T({}, COL({ visibility: "collapse" }), TR({}, TD({ verticalAlign: "middle" }, words(2, 15, 8)), TD({}, box(10, 21)))));
add("vcollapse/col-baseline", T({ ...bd(1) }, COL({ visibility: "collapse" }), TR({}, TD({}, F({ flexWrap: "wrap" }, F({ width: 15 }), F({ width: 15, height: 14 }))), TD({}, box(10, 5)))));
add("vcollapse/col-width", B({ width: 300 }, T({ width: 200 }, COL({ visibility: "collapse" }), TR({}, TD({}, box(20, 20)), TD({}, box(30, 20)), TD({}, box(40, 20))))));

// ---------------------------------------------------------------- anonymous boxes
add("anon/cells-in-table", T({}, TD({}, box(20, 20)), TD({}, box(30, 20)), box(40, 10), TR({}, box(10, 10), box(12, 12), TD({}, box(5, 5)))));
add("anon/rows-in-table", T({ borderSpacing: 3 }, TR({}, TD({}, box(20, 20))), TR({}, TD({}, box(30, 10))), CAP({}, box(10, 10)), TR({}, TD({}, box(15, 15))), TB({}, TR({}, TD({}, box(25, 5)))), TD({}, box(6, 6))));
add("anon/blocks-in-table", T({}, box(40, 10), box(50, 20), words(4)));
add("anon/blocks-in-row", T({}, TR({}, box(40, 10), TD({}, box(20, 30)), box(50, 20), words(4))));
add("anon/blocks-in-section", T({}, TB({}, box(40, 10), TD({}, box(20, 30)), TR({}, TD({}, box(5, 5)), TD({}, box(5, 5))), box(50, 20), words(4))));
add("anon/margins", T({}, TR({}, box(40, 10, { margin: 5 }), box(30, 10, { margin: "8px 0 3px 4px" }), TD({}, box(20, 60)), box(20, 10, { margin: "0 auto" }))));
add("anon/flex-fills", B({ width: 300 }, T({ width: 200 }, TR({}, F({ height: 20 }, F({ flexGrow: 1 }), F({ width: 20 })), TD({}, box(20, 30))))));
add("anon/pct-width", B({ width: 300 }, T({ width: 200 }, TR({}, B({ width: "50%", height: 10 }), TD({}, box(20, 30))))));
add("anon/nested-table", T({}, TR({}, T({ borderSpacing: 2 }, TR({}, TD({}, box(10, 10)), TD({}, box(20, 10)))), TD({}, box(20, 30)))));
add("anon/words", B({ width: 150 }, T({}, TR({}, words(8), TD({}, words(5, 20))))));
add("anon/none-children", T({}, c({ display: "none" }, box(5, 5)), TR({}, c({ display: "none", width: 9 }), TD({}, box(20, 20)), c({ display: "none" })), TB({}, c({ display: "none" }), TR({}, TD({}, box(30, 10))))));
add("anon/row-in-row", T({}, TR({}, TR({}, TD({}, box(20, 20)), TD({}, box(30, 20))), TD({}, box(10, 10)))));
add("anon/section-in-row", T({}, TR({}, TB({}, TR({}, TD({}, box(20, 20)))), CAP({}, box(9, 9)), TD({}, box(10, 10)))));

// ---------------------------------------------------------------- stray parts
add("stray/row-in-block", B({ width: 300 }, box(10, 10), TR({}, TD({}, box(20, 20)), TD({}, box(30, 10))), box(10, 10)));
add("stray/section-in-block", B({ width: 300 }, box(10, 10), TB({}, TR({}, TD({}, box(20, 20)), TD({}, box(30, 10))), TR({}, TD({}, box(40, 20)))), box(10, 10)));
add("stray/row-height", B({ width: 300 }, TR({ height: 50 }, TD({ verticalAlign: "middle" }, box(20, 20)), TD({}, box(30, 10)))));
add("stray/row-anon-cells", B({ width: 300 }, TR({}, box(20, 20), TD({}, box(30, 10)))));
add("stray/row-in-flex", F({ width: 300 }, TR({}, TD({}, box(20, 20)), TD({}, box(30, 10))), box(10, 10)));
add("stray/rows-adjacent", B({ width: 300 }, TR({}, TD({}, box(20, 20))), TR({}, TD({}, box(30, 20)))));
add("stray/cell-in-block", B({ width: 300 }, TD({}, box(20, 20)), box(10, 10)));

// ---------------------------------------------------------------- empty tables
add("empty/table", B({ width: 300 }, T({}), box(5, 5)));
add("empty/table-sized", B({ width: 300 }, T({ width: 100, height: 50, ...bd(2), padding: 3 }), box(5, 5)));
add("empty/table-padded", B({ width: 300 }, T({ ...bd(2), padding: 3, borderSpacing: 4 }), box(5, 5)));
add("empty/rows", B({ width: 300 }, T({ ...bd(2), borderSpacing: 4 }, TR({}), TR({})), box(5, 5)));
add("empty/rows-height", B({ width: 300 }, T({ borderSpacing: 4, width: 50 }, TR({ height: 20 }), TR({})), box(5, 5)));
add("empty/section", B({ width: 300 }, T({ ...bd(2), borderSpacing: 4, minWidth: 30 }, TB({})), box(5, 5)));
add("empty/cells", B({ width: 300 }, T({ borderSpacing: 4 }, TR({}, TD({}), TD({ padding: 3 }))), box(5, 5)));

// ---------------------------------------------------------------- tables in other formatting contexts
add("ctx/flex-row", F({ width: 300, height: 100 }, T({}, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), box(10, 10)));
add("ctx/flex-row-grow", F({ width: 300 }, T({ flexGrow: 1 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), box(10, 10)));
add("ctx/flex-row-shrink", F({ width: 100 }, T({}, TR({}, TD({}, words(4)), TD({}, words(6)))), box(40, 10, { flexShrink: 0 })));
add("ctx/flex-row-center", F({ width: 300, height: 100, alignItems: "center", justifyContent: "center" }, T({}, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));
add("ctx/flex-column", F({ width: 300, flexDirection: "column" }, T({}, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), box(10, 10)));
add("ctx/flex-column-start", F({ width: 300, flexDirection: "column", alignItems: "flex-start" }, T({}, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), box(10, 10)));
add("ctx/flex-column-grow", F({ width: 300, height: 200, flexDirection: "column" }, T({ flexGrow: 1 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))), TR({}, TD({}, box(40, 20)))), box(10, 10)));
add("ctx/flex-width", F({ width: 300 }, T({ width: 150, height: 80 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));
add("ctx/flex-row-height-below-content", F({ width: 300 }, T({ height: 30 }, TR({}, TD({}, box(40, 60)))), box(7, 7)));
add("ctx/flex-row-height-caption", F({ width: 300 }, T({ height: 50 }, CAP({}, box(30, 10)), TR({}, TD({}, box(40, 20)))), box(7, 7)));
add("ctx/flex-row-stretch-below-content", F({ width: 300, height: 40 }, T({}, TR({}, TD({}, box(40, 60)))), box(7, 7)));
add("ctx/flex-column-height-below-content", F({ width: 300, flexDirection: "column" }, T({ height: 30 }, TR({}, TD({}, box(40, 60)))), box(7, 7)));
add("ctx/flex-column-width-below-min", F({ width: 300, flexDirection: "column" }, T({ width: 50 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), box(7, 7)));
add("ctx/flex-column-collapsed-col", F({ width: 300, flexDirection: "column" }, T({ ...bd(1) }, COL({ width: "20%", visibility: "collapse" }), TR({}, TD({}, box(10, 10)), TD({}, box(20, 10))))));
add("ctx/flex-column-center-pct-col", F({ width: 300, flexDirection: "column", alignItems: "center" }, T({ ...bd(1) }, TR({}, TD({ width: "20%" }, box(10, 10)), TD({}, box(60, 10))))));
add("ctx/grid-track-below-min", G({ width: 300, gridTemplateColumns: "50px 1fr", gridTemplateRows: "20px" }, T({}, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), box(7, 7)));
add("ctx/grid-pct-height", G({ width: 300 }, T({ height: "80%" }, CAP({}, box(30, 14)), TR({}, TD({}, box(40, 5))))));
add("ctx/grid-collapsed-col", G({ width: 300, gridTemplateColumns: "200px 1fr" }, T({ ...bd(1) }, COL({ width: "20%", visibility: "collapse" }), TR({}, TD({}, box(10, 10)), TD({}, box(20, 10)))), box(5, 5)));
add("ctx/flex-column-center-width-below-min", F({ width: 300, flexDirection: "column", alignItems: "center" }, T({ width: 50 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));
add("ctx/flex-row-shrink-collapsed-border", F({ width: 200 }, box(20, 20), T({ ...C }, TR({}, TD({ ...bd(4) }, words(4)), TD({ padding: 5 }, words(6))))));
add("ctx/flex-width-below-min", F({ width: 300 }, T({ width: 50 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));
add("ctx/grid", G({ width: 300, gridTemplateColumns: "1fr 1fr" }, T({}, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30)))), T({ justifySelf: "center" }, TR({}, TD({}, box(40, 20))))));
add("ctx/grid-stretch", G({ width: 300, height: 120, gridTemplateColumns: "100px 1fr" }, T({}, TR({}, TD({}, box(40, 20)))), T({}, TR({}, TD({}, words(4))), TR({}, TD({}, box(10, 10))))));
add("ctx/block-auto-margins", B({ width: 300 }, T({ margin: "0 auto" }, TR({}, TD({}, box(40, 20)))), T({ marginLeft: "auto" }, TR({}, TD({}, box(40, 20))))));
add("ctx/block-margins-collapse", B({ width: 300 }, box(10, 10, { marginBottom: 12 }), T({ margin: "8px 0" }, TR({}, TD({}, box(40, 20)))), box(10, 10, { marginTop: 5 })));
add("ctx/absolute", B({ width: 300, height: 200, position: "relative" }, T({ position: "absolute", top: 10, left: 20 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));
add("ctx/absolute-stretch", B({ width: 300, height: 200, position: "relative" }, T({ position: "absolute", top: 10, left: 20, right: 30, bottom: 5 }, TR({}, TD({}, box(40, 20)), TD({}, box(60, 30))))));
add("ctx/in-cell-pct", B({ width: 300 }, T({ width: 200 }, TR({}, TD({}, T({ width: "100%" }, TR({}, TD({}, box(10, 10)), TD({}, box(20, 10))))), TD({}, box(20, 30))))));
add("ctx/nested", B({ width: 300 }, T({ borderSpacing: 2, ...bd(1) }, TR({}, TD({ padding: 3 }, T({ borderSpacing: 1 }, TR({}, TD({}, words(3)), TD({}, box(20, 10))), TR({}, TD({ colSpan: 2 }, box(70, 5))))), TD({ verticalAlign: "middle" }, T({}, TR({}, TD({}, box(8, 8)))))))));
add("ctx/cell-children", B({ width: 300 }, T({ width: 200 }, TR({}, TD({}, B({ width: "50%", height: 10 }), F({ height: 10 }, F({ flexGrow: 1 }), F({ width: 5 })), box(10, 10, { margin: "0 auto" })), TD({ width: 40 }, box(20, 30))))));
add("ctx/cell-abs-child", T({}, TR({}, TD({ position: "relative", padding: 4 }, box(40, 30), c({ display: "block", position: "absolute", right: 0, bottom: 0, width: 10, height: 10 })), TD({}, box(20, 50)))));
add("ctx/cell-margin-ignored", T({}, TR({}, TD({ margin: 10 }, box(40, 30)), TD({ marginLeft: 20 }, box(20, 50)))));
add("ctx/row-padding-ignored", T({}, TB({ padding: 9, ...bd(2) }, TR({ padding: 10, ...bd(3), margin: 4 }, TD({}, box(40, 30)), TD({}, box(20, 50))))));

// ---------------------------------------------------------------- known takumi deviations from Blink
// The first baseline of a table whose first row has no baseline-aligned content is the bottom of that row's
// content box; takumi's measure pass reports it for the row at its minimum height (before the table / section
// height or a rowspan grows the row), so a consumer that measures and then lays out sees two baselines.
add("quirk/nested-height-fallback-baseline", B({ width: 300 }, T({}, TR({}, TD({}, T({ height: 80 }, TR({}, TD({ verticalAlign: "middle" }, box(10, 10)))))))));
add("quirk/flex-baseline-table-height", F({ alignItems: "baseline", width: 300 }, T({ height: 80 }, TR({}, TD({ verticalAlign: "middle" }, box(10, 10)))), box(20, 20)));

// ---------------------------------------------------------------- seeded random nested table trees
let seed = +(process.env.SEED || 4242);
const NT = +(process.env.NT || 60);
const rnd = () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (...xs) => xs[Math.floor(rnd() * xs.length)];
const maybe = (p, v) => (rnd() < p ? v : {});
function randContent(depth) {
  const k = rnd();
  if (depth > 0 && k < 0.12) return randTable(depth - 1, false);
  if (k < 0.45) return words(1 + Math.floor(rnd() * 7), pick(15, 20, 30), pick(8, 10, 14), maybe(0.2, { gap: pick(2, 3) }));
  if (k < 0.55) return B({ ...maybe(0.5, { width: pick("50%", "100%", 30) }), height: pick(8, 15, 22), ...maybe(0.3, { margin: pick(2, "3px 5px", "0 auto") }) });
  if (k < 0.62) return F({ height: pick(10, 18) }, F({ flexGrow: 1 }), F({ width: pick(8, 14) }));
  return box(pick(10, 20, 35, 50.5, 70), pick(8, 12, 20, 33.25));
}
function randCell(depth, collapse) {
  const style = {
    ...maybe(0.3, { padding: pick(2, 4, "1px 6px", "3px 2px 5px 1px") }),
    ...maybe(collapse ? 0.6 : 0.25, bd(pick(1, 2, 3, 5))),
    ...maybe(0.25, { width: pick(30, 60, 90, "20%", "35%", "50%") }),
    ...maybe(0.15, { height: pick(20, 40, 55) }),
    ...maybe(0.12, { minWidth: pick(20, 50) }),
    ...maybe(0.1, { maxWidth: pick(40, 80) }),
    ...maybe(0.4, { verticalAlign: pick("top", "middle", "bottom", "baseline") }),
    ...maybe(0.15, { colSpan: pick(2, 2, 3) }),
    ...maybe(0.12, { rowSpan: pick(2, 2, 3) }),
    ...maybe(0.05, { boxSizing: "content-box" }),
  };
  const n = rnd() < 0.08 ? 0 : 1 + Math.floor(rnd() * 2.2);
  return TD(style, ...Array.from({ length: n }, () => randContent(depth)));
}
function randRow(depth, cols, collapse) {
  const n = Math.max(1, cols + pick(0, 0, 0, -1, 1));
  return TR({ ...maybe(0.15, { height: pick(20, 35, 50) }), ...maybe(collapse ? 0.2 : 0, bd(pick(2, 4))) }, ...Array.from({ length: n }, () => randCell(depth, collapse)));
}
function randTable(depth, isRoot) {
  const collapse = rnd() < 0.25;
  const style = {
    ...maybe(0.45, { width: pick(120, 180, 250, "100%", "70%") }),
    ...maybe(0.2, { height: pick(80, 120, 160) }),
    ...maybe(0.35, { borderSpacing: pick(1, 2, 4, "3px 6px") }),
    ...maybe(0.35, bd(pick(1, 2, 4))),
    ...maybe(0.2, { padding: pick(2, 5) }),
    ...maybe(0.15, { tableLayout: "fixed" }),
    ...maybe(0.1, { margin: pick(3, "0 auto") }),
    ...(collapse ? C : {}),
  };
  const cols = 1 + Math.floor(rnd() * 4);
  const rows = 1 + Math.floor(rnd() * 4);
  const kids = [];
  if (rnd() < 0.2) kids.push(CAP({ ...maybe(0.3, { captionSide: "bottom" }), ...maybe(0.3, { margin: pick(2, 4) }) }, randContent(0)));
  if (rnd() < 0.15) for (let i = 0; i < cols; i++) kids.push(COL({ ...maybe(0.6, { width: pick(30, 50, "25%") }) }));
  const body = Array.from({ length: rows }, () => randRow(depth, cols, collapse));
  const k = rnd();
  if (k < 0.5) kids.push(...body);
  else if (k < 0.8) kids.push(TB({}, ...body));
  else {
    // (first in layout order: the header, else the first body row, else the footer row)
    const hdr = rnd() < 0.5 ? randRow(depth, cols, collapse) : null;
    kids.push(TF({}, body[body.length > 1 || hdr ? body.length - 1 : 0]));
    if (body.length > 1) kids.push(TB({ ...maybe(0.3, { height: pick(60, 100) }) }, ...body.slice(0, -1)));
    if (hdr) { kids.push(TH({}, hdr)); body.unshift(hdr); }
  }
  if (!isRoot) {
    // takumi reports a nested table's baseline from its measure pass (first row at its minimum height, a known
    // takumi deviation from Blink when that row has no baseline-aligned content and grows later, see
    // quirk/*): keep the random trees clear of it
    const first = body[0].children[0];
    delete first.style.verticalAlign;
    if (!first.children.length) first.children.push(box(10, 10));
  }
  const t = T(style, ...kids);
  return isRoot ? B({ width: pick(200, 300, 333, 401) }, t) : t;
}
for (let i = 0; i < NT; i++) add(`rand/table-${i}`, randTable(2, true));

// odd structures: anonymous rows / cells, column boxes with spans, collapsed rows and columns, percentage
// heights, tables as flex / grid items
const NX = +(process.env.NX || 40);
function randOdd() {
  const collapse = rnd() < 0.2;
  const cols = 1 + Math.floor(rnd() * 4);
  const cell = () => TD({ ...maybe(0.2, { padding: pick(2, 5) }), ...maybe(collapse ? 0.5 : 0.15, bd(pick(1, 2, 4))), ...maybe(0.2, { width: pick(40, "30%", 70) }), ...maybe(0.15, { height: pick(25, "40%", 50) }), ...maybe(0.3, { verticalAlign: pick("top", "middle", "bottom") }), ...maybe(0.12, { colSpan: 2 }), ...maybe(0.1, { rowSpan: 2 }) },
    ...(rnd() < 0.1 ? [] : [rnd() < 0.2 ? B({ height: pick("50%", "100%", 12), width: pick(20, 30) }) : randContent(0)]));
  const loose = () => (rnd() < 0.5 ? randContent(0) : box(pick(15, 25, 40), pick(8, 14, 21), maybe(0.3, { margin: pick(2, "4px 1px", "0 auto") })));
  const row = () => TR({ ...maybe(0.15, { height: pick(20, "30%", 45) }), ...maybe(0.08, { visibility: "collapse" }), ...maybe(collapse ? 0.2 : 0, bd(pick(2, 3))) },
    ...Array.from({ length: Math.max(1, cols + pick(0, 0, -1, 1)) }, () => (rnd() < 0.12 ? loose() : cell())));
  const kids = [];
  if (rnd() < 0.3) {
    let left = cols;
    while (left > 0) {
      const span = Math.min(left, pick(1, 1, 2));
      const col = () => COL({ ...maybe(0.5, { width: pick(25, 45, "20%", "40%") }), ...(span > 1 ? { colSpan: span } : {}), ...maybe(0.1, { visibility: "collapse" }), ...maybe(collapse ? 0.3 : 0, bd(pick(1, 3))) });
      kids.push(rnd() < 0.25 ? CG({ ...maybe(0.4, { width: pick(30, 60) }) }, col()) : col());
      left -= span;
    }
  }
  if (rnd() < 0.25) kids.push(CAP({ ...maybe(0.4, { captionSide: "bottom" }), ...maybe(0.3, { width: pick(40, "50%") }), ...maybe(0.3, { margin: pick(3, "0 auto") }) }, randContent(0)));
  const n = 1 + Math.floor(rnd() * 4);
  for (let i = 0; i < n; i++) {
    const k = rnd();
    if (k < 0.55) kids.push(row());
    else if (k < 0.7) kids.push(cell(), cell());
    else if (k < 0.8) kids.push(loose());
    else kids.push(c({ display: pick("table-row-group", "table-row-group", "table-header-group", "table-footer-group"), ...maybe(0.2, { height: pick(40, "30%", 70) }), ...maybe(0.08, { visibility: "collapse" }) }, row(), ...(rnd() < 0.5 ? [row()] : []), ...(rnd() < 0.15 ? [cell()] : [])));
  }
  const t = T({ ...maybe(0.4, { width: pick(150, 220, "100%", "60%") }), ...maybe(0.3, { height: pick(90, 140, "80%") }), ...maybe(0.3, { borderSpacing: pick(2, "1px 5px") }), ...maybe(0.3, bd(pick(1, 3))), ...maybe(0.15, { padding: 3 }), ...maybe(0.12, { tableLayout: "fixed" }), ...maybe(0.1, { minHeight: 60 }), ...(collapse ? C : {}) }, ...kids);
  const k = rnd();
  if (k < 0.5) return B({ width: pick(240, 320), ...maybe(0.4, { height: 200 }) }, box(20, 6), t, box(20, 6));
  if (k < 0.65) {
    // (a column flex container aligns an item with a `width` by that width; a table may be wider, see
    // ctx/flex-column-center-width-below-min)
    const al = pick("flex-start", "center", "stretch");
    if (al === "center") delete t.style.width;
    return F({ width: pick(240, 320), flexDirection: "column", alignItems: al }, t, box(20, 6));
  }
  if (k < 0.8) {
    // (a row flex container takes its item's cross size from the `height` style and its minimum main size from
    // min(content, `width`): for a table both are only minimums, see ctx/flex-row-*; kept out of the random trees)
    for (const key of ["width", "height", "minHeight"]) delete t.style[key];
    return F({ width: pick(300, 380), alignItems: pick("flex-start", "center", "stretch", "flex-end") }, box(20, 30), t);
  }
  if (k < 0.9) return G({ width: 320, gridTemplateColumns: "1fr auto" }, t, box(20, 6));
  return t;
}
for (let i = 0; i < NX; i++) add(`rand/odd-${i}`, randOdd());

// ---------------------------------------------------------------- run the oracle
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const out = [];
  for (const cs of cases) {
    try {
      out.push({ ...cs, expect: await oracle(cs.node, cs.vp) });
    } catch (e) {
      console.error("skip", cs.name, e.message);
    }
  }
  const only = process.argv[2];
  if (only) {
    for (const o of out) if (o.name.includes(only)) console.log(JSON.stringify(o, null, 1));
  } else {
    // (OUT=<path> writes elsewhere: fuzzing with other SEED / NT values)
    writeFileSync(process.env.OUT || new URL("../../../src/layout/testdata/oracle_table.json", import.meta.url), JSON.stringify(out));
    console.log("wrote", out.length, "cases");
  }
}
