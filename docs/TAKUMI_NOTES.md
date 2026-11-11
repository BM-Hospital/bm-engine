# Takumi semantics notes (for the Zig port)

Source: `ref/takumi` at commit `33eed4a` (= npm `@takumi-rs/*` **2.20.0**, takumi-core 0.36.0, takumi-raster 0.7.0).
Paths below are relative to `ref/takumi/`. "EMPIRICAL" = confirmed by a probe in `bench/probe/*.mjs`
against `@takumi-rs/wasm/node` 2.20.0. "UNVERIFIED" = read from source or inferred, not tested.

**Headline:** takumi 2.x is no longer a taffy + parley renderer. It is a line-by-line Rust port of
**Blink's LayoutNG + paint** (file names and doc comments name the Blink classes: `SimpleFontData`,
`HarfBuzzShaper`, `FontHeight`, `NGLineBreaker`, `BoxPainterBase`, ...). It has block/inline/flex/grid/
table/float/abs-pos layout, fixed-point `LayoutUnit` (1/64 px), Blink-style pixel snapping, a CSS cascade
with real selectors, and an HTML parser. No taffy, no parley, no swash, no resvg, no cosmic-text.
To match it pixel-for-pixel, think "Chrome's behaviour, raster via tiny-skia masks + custom u8 compositing".

---------------------------------------------------------------------------------------------------

## 1. Input node JSON and the root / viewport

### 1.1 Node shapes (`takumi-core/src/layout/node/input.rs:95-212`, `node/mod.rs:58-170`, TS: `takumi-helpers/src/types.ts:100-140`)
```
{ type: "container", children?: Node[], ...meta }
{ type: "text",      text: string,           ...meta }
{ type: "image",     src: string | bytes | {width,height,data,premultiplied?}, width?: number, height?: number, ...meta }
meta = { style?, preset?, tw?, tagName?, className?, id?, attributes?: {k:v}, dir?: "ltr"|"rtl", lang? }
```
- `type` is required; missing `text`/`src` is an error. Unknown keys are ignored (`NodeField::Other`). Max nesting 512 (`node/mod.rs:29`).
- Implicit tag: container=`div`, text=`span`, image=`img` (`node/mod.rs:494-498`, used for selectors/HTML round-trip).
- A text node is an **element holding text** (like `<span>text</span>`), not a bare DOM text run, unless it has no
  style/preset/tw/class/id/etc. (`Node::is_text_run`, `node/mod.rs:393-417`). Either way its default display is `inline`.
- Image `width`/`height` (numbers, CSS px) become a size **preset** (lowest priority) (`node/mod.rs:618-631`, `push_size_preset`).
- `src` RGBA object: straight alpha unless `premultiplied: true`; length must be `w*h*4` (`node/mod.rs:80-135`).
- `renderer.render()` also accepts an **HTML string** (parsed in Rust, `<style>` CSS honoured) or `{json: string}`
  (`takumi-bindings-common/src/source.rs:15-36`).

### 1.2 Style objects (`takumi-core/src/style/stylesheets.rs:724-790`, `stylesheets_helpers.rs:220-236`)
- Keys must be **camelCase** (`backgroundColor`, `WebkitLineClamp`). They are converted `fooBar` -> `foo_bar`.
  **kebab-case keys (`"min-width"`) are silently ignored** (EMPIRICAL). Unknown properties are silently ignored. `--custom` props kept.
- Values: string (parsed with cssparser as the CSS value) or number. A number is stringified (`13` -> `"13"`) and
  re-parsed (`stylesheets.rs:650-655`). `null`/`undefined` = no declaration. Trailing `!important` honoured.
- **Unitless numbers are px for `<length>`** — both `13` and `"13"` (`properties/length.rs:380`). Unitless where the
  grammar wants a number (`lineHeight: 1.5`, `opacity`, `flexGrow`, `fontWeight`) stay numbers.
- An **invalid value throws** the whole render (`Error: invalid value for width near "banana" ...`) (EMPIRICAL).
- Full CSS syntax per property: `calc()/min()/max()/clamp()`, `var()`, `inherit/initial/unset/revert`, shorthands.

### 1.3 Cascade / precedence (`node/mod.rs:743-760`, `matching.rs:1158-1180,1324-1337`)
Low -> high: `preset` (UA origin) < presentation attributes (HTML attrs) < author rules (`css` option rules and
`tw` utilities compiled to rules) < inline `style`. `!important` follows normal CSS. EMPIRICAL: `style` beats
`tw`; `style` beats `preset`. Relative order of `css` rules vs `tw` rules: UNVERIFIED (tw rules are sorted by
utility order, `matching.rs:1334`). No UA stylesheet is applied to JSON nodes (presets come only from
`takumi-helpers` JSX conversion, `takumi-helpers/src/jsx/style-presets.ts`, or HTML parsing).

### 1.4 Root, viewport, canvas (`takumi-raster/src/render.rs:166-240`, `takumi-core/src/scene.rs:832-846`, `layout/tree.rs:2352-2397`, `viewport.rs`)
- Options `width`/`height` are **output pixels** (u32) and define the **initial containing block** (ICB).
  Missing dimension -> available space is max-content and the canvas takes the root box's size on that axis
  (`scene.rs:835-836`). Canvas size = `viewport.size` per axis if given, else root layout size, rounded
  (`render.rs:191`). 0 on either axis -> `InvalidViewport` error.
- The root node is **blockified** (inline -> block, inline-flex -> flex ...) per CSS Display §2.7 (`tree.rs:2389-2397`).
  It is **not stretched to the viewport height**: a root `div` with auto height in a 200x100 viewport is 200 wide
  (block fills ICB width) and content-tall (EMPIRICAL: `height: 21`). `height:"100%"` resolves against the ICB (EMPIRICAL).
- Canvas starts **transparent black (0,0,0,0)**; nothing paints the background except the nodes (EMPIRICAL).
- `devicePixelRatio` (default 1; <=0 -> 1) does **not** change the canvas size; it multiplies absolute lengths
  (see §3.3). `width:10,height:10` box at DPR 2 fills 20x20 output px (EMPIRICAL).
- Root computed style = initial values, `lang` option, font-family = `fontFamilies` option if given
  (`takumi-core/src/style/stylesheets_query.rs:23-33`). Default `font-size` = `medium` = `1rem` = 16px*DPR.

---------------------------------------------------------------------------------------------------

## 2. Initial values (CSS initial = Blink), and text-node layout

Defined in the `define_style!` table, `takumi-core/src/style/stylesheets.rs:1525-1842` (one line per longhand:
`name: Type [where inherit = true] [= default]`; type `Default` impls in `style/properties/*`).

| property | initial | note |
|---|---|---|
| display | **inline** (`properties/mod.rs:955-968`) | containers too! Root blockified; flex/grid items blockified |
| box-sizing | **border-box** (`mod.rs:438-445`) | NOT the CSS default (EMPIRICAL: `width:10,padding:3` -> 10) |
| position | static | |
| flex-direction / flex-wrap | row / nowrap | `flex-grow` 0, `flex-shrink` 1, `flex-basis` auto (Option None) |
| justify-content / align-items / align-content / align-self | `normal` (`mod.rs:862,1234`) | flex `normal` = stretch (EMPIRICAL) |
| min-width/min-height | auto | flex items get automatic minimum (EMPIRICAL: long word refuses to shrink) |
| margin / padding / inset | 0 / 0 / auto | |
| border-*-style / width | none / medium(3px) | width computes to 0 when style none (Blink) |
| border-radius | 0 | `corner-*-shape` round |
| background-color | transparent | image none; size auto; repeat repeat; position 0% 0%; origin padding-box (`mod.rs:340-345`); clip border-box (`mod.rs:301-304`) |
| opacity | 1 | transform none; transform-origin **50% 50%** (`stylesheets.rs:1608-1611`) |
| overflow | visible | |
| object-fit / object-position | **fill** (`mod.rs:275-278`) / 50% 50% | |
| image-rendering | auto (= Catmull-Rom downscale + bilinear, §7) (`mod.rs:1478-1495`) | |
| color | black (inherited) | |
| font-family | none -> fallback stack (§6.5) | |
| font-size | medium = 1rem = 16px (`font_size.rs:22,40`, `viewport.rs:4`) | |
| font-weight / style / stretch | 400 / normal / 100% | synthesis auto (weight, style, small-caps) |
| line-height | normal (§6.3) | |
| letter-spacing / word-spacing | 0 / 0 | |
| text-align | start (`mod.rs:455-468`) | |
| white-space-collapse / text-wrap-mode | collapse / wrap | i.e. `white-space: normal` |
| word-break / overflow-wrap / line-break | normal / normal / auto | |
| text-overflow / line-clamp | clip / none | |
| text-transform, text-decoration | none | |
| direction | ltr | `dir` node field / `lang` supported |
| visibility | visible | z-index auto |

### 2.1 How text nodes lay out
- Text content goes through Blink's **inline formatting context** (`layout/inline/*`): `InlineItemsBuilder` (whitespace
  collapsing), `HarfBuzzShaper`, `LineBreaker`, `LineInfo`, `LogicalLineBuilder`. A block container whose children are
  all inline-level gets an IFC (`tree.rs:2316-2336`); mixed block/inline children get anonymous block wrappers.
- Inside a flex/grid container every child (text nodes included) is blockified into a flex/grid item; a text item
  is a block container with one IFC inside. EMPIRICAL: `display:flex` row with `"Hi"` -> item width 15 (max-content), height stretched.
- Inline containers with `width/height` (default display!) ignore those sizes — a classic trap: in a block root,
  two child containers without `display` produce a 0-height line (EMPIRICAL).
- **No integer rounding of layout.** All geometry is `LayoutUnit` = i32 with 6 fractional bits (1/64 px)
  (`takumi-core/src/layout_unit.rs:83-170`): `from_float` truncates toward zero, `from_float_ceil` /
  `from_float_round` where Blink does. Text inline-size is the shaped advance **ceiled to 1/64**
  (EMPIRICAL: run 37.59999 -> box 37.609375). Flex 100/3 -> 33.328125, 33.34375, 33.328125 (EMPIRICAL).
- Rounding happens only at **paint** (pixel snapping, §5.2). Measure API returns the 1/64 values in device px.

---------------------------------------------------------------------------------------------------

## 3. Layout engine

### 3.1 Algorithms (`takumi-core/src/layout/**`)
Blink LayoutNG port: `block_layout_algorithm.rs` (margins collapse, floats/exclusions `exclusions/*`, BFC),
`inline/*` (IFC, `score_line_breaker.rs` = `text-wrap: pretty`, balance), `flex/*` (`flex_layout_algorithm.rs`, line
breaker, `line_flexer.rs`), `grid/*` (track sizing, placement, areas), `table/*` (auto/fixed, collapse borders),
`out_of_flow.rs` (absolute/fixed), `fragmentation*` (paged; not used by raster), list markers, counters,
`text_fit*` (`text-fit` property), line-clamp. `-webkit-box` legacy flexbox supported. No taffy anywhere.

### 3.2 Units (`style/properties/length.rs:389-506`, `style/sizing.rs`)
- `px` (and cm/mm/in/pt/pc/Q) are multiplied by DPR (`length.rs:494-503`, `viewport.rs:to_device`). Everything else
  resolves against bases that are already device px.
- `%` against the containing block per CSS (heights against definite CB height only; indefinite -> behaves auto:
  EMPIRICAL 50% height in auto-height column flex -> 0).
- `em` = element font-size; `rem` = **root element** font-size (fallback viewport 16px*DPR); `lh`/`rlh`, `ch`
  (`0` advance), `ex` (x-height), `cq*`.
- `vw`/`vh`/`vmin`/`vmax` against `viewport.size` **in output pixels** (not divided by DPR); missing dimension -> 0
  (`viewport.rs:unit_width/unit_height`). EMPIRICAL: width 100, DPR 2, `50vw` -> 50 output px.
- Border/outline widths: Blink `used line width`: floor to device px, but any non-zero width < 1 device px -> 1
  (`style/properties/border.rs:209-230` tests).

### 3.3 DPR summary
Layout is done in device pixels: CSS px lengths and font sizes are scaled by DPR before layout; canvas = width x height
as given; image intrinsic sizes scale by DPR (`layout/node/image.rs:58-62`); media `resolution` = DPR.

---------------------------------------------------------------------------------------------------

## 4. Supported CSS properties

Authoritative list = `define_style!` groups + `transient_longhands` + `shorthands` in
`takumi-core/src/style/stylesheets.rs:1525-2222`. `I` = inherited. **Bold** = top-60 og-image set.
Grammar is standard CSS unless noted; every property accepts CSS-wide keywords, `var()`, math functions.

**Box / display:** **display** (none|flex|inline-flex|grid|inline-grid|inline|block|inline-block|flow-root|list-item|table*|contents|-webkit-box),
**position** (static|relative|absolute|fixed; no sticky, `properties/mod.rs:674-690`), **top/right/bottom/left**, **inset** (+ inset-inline/-block[-start|-end]),
float, clear, **z-index**, **box-sizing**, **width/height** (`<length>|%|auto|min-content|max-content|fit-content|stretch`),
**min-width/min-height**, **max-width/max-height** (none|...), inline-size/block-size + min/max logical forms,
**aspect-ratio**, **overflow / overflow-x / overflow-y** (visible|hidden|clip|scroll|auto), overflow-inline/-block,
visibility, contain, isolation, vertical-align, table-layout, border-collapse (I), border-spacing (I),
caption-side (I), empty-cells (I), box-decoration-break, baseline-source, break-before/after/inside, orphans/widows (I), page.

**Spacing:** **margin**, **margin-top/right/bottom/left**, margin-inline/-block(+start/end), **padding** (+ sides, logical forms), **gap / row-gap / column-gap**.

**Flex:** **flex** (`none|auto|<grow> <shrink>? <basis>?`), **flex-grow**, **flex-shrink**, **flex-basis**, **flex-direction**,
**flex-wrap**, flex-flow, **justify-content**, **align-items**, **align-self**, **align-content**, justify-items,
justify-self, place-items/-content/-self, **order**, -webkit-box-orient / box-pack / box-align, flex-line-count.

**Grid:** **grid-template-columns/rows** (tracks, `repeat()`, `fr`, `minmax`, named lines), grid-template-areas,
grid-template, grid, grid-auto-rows/columns, grid-auto-flow, grid-row/column(-start|-end), grid-area.

**Border / outline:** **border**, **border-width**, **border-style** (none|hidden|dotted|dashed|solid|double|groove|ridge|inset|outset),
**border-color**, per-side `border-{top..left}[-width|-style|-color]`, logical border-* forms,
**border-radius** (`a b c d / e f g h`, %, per-corner `border-*-*-radius`, logical `border-start-start-radius`...),
corner-shape / corner-*-shape (superellipse), **outline**, outline-width/style/color, outline-offset.

**Background / mask:** **background** shorthand, **background-color**, **background-image** (url(), `linear-gradient`,
`radial-gradient`, `conic-gradient`, `repeating-*`, comma list), **background-size** (auto|cover|contain|<l> <l>),
**background-position**, **background-repeat** (repeat|no-repeat|repeat-x|-y|space|round), background-origin,
**background-clip** (border-box|padding-box|content-box|text|border-area), background-blend-mode,
mask, mask-image, mask-position, mask-size, mask-repeat, mask-type.

**Effects:** **box-shadow** (`[inset] x y [blur [spread]] color`, list), **opacity**, **filter** (blur, brightness, contrast,
grayscale, hue-rotate, invert, opacity, saturate, sepia, drop-shadow, url(#svg-filter)), backdrop-filter,
mix-blend-mode (all 16 + plus-lighter/plus-darker), **clip-path** (inset/circle/ellipse/polygon/path + box),
**transform** (2D functions only: no matrix3d/perspective/rotate3d in `transform.rs`), **transform-origin**, **translate**, **rotate**, **scale**,
offset-path/-distance/-rotate/-anchor/-position/offset, animations (`animation*`, `@keyframes`, `timeMs`).

**Images:** **object-fit** (fill|contain|cover|none|scale-down), **object-position**, image-rendering (I) (auto | smooth,high-quality -> Lanczos3 | pixelated,crisp-edges,optimizeSpeed -> nearest; `mod.rs:1500-1505`).

**Text (all I unless noted):** **color**, **font-family**, **font-size** (keywords, %, em...), **font-weight** (1-1000, bold, bolder, lighter),
**font-style** (normal|italic|oblique <angle>), font-stretch, **font** shorthand, font-variant(+ -ligatures, -numeric,
-caps, -east-asian, -position), font-feature-settings, font-variation-settings, font-kerning, font-optical-sizing,
font-language-override, font-synthesis(-weight/-style/-small-caps), **line-height** (normal|<number>|<length>|%),
**letter-spacing**, word-spacing, **text-align** (start|end|left|right|center|justify), text-align-last, text-justify,
text-indent, **text-transform**, **text-decoration** (line, style, color, thickness; non-I), text-decoration-skip-ink,
text-underline-offset/position, text-shadow, **white-space** (shorthand of white-space-collapse + text-wrap-mode),
text-wrap (text-wrap-mode + text-wrap-style: wrap|nowrap|balance|pretty|stable), **word-break**
(normal|break-all|keep-all|break-word), **overflow-wrap** (normal|break-word|anywhere), line-break, hyphens,
hyphenate-character, tab-size, **text-overflow** (non-I: clip|ellipsis|<string>), **line-clamp** / **-webkit-line-clamp**
(non-I `max-lines` + I `block-ellipsis` + `continue`), text-fit, -webkit-text-stroke(-width/-color),
-webkit-text-fill-color, direction, unicode-bidi (non-I), list-style(-type/-position/-image), content, counter-*.

**SVG presentation (for inline SVG / svg nodes):** fill, fill-opacity, fill-rule, stroke, stroke-width, stroke-*,
stop-color/opacity, flood-*, lighting-color, marker*, paint-order, shape-rendering, text-anchor, dominant-baseline,
alignment-baseline, baseline-shift, vector-effect, color-interpolation(-filters), x,y,cx,cy,r,rx,ry,d.

---------------------------------------------------------------------------------------------------

## 5. Painting

### 5.1 Pipeline
Scene (`takumi-core/src/scene.rs`) builds stacking contexts + property trees (clip/effect, `paint_property.rs`) and
paint chunks in CSS 2.1 Appendix E / Blink order (`paint_chunk.rs::in_paint_order`, `takumi-raster/src/stacking_context.rs:20-60`).
Per box (`takumi-raster/src/node_paint.rs:42-62`, `draw_box_shell`):
1. outer `box-shadow`s, **last listed first**, clipped *out* of the (snapped, rounded) border box (`painter/shadow.rs` `paint_normal_box_shadows`);
2. background color, then background-image layers (last layer bottom) clipped per `background-clip`;
3. inset `box-shadow`s, last first, clipped to the padding box;
4. border; then content (text / replaced image), then children; outline painted in a later phase.
Opacity / filter / mask / clip-path / mix-blend-mode / backdrop-filter create an **offscreen layer**
(`canvas.begin_effect_subcanvas`) composited with `opacity` and blend mode (`stacking_context.rs:190-267`).
Transforms are applied as an affine on draws (no layer), composed as
`T(origin) * translate * rotate * scale * offset-path * transform-list * T(-origin)` (CSS Transforms 2 order,
`style/stylesheets_query.rs:286-335`), origin default center of the border box.

### 5.2 Pixel snapping (Blink `ToPixelSnappedRect`) — `takumi-core/src/painter/snapped_box.rs`, `layout_unit.rs:486-501`
- Box decoration rect: `x' = round(x)`, `w' = round(frac(x) + w) - round(frac(x))` (snap_size_to_pixel); a non-zero
  size never snaps to 0 if |size| > 4/64. Rounding = round-half-up on 1/64 units.
- EMPIRICAL: `margin-left:0.5px; width:2px` -> covers px 1..2 fully opaque; `0.3px + 2.4px` -> px 0..2. Untransformed
  rectangles therefore have **hard (non-AA) edges**; only curves/transforms get AA.
- Inset rects (padding box, content box) are snapped from the unsnapped rect contracted by insets (`snapped_box.rs` `inset`).

### 5.3 Rasterisation, AA, compositing
- Canvas = `tiny_skia::Pixmap`, **8-bit premultiplied RGBA, sRGB-encoded values, no linearisation**
  (`takumi-raster/src/canvas.rs`, `blend.rs`). Output is demultiplied at the end (`canvas.rs:402-408`) with
  rounding `c' = (c*510 + a) / (2a)` via reciprocal table (`takumi-core/src/resources/image_buffer.rs:157-169`).
- Shapes (rounded rects, borders, clip paths, glyphs) become **coverage masks** via `tiny_skia::Mask::fill_path(.., anti_alias=true)`
  (`takumi-raster/src/canvas/mask.rs:662-710`) — tiny-skia's Skia-derived supersampling AA
  (SUPERSAMPLE_SHIFT=2, i.e. 4x4 sub-scanlines with fractional horizontal coverage: UNVERIFIED constant, external crate).
  Masks are bounded to `floor/ceil` of tight path bounds. Paths are built with kurbo/tiny-skia-path (circular-arc
  corners per `layout/border.rs`, `contoured_rect.rs`).
- Fill = color premultiplied, scaled by mask byte: `src = mul_div_255(premul_color, coverage)`; then source-over:
  `dst = src + mul_div_255(dst, 255 - src.a)` per channel (`blend.rs:436-458`). `div_255(v) = (v + 128 + (v>>8)) >> 8`
  (`takumi-core/src/style/math.rs`). Some paths use tiny-skia's own `fill_path` with a `Paint` (`canvas/skia.rs:78-121`).
- Non-normal blend modes: demultiply, blend in straight u8 (integer formulas for multiply..exclusion, float for the
  rest), re-premultiply (`blend.rs:461-500`, `blend.rs:1-200`). EMPIRICAL: rgba(0,0,255,.3) over white -> (178,178,255).
- `dithering` option default **"none"**; `"ordered-bayer"` = 8x8 Bayer on gradient LUT in 8.8 fixed point
  (`style/properties/gradient_utils.rs:20-35, 745-835`).

### 5.4 Gradients (`style/properties/gradient_utils.rs`, `linear_gradient.rs`, `radial_gradient.rs`, `conic_gradient.rs`)
- Stops resolved to px along the axis (CSS fix-up: clamp to previous, distribute unspecified) (`gradient_utils.rs:961-1060`).
  **Color hints are approximated** by inserting a stop at the hint with the 50% premultiplied mix (`gradient_utils.rs:991-1013`),
  not CSS's exponential curve.
- Interpolation space: default **legacy sRGB, premultiplied u8 lerp** with `round()` per channel
  (`interpolate_rgba_premultiplied`, `gradient_utils.rs:247-278`). If any stop uses a modern color function
  (lab/lch/oklab/oklch/color/color-mix) the default becomes **Oklab** (`gradient_utils.rs:95-121`); `in <space> [hue]` honoured.
  EMPIRICAL: red->rgba(0,0,255,0) keeps rgb (255,0,0) with falling alpha (premultiplied).
- Sampling is through a **LUT**: size = `max(2*len+1 (half-pixel samples), len/min_stop_gap + n + 1, 2n, 2)`, capped 8193
  (`gradient_utils.rs:905-945`); stop positions are snapped onto exact LUT entries; pixel (x,y) samples at its centre
  `(x+.5, y+.5)` and picks the **nearest** LUT entry (`round`) — no per-pixel interpolation (`linear_gradient.rs:226-250`).
  EMPIRICAL 10px red->blue: 242,217,191,166,140,115,89,64,38,13 (red channel).
- Linear geometry (Blink `EndPointsFromAngle`): dir = (sin a, -cos a), exact for 0/90/180/270; corner keywords use
  dir ∝ (±h, ±w) normalised (perpendicular-to-diagonal); axis length = `|w sin a| + |h cos a|`; projection
  `p = x*dx + y*dy + (L/2 - cx*dx - cy*dy)` clamped to [0, L] (`linear_gradient.rs:60-130, 221-250`).
- Radial: default shape **ellipse**, size **farthest-corner**, position center (`radial_gradient.rs:33-90`). Conic supported.
- Repeating: period = last - first stop; coincident stops -> solid last colour (`gradient_utils.rs:850-895`).

### 5.5 Shadows and blur
- `box-shadow` blur radius -> **sigma = blur/2** (`style/properties/filter.rs:80-85`; `filter: blur(r)` uses sigma = r);
  visible extent 1.5*blur (3*sigma). Spread grows/shrinks the rounded rect (`painter/shadow.rs`).
- Blur engine = Skia `SkBlurEngine` port (`takumi-core/src/blur.rs`): sigma <= 0.03 no-op; sigma < 2 -> exact normalised
  Gaussian kernel of radius `ceil(3 sigma)`; 2 <= sigma <= 135 -> Skia **three-box (tent) pass** per axis; sigma > 135 ->
  downscale, blur, upscale. Separable, horizontal then vertical, on the alpha mask (shadows) or premultiplied RGBA (filters).
  Outer shadow = blur(mask of rect) filled with shadow colour, clipped out of the border box. Shadows under a scaling
  transform scale offset/blur/spread (`shadow.rs::scaled`).
  EMPIRICAL (10x10 white box, `0 0 10px black`, row through centre, x=9..19): 1 2 5 9 14 21 30 42 55 68 83.
- `text-shadow`: same SizedShadow, no spread; blurred glyph masks.

### 5.6 Overflow / clipping / radius
`overflow: hidden|clip` clips descendants to the (rounded, inner-radius) padding box via an AA mask pushed on the canvas
mask stack (`canvas/mask.rs`, `layout/clip.rs`); `clip-path` likewise. Images inside rounded boxes are clipped by the
content-box contour (`image_drawing.rs:141-200`).

---------------------------------------------------------------------------------------------------

## 6. Text

### 6.1 Stack
- Font parsing/outlines/metrics: **skrifa 0.48** (fork, hinting compiled out) (`Cargo.toml:288-301`).
- Shaping: **harfrust 0.14** (pure-Rust HarfBuzz port; AAT tables disabled in fork) via Blink's `HarfBuzzShaper`
  (`takumi-core/src/fonts/shaping/harfbuzz_shaper.rs`), shape plans cached per font (`fonts/simple_font_data.rs:236-262`).
- Segmentation: Blink `RunSegmenter` (script runs `script_run_iterator.rs`, emoji `symbols_iterator.rs`, small caps), bidi via `unicode-bidi`.
- Line breaking: **ICU4X `icu_segmenter` 2.3 `LineSegmenter::new_for_non_complex_scripts`** (UAX #14 rule-based, compiled data,
  no dictionary/LSTM — Thai/Lao/Khmer/Myanmar get no word breaks) with options from `line-break`/`word-break`
  (`takumi-core/src/text/line_break_iterator.rs:217-240`); grapheme clusters via `GraphemeClusterSegmenter`.
  Breaker = Blink `NGLineBreaker` port (`layout/inline/line_breaker.rs`), `ShapingLineBreaker` reshapes at breaks.
- Rasterisation: **unhinted** outlines (`DrawSettings::unhinted(size, location)`, `resources/glyph.rs:551-556`) at the
  device font size, filled with tiny-skia AA mask; **no gamma/contrast adjustment**; coverage composited linearly like any
  mask. **Subpixel positioning: origin snapped to 1/4 px along the baseline axis, whole px across it** (`takumi-raster/src/text_drawing.rs:25-92`,
  `split_subpixel`: round(v*4)/4). Masks cached per (glyph, transform fraction, stroke) (`resources/glyph_cache.rs`).
- Synthetic bold = outline + centred stroke of `size * skia_fake_bold_factor(size)` (Skia fake-bold table, `glyph.rs:321-325`);
  synthetic italic = skew -14.036° (`simple_font_data.rs:29-33`). Colour fonts never synthesized.

### 6.2 Features
harfrust defaults (ccmp, locl, mark, mkmk, kern, liga, clig, calt, rlig, ...) are on. CSS `font-variant-*`/`font-kerning`
append explicit features, then `font-feature-settings` (`style/stylesheets_query.rs:479-513`). **letter-spacing != 0 disables
liga/clig/dlig/hlig/calt** (`style/properties/font_variant.rs:56-74`). letter-spacing is added **after every cluster including the
last** (Blink `ShapeResultSpacing`, `fonts/shaping/shape_result_spacing.rs:140-147`; EMPIRICAL "Hello"+2px = +10px), not to cursive scripts.

### 6.3 Vertical metrics and line box (`resources/font.rs:751-828`, `fonts/font_height.rs:58-71`)
- From skrifa `metrics()` at the instance: ascent, |descent|, line gap. skrifa picks OS/2 typo when USE_TYPO_METRICS else hhea
  (falling back typo then win) — UNVERIFIED for fonts where they differ; EMPIRICAL Geist/Archivo (hhea == typo) match, OS/2 win ignored.
- **Each of ascent, descent, lineGap is rounded to whole px** (`ascent.round()` etc.) — Blink `SimpleFontData::PlatformInit`.
- `line-height: normal` = rounded(asc) + rounded(desc) + rounded(gap). Geist 16px: asc 16.08->16, desc 4.72->5 -> **21** (EMPIRICAL); 64px -> 64+19 = 83; 13px -> 13+4 = 17.
- `line-height: <number>` = number * font-size; `<length>`/% as resolved; kept fractional (1.5*13 = 19.5, EMPIRICAL).
- Leading: `half = floor((line_height - (A+D)) / 2)` to a **whole pixel** goes above, the rest below (`calculate_leading_space`).
  Baseline = line top + A + half. The glyph run box top = baseline - exact (unrounded) ascent (EMPIRICAL run y = -0.08 for Geist 16px).
- Line box = Blink strut + inline box metrics united; consecutive lines step by the line height (EMPIRICAL 21px pitch).

### 6.4 Ellipsis / clamp / wrapping
- `text-overflow: ellipsis` needs `overflow` != visible and `white-space: nowrap` (or no wrap opportunity); inserts U+2026
  shaped in the block's font, truncating at a grapheme (EMPIRICAL "The quick br…"). Without overflow clip: no ellipsis (EMPIRICAL).
- `line-clamp: N` (and legacy `display:-webkit-box; -webkit-box-orient:vertical; -webkit-line-clamp:N`) cuts after N lines and
  appends "…" to the last line, box height = N lines (EMPIRICAL). `layout/line_clamp_data.rs`, `inline/line_truncator.rs`.
- `text-wrap: balance|pretty` implemented (`score_line_breaker.rs`). `overflow-wrap:anywhere/break-word`, `word-break:break-all/keep-all` supported.

### 6.5 Fonts: registration, matching, fallback
- Formats (wasm build): TTF/OTF (glyf, CFF, CFF2 via skrifa), **TTC/OTC** (each face registered, EMPIRICAL Ubuntu.ttc -> 2 faces),
  **WOFF2** (`wuff` + brotli). **WOFF1 is not compiled into wasm** (`woff` feature absent in `takumi-wasm/Cargo.toml` /
  `takumi-bindings-common/Cargo.toml`) — UNVERIFIED empirically. Variable fonts: yes (`fvar` axes; `wght` from font-weight,
  `wdth` from font-stretch, `opsz` from size when `font-optical-sizing:auto`, plus `font-variation-settings`) (`simple_font_data.rs:55-90`).
- Bundled last-resort font: **Geist variable (wght 300-800) TTF** `assets/fonts/geist/geist-latin-wght-300-800.ttf`, family "Geist",
  no generic claim (`takumi-bindings-common/src/lib.rs:43-77`). `clearFonts()` keeps it.
- Family list = `font-family` stack; generics resolve only to fonts registered with `generic:` (FontDetails). Per-character fallback
  (Blink `FontFallbackList`/`FontFallbackIterator`, `fonts/font_fallback_*.rs`): named families, then the render's fallback chain =
  `fontFamilies` option, else **all registered families in registration order**, then Geist. EMPIRICAL: after registering Inter,
  unstyled text uses Inter, not Geist. Emoji-presentation runs prefer colour/emoji faces (`emoji_presentation_scanner.rs`).
- Matching inside a family: CSS Fonts 4 / Blink `FontSelectionAlgorithm` (stretch, then style, then weight distance) (`fonts/font_selection_algorithm.rs`).
  `unicodeRange` subsets honoured. Registered weight/style come from the font (OS/2) unless overridden in FontDetails.
- Glyph kinds: plain outlines; **COLR v0/v1** colour outlines (skrifa ColorPainter, `glyph.rs:112-180`); embedded bitmaps
  CBDT/sbix (PNG decoded, `glyph.rs:448+`). **No emoji font bundled**: emoji fall back to `.notdef` of the last font
  (EMPIRICAL). `@takumi-rs/helpers` can replace emoji with twemoji/noto/... SVG image nodes (`takumi-helpers/src/emoji.ts`).

---------------------------------------------------------------------------------------------------

## 7. Images

- Decoders in wasm (`takumi-core/Cargo.toml` feature `image-decoding`): **PNG/APNG** (`png` 0.18 fork), **JPEG** (`zune-jpeg` 0.5),
  **WebP** (lossy+lossless+animated, `image-webp` 0.2 on wasm), **GIF** (animated). Sniffed by magic (`resources/image_decoder/mod.rs`,
  sizes via `imagesize`). No AVIF/BMP/TIFF.
- **SVG: takumi's own SVG engine** (`takumi-core/src/svg/**`: shapes, paths, text, gradients, patterns, masks, clip, filters
  incl. turbulence/lighting/morphology) rendered with tiny-skia — **not resvg/usvg**. `svg-raster` feature on in wasm.
- `src` resolution (`layout/node/image.rs:99-120`): `data:` URI (base64 or percent-encoded, decoded via resource cache) ->
  inline SVG markup (string starting like `<svg`) -> lookup in the render's `images: [{src, data}]` map -> else **error,
  swallowed**: the image paints nothing and has 0x0 natural size (EMPIRICAL: render succeeds). The raw wasm never fetches;
  the JS wrapper's `prepare()` fetches URLs (see §9). Bytes (`Uint8Array`) and `{width,height,data}` RGBA are accepted directly.
- Intrinsic size = decoded pixel size * DPR (CSS px = image px at DPR 1); `width` only -> height from aspect ratio
  (EMPIRICAL 2x1 png, width 50 -> 50x25). Standard replaced-element sizing (`layout/replaced.rs`, `length_utils.rs:62`: 300x150 default object size).
- `object-fit` default **fill**, `object-position` default **50% 50%**.
- Scaling: on decode the image is **downscaled (never upscaled)** to cover the draw box with the image-rendering filter:
  `auto` = **Catmull-Rom** (B=0,C=0.5), `smooth` = **Lanczos3**, `pixelated` = box/nearest, in premultiplied RGBA, matching
  `image::imageops::resize` (`resources/image_resampler.rs:1-60`, `image_decoder/mod.rs:146-176`). The draw then samples with
  **bilinear (8.8 fixed point) for magnification, box filter for minification**, nearest for pixelated
  (`takumi-raster/src/canvas/paint_source.rs:280-450, 652-720`); whole-pixel translations copy texels exactly.

---------------------------------------------------------------------------------------------------

## 8. Encoders (wasm) — `takumi-raster/src/write.rs`, `takumi-bindings-common/src/options.rs:200-235`

- **raw**: `width*height*4` bytes, row-major **RGBA, straight (un-premultiplied) alpha** (EMPIRICAL rgba(255,0,0,.5) -> 255,0,0,128). Size not returned; you know it.
- **PNG** (default format): `png` crate (fork) + `zlib-rs` deflate. If the image has <= 256 distinct RGBA colours (checked on every
  16th row first, then all pixels) -> **indexed (colour type 3)** with PLTE + tRNS; else RGBA, or **RGB if every alpha is 255**
  (`palette.rs`, `write.rs:534-575`). Compression: sample every 32nd row, try FLAT (zlib level 7, filter None) vs PHOTO (level 3,
  adaptive filter), pick smaller; deflate in 1-8 independent segments (`write.rs:350-420`, `zlib.rs`). Byte-exact parity needs the same
  encoder; pixel parity does not.
- **JPEG**: `jpeg-encoder` 0.7, default **quality 75** (`write.rs:36-55`), **4:4:4** sampling, optimised Huffman tables when <= 4 Mpx
  (`write.rs:515-533`). Input is the straight RGBA buffer with alpha **dropped, not composited** (transparent -> black) — UNVERIFIED decode.
- **WebP**: wasm is **always lossless** (VP8L) via `image-webp` encoder with predictor transform; RGB8 if fully opaque
  (`webp/image_webp.rs:12-50`); `quality`/`lossless` ignored on wasm (EMPIRICAL quality 50 -> VP8L).
- **ICO**: one PNG-compressed entry (Vista+ ICO), each side <= 256 (`write.rs:595-640`).
- Animation (`renderAnimation`): webp (lossless anim on wasm), apng, gif (per-frame palette quantisation).
- `renderAsDataUrl`: base64 of the encoded image, `raw` rejected.

---------------------------------------------------------------------------------------------------

## 9. JS API (`@takumi-rs/wasm` 2.20.0)

Raw wasm-bindgen class (`takumi-wasm/src/renderer.rs`, types `takumi-wasm/src/dts-header.d.ts`):
- `new Renderer({ cacheMaxBytes? = 64 MiB, fontCacheMaxBytes? = unbounded })`
- `registerFont(font: FontDetails | ByteBuf, key?) -> RegisteredFamily[]` (pinned); `cacheFont(font, key)` (evictable);
  `cachedFonts(key, pin)`; `cacheFontFile(url, bytes)` (for `@font-face`); `unregisterFont(family) -> bool`; `clearFonts()`.
  `FontDetails = { name?, data, weight?, style?, unicodeRange?: [lo,hi][], generic? }`.
- `render(source, options?) -> Uint8Array` (sync), `renderSvg`, `measure -> MeasuredNode {width,height,transform[6],children,runs[{text,x,y,width,height}]}`,
  `needs(source, options, listedFonts) -> {images, fonts, fontFiles}`, `renderAsDataUrl`, `animationNeeds`, `renderAnimation`.
  Module function `setGlyphCacheMaxBytes(bytes)`.
- `RenderOptions = { width?, height?, format? = "png" ("png"|"jpeg"|"webp"|"ico"|"raw"), quality?, lossless?, images?: {src,data,cache?}[],
  css?: (string|rule objects)[], stylesheets?(deprecated), keyframes?(deprecated), drawDebugBorder?, devicePixelRatio? = 1, timeMs?,
  dithering? = "none", fontFamilies?, lang? }` (`takumi-bindings-common/src/options.rs:44-98`).
- Every call deserialises options with `serde_wasm_bindgen`; the source is read by `read_source` (HTML string | `{json}` via
  `serde_json` | JS object via `serde_wasm_bindgen`), and the **last parsed source text is cached** (`source_cache.rs`).

`dist/export.mjs` wrapper (bundles `@takumi-rs/bindings-js`; depends on `@takumi-rs/helpers` for `fontFromUrl`, `prepareImages`):
- Wrapper methods are **async**: `prepare`, `render`, `renderAsDataUrl`, `renderSvg`, `measure`, `prepareAnimation`,
  `renderAnimation`, `registerFont(FontLoader)`, `unregisterFont`, `clearFonts`, `free`, `[Symbol.dispose]`. Entry
  `@takumi-rs/wasm/node` does `initSync` with the bundled 4.34 MB `.wasm` (`bundlers/node.mjs`).
- `toNativeSource`: a node tree is **`JSON.stringify`'d into `{json}`** (falls back to passing the object when it holds
  Uint8Array/ArrayBuffer, non-finite numbers, lone surrogates, depth > 127) (`export.mjs:638-670`). So normal trees cross as one string
  and are parsed by `serde_json` in wasm.
- Extra options handled in JS: `fonts` (FontLoader list: buffers, `{data: () => ...}`, or URL strings fetched via `fontFromUrl`) —
  registered with `cacheFont` and, **unless `fontFamilies` is given, the render's fallback stack becomes exactly those fonts' families**;
  `images` (array or `{sources, cache, fetch options}`; lazy `data()` resolved); `signal` (AbortSignal).
- `render` without `prepare` does **not fetch** remote images; `prepare(source, opts)` calls `needs` to list image URLs and
  `@font-face` files, fetches them (`prepareImages`), retries `needs` until settled, returns a `Prepared` you pass to `render`.
- `unicodeRange` font subsets are loaded lazily: only subsets the text needs are registered (needs pass with `ListedFont`s).

---------------------------------------------------------------------------------------------------

## 10. Test fixtures (reusable benchmark inputs)

- `takumi/tests/fixtures-html/*.html` (411 files): each is an HTML page; the `<body style="width:..;height:..">` gives the viewport,
  `<style>` gives CSS, body children are root elements; `<meta name="takumi-device-pixel-ratio">` / `takumi-presets` opt-ins
  (`takumi/tests/html_fixtures.rs:30-190`). **Goldens:** `takumi/tests/fixtures-generated/<name>.webp` (lossless) and `.svg`.
  The wasm `render()` accepts the HTML string directly, so they can be replayed through takumi itself.
- Fonts: `shared.css` + `takumi/tests/test_utils.rs:20-110` register **Geist[wght].woff2** first (default family for unstyled text),
  plus Geist Mono, Twemoji COLR, Archivo, Noto Sans TC, etc. **All repo fonts are variable or WOFF2** except `ubuntu/Ubuntu.ttc`
  (static TTC). For a static-TTF-only port, text fixtures need a static instance of Geist (e.g. `geist-latin-wght-300-800.ttf`
  instanced at wght 400) — goldens were made with Geist[wght].woff2 at default 400, so instancing must match.
- Images: `TEST_IMAGES` = `assets/images/yeecord.png`, `luma.svg`, `luma-cover-...jpeg` keyed by those paths.
- `takumi/tests/fixtures/*.rs` (15) are Rust-built node trees (opacity, background-image, text, png/jpeg/webp output).

Representative fixtures (vp = viewport; "no text" = needs no font at all):

| fixture (`takumi/tests/fixtures-html/`) | vp | exercises | fonts |
|---|---|---|---|
| `style_background_color.html` | 1200x630 | solid fills | no text |
| `style_background_image_gradient.html` | 1200x630 | linear gradients | no text |
| `style_background_image_gradient_hard_stop.html` | 1200x630 | hard stops / LUT snapping | no text |
| `style_background_image_radial_basic.html` | 300x160 | radial defaults | no text |
| `style_background_image_repeating_gradients.html` | 1200x630 | repeating-* | no text |
| `style_background_image_gradient_color_space_comparison.html` | 1200x630 | srgb vs oklab | no text |
| `style_border_radius.html`, `style_border_radius_per_corner.html` | 1200x630 | rounded-rect AA | no text |
| `style_border_width_with_radius.html` | 1200x630 | border + radius inner curve | no text |
| `style_box_shadow.html`, `style_box_shadow_inset.html`, `box_shadow_spread_corners.html` | 1200x630 | shadow blur/spread | no text |
| `style_rotate.html` | 1200x630 | rotate + AA | no text |
| `style_flex_direction.html`, `style_justify_content.html`, `style_align_items.html`, `style_gap.html`, `style_flex_basis.html` | 1200x630 | flexbox | no text |
| `style_padding.html`, `style_position.html` (400x200) | | box model, abs-pos | no text |
| `style_grid_template_columns.html` | 1200x630 | grid | no text |
| `style_mask_image_linear_gradient.html` | 1200x630 | mask layer | no text |
| `style_object_fit_position.html` | 860x380 | object-fit/position (yeecord.png) | images, no text |
| `style_overflow_clip_image.html`, `style_background_size_cover.html` | 1200x630 | image clip / bg-size | images, no text |
| `style_opacity.html` | 1200x630 | opacity layers | text (Geist) |
| `text_basic.html`, `text_typography_regular_24px.html` | 1200x630 | shaping, line box | Geist |
| `text_align.html` (600x256) | | text-align incl. rtl | Geist |
| `text_typography_letter_spacing_2px.html`, `text_typography_line_height_variants.html` | 1200x630 | spacing, leading | Geist |
| `text_ellipsis_text_nowrap.html`, `text_ellipsis_line_clamp_2.html`, `text_wrap_nowrap.html` | 1200x630 | ellipsis, clamp, wrapping | Geist |
| `text_shadow.html`, `style_filter_blur.html` | 1200x630 | blur paths | Geist (+images for filter) |
| `showcase_grid_hero.html` | | og-image style composite | Geist |

---------------------------------------------------------------------------------------------------

## 11. Design weaknesses (size / speed / memory)

1. **Scope = a browser engine.** Full LayoutNG port: tables, floats/exclusions, fragmentation (compiled out of raster), grid,
   list markers/counters, `text-fit`, HTML parser + 2407-line named-entity table (`html/named_references.rs`), selectors (`selectors`
   0.41 + `cssparser` 0.38), media/supports/layers/@property, animations, a full SVG renderer with filter primitives. Result:
   **4.34 MB wasm** even with `wasm-opt -Oz`, `opt-level="z"` for takumi-core in the wasm build (`takumi-wasm/package.json` build
   script) and many per-crate size profiles (`Cargo.toml:201-301`). Optimising takumi-core for size also slows layout/style.
2. **ICU4X compiled data** (`icu_segmenter`, `icu_properties`, `icu_casemap`, `icu_normalizer`, all `compiled_data`) — large tables
   baked in for line breaking, casing, properties; plus harfrust's full OpenType shaper and skrifa's CFF/CFF2/glyf/COLR/bitmap readers.
3. **Marshalling:** the JS wrapper `JSON.stringify`s the tree; wasm copies the string, `serde_json` parses it, and **every style value is
   re-tokenised by cssparser** (numbers are converted to strings first, `stylesheets.rs:650-655`). Options and results go through
   `serde_wasm_bindgen` (reflection on JS objects). Selector matching runs over every node even with no stylesheet.
4. **Style memory:** Blink-like grouped `ComputedStyle` with ~200 longhands in Rc-shared groups (`stylesheets.rs:1525+`), per-node
   `RenderNode`, `LayoutResults`, paint-chunk/property trees, then a scene — several full-tree representations per render.
5. **Pixel pipeline:** u8 premultiplied (good) but every effect (opacity, filter, mask, blend) allocates an offscreen subcanvas;
   per-shape coverage masks are heap `Vec<u8>` sized to path bounds; gradients build a LUT of `2*axis_px+1` entries (twice when
   dithering); raw output needs a full demultiply pass; `measure`/`needs` re-run cascade+layout.
6. **Encoding cost:** PNG encoder first scans for <=256 colours over all pixels, then deflates two candidate encodings on a 1/32
   row sample before the real deflate; JPEG keeps all blocks for optimised Huffman (<=4 Mpx).
7. **Single-threaded in wasm:** rayon is feature-gated off for wasm (`takumi-wasm/Cargo.toml`: takumi-raster default-features=false).
8. **Caches:** ResourceCache 64 MiB default (decoded images, SVG rasters, parsed stylesheets); font cache unbounded by default;
   glyph-mask cache (`setGlyphCacheMaxBytes`); per-font shape-plan vectors; last-source cache holds the whole JSON text + tree.
9. Fonts: WOFF2 decode (brotli) on registration; variable-font instancing per (face, size, axes) via harfrust instance builder.
