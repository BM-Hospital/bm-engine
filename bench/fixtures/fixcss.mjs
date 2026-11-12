// fix-css: CSS cascade / Tailwind / output-correctness regressions (structural selectors with text
// nodes, white-space-only text dropping, transforms in measure, image-rendering, Tailwind theme /
// space-* / animate-* / arbitrary properties, cascade layers). Every case is checked against takumi.
import { asset } from "./_h.mjs";

const FONT = "font-family: Inter;";

// ------------------------------------------------------------------------------------- 1. text nodes vs selectors
// takumi's selector DOM skips untagged text nodes as siblings (matching.rs `element_from`): text nodes with a
// class still match, but never count for :first-child / :nth-child / + / ~. A tagName makes them elements.
// White-space-only text (also a styled text element) not preceded by in-flow inline content is dropped
// (tree.rs `drop_collapsible_boundary_whitespace`).
const structCss = `
  .list { display: flex; flex-direction: column; width: 100%; height: 100%; padding: 20px; gap: 6px; background: #fff; ${FONT} }
  .row { display: flex; gap: 6px; }
  .x { display: block; height: 14px; width: 60px; background: #cbd5e1; }
  .x:first-child { height: 24px; background: #22c55e; }
  .x:last-child { height: 34px; background: #6366f1; }
  .x:nth-child(2) { width: 90px; }
  .x:nth-last-child(2) { border: 3px solid #0f172a; }
  .x:nth-of-type(1) { border-radius: 8px; }
  .x + .x { margin-left: 8px; }
  .y ~ .y { background: #f97316; }
  .x:only-child { background: #ec4899; }
  .e { display: block; height: 10px; width: 40px; background: red; }
`;
const T = (cls, text, extra = {}) => ({ type: "text", className: cls, text, ...extra });
const C = (cls) => ({ type: "container", className: cls, children: [] });
const item1 = [
  {
    id: "fix-css-struct-text-nodes", feature: "css-stylesheet", title: "structural pseudo-classes and sibling combinators: untagged text, tagged text and container siblings", width: 640, height: 420,
    opts: { css: [structCss] },
    node: { type: "container", className: "list", children: [
      { type: "container", className: "row", children: [T("x", "a"), T("x", "b"), T("x", "c")] },
      { type: "container", className: "row", children: ["a", "b", "c", "d"].map((s) => T("x", s, { tagName: "span" })) },
      { type: "container", className: "row", children: [C("x"), T("x", "t"), C("x"), T("x y", "u", { tagName: "i" }), C("x y")] },
      { type: "container", className: "row", children: [T("x", "o", { tagName: "b" })] },
      { type: "container", className: "row", children: [T("x y", "p", { tagName: "p" }), { type: "text", text: "bare" }, T("x y", "q", { tagName: "p" })] },
    ] },
  },
  {
    id: "fix-css-blank-text-dropped", feature: "css-stylesheet", title: "empty / white-space-only text nodes (also with class + display:block) generate no box", width: 480, height: 240,
    opts: { css: [structCss] },
    node: { type: "container", className: "list", children: [
      { type: "container", style: { display: "block" }, children: [T("e", ""), C("x"), T("e", "  "), T("x", "", { tagName: "span" }), { type: "text", text: " " }] },
      { type: "container", className: "row", children: [T("e", " "), C("x"), T("e", ""), C("x")] },
      { type: "container", style: { display: "block" }, children: [{ type: "text", text: "inline", style: { fontFamily: "Inter" } }, T("e", " ")] },
    ] },
  },
  {
    id: "fix-css-tw-structural-text", feature: "tailwind", title: "Tailwind first:/last:/odd:/even: on tagged and untagged text nodes", width: 560, height: 300,
    node: { type: "container", tw: "flex flex-col w-full h-full p-5 gap-2 bg-white", style: { fontFamily: "Inter" }, children: [
      { type: "container", tw: "flex gap-2", children: ["A", "B", "C", "D"].map((s) => ({ type: "text", tagName: "span", text: s, tw: "flex w-16 h-10 bg-gray-200 odd:bg-amber-300 even:bg-sky-300 first:rounded-xl last:border-4 last:border-black" })) },
      { type: "container", tw: "flex gap-2", children: ["A", "B", "C"].map((s) => ({ type: "text", text: s, tw: "flex w-16 h-10 bg-gray-200 even:bg-sky-300 first:rounded-xl last:border-4 last:border-black" })) },
      { type: "container", tw: "flex gap-2", children: [{ type: "text", text: "", tw: "block w-8 h-8 bg-red-500" }, ...["A", "B"].map((s) => ({ type: "container", tw: "flex w-16 h-10 bg-gray-200 first:bg-emerald-400 last:bg-indigo-400", children: [{ type: "text", text: s }] }))] },
    ] },
  },
  {
    id: "fix-css-playground-css-demo", feature: "css-stylesheet", title: "playground css-demo template (tagName div children: nth-child / first / last now apply)", width: 800, height: 500,
    opts: { css: [`.list { display: flex; flex-direction: column; width: 100%; height: 100%; padding: 28px; gap: 10px; background: #ffffff; font-family: Inter; }
.item { display: flex; padding: 12px 20px; font-size: 26px; border-radius: 10px; color: #111827; }
.item:nth-child(odd) { background: #dbeafe; }
.item:nth-child(even) { background: #fce7f3; }
.item:first-child { font-weight: 700; }
.item:last-child { border: 3px solid #111827; }
.item:nth-child(3n) { padding-left: 64px; }
.item.muted { color: #6b7280; }
@media (min-width: 900px) { .list { background: #f0fdf4; } .item { font-size: 30px; } }`] },
    node: { type: "container", className: "list", children: ["Alpha (first-child)", "Beta (even)", "Gamma (3n, muted)", "Delta", "Epsilon", "Zeta (last-child)"].map((s, i) => ({ type: "text", tagName: "div", className: i === 2 ? "item muted" : "item", text: s })) },
  },
];

// ------------------------------------------------------------------------------------- 2. transforms (measure)
// measure() reports takumi's composed matrix (parent * T(location) * local transform); these are also pixel
// fixtures. Exact measure JSON: bench/probe/fixcss/measure_cmp.mjs.
const xbox = (style, children = []) => ({ type: "container", style: { display: "flex", width: 90, height: 60, backgroundColor: "#6366f1", ...style }, children });
const item2 = [
  {
    id: "fix-css-transform-nested", feature: "transform", title: "nested transforms: scale > rotate+translate > child, individual translate / rotate / scale, transform-origin", width: 520, height: 320,
    node: { type: "container", style: { display: "flex", width: "100%", height: "100%", padding: 40, gap: 60, backgroundColor: "#f8fafc" }, children: [
      xbox({ transform: "scale(1.4)", padding: 8, backgroundColor: "#cbd5e1" }, [xbox({ width: 40, height: 30, transform: "rotate(90deg) translate(6px, 4px)", backgroundColor: "#f97316" }, [xbox({ width: 12, height: 12, marginLeft: 6, backgroundColor: "#0f172a" })])]),
      xbox({ translate: "10px 20%", rotate: "-30deg", scale: "1.2 0.8", transformOrigin: "0 0" }),
      xbox({ transform: "skew(10deg, 5deg) rotate(-37.5deg)", transformOrigin: "25% 80%", backgroundColor: "#22c55e" }),
    ] },
  },
  {
    id: "fix-css-transform-abs-text", feature: "transform", title: "rotated relative box with a scaled absolute child and skewed text", width: 420, height: 260,
    node: { type: "container", style: { display: "flex", width: "100%", height: "100%", padding: 50, backgroundColor: "#fff" }, children: [
      xbox({ position: "relative", width: 200, height: 120, transform: "rotate(8deg)", backgroundColor: "#e0e7ff", flexDirection: "column" }, [
        { type: "text", text: "Skewed text", style: { fontFamily: "Inter", fontSize: 26, transform: "skewX(-12deg)", color: "#1e1b4b" } },
        xbox({ position: "absolute", right: 10, bottom: 10, width: 24, height: 24, transform: "scale(1.5) rotate(45deg)", backgroundColor: "#ec4899" }),
      ]),
    ] },
  },
];

// ------------------------------------------------------------------------------------- 5. image-rendering
// pixelated / crisp-edges / optimizeSpeed = takumi `ImageScalingAlgorithm::Pixelated`: nearest-neighbour downscale
// on decode and nearest sampling on draw (img nodes and background images); auto / smooth unchanged.
const pixImgs = () => [{ src: "img://icon", data: asset("icon.png") }, { src: "img://photo", data: asset("photo.jpg") }, { src: "img://avatar", data: asset("avatar.png") }];
const irRow = (ir) => ({ type: "container", style: { display: "flex", gap: 10, alignItems: "flex-start" }, children: [
  { type: "image", src: "img://icon", style: { width: 230, height: 170, imageRendering: ir } },
  { type: "image", src: "img://photo", style: { width: 120, height: 80, objectFit: "cover", imageRendering: ir } },
  { type: "container", style: { width: 150, height: 110, backgroundImage: "url(img://avatar)", backgroundSize: "47px 37px", imageRendering: ir } },
] });
const item5 = [
  {
    id: "fix-css-image-rendering-pixelated", feature: "images", title: "image-rendering: pixelated on an upscaled PNG, a downscaled JPEG and a tiled background image", width: 560, height: 210, images: pixImgs(),
    node: { type: "container", style: { display: "flex", width: "100%", height: "100%", padding: 12, backgroundColor: "#fff" }, children: [irRow("pixelated")] },
  },
  {
    id: "fix-css-image-rendering-modes", feature: "images", title: "auto vs crisp-edges vs optimizeSpeed (inherited from the parent)", width: 560, height: 600, images: pixImgs(),
    node: { type: "container", style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", padding: 12, gap: 12, backgroundColor: "#f1f5f9" }, children: [
      irRow("auto"), irRow("crisp-edges"),
      { type: "container", style: { display: "flex", imageRendering: "optimizeSpeed" }, children: [{ type: "image", src: "img://icon", style: { width: 300, height: 150, objectFit: "contain", objectPosition: "left" } }] },
    ] },
  },
];

// ------------------------------------------------------------------------------------- 6. Tailwind
// (a) theme variables (`@theme` = `:root`, or set on a node) feed utilities only when defined (takumi `TwVarRef`):
// colours (+ opacity modifier, palette overrides, gradient stops), --spacing / --spacing-*, --radius-*, --text-*,
// --container-*, --animate-*, --breakpoint-*. (c) animate-* presets / arbitrary. (f) cascade: named @layer < tw <
// unlayered rules; !important reversed.
const themeCss = `@theme {
  --color-brand-500: #7c3aed; --color-red-500: #059669; --spacing: 3px; --spacing-big: 26px; --radius-blob: 22px 4px;
  --text-huge: 34px; --text-huge--line-height: 40px; --container-card: 150px; --breakpoint-tab: 300px; --breakpoint-md: 2000px;
}`;
const tw = (t, extra = {}) => ({ type: "container", tw: t, children: [], ...extra });
const item6 = [
  {
    id: "fix-css-tw-theme", feature: "tailwind", title: "@theme tokens: brand colour (+ /50), palette override, --spacing, --spacing-*, --radius-*, --text-*, --container-*, --breakpoint-*", width: 640, height: 360,
    opts: { css: [themeCss] },
    node: { type: "container", tw: "flex flex-col w-full h-full p-4 gap-big bg-white", style: { fontFamily: "Inter" }, children: [
      { type: "container", tw: "flex gap-4", children: [tw("w-16 h-16 bg-brand-500 rounded-blob"), tw("w-16 h-16 bg-brand-500/50"), tw("w-16 h-16 bg-red-500"), tw("w-big h-16 bg-linear-to-r from-red-500 to-brand-500"), tw("w-16 h-16 border-4 border-brand-500 -ml-big")] },
      { type: "text", text: "Huge brand text", tw: "text-huge text-brand-500 max-w-card" },
      { type: "container", tw: "flex gap-2", children: [tw("w-10 h-10 bg-gray-300 tab:bg-brand-500"), tw("w-10 h-10 bg-gray-300 md:bg-red-500"), tw("w-10 h-10 bg-gray-300 sm:bg-sky-500")] },
    ] },
  },
  {
    id: "fix-css-tw-theme-node-vars", feature: "tailwind", title: "theme variables set on nodes (inherited), undefined tokens stay no-ops", width: 480, height: 200,
    node: { type: "container", tw: "flex gap-3 p-4 w-full h-full bg-slate-50", style: { "--color-accent": "#f43f5e", "--spacing-gutter": "18px" }, children: [
      tw("w-16 h-16 bg-accent p-gutter"), tw("w-16 h-16 bg-sky-500 bg-nothing"), tw("w-16 h-16 bg-accent/40 rounded-xl", { style: { "--color-accent": "#22c55e" } }), tw("w-gutter h-16 bg-zinc-800"),
    ] },
  },
  {
    id: "fix-css-tw-animate", feature: "tailwind", title: "animate-spin / ping / pulse / bounce / animate-[...] / --animate-* at timeMs 350", width: 560, height: 160,
    opts: { timeMs: 350, css: ["@keyframes wig { from { width: 20px } to { width: 60px } } @theme { --animate-wobble: wig 1s linear infinite; }"] },
    node: { type: "container", tw: "flex items-center gap-8 p-8 w-full h-full bg-white", children: [
      tw("w-12 h-12 bg-indigo-500 animate-spin"), tw("w-12 h-12 bg-rose-500 animate-ping"), tw("w-12 h-12 bg-amber-500 animate-pulse"), tw("w-12 h-12 bg-emerald-500 animate-bounce"),
      tw("w-12 h-12 bg-sky-500 animate-[wig_700ms_ease-in-out_infinite]"), tw("w-12 h-12 bg-fuchsia-500 animate-wobble"),
    ] },
  },
  {
    id: "fix-css-cascade-layers-tw", feature: "css-stylesheet", title: "named @layer < tw < unlayered rules; !important: unlayered < tw < layers", width: 560, height: 120,
    opts: { css: ["@layer base, components; @layer components { .a { background-color: #2563eb; } .d { background-color: #2563eb !important; } } .b { background-color: #2563eb; } .c { background-color: #2563eb !important; } @layer base { .e { width: 90px; } }"] },
    node: { type: "container", tw: "flex gap-4 p-6 w-full h-full bg-white", children: [
      tw("w-16 h-16 bg-red-500", { className: "a" }), tw("w-16 h-16 bg-red-500", { className: "b" }), tw("w-16 h-16 !bg-red-500", { className: "c" }), tw("w-16 h-16 !bg-red-500", { className: "d" }), tw("w-16 h-16 bg-red-500", { className: "e" }),
    ] },
  },
];

// ------------------------------------------------------------------------------------- 7. em with an animated font-size
const item7 = [0, 500].map((t) => ({
  id: `fix-css-anim-font-size-em-t${t}`, feature: "animation", title: `own em lengths follow an animated font-size (t=${t})`, width: 300, height: 160,
  opts: { timeMs: t, css: ["@keyframes fs { from { font-size: 10px } to { font-size: 30px } } .a { animation: fs 1000ms linear; width: 3em; height: 2em; border-radius: 0.5em; background: #6366f1; } .b { animation: fs 1000ms linear; padding: 0.5em; background: #fde68a; } .c { width: 2em; height: 1em; background: #0f172a; }"] },
  node: { type: "container", style: { display: "flex", gap: 12, padding: 12, width: "100%", height: "100%", backgroundColor: "#fff" }, children: [{ type: "container", className: "a", children: [] }, { type: "container", className: "b", children: [{ type: "container", className: "c", children: [] }] }] },
}));

export default [...item1, ...item2, ...item5, ...item6, ...item7];
