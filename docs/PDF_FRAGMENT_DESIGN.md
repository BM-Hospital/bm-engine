# PDF fragments and page lifetime

Implementation checkpoint for `.agents/plans/pdf-takumi-parity`, tasks 02–03 and 16–21.
Reference: Takumi `ff9a5d411310c8cdd1ac76a4f106c123d309e0a4`.

## Coordinates and decoration fragments

The current layout produces stitched document coordinates. A page owns a half-open
vertical window. Layout coordinates, a fragment's local coordinates, and the final
paint transform must remain separate: painting must never temporarily rewrite a
shared layout node.

For a transformed box spanning pages, `Emitter.BoxFragment` records the box ID and
the active fragment window. The local transform origin resolves against that
fragment's dimensions. The border/background use the fragment window, while child
content retains its stitched offset. Deferred paint queues and lifted stacking
contexts capture the fragment state along with CTM, clips and page ownership.

Text ownership uses the paragraph border-box span, transformed together with the
line. A visible line whose baseline was clipped uses its visible vertical extent.
Its owning page emits selectable text; neighbouring pages reached by its geometry
emit outlines. This avoids duplicate extracted text when a rotated line reaches a
previous page.

Inline slice backgrounds have a separate image strip: the sum of a span's line
fragment widths. Each line clips that same strip at its cumulative offset.
`box-decoration-break:clone` instead positions the image within each fragment.

Remaining verification includes nested non-translation transforms, clone borders,
links under transformed fragments and intersecting clip paths. Passing the two
transform goldens does not establish those cases.

## Continuation tokens

`layout.fragment.Start` represents one box/text line, or parallel table-cell
resume points. Each cell point records its stable layout node, paragraph line,
forced-break state and whether its content is complete. `paged.laySegments`
translates the paragraph positions to shaped-glyph cuts when rebuilding at a new
width. Intrinsic widths still measure the original paragraph; completed content
has no new line height. The table carries its assigned, unfragmented row size so
an early-finishing cell retains the row's empty content regions. Row stretch is
not treated as a trailing child margin and truncated at the fake prefix page.

Pinned-reference probes cover alternating widths, unequal cell lengths, empty
continuation regions and links. Trailing cell decorations follow Takumi's cell
rule: a cell never breaks before its block-end border and padding, so a cell whose
content ends at a page end keeps them in that fragment, past the page
(`paged.cellOverflow`). The row, its cells and the boxes around it record that
fragment (`fragment.Extend`). The next run's row is shorter by the overflow, but
still holds the finished cells' trailing decorations on its last page. The page
after a run boundary paints the previous run's overflowing decorations and opens
their cells' empty content regions first. Collapsed-border tables and row/row-group
backgrounds are not covered. The Zig tests that go through `pdf/paged.zig` need the
PDF feature (paragraph cuts) and are skipped without `-Dpdf=true`. Flex/grid
parallel continuations retain their established track widths, matching the
current reference probes; this does not establish arbitrary nested cases.

Grid layout also retains the unaligned area block start through coordinate
rounding. An aligned item with an empty first fragment resumes at the following
fragment's start. When a better breakpoint exists before the grid, an empty item
fragment does not make the inside break preferable. Start/center/end alignment,
preceding content, row spans and flex regression probes pass. Full grid track
and spanning-row continuation state is still required.

The required token carries the formatting-context kind and its ordered child
continuations, text source-cluster position, consumed block size, repeated table
sections, grid row/track state, float exclusion state, and whether a break was
forced. Tokens must use stable source IDs rather than pointers into a frame that
will be released. Resume must reconstruct the containing-block and counter state
before laying out at the next page's width.

## Settled pages and retained state

There are three distinct lifetimes:

1. Document: source model, registered font/image resources, object IDs, font subset
   usage, destination IDs, structure-tree references and total-page counters.
2. Active layout: continuation tokens, current formatting-context stacks, live
   floats, repeated/fixed content and fragments that can still reach another page.
3. Page paint: paths, temporary masks/patterns, paint queues and content builders.

The existing emitter resets page paint scratch, and counter/band re-layout frees a
replaced pass. It still retains the complete final layout. That is **not** bounded
live-layout memory or emission before whole-document layout completes.

A page is releasable only when no pending layout decision can change its break,
no later transform/positioned descendant can paint into it, repeated content has a
stable placement, and page-rule/band/counter convergence is complete for it.
Unbounded backward transforms or forward references require retaining an affected
range or another layout pass. A fixed-size look-behind window is insufficient.

Font subsets, destinations and structure objects may be finalized after page
streams, provided streams reference stable document object IDs. Region ownership
and source order must survive release; retaining pointers to page scratch is invalid.

## Verification and measurements

The correctness-gated benchmark was run on 2026-11-14. Warm render geomean was
1.37 ms native and 2.01 ms WASM, versus 3.93 ms for Takumi. The 500-page case
took 1,150 ms native, 2,049 ms WASM and 6,846 ms for Takumi. These measurements
describe runtime only. They do not establish bounded live-layout memory: the
complete final layout is still retained. The benchmark did not separately
measure document resource bytes, live layout bytes, retained arena capacity,
page scratch and output bytes. RSS and WASM linear-memory size alone cannot prove
that live layout is bounded. See [the benchmark report](../bench/out/pdf/PDF.md).

Window scenes, streaming tests and memory tests remain required adapters. Every
reported run must identify backend, binary hash, source revision, font hashes,
toolchain and reference kind (committed fixtures, source build or published npm).

Latest verified run (2026-11-15): the full PDF benchmark measured 159 common documents over three interleaved passes. bm-native async was 0.31x Takumi time and bm-wasm async 0.51x. Full validator gate `bm-only` passed 161 documents, native/WASM byte identity passed 161/161, and veraPDF passed 45/45 for each backend. This supersedes the historical runtime measurements above; the remaining source audit differences are documented in `docs/PDF_TEST_PORT.md` and still need case-level classification.

Follow-up on 2026-11-15: collapsed-border rows cut by a page window now paint the fragment's start/end horizontal edges. Raster regression coverage checks both page boundaries on native and WASM. Full Zig (676), PDF API (393 per backend), 161-document visual gate, and the `bm-only` validator all pass after this change; the full strict audit has 1540/1571 probes passing, with 31 previously classified parity differences remaining.
