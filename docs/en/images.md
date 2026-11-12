# Images

[English](images.md) · [Tiếng Việt](../vi/images.md)

How pictures get into a bm-engine render: image nodes and HTML `<img>`, CSS `background-image` and
masks, the five ways to hand over the bytes (bm-engine never downloads anything), which formats each
profile decodes, how an image is sized and fitted into its box, and what the decoded-image cache does for
you. Every example on this page is a section of
`docs/examples/images.mjs` in the repository, run against the real package; the pictures below each
snippet are its output.

- [Setup and a test picture](#setup-and-a-test-picture)
- [Where image bytes come from](#where-image-bytes-come-from)
- [Supported formats per profile](#supported-formats-per-profile)
- [Sizing rules](#sizing-rules)
- [object-fit and object-position](#object-fit-and-object-position)
- [Background images](#background-images)
- [Styling images](#styling-images)
- [SVG images](#svg-images)
- [Images in HTML input](#images-in-html-input)
- [Animated sources](#animated-sources)
- [Caching, memory and limits](#caching-memory-and-limits)

## Setup and a test picture

The examples share one renderer (the `bm-engine` entry loads the `full` profile on Node.js) with Inter
regular and bold registered:

<!-- @example images#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

Instead of shipping sample files, the examples render their own test picture with bm-engine and feed the
PNG bytes back in. This also shows that the output of one render is a perfectly good input for the next
(useful for caching an expensive sub-image):

<!-- @example images#photo -->
```js
// A 320 × 200 test picture, rendered by bm-engine itself. Any PNG / JPEG bytes work the same way.
const photo = renderer.renderSync(
  {
    type: "container",
    style: {
      display: "flex", width: "100%", height: "100%", alignItems: "flex-end", justifyContent: "center",
      backgroundImage: "linear-gradient(#38bdf8, #e0f2fe)",
    },
    children: [
      { type: "container", style: { position: "absolute", top: 30, left: 40, width: 60, height: 60, borderRadius: 30, backgroundColor: "#facc15" } },
      { type: "container", style: { width: "100%", height: 70, backgroundColor: "#16a34a" } },
      { type: "text", text: "320 × 200", style: { position: "absolute", top: 80, fontFamily: "Inter", fontWeight: 700, fontSize: 32, color: "#0f172a" } },
    ],
  },
  { width: 320, height: 200 },
);
```

![The 320 × 200 test picture](/img/guide/images-photo.png)

## Where image bytes come from

An image node is `{ type: "image", src, width?, height?, style? }`. `src` can be any of these:

| `src` | Example | Notes |
|:--|:--|:--|
| a key of the `images` option | `"https://example.com/photo.png"` + `images: [{ src: "https://example.com/photo.png", data: bytes }]` | the string is only a lookup key; it can be any text |
| encoded bytes | a Node `Buffer`, `Uint8Array`, `ArrayBuffer` or other `ArrayBufferView` | no wrapper needed for `Buffer` |
| a `data:` URL | `"data:image/png;base64,iVBOR..."`, `"data:image/svg+xml;utf8,..."` | base64 or percent-encoded |
| raw pixels | `{ width, height, data, premultiplied? }` | RGBA8, `data.length` must be `width × height × 4` |
| SVG markup | `'<svg xmlns="http://www.w3.org/2000/svg" ...>'` | standard / full |

All five side by side:

<!-- @example images#sources -->
```js
const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="96" height="96">
  <circle cx="12" cy="12" r="11" fill="#6366f1"/><path d="M7 12.5l3 3 7-7" fill="none" stroke="white" stroke-width="2.5"/></svg>`;
const dataUrl = "data:image/png;base64," + Buffer.from(photo).toString("base64");
const pixels = new Uint8Array(4 * 4 * 4); // a 4 × 4 checkerboard of raw RGBA pixels
for (let i = 0; i < 16; i++) pixels.set((i + (i >> 2)) % 2 ? [244, 63, 94, 255] : [255, 255, 255, 255], i * 4);

const tile = (label, image) => ({
  type: "container",
  style: { display: "flex", flexDirection: "column", alignItems: "center", gap: 8, fontFamily: "Inter", fontSize: 14 },
  children: [image, { type: "text", text: label }],
});
const box = { width: 96, height: 96, objectFit: "cover", borderRadius: 12 };

const sources = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 20, padding: 20, width: "100%", height: "100%", backgroundColor: "#f8fafc" },
    children: [
      tile("images key", { type: "image", src: "https://example.com/photo.png", style: box }),
      tile("Buffer", { type: "image", src: photo, style: box }),
      tile("data: URL", { type: "image", src: dataUrl, style: box }),
      tile("raw RGBA", { type: "image", src: { width: 4, height: 4, data: pixels }, style: box }),
      tile("SVG markup", { type: "image", src: svg, style: box }),
    ],
  },
  {
    width: 600, height: 150,
    // The URL is only a lookup key: nothing is downloaded.
    images: [{ src: "https://example.com/photo.png", data: photo }],
  },
);
```

![The same picture from an images key, a Buffer and a data URL, a 4 × 4 raw RGBA checkerboard and an inline SVG](/img/guide/images-sources.png)

Notice the raw 4 × 4 checkerboard: it was scaled up to 96 × 96 with smooth (bilinear) resampling.
`image-rendering: pixelated` is parsed but not honoured for raster images in 0.1.0, so you cannot get
crisp pixel-art upscaling from the engine; upscale the pixels yourself if you need that.

::: warning bm-engine has no network access
A URL in `src` (or in `url(...)`) is **never fetched**, not even by `prepare()` (takumi's `prepare`
downloads; bm-engine's does not). Download the bytes yourself and pass them in `images`. The same
applies to `@font-face` URLs in stylesheets.
:::

A small helper that turns a list of URLs into an `images` array:

<!-- @example images#fetch -->
```js
async function loadImages(urls) {
  return Promise.all(urls.map(async (src) => ({ src, data: new Uint8Array(await (await fetch(src)).arrayBuffer()) })));
}
// const images = await loadImages(["https://example.com/logo.png"]);
// renderer.renderSync(node, { width: 1200, height: 630, images });
```

`images[].data` may also be a function or a promise. Such *lazy* entries are resolved by the async
methods (`render`, `renderAsDataUrl`, `measure`, `prepare`, ...); the sync methods throw
`bm-engine: lazy images[].data() needs the async API`:

<!-- @example images#lazy -->
```js
const lazy = await renderer.render(
  { type: "image", src: "avatar", style: { width: 64, height: 64, borderRadius: 32 } },
  { width: 64, height: 64, images: [{ src: "avatar", data: async () => photo }] }, // resolved by the async API
);
// renderer.renderSync(...) with the same options throws "lazy images[].data() needs the async API"
```

`images` may be an array or an object `{ sources, cache }` (the takumi shape). Per-image `cache` and
`images.cache` are accepted and ignored: decoded images are always cached (see
[Caching](#caching-memory-and-limits)). Only the entries whose `src` actually appears in the source are
copied into wasm memory, so it is fine to pass one shared list of all your assets to every render.

**A missing or undecodable image never throws.** It paints nothing and has a 0 × 0 intrinsic size, which
can collapse your layout. Give image nodes an explicit size when the picture may be missing:

<!-- @example images#missing -->
```js
const missing = renderer.measureSync(
  { type: "container", style: { display: "flex" }, children: [{ type: "image", src: "not-in-images" }] },
  { width: 100, height: 100 },
);
console.log(missing.children[0].width, missing.children[0].height); // 0 0, and no exception
```

## Supported formats per profile

| Input | core | standard | full |
|:--|:-:|:-:|:-:|
| PNG, JPEG (baseline and progressive) | ✓ | ✓ | ✓ |
| APNG | first frame | first frame | animated |
| WebP lossless (VP8L) | — | ✓ | ✓ |
| WebP lossy (VP8) | — | — | ✓ |
| GIF | — | first frame | animated |
| Animated WebP | — | — | animated |
| SVG (markup, `data:image/svg+xml`, `url()` backgrounds and masks) | — | ✓ | ✓ |

"—" means the image paints nothing and measures 0 × 0, exactly like a missing image; nothing throws.
"animated" means the frame current at `timeMs` is shown (see [Animated sources](#animated-sources)).
The core / standard / full columns were checked by the example script (it asserts the measured size of
a PNG, JPEG, lossless WebP, GIF and SVG source on `bm-engine/core` and `bm-engine/standard`); lossy
WebP was checked with a real VP8 file (0 × 0 on standard, 1200 × 630 on full). There is no ICO, BMP,
TIFF or AVIF decoder. `features.svg`, `features.webpGifDecode` and `features.extraCodecs` tell you at
runtime what the loaded binary decodes.

## Sizing rules

An image is a *replaced element*: it has an intrinsic size (its pixel size, or the `width` / `height`
/ `viewBox` of an SVG) and an aspect ratio, and CSS sizes it like a browser sizes `<img>`:

- With no size at all, it takes its intrinsic size (multiplied by `devicePixelRatio`).
- With only a width or only a height, the other side follows the aspect ratio.
- The node's `width` / `height` fields are **presentational hints**, like HTML attributes: any CSS
  `width` / `height` (inline `style`, stylesheet, `tw`) wins over them.

<!-- @example images#sizing -->
```js
const sized = renderer.measureSync(
  {
    type: "container",
    style: { display: "flex", alignItems: "flex-start" },
    children: [
      { type: "image", src: photo },                                   // intrinsic: 320 × 200
      { type: "image", src: photo, width: 160 },                       // height follows: 160 × 100
      { type: "image", src: photo, style: { height: 50 } },            // width follows: 80 × 50
      { type: "image", src: photo, width: 999, style: { width: 64 } }, // CSS beats the attribute: 64 × 40
    ],
  },
  { width: 800, height: 300 },
);
console.log(sized.children.map((c) => `${c.width}×${c.height}`).join(" ")); // 320×200 160×100 80×50 64×40
```

`devicePixelRatio` scales intrinsic sizes like every other CSS length, so a 320 × 200 picture occupies
640 × 400 output pixels at `devicePixelRatio: 2`. Render a 2× picture at DPR 2 to keep it sharp:

<!-- @example images#dpr -->
```js
const atDpr2 = renderer.measureSync(
  { type: "container", style: { display: "flex" }, children: [{ type: "image", src: photo }] },
  { width: 800, height: 600, devicePixelRatio: 2 },
);
console.log(atDpr2.children[0].width, atDpr2.children[0].height); // 640 400 (output pixels)
```

::: tip Images inside flex rows
A flex item's minimum size is its content size: a 320 px picture in a 200 px flex row keeps 320 px and
squeezes its siblings to zero width. Give the image a fixed `width` / `height` (as above) or
`minWidth: 0` so that it can shrink, and `flexShrink: 0` on items that must not.
:::

## object-fit and object-position

When both sides of the box are fixed, `objectFit` decides how the picture fills it. The default is
`fill` (stretch), as in CSS:

<!-- @example images#object-fit -->
```js
const fits = ["fill", "contain", "cover", "none", "scale-down"];
const objectFit = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 16, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: fits.map((fit) =>
      tile(fit, {
        type: "image", src: photo,
        style: { width: 100, height: 130, objectFit: fit, backgroundColor: "#cbd5e1", border: "2px solid #334155" },
      }),
    ),
  },
  { width: 600, height: 190 },
);
```

![object-fit: fill, contain, cover, none and scale-down on a 100 × 130 box](/img/guide/images-object-fit.png)

`objectPosition` places the picture inside the box (default `50% 50%`); it matters for `contain`,
`cover` and `none`. Keywords, lengths and percentages work:

<!-- @example images#object-position -->
```js
const positions = ["left top", "center", "right bottom", "20% 80%"];
const objectPosition = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 16, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: positions.map((pos) =>
      tile(pos, {
        type: "image", src: photo,
        style: { width: 120, height: 120, objectFit: "none", objectPosition: pos, border: "2px solid #334155" },
      }),
    ),
  },
  { width: 600, height: 180 },
);
```

![object-position: left top, center, right bottom and 20% 80% with object-fit: none](/img/guide/images-object-position.png)

## Background images

Any container can paint images with `backgroundImage: "url(key)"`, where `key` is looked up exactly like
an image `src` (an `images` key or a `data:` URL). Layers are separated by commas, the first one on top,
and can mix gradients and images. The usual companions all work: `backgroundSize` (`cover`, `contain`,
lengths, percentages, `auto`), `backgroundPosition` (also `backgroundPositionX` / `Y`),
`backgroundRepeat` (`repeat`, `no-repeat`, `repeat-x`, `repeat-y`, `space`, `round`),
`backgroundOrigin` and `backgroundClip`:

<!-- @example images#background -->
```js
const bg = (label, style) => tile(label, {
  type: "container",
  style: { width: 130, height: 100, border: "2px solid #334155", backgroundImage: "url(photo)", backgroundColor: "#cbd5e1", ...style },
});
const backgrounds = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexWrap: "wrap", gap: 16, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: [
      bg("cover", { backgroundSize: "cover", backgroundPosition: "center" }),
      bg("contain", { backgroundSize: "contain", backgroundRepeat: "no-repeat", backgroundPosition: "center" }),
      bg("64px repeat", { backgroundSize: "64px 40px" }),
      bg("64px space", { backgroundSize: "64px 40px", backgroundRepeat: "space" }),
      bg("round", { backgroundSize: "64px 40px", backgroundRepeat: "round" }),
      bg("repeat-x bottom", { backgroundSize: "50px", backgroundRepeat: "repeat-x", backgroundPosition: "left bottom" }),
      bg("gradient over image", { backgroundImage: "linear-gradient(transparent, rgba(15,23,42,.85)), url(photo)", backgroundSize: "cover" }),
      bg("radius + cover", { backgroundSize: "cover", borderRadius: 50, border: "none" }),
    ],
  },
  { width: 640, height: 300, images: [{ src: "photo", data: photo }] },
);
```

![Background images with cover, contain, a repeated tile, space, round, repeat-x, a gradient overlay and border-radius](/img/guide/images-background.png)

The "gradient over image" tile is the classic trick for readable text on photos: a gradient layer
above the picture, in the same `backgroundImage` list. `backgroundAttachment` is accepted and ignored
(there is no scrolling). `maskImage: "url(...)"` takes images the same way; see
[Effects](./effects.md#masks).

## Styling images

Image nodes are ordinary boxes: borders, `borderRadius` (clips the picture), shadows, filters,
opacity and transforms apply to them:

<!-- @example images#styling -->
```js
const styling = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 24, padding: 24, alignItems: "center", width: "100%", height: "100%", backgroundColor: "#0f172a" },
    children: [
      { type: "image", src: photo, style: { width: 100, height: 100, objectFit: "cover", borderRadius: "50%", border: "4px solid #f8fafc" } },
      { type: "image", src: photo, style: { width: 120, height: 90, objectFit: "cover", borderRadius: 16, boxShadow: "0 8px 24px rgba(0,0,0,.6)" } },
      { type: "image", src: photo, style: { width: 120, height: 90, objectFit: "cover", filter: "grayscale(1) contrast(1.2)" } },
      { type: "image", src: photo, style: { width: 120, height: 90, objectFit: "cover", opacity: 0.5, transform: "rotate(-8deg)" } },
    ],
  },
  { width: 600, height: 160 },
);
```

![A round avatar with a border, a card with a shadow, a grayscale image and a rotated half-transparent image](/img/guide/images-styling.png)

All of these work on every profile. For non-rectangular cut-outs use `clipPath` or `maskImage`
(standard / full), see [Effects](./effects.md#clip-path).

## SVG images

On `standard` and `full`, SVG is decoded by bm-engine's own SVG renderer and drawn as vectors at the
final size, so it stays sharp at any scale. It works as an image `src` (markup or `data:` URL), as an
`images` entry, and in `url()` backgrounds and masks:

<!-- @example images#svg -->
```js
const logo = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs><linearGradient id="g" x2="1" y2="1"><stop offset="0" stop-color="#f97316"/><stop offset="1" stop-color="#db2777"/></linearGradient></defs>
  <rect width="100" height="100" rx="24" fill="url(#g)"/>
  <path d="M30 70V30h22a12 12 0 0 1 0 24H30" fill="none" stroke="white" stroke-width="10" stroke-linejoin="round"/></svg>`;
const svgOut = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 24, padding: 24, alignItems: "center", width: "100%", height: "100%", backgroundColor: "#fff7ed" },
    children: [
      { type: "image", src: logo, style: { width: 48, height: 48 } }, // vector: sharp at any size
      { type: "image", src: logo, style: { width: 120, height: 120 } },
      { type: "image", src: "data:image/svg+xml;utf8," + encodeURIComponent(logo), style: { width: 80, height: 80 } },
      { type: "container", style: { width: 160, height: 120, borderRadius: 16, backgroundImage: "url(logo.svg)", backgroundSize: "40px 40px" } },
    ],
  },
  { width: 520, height: 170, images: [{ src: "logo.svg", data: new TextEncoder().encode(logo) }] },
);
```

![An SVG logo at 48 px, 120 px and from a data URL, and the same SVG tiled as a background](/img/guide/images-svg.png)

Supported: shapes, paths, `use` / `symbol`, gradients, patterns, `clipPath`, `mask`, markers,
nested `svg` / `image`, a `style` element with simple selectors, and the filters `feGaussianBlur`,
`feOffset`, `feFlood`, `feColorMatrix`, `feComposite`, `feMerge`, `feBlend`, `feDropShadow`,
`feComponentTransfer`. Not supported: `feTurbulence`, `feImage`, `feMorphology`,
`feConvolveMatrix`, `feDisplacementMap`, lighting filters, `feTile`, and external references (an
SVG cannot load another file).

SVG `text` elements are drawn with the fonts registered on the renderer, with a simple model: one run
per `text` element at its `x` / `y`, honouring `font-family`, `font-size`, `font-weight`,
`text-anchor` and a solid `fill`. A gradient fill on text draws nothing, and the character data of
`tspan` / `textPath` children is appended to the parent run (their own position and fill are ignored).
With no registered font the text is not drawn.

<!-- @example images#svg-text -->
```js
const badge = `<svg xmlns="http://www.w3.org/2000/svg" width="260" height="60">
  <rect width="260" height="60" rx="30" fill="#0f172a"/>
  <text x="130" y="39" font-family="Inter" font-size="22" font-weight="700" fill="#f8fafc" text-anchor="middle">SVG &lt;text&gt; works</text></svg>`;
const svgText = renderer.renderSync(
  { type: "container", style: { display: "flex", padding: 20, backgroundColor: "#fff7ed" }, children: [{ type: "image", src: badge }] },
  { width: 300, height: 100, images: { sources: [], cache: "none" } }, // the object form of `images` is accepted too
);
```

![An SVG badge whose label is an SVG text element](/img/guide/images-svg-text.png)

::: tip Charts and icons
Inline SVG is the easiest way to draw lines, curves and icons that CSS boxes cannot express (sparklines,
line charts, logos). See [Charts](./charts.md).
:::

On `core` an SVG source paints nothing (0 × 0). If you only need a few icons on `core`, rasterise them
once (for example with `standard` in a build step) and ship PNG bytes.

## Images in HTML input

With an HTML source (standard / full), `img` elements work like image nodes: `src` is looked up in
`images` or decoded as a `data:` URL, the `width` / `height` attributes are presentational hints, and
inline `svg` elements in the markup are rendered as SVG images. Note that `&lt;` is needed for a literal
`<` in HTML text:

<!-- @example images#html-img -->
```js
const html = renderer.renderSync(
  `<div style="display:flex;gap:16px;align-items:center;padding:16px;font-family:Inter;font-size:20px;background:#ecfeff;height:100%">
     <img src="photo" width="120" style="border-radius:12px" />
     <img src="${dataUrl}" style="width:60px;height:60px;object-fit:cover;border-radius:50%" />
     <span>&lt;img&gt; in HTML input</span>
   </div>`,
  { width: 520, height: 110, images: [{ src: "photo", data: photo }] },
);
```

![Two img elements in HTML input: a rounded picture and a round avatar](/img/guide/images-html-img.png)

## Animated sources

On `full`, an animated GIF, APNG or animated WebP shows the frame that is current at the render's
`timeMs` (looping over the file's total duration). In `renderAnimation` every frame advances it, so an
animated sticker plays inside an animated output. On `core` an APNG shows its first frame and a GIF
nothing; on `standard` both show their first frame. Here a two-frame GIF (made with
`renderAnimationSync`) is sampled at 0 ms and 700 ms:

<!-- @example images#animated -->
```js
// An animated GIF / APNG / WebP source shows the frame that is current at `timeMs` (full profile).
const fill = (color) => ({ type: "container", style: { width: "100%", height: "100%", backgroundColor: color } });
const gif = renderer.renderAnimationSync({
  scenes: [{ node: fill("#ef4444"), durationMs: 500 }, { node: fill("#3b82f6"), durationMs: 500 }],
  width: 40, height: 40, fps: 2, format: "gif",
});
const at = (timeMs) => renderer.renderSync({ type: "image", src: gif }, { width: 40, height: 40, format: "raw", timeMs });
console.log(at(0).slice(0, 3), at(700).slice(0, 3)); // red at 0 ms, blue at 700 ms
```

See [Animation](./animation.md) for `timeMs` and `renderAnimation`.

## Caching, memory and limits

- **Decode cache.** Each renderer caches decoded images keyed by the content of the bytes, so the same
  logo used in every render (or many times in one tree) is decoded once. When the cache grows beyond
  96 MiB it is cleared at the start of the next render. The budget is fixed: `new Renderer({
  cacheMaxBytes })` and per-image `cache` are accepted and ignored.
- **Copying.** For every render, the bytes of each referenced image are copied into wasm memory (only
  the ones the source mentions). Large images used often therefore cost a copy per render, but not a
  decode.
- **Size limit.** A single decoded image may have at most 24 megapixels (`96 MiB / 4`); larger images
  are not drawn. Resize huge photos before rendering: decoding a 12-megapixel JPEG to draw it at
  400 × 300 is the most common avoidable cost in image-heavy templates.
- **Encoded size matters less than pixels.** Decoding cost scales with pixel count. Prefer sending a
  picture at roughly the size it is drawn (× `devicePixelRatio`).
- **Lossless output of photos is large.** A photo in a PNG or WebP output compresses poorly; use
  `format: "jpeg"` for photo-heavy cards (see [Formats](./formats.md)).
- **Reuse one renderer.** The cache lives in the renderer; a new renderer per request decodes everything
  again. See [Performance](./performance.md).

See also: [CSS support → Images and SVG](./css-support.md#images-and-svg),
[Troubleshooting → Images do not appear](./troubleshooting.md#images-do-not-appear).
