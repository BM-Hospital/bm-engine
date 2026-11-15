# bm-engine documentation

bm-engine is a Zig library that turns node trees or HTML + CSS into images and PDF documents. It uses a native addon on Node.js when available and WebAssembly in browsers and other runtimes.

## Where to start

1. [Install](getting-started.md) the package and choose your runtime.
2. Create your [first image](image/index.md) or [first PDF](pdf/index.md).
3. Change an example in the [Image Playground](image/playground.md) or [PDF Playground](pdf/playground.md).

## Choose an output

| Your task | Guide |
|:--|:--|
| Social cards, thumbnails, banners | [Images](image/index.md) |
| Multi-page invoices, reports, tickets | [PDF](pdf/index.md) |
| Choose PNG, JPEG, WebP, SVG or PDF | [Choosing an output](outputs-compared.md) |
| Reduce the WebAssembly download | [Profiles and size](profiles-and-size.md) |
| Understand backends and parallel rendering | [Native and WebAssembly](native-vs-wasm.md) |

## Find a guide

| Topic | Guides |
|:--|:--|
| Image content and layout | [Concepts](image/concepts.md), [styles and layout](image/styles.md), [HTML and Tailwind](image/html-and-tailwind.md) |
| Text and images | [Fonts](image/fonts.md), [typography](image/typography.md), [images](image/images.md) |
| Application integration | [Frameworks](image/frameworks/index.md), [integration checklist](image/migration/checklist.md) |
| Multi-page documents | [Pagination](pdf/pagination.md), [headers and footers](pdf/headers-footers.md), [PDF fonts](pdf/fonts.md) |
| Reference | [Image API](image/api.md), [image CSS](image/css-support.md), [PDF API](pdf/api.md), [PDF CSS](pdf/css-support.md) |
| Unexpected results | [Troubleshooting](troubleshooting.md), [image limitations](image/limitations.md), [PDF limitations](pdf/limitations.md) |
| Measurements and comparisons | [Benchmark](benchmark.md) |
| Library development | [Building from source](building-from-source.md), [publishing](publishing.md) |
