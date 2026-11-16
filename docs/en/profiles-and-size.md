# Profiles and binary size

[English](profiles-and-size.md) · [Tiếng Việt](../vi/profiles-and-size.md)

Choose a profile to download only the features you need. Sizes below are after `wasm-opt -Oz`; KiB = 1024 bytes.

## Sizes

| Build | Raw | gzip -9 | brotli (q11)  |
|:--|--:|--:|--: |
| `core` — `bm_engine.core.wasm` | 626.2 KiB | 301.2 KiB | 254.1 KiB  |
| `standard` — `bm_engine.standard.wasm` | 1 075.6 KiB | 537.2 KiB | 458.0 KiB  |
| `full` — `bm_engine.wasm` | 1 272.7 KiB | 631.5 KiB | 529.1 KiB  |
| `pdf` — `bm_engine.pdf.wasm` (`full` + PDF output) | 1 906.7 KiB | 938.1 KiB | 767.1 KiB  |
| WOFF add-on — `bm_woff.wasm` | 84.4 KiB | 67.8 KiB | 65.5 KiB  |

The JavaScript wrapper is a few KiB of dependency-free ESM and the same for every profile. The binaries
import nothing from the host.

### Native addon (Node.js)

On Node.js, `bm-engine` uses a native addon when one is installed for the platform (an optional dependency,
one per platform; npm downloads only the matching one). The addon has the `full` feature set plus PDF output (used by `bm-engine/pdf`); the
profiles above apply to the wasm build only. Each addon is larger than the `full` wasm because it is compiled
for speed (ReleaseFast) rather than size, and the wasm build stays in the main package as the fallback.
Which backend to use and how they compare: [Native vs WebAssembly](./native-vs-wasm.md).

<!-- native-bench:sizes -->
| File | Target | KiB | gzip -9 KiB | brotli KiB | Status |
|:--|--:|--:|--:|--:|--:|
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 3 327 | 1 765 | 1 389 | executed (this benchmark) |
| `bm-engine.win32-arm64-msvc.node` | `aarch64-windows-gnu` | 2 627 | 1 577 | 1 179 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-x64-gnu.node` | `x86_64-linux-gnu.2.17` | 3 185 | 1 720 | 1 361 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-x64-musl.node` | `x86_64-linux-musl` | 3 185 | 1 720 | 1 362 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-arm64-gnu.node` | `aarch64-linux-gnu.2.17` | 2 634 | 1 579 | 1 180 | cross-compiled, structurally verified, never executed |
| `bm-engine.linux-arm64-musl.node` | `aarch64-linux-musl` | 2 633 | 1 579 | 1 180 | cross-compiled, structurally verified, never executed |
| `bm-engine.darwin-x64.node` | `x86_64-macos.10.15` | 3 175 | 1 719 | 1 360 | cross-compiled, structurally verified, never executed |
| `bm-engine.darwin-arm64.node` | `aarch64-macos.11.0` | 2 652 | 1 536 | 1 128 | cross-compiled, structurally verified, never executed |
| bm wasm `core` | wasm32 | 490 | 229 | 195 |  |
| bm wasm `standard` | wasm32 | 937 | 465 | 399 |  |
| bm wasm `full` | wasm32 | 1 144 | 560 | 471 |  |
| bm wasm `WOFF add-on` | wasm32 | 84.4 | 67.8 | 65.5  |

Native addons from `native/dist/manifest.json` (built 2026-11-13 with Zig 0.17.1, ReleaseFast). Each user downloads one addon (the optional package for their platform) plus the wasm fallback that ships in the main package.
<!-- /native-bench:sizes -->

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

### The `pdf` profile

`bm_engine.pdf.wasm` is `full` plus the `pdf` feature: the PDF writer, font subsetter, paged layout and the
CSS paged-media properties ([PDF output](pdf/index.md)). It is the only wasm binary with PDF; the native addon contains the PDF writer too and serves `bm-engine/pdf` on
Node.js (the addon is the `full` feature set plus PDF output). `features.pdf` is `true` there and `false` in the others, and `bm-engine` never exposes PDF. It adds about 0.6 MB to `full`. It is not part of the table below because `pdf` is
not a feature of `core`, `standard` or `full`.

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

The per-feature table above was measured in phase 2, before the inline-formatting work, which added about 26–30 KB to every profile.

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
| WOFF / WOFF2 font | throws `this build has no WOFF/WOFF2 font support (use the standard / full build, or load the WOFF add-on ...)`  |
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
The error messages for the `full`-only features (`renderSvg`, `renderAnimation`, ICO / extra codecs, colour fonts, complex text) say "use the full build".

## Custom builds

Every feature is a compile-time flag; the profiles are presets. With Zig 0.17.x
(see [Building from source](building-from-source.md)):

```sh
# a preset
zig build -Dprofile=core            # core | standard | full (default) | pdf (= full + PDF output)

# a preset plus / minus single features
zig build -Dprofile=core -Dcss=true -Dtw=true
zig build -Dprofile=full -Dcomplex_text=false -Danimation=false

# release build of all profiles (zig build + wasm-opt -Oz) with extra flags applied to each
node scripts/build.mjs -- -Dtables=false
```

Flags: `css`, `tw`, `html`, `svg`, `woff`, `variable_fonts`, `cff`, `effects`, `modern_color`,
`tables`, `floats`, `webp_gif_decode`, `text_wrap_balance`, `color_fonts`, `complex_text`,
`animation`, `extra_codecs`, `render_svg`, `pdf`. Other build options: `-Dwasm-optimize=small|fast|safe|debug`
(default `small`), `-Dstrip=false`, `-Dstack-kib=<n>` (default 1024). The output lands in
`zig-out/bin/bm_engine.wasm`; load it with `init(bytes)` / `initSync(bytes)`, or in Node with
`BM_WASM=path/to/bm_engine.wasm` and the `bm-engine` entry. `features` reports exactly the flags the
binary was built with.

## The WOFF add-on

`bm_woff.wasm` (84.4 KiB, 65.5 KiB brotli) is the engine's own WOFF / WOFF2 decoder (including brotli)
as a separate module. `loadWoff()` from `bm-engine/woff` installs it, after which `registerFont`
converts WOFF / WOFF2 to TTF / OTF before handing it to any entry. The converted font is byte-identical
to what the built-in decoder produces. It is useful on `core` when your fonts come as WOFF2 (for
example from Google Fonts); on `standard` / `full` it is not needed. See
[Getting started](image/index.md#woff-on-core).

## Why there are no other lazy add-ons

A feature can be split into a separately loaded module only if it is a pure bytes-in / bytes-out
function. WOFF decoding is. The others are not:

- **Tailwind** is a cascade layer of its own: it generates pseudo-elements and needs the element
  structure inside the engine.
- **SVG, stylesheets and shaping** read and write the engine's internal structures (computed styles,
  the layout tree, glyph caches) in the same linear memory. Splitting them would need a real dynamic
  linker for WebAssembly.

So the choice is made per binary: pick the profile, or build your own with the flags above.
