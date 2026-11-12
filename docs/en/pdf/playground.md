---
title: PDF playground
sidebar: false
aside: false
pageClass: playground-page
---

# PDF playground

[English](playground.md) · [Tiếng Việt](../../vi/pdf/playground.md)

The PDF playground runs the real `bm-engine/pdf` WebAssembly build (`bm_engine.pdf.wasm`) in your
browser: write node JSON, HTML or Tailwind, set the page, header, footer, metadata and standards
options, and look at the PDF it writes. Nothing is uploaded; fonts and images you add stay in the page.

<ClientOnly>
  <PlaygroundFrame lang="en" mode="pdf" />
</ClientOnly>

## Features

- The same editor as the [image playground](../image/playground.md): node JSON, HTML and Tailwind input,
  the `css` option, font and image upload. Switching between Image and PDF keeps what is in the editor.
- Every option comes from [`PdfRenderOptions`](api.md#render-options): page size (the presets or a custom
  size) and `landscape`, margins (empty = `auto`), paged output or one page (`viewport`), `header` and
  `footer` bands with the `pageNumber` / `totalPages` counters, `pages.first`, `pageRanges`,
  `backgroundColor`, `metadata` (title, authors, subject, keywords, creation date), `lang`, `outline`,
  `tagged` (including PDF/UA `ua1` / `ua2`), `pdfa` (only the combinations the typings allow can be
  selected) and `uncoveredText`. Engine errors, such as a PDF/UA validation failure, are shown verbatim.
- Templates: an invoice with a page-number footer, a multi-page A5 article with bookmarks and
  orphans / widows, a report whose table header repeats on every page, an event ticket on one custom-size
  page, a PDF/UA-1 document with alternate text, Vietnamese and other scripts, and links with a table of
  contents built from `targetPageNumber`.
- The preview is the browser's built-in PDF viewer. Where there is none (phones, or when you choose
  **Preview: pdf.js pages**) the pages are drawn by [pdf.js](https://mozilla.github.io/pdf.js/), which the
  site serves itself and loads only for that preview.
- Page count, file size, render time (median of the last renders), wasm memory and, with `measure()`,
  the laid-out size of the document.
- **Download .pdf**, **Open in new tab**, **Share link** (the source and every option in the URL hash)
  and **Copy code**, which copies a Node.js module that reproduces the render with `PdfRenderer`.

The engine bundles no font: the playground registers Inter and Noto Sans, like the image playground.
Text in a script those fonts do not cover needs an uploaded font (or `uncoveredText`).

## Run locally

```sh
npm run playground          # http://127.0.0.1:8080/docs/playground-app/?mode=pdf
```

The PDF engine (`js/pdf.mjs` and `bm_engine.pdf.wasm`, about 1.5 MiB) is loaded only when PDF mode is
used, so the image playground does not download it. The app also accepts `?mode=image|pdf`, `?lang=en|vi`
and `?theme=light|dark`; the source is in
[docs/playground-app/](../../playground-app/README.md).
