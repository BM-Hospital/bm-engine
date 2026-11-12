# Getting started

[English](getting-started.md) · [Tiếng Việt](../vi/getting-started.md)

This page takes you from `npm install` to a rendered image in Node.js, in a browser (with or without a
bundler) and on edge runtimes, then covers the three decisions every project has to make: which build
profile to load, which fonts to register (bm-engine ships **no** font), and how images reach the
renderer. Every Node.js snippet on this page was executed against bm-engine 0.1.0 with package
resolution; snippets for runtimes that could not be run here are marked as such.

- [Install](#install)
- [Package entry points](#package-entry-points)
- [Node.js](#nodejs)
- [Browser without a bundler](#browser-without-a-bundler)
- [Bundlers (Vite, webpack, Rollup, esbuild, Next.js)](#bundlers)
- [Cloudflare Workers and other edge runtimes, Deno, Bun](#edge-runtimes-deno-bun)
- [Choosing a profile](#choosing-a-profile)
- [Fonts](#fonts)
- [Images](#images)
- [Output formats](#output-formats)

## Install

```sh
npm install bm-engine
```

The package has no dependencies and no install scripts. It contains four prebuilt WebAssembly
binaries (`core`, `standard`, `full` and `pdf`, which adds PDF output), the optional WOFF add-on, a dependency-free ESM wrapper and
TypeScript declarations. The package is ES modules only (see [CommonJS](#commonjs)).

It also lists eight **optional dependencies**, one per platform: `bm-engine-win32-x64-msvc`,
`bm-engine-linux-x64-gnu`, ... (table below). Each holds only the native Node-API build of the same engine
(about 1 MB compressed) and declares `os`, `cpu` and, on Linux, `libc`, so your package manager installs
the one that matches the machine and skips the others. Nothing is compiled or downloaded at install time or
at run time; there is no postinstall script.

### Native on Node.js, WebAssembly everywhere else

On Node.js, `import ... from "bm-engine"` uses the native addon when its platform package is installed and
loads, and otherwise falls back to the `full` WebAssembly binary **automatically and silently**. The API is
the same and the output is the same, byte for byte; natively the engine is faster and the async methods
(`render`, `renderSvg`, `measure`, `renderAnimation`, ...) run on the libuv thread pool instead of blocking
the event loop. Browsers, bundlers for the browser, workers and edge runtimes never see the native code.

```js
import { backend } from "bm-engine";
console.log(backend); // "native" or "wasm"
```

| To force | Use |
|:--|:--|
| WebAssembly on Node | `BM_ENGINE_BACKEND=wasm`, or import `bm-engine/full` (always wasm) |
| native, or fail loudly | `BM_ENGINE_BACKEND=native` (the import throws and says why), or import `bm-engine/native` |

Why the addon was not used is in the error of `BM_ENGINE_BACKEND=native node app.mjs`, for example
`bm-engine: BM_ENGINE_BACKEND=native, but the native addon is not available (bm-engine-linux-x64-gnu: not
installed)`.

| Platform package | `os` / `cpu` / `libc` | Status |
|:--|:--|:--|
| `bm-engine-win32-x64-msvc` | win32 / x64 | **executed**: byte identity with wasm on 250 fixtures, thread / memory / fuzz tests, install tests |
| `bm-engine-win32-arm64-msvc` | win32 / arm64 | built and structurally verified, **never executed** |
| `bm-engine-linux-x64-gnu` | linux / x64 / glibc 2.17+ | built and structurally verified, **never executed** |
| `bm-engine-linux-x64-musl` | linux / x64 / musl (Alpine) | built and structurally verified, **never executed** |
| `bm-engine-linux-arm64-gnu` | linux / arm64 / glibc 2.17+ | built and structurally verified, **never executed** |
| `bm-engine-linux-arm64-musl` | linux / arm64 / musl | built and structurally verified, **never executed** |
| `bm-engine-darwin-x64` | darwin / x64 (macOS 10.15+) | built and structurally verified, **never executed** |
| `bm-engine-darwin-arm64` | darwin / arm64 (macOS 11+) | built and structurally verified, **never executed** |

"Structurally verified" means the build script checked each binary without running it (format, CPU,
exported and imported symbols, glibc symbol versions, no math-library imports). Until a platform is
executed, rely on the fallback: if its addon does not load, `bm-engine` uses WebAssembly. The x64 builds
need an x86-64-v2 CPU (SSE4.2, 2009 onwards); older CPUs get WebAssembly. Node.js 18 or newer.

### Package managers, Docker, serverless

- **npm, pnpm, Yarn, Bun** honour `os` and `cpu` (only npm was tested here). `libc` (glibc or musl) is honoured by current npm
  (tested: npm 11) and, per their documentation, pnpm and Yarn 3.2+; a manager that ignores it may install both Linux variants of your
  architecture, which is harmless: `bm-engine` detects musl and loads the right one.
- **`npm install --omit=optional`** (`--no-optional`, Yarn `--ignore-optional`, ...) installs no platform
  package: you get WebAssembly (tested with npm).
- **Lockfiles created on another OS.** With npm 11 the lockfile written on Windows lists all eight packages
  with their `os` / `cpu` / `libc`, and `npm ci` for Linux x64 installs `bm-engine-linux-x64-gnu` (tested).
  Some older npm versions dropped the other platforms' optional packages from the lockfile when
  `node_modules` already existed (npm/cli#4828), the classic native-package pitfall. Here it is not fatal:
  the missing addon means WebAssembly, not an error. To repair, delete `node_modules` and the lockfile and
  install again, and check `backend` in CI.
- **Docker.** Run `npm ci` inside the image, on the image's platform; do not copy a `node_modules` built
  on your Windows or macOS host into a Linux image (you would get WebAssembly). Multi-arch builds
  (`docker buildx --platform linux/amd64,linux/arm64`) install the right package per architecture. Alpine
  images get the `-musl` package.
- **Installing for another machine** (e.g. building a Linux deployment on a Mac): npm can be told the
  target, and then needs all three flags (without `--libc` it installed neither Linux package on Windows):

  ```sh
  npm ci --os=linux --cpu=x64 --libc=glibc     # AWS Lambda x86_64, most Linux servers
  npm ci --os=linux --cpu=arm64 --libc=glibc   # Lambda arm64 (Graviton)
  npm ci --os=linux --cpu=x64 --libc=musl      # Alpine
  ```

  pnpm and Yarn use `supportedArchitectures` in their configuration instead.
- **Serverless (AWS Lambda, Vercel Functions, Netlify Functions, ...).** The binary is chosen when
  dependencies are installed, on the build machine: a platform that builds on Linux x64 (Vercel, Netlify,
  most CI) gets `bm-engine-linux-x64-gnu`; a zip of `node_modules` made on a Mac or on Windows carries the
  wrong one (WebAssembly at run time). Bundling deployers must also ship the platform package; see
  [Next.js](./frameworks/nextjs.md#native-addon-in-deployments) for `outputFileTracingIncludes`. Log
  `backend` once at startup to know what runs. None of these deployments was tested.
- **Bun, Deno, Electron** load the `node` entry and may load the addon; not tested. If it does not load,
  they get WebAssembly.

## Package entry points

| Import | Node.js (`node` condition) | Everywhere else (browsers, bundlers, workers, Deno) |
|:--|:--|:--|
| `bm-engine` | the native addon if installed, else the `full` binary, ready on import (`BM_ENGINE_BACKEND`, `BM_PROFILE`, `BM_WASM` override it) | wrapper only: call `init(wasm)` with the binary yourself |
| `bm-engine/native` | the native addon, or the import throws | not available |
| `bm-engine/full` | `full`, initialised on import | `await init()` locates `bm_engine.wasm` next to the module (or pass it) |
| `bm-engine/standard` | `standard`, initialised on import | `await init()` locates `bm_engine.standard.wasm` |
| `bm-engine/core` | `core`, initialised on import | `await init()` locates `bm_engine.core.wasm` |
| `bm-engine/pdf` | the native addon when installed, else the wasm `pdf` profile (= `full` + PDF output), initialised on import; see [PDF output](pdf.md) | `await init()` locates `bm_engine.pdf.wasm` |
| `bm-engine/woff` | `loadWoff()` / `decodeWoff()` — the WOFF add-on | same |
| `bm-engine/full.wasm`, `/standard.wasm`, `/core.wasm`, `/woff.wasm` (`bm-engine/wasm` = full) | the raw binaries, for bundler asset imports and Workers module imports; each also as `...wasm?module` for Next.js Edge | same |

Every entry exposes the same API (`init`, `initSync`, `Renderer`, `features`, `backend`, ...; the profile entries
also export `profile` and `wasmUrl()`). Each entry has **its own module instance**, so several profiles
can be loaded side by side in one process; within one entry the first successful `init` wins and later
calls return the same instance. `bm-engine` and `bm-engine/full` are separate instances too: importing
both on Node loads the full binary twice, so pick one.

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
  See [Troubleshooting](troubleshooting.md#containers-collapse-to-zero-height).

The `bm-engine` Node entry honours three environment variables: `BM_ENGINE_BACKEND=wasm|native` (see
[Install](#native-on-nodejs-webassembly-everywhere-else)), `BM_PROFILE=core|standard|full` selects one of
the packaged wasm binaries and `BM_WASM=/path/to/file.wasm` loads a custom build (both imply wasm). Prefer the explicit
subpaths (`bm-engine/core`, ...) in application code.

### CommonJS

bm-engine is published as ES modules. Because the Node entries have no top-level `await`, Node versions
with `require(esm)` support (22.12+, 20.19+) can load them from CommonJS:

```js
const { Renderer } = require("bm-engine");
```

This was verified on Node 26.13. On older Node versions use `const { Renderer } = await import("bm-engine")`.

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
  run, see [Benchmark](benchmark.md#browser)).
  The package test also loads Vite-built pages in headless Edge 157 (PNG rendered, no console errors).
  Loading straight from a CDN (`https://cdn.jsdelivr.net/npm/bm-engine@0.1.0/js/core.mjs`, then
  `await init()`) should work the same way once the package is published; it is untested until then.

## Bundlers

Import a profile entry and call `init()` without an argument. The entries locate their binary with
`new URL("./bm_engine.wasm", import.meta.url)`, a pattern Vite, webpack 5, Rollup and Parcel recognise
and emit as an asset:

```js
import { init, Renderer } from "bm-engine/full"; // or bm-engine/standard, bm-engine/core

await init();
const renderer = new Renderer();
```

If your bundler does not handle that pattern, import the binary's URL yourself and pass it:

```js
import { init, Renderer } from "bm-engine/full";
import wasmUrl from "bm-engine/full.wasm?url"; // Vite

await init(wasmUrl);
```

| Bundler | Notes | Tested |
|:--|:--|:--|
| Vite | `await init()` emits the `.wasm` as an asset; `?url` imports also work; no extra configuration | yes: Vite 8.3.8 build and dev server, pages run in headless Edge 157 |
| webpack 5 | `new URL(..., import.meta.url)` is emitted as an asset module by default | no |
| Rollup | needs an asset plugin that handles `new URL(..., import.meta.url)` (for example `@web/rollup-plugin-import-meta-assets`), or pass the URL yourself | no |
| esbuild | bundles cleanly (browser and `workerd` conditions) but does not copy `new URL()` assets: copy the `.wasm` file next to your bundle, or use `--loader:.wasm=file` and pass the imported URL to `init` | bundling only (esbuild 0.28) |

**Bundling a Node.js program** (esbuild `--platform=node`, Rollup, webpack with `target: "node"`). The
simplest is to keep the package out of the bundle: `esbuild app.mjs --bundle --platform=node
--external:bm-engine`, and ship `node_modules`. Bundled anyway, the `bm-engine` Node entry still works as
long as `node_modules/bm-engine` (and the platform package) exist at run time: it looks for its wasm file
next to itself, then through package resolution, then in `<cwd>/node_modules/bm-engine/js/`, and requires
the platform package at run time (no `--loader:.node` is needed: the `.node` file is never part of the
bundle). Tested with esbuild 0.28: ESM and CommonJS bundles ran natively; the CommonJS bundle copied to a
directory without `node_modules` failed at import with `bm-engine: cannot find bm_engine.wasm (...). This
happens when a bundler moved bm-engine's Node.js entry away from its package: keep the package external
...`, and worked with `BM_WASM=/path/to/bm_engine.wasm`.

Do **not** enable a bundler's WebAssembly-ESM integration for these files (`experiments.asyncWebAssembly`,
`vite-plugin-wasm`): bm-engine instantiates the module itself and expects a URL, bytes or a
`WebAssembly.Module`.

**Next.js.** In Route Handlers on the Node.js runtime, import `bm-engine` and read fonts with `fs` as in
the Node example. With Next.js 16.4.6 (Turbopack and webpack builders) this works without any
configuration under `next start`, natively when the platform package is installed. For self-contained
output (`output: "standalone"`, Vercel) add `serverExternalPackages: ["bm-engine"]` and
`outputFileTracingIncludes: { "/*": ["./node_modules/bm-engine-*/**"] }` so that the wasm files and the
platform package are copied; without them a webpack build fails at run time and a Turbopack build falls
back to wasm. On the Edge runtime, `import wasm from "bm-engine/core.wasm?module"` and
`initSync(wasm)` (from `bm-engine/core`). bm-engine has no `ImageResponse` helper; return
`new Response(png, { headers: { "content-type": "image/png" } })`. See [Next.js](./frameworks/nextjs.md)
for the full setup and exactly what was verified.

Verification status of this section: the Vite and esbuild rows were exercised by the package test
(`npm run test:pack`: `npm pack`, install the tarball, build, run in headless Edge); webpack and Rollup
were not tested; Next.js is covered on its [own page](./frameworks/nextjs.md).

## Edge runtimes, Deno, Bun

**Cloudflare Workers / workerd** compile `.wasm` imports ahead of time and hand you a
`WebAssembly.Module` (runtime compilation from bytes is not allowed there). Import the binary and pass it
to `init` or `initSync`:

```js
import { initSync, Renderer } from "bm-engine/full";
import wasm from "bm-engine/full.wasm"; // a WebAssembly.Module under wrangler

initSync(wasm);
let renderer; // reuse one renderer per isolate

export default {
  async fetch() {
    renderer ??= new Renderer(); // + registerFont(...) with font bytes from an asset / KV / fetch
    const png = renderer.renderSync({ type: "container", style: { width: "100%", height: "100%", backgroundColor: "#7c3aed" } },
                                    { width: 1200, height: 630 });
    return new Response(png, { headers: { "content-type": "image/png" } });
  },
};
```

What was tested: `initSync(new WebAssembly.Module(bytes))` was executed in Node, and the package test
resolves the entries with `node --conditions=workerd` and initialises them from a `WebAssembly.Module`;
the snippet was **not** run under wrangler / workerd. The compressed size of each profile (gzip -9: core 228.4 KiB,
standard 463.7 KiB, full 559.0 KiB) is what counts against the Workers script-size limit of your plan. The
WOFF add-on works the same way: `import woff from "bm-engine/woff.wasm"; await loadWoff(woff)`.

- **Bun**: the `node` condition applies, so `import { Renderer } from "bm-engine"` tries the native
  addon and otherwise loads the wasm binary with `node:fs`. Not tested.
- **Deno**: `import { Renderer } from "npm:bm-engine"` uses the same Node entry. Not tested.

## Choosing a profile

| Profile | wasm raw / brotli | Pick it when |
|:--|:--|:--|
| `core` | 487.6 / 194.3 KiB | Inputs are node trees with inline `style`, static TTF fonts and PNG/JPEG images (typical OG cards). |
| `standard` | 934.4 / 398.0 KiB | You need stylesheets (`css`), Tailwind (`tw`), HTML input, SVG images, WOFF2, variable or CFF fonts, effects (clip-path, masks, blend modes, backdrop-filter), modern colours, tables or floats. |
| `full` | 1 141.5 / 469.8 KiB | You also need bidi / complex scripts (Arabic, Hebrew, Indic, Thai), colour emoji, CSS animations / `renderAnimation`, `renderSvg`, lossy-WebP or animated image input, or ICO output. |

Details, and what a smaller profile does with input it cannot handle, are in
[Profiles and size](profiles-and-size.md). At runtime `features` tells you what the loaded binary has:

```js
import { features } from "bm-engine/standard";
features.css;         // true
features.complexText; // false (full only)
```

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
`text.normalize("NFC")` on user input to be safe. See [Troubleshooting](troubleshooting.md#vietnamese-text).

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
