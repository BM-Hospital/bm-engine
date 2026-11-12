# bm-engine

[English](README.md) · [Tiếng Việt](README.vi.md)

Render node trees, HTML and Tailwind/CSS to PNG, JPEG, WebP, ICO, raw RGBA, SVG and animated WebP / APNG /
GIF with a dependency-free WebAssembly engine. bm-engine is a port of the Rust renderer
[takumi](https://github.com/kane50613/takumi) (2.20) to Zig 0.17: it accepts takumi's node format, render
options and API, and was checked against takumi fixture by fixture. It runs in Node.js, browsers,
bundlers, Bun, Deno and edge runtimes such as Cloudflare Workers, and ships in three build profiles so
you only load the features you use.

Documentation: [docs/en](docs/en/README.md) (on GitHub: `https://github.com/OWNER/bm-engine/tree/main/docs/en`).

## Highlights

Measured against `@takumi-rs/wasm` 2.20.0 on 200 shared fixtures (Node 26, i3-10100; details in
[docs/en/benchmark.md](docs/en/benchmark.md)):

- **Small**: `core` 454.5 KiB, `standard` 877.5 KiB, `full` 1 099.8 KiB of wasm (180 / 375 / 453 KiB
  brotli), against 4 234.9 KiB for takumi — 9.3× / 4.8× / 3.9× smaller. The module has **no imports**
  (no WASI, no wasm-bindgen glue) and the JS wrapper has no dependencies.
- **Same output**: 74 fixtures byte-identical, 126 equivalent (SSIM ≥ 0.99, differences at
  anti-aliased edges), 0 close, 0 different, 0 errors. `measure()` layouts match takumi to 0.001 px
  (197/197 non-transform cases).
- **Fast**: PNG rendering 0.49× takumi's time (geometric mean; faster in 191/191 cases), raw RGBA
  0.68× (faster in 171/191); cold start (init + font + first PNG) 71 ms vs 178 ms; PNG files 22 %
  smaller.
- **Synchronous or async**: every method has a `*Sync` twin; `init` / `initSync` accept bytes, URLs,
  `Response`s or a precompiled `WebAssembly.Module`.

Where it still loses: wasm linear memory is **9 % larger** than takumi's after 50 renders (11.6 vs
10.6 MiB); raw rendering is slower in the `border-radius` group (1.20×), `text-stroke` (1.61×),
`svg-image` (1.46×) and `text-decoration` (1.10×). See [Status](#status-and-limitations).

## Install

```sh
npm install bm-engine
```

## Quick start (Node.js)

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // Node: the full profile, initialised on import

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

## Profiles

| Profile | Import | wasm (raw / brotli) | Adds |
|:--|:--|--:|:--|
| `core` | `bm-engine/core` | 454.5 / 180.3 KiB | node trees + inline styles, `var()` / `calc()`, block / inline / flex / grid / absolute layout, static TTF fonts with OpenType shaping, all border styles, gradients, shadows, filters, 2D transforms, PNG / JPEG input, PNG / JPEG / WebP / raw output |
| `standard` | `bm-engine/standard` | 877.5 / 374.5 KiB | + stylesheets and selectors, Tailwind, HTML input, SVG images, WOFF / WOFF2, variable and CFF fonts, clip-path / masks / blend modes / backdrop-filter, oklch / lab / color-mix, tables, floats, WebP / GIF input, `text-wrap: balance` |
| `full` | `bm-engine` (Node), `bm-engine/full` | 1 099.8 / 453.4 KiB | + bidi and complex scripts, colour emoji, CSS animations and `renderAnimation`, `renderSvg`, lossy WebP and animated images, ICO output |

An 84 KiB add-on (`bm-engine/woff`) gives `core` WOFF / WOFF2 support. `features` tells you what the
loaded binary contains. Details: [Profiles and size](docs/en/profiles-and-size.md).

## Documentation

- [Getting started](docs/en/getting-started.md): install, Node / browser / bundlers / Workers, profiles, fonts, images, formats
- [API reference](docs/en/api.md): `init`, `Renderer`, node format, options, errors, limits, memory
- [CSS and feature support](docs/en/css-support.md): the feature matrix and every supported property
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
- **No JSX, no `ImageResponse`, no PDF, no native binding.** Convert JSX with `@takumi-rs/helpers`.
- **Inline layout is complete for common content** (text flows around floats; atomic inlines and inline
  span padding take part in line breaking). Remaining gaps: RTL inline boxes around LTR text, line-clamp
  around floats, block-in-inline, approximate float paint order, `text-wrap: balance` beside floats or
  atomic inlines, percentage padding on inline boxes (see [CSS support → Known gaps](docs/en/css-support.md#known-gaps)).
- Not supported: `display: contents`, list markers / counters, `writing-mode`, 3D transforms,
  `clip-path: url()`, relative colour syntax, Tailwind `animate-*` and interactive variants (as in
  takumi), `<text>` inside SVG images and some SVG filters.
- Known differences: `direction: rtl` does not reverse flex rows; `image-rendering: pixelated` is
  ignored on raster images; `measure()` text runs carry no `text` field.
- Single-threaded and synchronous inside one instance; WebAssembly memory grows but never shrinks.

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
