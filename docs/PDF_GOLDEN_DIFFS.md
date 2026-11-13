# PDF golden differences (bm-engine vs takumi-pdf)

Developer notes on the fixtures of `node scripts/pdf-compare.mjs` that are not identical, and why.
The script renders the input of each of takumi-pdf's 136 golden fixtures
(`ref/takumi/takumi-pdf/tests/fixtures-generated/*.pdf`; 89 in `scripts/pdf-compare.mjs`, 47 more in
`scripts/pdf-compare-more.mjs`) with `bm-engine/pdf` and compares every page operator by operator after
replacing resource names and object numbers by what they point at. The comparison rules were not changed
for this work. The feature-by-feature view, with the cause of every remaining difference, is
`docs/PDF_AUDIT.md` (see its "Golden coverage map").

## Numbers

| Run | fixtures | identical | close (numbers within 0.01) | differ | errors |
|:--|--:|--:|--:|--:|--:|
| before the `pdf-bugs` work | 89 | 73 | 3 | 13 | 0 |
| after the `pdf-bugs` fixes | 89 | 80 | 2 | 7 | 0 |
| before the PDF audit (main `664fb3f`) | 136 | 105 | 2 | 29 | 0 |
| now | 136 | 118 | 7 | 11 | 0 |

Object layout is identical in 134 of 136. Embedded font programs are byte-identical in 71 (the subsetter
does not write byte-identical subsets; this never changes a verdict, the comparison reads the fonts'
dictionaries, widths and CMaps separately).

## Which takumi the goldens come from

The published `takumi-pdf@0.20.0` package, run through `scripts/pdf-compare.mjs` in place of bm-engine
(measured on the first 89 fixtures), reproduces the goldens with 83 identical, 3 close and 3 different
fixtures, and its font programs are identical in all 89:

- `box-shadows`, `text-decoration-shadow` and `color-glyph-text-shadow` are only close: the alpha of the
  shadow bands differs in the eighth digit.
- `inline-images` differs in its pixel data.
- `text-shadow-stroke` and `text-stroke-paint-order` differ in structure: 0.20.0 draws stroked text as
  `2 Tr` text, the goldens draw it as separate paths.

So the goldens were written by a takumi slightly newer than 0.20.0. bm-engine follows the goldens in all
six of these. Seven of the 136 fixtures exist only in that newer source tree
(`avoid-break-out-of-flow-overflow`, `img-without-source-past-page`, `flex-item-margin-past-page`,
`flex-item-child-break-after`, `flex-item-table-row-break-after`, `floated-flex-item-break-after`,
`break-after-with-running-absolute`); bm-engine matches all seven. `ref/takumi` is a single commit (33eed4a, `takumi-pdf-js` version 0.20.0) without tags, so
0.20.0 and HEAD cannot be compared in git. Every behaviour fixed below is the same in 0.20.0 and in the
goldens.

## Per fixture (first round, 89 fixtures)

The table is the record of the first round. The "After" column is the state at the end of that round; the
current state of every fixture that is still not identical is in [Current state](#current-state).

Categories:

- **bm bug**: bm-engine computes something differently from takumi-pdf.
- **missing feature**: belongs to the `pdf-port` worktree.
- **legitimate**: float accumulation order, the same drawing.

| Fixture | Before | Category | Cause | After |
|:--|:--|:--|:--|:--|
| `svg-background-image` | differ | bm bug | A. The outline of a variable-font glyph (the `background-clip: text` clip path) was drawn with unrounded gvar deltas; skrifa, which krilla uses, rounds an unscaled outline's points to whole font units (at most 0.0136 px off). | identical |
| `text-decoration-shadow` | differ | bm bug | A, plus the bounding boxes of the shadow forms, which are derived from those outlines. | identical |
| `text-shadow-page-cut` | close | bm bug | A (at most 0.0078 px). | identical |
| `text-shadow-stroke` | differ | bm bug | A, and E: `background-clip: text` with a transparent `-webkit-text-stroke` dropped the stroke. takumi strokes the background with the stroke's width whatever its colour (`background_stroke`), so 10 operators per glyph were missing. | identical |
| `text-stroke-paint-order` | differ | bm bug, then legitimate | A. What is left is J: TJ adjustments such as `50.000122` vs `50.00006`, the order in which f32 advances are added. | close |
| `color-glyph-text-shadow` | differ | bm bug, not fixed | B. When a TrueType contour's first point is off-curve and its last is on-curve, skrifa starts the contour at the last point; bm-engine's static `glyf` reader (`src/font/ttf.zig` `simpleOutline`, shared with the raster and SVG paths) starts at the next on-curve point. The shape is the same, but the path operators come out rotated. Some implied midpoints of the Twemoji layers also land 1/128 px lower in takumi; that is not explained yet. A fix needs a PDF-only variant of the streaming contour reader. | differ |
| `bitmap-glyph-text-shadow` | differ | bm bug | H. The soft mask of a blurred bitmap glyph's shadow: takumi samples the bitmap nearest-neighbour at the device size (`write_alpha_mask`) and blurs it as RGBA (`blur_rgba`); bm-engine resampled it with the raster image filter and blurred it as an A8 mask (1701 of 6720 mask pixels off by up to 4). | identical |
| `text-decoration-styles` | differ | bm bug | D. Skip-ink cuts: takumi computes them from the glyph outlines (`intercept.rs`: curves flattened in 16 steps, nonzero spans on 9 scanlines across the band inset by 0.5 px, dilated by `min(thickness, 13)`) and snaps each cut to a whole device pixel of its CSS px device (`device_pixel_x`). bm-engine scanned the rasterised glyph masks column by column. | identical |
| `report-links-outline` | differ | bm bug, partly fixed | D fixed the underline pieces. Two causes remain. F: an underline and a link rectangle end at the next glyph's snapped x in bm-engine (`render.RunIter`, `x1`), while takumi uses the run's unsnapped sum of advances; the result is 0.013 px wider. C (block direction): the outline destination of a heading on page 2 is 0.005 pt off. | differ |
| `report-tagged-ua1` | differ | bm bug, partly fixed | Same as `report-links-outline`. | differ |
| `report-tagged-a2a` | differ | bm bug, partly fixed | Same as `report-links-outline`. | differ |
| `content-page-counters` | close | bm bug, partly fixed | C. takumi breaks the content at the page area truncated to 1/64 px (`LayoutUnit::from_float` of `fragmentainer_block_size`), but stacks the pages at their exact height, so content after a box that a page boundary slices sits `k × (exact − truncated)` lower on page k (0.0073 px on A4). bm-engine now breaks at the truncated height. It does not yet grow a box that is sliced across the boundary by that gap, so the text after the 1100 px paragraph is still 0.0073 px higher. | close |
| `at-page-root-element` | close | bm bug | C (inline direction). takumi lays the root out in the page area's width truncated to 1/64 px (479.359375 for 479.3701); bm-engine rounded it to 479.375, which moved right-aligned and RTL lines by 1/64 px. | identical |
| `stream-content-counters` | differ | bm bug, not fixed | G. A flex item `'r '`: takumi lays the line out as if the collapsible trailing space was never shaped (4.65625 px wide), while bm-engine drops the hung space but keeps the r+space kern on the `r` (4.375 px). This is in the text engine that the image path shares, so a fix has to be gated to PDF output or checked against the image suite. | differ |
| `at-page-first-left-right` | differ | missing feature | Pages of different widths: the `:first` landscape A5 page and the `:left` / `:right` width changes were dropped, because bm-engine laid the content out once, at one width. Now each run of pages of one width is laid out again from where the run before stopped (src/pdf/paged.zig `laySegments`, `fragment.Options.start`), in takumi's block coordinates; a footer band of another page width is laid out at that width. | close |
| `named-pages` | differ | missing feature, plus a bm bug | The same per-page-width limitation, now ported (see above). The bug was I: a collapsed table's borders were painted in full on every page and in every page pass (outside the page clip, so nothing was visible). The page content was 19444 operators against takumi's 3356. Each page now paints only the borders it shows. Left: page 2 (body width) in takumi also paints, outside its clip, the first border pieces of the wide table that starts page 3 (its page scene reaches the next page's fragment); bm-engine's page 3 is another frame, laid out at the landscape width, which page 2's passes do not visit (136 invisible operators). | differ (3220 / 3356 ops, structure tree same) |

### Summary by category

- **bm bug, fixed to identical:** 7. These are `svg-background-image`, `text-decoration-shadow`,
  `text-shadow-page-cut`, `text-shadow-stroke`, `bitmap-glyph-text-shadow`, `text-decoration-styles`
  and `at-page-root-element`.
- **bm bug, fixed to close (the rest is legitimate float order J):** 1, `text-stroke-paint-order`.
- **bm bug, partly fixed:**
  - 3 fixtures (`report-links-outline`, `report-tagged-ua1`, `report-tagged-a2a`) still differ because of F and C.
  - 1 fixture (`content-page-counters`) is still close because of C.
- **bm bug, not fixed at the end of the first round:** 2, both resolved since (see [Current state](#current-state)).
  - `color-glyph-text-shadow` (B): the contour start of the static `glyf` reader; only a form `/BBox` differs now.
  - `stream-content-counters` (G): the trailing-space kern in the shared text engine; identical now.
- **missing feature (pdf-port):** ported: `at-page-first-left-right` is close, `named-pages` differs only by
  invisible clipped border pieces (see the table). The border bloat of `named-pages` was a bm bug and is fixed.

## Where the fixes are

| Cause | Change |
|:--|:--|
| A | `src/font/ttf.zig` `PathOut.round_points` and `Font.outlineWith`; `src/font/variations.zig` `simpleVar` rounds the varied points when set; `src/pdf/type3.zig` `glyphPath` sets it. PDF builds only, so the raster and SVG paths keep exact points. |
| C | `src/layout/fragment.zig` `window` (breaks at the truncated height, pages stacked at the exact one) and `src/render.zig` `Frame.setPaged` (page area width truncated to 1/64 px). |
| D | `src/pdf/emit_text.zig` `skipInk`, `intercepts` and `mergeSpans` (a port of takumi's `intercept.rs` plus `device_pixel_x`); `src/pdf/text.zig` `glyphOutlinePx`. |
| E | `src/pdf/emit_text.zig` `glyphPass`: a transparent stroke keeps its width. |
| H | `src/pdf/text.zig` `blurredBitmapSilhouette`. |
| I | `src/pdf/emit.zig` `Emitter.pieceShows`, used by `src/pdf/emit_table.zig` `paintCollapsed`. |

## Current state

All 136 goldens are compared: 118 identical, 7 close, 11 differ, 0 errors. Object layout is identical in
134, embedded font programs byte-identical in 71. Of the open items of the first round, B (contour start of
the static `glyf` reader: contours now start where FreeType and skrifa start them), F (the right edge of a
decoration or link run is the run's origin plus its exact advance) and G (`stream-content-counters`) no
longer produce differences; per-page widths are ported (src/pdf/paged.zig `laySegments`). C (the 1/64 px
truncation of the page height) is still the cause of the close fixtures below. The 18 fixtures that are
not identical:

| Fixture | Result | Cause |
|:--|:--|:--|
| `text-stroke-paint-order` | close | f32 sums of advances added in another order (`50.000122` vs `50.00006`) |
| `content-page-counters` | close | takumi stacks pages at the exact height but breaks at the height truncated to 1/64 px; content after a sliced box is 0.0073 px higher in bm-engine |
| `report-links-outline`, `report-tagged-ua1`, `report-tagged-a2a` | close | outline destination of a heading on page 2 is 0.005 pt off (same cause as `content-page-counters`); link and decoration edges are identical |
| `at-page-first-left-right` | close | pages of different widths are laid out at their own width; numbers within 0.01 |
| `svg-filters-masks-and-patterns` | close | numbers within 0.01 |
| `color-glyph-text-shadow` | differ | only a form `/BBox` (124.51 vs 124.546): takumi measures it on tiny-skia's stroked outline |
| `named-pages` | differ | 3220 / 3356 ops: takumi's page 2 also paints the first border pieces of the wide table that starts page 3, outside its clip (invisible); in bm-engine page 3 is another frame laid out at its own width |
| `inline-span-background-image` | differ | inline-span background extents: 3 gradient fragments vs 2 |
| `inline-span-background-clip-text-nested` | differ | glyphs of a nested span inside the outer span's text mask sit 41/64 px further left in takumi; the visible text is identical |
| `background-clip-text-reach` | differ | 1723 / 1102 ops: how far the clip-text mask reaches past the box |
| `svg-singular-gradient-transform` | differ | `gradientTransform="scale(0)"`: a degenerate pattern matrix written differently, nothing visible |
| `paged-transforms`, `paged-rotated-text` | differ | takumi slices a rotated box cut by a page boundary per fragment; bm-engine paints it whole in its first page's pass |
| `paged-monolithic-overflow`, `paged-clipped-overflow` | differ | layout identical; marked-content regions and clip details at the page boundary |
| `list-marker-pagination` | differ | deliberate: the marker of a split item stays on its first line (Chrome); takumi moves it to the last fragment |

Still open on the layout side: **C**, growing a box that a page boundary slices by the gap between the
truncated and the exact page height; rotated boxes sliced per page fragment (needs a layout per fragment).

## Findings of the external validation run (pdf-validate)

| Item | Finding | Status |
|:--|:--|:--|
| A. Quadratic output and out of memory on long documents | The per-page `re` counts had two causes. First, a collapsed table's borders were painted in full on every page (I above). Second, every page walked the whole frame three times (once per page pass) and allocated its own tree order and table-part map, so time and memory grew with pages x document size. | Fixed (linear time): subtree extents are computed once per document and a page skips the subtrees that miss its window; the first page still walks everything, because the document-wide link, anchor and heading collections are made on it. Results on the stress document of `bench/pdf/corpus` (Inter, A4, table + image per page): <br>- native: 500 / 526 / 436 / 392 pages/s at 10 / 100 / 500 / 1000 pages <br>- wasm: 64 / 173 / 127 / 75 pages/s <br>- `re` per page equals takumi-pdf (47) <br>- engine memory plateaus over repeated renders, about 1.2 MiB per page, mostly the laid-out frame; page counter bands lay the document out up to three times. <br>Tests in `scripts/pdf-test.mjs`: a 70-row table's rectangles per page, a 500-page render, memory over three renders. <br>Later, on wasm the time per page still grew with the page count (500 pages: 1.94x the time per page of 100): `memory.grow` once per 256 KiB arena chunk (V8 moves the memory) and page lookups that walked every page. Fixed: `src/pages.zig` grows memory geometrically, `Pages.pageAt` and the paginator's `pageAt` binary-search, `textRegions` scans only the pages a box reaches. `scripts/pdf-scaling.mjs` (100 vs 500 pages of the stress document): wasm 4.9 / 4.2 ms per page, native 2.3 / 3.0 ms, takumi-pdf 0.20.0 14.8 / 14.2 ms; bytes per page 3782 / 3630 (takumi-pdf 4365 / 4476); engine memory at 500 pages 623 MiB (wasm) / 633 MiB (native) vs takumi-pdf 76 MiB. <br>Final state (PDF audit): time per page is flat, 3.1 ms/page at both 100 and 500 pages on wasm; files are 0.81-0.87x takumi-pdf's; engine memory at 500 pages is 260 MiB on wasm vs 76 MiB for takumi-pdf (layout passes and page drawing are freed; the laid-out document itself remains until the file is written). |
| B. Invoice `.meta`: one `P` in bm-engine, two in takumi-pdf | takumi walks the inline `<b>` / `<strong>` / `<em>` / `<i>` / `<code>` of a box's text as render nodes of their own: one ends the pending paragraph run (`build_node` → `flush_paragraph`) and, holding no content of its own (its text is recorded on the box laying it out), adds no element. Two flex items `<b>Billed to</b>…` and `<b>Issued</b>…` therefore give two `P`s. | Fixed: `src/pdf/tags.zig` `hasInlineRoleText` flushes the run after a box's own content when its inline content holds such an element. |
| C. PDF/UA-2 outline `/Dest` holding a structure element | takumi-pdf's goldens (`report-tagged-ua2`, identical in bm-engine) and the published takumi-pdf 0.20.0 (checked on a UA-2 document with an outline: every item's `Dest` starts with a structure element, in both engines) write the same thing. ISO 32000-2 §12.3.2.3 defines structure destinations for the `SD` entry of a go-to action; an outline item's `Dest` takes an explicit or named destination, so pdfcpu's complaint looks right. | Parity with takumi-pdf 0.20.0 confirmed (both engines write the structure element); kept for byte parity; to report upstream. |
| D. Arabic `معٕا` vs `معٕ ا` in extracted text | Not reproducible: pdftotext and pdf.js extract identical text from the files of bm-engine and takumi-pdf. The separate U+0655 item comes from the font's decomposition of the combining mark, not from either engine. | Not a bm-engine bug |
| E. `background-repeat: space / round` in image output; text-shadow differences between PDF and image | The image path was not touched (image suite 81 / 169 / 0). In PDF, `text-decoration-shadow` and `bitmap-glyph-text-shadow` are now identical to takumi-pdf's goldens. `color-glyph-text-shadow` differs only in path order (B above). | Image-side questions open |
| F. File-size outliers (`text-stroke-paint-order` 1.83×, `text-shadow-stroke` 1.34× vs takumi-pdf 0.20.0) | The goldens (a takumi newer than 0.20.0) draw stroked text as paths, while 0.20.0 uses `2 Tr` text. bm-engine follows the goldens, and its files are the goldens' size (15722 vs 15696 B, 113528 vs 115746 B). | Not a bug |
