# PDF quick start

[English](index.md) · [Tiếng Việt](../../vi/pdf/index.md)

bm-engine can write PDF files. The PDF writer is a port of `takumi-pdf`: the same layout engine that
draws PNG and SVG lays a document out, breaks it into pages and writes it as vector graphics with real,
selectable text and embedded subset fonts. It also writes headers and footers, links, bookmarks,
metadata, attachments, tagged PDF and PDF/A. The PDF writer is only in the **`pdf` build profile**
(`bm-engine/pdf`); `bm-engine` and the other entries do not expose it. This page covers the entry point, a
first render in Node.js and in a browser, `measure` and the options; every Node.js snippet is a section of
`docs/examples/pdf.mjs` in the repository and was executed by it. Installing the package is described in
[Getting started](../getting-started.md). The [PDF playground](playground.md) renders
these documents in your browser with the same wasm build.

- [Install and entry point](#install-and-entry-point)
- [Render HTML to a PDF](#render-html-to-a-pdf)
- [Render a node tree](#render-a-node-tree)
- [`measure`, `prepare` and the synchronous methods](#measure-prepare-and-the-synchronous-methods)
- [Options at a glance](#options-at-a-glance)
- [In a browser and on edge runtimes](#in-a-browser-and-on-edge-runtimes)
- [Next steps](#next-steps)

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
render fails when the text needs a character no registered font draws (see [Fonts in PDF](fonts.md)).
With no font registered at all there is no error: the text is silently left out of the page. So register
fonts first:

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
one page continues on the next ([Pagination](pagination.md)). The text in this file is drawn as
text, not as outlines, so a viewer can select, search and copy it, and every font is subset to the
glyphs the document uses.

## Render a node tree

Node trees are the same objects the image `Renderer` takes (see the [API reference](../image/api.md)). Style
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
`prepare()`. Tailwind classes go in a node's `tw` field or an HTML `tw` attribute ([HTML and Tailwind](../image/html-and-tailwind.md)).

## `measure`, `prepare` and the synchronous methods

`measure(source, options)` returns the laid-out `{ width, height }` in CSS px without writing a PDF. With
page options it lays the source out the way a header or footer is laid out: at the full page width with
unbounded height, with three-digit page counters. Margins do not change the result. With `viewport` it
lays out at the viewport. It is the tool for sizing a band yourself ([Headers, footers and page
counters](headers-footers.md#margins-and-bands)):

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
| `size`, `landscape`, `margin` | [here](page-size-and-viewport.md#page-size-orientation-and-margins) | Page geometry. |
| `viewport` | [here](page-size-and-viewport.md#one-page-viewport) | One page of a fixed size. |
| `backgroundColor` | [here](page-size-and-viewport.md#page-size-orientation-and-margins) | Paper colour. |
| `header`, `footer`, `pages` | [Headers and footers](headers-footers.md) | Bands repeated on every page and per-page overrides. |
| `pageRanges` | [Pagination](pagination.md#keeping-some-pages) | Keep only some pages. |
| `outline` | [Links and bookmarks](links-metadata.md#bookmarks) | Bookmarks from `h1`-`h6`. |
| `metadata`, `lang` | [Metadata](links-metadata.md#metadata) | Title, authors, dates, custom XMP; document language. |
| `attachments` | [Attachments](links-metadata.md#attachments) | Embedded files. |
| `uncoveredText`, `fontFamilies`, `fonts` | [Fonts in PDF](fonts.md) | What happens with characters no font draws; font stack; fonts to register. |
| `tagged`, `pdfa` | [Accessibility and archival](accessibility.md) | Structure tree, PDF/UA, PDF/A. |
| `css`, `cssVariables` | [HTML and Tailwind](../image/html-and-tailwind.md) | A stylesheet and `:root` custom properties applied before layout. |
| `images` | [Images](../image/images.md) | Pre-fetched image bytes for `src` values. |
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

See [Getting started](../getting-started.md#edge-runtimes-deno-bun) for bundler and runtime details; they
apply to this entry in the same way.

## Next steps

| Topic | Page |
|:--|:--|
| Paper size, orientation, margins, one-page documents | [Page size, margins and viewport](page-size-and-viewport.md) |
| Content across pages, forced and avoided breaks, `@page` | [Pagination](pagination.md) |
| Running headers and footers, page numbers | [Headers, footers and page counters](headers-footers.md) |
| Links, bookmarks, metadata, attachments | [Links, bookmarks, metadata and attachments](links-metadata.md) |
| Subsetting, fallback, characters no font covers | [Fonts in PDF](fonts.md) |
| Tagged PDF, PDF/UA, PDF/A | [Accessibility and archival](accessibility.md) |
| Complete documents: invoice, report, ticket | [Recipes](recipes.md) |
| HTTP handlers in Next.js, Hono, Workers, ... | [Serving PDFs from a framework](frameworks.md) |
| Native addon, WebAssembly, the `pdf` profile's size | [Native and WebAssembly](native-and-wasm.md) |
| Every export, method and option | [PDF API reference](api.md) |
| What CSS does in a PDF | [CSS in PDF](css-support.md) |
| Compared with takumi-pdf | [Differences from takumi-pdf](differences-from-takumi.md) |
