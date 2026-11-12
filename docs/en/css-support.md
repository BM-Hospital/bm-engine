# CSS and feature support

[English](css-support.md) · [Tiếng Việt](../vi/css-support.md)

What bm-engine 0.1.0 renders, which build profile each feature needs, and how closely the output matches
takumi 2.20. "Status" comes from the equivalence benchmark (250 fixtures rendered by both engines and
compared pixel by pixel, plus per-module oracle tests; see [Benchmark](benchmark.md)):
**identical** = byte-identical output, **equivalent** = SSIM ≥ 0.99 and ≤ 0.5 % of pixels differ (in
practice: anti-aliasing at curved edges and glyph edges), **close** = SSIM ≥ 0.95, **partial** = works
with documented gaps, **no** = not supported. The minimum profile is the smallest build that contains
the feature; `full` contains everything. The complete list of property names is in the
[appendix](#appendix-supported-property-names).

- [Conventions](#conventions)
- [Layout](#layout)
- [Box model and sizing](#box-model-and-sizing)
- [Backgrounds and gradients](#backgrounds-and-gradients)
- [Borders and outline](#borders-and-outline)
- [Shadows and effects](#shadows-and-effects)
- [Transforms](#transforms)
- [Text](#text)
- [Fonts](#fonts)
- [Colours](#colours)
- [Values, units, custom properties](#values-units-custom-properties)
- [Stylesheets and selectors](#stylesheets-and-selectors)
- [Tailwind](#tailwind)
- [HTML input](#html-input)
- [Animations](#animations)
- [Images and SVG](#images-and-svg)
- [Complex scripts, bidi, emoji](#complex-scripts-bidi-emoji)
- [Known gaps](#known-gaps)
- [Appendix: supported property names](#appendix-supported-property-names)

## Conventions

- Inline styles use camelCase keys (`backgroundColor`); stylesheets, HTML `style=""` attributes and
  Tailwind use normal CSS syntax. Every property accepts `inherit`, `initial`, `unset`, `revert`,
  `var()` and math functions.
- Defaults follow takumi (which follows Blink): **`display: inline`** for every node, **`box-sizing:
  border-box`**, `object-fit: fill`, transparent canvas. The root node and flex / grid items are
  blockified.
- Layout runs in device pixels with 1/64 px precision (Blink `LayoutUnit`), and pixel snapping happens
  at paint time, as in takumi; `measure()` matches takumi to within 0.001 px on the layout fixtures.

## Layout

| Feature | Min. profile | Status |
|:--|:--|:--|
| Block layout, margin collapsing, `flow-root` | core | identical / equivalent |
| Inline formatting (text runs, `inline`, `inline-block`, `inline-flex`, `inline-grid`, `vertical-align`) | core | equivalent (atomic inlines take part in line breaking mid-line with every `vertical-align`; inline span padding / border / margin push text; per-span `white-space`, `<br>`, per-box struts; `inline-flow` / `inline-box-model` fixtures at SSIM ≥ 0.9999); see [known gaps](#known-gaps) |
| Flexbox (direction, wrap, grow / shrink / basis, `gap`, alignment incl. `safe`, `order`, `-webkit-box`) | core | identical (5/5 fixtures) |
| `direction: rtl` / `dir="rtl"` on boxes: flex rows, grid columns, table columns and block alignment are mirrored | core | equivalent; the text inside is laid out right to left only on `full` (bidi); `justify-self: left / right` is not mirrored |
| Grid: tracks, `repeat()` incl. `auto-fill` / `auto-fit`, `fr`, `minmax()`, auto-placement, spans | core | equivalent (4/4) |
| Grid: named lines, `grid-template-areas`, `grid-area` | core | equivalent (3/3) |
| `position: relative / absolute / fixed`, `inset`, `z-index` | core | identical / equivalent (3/3); `fixed` is positioned against the canvas |
| `position: sticky` | core | parsed, behaves like `relative` (no scrolling) |
| `aspect-ratio`, `min-*` / `max-*`, `fit-content` / `min-content` / `max-content`, logical sizes | core | identical (5/5 sizing fixtures) |
| `overflow: hidden / clip` (incl. rounded clipping) | core | equivalent |
| Tables (`display: table*`, auto / fixed layout, `colspan` / `rowspan` via HTML, `border-collapse`, `border-spacing`, captions, `empty-cells`) | standard | equivalent (8/8 fixtures; 339/352 layout oracle cases) |
| Floats (`float`, `clear`) | standard (`floats` flag; also `full`) | equivalent; 138/138 layout oracle cases; text flows around floats (line boxes shorten beside a float and re-widen below it, floats inside inline content, RTL; 7 `float-text` fixtures at SSIM ≥ 0.9999) |
| `display: contents` | core | supported, following Chrome: the element generates no box and its children take part in the parent's layout (takumi does not support the value: it drops it from stylesheets and throws for inline style) |
| `display: list-item` | core | laid out as a block; no list marker |
| Writing modes (`writing-mode`) | — | no: parsed, horizontal layout only |

On `core`, `display: table*` lays out like `block` and `float` is ignored (no error).

## Box model and sizing

| Feature | Min. profile | Status |
|:--|:--|:--|
| `width` / `height` / `min-*` / `max-*` (px, %, em, rem, vw, vh, `auto`, `fit-content`, ...) | core | identical |
| `margin` (incl. `auto`), `padding`, logical forms (`marginInline`, `paddingBlockStart`, ...) | core | identical |
| `box-sizing: border-box` (default) / `content-box` | core | identical |
| `visibility: hidden / collapse` | core | identical |
| `opacity` | core | equivalent (4/4) |

## Backgrounds and gradients

| Feature | Min. profile | Status |
|:--|:--|:--|
| `background-color`, `background` shorthand, multiple layers | core | identical |
| `linear-gradient`, `radial-gradient`, `conic-gradient`, `repeating-*` | core | equivalent (7/7 fixtures; inner stops may differ by 1 colour level) |
| `background-image: url(...)`, `background-size` / `-position` / `-repeat` (incl. `space`, `round`) / `-origin` / `-clip` | core | equivalent (images fixtures) |
| `background-clip: text` | core | equivalent |
| Gradient interpolation space (`linear-gradient(in oklab, ...)`) | standard | identical to takumi up to 1–2 levels; ignored on core |
| `background-blend-mode` | standard | identical |

## Borders and outline

| Feature | Min. profile | Status |
|:--|:--|:--|
| `border` widths / colours, all styles: `solid`, `dashed`, `dotted`, `double`, `groove`, `ridge`, `inset`, `outset` | core | identical / equivalent (dashes on rounded corners can be ~0.1 px out of phase) |
| `border-radius` (elliptical, per corner, percentages, logical corners) | core | identical (4/4) |
| `outline`, `outline-offset` (px) | core | equivalent; `outline-offset` in % is not supported |

## Shadows and effects

| Feature | Min. profile | Status |
|:--|:--|:--|
| `box-shadow` (outer, inset, spread, multiple) | core | identical / equivalent (4/4) |
| `text-shadow` | core | equivalent |
| `filter`: `blur()`, `brightness()`, `contrast()`, `grayscale()`, `hue-rotate()`, `invert()`, `opacity()`, `saturate()`, `sepia()`, `drop-shadow()` | core | identical / equivalent; `filter: url(...)` is not supported |
| `backdrop-filter` | standard | identical |
| `mix-blend-mode` (16 modes + `plus-lighter`, `plus-darker`), `isolation` | standard | identical |
| `clip-path`: `inset()`, `circle()`, `ellipse()`, `polygon()` with a geometry box | standard | identical |
| `clip-path: path()` | standard (needs SVG) | supported; `clip-path: url(#id)` is not |
| `mask-image` / `mask-*` / `-webkit-mask-*` (gradients and images, `mask-mode`, `mask-type`) | standard | identical; `mask-composite` is ignored |

On `core` the effect properties of this table that need `standard` are accepted and ignored.

## Transforms

| Feature | Min. profile | Status |
|:--|:--|:--|
| 2D `transform` functions (`translate*`, `rotate`, `scale*`, `skew*`, `matrix`), `transform-origin` | core | equivalent (3/3) |
| Individual `translate`, `rotate`, `scale` properties | core | supported |
| 3D transforms (`rotateX`, `matrix3d`, `perspective()`) | — | no: an inline `transform` with a 3D function throws (as in takumi, which is 2D only) |

## Text

| Feature | Min. profile | Status |
|:--|:--|:--|
| Line breaking (UAX #14), `white-space` (all modes), `word-break`, `overflow-wrap`, `tab-size` | core | equivalent; widths and break positions match takumi (825/825 oracle cases) |
| `text-align` (incl. `justify`), `line-height`, `letter-spacing`, `word-spacing` | core | equivalent |
| `text-transform` | core | equivalent: full Unicode case mapping (`ß` → `SS`, final sigma, ligatures, titlecase digraphs); not done: `lang`-tailored casing (Turkish / Azeri, Greek, Lithuanian), `full-width`, `full-size-kana` |
| `text-indent` (lengths, %, negative, `each-line`, `hanging`, RTL) | core | equivalent; one deliberate difference: takumi also indents a non-first anonymous block (text after a block child), bm-engine and Chrome do not |
| `text-overflow: ellipsis` / `clip` / `"<string>"`, `line-clamp` / `-webkit-line-clamp` (incl. `<n> "<string>"`, `none`, `no-ellipsis`) | core | equivalent; a string marker is shaped with the element's font and fallback and mirrored in RTL (an empty string truncates without a marker); `overflow` clips the element's own glyphs |
| `text-decoration` (line, style incl. `wavy`, colour, thickness), `text-underline-offset` / `-position`, `text-decoration-skip-ink` | core | equivalent |
| `-webkit-text-stroke`, `-webkit-text-fill-color` | core | equivalent (stroke may differ by 1 level); `paint-order` is parsed but the stroke is always painted over the fill, as in takumi 2.20 |
| Inline boxes with background / border / padding, `box-decoration-break` | core | equivalent; horizontal padding / border / margin of a span push the text (first / last fragment edges, `box-decoration-break: clone`) |
| `text-wrap: balance` / `pretty` | standard | identical decisions to takumi (216/216); also with inline boxes, atomic inlines and beside a single leading float |
| Synthetic bold / italic when the face is missing | core | equivalent |
| `font-feature-settings`, `font-variant-*`, `font-kerning`, ligatures (GSUB 1–8, GPOS 1–9) | core | equivalent |
| `font-variant-caps` (`small-caps`, `all-small-caps`, `petite-caps`, `all-petite-caps`, `unicase`, `titling-caps`), `font-synthesis-small-caps` | core | the font's OpenType features when it has them, otherwise synthesised (uppercase at 70 % of the font size); petite caps and unicase fall back to small caps; `font-synthesis-small-caps: none` turns synthesis off |
| Inline boxes: percentage `margin` / `padding`, `position: relative` | core | percentages resolve against the containing block, following Chrome (takumi resolves them to 0); relative offsets shift the inline box |
| `hyphens`, `line-break`, `text-align-last` | — | parsed, no effect in 0.1.0 |

## Fonts

| Feature | Min. profile | Status |
|:--|:--|:--|
| TrueType (`glyf`), collections (`.ttc`) | core | equivalent |
| CFF / CFF2 (`.otf`) | standard | widths within 1/64 px |
| WOFF / WOFF2 | standard (core: [add-on](profiles-and-size.md#the-woff-add-on)) | 17/19 takumi WOFF2 test fonts decode byte-identical to the reference decoder (the other 2 differ by one flag bit) |
| Variable fonts (`fvar`, `avar`, `gvar`, `HVAR`, `MVAR`), `font-variation-settings`, `font-optical-sizing` | standard | 1 400 width comparisons within 1/64 px; on core only the default instance is drawn |
| Colour fonts: COLR v0 / v1 | full | SSIM ≥ 0.991 against Chrome (takumi does not draw COLR v1); `core` / `standard` draw the plain outlines, without colour |
| Bitmap colour fonts: CBDT, sbix | standard | drawn in colour on `standard` and `full`; `core` draws nothing for a bitmap-only font |
| `@font-face` in stylesheets | — | not loaded: register fonts with `registerFont` / `fonts` |

## Colours

| Feature | Min. profile | Status |
|:--|:--|:--|
| Named colours, `#rgb[a]`, `#rrggbb[aa]`, `rgb()` / `rgba()`, `hsl()` / `hsla()`, `hwb()`, `currentColor`, `transparent` | core | identical |
| `lab()`, `lch()`, `oklab()`, `oklch()`, `color()`, `color-mix()`, `light-dark()` | standard | 495/495 colours identical at 8 bits. On core these values are invalid: in an inline style they throw |
| Relative colour syntax (`rgb(from red r g b / 50%)`) | — | no (invalid value) |

## Values, units, custom properties

| Feature | Min. profile | Status |
|:--|:--|:--|
| `px`, `%`, `em`, `rem`, `vw`, `vh`, `vmin`, `vmax`, `pt`, `pc`, `in`, `cm`, `mm`, `Q`, `ch`, `ex`, `lh`, `rlh`, `cq*` | core | identical (DPR semantics as takumi: `vw`/`vh` refer to output pixels) |
| `calc()`, `min()`, `max()`, `clamp()` and other math functions | core | identical |
| Custom properties (`--x`) and `var()` with fallbacks, in inline styles | core | identical |
| `!important` | core | identical |

## Stylesheets and selectors

Pass stylesheets with the `css` option (strings or takumi rule objects `{ selector, style }`) or use
`<style>` in an HTML source. Needs `standard`. Status: 252/252 cascade-winner checks identical to takumi;
4 fixtures (1 identical, 3 equivalent).

- **Selectors**: type, universal, class, id, attribute (all 7 operators, `i` / `s` flags); combinators
  descendant, `>`, `+`, `~`; selector lists; `:root`, `:empty`, `:first-child`, `:last-child`,
  `:only-child`, `:first-of-type`, `:last-of-type`, `:only-of-type`, `:nth-child(An+B [of S])`,
  `:nth-last-child()`, `:nth-of-type()`, `:nth-last-of-type()`, `:not()`, `:is()`, `:where()`, `:has()`,
  `:lang()`, `:dir()`, `:scope`, form states (`:checked`, `:disabled`, ...). Pseudo-elements `::before` /
  `::after` (with `content`, `attr()`).
- Dynamic pseudo-classes (`:hover`, `:focus`, `:visited`, ...) and other pseudo-elements (`::marker`,
  `::placeholder`, `::first-line`, ...) parse but never match, as in takumi.
- **At-rules**: `@media` (`width`, `height`, `aspect-ratio`, `resolution`, `orientation`, range syntax,
  `and` / `or` / `not`; evaluated against the canvas size in CSS px), `@supports`, `@layer`, CSS Nesting
  (`&`), `@keyframes`, `@theme` (Tailwind theme variables), `@import "tailwindcss"` (enables Tailwind
  Preflight). `@font-face` descriptors are read but fonts are not fetched. `@page`, `@property`,
  `@container`, `@scope`, `@apply`, `@counter-style` and other at-rules are ignored, as in takumi.
- Invalid declarations are dropped one by one (CSS error recovery); a stylesheet never makes the render
  throw.
- **Cascade order**, as in takumi: rules in named `@layer` blocks < Tailwind utilities from `tw` <
  unlayered stylesheet rules < inline `style`; for `!important` declarations the order reverses:
  unlayered < `tw` < named layers.
- Text nodes without a `tagName` are not elements for structural pseudo-classes and sibling combinators
  (`:first-child`, `:nth-child()`, `+`, `~`, ...), as in takumi. Empty or whitespace-only text nodes
  are dropped unless in-flow inline content precedes them (always in flex and grid containers).
- Not supported: `counter()` / `counters()` in `content`, list markers.

## Tailwind

Put classes in a node's `tw` field (in HTML: a `tw="..."` attribute; `class` is only used for stylesheet selectors). Needs `standard`. Status:
656/657 class strings compile to the same declarations as takumi; 4 fixtures (2 identical, 2 equivalent).
The compiler is a port of takumi's Tailwind v4 subset, so it supports exactly what takumi supports:

- **Utility families**: layout and display (`flex`, `grid`, `block`, `hidden`, `contents`, ...),
  position and inset, sizing (`w-*`, `h-*`, `size-*`, `min-*`, `max-*`, `aspect-*`), spacing (`m*-*`,
  `p*-*`, `gap-*`), flex and grid (`basis-*`, `grow`, `shrink`, `grid-cols-*`, `col-span-*`, `items-*`,
  `justify-*`, `self-*`, ...), typography (`text-*`, `font-*`, `leading-*`, `tracking-*`, `line-clamp-*`,
  `truncate`, `whitespace-*`, decoration utilities, `uppercase`, ...), backgrounds (`bg-*`, gradients
  with `from-*` / `via-*` / `to-*`, `bg-linear-*`, `bg-radial`, `bg-conic`), borders and radius
  (`border*`, `rounded*`, `outline*`), effects (`shadow-*`, `inset-shadow-*`, `text-shadow-*`,
  `opacity-*`, `mix-blend-*`, `bg-blend-*`, `mask-*`), filters and backdrop filters, transforms
  (`translate-*`, `rotate-*`, `scale-*`, `origin-*`), `object-*`, `overflow-*`, `list-*`.
- **Values**: the default theme (spacing scale, the full colour palette with `/opacity` modifiers,
  font sizes, radii, shadows, breakpoints), arbitrary values (`w-[37px]`, `bg-[#123456]`,
  underscores as spaces), `!important` prefix.
- **`@theme` variables feed the utilities**: colours (with `/opacity`), `--spacing` and `--spacing-*`,
  `--container-*`, `--radius-*`, `--text-*` (with its `--line-height` companion), `--font-*`,
  `--font-weight-*`, `--tracking-*`, `--leading-*`, `--aspect-*`, `--animate-*`, `--breakpoint-*`.
- **`animate-*`** (`animate-spin`, `-ping`, `-pulse`, `-bounce`, `-none`, `animate-[...]`, theme names)
  on the `full` profile, which has animations.
- **Variants**: breakpoints `sm` `md` `lg` `xl` `2xl` (min-width against the canvas width),
  structural `first` `last` `only` `odd` `even` `*-of-type` `empty` `not-*` `nth-*` and `[&:...]`,
  `before:` / `after:`.
- **Not supported (as in takumi)**: `hover:`, `focus:`, `dark:`, `group-*:`, `peer-*:`, `max-*:`
  breakpoints; `z-*`, `order-*`, `skew-*`, `ring-*`, `space-x-*` / `space-y-*`, `divide-*`, `place-*`,
  `cursor-*`, `outline-2` alone, bare `backdrop-blur`, `mask-b-from-50%`; `var()` in arbitrary values
  (`bg-[var(--x)]`) and the `(--var)` shorthand; `[prop:value]` classes; the v3 name `bg-gradient-to-*`;
  the HTML `class` attribute (only `tw` is Tailwind). Unknown classes are skipped silently.
- `style` beats `tw`; `!`-prefixed utilities beat normal inline declarations.

## HTML input

Pass an HTML string as the source (every JS string is HTML, as in takumi). Needs `standard`. Status:
55/58 structure samples identical to takumi's tree; 8 fixtures equivalent.

- Tolerant tokenizer and tree builder (the same pragmatic subset of the WHATWG algorithm as takumi):
  implied end tags for `p`, `li`, `dt`/`dd`, `option`, table parts; implied `tbody`; void elements;
  character references (numeric + 338 named); fragment and document mode.
- `<style>` elements (with `media` attributes) are applied; `style=""` attributes; `class`, `id`, other
  attributes for selectors; `dir` and `lang`.
- Chromium's user-agent styles are applied as presets (`h1`, `p`, `b`, `ul`, `table`, ...).
- `<img src>` looks up the `images` option or uses a `data:` URL; inline `<svg>` elements are rendered
  as SVG images.
- `<script>`, `<template>` content, comments and `<head>` content are not rendered; nothing is executed
  or fetched.
- Not implemented (same gaps as takumi): adoption agency / formatting-element reconstruction, foster
  parenting, MathML, form controls as widgets.

## Animations

| Feature | Min. profile | Status |
|:--|:--|:--|
| `@keyframes` + `animation*` properties sampled at `timeMs` (delay, direction, fill mode, iteration count, timing functions incl. `cubic-bezier()` and `steps()`) | full | 42 fixtures: 32 identical, 10 equivalent |
| `keyframes` render option (deprecated takumi form) | full | supported |
| `renderAnimation` → animated WebP / APNG / GIF | full | frame counts and delays identical to takumi |
| Built-in names `spin`, `ping`, `pulse`, `bounce` (Tailwind keyframes) without a `@keyframes` rule | full | supported, as in takumi |
| Tailwind `animate-*` utilities, `--animate-*` theme variables | full | supported |
| `em` lengths on an element whose `font-size` is animated | full | follow the animated font size |
| Animations on `::before` / `::after`, animated custom properties | — | no |
| `transition*` | — | parsed; a still render has no transitions |
| `animation-play-state: paused` | full | ignored (sampled anyway), as in takumi |

On `standard` the `@keyframes` rules parse but animations are not applied; on `core` the `animation`
property is ignored.

## Images and SVG

| Feature | Min. profile | Status |
|:--|:--|:--|
| PNG, JPEG (baseline and progressive) | core | equivalent (JPEG decoding within 4/255 of takumi) |
| `object-fit`, `object-position`, `border-radius` clipping of images | core | equivalent |
| WebP lossless, GIF (first frame) | standard | supported |
| WebP lossy (VP8; bit-exact with libwebp), animated GIF / APNG / WebP sources | full | identical to the reference decoders |
| SVG images (`<svg>` markup, `data:image/svg+xml`, `url()` backgrounds and masks) | standard | 397/422 of takumi's SVG test files identical or equivalent |
| SVG coverage | standard | shapes, paths, `use` / `symbol`, gradients, patterns, `clipPath`, `mask`, markers, nested `<svg>` / `<image>`, `<style>` with simple selectors, filters `feGaussianBlur`, `feOffset`, `feFlood`, `feColorMatrix`, `feComposite`, `feMerge`, `feBlend`, `feDropShadow`, `feComponentTransfer`. `<text>` is drawn with the registered fonts in a simplified model (one run per element: `x` / `y`, `font-family`, `font-size`, `font-weight`, `text-anchor`, solid `fill`; `<tspan>` content joins the parent run with the parent style; gradient-filled or stroke-only text is not drawn; see [Charts](charts.md#what-svg-text-supports)). Not supported: `feTurbulence`, `feImage`, `feMorphology`, `feConvolveMatrix`, `feDisplacementMap`, lighting filters, `feTile`, external references |
| `image-rendering: pixelated` / `crisp-edges` | core | nearest-neighbour scaling of image nodes and background images, identical to takumi (also honoured inside SVG images) |
| Remote URLs | — | never fetched: pass bytes through `images` |

## Complex scripts, bidi, emoji

| Feature | Min. profile | Status |
|:--|:--|:--|
| Latin, Cyrillic, Greek, Vietnamese (precomposed), CJK line breaking | core | equivalent |
| Bidi (UAX #9), `direction`, `dir`, `unicode-bidi` isolation | full | 91 679/91 679 bidi conformance cases |
| Arabic, Hebrew, Devanagari, Bengali, Thai shaping; Unicode normalisation (decomposed Vietnamese) | full | glyph widths match takumi (0.000 px difference in every group); other Indic scripts use the default shaper |
| Emoji sequences: ZWJ, skin-tone modifiers, flags, tag flags, keycaps, VS15 / VS16 | standard | one cluster and one glyph each (never split by wrapping, fallback or letter spacing) |
| Colour emoji (with a registered emoji font) | standard (bitmap: CBDT / sbix), full (also COLR) | SSIM ≥ 0.991; the presentation of `©️` (U+00A9 + VS16) depends on context in takumi and can differ |

On `core` and `standard`, right-to-left and complex scripts are shaped with the default OpenType
shaper in logical order (no reordering).

## Known gaps

As of 0.1.0 (see [docs/BENCHMARK.md](../BENCHMARK.md) for the final status):

- **Inline layout (remaining gaps)** — RTL + `white-space: pre-wrap` hanging spaces; line-clamp /
  `-webkit-box` around floats; a block inside a relatively positioned inline box is not shifted with it;
  a chain of nested inline-blocks is limited to about 255 levels (a clean "nested too deeply" error),
  although plain nesting supports 512.
- **Paint order** — raster output paints floats and positioned boxes in CSS 2.1 Appendix E order (floats
  after block backgrounds and before inline content; positioned boxes after the in-flow content of their
  stacking context); `renderSvg` still uses the older, approximate order, and negative `z-index` keeps a
  sibling-level approximation.
- **RTL** — `justify-self: left / right` is not mirrored under `direction: rtl`; on `core` and
  `standard` boxes are mirrored but the text inside them stays left to right (bidi needs `full`).
- **Structural pseudo-classes on text nodes** — a `text` node without a `tagName` is not an element for
  `:first-child`, `:nth-child()`, sibling combinators or the Tailwind `first:` / `odd:` / ... variants
  (as in takumi): it does not count as a sibling, so every one of several bare text siblings matches
  `first:`, `last:` and `odd:`. Give the node a `tagName` or wrap the text in a container.
- **`text-transform`** — no `lang`-tailored casing (Turkish, Azeri, Greek, Lithuanian), no `full-width` /
  `full-size-kana`.
- Not supported: list markers and counters, `writing-mode`, 3D transforms, `filter: url()` /
  `clip-path: url()`, relative colour syntax, `outline-offset` in %, `@apply`, animations on
  pseudo-elements, PDF output.
- Remaining one-level differences: gradient interior, dashed borders on rounded corners, rotated text,
  `text-stroke`.

## Appendix: supported property names

The 296 property names the style parser recognises, generated from `src/style/props.zig` (camelCase,
as used in inline `style` objects; stylesheets use the kebab-case form). Recognised does not always
mean implemented: see the notes at the end.

**Display and positioning:** `display`, `position`, `top`, `right`, `bottom`, `left`, `inset`,
`insetBlock`, `insetBlockEnd`, `insetBlockStart`, `insetInline`, `insetInlineEnd`, `insetInlineStart`,
`zIndex`, `float`, `clear`, `visibility`, `overflow`, `overflowX`, `overflowY`, `overflowBlock`,
`overflowInline`, `contain`, `verticalAlign`, `order`, `boxSizing`, `aspectRatio`.

**Sizing:** `width`, `height`, `minWidth`, `minHeight`, `maxWidth`, `maxHeight`, `inlineSize`,
`blockSize`, `minInlineSize`, `minBlockSize`, `maxInlineSize`, `maxBlockSize`.

**Spacing:** `margin`, `marginTop`, `marginRight`, `marginBottom`, `marginLeft`, `marginBlock`,
`marginBlockStart`, `marginBlockEnd`, `marginInline`, `marginInlineStart`, `marginInlineEnd`,
`padding`, `paddingTop`, `paddingRight`, `paddingBottom`, `paddingLeft`, `paddingBlock`,
`paddingBlockStart`, `paddingBlockEnd`, `paddingInline`, `paddingInlineStart`, `paddingInlineEnd`,
`gap`, `rowGap`, `columnGap`.

**Flexbox and alignment:** `flex`, `flexBasis`, `flexDirection`, `flexFlow`, `flexGrow`, `flexShrink`,
`flexWrap`, `alignContent`, `alignItems`, `alignSelf`, `justifyContent`, `justifyItems`, `justifySelf`,
`placeContent`, `placeItems`, `placeSelf`, `WebkitBoxOrient`.

**Grid:** `grid`, `gridArea`, `gridAutoColumns`, `gridAutoFlow`, `gridAutoRows`, `gridColumn`,
`gridColumnEnd`, `gridColumnStart`, `gridRow`, `gridRowEnd`, `gridRowStart`, `gridTemplate`,
`gridTemplateAreas`, `gridTemplateColumns`, `gridTemplateRows`.

**Tables:** `tableLayout`, `borderCollapse`, `borderSpacing`, `captionSide`, `emptyCells`.

**Borders and outline:** `border`, `borderTop`, `borderRight`, `borderBottom`, `borderLeft`,
`borderColor`, `borderStyle`, `borderWidth`, `borderTopColor`, `borderTopStyle`, `borderTopWidth`,
`borderRightColor`, `borderRightStyle`, `borderRightWidth`, `borderBottomColor`, `borderBottomStyle`,
`borderBottomWidth`, `borderLeftColor`, `borderLeftStyle`, `borderLeftWidth`, `borderBlock`,
`borderBlockColor`, `borderBlockStyle`, `borderBlockWidth`, `borderBlockStart`,
`borderBlockStartColor`, `borderBlockStartStyle`, `borderBlockStartWidth`, `borderBlockEnd`,
`borderBlockEndColor`, `borderBlockEndStyle`, `borderBlockEndWidth`, `borderInline`,
`borderInlineColor`, `borderInlineStyle`, `borderInlineWidth`, `borderInlineStart`,
`borderInlineStartColor`, `borderInlineStartStyle`, `borderInlineStartWidth`, `borderInlineEnd`,
`borderInlineEndColor`, `borderInlineEndStyle`, `borderInlineEndWidth`, `borderRadius`,
`borderTopLeftRadius`, `borderTopRightRadius`, `borderBottomRightRadius`, `borderBottomLeftRadius`,
`borderStartStartRadius`, `borderStartEndRadius`, `borderEndStartRadius`, `borderEndEndRadius`,
`outline`, `outlineColor`, `outlineOffset`, `outlineStyle`, `outlineWidth`.

**Backgrounds:** `background`, `backgroundAttachment`, `backgroundBlendMode`, `backgroundClip`,
`backgroundColor`, `backgroundImage`, `backgroundOrigin`, `backgroundPosition`,
`backgroundPositionX`, `backgroundPositionY`, `backgroundRepeat`, `backgroundSize`.

**Masks and clipping:** `clipPath`, `WebkitClipPath`, `mask`, `maskClip`, `maskComposite`,
`maskImage`, `maskMode`, `maskOrigin`, `maskPosition`, `maskRepeat`, `maskSize`, `maskType`,
`WebkitMask`, `WebkitMaskClip`, `WebkitMaskComposite`, `WebkitMaskImage`, `WebkitMaskOrigin`,
`WebkitMaskPosition`, `WebkitMaskRepeat`, `WebkitMaskSize`.

**Effects:** `opacity`, `boxShadow`, `filter`, `backdropFilter`, `WebkitBackdropFilter`,
`mixBlendMode`, `isolation`.

**Transforms:** `transform`, `transformOrigin`, `translate`, `rotate`, `scale`.

**Images:** `objectFit`, `objectPosition`, `imageRendering`.

**Text:** `color`, `direction`, `unicodeBidi`, `writingMode`, `textAlign`, `textAlignLast`,
`textIndent`, `textTransform`, `textShadow`, `textOverflow`, `textWrap`, `textWrapMode`,
`textWrapStyle`, `whiteSpace`, `whiteSpaceCollapse`, `wordBreak`, `wordSpacing`, `wordWrap`,
`overflowWrap`, `letterSpacing`, `lineHeight`, `lineBreak`, `lineClamp`, `WebkitLineClamp`,
`hyphens`, `WebkitHyphens`, `tabSize`, `textDecoration`, `textDecorationColor`,
`textDecorationLine`, `textDecorationSkipInk`, `textDecorationStyle`, `textDecorationThickness`,
`textUnderlineOffset`, `textUnderlinePosition`, `WebkitTextFillColor`, `WebkitTextStroke`,
`WebkitTextStrokeColor`, `WebkitTextStrokeWidth`, `paintOrder`, `boxDecorationBreak`,
`WebkitBoxDecorationBreak`.

**Fonts:** `font`, `fontFamily`, `fontSize`, `fontStyle`, `fontWeight`, `fontStretch`,
`fontFeatureSettings`, `fontKerning`, `fontOpticalSizing`, `fontVariant`, `fontVariantCaps`,
`fontVariantEastAsian`, `fontVariantLigatures`, `fontVariantNumeric`, `fontVariantPosition`,
`fontVariationSettings`, `fontSynthesis`, `fontSynthesisSmallCaps`, `fontSynthesisStyle`,
`fontSynthesisWeight`.

**Generated content and lists:** `content`, `counterIncrement`, `counterReset`, `counterSet`,
`listStyle`, `listStyleImage`, `listStylePosition`, `listStyleType`.

**Animation and transition:** `animation`, `animationDelay`, `animationDirection`,
`animationDuration`, `animationFillMode`, `animationIterationCount`, `animationName`,
`animationPlayState`, `animationTimingFunction`, `transition`, `transitionBehavior`,
`transitionDelay`, `transitionDuration`, `transitionProperty`, `transitionTimingFunction`.

**Interaction (accepted for compatibility):** `cursor`, `pointerEvents`, `userSelect`,
`WebkitUserSelect`, `willChange`.

Notes:

- **Accepted and ignored** (value not even parsed): `backgroundAttachment`, `willChange`,
  `pointerEvents`, `cursor`, `userSelect`, `WebkitUserSelect`, `transitionBehavior`, `maskComposite`,
  `WebkitMaskComposite`.
- **Parsed, no visible effect in 0.1.0** (found by inspecting which computed values the renderer
  reads): `writingMode`, `hyphens` / `WebkitHyphens`, `lineBreak`, `textAlignLast`, `unicodeBidi`,
  `fontSynthesisWeight` / `fontSynthesisStyle` and the weight / style parts of `fontSynthesis` (bold /
  italic synthesis is always on; small-caps synthesis does follow `fontSynthesis` /
  `fontSynthesisSmallCaps`), `counterReset` / `counterIncrement` / `counterSet`, `listStyle*` (no
  markers), `transition*`, `paintOrder` on text (ignored as in takumi 2.20).
- Properties of a feature that is compiled out of the loaded profile are accepted and ignored (for
  example `float` on `core`), except values that need a missing parser (modern colour functions on
  `core`), which are invalid.
- Any other key is ignored silently, as are kebab-case keys in inline `style` objects.


## See also

The guide pages go deeper into each topic, with runnable examples and their rendered output:
[Concepts](concepts.md) · [Styles and layout](styles.md) · [HTML and Tailwind](html-and-tailwind.md) ·
[Fonts](fonts.md) · [Typography](typography.md) · [Images](images.md) · [Tables and floats](tables.md) ·
[Effects](effects.md) · [Output formats](formats.md) · [Animation](animation.md) · [measure()](measure.md) ·
[Charts](charts.md) · [Templates](templates.md) · [Performance](performance.md)
