// Generates src/layout/testdata/oracle_misc.json: order, safe alignment, position: fixed, absolutely positioned
// grid children in grid areas, aspect-ratio automatic minimums + takumi's layout.
// Usage: node gen_misc.mjs [name-filter]      (run from bench/probe/layout)
import { Renderer } from "@takumi-rs/wasm/node";
import { writeFileSync } from "node:fs";

const r = new Renderer();
const cases = [];
const c = (style, ...children) => ({ style, children });
const B = (style, ...ch) => c({ display: "block", ...style }, ...ch);
const F = (style, ...ch) => c({ display: "flex", ...style }, ...ch);
const G = (style, ...ch) => c({ display: "grid", ...style }, ...ch);
const box = (w, h, extra = {}) => F({ width: w, height: h, ...extra });
const add = (name, node, vp = [400, 300]) => cases.push({ name, vp, node });

// ---------------------------------------------------------------- order
add("order/flex-row", F({ width: 300, height: 50 }, box(50, 10, { order: 2 }), box(60, 10, { order: -1 }), box(70, 10), box(20, 10, { order: 2 }), box(30, 10, { order: -1 })));
add("order/flex-column-reverse", F({ width: 300, height: 200, flexDirection: "column-reverse", gap: 3 }, box(50, 10, { order: 1 }), box(60, 20), box(70, 30, { order: -5 })));
add("order/flex-wrap", F({ width: 120, flexWrap: "wrap" }, box(50, 10, { order: 3 }), box(60, 20, { order: 1 }), box(70, 30, { order: 2 }), box(40, 15), box(30, 12, { order: 1 })));
add("order/flex-baseline", F({ width: 300, alignItems: "baseline" }, F({ order: 1, padding: 10 }, box(20, 30)), box(50, 40), F({ order: -1, flexDirection: "column" }, box(20, 25), box(20, 25))));
add("order/flex-abs-ignored", F({ width: 300, height: 50, position: "relative" }, box(50, 10, { order: 2 }), F({ position: "absolute", order: -3, width: 10, height: 10 }), box(60, 10)));
add("order/grid", G({ width: 300, gridTemplateColumns: "1fr 1fr" }, F({ height: 50, order: 2 }), F({ height: 60, order: -1 }), F({ height: 70 }), F({ height: 20, order: 2, gridColumn: "2" }), F({ height: 30, order: -1 })));
add("order/grid-dense", G({ width: 300, gridTemplateColumns: "1fr 1fr 1fr", gridAutoFlow: "row dense", gridAutoRows: "20px" }, F({ gridColumn: "span 2", order: 1 }), F({ gridColumn: "span 2" }), F({ order: -1 }), F({ order: 5 })));
add("order/equal-stable", F({ width: 300, height: 50 }, box(10, 10, { order: 1 }), box(20, 10, { order: 1 }), box(30, 10, { order: 1 }), box(40, 10, { order: 0 })));

// ---------------------------------------------------------------- safe alignment
const big = box(150, 80, { flexShrink: 0 });
for (const v of ["center", "end", "flex-end"]) {
  add(`safe/flex-justify-${v}`, F({ width: 100, height: 50, justifyContent: `safe ${v}` }, big));
  add(`safe/flex-align-items-${v}`, F({ width: 100, height: 50, alignItems: `safe ${v}` }, big));
  add(`safe/flex-unsafe-${v}`, F({ width: 100, height: 50, justifyContent: `unsafe ${v}`, alignItems: `unsafe ${v}` }, big));
  add(`safe/flex-fits-${v}`, F({ width: 300, height: 150, justifyContent: `safe ${v}`, alignItems: `safe ${v}` }, big));
  add(`safe/flex-column-${v}`, F({ width: 100, height: 50, flexDirection: "column", justifyContent: `safe ${v}`, alignItems: `safe ${v}` }, big));
}
add("safe/flex-reverse", F({ width: 100, height: 50, flexDirection: "row-reverse", justifyContent: "safe flex-end", alignItems: "safe flex-end" }, big));
add("safe/flex-align-content", F({ width: 100, height: 50, flexWrap: "wrap", alignContent: "safe center" }, big, box(40, 80, { alignSelf: "safe end" })));
add("safe/flex-align-self", F({ width: 100, height: 50, alignItems: "center" }, box(30, 80, { alignSelf: "safe center" }), box(30, 80), box(30, 20, { alignSelf: "safe end" })));
add("safe/grid-items", G({ width: 100, height: 50, justifyItems: "safe center", alignItems: "safe end", gridTemplateColumns: "150px", gridTemplateRows: "70px" }, box(180, 80), box(180, 80, { justifySelf: "center", alignSelf: "safe center" })));
add("safe/grid-content", G({ width: 100, height: 50, justifyContent: "safe center", alignContent: "safe end", gridTemplateColumns: "150px", gridTemplateRows: "70px" }, box(20, 20)));
add("safe/grid-content-unsafe", G({ width: 100, height: 50, justifyContent: "center", alignContent: "end", gridTemplateColumns: "150px", gridTemplateRows: "70px" }, box(20, 20)));

// ---------------------------------------------------------------- position: fixed
const fixed = (extra) => F({ position: "fixed", ...extra });
add("fixed/insets", B({ width: 300, height: 200, margin: 7 }, B({ position: "relative", margin: 20, height: 50 }, fixed({ top: 5, right: 5, width: 30, height: 30 }), fixed({ width: 30, height: 30 }), fixed({ inset: "10%" }))));
add("fixed/in-flex", F({ width: 300, height: 200, padding: 10, position: "relative", justifyContent: "center", alignItems: "center" }, box(20, 20), fixed({ width: 30, height: 30 }), fixed({ bottom: 0, left: "50%", width: "25%", height: 10 })));
add("fixed/in-grid", G({ width: 300, height: 200, padding: 10, position: "relative", gridTemplateColumns: "1fr 1fr" }, box(20, 20), fixed({ gridColumn: "2", inset: 3 })));
add("fixed/deep", B({ width: 200, padding: 5, position: "relative" }, B({ padding: 5, position: "relative" }, B({ padding: 5, position: "absolute", top: 40, left: 40, width: 100, height: 50 }, fixed({ top: 1, left: 2, width: 10, height: 10 }), fixed({ right: 0, bottom: 0, width: 10, height: 10 })))));
add("fixed/root-smaller-than-viewport", B({ width: 100, height: 50 }, fixed({ right: 0, bottom: 0, width: 10, height: 10 })));
add("fixed/content-sized", B({ width: 300 }, fixed({ top: 10, left: 20, padding: 5 }, box(40, 30), box(20, 10))));

// ---------------------------------------------------------------- absolutely positioned grid children
const abs = (extra) => F({ position: "absolute", ...extra });
const grid = (extra, ...ch) => G({ position: "relative", width: 300, height: 200, padding: 10, gap: 5, gridTemplateColumns: "50px 1fr 80px", gridTemplateRows: "40px 1fr", ...extra }, ...ch, F({ height: 10 }));
add("gridabs/area", grid({}, abs({ gridColumn: "2 / 3", gridRow: "1 / 2", inset: 0 })));
add("gridabs/column-only", grid({}, abs({ gridColumn: "2", width: 20, height: 20 })));
add("gridabs/percent", grid({}, abs({ gridColumn: "1 / -1", gridRow: "2", top: 5, right: 5, width: "50%", height: "50%" })));
add("gridabs/auto-start", grid({}, abs({ gridRow: "auto / 2", left: 3, bottom: 0, width: 10, height: 10 })));
add("gridabs/out-of-range", grid({}, abs({ gridColumn: "3 / 9", inset: 2 }), abs({ gridColumn: "-9 / 2", inset: 2 })));
add("gridabs/span", grid({}, abs({ gridColumn: "span 2 / 3", inset: 2 }), abs({ gridColumn: "2 / span 2", gridRow: "span 1 / -1", inset: 2 })));
add("gridabs/last-line", grid({}, abs({ gridColumn: "4", gridRow: "1 / 3", justifySelf: "end", alignSelf: "center", width: 10, height: 10 }), abs({ gridColumn: "-2 / span 5", gridRow: "3", inset: 2 })));
add("gridabs/static-pos", grid({ justifyItems: "center", alignItems: "end" }, abs({ gridColumn: "2", gridRow: "2", width: 20, height: 20 }), abs({ gridColumn: "3", width: 20, height: 20, justifySelf: "start" })));
add("gridabs/content-alignment", G({ position: "relative", width: 300, height: 200, justifyContent: "center", alignContent: "end", gap: 5, gridTemplateColumns: "50px 60px", gridTemplateRows: "40px 30px" }, abs({ gridColumn: "1 / 2", gridRow: "2", inset: 0 }), abs({ gridColumn: "2", width: 20, height: 20, justifySelf: "center" }), abs({ gridColumn: "1 / 3", gridRow: "1 / 3", width: 20, height: 20, justifySelf: "end", alignSelf: "end" }), F({ height: 10 })));
add("gridabs/implicit-tracks", G({ position: "relative", width: 300, gridTemplateColumns: "100px", gridAutoColumns: "40px", gridAutoRows: "30px" }, F({ gridColumn: 3 }), F({}), abs({ gridColumn: "2 / 4", gridRow: "1", inset: 1 })));
add("gridabs/margin-auto", grid({}, abs({ gridColumn: "2", gridRow: "2", inset: 0, margin: "auto", width: 20, height: 20 })));
add("gridabs/border", grid({ borderWidth: 4, borderStyle: "solid" }, abs({ gridColumn: "1", inset: 0 }), abs({ top: 0, left: 0, width: 5, height: 5 })));

// ---------------------------------------------------------------- aspect-ratio automatic minimums (reduced from random cases)
add("ratio/leaf-in-wrap-column", F({ width: 140, height: 55.5, flexDirection: "column", flexWrap: "wrap" }, B({ minWidth: 70 }), B({ aspectRatio: 2, padding: "2px 10px" })));
add("ratio/min-content-floor-width", F({ flexDirection: "column", flexWrap: "wrap-reverse", alignItems: "flex-end", width: 60 }, F({ height: 15, aspectRatio: 0.5, flexDirection: "column" }, F({ flexWrap: "wrap" }, box(30, 16, { flexShrink: 0 }), box(30, 16, { flexShrink: 0 })))));
add("ratio/column-item-basis", F({ width: 100.25, height: 15, flexDirection: "column", alignItems: "baseline" }, F({ aspectRatio: 2, padding: 3, flexDirection: "column-reverse" }, F({ width: 90.5, height: "50%" }), B({ height: 30, flexBasis: 40 }))));
add("ratio/column-content-floor", F({ height: 30, flexDirection: "column", flexWrap: "wrap", width: 110 }, F({ aspectRatio: 2, flexShrink: 0, flexDirection: "column" }, box(140, 30, { flexShrink: 3 }), box(142, 32), box(30, 15))));
add("ratio/block-child-min-content", B({ width: 88.5 }, B({ height: 80, aspectRatio: 1 }, F({ flexWrap: "wrap", gap: 2 }, box(20, 10, { flexShrink: 0 }), box(20, 10, { flexShrink: 0 })), F({ width: 140, aspectRatio: 1 }))));
add("ratio/transferred-max-clamps-intrinsic", F({ height: 160, width: 320, flexDirection: "column", alignItems: "flex-start" }, F({ width: 60, aspectRatio: 1, padding: 3, maxWidth: 50, flexDirection: "row-reverse" }, B({ width: 140, flexShrink: 3 }, F({ height: 55.5 })), F({ width: 30, height: 15 }))));
add("ratio/row-content-floor", F({ width: 220, flexDirection: "column", flexWrap: "wrap-reverse" }, F({ width: "35%", aspectRatio: 0.5, margin: "2px 8px" }, B({}, F({ width: "50%", height: 80 }), F({ width: 90.5, height: 55.5 }), B({ height: 55.5 })))));
add("ratio/stretched-item-min", F({ height: 160 }, F({}, B({ aspectRatio: 1, minHeight: 20 }), F({ width: "35%" }))));
add("ratio/transferred-max-item", F({}, B({ aspectRatio: 1, maxHeight: 30 }, F({ width: 45 }))));
add("ratio/transferred-min-item", F({}, F({ aspectRatio: 0.5, minHeight: 60 }, B({}))));
add("ratio/basis-is-ratio-size", F({}, F({ flexGrow: 1 }, F({ flexGrow: 2 }), B({ aspectRatio: 0.5, flexGrow: 2 }, B({ height: 15, aspectRatio: 0.5 })))));
add("ratio/basis-zero-cross", F({}, F({ flexGrow: 1, padding: "5%", maxHeight: 30 }, F({ flexGrow: 2 }), B({ aspectRatio: 0.5, flexGrow: 2 }, B({ height: 15, aspectRatio: 0.5 })))));
add("ratio/percent-height-wrap-column-item", F({}, F({ maxHeight: 120, flexDirection: "column-reverse" }, F({ height: "50%", margin: "2px 6px", flexDirection: "column", flexWrap: "wrap", gap: 2 }, F({ height: 40 }), F({ height: 20 })), F({ height: 60 }))));
add("abs/static-baseline-wrap-reverse", F({}, B({}, F({ width: 30 }), F({ flexDirection: "column-reverse", flexWrap: "wrap-reverse", alignItems: "baseline" }, F({ position: "absolute" })))));

// ---------------------------------------------------------------- run the oracle
const toTakumi = (n) => ({ type: "container", style: n.style, children: n.children.map(toTakumi) });
const conv = (n, m) => {
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
  try {
    const m = await r.measure(toTakumi(cs.node), { width: cs.vp[0], height: cs.vp[1] });
    out.push({ ...cs, expect: conv(cs.node, m) });
  } catch (e) {
    console.error("skip", cs.name, String(e.message).slice(0, 100));
  }
}
const only = process.argv[2];
if (only) {
  for (const o of out) if (o.name.includes(only)) console.log(JSON.stringify(o, null, 1));
} else {
  writeFileSync("../../../src/layout/testdata/oracle_misc.json", JSON.stringify(out));
  console.log("wrote", out.length, "cases");
}
