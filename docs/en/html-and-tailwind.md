# HTML and Tailwind

[English](html-and-tailwind.md) · [Tiếng Việt](../vi/html-and-tailwind.md)

Besides node trees, the `standard` and `full` profiles accept two more ways of describing an image: an
**HTML string** as the render source, and **Tailwind classes** in a node's `tw` field (or a `tw=""`
attribute in HTML). Both are ports of takumi's own HTML parser and Tailwind compiler, so they accept
the same subset. This page covers what the HTML parser understands, which user-agent styles apply,
what is ignored, and how far the Tailwind compiler goes — variants, arbitrary values, Preflight, theme
variables and the gaps. All code is `docs/examples/html-and-tailwind.mjs`, run with `bm-engine/standard`.

[[toc]]

<!-- @example html-and-tailwind#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine/standard"; // HTML and Tailwind need standard or full

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Italic.ttf"));
```

On `core` both inputs throw:

<!-- @example html-and-tailwind#core-errors -->
```js
import { Renderer as CoreRenderer } from "bm-engine/core";
const core = new CoreRenderer();
expectThrow(() => core.renderSync("<div></div>", { width: 10, height: 10 }));
// "bm-engine: this build has no HTML input support (use the standard / full build)"
expectThrow(() => core.renderSync({ type: "container", tw: "flex" }, { width: 10, height: 10 }));
// "bm-engine: Tailwind (`tw`) is not supported by this build"
```

## HTML sources

**Every JavaScript string passed as a source is parsed as HTML** (as in takumi). The parser is a
tolerant subset of the WHATWG algorithm: it accepts fragments and whole documents, implied end tags
(`p`, `li`, `dt` / `dd`, table parts), implied `tbody`, void elements and character references. A
`<style>` block anywhere in the string is applied as a stylesheet, together with any `css` option.

<!-- @example html-and-tailwind#article -->
```js
const html = `
<style>
  .post { font-family: Inter; padding: 20px 28px; background: #fff; color: #1f2937; height: 100%; }
  .post h1 { margin: 0 0 6px; font-size: 30px; }
  .meta { color: #6b7280; font-size: 14px; }
  .post p { font-size: 16px; line-height: 1.5; margin: 10px 0; }
  mark { background: #fef08a; }
</style>
<article class="post">
  <h1>Rendering HTML</h1>
  <div class="meta">5&nbsp;min read &middot; 2026</div>
  <p>The source is a <strong>plain string</strong> with <em>inline</em> elements,
     <mark>highlighted text</mark> and <code>code</code>.</p>
  <p>Line one<br>line two &mdash; entities such as &amp;, &lt; and &copy; are decoded.</p>
</article>`;
const articlePng = renderer.renderSync(html, { width: 560, height: 230 });
```

![An article with a heading, a grey meta line, a paragraph with bold, italic and highlighted text and a line break](/img/guide/html-and-tailwind-article.png)

Things to notice in the output:

- `<strong>`, `<em>` and `<mark>` got their user-agent styles; `<br>` broke the line.
- `&nbsp;`, `&middot;`, `&mdash;`, `&amp;`, `&lt;`, `&copy;` were decoded (numeric references and 338
  named ones are known).
- `<code>` is drawn in Inter: the user-agent stylesheet asks for `monospace`, but generic family names
  are not mapped to fonts, so text falls back to the registered fonts (see [Fonts](./fonts.md)).
  Register a monospace font and set `font-family` on `code` to change that.
- Whitespace collapses as in a browser.

### User-agent styles

Chromium's user-agent styles are applied as the lowest layer (the node `preset`), so unstyled HTML
looks like it does in a browser: `div`, `p`, `h1`–`h6`, `ul`, `blockquote`, `table`, ... are blocks
with their usual margins, `b` / `strong` are bold, `i` / `em` italic, `u` underlined, `s` struck
through, `small` smaller, and so on.

<!-- @example html-and-tailwind#ua-styles -->
```js
// No stylesheet at all: the Chromium user-agent defaults give headings, paragraphs and lists their look
const uaPng = renderer.renderSync(`
  <div style="font-family: Inter; padding: 0 16px; background: white; height: 100%">
    <h2>Heading 2</h2>
    <p>A paragraph with <b>bold</b>, <i>italic</i>, <u>underline</u>, <s>strike</s> and <small>small</small> text.</p>
    <ul><li>first item</li><li>second item</li></ul>
    <blockquote>blockquote</blockquote>
  </div>`, { width: 560, height: 280 });
```

![Unstyled HTML: a bold heading, a paragraph with inline styles, an indented list without bullets and an indented blockquote](/img/guide/html-and-tailwind-ua-styles.png)

::: warning No list markers
List items are laid out (with the `ul` / `ol` indentation) but **no bullet or number is drawn**:
markers, `::marker` and CSS counters are not implemented in 0.1.0. Draw your own with `::before` or an
inline element if you need them.
:::

The user-agent styles only apply to HTML sources. Setting `tagName: "h1"` on a node tree makes the node
match `h1` selectors but does not make it bold or large (as in takumi).

### Fragments and documents

A fragment (`<div>...</div>`) is rendered as is. A full document (`<html><body>...`) gets the
`body { margin: 8px }` default, exactly like a browser page:

<!-- @example html-and-tailwind#document-mode -->
```js
const firstBox = (source) => renderer.measureSync(source, { width: 400, height: 300 }).children[0];
firstBox("<div><div style='height:10px'></div></div>").transform; // [1,0,0,1,0,0] – a fragment: no body margin
firstBox("<html><body><div style='height:10px'></div></body></html>").transform; // [1,0,0,1,8,8] – body has an 8px margin
```

A fragment with several top-level elements is wrapped in an anonymous root that fills the canvas.
Like node trees, the root is not stretched to the canvas: use `width: 100%; height: 100%` on your
outer element (or a `<style>` rule) to fill it.

### Attributes

| Attribute | Effect |
|:--|:--|
| `style="..."` | inline declarations in normal CSS syntax (kebab-case); invalid declarations are dropped, not thrown |
| `class`, `id`, any other attribute | available to stylesheet selectors (`.x`, `#x`, `[data-x=y]`); `attr()` in `content` |
| `tw="..."` | Tailwind classes ([below](#tailwind)) |
| `dir`, `lang` | text direction and language (`:dir()`, `:lang()`, bidi on `full`) |
| `width`, `height` on `img` / `svg` | presentational size hints |
| `src` on `img` | a `data:` URL or a key of the `images` option |

### Images and inline SVG

`<img src>` never downloads anything: the value is a lookup key into the `images` render option, or a
`data:` URL. An inline `<svg>` element is rendered as an SVG image. An unknown key paints nothing (no
error); the element keeps its `width` / `height`.

<!-- @example html-and-tailwind#images-svg -->
```js
const logo = readFileSync("docs/public/favicon.svg"); // any PNG / JPEG / WebP / GIF / SVG bytes
const imgPng = renderer.renderSync(`
  <div style="display:flex; align-items:center; gap:20px; padding:20px; background:#0f172a; height:100%">
    <img src="logo.svg" width="64" height="64">
    <svg width="64" height="64" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" fill="#f472b6"/></svg>
    <img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'%3E%3Crect width='10' height='10' rx='2' fill='%2338bdf8'/%3E%3C/svg%3E" width="64" height="64">
    <img src="https://example.com/never-fetched.png" width="64" height="64" style="background:#334155">
  </div>`, {
  width: 400,
  height: 104,
  images: [{ src: "logo.svg", data: logo }], // <img src> is a lookup key into `images`
});
```

![Four squares: the favicon from images, a pink inline SVG circle, a blue data URL SVG and an empty slate box for the unfetched URL](/img/guide/html-and-tailwind-images.png)

More about image sources and decoders: [Images](./images.md).

### What is ignored

`<script>` (never executed), `<template>` content, comments, and everything in `<head>` except
`<style>` produce no boxes. Nothing is fetched: `<link rel="stylesheet">`, `@import url(...)` and
`@font-face` URLs are not loaded.

<!-- @example html-and-tailwind#ignored -->
```js
// <script>, <head> content, comments and the hidden attribute
const ignoredPng = renderer.renderSync(`
  <html><head><title>not drawn</title><style>p { color: #059669 }</style></head>
  <body style="margin:0; font-family:Inter; padding: 12px; background:white">
    <script>document.body.innerHTML = "never runs"</script>
    <!-- a comment -->
    <p style="margin:0">Body content is drawn.</p>
    <p hidden style="margin:0">hidden attribute: still drawn in 0.1.0</p>
  </body></html>`, { width: 400, height: 70 });
```

![Two green lines of text: the body paragraph and the paragraph with the hidden attribute](/img/guide/html-and-tailwind-ignored.png)

::: warning The `hidden` attribute is not honoured
An element with `hidden` is still drawn (there is no `[hidden] { display: none }` rule in the
user-agent styles), as in takumi. Use `style="display:none"` instead.
:::

Also not implemented (same gaps as takumi's parser): the adoption-agency algorithm for misnested
formatting tags, foster parenting of stray table content, MathML, and form controls as widgets
(`<input>`, `<button>`, `<select>` are plain boxes).

## Tailwind

Put classes in the `tw` field of a node, or in a `tw="..."` attribute in HTML. They are compiled to CSS
declarations at render time and need the `standard` or `full` profile. The compiler is a port of
takumi's Tailwind v4 subset: 656 of 657 class strings in the equivalence test compile to the same
declarations as takumi.

<!-- @example html-and-tailwind#tw-node -->
```js
const twPng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col justify-between w-full h-full p-6 bg-linear-to-br from-indigo-600 to-fuchsia-600",
  style: { fontFamily: "Inter" },
  children: [
    { type: "text", tw: "text-sm font-bold uppercase tracking-widest text-white/70", text: "Tailwind on nodes" },
    { type: "text", tw: "text-3xl font-bold text-white leading-tight", text: "Utility classes compiled at render time" },
    {
      type: "container",
      tw: "flex gap-2",
      children: ["flex", "p-6", "bg-linear-to-br", "text-white/70"].map((c) => ({
        type: "text", tw: "px-3 py-1 rounded-full bg-white/20 text-white text-xs", text: c,
      })),
    },
  ],
}, { width: 560, height: 200 });
```

![A purple to magenta gradient card with an uppercase label, a large white title and four translucent pills](/img/guide/html-and-tailwind-tw-node.png)

### `tw`, not `class`

In HTML only the `tw` attribute feeds the Tailwind compiler. `class` is for stylesheet selectors, so a
Tailwind class name in `class` does nothing unless a stylesheet defines it (checked in 0.1.0):

<!-- @example html-and-tailwind#tw-html -->
```js
// In HTML the attribute is tw="..."; class="..." only feeds stylesheet selectors
const twHtmlPng = renderer.renderSync(`
  <div tw="flex items-center gap-4 w-full h-full px-6 bg-emerald-50" style="font-family: Inter">
    <div tw="w-12 h-12 rounded-xl bg-emerald-500"></div>
    <div tw="flex flex-col">
      <span tw="text-xl font-bold text-emerald-900">tw attribute</span>
      <span class="text-xl text-red-600">class attribute: not Tailwind</span>
    </div>
  </div>`, { width: 460, height: 100 });
```

![A green square, a bold title from tw and a plain black line whose class did nothing](/img/guide/html-and-tailwind-tw-html.png)

The same holds for node trees: `className: "flex p-4"` is a class name for selectors, not Tailwind.

### Supported utility families

| Family | Examples |
|:--|:--|
| Layout and display | `flex`, `grid`, `block`, `inline-block`, `hidden`, `contents`, `overflow-hidden`, `object-cover` |
| Position | `relative`, `absolute`, `inset-0`, `top-4`, `-left-2` |
| Sizing | `w-64`, `h-full`, `size-12`, `min-w-0`, `max-w-md`, `aspect-video` |
| Spacing | `p-6`, `px-3`, `mt-2`, `-mb-1`, `gap-4`, `gap-x-2` |
| Flex and grid | `flex-col`, `flex-wrap`, `grow`, `shrink-0`, `basis-1/2`, `items-center`, `justify-between`, `self-end`, `grid-cols-3`, `col-span-2` |
| Typography | `text-3xl`, `text-slate-700`, `font-bold`, `leading-tight`, `tracking-wide`, `uppercase`, `truncate`, `line-clamp-2`, `whitespace-nowrap`, `underline`, `decoration-wavy` |
| Backgrounds | `bg-sky-500`, `bg-white/20`, `bg-linear-to-br from-indigo-600 via-... to-fuchsia-600`, `bg-radial`, `bg-conic`, `bg-cover` |
| Borders | `border`, `border-2`, `border-dashed`, `border-slate-300`, `rounded-xl`, `rounded-t-lg`, `outline-2 outline-solid` (`outline-2` alone draws nothing) |
| Effects | `shadow-lg`, `inset-shadow-sm`, `text-shadow-md`, `opacity-50`, `mix-blend-multiply`, `bg-blend-overlay`, `mask-[linear-gradient(black,transparent)]` (the named v4 mask utilities such as `mask-b-from-50%` do nothing) |
| Filters | `blur-sm`, `grayscale`, `drop-shadow-md`, `backdrop-blur-md` (the bare v3 `backdrop-blur` does nothing) |
| Transforms | `rotate-6`, `scale-95`, `translate-x-4`, `origin-top-left` |

Values come from Tailwind's default theme: the spacing scale (`p-4` = 16px), the full colour palette
with `/opacity` modifiers (`bg-red-500/50`), font sizes with their line heights (`text-sm` = 14px /
20px), radii, shadows and breakpoints.

### Arbitrary values

Square brackets take any CSS value; underscores stand for spaces:

<!-- @example html-and-tailwind#arbitrary -->
```js
const arbitraryPng = renderer.renderSync({
  type: "container",
  tw: "flex items-center justify-center w-full h-full bg-[#0b1020]",
  children: [{
    type: "text",
    tw: "px-[18px] py-[6px] rounded-[10px] border-2 border-[rgb(250_204_21)] text-[26px] text-[#facc15] tracking-[0.2em]",
    style: { fontFamily: "Inter" },
    text: "ARBITRARY",
  }],
}, { width: 400, height: 90 });
```

![A yellow outlined ARBITRARY label on a near-black background](/img/guide/html-and-tailwind-arbitrary.png)

Arbitrary properties (`[width:30px]`), the `(--var)` shorthand and `var()` inside brackets
(`bg-[var(--brand)]`) are not supported — see [Gaps](#what-tailwind-does-not-do).

### Variants

| Variant | Applies when |
|:--|:--|
| `sm:` `md:` `lg:` `xl:` `2xl:` | the canvas is at least 640 / 768 / 1024 / 1280 / 1536 CSS px wide |
| `first:` `last:` `only:` `odd:` `even:` | position among siblings |
| `first-of-type:` `last-of-type:` `only-of-type:` `empty:` `nth-*:` `not-*:` `[&:...]:` | structural, as in Tailwind |
| `before:` `after:` | style the `::before` / `::after` pseudo-element (`content-['...']` gives it text) |

<!-- @example html-and-tailwind#variants -->
```js
const rows = ["Plan", "Seats", "Total", "Due"];
const variantsPng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col w-full h-full p-4 bg-white",
  style: { fontFamily: "Inter" },
  children: [
    {
      type: "text",
      tw: "text-lg font-bold mb-2 after:content-['NEW'] after:ml-2 after:px-2 after:rounded after:bg-amber-300 after:text-xs",
      text: "Structural variants",
    },
    {
      type: "container",
      tw: "flex flex-col",
      // structural variants: use container rows (or a tagName): a bare text node is not an element for them
      children: rows.map((r) => ({
        type: "container",
        tw: "flex px-3 py-1 text-sm bg-slate-100 odd:bg-sky-100 first:rounded-t-lg last:rounded-b-lg last:font-bold",
        children: [{ type: "text", text: r }],
      })),
    },
  ],
}, { width: 400, height: 190 });
```

![A title with an amber NEW badge from after:, and four rows with alternating blue rows, rounded first and last rows and a bold last row](/img/guide/html-and-tailwind-variants.png)

::: warning Structural variants on bare text nodes
A `text` node without a `tagName` is not an element for `first:`, `last:`, `odd:` and friends (nor for
`:first-child` in stylesheets), as in takumi: it does not count among its siblings, so when several bare
text nodes sit side by side **every** one of them matches `first:`, `last:` and `odd:`. That is why the
rows above are containers with a text child; giving the text nodes a `tagName` (for example `"div"`)
works too. HTML elements are not affected.
:::

Breakpoints compare against the canvas width in CSS px:

<!-- @example html-and-tailwind#breakpoints -->
```js
const responsive = { type: "container", tw: "block h-2 w-10 sm:w-20 md:w-40" };
renderer.measureSync(responsive, { width: 600, height: 10 }).width; // 40  – sm (≥ 640px) does not match a 600px canvas…
renderer.measureSync(responsive, { width: 700, height: 10 }).width; // 80  – …sm matches at 700px
renderer.measureSync(responsive, { width: 800, height: 10 }).width; // 160 – md (≥ 768px)
```

### Conflicts and precedence

As in Tailwind, the order of classes in the string does not matter: the compiler's own sort order
decides. A side-specific utility beats a general one, and between two utilities for the same property
(such as two background colours) the alphabetically later one wins (`bg-red-500 bg-blue-500` is red).

<!-- @example html-and-tailwind#conflicts -->
```js
const w = (tw, style) => renderer.measureSync({ type: "container", tw, style }, { width: 400, height: 50 });
w("block pt-2 p-4").height; // 24 – pt-2 (8) + bottom p-4 (16): the side-specific utility wins…
w("block p-4 pt-2").height; // 24 – …whatever the class order
w("block w-20 h-1", { width: 40 }).width;  // 40 – inline style beats tw
w("block !w-20 h-1", { width: 40 }).width; // 80 – unless the utility is !important
```

Against other style sources: inline `style` beats `tw`, an unlayered stylesheet rule beats `tw`, `tw`
beats a rule inside a named `@layer`, and an `!`-prefixed utility beats every normal declaration and
unlayered `!important` rules (only `!important` rules in named layers beat it). See
[Styles](./styles.md#how-the-layers-combine).

### Preflight

No Tailwind Preflight is applied by default, so HTML elements keep their user-agent margins and
heading sizes. Add `@import "tailwindcss";` to `css` to turn Preflight on — it removes margins and
resets heading sizes and weights:

<!-- @example html-and-tailwind#preflight -->
```js
const page = `<div style="font-family: Inter; background: white; height: 100%; padding: 0 12px"><h1>Heading</h1><p>Paragraph</p></div>`;
const withoutPreflight = renderer.renderSync(page, { width: 280, height: 160 });
const withPreflight = renderer.renderSync(page, { width: 280, height: 160, css: ['@import "tailwindcss";'] });
```

| default | with `@import "tailwindcss";` |
|:-:|:-:|
| ![A large bold heading with margins above a paragraph](/img/guide/html-and-tailwind-preflight-off.png) | ![Heading and paragraph in the same plain style with no margins](/img/guide/html-and-tailwind-preflight-on.png) |

### Theme variables

`@theme { ... }` in a stylesheet defines theme variables. The utilities read them, as in Tailwind v4:
colours (`--color-*`, also with an `/opacity` modifier), `--spacing` and `--spacing-*`, `--container-*`,
`--radius-*`, `--text-*` (with the `--text-*--line-height` companion), `--font-*`, `--font-weight-*`,
`--tracking-*`, `--leading-*`, `--aspect-*`, `--animate-*` and `--breakpoint-*`; redefining a default
(`--color-red-500`) changes `bg-red-500`. The variables are also declared on `:root`, so `var()` can read
them in CSS and inline styles:

<!-- @example html-and-tailwind#theme -->
```js
// @theme variables feed the utilities (bg-brand-500, bg-brand-500/15, rounded-card, text-hero,
// font-display, ...) and are also custom properties on :root, so var() can read them.
const theme = `@theme {
  --color-brand-500: #7c3aed;
  --radius-card: 14px;
  --text-hero: 28px;
  --text-hero--line-height: 34px;
  --font-display: Inter;
}`;
const themePng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col items-center justify-center gap-2 w-full h-full bg-brand-500/15 font-display",
  children: [
    { type: "text", text: "@theme → utilities", tw: "text-hero font-bold text-brand-500" },
    { type: "container", tw: "flex px-4 py-1 rounded-card bg-brand-500",
      children: [{ type: "text", text: "rounded-card bg-brand-500", tw: "text-sm text-white" }] },
    { type: "text", text: "var(--color-brand-500) in a style", tw: "text-sm", style: { color: "var(--color-brand-500)" } },
  ],
}, { width: 340, height: 140, css: [theme] });
```

![A light violet card with a large violet title, a rounded violet pill and a violet line, all coloured by an @theme variable](/img/guide/html-and-tailwind-theme.png)

`animate-*` utilities, including names from `--animate-*`, need the `full` profile; see
[Animation](./animation.md#built-in-names-and-tailwind).

### What Tailwind does not do

Checked against the package. takumi does not support any of these either:

<!-- @example html-and-tailwind#tw-gaps -->
```js
const px = (tw, css) => {
  const raw = renderer.renderSync({ type: "container", tw: `block w-4 h-4 ${tw}` }, { width: 16, height: 16, format: "raw", css });
  return raw[3] === 0 ? "transparent" : "painted";
};
px("bg-red-500");                                          // painted
px("bg-linear-to-r from-red-500 to-blue-500");             // painted
px("bg-gradient-to-r from-red-500 to-blue-500");           // transparent – Tailwind v3 name, not supported
px("bg-brand-500", ["@theme { --color-brand-500: red }"]);  // painted – utilities read @theme variables
px("bg-[var(--brand)]", [":root { --brand: red }"]);        // transparent – var() inside [...] is not supported
px("bg-(--brand)", [":root { --brand: red }"]);             // transparent – nor the (--var) shorthand
px("hover:bg-red-500");                                    // transparent – hover / focus / dark never apply
```

- **Tailwind v3 names**: `bg-gradient-to-*` compiles to nothing; use the v4 `bg-linear-to-*` (with
  `from-*` / `via-*` / `to-*`), `bg-radial`, `bg-conic`.
- **Interactive and environment variants**: `hover:`, `focus:`, `dark:`, `group-*:`, `peer-*:`,
  `max-*:` breakpoints.
- **Utilities**: `z-*`, `order-*`, `skew-*`, `ring-*`, `space-x-*` / `space-y-*` (use `gap-*`),
  `divide-*`, `place-*`, `cursor-*`; `outline-2` without an outline style, `backdrop-blur` without a
  size, `mask-b-from-50%`.
- **Syntax**: arbitrary properties (`[width:30px]`), `(--var)` shorthand, `var()` in brackets
  (`bg-[var(--x)]`, `w-[var(--w)]`), `@apply` in stylesheets, `@utility`, `@plugin`, `@config`.
- **The `class` attribute**: in HTML only `tw="..."` is compiled as Tailwind (see [above](#tailwind)).
- Unknown classes are skipped silently; nothing throws.

If you need more of Tailwind, compile your classes with the real Tailwind in your build and pass the
generated CSS through `css`; the stylesheet engine then applies whatever CSS it supports, matching
elements by `class` (HTML) or `className` (node trees).

## See also

- [Styles](./styles.md) — inline styles, stylesheets, cascade and layout modes
- [CSS support](./css-support.md#html-input) — the HTML and Tailwind status tables
- [Images](./images.md) — image sources for `<img>`
- [How bm-engine works](./concepts.md) — the pipeline and the three inputs
