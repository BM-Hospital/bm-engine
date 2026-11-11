# bm-engine vs takumi — benchmark & equivalence results

- Date: 2026-11-11T21:14:49.188Z  |  Node v26.13.0  |  win32 10.0.26200 x64
- CPU: Intel(R) Core(TM) i3-10100 CPU @ 3.60GHz (8 logical)  |  RAM 7.8 GB
- Command: `node run.mjs `  |  iterations: >=20 and >=300ms (cap 2000ms), 3 warm-up
- Engines: takumi-wasm = available, takumi-native = available, bm = available
- Times are milliseconds per `render()` call (median; p95 in parentheses). Ratio = bm / takumi-wasm (lower is better for bm; <1 means bm is faster).

## Binary & glue size

| engine | artifact | raw | gzip -9 | brotli |
| :-- | :-- | --: | --: | --: |
| takumi-wasm | binary (pkg/takumi_wasm_bg.wasm) | 4234.9 KiB | 1860.9 KiB | 1409.3 KiB |
| takumi-wasm | JS glue (dist/export.mjs) | 37.5 KiB | 10.0 KiB | 8.8 KiB |
| takumi-native | binary (.node addon) | 9796.0 KiB | 4257.9 KiB | 3201.3 KiB |
| takumi-native | JS glue (dist/export.mjs) | 43.5 KiB | 7.4 KiB | 6.5 KiB |
| bm | binary (zig-out/bin/bm_engine.wasm) | 1070.0 KiB | 526.0 KiB | 442.8 KiB |
| bm | JS glue (js/index.mjs + js/node.mjs) | 23.7 KiB | 7.8 KiB | 6.9 KiB |

## Cold start (fresh `node` process, median of runs)

| engine | runs | wasm compile+instantiate (native: addon load) ms | register Inter-Regular ms | first render (og-card, png) ms | total ms |
| :-- | --: | --: | --: | --: | --: |
| takumi-wasm | 7 | 33.59 | 3.67 | 150.20 | 186.86 |
| takumi-native | 7 | 22.78 | 1.62 | 19.84 | 44.16 |
| bm | 7 | 4.88 | 2.95 | 63.95 | 72.06 |

## Memory (child process: all fonts, 50 og-card PNG renders)

| engine | peak RSS (maxRSS) | wasm linear memory after init+fonts | wasm linear memory after 50 renders |
| :-- | --: | --: | --: |
| takumi-wasm | 99.4 MiB | 6.3 MiB | 10.6 MiB |
| takumi-native | 82.7 MiB | – | – |
| bm | 88.6 MiB | 6.4 MiB | 11.6 MiB |

Bare `node` baseline peak RSS: 44.6 MiB.

Wasm linear memory at end of the full case run (largest instance): takumi-wasm 67.6 MiB, bm 69.9 MiB.

## Output equivalence (reference = takumi-wasm, `format: raw`)

Verdict rules: **identical** = 0 differing bytes; **equivalent** = SSIM >= 0.99 and <= 0.5% pixels differing (pixelmatch thr 0.1, includeAA=true); **close** = SSIM >= 0.95 and <= 5% pixels differing; else **different**. `error/unsupported` when an engine threw. SSIM = mean over uniform 8x8 windows (stride 1) of luma over white; `SSIM RGB` = mean of per-channel SSIMs (catches chroma-only changes). Verdicts use min(luma, RGB). `px strict/AA` = pixelmatch count with includeAA true / false. `native` rows are the noise-floor baseline (same Rust code, different build).

### Verdict summary

| candidate | identical | equivalent | close | different | error/unsupported |
| :-- | --: | --: | --: | --: | --: |
| bm | 74 | 109 | 1 | 0 | 0 |
| takumi-native | 184 | 0 | 0 | 0 | 0 |

### bm vs takumi-wasm

| case | feature | verdict | SSIM luma | SSIM RGB | % diff strict | % diff AA-tol | px strict / AA | mean abs | max abs | PSNR dB |
| :-- | :-- | :-- | --: | --: | --: | --: | --: | --: | --: | --: |
| colors-solid-bg | colors | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| colors-hex | colors | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 14 | 64.6 |
| colors-functional | colors | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 14 | 65.8 |
| colors-named | colors | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 13 | 72.5 |
| colors-transparent-canvas | colors | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-row-column | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-justify-align | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-wrap-gap | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-grow-shrink-basis | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-nested-small | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-percent | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-minmax | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-aspect-ratio | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-padding-margin | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-auto-margin-center | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| abs-inset | absolute | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| abs-zorder | absolute | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| abs-in-flow | absolute | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 12 | 77.3 |
| borders-uniform | borders | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| borders-per-side | borders | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| borders-with-radius | borders | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radius-uniform-percorner | border-radius | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radius-elliptical | border-radius | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radius-pill-circle | border-radius | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radius-small | border-radius | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| lingrad-angles | linear-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 1 | 74.8 |
| lingrad-multistop | linear-gradient | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| lingrad-alpha | linear-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 1 | 78.1 |
| lingrad-hero-small | linear-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 11 | 68.5 |
| radial-shapes | radial-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 1 | 79.0 |
| radial-at-position | radial-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 1 | 86.7 |
| radial-spotlight-small | radial-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 1 | 82.2 |
| shadow-offset-blur | box-shadow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| shadow-spread-multi | box-shadow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 35 | 65.9 |
| shadow-inset | box-shadow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 1 | 85.8 |
| shadow-small | box-shadow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| opacity-basic | opacity | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 12 | 82.7 |
| opacity-nested | opacity | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 14 | 78.0 |
| opacity-with-radius-shadow | opacity | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 11 | 70.3 |
| overflow-hidden-clip | overflow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 15 | 72.0 |
| overflow-radius-clip | overflow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 15 | 70.3 |
| overflow-nested | overflow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| transform-basic | transform | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 2 / 2 | 0.001 | 167 | 63.1 |
| transform-combined-origin | transform | equivalent | 1.0000 | 1.0000 | 0.001 | 0.001 | 8 / 7 | 0.001 | 196 | 57.9 |
| transform-text-small | transform | equivalent | 0.9995 | 0.9996 | 0.077 | 0.011 | 92 / 13 | 0.024 | 62 | 48.2 |
| text-single-sizes | text-single-line | equivalent | 1.0000 | 1.0000 | 0.002 | 0.000 | 13 / 0 | 0.004 | 45 | 60.5 |
| text-single-colors-small | text-single-line | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.004 | 15 | 62.5 |
| text-single-fonts | text-single-line | equivalent | 1.0000 | 1.0000 | 0.002 | 0.000 | 12 / 0 | 0.004 | 45 | 60.0 |
| text-paragraph-wrap | text-paragraph | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.004 | 16 | 60.3 |
| text-paragraph-lineheight | text-paragraph | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 2 / 0 | 0.005 | 30 | 59.1 |
| text-paragraph-letterspacing | text-paragraph | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.005 | 16 | 59.8 |
| text-paragraph-small | text-paragraph | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.009 | 15 | 56.9 |
| text-long-wrap | text-paragraph | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 15 | 64.0 |
| fonts-weights-italic | fonts | equivalent | 1.0000 | 1.0000 | 0.002 | 0.000 | 11 / 0 | 0.007 | 32 | 57.6 |
| fonts-mixed-inline | fonts | equivalent | 1.0000 | 1.0000 | 0.015 | 0.000 | 112 / 0 | 0.010 | 60 | 55.6 |
| text-vietnamese | text-i18n | equivalent | 1.0000 | 1.0000 | 0.002 | 0.000 | 13 / 0 | 0.006 | 60 | 58.3 |
| text-accented-latin | text-i18n | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 5 / 0 | 0.004 | 59 | 59.9 |
| text-ellipsis-nowrap | text-truncation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 2 / 0 | 0.002 | 30 | 63.5 |
| text-lineclamp | text-truncation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 15 | 62.3 |
| text-lineclamp-small | text-truncation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 15 | 63.5 |
| img-png-fit | images | equivalent | 0.9999 | 0.9999 | 0.000 | 0.000 | 0 / 0 | 0.025 | 14 | 59.2 |
| img-jpeg-fit | images | equivalent | 0.9996 | 0.9994 | 0.000 | 0.000 | 1 / 1 | 0.114 | 28 | 51.6 |
| img-intrinsic-size | images | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 1 | 85.5 |
| img-radius-clip | images | equivalent | 1.0000 | 0.9999 | 0.000 | 0.000 | 0 / 0 | 0.022 | 2 | 64.7 |
| img-photo-bg | images | equivalent | 0.9999 | 0.9998 | 0.000 | 0.000 | 0 / 0 | 0.016 | 3 | 65.8 |
| grid-fixed-fr | grid | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 16 | 78.7 |
| grid-repeat-gap | grid | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 31 | 74.0 |
| grid-spans | grid | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 31 | 77.8 |
| grid-small-mixed | grid | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 70.7 |
| card-og | og-card | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 24 | 64.0 |
| card-og-small | og-card | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.009 | 15 | 57.6 |
| card-blog | blog-card | equivalent | 1.0000 | 0.9999 | 0.001 | 0.000 | 4 / 0 | 0.010 | 61 | 61.3 |
| card-flat-ui | blog-card | equivalent | 0.9998 | 0.9998 | 0.005 | 0.000 | 39 / 0 | 0.011 | 54 | 53.9 |
| stress-600-boxes | stress | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| stress-200-labels | stress | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.005 | 14 | 60.0 |
| stress-3000x2000-card | stress | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 16 / 0 | 0.002 | 39 | 64.2 |
| fx-text-shadow | text-shadow | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.003 | 29 | 63.1 |
| gap-dashed-dotted-border | known-gaps | equivalent | 0.9994 | 0.9995 | 0.123 | 0.000 | 148 / 0 | 0.065 | 82 | 44.7 |
| fx-filter-blur-grayscale | filter | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-tailwind-tw | known-gaps | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 14 | 69.4 |
| gap-oklch-color | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-svg-image | known-gaps | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 1 | 77.6 |
| gap-inline-box-decoration | known-gaps | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.010 | 15 | 56.4 |
| gap-mix-blend-mode | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-clip-path | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-background-clip-text | known-gaps | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.012 | 1 | 67.3 |
| gap-text-wrap-balance | known-gaps | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.007 | 15 | 58.2 |
| pfx-aa-shapes | aa-exact | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-aa-text | aa-exact | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.008 | 30 | 57.7 |
| pfx-border-dashed | dashed-border | equivalent | 0.9997 | 0.9997 | 0.077 | 0.000 | 93 / 0 | 0.039 | 104 | 45.2 |
| pfx-border-dotted | dotted-border | equivalent | 0.9987 | 0.9988 | 0.248 | 0.000 | 298 / 0 | 0.112 | 95 | 42.1 |
| pfx-border-double-3d | double-3d-border | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-border-mixed | mixed-border | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 11 | 69.6 |
| pfx-outline | outline | equivalent | 0.9996 | 0.9996 | 0.068 | 0.001 | 81 / 1 | 0.042 | 117 | 45.9 |
| pfx-clip-path-shapes | clip-path | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-mask-gradient | mask | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-bg-clip-text | bg-clip-text | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.022 | 16 | 61.1 |
| pfx-mix-blend | mix-blend | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-bg-blend | bg-blend | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-drop-shadow | drop-shadow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 27 | 64.5 |
| pfx-backdrop-filter | backdrop-filter | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-text-stroke | text-stroke | equivalent | 0.9986 | 0.9989 | 0.195 | 0.007 | 234 / 8 | 0.100 | 154 | 44.3 |
| pfx-text-decoration | text-decoration | equivalent | 0.9992 | 0.9993 | 0.019 | 0.015 | 29 / 23 | 0.058 | 238 | 39.9 |
| pfx-visibility | visibility | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-opacity-layers | opacity | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 11 | 74.2 |
| pfx-svg-background | svg-image | equivalent | 0.9989 | 0.9989 | 0.095 | 0.000 | 114 / 0 | 0.114 | 59 | 44.6 |
| pfx-inline-boxes-many | inline-box | equivalent | 1.0000 | 1.0000 | 0.008 | 0.006 | 14 / 10 | 0.016 | 30 | 54.3 |
| css-class-id | css-stylesheet | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 7 / 0 | 0.001 | 30 | 65.5 |
| css-nth-child | css-stylesheet | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 14 | 68.5 |
| css-media-layer | css-stylesheet | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| css-important-var | css-stylesheet | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 13 | 77.5 |
| tw-card | tailwind | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 65.5 |
| tw-responsive | tailwind | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| tw-structural | tailwind | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| tw-arbitrary | tailwind | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 19 | 69.6 |
| html-article | html | equivalent | 1.0000 | 1.0000 | 0.002 | 0.000 | 12 / 0 | 0.003 | 29 | 61.2 |
| html-document | html | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 32 | 66.7 |
| html-flex-card | html | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 12 | 73.2 |
| html-inline | html | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 1 / 0 | 0.004 | 32 | 59.9 |
| pseudo-inline | pseudo-elements | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 1 / 0 | 0.004 | 30 | 60.4 |
| pseudo-block | pseudo-elements | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 67.4 |
| pseudo-attr | pseudo-elements | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 13 | 72.4 |
| pseudo-tw | pseudo-elements | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 15 | 67.3 |
| anim-opacity-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t250 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t900 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t1500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t200 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t400 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t600 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t800 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-color-t0 | animation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 12 | 71.9 |
| anim-color-t300 | animation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 6 | 78.9 |
| anim-color-t700 | animation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 6 | 80.3 |
| anim-color-t2000 | animation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 13 | 72.8 |
| anim-width-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-width-t100 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-width-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-width-t999 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-delay-fill-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-delay-fill-t750 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-delay-fill-t2000 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t100 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t700 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t1100 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t1300 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-steps-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-steps-t260 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-steps-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-steps-t990 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-two-anims-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-two-anims-t400 | animation | equivalent | 0.9998 | 0.9998 | 0.005 | 0.005 | 4 / 4 | 0.003 | 89 | 55.4 |
| anim-two-anims-t600 | animation | equivalent | 0.9998 | 0.9998 | 0.004 | 0.004 | 3 / 3 | 0.003 | 127 | 53.6 |
| anim-two-anims-t1200 | animation | equivalent | 0.9997 | 0.9997 | 0.005 | 0.005 | 4 / 4 | 0.005 | 214 | 48.5 |
| anim-inherit-t0 | animation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 12 | 65.7 |
| anim-inherit-t500 | animation | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.007 | 23 | 59.9 |
| anim-inherit-t1000 | animation | equivalent | 1.0000 | 1.0000 | 0.004 | 0.000 | 3 / 0 | 0.004 | 29 | 61.1 |
| anim-tw-spin-t125 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-tw-spin-t375 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-tw-spin-t1600 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-kf-option-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-kf-option-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-auto | table | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 15 | 62.1 |
| layout2-table-spans | table | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 15 | 62.7 |
| layout2-table-fixed | table | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.005 | 31 | 60.2 |
| layout2-table-percent | table | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 67.5 |
| layout2-table-collapse-conflicts | table | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 16 | 63.0 |
| layout2-table-col-backgrounds | table | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 15 | 64.6 |
| layout2-table-empty-cells | table | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 15 | 72.7 |
| layout2-table-caption-bottom | table | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.001 | 26 | 65.7 |
| layout2-float-image | float | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 16 | 62.4 |
| layout2-float-clear | float | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 15 | 68.2 |
| layout2-float-bfc | float | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-float-wrap | float | close | 0.9511 | 0.9511 | 1.676 | 0.776 | 2615 / 1210 | 1.703 | 240 | 23.6 |
| layout2-ib-badges | inline-block | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 15 | 65.7 |
| layout2-ib-wrap | inline-block | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 15 | 62.0 |
| layout2-ib-valign | inline-block | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 16 | 63.0 |
| layout2-ib-json | inline-block | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.003 | 32 | 61.6 |
| layout2-grid-areas | grid-areas | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 69.9 |
| layout2-grid-named-lines | grid-areas | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 67.9 |
| layout2-grid-areas-auto | grid-areas | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 9 | 80.5 |

### takumi-native vs takumi-wasm

| case | feature | verdict | SSIM luma | SSIM RGB | % diff strict | % diff AA-tol | px strict / AA | mean abs | max abs | PSNR dB |
| :-- | :-- | :-- | --: | --: | --: | --: | --: | --: | --: | --: |
| colors-solid-bg | colors | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| colors-hex | colors | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| colors-functional | colors | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| colors-named | colors | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| colors-transparent-canvas | colors | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-row-column | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-justify-align | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-wrap-gap | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-grow-shrink-basis | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-nested-small | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-percent | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-minmax | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-aspect-ratio | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-padding-margin | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-auto-margin-center | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| abs-inset | absolute | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| abs-zorder | absolute | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| abs-in-flow | absolute | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| borders-uniform | borders | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| borders-per-side | borders | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| borders-with-radius | borders | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radius-uniform-percorner | border-radius | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radius-elliptical | border-radius | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radius-pill-circle | border-radius | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radius-small | border-radius | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| lingrad-angles | linear-gradient | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| lingrad-multistop | linear-gradient | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| lingrad-alpha | linear-gradient | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| lingrad-hero-small | linear-gradient | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radial-shapes | radial-gradient | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radial-at-position | radial-gradient | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| radial-spotlight-small | radial-gradient | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| shadow-offset-blur | box-shadow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| shadow-spread-multi | box-shadow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| shadow-inset | box-shadow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| shadow-small | box-shadow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| opacity-basic | opacity | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| opacity-nested | opacity | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| opacity-with-radius-shadow | opacity | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| overflow-hidden-clip | overflow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| overflow-radius-clip | overflow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| overflow-nested | overflow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| transform-basic | transform | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| transform-combined-origin | transform | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| transform-text-small | transform | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-single-sizes | text-single-line | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-single-colors-small | text-single-line | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-single-fonts | text-single-line | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-paragraph-wrap | text-paragraph | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-paragraph-lineheight | text-paragraph | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-paragraph-letterspacing | text-paragraph | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-paragraph-small | text-paragraph | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-long-wrap | text-paragraph | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| fonts-weights-italic | fonts | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| fonts-mixed-inline | fonts | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-vietnamese | text-i18n | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-accented-latin | text-i18n | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-ellipsis-nowrap | text-truncation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-lineclamp | text-truncation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| text-lineclamp-small | text-truncation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| img-png-fit | images | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| img-jpeg-fit | images | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| img-intrinsic-size | images | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| img-radius-clip | images | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| img-photo-bg | images | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| grid-fixed-fr | grid | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| grid-repeat-gap | grid | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| grid-spans | grid | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| grid-small-mixed | grid | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| card-og | og-card | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| card-og-small | og-card | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| card-blog | blog-card | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| card-flat-ui | blog-card | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| stress-600-boxes | stress | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| stress-200-labels | stress | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| stress-3000x2000-card | stress | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| fx-text-shadow | text-shadow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-dashed-dotted-border | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| fx-filter-blur-grayscale | filter | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-tailwind-tw | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-oklch-color | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-svg-image | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-inline-box-decoration | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-mix-blend-mode | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-clip-path | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-background-clip-text | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-text-wrap-balance | known-gaps | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-aa-shapes | aa-exact | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-aa-text | aa-exact | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-border-dashed | dashed-border | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-border-dotted | dotted-border | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-border-double-3d | double-3d-border | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-border-mixed | mixed-border | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-outline | outline | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-clip-path-shapes | clip-path | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-mask-gradient | mask | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-bg-clip-text | bg-clip-text | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-mix-blend | mix-blend | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-bg-blend | bg-blend | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-drop-shadow | drop-shadow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-backdrop-filter | backdrop-filter | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-text-stroke | text-stroke | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-text-decoration | text-decoration | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-visibility | visibility | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-opacity-layers | opacity | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-svg-background | svg-image | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pfx-inline-boxes-many | inline-box | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| css-class-id | css-stylesheet | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| css-nth-child | css-stylesheet | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| css-media-layer | css-stylesheet | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| css-important-var | css-stylesheet | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| tw-card | tailwind | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| tw-responsive | tailwind | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| tw-structural | tailwind | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| tw-arbitrary | tailwind | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| html-article | html | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| html-document | html | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| html-flex-card | html | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| html-inline | html | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pseudo-inline | pseudo-elements | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pseudo-block | pseudo-elements | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pseudo-attr | pseudo-elements | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| pseudo-tw | pseudo-elements | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t250 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t900 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-opacity-t1500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t200 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t400 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t600 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-transform-t800 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-color-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-color-t300 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-color-t700 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-color-t2000 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-width-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-width-t100 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-width-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-width-t999 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-delay-fill-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-delay-fill-t750 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-delay-fill-t2000 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t100 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t700 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t1100 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-alternate-t1300 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-steps-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-steps-t260 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-steps-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-steps-t990 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-two-anims-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-two-anims-t400 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-two-anims-t600 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-two-anims-t1200 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-inherit-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-inherit-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-inherit-t1000 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-tw-spin-t125 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-tw-spin-t375 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-tw-spin-t1600 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-kf-option-t0 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| anim-kf-option-t500 | animation | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-auto | table | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-spans | table | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-fixed | table | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-percent | table | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-collapse-conflicts | table | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-col-backgrounds | table | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-empty-cells | table | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-table-caption-bottom | table | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-float-image | float | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-float-clear | float | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-float-bfc | float | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-float-wrap | float | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-ib-badges | inline-block | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-ib-wrap | inline-block | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-ib-valign | inline-block | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-ib-json | inline-block | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-grid-areas | grid-areas | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-grid-named-lines | grid-areas | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout2-grid-areas-auto | grid-areas | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |

Noise floor (native vs wasm): 184/184 identical; lowest SSIM 1.00000 on `colors-solid-bg`.

## Performance

### `format: raw` — median ms (p95)

| case | feature | size | takumi-wasm | takumi-native | bm | bm / takumi-wasm | native / wasm |
| :-- | :-- | --: | --: | --: | --: | --: | --: |
| colors-solid-bg | colors | 400x300 | 0.33 (0.78) | 0.32 (0.69) | 0.23 (0.42) | 0.68 | 0.97 |
| colors-hex | colors | 1200x630 | 3.68 (5.75) | 2.45 (4.79) | 1.89 (3.11) | 0.51 | 0.67 |
| colors-functional | colors | 1200x630 | 2.86 (4.31) | 2.34 (4.80) | 1.78 (3.02) | 0.62 | 0.82 |
| colors-named | colors | 1200x630 | 2.67 (4.38) | 2.59 (4.26) | 1.90 (2.64) | 0.71 | 0.97 |
| colors-transparent-canvas | colors | 400x300 | 0.61 (0.86) | 0.42 (0.85) | 0.40 (0.68) | 0.66 | 0.69 |
| flex-row-column | flex | 1200x630 | 1.47 (2.81) | 1.62 (3.69) | 1.58 (2.68) | 1.07 | 1.10 |
| flex-justify-align | flex | 1200x630 | 1.96 (3.39) | 2.20 (4.13) | 1.74 (2.74) | 0.89 | 1.12 |
| flex-wrap-gap | flex | 1200x630 | 1.70 (4.18) | 2.00 (4.11) | 2.22 (3.64) | 1.30 | 1.18 |
| flex-grow-shrink-basis | flex | 1200x630 | 1.43 (2.69) | 1.59 (3.32) | 1.24 (1.96) | 0.87 | 1.11 |
| flex-nested-small | flex | 400x300 | 0.35 (0.62) | 0.26 (0.69) | 0.22 (0.38) | 0.63 | 0.75 |
| sizing-percent | sizing | 1200x630 | 1.38 (2.90) | 1.57 (3.40) | 1.18 (2.00) | 0.85 | 1.14 |
| sizing-minmax | sizing | 1200x630 | 1.24 (2.65) | 1.48 (3.32) | 1.10 (2.02) | 0.88 | 1.19 |
| sizing-aspect-ratio | sizing | 1200x630 | 1.23 (3.13) | 1.56 (4.12) | 1.25 (2.80) | 1.02 | 1.27 |
| sizing-padding-margin | sizing | 1200x630 | 1.42 (3.41) | 1.84 (3.75) | 1.29 (2.48) | 0.91 | 1.30 |
| sizing-auto-margin-center | sizing | 400x300 | 0.20 (0.40) | 0.20 (0.50) | 0.22 (0.33) | 1.12 | 1.01 |
| abs-inset | absolute | 1200x630 | 2.05 (3.35) | 1.78 (3.56) | 1.28 (2.66) | 0.62 | 0.87 |
| abs-zorder | absolute | 1200x630 | 1.74 (3.68) | 1.86 (4.04) | 2.26 (3.90) | 1.30 | 1.07 |
| abs-in-flow | absolute | 400x300 | 0.33 (0.58) | 0.29 (0.66) | 0.25 (0.40) | 0.75 | 0.89 |
| borders-uniform | borders | 1200x630 | 1.76 (2.97) | 1.70 (3.14) | 1.21 (2.04) | 0.68 | 0.96 |
| borders-per-side | borders | 1200x630 | 1.79 (3.83) | 1.77 (3.58) | 1.44 (2.97) | 0.80 | 0.99 |
| borders-with-radius | borders | 400x300 | 0.81 (1.13) | 0.46 (0.92) | 0.75 (0.92) | 0.92 | 0.56 |
| radius-uniform-percorner | border-radius | 1200x630 | 1.38 (2.61) | 1.63 (3.69) | 1.54 (2.39) | 1.12 | 1.18 |
| radius-elliptical | border-radius | 1200x630 | 1.39 (2.71) | 1.58 (3.27) | 1.63 (3.37) | 1.17 | 1.14 |
| radius-pill-circle | border-radius | 1200x630 | 1.31 (2.84) | 1.50 (2.94) | 1.52 (2.40) | 1.16 | 1.14 |
| radius-small | border-radius | 400x300 | 0.21 (0.39) | 0.20 (0.50) | 0.26 (0.43) | 1.28 | 0.98 |
| lingrad-angles | linear-gradient | 1200x630 | 6.61 (8.73) | 5.26 (7.70) | 3.92 (5.17) | 0.59 | 0.80 |
| lingrad-multistop | linear-gradient | 1200x630 | 6.45 (7.34) | 5.53 (7.15) | 3.17 (4.92) | 0.49 | 0.86 |
| lingrad-alpha | linear-gradient | 1200x630 | 7.44 (8.58) | 5.22 (7.35) | 5.21 (6.72) | 0.70 | 0.70 |
| lingrad-hero-small | linear-gradient | 400x300 | 0.73 (1.03) | 0.55 (0.97) | 0.41 (0.54) | 0.56 | 0.76 |
| radial-shapes | radial-gradient | 1200x630 | 8.02 (9.14) | 6.90 (8.82) | 3.30 (5.15) | 0.41 | 0.86 |
| radial-at-position | radial-gradient | 1200x630 | 9.78 (10.85) | 7.75 (9.08) | 4.04 (5.39) | 0.41 | 0.79 |
| radial-spotlight-small | radial-gradient | 400x300 | 1.40 (1.72) | 1.26 (1.63) | 0.43 (0.77) | 0.30 | 0.90 |
| shadow-offset-blur | box-shadow | 1200x630 | 8.57 (9.77) | 6.29 (8.49) | 4.97 (5.92) | 0.58 | 0.73 |
| shadow-spread-multi | box-shadow | 1200x630 | 8.60 (9.99) | 5.99 (7.18) | 5.50 (6.15) | 0.64 | 0.70 |
| shadow-inset | box-shadow | 1200x630 | 11.48 (12.47) | 8.18 (9.55) | 5.73 (6.35) | 0.50 | 0.71 |
| shadow-small | box-shadow | 400x300 | 1.37 (1.68) | 0.96 (1.49) | 0.75 (0.97) | 0.55 | 0.70 |
| opacity-basic | opacity | 1200x630 | 6.96 (8.43) | 3.72 (6.38) | 3.71 (4.80) | 0.53 | 0.53 |
| opacity-nested | opacity | 1200x630 | 9.80 (11.82) | 4.76 (7.11) | 2.40 (3.85) | 0.24 | 0.49 |
| opacity-with-radius-shadow | opacity | 400x300 | 3.66 (3.99) | 1.96 (2.59) | 1.34 (1.77) | 0.37 | 0.54 |
| overflow-hidden-clip | overflow | 1200x630 | 2.62 (4.21) | 2.43 (4.74) | 1.32 (2.71) | 0.50 | 0.93 |
| overflow-radius-clip | overflow | 1200x630 | 3.63 (5.10) | 3.50 (5.69) | 2.28 (3.07) | 0.63 | 0.96 |
| overflow-nested | overflow | 400x300 | 0.44 (0.71) | 0.34 (0.71) | 0.33 (0.53) | 0.76 | 0.78 |
| transform-basic | transform | 1200x630 | 4.20 (6.17) | 4.45 (7.13) | 2.23 (3.80) | 0.53 | 1.06 |
| transform-combined-origin | transform | 1200x630 | 3.90 (4.74) | 3.51 (14.19) | 2.20 (4.78) | 0.56 | 0.90 |
| transform-text-small | transform | 400x300 | 1.69 (2.27) | 1.24 (1.97) | 0.95 (1.56) | 0.56 | 0.74 |
| text-single-sizes | text-single-line | 1200x630 | 2.11 (3.41) | 2.43 (5.02) | 1.62 (3.10) | 0.77 | 1.15 |
| text-single-colors-small | text-single-line | 400x300 | 0.68 (1.14) | 0.56 (1.01) | 0.30 (0.55) | 0.44 | 0.82 |
| text-single-fonts | text-single-line | 1200x630 | 2.29 (3.65) | 2.48 (5.63) | 1.61 (3.07) | 0.70 | 1.08 |
| text-paragraph-wrap | text-paragraph | 1200x630 | 3.18 (5.59) | 2.94 (4.65) | 2.04 (2.93) | 0.64 | 0.92 |
| text-paragraph-lineheight | text-paragraph | 1200x630 | 3.62 (5.32) | 3.29 (5.52) | 2.20 (3.66) | 0.61 | 0.91 |
| text-paragraph-letterspacing | text-paragraph | 1200x630 | 3.76 (5.48) | 3.45 (5.71) | 2.37 (3.32) | 0.63 | 0.92 |
| text-paragraph-small | text-paragraph | 400x300 | 0.59 (0.81) | 0.48 (0.93) | 0.35 (0.61) | 0.59 | 0.81 |
| text-long-wrap | text-paragraph | 1200x630 | 2.03 (4.16) | 2.16 (4.93) | 1.59 (2.92) | 0.79 | 1.07 |
| fonts-weights-italic | fonts | 1200x630 | 3.03 (4.30) | 2.77 (5.20) | 1.93 (3.29) | 0.64 | 0.92 |
| fonts-mixed-inline | fonts | 1200x630 | 2.42 (4.40) | 2.35 (4.60) | 1.49 (3.17) | 0.62 | 0.97 |
| text-vietnamese | text-i18n | 1200x630 | 2.31 (3.58) | 2.28 (4.65) | 1.55 (3.18) | 0.67 | 0.99 |
| text-accented-latin | text-i18n | 1200x630 | 2.38 (3.55) | 2.37 (5.11) | 1.57 (2.58) | 0.66 | 0.99 |
| text-ellipsis-nowrap | text-truncation | 1200x630 | 2.07 (3.20) | 2.09 (4.60) | 1.34 (2.58) | 0.65 | 1.01 |
| text-lineclamp | text-truncation | 1200x630 | 3.02 (4.07) | 2.74 (5.02) | 2.04 (2.97) | 0.68 | 0.91 |
| text-lineclamp-small | text-truncation | 400x300 | 0.54 (0.85) | 0.43 (0.82) | 0.27 (0.43) | 0.50 | 0.80 |
| img-png-fit | images | 1200x630 | 6.18 (8.52) | 5.10 (6.41) | 2.60 (3.78) | 0.42 | 0.83 |
| img-jpeg-fit | images | 1200x630 | 19.61 (20.71) | 13.02 (15.30) | 2.53 (3.80) | 0.13 | 0.66 |
| img-intrinsic-size | images | 400x300 | 0.39 (0.66) | 0.33 (0.74) | 0.34 (0.55) | 0.87 | 0.85 |
| img-radius-clip | images | 1200x630 | 7.48 (8.39) | 5.94 (7.80) | 4.42 (5.68) | 0.59 | 0.79 |
| img-photo-bg | images | 1200x630 | 6.23 (7.74) | 4.62 (6.55) | 1.80 (3.01) | 0.29 | 0.74 |
| grid-fixed-fr | grid | 1200x630 | 1.96 (3.48) | 2.18 (4.79) | 1.69 (3.34) | 0.87 | 1.11 |
| grid-repeat-gap | grid | 1200x630 | 2.46 (4.02) | 2.37 (4.96) | 1.99 (3.44) | 0.81 | 0.97 |
| grid-spans | grid | 1200x630 | 2.00 (3.15) | 2.13 (4.46) | 1.63 (2.93) | 0.82 | 1.07 |
| grid-small-mixed | grid | 400x300 | 0.71 (0.98) | 0.58 (1.05) | 0.46 (0.69) | 0.65 | 0.83 |
| card-og | og-card | 1200x630 | 6.12 (8.34) | 5.11 (6.75) | 3.72 (4.87) | 0.61 | 0.83 |
| card-og-small | og-card | 600x315 | 2.94 (3.55) | 2.16 (3.08) | 1.57 (1.90) | 0.53 | 0.74 |
| card-blog | blog-card | 1200x630 | 15.72 (16.99) | 7.87 (10.85) | 10.06 (12.05) | 0.64 | 0.50 |
| card-flat-ui | blog-card | 1200x630 | 7.02 (7.93) | 4.98 (6.47) | 4.63 (5.51) | 0.66 | 0.71 |
| stress-600-boxes | stress | 1200x630 | 8.75 (10.67) | 8.30 (10.44) | 8.56 (9.89) | 0.98 | 0.95 |
| stress-200-labels | stress | 1200x630 | 15.19 (17.24) | 12.33 (14.19) | 8.53 (10.02) | 0.56 | 0.81 |
| stress-3000x2000-card | stress | 3000x2000 | 31.51 (36.24) | 27.22 (29.47) | 22.72 (25.45) | 0.72 | 0.86 |
| fx-text-shadow | text-shadow | 600x200 | 1.00 (1.46) | 0.72 (1.25) | 1.00 (1.20) | 1.01 | 0.73 |
| gap-dashed-dotted-border | known-gaps | 600x200 | 1.72 (2.05) | 1.07 (1.39) | 0.96 (1.20) | 0.56 | 0.62 |
| fx-filter-blur-grayscale | filter | 600x200 | 1.77 (2.11) | 1.19 (1.89) | 1.30 (1.54) | 0.74 | 0.67 |
| gap-tailwind-tw | known-gaps | 600x200 | 0.33 (0.64) | 0.28 (0.63) | 0.27 (0.44) | 0.84 | 0.86 |
| gap-oklch-color | known-gaps | 600x200 | 0.18 (0.34) | 0.24 (0.66) | 0.15 (0.25) | 0.85 | 1.35 |
| gap-svg-image | known-gaps | 600x200 | 0.29 (0.55) | 0.23 (0.55) | 0.23 (0.38) | 0.77 | 0.79 |
| gap-inline-box-decoration | known-gaps | 600x200 | 0.51 (0.77) | 0.40 (0.78) | 0.27 (0.45) | 0.52 | 0.79 |
| gap-mix-blend-mode | known-gaps | 600x200 | 0.80 (1.18) | 0.43 (0.83) | 0.39 (0.64) | 0.49 | 0.54 |
| gap-clip-path | known-gaps | 600x200 | 0.61 (0.81) | 0.41 (0.85) | 0.49 (0.68) | 0.81 | 0.67 |
| gap-background-clip-text | known-gaps | 600x200 | 1.85 (2.24) | 1.23 (1.60) | 0.32 (0.52) | 0.17 | 0.67 |
| gap-text-wrap-balance | known-gaps | 600x200 | 0.51 (0.95) | 0.37 (0.76) | 0.24 (0.46) | 0.48 | 0.72 |
| pfx-aa-shapes | aa-exact | 600x200 | 0.52 (0.81) | 0.37 (0.78) | 0.41 (0.74) | 0.78 | 0.72 |
| pfx-aa-text | aa-exact | 600x200 | 0.71 (1.15) | 0.58 (1.05) | 0.34 (0.64) | 0.48 | 0.81 |
| pfx-border-dashed | dashed-border | 600x200 | 2.40 (2.75) | 1.39 (2.03) | 1.34 (1.66) | 0.56 | 0.58 |
| pfx-border-dotted | dotted-border | 600x200 | 2.82 (3.15) | 1.57 (1.97) | 1.50 (1.76) | 0.53 | 0.56 |
| pfx-border-double-3d | double-3d-border | 600x200 | 0.60 (0.88) | 0.46 (0.90) | 0.49 (0.76) | 0.81 | 0.76 |
| pfx-border-mixed | mixed-border | 600x200 | 1.07 (1.32) | 0.62 (1.11) | 0.71 (0.95) | 0.66 | 0.58 |
| pfx-outline | outline | 600x200 | 1.53 (1.80) | 0.93 (1.29) | 0.82 (1.10) | 0.54 | 0.60 |
| pfx-clip-path-shapes | clip-path | 600x200 | 0.87 (1.13) | 0.58 (1.01) | 0.63 (0.81) | 0.72 | 0.67 |
| pfx-mask-gradient | mask | 600x200 | 1.57 (1.92) | 1.04 (1.41) | 1.12 (1.35) | 0.71 | 0.66 |
| pfx-bg-clip-text | bg-clip-text | 600x200 | 2.63 (3.02) | 1.83 (2.28) | 0.44 (0.65) | 0.17 | 0.69 |
| pfx-mix-blend | mix-blend | 600x200 | 1.80 (2.13) | 1.03 (1.51) | 1.23 (1.54) | 0.69 | 0.57 |
| pfx-bg-blend | bg-blend | 600x200 | 4.92 (5.26) | 3.91 (4.27) | 0.99 (1.58) | 0.20 | 0.80 |
| pfx-drop-shadow | drop-shadow | 600x200 | 1.53 (1.87) | 1.09 (1.56) | 1.20 (1.52) | 0.79 | 0.71 |
| pfx-backdrop-filter | backdrop-filter | 600x200 | 4.42 (4.87) | 2.43 (3.03) | 2.79 (3.10) | 0.63 | 0.55 |
| pfx-text-stroke | text-stroke | 600x200 | 0.74 (1.28) | 0.59 (1.03) | 1.18 (1.43) | 1.58 | 0.79 |
| pfx-text-decoration | text-decoration | 600x260 | 1.68 (2.06) | 1.29 (1.89) | 1.80 (2.14) | 1.07 | 0.77 |
| pfx-visibility | visibility | 600x200 | 0.30 (0.51) | 0.27 (0.64) | 0.18 (0.32) | 0.62 | 0.92 |
| pfx-opacity-layers | opacity | 600x200 | 3.00 (3.34) | 1.84 (2.56) | 2.20 (2.94) | 0.73 | 0.61 |
| pfx-svg-background | svg-image | 600x200 | 0.77 (1.05) | 0.48 (0.87) | 1.19 (1.47) | 1.55 | 0.63 |
| pfx-inline-boxes-many | inline-box | 600x300 | 2.67 (3.06) | 1.91 (2.68) | 1.85 (2.20) | 0.69 | 0.71 |
| css-class-id | css-stylesheet | 1200x630 | 2.55 (4.65) | 2.58 (4.83) | 1.83 (3.47) | 0.72 | 1.01 |
| css-nth-child | css-stylesheet | 800x500 | 1.58 (2.69) | 1.43 (3.12) | 1.10 (1.82) | 0.69 | 0.91 |
| css-media-layer | css-stylesheet | 1200x400 | 0.83 (1.80) | 1.21 (2.92) | 0.89 (1.36) | 1.07 | 1.47 |
| css-important-var | css-stylesheet | 900x400 | 0.99 (1.79) | 1.07 (3.00) | 0.67 (1.13) | 0.68 | 1.08 |
| tw-card | tailwind | 1200x630 | 2.16 (4.04) | 2.21 (4.73) | 1.65 (3.47) | 0.76 | 1.02 |
| tw-responsive | tailwind | 1200x400 | 0.72 (1.67) | 1.30 (2.63) | 0.79 (1.37) | 1.09 | 1.79 |
| tw-structural | tailwind | 800x500 | 0.77 (1.74) | 0.96 (2.58) | 0.90 (1.42) | 1.17 | 1.24 |
| tw-arbitrary | tailwind | 900x450 | 5.23 (6.48) | 3.88 (5.91) | 2.83 (3.97) | 0.54 | 0.74 |
| html-article | html | 1000x600 | 1.71 (2.89) | 1.68 (4.07) | 1.21 (2.02) | 0.71 | 0.98 |
| html-document | html | 800x400 | 0.80 (1.63) | 0.98 (2.77) | 0.57 (1.16) | 0.72 | 1.23 |
| html-flex-card | html | 1000x500 | 3.84 (5.04) | 2.88 (4.63) | 2.01 (2.93) | 0.52 | 0.75 |
| html-inline | html | 900x300 | 1.09 (1.59) | 1.12 (2.65) | 0.64 (0.99) | 0.58 | 1.02 |
| pseudo-inline | pseudo-elements | 800x300 | 0.81 (1.32) | 0.82 (1.53) | 0.41 (0.72) | 0.51 | 1.00 |
| pseudo-block | pseudo-elements | 800x400 | 0.99 (1.63) | 1.09 (2.78) | 0.76 (1.22) | 0.77 | 1.09 |
| pseudo-attr | pseudo-elements | 800x250 | 0.70 (1.15) | 0.51 (1.01) | 0.39 (0.71) | 0.56 | 0.73 |
| pseudo-tw | pseudo-elements | 800x300 | 0.65 (1.17) | 0.72 (1.51) | 0.51 (0.81) | 0.77 | 1.10 |
| anim-opacity-t0 | animation | 400x200 | 0.14 (0.24) | 0.14 (0.35) | 0.12 (0.23) | 0.85 | 1.01 |
| anim-opacity-t250 | animation | 400x200 | 0.30 (0.49) | 0.21 (0.45) | 0.14 (0.24) | 0.47 | 0.71 |
| anim-opacity-t500 | animation | 400x200 | 0.29 (0.45) | 0.22 (0.51) | 0.14 (0.23) | 0.47 | 0.76 |
| anim-opacity-t900 | animation | 400x200 | 0.30 (0.47) | 0.21 (0.44) | 0.14 (0.23) | 0.47 | 0.69 |
| anim-opacity-t1500 | animation | 400x200 | 0.15 (0.29) | 0.15 (0.36) | 0.11 (0.19) | 0.79 | 1.02 |
| anim-transform-t0 | animation | 400x200 | 0.15 (0.26) | 0.16 (0.37) | 0.16 (0.24) | 1.01 | 1.02 |
| anim-transform-t200 | animation | 400x200 | 0.16 (0.29) | 0.17 (0.42) | 0.16 (0.27) | 0.98 | 1.01 |
| anim-transform-t400 | animation | 400x200 | 0.17 (0.34) | 0.18 (0.42) | 0.16 (0.26) | 0.91 | 1.03 |
| anim-transform-t600 | animation | 400x200 | 0.16 (0.29) | 0.16 (0.39) | 0.16 (0.25) | 0.98 | 1.02 |
| anim-transform-t800 | animation | 400x200 | 0.16 (0.35) | 0.16 (0.36) | 0.14 (0.24) | 0.89 | 1.00 |
| anim-color-t0 | animation | 400x200 | 0.32 (0.55) | 0.26 (0.56) | 0.16 (0.25) | 0.51 | 0.82 |
| anim-color-t300 | animation | 400x200 | 0.30 (0.51) | 0.26 (0.57) | 0.16 (0.26) | 0.55 | 0.88 |
| anim-color-t700 | animation | 400x200 | 0.29 (0.51) | 0.27 (0.56) | 0.16 (0.26) | 0.55 | 0.91 |
| anim-color-t2000 | animation | 400x200 | 0.29 (0.48) | 0.27 (0.58) | 0.17 (0.27) | 0.58 | 0.93 |
| anim-width-t0 | animation | 400x200 | 0.16 (0.29) | 0.17 (0.41) | 0.13 (0.21) | 0.85 | 1.10 |
| anim-width-t100 | animation | 400x200 | 0.16 (0.30) | 0.17 (0.39) | 0.17 (0.26) | 1.04 | 1.03 |
| anim-width-t500 | animation | 400x200 | 0.19 (0.33) | 0.18 (0.41) | 0.21 (0.30) | 1.13 | 0.97 |
| anim-width-t999 | animation | 400x200 | 0.19 (0.35) | 0.21 (0.50) | 0.21 (0.30) | 1.09 | 1.07 |
| anim-delay-fill-t0 | animation | 400x200 | 0.31 (0.55) | 0.23 (0.52) | 0.18 (0.27) | 0.57 | 0.75 |
| anim-delay-fill-t750 | animation | 400x200 | 0.47 (0.78) | 0.28 (0.57) | 0.21 (0.34) | 0.45 | 0.60 |
| anim-delay-fill-t2000 | animation | 400x200 | 0.18 (0.32) | 0.19 (0.43) | 0.17 (0.28) | 0.90 | 1.04 |
| anim-alternate-t100 | animation | 400x200 | 0.31 (0.45) | 0.24 (0.51) | 0.14 (0.25) | 0.44 | 0.79 |
| anim-alternate-t500 | animation | 400x200 | 0.30 (0.51) | 0.24 (0.49) | 0.14 (0.23) | 0.46 | 0.78 |
| anim-alternate-t700 | animation | 400x200 | 0.30 (0.45) | 0.24 (0.50) | 0.13 (0.22) | 0.44 | 0.78 |
| anim-alternate-t1100 | animation | 400x200 | 0.35 (0.58) | 0.24 (0.52) | 0.14 (0.23) | 0.41 | 0.69 |
| anim-alternate-t1300 | animation | 400x200 | 0.14 (0.26) | 0.15 (0.39) | 0.13 (0.20) | 0.86 | 1.05 |
| anim-steps-t0 | animation | 400x200 | 0.16 (0.31) | 0.17 (0.43) | 0.14 (0.22) | 0.87 | 1.07 |
| anim-steps-t260 | animation | 400x200 | 0.16 (0.29) | 0.17 (0.42) | 0.15 (0.26) | 0.91 | 1.07 |
| anim-steps-t500 | animation | 400x200 | 0.16 (0.29) | 0.17 (0.39) | 0.14 (0.22) | 0.89 | 1.07 |
| anim-steps-t990 | animation | 400x200 | 0.16 (0.28) | 0.16 (0.41) | 0.14 (0.22) | 0.87 | 1.03 |
| anim-two-anims-t0 | animation | 400x200 | 0.29 (0.46) | 0.22 (0.47) | 0.16 (0.24) | 0.55 | 0.74 |
| anim-two-anims-t400 | animation | 400x200 | 0.58 (0.82) | 0.34 (0.63) | 0.24 (0.38) | 0.41 | 0.58 |
| anim-two-anims-t600 | animation | 400x200 | 0.66 (0.89) | 0.37 (0.70) | 0.25 (0.35) | 0.37 | 0.55 |
| anim-two-anims-t1200 | animation | 400x200 | 0.36 (0.51) | 0.26 (0.53) | 0.17 (0.28) | 0.46 | 0.72 |
| anim-inherit-t0 | animation | 400x200 | 0.35 (0.60) | 0.32 (0.63) | 0.19 (0.33) | 0.55 | 0.92 |
| anim-inherit-t500 | animation | 400x200 | 0.38 (0.55) | 0.32 (0.65) | 0.20 (0.32) | 0.53 | 0.85 |
| anim-inherit-t1000 | animation | 400x200 | 0.42 (0.66) | 0.34 (0.68) | 0.21 (0.33) | 0.50 | 0.79 |
| anim-tw-spin-t125 | animation | 400x200 | 0.31 (0.45) | 0.25 (0.54) | 0.15 (0.24) | 0.47 | 0.81 |
| anim-tw-spin-t375 | animation | 400x200 | 0.31 (0.51) | 0.24 (0.49) | 0.15 (0.24) | 0.48 | 0.77 |
| anim-tw-spin-t1600 | animation | 400x200 | 0.32 (0.56) | 0.24 (0.50) | 0.15 (0.25) | 0.47 | 0.76 |
| anim-kf-option-t0 | animation | 400x200 | 0.21 (0.36) | 0.20 (0.48) | 0.18 (0.27) | 0.83 | 0.92 |
| anim-kf-option-t500 | animation | 400x200 | 0.48 (0.86) | 0.32 (0.81) | 0.21 (0.37) | 0.44 | 0.66 |
| layout2-table-auto | table | 600x300 | 1.28 (1.79) | 1.03 (1.82) | 0.84 (1.15) | 0.66 | 0.80 |
| layout2-table-spans | table | 600x320 | 0.88 (1.36) | 0.71 (1.20) | 0.58 (0.81) | 0.66 | 0.80 |
| layout2-table-fixed | table | 600x260 | 1.16 (1.49) | 0.93 (1.46) | 0.69 (1.11) | 0.60 | 0.80 |
| layout2-table-percent | table | 600x220 | 0.64 (0.94) | 0.52 (0.93) | 0.39 (0.64) | 0.61 | 0.81 |
| layout2-table-collapse-conflicts | table | 600x300 | 1.33 (1.86) | 1.05 (1.56) | 0.81 (1.29) | 0.61 | 0.79 |
| layout2-table-col-backgrounds | table | 600x260 | 1.93 (2.52) | 1.50 (2.02) | 0.96 (1.26) | 0.50 | 0.78 |
| layout2-table-empty-cells | table | 600x240 | 1.09 (1.46) | 0.91 (1.29) | 0.61 (0.94) | 0.56 | 0.84 |
| layout2-table-caption-bottom | table | 600x300 | 1.53 (2.01) | 1.13 (1.74) | 0.91 (1.46) | 0.59 | 0.74 |
| layout2-float-image | float | 600x240 | 0.73 (1.11) | 0.60 (1.17) | 0.58 (0.83) | 0.79 | 0.82 |
| layout2-float-clear | float | 600x260 | 0.37 (0.64) | 0.33 (0.72) | 0.30 (0.48) | 0.83 | 0.90 |
| layout2-float-bfc | float | 600x260 | 0.52 (0.80) | 0.42 (0.93) | 0.31 (0.58) | 0.58 | 0.81 |
| layout2-float-wrap | float | 600x260 | 0.67 (0.95) | 0.49 (1.03) | 0.49 (0.71) | 0.74 | 0.73 |
| layout2-ib-badges | inline-block | 600x200 | 0.54 (0.83) | 0.44 (0.94) | 0.33 (0.48) | 0.60 | 0.81 |
| layout2-ib-wrap | inline-block | 600x260 | 0.66 (0.91) | 0.54 (1.05) | 0.48 (0.72) | 0.74 | 0.82 |
| layout2-ib-valign | inline-block | 600x220 | 0.56 (0.82) | 0.47 (0.93) | 0.35 (0.53) | 0.63 | 0.83 |
| layout2-ib-json | inline-block | 600x160 | 0.45 (0.67) | 0.36 (0.75) | 0.25 (0.42) | 0.55 | 0.80 |
| layout2-grid-areas | grid-areas | 600x360 | 0.72 (1.32) | 0.61 (1.18) | 0.61 (0.85) | 0.84 | 0.84 |
| layout2-grid-named-lines | grid-areas | 600x300 | 0.79 (1.35) | 0.70 (1.13) | 0.58 (1.00) | 0.73 | 0.88 |
| layout2-grid-areas-auto | grid-areas | 600x300 | 0.64 (1.02) | 0.58 (1.11) | 0.44 (0.73) | 0.69 | 0.91 |

### `format: png` — median ms (p95)

| case | feature | size | takumi-wasm | takumi-native | bm | bm / takumi-wasm | native / wasm |
| :-- | :-- | --: | --: | --: | --: | --: | --: |
| colors-solid-bg | colors | 400x300 | 1.23 (1.52) | 0.70 (1.08) | 0.45 (0.59) | 0.36 | 0.57 |
| colors-hex | colors | 1200x630 | 8.71 (9.51) | 4.47 (5.16) | 3.16 (4.18) | 0.36 | 0.51 |
| colors-functional | colors | 1200x630 | 7.76 (8.29) | 4.06 (4.67) | 2.88 (3.67) | 0.37 | 0.52 |
| colors-named | colors | 1200x630 | 7.91 (8.37) | 4.51 (5.33) | 3.11 (3.68) | 0.39 | 0.57 |
| colors-transparent-canvas | colors | 400x300 | 1.39 (1.58) | 0.85 (1.36) | 0.62 (1.12) | 0.44 | 0.61 |
| flex-row-column | flex | 1200x630 | 7.06 (7.77) | 3.52 (4.43) | 2.66 (3.28) | 0.38 | 0.50 |
| flex-justify-align | flex | 1200x630 | 6.66 (7.36) | 3.41 (4.32) | 2.91 (3.62) | 0.44 | 0.51 |
| flex-wrap-gap | flex | 1200x630 | 6.68 (7.69) | 3.52 (4.34) | 3.36 (4.35) | 0.50 | 0.53 |
| flex-grow-shrink-basis | flex | 1200x630 | 5.68 (6.15) | 2.95 (3.65) | 3.32 (3.85) | 0.58 | 0.52 |
| flex-nested-small | flex | 400x300 | 1.12 (1.34) | 0.67 (0.92) | 0.43 (0.62) | 0.38 | 0.59 |
| sizing-percent | sizing | 1200x630 | 7.01 (7.95) | 3.59 (4.31) | 3.27 (3.77) | 0.47 | 0.51 |
| sizing-minmax | sizing | 1200x630 | 6.38 (6.87) | 3.60 (4.38) | 3.13 (3.97) | 0.49 | 0.57 |
| sizing-aspect-ratio | sizing | 1200x630 | 6.90 (7.41) | 3.54 (4.08) | 2.25 (2.93) | 0.33 | 0.51 |
| sizing-padding-margin | sizing | 1200x630 | 6.67 (7.24) | 3.26 (4.08) | 3.47 (4.26) | 0.52 | 0.49 |
| sizing-auto-margin-center | sizing | 400x300 | 0.89 (1.10) | 0.52 (0.70) | 0.50 (0.60) | 0.57 | 0.58 |
| abs-inset | absolute | 1200x630 | 8.04 (8.68) | 3.95 (4.86) | 3.40 (4.06) | 0.42 | 0.49 |
| abs-zorder | absolute | 1200x630 | 14.59 (15.49) | 4.36 (5.18) | 6.76 (8.46) | 0.46 | 0.30 |
| abs-in-flow | absolute | 400x300 | 1.29 (1.54) | 0.85 (1.18) | 0.49 (0.62) | 0.38 | 0.66 |
| borders-uniform | borders | 1200x630 | 6.24 (10.32) | 3.29 (4.78) | 3.30 (4.02) | 0.53 | 0.53 |
| borders-per-side | borders | 1200x630 | 6.52 (7.19) | 3.37 (4.30) | 2.26 (3.00) | 0.35 | 0.52 |
| borders-with-radius | borders | 400x300 | 1.78 (2.01) | 1.09 (1.45) | 1.12 (1.27) | 0.63 | 0.61 |
| radius-uniform-percorner | border-radius | 1200x630 | 7.33 (7.64) | 3.51 (4.06) | 3.02 (3.64) | 0.41 | 0.48 |
| radius-elliptical | border-radius | 1200x630 | 6.66 (7.38) | 3.20 (3.96) | 2.96 (3.59) | 0.44 | 0.48 |
| radius-pill-circle | border-radius | 1200x630 | 6.11 (6.96) | 2.91 (3.67) | 2.72 (3.52) | 0.45 | 0.48 |
| radius-small | border-radius | 400x300 | 0.95 (1.46) | 0.57 (0.79) | 0.47 (0.61) | 0.50 | 0.60 |
| lingrad-angles | linear-gradient | 1200x630 | 35.52 (36.32) | 8.29 (10.29) | 10.22 (11.03) | 0.29 | 0.23 |
| lingrad-multistop | linear-gradient | 1200x630 | 24.33 (24.67) | 7.20 (7.91) | 10.81 (12.89) | 0.44 | 0.30 |
| lingrad-alpha | linear-gradient | 1200x630 | 30.20 (33.94) | 7.20 (8.16) | 9.23 (10.01) | 0.31 | 0.24 |
| lingrad-hero-small | linear-gradient | 400x300 | 3.26 (3.63) | 1.40 (1.77) | 1.80 (2.12) | 0.55 | 0.43 |
| radial-shapes | radial-gradient | 1200x630 | 37.83 (42.56) | 11.11 (13.33) | 18.23 (25.21) | 0.48 | 0.29 |
| radial-at-position | radial-gradient | 1200x630 | 39.29 (40.52) | 12.03 (13.10) | 16.81 (18.46) | 0.43 | 0.31 |
| radial-spotlight-small | radial-gradient | 400x300 | 10.23 (10.45) | 2.76 (3.48) | 5.64 (6.06) | 0.55 | 0.27 |
| shadow-offset-blur | box-shadow | 1200x630 | 29.81 (30.27) | 8.43 (8.97) | 13.98 (14.48) | 0.47 | 0.28 |
| shadow-spread-multi | box-shadow | 1200x630 | 29.97 (30.95) | 8.25 (10.02) | 14.85 (15.86) | 0.50 | 0.28 |
| shadow-inset | box-shadow | 1200x630 | 30.44 (32.68) | 9.75 (10.83) | 13.78 (14.48) | 0.45 | 0.32 |
| shadow-small | box-shadow | 400x300 | 2.25 (2.96) | 1.48 (2.02) | 1.16 (1.30) | 0.51 | 0.65 |
| opacity-basic | opacity | 1200x630 | 13.62 (14.97) | 5.63 (6.21) | 5.10 (5.66) | 0.37 | 0.41 |
| opacity-nested | opacity | 1200x630 | 14.75 (16.86) | 6.50 (8.09) | 3.86 (5.41) | 0.26 | 0.44 |
| opacity-with-radius-shadow | opacity | 400x300 | 4.75 (4.97) | 2.48 (3.09) | 1.83 (2.05) | 0.39 | 0.52 |
| overflow-hidden-clip | overflow | 1200x630 | 7.25 (8.27) | 3.79 (4.75) | 2.46 (3.08) | 0.34 | 0.52 |
| overflow-radius-clip | overflow | 1200x630 | 14.97 (15.84) | 5.09 (6.29) | 6.03 (8.04) | 0.40 | 0.34 |
| overflow-nested | overflow | 400x300 | 1.50 (1.75) | 0.93 (1.19) | 0.60 (0.73) | 0.40 | 0.62 |
| transform-basic | transform | 1200x630 | 9.87 (11.82) | 5.06 (6.53) | 3.72 (4.76) | 0.38 | 0.51 |
| transform-combined-origin | transform | 1200x630 | 9.35 (10.33) | 5.10 (7.15) | 3.51 (4.57) | 0.38 | 0.55 |
| transform-text-small | transform | 400x300 | 2.80 (3.37) | 1.86 (2.40) | 1.52 (2.27) | 0.54 | 0.66 |
| text-single-sizes | text-single-line | 1200x630 | 7.55 (10.48) | 4.05 (5.14) | 3.72 (5.02) | 0.49 | 0.54 |
| text-single-colors-small | text-single-line | 400x300 | 1.73 (2.10) | 1.34 (1.84) | 0.78 (1.07) | 0.45 | 0.77 |
| text-single-fonts | text-single-line | 1200x630 | 8.15 (8.91) | 4.34 (7.08) | 4.03 (4.86) | 0.49 | 0.53 |
| text-paragraph-wrap | text-paragraph | 1200x630 | 8.80 (9.35) | 4.58 (5.38) | 4.61 (5.91) | 0.52 | 0.52 |
| text-paragraph-lineheight | text-paragraph | 1200x630 | 9.12 (9.96) | 4.95 (6.19) | 5.15 (5.75) | 0.56 | 0.54 |
| text-paragraph-letterspacing | text-paragraph | 1200x630 | 10.15 (11.05) | 5.18 (6.24) | 6.00 (6.74) | 0.59 | 0.51 |
| text-paragraph-small | text-paragraph | 400x300 | 1.82 (2.19) | 1.23 (1.63) | 1.03 (1.39) | 0.57 | 0.68 |
| text-long-wrap | text-paragraph | 1200x630 | 10.39 (11.64) | 4.23 (5.22) | 3.91 (4.82) | 0.38 | 0.41 |
| fonts-weights-italic | fonts | 1200x630 | 9.76 (10.15) | 4.82 (5.83) | 5.59 (6.09) | 0.57 | 0.49 |
| fonts-mixed-inline | fonts | 1200x630 | 7.97 (9.78) | 4.02 (4.62) | 3.87 (5.01) | 0.49 | 0.50 |
| text-vietnamese | text-i18n | 1200x630 | 8.25 (10.15) | 3.96 (4.69) | 4.09 (5.09) | 0.50 | 0.48 |
| text-accented-latin | text-i18n | 1200x630 | 7.62 (8.16) | 3.88 (4.54) | 4.01 (4.61) | 0.53 | 0.51 |
| text-ellipsis-nowrap | text-truncation | 1200x630 | 6.64 (6.97) | 3.56 (4.22) | 2.53 (3.13) | 0.38 | 0.54 |
| text-lineclamp | text-truncation | 1200x630 | 8.10 (9.12) | 4.22 (4.75) | 3.79 (4.62) | 0.47 | 0.52 |
| text-lineclamp-small | text-truncation | 400x300 | 1.34 (1.62) | 0.88 (1.19) | 0.59 (0.70) | 0.44 | 0.66 |
| img-png-fit | images | 1200x630 | 35.13 (38.78) | 9.35 (9.98) | 18.41 (19.05) | 0.52 | 0.27 |
| img-jpeg-fit | images | 1200x630 | 53.08 (60.69) | 18.84 (19.68) | 28.36 (32.18) | 0.53 | 0.35 |
| img-intrinsic-size | images | 400x300 | 5.26 (7.13) | 1.38 (1.84) | 2.83 (3.29) | 0.54 | 0.26 |
| img-radius-clip | images | 1200x630 | 35.56 (36.64) | 10.64 (12.49) | 23.50 (25.11) | 0.66 | 0.30 |
| img-photo-bg | images | 1200x630 | 54.53 (55.07) | 12.82 (15.16) | 41.79 (43.90) | 0.77 | 0.24 |
| grid-fixed-fr | grid | 1200x630 | 6.71 (7.36) | 3.52 (4.24) | 3.11 (3.87) | 0.46 | 0.52 |
| grid-repeat-gap | grid | 1200x630 | 10.67 (11.40) | 4.38 (5.58) | 3.57 (4.22) | 0.33 | 0.41 |
| grid-spans | grid | 1200x630 | 7.57 (8.31) | 4.01 (4.82) | 2.82 (3.34) | 0.37 | 0.53 |
| grid-small-mixed | grid | 400x300 | 1.74 (2.06) | 1.09 (1.41) | 0.85 (1.00) | 0.49 | 0.62 |
| card-og | og-card | 1200x630 | 21.68 (22.11) | 7.84 (8.93) | 14.48 (15.41) | 0.67 | 0.36 |
| card-og-small | og-card | 600x315 | 8.29 (9.02) | 3.66 (4.61) | 5.88 (6.86) | 0.71 | 0.44 |
| card-blog | blog-card | 1200x630 | 48.83 (49.56) | 12.78 (13.72) | 30.32 (31.24) | 0.62 | 0.26 |
| card-flat-ui | blog-card | 1200x630 | 19.86 (20.64) | 7.20 (8.24) | 8.95 (9.62) | 0.45 | 0.36 |
| stress-600-boxes | stress | 1200x630 | 15.88 (17.00) | 9.76 (10.51) | 12.14 (12.91) | 0.76 | 0.61 |
| stress-200-labels | stress | 1200x630 | 22.89 (23.79) | 14.56 (16.13) | 14.34 (15.00) | 0.63 | 0.64 |
| stress-3000x2000-card | stress | 3000x2000 | 136.09 (140.07) | 41.74 (44.41) | 79.45 (85.12) | 0.58 | 0.31 |
| fx-text-shadow | text-shadow | 600x200 | 4.35 (5.19) | 1.89 (2.39) | 3.95 (4.29) | 0.91 | 0.43 |
| gap-dashed-dotted-border | known-gaps | 600x200 | 2.57 (2.99) | 1.47 (1.74) | 1.24 (1.57) | 0.48 | 0.57 |
| fx-filter-blur-grayscale | filter | 600x200 | 4.89 (5.34) | 1.91 (2.43) | 3.09 (3.52) | 0.63 | 0.39 |
| gap-tailwind-tw | known-gaps | 600x200 | 1.29 (1.57) | 0.83 (1.08) | 0.56 (0.68) | 0.44 | 0.65 |
| gap-oklch-color | known-gaps | 600x200 | 1.08 (1.33) | 0.66 (0.86) | 0.45 (0.55) | 0.42 | 0.61 |
| gap-svg-image | known-gaps | 600x200 | 1.08 (1.41) | 0.65 (1.02) | 0.52 (0.69) | 0.48 | 0.60 |
| gap-inline-box-decoration | known-gaps | 600x200 | 1.72 (2.10) | 1.11 (1.45) | 0.84 (1.10) | 0.49 | 0.64 |
| gap-mix-blend-mode | known-gaps | 600x200 | 1.54 (1.80) | 0.93 (1.21) | 0.71 (0.81) | 0.46 | 0.60 |
| gap-clip-path | known-gaps | 600x200 | 6.46 (6.78) | 1.29 (1.67) | 1.49 (1.67) | 0.23 | 0.20 |
| gap-background-clip-text | known-gaps | 600x200 | 5.32 (5.60) | 2.02 (2.47) | 1.45 (1.63) | 0.27 | 0.38 |
| gap-text-wrap-balance | known-gaps | 600x200 | 1.63 (2.32) | 1.17 (1.55) | 0.79 (1.05) | 0.48 | 0.71 |
| pfx-aa-shapes | aa-exact | 600x200 | 1.37 (1.67) | 0.87 (1.17) | 0.73 (0.87) | 0.53 | 0.64 |
| pfx-aa-text | aa-exact | 600x200 | 1.81 (2.14) | 1.18 (1.44) | 0.98 (1.12) | 0.54 | 0.65 |
| pfx-border-dashed | dashed-border | 600x200 | 3.35 (3.65) | 1.82 (2.11) | 1.67 (1.97) | 0.50 | 0.54 |
| pfx-border-dotted | dotted-border | 600x200 | 3.65 (4.05) | 2.03 (2.36) | 1.83 (2.12) | 0.50 | 0.56 |
| pfx-border-double-3d | double-3d-border | 600x200 | 1.40 (2.16) | 0.84 (1.10) | 0.70 (1.05) | 0.50 | 0.60 |
| pfx-border-mixed | mixed-border | 600x200 | 1.94 (2.22) | 1.15 (1.47) | 1.05 (1.29) | 0.54 | 0.59 |
| pfx-outline | outline | 600x200 | 2.64 (3.40) | 1.55 (1.91) | 1.18 (1.34) | 0.45 | 0.59 |
| pfx-clip-path-shapes | clip-path | 600x200 | 5.44 (5.83) | 1.51 (2.00) | 1.95 (2.18) | 0.36 | 0.28 |
| pfx-mask-gradient | mask | 600x200 | 6.32 (6.61) | 1.80 (2.26) | 2.29 (2.57) | 0.36 | 0.28 |
| pfx-bg-clip-text | bg-clip-text | 600x200 | 5.36 (5.68) | 2.61 (3.05) | 2.16 (2.70) | 0.40 | 0.49 |
| pfx-mix-blend | mix-blend | 600x200 | 7.64 (8.46) | 2.06 (2.66) | 4.15 (4.42) | 0.54 | 0.27 |
| pfx-bg-blend | bg-blend | 600x200 | 10.58 (10.82) | 4.86 (5.41) | 4.37 (4.90) | 0.41 | 0.46 |
| pfx-drop-shadow | drop-shadow | 600x200 | 7.06 (7.51) | 1.91 (2.35) | 3.45 (3.81) | 0.49 | 0.27 |
| pfx-backdrop-filter | backdrop-filter | 600x200 | 7.36 (7.96) | 3.22 (4.08) | 4.11 (4.91) | 0.56 | 0.44 |
| pfx-text-stroke | text-stroke | 600x200 | 2.11 (2.53) | 1.42 (2.02) | 1.90 (2.39) | 0.90 | 0.67 |
| pfx-text-decoration | text-decoration | 600x260 | 3.71 (4.30) | 2.10 (3.04) | 2.85 (3.10) | 0.77 | 0.57 |
| pfx-visibility | visibility | 600x200 | 1.20 (1.53) | 0.76 (1.04) | 0.52 (0.66) | 0.43 | 0.64 |
| pfx-opacity-layers | opacity | 600x200 | 7.07 (7.58) | 2.72 (3.26) | 4.06 (4.62) | 0.57 | 0.38 |
| pfx-svg-background | svg-image | 600x200 | 2.21 (2.68) | 1.25 (1.61) | 1.81 (2.06) | 0.82 | 0.56 |
| pfx-inline-boxes-many | inline-box | 600x300 | 5.34 (5.86) | 2.99 (3.57) | 3.68 (4.33) | 0.69 | 0.56 |
| css-class-id | css-stylesheet | 1200x630 | 7.53 (9.62) | 3.85 (5.35) | 3.38 (4.23) | 0.45 | 0.51 |
| css-nth-child | css-stylesheet | 800x500 | 4.23 (4.99) | 2.61 (3.43) | 1.83 (2.25) | 0.43 | 0.62 |
| css-media-layer | css-stylesheet | 1200x400 | 4.67 (5.05) | 2.57 (3.21) | 1.49 (1.81) | 0.32 | 0.55 |
| css-important-var | css-stylesheet | 900x400 | 3.50 (4.10) | 2.28 (2.77) | 1.09 (1.33) | 0.31 | 0.65 |
| tw-card | tailwind | 1200x630 | 7.59 (9.74) | 4.07 (4.94) | 3.38 (4.14) | 0.45 | 0.54 |
| tw-responsive | tailwind | 1200x400 | 3.64 (4.03) | 2.26 (3.11) | 1.24 (1.50) | 0.34 | 0.62 |
| tw-structural | tailwind | 800x500 | 3.11 (3.44) | 2.04 (2.90) | 1.34 (1.61) | 0.43 | 0.66 |
| tw-arbitrary | tailwind | 900x450 | 8.30 (9.07) | 4.83 (6.65) | 3.74 (4.23) | 0.45 | 0.58 |
| html-article | html | 1000x600 | 5.59 (6.13) | 3.03 (3.52) | 2.42 (3.19) | 0.43 | 0.54 |
| html-document | html | 800x400 | 2.61 (2.99) | 1.82 (2.42) | 1.11 (1.71) | 0.42 | 0.70 |
| html-flex-card | html | 1000x500 | 11.91 (13.19) | 4.71 (5.80) | 6.90 (8.22) | 0.58 | 0.40 |
| html-inline | html | 900x300 | 2.75 (3.24) | 2.04 (2.63) | 1.36 (1.79) | 0.50 | 0.74 |
| pseudo-inline | pseudo-elements | 800x300 | 2.55 (2.85) | 1.42 (1.76) | 1.03 (1.17) | 0.40 | 0.56 |
| pseudo-block | pseudo-elements | 800x400 | 2.91 (3.29) | 1.72 (2.10) | 1.22 (1.52) | 0.42 | 0.59 |
| pseudo-attr | pseudo-elements | 800x250 | 2.01 (2.47) | 1.07 (1.40) | 0.74 (0.86) | 0.37 | 0.54 |
| pseudo-tw | pseudo-elements | 800x300 | 2.25 (2.57) | 1.15 (1.60) | 0.96 (1.20) | 0.43 | 0.51 |
| anim-opacity-t0 | animation | 400x200 | 0.52 (0.84) | 0.34 (0.56) | 0.31 (0.45) | 0.60 | 0.65 |
| anim-opacity-t250 | animation | 400x200 | 0.79 (1.05) | 0.45 (0.64) | 0.33 (0.42) | 0.42 | 0.57 |
| anim-opacity-t500 | animation | 400x200 | 0.76 (0.96) | 0.45 (0.63) | 0.33 (0.44) | 0.44 | 0.59 |
| anim-opacity-t900 | animation | 400x200 | 0.78 (1.03) | 0.47 (0.66) | 0.34 (0.40) | 0.43 | 0.60 |
| anim-opacity-t1500 | animation | 400x200 | 0.61 (0.75) | 0.40 (0.57) | 0.31 (0.36) | 0.51 | 0.66 |
| anim-transform-t0 | animation | 400x200 | 0.64 (0.84) | 0.43 (0.75) | 0.41 (0.54) | 0.63 | 0.67 |
| anim-transform-t200 | animation | 400x200 | 0.66 (0.84) | 0.44 (0.64) | 0.34 (0.42) | 0.51 | 0.67 |
| anim-transform-t400 | animation | 400x200 | 0.64 (0.84) | 0.41 (0.62) | 0.32 (0.38) | 0.50 | 0.65 |
| anim-transform-t600 | animation | 400x200 | 0.65 (0.86) | 0.43 (0.61) | 0.34 (0.46) | 0.52 | 0.65 |
| anim-transform-t800 | animation | 400x200 | 0.65 (0.97) | 0.41 (0.55) | 0.38 (0.46) | 0.59 | 0.64 |
| anim-color-t0 | animation | 400x200 | 0.81 (1.06) | 0.56 (0.90) | 0.32 (0.43) | 0.40 | 0.70 |
| anim-color-t300 | animation | 400x200 | 0.79 (1.01) | 0.55 (0.74) | 0.32 (0.41) | 0.40 | 0.69 |
| anim-color-t700 | animation | 400x200 | 0.85 (1.14) | 0.55 (0.74) | 0.32 (0.41) | 0.38 | 0.65 |
| anim-color-t2000 | animation | 400x200 | 0.80 (0.99) | 0.54 (0.75) | 0.32 (0.41) | 0.40 | 0.67 |
| anim-width-t0 | animation | 400x200 | 0.58 (0.80) | 0.38 (0.57) | 0.34 (0.42) | 0.58 | 0.65 |
| anim-width-t100 | animation | 400x200 | 0.66 (0.80) | 0.43 (0.59) | 0.32 (0.57) | 0.48 | 0.65 |
| anim-width-t500 | animation | 400x200 | 0.70 (1.13) | 0.47 (0.69) | 0.41 (0.50) | 0.58 | 0.68 |
| anim-width-t999 | animation | 400x200 | 0.71 (0.90) | 0.47 (0.67) | 0.41 (0.55) | 0.58 | 0.66 |
| anim-delay-fill-t0 | animation | 400x200 | 0.78 (0.96) | 0.48 (0.71) | 0.41 (0.49) | 0.53 | 0.62 |
| anim-delay-fill-t750 | animation | 400x200 | 0.93 (1.54) | 0.51 (0.70) | 0.44 (0.56) | 0.47 | 0.55 |
| anim-delay-fill-t2000 | animation | 400x200 | 0.67 (0.94) | 0.44 (0.66) | 0.40 (0.53) | 0.60 | 0.66 |
| anim-alternate-t100 | animation | 400x200 | 0.76 (1.03) | 0.48 (0.62) | 0.33 (0.42) | 0.43 | 0.62 |
| anim-alternate-t500 | animation | 400x200 | 0.76 (0.91) | 0.48 (0.63) | 0.34 (0.41) | 0.44 | 0.64 |
| anim-alternate-t700 | animation | 400x200 | 0.76 (0.95) | 0.52 (0.74) | 0.34 (0.42) | 0.44 | 0.68 |
| anim-alternate-t1100 | animation | 400x200 | 0.76 (0.95) | 0.46 (0.64) | 0.33 (0.42) | 0.44 | 0.61 |
| anim-alternate-t1300 | animation | 400x200 | 0.60 (1.12) | 0.40 (0.76) | 0.33 (0.55) | 0.55 | 0.66 |
| anim-steps-t0 | animation | 400x200 | 0.59 (0.75) | 0.39 (0.57) | 0.35 (0.43) | 0.58 | 0.65 |
| anim-steps-t260 | animation | 400x200 | 0.60 (0.78) | 0.38 (0.54) | 0.35 (0.43) | 0.58 | 0.64 |
| anim-steps-t500 | animation | 400x200 | 0.61 (0.78) | 0.38 (0.59) | 0.35 (0.49) | 0.56 | 0.62 |
| anim-steps-t990 | animation | 400x200 | 0.59 (0.74) | 0.39 (0.58) | 0.35 (0.41) | 0.59 | 0.65 |
| anim-two-anims-t0 | animation | 400x200 | 0.78 (1.04) | 0.48 (0.76) | 0.36 (0.44) | 0.47 | 0.62 |
| anim-two-anims-t400 | animation | 400x200 | 1.10 (1.42) | 0.61 (0.87) | 0.46 (0.55) | 0.42 | 0.56 |
| anim-two-anims-t600 | animation | 400x200 | 1.13 (1.32) | 0.66 (1.09) | 0.48 (0.59) | 0.43 | 0.58 |
| anim-two-anims-t1200 | animation | 400x200 | 0.87 (1.07) | 0.52 (0.72) | 0.40 (0.50) | 0.46 | 0.60 |
| anim-inherit-t0 | animation | 400x200 | 0.85 (1.13) | 0.59 (0.86) | 0.39 (0.47) | 0.45 | 0.69 |
| anim-inherit-t500 | animation | 400x200 | 0.99 (1.24) | 0.68 (0.97) | 0.52 (0.78) | 0.52 | 0.69 |
| anim-inherit-t1000 | animation | 400x200 | 1.21 (1.47) | 0.92 (1.20) | 0.60 (0.81) | 0.49 | 0.76 |
| anim-tw-spin-t125 | animation | 400x200 | 0.79 (0.96) | 0.49 (0.71) | 0.36 (0.48) | 0.45 | 0.62 |
| anim-tw-spin-t375 | animation | 400x200 | 0.78 (1.00) | 0.50 (0.71) | 0.37 (0.45) | 0.47 | 0.64 |
| anim-tw-spin-t1600 | animation | 400x200 | 0.79 (0.98) | 0.50 (0.70) | 0.38 (0.44) | 0.48 | 0.63 |
| anim-kf-option-t0 | animation | 400x200 | 0.63 (0.82) | 0.40 (0.58) | 0.38 (0.50) | 0.59 | 0.63 |
| anim-kf-option-t500 | animation | 400x200 | 0.93 (1.11) | 0.54 (0.78) | 0.40 (0.51) | 0.43 | 0.59 |
| layout2-table-auto | table | 600x300 | 2.95 (3.32) | 1.78 (2.56) | 1.47 (1.75) | 0.50 | 0.60 |
| layout2-table-spans | table | 600x320 | 2.23 (2.51) | 1.35 (1.81) | 1.17 (1.44) | 0.52 | 0.60 |
| layout2-table-fixed | table | 600x260 | 2.60 (3.29) | 1.72 (2.16) | 1.32 (2.01) | 0.51 | 0.66 |
| layout2-table-percent | table | 600x220 | 1.51 (1.83) | 1.03 (1.45) | 0.70 (1.06) | 0.46 | 0.69 |
| layout2-table-collapse-conflicts | table | 600x300 | 2.53 (2.89) | 1.64 (1.96) | 1.23 (1.44) | 0.49 | 0.65 |
| layout2-table-col-backgrounds | table | 600x260 | 4.85 (5.29) | 2.36 (2.87) | 2.90 (3.15) | 0.60 | 0.49 |
| layout2-table-empty-cells | table | 600x240 | 1.98 (2.47) | 1.32 (1.73) | 0.86 (1.06) | 0.43 | 0.66 |
| layout2-table-caption-bottom | table | 600x300 | 2.71 (3.11) | 1.85 (2.46) | 1.41 (1.61) | 0.52 | 0.68 |
| layout2-float-image | float | 600x240 | 5.66 (6.10) | 1.63 (2.13) | 2.46 (2.76) | 0.43 | 0.29 |
| layout2-float-clear | float | 600x260 | 1.88 (2.15) | 1.07 (1.43) | 0.61 (0.94) | 0.32 | 0.57 |
| layout2-float-bfc | float | 600x260 | 1.51 (1.89) | 0.91 (1.13) | 0.79 (0.91) | 0.52 | 0.60 |
| layout2-float-wrap | float | 600x260 | 2.21 (2.54) | 1.37 (1.80) | 1.11 (1.28) | 0.50 | 0.62 |
| layout2-ib-badges | inline-block | 600x200 | 1.28 (1.55) | 0.81 (1.08) | 0.60 (0.74) | 0.47 | 0.63 |
| layout2-ib-wrap | inline-block | 600x260 | 1.97 (2.49) | 1.26 (1.68) | 0.95 (1.17) | 0.48 | 0.64 |
| layout2-ib-valign | inline-block | 600x220 | 3.29 (3.83) | 1.55 (2.21) | 2.42 (3.62) | 0.74 | 0.47 |
| layout2-ib-json | inline-block | 600x160 | 1.27 (2.00) | 0.81 (1.13) | 0.48 (0.62) | 0.38 | 0.64 |
| layout2-grid-areas | grid-areas | 600x360 | 2.21 (2.52) | 1.43 (1.81) | 1.10 (1.29) | 0.50 | 0.65 |
| layout2-grid-named-lines | grid-areas | 600x300 | 2.26 (2.67) | 1.43 (1.91) | 0.96 (1.27) | 0.43 | 0.63 |
| layout2-grid-areas-auto | grid-areas | 600x300 | 1.93 (2.51) | 1.25 (1.90) | 0.79 (1.04) | 0.41 | 0.65 |

### Per-feature summary (geometric mean of per-case median ratios)

| feature | cases | takumi-wasm raw ms (geomean) | takumi-wasm png ms (geomean) | bm/wasm raw | bm/wasm png | native/wasm raw | native/wasm png |
| :-- | --: | --: | --: | --: | --: | --: | --: |
| colors | 5 | 1.41 | 3.91 | 0.63 | 0.39 | 0.81 | 0.56 |
| flex | 5 | 1.19 | 4.58 | 0.93 | 0.45 | 1.04 | 0.53 |
| sizing | 5 | 0.90 | 4.49 | 0.95 | 0.47 | 1.18 | 0.53 |
| absolute | 3 | 1.05 | 5.32 | 0.85 | 0.42 | 0.94 | 0.46 |
| borders | 3 | 1.37 | 4.17 | 0.80 | 0.49 | 0.81 | 0.55 |
| border-radius | 4 | 0.85 | 4.10 | 1.18 | 0.45 | 1.11 | 0.51 |
| linear-gradient | 4 | 3.90 | 17.08 | 0.58 | 0.38 | 0.78 | 0.29 |
| radial-gradient | 3 | 4.79 | 24.77 | 0.37 | 0.48 | 0.85 | 0.29 |
| box-shadow | 4 | 5.84 | 15.74 | 0.56 | 0.48 | 0.71 | 0.36 |
| opacity | 4 | 5.23 | 9.06 | 0.43 | 0.38 | 0.54 | 0.44 |
| overflow | 3 | 1.61 | 5.46 | 0.62 | 0.38 | 0.89 | 0.48 |
| transform | 3 | 3.02 | 6.37 | 0.55 | 0.43 | 0.89 | 0.57 |
| text-single-line | 3 | 1.49 | 4.74 | 0.62 | 0.48 | 1.01 | 0.60 |
| text-paragraph | 5 | 2.20 | 6.88 | 0.65 | 0.52 | 0.92 | 0.52 |
| fonts | 2 | 2.71 | 8.82 | 0.63 | 0.53 | 0.94 | 0.50 |
| text-i18n | 2 | 2.34 | 7.93 | 0.67 | 0.51 | 0.99 | 0.49 |
| text-truncation | 3 | 1.50 | 4.16 | 0.60 | 0.43 | 0.90 | 0.57 |
| images | 5 | 4.66 | 28.56 | 0.38 | 0.60 | 0.77 | 0.28 |
| grid | 4 | 1.61 | 5.54 | 0.78 | 0.41 | 0.99 | 0.52 |
| og-card | 2 | 4.24 | 13.41 | 0.57 | 0.69 | 0.78 | 0.40 |
| blog-card | 2 | 10.51 | 31.14 | 0.65 | 0.53 | 0.60 | 0.31 |
| stress | 3 | 16.11 | 36.71 | 0.73 | 0.65 | 0.87 | 0.49 |
| text-shadow | 1 | 1.00 | 4.35 | 1.01 | 0.91 | 0.73 | 0.43 |
| known-gaps | 9 | 0.57 | 2.03 | 0.56 | 0.40 | 0.75 | 0.52 |
| filter | 1 | 1.77 | 4.89 | 0.74 | 0.63 | 0.67 | 0.39 |
| aa-exact | 2 | 0.61 | 1.57 | 0.61 | 0.54 | 0.76 | 0.64 |
| dashed-border | 1 | 2.40 | 3.35 | 0.56 | 0.50 | 0.58 | 0.54 |
| dotted-border | 1 | 2.82 | 3.65 | 0.53 | 0.50 | 0.56 | 0.56 |
| double-3d-border | 1 | 0.60 | 1.40 | 0.81 | 0.50 | 0.76 | 0.60 |
| mixed-border | 1 | 1.07 | 1.94 | 0.66 | 0.54 | 0.58 | 0.59 |
| outline | 1 | 1.53 | 2.64 | 0.54 | 0.45 | 0.60 | 0.59 |
| clip-path | 1 | 0.87 | 5.44 | 0.72 | 0.36 | 0.67 | 0.28 |
| mask | 1 | 1.57 | 6.32 | 0.71 | 0.36 | 0.66 | 0.28 |
| bg-clip-text | 1 | 2.63 | 5.36 | 0.17 | 0.40 | 0.69 | 0.49 |
| mix-blend | 1 | 1.80 | 7.64 | 0.69 | 0.54 | 0.57 | 0.27 |
| bg-blend | 1 | 4.92 | 10.58 | 0.20 | 0.41 | 0.80 | 0.46 |
| drop-shadow | 1 | 1.53 | 7.06 | 0.79 | 0.49 | 0.71 | 0.27 |
| backdrop-filter | 1 | 4.42 | 7.36 | 0.63 | 0.56 | 0.55 | 0.44 |
| text-stroke | 1 | 0.74 | 2.11 | 1.58 | 0.90 | 0.79 | 0.67 |
| text-decoration | 1 | 1.68 | 3.71 | 1.07 | 0.77 | 0.77 | 0.57 |
| visibility | 1 | 0.30 | 1.20 | 0.62 | 0.43 | 0.92 | 0.64 |
| svg-image | 1 | 0.77 | 2.21 | 1.55 | 0.82 | 0.63 | 0.56 |
| inline-box | 1 | 2.67 | 5.34 | 0.69 | 0.69 | 0.71 | 0.56 |
| css-stylesheet | 4 | 1.35 | 4.78 | 0.78 | 0.37 | 1.10 | 0.58 |
| tailwind | 4 | 1.59 | 5.17 | 0.85 | 0.41 | 1.14 | 0.60 |
| html | 4 | 1.55 | 4.68 | 0.63 | 0.48 | 0.98 | 0.58 |
| pseudo-elements | 4 | 0.78 | 2.41 | 0.64 | 0.40 | 0.97 | 0.55 |
| animation | 42 | 0.25 | 0.75 | 0.64 | 0.49 | 0.86 | 0.64 |
| table | 8 | 1.17 | 2.54 | 0.60 | 0.50 | 0.79 | 0.63 |
| float | 4 | 0.55 | 2.44 | 0.73 | 0.44 | 0.81 | 0.50 |
| inline-block | 4 | 0.55 | 1.80 | 0.62 | 0.50 | 0.82 | 0.59 |
| grid-areas | 3 | 0.71 | 2.13 | 0.75 | 0.44 | 0.88 | 0.64 |

Overall geomean bm / takumi-wasm: raw **0.65**, png **0.47**.

### Encoders: jpeg (q85) and webp (default/lossless) — median ms (p95) and encoded bytes

| case | format | takumi-wasm | takumi-native | bm |
| :-- | :-- | --: | --: | --: |
| lingrad-angles | png | 35.52 (36.32) · 101.9 KiB | 8.29 (10.29) · 101.9 KiB | 10.22 (11.03) · 32.6 KiB |
| lingrad-angles | jpeg | 24.71 (26.27) · 52.3 KiB | 18.44 (19.16) · 52.3 KiB | 18.78 (19.71) · 52.2 KiB |
| lingrad-angles | webp | 15.56 (19.07) · 169.4 KiB | 114.03 (117.46) · 22.8 KiB | 10.63 (11.54) · 28.9 KiB |
| img-photo-bg | png | 54.53 (55.07) · 512.7 KiB | 12.82 (15.16) · 512.7 KiB | 41.79 (43.90) · 510.9 KiB |
| img-photo-bg | jpeg | 24.68 (25.56) · 55.2 KiB | 18.57 (20.16) · 55.2 KiB | 17.53 (18.11) · 55.1 KiB |
| img-photo-bg | webp | 21.26 (22.30) · 470.3 KiB | 173.75 (179.07) · 413.8 KiB | 19.86 (21.19) · 366.9 KiB |
| card-flat-ui | png | 19.86 (20.64) · 25.3 KiB | 7.20 (8.24) · 25.3 KiB | 8.95 (9.62) · 23.1 KiB |
| card-flat-ui | jpeg | 25.05 (26.33) · 49.0 KiB | 18.16 (18.55) · 49.0 KiB | 20.00 (21.58) · 48.9 KiB |
| card-flat-ui | webp | 12.60 (13.60) · 27.6 KiB | 17.77 (19.06) · 13.4 KiB | 9.62 (10.40) · 18.5 KiB |

## Errors

None.

