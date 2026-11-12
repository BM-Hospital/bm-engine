# Effects

[English](effects.md) · [Tiếng Việt](../vi/effects.md)

The visual effects bm-engine paints: gradients, borders and radius, outlines, box and text shadows,
gradient text and text stroke, filters, opacity, 2D transforms, clip paths, masks, blend modes and
backdrop filters. Each section has a small example and states the profile it needs; most effects are in
every profile, while clip-path, masks, blend modes, backdrop-filter and modern colour spaces need
**standard** or **full** (`features.effects`, `features.modernColor`). All examples are sections of
`docs/examples/effects.mjs` in the repository and the images are its output.

- [Setup](#setup)
- [Gradients](#gradients) · [Colour spaces](#colour-spaces)
- [Borders and border-radius](#borders-and-border-radius) · [Outline](#outline)
- [Box shadows](#box-shadows)
- [Text effects](#text-effects)
- [Filters](#filters)
- [Opacity](#opacity)
- [Transforms](#transforms)
- [clip-path](#clip-path)
- [Masks](#masks)
- [Blend modes](#blend-modes)
- [backdrop-filter](#backdrop-filter)
- [Profile summary](#profile-summary)

## Setup

The examples render on the `full` entry and use two small helpers: `tile(label, style, children)`
draws a labelled 130 × 90 box and `grid(tiles)` lays tiles out in rows.

<!-- @example effects#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

// A labelled demo tile and a wrapping grid of tiles, used by every example below.
const tile = (label, style, children = []) => ({
  type: "container",
  style: { display: "flex", flexDirection: "column", alignItems: "center", gap: 6 },
  children: [
    { type: "container", style: { display: "flex", width: 130, height: 90, alignItems: "center", justifyContent: "center", ...style }, children },
    { type: "text", text: label, style: { fontSize: 12, color: "#334155" } },
  ],
});
const grid = (tiles, background = "#f8fafc") => ({
  type: "container",
  style: { display: "flex", flexWrap: "wrap", gap: 18, padding: 18, width: "100%", height: "100%", backgroundColor: background, fontFamily: "Inter" },
  children: tiles,
});
```

## Gradients

`linear-gradient()`, `radial-gradient()`, `conic-gradient()` and their `repeating-*` variants work in
`backgroundImage` on every profile, and in `maskImage` on standard / full (`border-image` is not
supported at all). Colour stops
accept positions, double positions (`#facc15 33% 66%`) for hard stops, and hints. Several layers can be
stacked with commas; the first layer is on top.

<!-- @example effects#gradients -->
```js
const gradients = renderer.renderSync(grid([
  tile("linear-gradient", { backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)" }),
  tile("hard stops", { backgroundImage: "linear-gradient(90deg, #ef4444 33%, #facc15 33% 66%, #22c55e 66%)" }),
  tile("radial-gradient", { backgroundImage: "radial-gradient(circle at 30% 30%, #fde68a, #f59e0b 40%, #7c2d12)" }),
  tile("conic-gradient", { backgroundImage: "conic-gradient(from 90deg, #22d3ee, #a855f7, #f43f5e, #22d3ee)" }),
  tile("repeating-linear", { backgroundImage: "repeating-linear-gradient(45deg, #0f172a 0 10px, #fbbf24 10px 20px)" }),
  tile("repeating-radial", { backgroundImage: "repeating-radial-gradient(circle, #e0e7ff 0 8px, #6366f1 8px 16px)" }),
  tile("repeating-conic", { backgroundImage: "repeating-conic-gradient(#0f172a 0 25%, #f1f5f9 0 50%)", backgroundSize: "30px 30px" }),
  tile("layers", { backgroundColor: "#0b1020", backgroundImage: "radial-gradient(ellipse 80% 60% at 70% 20%, rgba(139,92,246,.8), transparent 70%), radial-gradient(ellipse 70% 60% at 20% 80%, rgba(236,72,153,.7), transparent 70%)" }),
]), { width: 640, height: 260 });
```

![Linear, hard-stop, radial, conic, repeating linear, repeating radial and repeating conic gradients, and two layered radial gradients](/img/guide/effects-gradients.png)

Notes:

- Directions: angles (`135deg`, `0.25turn`) and keywords (`to right`, `to bottom left`). Radial
  gradients take `circle` / `ellipse`, sizes (`closest-side`, `farthest-corner`, lengths, percentages)
  and `at <position>`; conic gradients take `from <angle>` and `at <position>`.
- `backgroundSize` and `backgroundRepeat` tile gradients like images (the checkerboard tile is a
  `repeating-conic-gradient` at `30px 30px`).
- Gradient interiors may differ from takumi by one colour level (benchmark: 7 / 7 gradient fixtures
  equivalent).

### Colour spaces

On `standard` and `full` a gradient can interpolate in another colour space (`in oklab`, `in oklch`,
`in srgb-linear`, ... with `shorter` / `longer hue`), and colours can be written with `oklch()`,
`oklab()`, `lab()`, `lch()`, `color()`, `color-mix()` and `light-dark()`:

<!-- @example effects#interpolation -->
```js
const interpolation = renderer.renderSync(grid([
  tile("sRGB (default)", { width: 280, backgroundImage: "linear-gradient(90deg, #2563eb, #facc15)" }),
  tile("in oklab", { width: 280, backgroundImage: "linear-gradient(in oklab 90deg, #2563eb, #facc15)" }),
  tile("in oklch longer hue", { width: 280, backgroundImage: "linear-gradient(in oklch longer hue 90deg, #ff5f6d, #ffc371)" }),
  tile("color-mix() / oklch()", { width: 280, backgroundImage: "linear-gradient(90deg, oklch(70% 0.2 145), color-mix(in oklab, #2563eb 40%, white))" }),
]), { width: 640, height: 260 });
```

![The same blue-to-yellow gradient in sRGB and in oklab, an oklch longer-hue rainbow and modern colour functions](/img/guide/effects-interpolation.png)

On `core`, an interpolation space is ignored (the gradient is interpolated in sRGB), and modern colour
functions are invalid values: in an inline style they make the render throw
`invalid value for style property ...`.

## Borders and border-radius

All CSS border styles are drawn on every profile, following Chromium's border painter:

<!-- @example effects#borders -->
```js
const borderStyles = ["solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset"];
const borders = renderer.renderSync(grid([
  ...borderStyles.map((s) => tile(s, { border: `8px ${s} #6366f1`, backgroundColor: "white" })),
]), { width: 640, height: 260 });
```

![Eight boxes with solid, dashed, dotted, double, groove, ridge, inset and outset borders](/img/guide/effects-borders.png)

`borderRadius` takes one to four values, percentages and the elliptical `/` syntax; every corner and the
logical corners (`borderStartStartRadius`, ...) can be set separately. The radius clips the background,
and with `overflow: "hidden"` also the children:

<!-- @example effects#radius -->
```js
const radius = renderer.renderSync(grid([
  tile("borderRadius: 16", { borderRadius: 16, backgroundColor: "#0ea5e9" }),
  tile("50% (ellipse)", { borderRadius: "50%", backgroundColor: "#0ea5e9" }),
  tile("per corner", { borderRadius: "40px 0 40px 0", backgroundColor: "#0ea5e9" }),
  tile("elliptical 60px / 20px", { borderRadius: "60px / 20px", backgroundColor: "#0ea5e9" }),
  tile("radius + border", { borderRadius: 24, border: "6px solid #0369a1", backgroundColor: "#bae6fd" }),
  tile("mixed border colours", { borderRadius: 45, borderWidth: 10, borderStyle: "solid", borderColor: "#ef4444 #f59e0b #22c55e #3b82f6" }),
  tile("outline + offset", { borderRadius: 12, backgroundColor: "#fde68a", outline: "3px dashed #b45309", outlineOffset: 6 }),
  tile("overflow clip", { borderRadius: 30, overflow: "hidden", backgroundColor: "#e2e8f0", alignItems: "flex-start" },
    [{ type: "container", style: { width: 130, height: 40, backgroundColor: "#0f172a" } }]),
]), { width: 640, height: 260 });
```

![Rounded boxes: a fixed radius, 50 % ellipse, per-corner radii, an elliptical radius, a radius with a border, four border colours, an outline with offset and overflow clipping](/img/guide/effects-radius.png)

### Outline

`outline` (width, style, colour) is drawn outside the border box and follows the border radius;
`outlineOffset` moves it out (or in, with a negative value). `outlineOffset` in percent is not
supported. Outlines take no space in the layout. Every profile.

## Box shadows

`boxShadow` takes any number of shadows with offset, blur, spread, colour and `inset`; shadows follow
the border radius. Every profile.

<!-- @example effects#shadows -->
```js
const card = { backgroundColor: "white", borderRadius: 14 };
const shadows = renderer.renderSync(grid([
  tile("soft", { ...card, boxShadow: "0 10px 25px rgba(15,23,42,.25)" }),
  tile("hard offset", { ...card, border: "2px solid #0f172a", boxShadow: "6px 6px 0 #0f172a" }),
  tile("spread ring", { ...card, boxShadow: "0 0 0 6px #a5b4fc" }),
  tile("inset", { ...card, backgroundColor: "#e2e8f0", boxShadow: "inset 0 6px 14px rgba(0,0,0,.35)" }),
  tile("multiple", { ...card, boxShadow: "0 0 0 3px #f472b6, 0 0 0 7px #fbcfe8, 0 12px 20px rgba(0,0,0,.3)" }),
  tile("coloured glow", { ...card, backgroundColor: "#7c3aed", boxShadow: "0 0 30px 6px rgba(124,58,237,.7)" }),
], "#f1f5f9"), { width: 640, height: 260 });
```

![A soft shadow, a hard offset shadow, a spread ring, an inset shadow, stacked rings and a coloured glow](/img/guide/effects-shadows.png)

A zero-blur spread shadow (`0 0 0 6px`) is the usual way to draw a "ring" around a box without
changing its size (Tailwind's `ring-*` utilities are not supported, see
[HTML and Tailwind](./html-and-tailwind.md)).

## Text effects

`textShadow` (several shadows, blur), `WebkitTextStroke` (outline text, with `paintOrder`), and
gradient text with `backgroundClip: "text"` plus a transparent `color`:

<!-- @example effects#text-effects -->
```js
const big = { fontSize: 40, fontWeight: 700 };
const text = (t, style) => ({ type: "text", text: t, style: { ...big, ...style } });
const textEffects = renderer.renderSync({
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 14, padding: 20, width: "100%", height: "100%", backgroundColor: "#0f172a", fontFamily: "Inter" },
  children: [
    text("Neon glow", { color: "#fff", textShadow: "0 0 6px #fff, 0 0 18px #ff2d95, 0 0 42px #ff2d95" }),
    text("Hard shadow", { color: "#fbbf24", textShadow: "3px 3px 0 #b91c1c" }),
    text("Outlined", { color: "transparent", WebkitTextStroke: "1.5px #38bdf8" }),
    { type: "container", style: { display: "flex" }, children: [
      text("Gradient text", { backgroundImage: "linear-gradient(90deg, #f97316, #ec4899, #8b5cf6)", backgroundClip: "text", color: "transparent" }),
    ] },
  ],
}, { width: 640, height: 280 });
```

![Neon glowing text, a hard text shadow, outlined text and gradient text](/img/guide/effects-text-effects.png)

All four work on every profile (gradient text was checked on `core` too). For gradient text, put the
text node in a container that does not stretch it (the flex row above), otherwise the gradient spans
the whole stretched width. Decorations, `text-transform` and other typography are covered in
[Typography](./typography.md).

## Filters

`filter` applies to the element and its children: `blur()`, `brightness()`, `contrast()`,
`grayscale()`, `hue-rotate()`, `invert()`, `opacity()`, `saturate()`, `sepia()` and
`drop-shadow()`, in any combination (they apply in order). Every profile. `filter: url(...)` (SVG
filters by reference) is not supported.

<!-- @example effects#filters -->
```js
const sample = {
  backgroundImage: "linear-gradient(135deg, #ef4444, #facc15 50%, #22c55e)",
  borderRadius: 12,
};
const filters = renderer.renderSync(grid([
  tile("none", sample),
  tile("blur(4px)", { ...sample, filter: "blur(4px)" }),
  tile("grayscale(1)", { ...sample, filter: "grayscale(1)" }),
  tile("sepia(1)", { ...sample, filter: "sepia(1)" }),
  tile("hue-rotate(180deg)", { ...sample, filter: "hue-rotate(180deg)" }),
  tile("invert(1)", { ...sample, filter: "invert(1)" }),
  tile("brightness(.6) contrast(1.5)", { ...sample, filter: "brightness(.6) contrast(1.5)" }),
  tile("drop-shadow", { filter: "drop-shadow(4px 6px 3px rgba(0,0,0,.5))" },
    [{ type: "text", text: "★", style: { fontSize: 64, color: "#f59e0b" } }]),
]), { width: 640, height: 260 });
```

![A gradient box with no filter, blur, grayscale, sepia, hue-rotate, invert and brightness plus contrast, and a star with a drop-shadow](/img/guide/effects-filters.png)

`drop-shadow()` follows the alpha shape of the content (the star glyph), unlike `boxShadow`, which
follows the box. Filters also work on image nodes (see [Images](./images.md#styling-images)).

## Opacity

`opacity` makes the element and everything inside it translucent as a group. To make only the
background translucent, use an `rgba()` / `#rrggbbaa` colour instead. Every profile.

<!-- @example effects#opacity -->
```js
const opacity = renderer.renderSync(grid([
  tile("opacity: 1", { backgroundColor: "#2563eb" }),
  tile("opacity: .6", { backgroundColor: "#2563eb", opacity: 0.6 }),
  tile("opacity: .25", { backgroundColor: "#2563eb", opacity: 0.25 }),
  tile("rgba() background", { backgroundColor: "rgba(37,99,235,.25)" },
    [{ type: "text", text: "text stays opaque", style: { fontSize: 13 } }]),
]), { width: 640, height: 140 });
```

![The same blue box at opacity 1, 0.6 and 0.25, and a translucent rgba background with opaque text](/img/guide/effects-opacity.png)

## Transforms

2D transforms work on every profile: `translate*()`, `rotate()`, `scale*()`, `skew*()`, `matrix()`,
the individual `translate`, `rotate` and `scale` properties, and `transformOrigin` (default
`50% 50%`). Transforms do not affect layout; they move the painted result.

<!-- @example effects#transforms -->
```js
const square = (transform, extra = {}) => [{
  type: "container",
  style: { width: 50, height: 50, backgroundColor: "#f43f5e", border: "2px solid #881337", transform, ...extra },
}];
const transforms = renderer.renderSync(grid([
  tile("rotate(30deg)", { backgroundColor: "#ffe4e6" }, square("rotate(30deg)")),
  tile("scale(1.4, .7)", { backgroundColor: "#ffe4e6" }, square("scale(1.4, .7)")),
  tile("skewX(-20deg)", { backgroundColor: "#ffe4e6" }, square("skewX(-20deg)")),
  tile("translate(30px, 15px)", { backgroundColor: "#ffe4e6" }, square("translate(30px, 15px)")),
  tile("origin: top left", { backgroundColor: "#ffe4e6" }, square("rotate(25deg)", { transformOrigin: "top left" })),
  tile("rotate: 45deg + scale: .8", { backgroundColor: "#ffe4e6" }, square(undefined, { rotate: "45deg", scale: 0.8 })),
  tile("matrix(...)", { backgroundColor: "#ffe4e6" }, square("matrix(1, .3, -.3, 1, 0, 0)")),
  tile("rotated text", { backgroundColor: "#ffe4e6" },
    [{ type: "text", text: "SALE", style: { fontSize: 28, fontWeight: 700, color: "#be123c", transform: "rotate(-12deg)" } }]),
]), { width: 640, height: 260 });
```

![Squares rotated, scaled, skewed, translated, rotated around the top-left corner, with individual rotate and scale properties, a matrix, and rotated text](/img/guide/effects-transforms.png)

::: warning No 3D transforms
3D functions (`rotateX()`, `rotateY()`, `perspective()`, `matrix3d()`, `translateZ()`, ...) are invalid
values, as in takumi. In an inline style they make the whole render throw:
:::

<!-- @example effects#transform-3d -->
```js
const message = expectThrow(() =>
  renderer.renderSync({ type: "container", style: { width: 10, height: 10, transform: "rotateX(45deg)" } }, { width: 10, height: 10 }),
);
console.log(message); // bm-engine: invalid value for style property transform
```

In a stylesheet or `tw` class the invalid declaration is dropped instead (CSS error recovery).

## clip-path

`clipPath` cuts the element and its children to a shape: `inset()` (with
`round`), `circle()`, `ellipse()`, `polygon()` and `path()`, optionally with a geometry box
(`border-box`, `padding-box`, `content-box`, ...). Needs **standard** or **full**; `path()` uses the SVG
code, which both have.

<!-- @example effects#clip-path -->
```js
const photoLike = { backgroundImage: "linear-gradient(135deg, #06b6d4, #3b82f6 50%, #a855f7)" };
const clipPaths = renderer.renderSync(grid([
  tile("circle(40%)", { ...photoLike, clipPath: "circle(40%)" }),
  tile("ellipse(50% 35%)", { ...photoLike, clipPath: "ellipse(50% 35%)" }),
  tile("polygon (triangle)", { ...photoLike, clipPath: "polygon(50% 0, 100% 100%, 0 100%)" }),
  tile("polygon (arrow)", { ...photoLike, clipPath: "polygon(0 30%, 60% 30%, 60% 0, 100% 50%, 60% 100%, 60% 70%, 0 70%)" }),
  tile("inset(10px round 20px)", { ...photoLike, clipPath: "inset(10px 20px round 20px)" }),
  tile("path()", { ...photoLike, clipPath: "path('M65 80 C10 45 20 5 65 30 C110 5 120 45 65 80Z')" }),
]), { width: 640, height: 260 });
```

![A gradient clipped to a circle, an ellipse, a triangle, an arrow, a rounded inset and a heart-shaped path](/img/guide/effects-clip-path.png)

`clip-path: url(#id)` (a reference to an SVG clip path) is not supported. Note that `path()`
coordinates are pixels in the element's border box and do not scale with it.

## Masks

`maskImage` (and the other `mask*` / `WebkitMask*` properties: `maskSize`, `maskPosition`,
`maskRepeat`, `maskMode`, `maskOrigin`, `maskClip`, `maskType`) uses the alpha of a gradient or an image
(including SVG) to fade or cut the element. Needs **standard** or **full**.

<!-- @example effects#masks -->
```js
const masks = renderer.renderSync(grid([
  tile("linear fade", { ...photoLike, maskImage: "linear-gradient(to right, black, transparent)" }),
  tile("radial spotlight", { ...photoLike, maskImage: "radial-gradient(circle, black 40%, transparent 70%)" }),
  tile("repeating stripes", { ...photoLike, maskImage: "repeating-linear-gradient(90deg, black 0 8px, transparent 8px 14px)" }),
  tile("SVG mask image", {
    ...photoLike,
    maskImage: `url("data:image/svg+xml;utf8,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 2l3 7h7l-5.5 4.5 2 7.5-6.5-4.5-6.5 4.5 2-7.5L2 9h7z"/></svg>')}")`,
    maskSize: "contain", maskRepeat: "no-repeat", maskPosition: "center",
  }),
]), { width: 640, height: 140 });
```

![A gradient faded with a linear mask, a radial spotlight mask, a striped mask and a star-shaped SVG mask](/img/guide/effects-masks.png)

`maskComposite` is accepted and ignored: several mask layers are always combined with `add`.

## Blend modes

`mixBlendMode` blends an element with what is painted below it, using the 16 CSS blend modes plus
`plus-lighter` and `plus-darker`; `backgroundBlendMode` blends background layers with each other;
`isolation: "isolate"` limits blending to a group. Needs **standard** or **full**.

<!-- @example effects#blend -->
```js
const blendModes = ["normal", "multiply", "screen", "overlay", "darken", "lighten", "difference", "exclusion"];
const circles = (mode) => [
  { type: "container", style: { position: "absolute", left: 25, top: 10, width: 55, height: 55, borderRadius: 30, backgroundColor: "#f43f5e" } },
  { type: "container", style: { position: "absolute", left: 50, top: 25, width: 55, height: 55, borderRadius: 30, backgroundColor: "#22d3ee", mixBlendMode: mode } },
];
const blend = renderer.renderSync(grid(
  blendModes.map((mode) => tile(mode, { position: "relative", backgroundColor: "#facc15", isolation: "isolate" }, circles(mode))),
), { width: 640, height: 260 });
```

![A cyan circle over a red circle on yellow with the blend modes normal, multiply, screen, overlay, darken, lighten, difference and exclusion](/img/guide/effects-blend.png)

The circles are positioned absolutely, so each tile has `position: "relative"`: without it, every
circle would be placed against the canvas.

## backdrop-filter

`backdropFilter` (also `WebkitBackdropFilter`) applies filters to what is behind the element, inside
its border box and radius: the "frosted glass" effect. Give the element a translucent background so
that the filtered backdrop shows through. Needs **standard** or **full**.

<!-- @example effects#backdrop -->
```js
const backdrop = renderer.renderSync({
  type: "container",
  style: {
    display: "flex", gap: 24, padding: 30, width: "100%", height: "100%", alignItems: "center", fontFamily: "Inter",
    backgroundImage: "radial-gradient(circle at 20% 30%, #f97316 0 60px, transparent 61px), radial-gradient(circle at 75% 70%, #8b5cf6 0 80px, transparent 81px), linear-gradient(#0ea5e9, #1e3a8a)",
  },
  children: ["blur(8px)", "blur(8px) saturate(1.8)", "grayscale(1)"].map((f) => ({
    type: "container",
    style: {
      display: "flex", width: 170, height: 120, alignItems: "center", justifyContent: "center", borderRadius: 18,
      backgroundColor: "rgba(255,255,255,.18)", border: "1px solid rgba(255,255,255,.5)", backdropFilter: f,
    },
    children: [{ type: "text", text: f, style: { color: "white", fontSize: 14, fontWeight: 700 } }],
  })),
}, { width: 640, height: 180 });
```

![Three translucent cards over coloured circles with backdrop filters blur, blur plus saturate, and grayscale](/img/guide/effects-backdrop.png)

## Profile summary

| Effect | core | standard | full |
|:--|:-:|:-:|:-:|
| Gradients (all kinds, repeating, layered) | ✓ | ✓ | ✓ |
| Gradient interpolation spaces, `oklch()` / `lab()` / `color-mix()` / `light-dark()` | sRGB / throws | ✓ | ✓ |
| Border styles, `borderRadius`, `outline`, `overflow` clipping | ✓ | ✓ | ✓ |
| `boxShadow`, `textShadow`, `WebkitTextStroke`, `backgroundClip: "text"` | ✓ | ✓ | ✓ |
| `filter`, `opacity`, 2D transforms | ✓ | ✓ | ✓ |
| `clipPath`, `maskImage`, `mixBlendMode`, `backgroundBlendMode`, `isolation`, `backdropFilter` | ignored | ✓ | ✓ |
| 3D transforms, `filter: url()`, `clip-path: url()` | — | — | — |

"ignored" means the property is accepted without an error and has no effect. The example script checks
this for `clipPath`: the same clipped tile on `core` and on `full`:

<!-- @example effects#core-ignores -->
```js
// The same clipped tile on core and on full: core accepts clipPath but ignores it.
const clipped = { type: "container", style: { width: 40, height: 40, backgroundColor: "red", clipPath: "circle(10px)" } };
const corner = (r) => r.renderSync(clipped, { width: 40, height: 40, format: "raw" }).slice(0, 4);
const coreRenderer = new core.Renderer();
console.log("core:", corner(coreRenderer), "full:", corner(renderer)); // core: 255,0,0,255  full: 0,0,0,0
```

See also: [CSS support → Shadows and effects](./css-support.md#shadows-and-effects),
[Profiles and size](./profiles-and-size.md), [Animation](./animation.md).
