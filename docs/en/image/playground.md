---
title: Playground
sidebar: false
aside: false
pageClass: playground-page
---

# Playground

[English](playground.md) · [Tiếng Việt](../../vi/image/playground.md)

The playground runs the real bm-engine WebAssembly build in your browser: try node JSON, HTML and
Tailwind input, compare the three profiles, inspect layout with `measure()` and export every output
format. Nothing is uploaded; fonts and images you add stay in the page.

<ClientOnly>
  <PlaygroundFrame lang="en" />
</ClientOnly>

## Features

- Profile selector (`core` / `standard` / `full`); switching reloads the page with
  `?profile=core|standard|full` because each page keeps one wasm instance. Your source, options and
  images are restored from `localStorage`.
- Inputs: node JSON, HTML, Tailwind; the `css` option; font and image upload.
- Outputs: PNG, JPEG, WebP, raw, SVG (`renderSvg`) and animated WebP / APNG / GIF, with render timing,
  download and "copy data URL".
- `measure()` overlay, templates (OG card, blog card, Vietnamese text, emoji, SVG image, HTML article,
  Tailwind card, CSS demo, animation, gradients, table + float), English / Vietnamese UI.
- **Share link** puts the deflate-compressed state into the URL hash.

Templates that need a feature the selected profile lacks show a clear message or render in a degraded
way (for example the Tailwind card on `core`), which makes the playground a quick way to see what each
profile drops.

## Run locally

The playground source lives in [docs/playground-app/](../../playground-app/README.md) (plain HTML, ES
modules and CSS, no framework, no external requests). From a repository checkout with the `js/*.wasm`
binaries present (prebuilt in the repository, or `node scripts/build.mjs`):

```sh
npm run playground          # = node docs/playground-app/serve.mjs -> http://127.0.0.1:8080/docs/playground-app/
npm run docs:dev            # the whole documentation site, playground included -> http://localhost:5173/playground
```

The development page loads the engine from `../../js/` and fonts from `../../assets/fonts/`; the
documentation build (`npm run docs:build`) runs `docs/playground-app/build.mjs`, which copies the app,
`js/*.mjs`, the `.wasm` files and the default fonts into `docs/public/playground-app/` (`vendor/`), and the
site embeds that copy. Both layouts are described by `config.js`. The app accepts `?lang=en|vi` and
`?theme=light|dark`.

Automated test: `node bench/browser/playground-test.mjs` (headless Edge / Chrome via puppeteer-core;
tests the development server on all three profiles, the self-contained build and the playground page of
the built documentation site; writes `bench/out/PLAYGROUND.md`).
