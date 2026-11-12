# Benchmark summary

[English](benchmark.md) · [Tiếng Việt](../vi/benchmark.md)

An English summary of the final 0.1.0 results (final build, 250 fixtures; built on the phase-2 and phase-3 reports) in [docs/BENCHMARK.md](../BENCHMARK.md) (the full report, in
Vietnamese, with the phase-1 report kept below it), together with how to reproduce them. bm-engine
(`full` profile) was compared with `@takumi-rs/wasm` 2.20.0 on 250 shared fixtures: every fixture is
identical (81) or equivalent (169) to takumi, with 0 close, 0 different and 0 errors; PNG rendering is faster in 248/250 timed
cases (0.45× takumi's time), raw rendering in 229/250 (0.63×); cold start is 2.5× faster (78.1 vs 193.8 ms); the binaries are 4–9× smaller. bm-engine
still uses 9 % more wasm memory than takumi and is slower on a few raw cases. Per-fixture numbers:
[RESULTS_FULL.md](../RESULTS_FULL.md) and [results.json](../results.json).

## PDF output (phase 6)

`bm-engine/pdf` measured against takumi-pdf on the same machine, Node.js, fonts, images and inputs: **bm-native**
(the Node-API addon, sync and async API), **bm-wasm** (`bm_engine.pdf.wasm`, the `pdf` profile) and **takumi-pdf**
(npm `takumi-pdf`, wasm only; no native build is published). The corpus is the inputs of takumi-pdf's 89 goldens, the
documents of the [PDF guide](pdf/index.md) and stress documents of 1, 10, 100 and 500 pages. Every table is generated
from [results-pdf.json](../results-pdf.json) by `node bench/pdf/bench.mjs`; the PDFs are checked by external
validators (`node bench/pdf/validate.mjs`: qpdf, pdfcpu, poppler, MuPDF, pdf.js, veraPDF) and compared visually with
takumi-pdf's (`node bench/pdf/visual.mjs`). Render times are warm, engines interleaved per document, in several passes;
cold start, memory, event loop, scaling and throughput run one fresh process per point.

<!-- pdf-bench:summary -->
- **Render time, bm-native vs takumi-pdf:** sync 0.30× [0.31× / 0.30× / 0.31×] (faster on 112/112, 0.12×–0.97×); async 0.32× [0.32× / 0.31× / 0.32×] (faster on 112/112, 0.12×–0.94×). Below 1× = bm takes less time; in brackets the same ratio per pass.
- **bm-wasm vs takumi-pdf (both wasm):** 0.49× [0.50× / 0.49× / 0.49×] (faster on 107/112, 0.20×–1.36×). **bm-native vs bm-wasm (sync):** 0.62× [0.61× / 0.61× / 0.62×] (faster on 112/112, 0.38×–0.77×).
- **Pages per second at 1 / 10 / 100 / 500 pages:** bm-native 284 / 206 / 28 / error; bm-wasm 108 / 89 / 14 / error; takumi-pdf 29 / 46 / 75 / 83.
- **Identity:** bm-native == bm-wasm 113/114 documents, same error on both: 1.
- **Validators:** bm-native 104/113 PDFs without any error or warning (takumi-pdf 105/114); veraPDF bm-native 45/45, takumi-pdf 45/45; same text, links, outline and tags as takumi-pdf: 101/113.
- **Visual verdicts vs takumi-pdf (best over the rasterisers):** identical 79, equivalent 30, different 3, close 1 (113 documents, pdfium + mupdf).
- **Noise:** absolute geomeans moved between passes by bm-native:sync 10.1 %, bm-native:async 10.2 %, bm-wasm:sync 10.2 %, bm-wasm:async 11.6 %, takumi-pdf:async 12.9 % ⚠; read the ratios (measured interleaved).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:speed -->
| Variant | geomean ms | per pass | spread |
|:--|--:|--:|--:|
| bm-native:sync | 1.08 | 1.05 / 1.16 / 1.15 | 10.1 % ⚠ |
| bm-native:async | 1.13 | 1.09 / 1.20 / 1.21 | 10.2 % ⚠ |
| bm-wasm:sync | 1.75 | 1.71 / 1.90 / 1.85 | 10.2 % ⚠ |
| bm-wasm:async | 1.66 | 1.62 / 1.82 / 1.75 | 11.6 % ⚠ |
| takumi-pdf:async | 3.56 | 3.40 / 3.89 / 3.79 | 12.9 % ⚠ |

| Ratio (time) | geomean | per pass | faster | range | spread |
|:--|--:|--:|--:|--:|--:|
| bm-native:sync / takumi-pdf:async | 0.30× | 0.31× / 0.30× / 0.31× | 112/112 | 0.12×–0.97× | 3.0 % |
| bm-native:async / takumi-pdf:async | 0.32× | 0.32× / 0.31× / 0.32× | 112/112 | 0.12×–0.94× | 4.1 % |
| bm-wasm:sync / takumi-pdf:async | 0.49× | 0.50× / 0.49× / 0.49× | 107/112 | 0.20×–1.36× | 3.1 % |
| bm-native:sync / bm-wasm:sync | 0.62× | 0.61× / 0.61× / 0.62× | 112/112 | 0.38×–0.77× | 1.8 % |
| bm-native:async / bm-native:sync | 1.05× | 1.04× / 1.03× / 1.05× | 25/112 | 0.88×–1.39× | 2.1 % |

Warm render time per document (fonts registered beforehand, the output kept in memory), 112 documents, 3 pass(es); variants interleaved in rotating order every round.
<!-- /pdf-bench:speed -->

<!-- pdf-bench:scale -->
| Pages | bm-native ms | pages/s | size | peak RSS | bm-wasm ms | pages/s | size | peak RSS | takumi-pdf ms | pages/s | size | peak RSS |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| 1 | 3.50 ms | 283.7 | 27 KiB | 60 MiB | 9.30 ms | 107.9 | 27 KiB | 85 MiB | 34.9 ms | 28.6 | 27 KiB | 111 MiB |
| 10 | 48.5 ms | 206.3 | 99 KiB | 75 MiB | 112 ms | 89.0 | 99 KiB | 89 MiB | 219 ms | 45.6 | 58 KiB | 119 MiB |
| 100 | 3,553 ms | 28.1 | 4,530 KiB | 571 MiB | 7,147 ms | 14.0 | 4,530 KiB | 669 MiB | 1,341 ms | 74.6 | 426 KiB | 135 MiB |
| 500 | error: bm-engine: out of memory |  |  | 2,433 MiB | error: bm-engine: out of memory |  |  | 2,098 MiB | 6,015 ms | 83.1 | 2,186 KiB | 191 MiB |

One render of the stress document (per page: heading, paragraphs, a 14-row table, an image; `break-after: page`) in a fresh process per point; warmed with the 1-page document. Super-linearity (time per page at 100 pages / at 10 pages; 1× = linear): bm-native 7.33×, bm-wasm 6.36×, takumi-pdf 0.61×.
<!-- /pdf-bench:scale -->

<!-- pdf-bench:equiv -->
| Engine | PDFs | clean | errors | warnings | bm-only | shared with takumi-pdf | veraPDF |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 113 | 104 | 12 | 0 | 0 | 12 | 45/45 |
| bm-wasm | 113 | 104 | 12 | 0 | 0 | 12 | 45/45 |
| takumi-pdf | 114 | 105 | 12 | 0 | — | — | 45/45 |

Validators: qpdf 12.4.2, pdfcpu 0.16.4 (strict), poppler 26.09.0 (oschwartz10612/poppler-windows Release-26.09.0-0) (pdfinfo, pdffonts), MuPDF 1.28.6 (wasm), pdf.js 6.5.438, veraPDF 1.28.2 (greenfield-apps, the shaded CLI jar published to Maven Central). Semantics (pdf.js: text per page, links, outline, attachments, tags, metadata) identical to takumi-pdf in 101/113 documents.

| Rasteriser | identical | equivalent | close | different |
|:--|--:|--:|--:|--:|
| pdfium | 73 | 35 | 2 | 3 |
| mupdf | 69 | 39 | 2 | 3 |
| best of the rasterisers | 79 | 30 | 1 | 3 |

bm-native vs takumi-pdf, same rasteriser, 96 and 144 dpi, 113 documents (worst page counts). bm's PDF vs bm's own image render of the same tree (viewport documents, 96 dpi): pdfium equivalent 7, different 11, close 16, identical 2; mupdf equivalent 19, different 11, close 6.

bm-native == bm-wasm byte for byte: 113/114 (+1 with the same error on both). Render errors: stress/500p bm-native: bm-engine: out of memory; stress/500p bm-wasm: bm-engine: out of memory.
<!-- /pdf-bench:equiv -->

## Native Node.js addon (phase 4)

Since phase 4, `bm-engine` on Node.js runs as a native addon when one is installed for the platform, with the
wasm build as an automatic fallback. The four builds — bm-native, bm-wasm (`full`), takumi-native
(`@takumi-rs/core`) and takumi-wasm — were measured together on the same 250 fixtures. The tables below are
generated from [results-native.json](../results-native.json) by `node bench/run-native.mjs`; the guide
page is [Native vs WebAssembly](native-vs-wasm.md) and the full tables (per category, per fixture, method,
noise record) are in [docs/BENCHMARK.md](../BENCHMARK.md#giai-đoạn-4--native-nodejs). The rest of this page
is the wasm report (final build; earlier phases are kept as history).

<!-- native-bench:highlights -->
- **bm-native vs bm-wasm (sync):** raw 0.60× the wasm time [0.60× / 0.59× / 0.60×] (faster on 250/250 fixtures), PNG 0.68× [0.68× / 0.68× / 0.68×] (faster on 250/250).
- **bm-native vs takumi-native, both async:** raw 0.55× [0.55× / 0.55× / 0.55×] (bm faster on 244/250, per fixture 0.13×–1.21×), PNG 0.56× [0.56× / 0.58× / 0.56×] (bm faster on 227/250, per fixture 0.23×–2.28×). With bm's sync API: raw 0.50×, PNG 0.56×. Below 1× = bm-native takes less time; in brackets the same ratio in each pass.
- **CPU time per image (both async):** PNG 2.32 ms bm-native vs 3.81 ms takumi-native (1.47 vs 1.78 cores busy during a render); raw 1.42 vs 1.71 ms. takumi-native runs parts of one render (PNG deflate segments, blur, WebP, animation frames) on its own rayon thread pool; bm renders one image on one thread (bm-native sync: 0.91 cores for PNG).
- **takumi's own two builds:** takumi-native takes 0.75× the time of takumi-wasm for raw and 0.56× for PNG.
- **Identity:** bm-native and bm-wasm produced the same bytes in 1810/1810 comparisons over 250 fixtures (637 MB; 0 mismatches).
- **Noise:** the absolute raw / PNG geomeans moved by up to 33.4 % between passes (the load from other processes changed during the run), while the engine-to-engine ratios, measured interleaved inside each pass, moved by at most 3.70 %. Read the ratios; treat absolute milliseconds as ±16.7 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Metric | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — sync API | 0.51 ±15.5 % ⚠ | 0.85 ±16.1 % ⚠ | no sync API | — |
| raw RGBA, geomean ms — async API | 0.56 ±15.7 % ⚠ | — | 1.02 ±15.3 % ⚠ | 1.36 ±15.8 % ⚠ |
| PNG, geomean ms — sync API | 1.05 ±14.6 % ⚠ | 1.56 ±15.0 % ⚠ | no sync API | — |
| PNG, geomean ms — async API | 1.06 ±16.7 % ⚠ | — | 1.89 ±14.5 % ⚠ | 3.36 ±15.8 % ⚠ |
| CPU time per PNG render, mean ms (cores used) | 1.42 (0.91 cores) | 1.78 (0.77 cores) | 3.81 (1.78 cores) | 4.08 (0.86 cores) |
| PNG file size, geomean vs takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start over empty Node, median / p95 ms | 31.3 / 69.2 | 99.9 / 138 | 50.9 / 97.5 | 238 / 304 |
| RSS after 1 → 10 suite passes, MiB | 94.7 → 96.0 | 132 → 156 | 102 → 139 | 140 → 176 |
| Peak RSS, one 4000×4000 PNG, MiB | 143 | 149 | 135 | 151 |
| Event loop: max 1 ms-timer delay, heavy 2400×2400 render, ms | 227 (sync) · 1.50 (async) | 455 (sync) · 473 (async) | 7.30 (async) | 819 (async) |
| Event loop: same, 60-frame animation, ms | 476 (sync) · 1.20 (async) | 969 (sync) · 954 (async) | 21.6 (async) | 2 072 (async) |
| Throughput, og card PNG, 4 concurrent, images/s (best config) | 312 (many K=4, UV 4) ⚠ | 233 (pool K=4) ⚠ | 270 (one, UV 8) ⚠ | 137 (pool K=8) ⚠ |
| Throughput, 8 concurrent, images/s (best config) | 402 (many K=8, UV 8) ⚠ | 270 (pool K=8) ⚠ | 316 (one, UV 8) ⚠ | 180 (pool K=8) ⚠ |

Geomeans over the 250 fixtures every engine rendered; ± = half the range of the 3 passes' geomeans relative to their median; ⚠ = more than 10 % range. Cold start: median / p95 of 30 fresh processes minus the empty-Node median. Event-loop, memory and throughput are single runs; on the throughput rows ⚠ = other processes used more than one core on average during that stage.
<!-- /native-bench:summary -->

## Conditions

- Intel Core i3-10100 @ 3.6 GHz (8 threads), 7.8 GB RAM, Windows 11, Node 26.13.0, 2026-11-12.
- Reference: `@takumi-rs/wasm` 2.20.0 (the official wasm build) and `@takumi-rs/core` 2.20.0 (native,
  for the noise floor only).
- 250 fixtures in `bench/fixtures/` (200 up to phase 3: 87 from phase 1 + 97 for the features ported in phase 2 + 16 inline-layout fixtures in phase 3; 50 more added since), the same
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

| Metric | takumi-wasm (final build) | bm phase 1 | bm phase 2 (`full`) | bm phase 3 (`full`, 200 fixtures) | bm final 0.1.0 (`full`, 250 fixtures) |
|:--|--:|--:|--:|--:|--:|
| Equivalence over all fixtures | — | 78 cases: 9 identical / 69 equivalent (+ 9 "gap" cases: 5 different, 1 error) | 184 cases: 74 / 109 / 1 close / 0 / 0 | 200 cases: 74 / 126 / 0 / 0 / 0 | **250 cases: 81 identical / 169 equivalent / 0 close / 0 different / 0 errors** |
| `raw` render, geometric mean | 1.01 ms (250 cases) | 0.61× takumi (78 cases) | 0.65× (faster in 155/175) | 0.68× (0.69 ms; faster in 171/191) | **0.63×** (0.64 ms; faster in 229/250) |
| `png` render, geometric mean | 2.95 ms | 0.72× | 0.48× (faster in 175/175) | 0.49× (1.59 ms; faster in 191/191) | **0.45×** (1.33 ms; faster in **248/250**) |
| PNG file size, geometric mean | 1.00 | 0.75 | 0.76 | 0.78 | 0.80 |
| Cold start (init + font + first og-card PNG) | 193.8 ms (native 44.2 ms) | 79.5 ms | 72.1 ms | 70.8 ms | **78.1 ms** |
| wasm memory after 50 og-card PNG renders | 10.6 MiB | 11.9 MiB (+12 %) | 11.6 MiB (+9 %) | 11.6 MiB (+9 %) | 11.6 MiB (**+9 %**) |
| Peak process RSS | 105.0 MiB | 77.2 MiB | 88.6 MiB | 89.1 MiB | 92.3 MiB |
| Maximum tree depth | 512 | 128 | 512 | 512 | **512** |

## Binary size

| Build | Raw | gzip -9 | brotli | vs. takumi (4 234.9 KiB) |
|:--|--:|--:|--:|:--|
| `core` | 487.6 KiB | 228.4 KiB | 194.3 KiB | 8.7× smaller |
| `standard` | 934.4 KiB | 463.7 KiB | 398.0 KiB | 4.5× smaller |
| `full` | 1 141.5 KiB | 559.0 KiB | 469.8 KiB | 3.7× smaller |
| WOFF add-on | 84.2 KiB | 67.7 KiB | 65.5 KiB | — |
| phase 1 (single build) | 320.9 KiB | 147.1 KiB | 126.5 KiB | 13.2× smaller |

Phase-2 sizes were 428.5 / 849.6 / 1 070.0 KiB (9.9× / 5.0× / 4.0× smaller) and phase-3 sizes 454.5 / 877.5 / 1 099.8 KiB; the inline-formatting work added about 26–30 KB to every profile, and the later fixes about 33–56 KB more.
Per-feature costs (measured in phase 2): [Profiles and size](profiles-and-size.md#marginal-cost-per-feature).

## Where bm-engine still loses

- **wasm memory: +9 %** (11.6 vs 10.6 MiB after 50 og-card renders). The remainder is rasterizer
  scratch buffers, canvas-sized layers and 64 KiB page-granular allocation.
- **`border-radius` group, raw: 1.20×** takumi (1.18× in the phase-2 run: 1.00 vs 0.85 ms). The rasterizer itself was fixed
  (large ellipse 0.97 → 0.43 ms); what is left is fixed per-frame cost (canvas clear, un-premultiply,
  copying 3 MB to JS).
- **`text-stroke` raw 1.58×** and **`svg-image` raw 1.48×** (stroker and SVG paths not optimised yet);
  **`text-decoration` raw 1.12×**.
- Peak RSS grew from phase 1 (77 → 92 MiB) but stays below takumi-wasm (105.0 MiB).

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

See [CSS support → Known gaps](image/css-support.md#known-gaps) and
[Differences from takumi](image/differences-from-takumi.md). The two layout gaps that were open in phase 2 are done in phase 3: text flows around floats, and atomic inlines
(`inline-block` / `inline-flex` / `inline-grid` / inline images, all `vertical-align` values), inline span
padding / border / margin, per-span `white-space`, `<br>` and per-box struts take part in real inline formatting.
New fixtures `float-text` (7), `inline-flow` (5) and `inline-box-model` (4) are all equivalent to takumi (SSIM ≥ 0.9999),
and the measure-tree gate matches takumi within 0.001 px on 246/247 non-transform cases (the exception, `fix-css-blank-text-dropped`, differs in child count).
Remaining inline gaps: RTL inline boxes around LTR text (edges on the wrong visual side; fragments not split across
bidi runs), RTL + `pre-wrap` hanging spaces, line-clamp / `-webkit-box` around floats, block-in-inline, approximate float
paint order, `text-wrap: balance / pretty` falling back to greedy wrapping with inline boxes or beside floats,
percentage padding / margin on inline boxes (0), and about 255 levels of chained nested inline-blocks
(clean "nested too deeply" error; plain nesting supports 512).
Package: the final `npm pack` has 28 files (1 293.8 KiB packed, 2 655.8 KiB unpacked); `npm run test:pack` passes 15/15; 436/436 unit tests pass.

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
