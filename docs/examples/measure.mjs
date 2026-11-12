// Examples for docs/{en,vi}/measure.md. Run: node docs/examples/run-all.mjs measure
import { saver } from "./_lib.mjs";
const save = saver("measure");
const log = (label, value) => console.log(label, JSON.stringify(value));

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
// #endregion

// #region basic
const card = {
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 8, width: 320, padding: 16, fontFamily: "Inter", fontSize: 16 },
  children: [
    { type: "text", text: "Release notes", style: { fontSize: 24, fontWeight: 700 } },
    { type: "text", text: "Faster PNG encoding and a smaller core build." },
  ],
};
const measured = renderer.measureSync(card, { width: 400, height: 200 });
// #endregion
log("basic", measured);

// #region intrinsic
// Without width / height the root is laid out at its max-content size: the result is
// the size the image would have if you rendered it without a canvas size.
const label = { type: "text", text: "Hello bm-engine", style: { fontFamily: "Inter", fontSize: 32, fontWeight: 700 } };
const { width, height } = renderer.measureSync(label); // { width: 258.71875, height: 39 }
const tight = renderer.renderSync(label); // a 259 × 39 PNG
// #endregion
log("intrinsic", { width, height });
save("intrinsic", tight);

// #region runs
// Text inside a block container belongs to that container: there is no child for the
// text node, and every inline fragment on a line is a separate run.
const paragraph = {
  type: "container",
  style: { display: "block", width: 260, padding: 20, border: "4px solid #e2e8f0", fontFamily: "Inter", fontSize: 16 },
  children: [
    { type: "text", text: "Runs are reported per line and per inline " },
    { type: "container", style: { fontWeight: 700, color: "#dc2626" }, children: [{ type: "text", text: "fragment" }] },
    { type: "text", text: ", relative to the content box." },
  ],
};
const p = renderer.measureSync(paragraph, { width: 300, height: 140 });
// p.children: []   p.runs: [{ x: 0, y: 0, width: 196.359375, height: 20 }, ...] (5 runs)
// #endregion
log("runs", p);

// #region overlay
// Draw the measured geometry on top of the rendered tree: boxes in blue, text runs in red.
// Runs are relative to the owner's content box, so add its border + padding (here 4 + 20).
function overlay(node, m, contentOffset) {
  const boxes = [];
  const walk = (n, inset) => {
    const [, , , , x, y] = n.transform;
    boxes.push({ type: "container", style: { position: "absolute", left: x, top: y, width: n.width, height: n.height, border: "1px solid #2563eb" } });
    for (const r of n.runs) {
      boxes.push({ type: "container", style: { position: "absolute", left: x + inset + r.x, top: y + inset + r.y, width: r.width, height: r.height, backgroundColor: "rgba(239,68,68,0.25)" } });
    }
    n.children.forEach((c) => walk(c, 0));
  };
  walk(m, contentOffset);
  return { type: "container", style: { display: "block", position: "relative", width: "100%", height: "100%", backgroundColor: "#fff" }, children: [node, ...boxes] };
}
const overlayPng = renderer.renderSync(overlay(paragraph, p, 24), { width: 300, height: 140 });
// #endregion
save("overlay", overlayPng);

// #region fit
// Auto-shrink: the largest font size (between min and max) at which the title fits
// in `maxLines` lines of a box `boxWidth` px wide. Each probe is a layout-only measure.
function fitFontSize(text, { boxWidth, maxLines, min = 12, max = 64, fontWeight = 700 }) {
  const lines = (fontSize) => {
    const m = renderer.measureSync(
      { type: "container", style: { display: "block", width: boxWidth, fontFamily: "Inter", fontWeight, fontSize, lineHeight: 1.15 },
        children: [{ type: "text", text }] },
      { width: boxWidth, height: 1000 },
    );
    return new Set(m.runs.map((r) => r.y)).size; // distinct line positions
  };
  let lo = min, hi = max;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (lines(mid) <= maxLines) lo = mid; else hi = mid - 1;
  }
  return lo;
}

const titles = ["Ship it", "Rendering OG images in WebAssembly", "A much longer headline that has to shrink before it fits in two lines"];
const cards = titles.map((title) => {
  const fontSize = fitFontSize(title, { boxWidth: 200, maxLines: 2 });
  return {
    type: "container",
    style: { display: "flex", flexDirection: "column", justifyContent: "space-between", width: 232, height: 150, padding: 16, borderRadius: 12, backgroundColor: "#1e1b4b", color: "#fff", fontFamily: "Inter" },
    children: [
      { type: "text", text: title, style: { fontSize, fontWeight: 700, lineHeight: 1.15 } },
      { type: "text", text: `fontSize ${fontSize}px`, style: { fontSize: 13, color: "#a5b4fc" } },
    ],
  };
});
const fitted = renderer.renderSync(
  { type: "container", style: { display: "flex", gap: 12, padding: 12, width: "100%", height: "100%", backgroundColor: "#f1f5f9" }, children: cards },
  { width: 744, height: 174 },
);
// #endregion
save("fit", fitted);
log("fit sizes", titles.map((t) => fitFontSize(t, { boxWidth: 200, maxLines: 2 })));

// #region dpr
// Results are in device pixels: devicePixelRatio scales CSS lengths and font sizes.
const box = { type: "container", style: { display: "block", width: 100, height: 20 } };
renderer.measureSync(box, { width: 300, height: 100 }).width; // 100
renderer.measureSync(box, { width: 300, height: 100, devicePixelRatio: 2 }).width; // 200
// #endregion
log("dpr", [renderer.measureSync(box, { width: 300, height: 100 }).width, renderer.measureSync(box, { width: 300, height: 100, devicePixelRatio: 2 }).width]);

// #region transforms
// transform holds the box position only: CSS transforms (rotate, scale, translate) are not
// included in the matrix in 0.1.0; position: relative offsets are.
const moved = renderer.measureSync(
  { type: "container", style: { display: "flex", width: 300, height: 100 }, children: [
    { type: "container", style: { width: 50, height: 50, transform: "translate(10px, 20px) rotate(45deg)" } },
    { type: "container", style: { width: 50, height: 50, position: "relative", left: 7, top: 3 } },
  ] },
);
// moved.children[0].transform: [1, 0, 0, 1, 0, 0]
// moved.children[1].transform: [1, 0, 0, 1, 57, 3]
// #endregion
log("transforms", moved.children.map((c) => c.transform));

// #region html
// HTML strings and stylesheets measure exactly like they render (standard / full).
const fromHtml = renderer.measureSync(
  `<div class="card"><h1>Title</h1><p>Body text</p></div>`,
  { width: 400, height: 300, css: [".card { display: flex; flex-direction: column; padding: 12px; font-family: Inter } h1, p { margin: 0 }"] },
);
// fromHtml is the .card box; fromHtml.children are the h1 and p boxes (canvas coordinates)
// #endregion
log("html", fromHtml);
