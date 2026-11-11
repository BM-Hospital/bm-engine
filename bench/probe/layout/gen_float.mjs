// Generates src/layout/testdata/oracle_float.json: block formatting contexts with floats + takumi's layout.
// Usage: node gen_float.mjs [name-filter]      (run from bench/probe/layout)
import { Renderer } from "@takumi-rs/wasm/node";
import { writeFileSync } from "node:fs";

const r = new Renderer();
const cases = [];
const c = (style, ...children) => ({ style, children });
const B = (style, ...ch) => c({ display: "block", ...style }, ...ch);
const F = (style, ...ch) => c({ display: "flex", ...style }, ...ch);
const FL = (w, h, extra = {}) => B({ float: "left", width: w, height: h, ...extra });
const FR = (w, h, extra = {}) => B({ float: "right", width: w, height: h, ...extra });
const add = (name, node, vp = [400, 300]) => cases.push({ name, vp, node });
// "text-like" content: a wrapping flex row of fixed boxes
const words = (n, w = 30, h = 10, extra = {}) => F({ flexWrap: "wrap", ...extra }, ...Array.from({ length: n }, () => F({ width: w, height: h, flexShrink: 0 })));

// ---------------------------------------------------------------- placement
add("place/left", B({ width: 300 }, FL(50, 40), B({ height: 20 })));
add("place/right", B({ width: 300 }, FR(50, 40), B({ height: 20 })));
add("place/left-right", B({ width: 300 }, FL(50, 40), FR(70, 30), B({ height: 20 })));
add("place/stack-left", B({ width: 300 }, FL(50, 40), FL(60, 30), FL(70, 20), B({ height: 10 })));
add("place/stack-right", B({ width: 300 }, FR(50, 40), FR(60, 30), FR(70, 20), B({ height: 10 })));
add("place/wrap-left", B({ width: 200 }, FL(90, 40), FL(90, 30), FL(90, 20), FL(90, 10)));
add("place/wrap-right", B({ width: 200 }, FR(90, 40), FR(90, 30), FR(90, 20), FR(90, 10)));
add("place/wrap-mixed", B({ width: 200 }, FL(90, 40), FR(60, 30), FL(80, 20), FR(90, 10), FL(30, 30)));
add("place/too-wide", B({ width: 200 }, FL(90, 40), FL(250, 30), FL(40, 20)));
add("place/too-wide-right", B({ width: 200 }, FR(90, 40), FR(250, 30), FR(40, 20)));
add("place/staircase", B({ width: 300 }, FL(100, 60), FL(100, 40), FL(100, 20), FL(120, 10), FL(150, 10)));
add("place/not-above-earlier", B({ width: 300 }, FL(200, 20), FL(200, 20), FR(50, 10), FL(20, 10)));
add("place/after-block", B({ width: 300 }, B({ height: 25 }), FL(50, 40), B({ height: 20 }), FR(30, 30), B({ height: 5 })));
add("place/after-margin", B({ width: 300 }, B({ height: 20, marginBottom: 20 }), FL(50, 60), B({ height: 30, marginTop: 30 })));
add("place/margins", B({ width: 300 }, FL(50, 40, { margin: 10 }), FL(50, 40, { margin: "5px 20px" }), FR(40, 20, { marginLeft: 30, marginTop: 7 }), B({ height: 5 })));
add("place/negative-margin", B({ width: 300 }, FL(50, 40, { marginLeft: -10 }), FL(50, 40, { marginTop: -10 }), FR(50, 40, { marginRight: -20 })));
add("place/percent", B({ width: 300 }, FL("30%", 40), FR("50%", 30), FL("30%", 20, { marginLeft: "5%" })));
add("place/padding-container", B({ width: 300, padding: 10, borderWidth: 3, borderStyle: "solid" }, FL(50, 40), FR(60, 30), B({ height: 20 })));
add("place/zero-height", B({ width: 300 }, FL(50, 0), FL(60, 30), B({ height: 10 })));
add("place/zero-width", B({ width: 300 }, FL(0, 40), FL(60, 30), B({ height: 10 })));
add("place/relative", B({ width: 300 }, FL(50, 40, { position: "relative", top: 5, left: 7 }), FL(50, 40)));
add("place/only-floats", B({ width: 300 }, FL(50, 40), FR(60, 70)));
add("place/exact-fit", B({ width: 200 }, FL(100, 40), FL(100, 30), FL(100, 20)));
add("place/fractional", B({ width: 200 }, FL(66.7, 40), FL(66.7, 30), FL(66.7, 20)));

// ---------------------------------------------------------------- shrink-to-fit
add("fit/content", B({ width: 300 }, B({ float: "left" }, F({ width: 70, height: 8 })), B({ float: "right", padding: 5 }, F({ width: 40, height: 8 }))));
add("fit/words", B({ width: 200 }, B({ float: "left" }, words(10)), B({ height: 5 })));
add("fit/words-next-to-float", B({ width: 200 }, FL(90, 30), B({ float: "left" }, words(10)), B({ height: 5 })));
add("fit/min-max", B({ width: 300 }, B({ float: "left", minWidth: 100 }, F({ width: 40, height: 8 })), B({ float: "left", maxWidth: 50 }, words(4))));
add("fit/flex-float", B({ width: 300 }, F({ float: "left", gap: 4 }, F({ width: 40, height: 8 }), F({ width: 20, height: 18 })), B({ height: 5 })));
add("fit/nested-float", B({ width: 300 }, B({ float: "left", padding: 4 }, FL(30, 30), FL(40, 20)), B({ height: 5 })));
add("fit/height-auto", B({ width: 300 }, B({ float: "left", width: 100 }, B({ height: 20 }), B({ height: 30, marginTop: 10 }))));
add("fit/aspect", B({ width: 300 }, B({ float: "left", width: 80, aspectRatio: 2 }), B({ float: "right", height: 30, aspectRatio: 2 })));

// ---------------------------------------------------------------- BFC roots contain floats, others do not
add("contain/root-height", B({ width: 300 }, FL(50, 80), B({ height: 20 })));
add("contain/non-root-overflow", B({ width: 300 }, B({}, FL(50, 80), B({ height: 20 })), B({ height: 10 })));
add("contain/overflow-hidden", B({ width: 300 }, B({ overflow: "hidden" }, FL(50, 80), B({ height: 20 })), B({ height: 10 })));
add("contain/flow-root", B({ width: 300 }, B({ display: "flow-root" }, FL(50, 80), B({ height: 20 })), B({ height: 10 })));
add("contain/flex-item", F({ width: 300, flexDirection: "column" }, B({}, FL(50, 80), B({ height: 20 })), B({ height: 10 })));
add("contain/float-in-float", B({ width: 300 }, B({ float: "left", width: 120 }, FL(50, 80), FR(30, 20)), B({ height: 10 })));
add("contain/abs", B({ width: 300, position: "relative" }, B({ position: "absolute", top: 5, left: 5, width: 100 }, FL(50, 80), B({ height: 10 }))));
add("contain/padding-bottom", B({ width: 300, padding: 6 }, FL(50, 80), B({ height: 20 })));
add("contain/min-height", B({ width: 300, minHeight: 120 }, FL(50, 80)));
add("contain/fixed-height", B({ width: 300, height: 30 }, FL(50, 80), B({ height: 10 })));
add("contain/margin-bottom-vs-float", B({ width: 300 }, FL(50, 40), B({ height: 30, marginBottom: 30 })));
add("contain/empty-with-floats", B({ width: 300 }, B({}, FL(50, 40)), B({ height: 10 })));
add("contain/empty-margins", B({ width: 300 }, B({ height: 10, marginBottom: 10 }), B({ marginTop: 20, marginBottom: 5 }, FL(50, 40)), B({ height: 10, marginTop: 15 })));

// ---------------------------------------------------------------- formatting context roots avoid floats
for (const disp of ["flex", "grid", "flow-root"]) {
  add(`avoid/${disp}-auto`, B({ width: 300 }, FL(50, 60), c({ display: disp, height: 10 })));
  add(`avoid/${disp}-both`, B({ width: 300 }, FL(50, 60), FR(70, 30), c({ display: disp, height: 10 }), c({ display: disp, height: 40 })));
  add(`avoid/${disp}-fixed-fits`, B({ width: 300 }, FL(50, 60), c({ display: disp, height: 10, width: 200 })));
  add(`avoid/${disp}-fixed-too-wide`, B({ width: 300 }, FL(50, 60), c({ display: disp, height: 10, width: 260 }), B({ height: 5 })));
  add(`avoid/${disp}-margin`, B({ width: 300 }, FL(50, 60), c({ display: disp, height: 10, margin: "5px 10px" })));
}
add("avoid/overflow-hidden", B({ width: 300 }, FL(50, 60), FR(40, 20), B({ overflow: "hidden", height: 15 }), B({ overflow: "hidden", height: 15 })));
add("avoid/overflow-hidden-content", B({ width: 200 }, FL(90, 60), B({ overflow: "hidden" }, words(8)), B({ height: 4 })));
add("avoid/min-content-too-wide", B({ width: 200 }, FL(150, 40), F({}, F({ width: 80, height: 10, flexShrink: 0 })), B({ height: 4 })));
add("avoid/step-down", B({ width: 200 }, FL(150, 20), FL(100, 20), FL(50, 20), F({ width: 120, height: 10 })));
add("avoid/plain-block-overlaps", B({ width: 300 }, FL(50, 60), B({ height: 10 }), B({ height: 10, width: 100 }), B({ height: 10, marginLeft: 20 })));
add("avoid/after-margin", B({ width: 300 }, B({ height: 10, marginBottom: 12 }), FL(50, 60), F({ height: 10, marginTop: 20 })));
add("avoid/auto-margins", B({ width: 300 }, FL(50, 60), F({ height: 10, width: 100, margin: "0 auto" }), F({ height: 10, width: 100, marginLeft: "auto" })));
add("avoid/percent-width", B({ width: 300 }, FL(50, 60), F({ height: 10, width: "50%" }), F({ height: 10, width: "100%" })));
add("avoid/float-starts-lower", B({ width: 300 }, B({ height: 10 }), FL(50, 30), F({ height: 80 }), FR(40, 20), F({ height: 10 })));
add("avoid/right-only", B({ width: 300 }, FR(80, 60), F({ height: 10 }), F({ height: 10, width: 250 })));

// ---------------------------------------------------------------- clear
for (const cl of ["left", "right", "both"]) {
  add(`clear/${cl}`, B({ width: 300 }, FL(50, 60), FR(40, 30), B({ clear: cl, height: 10 }), B({ height: 5 })));
  add(`clear/${cl}-float`, B({ width: 300 }, FL(50, 60), FR(40, 30), FL(30, 20, { clear: cl }), FR(30, 20, { clear: cl })));
}
add("clear/margin-top", B({ width: 300 }, FL(50, 60), B({ clear: "left", height: 10, marginTop: 20 }), B({ height: 5 })));
add("clear/margin-top-large", B({ width: 300 }, FL(50, 60), B({ clear: "left", height: 10, marginTop: 100 }), B({ height: 5 })));
add("clear/after-block", B({ width: 300 }, FL(50, 60), B({ height: 20, marginBottom: 15 }), B({ clear: "both", height: 10, marginTop: 5 })));
add("clear/no-floats", B({ width: 300 }, B({ height: 20, marginBottom: 15 }), B({ clear: "both", height: 10, marginTop: 5 })));
add("clear/nested", B({ width: 300 }, FL(50, 60), B({}, B({ clear: "left", height: 10 })), B({ height: 5 })));
add("clear/bfc-root", B({ width: 300 }, FL(50, 60), F({ clear: "left", height: 10 }), B({ height: 5 })));
add("clear/first-child", B({ width: 300 }, FL(50, 60), B({}, B({ height: 5 }), B({ clear: "both", height: 10 }))));

// ---------------------------------------------------------------- nesting inside one formatting context
add("nest/float-in-child", B({ width: 300 }, B({ padding: "0 10px" }, FL(50, 60), B({ height: 10 })), F({ height: 10 }), B({ height: 5 })));
add("nest/float-in-child-margin", B({ width: 300 }, B({}, FL(50, 60), B({ height: 30, marginTop: 20 })), F({ height: 10, width: 260 })));
add("nest/outer-float-inner-root", B({ width: 300 }, FL(50, 60), B({ marginLeft: 10, paddingLeft: 5 }, B({ height: 5 }), F({ height: 10 }), B({ overflow: "hidden", height: 10 }))));
add("nest/outer-float-inner-float", B({ width: 300 }, FL(50, 60), B({ margin: "0 20px" }, FL(30, 30), FR(30, 30), B({ height: 5 })), F({ height: 10 })));
add("nest/deep", B({ width: 300 }, FL(50, 80), B({ paddingLeft: 4 }, B({ marginTop: 10 }, B({ marginTop: 20 }, FL(20, 20), F({ height: 10 }), B({ height: 5, marginTop: 3 }))))));
add("nest/sibling-blocks", B({ width: 300 }, B({}, FL(50, 80)), B({}, F({ height: 10 })), B({}, FR(60, 20), F({ height: 10 })), B({ clear: "both", height: 5 })));
add("nest/float-after-content-in-child", B({ width: 300 }, B({}, B({ height: 15 }), FL(50, 60)), B({ height: 5 }), F({ height: 10 })));
add("nest/padding-child", B({ width: 300 }, FL(50, 60), B({ padding: 8, borderWidth: 2, borderStyle: "solid" }, F({ height: 10 }), FL(20, 20), F({ height: 10 }))));
add("nest/narrow-child", B({ width: 300 }, FL(50, 60), B({ width: 150, marginLeft: 100 }, FL(20, 20), F({ height: 10 }), FR(30, 10), F({ height: 10 }))));
add("nest/child-centered", B({ width: 300 }, FL(50, 60), B({ width: 150, margin: "0 auto" }, FL(20, 20), F({ height: 10 }))));

// ---------------------------------------------------------------- intrinsic sizes with floats
add("intrinsic/flex-item", F({ width: 400 }, B({}, FL(50, 40), FL(60, 30), B({ height: 5, width: 20 })), F({ flexGrow: 1 })));
add("intrinsic/abs", B({ width: 400, position: "relative" }, B({ position: "absolute", left: 0, top: 0 }, FL(50, 40), FR(60, 30))));
add("intrinsic/float-with-floats", B({ width: 400 }, B({ float: "left" }, FL(50, 40), FL(60, 30), FR(20, 10)), B({ height: 5 })));
add("intrinsic/narrow", F({ width: 100 }, B({}, FL(50, 40), FL(60, 30), FL(30, 10))));
add("intrinsic/clear", F({ width: 400 }, B({}, FL(50, 40), FL(60, 30, { clear: "left" }), FL(30, 10))));

// ---------------------------------------------------------------- seeded random
let seed = 20261112;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
const pick = (a) => a[Math.floor(rnd() * a.length) % a.length];
function randFloatTree(depth, width) {
  const kids = [];
  const n = 2 + Math.floor(rnd() * 5);
  for (let i = 0; i < n; i++) {
    const k = rnd();
    if (k < 0.4) {
      const st = { float: pick(["left", "right"]), width: pick([30, 50, 80, 120, "30%"]), height: pick([10, 20, 40, 60]) };
      if (rnd() < 0.25) st.margin = pick([4, "3px 8px", 10]);
      if (rnd() < 0.15) st.clear = pick(["left", "right", "both"]);
      kids.push(B(st));
    } else if (k < 0.55) {
      const st = { height: pick([5, 10, 25]) };
      if (rnd() < 0.3) st.marginTop = pick([5, 12, 20]);
      if (rnd() < 0.3) st.marginBottom = pick([5, 12, 20]);
      if (rnd() < 0.2) st.clear = pick(["left", "right", "both"]);
      kids.push(B(st));
    } else if (k < 0.75) {
      const st = { height: pick([8, 16, 30]) };
      if (rnd() < 0.4) st.width = pick([60, 120, 200, "50%"]);
      if (rnd() < 0.3) st.marginTop = pick([5, 12]);
      kids.push(rnd() < 0.5 ? F(st) : B({ ...st, overflow: "hidden" }));
    } else if (depth > 0) {
      const st = {};
      if (rnd() < 0.3) st.padding = pick([4, "0 10px"]);
      if (rnd() < 0.3) st.marginTop = pick([6, 14]);
      if (rnd() < 0.2) st.marginLeft = 15;
      if (rnd() < 0.25) st.display = "flow-root";
      kids.push(B(st, ...randFloatTree(depth - 1, width)));
    } else kids.push(B({ height: 6 }));
  }
  return kids;
}
for (let i = 0; i < 40; i++) add(`rand/float-${i}`, B({ width: pick([200, 300, 360]) }, ...randFloatTree(2, 300)));

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
  writeFileSync("../../../src/layout/testdata/oracle_float.json", JSON.stringify(out));
  console.log("wrote", out.length, "cases");
}
