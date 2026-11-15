# CSS in PDF

[English](css-support.md) · [Tiếng Việt](../../vi/pdf/css-support.md)

A PDF is laid out by the same engine as an image, so the CSS that bm-engine supports for images
([CSS and feature support](../image/css-support.md)) applies to PDF output too, with the additions and
exceptions on this page: the paged-media properties that only PDF output reads, what is drawn and how, and
the image features that behave differently in a PDF. The snippets are sections of
`docs/examples/pdf-css-support.mjs`, which runs them on the wasm and the native backend.

- [Paged media](#paged-media)
- [What is drawn and what is not](#what-is-drawn-and-what-is-not)
- [Differences from image output](#differences-from-image-output)

## Paged media

These apply only to PDF output. Image renders (`render`, `renderSvg`, `measure`) accept and ignore them on
every build, including `bm-engine/pdf` and the native addon:

| Feature | Status | Page |
|:--|:--|:--|
| `break-before`, `break-after`, `break-inside`, `page-break-before` / `-after` / `-inside` | `auto`, `avoid`, `avoid-page`, `avoid-column`, `page`, `always`, `column`, `left`, `right`, `recto`, `verso` parse; `left`, `right`, `recto`, `verso` break the page without inserting a blank page; `column` is not a page break | [Pagination](pagination.md#forcing-a-break) |
| `orphans`, `widows` | integers of at least 1, inherited, default 2 | [Pagination](pagination.md#orphans-and-widows) |
| Tailwind `break-before-*`, `break-inside-*`, `break-after-*` | in the `tw` field / attribute | [Pagination](pagination.md#forcing-a-break) |
| `@page` with `size`, `margin*`, `:first`, `:left`, `:right`, named pages (`page`, `@page name`) | from the `css` option and HTML `<style>`, also inside `@media`, `@supports` and `@layer`; each page lays its content out at its own width | [Pagination](pagination.md#page-rules) |
| Table header and footer groups (`thead`, `tfoot`) | repeated at the top / bottom of every page the table crosses | [Pagination](pagination.md#tables) |
| `position: fixed` | repeated on every page | [Headers and footers](headers-footers.md#counters-in-a-repeated-fixed-box) |
| `box-decoration-break: clone` | each fragment of a box cut by a page keeps its border, padding and radii | [Pagination](pagination.md#limits-and-what-is-approximate) |
| `background-clip: border-area` | PDF output only | |
| Page counters | `PageNumber`, `TotalPages`, `TargetPageNumber` elements; CSS counters in `content` also work: `counter()`, `counters()`, `counter(page)`, `target-counter()` | [Headers and footers](headers-footers.md) |
| Page-margin boxes (`@top-center`, ...) | not supported (use the `header` / `footer` options) | [Headers and footers](headers-footers.md) |

<!-- @example pdf-css-support#ignored-in-images -->
```js
import { Renderer } from "bm-engine/pdf";

const html = `<div style="font-family: Inter">
  <p>Page one</p><p style="break-before: page">Page two</p>
</div>`;
const doc = await pdf.render(html, page);                 // two pages
const image = new Renderer();
image.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const png = image.renderSync(html, { width: 400, height: 120 }); // one image: break-before is ignored
```

## What is drawn and what is not

The PDF writer draws what the image painter draws, as vector operators: backgrounds, borders and
outlines, gradients (linear, radial and conic), box and text shadows, opacity and isolation groups,
blend modes, `clip-path`, masks, colour `filter` functions, transforms, text with decorations and
strokes, tables, floats, images (JPEG and PNG are embedded as their original bytes when possible) and SVG images
drawn as vector paths ([Fonts in PDF](fonts.md) covers text).
Structure for accessibility and the PDF/A and PDF/UA standards are described in
[Accessibility and archival](accessibility.md).

Some CSS has no PDF equivalent. A `blur()` or `drop-shadow()` `filter` fails the render with
`A PDF cannot draw filter: blur(2px)` (the message names the filter). `backdrop-filter`
is ignored.

## Differences from image output

**List markers** are drawn in PDF output only (paged and `viewport`), with `Lbl` structure elements; PNG,
JPEG, WebP and SVG output draw none. See [Known limitations](limitations.md).

**`text-overflow`** markers are drawn, but they are not text: extracting the text of the page (copy and
paste, search, `pdftotext`) gives the characters drawn before the marker, not the marker and not the
cut-off rest. Checked with poppler's `pdftotext`:

<!-- @example pdf-css-support#text-overflow -->
```js
const clipped = await pdf.render(
  `<p style="font-family: Inter; font-size: 20px; width: 200px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">
     A very long product name that does not fit
   </p>`,
  page,
);
// the page shows "A very long produc…"; the marker is drawn but is not text: extracting the text
// (pdftotext, copy and paste) gives "A very long product", not the "…" and not the cut-off rest
```

**`image-rendering`** has no effect on PDF output. A PDF image has no such setting, so `pixelated` and
`crisp-edges` give the same file as `auto`, and how an enlarged image is smoothed is up to the viewer
(in image output, `pixelated` scales with nearest-neighbour):

<!-- @example pdf-css-support#image-rendering -->
```js
const pixels = { width: 2, height: 2, data: new Uint8Array([255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255, 255, 0, 0, 255]) };
const scaled = (rendering) => pdf.render({
  type: "image", src: pixels, style: { width: 120, height: 120, imageRendering: rendering },
}, { viewport: { width: 120, height: 120 } });
const smooth = await scaled("auto");
const pixelated = await scaled("pixelated");
// the two files are byte for byte the same: a PDF image has no image-rendering setting
```

**Filters that blur** cannot be drawn: `blur()` and `drop-shadow()` in `filter` fail the render, where an
image render draws them:

<!-- @example pdf-css-support#blur-error -->
```js
let blurError;
try {
  await pdf.render(`<div style="filter: blur(2px); width: 50px; height: 50px; background: red"></div>`, page);
} catch (e) {
  blurError = e.message;
}
// A PDF cannot draw filter: blur(2px)
```

**Box shadow blur** is approximated with vector shapes (eight fainter spread bands around the shadow),
so a soft shadow looks slightly different from the PNG.
