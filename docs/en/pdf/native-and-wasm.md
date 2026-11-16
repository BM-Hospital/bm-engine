# Native and WebAssembly

[English](native-and-wasm.md) · [Tiếng Việt](../../vi/pdf/native-and-wasm.md)

`bm-render/pdf` runs on two engines with one API: the native Node-API addon on Node.js (when the platform
package is installed) and the WebAssembly binary `bm_render.pdf.wasm` everywhere else and as the automatic
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

On Node.js, Bun and Deno, `bm-render/pdf` runs on the native Node-API addon when it is installed (the same
addon and the same optional `bm-render-<platform>` package that `bm-render` uses; there is no extra package),
and otherwise falls back, silently, to the wasm `pdf` profile. `backend`, exported from `bm-render/pdf`, is
`"native"` or `"wasm"`, and `BM_RENDER_BACKEND=wasm|native` forces one. The PDF bytes are identical on both
backends. Natively, the async methods (`PdfRenderer.render` and `measure`, `Renderer.renderPdf` and
`measurePdf`) run on the libuv thread pool instead of blocking the event loop; `init()` and `initSync()` do
nothing there, and `profile` is still `"pdf"`. In browsers, bundlers, Workers and edge runtimes nothing
changes: the entry is the wasm `pdf` profile. See [Native addon vs WebAssembly](../native-vs-wasm.md).

## Same bytes on both backends

`backend`, `profile` and `features` tell you what serves the entry:

<!-- @example pdf-native-and-wasm#backend -->
```js
const { backend, profile, features, PdfRenderer } = await import("bm-render/pdf");
console.log(backend, profile, features.pdf); // "native" pdf true  (or "wasm" pdf true without the addon)
```

The example script renders this document once with `BM_RENDER_BACKEND=wasm` and once with
`BM_RENDER_BACKEND=native`, each in its own process (the backend is chosen when the module is imported),
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

In the run for this page both files were 8 943 bytes with the same hash. bm-render writes no date and no
random file identifier unless you pass them (`metadata.creationDate`, ...), so the output is also the same
from one run to the next, which makes PDFs easy to cache and to compare in tests.

## The `pdf` profile and its size

`bm_render.pdf.wasm` is `full` plus the PDF writer: 1 906.7 KiB raw, 938.1 KiB with gzip -9 and
767.1 KiB with brotli -11, about 0.6 MB more than `bm_render.wasm` (`full`: 1 272.7 / 631.5 / 529.1 KiB). The PDF code is compiled only into this binary and into the native addon, and so are the paged
layout and the CSS paged-media properties it needs. (The native addon is the `full` feature set plus PDF
output; `bm-render` itself never exposes the PDF writer.) [Profiles and size](../profiles-and-size.md) has the
exact numbers for every binary. Build it yourself with `npm run build:pdf`
(`node scripts/build.mjs --profile=pdf`) or `zig build -Dprofile=pdf`
([Building from source](../building-from-source.md)).

Because the pagination code is only in this profile, the CSS properties `break-before`, `break-after`,
`break-inside`, `page-break-*`, `orphans` and `widows`, and the Tailwind `break-before-*`,
`break-inside-*` and `break-after-*` utilities, apply only to PDF output (`bm-render/pdf`). Image renders
(`render`, `renderSvg`, `measure`) accept and ignore them on every build, including `bm-render/pdf` and the native
addon, so an image is the same on every build. `background-clip: border-area` follows the same rule.

## What the other profiles do

Every `Renderer` has `renderPdf`, `renderPdfSync`, `measurePdf` and `measurePdfSync`, but only the
`pdf` build exposes a PDF writer. On any other build they throw, and that includes `bm-render` running on the
native addon (the addon binary contains the PDF writer, but `bm-render` hides it: `features.pdf` is `false`):

<!-- @example pdf#not-supported -->
```js
import { Renderer } from "bm-render/full"; // the full profile has no PDF writer
let message;
try {
  new Renderer().renderPdfSync(card);
} catch (e) {
  message = e.message;
}
// message: bm-render: renderPdf is not supported by this build (use the pdf build: import from "bm-render/pdf")
```

Check `features.pdf` before you call them if your build can vary.

In a browser or a Worker, only this binary is downloaded for PDF output: import `bm-render/pdf` and nothing
else from bm-render, since every other entry has its own module instance and binary
([PDF quick start → In a browser](index.md#in-a-browser-and-on-edge-runtimes)).

## Performance and validation

See [Benchmark](../benchmark.md) for measurements and reproduction steps.
