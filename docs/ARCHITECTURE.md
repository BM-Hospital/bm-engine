# bm-engine architecture

bm-engine is a Zig 0.17 re-implementation of the core of [takumi](https://github.com/kane50613/takumi)
(node tree → image), built as small `wasm32-freestanding` binaries (three feature profiles) that run unchanged in browsers,
Node.js, Bun, Deno and edge runtimes. It accepts takumi's node format so the same inputs can be rendered
by both engines and compared.

## Goals and budget

| | takumi 2.20 (`@takumi-rs/wasm`) | bm-engine target |
|---|---|---|
| `.wasm` size | 4.34 MB (4 235 KiB) | phase 1: 321 KiB (one build). Phase 2: **core 428.5 KiB, standard 849.6 KiB, full 1 070.0 KiB** (+ 84.2 KiB WOFF add-on) |
| JS glue | ~38 KB + wasm-bindgen marshalling | dependency-free ESM (`js/engine.mjs` + small entry files) |
| Imports from host | wasm-bindgen shims (dozens) | **none** (pure computation; no WASI) |
| Init | async fetch/instantiate | sync or async, no start function |

## Scope and build profiles

Phase 1 shipped the MVP (inline styles, flex / block / grid, static TrueType text, PNG / JPEG / WebP).
Phase 2 ported the rest of takumi's renderer except PDF. Optional features are compile-time flags
(`src/config.zig`, set by `build.zig`); three presets are shipped:

| Profile | Size (wasm-opt -Oz) | Contents |
|:--|--:|:--|
| core | 428.5 KiB | node JSON + inline styles, var() / calc(), block / inline / flex / grid / absolute, static TTF / TTC + default OpenType shaper, every border style, outline, text decorations, PNG / JPEG in, PNG / JPEG / WebP / raw out |
| standard | 849.6 KiB | core + stylesheets / selectors (`css`), Tailwind (`tw`), HTML, SVG images, WOFF / WOFF2, variable fonts, CFF, effects (clip-path, masks, blend modes, backdrop-filter), modern colours, tables, floats, WebP / GIF in, text-wrap balance |
| full | 1 070.0 KiB | standard + complex text (bidi, Arabic, Hebrew, Indic, Thai), colour emoji, animations + renderAnimation, lossy WebP / animated codecs / ICO, renderSvg |

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

## wasm ABI (stable surface used by js/engine.mjs)

All functions use plain integers/pointers; no imports. Errors are reported through a status code plus a
UTF-8 message buffer (`bm_last_error_ptr/len`). See `src/wasm.zig` for the authoritative list.

## What was measured

See `docs/BENCHMARK.md` for sizes, speed, memory and pixel-equivalence against takumi 2.20.0, and for the
list of gaps.
