# Differences from takumi and migration guide

[English](differences-from-takumi.md) · [Tiếng Việt](../vi/differences-from-takumi.md)

bm-engine is a Zig re-implementation of [takumi](https://github.com/kane50613/takumi) 2.20's renderer
(`@takumi-rs/wasm`), not a fork: it accepts the same node trees, HTML, stylesheets, Tailwind classes
and render options, and was developed against takumi as an oracle until outputs matched (184/184
benchmark fixtures identical or equivalent, one "close"). This page lists what changes when you move
from `@takumi-rs/wasm` or `takumi-js` to bm-engine, the API and rendering differences that remain, and
the takumi behaviours bm-engine deliberately reproduces.

- [Migration in five steps](#migration-in-five-steps)
- [Side-by-side example](#side-by-side-example)
- [API differences](#api-differences)
- [Rendering differences](#rendering-differences)
- [Not ported](#not-ported)
- [takumi behaviours bm-engine reproduces on purpose](#takumi-behaviours-bm-engine-reproduces-on-purpose)

## Migration in five steps

1. **Replace the package.** `@takumi-rs/wasm`, `@takumi-rs/wasm/node` and `@takumi-rs/core` →
   `bm-engine` (or `bm-engine/core` / `bm-engine/standard` for a smaller binary; see
   [Profiles](profiles-and-size.md)). The `Renderer` class keeps its name and methods.
2. **Initialisation.** On Node.js nothing changes: the entry initialises on import (like
   `@takumi-rs/wasm/node`). Elsewhere, `init({ module_or_path })` still works; with the profile entries
   you can simply call `await init()`. On Cloudflare Workers import `bm-engine/full.wasm` instead of
   `@takumi-rs/wasm/takumi_wasm_bg.wasm`.
3. **Register a font.** takumi bundles Geist as a last-resort font; bm-engine bundles nothing. Without
   `registerFont` (or the `fonts` option) text is not drawn.
4. **Fetch remote resources yourself.** bm-engine's `prepare()` does not download images or
   `@font-face` files. Pass image bytes through `images`, fonts through `registerFont` / `fonts`.
5. **JSX.** bm-engine takes node trees, `{ json }` and HTML, not JSX. Keep using
   `@takumi-rs/helpers` to convert: `fromJsx(element)` returns `{ node, css }`, which you pass as
   `render(node, { css, ... })` (checked with a hand-built React element; not tested with React itself).
   There is no `ImageResponse`; wrap the bytes in a `Response` yourself.

## Side-by-side example

takumi (`@takumi-rs/wasm`, bundler):

```js
import init, { Renderer } from "@takumi-rs/wasm";
import wasmUrl from "@takumi-rs/wasm/wasm-url";

await init({ module_or_path: wasmUrl });
const renderer = new Renderer();
await renderer.registerFont(await (await fetch("/Inter.ttf")).arrayBuffer()); // optional: Geist is built in

const png = await renderer.render(
  { type: "container", style: { display: "flex", width: "100%", height: "100%" },
    children: [{ type: "text", text: "Hello", style: { fontSize: 64 } }] },
  { width: 1200, height: 630, images: [{ src: "logo", data: logoBytes }] },
);
```

bm-engine:

```js
import { init, Renderer } from "bm-engine/full";

await init(); // finds bm_engine.wasm next to the module; init({ module_or_path: url }) also works
const renderer = new Renderer();
renderer.registerFont(await (await fetch("/Inter.ttf")).arrayBuffer()); // required: no built-in font

const png = await renderer.render( // or renderer.renderSync(...)
  { type: "container", style: { display: "flex", width: "100%", height: "100%" },
    children: [{ type: "text", text: "Hello", style: { fontSize: 64 } }] },
  { width: 1200, height: 630, images: [{ src: "logo", data: logoBytes }] },
);
```

`takumi-js`'s top-level `render(jsx, options)` maps to `new Renderer()` + `renderer.render(node, options)`
after converting the JSX with `fromJsx` (see step 5).

## API differences

| Area | takumi 2.20 | bm-engine 0.1.0 |
|:--|:--|:--|
| Package / module format | `@takumi-rs/wasm` (ESM + CJS), `@takumi-rs/core` (native N-API) | `bm-engine`, ESM only (CommonJS via `require(esm)`), WebAssembly only — no native binding |
| Binary | one 4.2 MB wasm | three profiles (428 KiB – 1.05 MiB) + WOFF add-on; `features` reports the loaded one |
| Wasm imports | wasm-bindgen glue | none |
| Sync API | wrapper methods are async | every method has a `*Sync` twin; async methods resolve immediately |
| `registerFont` | returns `Promise<RegisteredFamily[]>` (wrapper) | returns `RegisteredFamily[]` synchronously for bytes / `{ data: bytes }`; a `Promise` only for URLs and lazy data |
| `unicodeRange`, `subsetOf`, `generic` (FontDetails) | lazy subsets, generic families | accepted and ignored: every face is registered eagerly; generic names are not mapped |
| `cacheFont`, `cachedFonts`, `cacheFontFile`, `needs`, `animationNeeds` | available | not provided |
| Built-in font | Geist (variable, kept by `clearFonts`) | none |
| `prepare` / `prepareAnimation` | fetch remote images and `@font-face` files (needs pass) | resolve `fonts` and lazy `images` only; fetch nothing |
| `render` remote URLs | not fetched without `prepare` | never fetched |
| `new Renderer({ cacheMaxBytes, fontCacheMaxBytes })`, `setGlyphCacheMaxBytes` | configurable caches | accepted and ignored (fixed 96 MiB images / 8 MiB glyphs) |
| `drawDebugBorder`, `dithering` | supported | accepted and ignored |
| `measure` result | runs include `text`, glyph-box heights | same tree, boxes and positions; runs have no `text` and use the line height (see [API](api.md#measure--measuresync)) |
| `renderSvg` | takumi-svg | ported (full profile): same structure, glyphs as outlines, no font embedding |
| PDF (`takumi-pdf`) | separate package | not ported |
| `ImageResponse`, JSX `render()` (`takumi-js`) | available | not provided; use `@takumi-rs/helpers` + `new Response(...)` |
| `memoryBytes()` | — | added: current wasm memory size |
| Errors | `Error` with takumi messages | `Error` with `bm-engine: ` prefix; messages differ in wording |

## Rendering differences

From the equivalence benchmark (see [Benchmark](benchmark.md)); everything else renders identically or
within anti-aliasing noise.

- **Anti-aliasing**: bm-engine ports tiny-skia's 4×4 supersampling scan converter and takumi's
  `div_255`, so 74/184 fixtures are byte-identical. The rest differ at curved edges and glyph edges by a
  sub-sample (SSIM ≥ 0.99).
- **One-level differences**: gradient interiors (takumi accumulates `f32` per span), dashed borders on
  rounded corners (~0.1 px phase), rotated text, `-webkit-text-stroke`.
- **Text next to floats**: the paragraph keeps the narrow width below the float (one "close" fixture).
  In progress in 0.1.0; see [docs/BENCHMARK.md](../BENCHMARK.md) for the final status.
- **Mixed inline content**: no wrapping around an `inline-block` mid-line; inline span padding does not
  push text. In progress in 0.1.0.
- **`direction: rtl` on flex containers** does not reverse the main axis in 0.1.0.
- **`image-rendering: pixelated`** on raster images is ignored (smooth resampling).
- **Colour emoji**: bm-engine draws COLR v1 fonts (takumi does not); some ZWJ sequences are not merged
  and emoji-font preference differs for a few characters.
- **SVG images**: `<text>` inside SVG images and a few filter primitives (`feTurbulence`, `feImage`,
  `feMorphology`, `feConvolveMatrix`, `feDisplacementMap`, lighting, `feTile`) are not supported.
- **Encoders**: encoded files are different bytes (bm-engine's encoders are its own; PNG files are
  24 % smaller, geometric mean over the fixtures); decoded pixels are what the benchmark compares.
- **`display: contents`** is rejected by takumi's inline-style parser but accepted (and not rendered) by
  bm-engine.

## Not ported

- PDF output (`takumi-pdf`, a separate product of ~43 500 lines of Rust).
- Native N-API binding (`@takumi-rs/core`).
- Network access of any kind (`prepare` fetching, `@font-face` URLs).
- Counters in `content`, list markers, `@apply`, Tailwind `animate-*`, animations on pseudo-elements,
  `clip-path: url()`, relative colour syntax, `outline-offset` in %.

## takumi behaviours bm-engine reproduces on purpose

These follow takumi (and Blink) even where they surprise newcomers, so that a tree designed for takumi
renders the same:

- `display` defaults to **`inline`** for every node, including containers; the root and flex / grid
  children are blockified. A container without `display` ignores its `width` / `height`.
- `box-sizing` defaults to **`border-box`**.
- Inline `style` keys must be camelCase; kebab-case keys and unknown properties are ignored silently.
- An invalid inline style value throws, while invalid stylesheet / Tailwind declarations are dropped.
- Unitless numbers are px for lengths; numbers stay numbers for `opacity`, `lineHeight`, `flexGrow`,
  `fontWeight`.
- `width` / `height` options are output pixels; `devicePixelRatio` scales CSS lengths without changing
  the canvas size; `vw` / `vh` refer to output pixels.
- The root is not stretched to the canvas height; `height: "100%"` resolves against the canvas.
- The canvas starts transparent; JPEG output drops alpha (transparent becomes black); WebP output is
  always lossless.
- Font fallback walks every registered family in registration order. With the `fonts` option and no
  `fontFamilies`, the families of those fonts become the root font stack.
- Every JS string source is HTML; JSON text must be wrapped as `{ json }`.
- Missing images paint nothing and do not throw.
- Tailwind: takumi's utility table, sort order and variant set (no `hover:`, `dark:`, `z-*`, `ring-*`,
  ...); the alphabetically later of two conflicting colour classes wins.
- Stylesheets: takumi's lossy parsing (`@page`, `@container`, `@scope`, ... are dropped), dynamic
  pseudo-classes never match, `@media` against the canvas size in CSS px, unsupported media features
  make the whole query false.
- Animations: integer-ms timeline, applied at t = 0 by default, `animation-play-state` ignored,
  built-in `spin` / `ping` / `pulse` / `bounce` keyframes, takumi's frame schedule for
  `renderAnimation`.
- Limits: 512 levels of nesting.
