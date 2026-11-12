# measure()

[English](measure.md) · [Tiếng Việt](../vi/measure.md)

`measure()` runs the same style and layout passes as `render()` but stops before painting and encoding.
It returns the size and position of every box and every text run, which is what you need to fit a
headline into a box, size a canvas to its content, or position something relative to laid-out text.
This page explains the result, its coordinate system, its limits in 0.1.0, and walks through an
auto-shrinking title. Every example was run by `docs/examples/measure.mjs`.

[[toc]]

## Calling it

```ts
renderer.measureSync(source, options?): MeasuredNode
renderer.measure(source, options?): Promise<MeasuredNode>
```

`source` and `options` are the same as for [`render`](./api.md#render--rendersync): a node tree, an
HTML string (`standard` / `full`), `{ json }` or a `prepare()` handle, with `width`, `height`, `css`,
`images`, `fontFamilies`, `devicePixelRatio` and, for the async variant, `fonts`. Output options
(`format`, `quality`) are ignored. Fonts must be registered exactly as for rendering: text measured
without a font has zero width.

<!-- @example measure#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
```

## The result

<!-- @example measure#basic -->
```js
const card = {
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 8, width: 320, padding: 16, fontFamily: "Inter", fontSize: 16 },
  children: [
    { type: "text", text: "Release notes", style: { fontSize: 24, fontWeight: 700 } },
    { type: "text", text: "Faster PNG encoding and a smaller core build." },
  ],
};
const measured = renderer.measureSync(card, { width: 400, height: 200 });
```

The returned tree for this card (copied from the script's output):

```json
{
  "width": 320, "height": 109, "transform": [1, 0, 0, 1, 0, 0], "runs": [],
  "children": [
    { "width": 288, "height": 29, "transform": [1, 0, 0, 1, 16, 16], "children": [],
      "runs": [{ "x": 0, "y": 0, "width": 164.109375, "height": 29 }] },
    { "width": 288, "height": 40, "transform": [1, 0, 0, 1, 16, 53], "children": [],
      "runs": [{ "x": 0, "y": 0, "width": 265.84375, "height": 20 },
               { "x": 0, "y": 20, "width": 79.734375, "height": 20 }] }
  ]
}
```

| Field | Meaning |
|:--|:--|
| `width`, `height` | the **border box** of the node, in device pixels (1/64 px precision) |
| `transform` | `[a, b, c, d, e, f]`: a 2D matrix placing the box in the canvas; `e`, `f` are the absolute x / y of the border box's top-left corner |
| `children` | measured child boxes, in tree order |
| `runs` | the text runs this box lays out: `{ x, y, width, height }` |

The two text nodes are flex items here, so each one is a box of its own (288 px wide, the flex
container's content width) and owns its runs. The second text wraps onto two lines: two runs, 20 px apart
(the line height of Inter at 16 px).

## Coordinates

- `transform[4]` and `transform[5]` are **canvas** coordinates, not relative to the parent: the title
  above sits at (16, 16) because of the card's padding, the body text at (16, 53) = 16 + 29 + gap 8.
- A run's `x` and `y` are relative to the **content box** of the box that owns it, so add that box's
  border and padding (and its `transform` position) to get canvas coordinates.
- A run's `height` is the line height, not the glyph extent; takumi reports glyph-box heights here,
  so values differ (positions and widths match).
- Runs have no `text` field in 0.1.0 (takumi's have one). If you need the text of each line, keep it on
  your side or measure the words individually.

### Which boxes appear

Only boxes appear in `children`: block containers, flex and grid items, inline-blocks, images and the
like. Text inside a block container (and the inline containers, the "spans", around it) belongs to that
container: it shows up as **runs of the container**, one run per line **and per inline fragment**:

<!-- @example measure#runs -->
```js
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
```

This paragraph produces five runs on three lines: the second line is split into "and per inline", the
bold "fragment" and the comma. Inline-blocks and images on a line appear as children, with their own
transforms.

### Drawing an overlay from the measurements

Because transforms are absolute, you can turn a measurement into absolutely positioned boxes and draw
them over the original tree. Blue frames are boxes, red rectangles are runs; the runs are shifted by the
paragraph's border and padding (4 + 20 px):

<!-- @example measure#overlay -->
```js
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
```

![A paragraph with its box outlined in blue and every text run highlighted in red](/img/guide/measure-overlay.png)

The same technique places badges after the last line of a title, draws highlight markers behind
specific runs, or produces debug views of a layout.

## Content size and tight canvases

Without `width` / `height`, the root is laid out at its max-content size, and `render()` would produce
an image of exactly that size (rounded up to whole pixels). `measure()` tells you that size in advance:

<!-- @example measure#intrinsic -->
```js
// Without width / height the root is laid out at its max-content size: the result is
// the size the image would have if you rendered it without a canvas size.
const label = { type: "text", text: "Hello bm-engine", style: { fontFamily: "Inter", fontSize: 32, fontWeight: 700 } };
const { width, height } = renderer.measureSync(label); // { width: 258.71875, height: 39 }
const tight = renderer.renderSync(label); // a 259 × 39 PNG
```

![The bold label "Hello bm-engine" on a transparent 259 by 39 canvas](/img/guide/measure-intrinsic.png)

With `width` / `height` set, percentage sizes, `vw` / `vh` and `@media` queries resolve against them, as
in a render.

## Example: auto-shrinking a title

The function below finds, by binary search, the largest font size at which a title fits into two lines
of a 200 px wide box. Each step is one `measureSync` call; line count is the number of distinct run
`y` positions. Then the three cards are rendered with the sizes found:

<!-- @example measure#fit -->
```js
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
```

![Three cards: "Ship it" at 64px, "Rendering OG images in WebAssembly" at 18px, and a long headline at 12px, each filling at most two lines](/img/guide/measure-fit.png)

Tips for fitting text:

- Measure exactly the styles you render with (same font family, weight, `lineHeight`, letter spacing,
  width). A different `lineHeight` changes both the line count and the height.
- Counting lines by distinct `y` works for plain text. With mixed inline content, a line can contain
  several runs, which is why the example uses a `Set`.
- To fit by height instead of line count, compare the root `height` with the space you have.
- A search over 12–64 px needs about six measurements. Layout-only calls skip painting and PNG
  encoding, which is usually most of a render's time (see [Performance](./performance.md)).
- For a single line, measure the text once at a reference size and scale: the width of unwrapped text
  is proportional to the font size up to rounding.

## Device pixel ratio

All values are in **device pixels**: `devicePixelRatio` scales CSS lengths and font sizes, so a 100 px box
measures 200 at a ratio of 2:

<!-- @example measure#dpr -->
```js
// Results are in device pixels: devicePixelRatio scales CSS lengths and font sizes.
const box = { type: "container", style: { display: "block", width: 100, height: 20 } };
renderer.measureSync(box, { width: 300, height: 100 }).width; // 100
renderer.measureSync(box, { width: 300, height: 100, devicePixelRatio: 2 }).width; // 200
```

Text does not always scale exactly: line heights come from the font metrics at the scaled size and are
rounded per size (the body text of the [result section](#the-result) has 20 px lines at ratio 1 and
39 px lines at ratio 2, not 40). Divide by the ratio to get CSS pixels.

## Transforms are not included

::: warning 0.1.0 limitation
`transform` contains only the box position. CSS transforms (`transform`, `translate`, `rotate`, `scale`)
are **not** applied to the matrix; `position: relative` offsets are, because they are part of layout.
takumi includes CSS transforms in this matrix.
:::

<!-- @example measure#transforms -->
```js
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
```

If you need the painted position of a transformed box, apply its transform yourself around its
`transform-origin` (by default the centre of the border box).

## HTML and stylesheets

HTML strings and the `css` option work as for rendering (they need `standard` or `full`). The root of the
result is the root element of the HTML:

<!-- @example measure#html -->
```js
// HTML strings and stylesheets measure exactly like they render (standard / full).
const fromHtml = renderer.measureSync(
  `<div class="card"><h1>Title</h1><p>Body text</p></div>`,
  { width: 400, height: 300, css: [".card { display: flex; flex-direction: column; padding: 12px; font-family: Inter } h1, p { margin: 0 }"] },
);
// fromHtml is the .card box; fromHtml.children are the h1 and p boxes (canvas coordinates)
```

## Errors and edge cases

- Measuring throws for the same reasons rendering does: invalid inline style values, a feature missing
  from the profile (HTML on `core`), malformed nodes. See [API: errors](./api.md#errors).
- Content with zero size and no `width` / `height` throws
  `invalid viewport: content has zero size and no width/height was given`.
- Elements with `display: "none"` still appear in `children`, as 0 × 0 entries at (0, 0), so child
  indexes keep matching the node tree.

See also: [API reference](./api.md#measure--measuresync), [Typography](./typography.md), [Fonts](./fonts.md).
