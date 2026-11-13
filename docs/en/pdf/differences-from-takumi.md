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
- **`prepare` fetches images, not fonts.** `prepare` downloads the remote images the document and its bands
  name and that `images` does not provide (with `images.fetch`, or the global `fetch`). It finds them by
  scanning the source in JavaScript, not with takumi-pdf's native `needs` pass. `@font-face` files are not
  downloaded: pass fonts in `fonts` / `registerFont`.
- **JSX.** A React element is accepted as a document and as a band. It is converted to HTML; components run
  once without a React dispatcher, so hooks other than plain reads do not work.
- **Counters in generated content.** CSS counters work in PDF output: `counter()`, `counters()`,
  `counter-reset`, `counter-increment`, `counter-set`, `counter(page)` and `target-counter()`. `PageNumber`,
  `TotalPages` and `TargetPageNumber` remain available ([Headers, footers and page
  counters](headers-footers.md)).
- **Option errors.** Messages are takumi-pdf's, with a `bm-engine: ` prefix. Where takumi-pdf's message is a
  serde error (`unknown variant ...`), bm-engine writes the same text for the cases listed in the [API
  reference](api.md#errors); for other wrongly typed values it rejects the input with its own wording.
- **Images.** PNG and JPEG are embedded as their original bytes where possible, so files are smaller and
  16-bit, gray, ICC-profiled and CMYK images keep their data. SVG images are drawn as vectors.

## Known limitations

These are the differences from takumi-pdf that are known at the time of writing, taken from
`docs/PDF_AUDIT.md`, the feature-by-feature audit against takumi-pdf 0.20.0.

**Fonts and text**

- **No bundled fallback font.** takumi-pdf falls back to Geist; bm-engine ships no font. With no font
  registered at all, a render with text fails (`No font is registered to draw ...`) unless
  `uncoveredText` is `"blank"`; with at least one, a character no font
  draws follows `uncoveredText`. Register a font ([Fonts in PDF](fonts.md)).
- **`unicode-bidi: bidi-override`** is parsed but has no effect. Ordinary bidirectional text, Arabic shaping,
  CJK and emoji work and extract the same text as takumi-pdf.
- **Form controls.** `input`, `textarea` and `select` boxes and borders are painted; the value, the
  placeholder and the lines of a `textarea` are not drawn, and the text of a `select` is offset.
- **SVG text** uses the first value of the `x`, `y`, `dx` and `dy` lists only; `rotate`, `textPath` and text
  decorations are not drawn. SVG-in-OpenType glyphs are drawn as their outline. COLR (v0 and v1) and bitmap
  (CBDT, sbix) glyphs are embedded.
- **Page CSS inside an inline `<svg>`** (a `<style>` in the `svg` element) is not applied.
- **Gradient interpolation spaces.** `in oklch`, `in oklab` and the like are sampled in the space asked for
  (CSS behaviour); takumi-pdf 0.20.0 writes sRGB stops and ignores the space, so the colours differ.
- **Embedded font programs.** The subset fonts in the file are not always byte-identical to the ones
  takumi-pdf writes (71 of 136 fixtures are), although they draw the same glyphs.

**CSS features that are not supported**

- **List markers.** PDF output paints them, in paged and in `viewport` renders, with `Lbl` structure elements;
  PNG, JPEG, WebP and SVG output draw none. Supported: takumi's counter styles for ordered lists, the symbols
  disc, circle, square and disclosure, `start`, `reversed`, `value`, and inside and outside placement. Not
  supported: `list-style-image` (the counter style is drawn instead), `::marker` rules, and markers of an item
  that starts with a flex, grid, table or image box (those items get no marker).
- **`content: url()`** draws nothing.
- **Not supported:** `offset-path` and relative colour syntax (`rgb(from ...)`).
- **Stacking order.** Positioned and `z-index`ed boxes are painted with their stacking context, in CSS painting
  order, as takumi does (including the layer of negative `z-index`). No difference is known in the fixtures
  compared with takumi-pdf, but the order is not proven identical for every document.

**Pages**

- **`@page`.** `size`, `margin`, `:first`, `:left` and `:right` work, and so do named pages (the `page`
  property, `@page name`, `name:first`), `@page` inside `@media`, `@layer` and `@supports`, `!important`,
  layers and specificity, and lengths in any unit, including `calc()`, viewport units and `var()`. Each page
  lays its content out at its own width, also when `:first`, `:left`, `:right` or a named page has another
  width, as in takumi. A page boundary inside a table row or a flex line across a width change keeps the
  previous width for the continued row or line. The custom properties the `cssVariables` option gives a
  whole HTML document reach the page rules in bm-engine, not in takumi. Page-margin boxes (`@top-center` ...)
  are parsed and skipped, as in takumi-pdf. See [Pagination](pagination.md#page-rules).
- **Breaking.** `break-before` / `break-after` with `left`, `right`, `recto` or `verso` break the page
  but do not insert a blank page to land on a left or right side. `column` is not a page break. Tailwind's
  `break-before-*`, `break-after-*` and `break-inside-*` utilities work as Tailwind defines them; takumi has
  none (an extension). `box-decoration-break: clone` works: each fragment of a box cut by a page keeps its
  border, padding and radii.
- **Tables.** Repeated `thead` / `tfoot`, row splitting and cells that span rows (`rowspan`) are handled
  across pages. Collapsed borders end each fragment with its own bottom border; small offsets remain for 4 px
  borders and repeated headers. Table captions across pages differ (takumi drops caption lines on page 1).
- **Floats.** Lines do not re-flow beside a float that moved to another page: bm-engine paginates one finished
  layout.
- **Rotated and skewed boxes cut by a page boundary** are painted whole in the page where they start; takumi
  slices them per fragment.
- **Flex and grid.** Flex rows across pages match takumi-pdf. In grid, an `align-items: end` item that breaks
  before its row differs, because bm-engine has no grid-row fragments.
- **List markers across pages.** The marker of an item split across pages stays on the item's first line
  (as in Chrome); takumi puts it on the first line of the last fragment. This is deliberate.
- **Long documents.** Time per page is flat (3.1 ms per page at 100 and at 500 pages on WebAssembly) and
  files are 0.81 to 0.87 times the size of takumi-pdf's. Memory is higher: at 500 pages the wasm engine
  holds about 260 MiB against 76 MiB for takumi-pdf, because bm-engine keeps the whole laid-out document
  until the file is written.

**Files**

- **PDF/A and PDF/UA are checked, and validated with veraPDF, but not certified.** The validation is a port of
  krilla's rules (fonts, document language and title, alternate text, outline, attachments, dates, and the
  string, name and nesting limits). veraPDF 1.28.2 reports all 45 bm-engine files compliant (PDF/A-2a, 2b,
  2u, 3a, 3b, 3u, 4, 4f and PDF/UA-1, PDF/UA-2), the same as for takumi-pdf's files. pdfcpu in strict mode
  reports 12 issues on the files of both engines (the PDF/A-3 `AFRelationship` key, which it flags as PDF 2.0
  only, and the structure destinations in PDF/UA-2 outline items); none is specific to bm-engine. qpdf,
  poppler, MuPDF and pdf.js read the files without complaint. None of this is a certification; see
  [Accessibility and archival](accessibility.md#how-far-the-checks-go).
- **Errors.** Huge sizes that takumi-pdf renders (a 750,000,000 pt page, a 100,000 px viewport) are rejected by
  bm-engine. A truncated font or a font without a `cmap` is rejected ; takumi accepts them.
  A NaN `margin` becomes `null` in JSON and so means the default margin.

## Compared with takumi-pdf's goldens

`node scripts/pdf-compare.mjs` renders the input of each of takumi-pdf's 136 golden fixtures
(`takumi-pdf/tests/fixtures-generated/*.pdf`) with `bm-engine/pdf`, parses both files and compares every
page operator by operator after replacing object numbers and resource names by what they point at (fonts,
images, shadings, soft masks, form XObjects). Fonts, the structure tree, annotations, outline, metadata and
attachments are compared separately. In the run made for this page:

| Result | Fixtures |
|:--|--:|
| identical page content | 118 |
| close: same operators, numbers within 0.01 | 7 |
| different | 11 |
| render errors | 0 |
| object layout identical | 134 |
| embedded font programs identical | 71 |

Seven of the goldens were written by a takumi newer than the published 0.20.0 package; bm-engine matches
all seven. The 18 fixtures that are not identical, by cause:

| Fixture | What differs |
|:--|:--|
| `text-stroke-paint-order` (close) | the order in which f32 advances are added: `50.000122` against `50.00006` |
| `content-page-counters`, `report-links-outline`, `report-tagged-ua1`, `report-tagged-a2a` (close) | takumi stacks pages at their exact height but breaks at the height truncated to 1/64 px; content after a box sliced by a page boundary, and the outline destination of a heading on page 2, are 0.005 to 0.0073 px off |
| `at-page-first-left-right`, `svg-filters-masks-and-patterns` (close) | numbers within 0.01 |
| `color-glyph-text-shadow` | one form `/BBox` (124.51 against 124.546), which takumi measures on tiny-skia's stroked outline |
| `named-pages` | the body page before the wide table also paints, outside its page clip, the table's first border pieces (invisible); bm-engine lays the wide page out as another frame at its own width |
| `inline-span-background-image` | the extents of an inline span's background: 3 gradient fragments against 2 |
| `inline-span-background-clip-text-nested`, `background-clip-text-reach` | the glyphs of a nested span in a `background-clip: text` mask sit 41/64 px apart (the visible text is the same); how far the clip-text mask reaches past the box |
| `svg-singular-gradient-transform` | `gradientTransform="scale(0)"`: a degenerate matrix written differently, nothing visible |
| `paged-transforms`, `paged-rotated-text` | rotated boxes cut by a page boundary (see [Pages](#known-limitations)) |
| `paged-monolithic-overflow`, `paged-clipped-overflow` | layout identical; marked-content regions and clip details at the page boundary |
| `list-marker-pagination` | deliberate: the marker of a split item stays on its first line |

The other 118 fixtures, including the invoice fixtures, repeated table headers and footers and the list
fixtures, are identical. Font programs differ in the fixtures where the subsetter does not write
byte-identical subsets, although they draw the same glyphs. These numbers are from one run at the time of
writing and change with the build; the script needs the takumi sources in `ref/takumi`. The per-fixture
analysis is in `docs/PDF_AUDIT.md` and `docs/PDF_GOLDEN_DIFFS.md`.

When you run into a difference that matters, [Troubleshooting](../troubleshooting.md) lists the usual causes
of missing text and wrong layout; they apply to PDF in the same way.
