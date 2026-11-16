# Vite and browsers

[English](vite-browser.md) · [Tiếng Việt](../../../vi/image/frameworks/vite-browser.md)

bm-render runs entirely in the browser: the binary has no imports, so any engine with WebAssembly SIMD
renders the same bytes as Node. This page covers bundlers (Vite first), loading without a bundler or
from a CDN, rendering in a Web Worker so the page never stutters, and displaying the result.

::: info Verification status
- **Vite**: the repository's package test (`npm run test:pack`, `scripts/pack-test.mjs`) builds two pages
  with **Vite 8.3.8** — `bm-render/core` + `await init()`, and `bm-render` + `init(wasmUrl)` from a `?url`
  import, plus the WOFF add-on — and loads them in **headless Edge 157**: PNG rendered, no console errors.
- **Web Worker, no bundler**: `docs/examples/frameworks/check-browser.mjs` serves
  `docs/examples/frameworks/browser/` and runs it in headless Edge 157: a module worker runs
  `await init()` from `bm-render/standard`, renders at `devicePixelRatio` 2, transfers the PNG, and the page
  displays it through a blob URL and `createImageBitmap` (1200 × 630, no console errors).
- `init(fetch(url))` with `application/wasm` used `WebAssembly.instantiateStreaming` (checked under
  `node --conditions=browser`).
- **Not tested**: Vite's worker bundling (`new Worker(new URL(...))` inside a Vite build), webpack,
  Rollup, Parcel, and loading from a CDN (the package is not published yet).
:::

## Vite

Import a profile entry and call `init()` without an argument:

```js
import { init, Renderer } from "bm-render/standard";

await init(); // Vite emits bm_render.standard.wasm as an asset and rewrites the URL
const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: await (await fetch("/Inter-Regular.ttf")).arrayBuffer() });
```

The profile entries locate their binary with `new URL("./bm_render.standard.wasm", import.meta.url)`,
a pattern Vite (and webpack 5, Parcel) turn into an emitted asset. If you prefer to control the URL,
import it with `?url` and pass it:

```js
import { init, Renderer } from "bm-render";
import wasmUrl from "bm-render/standard.wasm?url";

await init(wasmUrl); // any profile's binary works with the generic entry
```

- Do **not** add `vite-plugin-wasm` or enable WebAssembly ESM integration for these files: bm-render
  instantiates the module itself and needs a URL, bytes or an uninstantiated `WebAssembly.Module`.
- Serve `.wasm` as `application/wasm` in production for streaming compilation (Vite's dev server and
  most hosts do). With another content type `init` falls back to `arrayBuffer()`, which also works.
- In SSR code (Vite SSR, frameworks built on Vite), import the same profile entry: on the server the
  `node` condition picks the auto-initialising Node file, and `await init()` is a harmless no-op.

Other bundlers, from [Getting started](../../getting-started.md#bundlers): webpack 5 emits
`new URL(..., import.meta.url)` assets by default (not tested); Rollup needs an asset plugin, or pass the
URL yourself; esbuild bundles the JS but does not copy the `.wasm` (copy it next to the bundle and pass
its URL).

## Render in a Web Worker

A render is synchronous: a large card can take tens of milliseconds, which is visible jank on the main
thread. Move the engine into a module worker and transfer the bytes back:

```js
// render-worker.js
import { init, Renderer } from "bm-render/standard";

const ready = (async () => {
  await init();
  const renderer = new Renderer();
  const font = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
  renderer.registerFont({ name: "Inter", data: font });
  return renderer;
})();

self.onmessage = async ({ data: { id, node, options } }) => {
  try {
    const renderer = await ready;
    const png = renderer.renderSync(node, options);
    self.postMessage({ id, png }, [png.buffer]); // transfer, no copy
  } catch (error) {
    self.postMessage({ id, error: String(error?.message ?? error) });
  }
};
```

```js
// main.js
const worker = new Worker(new URL("./render-worker.js", import.meta.url), { type: "module" });
let nextId = 0;
const pending = new Map();
worker.onmessage = ({ data: { id, png, error } }) => {
  const p = pending.get(id);
  pending.delete(id);
  error ? p.reject(new Error(error)) : p.resolve(png);
};
export const render = (node, options) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject });
  worker.postMessage({ id, node, options });
});
```

The verified copy imports `/node_modules/bm-render/js/standard.mjs` by path (no bundler); with Vite,
import `bm-render/standard` as above. Node trees are plain objects, so they cross `postMessage`
unchanged; image bytes in `images` can be transferred too. Each worker has its own wasm instance and
its own fonts.

## Show the result

```js
const dpr = Math.min(window.devicePixelRatio || 1, 3);
const png = await render(node, { width: Math.round(600 * dpr), height: Math.round(315 * dpr), devicePixelRatio: dpr });
const blob = new Blob([png], { type: "image/png" });

// as an image element
img.src = URL.createObjectURL(blob);   // URL.revokeObjectURL(img.src) when replaced
img.style.width = "600px";

// or onto a canvas
const bitmap = await createImageBitmap(blob);
canvas.getContext("2d").drawImage(bitmap, 0, 0, 600, 315);
```

Render `width × dpr` by `height × dpr` pixels **and** pass `devicePixelRatio: dpr`: the canvas size is
always `width × height`, and `devicePixelRatio` scales the CSS lengths inside it (verified: dpr 2 gave a
1200 × 630 bitmap for a 600 × 315 layout). For a canvas you can also skip PNG encoding:
`format: "raw"` returns straight RGBA, `new ImageData(new Uint8ClampedArray(raw.buffer), w, h)` then
`putImageData` (`raw` was not part of the browser test). `renderAsDataUrl()` returns a `data:` URL if you
need a string.

## Without a bundler, or from a CDN

Serve the package's `js/` folder and import a profile entry; `init()` fetches the binary next to it:

```html
<script type="module">
  import { init, Renderer } from "/node_modules/bm-render/js/standard.mjs";
  await init();
  const renderer = new Renderer();
</script>
```

From a CDN that serves npm packages (jsDelivr, unpkg), the same works with a versioned URL — pin the
exact version you tested:

```js
import { init, Renderer } from "https://cdn.jsdelivr.net/npm/bm-render@<version>/js/standard.mjs";
await init(); // fetches .../js/bm_render.standard.wasm from the same CDN
```

The CDN form is untested until the package is published. Check that the CDN sends
`application/wasm` and CORS headers for the `.wasm` file; if it does not, `init` still works through
`arrayBuffer()` as long as the request itself is allowed.

## Size in the browser

| Profile | wasm brotli | When |
|:--|--:|:--|
| `core` | 195.3 KiB | node trees, inline styles, TTF, PNG / JPEG images |
| `standard` | 398.6 KiB | + HTML, CSS, Tailwind, SVG, WOFF2, effects, tables |
| `full` | 470.8 KiB | + complex scripts, colour emoji, animation, `renderSvg` |

Fonts are often the biggest download; subset them. See [Profiles and size](../../profiles-and-size.md).
