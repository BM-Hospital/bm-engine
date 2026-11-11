// Generates src/layout/testdata/oracle.json: small container trees + takumi's (Blink-LayoutNG port) layout results.
// Usage: node gen.mjs            (run from bench/probe/layout)
import { Renderer } from "@takumi-rs/wasm/node";
import { writeFileSync } from "node:fs";

const r = new Renderer();
const cases = [];
const c = (style, ...children) => ({ style, children });
const F = (style, ...ch) => c({ display: "flex", ...style }, ...ch);
const B = (style, ...ch) => c({ display: "block", ...style }, ...ch);
const G = (style, ...ch) => c({ display: "grid", ...style }, ...ch);
const box = (w, h, extra = {}) => F({ width: w, height: h, ...extra });
const add = (name, node, vp = [400, 300]) => cases.push({ name, vp, node });

// "text-like" content: a wrapping flex row of fixed boxes (min-content = widest box, max-content = sum)
const words = (n, w = 30, h = 10, extra = {}) => F({ flexWrap: "wrap", ...extra }, ...Array.from({ length: n }, () => box(w, h, { flexShrink: 0 })));

// ---------------------------------------------------------------- flex basics
for (const dir of ["row", "column", "row-reverse", "column-reverse"]) {
  add(`flex/dir-${dir}`, F({ flexDirection: dir, width: 300, height: 200 }, box(50, 40), box(60, 30), box(70.5, 20)));
  add(`flex/dir-${dir}-gap-pad`, F({ flexDirection: dir, width: 300, height: 200, gap: 8, padding: 10, borderWidth: 3, borderStyle: "solid" }, box(50, 40), box(60, 30), box(70, 20)));
  for (const jc of ["flex-start", "flex-end", "center", "space-between", "space-around", "space-evenly", "start", "end"]) {
    add(`flex/justify-${dir}-${jc}`, F({ flexDirection: dir, justifyContent: jc, width: 300, height: 200, gap: 5 }, box(50, 40), box(60, 30), box(70, 20)));
  }
  for (const ai of ["flex-start", "flex-end", "center", "stretch", "baseline", "start", "end"]) {
    add(`flex/align-${dir}-${ai}`, F({ flexDirection: dir, alignItems: ai, width: 300, height: 200 }, box(50, 40), F({ width: 60 }), F({ height: 20 }), F({}, box(10, 10))));
  }
  add(`flex/overflow-justify-${dir}`, F({ flexDirection: dir, justifyContent: "center", width: 100, height: 100 }, box(80, 80, { flexShrink: 0 }), box(80, 80, { flexShrink: 0 })));
  add(`flex/overflow-between-${dir}`, F({ flexDirection: dir, justifyContent: "space-between", width: 100, height: 100 }, box(80, 80, { flexShrink: 0 }), box(80, 80, { flexShrink: 0 })));
  add(`flex/overflow-around-${dir}`, F({ flexDirection: dir, justifyContent: "space-around", width: 100, height: 100 }, box(80, 80, { flexShrink: 0 }), box(80, 80, { flexShrink: 0 })));
}
add("flex/grow-1-1-1", F({ width: 100, height: 50 }, F({ flexGrow: 1 }), F({ flexGrow: 1 }), F({ flexGrow: 1 })));
add("flex/grow-1-2-3", F({ width: 307, height: 50, gap: 3.5 }, F({ flexGrow: 1 }), F({ flexGrow: 2 }), F({ flexGrow: 3, width: 20 })));
add("flex/grow-fraction", F({ width: 300, height: 50 }, F({ flexGrow: 0.2, width: 50 }), F({ flexGrow: 0.3, width: 50 })));
add("flex/grow-max", F({ width: 300, height: 50 }, F({ flexGrow: 1, maxWidth: 60 }), F({ flexGrow: 1 }), F({ flexGrow: 1, minWidth: 150 })));
add("flex/shrink", F({ width: 200, height: 50 }, box(100, 20), box(150, 20), box(50, 20, { flexShrink: 0 })));
add("flex/shrink-weights", F({ width: 200, height: 50 }, box(100, 20, { flexShrink: 2 }), box(150, 20, { flexShrink: 1 }), box(100, 20, { flexShrink: 3 })));
add("flex/shrink-min", F({ width: 200, height: 50 }, box(150, 20, { minWidth: 120 }), box(150, 20), box(100, 20)));
add("flex/shrink-fraction", F({ width: 200, height: 50 }, box(150, 20, { flexShrink: 0.2 }), box(150, 20, { flexShrink: 0.3 })));
add("flex/shrink-padding", F({ width: 200, height: 50 }, box(150, 20, { padding: 20 }), box(150, 20, { padding: "0 40px" }), box(100, 20)));
add("flex/shrink-content-min", F({ width: 100, height: 50 }, F({}, box(80, 10)), F({}, box(80, 10)), box(50, 10)));
add("flex/shrink-content-min-overflow", F({ width: 100, height: 50 }, F({ overflow: "hidden" }, box(80, 10)), F({}, box(80, 10)), box(50, 10)));
add("flex/shrink-min-size-clamped", F({ width: 100, height: 50 }, F({ width: 60 }, box(80, 10)), F({ maxWidth: 30 }, box(80, 10)), box(50, 10)));
add("flex/basis-px", F({ width: 300, height: 50 }, F({ flexBasis: 100 }), F({ flexBasis: 50, width: 200 }), F({ flexBasis: "20%" })));
add("flex/basis-0-grow", F({ width: 300, height: 50 }, F({ flexBasis: 0, flexGrow: 1 }, box(40, 10)), F({ flexBasis: 0, flexGrow: 1 }, box(100, 10)), F({ flexBasis: 0, flexGrow: 2 })));
add("flex/basis-col", F({ flexDirection: "column", width: 100, height: 300 }, F({ flexBasis: 100 }), F({ flexBasis: 50, height: 200 }), F({ flexBasis: "20%" })));
add("flex/basis-content-box", F({ width: 300, height: 50 }, F({ flexBasis: 100, padding: 10, boxSizing: "content-box" }), F({ width: 50, padding: 10, borderWidth: 2, borderStyle: "solid", boxSizing: "content-box" })));
add("flex/auto-container-row", F({ flexDirection: "row" }, box(50, 40), box(60, 30)));
add("flex/auto-container-col", F({ flexDirection: "column" }, box(50, 40), box(60, 30)));
add("flex/nested-auto", F({ width: 300 }, F({ flexDirection: "column", padding: 5 }, box(50, 40), box(60, 30)), F({ flexGrow: 1 }, F({ flexGrow: 1 }, box(10, 77)))));
add("flex/nested-stretch", F({ width: 300, height: 200, flexDirection: "column" }, F({}, box(50, 40), F({ flexGrow: 1 })), F({ flexGrow: 1 }, F({ flexGrow: 1 }), F({ width: 20 }))));
add("flex/inline-shrink-to-fit", F({ width: 300, height: 200, flexDirection: "column", alignItems: "flex-start" }, F({}, box(50, 40), box(60, 30)), F({ padding: 7 }, box(500, 40, { flexShrink: 0 })), F({ padding: 7 }, box(500, 40))));
add("flex/col-center-children", F({ width: 300, height: 200, flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 10 }, F({}, box(50, 40), box(60, 30)), F({ padding: 7 }, box(100, 40))));

// wrap
for (const wrap of ["wrap", "wrap-reverse"]) {
  for (const dir of ["row", "column", "row-reverse"]) {
    add(`flex/${wrap}-${dir}`, F({ flexDirection: dir, flexWrap: wrap, width: 200, height: 200, gap: 10 }, box(80, 40), box(80, 50), box(80, 30), box(80, 60), box(80, 20)));
    add(`flex/${wrap}-${dir}-auto-cross`, F({ flexDirection: dir, flexWrap: wrap, ...(dir === "column" ? { height: 200 } : { width: 200 }), columnGap: 10, rowGap: 4 }, box(80, 40), box(80, 50), box(80, 30), box(80, 60), box(80, 20)));
  }
  for (const ac of ["flex-start", "flex-end", "center", "stretch", "space-between", "space-around", "space-evenly"]) {
    add(`flex/${wrap}-align-content-${ac}`, F({ flexWrap: wrap, alignContent: ac, width: 200, height: 300, gap: 6 }, box(80, 40), box(80, 50), F({ width: 80 }), box(80, 60), box(80, 20)));
  }
  add(`flex/${wrap}-grow`, F({ flexWrap: wrap, width: 200, height: 200 }, box(80, 40, { flexGrow: 1 }), box(80, 50, { flexGrow: 1 }), box(80, 30, { flexGrow: 1 }), F({ width: 80, flexGrow: 2 }), F({ width: 80 })));
  add(`flex/${wrap}-align-items`, F({ flexWrap: wrap, alignItems: "center", width: 200, height: 200 }, box(80, 40), box(80, 50), box(80, 30, { alignSelf: "flex-end" }), box(80, 60, { alignSelf: "flex-start" }), box(80, 20, { alignSelf: "stretch" })));
}
add("flex/wrap-exact-fit", F({ flexWrap: "wrap", width: 200 }, box(100, 40), box(100, 50), box(100, 30)));
add("flex/wrap-margin", F({ flexWrap: "wrap", width: 200 }, box(90, 40, { margin: 5 }), box(90, 50, { margin: 5 }), box(90, 30, { margin: 5 })));
add("flex/wrap-min-height", F({ flexWrap: "wrap", width: 200, minHeight: 200 }, box(120, 40), box(120, 50)));
add("flex/wrap-in-column", F({ flexDirection: "column", width: 200 }, words(7), words(3, 50, 20, { gap: 5 })));
add("flex/wrap-in-row", F({ width: 200 }, words(7), box(50, 20, { flexShrink: 0 })));
add("flex/wrap-in-row-two", F({ width: 200 }, words(7), words(5, 40)));
add("flex/wrap-in-center", F({ width: 200, flexDirection: "column", alignItems: "center" }, words(3), words(12)));
add("flex/wrap-max-width", F({ flexWrap: "wrap", maxWidth: 150, flexDirection: "row" }, box(60, 10), box(60, 10), box(60, 10)), [400, 300]);
add("flex/wrap-col-max-height", F({ width: 300, height: 200 }, F({ flexWrap: "wrap", maxHeight: 100, flexDirection: "column" }, box(60, 40), box(60, 40), box(60, 40))));

// sizes: min/max/percent/aspect
add("flex/percent-sizes", F({ width: 300, height: 200, padding: 10 }, F({ width: "50%", height: "50%" }), F({ width: "25%", minHeight: "10%", maxWidth: "10%" })));
add("flex/percent-indefinite-height", F({ width: 300, flexDirection: "column" }, F({ height: "50%" }, box(20, 30)), box(10, 10)));
add("flex/percent-padding-margin", F({ width: 300, height: 200 }, F({ width: 100, padding: "10%", margin: "5%" }), F({ flexGrow: 1, marginLeft: "10%" })));
add("flex/percent-gap", F({ width: 300, height: 200, gap: "10%", flexWrap: "wrap" }, box(100, 50), box(100, 50), box(100, 50)));
add("flex/percent-of-stretched", F({ width: 300, height: 200 }, F({ width: 100 }, F({ width: "50%", height: "50%" }))));
add("flex/percent-nested-auto", F({ width: 300 }, F({ flexGrow: 1 }, F({ width: "50%", height: 20 })), F({}, F({ width: "50%", height: 20 }, box(30, 5)))));
add("flex/min-max-container", F({ minWidth: 100, maxWidth: 200, minHeight: 50, flexDirection: "column", alignSelf: "flex-start" }, box(20, 20)));
add("flex/min-max-items", F({ width: 300, height: 200 }, F({ width: 50, minWidth: 80, height: 300, maxHeight: 150 }), F({ width: 200, maxWidth: 100, minHeight: 250 })));
add("flex/max-height-content", F({ width: 300, flexDirection: "column", maxHeight: 100 }, box(50, 80), box(50, 80)));
add("flex/min-height-stretch", F({ width: 300, minHeight: 100 }, F({ width: 50 }), box(50, 20)));
add("flex/min-height-col-grow", F({ width: 300, minHeight: 100, flexDirection: "column" }, F({ flexGrow: 1 }), box(50, 20)));
add("flex/max-width-col-stretch", F({ width: 300, flexDirection: "column" }, F({ maxWidth: 100, height: 20 }), F({ minWidth: 400, height: 20 }), F({ width: 50, height: 10, alignSelf: "stretch" })));
for (const dir of ["row", "column"]) {
  add(`flex/aspect-${dir}-width`, F({ flexDirection: dir, width: 300, height: 200, alignItems: "flex-start" }, F({ width: 100, aspectRatio: 2 }), F({ height: 50, aspectRatio: 0.5 })));
  add(`flex/aspect-${dir}-stretch`, F({ flexDirection: dir, width: 300, height: 200 }, F({ aspectRatio: 2 }), F({ flexGrow: 1, aspectRatio: 1 })));
  add(`flex/aspect-${dir}-grow`, F({ flexDirection: dir, width: 300, height: 200, alignItems: "center" }, F({ flexGrow: 1, aspectRatio: 3 }), F({ width: 30, height: 30 })));
  add(`flex/aspect-${dir}-minmax`, F({ flexDirection: dir, width: 300, height: 200, alignItems: "flex-start" }, F({ width: 100, aspectRatio: 2, minHeight: 80 }), F({ height: 50, aspectRatio: 0.5, maxWidth: 10 })));
}
add("flex/box-sizing-content", F({ width: 300, height: 200, padding: 10, boxSizing: "content-box" }, F({ width: 50, height: 50, padding: 10, borderWidth: 5, borderStyle: "solid", boxSizing: "content-box" }), F({ flexGrow: 1, minWidth: 30, padding: 4, boxSizing: "content-box" })));
add("flex/padding-larger-than-size", F({ width: 300, height: 200 }, F({ width: 10, height: 10, padding: 20 }), F({ padding: 20, borderWidth: 3, borderStyle: "solid" })));
add("flex/border-sides", F({ width: 300, height: 200, borderLeftWidth: 10, borderTopWidth: 4, borderRightWidth: 2, borderBottomWidth: 6, borderStyle: "solid", paddingLeft: 3, paddingTop: 5 }, F({ flexGrow: 1 }), box(20, 20, { alignSelf: "flex-end" })));

// margins
add("flex/margin-basic", F({ width: 300, height: 200 }, box(50, 40, { margin: 10 }), box(60, 30, { marginLeft: 20, marginTop: 5 }), F({ flexGrow: 1, margin: "4px 8px" })));
add("flex/margin-auto-left", F({ width: 300, height: 200 }, box(50, 40), box(60, 30, { marginLeft: "auto" })));
add("flex/margin-auto-both", F({ width: 300, height: 200 }, box(50, 40, { margin: "auto" })));
add("flex/margin-auto-multi", F({ width: 300, height: 200, gap: 10 }, box(50, 40, { marginRight: "auto" }), box(50, 40, { margin: "0 auto" }), box(50, 40)));
add("flex/margin-auto-cross", F({ width: 300, height: 200 }, box(50, 40, { marginTop: "auto" }), box(50, 40, { marginBottom: "auto" }), box(50, 40, { margin: "auto 0" })));
add("flex/margin-auto-col", F({ width: 300, height: 200, flexDirection: "column" }, box(50, 40, { marginLeft: "auto" }), box(50, 40, { marginTop: "auto" }), box(50, 40, { margin: "0 auto" })));
add("flex/margin-auto-overflow", F({ width: 100, height: 100 }, box(80, 140, { margin: "auto", flexShrink: 0 }), box(80, 40, { marginLeft: "auto", flexShrink: 0 })));
add("flex/margin-auto-reverse", F({ width: 300, height: 200, flexDirection: "row-reverse" }, box(50, 40), box(60, 30, { marginLeft: "auto" })));
add("flex/margin-negative", F({ width: 300, height: 200 }, box(50, 40, { marginLeft: -10 }), box(60, 30, { marginLeft: -20, marginTop: -5 })));
add("flex/margin-stretch", F({ width: 300, height: 200 }, F({ width: 50, margin: 10 }), F({ width: 50, marginTop: 30 })));
add("flex/margin-col-no-collapse", F({ width: 300, flexDirection: "column" }, box(50, 40, { marginBottom: 10 }), box(50, 40, { marginTop: 20 })));

// align-self, baseline
add("flex/align-self", F({ width: 300, height: 200, alignItems: "center" }, box(50, 40, { alignSelf: "flex-start" }), box(50, 40, { alignSelf: "flex-end" }), box(50, 40), F({ width: 50, alignSelf: "stretch" }), box(50, 40, { alignSelf: "baseline" })));
add("flex/baseline-nested", F({ width: 300, height: 200, alignItems: "baseline" }, box(50, 40), F({ padding: 10 }, box(20, 60)), F({ flexDirection: "column", marginTop: 7 }, box(20, 25), box(20, 25))));
add("flex/baseline-wrap", F({ width: 120, alignItems: "baseline", flexWrap: "wrap" }, box(50, 40), box(50, 60), box(50, 20), box(50, 30, { marginTop: 5 })));

// absolute
const rel = { position: "relative" };
add("abs/inset-basic", F({ ...rel, width: 300, height: 200, padding: 10, borderWidth: 5, borderStyle: "solid" }, F({ position: "absolute", top: 10, left: 20, width: 50, height: 40 }), F({ position: "absolute", bottom: 10, right: 20, width: 50, height: 40 }), box(30, 30)));
add("abs/inset-stretch", F({ ...rel, width: 300, height: 200, padding: 10 }, F({ position: "absolute", top: 10, left: 20, right: 30, bottom: 40 }), F({ position: "absolute", inset: 0 }), F({ position: "absolute", top: 0, bottom: 0, left: "10%", width: "25%" })));
add("abs/inset-margin", F({ ...rel, width: 300, height: 200 }, F({ position: "absolute", top: 10, left: 20, right: 30, bottom: 40, margin: 5 }), F({ position: "absolute", inset: 0, margin: "auto", width: 100, height: 50 }), F({ position: "absolute", left: 0, right: 0, marginLeft: "auto", width: 100, height: 50 })));
add("abs/percent", F({ ...rel, width: 300, height: 200, padding: 20 }, F({ position: "absolute", top: "50%", left: "50%", width: "50%", height: "25%" })));
for (const jc of ["flex-start", "center", "flex-end", "space-between", "space-around"]) {
  for (const ai of ["flex-start", "center", "flex-end", "stretch"]) {
    add(`abs/static-${jc}-${ai}`, F({ ...rel, width: 300, height: 200, padding: 10, justifyContent: jc, alignItems: ai }, F({ position: "absolute", width: 50, height: 40 }), box(30, 30)));
  }
}
add("abs/static-col", F({ ...rel, width: 300, height: 200, padding: 10, flexDirection: "column", justifyContent: "flex-end", alignItems: "center" }, F({ position: "absolute", width: 50, height: 40 }), box(30, 30)));
add("abs/static-row-reverse", F({ ...rel, width: 300, height: 200, padding: 10, flexDirection: "row-reverse" }, F({ position: "absolute", width: 50, height: 40 }), box(30, 30)));
add("abs/static-align-self", F({ ...rel, width: 300, height: 200 }, F({ position: "absolute", width: 50, height: 40, alignSelf: "flex-end" }), F({ position: "absolute", width: 50, height: 40, alignSelf: "center", left: 5 })));
add("abs/content-sized", F({ ...rel, width: 300, height: 200 }, F({ position: "absolute", top: 10, left: 20, padding: 5 }, box(40, 30), box(20, 10)), F({ position: "absolute", right: 0, bottom: 0, flexDirection: "column" }, box(40, 30), box(20, 10))));
add("abs/shrink-to-fit", F({ ...rel, width: 200, height: 200 }, c({ display: "flex", position: "absolute", top: 10, left: 120, flexWrap: "wrap" }, box(30, 10), box(30, 10), box(30, 10), box(30, 10))));
add("abs/aspect", F({ ...rel, width: 300, height: 200 }, F({ position: "absolute", top: 10, left: 20, width: 80, aspectRatio: 2 }), F({ position: "absolute", top: 0, bottom: 0, right: 0, aspectRatio: 0.5 })));
add("abs/min-max", F({ ...rel, width: 300, height: 200 }, F({ position: "absolute", inset: 0, maxWidth: 100, minHeight: 250 })));
add("abs/nested-static-ancestor", F({ ...rel, width: 300, height: 200, padding: 20 }, F({ width: 100, height: 100, padding: 5, marginLeft: 30 }, F({ position: "absolute", top: 10, left: 10, width: 50, height: 50 }), F({ position: "absolute", width: 20, height: 20 }), F({ position: "absolute", right: 0, bottom: 0, width: "50%", height: "10%" }))));
add("abs/in-block", B({ ...rel, width: 300, padding: 10 }, B({ height: 30 }), B({ position: "absolute", width: 50, height: 40 }), B({ height: 30 }), B({ position: "absolute", width: 50, height: 40, right: 0 })));
add("abs/only-child-auto-parent", F({ ...rel, width: 300 }, F({ position: "absolute", width: 50, height: 40 })));
add("rel/offsets", F({ width: 300, height: 200 }, box(50, 40, { position: "relative", top: 10, left: 20 }), box(50, 40, { position: "relative", bottom: 10, right: 20 }), box(50, 40, { position: "relative", top: "10%", left: "10%" })));
add("none/skipped", F({ width: 300, height: 200, gap: 10 }, box(50, 40), c({ display: "none", width: 100, height: 100 }, box(10, 10)), box(50, 40)));

// ---------------------------------------------------------------- block
add("block/stack", B({ width: 300 }, B({ height: 50 }), B({ height: 30, width: 100.4 }), B({ height: 20, width: "50%" })));
add("block/margins-collapse-siblings", B({ width: 300 }, B({ height: 50, marginBottom: 20 }), B({ height: 30, marginTop: 30, marginBottom: 10 }), B({ height: 20, marginTop: 5 })));
add("block/margins-negative", B({ width: 300 }, B({ height: 50, marginBottom: 20 }), B({ height: 30, marginTop: -30, marginBottom: -10 }), B({ height: 20, marginTop: -5 })));
add("block/margin-collapse-parent-first", B({ width: 300 }, B({}, B({ height: 50, marginTop: 20, marginBottom: 15 })), B({ marginTop: 10 }, B({ height: 30, marginTop: 30 }))));
add("block/margin-collapse-parent-padding", B({ width: 300 }, B({ paddingTop: 1 }, B({ height: 50, marginTop: 20, marginBottom: 15 })), B({ marginTop: 10, borderWidth: 0, borderStyle: "solid", borderBottomWidth: 2 }, B({ height: 30, marginTop: 30, marginBottom: 9 }))));
add("block/margin-collapse-through-empty", B({ width: 300 }, B({ height: 50, marginBottom: 20 }), B({ marginTop: 40, marginBottom: 25 }), B({ height: 20, marginTop: 5 })));
add("block/margin-collapse-nested-deep", B({ width: 300, padding: 1 }, B({ marginTop: 5 }, B({ marginTop: 15 }, B({ marginTop: 10, height: 20, marginBottom: 12 })), B({ height: 10, marginBottom: 30 })), B({ height: 10, marginTop: 7 })));
add("block/margin-root-child", B({ width: 300 }, B({ height: 50, marginTop: 20, marginBottom: 15 })));
add("block/margin-in-flex-item", F({ width: 300, flexDirection: "column" }, B({}, B({ height: 50, marginTop: 20, marginBottom: 15 })), B({}, B({ height: 20, marginTop: 20 }))));
add("block/margin-overflow-hidden", B({ width: 300 }, B({ overflow: "hidden" }, B({ height: 50, marginTop: 20, marginBottom: 15 })), B({ height: 20, marginTop: 20 })));
add("block/margin-height-parent", B({ width: 300 }, B({ height: 100 }, B({ height: 50, marginTop: 20, marginBottom: 15 })), B({ height: 20, marginTop: 20 })));
add("block/margin-min-height-parent", B({ width: 300 }, B({ minHeight: 100 }, B({ height: 50, marginTop: 20, marginBottom: 15 })), B({ height: 20, marginTop: 20 })));
add("block/auto-margins", B({ width: 300 }, B({ height: 50, width: 100, margin: "0 auto" }), B({ height: 30, width: 100, marginLeft: "auto" }), B({ height: 30, width: 100, marginRight: "auto", marginLeft: 10 }), B({ height: 30, margin: "0 auto" })));
add("block/padding-border", B({ width: 300, padding: 10, borderWidth: 5, borderStyle: "solid" }, B({ height: 50, margin: 10 }), B({ padding: "5px 10px" }, B({ height: 10 }))));
add("block/percent", B({ width: 300, height: 200 }, B({ height: "50%", width: "50%", padding: "5%", margin: "2%" }), B({ height: "25%" })));
add("block/percent-height-auto-parent", B({ width: 300 }, B({ height: "50%" }, B({ height: 20 })), B({ height: 10 })));
add("block/min-max", B({ width: 300 }, B({ height: 50, maxWidth: 100 }), B({ height: 30, minWidth: 400 }), B({ minHeight: 40 }), B({ maxHeight: 10 }, B({ height: 50 })), B({ height: 5 })));
add("block/flex-children", B({ width: 300, padding: 5 }, F({ gap: 5 }, box(50, 40), F({ flexGrow: 1 })), F({ marginTop: 10, flexDirection: "column" }, box(50, 40)), B({ marginTop: 20, height: 10 })));
add("block/in-flex-row", F({ width: 300, height: 100 }, B({}, B({ width: 50, height: 20 }), B({ width: 80, height: 20 })), B({ flexGrow: 1 }, B({ height: 20 })), B({ padding: 3 }, words(4))));
add("block/in-flex-col-center", F({ width: 300, flexDirection: "column", alignItems: "center" }, B({}, B({ width: 50, height: 20 }), B({ width: 80, height: 20, marginLeft: 10 })), B({ padding: 3 }, words(4)), B({ padding: 3 }, words(20))));
add("block/aspect", B({ width: 300 }, B({ aspectRatio: 2 }), B({ width: 100, aspectRatio: 0.5 }), B({ height: 30, aspectRatio: 2 })));
add("block/content-box", B({ width: 300, padding: 10, boxSizing: "content-box" }, B({ width: 100, height: 20, padding: 10, boxSizing: "content-box" }), B({ height: 20, padding: 10, boxSizing: "content-box" })));
add("block/relative", B({ width: 300 }, B({ height: 50, position: "relative", top: 10, left: 5 }), B({ height: 30 })));
add("block/none", B({ width: 300 }, B({ height: 50, marginBottom: 10 }), c({ display: "none", height: 100 }), B({ height: 30, marginTop: 20 })));
add("block/root-auto-height", B({}, B({ height: 50 }), B({ height: 30 })));
add("block/nested-flex-block-flex", B({ width: 320 }, F({ padding: 8, gap: 8 }, B({ flexGrow: 1 }, F({ flexDirection: "column", gap: 2 }, box(30, 10), box(40, 10)), B({ height: 5, marginTop: 5 })), B({ width: 100 }, B({ height: 40, margin: "10px auto", width: 50 })))));
add("block/empty-collapse-with-padding", B({ width: 300 }, B({ height: 20, marginBottom: 10 }), B({ marginTop: 20, marginBottom: 30, paddingTop: 1 }), B({ height: 20, marginTop: 15 })));
add("block/last-child-margin", B({ width: 300 }, B({}, B({ height: 20, marginBottom: 30 })), B({ height: 20 })));
add("block/last-child-margin-root-padding", B({ width: 300, paddingBottom: 4 }, B({}, B({ height: 20, marginBottom: 30 }))));

// root behaviour
add("root/flex-auto", F({}, box(50, 40)));
add("root/percent", F({ width: "50%", height: "50%" }, F({ flexGrow: 1 })));
add("root/margin", F({ margin: 10 }, box(50, 40)));
add("root/margin-fixed", F({ margin: 10, width: 100, height: 50 }, F({ flexGrow: 1 })));
add("root/padding-percent", F({ padding: "10%" }, box(50, 40)));
add("root/max-width", F({ maxWidth: 200, minHeight: 80 }, box(50, 40)));
add("root/aspect", F({ aspectRatio: 2 }, box(50, 40)));
add("root/col-overflow-viewport", F({ flexDirection: "column" }, box(50, 200), box(50, 200)));
add("root/wrap-col-auto", F({ flexDirection: "column", flexWrap: "wrap" }, box(50, 200), box(50, 200)));

// ---------------------------------------------------------------- seeded random flex/block trees
let seed = +(process.env.SEED || 12345);
const NF = +(process.env.NF || 80), NB = +(process.env.NB || 40), NM = +(process.env.NM || 60);
const rnd = () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (...xs) => xs[Math.floor(rnd() * xs.length)];
const maybe = (p, v) => (rnd() < p ? v : {});
function randFlex(depth, isRoot) {
  const leaf = depth <= 0 || rnd() < 0.3;
  const style = {
    display: "flex",
    ...maybe(0.5, { width: pick(20, 40, 60.5, 100, 150, "50%", "30%") }),
    ...maybe(0.5, { height: pick(20, 40, 60, 100.25, "50%") }),
    ...maybe(0.3, { flexGrow: pick(1, 2, 0.5) }),
    ...maybe(0.2, { flexShrink: pick(0, 2) }),
    ...maybe(0.15, { flexBasis: pick(0, 30, "20%") }),
    ...maybe(0.25, { margin: pick(3, 5, "2px 6px", "auto") }),
    ...maybe(0.25, { padding: pick(2, 6, "3px 9px") }),
    ...maybe(0.15, { borderWidth: pick(1, 3), borderStyle: "solid" }),
    ...maybe(0.15, { minWidth: pick(10, 50) }),
    ...maybe(0.15, { maxWidth: pick(40, 120) }),
    ...maybe(0.1, { minHeight: pick(10, 50) }),
    ...maybe(0.1, { maxHeight: pick(40, 120) }),
    ...maybe(0.2, { alignSelf: pick("flex-start", "center", "flex-end", "stretch") }),
  };
  if (isRoot) Object.assign(style, { width: pick(200, 300, 333), ...maybe(0.7, { height: pick(150, 200, 250) }) }, { margin: 0 });
  if (leaf) return c(style);
  Object.assign(style, {
    flexDirection: pick("row", "column", "row", "column", "row-reverse", "column-reverse"),
    ...maybe(0.3, { flexWrap: pick("wrap", "wrap", "wrap-reverse") }),
    ...maybe(0.5, { justifyContent: pick("flex-start", "center", "flex-end", "space-between", "space-around", "space-evenly") }),
    ...maybe(0.5, { alignItems: pick("flex-start", "center", "flex-end", "stretch") }),
    ...maybe(0.3, { alignContent: pick("flex-start", "center", "flex-end", "stretch", "space-between", "space-around") }),
    ...maybe(0.4, { gap: pick(2, 5, 10) }),
  });
  const n = 1 + Math.floor(rnd() * 4);
  return c(style, ...Array.from({ length: n }, () => randFlex(depth - 1, false)));
}
for (let i = 0; i < NF; i++) add(`rand/flex-${i}`, randFlex(3, true));

function randBlock(depth, isRoot) {
  const leaf = depth <= 0 || rnd() < 0.3;
  const style = {
    display: "block",
    ...maybe(0.3, { width: pick(40, 100, 150, "50%") }),
    ...maybe(leaf ? 0.8 : 0.2, { height: pick(10, 20, 35.5) }),
    ...maybe(0.5, { marginTop: pick(5, 10, 20, -5) }),
    ...maybe(0.5, { marginBottom: pick(5, 10, 20, -8) }),
    ...maybe(0.2, { marginLeft: pick(5, "auto") }),
    ...maybe(0.2, { paddingTop: pick(2, 6) }),
    ...maybe(0.15, { paddingBottom: pick(2, 6) }),
    ...maybe(0.1, { borderWidth: pick(1, 3), borderStyle: "solid" }),
    ...maybe(0.1, { minHeight: pick(10, 50) }),
  };
  if (isRoot) Object.assign(style, { width: 300 });
  if (leaf) return c(style);
  const n = 1 + Math.floor(rnd() * 4);
  return c(style, ...Array.from({ length: n }, () => (rnd() < 0.15 ? randFlex(1, false) : randBlock(depth - 1, false))));
}
for (let i = 0; i < NB; i++) add(`rand/block-${i}`, randBlock(3, true));

// mixed trees: text-like wrapping leaves, absolute children, aspect ratios, blocks inside flex, baseline
function randMix(depth, isRoot, parentKind) {
  const k = rnd();
  if (!isRoot && k < 0.12) return words(1 + Math.floor(rnd() * 8), pick(20, 30, 45), pick(10, 16), maybe(0.3, { gap: pick(2, 4) }));
  if (!isRoot && k < 0.2 && parentKind === "flex") return c({ display: "flex", position: "absolute", ...maybe(0.5, { top: pick(0, 5, "10%") }), ...maybe(0.5, { left: pick(0, 7, "20%") }), ...maybe(0.3, { right: pick(0, 4) }), ...maybe(0.3, { bottom: pick(0, 6) }), ...maybe(0.6, { width: pick(20, 50, "30%") }), ...maybe(0.6, { height: pick(10, 30, "40%") }), ...maybe(0.2, { margin: pick(3, "auto") }) }, ...(rnd() < 0.3 ? [box(15, 12)] : []));
  if (!isRoot && k < 0.24) return c({ display: "none", width: 50, height: 50 });
  const isBlock = rnd() < 0.25;
  const leaf = depth <= 0 || rnd() < 0.25;
  const style = {
    display: isBlock ? "block" : "flex",
    position: "relative",
    ...maybe(0.35, { width: pick(30, 60, 90.5, 140, "50%", "35%") }),
    ...maybe(leaf ? 0.6 : 0.25, { height: pick(15, 30, 55.5, 80, "50%") }),
    ...maybe(0.12, { aspectRatio: pick(1, 2, 0.5) }),
    ...maybe(0.25, { flexGrow: pick(1, 2) }),
    ...maybe(0.15, { flexShrink: pick(0, 3) }),
    ...maybe(0.1, { flexBasis: pick(0, 40, "25%", "auto") }),
    ...maybe(0.2, { margin: pick(4, "2px 8px", "0 auto", "auto") }),
    ...maybe(0.2, { padding: pick(3, 7, "2px 10px", "5%") }),
    ...maybe(0.1, { borderWidth: pick(1, 2), borderStyle: "solid" }),
    ...maybe(0.1, { minWidth: pick(20, 70) }),
    ...maybe(0.1, { maxWidth: pick(50, 110) }),
    ...maybe(0.08, { minHeight: pick(20, 60) }),
    ...maybe(0.08, { maxHeight: pick(30, 90) }),
    ...maybe(0.15, { alignSelf: pick("flex-start", "center", "flex-end", "stretch", "baseline") }),
    ...maybe(0.06, { overflow: "hidden" }),
    ...maybe(0.06, { boxSizing: "content-box" }),
  };
  if (isRoot) Object.assign(style, { width: pick(220, 320, 401), margin: 0, ...maybe(0.6, { height: pick(160, 240) }) });
  if (leaf) return c(style);
  if (!isBlock) Object.assign(style, {
    flexDirection: pick("row", "column", "row", "column", "row-reverse", "column-reverse"),
    ...maybe(0.3, { flexWrap: pick("wrap", "wrap", "wrap-reverse") }),
    ...maybe(0.5, { justifyContent: pick("flex-start", "center", "flex-end", "space-between", "space-around", "space-evenly") }),
    ...maybe(0.5, { alignItems: pick("flex-start", "center", "flex-end", "stretch", "baseline") }),
    ...maybe(0.25, { alignContent: pick("flex-start", "center", "flex-end", "stretch", "space-between", "space-around", "space-evenly") }),
    ...maybe(0.4, { gap: pick(3, 6, "4px 9px") }),
  });
  const n = 1 + Math.floor(rnd() * 4);
  return c(style, ...Array.from({ length: n }, () => randMix(depth - 1, false, isBlock ? "block" : "flex")));
}
for (let i = 0; i < NM; i++) add(`rand/mix-${i}`, randMix(3, true, "flex"));

export { cases, c, F, B, G, box, add, words, rnd, pick, maybe };
const { addGrid } = await import("./gen_grid.mjs").catch(() => ({ addGrid: null }));
if (addGrid) addGrid();

// ---------------------------------------------------------------- run the oracle
const toTakumi = (n) => ({ type: "container", style: n.style, children: n.children.map(toTakumi) });
const conv = (n, m) => {
  // takumi omits display:none nodes from its result
  const kids = [];
  let i = 0;
  for (const ch of n.children) {
    if (ch.style.display === "none") kids.push({ x: 0, y: 0, w: 0, h: 0, none: true });
    else kids.push(conv(ch, m.children[i++]));
  }
  if (i !== m.children.length) throw new Error("child count mismatch");
  return { x: m.transform[4], y: m.transform[5], w: m.width, h: m.height, ...(kids.length ? { children: kids } : {}) };
};
const out = [];
for (const cs of cases) {
  const m = await r.measure(toTakumi(cs.node), { width: cs.vp[0], height: cs.vp[1] });
  try {
    out.push({ ...cs, expect: conv(cs.node, m) });
  } catch (e) {
    console.error("skip", cs.name, e.message);
  }
}
const only = process.argv[2];
if (only) {
  for (const o of out) if (o.name.includes(only)) console.log(JSON.stringify(o, null, 1));
} else {
  writeFileSync("../../../src/layout/testdata/oracle.json", JSON.stringify(out));
  console.log("wrote", out.length, "cases");
}
