# Pagination

[English](pagination.md) · [Tiếng Việt](../../vi/pdf/pagination.md)

A paged PDF lays the document out at the width of the page area and then cuts it into pages with
CSS fragmentation rules. This page shows how content flows from page to page, how to force and forbid breaks
with CSS, Tailwind or a node tree, how tables repeat their header and footer, what `@page` can set, and
how to keep only some pages. It needs the [`pdf` profile](index.md); the break properties are ignored by
every other profile. Every Node.js snippet is a section of `docs/examples/pdf-pagination.mjs` in the
repository and was executed by it.

- [Setup](#setup)
- [Content flows onto new pages](#content-flows-onto-new-pages)
- [Forcing a break](#forcing-a-break)
- [Keeping things together](#keeping-things-together)
- [Orphans and widows](#orphans-and-widows)
- [Tables](#tables)
- [Page rules](#page-rules)
  - [Named pages](#named-pages)
- [Keeping some pages](#keeping-some-pages)
- [Limits and what is approximate](#limits-and-what-is-approximate)

## Setup

The examples use small 400 x 300 px pages with 24 px margins so that a few lines already fill a page:

<!-- @example pdf-pagination#setup -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const small = { size: { width: 400, height: 300 }, margin: 24 }; // pages of 400 x 300 CSS px
```

## Content flows onto new pages

Nothing has to be done: when the content is taller than the page area, it continues on the next page.
A line of text is never split, a block can be split between lines, and the break is chosen where Chromium
would choose it (between blocks first, inside a paragraph between lines, with the `orphans` and
`widows` rules below).

<!-- @example pdf-pagination#flow -->
```js
const lines = Array.from({ length: 40 }, (_, k) => `<p>Line ${k + 1} of the report</p>`).join("");
const flowing = await pdf.render(`<div style="font-family: Inter; font-size: 14px">${lines}</div>`, small);
```

The document can have at most 20 000 pages; beyond that the render throws `too many pages`.

## Forcing a break

`break-before` and `break-after` with `page` (or the older `always`) force a break. The same works with
the legacy names `page-break-before` and `page-break-after`.

| Value | Effect in a PDF |
|:--|:--|
| `auto` | Break only where the content needs it (the default). |
| `page`, `always` | Always break. |
| `left`, `right`, `recto`, `verso` | Always break. **No blank page is inserted** to land on a left or right page. |
| `avoid`, `avoid-page` | Avoid a break here when there is any other choice. |
| `column`, `avoid-column` | Not a page break (`avoid-column` is `auto`). |

A forced break at the very start of the document does not add an empty first page.

<!-- @example pdf-pagination#break-before -->
```js
const chapters = ["Intro", "Method", "Results"]
  .map((t) => `<h1 style="break-before: page">${t}</h1><p>Text of ${t}.</p>`)
  .join("");
const book = await pdf.render(`<div style="font-family: Inter">${chapters}</div>`, small);
// a forced break at the very start of the document adds no empty first page
```

In HTML, Tailwind v4 break utilities are accepted in the `tw` attribute (not in `class`) on the `pdf`
profile: `break-before-auto`, `break-before-avoid`, `break-before-page` (also `break-before-all`),
`break-before-avoid-page`, `break-before-left`, `break-before-right`, `break-before-column`, the same
for `break-after-*`, and `break-inside-auto`, `break-inside-avoid`, `break-inside-avoid-page`,
`break-inside-avoid-column`. These utilities use Tailwind’s meanings.

<!-- @example pdf-pagination#tailwind -->
```js
const tw = await pdf.render(
  `<div style="font-family: Inter">
     <section tw="break-after-page"><h1>Cover</h1></section>
     <section tw="break-inside-avoid"><h2>Summary</h2><p>Kept together on one page.</p></section>
   </div>`,
  small,
);
```

In a node tree, use the camelCase style property, which is the same as the CSS one:

<!-- @example pdf-pagination#node-tree -->
```js
const tree = {
  type: "container",
  style: { display: "flex", flexDirection: "column", fontFamily: "Inter", fontSize: 16 },
  children: [
    { type: "text", text: "Page one" },
    { type: "text", text: "Page two", style: { breakBefore: "page" } },
  ],
};
const twoPages = await pdf.render(tree, small);
```

## Keeping things together

`break-inside: avoid` (or `avoid-page`) asks for a box not to be split. The page break then moves before
the box when it would otherwise be cut. In the example the
cards are 90 px tall on a 252 px page area: without the rule card 3 starts on page 1 and continues on
page 2, with it card 3 moves to page 2 whole.

<!-- @example pdf-pagination#avoid -->
```js
const cards = (rule) => Array.from({ length: 6 }, (_, k) =>
  `<div style="${rule} margin-bottom: 8px; height: 90px; border: 1px solid #94a3b8"><b>Card ${k + 1}</b></div>`).join("");
const cut = await pdf.render(`<div style="font-family: Inter">${cards("")}</div>`, small);
// page 1 shows cards 1, 2 and the top of card 3
const whole = await pdf.render(`<div style="font-family: Inter">${cards("break-inside: avoid;")}</div>`, small);
// card 3 does not fit in what is left of page 1, so it moves to page 2 whole: two cards per page
```

`break-before: avoid` and `break-after: avoid` ask for no break right before or after the box, which is how
you keep a heading with the paragraph that follows it. Replaced content (images) and `line-clamp` boxes
are never split.

## Orphans and widows

`orphans` is the least number of lines of a paragraph left at the bottom of a page, and `widows` the
least number carried to the next one. Both take an integer of at least 1, are inherited and default to 2.
Here the paragraph has room for exactly one line on page 1; with the default of 2 the whole paragraph
moves to page 2, with `orphans: 1` one line stays behind:

<!-- @example pdf-pagination#widows -->
```js
const paragraph = "The quick brown fox jumps over the lazy dog. ".repeat(12);
const flow = (rule) =>
  `<div style="height: 230px"></div>
   <p style="margin: 0; font: 13px/16px Inter; ${rule}">${paragraph}</p>`;
const oneLine = await pdf.render(flow("orphans: 1"), small); // one line of the paragraph at the bottom of page 1
const moved = await pdf.render(flow("orphans: 2"), small);   // the default: the paragraph starts on page 2
```

## Tables

A `thead` is drawn again at the top of every page the table continues on, and a `tfoot` again at the
bottom of every page before its last. Tables need the `tables` feature, which the `pdf` profile has.

<!-- @example pdf-pagination#table -->
```js
const rows = Array.from({ length: 30 }, (_, k) => `<tr><td>Item ${k + 1}</td><td>${(k + 1) * 3}</td></tr>`).join("");
const table = await pdf.render(
  `<table style="width: 100%; font-family: Inter; font-size: 12px">
     <thead><tr style="background: #e2e8f0"><th>Name</th><th>Qty</th></tr></thead>
     <tbody>${rows}</tbody>
     <tfoot><tr><td>Total</td><td>1395</td></tr></tfoot>
   </table>`,
  small,
);
// the header group is drawn again at the top of every page, the footer group at the bottom of every page
```

Rows are split across pages when they do not fit, and a cell that spans several rows (`rowspan`) is cut with its rows. Collapsed borders end each fragment with its own bottom border. Check collapsed borders with repeated headers at the intended print size.

## Page rules

Besides the `size` and `margin` options, the page can be set from CSS. The rules are read from the
`<style>` elements of an HTML source and from the strings of the `css` option (also for a node tree).
A document's `@page` wins over the `size` and `margin` options, as with Chromium's
`preferCSSPageSize`.

<!-- @example pdf-pagination#at-page -->
```js
const styled = await pdf.render(
  `<style>
     @page { size: A5 landscape; margin: 12mm }
     @page :first { margin-top: 40mm }
   </style>
   <div style="font-family: Inter">${lines}</div>`,
);
```

<!-- @example pdf-pagination#at-page-css -->
```js
const viaOption = await pdf.render(`<div style="font-family: Inter">${lines}</div>`, {
  css: "@page { size: letter; margin: 0.5in }", // the css option works for node trees too
});
```

Supported:

- `@page`, `@page :first`, `@page :left` and `@page :right`, at the top level of the stylesheet or inside
  `@media` (print media the size of the options' page), `@supports` and `@layer`. The first page counts as a
  right page (a left one when the root element has `direction: rtl`). The rules cascade per page kind as in
  Blink: `!important` first, then the cascade layer, then a page name over `:first` over `:left` / `:right`
  over none, then source order.
- **Named pages**: the `page` property (`auto` or a custom identifier; it is not inherited), `@page name { ... }`
  and `@page name:first` (also `:left` / `:right`). When the used page name changes between block siblings the
  page breaks, and each page takes the `size`, margins and page-area height of its name (see
  [Named pages](#named-pages)).
- `size`: `auto`, a name from the list in [PDF output](page-size-and-viewport.md#page-size-orientation-and-margins)
  optionally with `portrait` or `landscape`, an orientation alone, or one or two lengths.
- `margin` (one to four values) and `margin-top`, `margin-right`, `margin-bottom`, `margin-left`. Lengths
  in any CSS unit: `px`, `mm`, `cm`, `in`, `pt`, `pc`, `q`, viewport units (of the options' page), `em` /
  `ex` / `ch` (of the root element's font) and `rem`; `calc()`, `min()`, `max()` and `clamp()`; `var()` of
  the root element's custom properties (a `var()` that does not resolve resets the descriptor: `size: auto`,
  a margin of 0); percentages of the page size on that side's axis; `auto` is 0. An invalid declaration is
  dropped on its own.

The root element, for `em`, `var()` and `direction`, is the `<body>` of a whole HTML document (`rem` reads
the `<html>` element); the custom properties of a fragment with several top-level elements are not read.
A page whose margins leave no page area keeps the geometry of the options.

Not supported: rule objects in `css`. Page-margin boxes such as `@top-center` are skipped; the descriptors around them still apply.

### Named pages

Give an element `page: name` and a matching `@page name` rule, and its content is printed on pages of that
name. The page breaks where the name changes, before and after the annex here:

<!-- @example pdf-pagination#named-pages -->
```js
const named = await pdf.render(
  `<style>
     @page wide { size: 600px 300px; margin: 24px }
     .annex { page: wide }
   </style>
   <div style="font-family: Inter">
     <p>Body text on a normal page.</p>
     <section class="annex"><h2>Annex</h2><p>This section is printed on a wider page.</p></section>
     <p>Back to a normal page.</p>
   </div>`,
  small,
);
// the used page name changes twice, so there is a break before and after the annex
```

Each page lays its content out at its own page-area width does. A named page of another width
re-flows the content it holds, and so does a page whose `:first`, `:left` or `:right` rule changes the
width: when a paragraph breaks across the change, its lines after the break wrap at the new width. Tables,
flex and grid containers that continue on a page of another width are laid out again at that width.

When every page has the same width, the document is laid out once. Otherwise each run of pages of one width
is laid out from where the run before it stopped, so a document whose width changes often (`:left` and
`:right` pages of different widths) costs about one layout of the rest of the document per change. A page
that starts in the middle of side-by-side content (a table row or a flex line broken across the change)
keeps the width of the page before it.

## Keeping some pages

`pageRanges` keeps only the listed pages. An entry is a page number or `{ from, to }`; both bounds are
inclusive and optional (an unset `from` is the first page, an unset `to` the last). Pages are numbered
from 1. The page counters keep the numbers of the full document ([Headers, footers and page
counters](headers-footers.md)).

<!-- @example pdf-pagination#ranges -->
```js
const part = await pdf.render(`<div style="font-family: Inter; font-size: 14px">${lines}</div>`, {
  ...small,
  pageRanges: [1, { from: 3 }], // page 1 and page 3 to the end; pages are numbered from 1
});
```

A range that is not valid (`0`, `1.5`, or `from` after `to`) throws `Page range is invalid: ...`, and
a list that keeps none of the document's pages throws:

<!-- @example pdf-pagination#ranges-error -->
```js
let rangeError;
try {
  await pdf.render(`<p style="font-family: Inter">one page</p>`, { pageRanges: [{ from: 5 }] });
} catch (e) {
  rangeError = e.message;
}
// bm-engine: The page ranges select none of the document's 1 pages
```

## Limits and what is approximate

The pages are cut after layout, from one tall layout, the way Blink handles flex and grid fragmentation.
That has consequences:

- Percentages and stretching never see the page size.
- A box with a definite `height` keeps it even when its content is pushed across a page; other boxes grow by
  what a break pushed down.
- Lines do not re-flow around a float that moved to another page: the layout is paginated once, not laid out again per fragment.
- A rotated or skewed box cut by a page boundary is painted whole in the page where it starts.
- The marker of a list item split across pages stays on the first line of the item, as in Chrome.
- A page that starts in the middle of a table row or a flex line keeps the width of the page before it when
  its own width differs (see [Named pages](#named-pages)).
- A background or border of a box that spans a page edge is cut by the page. With `box-decoration-break: slice`
  (the default) the cut edges lose their border, padding and corner radii; with `clone` every fragment keeps its
  border, padding and radii.
