# bm-engine architecture

bm-engine is a Zig 0.17 re-implementation of the core of [takumi](https://github.com/kane50613/takumi)
(node tree → image), built as one small `wasm32-freestanding` binary that runs unchanged in browsers,
Node.js, Bun, Deno and edge runtimes. It accepts takumi's node format so the same inputs can be rendered
by both engines and compared.

## Goals and budget

| | takumi 2.20 (`@takumi-rs/wasm`) | bm-engine target |
|---|---|---|
| `.wasm` size | 4.34 MB (4 235 KiB) | target ≤ 300 KB; **actual 318 KiB** with every codec (target missed by ~6%) |
| JS glue | ~38 KB + wasm-bindgen marshalling | one dependency-free ESM file, a few KB |
| Imports from host | wasm-bindgen shims (dozens) | **none** (pure computation; no WASI) |
| Init | async fetch/instantiate | sync or async, no start function |

## Scope (MVP) vs takumi

In scope (implemented): container/text/image nodes; inline `style` / `preset` objects (camelCase CSS, 141
properties parsed); flexbox, block and grid layout; absolute positioning; backgrounds (colour,
linear/radial/conic gradients, `url()` images), borders, border-radius, box-shadow (outer/inset), opacity,
overflow clipping, 2D transforms, text-shadow, filters (blur + colour matrices); text with static TrueType
fonts (GPOS kerning, basic GSUB, wrapping, alignment, line-height, letter-spacing, ellipsis, line clamp,
synthetic bold/italic); PNG/JPEG/WebP-lossless/GIF decoding; PNG/JPEG/WebP(lossless)/raw encoding; `measure()`.

Out of scope for now (see BENCHMARK.md for the honest list): stylesheets/selectors/cascade (`css`
option, `className`), Tailwind (`tw`), HTML input, animations/keyframes, SVG input & `renderSvg`, PDF,
complex-script shaping (Arabic/Indic, bidi), colour emoji, variable fonts, WOFF/WOFF2, blend modes,
masks / clip-path, background-clip:text, dashed/dotted borders, inline box decorations, CFF outlines,
modern colour spaces (oklch, color-mix).

## Where we deliberately differ from takumi

1. **Marshalling**: takumi walks the JS object tree through `serde-wasm-bindgen` (one JS↔wasm call per
   property). We `JSON.stringify` once in JS, copy one UTF-8 buffer, and parse it in wasm with a tiny
   DOM parser. Binary payloads (fonts, images) are copied once into wasm memory and referenced by id.
2. **No general CSS engine**: takumi links `cssparser` + `selectors` (Servo) for a full cascade. We parse
   property *values* with small hand-written parsers; there is no selector matching.
3. **Memory**: one chunk-reusing bump allocator per render (`src/bump.zig`) — steady-state renders do no
   backing allocations. Large blocks come from a page allocator (`src/pages.zig`) instead of std's
   power-of-two size classes. Fonts, decoded images (96 MiB budget) and glyph masks (8 MiB budget) are
   long-lived. The shadow stack is 1 MiB and node nesting is capped at 128 levels.
4. **Rasterizer**: one exact-area coverage rasterizer (font-rs style accumulation, sparse blocks) for
   every shape, writing premultiplied RGBA8; gradients use takumi's LUT sampling rule (byte-exact in
   most cases). To match takumi's tiny-skia output (and to keep PNGs small) coverage is quantised to 17
   levels, and glyphs are scan-converted at 4x and box-filtered like a 4x4 supersampler; glyph masks are
   cached per (face, glyph, size, quarter-pixel phase).
5. **Text stack**: instead of skrifa + harfrust + parley + ICU segmenter data, a compact sfnt parser,
   GPOS pair-kerning, and a UAX#14-subset line breaker. This is the single biggest size win and the
   single biggest functional gap (no complex scripts).
6. **Encoders**: purpose-built fast deflate/PNG encoder tuned for flat UI content.

## Module map

```
js/index.mjs          ESM wrapper: init/initSync, Renderer (render, renderSync, measure, registerFont…)
js/node.mjs           Node entry: reads the .wasm from disk and inits synchronously
src/wasm.zig          wasm exports (C ABI): alloc/free, font/image registration, render, result access
src/root.zig          native root (unit tests of every module)
src/json.zig          JSON DOM parser
src/style/            CSS value parsing → computed Style (colors, lengths, gradients, shadows, transforms)
src/node.zig          node tree construction from JSON + style inheritance
src/layout/           flexbox / block / grid engine (taffy-equivalent), measure callback for leaves
src/font/             sfnt parser, cmap, glyf outlines, GPOS kerning, shaping, line breaking
src/raster/           paths, coverage rasterizer, paints, compositing, blur, resampling
src/codec/            inflate/deflate, PNG dec/enc, JPEG dec/enc, WebP lossless enc
src/render.zig        pipeline: tree → style → layout → paint → encode
bench/                fixtures shared with takumi, benchmark + pixel-equivalence harness
```

## Render pipeline

1. JS: `JSON.stringify(node)` (binary image sources replaced by resource ids) → wasm memory.
2. `json.parse` → `node.build`: resolve each node's style (inherit text properties, convert units with
   viewport + devicePixelRatio).
3. Build layout tree; text and image leaves are *measured* nodes. Text is shaped once per node and
   re-broken per measure call (cached).
4. `layout.compute` → absolute boxes.
5. Paint in document order (stacking: positioned/z-index sorting where specified): shadow → background →
   border → content → children, with clip stack and opacity layers.
6. Un-premultiply and encode (PNG/JPEG/WebP) or return raw RGBA.
7. Reset arena.

## wasm ABI (stable surface used by js/index.mjs)

All functions use plain integers/pointers; no imports. Errors are reported through a status code plus a
UTF-8 message buffer (`bm_last_error_ptr/len`). See `src/wasm.zig` for the authoritative list.

## What was measured

See `docs/BENCHMARK.md` for sizes, speed, memory and pixel-equivalence against takumi 2.20.0, and for the
list of gaps.
