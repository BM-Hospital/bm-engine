// Examples for docs/{en,vi}/styles.md. Run: node docs/examples/run-all.mjs styles
import { saver, expectThrow } from "./_lib.mjs";
import assert from "node:assert/strict";
const save = saver("styles");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // stylesheets and Tailwind need the standard or full profile

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
// #endregion

// #region inline
const inlinePng = renderer.renderSync({
  type: "container",
  style: {
    display: "flex",
    alignItems: "center",
    gap: 16,                              // number = px
    padding: "0 24px",                    // string = any CSS value
    width: "100%",
    height: "100%",
    "--accent": "#db2777",                // custom properties keep their dashes
    backgroundColor: "#fdf2f8",
    borderLeft: "8px solid var(--accent)",
    fontFamily: "Inter",                  // inherited by the text below
  },
  children: [
    { type: "text", text: "Inline style", style: { fontSize: 32, fontWeight: 700, color: "var(--accent)" } },
    { type: "text", text: "opacity: 0.6", style: { fontSize: 20, opacity: 0.6 } }, // plain number
  ],
}, { width: 500, height: 100 });
// #endregion
save("inline", inlinePng);

// #region inline-errors
// kebab-case keys and unknown properties are ignored silently
renderer.renderSync({ type: "container", style: { "background-color": "red", colour: "blue" } }, { width: 10, height: 10 });

// an invalid value for a known property throws
expectThrow(() => renderer.renderSync({ type: "container", style: { width: "10 px" } }, { width: 10, height: 10 }));
// "bm-engine: invalid value for style property width"
// #endregion
assert.match(expectThrow(() => renderer.renderSync({ type: "container", style: { width: "10 px" } }, { width: 10, height: 10 })), /invalid value for style property width/);

// #region stylesheet
const css = `
  :root { --brand: #2563eb; --radius: 14px; }
  .card { display: flex; flex-direction: column; gap: 8px; width: 100%; height: 100%; padding: 24px;
          font-family: Inter; background: #eff6ff; border-radius: var(--radius); }
  .card > .title { font-size: 30px; font-weight: 700; color: var(--brand); }
  .tags { display: flex; gap: 8px; }
  .tag { padding: 4px 12px; border-radius: 999px; background: white; color: #1e3a8a; font-size: 16px; }
  .tag:first-child { background: var(--brand); color: white; }
  @media (max-width: 400px) {
    .card { padding: 14px; }
    .card > .title { font-size: 22px; }
  }
`;

const tagged = {
  type: "container",
  className: "card",
  children: [
    { type: "text", className: "title", text: "Stylesheets" },
    { type: "container", className: "tags", children: ["css", "selectors", "@media"].map((t) => ({ type: "text", className: "tag", text: t })) },
  ],
};

const wide = renderer.renderSync(tagged, { width: 560, height: 120, css: [css] });
const narrow = renderer.renderSync(tagged, { width: 360, height: 100, css: [css] }); // @media matches
// #endregion
save("stylesheet-wide", wide);
save("stylesheet-narrow", narrow);

// #region rule-objects
// takumi rule objects: data stays data, no string concatenation
const theme = { brand: "#16a34a" };
const ruleObjects = renderer.renderSync(tagged, {
  width: 560,
  height: 120,
  css: [
    css,
    { selector: ":root", style: { "--brand": theme.brand } },
    { selector: ".card", style: { backgroundColor: "#f0fdf4" } },
  ],
});
// #endregion
save("rule-objects", ruleObjects);

// #region precedence
const widthWith = (node, css = []) => renderer.measureSync(node, { width: 400, height: 100, css }).width;
const base = { type: "container", className: "box", tw: "block w-20 h-5" };   // tw: width 80px

widthWith(base);                                                      // 80  – tw
widthWith(base, [".box { width: 60px }"]);                            // 60  – a stylesheet rule beats tw
widthWith({ ...base, style: { width: 40 } }, [".box { width: 60px }"]); // 40  – inline style beats both
widthWith({ ...base, style: { width: 40 } }, [".box { width: 60px !important }"]); // 60 – !important wins
widthWith({ ...base, tw: "block !w-20 h-5", style: { width: 40 } });  // 80  – a !utility beats inline style
widthWith({ type: "container", preset: { display: "block", width: 30 }, style: { height: 5 } }); // 30 – preset is the lowest layer
// #endregion
assert.equal(widthWith(base), 80);
assert.equal(widthWith(base, [".box { width: 60px }"]), 60);
assert.equal(widthWith({ ...base, style: { width: 40 } }, [".box { width: 60px }"]), 40);
assert.equal(widthWith({ ...base, style: { width: 40 } }, [".box { width: 60px !important }"]), 60);
assert.equal(widthWith({ ...base, tw: "block !w-20 h-5", style: { width: 40 } }), 80);
assert.equal(widthWith({ type: "container", preset: { display: "block", width: 30 }, style: { height: 5 } }), 30);

// #region selectors-tagname
// A type selector only matches nodes that have a tagName; `*`, classes, ids and attributes match any node
const heightWith = (node, css) => renderer.measureSync(node, { width: 100, height: 100, css: [css] }).height;
heightWith({ type: "container" }, "div { display: block; height: 7px }");                   // 0 – no tagName
heightWith({ type: "container", tagName: "div" }, "div { display: block; height: 7px }");   // 7
heightWith({ type: "container", id: "hero" }, "#hero { display: block; height: 7px }");     // 7
heightWith({ type: "container", attributes: { "data-kind": "pro" } }, "[data-kind=pro] { display: block; height: 7px }"); // 7
// #endregion
assert.equal(heightWith({ type: "container" }, "div { display: block; height: 7px }"), 0);
assert.equal(heightWith({ type: "container", tagName: "div" }, "div { display: block; height: 7px }"), 7);
assert.equal(heightWith({ type: "container", id: "hero" }, "#hero { display: block; height: 7px }"), 7);
assert.equal(heightWith({ type: "container", attributes: { "data-kind": "pro" } }, "[data-kind=pro] { display: block; height: 7px }"), 7);

// #region tailwind
const twPng = renderer.renderSync({
  type: "container",
  tw: "flex items-center justify-between w-full h-full px-8 bg-slate-900",
  style: { fontFamily: "Inter" },
  children: [
    { type: "text", text: "Tailwind via tw", tw: "text-3xl font-bold text-white" },
    { type: "text", text: "PRO", tw: "px-3 py-1 rounded-md bg-amber-400/90 text-slate-900 text-sm font-bold" },
  ],
}, { width: 500, height: 100 });
// #endregion
save("tailwind", twPng);

// helpers for the layout examples
const label = (text, extra = {}) => ({ type: "text", text, style: { fontSize: 16, fontWeight: 700, color: "white", ...extra } });

// #region flex
const box = (text, style) => ({
  type: "container",
  style: { display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 8, ...style },
  children: [label(text)],
});
const flexPng = renderer.renderSync({
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 10, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9", fontFamily: "Inter" },
  children: [
    { // a row: fixed, growing and shrinking items
      type: "container",
      style: { display: "flex", gap: 10, height: 60 },
      children: [
        box("120px", { width: 120, backgroundColor: "#0ea5e9" }),
        box("flex: 1", { flex: 1, backgroundColor: "#6366f1" }),
        box("flex: 2", { flex: 2, backgroundColor: "#a855f7" }),
      ],
    },
    { // wrapping, centred
      type: "container",
      style: { display: "flex", flexWrap: "wrap", justifyContent: "center", gap: 8, flex: 1, alignContent: "center" },
      children: ["one", "two", "three", "four", "five", "six", "seven"].map((t) => box(t, { width: 110, height: 34, backgroundColor: "#f97316" })),
    },
  ],
}, { width: 560, height: 200 });
// #endregion
save("flex", flexPng);

// #region grid
const area = (name, color) => ({
  type: "container",
  style: { gridArea: name, display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 8, backgroundColor: color },
  children: [label(name)],
});
const gridPng = renderer.renderSync({
  type: "container",
  style: {
    display: "grid",
    gridTemplateColumns: "120px 1fr 1fr",
    gridTemplateRows: "40px 1fr 30px",
    gridTemplateAreas: '"head head head" "side main main" "side foot foot"',
    gap: 8, padding: 12, width: "100%", height: "100%", backgroundColor: "#f1f5f9", fontFamily: "Inter",
  },
  children: [area("head", "#0f172a"), area("side", "#0d9488"), area("main", "#2563eb"), area("foot", "#64748b")],
}, { width: 560, height: 200 });
// #endregion
save("grid", gridPng);

// #region flow
// Block and inline flow: block boxes stack, inline content wraps into lines
const flowPng = renderer.renderSync({
  type: "container",
  style: { display: "block", padding: 16, width: "100%", height: "100%", backgroundColor: "white", fontFamily: "Inter", fontSize: 18, color: "#1e293b" },
  children: [
    { type: "text", text: "Block flow", style: { display: "block", fontSize: 24, fontWeight: 700, marginBottom: 8 } },
    {
      type: "container",
      style: { display: "block", lineHeight: 1.6 },
      children: [
        { type: "text", text: "Text runs, " },
        { type: "text", text: "styled spans", style: { color: "#be185d", fontWeight: 700 } },
        { type: "text", text: " and an " },
        { type: "container", style: { display: "inline-block", width: 60, height: 18, borderRadius: 9, backgroundColor: "#22c55e", verticalAlign: "middle" } },
        { type: "text", text: " inline-block share the same lines and wrap at the container edge." },
      ],
    },
  ],
}, { width: 560, height: 150 });
// #endregion
save("flow", flowPng);

// #region absolute
const absPng = renderer.renderSync({
  type: "container",
  style: { display: "flex", position: "relative", width: "100%", height: "100%", backgroundColor: "#1e293b", fontFamily: "Inter" },
  children: [
    { type: "container", style: { position: "absolute", top: 16, left: 16, width: 120, height: 80, borderRadius: 10, backgroundColor: "#38bdf8" } },
    { type: "container", style: { position: "absolute", top: 50, left: 90, width: 120, height: 80, borderRadius: 10, backgroundColor: "#f472b6", opacity: 0.9 } },
    { type: "container", style: { position: "absolute", top: 30, left: 50, width: 120, height: 80, borderRadius: 10, backgroundColor: "#facc15", zIndex: 2 } },
    {
      type: "container",
      style: { position: "absolute", right: 16, bottom: 16, padding: "6px 14px", borderRadius: 999, backgroundColor: "#ef4444" },
      children: [label("NEW")],
    },
  ],
}, { width: 400, height: 160 });
// #endregion
save("absolute", absPng);

// #region floats
// floats need the standard or full profile (ignored on core)
const floatPng = renderer.renderSync({
  type: "container",
  style: { display: "block", padding: 16, width: "100%", height: "100%", backgroundColor: "white", fontFamily: "Inter", fontSize: 16, lineHeight: 1.5, color: "#334155" },
  children: [
    { type: "container", style: { float: "left", width: 90, height: 90, marginRight: 14, borderRadius: 12, backgroundImage: "linear-gradient(135deg, #f97316, #db2777)" } },
    { type: "text", text: "This paragraph flows around the floated box: lines beside the float are shorter, and once the float ends the text returns to the full width of the container, as in a browser. Use clear to start below a float." },
  ],
}, { width: 460, height: 170 });
// #endregion
save("floats", floatPng);

// #region colors
const swatch = (color) => ({
  type: "container",
  style: { display: "flex", alignItems: "flex-end", height: 70, padding: 6, borderRadius: 8, backgroundColor: color },
  children: [{ type: "text", text: color, style: { fontSize: 11, color: "white", backgroundColor: "rgb(0 0 0 / 0.45)", padding: "1px 4px", borderRadius: 4 } }],
});
const colorsPng = renderer.renderSync({
  type: "container",
  style: { display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 8, padding: 12, width: "100%", height: "100%", backgroundColor: "#f8fafc", fontFamily: "Inter" },
  children: [
    "tomato", "#0ea5e9", "rgb(34 197 94)", "hsl(270 70% 55%)",
    "oklch(62% 0.2 30)", "color-mix(in oklab, #2563eb 60%, white)", "lab(55% 40 -60)", "rgb(15 23 42 / 0.5)",
  ].map(swatch),
}, { width: 560, height: 190 });
// #endregion
save("colors", colorsPng);

// #region core-colors
import { Renderer as CoreRenderer } from "bm-engine/core";
const core = new CoreRenderer();
expectThrow(() => core.renderSync({ type: "container", style: { width: 10, height: 10, backgroundColor: "oklch(62% 0.2 30)" } }, { width: 10, height: 10 }));
// "bm-engine: invalid value for style property backgroundColor"
// #endregion
assert.match(expectThrow(() => core.renderSync({ type: "container", style: { width: 10, height: 10, backgroundColor: "oklch(62% 0.2 30)" } }, { width: 10, height: 10 })), /invalid value for style property backgroundColor/);
