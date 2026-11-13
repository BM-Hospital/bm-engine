# PDF golden differences (bm-engine vs takumi-pdf)

Developer notes on the fixtures of `node scripts/pdf-compare.mjs` that are not identical, and why.
The script renders the input of each of takumi-pdf's 89 golden fixtures
(`ref/takumi/takumi-pdf/tests/fixtures-generated/*.pdf`) with `bm-engine/pdf` and compares every
page operator by operator after replacing resource names and object numbers by what they point at.
The comparison rules were not changed for this work.

## Numbers

| Run | identical | close (numbers within 0.01) | differ | errors |
|:--|--:|--:|--:|--:|
| before (branch point of `pdf-bugs`) | 73 | 3 | 13 | 0 |
| after the fixes below | 80 | 2 | 7 | 0 |

Object layout is identical in all 89. Embedded font programs are byte-identical in 42 (the subsetter
does not write byte-identical subsets; this never changes a verdict, the comparison reads the fonts'
dictionaries, widths and CMaps separately).

## Which takumi the goldens come from

The published `takumi-pdf@0.20.0` package, run through `scripts/pdf-compare.mjs` in place of bm-engine,
reproduces the goldens with 83 identical, 3 close and 3 different fixtures, and its font programs are
identical in all 89:

- `box-shadows`, `text-decoration-shadow` and `color-glyph-text-shadow` are only close: the alpha of the
  shadow bands differs in the eighth digit.
- `inline-images` differs in its pixel data.
- `text-shadow-stroke` and `text-stroke-paint-order` differ in structure: 0.20.0 draws stroked text as
  `2 Tr` text, the goldens draw it as separate paths.

So the goldens were written by a takumi slightly newer than 0.20.0. bm-engine follows the goldens in all
six of these. `ref/takumi` is a single commit (33eed4a, `takumi-pdf-js` version 0.20.0) without tags, so
0.20.0 and HEAD cannot be compared in git. Every behaviour fixed below is the same in 0.20.0 and in the
goldens.

## Per fixture

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
- **bm bug, not fixed:** 2.
  - `color-glyph-text-shadow` (B): the contour start of the static `glyf` reader.
  - `stream-content-counters` (G): the trailing-space kern in the shared text engine.
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

## Remaining work

- **B:** a PDF-only start point for `glyf` contours that begin off-curve, following skrifa.
- **C:** in the paginator, grow a box that a page boundary slices by the gap between the truncated and
  the exact page height, then re-check the outline destinations of `report-*`.
- **F:** the right edge of a decoration or link run as `x0 + Σ advances`. `PositionedGlyph` carries no
  advance, so this needs the advance of each run's last glyph in the text layout of PDF builds.
- **G:** collapse the trailing space before shaping, or drop its kern, in PDF builds; then re-run the
  image suite.
- **Per-page widths (pdf-port):** done (src/pdf/paged.zig `laySegments`).

## Findings of the external validation run (pdf-validate)

| Item | Finding | Status |
|:--|:--|:--|
| A. Quadratic output and out of memory on long documents | The per-page `re` counts had two causes. First, a collapsed table's borders were painted in full on every page (I above). Second, every page walked the whole frame three times (once per page pass) and allocated its own tree order and table-part map, so time and memory grew with pages x document size. | Fixed: subtree extents are computed once per document and a page skips the subtrees that miss its window; the first page still walks everything, because the document-wide link, anchor and heading collections are made on it. Results on the stress document of `bench/pdf/corpus` (Inter, A4, table + image per page): <br>- native: 500 / 526 / 436 / 392 pages/s at 10 / 100 / 500 / 1000 pages <br>- wasm: 64 / 173 / 127 / 75 pages/s <br>- `re` per page equals takumi-pdf (47) <br>- engine memory plateaus over repeated renders, about 1.2 MiB per page, mostly the laid-out frame; page counter bands lay the document out up to three times. <br>Tests in `scripts/pdf-test.mjs`: a 70-row table's rectangles per page, a 500-page render, memory over three renders. |
| B. Invoice `.meta`: one `P` in bm-engine, two in takumi-pdf | takumi gives inline `<b>` / `<strong>` / `<em>` their own `Strong` / `Em` elements, and each of them ends the pending paragraph run (`build_node` → `flush_paragraph`). Two flex items `<b>Billed to</b>…` and `<b>Issued</b>…` therefore give two `P`s. bm-engine's render tree has no node for an undecorated inline element, so neither the `Strong` element nor the paragraph split appears. | Not fixed: needs inline-element structure elements in tags.zig. |
| C. PDF/UA-2 outline `/Dest` holding a structure element | takumi-pdf's goldens (`report-tagged-ua2`, identical in bm-engine) write the same thing. ISO 32000-2 §12.3.2.3 defines structure destinations for the `SD` entry of a go-to action; an outline item's `Dest` takes an explicit or named destination, so pdfcpu's complaint looks right. | Kept for byte parity with takumi-pdf; to report upstream. |
| D. Arabic `معٕا` vs `معٕ ا` in extracted text | Not investigated in this round (extraction spacing of a combining mark). | Open |
| E. `background-repeat: space / round` in image output; text-shadow differences between PDF and image | The image path was not touched (image suite 81 / 169 / 0). In PDF, `text-decoration-shadow` and `bitmap-glyph-text-shadow` are now identical to takumi-pdf's goldens. `color-glyph-text-shadow` differs only in path order (B above). | Image-side questions open |
| F. File-size outliers (`text-stroke-paint-order` 1.83×, `text-shadow-stroke` 1.34× vs takumi-pdf 0.20.0) | The goldens (a takumi newer than 0.20.0) draw stroked text as paths, while 0.20.0 uses `2 Tr` text. bm-engine follows the goldens, and its files are the goldens' size (15722 vs 15696 B, 113528 vs 115746 B). | Not a bug |
