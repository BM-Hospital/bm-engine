# Native and WebAssembly

[English](native-and-wasm.md) · [Tiếng Việt](../../vi/pdf/native-and-wasm.md)

`bm-engine/pdf` runs on two engines with one API: the native Node-API addon on Node.js (when the platform
package is installed) and the WebAssembly binary `bm_engine.pdf.wasm` everywhere else and as the automatic
fallback. Both write **the same bytes** for the same input. This page covers which one you get, how to
check and force it, the size of the `pdf` binary, and what the other builds do with `renderPdf`. The
snippets are sections of `docs/examples/pdf-native-and-wasm.mjs` and `docs/examples/pdf.mjs`, which run
them; the comparison of the two backends was run on Windows x64 (Node.js 26), the only platform whose addon
has been executed (see [Getting started](../getting-started.md#native-on-nodejs-webassembly-everywhere-else)).

- [Native backend on Node.js](#native-backend-on-nodejs)
- [Same bytes on both backends](#same-bytes-on-both-backends)
- [The `pdf` profile and its size](#the-pdf-profile-and-its-size)
- [What the other profiles do](#what-the-other-profiles-do)

## Native backend on Node.js

On Node.js, Bun and Deno, `bm-engine/pdf` runs on the native Node-API addon when it is installed (the same
addon and the same optional `bm-engine-<platform>` package that `bm-engine` uses; there is no extra package),
and otherwise falls back, silently, to the wasm `pdf` profile. `backend`, exported from `bm-engine/pdf`, is
`"native"` or `"wasm"`, and `BM_ENGINE_BACKEND=wasm|native` forces one. The PDF bytes are identical on both
backends. Natively, the async methods (`PdfRenderer.render` and `measure`, `Renderer.renderPdf` and
`measurePdf`) run on the libuv thread pool instead of blocking the event loop; `init()` and `initSync()` do
nothing there, and `profile` is still `"pdf"`. In browsers, bundlers, Workers and edge runtimes nothing
changes: the entry is the wasm `pdf` profile. See [Native addon vs WebAssembly](../native-vs-wasm.md).

## Same bytes on both backends

`backend`, `profile` and `features` tell you what serves the entry:

<!-- @example pdf-native-and-wasm#backend -->
```js
const { backend, profile, features, PdfRenderer } = await import("bm-engine/pdf");
console.log(backend, profile, features.pdf); // "native" pdf true  (or "wasm" pdf true without the addon)
```

The example script renders this document once with `BM_ENGINE_BACKEND=wasm` and once with
`BM_ENGINE_BACKEND=native`, each in its own process (the backend is chosen when the module is imported),
and checks that the two files have the same SHA-256:

<!-- @example pdf-native-and-wasm#same-bytes -->
```js
const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const bytes = await pdf.render(
  `<h1 style="font-family: Inter">Same bytes</h1><p style="font-family: Inter">on every backend</p>`,
);
// no date is written unless you pass one, so the same input gives the same bytes on every run and backend
```

In the run for this page both files were 8 943 bytes with the same hash. bm-engine writes no date and no
random file identifier unless you pass them (`metadata.creationDate`, ...), so the output is also the same
from one run to the next, which makes PDFs easy to cache and to compare in tests.

## The `pdf` profile and its size

`bm_engine.pdf.wasm` is `full` plus the PDF writer: 1 555.8 KiB raw, 761.6 KiB with gzip -9 and
625.1 KiB with brotli -11, about 0.4 MB more than `bm_engine.wasm` (`full`: 1 141.5 / 559.0 / 469.8 KiB). The PDF code is compiled only into this binary and into the native addon, and so are the paged
layout and the CSS paged-media properties it needs. (The native addon is the `full` feature set plus PDF
output; `bm-engine` itself never exposes the PDF writer.) [Profiles and size](../profiles-and-size.md) has the
exact numbers for every binary. Build it yourself with `npm run build:pdf`
(`node scripts/build.mjs --profile=pdf`) or `zig build -Dprofile=pdf`
([Building from source](../building-from-source.md)).

Because the pagination code is only in this profile, the CSS properties `break-before`, `break-after`,
`break-inside`, `page-break-*`, `orphans` and `widows`, and the Tailwind `break-before-*`,
`break-inside-*` and `break-after-*` utilities, apply only to PDF output (`bm-engine/pdf`). Image renders
(`render`, `renderSvg`, `measure`) accept and ignore them on every build, including `bm-engine/pdf` and the native
addon, so an image is the same on every build. `background-clip: border-area` follows the same rule.

## What the other profiles do

Every `Renderer` has `renderPdf`, `renderPdfSync`, `measurePdf` and `measurePdfSync`, but only the
`pdf` build exposes a PDF writer. On any other build they throw, and that includes `bm-engine` running on the
native addon (the addon binary contains the PDF writer, but `bm-engine` hides it: `features.pdf` is `false`):

<!-- @example pdf#not-supported -->
```js
import { Renderer } from "bm-engine/full"; // the full profile has no PDF writer
let message;
try {
  new Renderer().renderPdfSync(card);
} catch (e) {
  message = e.message;
}
// message: bm-engine: renderPdf is not supported by this build (use the pdf build: import from "bm-engine/pdf")
```

Check `features.pdf` before you call them if your build can vary.

In a browser or a Worker, only this binary is downloaded for PDF output: import `bm-engine/pdf` and nothing
else from bm-engine, since every other entry has its own module instance and binary
([PDF quick start → In a browser](index.md#in-a-browser-and-on-edge-runtimes)).

## Performance and validation

Measured by `node bench/pdf/bench.mjs` against takumi-pdf on the same machine and inputs (tables generated from
[results-pdf.json](../../results-pdf.json); the full report is in [Benchmark](../benchmark.md)). bm-native and bm-wasm
are compared byte for byte on every corpus document, and every PDF goes through external validators
(`node bench/pdf/validate.mjs`) and a visual comparison with takumi-pdf (`node bench/pdf/visual.mjs`).

<!-- pdf-bench:summary -->
- **Render time, bm-native vs takumi-pdf:** sync 0.30× [0.31× / 0.30× / 0.31×] (faster on 112/112, 0.12×–0.97×); async 0.32× [0.32× / 0.31× / 0.32×] (faster on 112/112, 0.12×–0.94×). Below 1× = bm takes less time; in brackets the same ratio per pass.
- **bm-wasm vs takumi-pdf (both wasm):** 0.49× [0.50× / 0.49× / 0.49×] (faster on 107/112, 0.20×–1.36×). **bm-native vs bm-wasm (sync):** 0.62× [0.61× / 0.61× / 0.62×] (faster on 112/112, 0.38×–0.77×).
- **Pages per second at 1 / 10 / 100 / 500 pages:** bm-native 284 / 206 / 28 / error; bm-wasm 108 / 89 / 14 / error; takumi-pdf 29 / 46 / 75 / 83.
- **Identity:** bm-native == bm-wasm 113/114 documents, same error on both: 1.
- **Validators:** bm-native 104/113 PDFs without any error or warning (takumi-pdf 105/114); veraPDF bm-native 45/45, takumi-pdf 45/45; same text, links, outline and tags as takumi-pdf: 101/113.
- **Visual verdicts vs takumi-pdf (best over the rasterisers):** identical 79, equivalent 30, different 3, close 1 (113 documents, pdfium + mupdf).
- **Noise:** absolute geomeans moved between passes by bm-native:sync 10.1 %, bm-native:async 10.2 %, bm-wasm:sync 10.2 %, bm-wasm:async 11.6 %, takumi-pdf:async 12.9 % ⚠; read the ratios (measured interleaved).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:cold -->
| Engine | wall median ms | p95 | over empty Node | import | font | first PDF | peak RSS |
|:--|--:|--:|--:|--:|--:|--:|--:|
| empty Node.js | 55.9 | 88.6 | — | — | — | — | 45 MiB |
| bm-native | 67.7 | 106 | 11.8 | 6.80 | 0.36 | 3.10 | 50 MiB |
| bm-wasm | 162 | 209 | 106 | 9.90 | 2.56 | 58.7 | 74 MiB |
| takumi-pdf | 268 | 296 | 213 | 42.4 | 3.49 | 128 | 76 MiB |

30 runs per engine, interleaved: spawn Node -> import -> register Inter Regular -> one-page A4 invoice -> exit. CPU busy meanwhile 52 %.
<!-- /pdf-bench:cold -->

<!-- pdf-bench:eventloop -->
| Engine | API | render ms | max timer delay | p99 | ticks |
|:--|--:|--:|--:|--:|--:|
| bm-native | sync | 3,899 | 3,899 ms | 3,899 ms | 1 |
| bm-native | async | 3,765 | 15.9 ms | 1.40 ms | 3681 |
| bm-wasm | sync | 10,694 | 10,694 ms | 10,694 ms | 1 |
| bm-wasm | async | 10,366 | 10,366 ms | 10,366 ms | 1 |
| takumi-pdf | async | 1,511 | 1,511 ms | 1,511 ms | 1 |

One 100-page render while a 1 ms interval timer runs; a delay close to the render time means the event loop was blocked for the whole render.
<!-- /pdf-bench:eventloop -->

<!-- pdf-bench:throughput -->
| Configuration | N=1 | N=2 | N=4 | N=8 |
|:--|--:|--:|--:|--:|
| bm-native seq uv=4 | 464 |  |  |  |
| bm-wasm seq | 277 |  |  |  |
| takumi-pdf seq | 129 |  |  |  |
| bm-native many k=1 uv=4 | 521 | 529 | 473 | 513 |
| bm-native many k=2 uv=4 | 503 | 976 | 925 | 738 |
| bm-native many k=4 uv=4 | 347 | 722 | 1,299 | 1,370 |
| bm-native many k=8 uv=4 | 430 | 827 | 1,380 | 1,495 |
| bm-native many k=1 uv=8 | 477 | 492 | 460 | 492 |
| bm-native many k=2 uv=8 | 485 | 798 | 941 | 914 |
| bm-native many k=4 uv=8 | 474 | 888 | 1,523 | 1,639 |
| bm-native many k=8 uv=8 | 513 | 951 | 1,684 | 2,295 |
| bm-wasm pool k=1 | 308 | 314 | 314 | 321 |
| bm-wasm pool k=2 | 297 | 620 | 638 | 630 |
| bm-wasm pool k=4 | 308 | 618 | 981 | 981 |
| bm-wasm pool k=8 | 321 | 576 | 719 | 1,154 |
| takumi-pdf pool k=1 | 107 | 129 | 127 | 139 |
| takumi-pdf pool k=2 | 122 | 293 | 283 | 297 |
| takumi-pdf pool k=4 | 123 | 282 | 404 | 497 |
| takumi-pdf pool k=8 | 129 | 288 | 510 | 635 |

PDFs per second, docs/invoice (one-page A4 invoice, HTML + footer), closed loop: N clients each with one request in flight; 2000 ms per point, 8 logical CPUs. seq = one client on the sync API (takumi-pdf: awaited render), many = N clients on K bm-native renderers (async API on the libuv pool, UV_THREADPOOL_SIZE = uv), pool = worker_threads pool of K workers each with its own engine.
<!-- /pdf-bench:throughput -->
