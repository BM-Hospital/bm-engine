# bm-engine

[English](README.md) · [Tiếng Việt](README.vi.md)

Render node trees, HTML and Tailwind/CSS to PNG, JPEG, WebP, ICO, raw RGBA, SVG, animated WebP / APNG /
GIF and paged PDF with a dependency-free WebAssembly engine. bm-engine is a port of the Rust renderer
[takumi](https://github.com/kane50613/takumi) (2.20) to Zig 0.17: it accepts takumi's node format, render
options and API, and was checked against takumi fixture by fixture. It runs in Node.js, browsers,
bundlers, Bun, Deno and edge runtimes such as Cloudflare Workers, and ships in three build profiles (plus a
`pdf` profile for PDF output) so you only load the features you use.

Documentation: [docs/en](docs/en/README.md) (on GitHub: `https://github.com/OWNER/bm-engine/tree/main/docs/en`).

## Highlights

Measured against `@takumi-rs/wasm` 2.20.0 on 250 shared fixtures (Node 26, i3-10100; details in
[docs/en/benchmark.md](docs/en/benchmark.md)):

- **Small**: `core` 487.6 KiB, `standard` 934.4 KiB, `full` 1 141.5 KiB of wasm (194 / 398 / 470 KiB
  brotli), against 4 234.9 KiB for takumi — 8.7× / 4.5× / 3.7× smaller. The module has **no imports**
  (no WASI, no wasm-bindgen glue) and the JS wrapper has no dependencies.
- **Same output**: 81 fixtures byte-identical, 169 equivalent (SSIM ≥ 0.99, differences at
  anti-aliased edges), 0 close, 0 different, 0 errors. `measure()` layouts match takumi to 0.001 px
  (246/247 non-transform cases).
- **Fast**: PNG rendering 0.45× takumi's time (geometric mean; faster in 248/250 cases), raw RGBA
  0.63× (faster in 229/250); cold start (init + font + first PNG) 78 ms vs 194 ms; PNG files 20 %
  smaller.
- **Synchronous or async**: every method has a `*Sync` twin; `init` / `initSync` accept bytes, URLs,
  `Response`s or a precompiled `WebAssembly.Module`.

Where it still loses: wasm linear memory is **9 % larger** than takumi's after 50 renders (11.6 vs
10.6 MiB); raw rendering is slower in the `border-radius` group (1.20×), `text-stroke` (1.58×),
`svg-image` (1.48×) and `text-decoration` (1.12×). See [Status](#status-and-limitations).

## Install

```sh
npm install bm-engine
```

### Native on Node.js, wasm everywhere else

On Node.js the same package also runs as a **native Node-API addon**: `npm install bm-engine` pulls in the
one optional platform package that matches the machine (`bm-engine-linux-x64-gnu`, `bm-engine-darwin-arm64`,
...; no compiler, no install script), and `import ... from "bm-engine"` uses it, with the same API and
byte-identical output, faster, and with `render()` & co. running on the libuv thread pool. If the addon is
missing or does not load, `bm-engine` falls back to WebAssembly silently. Browsers, workers and edge
runtimes always use WebAssembly. Check with `import { backend } from "bm-engine"`; force with
`BM_ENGINE_BACKEND=wasm|native`.

| Platform package | Status |
|:--|:--|
| `win32-x64-msvc` | executed: byte identity with wasm on 250 fixtures, threading, memory, fuzz and install tests |
| `win32-arm64-msvc`, `linux-x64-gnu`, `linux-x64-musl`, `linux-arm64-gnu`, `linux-arm64-musl`, `darwin-x64`, `darwin-arm64` | cross-compiled and structurally verified, **never executed** yet (wasm fallback if they do not load) |

Details: [Getting started → Install](docs/en/getting-started.md#install) (package managers, Docker,
serverless, lockfiles), [docs/NATIVE.md](docs/NATIVE.md) (design), [Publishing](docs/en/publishing.md)
(maintainers).

## Quick start (Node.js)

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // Node: native addon or the full wasm profile, ready on import

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") }); // no font is bundled

const png = renderer.renderSync(
  {
    type: "container",
    style: {
      display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
      backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)",
    },
    children: [{ type: "text", text: "Hello from bm-engine", style: { fontFamily: "Inter", fontSize: 64, color: "white" } }],
  },
  { width: 1200, height: 630 }, // format: "png" (default) | "jpeg" | "webp" | "raw" | "ico"
);
writeFileSync("og.png", png);
```

HTML and stylesheets work too (`standard` and `full` profiles):
`renderer.renderSync("<div style='display:flex;...'>Hi</div>", { width: 1200, height: 630, css: [".x { ... }"] })`.

## Quick start (browser)

```js
import { init, Renderer } from "bm-engine/full"; // or bm-engine/standard, bm-engine/core

await init(); // fetches bm_engine.wasm next to the module (bundlers emit it as an asset)
const renderer = new Renderer();
renderer.registerFont(await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer());
const png = await renderer.render(node, { width: 1200, height: 630 });
document.querySelector("img").src = URL.createObjectURL(new Blob([png], { type: "image/png" }));
```

On Cloudflare Workers import the binary as a module and pass it: `import wasm from "bm-engine/full.wasm";
initSync(wasm)`. See [Getting started](docs/en/getting-started.md) for bundlers, Workers, Deno and Bun.

## Quick start (PDF)

```js
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf"; // the pdf profile: full + PDF output

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const bytes = await pdf.render(
  `<h1 style="font-family: Inter">Quarterly report</h1><p style="font-family: Inter">Selectable text.</p>`,
  { size: "a4", margin: 36, footer: `<span style="font: 10px Inter">Page <span class="pageNumber"></span></span>` },
);
writeFileSync("report.pdf", bytes);
```

Content flows across pages; headers, footers, page counters, links, bookmarks, metadata, attachments, tagged
PDF (PDF/UA) and PDF/A are supported. See [PDF output](docs/en/pdf.md). On Node.js `bm-engine/pdf` uses the native
addon when it is installed (same bytes, faster, async off the main thread) and the wasm `pdf` profile otherwise.

## Profiles

| Profile | Import | wasm (raw / brotli) | Adds |
|:--|:--|--:|:--|
| `core` | `bm-engine/core` | 487.6 / 194.3 KiB | node trees + inline styles, `var()` / `calc()`, block / inline / flex / grid / absolute layout, static TTF fonts with OpenType shaping, all border styles, gradients, shadows, filters, 2D transforms, PNG / JPEG input, PNG / JPEG / WebP / raw output |
| `standard` | `bm-engine/standard` | 934.4 / 398.0 KiB | + stylesheets and selectors, Tailwind, HTML input, SVG images, WOFF / WOFF2, variable and CFF fonts, clip-path / masks / blend modes / backdrop-filter, oklch / lab / color-mix, tables, floats, WebP / GIF input, `text-wrap: balance` |
| `full` | `bm-engine` (Node), `bm-engine/full` | 1 141.5 / 469.8 KiB | + bidi and complex scripts, colour emoji, CSS animations and `renderAnimation`, `renderSvg`, lossy WebP and animated images, ICO output |
| `pdf` | `bm-engine/pdf` | about 1.5 MB raw | `full` + PDF output: pagination, headers / footers, links, bookmarks, metadata, attachments, tagged PDF, PDF/A. See [PDF output](docs/en/pdf.md) |

An 84 KiB add-on (`bm-engine/woff`) gives `core` WOFF / WOFF2 support. `features` tells you what the
loaded binary contains. Details: [Profiles and size](docs/en/profiles-and-size.md).

## Documentation

- [Getting started](docs/en/getting-started.md): install, Node / browser / bundlers / Workers, profiles, fonts, images, formats
- [API reference](docs/en/api.md): `init`, `Renderer`, node format, options, errors, limits, memory
- [CSS and feature support](docs/en/css-support.md): the feature matrix and every supported property
- [PDF output](docs/en/pdf.md): pages, [pagination](docs/en/pdf-pagination.md), [headers and footers](docs/en/pdf-headers-footers.md), [links and metadata](docs/en/pdf-links-metadata.md), [fonts](docs/en/pdf-fonts.md), [PDF/UA and PDF/A](docs/en/pdf-accessibility.md)
- [Profiles and size](docs/en/profiles-and-size.md) · [Differences from takumi / migration](docs/en/differences-from-takumi.md)
- [Benchmark](docs/en/benchmark.md) · [Building from source](docs/en/building-from-source.md) · [Playground](docs/en/playground.md) · [Troubleshooting](docs/en/troubleshooting.md)
- Developer docs: [ARCHITECTURE](docs/ARCHITECTURE.md), [TAKUMI_NOTES](docs/TAKUMI_NOTES.md), [CONVENTIONS](docs/CONVENTIONS.md), [BENCHMARK (full report, Vietnamese)](docs/BENCHMARK.md)

The documentation is also a VitePress site with the browser **playground** built in (templates, all three
profiles, every output format): `npm run docs` in a repository checkout, then open `http://localhost:5173/`
(playground: `/playground`). The playground alone: `npm run playground`, then
`http://127.0.0.1:8080/docs/playground-app/`; see [docs/en/playground.md](docs/en/playground.md).

## Status and limitations

Version 0.1.0. What to know before adopting it:

- **No bundled font.** takumi ships Geist; bm-engine draws no text until you register a font.
- **No network access.** Remote images and `@font-face` URLs are never fetched (`prepare()` does not
  fetch either); pass bytes through `images` and `registerFont`.
- **No JSX, no `ImageResponse`.** Convert JSX with `@takumi-rs/helpers`.
- **PDF is a separate entry** (`bm-engine/pdf`: the wasm `pdf` profile, about 1.5 MB raw, or the native addon on Node.js) and a port of `takumi-pdf` with known
  differences: content is laid out once at one width (a named page of another width is not re-flowed), `list-style-image` is not supported, PDF/A is checked but not certified, and there is no `needs`
  pass (see [PDF output → Known limitations](docs/en/pdf.md#known-limitations)).
- **Inline layout is complete for common content** (text flows around floats; block-in-inline, RTL
  inline boxes, atomic inlines and inline span padding take part in line breaking). Remaining gaps: RTL +
  `pre-wrap` hanging spaces, line-clamp around floats, a block inside a relatively positioned inline box
  (see [CSS support → Known gaps](docs/en/css-support.md#known-gaps)).
- Not supported: list markers / counters, `writing-mode`, 3D transforms, `clip-path: url()`, relative
  colour syntax, Tailwind interactive variants and `space-*` (as in takumi), `<text>` inside SVG images and
  some SVG filters.
- Known differences: `display: contents`, percentage margin / padding on inline boxes and `text-indent`
  after a block child follow Chrome rather than takumi; `measure()` text runs carry no `text` field.
- WebAssembly: single-threaded and synchronous inside one instance; memory grows but never shrinks. Native
  (Node.js): one renderer runs one call at a time, several renderers run in parallel; only the Windows x64
  addon has been executed so far.

Full list: [CSS support → Known gaps](docs/en/css-support.md#known-gaps) and
[Differences from takumi](docs/en/differences-from-takumi.md).

## License and attribution

bm-engine is licensed under either of the [MIT License](LICENSE-MIT) or the
[Apache License 2.0](LICENSE-APACHE), at your option — the same terms as takumi.

bm-engine is a derivative work of **takumi** by Kane Wang (MIT OR Apache-2.0): large parts are
transliterations of takumi's Rust code (layout, painting, text, CSS, Tailwind, HTML, SVG, animation,
codecs), and its behaviour was verified against takumi's own output. All credit for the design of the
renderer goes to the takumi project. takumi in turn follows Chromium's Blink and Skia; bm-engine also
ports algorithms and data from tiny-skia, HarfBuzz, libwebp, libjpeg, Unicode / ICU, Brotli and others.
See [NOTICE](NOTICE) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the attributions.
