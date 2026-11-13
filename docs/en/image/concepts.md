# How bm-engine works

[English](concepts.md) · [Tiếng Việt](../../vi/image/concepts.md)

This page explains the model behind every render: what goes in (a node tree, an HTML string or Tailwind
classes), the stages the engine runs (style, layout, paint, encode), the defaults that surprise people
coming from the browser, and how renderers and memory behave over the life of a process. Read it once
before the topic pages ([Styles](./styles.md), [Fonts](./fonts.md), [Typography](./typography.md),
[Images](./images.md), ...). Every snippet below is part of `docs/examples/concepts.mjs` and was run
against the package; the images are its output.

[[toc]]

## The pipeline

A call such as `renderer.renderSync(source, options)` runs five stages, all inside one WebAssembly
module and all synchronous:

| Stage | What happens | Inputs that matter |
|:--|:--|:--|
| 1. Input | The source becomes an element tree. A node object is read directly, `{ json }` is parsed, a string is parsed as HTML (standard / full). | `source` |
| 2. Style | Each element gets its computed style: user-agent defaults (`preset`, HTML tags), stylesheet rules (`css`, `<style>`), Tailwind utilities (`tw`), inline `style`, then inheritance, `var()` and `calc()`. | `css`, `tw`, `style`, `devicePixelRatio`, `timeMs` |
| 3. Layout | Boxes get positions and sizes: block and inline flow with line breaking and text shaping, flexbox, grid, tables, floats, absolute positioning. Units are device pixels with 1/64 px precision. | `width`, `height`, registered fonts |
| 4. Paint | Backgrounds, borders, shadows, images, glyphs, filters and effects are rasterised into an RGBA canvas (anti-aliased with 4×4 supersampling, like takumi). | `images` |
| 5. Encode | The canvas becomes PNG, JPEG, WebP, ICO or stays raw RGBA. `renderSvg` replaces paint + encode with SVG output; `measure` stops after layout. | `format`, `quality` |

Nothing in the pipeline touches the network, the file system or system fonts: every font and every
image byte comes from your JavaScript (see [Images](./images.md) and [Fonts](./fonts.md)).

Here is the smallest complete program. Create the renderer once, register the fonts once, render as
often as you like:

<!-- @example concepts#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer, features } from "bm-engine";

const renderer = new Renderer(); // create once, reuse for every render
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

<!-- @example concepts#first -->
```js
const png = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#4f46e5" },
    children: [{ type: "text", text: "Hello, bm-engine", style: { fontFamily: "Inter", fontSize: 40, fontWeight: 700, color: "white" } }],
  },
  { width: 600, height: 200 },
);
```

![A purple banner with the text Hello, bm-engine](/img/guide/concepts-first.png)

`renderSync` returns a `Uint8Array` with the PNG file. Each method has an async twin (`render`,
`measure`, ...) that only differs in accepting asynchronous options such as lazy image data; the
rendering itself is synchronous in both. Choose the format with `format`, see [Formats](./formats.md).

## The node format

A node tree is plain JSON-compatible data. There are three node types:

| `type` | Required fields | Behaves like |
|:--|:--|:--|
| `"container"` | — (`children` optional) | an element (`div`) |
| `"text"` | `text` | an inline run of text (`span`) |
| `"image"` | `src` | a replaced element (`img`) |

Every node may also carry:

| Field | Purpose |
|:--|:--|
| `style` | inline CSS declarations with **camelCase** keys (`backgroundColor`) |
| `tw` | Tailwind classes (standard / full) |
| `preset` | a lowest-priority style layer, for user-agent-like defaults |
| `className`, `id`, `attributes`, `tagName` | hooks for stylesheet selectors (see [Styles](./styles.md#selectors-and-tagname)) |
| `dir`, `lang` | text direction and language (bidi, `:lang()`, OpenType language) |

An image node's `width` / `height` fields are presentational hints, like HTML attributes; CSS `width`
and `height` win over them. `src` can be raw RGBA pixels, encoded bytes, a `data:` URL, inline SVG
markup or a key of the `images` option — see [Images](./images.md).

<!-- @example concepts#node-format -->
```js
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
```

![An image of four blurred colours next to a title and subtitle](/img/guide/concepts-node-format.png)

The 2 × 2 image is stretched to 96 × 96 with smooth resampling; `objectFit` defaults to `fill`.
Unknown keys on a node are ignored; a node without `type` throws ``bm-engine: node is missing `type` ``
and a text node without `text` throws ``bm-engine: text node is missing `text` ``.

## Three ways to describe the same image

The node tree is the native input. On the `standard` and `full` profiles you can also pass an HTML
string or use Tailwind classes; they produce the same element tree and go through the same pipeline.

<!-- @example concepts#inputs -->
```js
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
```

| Node tree | HTML string | Tailwind |
|:-:|:-:|:-:|
| ![Node tree](/img/guide/concepts-input-tree.png) | ![HTML string](/img/guide/concepts-input-html.png) | ![Tailwind](/img/guide/concepts-input-tw.png) |

- **Every JavaScript string is HTML**, as in takumi. To pass a node tree as JSON text, wrap it:
  `{ json: "..." }`.
- The forms mix freely: HTML can carry `style=""`, `tw=""` and `<style>` blocks; a node tree can carry
  `tw` and be styled by the `css` option.
- On `core`, an HTML source throws `this build has no HTML input support` and a node with `tw` throws
  ``Tailwind (`tw`) is not supported by this build``. See [HTML and Tailwind](./html-and-tailwind.md).

If you write JSX, convert it to a node tree first (for example with `fromJsx` from
`@takumi-rs/helpers`; see [Differences from takumi](./differences-from-takumi.md#migration-in-five-steps)).

## Defaults that surprise people

bm-engine follows takumi, which follows CSS and Chromium. A few CSS defaults look odd when you come from
satori or from a browser with a CSS reset.

### `display` is `inline`

Every node — containers included — starts as `display: inline`, exactly like an unstyled element in
CSS. An inline box ignores `width` and `height`. Only the root and the children of flex / grid
containers are *blockified* automatically:

<!-- @example concepts#display-default -->
```js
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
```

The same three boxes rendered (each inside a block wrapper):

<!-- @example concepts#display-image -->
```js
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
```

![Three rows: the default row shows only a small grey square (the padding of the empty inline box), the block row a grey padding strip, the flex row the orange and purple squares](/img/guide/concepts-display.png)

::: tip Rule of thumb
Give every container that has a size, or whose children should form a row or a column, an explicit
`display: "flex"`, `"block"` or `"grid"`. Text nodes inside a flex container need nothing.
:::

HTML input is different: there the Chromium user-agent stylesheet makes `div`, `p`, `h1`, ... block
boxes, as in a browser (see [HTML and Tailwind](./html-and-tailwind.md#user-agent-styles)).

::: info measure() and inline boxes
`measure()` only reports block-level boxes (and text runs). An inline container is absent from the
`children` of its parent, which is why the example measures the parent's height.
:::

### `box-sizing` is `border-box`

Unlike CSS, `width` and `height` include padding and border by default (takumi's choice). Set
`boxSizing: "content-box"` to get the CSS behaviour:

<!-- @example concepts#box-sizing -->
```js
const boxes = renderer.measureSync({
  type: "container",
  style: { display: "flex", gap: 10 },
  children: [
    { type: "container", style: { width: 100, height: 40, padding: 10, border: "5px solid black" } },
    { type: "container", style: { width: 100, height: 40, padding: 10, border: "5px solid black", boxSizing: "content-box" } },
  ],
}, { width: 400, height: 100 });
boxes.children.map((c) => `${c.width}×${c.height}`); // [ '100×40', '130×70' ]
```

### Numbers, units and the viewport

- A number is **px** for properties that take a length (`width: 120`) and stays a plain number
  elsewhere (`opacity: 0.6`, `lineHeight: 1.4`, `flexGrow: 1`, `fontWeight: 700`).
- Strings accept any CSS value: `"50%"`, `"2rem"`, `"25vw"`, `"calc(100% - 48px)"`, `clamp()`, ...
- The **canvas is the viewport**: `%` on the root, `vw`, `vh` and `@media` queries refer to the `width`
  and `height` render options. The root font size is 16 px, so `1rem = 16px`.

<!-- @example concepts#units -->
```js
const unitBox = (width) => ({ type: "container", style: { display: "block", width, height: 10 } });
const widthOf = (width, options = {}) => renderer.measureSync(unitBox(width), { width: 400, height: 100, ...options }).width;

widthOf(120);                       // 120 – a number is px
widthOf("50%");                     // 200 – of the canvas width
widthOf("25vw");                    // 100 – vw / vh refer to the canvas
widthOf("2rem");                    // 32  – root font size is 16px
widthOf("calc(100% - 2 * 24px)");   // 352
widthOf(120, { devicePixelRatio: 2 }); // 240 – CSS px are scaled, the canvas is not
```

The values returned by `measure` are device pixels (CSS px × `devicePixelRatio`).

### The canvas

- `width` / `height` are the output size in pixels (at most 16384 per side and 40 megapixels).
- The canvas starts **transparent**. Paint a background on the root if you need one; JPEG output turns
  transparent pixels black.
- The root is *not* stretched to the canvas: give it `width: "100%"` and `height: "100%"` to fill it.
- Leave `width` and/or `height` out and the canvas takes the size of the laid-out root:

<!-- @example concepts#canvas -->
```js
// No width / height: the canvas takes the size of the root box
const auto = renderer.renderSync({ type: "container", style: { width: 240, height: 60, backgroundColor: "#22c55e" } });
// auto is a 240 × 60 PNG

// Empty content and no size is an error
expectThrow(() => renderer.renderSync({ type: "container" }));
// "bm-engine: invalid viewport: content has zero size and no width/height was given"
```

### Device pixel ratio

`devicePixelRatio` multiplies every CSS length and font size but **does not** change the canvas size.
For a sharper image of the same design, multiply the canvas by the same factor:

<!-- @example concepts#dpr -->
```js
const badge = {
  type: "container",
  style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#fef3c7", borderRadius: 12 },
  children: [{ type: "text", text: "Retina", style: { fontFamily: "Inter", fontSize: 24, fontWeight: 700, color: "#92400e" } }],
};
const x1 = renderer.renderSync(badge, { width: 160, height: 60 });
// same design, twice the pixels: double the canvas AND set devicePixelRatio
const x2 = renderer.renderSync(badge, { width: 320, height: 120, devicePixelRatio: 2 });
```

| `width: 160, height: 60` | `width: 320, height: 120, devicePixelRatio: 2` |
|:-:|:-:|
| ![1x badge](/img/guide/concepts-dpr-1x.png) | ![2x badge](/img/guide/concepts-dpr-2x.png) |

`%`, `vw` and `vh` already follow the canvas, so they need no change. `@media` queries see the canvas
size in CSS px (output px ÷ `devicePixelRatio`).

### Fonts: none built in

bm-engine ships no font and never reads system fonts. Text with no usable registered font is **not
drawn**, without an error. Register every font you use on every renderer — see [Fonts](./fonts.md).

### Strict inline styles, forgiving stylesheets

An invalid value in an inline `style` (`width: "10 px"`) throws
`bm-engine: invalid value for style property width`. The same mistake in a stylesheet or a Tailwind
class is dropped silently, as in a browser. Unknown properties and kebab-case keys in `style` are
ignored silently. See [Styles](./styles.md#inline-styles).

## Renderers, instances and memory

Three objects have different lifetimes:

| Object | How many | Holds |
|:--|:--|:--|
| The **wasm instance** | one per entry (`bm-engine`, `bm-engine/core`, `/standard`, `/full`), created by `init` (automatic on Node) | the linear memory shared by all renderers of that entry |
| A **`Renderer`** | as many as you need; usually one per font set | registered fonts, a decoded-image cache (cleared above 96 MiB), a glyph cache (cleared above 8 MiB), the canvas |
| A **render** | one per call | a scratch arena, reused by the next render |

<!-- @example concepts#lifecycle -->
```js
// Renderers are cheap; fonts are not. Keep one renderer per font set and reuse it.
const r = new Renderer();
r.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf")); // family name read from the font: "Inter"

for (let i = 0; i < 3; i++) {
  r.renderSync({ type: "text", text: `card ${i}`, style: { fontFamily: "Inter" } }, { width: 200, height: 40 });
}
r.memoryBytes(); // size of the wasm memory shared by every renderer of this entry, in bytes

r.free();        // releases its fonts and caches; r can no longer be used
expectThrow(() => r.renderSync({ type: "container" }, { width: 10, height: 10 }));
// "bm-engine: renderer has been freed"

{
  using scoped = new Renderer(); // free() is called at the end of the block
  scoped.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
}
```

- **Create once, reuse.** Constructing a renderer is cheap; registering fonts copies and parses the
  font bytes. Keep a long-lived renderer per font set (for example per server process or per worker)
  instead of one per request.
- **Memory only grows.** WebAssembly memory cannot shrink. Freed memory is reused by later renders, so
  a steady workload plateaus (about 6 MiB for 1200 × 630 cards with one font). One very large canvas
  raises the plateau for the rest of the instance's life; see [Performance](./performance.md).
- **Single-threaded.** A render blocks the calling thread. For parallelism, run one instance per worker
  thread; renderers cannot be shared between threads.
- `free()` (or `using`) releases a renderer's fonts and caches; afterwards every call on it throws
  `bm-engine: renderer has been freed`.

## Profiles in one paragraph

The engine is compiled into three binaries for images (and a fourth, `pdf`, that adds PDF output; see [PDF output](../pdf/index.md)): `core` (node trees, inline styles, static TrueType fonts,
PNG / JPEG images; 489.6 KiB), `standard` (adds stylesheets, Tailwind, HTML, SVG images, WOFF2,
variable and CFF fonts, effects such as clip-path and blend modes, modern colours, tables, floats;
936.5 KiB) and `full` (adds bidi and complex scripts, colour emoji, CSS animations and
`renderAnimation`, `renderSvg`, extra codecs; 1 143.6 KiB). On Node.js, `bm-engine` loads `full`;
`bm-engine/core` and `bm-engine/standard` load the smaller ones. `features` tells you what the loaded
binary can do:

<!-- @example concepts#features -->
```js
features.html;        // true on standard / full
features.complexText; // true on full only
```

The full comparison, and what a smaller profile does with input it cannot handle, is in
[Profiles and size](../profiles-and-size.md).

## See also

- [Styles](./styles.md) — inline styles, stylesheets, Tailwind and layout modes
- [HTML and Tailwind](./html-and-tailwind.md) — the HTML parser and the Tailwind compiler in depth
- [API reference](./api.md) — every method and option
- [Troubleshooting](../troubleshooting.md) — the symptoms these defaults cause
