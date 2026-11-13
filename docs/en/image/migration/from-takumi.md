# Migrating from takumi

[English](from-takumi.md) · [Tiếng Việt](../../../vi/image/migration/from-takumi.md)

bm-engine re-implements the renderer of takumi 2.20 (`@takumi-rs/wasm`) in Zig: the node format, the
render options and the `Renderer` methods are the same, so most migrations are an import change, a font
registration and a `Response` wrapper. This page maps every takumi package to its bm-engine equivalent
(or says plainly that there is none), lists the option names, and ends with a checklist. The rendering
differences that remain are in [Differences from takumi](../differences-from-takumi.md).

::: info Verification status
The bm-engine side of every mapping was checked against `js/index.d.mts` and executed on Node 26.13
(see the framework examples in `docs/examples/frameworks/`). takumi's side is taken from the takumi
2.20 sources and documentation in the repository's reference copy; **no takumi code was executed**, so
statements about takumi's behaviour are as documented by takumi.
:::

## Package mapping

| takumi package / import | What it is | bm-engine |
|:--|:--|:--|
| `@takumi-rs/wasm` | WebAssembly renderer (`init`, `Renderer`) | `bm-engine` (same `init` / `Renderer` API), or a profile entry `bm-engine/core` · `/standard` · `/full` |
| `@takumi-rs/wasm/node`, `@takumi-rs/wasm/auto` | auto-initialised on Node | `bm-engine` (or a profile entry) on Node: initialised on import |
| `@takumi-rs/wasm/no-bundler` | wasm-bindgen glue for plain browsers | a profile entry + `await init()`; there is no glue to load |
| `@takumi-rs/wasm/takumi_wasm_bg.wasm`, `@takumi-rs/wasm/wasm-url` | the binary / its URL | `bm-engine/wasm` (= `full.wasm`), `bm-engine/core.wasm`, `/standard.wasm`, `/full.wasm`; in Vite `bm-engine/<profile>.wasm?url` |
| `@takumi-rs/wasm/next`, `@takumi-rs/wasm/vite` | framework-specific entries | none; see [Next.js](../frameworks/nextjs.md) and [Vite](../frameworks/vite-browser.md) |
| `@takumi-rs/core` | native N-API binding (multi-threaded, off the event loop) | **not available** — bm-engine is WebAssembly only. For parallelism use a [worker_threads pool](../recipes.md#worker-threads-pool). |
| `takumi-js` | high-level `render(jsx)`, `renderSvg`, `measure`, `renderAnimation` | `new Renderer()` + `renderer.render(node, options)` etc.; JSX must be converted first ([JSX](#jsx)) |
| `takumi-js/response`, `@takumi-rs/image-response` | `ImageResponse` (a `Response` subclass) | **not available**; use the 30-line [`imageResponse()` helper](../frameworks/index.md#an-imageresponse-helper) or `new Response(bytes, { headers })` |
| `takumi-js/helpers`, `@takumi-rs/helpers` | `fromJsx`, `fromHtml`, `container` / `text` / `image` builders, `googleFonts`, emoji loaders | not part of bm-engine. The builders return plain node objects in the shared format; bm-engine also takes HTML strings directly. See below. |
| `takumi-pdf` | PDF output | `bm-engine/pdf` (`PdfRenderer`, `render`, `measure`, `prepare`, `PageNumber`, `TotalPages`, `TargetPageNumber`); see [PDF](#pdf) |
| `takumi-paint` | paint-tree output | **not available** ([Image, PDF and Paint compared](../../outputs-compared.md)) |

## Initialisation

| takumi | bm-engine |
|:--|:--|
| `import init, { Renderer } from "@takumi-rs/wasm"; await init({ module_or_path: wasmUrl })` | `import { init, Renderer } from "bm-engine/full"; await init()` — or keep `init({ module_or_path: url })`, which bm-engine accepts too |
| `initSync({ module })` | `initSync(module)` or `initSync({ module })` |
| Workers: `import wasm from "@takumi-rs/wasm/takumi_wasm_bg.wasm"` | `import wasm from "bm-engine/full.wasm"` (or `core.wasm` / `standard.wasm` with the matching entry) |
| `default` export is `init` | same (`import init from "bm-engine/full"`) |

`init` returns the raw wasm exports in both; nothing in a normal application uses them.

## Renderer methods

| Method | Status in bm-engine 0.1.0 |
|:--|:--|
| `new Renderer({ cacheMaxBytes, fontCacheMaxBytes })` | accepted; both options ignored (fixed 96 MiB image / 8 MiB glyph budgets) |
| `registerFont` / `loadFont` | same; **synchronous** for bytes and `{ data: bytes }`, a `Promise` for URLs and lazy data |
| `unregisterFont`, `clearFonts` | same; `clearFonts()` leaves no font at all (takumi keeps its built-in Geist) |
| `render`, `renderAsDataUrl`, `renderSvg`, `measure`, `renderAnimation` | same; each also has a `*Sync` twin |
| `prepare`, `prepareAnimation` | same shape, but **fetch nothing** (no `needs` pass for remote images / `@font-face`) |
| `cacheFont`, `cachedFonts`, `cacheFontFile`, `needs`, `animationNeeds` | not provided |
| `free`, `[Symbol.dispose]` | same |
| — | `memoryBytes()`, `features`, `profile`, `wasmUrl()` are bm-engine additions |

## Render options

| Option | bm-engine |
|:--|:--|
| `width`, `height`, `format`, `quality`, `devicePixelRatio` | same meaning; `quality` applies to JPEG only (WebP output is always lossless, as in takumi's wasm build) |
| `images` (`[{ src, data }]` or `{ sources }`) | same; lazy `data()` with the async API; URLs are lookup keys only, never fetched |
| `css`, `stylesheets`, `keyframes` | same (`css` needs `standard` / `full`) |
| `fontFamilies`, `lang`, `timeMs`, `signal` | same; `signal` is checked before rendering |
| `fonts` | same (async API) |
| `lossless`, `dithering`, `drawDebugBorder` | accepted and ignored |
| `emoji` (takumi-js / `ImageResponse`) | not available: register a colour emoji font instead (`full` profile) |
| `jsx`, `renderer`, `headers`, `status`, `onError` (`ImageResponse`) | belong to `ImageResponse`; the helper supports `headers`, `status`, `onError` |

## Node format compatibility

Node trees are interchangeable: `{ type: "container" | "text" | "image", style, preset, tw, tagName,
className, id, attributes, dir, lang, children / text / src }`, camelCase style keys, numbers as px,
`{ json }` for JSON text, every JS string treated as HTML. Defaults follow takumi (`display: inline`,
`box-sizing: border-box`, transparent canvas). A tree serialised from takumi renders unchanged; the
benchmark compares 250 fixtures between the two engines (see [Benchmark](../../benchmark.md)).

What bm-engine accepts that only matters when it is missing: features compiled out of a smaller profile
(HTML, `css`, `tw`, SVG images, WOFF2, ...) throw or are ignored — use the `full` profile while migrating,
then shrink ([Profiles and size](../../profiles-and-size.md)).

## JSX

bm-engine has no JSX runtime. Three ways to keep JSX templates:

1. **Keep `@takumi-rs/helpers`** for conversion: `const { node, css } = await fromJsx(<Card />)`, then
   `renderer.render(node, { css, width, height })`. `fromJsx` is async and returns `{ node, css }` per the
   takumi sources; it produces takumi's node format, which bm-engine reads. Earlier bm-engine testing
   used a hand-built React element, not React itself (see
   [Differences from takumi](../differences-from-takumi.md#migration-in-five-steps)); the `css` it returns
   needs the `standard` or `full` profile.
2. **Use the tiny [`h()` factory](../frameworks/index.md#node-trees-without-jsx)** as the JSX factory of
   your template files (verified with esbuild). No hooks, no UA styles.
3. **Render JSX to HTML** with your framework's server renderer and pass the string (needs `standard` or
   `full`).

takumi's `container()`, `text()`, `image()` builders from `@takumi-rs/helpers` return plain node objects
in the same format, so trees built with them should render as is (not tested).

## PDF

`takumi-pdf` maps to `bm-engine/pdf` ([PDF output](../../pdf/index.md)). The option names and shapes are takumi-pdf's
(`size`, `landscape`, `margin`, `header`, `footer`, `pages`, `pageRanges`, `viewport`, `metadata`, `outline`,
`pdfa`, `tagged`, `attachments`, `uncoveredText`, ...), and so are most validation messages.
What to change when you move code over:

- Import `PdfRenderer` from `bm-engine/pdf` instead of `takumi-pdf`; there is no JSX, so `PageNumber()`,
  `TotalPages()` and `TargetPageNumber()` return node objects (a `span` with the class hook), and `header` /
  `footer` are HTML strings or node trees.
- `prepare` and `render` fetch nothing and there is no `needs`: pass image bytes in `images` and fonts through
  `registerFont` or `fonts`. bm-engine ships no font.
- Registered fonts must cover every character, or the render fails (`uncoveredText: "error"`, as in takumi-pdf).
- Known differences: PDF/A is checked but not certified, and `list-style-image` is not supported
  ([Known limitations](../../pdf/differences-from-takumi.md#known-limitations)).

`takumi-paint` has no counterpart ([Image, PDF and Paint compared](../../outputs-compared.md)).

## Output differences to expect

Pixels match takumi on most fixtures and differ by anti-aliasing noise elsewhere. The cases worth a
visual check after migrating are listed in
[Differences from takumi → Rendering differences](../differences-from-takumi.md#rendering-differences):
gradients, dashed rounded borders, rotated text, `-webkit-text-stroke`, `©️` emoji presentation, SVG
`<text>`, and the cases where bm-engine deliberately follows Chrome (`display: contents`, percentage
margin / padding on inline boxes, `text-indent` after a block child). Encoded files are different bytes
(different encoders) even when pixels match — compare decoded pixels, not file hashes.

## Checklist

- Replace the import (`@takumi-rs/wasm` → `bm-engine/<profile>`); start with `full`.
- Keep `init()` (browsers, bundlers) or drop it (Node); on Workers import `bm-engine/<profile>.wasm`.
- Register every font you use — there is no built-in Geist. Text without a font is silently not drawn.
- Replace `ImageResponse` with `new Response(bytes, { headers })` or the `imageResponse()` helper; set
  `content-type` yourself.
- Replace `emoji: "twemoji"` (etc.) with a registered colour emoji font on `full`.
- Fetch remote images yourself and pass them as `images` (takumi's `prepare` fetched them).
- Replace `@font-face` URLs in stylesheets with `registerFont` calls.
- Remove `@takumi-rs/core` from `serverExternalPackages` and add `bm-engine` (Next.js).
- Remove reliance on `cacheFont` / `needs`; drop cache-size options (they are ignored).
- If you used the native binding for parallelism, add a worker pool.
- Visually compare a sample of outputs; then try `standard` or `core` and check `features`.
