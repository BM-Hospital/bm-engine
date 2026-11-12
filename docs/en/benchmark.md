# Benchmark summary

[English](benchmark.md) · [Tiếng Việt](../vi/benchmark.md)

An English summary of the final 0.1.0 results (phase 3, built on the phase-2 report) in [docs/BENCHMARK.md](../BENCHMARK.md) (the full report, in
Vietnamese, with the phase-1 report kept below it), together with how to reproduce them. bm-engine
(`full` profile) was compared with `@takumi-rs/wasm` 2.20.0 on 200 shared fixtures: every fixture is
identical (74) or equivalent (126) to takumi, with 0 close, 0 different and 0 errors; PNG rendering is faster in 191/191 timed
cases, raw rendering in 171/191; cold start is 2.5× faster; the binaries are 4–9× smaller. bm-engine
still uses 9 % more wasm memory than takumi and is slower on a few raw cases. Per-fixture numbers:
[RESULTS_FULL.md](../RESULTS_FULL.md) and [results.json](../results.json).

## Conditions

- Intel Core i3-10100 @ 3.6 GHz (8 threads), 7.8 GB RAM, Windows 11, Node 26.13.0, 2026-11-12.
- Reference: `@takumi-rs/wasm` 2.20.0 (the official wasm build) and `@takumi-rs/core` 2.20.0 (native,
  for the noise floor only).
- 200 fixtures in `bench/fixtures/` (87 from phase 1 + 97 for the features ported in phase 2 + 16 inline-layout fixtures in phase 3), the same
  node trees and the same 9 static TTF fonts (Inter, Noto Sans, Roboto) registered identically in every
  engine.
- Timing: median of ≥ 20 iterations and ≥ 300 ms after 3 warm-up renders, engines interleaved per case.
  `raw` = `render(..., { format: "raw" })`, `png` = the default format.
- Equivalence: bm-engine's `raw` buffer against takumi-wasm's. **identical** = 0 bytes differ;
  **equivalent** = SSIM ≥ 0.99 and ≤ 0.5 % of pixels above the pixelmatch 0.1 threshold; **close** =
  SSIM ≥ 0.95 and ≤ 5 %; otherwise **different**. SSIM is the lower of luma SSIM and RGB SSIM.
- Noise floor: takumi-native and takumi-wasm are byte-identical on every case, so every difference
  reported for bm-engine is real.

## Headline numbers

| Metric | takumi-wasm | bm phase 1 | bm phase 2 (`full`) | bm final 0.1.0 (`full`) |
|:--|--:|--:|--:|--:|
| Equivalence over all fixtures | — | 78 cases: 9 identical / 69 equivalent (+ 9 "gap" cases: 5 different, 1 error) | 184 cases: 74 / 109 / 1 close / 0 / 0 | **200 cases: 74 identical / 126 equivalent / 0 close / 0 different / 0 errors** |
| `raw` render, geometric mean | 1.02 ms (191 cases) | 0.61× takumi (78 cases) | 0.65× (faster in 155/175) | **0.68×** (0.69 ms; faster in 171/191) |
| `png` render, geometric mean | 3.26 ms | 0.72× | 0.48× (faster in 175/175) | **0.49×** (1.59 ms; faster in **191/191**) |
| PNG file size, geometric mean | 1.00 | 0.75 | 0.76 | 0.78 |
| Cold start (init + font + first og-card PNG) | 178.4 ms (native 43.8 ms) | 79.5 ms | 72.1 ms | **70.8 ms** |
| wasm memory after 50 og-card PNG renders | 10.6 MiB | 11.9 MiB (+12 %) | 11.6 MiB (+9 %) | 11.6 MiB (**+9 %**) |
| Peak process RSS | 107.9 MiB | 77.2 MiB | 88.6 MiB | 89.1 MiB |
| Maximum tree depth | 512 | 128 | 512 | **512** |

## Binary size

| Build | Raw | gzip -9 | brotli | vs. takumi (4 234.9 KiB) |
|:--|--:|--:|--:|:--|
| `core` | 454.5 KiB | 211.5 KiB | 180.3 KiB | 9.3× smaller |
| `standard` | 877.5 KiB | 435.2 KiB | 374.5 KiB | 4.8× smaller |
| `full` | 1 099.8 KiB | 538.2 KiB | 453.4 KiB | 3.9× smaller |
| WOFF add-on | 84.2 KiB | 67.7 KiB | 65.5 KiB | — |
| phase 1 (single build) | 320.9 KiB | 147.1 KiB | 126.5 KiB | 13.2× smaller |

Phase-2 sizes were 428.5 / 849.6 / 1 070.0 KiB (9.9× / 5.0× / 4.0× smaller); the inline-formatting work added about 26–30 KB to every profile.
Per-feature costs (measured in phase 2): [Profiles and size](profiles-and-size.md#marginal-cost-per-feature).

## Where bm-engine still loses

- **wasm memory: +9 %** (11.6 vs 10.6 MiB after 50 og-card renders). The remainder is rasterizer
  scratch buffers, canvas-sized layers and 64 KiB page-granular allocation.
- **`border-radius` group, raw: 1.20×** takumi (1.18× in the phase-2 run: 1.00 vs 0.85 ms). The rasterizer itself was fixed
  (large ellipse 0.97 → 0.43 ms); what is left is fixed per-frame cost (canvas clear, un-premultiply,
  copying 3 MB to JS).
- **`text-stroke` raw 1.61×** and **`svg-image` raw 1.46×** (stroker and SVG paths not optimised yet);
  **`text-decoration` raw 1.10×**.
- Peak RSS grew from phase 1 (77 → 89 MiB) but stays below takumi-wasm (107.9 MiB).

## Phase-1 losses and what was done

| # | Loss in phase 1 | Root cause | Fixed? | Before → after |
|:--|:--|:--|:--|:--|
| 1 | `border-radius` raw slower | coverage mask built over the whole bbox, then re-read | partly | ellipse 1200×630: 0.97 → 0.43 ms; group still 1.18× (per-frame fixed cost) |
| 2 | PNG slower on text-heavy images | latency-bound hash chains, 3 filter strategies × 51 rows, mispredicted palette counting, slow Adler-32 | yes | PNG step −34…−62 %: text-vietnamese 8.41 → 4.33 ms (takumi 8.32); card-og 21.5 → 15.2 ms (22.7). PNG now faster in 175/175 cases |
| 3 | Lossless WebP of photos 2.1× slower | LZ77 hash chains on photo residuals (and 9 % larger files) | yes | photo detection, left/up copies only: img-photo-bg 45.9 → 19.9 ms (takumi 21.3), 414 → 376 KB (takumi 482 KB) |
| 4 | wasm memory +12 % | PNG scratch copy, canvas-sized group layers, unreleased hi-res glyph masks, uploading unused images | partly | streaming PNG, canvas outside the arena, separate glyph scratch, only referenced images uploaded: 11.9 → 11.6 MiB (+9 %) |
| 5 | dashed / dotted borders drawn solid | not implemented | yes | Blink's / takumi's `BoxBorderPainter` ported: card-flat-ui SSIM 0.9949 → 0.9998 |
| + | anti-aliased edges never byte-identical | exact-area AA ≠ tiny-skia's 4×4 supersampling; takumi's `div_255` off by one in 126/65536 products | yes | supersampling scan converter (232/232 test shapes byte-identical) and `div_255` ported: identical fixtures 9 → 74 |

## Phase-2 features and their equivalence

| Feature | Check against takumi |
|:--|:--|
| Stylesheets / selectors / cascade, `@media`, `@layer`, `@supports`, nesting, `var()` | 252/252 nodes pick the same winning rule; 4 fixtures: 1 identical, 3 equivalent |
| Tailwind `tw` | 656/657 class strings compile identically; 4 fixtures: 2 identical, 2 equivalent |
| HTML input, UA presets, `::before` / `::after` | 55/58 samples give the same tree; 8 fixtures equivalent |
| oklch / lab / lch / color() / color-mix, gradient interpolation spaces | 495/495 colours identical at 8 bits; gradients within 1–2 levels |
| WOFF / WOFF2 (brotli written from scratch) | 17/19 of takumi's WOFF2 fonts byte-identical to the reference decoder; 2 differ by one flag bit (newer spec) |
| Variable fonts, CFF / CFF2, TTC | 1 400 width comparisons within 1/64 px; 196/196 line heights |
| Full shaping (GSUB 1–8, GPOS 1–9), bidi (UAX #9), Arabic, Hebrew, Devanagari, Bengali, Thai, Vietnamese, `text-wrap: balance/pretty` | 0.000 px width difference in every group; bidi 91 679/91 679; balance/pretty 216/216; 825/825 phase-1 Latin cases unchanged |
| Colour emoji: COLR v0/v1, CBDT, sbix | SSIM ≥ 0.991 (compared with Chrome: takumi cannot draw COLR v1) |
| SVG images (own parser + renderer) | 397/422 of takumi's SVGs identical/equivalent, mean SSIM 0.9956; 3–10× faster |
| `renderSvg` | both engines' SVGs rasterised with the same rasterizer: 175/179 fixtures identical/equivalent |
| Tables, floats, inline-block, named grid areas, depth 512 | layout: 339/352 tables, 138/138 floats, 168/179 inline; 19 fixtures: 18 identical/equivalent, 1 close (phase 2; `layout2-float-wrap` is now equivalent) |
| Dashed / dotted / double / groove / ridge / inset / outset borders, outline | 5 fixtures: 1 identical, 4 equivalent |
| clip-path, mask-image, blend modes, `background-clip: text`, drop-shadow, backdrop-filter, text-stroke, text decorations, inline boxes | 12 fixtures: 6 identical, 6 equivalent |
| CSS animations at `timeMs`, `renderAnimation` (WebP / APNG / GIF) | 42 fixtures: 32 identical, 10 equivalent; frame counts and delays exact |
| Lossy WebP (VP8), animated GIF / APNG / WebP, ICO | VP8 bit-exact with libwebp; animated frames match `anim_dump` |
| Real browser (headless Edge 157) | 78/78 raw renders byte-identical to Node; PNG / WebP / JPEG decode correctly in the browser |

## Per-feature timing (phase 2 run, `full`)

Geometric means of medians in ms; ratio < 1 means bm-engine is faster. Equivalence column:
identical / equivalent / close / different / error.

| Feature | Cases | raw takumi | raw bm | ratio | png takumi | png bm | ratio | PNG bytes bm/takumi | Equivalence |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|:--|
| colors | 5 | 1.41 | 0.90 | 0.63 | 3.91 | 1.51 | 0.39 | 0.65 | 2/3/0/0/0 |
| flex | 5 | 1.19 | 1.11 | 0.93 | 4.58 | 2.06 | 0.45 | 0.67 | 5/0/0/0/0 |
| sizing | 5 | 0.90 | 0.86 | 0.95 | 4.49 | 2.09 | 0.47 | 0.40 | 5/0/0/0/0 |
| absolute | 3 | 1.05 | 0.89 | 0.85 | 5.32 | 2.25 | 0.42 | 0.55 | 2/1/0/0/0 |
| borders | 3 | 1.37 | 1.09 | 0.80 | 4.17 | 2.03 | 0.49 | 0.61 | 3/0/0/0/0 |
| border-radius | 4 | 0.85 | 1.00 | 1.18 | 4.10 | 1.84 | 0.45 | 0.83 | 4/0/0/0/0 |
| linear-gradient | 4 | 3.90 | 2.26 | 0.58 | 17.08 | 6.55 | 0.38 | 0.65 | 1/3/0/0/0 |
| radial-gradient | 3 | 4.79 | 1.78 | 0.37 | 24.77 | 12.00 | 0.48 | 0.58 | 0/3/0/0/0 |
| box-shadow | 4 | 5.84 | 3.30 | 0.56 | 15.74 | 7.59 | 0.48 | 0.98 | 2/2/0/0/0 |
| opacity | 4 | 5.23 | 2.26 | 0.43 | 9.06 | 3.48 | 0.38 | 0.81 | 0/4/0/0/0 |
| overflow | 3 | 1.61 | 1.00 | 0.62 | 5.46 | 2.07 | 0.38 | 0.77 | 1/2/0/0/0 |
| transform | 3 | 3.02 | 1.67 | 0.55 | 6.37 | 2.71 | 0.43 | 0.90 | 0/3/0/0/0 |
| text-single-line | 3 | 1.49 | 0.92 | 0.62 | 4.74 | 2.27 | 0.48 | 0.99 | 0/3/0/0/0 |
| text-paragraph | 5 | 2.20 | 1.43 | 0.65 | 6.88 | 3.56 | 0.52 | 0.91 | 0/5/0/0/0 |
| fonts | 2 | 2.71 | 1.69 | 0.63 | 8.82 | 4.65 | 0.53 | 0.99 | 0/2/0/0/0 |
| text-i18n | 2 | 2.34 | 1.56 | 0.67 | 7.93 | 4.05 | 0.51 | 1.01 | 0/2/0/0/0 |
| text-truncation | 3 | 1.50 | 0.90 | 0.60 | 4.16 | 1.78 | 0.43 | 0.92 | 0/3/0/0/0 |
| images | 5 | 4.66 | 1.77 | 0.38 | 28.56 | 17.08 | 0.60 | 1.00 | 0/5/0/0/0 |
| grid | 4 | 1.61 | 1.26 | 0.78 | 5.54 | 2.27 | 0.41 | 0.70 | 0/4/0/0/0 |
| og-card | 2 | 4.24 | 2.41 | 0.57 | 13.41 | 9.23 | 0.69 | 1.00 | 0/2/0/0/0 |
| blog-card | 2 | 10.51 | 6.82 | 0.65 | 31.14 | 16.47 | 0.53 | 0.95 | 0/2/0/0/0 |
| stress | 3 | 16.11 | 11.84 | 0.73 | 36.71 | 24.00 | 0.65 | 0.98 | 1/2/0/0/0 |
| text-shadow | 1 | 1.00 | 1.00 | 1.01 | 4.35 | 3.95 | 0.91 | 1.03 | 0/1/0/0/0 |
| known-gaps (phase-1 gap cases) | 9 | 0.57 | 0.32 | 0.56 | 2.03 | 0.82 | 0.40 | 0.71 | 3/6/0/0/0 |
| filter | 1 | 1.77 | 1.30 | 0.74 | 4.89 | 3.09 | 0.63 | 0.98 | 1/0/0/0/0 |
| aa-exact | 2 | 0.61 | 0.37 | 0.61 | 1.57 | 0.84 | 0.54 | 0.98 | 1/1/0/0/0 |
| dashed-border | 1 | 2.40 | 1.34 | 0.56 | 3.35 | 1.67 | 0.50 | 0.91 | 0/1/0/0/0 |
| dotted-border | 1 | 2.82 | 1.50 | 0.53 | 3.65 | 1.83 | 0.50 | 0.91 | 0/1/0/0/0 |
| double-3d-border | 1 | 0.60 | 0.49 | 0.81 | 1.40 | 0.70 | 0.50 | 0.83 | 1/0/0/0/0 |
| mixed-border | 1 | 1.07 | 0.71 | 0.66 | 1.94 | 1.05 | 0.54 | 0.92 | 0/1/0/0/0 |
| outline | 1 | 1.53 | 0.82 | 0.54 | 2.64 | 1.18 | 0.45 | 0.94 | 0/1/0/0/0 |
| clip-path | 1 | 0.87 | 0.63 | 0.72 | 5.44 | 1.95 | 0.36 | 0.73 | 1/0/0/0/0 |
| mask | 1 | 1.57 | 1.12 | 0.71 | 6.32 | 2.29 | 0.36 | 0.70 | 1/0/0/0/0 |
| bg-clip-text | 1 | 2.63 | 0.44 | 0.17 | 5.36 | 2.16 | 0.40 | 1.00 | 0/1/0/0/0 |
| mix-blend | 1 | 1.80 | 1.23 | 0.69 | 7.64 | 4.15 | 0.54 | 0.95 | 1/0/0/0/0 |
| bg-blend | 1 | 4.92 | 0.99 | 0.20 | 10.58 | 4.37 | 0.41 | 0.99 | 1/0/0/0/0 |
| drop-shadow | 1 | 1.53 | 1.20 | 0.79 | 7.06 | 3.45 | 0.49 | 0.97 | 0/1/0/0/0 |
| backdrop-filter | 1 | 4.42 | 2.79 | 0.63 | 7.36 | 4.11 | 0.56 | 0.87 | 1/0/0/0/0 |
| text-stroke | 1 | 0.74 | 1.18 | 1.58 | 2.11 | 1.90 | 0.90 | 1.00 | 0/1/0/0/0 |
| text-decoration | 1 | 1.68 | 1.80 | 1.07 | 3.71 | 2.85 | 0.77 | 0.96 | 0/1/0/0/0 |
| visibility | 1 | 0.30 | 0.18 | 0.62 | 1.20 | 0.52 | 0.43 | 0.36 | 1/0/0/0/0 |
| svg-image | 1 | 0.77 | 1.19 | 1.55 | 2.21 | 1.81 | 0.82 | 0.87 | 0/1/0/0/0 |
| inline-box | 1 | 2.67 | 1.85 | 0.69 | 5.34 | 3.68 | 0.69 | 1.01 | 0/1/0/0/0 |
| css-stylesheet | 4 | 1.35 | 1.05 | 0.78 | 4.78 | 1.78 | 0.37 | 0.70 | 1/3/0/0/0 |
| tailwind | 4 | 1.59 | 1.35 | 0.85 | 5.17 | 2.14 | 0.41 | 0.86 | 2/2/0/0/0 |
| html | 4 | 1.55 | 0.97 | 0.63 | 4.68 | 2.24 | 0.48 | 0.98 | 0/4/0/0/0 |
| pseudo-elements | 4 | 0.78 | 0.50 | 0.64 | 2.41 | 0.97 | 0.40 | 0.93 | 0/4/0/0/0 |
| animation | 42 | 0.25 | 0.16 | 0.64 | 0.75 | 0.37 | 0.49 | 0.62 | 32/10/0/0/0 |
| table | 8 | 1.17 | 0.70 | 0.60 | 2.54 | 1.27 | 0.50 | 0.99 | 0/8/0/0/0 |
| float | 4 | 0.55 | 0.40 | 0.73 | 2.44 | 1.07 | 0.44 | 0.76 | 1/2/1/0/0 |
| inline-block | 4 | 0.55 | 0.34 | 0.62 | 1.80 | 0.90 | 0.50 | 0.98 | 0/4/0/0/0 |
| grid-areas | 3 | 0.71 | 0.54 | 0.75 | 2.13 | 0.94 | 0.44 | 0.88 | 0/3/0/0/0 |
| **All (excluding known-gaps), geomean** | 175 | 1.09 | 0.71 | **0.65** | 3.41 | 1.62 | **0.48** | **0.76** | |

## Browser

`bench/browser` runs the engine in headless Edge / Chrome through `puppeteer-core` and compares it with
Node. The phase-2 report states 78/78 raw renders byte-identical to Node, PNG / WebP / JPEG decoding
correctly in the browser, and takumi also running in the same browser for timing. The latest quick
run (`bench/out/BROWSER.md`, Edge 157.0.4341.46, 12 cases) passed: 12/12 raw renders identical, all
PNG / WebP / JPEG decodes correct, 0 console errors, streaming compile + instantiate 20.4 ms.

## Remaining gaps

See [CSS support → Known gaps](css-support.md#known-gaps) and
[Differences from takumi](differences-from-takumi.md). The two layout gaps that were open in phase 2 are done in phase 3: text flows around floats, and atomic inlines
(`inline-block` / `inline-flex` / `inline-grid` / inline images, all `vertical-align` values), inline span
padding / border / margin, per-span `white-space`, `<br>` and per-box struts take part in real inline formatting.
New fixtures `float-text` (7), `inline-flow` (5) and `inline-box-model` (4) are all equivalent to takumi (SSIM ≥ 0.9999),
and the measure-tree gate matches takumi within 0.001 px on 197/197 non-transform cases.
Remaining inline gaps: RTL inline boxes around LTR text (edges on the wrong visual side; fragments not split across
bidi runs), RTL + `pre-wrap` hanging spaces, line-clamp / `-webkit-box` around floats, block-in-inline, approximate float
paint order, `text-wrap: balance / pretty` falling back to greedy wrapping with inline boxes or beside floats,
percentage padding / margin on inline boxes (0), and about 255 levels of chained nested inline-blocks
(clean "nested too deeply" error; plain nesting supports 512).
Package: the final `npm pack` has 28 files (1 293.8 KiB packed, 2 655.8 KiB unpacked); `npm run test:pack` passes 15/15; 402/402 unit tests pass.

## Reproducing

From a source checkout (see [Building from source](building-from-source.md)):

```sh
cd bench
npm install --ignore-scripts      # takumi 2.20 (oracle), pixelmatch, pngjs, binaryen, puppeteer-core
node run.mjs                      # full run: equivalence + timing + cold start + memory + sizes (several minutes)
node run.mjs --quick              # shorter timing budgets
node run.mjs --filter="text|card" --engines=takumi-wasm,bm
node report.mjs                   # regenerate out/RESULTS.md from out/results.json
node selftest.mjs                 # self-checks of the metrics (SSIM, pixelmatch, ...)
node probe/lay.mjs "^(?!transform)" 0.001   # compare measure() layout trees with takumi at 0.001 px
npm run browser:quick             # real-browser test (Edge / Chrome found automatically)
```

Per-case images are written to `bench/out/<id>/{takumi,bm,native,diff}.png`. Numbers depend on the
machine; ratios are more stable than absolute times.
