# PDF output

[English](pdf.md) · [Tiếng Việt](../vi/pdf.md)

bm-engine can write PDF files. The PDF writer is a port of `takumi-pdf`: the same layout engine that
draws PNG and SVG lays a document out, breaks it into pages and writes it as vector graphics with real,
selectable text and embedded subset fonts. It also writes headers and footers, links, bookmarks,
metadata, attachments, tagged PDF and PDF/A. The PDF writer is only in the **`pdf` build profile**
(`bm-engine/pdf`); `bm-engine` and the other entries do not expose it. This page covers the entry point, a first
render in Node.js and in a browser, page size and margins, `measure`, the profile's size and what is
not supported. Every Node.js snippet is a section of `docs/examples/pdf.mjs` in the repository and was
executed by it. Further pages: [Pagination](pdf-pagination.md),
[Headers, footers and page counters](pdf-headers-footers.md),
[Links, bookmarks, metadata and attachments](pdf-links-metadata.md), [Fonts in PDF](pdf-fonts.md) and
[Accessibility and archival](pdf-accessibility.md).

- [Install and entry point](#install-and-entry-point)
- [Render HTML to a PDF](#render-html-to-a-pdf)
- [Render a node tree](#render-a-node-tree)
- [Page size, orientation and margins](#page-size-orientation-and-margins)
- [One page: `viewport`](#one-page-viewport)
- [`measure`, `prepare` and the synchronous methods](#measure-prepare-and-the-synchronous-methods)
- [Options at a glance](#options-at-a-glance)
- [In a browser and on edge runtimes](#in-a-browser-and-on-edge-runtimes)
- [The `pdf` profile and its size](#the-pdf-profile-and-its-size)
- [What the other profiles do](#what-the-other-profiles-do)
- [What is drawn and what is not](#what-is-drawn-and-what-is-not)
- [Known limitations](#known-limitations)

## Install and entry point

PDF output ships in the same npm package as the image engine:

```sh
npm install bm-engine
```

| Import | Node.js | Everywhere else |
|:--|:--|:--|
| `bm-engine/pdf` | the native addon when it is installed, otherwise the `pdf` binary (`bm_engine.pdf.wasm`); initialised on import | `await init()` loads `bm_engine.pdf.wasm` next to the module, or pass the binary: `await init(wasm)` |
| `bm-engine/pdf.wasm` | the raw binary, for bundler asset imports and Workers module imports | same |

`bm-engine/pdf` exports everything the image entries export (`init`, `initSync`, `Renderer`, `features`,
...) and adds `PdfRenderer`, the shared functions `render`, `measure` and `prepare`, and the page counter
helpers `PageNumber`, `TotalPages` and `TargetPageNumber`. Like the other profile entries it has **its
own module instance**, so it can be loaded next to `bm-engine/full` in one process. `profile` is `"pdf"`
and `features.pdf` is `true` (every other feature is on as well: the profile is `full` plus PDF).

## Render HTML to a PDF

`PdfRenderer` holds the registered fonts, so create one and reuse it. bm-engine ships no font, and a
render fails when the text needs a character no registered font draws (see [Fonts in PDF](pdf-fonts.md)),
so register fonts first:

<!-- @example pdf#setup -->
```js
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

A string source is HTML, as everywhere in bm-engine. The result is a `Uint8Array`:

<!-- @example pdf#html -->
```js
const bytes = await pdf.render(
  `<style>
     body { font-family: Inter; font-size: 14px; color: #0f172a; }
     h1 { font-size: 28px; }
   </style>
   <h1>Quarterly report</h1>
   <p>This page is vector text: it can be selected, searched and copied.</p>`,
);
writeFileSync("report.pdf", bytes); // A4, 10 mm margins
```

Without options the output is paged: A4, 10 mm margins on every side, and content that does not fit on
one page continues on the next ([Pagination](pdf-pagination.md)). The text in this file is drawn as
text, not as outlines, so a viewer can select, search and copy it, and every font is subset to the
glyphs the document uses.

## Render a node tree

Node trees are the same objects the image `Renderer` takes (see the [API reference](api.md)). Style
fields use camelCase and text takes `fontFamily` of a registered font:

<!-- @example pdf#node-tree -->
```js
const card = {
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 8, padding: 24, backgroundColor: "#f1f5f9" },
  children: [
    { type: "text", text: "Hello PDF", style: { fontFamily: "Inter", fontSize: 32, fontWeight: 700 } },
    { type: "text", text: "A node tree renders the same way as HTML.", style: { fontFamily: "Inter", fontSize: 14 } },
  ],
};
const letter = await pdf.render(card, { size: "letter", landscape: true, margin: 24 });
```

A source can be an HTML string, a node tree, `{ json: "<node tree as JSON text>" }`, or a handle from
`prepare()`. Tailwind classes go in a node's `tw` field or an HTML `tw` attribute ([HTML and Tailwind](html-and-tailwind.md)).

## Page size, orientation and margins

| Option | Meaning |
|:--|:--|
| `size` | A page size name or `{ width, height }` in CSS px. Default `"a4"`. |
| `landscape` | `true` swaps the page's width and height, also for an explicit `size`. |
| `margin` | One number for all sides, or `{ top, right, bottom, left }`. Each side is a number in CSS px or `"auto"`; a side you leave out is `"auto"`. Default `"auto"` on every side. |
| `backgroundColor` | The paper colour, any CSS colour, painted under everything on every page. Unset leaves the page empty. |

Size names are `a3`, `a4`, `a5`, `b4`, `b5`, `jis-b4`, `jis-b5`, `ledger`, `legal` and `letter`, matched
without regard to case and portrait (`ledger` is 11 x 17 in, `letter` 8.5 x 11 in). A PDF page is
measured in points: one CSS px is 0.75 pt, so `{ width: 400, height: 240 }` is a 300 x 180 pt page.

<!-- @example pdf#custom-size -->
```js
const ticket = await pdf.render(card, {
  size: { width: 400, height: 240 }, // CSS px: 300 x 180 pt
  margin: { top: 12, right: 12, bottom: 12, left: 12 },
  backgroundColor: "#ffffff",       // paper colour under everything
});
```

`"auto"` on a side that carries a header or footer makes the margin as large as the band needs (the
band's height plus 20 px, and at least 10 mm, which is 37.8 px); on the other sides, and on a side
without a band, it is 10 mm. See [Headers, footers and page counters](pdf-headers-footers.md#margins-and-bands).
`landscape` and an `@page` rule can also set the page size; a document's `@page { size: ... }` wins
over the `size` option ([Pagination](pdf-pagination.md#page-rules)).

Pages must leave room for content: a size and margins that leave less than 1 px of width or height
throw `Page size must be finite and larger than zero`. An unknown size name throws
`unknown page size: <name>`.

## One page: `viewport`

`viewport: { width, height? }` renders the whole document on a single page of that size in CSS px, with
no margins, headers or page breaks. Without `height`, the page is as tall as the laid-out content. This
is the form for tickets, badges and posters. `viewport` cannot be combined with `size`, `landscape`,
`margin`, `header`, `footer`, `pages` or `pageRanges`; doing so throws `viewport is mutually exclusive
with the paged options (size, landscape, margin, header, footer, pages, pageRanges)`.

<!-- @example pdf#viewport -->
```js
const poster = await pdf.render(card, { viewport: { width: 600 } }); // one page, as tall as the content
```

## `measure`, `prepare` and the synchronous methods

`measure(source, options)` returns the laid-out `{ width, height }` in CSS px without writing a PDF. With
page options it lays the source out the way a header or footer is laid out: at the full page width with
unbounded height, with three-digit page counters. Margins do not change the result. With `viewport` it
lays out at the viewport. It is the tool for sizing a band yourself ([Headers, footers and page
counters](pdf-headers-footers.md#margins-and-bands)):

<!-- @example pdf#measure -->
```js
const { width, height } = await pdf.measure(card, { size: "a4" });
```

`renderSync` and `measureSync` do the same without awaiting; the async forms exist for `fonts` and lazily
loaded `images`. `prepare(source, options)` resolves fonts and images once and returns a handle that
`render` and `measure` accept; options passed to `render` merge over the ones given to `prepare`. It
fetches nothing: bm-engine has no equivalent of takumi-pdf's `needs` pass, so image bytes go in the
`images` option (`[{ src, data }]`) and font files in `fonts` or `registerFont`. A `@font-face` rule's
files are not downloaded.

<!-- @example pdf#sync -->
```js
const same = pdf.renderSync(card, { viewport: { width: 600 } });
```

The module-level `render`, `measure` and `prepare` use one lazily created `PdfRenderer` that you cannot
reach to register fonts; use them for documents without text or with the `fonts` option, and a
`PdfRenderer` otherwise. Call `free()` on a renderer you no longer need (it is also disposable with
`using`).

## Options at a glance

| Option | Page | Meaning |
|:--|:--|:--|
| `size`, `landscape`, `margin` | [here](#page-size-orientation-and-margins) | Page geometry. |
| `viewport` | [here](#one-page-viewport) | One page of a fixed size. |
| `backgroundColor` | [here](#page-size-orientation-and-margins) | Paper colour. |
| `header`, `footer`, `pages` | [Headers and footers](pdf-headers-footers.md) | Bands repeated on every page and per-page overrides. |
| `pageRanges` | [Pagination](pdf-pagination.md#keeping-some-pages) | Keep only some pages. |
| `outline` | [Links and bookmarks](pdf-links-metadata.md#bookmarks) | Bookmarks from `h1`-`h6`. |
| `metadata`, `lang` | [Metadata](pdf-links-metadata.md#metadata) | Title, authors, dates, custom XMP; document language. |
| `attachments` | [Attachments](pdf-links-metadata.md#attachments) | Embedded files. |
| `uncoveredText`, `fontFamilies`, `fonts` | [Fonts in PDF](pdf-fonts.md) | What happens with characters no font draws; font stack; fonts to register. |
| `tagged`, `pdfa` | [Accessibility and archival](pdf-accessibility.md) | Structure tree, PDF/UA, PDF/A. |
| `css`, `cssVariables` | [HTML and Tailwind](html-and-tailwind.md) | A stylesheet and `:root` custom properties applied before layout. |
| `images` | [Images](images.md) | Pre-fetched image bytes for `src` values. |
| `signal` | | An `AbortSignal` checked before the render reads and draws the document. |

An unknown or misspelt option is not reported; a wrong value of a known option throws with a message
that names it (for example `invalid margin: expected a number or "auto"`).

## In a browser and on edge runtimes

The entry has no Node.js dependency. In a browser, call `init()` once (it fetches the binary next to
the module), then use the same API; in a Cloudflare Worker, import the binary as a module. These
snippets were not run here (the Node.js entry shares the same code):

```js
// Browser, ES modules
import { init, PdfRenderer } from "bm-engine/pdf";
await init(); // fetches bm_engine.pdf.wasm

const pdf = new PdfRenderer();
const font = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
pdf.registerFont({ name: "Inter", data: font });

const bytes = await pdf.render(`<h1 style="font-family: Inter">Hello</h1>`);
const url = URL.createObjectURL(new Blob([bytes], { type: "application/pdf" }));
window.open(url); // or set it as an <a download> / <iframe> source
```

```js
// Cloudflare Workers
import wasm from "bm-engine/pdf.wasm";
import { init, PdfRenderer } from "bm-engine/pdf";

await init(wasm);
```

See [Getting started](getting-started.md#edge-runtimes-deno-bun) for bundler and runtime details; they
apply to this entry in the same way.

### Native backend on Node.js

On Node.js, Bun and Deno, `bm-engine/pdf` runs on the native Node-API addon when it is installed (the same
addon and the same optional `bm-engine-<platform>` package that `bm-engine` uses; there is no extra package),
and otherwise falls back, silently, to the wasm `pdf` profile. `backend`, exported from `bm-engine/pdf`, is
`"native"` or `"wasm"`, and `BM_ENGINE_BACKEND=wasm|native` forces one. The PDF bytes are identical on both
backends. Natively, the async methods (`PdfRenderer.render` and `measure`, `Renderer.renderPdf` and
`measurePdf`) run on the libuv thread pool instead of blocking the event loop; `init()` and `initSync()` do
nothing there, and `profile` is still `"pdf"`. In browsers, bundlers, Workers and edge runtimes nothing
changes: the entry is the wasm `pdf` profile. See [Native addon vs WebAssembly](native-vs-wasm.md).

## The `pdf` profile and its size

`bm_engine.pdf.wasm` is `full` plus the PDF writer: about 1.5 MB raw, about 0.4 MB more than
`bm_engine.wasm` (`full`). The PDF code is compiled only into this binary and into the native addon, and so are the paged
layout and the CSS paged-media properties it needs. (The native addon is the `full` feature set plus PDF
output; `bm-engine` itself never exposes the PDF writer.) [Profiles and size](profiles-and-size.md) has the
exact numbers for every binary. Build it yourself with `npm run build:pdf`
(`node scripts/build.mjs --profile=pdf`) or `zig build -Dprofile=pdf`
([Building from source](building-from-source.md)).

Because the pagination code is only in this profile, the CSS properties `break-before`, `break-after`,
`break-inside`, `page-break-*`, `orphans` and `widows`, and the Tailwind `break-before-*`,
`break-inside-*` and `break-after-*` utilities, apply only to PDF output (`bm-engine/pdf`). Image renders
(`render`, `renderSvg`, `measure`) accept and ignore them on every build, including `bm-engine/pdf` and the native
addon, so an image is the same on every build. `background-clip: border-area` follows the same rule.

## What the other profiles do

Every `Renderer` has `renderPdf`, `renderPdfSync`, `measurePdf` and `measurePdfSync`, but only the
`pdf` build exposes a PDF writer. On any other build they throw, and that includes `bm-engine` running on the
native addon (the addon binary contains the PDF writer, but `bm-engine` hides it: `features.pdf` is `false`):

<!-- @example pdf#not-supported -->
```js
import { Renderer } from "bm-engine/full"; // the full profile has no PDF writer
let message;
try {
  new Renderer().renderPdfSync(card);
} catch (e) {
  message = e.message;
}
// message: bm-engine: renderPdf is not supported by this build (use the pdf build: import from "bm-engine/pdf")
```

Check `features.pdf` before you call them if your build can vary.

## What is drawn and what is not

The PDF writer draws what the image painter draws, as vector operators: backgrounds, borders and
outlines, gradients (linear, radial and conic), box and text shadows, opacity and isolation groups,
blend modes, `clip-path`, masks, colour `filter` functions, transforms, text with decorations and
strokes, tables, floats, images (JPEG and PNG are embedded as they are when possible) and SVG images
that use the supported subset as vector paths ([Fonts in PDF](pdf-fonts.md) covers text).
Structure for accessibility and the PDF/A and PDF/UA standards are described in
[Accessibility and archival](pdf-accessibility.md).

Some CSS has no PDF equivalent. A `blur()` or `drop-shadow()` `filter` fails the render with
`A PDF cannot draw filter: blur(2px)` (the message names the filter), as in takumi-pdf. `backdrop-filter`
is ignored.

## Known limitations

These are the differences from takumi-pdf that are known at the time of writing. Each is checked
against the sources.

- **List markers.** PDF output paints them, in paged and in `viewport` renders, with `Lbl` structure elements;
  PNG, JPEG, WebP and SVG output draw none. Supported: takumi's counter styles for ordered lists, the symbols
  disc, circle, square and disclosure, `start`, `reversed`, `value`, and inside and outside placement. Not
  supported: `list-style-image` (the counter style is drawn instead), `::marker` rules, and markers of an item
  that starts with a flex, grid, table or image box (those items get no marker).
- **Stacking order.** Positioned and `z-index`ed boxes are painted with their stacking context, in CSS painting
  order, as takumi does. No difference is known in the fixtures compared with takumi-pdf, but the order is not
  proven identical for every document.
- **`@page`.** `size`, `margin`, `:first`, `:left` and `:right` work, and so do named pages (the `page`
  property, `@page name`, `name:first`): each named page has its own size, margins and page-area height. The
  content is laid out once, at the unnamed pages' page-area width. A named page of another width gets its size, but
  the content keeps its width and starts at the page's left margin; `:first`, `:left` and `:right` rules that
  change the width are dropped. `@page` inside `@media`, `@layer` or `@supports` and viewport units in page
  descriptors are not supported. See [Pagination](pdf-pagination.md#page-rules).
- **Breaking.** `break-before` / `break-after` with `left`, `right`, `recto` or `verso` break the page
  but do not insert a blank page to land on a left or right side. `column` is not a page break. Lines do
  not re-flow around a float that moved to another page, a table cell that spans rows is not split
  across pages, and table parts are not sliced specially at page edges. `box-decoration-break: clone` works: each
  fragment of a box cut by a page keeps its border, padding and radii.
- **`needs`.** takumi-pdf's `needs` pass (listing the images and font files a document wants) is not
  implemented; pass image bytes and fonts yourself.
- **Colour glyphs.** COLR (v0 and v1) and bitmap (CBDT, sbix) glyphs are embedded; SVG-in-OpenType glyphs
  are drawn as their outline.
- **PDF/A is checked, not certified.** The validation covers the main rules krilla enforces
  (fonts, document language and title, alternate text, outline, attachments, dates). It does not check
  limits such as string, array or nesting lengths. No external validator (veraPDF) has been run on the
  output; conformance is established by comparing bm-engine's files with takumi-pdf's, not by a
  certification. See [Accessibility and archival](pdf-accessibility.md#how-far-the-checks-go).
- **Embedded font programs.** The subset fonts in the file are not always byte-identical to the ones
  takumi-pdf writes, although they draw the same glyphs.

Compared with takumi-pdf's 89 golden PDFs (`node scripts/pdf-compare.mjs`), most fixtures render with
the same page content operator for operator; see [Differences from
takumi](differences-from-takumi.md#pdf-output) for the current state.

When you run into a difference that matters, [Troubleshooting](troubleshooting.md) lists the usual
causes of missing text and wrong layout; they apply to PDF in the same way.
