---
layout: home
title: bm-render
titleTemplate: Node trees and HTML + CSS to images and PDF

hero:
  name: bm-render
  text: Node trees and HTML + CSS to images and PDF
  tagline: One package, one engine written in Zig. Create social cards, banners, invoices and reports on Node.js, browsers, Bun, Deno and edge workers, without a headless browser.
  actions:
    - theme: brand
      text: Get started
      link: /getting-started
    - theme: alt
      text: Create images
      link: /image/
    - theme: alt
      text: Create PDFs
      link: /pdf/

features:
  - icon: '<svg viewBox="0 0 24 24"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/></svg>'
    title: Runs everywhere
    details: Native addon on Node.js, WebAssembly in browsers, Bun, Deno and edge runtimes. Same API, byte-identical output.
    link: /native-vs-wasm
    linkText: Native vs WebAssembly
  - icon: '<svg viewBox="0 0 24 24"><path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/></svg>'
    title: Ship only what you use
    details: "Four profiles: core, standard, full and pdf. Pick by input and output to keep the bundle small."
    link: /profiles-and-size
    linkText: Profiles & size
  - icon: '<svg viewBox="0 0 24 24"><path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>'
    title: Measured, not claimed
    details: "Against Takumi on the same inputs: <strong>~1.9× faster</strong> for PNG images and <strong>~3.2× faster</strong> for PDF (native)."
    link: /benchmark
    linkText: See the benchmark
  - icon: '<svg viewBox="0 0 24 24"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="m9 8 6 4-6 4Z"/></svg>'
    title: Try it in your browser
    details: Edit HTML, Tailwind or a node tree and see the result instantly. Nothing is uploaded.
    link: /image/playground
    linkText: Open the playground
---

## Start in one minute

```sh
npm install bm-render
```

Register a font before rendering text (image output ships no fonts). The same HTML becomes an image or a PDF:

::: code-group

```js [Image (PNG)]
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const png = renderer.renderSync(
  `<div style="display:flex; width:100%; height:100%; align-items:center; justify-content:center;
               background:linear-gradient(135deg, #0f766e, #4f46e5); color:white; font:64px Inter">
     Hello from bm-render
   </div>`,
  { width: 1200, height: 630 },
);
writeFileSync("og.png", png);
```

```js [PDF]
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer } from "bm-render/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const bytes = await pdf.render(`
  <h1 style="font-family: Inter">Invoice #42</h1>
  <p style="font-family: Inter">Selectable, searchable vector text.</p>`);
writeFileSync("invoice.pdf", bytes); // A4, 10 mm margins, flows onto new pages
```

:::

Next: [install & entry points](/getting-started) (native or WebAssembly, bundlers, edge),
the [image quick start](/image/) or the [PDF quick start](/pdf/).
