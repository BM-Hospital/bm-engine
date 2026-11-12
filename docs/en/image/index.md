# Image quick start

[English](index.md) · [Tiếng Việt](../../vi/image/index.md)

This page takes you from an installed package to a rendered image in Node.js and in a browser, then
covers the two things every image project has to provide: fonts (bm-engine ships **no** font) and
images. Install the package and pick an entry point first: [Getting started](../getting-started.md)
covers the native addon and WebAssembly, bundlers, edge runtimes and the build profiles. Every Node.js
snippet on this page was executed against bm-engine 0.1.0 with package resolution.

- [Node.js](#nodejs)
- [Browser without a bundler](#browser-without-a-bundler)
- [Fonts](#fonts)
- [Images](#images)
- [Output formats](#output-formats)
- [See also](#see-also)

## Node.js

On Node.js every entry is ready on import (`bm-engine` with the native addon or, without it, like the
profile entries, by reading its wasm binary from disk and initialising synchronously), so you can create a
`Renderer` immediately:

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const png = renderer.renderSync(
  {
    type: "container",
    style: {
      display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
      backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)",
    },
    children: [{ type: "text", text: "Hello from bm-engine", style: { fontFamily: "Inter", fontSize: 64, color: "white" } }],
  },
  { width: 1200, height: 630 },
);
writeFileSync("og.png", png);
```

Things to notice:

- **Register a font before rendering text.** Without one, text is silently not drawn (takumi bundles
  the Geist font; bm-engine does not). See [Fonts](#fonts).
- `renderSync` returns a `Uint8Array` (PNG unless you pass `format`). Every method also has an async
  twin (`render`, `measure`, ...). On the native backend the async variants render on the libuv thread
  pool (one renderer runs one call at a time: create several renderers to render in parallel); on wasm
  rendering is synchronous either way and the async variants exist for takumi compatibility and for the
  options that need awaiting (`fonts`, lazy `images`).
- `display` defaults to **`inline`**, as in takumi and CSS. Give every container that has a size, or
  whose children should be laid out as a row/column, an explicit `display: "flex"` / `"block"` / `"grid"`.
  See [Troubleshooting](../troubleshooting.md#containers-collapse-to-zero-height).

The `bm-engine` Node entry honours three environment variables: `BM_ENGINE_BACKEND=wasm|native` (see
[Install](../getting-started.md#native-on-nodejs-webassembly-everywhere-else)), `BM_PROFILE=core|standard|full` selects one of
the packaged wasm binaries and `BM_WASM=/path/to/file.wasm` loads a custom build (both imply wasm). Prefer the explicit
subpaths (`bm-engine/core`, ...) in application code.

## Browser without a bundler

Serve the package directory and import a profile entry by URL. `init()` without an argument fetches the
binary that sits next to the entry module:

```html
<img id="out" />
<script type="module">
  import { init, Renderer } from "/node_modules/bm-engine/js/full.mjs"; // or core.mjs / standard.mjs

  await init(); // fetches ./bm_engine.wasm relative to full.mjs
  const renderer = new Renderer();
  const font = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
  renderer.registerFont({ name: "Inter", data: font });

  const png = await renderer.render(
    { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#7c3aed" },
      children: [{ type: "text", text: "Hi", style: { fontFamily: "Inter", fontSize: 48, color: "white" } }] },
    { width: 300, height: 100 },
  );
  document.getElementById("out").src = URL.createObjectURL(new Blob([png], { type: "image/png" }));
</script>
```

With the generic entry (`js/index.mjs`) you pass the binary explicitly:
`await init(fetch("/node_modules/bm-engine/js/bm_engine.wasm"))`. `init` accepts a URL string, `URL`,
`Request`, `Response`, `Promise<Response>`, bytes or a compiled `WebAssembly.Module`.

- Serve `.wasm` files as `application/wasm` to get streaming compilation; with any other content type
  `init` falls back to `arrayBuffer()` + `WebAssembly.instantiate`, which also works.
- The binary has **no imports** (no WASI, no wasm-bindgen glue). The runtime needs WebAssembly with
  SIMD128 and bulk memory (every current browser engine).
- What was tested: the `init(fetch(url))` path was executed in Node against a local HTTP server
  serving the package; the repository's browser test (`bench/browser`, headless Edge 157) loads the
  same wrapper and binary and checks that raw output is byte-identical to Node (12/12 cases in the last
  run, see [Benchmark](../benchmark.md#browser)).
  The package test also loads Vite-built pages in headless Edge 157 (PNG rendered, no console errors).
  Loading straight from a CDN (`https://cdn.jsdelivr.net/npm/bm-engine@0.1.0/js/core.mjs`, then
  `await init()`) should work the same way once the package is published; it is untested until then.

## Fonts

bm-engine never reads system fonts and **bundles none**. Register every font you use, per `Renderer`:

```js
renderer.registerFont(readFileSync("Inter-Regular.ttf"));                                     // name / weight / style read from the font
renderer.registerFont({ name: "Brand", data: readFileSync("Inter-Bold.ttf"), weight: 700 });  // explicit
renderer.registerFont({ name: "Geist", data: readFileSync("Geist-VF.ttf") });                 // variable font
await renderer.registerFont("https://example.com/font.woff2");                                // URL: fetched, returns a Promise
```

`registerFont` returns takumi's `RegisteredFamily[]`:
`[{ name, faces: [{ weight, style, width, index }], weight, style }]`. Registering another file under
an existing family name adds faces to that family. See the [API reference](api.md#registerfont).

| Format | core | standard | full |
|:--|:-:|:-:|:-:|
| TrueType `.ttf`, collections `.ttc` (every face) | yes | yes | yes |
| OpenType with CFF / CFF2 outlines (`.otf`) | no (`unsupported font format`) | yes | yes |
| WOFF / WOFF2 | with the [WOFF add-on](#woff-on-core) | yes | yes |
| Variable fonts | registered, drawn at the default instance only | yes | yes |
| Colour glyphs, emoji fonts: COLR v0/v1 / bitmap CBDT, sbix | no colour / not drawn | no colour / yes | yes |

On `standard` and `full`, a variable font follows `font-weight` (`wght`), `font-stretch` (`wdth`),
`font-optical-sizing` (`opsz`) and `font-variation-settings`.

**Matching and fallback.** Within a family the closest face is chosen by CSS font matching (stretch,
then style, then weight); missing bold / italic faces are synthesised. An element without
`font-family` uses the `fontFamilies` render option (the root font stack) if given. A character not
found in the element's families falls back to **every registered family in registration order**. A character no
registered font covers is drawn as the font's `.notdef` glyph (usually an empty box). Generic names
(`sans-serif`, ...) are not mapped to anything; text using them simply falls through to the fallback
chain.

**Emoji.** Colour emoji need the `full` profile *and* a registered colour emoji font (for example
Noto Color Emoji). Because the fallback walks every registered family, registering the emoji font is
enough.

**Vietnamese and other accented Latin.** Precomposed (NFC) text works on every profile. Decomposed
(NFD) text depends on the font's mark positioning; only `full` normalises text. Call
`text.normalize("NFC")` on user input to be safe. See [Troubleshooting](../troubleshooting.md#vietnamese-text).

### WOFF on core

The `core` binary has no WOFF/WOFF2 decoder. A separate 84 KiB add-on (`bm-engine/woff`) converts
WOFF/WOFF2 to TTF/OTF before registration; the result is byte-identical to the built-in decoder:

```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine/core";
import { loadWoff } from "bm-engine/woff";

await loadWoff(); // Node: reads bm_woff.wasm from the package; bundlers: emitted as an asset
const renderer = new Renderer();
renderer.registerFont({ name: "Geist", data: readFileSync("Geist.woff2") }); // accepted now
```

On Workers pass the module: `import woff from "bm-engine/woff.wasm"; await loadWoff(woff)`. Converting
does not add CFF support: a CFF-flavoured WOFF2 still needs `standard` or `full`.

## Images

An `image` node's `src`, and a CSS `url(...)` in `backgroundImage` / `maskImage`, can be:

| `src` | Example |
|:--|:--|
| a key of the `images` render option | `src: "https://example.com/logo.png"` + `images: [{ src: "https://example.com/logo.png", data: bytes }]` |
| a `data:` URL (base64 or percent-encoded) | `"data:image/png;base64,iVBOR..."` |
| bytes | `src: new Uint8Array(bytes)` or an `ArrayBuffer` |
| raw pixels | `src: { width, height, data, premultiplied? }`: RGBA8, `data.length === width * height * 4` |
| inline SVG markup | `src: '<svg xmlns="http://www.w3.org/2000/svg" ...>...</svg>'` (standard / full) |

```js
const logo = readFileSync("logo.png");
const png = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 16, padding: 16, width: "100%", height: "100%" },
    children: [
      { type: "image", src: "https://example.com/logo.png", width: 64, height: 64 },
      { type: "image", src: new Uint8Array(logo), width: 64, height: 64 },
      { type: "container", style: { width: 64, height: 64, backgroundImage: "url(logo)", backgroundSize: "cover", borderRadius: 32 } },
    ],
  },
  {
    width: 280, height: 96,
    images: [
      { src: "https://example.com/logo.png", data: logo },
      { src: "logo", data: logo },
    ],
  },
);
```

- **Nothing is downloaded.** A URL is only a lookup key into `images`; an unknown key paints nothing
  and does not throw, like takumi's `render` without `prepare`. Fetch the bytes yourself.
- **Node `Buffer` directly in `src`:** works as is; wrapping it in `new Uint8Array(buffer)` is no longer
  necessary. Buffers in `images[].data` and `registerFont` work too.
- `images[].data` may be a function or a promise (lazy loading) with the async methods (`render`,
  `prepare`, ...); the sync methods throw `lazy images[].data() needs the async API`.
- Only images the source actually references are copied into wasm memory.
- `width` / `height` on an image node are presentational hints (lowest priority, like HTML attributes);
  CSS `width` / `height` win. Given only one of them, the other follows the aspect ratio. Without either
  the intrinsic size (× `devicePixelRatio`) is used.

| Image input | core | standard | full |
|:--|:-:|:-:|:-:|
| PNG, JPEG | yes | yes | yes |
| SVG (`<svg>` markup, `data:image/svg+xml`, `url()`) | no (paints nothing) | yes | yes |
| WebP lossless, GIF (first frame) | no (paints nothing) | yes | yes |
| WebP lossy (VP8), animated GIF / APNG / WebP | no | no lossy WebP | yes |

## Output formats

| `format` | Output | Profiles |
|:--|:--|:--|
| `"png"` (default) | PNG; indexed / RGB / RGBA chosen automatically | all |
| `"jpeg"` (alias `"jpg"`) | baseline JPEG, `quality` 1–100 (default 75); transparent pixels become black | all |
| `"webp"` | **lossless** WebP (`quality` / `lossless` ignored, as in takumi's wasm build) | all |
| `"raw"` | `width × height × 4` bytes, straight (non-premultiplied) RGBA8, row-major | all |
| `"ico"` | ICO with one PNG entry; 1–256 px per side | full |
| `renderSvg()` | SVG document string | full |
| `renderAnimation()` | animated WebP (lossless, default), APNG or GIF | full |

`renderAsDataUrl` returns `data:image/...;base64,...` for `png`, `jpeg`, `webp` and `ico` (not `raw`).
Continue with the [API reference](api.md).


## See also

The guide pages go deeper into each topic, with runnable examples and their rendered output:
[Concepts](concepts.md) · [Styles and layout](styles.md) · [HTML and Tailwind](html-and-tailwind.md) ·
[Fonts](fonts.md) · [Typography](typography.md) · [Images](images.md) · [Tables and floats](tables.md) ·
[Effects](effects.md) · [Output formats](formats.md) · [Animation](animation.md) · [measure()](measure.md) ·
[Charts](charts.md) · [Templates](templates.md) · [Performance](performance.md)
