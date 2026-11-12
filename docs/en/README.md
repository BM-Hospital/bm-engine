# bm-engine documentation

[English](README.md) · [Tiếng Việt](../vi/README.md)

User documentation for bm-engine 0.1.0, a Zig port of the takumi renderer. One package has two products:
**Image** (PNG, JPEG, WebP, SVG and animations; `bm-engine`) and **PDF** (paged documents;
`bm-engine/pdf`). Each has its own folder ([image/](image/index.md), [pdf/](pdf/index.md)); the pages that apply to both
are at the top of this folder. Start with [Getting started](getting-started.md), then the quick start of
your product.

## Package (both products)

| Page | What it covers |
|:--|:--|
| [Getting started](getting-started.md) | Install, native addon and WebAssembly, package entry points, CommonJS, bundlers, Workers / Deno / Bun, choosing a profile |
| [Native vs WebAssembly](native-vs-wasm.md) | Which Node.js backend you get, threading model, output identity, platform support, speed / memory / cold start compared with wasm and takumi |
| [Profiles and size](profiles-and-size.md) | What `core` / `standard` / `full` / `pdf` contain, sizes, per-feature cost, custom builds, the WOFF add-on |
| [Image, PDF and Paint compared](outputs-compared.md) | The three outputs of takumi and what bm-engine covers |
| [Benchmark](benchmark.md) | Speed, size, memory and pixel equivalence against takumi 2.20, and how to reproduce |
| [Troubleshooting](troubleshooting.md) | Missing text, collapsed containers, profile errors, images, wasm loading, memory, DPR, Vietnamese, emoji |
| [Building from source](building-from-source.md) | Zig toolchain, build / test / fuzz commands, repository layout, contributing |
| [Publishing (maintainers)](publishing.md) | Releasing the nine npm packages: one-time setup, release procedure, recovering from failures, prereleases and dist-tags, CI |

## Image

| Page | What it covers |
|:--|:--|
| [Image quick start](image/index.md) | A first render in Node.js and in a browser, fonts, images, output formats |
| [Concepts](image/concepts.md) · [Playground](image/playground.md) | The node model, sizes and units; the in-browser playground |
| [Styles](image/styles.md) · [HTML and Tailwind](image/html-and-tailwind.md) · [Fonts](image/fonts.md) · [Typography](image/typography.md) · [Images](image/images.md) · [Tables](image/tables.md) · [Charts](image/charts.md) · [Effects](image/effects.md) | Content, with runnable examples and their output |
| [Output formats](image/formats.md) · [Animation](image/animation.md) · [Performance](image/performance.md) | Rendering |
| [Frameworks](image/frameworks/index.md) | Next.js, Nuxt / Nitro, SvelteKit, Astro, TanStack Start, Hono / Express, Cloudflare Workers, Deno / Bun, Vite |
| [API reference](image/api.md) | `init`, `features`, `Renderer` and every method, node format, render options, errors, limits, memory model, WOFF add-on |
| [measure()](image/measure.md) · [CSS and feature support](image/css-support.md) · [Recipes](image/recipes.md) · [Templates](image/templates.md) | Reference |
| [From takumi](image/migration/from-takumi.md) · [From Satori](image/migration/from-satori.md) · [Differences from takumi](image/differences-from-takumi.md) | Migration |

## PDF

| Page | What it covers |
|:--|:--|
| [PDF quick start](pdf/index.md) | `bm-engine/pdf`, a first document in Node.js and in a browser, `measure`, the options |
| [Page size, margins and viewport](pdf/page-size-and-viewport.md) · [Native and WebAssembly](pdf/native-and-wasm.md) | Page geometry and one-page documents; backends and the `pdf` profile's size |
| [Pagination](pdf/pagination.md) · [Headers, footers and counters](pdf/headers-footers.md) · [Links, bookmarks, metadata, attachments](pdf/links-metadata.md) · [Fonts in PDF](pdf/fonts.md) · [Accessibility and archival](pdf/accessibility.md) | Guides |
| [Recipes](pdf/recipes.md) · [Serving PDFs from a framework](pdf/frameworks.md) | Invoice, report, ticket; HTTP handlers |
| [PDF API reference](pdf/api.md) · [CSS in PDF](pdf/css-support.md) · [Differences from takumi-pdf](pdf/differences-from-takumi.md) | Reference |

Developer documents (in the parent folder): [ARCHITECTURE.md](../ARCHITECTURE.md),
[TAKUMI_NOTES.md](../TAKUMI_NOTES.md), [CONVENTIONS.md](../CONVENTIONS.md),
[BENCHMARK.md](../BENCHMARK.md) (full benchmark report, Vietnamese), [RESULTS_FULL.md](../RESULTS_FULL.md).
