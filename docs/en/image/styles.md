# Styles and layout

[English](styles.md) · [Tiếng Việt](../../vi/image/styles.md)

bm-engine styles elements with real CSS: the same properties, values, cascade and layout algorithms as
a browser. This page shows the three ways to attach styles —
inline `style` objects, stylesheets through the `css` option, and Tailwind classes in `tw` — how they
combine, and one worked example for each layout mode (flex, grid, block / inline flow, absolute
positioning, floats), followed by units and colours. The exhaustive list of properties and their
status is in [CSS support](./css-support.md). All code below is `docs/examples/styles.mjs`, run on the
`full` profile; each image is the output of the code right above it.

[[toc]]

## Which mechanism to use

| You have | Use | Profile |
|:--|:--|:--|
| Styles computed in code, one node at a time | [inline `style`](#inline-styles) | all |
| CSS text, shared classes, `@media`, design tokens in `:root` | [the `css` option](#stylesheets-the-css-option) | standard / full |
| Tailwind classes, no build step | [`tw`](#tailwind-tw) | standard / full |
| Tailwind compiled by your bundler | the generated CSS in `css` (only what the stylesheet engine supports applies) | standard / full |
| HTML with `<style>` and `style=""` | an [HTML source](./html-and-tailwind.md) | standard / full |

The examples share this setup:

<!-- @example styles#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // stylesheets and Tailwind need the standard or full profile

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
```

## Inline styles

`style` is an object of CSS declarations with **camelCase** keys. Values are CSS strings or numbers:
a number means px for properties that take a length and a plain number otherwise. Custom properties
keep their dashes and work with `var()`, and inherited properties (`fontFamily`, `color`, `fontSize`,
...) flow from a container into its text.

<!-- @example styles#inline -->
```js
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
```

![A pink banner with a pink left border and the words Inline style](/img/guide/styles-inline.png)

Inline styles are strict about values and lenient about names:

<!-- @example styles#inline-errors -->
```js
// kebab-case keys and unknown properties are ignored silently
renderer.renderSync({ type: "container", style: { "background-color": "red", colour: "blue" } }, { width: 10, height: 10 });

// an invalid value for a known property throws
expectThrow(() => renderer.renderSync({ type: "container", style: { width: "10 px" } }, { width: 10, height: 10 }));
// "bm-engine: invalid value for style property width"
```

::: warning Kebab-case keys are ignored
`{ "background-color": "red" }` is silently ignored. Use `backgroundColor`. Vendor
prefixes are capitalised: `WebkitLineClamp`, `WebkitTextStroke`.
:::

Shorthands (`border`, `background`, `flex`, `font`, `inset`, `gridArea`, ...) and their longhands both
work; logical properties (`marginInline`, `paddingBlockStart`, `insetInlineEnd`) too. `"!important"`
inside a string value is honoured.

## Stylesheets: the `css` option

Pass one or more stylesheets as strings (or [rule objects](#rule-objects)) in `css`. Nodes are matched
by `className`, `id`, `attributes` and `tagName`. Everything you expect from CSS is there: selectors and
combinators, `:root` custom properties, `var()`, nesting, `@media`, `@supports`, `@layer`.

<!-- @example styles#stylesheet -->
```js
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
```

| 560 × 120 | 360 × 100 (`@media (max-width: 400px)` matches) |
|:-:|:-:|
| ![Wide card](/img/guide/styles-stylesheet-wide.png) | ![Narrow card with smaller title](/img/guide/styles-stylesheet-narrow.png) |

What the stylesheet engine supports, in short (full list in
[CSS support](./css-support.md#stylesheets-and-selectors)):

- **Selectors**: type, universal, class, id, attribute (all operators), the four combinators, selector
  lists, structural pseudo-classes (`:first-child`, `:nth-child(2n+1 of .x)`, `:only-of-type`, ...),
  `:not()`, `:is()`, `:where()`, `:has()`, `:root`, `:empty`, `:lang()`, `:dir()`, and the
  `::before` / `::after` pseudo-elements with `content`.
- **At-rules**: `@media` (`width`, `height`, `aspect-ratio`, `orientation`, `resolution`, range syntax,
  `and` / `or` / `not`), `@supports`, `@layer`, CSS nesting with `&`, `@keyframes`
  ([Animation](./animation.md)), `@theme`, `@import "tailwindcss"`.
- **Not applied**: `@font-face` (register fonts with `registerFont`), `@property`, `@container`,
  `@apply`, `@page`; dynamic pseudo-classes such as `:hover` parse but never match.
- `@media` is evaluated against the canvas size in **CSS px** (canvas px ÷ `devicePixelRatio`);
  media features it does not know (for example `prefers-color-scheme`) make the query false.
- A broken declaration or rule is dropped; a stylesheet never makes a render throw.

::: warning Structural pseudo-classes on text nodes
A `text` node without a `tagName` is not an element for `:first-child`, `:nth-child()`, `+` / `~` and
the Tailwind `first:` / `odd:` / ... variants: it is not counted among its siblings, so
when several bare text nodes sit side by side, **every** one of them matches `first:`, `last:` and
`odd:`. Give the node a `tagName` (`{ type: "text", tagName: "div", ... }`) or put the text inside a
`container` when the position matters. Empty or whitespace-only text nodes are dropped (in flex and grid
containers always, elsewhere unless inline content precedes them), even when they carry a class or a
style.
:::

### Rule objects

Instead of text you can pass rule objects, `{ selector, style }` with a camelCase `style`. They
are convenient when values come from data, because nothing is concatenated into CSS text. Array order
is cascade order:

<!-- @example styles#rule-objects -->
```js
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
```

![The same card with a green brand colour and green background](/img/guide/styles-rule-objects.png)

Other rule-object forms (`{ media, rules }`, `{ keyframes, steps }`, ...) are accepted as
well; `{ selector, style }` and `{ media, rules }` were checked here.

### Selectors and tagName

A node tree has no tag names unless you give them: a container is *not* a `div` for selectors. Type
selectors match only nodes with a `tagName`; class, id, attribute and `*` selectors match any node.

<!-- @example styles#selectors-tagname -->
```js
// A type selector only matches nodes that have a tagName; `*`, classes, ids and attributes match any node
const heightWith = (node, css) => renderer.measureSync(node, { width: 100, height: 100, css: [css] }).height;
heightWith({ type: "container" }, "div { display: block; height: 7px }");                   // 0 – no tagName
heightWith({ type: "container", tagName: "div" }, "div { display: block; height: 7px }");   // 7
heightWith({ type: "container", id: "hero" }, "#hero { display: block; height: 7px }");     // 7
heightWith({ type: "container", attributes: { "data-kind": "pro" } }, "[data-kind=pro] { display: block; height: 7px }"); // 7
```

Setting `tagName` on a node tree does not apply the HTML user-agent styles (an `h1` node is not bold);
use the `preset` field, or an [HTML source](./html-and-tailwind.md#user-agent-styles), for that.

## Tailwind: `tw`

The `tw` field takes Tailwind v4 utility classes and compiles them inside the engine — no build step.
For supported utilities, see
[HTML and Tailwind](./html-and-tailwind.md#tailwind) for variants, arbitrary values and what is not
supported.

<!-- @example styles#tailwind -->
```js
const twPng = renderer.renderSync({
  type: "container",
  tw: "flex items-center justify-between w-full h-full px-8 bg-slate-900",
  style: { fontFamily: "Inter" },
  children: [
    { type: "text", text: "Tailwind via tw", tw: "text-3xl font-bold text-white" },
    { type: "text", text: "PRO", tw: "px-3 py-1 rounded-md bg-amber-400/90 text-slate-900 text-sm font-bold" },
  ],
}, { width: 500, height: 100 });
```

![A dark banner with the title Tailwind via tw and an amber PRO badge](/img/guide/styles-tailwind.png)

## How the layers combine

From lowest to highest priority:

1. `preset` (user-agent layer; HTML tags get Chromium's defaults here)
2. stylesheet rules inside named `@layer` blocks
3. Tailwind utilities from `tw`
4. unlayered stylesheet rules from `css` and `<style>` (by specificity and order)
5. inline `style`
6. `!important` declarations, which reverse the order as in CSS: unlayered `!important` rules <
   `!`-prefixed utilities such as `!w-20` < `!important` rules in named layers; all of them beat
   normal inline declarations

This order matches Tailwind v4 in a browser for layers declared before
`@layer utilities` (such as `base`).

<!-- @example styles#precedence -->
```js
const widthWith = (node, css = []) => renderer.measureSync(node, { width: 400, height: 100, css }).width;
const base = { type: "container", className: "box", tw: "block w-20 h-5" };   // tw: width 80px

widthWith(base);                                                      // 80  – tw
widthWith(base, [".box { width: 60px }"]);                            // 60  – a stylesheet rule beats tw
widthWith(base, ["@layer base { .box { width: 33px } }"]);            // 80  – … unless it sits in a named @layer
widthWith({ ...base, style: { width: 40 } }, [".box { width: 60px }"]); // 40  – inline style beats both
widthWith({ ...base, style: { width: 40 } }, [".box { width: 60px !important }"]); // 60 – !important wins
widthWith({ ...base, tw: "block !w-20 h-5", style: { width: 40 } });  // 80  – a !utility beats inline style
widthWith({ ...base, tw: "block !w-20 h-5" }, [".box { width: 60px !important }"]); // 80 – … and an unlayered !important rule
widthWith({ ...base, tw: "block !w-20 h-5" }, ["@layer base { .box { width: 33px !important } }"]); // 33 – a layered one wins
widthWith({ type: "container", preset: { display: "block", width: 30 }, style: { height: 5 } }); // 30 – preset is the lowest layer
```


## Layout modes

The CSS layout modes described here is available on every profile, except floats and tables
which need `standard`. Tables have their own page: [Tables and floats](./tables.md).

### Flexbox

`display: "flex"` with `flexDirection`, `flexWrap`, `gap`, `flex` / `flexGrow` / `flexShrink` /
`flexBasis`, `justifyContent`, `alignItems`, `alignContent`, `alignSelf` and `order`. This is the
workhorse for cards and banners:

<!-- @example styles#flex -->
```js
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
```

![A row of three boxes 120px, flex 1, flex 2 above two centred wrapped rows of orange pills](/img/guide/styles-flex.png)

### Right to left {#right-to-left}

`direction: "rtl"` in the style (or `dir: "rtl"` on the node, `dir="rtl"` in HTML) mirrors the layout of
boxes, as in a browser: a flex row starts at the right, grid columns are placed from the right and
block children with a fixed width sit at the right edge. Tables mirror their columns too (see
[Tables](./tables.md#rtl-tables)). This works on every profile; laying out the *text* inside right to
left (bidi) needs `full`.

<!-- @example styles#rtl -->
```js
// direction: rtl (or dir: "rtl" on the node) mirrors flex rows, grid columns and block alignment
const steps = (style) => ({
  type: "container",
  style: { display: "flex", gap: 10, height: 44, ...style },
  children: ["first", "second", "third"].map((t, i) => box(t, { width: 110, backgroundColor: ["#0ea5e9", "#6366f1", "#a855f7"][i] })),
});
const rtlPng = renderer.renderSync({
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 10, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9", fontFamily: "Inter" },
  children: [
    steps({}),                                     // ltr: first item on the left
    steps({ direction: "rtl" }),                   // rtl: first item on the right
    { ...steps({ display: "grid", gridTemplateColumns: "110px 110px 110px" }), dir: "rtl" }, // grid columns too
  ],
}, { width: 560, height: 190 });
```

![Three boxes first, second, third from left to right, then the same row and a grid mirrored from right to left](/img/guide/styles-rtl.png)

### Grid

`display: "grid"` with track lists (`px`, `%`, `fr`, `auto`, `minmax()`, `repeat()` including
`auto-fill` / `auto-fit`), auto-placement, spans, named lines and `gridTemplateAreas`:

<!-- @example styles#grid -->
```js
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
```

![A grid with a dark head row, a teal side column and main and foot areas](/img/guide/styles-grid.png)

### Block and inline flow

`display: "block"` boxes stack vertically with margin collapsing; text and inline boxes inside them
form line boxes that wrap at the container edge. Mix text runs, styled spans and `inline-block` boxes
on one line:

<!-- @example styles#flow -->
```js
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
```

![A heading and a paragraph with a pink bold span and a green pill inline-block that wraps to two lines](/img/guide/styles-flow.png)

Text layout (wrapping, `whiteSpace`, `lineHeight`, ellipsis, ...) is covered in
[Typography](./typography.md).

An inline container that holds a block-level child is split around it, as in a browser: the inline
content before the block, the block itself and the content after it are laid out one below the other,
and the inline box's background and borders are drawn on each part (without the edge where it was split).

### `display: contents` {#display-contents}

`display: contents` does not generate its own box. Its children participate directly in the parent’s layout.

<!-- @example styles#contents -->
```js
// display: contents removes the element's own box: its children take part in the parent's
// layout (here: they become flex items of the row) and its padding / background are not drawn.
const pill = (t, color) => box(t, { padding: "8px 14px", backgroundColor: color });
const group = (display) => ({
  type: "container",
  style: { display, gap: 10, padding: 10, backgroundColor: "#fecaca" }, // padding + background of the wrapper
  children: [pill("B", "#6366f1"), pill("C", "#a855f7")],
});
const contentsRow = (display) => ({
  type: "container",
  style: { display: "flex", gap: 10, alignItems: "center", padding: 10, backgroundColor: "#e2e8f0" },
  children: [pill("A", "#0ea5e9"), group(display), pill("D", "#f97316")],
});
const contentsPng = renderer.renderSync({
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 12, padding: 16, width: "100%", height: "100%", backgroundColor: "white", fontFamily: "Inter" },
  children: [contentsRow("flex"), contentsRow("contents")],
}, { width: 400, height: 150 });
```

![Top row: A, a pink wrapper with B and C, D. Bottom row: A, B, C and D as equal flex items, no pink wrapper](/img/guide/styles-contents.png)

### Absolute positioning

`position: "absolute"` takes the box out of the flow and places it with `top` / `right` / `bottom` /
`left` (or `inset`) against the nearest positioned ancestor; `zIndex` changes the paint order.
`position: "fixed"` is positioned against the canvas; `sticky` behaves like `relative`.

<!-- @example styles#absolute -->
```js
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
```

![Three overlapping rounded rectangles, the yellow one on top through z-index, and a red NEW badge in the corner](/img/guide/styles-absolute.png)

### Floats

`float: "left" | "right"` and `clear` (standard / full; ignored on `core`). Line boxes beside a float
are shortened and widen again below it:

<!-- @example styles#floats -->
```js
// floats need the standard or full profile (ignored on core)
const floatPng = renderer.renderSync({
  type: "container",
  style: { display: "block", padding: 16, width: "100%", height: "100%", backgroundColor: "white", fontFamily: "Inter", fontSize: 16, lineHeight: 1.5, color: "#334155" },
  children: [
    { type: "container", style: { float: "left", width: 90, height: 90, marginRight: 14, borderRadius: 12, backgroundImage: "linear-gradient(135deg, #f97316, #db2777)" } },
    { type: "text", text: "This paragraph flows around the floated box: lines beside the float are shorter, and once the float ends the text returns to the full width of the container, as in a browser. Use clear to start below a float." },
  ],
}, { width: 460, height: 170 });
```

![A gradient square floated left with a paragraph wrapping around it and continuing below](/img/guide/styles-floats.png)

More on floats and their limits: [Tables and floats](./tables.md).

## Units

| Unit | Meaning in bm-engine |
|:--|:--|
| number, `px` | CSS px (× `devicePixelRatio` on the canvas) |
| `%` | of the containing block; on the root, of the canvas |
| `em`, `rem` | of the element's / root's font size (root: 16 px) |
| `vw`, `vh`, `vmin`, `vmax` | of the canvas (output px) |
| `pt`, `pc`, `in`, `cm`, `mm`, `Q` | absolute units (1in = 96px) |
| `ch`, `ex`, `lh`, `rlh`, `cq*` | supported as in CSS |
| `calc()`, `min()`, `max()`, `clamp()` and other math functions | supported everywhere a length or number is accepted |

See [How bm-engine works](./concepts.md#numbers-units-and-the-viewport) for a measured example.

## Colours

Named colours, hex (`#rgb`, `#rrggbbaa`), `rgb()` / `hsl()` / `hwb()` in both syntaxes, `currentColor`
and `transparent` work everywhere. `standard` and `full` add `oklch()`, `oklab()`, `lab()`, `lch()`,
`color()`, `color-mix()` and `light-dark()` (which always picks the light value):

<!-- @example styles#colors -->
```js
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
```

![Eight colour swatches labelled with the CSS colour that produced them](/img/guide/styles-colors.png)

On `core` the modern colour functions are not parsed, so an inline style using them throws:

<!-- @example styles#core-colors -->
```js
import { Renderer as CoreRenderer } from "bm-engine/core";
const core = new CoreRenderer();
expectThrow(() => core.renderSync({ type: "container", style: { width: 10, height: 10, backgroundColor: "oklch(62% 0.2 30)" } }, { width: 10, height: 10 }));
// "bm-engine: invalid value for style property backgroundColor"
```

In a stylesheet the same declaration is simply dropped. Relative colour syntax
(`rgb(from red r g b / 50%)`) is not supported on any profile.

## See also

- [CSS support](./css-support.md) — every property, value and its status
- [HTML and Tailwind](./html-and-tailwind.md) — HTML sources and the Tailwind compiler
- [Typography](./typography.md), [Effects](./effects.md), [Images](./images.md)
- [How bm-engine works](./concepts.md) — defaults such as `display: inline` and `border-box`
