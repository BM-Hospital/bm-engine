// Examples for docs/{en,vi}/image/concepts.md. Run: node docs/examples/run-all.mjs concepts
import { saver, expectThrow } from "./_lib.mjs";
import assert from "node:assert/strict";
const save = saver("concepts");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer, features } from "bm-render";

const renderer = new Renderer(); // create once, reuse for every render
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
// #endregion

// #region first
const png = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#4f46e5" },
    children: [{ type: "text", text: "Hello, bm-render", style: { fontFamily: "Inter", fontSize: 40, fontWeight: 700, color: "white" } }],
  },
  { width: 600, height: 200 },
);
// #endregion
save("first", png);

// #region node-format
// a 2 × 2 RGBA image, built in code (raw pixels work on every profile)
const pixels = { width: 2, height: 2, data: new Uint8Array([
  239, 68, 68, 255,   34, 197, 94, 255,
  59, 130, 246, 255,  234, 179, 8, 255,
]) };

const card = {
  type: "container",                                  // a box; may have children
  style: { display: "flex", gap: 24, padding: 32, width: "100%", height: "100%", alignItems: "center", backgroundColor: "#f8fafc" },
  children: [
    { type: "image", src: pixels, width: 96, height: 96, style: { borderRadius: 16 } },        // an image
    {
      type: "container",
      style: { display: "flex", flexDirection: "column", gap: 6 },
      children: [
        { type: "text", text: "Three node types", style: { fontFamily: "Inter", fontSize: 32, fontWeight: 700, color: "#0f172a" } }, // text
        { type: "text", text: "container · text · image", style: { fontFamily: "Inter", fontSize: 22, color: "#475569" } },
        null, // null / undefined children are skipped
      ],
    },
  ],
};
const nodePng = renderer.renderSync(card, { width: 600, height: 160 });
// #endregion
save("node-format", nodePng);

// #region inputs
// 1. a node tree (every profile)
const fromTree = renderer.renderSync({
  type: "container",
  style: { display: "flex", width: "100%", height: "100%", padding: 24, backgroundColor: "#0f172a" },
  children: [{ type: "text", text: "Node tree", style: { fontFamily: "Inter", fontSize: 36, color: "#38bdf8" } }],
}, { width: 300, height: 100 });

// 2. an HTML string (standard / full): every JS string source is parsed as HTML
const fromHtml = renderer.renderSync(
  `<div style="display:flex; width:100%; height:100%; padding:24px; background:#0f172a">
     <span style="font-family:Inter; font-size:36px; color:#a3e635">HTML string</span>
   </div>`,
  { width: 300, height: 100 },
);

// 3. Tailwind classes in `tw` (standard / full), on a node tree or as a tw="" attribute in HTML
const fromTw = renderer.renderSync({
  type: "container",
  tw: "flex w-full h-full p-6 bg-slate-900",
  children: [{ type: "text", text: "Tailwind", tw: "text-4xl text-pink-400", style: { fontFamily: "Inter" } }],
}, { width: 300, height: 100 });

// 4. JSON text: wrap it, because a plain string would be parsed as HTML
const fromJson = renderer.renderSync({ json: '{"type":"container","style":{"width":300,"height":100,"backgroundColor":"#0f172a"}}' });
// #endregion
save("input-tree", fromTree);
save("input-html", fromHtml);
save("input-tw", fromTw);
assert.equal(fromJson[19], 44); // IHDR width low byte (300 = 0x12c)

// #region display-default
const twoSquares = (display) => ({
  type: "container",
  style: { display, gap: 10, padding: 10, backgroundColor: "#e2e8f0" },
  children: [
    { type: "container", style: { width: 50, height: 50, backgroundColor: "#f97316" } },
    { type: "container", style: { width: 50, height: 50, backgroundColor: "#8b5cf6" } },
  ],
});
// wrap the box in a block parent and measure how tall the parent becomes
const heightOf = (display) =>
  renderer.measureSync({ type: "container", style: { display: "block" }, children: [twoSquares(display)] }, { width: 200, height: 100 }).height;

heightOf(undefined); // 20 – default display is inline: width / height of the box and of its inline children are
                     //      ignored; only one line remains (the padded inline box makes it a non-empty line)
heightOf("block");   // 20 – only the padding: the children are still inline
heightOf("flex");    // 70 – flex items are blockified: 50 + 2 × 10 padding
// #endregion
assert.equal(heightOf(undefined), 20);
assert.equal(heightOf("block"), 20);
assert.equal(heightOf("flex"), 70);

// #region display-image
const row = (display, label) => ({
  type: "container",
  style: { display: "flex", alignItems: "center", gap: 16 },
  children: [
    { type: "text", text: label, style: { fontFamily: "Inter", fontSize: 18, width: 170, color: "#334155" } },
    // a block wrapper, so that twoSquares is not itself a (blockified) flex item
    { type: "container", style: { display: "block", width: 140 }, children: [twoSquares(display)] },
  ],
});
const displayPng = renderer.renderSync({
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 12, padding: 16, width: "100%", height: "100%", backgroundColor: "white" },
  children: [row(undefined, "display: (default)"), row("block", "display: block"), row("flex", "display: flex")],
}, { width: 420, height: 180 });
// #endregion
save("display", displayPng);

// #region box-sizing
const boxes = renderer.measureSync({
  type: "container",
  style: { display: "flex", gap: 10 },
  children: [
    { type: "container", style: { width: 100, height: 40, padding: 10, border: "5px solid black" } },
    { type: "container", style: { width: 100, height: 40, padding: 10, border: "5px solid black", boxSizing: "content-box" } },
  ],
}, { width: 400, height: 100 });
boxes.children.map((c) => `${c.width}×${c.height}`); // [ '100×40', '130×70' ]
// #endregion
assert.deepEqual(boxes.children.map((c) => `${c.width}×${c.height}`), ["100×40", "130×70"]);

// #region units
const unitBox = (width) => ({ type: "container", style: { display: "block", width, height: 10 } });
const widthOf = (width, options = {}) => renderer.measureSync(unitBox(width), { width: 400, height: 100, ...options }).width;

widthOf(120);                       // 120 – a number is px
widthOf("50%");                     // 200 – of the canvas width
widthOf("25vw");                    // 100 – vw / vh refer to the canvas
widthOf("2rem");                    // 32  – root font size is 16px
widthOf("calc(100% - 2 * 24px)");   // 352
widthOf(120, { devicePixelRatio: 2 }); // 240 – CSS px are scaled, the canvas is not
// #endregion
assert.equal(widthOf(120), 120);
assert.equal(widthOf("50%"), 200);
assert.equal(widthOf("25vw"), 100);
assert.equal(widthOf("2rem"), 32);
assert.equal(widthOf("calc(100% - 2 * 24px)"), 352);
assert.equal(widthOf(120, { devicePixelRatio: 2 }), 240);

// #region canvas
// No width / height: the canvas takes the size of the root box
const auto = renderer.renderSync({ type: "container", style: { width: 240, height: 60, backgroundColor: "#22c55e" } });
// auto is a 240 × 60 PNG

// Empty content and no size is an error
expectThrow(() => renderer.renderSync({ type: "container" }));
// "bm-render: invalid viewport: content has zero size and no width/height was given"
// #endregion
assert.equal((auto[18] << 8) | auto[19], 240);
assert.match(expectThrow(() => renderer.renderSync({ type: "container" })), /content has zero size/);

// #region dpr
const badge = {
  type: "container",
  style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#fef3c7", borderRadius: 12 },
  children: [{ type: "text", text: "Retina", style: { fontFamily: "Inter", fontSize: 24, fontWeight: 700, color: "#92400e" } }],
};
const x1 = renderer.renderSync(badge, { width: 160, height: 60 });
// same design, twice the pixels: double the canvas AND set devicePixelRatio
const x2 = renderer.renderSync(badge, { width: 320, height: 120, devicePixelRatio: 2 });
// #endregion
save("dpr-1x", x1);
save("dpr-2x", x2);

// #region lifecycle
// Renderers are cheap; fonts are not. Keep one renderer per font set and reuse it.
const r = new Renderer();
r.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf")); // family name read from the font: "Inter"

for (let i = 0; i < 3; i++) {
  r.renderSync({ type: "text", text: `card ${i}`, style: { fontFamily: "Inter" } }, { width: 200, height: 40 });
}
r.memoryBytes(); // size of the wasm memory shared by every renderer of this entry, in bytes

r.free();        // releases its fonts and caches; r can no longer be used
expectThrow(() => r.renderSync({ type: "container" }, { width: 10, height: 10 }));
// "bm-render: renderer has been freed"

{
  using scoped = new Renderer(); // free() is called at the end of the block
  scoped.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
}
// #endregion
assert.match(expectThrow(() => r.renderSync({ type: "container" }, { width: 10, height: 10 })), /freed/);

// #region features
features.html;        // true on standard / full
features.complexText; // true on full only
// #endregion
assert.equal(features.html, true);
console.log("memory", renderer.memoryBytes());
