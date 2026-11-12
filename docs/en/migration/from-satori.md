# Migrating from satori and next/og

[English](from-satori.md) · [Tiếng Việt](../../vi/migration/from-satori.md)

[satori](https://github.com/vercel/satori) turns JSX into an SVG string; a second tool such as
`@resvg/resvg-js` (or sharp) turns the SVG into a PNG, and `next/og` / `@vercel/og` package both steps
behind `ImageResponse`. bm-engine replaces the whole pipeline with one call that returns PNG, JPEG or
WebP bytes directly (or SVG with `renderSvg`). This page shows how each piece maps, how to bring your
JSX along, and what each side can do that the other cannot.

::: info Verification status
Everything stated about bm-engine was executed on Node 26.13 (`docs/examples/frameworks/check-helpers.mjs`:
the `h()` JSX factory through esbuild, `flexByDefault()`, `renderSvg` + PNG output). satori, resvg and
`next/og` were **not installed or run**: statements about them are widely known characteristics of
those projects at the time of writing, hedged where versions differ — check their current READMEs.
:::

## The pipeline, side by side

```js
// before: satori + resvg
import satori from "satori";
import { Resvg } from "@resvg/resvg-js";

const svg = await satori(<Card title="Hello" />, {
  width: 1200,
  height: 630,
  fonts: [{ name: "Inter", data: interBytes, weight: 400, style: "normal" }],
});
const png = new Resvg(svg).render().asPng();
```

```js
// after: bm-engine
import { Renderer } from "bm-engine/standard";
import { h } from "./h.js"; // JSX factory, see below

const renderer = new Renderer(); // once per process
renderer.registerFont({ name: "Inter", data: interBytes, weight: 400, style: "normal" });

const png = renderer.renderSync(Card({ title: "Hello" }), { width: 1200, height: 630 });
// need the SVG too?  renderer.renderSvgSync(node, { width: 1200, height: 630 })  (full profile)
```

| satori / resvg / next/og | bm-engine |
|:--|:--|
| `satori(element, { width, height, fonts })` → SVG | `renderer.renderSvgSync(node, { width, height })` → SVG (`full` profile); text becomes outlines, as in satori's default output |
| `new Resvg(svg).render().asPng()` | not needed: `renderer.renderSync(node, options)` returns PNG (`format: "jpeg" \| "webp"` for others) |
| `fonts: [...]` on every call | `registerFont(...)` once per renderer (the `fonts` render option also exists) |
| `new ImageResponse(element, options)` | `new Response(bytes, { headers })` or the [`imageResponse()` helper](../frameworks/index.md#an-imageresponse-helper) |
| `loadAdditionalAsset` (dynamic fonts / emoji) | no callback: register fallback fonts up front ([fallback chain](../recipes.md#i18n-font-fallback-chain)); colour emoji from a registered emoji font on `full` |
| `graphemeImages` | no equivalent; use `image` nodes |
| `debug: true` | `drawDebugBorder` is accepted and ignored |
| `tw` prop (satori's Tailwind support) | `tw` on nodes, `standard` / `full` profile; class coverage follows takumi's table, not satori's |

## Converting JSX

satori consumes React elements. bm-engine consumes plain node objects. Choose one:

1. **Compile your card files with the [`h()` factory](../frameworks/index.md#node-trees-without-jsx).**
   With esbuild `--jsx-factory=h --jsx-fragment=Fragment`, TypeScript `"jsxFactory": "h"`, or a
   `/** @jsx h */` pragma, `<div style={...}>` becomes a container node, strings become text nodes and
   `<img src>` an image node. Verified with esbuild 0.28.2. Function components work (they are called
   with their props); hooks and context do not.
2. **Convert React elements** with takumi's `fromJsx()` from `@takumi-rs/helpers`, which also maps HTML
   elements to takumi's default presets (see [Migrating from takumi → JSX](./from-takumi.md#jsx)).
3. **Render to HTML** with `react-dom/server` and pass the string (`standard` / `full`); HTML input gets
   user-agent styles for `h1`, `p`, ... like a browser. See [HTML and Tailwind](../html-and-tailwind.md).

### `display: flex` everywhere

satori (and therefore `next/og`) treats every element as a flex container. bm-engine follows CSS and
takumi: every node is `display: inline` until you say otherwise, and inline containers ignore `width` /
`height`. Templates written for satori often rely on the flex default, so either add `display: "flex"`
where needed, or apply satori's default to the whole tree:

```js
export function flexByDefault(node) {
  if (!node || node.type !== "container") return node;
  return { ...node, style: { display: "flex", ...node.style }, children: node.children?.map(flexByDefault) };
}

renderer.renderSync(flexByDefault(Card({ title: "Hello" })), { width: 1200, height: 630 });
```

Verified: a 400 × 200 container with two 100 × 50 children and no `display` measured as one inline
line with no child boxes; after `flexByDefault()` the children sat in a row at x = 0 and x = 100.

## Fonts

- satori requires `fonts` and reads TTF, OTF and WOFF (not WOFF2, as far as its README states).
  bm-engine reads TTF on every profile, OTF (CFF) and WOFF / WOFF2 on `standard` / `full`, WOFF / WOFF2 on
  `core` through the [WOFF add-on](../api.md#woff-add-on).
- Like satori, bm-engine has no system fonts and no default font: text without a registered font is not
  drawn (no error).
- Variable fonts follow `font-weight` / `font-variation-settings` on `standard` / `full`.
- Register fonts **once** per renderer instead of passing the bytes on every call; parsing them is the
  expensive part.

## What bm-engine adds

Verified on the bm-engine side (see the [CSS support](../css-support.md) matrix for details):

- Direct raster output: PNG, JPEG, WebP, raw RGBA (and ICO on `full`) — no resvg step.
- Layout beyond flexbox: block, inline, grid, floats and tables (`tables` / `floats` on `standard`).
- Stylesheets (`css` option, HTML `<style>`), selectors, `@media` against the canvas, Tailwind via `tw`.
- HTML strings as input (`standard` / `full`).
- CSS animations rendered to animated WebP / APNG / GIF (`full`), or a single frame with `timeMs`.
- Bidi and complex scripts (Arabic, Hebrew, Indic, Thai) and colour emoji fonts on `full`.
- `measure()` for layout boxes and text line runs (see [Measure](../measure.md)).
- Synchronous API, no dependencies, one `.wasm` per profile (454.9 KiB – 1.08 MiB raw).

## What satori has that bm-engine does not

Hedged — based on satori's documented features, not on running it:

- Accepts React elements directly (bm-engine needs a conversion step, above).
- The `loadAdditionalAsset` callback to fetch fonts or emoji images on demand while rendering.
- `graphemeImages` to map characters to images.
- A JavaScript-only distribution of the layout step (satori uses Yoga compiled to WebAssembly; resvg is a
  separate binary or wasm module) — bm-engine is one WebAssembly binary you load with `init` on
  non-Node runtimes.
- A larger ecosystem: `next/og` is built in to Next.js, and many templates target satori's flex-default
  behaviour.

## Checklist

- Replace `satori` + `resvg` with one `Renderer`, created once, fonts registered once.
- Convert JSX with `h()`, `fromJsx()` or HTML; add `display: "flex"` (or `flexByDefault()`).
- Replace `ImageResponse` with a `Response` (or `imageResponse()`), and set `content-type`.
- Replace `loadAdditionalAsset` / emoji options with registered fallback and emoji fonts.
- Pick a profile: `core` for inline-style node trees with TTF fonts, `standard` for Tailwind / HTML /
  WOFF2, `full` for SVG output, emoji and complex scripts.
- Compare a few outputs visually: the engines lay out text differently, so line breaks can move.
