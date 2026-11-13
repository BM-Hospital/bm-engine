# Differences from takumi-pdf

[English](differences-from-takumi.md) · [Tiếng Việt](../../vi/pdf/differences-from-takumi.md)

`bm-engine/pdf` is a port of [takumi-pdf](https://github.com/kane50613/takumi): the option names, defaults,
validation rules and most error messages are takumi-pdf's, and a document renders to the same page
content in most cases. This page lists what is different, then how the output was compared. The image
side has its own page: [Differences from takumi](../image/differences-from-takumi.md).

- [API and packaging](#api-and-packaging)
- [Known limitations](#known-limitations)
- [Compared with takumi-pdf's goldens](#compared-with-takumi-pdfs-goldens)

## API and packaging

- **Separate entry.** PDF output is only in `bm-engine/pdf`; `renderPdf` on any other build throws, also when
  `bm-engine` runs on the native addon ([Native and WebAssembly](native-and-wasm.md#what-the-other-profiles-do)).
  On Node.js `bm-engine/pdf` itself uses the native addon when it is installed and the wasm `pdf` profile
  otherwise.
- **No `needs` pass.** `prepare` fetches nothing and `@font-face` files are not downloaded: pass image bytes in
  `images` and fonts in `fonts` / `registerFont`.
- **Counters in generated content** (`counter(page)`, `target-counter()`) do not work, as in takumi; use
  `PageNumber`, `TotalPages` and `TargetPageNumber` ([Headers, footers and page counters](headers-footers.md)).

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
  property, `@page name`, `name:first`), `@page` inside `@media`, `@layer` and `@supports`, `!important`, and
  lengths in any unit with `calc()` and `var()`. Each page lays its content out at its own width, as in takumi.
  A page that starts in the middle of a table row or a flex line keeps the width of the page before it when its
  own differs. The custom properties the `cssVariables` option gives a whole HTML document reach the page rules
  in bm-engine, not in takumi. See [Pagination](pagination.md#page-rules).
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
  certification. See [Accessibility and archival](accessibility.md#how-far-the-checks-go).
- **Embedded font programs.** The subset fonts in the file are not always byte-identical to the ones
  takumi-pdf writes, although they draw the same glyphs.


## Compared with takumi-pdf's goldens

`node scripts/pdf-compare.mjs` renders the input of each of takumi-pdf's 89 golden fixtures
(`takumi-pdf/tests/fixtures-generated/*.pdf`) with `bm-engine/pdf`, parses both files and compares every
page operator by operator after replacing object numbers and resource names by what they point at (fonts,
images, shadings, soft masks, form XObjects). Fonts, the structure tree, annotations, outline, metadata and
attachments are compared separately. In the run made for this page:

| Result | Fixtures |
|:--|--:|
| identical page content | 73 |
| close: same operators, numbers within 0.01 | 4 |
| different | 12 |
| render errors | 0 |
| object layout identical | 89 |
| embedded font programs identical | 42 |
| structure tree identical | 88 |

The 12 differences, by fixture:

| Fixture | What differs |
|:--|:--|
| `text-shadow-stroke`, `text-decoration-shadow`, `color-glyph-text-shadow`, `text-stroke-paint-order`, `svg-background-image` | glyph outline coordinates differ in the third or fourth significant digit (outline precision) |
| `text-decoration-styles` | the width of a dash in a dashed text decoration |
| `bitmap-glyph-text-shadow` | the soft mask of a bitmap glyph's shadow |
| `report-links-outline`, `report-tagged-ua1`, `report-tagged-a2a` | tiny kerning adjustments and link rectangles (annotations) |
| `stream-content-counters` | the width of a page-counter placeholder |
| `named-pages` | the body page before the wide table also paints, outside its page clip, the table's first border pieces: takumi's page reaches into the next page's fragment, which bm-engine lays out at that page's width in another layout ([Named pages](pagination.md#named-pages)) |

The four close fixtures are `text-shadow-page-cut`, `content-page-counters`, `at-page-root-element` and
`at-page-first-left-right`.
The invoice fixtures, repeated table headers and footers, and the list fixtures are identical. Font
programs differ in the other fixtures because the subsetter does not write byte-identical subsets, although
they draw the same glyphs. These numbers are from one run at the time of writing and change with the build;
the script needs the takumi sources in `ref/takumi`.

When you run into a difference that matters, [Troubleshooting](../troubleshooting.md) lists the usual causes
of missing text and wrong layout; they apply to PDF in the same way.
