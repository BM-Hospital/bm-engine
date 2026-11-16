# bm-engine architecture

bm-engine is a Zig 0.17 re-implementation of the core of [takumi](https://github.com/kane50613/takumi)
(node tree → image, and node tree → paged PDF), built as small `wasm32-freestanding` binaries (three feature profiles, plus a `pdf` profile) that run unchanged in browsers,
Node.js, Bun, Deno and edge runtimes. It accepts takumi's node format so the same inputs can be rendered
by both engines and compared.

## Goals and budget

| | takumi 2.20 (`@takumi-rs/wasm`) | bm-engine target |
|---|---|---|
| `.wasm` size | 4.34 MB (4 235 KiB) | phase 1: 321 KiB (one build). Phase 2 / final 0.1.0 (after wasm-opt): **core 489.6 KiB, standard 936.5 KiB, full 1 143.6 KiB** (+ 84.4 KiB WOFF add-on) |
| JS glue | ~38 KB + wasm-bindgen marshalling | dependency-free ESM (`js/engine.mjs` + small entry files) |
| Imports from host | wasm-bindgen shims (dozens) | **none** (pure computation; no WASI) |
| Init | async fetch/instantiate | sync or async, no start function |

## Scope and build profiles

Phase 1 shipped the MVP (inline styles, flex / block / grid, static TrueType text, PNG / JPEG / WebP).
Phase 2 ported the rest of takumi's image renderer. PDF output (a port of `takumi-pdf`) came afterwards as a
fourth profile. Optional features are compile-time flags (`src/config.zig`, set by `build.zig`); four presets
are shipped:

| Profile | Size (wasm-opt -Oz) | Contents |
|:--|--:|:--|
| core | 489.6 KiB | node JSON + inline styles, var() / calc(), block / inline / flex / grid / absolute, static TTF / TTC + default OpenType shaper, every border style, outline, text decorations, PNG / JPEG in, PNG / JPEG / WebP / raw out |
| standard | 936.5 KiB | core + stylesheets / selectors (`css`), Tailwind (`tw`), HTML, SVG images, WOFF / WOFF2, variable fonts, CFF, effects (clip-path, masks, blend modes, backdrop-filter), modern colours, tables, floats, WebP / GIF in, text-wrap balance |
| full | 1 143.6 KiB | standard + complex text (bidi, Arabic, Hebrew, Indic, Thai), colour emoji, animations + renderAnimation, lossy WebP / animated codecs / ICO, renderSvg |
| pdf | about 1.9 MB raw | full + `renderPdf` / `measurePdf` (the `pdf` flag): the PDF pipeline below, block fragmentation (`src/layout/fragment.zig`) and the paged-media CSS properties. `bm-engine/pdf`, `js/bm_engine.pdf.wasm` |

`bm_features()` exports the flag bits; the JS wrapper exposes them as `features`. The WOFF decoder is
also built as a separate add-on module (`src/addon_woff.zig` → `bm_woff.wasm`). User-facing details:
[docs/en/profiles-and-size.md](en/profiles-and-size.md); remaining gaps: [BENCHMARK.md](BENCHMARK.md).

## Where we deliberately differ from takumi

1. **Marshalling**: takumi walks the JS object tree through `serde-wasm-bindgen` (one JS↔wasm call per
   property). We `JSON.stringify` once in JS, copy one UTF-8 buffer, and parse it in wasm with a tiny
   DOM parser. Binary payloads (fonts, images) are copied once into wasm memory and referenced by id.
2. **Own CSS stack**: takumi links `cssparser` + `selectors` (Servo). bm-engine has small hand-written
   value parsers (`src/style/`) and, in the standard / full profiles, its own stylesheet parser, selector
   matcher and cascade (`src/css/`) that mirror takumi's lossy parsing and matching rules.
3. **Memory**: one chunk-reusing bump allocator per render (`src/bump.zig`) — steady-state renders do no
   backing allocations. Large blocks come from a page allocator (`src/pages.zig`) instead of std's
   power-of-two size classes. Fonts, decoded images (96 MiB budget) and glyph masks (8 MiB budget) are
   long-lived. The shadow stack is 1 MiB and node nesting is capped at 512 levels (as in takumi).
4. **Rasterizer**: a port of tiny-skia's 4x4 supersampling scan converter (byte-identical coverage on
   the test shapes) plus takumi's `div_255` compositing, writing premultiplied RGBA8; gradients use
   takumi's LUT sampling rule. Glyph masks are cached per (face, glyph, size, quarter-pixel phase).
5. **Text stack**: instead of skrifa + harfrust + parley + ICU data, a compact sfnt / CFF / variations
   parser, a GSUB / GPOS engine, UAX #14 line breaking, and (full profile only) bidi, script shapers
   (Arabic, Indic, Thai), normalisation and colour glyphs. The complex-text parts are compiled out of
   core / standard.
6. **Encoders**: purpose-built fast deflate/PNG encoder tuned for flat UI content.

## Module map

```
js/engine.mjs         binding around one wasm instance: init/initSync, Renderer, features (createBinding)
js/index.mjs          "bm-engine" (neutral entry, explicit init); js/node.mjs = Node entry, inits on import
js/{core,standard,full}.mjs, js/node-{core,standard,full}.mjs   profile entries (own instances)
js/addons.mjs         "bm-engine/woff": WOFF add-on loader
src/wasm.zig          wasm exports (C ABI): alloc/free, font/image registration, render, results, bm_features
src/config.zig        compile-time feature flags (profiles from build.zig)
src/root.zig          native root (unit tests of every module)
src/json.zig          JSON DOM parser
src/dom.zig           element tree from JSON / HTML, per-element cascade (preset < css / tw < style)
src/style/            CSS value parsing -> ComputedStyle (props.zig = property table), colours, gradients, calc
src/css/              stylesheet tokenizer / parser, selectors, cascade, @media / @supports / @layer
src/tw/               Tailwind compiler + palette
src/html/             HTML tokenizer / tree builder, Chromium UA presets, entities
src/layout/           block / inline / flex / grid / table / float layout, measure callback for leaves
src/font/             sfnt, CFF, variations, GSUB / GPOS, Arabic / Indic shapers, bidi, normalisation, colour glyphs
src/woff/             WOFF / WOFF2 + brotli (also built as the add-on: src/addon_woff.zig)
src/raster/           paths, tiny-skia-exact scan conversion, stroker, blur, blending, image resampling
src/paint*.zig        painter (Blink paint order), borders, effects, text, tables, SVG images
src/svg/              SVG parser + renderer (SVG images)
src/svg_out*.zig      renderSvg (node tree -> SVG document)
src/animate.zig       CSS animation sampling at timeMs
src/codec/            inflate / deflate, PNG, JPEG, WebP (lossless + VP8), GIF, ICO, animation encoders
src/pdf/              PDF output (the `pdf` flag only): see "PDF pipeline" below
src/layout/fragment.zig  block fragmentation (pagination), compiled with the `pdf` flag
js/pdf.mjs, js/node-pdf.mjs, js/pdf-api.mjs   "bm-engine/pdf": PdfRenderer (pdf-api.mjs, shared), render / measure / prepare, page counter helpers; pdf.mjs is the wasm-only entry, node-pdf.mjs the Node entry (native addon when present, else wasm)
src/render.zig        pipeline: source -> DOM -> style -> layout -> paint -> encode; options, caches, renderAnimation
src/bump.zig, src/pages.zig   per-render bump arena, page allocator
bench/                fixtures shared with takumi, benchmark + pixel-equivalence harness, probes, browser test
```

## Render pipeline

1. JS: `JSON.stringify(node)` (binary image sources replaced by resource ids) → wasm memory.
2. `json.parse` (or the HTML parser) → `dom`: build the element tree, apply presets, stylesheets, `tw`
   and inline styles, resolve each element's computed style (inheritance, units with viewport +
   devicePixelRatio, animations at `timeMs`).
3. Build layout tree; text and image leaves are *measured* nodes. Text is shaped once per node and
   re-broken per measure call (cached).
4. `layout.compute` → absolute boxes.
5. Paint in document order (stacking: positioned/z-index sorting where specified): shadow → background →
   border → content → children, with clip stack and opacity layers.
6. Un-premultiply and encode (PNG / JPEG / WebP / ICO) or return raw RGBA; `renderSvg` serialises the
   same prepared frame as SVG instead of painting pixels.
7. Reset arena.

## PDF pipeline

PDF output reuses everything up to layout. `Renderer.renderPdf` (`src/render.zig`, wasm export `bm_render_pdf`; the native addon exposes it as the ops `pdf` and `pdfMeasure` in `src/native/ops.zig`) calls

`src/pdf/pdf.zig`, which exists only when `config.enable_pdf` is set; the other wasm profiles contain none of it (the native addon is built with it).
The stages, in the order a document passes through them:

1. **Options** (`src/pdf/options.zig`): the JS wrapper sends the options as JSON; this file parses and validates
   them with takumi-pdf's rules and messages (page geometry, bands, page rules, `pageRanges`, metadata,
   attachments, `pdfa`, `tagged`, `uncoveredText`). It has no dependency on the renderer and is unit-tested natively.
2. **Writer** (`src/pdf/writer.zig`, `content.zig`): the object model and file structure of `pdf-writer` plus
   krilla's chunk container: objects are written into categories and renumbered at `finish`, with a
   cross-reference stream (PDF >= 1.5), so object numbers and key order follow takumi-pdf's output.
   `content.zig` builds content streams.
3. **Subsetter** (`subset.zig`, `subset_cff.zig`): a port of the `subsetter` crate. It keeps the used glyphs of
   a TrueType or CFF font, renumbers them, and instances variable fonts at the location in use. `font_embed.zig`
   (CID fonts, `ToUnicode`, `ActualText` rules) and `font_objects.zig` (the document's font registry, Type 3 fonts for
   colour glyphs) turn that into PDF objects.
4. **Emitter over `render.Frame`** (`emit.zig` and `emit_*.zig`): after style, layout and the cascade, the
   emitter walks the same `Frame` the raster painter and `svg_out` walk, in Blink paint order, and draws onto
   a krilla-style surface (`emit_surface.zig`: graphics states, clips, transparency groups, patterns, soft masks).
   Backgrounds and borders (`emit_border.zig`), gradients and shadings (`emit_shading.zig`), images (`emit_image.zig`:
   JPEG and eligible PNG bytes embedded as is), SVG images as vector paths (`emit_svg.zig`; unsupported SVG falls back
   to raster), tables (`emit_table.zig`), geometry and devices (`emit_geom.zig`, `emit_device.zig`).
5. **Text** (`text.zig`, `emit_text.zig`, `type3.zig`): glyph runs are encoded as text operators over the subset
   fonts; colour (COLR, CBDT, sbix) glyphs go through Type 3; the `uncoveredText` policy lives here.
6. **Pagination** (`src/layout/fragment.zig`, `src/pdf/paged.zig`, `page_rules.zig`): the document is laid out once at
   the page-area width with an unbounded height, then `fragment.paginate` picks the breaks by Blink's
   rules (forced and avoided breaks, `orphans` / `widows`, repeated table header / footer groups, fixed boxes) and
   moves content down in place. A page is then the whole tree painted under a clip and a translation. `page_rules.zig`
   resolves `@page` geometry; `paged.zig` runs the passes below. When page areas differ in width, `paged.zig` lays the
   content out again for each run of pages of one width, from where the run before stopped (`fragment.Options.start`),
   in one block coordinate space; the emitter draws each page from its run's frame.
7. **Bands and counters** (`bands.zig`, `counters.zig`): headers and footers are laid out on their own at the full page
   width and drawn in the margins; the margins resolve around their heights. Page counters are class hooks
   substituted into the DOM between the build and the cascade; `paged.zig` repeats layout until the counters settle
   (three counter passes, three band passes).
8. **Interactive and document parts** (`interactive.zig`, `metadata.zig`, `attach.zig`): links and anchors are collected
   during the emitter's walk and written as annotations and destinations; the outline comes from headings; the Info
   dictionary, XMP packet and catalog are written by `metadata.zig`; attachments by `attach.zig`.
9. **Tagging and conformance** (`tags.zig`, `tagdoc.zig`, `emit_tag.zig`, `conform.zig`): the emitter records marked-content
   ids; `tags.zig` builds the structure tree from the element model; `conform.zig` chooses the PDF version from the
   requested validators (PDF/A, PDF/UA), records violations the way krilla does, and supplies the embedded sRGB profile
   (`srgb-v4.icc`) and output intent for PDF/A.

The code is a port of `takumi-pdf` and the krilla, `pdf-writer`, `xmp-writer` and `subsetter` crates it builds on;
the file headers in `src/pdf/` name the Rust files each follows. Licences: [THIRD-PARTY-NOTICES](../THIRD-PARTY-NOTICES.md).
User documentation: [PDF output](en/pdf/index.md). Checks: `node scripts/pdf-test.mjs` (API, options, text extraction with
`pdftotext`) and `node scripts/pdf-compare.mjs` (operator-level comparison with takumi-pdf's golden PDFs).

## wasm ABI (stable surface used by js/engine.mjs)

All functions use plain integers/pointers; no imports. Errors are reported through a status code plus a
UTF-8 message buffer (`bm_last_error_ptr/len`). See `src/wasm.zig` for the authoritative list.

## What was measured

See `docs/BENCHMARK.md` for sizes, speed, memory and pixel-equivalence against takumi 2.20.0, and for the
list of gaps.
