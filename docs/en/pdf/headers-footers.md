# Headers, footers and page counters

[English](headers-footers.md) · [Tiếng Việt](../../vi/pdf/headers-footers.md)

A paged PDF can repeat a header at the top and a footer at the bottom of every page, with the page
number, the page count and, for cross references, the page another element landed on. A header or footer
(a *band*) is an ordinary HTML string or node tree, so everything the engine can lay out works in it. This
page covers writing a band, the counters, per-page overrides, how the margins follow the bands, and
counters inside the document itself. It needs the [`pdf` profile](index.md). Every Node.js snippet is a
section of `docs/examples/pdf-headers.mjs` in the repository and was executed by it.

- [Setup](#setup)
- [A footer with page numbers](#a-footer-with-page-numbers)
- [Counters in a node tree](#counters-in-a-node-tree)
- [A header](#a-header)
- [Different bands on some pages](#different-bands-on-some-pages)
- [Margins and bands](#margins-and-bands)
- [Counters in the content](#counters-in-the-content)
- [Counters in a repeated fixed box](#counters-in-a-repeated-fixed-box)
- [Rules and limits](#rules-and-limits)

## Setup

<!-- @example pdf-headers-footers#setup -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer, PageNumber, TotalPages } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const lines = Array.from({ length: 40 }, (_, k) => `<p>Line ${k + 1} of the report</p>`).join("");
const body = `<div style="font-family: Inter; font-size: 14px">${lines}</div>`;
const page = { size: { width: 400, height: 300 }, margin: 24 };
```

## A footer with page numbers

`footer` and `header` take an HTML string, a node tree or `false` (no band). An element of the band whose
class list contains `pageNumber` gets the number of the page being drawn, and one classed `totalPages`
gets the page count. They are class names, not tags, so they work on a `span` in HTML; the element's
content is replaced by the number.

<!-- @example pdf-headers-footers#footer-html -->
```js
const footer = `<div style="font: 11px Inter; color: #475569">
  Page <span class="pageNumber"></span> of <span class="totalPages"></span>
</div>`;
const numbered = await pdf.render(body, { ...page, footer });
```

A band is laid out on its own, apart from the document, so set its font and size on the band's own
elements (the example uses the `font` shorthand). It uses the fonts registered on the renderer.

## Counters in a node tree

In a node tree, `PageNumber()`, `TotalPages()` and `TargetPageNumber()` build the nodes with the right
class. Each takes `{ format, className, style, tw }`. `format` is a counter style name and defaults to
`decimal`: `decimal`, `decimal-leading-zero`, `lower-roman`, `upper-roman`, `lower-alpha`, `lower-latin`,
`upper-alpha`, `upper-latin`, `lower-greek`, `hiragana`, `katakana`, `trad-chinese-informal`,
`cjk-ideographic`, `cjk-decimal`, and the digit systems `arabic-indic`, `bengali`, `cambodian`, `khmer`,
`devanagari`, `gujarati`, `gurmukhi`, `kannada`, `lao`, `malayalam`, `mongolian`, `myanmar`, `oriya`,
`persian`, `urdu`, `tamil`, `telugu`, `thai` and `tibetan`. In HTML, put the same name as an extra class:
`<span class="pageNumber lower-roman">`.

<!-- @example pdf-headers-footers#footer-node -->
```js
const nodeFooter = {
  type: "container",
  style: { display: "flex", columnGap: 4, fontFamily: "Inter", fontSize: 11, color: "#475569" },
  children: [
    { type: "text", text: "Sheet" },
    PageNumber({ format: "upper-roman" }), // I, II, III
    { type: "text", text: "/" },
    TotalPages(),
  ],
};
const roman = await pdf.render(body, { ...page, footer: nodeFooter });
```

## A header

A header works exactly like a footer. It is drawn before the page content, the footer after it.

<!-- @example pdf-headers-footers#header -->
```js
const header = `<div style="font: 11px Inter; display: flex; justify-content: space-between">
  <span>ACME Corp</span><span>Confidential</span>
</div>`;
const both = await pdf.render(body, { ...page, header, footer });
```

## Different bands on some pages

`pages` replaces the band on some pages. The keys are `first`, `last`, `odd` and `even`, each an object
with optional `header` and `footer`. `first` and `last` win over `odd` and `even`. A field you leave out
falls through to the next rule and finally to the document's own `header` / `footer`; `false` draws
nothing on those pages. A one-page document counts as both `first` and `last`.

<!-- @example pdf-headers-footers#pages -->
```js
const ruled = await pdf.render(body, {
  ...page,
  header,
  footer,
  pages: {
    first: { header: false },                         // no header on the cover page
    last: { footer: "<b>End of document</b>" },       // the last page ends differently
    even: { header: "<span style=\"font: 11px Inter\">Even pages</span>" },
  },
});
```

## Margins and bands

Bands are drawn in the page margin. The band is laid out at the full page width, starts 15 pt (20 px)
below the top edge for a header and ends 15 pt above the bottom edge for a footer, and is clipped to
that area. The `auto` margin of the side it sits on grows to fit: the band's height plus 20 px, but never
less than 10 mm (37.8 px). The other sides stay at 10 mm. A number overrides this.

<!-- @example pdf-headers-footers#margins -->
```js
const roomy = await pdf.render(body, {
  ...page,
  margin: { top: "auto", bottom: 60, left: 24, right: 24 }, // top follows the header, bottom is fixed
  header,
});
```

`measure()` gives the height of a band, laid out at the page width with three-digit counters (so a band
that wraps with `100` pages is measured as it will be). That makes the arithmetic explicit; the two
renders below are the same file:

<!-- @example pdf-headers-footers#measure -->
```js
const tall = `<div style="height: 64px; font: 11px Inter">Letterhead</div>`;
const bandHeight = (await pdf.measure(tall, { size: page.size })).height; // 64: the band laid out at the page width
const automatic = await pdf.render(body, { size: page.size, header: tall }); // every margin "auto"
const manual = await pdf.render(body, { size: page.size, header: tall, margin: { top: bandHeight + 20 } });
// the same file: an auto margin is the band height + 20 px (but at least 37.8 px, 10 mm)
```

When the band's size depends on the page count, the engine measures it again with the real count, and if
that moves an `auto` margin the content is laid out again, up to three times.

## Counters in the content

The same classes work in the document itself. The element shows the page it lands on:

<!-- @example pdf-headers-footers#flow-counters -->
```js
const toc = await pdf.render(
  `<div style="font-family: Inter; font-size: 14px">
     <p><a href="#results">Results</a> on page <a href="#results"><span class="targetPageNumber"></span></a></p>
     <h2 id="results" style="break-before: page">Results</h2>
     <p>This is page <span class="pageNumber"></span> of <span class="totalPages"></span>.</p>
   </div>`,
  page,
);
```

`targetPageNumber` gives the page of the element that the nearest enclosing `<a href="#id">` points at
(or the element's own `href`, for `TargetPageNumber({ href })`, which renders its own link). Use it for
"see page 12" and tables of contents. The numbers are
settled over up to three layout passes, because inserting a number can change where later content
lands.

## Counters in a repeated fixed box

A `position: fixed` box is drawn on every page, and counters inside it show each page's own numbers:

<!-- @example pdf-headers-footers#fixed -->
```js
const stamped = await pdf.render(
  `<div style="font-family: Inter; font-size: 14px">
     <div style="position: fixed; top: 4px; right: 8px; font-size: 10px">Sheet <span class="pageNumber"></span>/<span class="totalPages"></span></div>
     ${lines}
   </div>`,
  page,
);
```

## Rules and limits

- A band can hold images (pass bytes or a key from `images`), text, flex and grid. A band that has no
  counter and no `pages` rule is laid out once and drawn on every page.
- Bands never carry link annotations, and in a tagged PDF they are marked as artifacts, so screen readers
  skip them ([Accessibility and archival](accessibility.md)).
- `pageRanges` keeps the numbers of the full document: with `pageRanges: [1, 3]` of a three-page document
  the second page of the file says "Page 3 of 3".
- CSS counters in generated content work in PDF output: `counter()`, `counters()`, `counter-reset`,
  `counter-increment`, `counter-set`, `counter(page)` and `target-counter()`, in the document and in bands.
  The class hooks above remain the way to put page numbers in a node tree.
- Viewport units (`vw`, `vh`, ...) in a band measure the whole page, not the band.
- In the viewport form (`viewport`) there are no bands.
