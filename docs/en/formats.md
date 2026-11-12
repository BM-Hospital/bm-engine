# Output formats

[English](formats.md) · [Tiếng Việt](../vi/formats.md)

`render()` lays the page out once and then hands the pixels to an encoder; the `format` option picks
which one. This page shows every output bm-engine 0.1.0 can produce — PNG, JPEG, WebP, raw RGBA, ICO,
data URLs, SVG documents and (on its own page) animations — what each does with transparency and
`quality`, how `devicePixelRatio` and the canvas size interact, which profile ships which encoder, and
what the benchmark says about speed and file size. PDF documents have their own pages, starting at [PDF output](pdf.md). Every snippet below is part of
`docs/examples/formats.mjs` and the images under it are its real output.

## At a glance

| `format` | Alpha | `quality` | Profiles | Notes |
|:--|:-:|:-:|:--|:--|
| `"png"` (default) | yes | ignored | all | lossless; palette / RGB / RGBA chosen automatically |
| `"jpeg"` (alias `"jpg"`) | no — dropped, transparent becomes **black** (same as takumi) | 1–100, default 75 | all | baseline JPEG; give the root an opaque background |
| `"webp"` | yes | ignored | all | always **lossless** (as in takumi's wasm build); `lossless` is ignored too |
| `"raw"` | yes | ignored | all | `width × height × 4` bytes of straight (non-premultiplied) RGBA8 |
| `"ico"` | yes | ignored | `full` | one PNG inside an ICO container, 1–256 px per side |
| `renderSvg()` | yes | — | `full` | an SVG document string |
| `renderAnimation()` | yes | — | `full` | animated WebP (default), APNG or GIF; see [Animation](./animation.md) |

Any other `format` throws `bm-engine: unsupported format: <x>` (for example `"gif"` for a still image).

All examples on this page use this setup and card. Note the rounded corners on a transparent canvas: they
show what each format does with alpha.

<!-- @example formats#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // Node: the full profile

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

// A card with rounded corners on a transparent canvas: good for showing what each format does with alpha.
const card = {
  type: "container",
  style: {
    display: "flex", flexDirection: "column", justifyContent: "center", gap: 6,
    width: "100%", height: "100%", padding: 28, borderRadius: 28, fontFamily: "Inter",
    backgroundImage: "linear-gradient(135deg, #f97316, #db2777 55%, #7c3aed)",
  },
  children: [
    { type: "text", text: "bm-engine", style: { fontSize: 40, fontWeight: 700, color: "white" } },
    { type: "text", text: "PNG · JPEG · WebP · SVG", style: { fontSize: 20, color: "rgba(255,255,255,0.85)" } },
  ],
};
```

## PNG

PNG is the default and the safe choice: lossless, transparent, and decoded everywhere.

<!-- @example formats#png -->
```js
const png = renderer.renderSync(card, { width: 400, height: 200 }); // format defaults to "png"
```

![PNG output of the card](/img/guide/formats-png.png)

The encoder picks the pixel format per image: a flat image with few colours is written as an indexed
(palette) PNG, a gradient like the one above as 8-bit RGBA. You do not need to configure anything, and
there is no compression-level option. In the benchmark, bm-engine's PNG files are 0.78× the size of
takumi's on average (geometric mean over 191 fixtures, see [Benchmark](./benchmark.md)).

## Comparing sizes

The same card, encoded three ways:

<!-- @example formats#compare -->
```js
for (const format of ["png", "jpeg", "webp"]) {
  const bytes = renderer.renderSync(card, { width: 400, height: 200, format });
  console.log(format, bytes.length, "bytes");
}
```

What this example printed (400 × 200, gradient + text; sizes are for this image only):

| Format | Bytes |
|:--|--:|
| PNG | 12 145 |
| JPEG (quality 75) | 9 681 |
| WebP (lossless) | 13 882 |

For gradients and photos JPEG wins; for flat UI (solid colours, text) PNG and lossless WebP are usually
smaller than JPEG and have no artefacts. The phase-1 benchmark measured three representative 1200 × 630
cases (time = render + encode, median; numbers from [docs/BENCHMARK.md](../BENCHMARK.md)):

| Case | PNG | JPEG q75 | WebP lossless |
|:--|--:|--:|--:|
| flat UI card | 7.13 ms / 13 381 B | 17.63 ms / 47 298 B | 8.99 ms / 11 134 B |
| gradients | 14.50 ms / 32 991 B | 19.28 ms / 53 465 B | 11.57 ms / 29 580 B |
| photo background | 47.60 ms / 523 396 B | 17.88 ms / 56 442 B | 45.94 ms / 414 512 B |

The photo WebP case was optimised afterwards (45.9 → 19.9 ms, 414 → 376 KB, see
[Benchmark](./benchmark.md#phase-1-losses-and-what-was-done)); the other numbers have not been
re-measured per format since. Overall, the final 0.1.0 run renders a PNG in 1.33 ms and a raw buffer
in 0.64 ms (geometric means over 250 fixtures on an Intel i3-10100).

## JPEG and `quality`

`quality` only affects JPEG. It is clamped to 1–100 and defaults to 75.

<!-- @example formats#jpeg-quality -->
```js
const low = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 15 });
const high = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 90 });
console.log("quality 15:", low.length, "bytes; quality 90:", high.length, "bytes");
```

This printed `quality 15: 3525 bytes; quality 90: 15693 bytes` (the default 75 gave 9 681 bytes).

| quality 15 | quality 90 |
|:-:|:-:|
| ![JPEG at quality 15](/img/guide/formats-jpeg-q15.jpg) | ![JPEG at quality 90](/img/guide/formats-jpeg-q90.jpg) |

### Transparency in JPEG

The canvas starts transparent, and JPEG has no alpha channel, so every transparent pixel is written as
**black** — here, the area outside the rounded corners. Paint an opaque background behind your content
when you encode to JPEG:

<!-- @example formats#jpeg-opaque -->
```js
// JPEG has no alpha channel: transparent pixels (the rounded corners) come out black.
const cornersBlack = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 90 });

// Paint an opaque background behind the card instead:
const onWhite = renderer.renderSync(
  { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "white" }, children: [card] },
  { width: 400, height: 200, format: "jpeg", quality: 90 },
);
```

| transparent corners → black | opaque background |
|:-:|:-:|
| ![JPEG with black corners](/img/guide/formats-jpeg-black-corners.jpg) | ![JPEG on a white background](/img/guide/formats-jpeg-on-white.jpg) |

::: tip
The JPEG encoder simply drops the alpha channel; it does not blend with any colour, and there is no
background option — takumi behaves the same. Fully transparent
pixels become black, and a semi-transparent pixel keeps its colour at full strength: a canvas filled
with `rgba(255, 0, 0, 0.5)` comes out solid red, and a soft shadow on a transparent canvas turns into a
hard-edged block of the shadow colour. Put a solid colour on the root whenever you encode to JPEG.
:::

## WebP

WebP output is **always lossless**, exactly like takumi's WebAssembly build: `quality` and
`lossless: false` are accepted and ignored. Alpha is kept.

<!-- @example formats#webp -->
```js
const webp = renderer.renderSync(card, { width: 400, height: 200, format: "webp", quality: 10 });
const webpDefault = renderer.renderSync(card, { width: 400, height: 200, format: "webp" });
console.log(webp.length === webpDefault.length); // true: WebP output is always lossless, quality is ignored
```

![Lossless WebP output](/img/guide/formats-webp.webp)

Choose lossless WebP when you want transparency and smaller files than PNG on flat content; choose JPEG
when you need lossy compression of photographic content. Lossy WebP *input* (decoding) exists on `full`
(see [Images](./images.md)), lossy WebP *output* does not exist on any profile.

## Raw pixels

`format: "raw"` skips encoding and returns the canvas as straight RGBA8, row by row, top to bottom. Use it
to post-process pixels, to compare images, to feed a video encoder, or to hand the frame to a
`<canvas>` (`new ImageData(new Uint8ClampedArray(raw.buffer), width, height)` in a browser).

<!-- @example formats#raw -->
```js
const width = 400, height = 200;
const raw = renderer.renderSync(card, { width, height, format: "raw" });
console.log(raw.length === width * height * 4); // true: straight (non-premultiplied) RGBA8, row by row

const pixel = (x, y) => Array.from(raw.subarray((y * width + x) * 4, (y * width + x) * 4 + 4));
console.log(pixel(0, 0));     // [0, 0, 0, 0]: the corner outside the border radius is transparent
console.log(pixel(200, 100)); // an opaque pixel of the gradient
```

The printed opaque pixel was `[222, 46, 110, 255]`. Raw output is also the fastest path, because the
encoder is skipped (0.64 ms vs 1.33 ms geometric mean in the benchmark).

A raw buffer can go straight back into bm-engine as an image source, which is handy for composing
thumbnails or frame strips without an extra image library:

<!-- @example formats#raw-roundtrip -->
```js
// Raw pixels can be fed back as an image source: { width, height, data }.
const thumbnails = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 12, padding: 12, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: [1, 2, 3].map(() => ({ type: "image", src: { width, height, data: raw }, style: { width: 120, height: 60 } })),
  },
  { width: 420, height: 84 },
);
```

![Three thumbnails composed from a raw buffer](/img/guide/formats-raw-roundtrip.png)

## Data URLs

`renderAsDataUrl()` / `renderAsDataUrlSync()` take the same arguments as `render()` and return
`data:<mime>;base64,...` for `png`, `jpeg` (also as `"jpg"`), `webp` and `ico`.

<!-- @example formats#dataurl -->
```js
const url = renderer.renderAsDataUrlSync(card, { width: 400, height: 200, format: "webp" });
console.log(url.slice(0, 23)); // "data:image/webp;base64,"
// in a browser: img.src = url
```

`format: "raw"` throws `bm-engine: renderAsDataUrl needs an encoded format`. Data URLs are about a third
larger than the bytes they encode; for HTTP responses send the bytes with the right `content-type`.

## ICO (favicons)

`format: "ico"` writes an ICO file containing one PNG image. It needs the `full` profile and a canvas of
1 to 256 pixels per side; anything bigger throws `bm-engine: ICO images are 1 to 256 pixels on a side,
not 300`.

<!-- @example formats#ico -->
```js
const favicon = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
             borderRadius: 12, backgroundColor: "#7c3aed" },
    children: [{ type: "text", text: "b", style: { fontFamily: "Inter", fontWeight: 700, fontSize: 44, color: "white" } }],
  },
  { width: 64, height: 64, format: "ico" }, // full profile only; 1-256 px per side
);
```

The ICO file of this example is 553 bytes and starts with the ICO signature `[0, 0, 1, 0]`. The same
node rendered as PNG:

![The favicon as PNG](/img/guide/formats-favicon.png)

## SVG documents

`renderSvg()` / `renderSvgSync()` (full profile) run the same layout and emit an SVG document instead of
a bitmap: boxes become `<rect>` / `<path>`, gradients `<linearGradient>` / `<radialGradient>` (conic
gradients as wedges), shadows `<filter>`s, images are embedded as `data:` URLs and text becomes glyph
outlines (`<use>` of paths in `<defs>`).

<!-- @example formats#svg -->
```js
const svg = renderer.renderSvgSync(card, { width: 400, height: 200 }); // full profile only
console.log(svg.slice(0, 90));
// '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200" viewBox="0 0 400 200">...'
```

![The card as an SVG document](/img/guide/formats-card.svg)

The SVG of this example is 7 118 bytes. Things to know:

- **Text is not text.** Glyphs are drawn as outlines; there is no font embedding and the text is not
  selectable or searchable. In exchange, the SVG looks the same without your fonts installed.
- `format`, `quality` and `devicePixelRatio` are ignored: SVG output is always laid out at a device
  pixel ratio of 1, as in takumi (the document is scalable anyway).
- In the benchmark both engines' SVG output was rasterised and compared: 175/179 fixtures identical or
  equivalent to takumi's SVG.

## Device pixel ratio

`width` and `height` are always the size of the output image in pixels. `devicePixelRatio` multiplies
every CSS length (px, font sizes, image intrinsic sizes) but does **not** change the canvas. To render a
400 × 200 design at 2×, double the canvas *and* set the ratio:

<!-- @example formats#dpr -->
```js
// The same 400 x 200 CSS layout, rendered with twice as many pixels:
const retina = renderer.renderSync(card, { width: 800, height: 400, devicePixelRatio: 2 });

// Without the larger canvas, devicePixelRatio: 2 leaves only 200 x 100 CSS px of room:
const cramped = renderer.renderSync(card, { width: 400, height: 200, devicePixelRatio: 2 });
```

`retina` (800 × 400, the same layout at twice the resolution):

![Card rendered at devicePixelRatio 2](/img/guide/formats-dpr2.png)

`cramped` (400 × 200 canvas with ratio 2, so the layout only gets 200 × 100 CSS px and the text no
longer fits):

![Cramped render: ratio 2 without a bigger canvas](/img/guide/formats-dpr2-cramped.png)

`%`, `vw` and `vh` refer to the canvas, so `width: "100%"` needs no change. Values outside (0, 64) are
ignored. Display a 2× image at half its pixel size (`<img width="400">`).

## Letting the content decide the size

Without `width` and/or `height`, the root is laid out at its max-content size on that axis and the
canvas takes the result:

<!-- @example formats#auto-size -->
```js
// Without width / height the canvas takes the size of the laid-out root.
const badge = renderer.renderSync({
  type: "container",
  style: { display: "flex", padding: "6px 14px", borderRadius: 999, backgroundColor: "#0f172a" },
  children: [{ type: "text", text: "v0.1.0", style: { fontFamily: "Inter", fontSize: 18, color: "#e2e8f0" } }],
});
```

![A badge sized by its content](/img/guide/formats-auto-size.png)

This badge came out 76 × 33 px. A root with nothing to measure and no size throws
`invalid viewport: content has zero size and no width/height was given`. The canvas is limited to 16 384
px per side and 40 megapixels (`canvas too large`).

## Animated output

`renderAnimation()` encodes scenes into an animated WebP (lossless, default), APNG or GIF, and
`render(..., { timeMs })` renders one frame of a CSS animation. Both need the `full` profile and are
covered in [Animation](./animation.md).

## Cancellation

`signal` takes an `AbortSignal`. It is checked before rendering starts (and before the async options
are resolved); an aborted signal throws its `reason`. A render that has started cannot be interrupted —
it is synchronous and usually takes a few milliseconds.

<!-- @example formats#abort -->
```js
const controller = new AbortController();
controller.abort(new Error("request closed"));
try {
  await renderer.render(card, { width: 400, height: 200, signal: controller.signal });
} catch (err) {
  console.log(err.message); // "request closed": the signal is checked before rendering starts
}
```

## Encoders per profile

| Output | core | standard | full |
|:--|:-:|:-:|:-:|
| PNG, JPEG, lossless WebP, raw, data URLs | ✓ | ✓ | ✓ |
| ICO | | | ✓ |
| `renderSvg()` | | | ✓ |
| `renderAnimation()` (WebP / APNG / GIF) | | | ✓ |
| PDF (`renderPdf()`, `bm-engine/pdf`) | | | not in `full`: see [PDF output](pdf.md) |

On a smaller profile the `full`-only outputs throw a clear error:

<!-- @example formats#core -->
```js
import * as core from "bm-engine/core";

const small = new core.Renderer();
small.renderSync({ type: "container", style: { width: 16, height: 16, backgroundColor: "red" } },
                 { width: 16, height: 16, format: "webp" }); // png / jpeg / webp / raw work on every profile
try {
  small.renderSync({ type: "container" }, { width: 16, height: 16, format: "ico" });
} catch (err) {
  console.log(err.message); // "bm-engine: this build has no ICO output support (use the full build)"
}
```

The encoders are bm-engine's own, so the bytes differ from takumi's even where the pixels are identical;
the [Benchmark](./benchmark.md) compares decoded pixels. See also [Performance](./performance.md) for
choosing between raw and encoded output, and [Profiles and size](./profiles-and-size.md).
