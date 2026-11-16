# Takumi PDF port checkpoint — 2026-11-14

## 2026-11-14 image sizing follow-up

Auto-sized replaced images at the layout root now retain their intrinsic dimensions instead of inheriting the initial containing block width. The pinned `images.root-img.png`, `images.root-img.png-margin`, and `images.root-img.svg` probes pass on native and WASM. The PDF Zig suite passes 676/676 and the public PDF API suite passes 393/393 on native. The latest full strict audit is 1,501/1,567 on both native and WASM (66 failed probes, 121 failed assertions, 0 unverified). The latest audit also drops raw compressed-length comparisons for embedded attachments because Deflate output is implementation-dependent; decoded payload and stream parameters still match. The audit remains red, so this is not Takumi parity completion and no fresh runtime benchmark is claimed.

## Current verified checkpoint

The painted table-cell continuation fix now matches Takumi's page-root reach
behavior: trailing border/padding from a completed cell paints into the next
page window while retaining the empty cell region. The strict
`pagination.continuation` audit passes 17/17 probes, including painted,
padded and unequal-cell cases. This is a focused parity result, not completion
of the overall PDF port.

Latest checks on the current source: PDF-enabled Zig suite 675/675; focused
float Zig tests 14/14; public PDF API suite 393/393 on both native and WASM.
Strict audit on each backend: float reflow 24/24, float suite 42/42, grid
48/48, continuation 17/17, and the mapped source float fit/split probe 22/22.
The 161-document
validation run has 153/161 semantic matches, no bm-only validator errors, and
45/45 veraPDF-compliant documents per engine. Eight semantic differences and
eight visual consensus differences remain; see the generated validation and
visual reports under `bench/out/pdf`.

The full benchmark has run against freshly rebuilt native and WASM artifacts;
it predates the latest inline-float anchor correction and will be rerun after
the remaining parity work. Warm render geomean was 0.91 ms native and 1.41 ms WASM, versus
2.66 ms for Takumi (0.34x and 0.53x Takumi's runtime). For 500-page documents
the measured times were 967 ms native, 1,655 ms WASM and 5,046 ms Takumi.
These are throughput measurements only: they do not show
bounded live-layout memory, which remains unimplemented. Benchmark details and
machine-noise caveats are in [the PDF benchmark report](../bench/out/pdf/PDF.md).

Overall parity and source-test mapping remain incomplete. The inventory still
tracks 272 Rust and 69 JavaScript test declarations, with unmapped cases and
architectural streaming/memory invariants open.

Reference: `ff9a5d411310c8cdd1ac76a4f106c123d309e0a4`. All 1,909 canonical test/assets/license files are vendored in `tests/upstream/takumi` (39.93 MiB), with SHA-256 checks in the manifest. Full source in `ref/takumi` is used to build the oracle; public PDF adapters read the vendored corpus.

## Reference and coverage

The pinned Rust oracle passed 272/272 upstream tests and regenerated 136 goldens. This verifies the reference, not bm coverage. The source-built WASM oracle also verifies revision and binary/wrapper hashes before loading.

`pdf-coverage.mjs` inventories 272 Rust and 69 JavaScript test declarations. Rust inventory: 120 golden adapters, 115 pending adapters and 37 internal cases requiring review. JavaScript case-level mappings remain pending. No executed feature-coverage percentage is claimed; coverage `--strict` rejects this state.

## Implemented changes with focused checks

- Per-fragment transformed decorations, visible text ownership under clipping, and inline outline paint reach in neighbouring marked-content regions.
- Inline slice background image strips; kerning and ligatures across paint-only span boundaries; background-clip text reach and positions.
- Input value sanitization/password masking, textarea sizing/lines, host/editor content ownership and empty inline contexts beside blocks.
- CSS bidi scopes; ellipsis color/order; CSS tab-size; generated hyphen Unicode mapping. Independent pdf.js extraction/raster checks cover tabs, pre-wrap and soft-hyphen.
- URL marker images and mixed generated text/images with missing-image fallback.
- SVG position/rotation lists, textPath with bounded adaptive arc-length measurement, text decorations and page cascade into inline SVG.
- Pinned-reference relative color syntax and path/ray/basic-shape motion paths.
- Non-solid multiline outlines with radii, 3D styles, opacity, transform and clip.
- Engine resource-needs pass and preparation of required image/font resources: unicodeRange subsets, @font-face source fallback, cancellation, cache/dedup, failed fetch retry and fonts discovered from downloaded SVG text.
- Seven preexisting PNG/WebP codec failures fixed by preserving unsigned channel bits instead of saturating signed SIMD conversions.

Focused probes do not certify arbitrary nested page/clip/link combinations. SVG resource-needs now reads cascaded families/weights, follows bounded `use` references and omits unused definitions and hidden text. Generated gradients and image paragraph ownership have focused reference checks.

## Continuation and resolved-glyph progress

Parallel table-cell resume tokens, glyph cuts and preserved row space pass
text/unequal-cell/link probes across alternating page widths. Independent
rowspan continuations preserve glyph cuts, assigned row heights and settled
row positions in the covered fixed-width cases. A new width-change regression
now exposes an uncovered case: after page 2, BM emits six rowspan text lines
where Takumi emits three, and link rectangles diverge. The strict pinned-oracle
probe is `pagination.continuation.rowspan-width-reflow`; keep it failing until
the resume token preserves both the spanning cell's glyph cursor and its
vertical position within the current fragment. A glyph-cursor-only attempt did
not change the output and was discarded. Painted-cell
overflow was a failure at this historical checkpoint; it is fixed in the
current 17/17 continuation result at the top of this document. Aligned grid continuation and flex/grid regressions
passed 9/9 source probes. Full Zig at this earlier checkpoint passed 668/668;
after resolved-glyph changes it passed 669/669, exit 0.

Resolved glyf outlines quantize encoded points and implied midpoints using
FreeType's signed 26.6 arithmetic. COLR shadows and SVG use this path. The
shadow/SVG group passes 123/123 source probes. Golden comparison is now 123
IDENTICAL, 10 CLOSE, 3 DIFFER, 0 errors, with structure/parent tree 136/136.
The color-shadow CLOSE result uses a fixture-specific gate with extraction and
six viewer checks, described in [PDF_GOLDEN_DIFFS.md](PDF_GOLDEN_DIFFS.md).
Mutation gate tests pass 5/5.

Newer checkpoints: full Zig after generated-image changes passed 671/671 (exit
0); this predates the subsequent SVG-needs, character-variant and float-reflow
changes. API with mandatory Poppler verification passed 393/393 after SVG-needs.
The geometry gate now rejects absent/malformed extraction and accepts Poppler's
specific `no word list` warning only when real page elements are present. Gate
regressions pass 6/6.

A subsequent full Zig run passed 673/673 (exit 0), including SVG-needs,
text variants and uniform/variable-height whole-float reflow. This run predates
the later float-placement carry between width segments and conic-stop changes;
those need their own final full-suite checkpoint. Native and optimized WASM API
checks both passed 393/393 at the 673-test source checkpoint.

Generated URL content, gradient content and generated-image structure ownership
match the pinned source. Full-width/full-size-kana transforms compose with case
mapping, preserve ideographic spaces only for preserved whitespace and reject
duplicate keywords. A focused reference run covering these changes plus aligned
grid/flex regressions passed 32/32; its word geometry was verified with Poppler.

Whole floats deferred to another page feed their placement back into BFC
exclusion layout, then recompute line wrapping. Split floats now also preserve
the extra exclusion extent introduced by a page break and carry their resume
point across a page-width run. The strict pinned-reference float probes pass
42/42 (`pagination.float`) and 24/24 (`pagination.float.reflow-contexts`),
including nested BFC, RTL, variable page dimensions, long prefixes and a split
float crossing a width change. A new adapter ports the upstream
`a_float_breaks_only_when_it_does_not_fit_its_page` assertions: 65px stays
whole and 120px splits 75px + 45px. Its 22 assertions pass on native and WASM,
including widows/orphans, RTL, nested `flow-root` and `clear:both`. The full Zig
run verifies all 138 `oracle_float.json` cases in standard and exact-LayoutUnit
modes. Broader source-case mapping remains open.

Resumed paragraphs now query float exclusions at their fragment origin, and
following blocks retain the fragment offset for clearance. When a text break
moves later lines, an inline float moves only if its anchor starts after the
break; a tall float anchored before the cut keeps its independent parallel-flow
position. The pinned source regression and its clear/RTL/nested/widow-orphan
variants pass on both backends.
The earlier 14/15 result was superseded by the current 17/17 strict continuation
probe result documented above.
Repeating conic gradients now preserve the source's f32 percentage
round trip (30deg resolves to 30.000004deg), including fractional-turn stops.
All eight conic source probes and the 11-test native conic regression pass.

Painted counter ownership now includes transforms while its flow edge excludes
the box's own transform, matching pinned `Interactive::BoxExtent`. All 17 counter
probes pass, including nested/backward transforms and transformed targets. The
native Zig regression for this rule passes. Generated gradient content is
covered by the newer focused checkpoints above.

The full benchmark and validation reports were refreshed on 2026-11-14. The
complete parity plan remains unfinished.

## Baseline before continuation changes

| Check | Result |
|:--|:--|
| Full Zig (PDF enabled), current | 675 passed, 0 failed; exit 0 |
| Golden inputs | 136/136 rendered, 0 errors |
| Page content | 123 IDENTICAL, 9 CLOSE, 4 DIFFER |
| Structure / parent tree | 136 same |
| Annotations | 132 same, 1 close, 3 different |
| Public PDF API, current | 393 passed, 0 failed |
| Focused form/outline/viewer probes | 5 passed, 0 failed, 0 unverified |
| Native backend | Rebuilt; API 389/389, focused probes 73/73 |
| External validation (161 documents) | Native/WASM identity 161/161; semantic match 153/161 |
| veraPDF | 45/45 compliant per engine; no bm-only validator issues |

Remaining page-content differences: `color-glyph-text-shadow`, `named-pages`, `paged-monolithic-overflow`, `list-marker-pagination`. Named pages previously matched raster pixels despite operator differences; monolithic overflow now matches structure/parent mappings and differs in the order of an empty region within the same paragraph. Split-list marker placement is an intentional difference. No broad exception makes these gates pass.

The selected validator run uses qpdf 12.4.2, pdfcpu 0.16.4, Poppler 26.09.0, veraPDF 1.28.2, pdf.js 6.5.438 and MuPDF 1.28.6, with the pinned source-built reference. Six pdfcpu issues per bm backend are shared with that reference. The `bm-only` gate passed with real exit 0; the stronger `all` gate is not claimed. Reports: `bench/out/pdf/validation.json` and `VALIDATION.md`.

The broad source-reference run has 1,516 probes: 1,442 pass, 74 fail, 0 unverified. These failures include intentional API/CSS policy differences as well as outstanding parity cases; they have not all been classified into narrow expected exceptions. A clean API suite or successful rendering of 136 inputs is not a clean parity gate.

## Architectural work still open

Plan tasks 16–21 remain incomplete: table/flex/grid tree continuations across width changes, float reflow after page breaks, emission before full layout ends, metadata/counter convergence around released pages, and bounded live-layout memory. The final document layout is still retained. See [PDF_FRAGMENT_DESIGN.md](PDF_FRAGMENT_DESIGN.md).

Task 22 is audited N/A for parity: Takumi's default `SerializeSettings.render_svg_glyph_fn` returns None (`takumi-pdf/src/krilla/serialize.rs:156`). Public probe `fonts.svg-opentype-outline-fallback` uses a valid font whose SVG table paints a conspicuous rectangle; both engines instead emit outline fallback. SVG glyph paint would be an extension.

## Reproduce

```powershell
node scripts/fetch-takumi-tests.mjs
node scripts/pdf-coverage.mjs --check
node scripts/build-takumi-pdf-oracle.mjs --all-tests
node scripts/build-takumi-pdf-wasm.mjs
node scripts/build.mjs --profile=pdf
$env:BM_RENDER_BACKEND = 'wasm'
$env:TAKUMI_PDF_REF_ENTRY = (Resolve-Path bench/out/pdf-oracle/node.mjs).Path
node scripts/pdf-compare.mjs --strict --golden-dir=bench/out/pdf-oracle/fixtures-generated
node scripts/pdf-audit/run.mjs --strict
node scripts/pdf-test.mjs --no-build
zig build test -Dpdf=true -j1 --summary all
```

Strict full-parity and source-coverage gates remain incomplete. The requested
benchmark has run; its results do not imply settled-page emission or bounded
live-layout memory. See the current checkpoint above and the generated reports.

## 2026-11-14 continuation-width regression checkpoint

The `pagination.continuation.rowspan-width-reflow` mismatch was caused by a page-start token whose main-flow node was `no_node` while its `side_flows` contained the continuing rowspan paragraph. Segment discovery skipped that token and held the old wide frame across the width boundary. `laySegments` now accepts side-flow-only starts as continuation boundaries. The regression passes 5/5 assertions on native and optimized WASM; the full `pagination.continuation` group passes 18/18 on both backends.

The PDF Zig suite passes 676/676. Public PDF API checks pass 393/393 on native, with Poppler text validation enabled. After the latest changes, native and WASM strict audits match: 1,501/1,567 probes pass, 66 probes fail (121 assertions), and 0 are unverified. Remaining failures cluster in API policy/diagnostic differences, font fallback and malformed-font cases, paint serialization/geometry, pagination edge cases (including monolithic boxes, table captions/borders and positioned content), annotations and paged tagging. Several observed differences are intentional behavior advantages rather than missing support: BM applies `cssVariables` and Tailwind break utilities in cases where Takumi ignores them; BM also intentionally ships no default font. The 66 failed probes still mix such policy and serialization cases with genuine rendering, font, link and tagging mismatches and need case-by-case classification. The upstream source map currently has 121/272 Rust test declarations mapped to an adapter or verified case, 151 awaiting adapter/review, and 0/69 JavaScript test declarations mapped and verified. This map measures test traceability, not feature support.

The latest fixes also reject non-finite JS margins before JSON serialization erases them and preserve complete PDF error diagnostics through the native N-API boundary. `page.margin.nan` passes 6/6 on both backends; three JPEG error probes that previously failed only on native now pass there and match WASM.

The 66 remaining failing probe IDs are grouped as follows; a failed probe can contain several assertions:

| Probe prefix | Failing probes | Main unresolved areas |
|:--|--:|:--|
| `api` | 5 | Invalid-input handling, font option behavior, and source conversion differences |
| `bands` | 1 | CSS-variable geometry in running headers/footers |
| `paint` | 25 | Gradient representation, clip/mask/overflow, transforms, filters and generated paint |
| `fonts` | 4 | Font container/subset shape, unicode-range fallback, malformed inputs |
| `images` | 1 | SVG as a list-style image |
| `links` | 3 | Padded inline rectangles, repeated table links and paged outlines |
| `page` | 8 | Invalid option types, non-finite explicit dimensions and `@page` values |
| `pagination` | 11 | Tailwind break utilities, monolithic overflow, decoration fragments, table and positioned content |
| `tagging` | 3 | Structure/parent-tree order across repeated headers and fragmented figures |
| `text` | 5 | Stroke paint order, background clipping and font coverage edge cases |

These are parity probe failures, not a count of unsupported APIs. For example, the inline-link padding and Tailwind break cases are intentional behavior differences documented by their probes; several other failures are PDF object serialization differences. Rendering, link target/rectangle behavior and tagged structure mismatches remain to be individually classified or fixed.

Correctness parity is still not green, so no new runtime benchmark was run. The 500-page and memory plateau checks in the public API suite are regression tests, not a substitute for the requested benchmark gate.

## 2026-11-15 focused PDF rendering fixes

CSS `filter:url(...)` references are treated as identity operations when SVG filter rasterization is unavailable; supported functions after the reference still apply. Text paint-order resolution ignores the markers phase, so `paint-order: markers stroke` draws the glyph stroke before its fill. The URL-filter parser regression and paint-order style tests pass; the `paint.filter` and `text.stroke` source-reference groups pass 45/45 on native and WASM.

The fresh full strict audit against pinned Takumi source `ff9a5d4` matches across backends: 1,505/1,568 probes pass, 63 probes (115 assertions) fail, and 0 are unverified. The remaining failures mix product-policy differences, serialization differences, and possible rendering, font, annotation, and tagging defects. They still require case-level triage; this checkpoint does not claim PDF completion or final benchmark readiness.

## 2026-11-15 full output validation and benchmark

Fresh `node bench/pdf/validate.mjs --gate=bm-only --jobs=4`: all 161 documents rendered on bm-native, bm-wasm, and takumi-pdf with 0 render errors. bm-native == bm-wasm byte-for-byte 161/161; sync == async 161/161. No bm-only validator issue; the only 12 strict pdfcpu errors are shared by both engines. veraPDF 1.28.2 passes every claimed profile: 45/45 for each backend. PDF API tests pass 393/393; the PDF Zig suite passes 676/676 (6 min, 1 GiB peak).

Full `node bench/pdf/bench.mjs` ran all stages on 159 common documents, three interleaved speed passes. Warm geomean: bm-native async 1.77 ms vs Takumi 5.68 ms (0.31x time; faster on 159/159); bm-wasm async 2.77 ms (0.51x; faster on 155/159). Scaling 1/10/100/500 pages: bm-native 4/27/314/2067 ms, bm-wasm 15.6/74.6/545/3525 ms, Takumi 45.4/230/2250/12348 ms. The generated benchmark report records CPU load and per-stage spread; see `bench/out/pdf/PDF.md` and the benchmark tables in the docs.

The source strict audit still has 63/1,568 probes (115 assertions) that differ from Takumi. This is a behavior comparison, not a count of bm-render defects. Case review confirms several differences are better CSS behavior in bm-render: text-shaped `background-clip`, elliptical `clip-path`, independent cell fragmentation, intact replaced images, forced breaks in flex content, and list markers on the first fragment. Eight corpus documents differ semantically from Takumi; their PDF rasters were inspected and the observed differences preserve content or honor forced breaks where Takumi drops or misplaces it. Remaining source-probe differences still need a final case-level classification before treating the audit as fully closed.

## 2026-11-15 repeated table-header border fix

Raster inspection found a real PDF defect: a repeated `thead` painted its text on later pages but omitted its collapsed borders. `src/pdf/emit_table.zig` now replays the matching table section's collapsed borders using the page repeat's `dy`, before painting cell content. The regression checks both top and bottom borders on the repeated header. The border/caption/row pagination probes pass on native and WASM: 41/41 rows, 12/12 rowspans, 11/11 captions, and 24/24 collapsed-border assertions. Raster comparison shows the repeated header matches Takumi visually; the remaining coordinate difference is under 1 CSS px. The row separator at a page break is intentionally retained because Takumi omits it.

After the Zig change, `zig build test -Dprofile=pdf -j1 --summary all` passes 676/676 and `node scripts/pdf-test.mjs --no-build` passes 393/393 on the rebuilt native addon. The complete source audit has not yet been rerun after the latest case-level reclassification; the still-open strict differences are not being treated as a count of BM defects.

## 2026-11-15 collapsed-border fragment edges

A focused raster comparison exposed a real pagination paint defect: a collapsed-border row that crosses a page cut lost the fragment's block-end edge on the earlier page and block-start edge on the next page. `src/pdf/emit_table.zig` now paints the winning collapsed horizontal edge at the current page window when that window cuts through a row. The regression uses different top/bottom border colors and checks rendered PDFium pixels at both boundaries, as well as text geometry; `pagination.continuation` passes on native and WASM.

Verification after the fix: PDF-enabled Zig suite 676/676; public PDF API 393/393 on native and 393/393 on WASM; full strict audit 1541/1571 probes pass on each backend (30 remaining strict parity differences, 0 unverified); visual corpus gate passes all 161 documents; `validate.mjs --gate=bm-only` passes 161 documents with no bm-only validator errors and veraPDF 45/45 per backend. The 12 `pdfcpu` errors remain shared with Takumi.

A quick post-fix benchmark remeasured speed and scale in one pass. The report gives bm-native async at 0.34x Takumi's time and bm-WASM at 0.58x; at 1 / 10 / 100 pages native took 3.2 / 20.3 / 226 ms versus Takumi's 25.9 / 205.5 / 1437.1 ms. This is a quick remeasurement, not a fresh three-pass full benchmark; see `bench/out/pdf/PDF.md` for the detailed environment and load notes.

## 2026-11-15 inline-link annotation verification

The padded inline-link probe previously failed only because it compared BM's annotation rectangle to Takumi's. The probe now checks both tagged and untagged BM PDFs against Poppler's extracted text bounds. On both backends the rectangle covers the linked word; Takumi's rectangle starts 9.75 pt to its left, inside the block padding. Full strict audit is now 1541/1571 probes passing on native and WASM, with 30 remaining parity differences. This corrects the audit classification; it does not change PDF generation.

## 2026-11-15 deferred-float text overlap fix

A regression case exposed a real output defect: when a `break-inside: avoid` float moved onto a page with a different width, the first word in the following paragraph was laid out at the float's x-position and overlapped the float. `Frame.paginate` now retries inline layout from the fragment origin when the deferred float changes the paragraph's available area, including when the first line has not yet been consumed. The regression is in `pagination.float.reflow-contexts`.

Verification after the change: pagination probes pass 89/89 on native and WASM; the PDF Zig suite passes 676/676; public PDF API tests pass 393/393 on both native and WASM. The latest strict audit also matches on both backends at 1541/1571 (30 remaining strict differences, 0 unverified). This means the targeted overlap defect is fixed; the remaining strict differences still need classification and any genuine PDF output defects among them need fixes.

A fresh three-pass speed run over 159 documents measured bm-native async at about 0.31x Takumi's time and faster on 159/159 cases. bm-WASM measured about 0.48x and faster on 152–154/159 cases across passes. These are generation-time results; they do not imply that every output difference is resolved. See `bench/out/pdf/PDF.md` for the complete run report.
