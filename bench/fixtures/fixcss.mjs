// fix-css: CSS cascade / Tailwind / output-correctness regressions (structural selectors with text
// nodes, white-space-only text dropping, transforms in measure, image-rendering, Tailwind theme /
// space-* / animate-* / arbitrary properties, cascade layers). Every case is checked against takumi.
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

export default [...item1];
