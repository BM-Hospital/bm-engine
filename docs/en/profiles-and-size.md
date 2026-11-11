# Profiles and binary size

[English](profiles-and-size.md) · [Tiếng Việt](../vi/profiles-and-size.md)

bm-engine is compiled into three binaries with different feature sets so that you only download what you
use: `core` (428.5 KiB), `standard` (849.6 KiB) and `full` (1 070.0 KiB), against 4 234.9 KiB for
takumi 2.20's wasm. This page lists what each profile contains, what each optional feature costs, what a
smaller profile does with input it cannot handle, how to make a custom build, and why only WOFF is
available as a lazily loaded add-on. All sizes are after `wasm-opt -Oz`; KiB = 1024 bytes.

## Sizes

| Build | Raw | gzip -9 | brotli (q11) | vs. takumi raw |
|:--|--:|--:|--:|:--|
| `core` — `bm_engine.core.wasm` | 428.5 KiB | 200.4 KiB | 171.0 KiB | 9.9× smaller |
| `standard` — `bm_engine.standard.wasm` | 849.6 KiB | 422.3 KiB | 364.5 KiB | 5.0× smaller |
| `full` — `bm_engine.wasm` | 1 070.0 KiB | 526.0 KiB | 442.8 KiB | 4.0× smaller |
| WOFF add-on — `bm_woff.wasm` | 84.2 KiB | 67.7 KiB | 65.5 KiB | — |
| takumi 2.20 (`@takumi-rs/wasm`) | 4 234.9 KiB | 1 860.9 KiB | 1 409.3 KiB | — |

The JavaScript wrapper is a few KiB of dependency-free ESM and the same for every profile. The binaries
import nothing from the host.

## What each profile contains

| Feature (`features` key) | core | standard | full |
|:--|:-:|:-:|:-:|
| Node trees (`{ type, style, children }`), `{ json }` sources, inline `style` / `preset`, `var()`, `calc()` | ✓ | ✓ | ✓ |
| Block, inline, flex, grid (incl. named lines / areas), absolute / fixed positioning, inline-block | ✓ | ✓ | ✓ |
| Static TrueType / TTC fonts with the default OpenType shaper (GSUB / GPOS, kerning, ligatures) | ✓ | ✓ | ✓ |
| Backgrounds, gradients, all border styles, outline, radius, box / text shadows, filters, opacity, 2D transforms, text decorations, text stroke | ✓ | ✓ | ✓ |
| PNG / JPEG images in; PNG / JPEG / WebP (lossless) / raw out; `measure` | ✓ | ✓ | ✓ |
| Stylesheets, selectors, `@media` / `@layer` / `@supports`, `::before` / `::after` (`css`) | | ✓ | ✓ |
| Tailwind `tw` (`tw`) | | ✓ | ✓ |
| HTML string sources (`html`) | | ✓ | ✓ |
| SVG images, `clip-path: path()` (`svg`) | | ✓ | ✓ |
| WOFF / WOFF2 (`woff`) | add-on | ✓ | ✓ |
| Variable fonts (`variableFonts`) | | ✓ | ✓ |
| CFF / CFF2 outlines (`cff`) | | ✓ | ✓ |
| clip-path, masks, blend modes, backdrop-filter, isolation (`effects`) | | ✓ | ✓ |
| `lab()` / `lch()` / `oklab()` / `oklch()` / `color()` / `color-mix()` / `light-dark()`, gradient interpolation spaces (`modernColor`) | | ✓ | ✓ |
| Tables (`tables`) | | ✓ | ✓ |
| Floats (`floats`) | | ✓ | ✓ |
| WebP-lossless and GIF image sources (`webpGifDecode`) | | ✓ | ✓ |
| `text-wrap: balance / pretty` (`textWrapBalance`) | | ✓ | ✓ |
| Colour glyphs / emoji: COLR v0/v1, CBDT, sbix (`colorFonts`) | | | ✓ |
| Bidi, Arabic / Hebrew / Indic / Thai shaping, normalisation (`complexText`) | | | ✓ |
| CSS animations at `timeMs`, `renderAnimation`, animated image sources (`animation`) | | | ✓ |
| Lossy WebP decode, animated GIF / APNG / WebP codecs, ICO output (`extraCodecs`) | | | ✓ |
| `renderSvg` (`renderSvg`) | | | ✓ |

## Marginal cost per feature

KB after `wasm-opt`, measured two ways: added to `core` alone / removed from `full` alone.

| Feature | + to core | − from full | Note |
|:--|--:|--:|:--|
| `css` | 62.5 | 60.7 | |
| `tw` | 37.5 | 32.2 | |
| `html` | 27.8 | 27.2 | |
| `svg` | 100.6 | 102.7 | |
| `woff` | 80.1 | 79.5 | 52 KB of it is the mandatory brotli dictionary |
| `variable_fonts` | 15.8 | 14.4 | |
| `cff` | 9.7 | 8.3 | |
| `effects` | 17.4 | 17.6 | |
| `modern_color` | 12.1 | 10.1 | |
| `tables` | 48.1 | 46.1 | |
| `floats` | 6.5 | 4.8 | |
| `color_fonts` | 30.9 | 35.9 | |
| `complex_text` | 52.2 | 53.0 | |
| `animation` | 42.0 | 52.9 | |
| `extra_codecs` | 0.8 | 33.5 | most of it only pays off together with `animation` |
| `render_svg` | 57.0 | 59.1 | |

Why `core` is not smaller (the phase-1 single build was 320.9 KiB): the shared core grew by about
113 KB of real functionality — every border style, outline and text decoration (+31 KB), the full
GSUB/GPOS engine (+26 KB), `var()` / `calc()` / named grid lines / logical properties (+24 KB),
tiny-skia-exact anti-aliasing and the stroker (+17 KB), layout (+9 KB), DOM / measure (+20 KB) — while
dropping WebP / GIF input (−36 KB). Shrinking it further would mean changing algorithms or changing
`core`'s output.

## What a smaller profile does with unsupported input

Checked with `bench/probe/profiles.mjs` on all three binaries (no input ever traps):

| Input | core | standard |
|:--|:--|:--|
| HTML string source | throws `this build has no HTML input support (use the standard / full build)` | ✓ |
| `css` / `stylesheets` option | throws `this build has no stylesheet (\`css\` option) support ...` | ✓ |
| node with `tw` | throws `Tailwind (\`tw\`) is not supported by this build` | ✓ |
| WOFF / WOFF2 font | throws `this build has no WOFF/WOFF2 font support (use the standard / full build, or load the WOFF add-on ...)` | ✓ |
| CFF `.otf` font | throws `unsupported font format` | ✓ |
| `oklch()` / `lab()` / `color-mix()` in an inline style | throws `invalid value for style property ...` | ✓ |
| SVG / WebP / GIF image | paints nothing | ✓ |
| `clip-path`, `mix-blend-mode`, masks, `backdrop-filter` | ignored | ✓ |
| `display: table*` | laid out as block | ✓ |
| `float` | ignored | ✓ |
| gradient `in oklab` | interpolated in sRGB | ✓ |
| variable font | drawn at the default instance | ✓ |
| `text-wrap: balance` | normal wrapping | ✓ |
| `animation` / `timeMs` | ignored | ignored (`@keyframes` parse, nothing animates) |
| RTL / complex scripts | no bidi reordering, default shaper | same as core |
| colour emoji font | outlines without colour | same as core |
| `format: "ico"`, `renderSvg()`, `renderAnimation()` | throw `this build has no ... support` | same as core |

Check `features` at startup if your inputs vary, and choose the smallest profile that covers them.
Note: in 0.1.0 the error message for `renderAnimation`, `renderSvg` and ICO on `standard` still says
"use the standard / full build"; only `full` has them.

## Custom builds

Every feature is a compile-time flag; the profiles are presets. With Zig 0.17.x
(see [Building from source](building-from-source.md)):

```sh
# a preset
zig build -Dprofile=core            # core | standard | full (default)

# a preset plus / minus single features
zig build -Dprofile=core -Dcss=true -Dtw=true
zig build -Dprofile=full -Dcomplex_text=false -Danimation=false

# release build of all profiles (zig build + wasm-opt -Oz) with extra flags applied to each
node scripts/build.mjs -- -Dtables=false
```

Flags: `css`, `tw`, `html`, `svg`, `woff`, `variable_fonts`, `cff`, `effects`, `modern_color`,
`tables`, `floats`, `webp_gif_decode`, `text_wrap_balance`, `color_fonts`, `complex_text`,
`animation`, `extra_codecs`, `render_svg`. Other build options: `-Dwasm-optimize=small|fast|safe|debug`
(default `small`), `-Dstrip=false`, `-Dstack-kib=<n>` (default 1024). The output lands in
`zig-out/bin/bm_engine.wasm`; load it with `init(bytes)` / `initSync(bytes)`, or in Node with
`BM_WASM=path/to/bm_engine.wasm` and the `bm-engine` entry. `features` reports exactly the flags the
binary was built with.

## The WOFF add-on

`bm_woff.wasm` (84.2 KiB, 65.5 KiB brotli) is the engine's own WOFF / WOFF2 decoder (including brotli)
as a separate module. `loadWoff()` from `bm-engine/woff` installs it, after which `registerFont`
converts WOFF / WOFF2 to TTF / OTF before handing it to any entry. The converted font is byte-identical
to what the built-in decoder produces. It is useful on `core` when your fonts come as WOFF2 (for
example from Google Fonts); on `standard` / `full` it is not needed. See
[Getting started](getting-started.md#woff-on-core).

## Why there are no other lazy add-ons

A feature can be split into a separately loaded module only if it is a pure bytes-in / bytes-out
function. WOFF decoding is. The others are not:

- **Tailwind** is a cascade layer of its own: it generates pseudo-elements and needs the element
  structure inside the engine.
- **SVG, stylesheets and shaping** read and write the engine's internal structures (computed styles,
  the layout tree, glyph caches) in the same linear memory. Splitting them would need a real dynamic
  linker for WebAssembly.

So the choice is made per binary: pick the profile, or build your own with the flags above.
