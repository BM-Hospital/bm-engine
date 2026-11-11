// Generates src/layout/testdata/oracle_inline.json: block containers with inline-block / inline-flex / inline-grid
// children (atomic inlines on line boxes) + takumi's layout results.
// Usage: node gen_inline.mjs [name-filter]      (run from bench/probe/layout)
//
// Fixture format: { name, vp, node, expect } like gen.mjs, where a node is
//   { style, children, inlineRow? }
// `style` holds only keys tests.zig `styleFrom` understands. The takumi-only font keys (`fontSize`, `lineHeight`)
// are given through the `tk` argument of the helpers below and are NOT stored: what the layout engine needs from
// them is stored as `inlineRow` on every container that has inline-level children:
//   inlineRow: { strut: [ascent, descent, middle], align: <inherited text-align> }
// The replay (tests_inline.zig) wraps each run of consecutive inline-level children ("inline-*" displays) of such
// a container in an anonymous `inline_row` node carrying that strut and alignment.
//
// The strut is derived from takumi's fallback font (Geist: ascent 1.005 em, descent 0.295 em, line gap 0,
// x-height 0.53 em) exactly like Blink does:
//   A = round(ascent px), D = round(descent px), G = round(line gap px)
//   L = line-height (normal: A + D + G; <number>: number * font-size; <length>: px)
//   half = floor((L - (A + D)) / 2)            (whole pixels)
//   strut ascent = A + half, strut descent = L - strut ascent, middle = x-height px / 2
import { Renderer } from "@takumi-rs/wasm/node";
import { writeFileSync } from "node:fs";

const r = new Renderer();
const cases = [];
const c = (style, ...children) => ({ style, children });
// a second leading object with a `tk` key carries takumi-only style: B({ width: 100 }, tk({ fontSize: 32 }), ...kids)
const tk = (o) => ({ __tk: o });
const mk = (display) => (style, ...ch) => {
  const n = { style: { display, ...style }, children: ch.filter((x) => !x.__tk) };
  const t = ch.find((x) => x.__tk);
  if (t) n.tk = t.__tk;
  return n;
};
const F = mk("flex");
const B = mk("block");
const G = mk("grid");
const IB = mk("inline-block");
const IF = mk("inline-flex");
const IG = mk("inline-grid");
const ib = (w, h, extra = {}) => IB({ width: w, height: h, ...extra });
const box = (w, h, extra = {}) => B({ width: w, height: h, ...extra });
const add = (name, node, vp = [400, 300]) => cases.push({ name, vp, node });

const FONT = { ascent: 1.005, descent: 0.295, gap: 0, xHeight: 0.53 };
function strutOf(fs, lh) {
  const A = Math.round(FONT.ascent * fs), D = Math.round(FONT.descent * fs), Gp = Math.round(FONT.gap * fs);
  const L = lh.kind === "normal" ? A + D + Gp : lh.kind === "num" ? lh.v * fs : lh.v;
  const half = Math.floor((L - (A + D)) / 2);
  return [A + half, L - (A + half), (FONT.xHeight * fs) / 2];
}
// marks the containers that hold inline-level children (font-size, line-height and text-align inherit)
function annotate(n, inh) {
  const s = { ...n.style, ...(n.tk || {}) };
  const cur = { ...inh };
  if (s.fontSize !== undefined) cur.fs = s.fontSize;
  if (s.lineHeight !== undefined) cur.lh = typeof s.lineHeight === "number" ? { kind: "num", v: s.lineHeight } : { kind: "px", v: parseFloat(s.lineHeight) };
  if (s.textAlign !== undefined) cur.align = s.textAlign;
  const blockish = ["block", "inline-block", "flow-root"].includes(s.display);
  if (blockish && n.children.some((ch) => String(ch.style.display).startsWith("inline-"))) {
    n.inlineRow = { strut: strutOf(cur.fs, cur.lh), align: cur.align };
  }
  for (const ch of n.children) annotate(ch, cur);
}

// ---------------------------------------------------------------- single line, strut
add("line/one-small", B({ width: 300 }, ib(10, 2)));
add("line/one-tall", B({ width: 300 }, ib(10, 50)));
add("line/three", B({ width: 300 }, ib(40, 10), ib(50, 30), ib(60.5, 20)));
add("line/auto-width-container", F({ width: 300, alignItems: "flex-start" }, B({}, ib(40, 10), ib(50, 30))));
add("line/padding-border", B({ width: 300, padding: 7, borderWidth: 3, borderStyle: "solid" }, ib(40, 10), ib(50, 30)));
add("line/fractional", B({ width: 300.5 }, ib(40.3, 10.7), ib(50.25, 30.1), ib(60.6, 20.9)));
for (const [fs, lh] of [[10, undefined], [32, undefined], [64, undefined], [13, undefined], [16, 1], [16, 1.5], [16, "40px"], [16, "10px"], [64, "10px"], [20, 3], [13, 1.5]]) {
  const f = { fontSize: fs, ...(lh !== undefined ? { lineHeight: lh } : {}) };
  add(`strut/fs${fs}-lh${lh ?? "normal"}`, B({ width: 300 }, tk(f), ib(10, 2), ib(10, 2, { verticalAlign: "top" }), ib(10, 2, { verticalAlign: "middle" }), ib(10, 2, { verticalAlign: "bottom" })));
}
add("strut/inherited", B({ width: 300 }, tk({ fontSize: 40, lineHeight: 1.2 }), B({}, ib(10, 2), ib(20, 30)), B({}, tk({ fontSize: 10 }), ib(10, 2), ib(20, 5, { verticalAlign: "middle" }))));

// ---------------------------------------------------------------- wrapping
add("wrap/basic", B({ width: 100 }, ib(40, 10), ib(40, 30), ib(40, 20), ib(40, 5)));
add("wrap/exact-fit", B({ width: 120 }, ib(40, 10), ib(40, 30), ib(40, 20), ib(40, 5)));
add("wrap/one-per-line", B({ width: 50 }, ib(40, 10), ib(40, 30), ib(40, 20)));
add("wrap/wider-than-container", B({ width: 100 }, ib(20, 10), ib(150, 10), ib(20, 10)));
add("wrap/wider-first", B({ width: 100 }, ib(150, 10), ib(20, 10), ib(90, 10)));
add("wrap/margins", B({ width: 100 }, ib(40, 10, { margin: 5 }), ib(40, 30, { margin: "0 6px" }), ib(40, 20, { marginLeft: 3 }), ib(40, 5)));
add("wrap/margin-fit", B({ width: 100 }, ib(40, 10, { marginRight: 10 }), ib(40, 30, { marginRight: 10 }), ib(40, 20)));
add("wrap/negative-margin-fit", B({ width: 100 }, ib(60, 10), ib(60, 30, { marginLeft: -20 }), ib(40, 20)));
add("wrap/many", B({ width: 200 }, ...Array.from({ length: 14 }, (_, i) => ib(30 + (i * 7) % 25, 8 + (i * 5) % 17))));
add("wrap/padding-container", B({ width: 120, padding: "4px 10px" }, ib(40, 10), ib(40, 30), ib(40, 20), ib(40, 5)));
add("wrap/fractional-fit", B({ width: 100 }, ib(33.3, 10), ib(33.3, 10), ib(33.4, 10), ib(33.5, 10)));

// ---------------------------------------------------------------- text-align
for (const ta of ["start", "center", "end", "right", "justify"]) {
  add(`align/${ta}`, B({ width: 100, textAlign: ta }, ib(30, 10), ib(30, 10), ib(30, 10), ib(30, 10), ib(30, 10)));
  add(`align/${ta}-single`, B({ width: 100, textAlign: ta }, ib(30, 10)));
  add(`align/${ta}-overflow`, B({ width: 100, textAlign: ta }, ib(130, 10), ib(30, 10)));
  add(`align/${ta}-odd`, B({ width: 101.5, textAlign: ta, padding: 3 }, ib(30.25, 10), ib(31, 10, { margin: 2 }), ib(40, 10)));
}
add("align/inherited", B({ width: 200, textAlign: "center" }, B({ width: 150 }, ib(30, 10), ib(30, 10)), B({ textAlign: "end" }, ib(30, 10)), IB({ width: 120 }, ib(30, 10))));

// ---------------------------------------------------------------- vertical-align
for (const va of ["baseline", "top", "middle", "bottom"]) {
  add(`valign/${va}-small`, B({ width: 300 }, ib(10, 6, { verticalAlign: va })));
  add(`valign/${va}-tall`, B({ width: 300 }, ib(10, 60, { verticalAlign: va })));
  add(`valign/${va}-tall-with-baseline`, B({ width: 300 }, ib(10, 60, { verticalAlign: va }), ib(10, 10), ib(10, 33)));
  add(`valign/${va}-margins`, B({ width: 300 }, ib(10, 40, { verticalAlign: va, marginTop: 7, marginBottom: 11 }), ib(10, 10)));
  add(`valign/${va}-odd`, B({ width: 300 }, ib(10, 33.3, { verticalAlign: va }), ib(10, 10.6), ib(10, 3, { verticalAlign: va })));
}
add("valign/top-then-bottom", B({ width: 300 }, ib(10, 60, { verticalAlign: "top" }), ib(10, 80, { verticalAlign: "bottom" }), ib(10, 10)));
add("valign/bottom-then-top", B({ width: 300 }, ib(10, 80, { verticalAlign: "bottom" }), ib(10, 60, { verticalAlign: "top" }), ib(10, 10)));
add("valign/top-taller-then-bottom", B({ width: 300 }, ib(10, 80, { verticalAlign: "top" }), ib(10, 60, { verticalAlign: "bottom" }), ib(10, 10)));
add("valign/bottom-taller-then-top", B({ width: 300 }, ib(10, 60, { verticalAlign: "bottom" }), ib(10, 80, { verticalAlign: "top" }), ib(10, 10)));
add("valign/equal-top-bottom", B({ width: 300 }, ib(10, 60, { verticalAlign: "top" }), ib(10, 60, { verticalAlign: "bottom" }), ib(10, 10)));
add("valign/all-four", B({ width: 300 }, ib(10, 30), ib(10, 44, { verticalAlign: "top" }), ib(10, 50, { verticalAlign: "middle" }), ib(10, 38, { verticalAlign: "bottom" })));
add("valign/middle-tall-two", B({ width: 300 }, ib(10, 61, { verticalAlign: "middle" }), ib(10, 20, { verticalAlign: "middle" }), ib(10, 70)));
add("valign/wrap-mixed", B({ width: 60 }, ib(25, 30), ib(25, 50, { verticalAlign: "top" }), ib(25, 40, { verticalAlign: "bottom" }), ib(25, 10), ib(25, 44, { verticalAlign: "middle" }), ib(25, 9, { verticalAlign: "top" })));
add("valign/top-only-line", B({ width: 300 }, ib(10, 4, { verticalAlign: "top" }), ib(10, 9, { verticalAlign: "bottom" })));

// ---------------------------------------------------------------- margins
add("margin/basic", B({ width: 300 }, ib(30, 10, { margin: 5 }), ib(30, 20, { marginTop: 10, marginBottom: 7, marginLeft: -5 }), ib(30, 10)));
add("margin/vertical-no-collapse", B({ width: 40 }, ib(30, 10, { marginBottom: 9 }), ib(30, 20, { marginTop: 10 })));
add("margin/negative-top", B({ width: 300 }, ib(30, 40, { marginTop: -15 }), ib(30, 10)));
add("margin/negative-bottom", B({ width: 300 }, ib(30, 40, { marginBottom: -15 }), ib(30, 10)));
add("margin/percent", B({ width: 300 }, ib(30, 10, { margin: "5%" }), ib(30, 20, { marginLeft: "10%" })));
add("margin/auto", B({ width: 300 }, ib(30, 10, { margin: "auto" }), ib(30, 20, { marginLeft: "auto" })));

// ---------------------------------------------------------------- sizes
add("size/percent-width", B({ width: 300 }, ib("50%", 10), ib("50%", 10), ib("33.3%", 10), ib("33.3%", 10), ib("33.3%", 10), ib("33.4%", 10)));
add("size/percent-in-padded", B({ width: 300, padding: 20 }, ib("50%", 10), ib("50%", 10), ib("25%", 20)));
add("size/percent-height", B({ width: 300, height: 200 }, ib(30, "50%"), ib(30, "25%", { verticalAlign: "top" })));
add("size/percent-height-auto-parent", B({ width: 300 }, IB({ width: 30, height: "50%" }, box(10, 17)), ib(30, 10)));
add("size/min-max", B({ width: 300 }, ib(30, 10, { minWidth: 50, minHeight: 20 }), ib(80, 60, { maxWidth: 40, maxHeight: 25 }), IB({ minWidth: 35 }, box(10, 10)), IB({ maxWidth: 35 }, box(60, 10))));
add("size/padding-border", B({ width: 300 }, IB({ padding: 5, borderWidth: 2, borderStyle: "solid" }, box(20, 20)), ib(30, 30, { padding: 5, boxSizing: "content-box" }), ib(10, 10)));
add("size/aspect-ratio", B({ width: 300 }, IB({ width: 40, aspectRatio: 2 }), IB({ height: 30, aspectRatio: 0.5 }), ib(10, 10)));
add("size/shrink-to-fit", B({ width: 100 }, IB({}, ib(60, 10), ib(60, 10)), ib(20, 10)));
add("size/shrink-to-fit-min", B({ width: 100 }, ib(30, 10), IB({}, ib(160, 10), ib(60, 10)), ib(20, 10)));
add("size/shrink-to-fit-margin", B({ width: 100 }, IB({ margin: "0 10px", padding: 2 }, ib(50, 10), ib(50, 10))));
add("size/content-sized", B({ width: 300 }, IB({}, box(40, 10), box(25, 10)), IF({}, box(40, 10), box(25, 10)), IF({ flexDirection: "column" }, box(40, 10), box(25, 10))));
add("size/empty-items", B({ width: 300 }, IB({}), IB({ padding: 4 }), IF({}), ib(10, 10)));
add("size/zero-width-items-wrap", B({ width: 50 }, ib(50, 10), ib(0, 20), ib(0, 5), ib(10, 10)));

// ---------------------------------------------------------------- baselines of items
add("baseline/ib-block-child", B({ width: 300 }, IB({ padding: 3 }, box(20, 30)), ib(10, 10)));
add("baseline/ib-flex-child", B({ width: 300 }, IB({ padding: 3 }, F({ width: 40 }, box(20, 30), box(20, 12))), ib(10, 10)));
add("baseline/ib-two-flex-children", B({ width: 300 }, IB({ padding: 3 }, F({ width: 40 }, box(20, 30)), F({ width: 40 }, box(20, 12))), ib(10, 10)));
add("baseline/iflex-row", B({ width: 300 }, IF({ padding: 3 }, box(20, 30), box(20, 12, { marginTop: 4 })), ib(10, 10)));
add("baseline/iflex-column", B({ width: 300 }, IF({ padding: 3, flexDirection: "column" }, box(20, 30), box(20, 12)), ib(10, 10)));
add("baseline/iflex-empty", B({ width: 300 }, IF({ padding: 3, width: 20, height: 40 }), ib(10, 10)));
add("baseline/iflex-align-end", B({ width: 300 }, IF({ height: 50, alignItems: "flex-end" }, box(20, 30), box(20, 12)), ib(10, 10)));
add("baseline/iflex-hidden", B({ width: 300 }, IF({ padding: 3, overflow: "hidden" }, box(20, 30), box(20, 12)), ib(10, 10)));
add("baseline/igrid", B({ width: 300 }, IG({ padding: 3, gridTemplateColumns: "20px 30px" }, box(20, 30), box(20, 12), box(10, 9)), ib(10, 10)));
add("baseline/nested-ib", B({ width: 300 }, IB({ padding: 3 }, ib(20, 30), ib(10, 5)), ib(10, 10)));
add("baseline/nested-ib-margin", B({ width: 300 }, IB({ padding: 3, marginTop: 6, marginBottom: 4 }, ib(20, 30), ib(10, 5)), ib(10, 10)));
add("baseline/nested-ib-hidden", B({ width: 300 }, IB({ padding: 3, overflow: "hidden" }, ib(20, 30), ib(10, 5)), ib(10, 10)));
add("baseline/nested-ib-hidden-margin", B({ width: 300 }, IB({ padding: 3, overflow: "hidden", marginBottom: 8 }, ib(20, 30), ib(10, 5)), ib(10, 10)));
add("baseline/nested-ib-two-lines", B({ width: 300 }, IB({ padding: 3, width: 40 }, ib(20, 30), ib(30, 15)), ib(10, 10)));
add("baseline/nested-three-deep", B({ width: 300 }, IB({ padding: 2 }, IB({ padding: 2 }, IB({ padding: 2 }, ib(10, 12)), ib(8, 20)), ib(6, 30)), ib(10, 10)));
add("baseline/ib-block-then-row", B({ width: 300 }, IB({}, box(30, 20), B({}, ib(20, 10), ib(10, 5))), ib(10, 10)));
add("baseline/ib-row-then-block", B({ width: 300 }, IB({}, B({}, ib(20, 10), ib(10, 5)), box(30, 20)), ib(10, 10)));
add("baseline/mixed-items", B({ width: 300 }, IB({ padding: 3 }, ib(20, 30)), IF({ marginTop: 5 }, box(10, 22)), ib(10, 10, { verticalAlign: "middle" }), IB({ height: 50, verticalAlign: "top" }, ib(5, 5))));

// ---------------------------------------------------------------- overflow items
add("overflow/hidden-item", B({ width: 300 }, ib(30, 20, { overflow: "hidden" }), ib(10, 10)));
add("overflow/hidden-content-taller", B({ width: 300 }, IB({ width: 30, height: 20, overflow: "hidden" }, box(10, 50)), ib(10, 10)));
add("overflow/visible-content-taller", B({ width: 300 }, IB({ width: 30, height: 20 }, ib(10, 50)), ib(10, 10)));
add("overflow/hidden-flex-item", B({ width: 300 }, IF({ width: 30, height: 20, overflow: "hidden" }, box(10, 50)), ib(10, 10)));

// ---------------------------------------------------------------- mixed block-level / inline-level children
add("mixed/block-between", B({ width: 200 }, ib(30, 10), ib(30, 20), box(100, 15), ib(30, 10)));
add("mixed/block-first-last", B({ width: 200 }, box(100, 15, { marginBottom: 6 }), ib(30, 10), ib(30, 20), box(50, 5, { marginTop: 4 })));
add("mixed/align", B({ width: 200, textAlign: "center" }, ib(30, 10), box(100, 15), ib(30, 10), ib(40, 10)));
add("mixed/display-none", B({ width: 200 }, ib(30, 10), IB({ display: "none", width: 50, height: 50 }), ib(30, 20)));

// ---------------------------------------------------------------- inside flex / grid items, intrinsic sizes
add("ctx/flex-item-row", F({ width: 300 }, B({}, ib(40, 10), ib(50, 30)), B({ flexGrow: 1 }, ib(40, 10), ib(50, 30))));
add("ctx/flex-item-shrinks", F({ width: 150 }, B({}, ib(40, 10), ib(50, 30), ib(30, 10)), box(80, 10, { flexShrink: 0 })));
add("ctx/flex-item-min-content", F({ width: 60 }, B({}, ib(40, 10), ib(50, 30), ib(30, 10)), box(50, 10, { flexShrink: 0 })));
add("ctx/flex-column-center", F({ width: 300, flexDirection: "column", alignItems: "center" }, B({}, ib(40, 10), ib(50, 30)), B({ textAlign: "end", width: 200 }, ib(40, 10))));
add("ctx/flex-baseline", F({ width: 300, alignItems: "baseline" }, B({}, ib(40, 10), ib(50, 30)), box(20, 50), B({ padding: 4 }, ib(10, 5))));
add("ctx/flex-wrap-items", F({ width: 120, flexWrap: "wrap" }, B({}, ib(40, 10), ib(50, 30)), B({}, ib(40, 10), ib(30, 30))));
add("ctx/grid-items", G({ width: 300, gridTemplateColumns: "100px 1fr" }, B({}, ib(40, 10), ib(50, 30), ib(30, 10)), B({ textAlign: "center" }, ib(40, 10), ib(50, 30))));
add("ctx/grid-auto-tracks", G({ width: 300, gridTemplateColumns: "auto auto", justifyContent: "start" }, B({}, ib(40, 10), ib(50, 30)), B({}, ib(20, 10)), B({}, ib(70, 44))));
add("ctx/grid-min-content-track", G({ width: 300, gridTemplateColumns: "min-content max-content" }, B({}, ib(40, 10), ib(50, 30)), B({}, ib(20, 10), ib(25, 10))));
add("ctx/abs-shrink-to-fit", B({ width: 200, height: 100, position: "relative" }, B({ position: "absolute", left: 120, top: 5 }, ib(30, 10), ib(30, 10), ib(30, 10), ib(30, 10))));
add("ctx/nested-rows", B({ width: 200 }, IB({ width: 90, textAlign: "center" }, ib(30, 10), ib(30, 20), ib(40, 10)), IB({ width: 90, verticalAlign: "top" }, ib(30, 10), IB({}, ib(12, 12), ib(12, 30)))));
add("ctx/row-in-ib-in-flex-in-ib", B({ width: 300 }, IB({ padding: 2 }, F({ gap: 4 }, B({}, ib(20, 10), ib(20, 25)), B({}, ib(10, 40)))), ib(10, 10)));
add("ctx/min-height-container", B({ width: 300, minHeight: 80 }, ib(40, 10), ib(50, 30)));
add("ctx/fixed-height-container", B({ width: 100, height: 30 }, ib(40, 10), ib(50, 30), ib(60, 20)));
add("ctx/block-margins-around-row", B({ width: 200 }, box(50, 10, { marginBottom: 12 }), B({}, ib(30, 10)), box(50, 10, { marginTop: 9 })));

// ---------------------------------------------------------------- random
let seed = 20240611;
const rnd = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);
const pick = (...xs) => xs[Math.floor(rnd() * xs.length)];
const maybe = (p, o) => (rnd() < p ? o : {});
function randItem(depth) {
  const st = {
    ...maybe(0.35, { verticalAlign: pick("top", "middle", "bottom", "baseline") }),
    ...maybe(0.25, { margin: pick(3, "2px 6px", "5px 0 1px 4px", -2) }),
    ...maybe(0.2, { padding: pick(2, 5, "1px 7px") }),
    ...maybe(0.1, { borderWidth: pick(1, 2), borderStyle: "solid" }),
  };
  const k = rnd();
  if (depth <= 0 || k < 0.55) return ib(pick(12, 20, 33.5, 47, 60, "25%", "40%"), pick(6, 14, 22.25, 37, 52), st);
  if (k < 0.7) return IF({ ...st, ...maybe(0.4, { flexDirection: "column" }), ...maybe(0.3, { gap: 3 }) }, ...Array.from({ length: 1 + Math.floor(rnd() * 3) }, () => box(pick(10, 18, 26), pick(8, 15, 30))));
  if (k < 0.8) return IB(st, ...Array.from({ length: 1 + Math.floor(rnd() * 2) }, () => box(pick(10, 18, 26), pick(8, 15, 30))));
  // nested row; a single line keeps the first and the last baseline equal
  return IB({ ...st, ...maybe(0.3, { overflow: "hidden" }) }, ...Array.from({ length: 1 + Math.floor(rnd() * 3) }, () => randItem(depth - 1)));
}
for (let i = 0; i < 40; i++) {
  const n = 2 + Math.floor(rnd() * 8);
  add(`rand/row-${i}`, B({ width: pick(120, 180, 240.5, 333), ...maybe(0.5, { textAlign: pick("center", "end", "start") }), ...maybe(0.3, { padding: pick(4, "3px 9px") }) },
    ...(rnd() < 0.3 ? [tk({ fontSize: pick(10, 13, 24, 40), ...maybe(0.5, { lineHeight: pick(1, 1.4, "30px", 2) }) })] : []),
    ...Array.from({ length: n }, () => randItem(2))), [400, 300]);
}

// ---------------------------------------------------------------- run the oracle
for (const cs of cases) annotate(cs.node, { fs: 16, lh: { kind: "normal" }, align: "start" });
const toTakumi = (n) => ({ type: "container", style: { ...n.style, ...(n.tk || {}) }, children: n.children.map(toTakumi) });
const strip = (n) => ({ style: n.style, ...(n.inlineRow ? { inlineRow: n.inlineRow } : {}), children: n.children.map(strip) });
const isInline = (ch) => String(ch.style.display).startsWith("inline-");
const conv = (n, m) => {
  // takumi omits display:none nodes from its result, and reports the anonymous block around each run of
  // inline-level children of a container that also has block-level children: those are flattened away here
  // (positions are absolute); the replay skips its own anonymous rows the same way.
  const live = n.children.filter((ch) => ch.style.display !== "none");
  const mixed = live.some(isInline) && live.some((ch) => !isInline(ch));
  const kids = [];
  let i = 0, j = 0, anon = null;
  for (const ch of n.children) {
    if (ch.style.display === "none") { kids.push({ x: 0, y: 0, w: 0, h: 0, none: true }); continue; }
    if (mixed && isInline(ch)) {
      if (!anon) { anon = m.children[i++]; j = 0; }
      kids.push(conv(ch, anon.children[j++]));
      continue;
    }
    if (anon && j !== anon.children.length) throw new Error("anonymous child count mismatch");
    anon = null;
    kids.push(conv(ch, m.children[i++]));
  }
  if (i !== m.children.length) throw new Error("child count mismatch");
  return { x: m.transform[4], y: m.transform[5], w: m.width, h: m.height, ...(kids.length ? { children: kids } : {}) };
};
const out = [];
for (const cs of cases) {
  const m = await r.measure(toTakumi(cs.node), { width: cs.vp[0], height: cs.vp[1] });
  try {
    out.push({ name: cs.name, vp: cs.vp, node: strip(cs.node), expect: conv(cs.node, m) });
  } catch (e) {
    console.error("skip", cs.name, e.message);
  }
}
const only = process.argv[2];
if (only) {
  for (const o of out) if (o.name.includes(only)) console.log(JSON.stringify(o, null, 1));
} else {
  writeFileSync("../../../src/layout/testdata/oracle_inline.json", JSON.stringify(out));
  console.log("wrote", out.length, "cases");
}
