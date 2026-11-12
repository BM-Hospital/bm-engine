# bm-engine vs takumi — benchmark & equivalence results

- Date: 2026-11-11T23:59:23.163Z  |  Node v26.13.0  |  win32 10.0.26200 x64
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
| bm | binary (zig-out/bin/bm_engine.wasm) | 1099.8 KiB | 538.2 KiB | 453.4 KiB |
| bm | JS glue (js/engine.mjs + js/index.mjs + js/node.mjs) | 29.2 KiB | 9.5 KiB | 8.3 KiB |

## Cold start (fresh `node` process, median of runs)

| engine | runs | wasm compile+instantiate (native: addon load) ms | register Inter-Regular ms | first render (og-card, png) ms | total ms |
| :-- | --: | --: | --: | --: | --: |
| takumi-wasm | 7 | 33.01 | 3.55 | 141.43 | 178.38 |
| takumi-native | 7 | 21.83 | 1.61 | 20.15 | 43.77 |
| bm | 7 | 5.11 | 2.69 | 63.11 | 70.77 |

## Memory (child process: all fonts, 50 og-card PNG renders)

| engine | peak RSS (maxRSS) | wasm linear memory after init+fonts | wasm linear memory after 50 renders |
| :-- | --: | --: | --: |
| takumi-wasm | 107.9 MiB | 6.3 MiB | 10.6 MiB |
| takumi-native | 82.1 MiB | – | – |
| bm | 89.1 MiB | 6.4 MiB | 11.6 MiB |

Bare `node` baseline peak RSS: 44.6 MiB.

Wasm linear memory at end of the full case run (largest instance): takumi-wasm 66.4 MiB, bm 69.9 MiB.

## Output equivalence (reference = takumi-wasm, `format: raw`)

Verdict rules: **identical** = 0 differing bytes; **equivalent** = SSIM >= 0.99 and <= 0.5% pixels differing (pixelmatch thr 0.1, includeAA=true); **close** = SSIM >= 0.95 and <= 5% pixels differing; else **different**. `error/unsupported` when an engine threw. SSIM = mean over uniform 8x8 windows (stride 1) of luma over white; `SSIM RGB` = mean of per-channel SSIMs (catches chroma-only changes). Verdicts use min(luma, RGB). `px strict/AA` = pixelmatch count with includeAA true / false. `native` rows are the noise-floor baseline (same Rust code, different build).

### Verdict summary

| candidate | identical | equivalent | close | different | error/unsupported |
| :-- | --: | --: | --: | --: | --: |
| bm | 74 | 126 | 0 | 0 | 0 |
| takumi-native | 200 | 0 | 0 | 0 | 0 |

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
| layout2-float-wrap | float | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.007 | 30 | 58.0 |
| layout2-ib-badges | inline-block | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 15 | 65.7 |
| layout2-ib-wrap | inline-block | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 15 | 62.0 |
| layout2-ib-valign | inline-block | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 16 | 63.0 |
| layout2-ib-json | inline-block | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.003 | 32 | 61.6 |
| layout2-grid-areas | grid-areas | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 69.9 |
| layout2-grid-named-lines | grid-areas | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 67.9 |
| layout2-grid-areas-auto | grid-areas | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 9 | 80.5 |
| layout3-float-left | float-text | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.008 | 30 | 57.6 |
| layout3-float-right | float-text | equivalent | 0.9999 | 0.9999 | 0.033 | 0.008 | 45 / 11 | 0.021 | 61 | 49.3 |
| layout3-float-stacked | float-text | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 2 / 0 | 0.011 | 31 | 56.1 |
| layout3-float-tall | float-text | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.012 | 30 | 55.9 |
| layout3-float-in-text | float-text | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.010 | 16 | 56.4 |
| layout3-float-rtl | float-text | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.015 | 16 | 54.7 |
| layout3-float-inline-box | float-text | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.007 | 31 | 58.3 |
| layout3-inline-badges | inline-flow | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.008 | 31 | 57.5 |
| layout3-inline-image | inline-flow | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 2 / 0 | 0.006 | 31 | 58.8 |
| layout3-inline-flex-chip | inline-flow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.006 | 16 | 59.2 |
| layout3-inline-br | inline-flow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.004 | 24 | 60.4 |
| layout3-inline-abs | inline-flow | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.007 | 30 | 58.1 |
| layout3-span-edges | inline-box-model | equivalent | 1.0000 | 1.0000 | 0.001 | 0.000 | 1 / 0 | 0.008 | 30 | 57.9 |
| layout3-span-nowrap | inline-box-model | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.009 | 16 | 57.1 |
| layout3-span-valign | inline-box-model | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.008 | 16 | 57.7 |
| layout3-card-all | inline-box-model | equivalent | 1.0000 | 1.0000 | 0.002 | 0.000 | 5 / 0 | 0.010 | 28 | 56.7 |

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
| layout3-float-left | float-text | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-float-right | float-text | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-float-stacked | float-text | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-float-tall | float-text | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-float-in-text | float-text | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-float-rtl | float-text | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-float-inline-box | float-text | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-inline-badges | inline-flow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-inline-image | inline-flow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-inline-flex-chip | inline-flow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-inline-br | inline-flow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-inline-abs | inline-flow | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-span-edges | inline-box-model | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-span-nowrap | inline-box-model | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-span-valign | inline-box-model | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| layout3-card-all | inline-box-model | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |

Noise floor (native vs wasm): 200/200 identical; lowest SSIM 1.00000 on `colors-solid-bg`.

## Performance

### `format: raw` — median ms (p95)

| case | feature | size | takumi-wasm | takumi-native | bm | bm / takumi-wasm | native / wasm |
| :-- | :-- | --: | --: | --: | --: | --: | --: |
| colors-solid-bg | colors | 400x300 | 0.30 (0.63) | 0.29 (0.57) | 0.23 (0.43) | 0.76 | 0.96 |
| colors-hex | colors | 1200x630 | 3.31 (5.97) | 2.38 (4.14) | 1.90 (2.89) | 0.57 | 0.72 |
| colors-functional | colors | 1200x630 | 2.85 (4.97) | 2.21 (4.07) | 1.68 (2.77) | 0.59 | 0.78 |
| colors-named | colors | 1200x630 | 2.51 (4.03) | 2.42 (3.87) | 1.92 (3.03) | 0.76 | 0.96 |
| colors-transparent-canvas | colors | 400x300 | 0.60 (0.94) | 0.47 (0.87) | 0.40 (0.54) | 0.67 | 0.79 |
| flex-row-column | flex | 1200x630 | 1.28 (2.45) | 1.38 (3.29) | 1.47 (2.46) | 1.15 | 1.08 |
| flex-justify-align | flex | 1200x630 | 1.74 (3.33) | 1.73 (3.39) | 1.64 (2.47) | 0.94 | 1.00 |
| flex-wrap-gap | flex | 1200x630 | 1.63 (3.11) | 1.71 (3.48) | 2.02 (3.33) | 1.24 | 1.05 |
| flex-grow-shrink-basis | flex | 1200x630 | 1.24 (2.91) | 1.54 (3.67) | 1.20 (2.20) | 0.97 | 1.24 |
| flex-nested-small | flex | 400x300 | 0.28 (0.45) | 0.30 (0.64) | 0.22 (0.42) | 0.82 | 1.09 |
| sizing-percent | sizing | 1200x630 | 1.27 (2.73) | 1.42 (3.10) | 1.12 (1.81) | 0.88 | 1.12 |
| sizing-minmax | sizing | 1200x630 | 1.03 (1.99) | 1.25 (3.29) | 1.01 (1.54) | 0.98 | 1.22 |
| sizing-aspect-ratio | sizing | 1200x630 | 1.15 (2.12) | 1.30 (2.89) | 1.30 (2.37) | 1.13 | 1.14 |
| sizing-padding-margin | sizing | 1200x630 | 1.19 (2.21) | 1.36 (3.17) | 1.17 (2.47) | 0.99 | 1.14 |
| sizing-auto-margin-center | sizing | 400x300 | 0.18 (0.35) | 0.25 (0.52) | 0.16 (0.28) | 0.92 | 1.39 |
| abs-inset | absolute | 1200x630 | 1.95 (3.25) | 1.66 (3.46) | 1.35 (2.29) | 0.69 | 0.85 |
| abs-zorder | absolute | 1200x630 | 1.51 (3.38) | 1.53 (3.33) | 2.06 (3.61) | 1.37 | 1.01 |
| abs-in-flow | absolute | 400x300 | 0.36 (0.70) | 0.27 (0.57) | 0.24 (0.43) | 0.67 | 0.74 |
| borders-uniform | borders | 1200x630 | 1.51 (3.28) | 1.61 (3.51) | 1.10 (2.46) | 0.73 | 1.06 |
| borders-per-side | borders | 1200x630 | 1.36 (2.34) | 1.55 (3.10) | 1.19 (2.62) | 0.88 | 1.14 |
| borders-with-radius | borders | 400x300 | 0.80 (1.08) | 0.45 (0.83) | 0.74 (1.37) | 0.93 | 0.57 |
| radius-uniform-percorner | border-radius | 1200x630 | 1.23 (2.77) | 1.50 (3.04) | 1.51 (2.71) | 1.22 | 1.22 |
| radius-elliptical | border-radius | 1200x630 | 1.21 (2.81) | 1.37 (3.02) | 1.49 (2.20) | 1.23 | 1.13 |
| radius-pill-circle | border-radius | 1200x630 | 1.13 (2.75) | 1.32 (3.05) | 1.38 (2.76) | 1.22 | 1.17 |
| radius-small | border-radius | 400x300 | 0.21 (0.44) | 0.19 (0.44) | 0.24 (0.37) | 1.14 | 0.87 |
| lingrad-angles | linear-gradient | 1200x630 | 6.28 (7.78) | 4.77 (6.64) | 3.60 (5.19) | 0.57 | 0.76 |
| lingrad-multistop | linear-gradient | 1200x630 | 6.20 (7.77) | 5.39 (6.64) | 3.27 (4.59) | 0.53 | 0.87 |
| lingrad-alpha | linear-gradient | 1200x630 | 7.24 (8.01) | 5.29 (6.79) | 4.95 (6.04) | 0.68 | 0.73 |
| lingrad-hero-small | linear-gradient | 400x300 | 0.71 (1.00) | 0.54 (0.99) | 0.45 (0.76) | 0.64 | 0.77 |
| radial-shapes | radial-gradient | 1200x630 | 7.73 (8.57) | 6.65 (7.97) | 3.02 (5.13) | 0.39 | 0.86 |
| radial-at-position | radial-gradient | 1200x630 | 9.53 (10.39) | 7.72 (9.53) | 3.66 (4.46) | 0.38 | 0.81 |
| radial-spotlight-small | radial-gradient | 400x300 | 1.33 (1.70) | 1.19 (1.59) | 0.42 (0.64) | 0.32 | 0.89 |
| shadow-offset-blur | box-shadow | 1200x630 | 8.47 (9.72) | 6.18 (7.89) | 4.99 (5.63) | 0.59 | 0.73 |
| shadow-spread-multi | box-shadow | 1200x630 | 8.74 (9.57) | 5.84 (7.73) | 5.21 (6.68) | 0.60 | 0.67 |
| shadow-inset | box-shadow | 1200x630 | 11.50 (12.86) | 8.18 (9.27) | 5.55 (6.38) | 0.48 | 0.71 |
| shadow-small | box-shadow | 400x300 | 1.32 (1.63) | 0.83 (1.25) | 0.72 (0.99) | 0.54 | 0.63 |
| opacity-basic | opacity | 1200x630 | 6.86 (9.03) | 4.20 (6.06) | 3.48 (4.71) | 0.51 | 0.61 |
| opacity-nested | opacity | 1200x630 | 9.70 (10.63) | 4.82 (6.32) | 2.29 (3.75) | 0.24 | 0.50 |
| opacity-with-radius-shadow | opacity | 400x300 | 3.56 (3.89) | 1.81 (2.41) | 1.29 (1.71) | 0.36 | 0.51 |
| overflow-hidden-clip | overflow | 1200x630 | 2.15 (3.67) | 2.09 (4.44) | 1.25 (2.16) | 0.58 | 0.97 |
| overflow-radius-clip | overflow | 1200x630 | 3.45 (5.04) | 3.40 (5.39) | 2.13 (3.27) | 0.62 | 0.99 |
| overflow-nested | overflow | 400x300 | 0.42 (0.72) | 0.33 (0.64) | 0.33 (0.58) | 0.79 | 0.78 |
| transform-basic | transform | 1200x630 | 4.00 (5.32) | 3.16 (5.00) | 1.81 (3.14) | 0.45 | 0.79 |
| transform-combined-origin | transform | 1200x630 | 3.49 (5.46) | 2.77 (4.85) | 1.73 (3.10) | 0.49 | 0.79 |
| transform-text-small | transform | 400x300 | 1.50 (2.06) | 0.94 (1.54) | 0.86 (1.18) | 0.57 | 0.63 |
| text-single-sizes | text-single-line | 1200x630 | 2.11 (2.95) | 2.25 (4.71) | 1.44 (2.87) | 0.68 | 1.06 |
| text-single-colors-small | text-single-line | 400x300 | 0.55 (0.82) | 0.43 (0.85) | 0.26 (0.41) | 0.48 | 0.79 |
| text-single-fonts | text-single-line | 1200x630 | 1.84 (3.30) | 1.98 (4.44) | 1.31 (2.50) | 0.71 | 1.08 |
| text-paragraph-wrap | text-paragraph | 1200x630 | 2.90 (4.57) | 2.76 (4.99) | 1.88 (2.63) | 0.65 | 0.95 |
| text-paragraph-lineheight | text-paragraph | 1200x630 | 3.46 (5.26) | 3.02 (5.14) | 2.21 (3.24) | 0.64 | 0.87 |
| text-paragraph-letterspacing | text-paragraph | 1200x630 | 3.54 (5.02) | 3.06 (4.88) | 2.19 (3.36) | 0.62 | 0.87 |
| text-paragraph-small | text-paragraph | 400x300 | 0.55 (0.89) | 0.49 (0.98) | 0.35 (0.58) | 0.64 | 0.90 |
| text-long-wrap | text-paragraph | 1200x630 | 1.94 (3.39) | 1.85 (4.53) | 1.49 (2.61) | 0.77 | 0.96 |
| fonts-weights-italic | fonts | 1200x630 | 2.80 (4.49) | 2.50 (4.64) | 1.66 (2.77) | 0.59 | 0.89 |
| fonts-mixed-inline | fonts | 1200x630 | 2.51 (4.02) | 2.13 (4.34) | 1.37 (2.63) | 0.55 | 0.85 |
| text-vietnamese | text-i18n | 1200x630 | 2.21 (4.46) | 2.02 (4.39) | 1.36 (2.41) | 0.61 | 0.92 |
| text-accented-latin | text-i18n | 1200x630 | 2.63 (4.22) | 2.49 (4.96) | 1.76 (3.76) | 0.67 | 0.95 |
| text-ellipsis-nowrap | text-truncation | 1200x630 | 2.08 (3.66) | 2.03 (4.52) | 1.46 (2.83) | 0.70 | 0.98 |
| text-lineclamp | text-truncation | 1200x630 | 3.00 (4.40) | 2.76 (5.02) | 2.02 (3.20) | 0.67 | 0.92 |
| text-lineclamp-small | text-truncation | 400x300 | 0.53 (0.76) | 0.39 (0.74) | 0.28 (0.45) | 0.52 | 0.73 |
| img-png-fit | images | 1200x630 | 6.00 (8.05) | 4.91 (6.56) | 2.45 (3.65) | 0.41 | 0.82 |
| img-jpeg-fit | images | 1200x630 | 19.22 (23.53) | 12.95 (14.33) | 2.40 (4.12) | 0.13 | 0.67 |
| img-intrinsic-size | images | 400x300 | 0.40 (0.71) | 0.30 (0.61) | 0.34 (0.59) | 0.85 | 0.75 |
| img-radius-clip | images | 1200x630 | 7.24 (8.62) | 5.70 (7.20) | 4.45 (5.60) | 0.62 | 0.79 |
| img-photo-bg | images | 1200x630 | 5.98 (7.34) | 4.47 (6.51) | 1.61 (2.75) | 0.27 | 0.75 |
| grid-fixed-fr | grid | 1200x630 | 1.74 (3.13) | 2.08 (4.61) | 1.62 (3.10) | 0.93 | 1.20 |
| grid-repeat-gap | grid | 1200x630 | 2.13 (3.51) | 2.02 (4.69) | 1.82 (2.78) | 0.86 | 0.95 |
| grid-spans | grid | 1200x630 | 1.78 (3.62) | 1.95 (4.45) | 1.47 (2.53) | 0.83 | 1.10 |
| grid-small-mixed | grid | 400x300 | 0.66 (0.99) | 0.51 (1.00) | 0.46 (0.71) | 0.69 | 0.76 |
| card-og | og-card | 1200x630 | 5.67 (6.91) | 5.00 (6.66) | 3.57 (5.12) | 0.63 | 0.88 |
| card-og-small | og-card | 600x315 | 2.59 (3.48) | 1.87 (2.45) | 1.47 (2.25) | 0.57 | 0.72 |
| card-blog | blog-card | 1200x630 | 15.90 (18.39) | 8.30 (9.75) | 10.06 (11.27) | 0.63 | 0.52 |
| card-flat-ui | blog-card | 1200x630 | 6.60 (7.91) | 4.74 (6.72) | 4.33 (6.27) | 0.66 | 0.72 |
| stress-600-boxes | stress | 1200x630 | 8.76 (11.00) | 7.78 (10.23) | 8.29 (9.85) | 0.95 | 0.89 |
| stress-200-labels | stress | 1200x630 | 15.01 (16.50) | 12.42 (15.53) | 9.52 (11.36) | 0.63 | 0.83 |
| stress-3000x2000-card | stress | 3000x2000 | 32.61 (36.03) | 25.77 (26.53) | 21.31 (25.38) | 0.65 | 0.79 |
| fx-text-shadow | text-shadow | 600x200 | 0.94 (1.34) | 0.66 (1.14) | 1.00 (1.22) | 1.07 | 0.71 |
| gap-dashed-dotted-border | known-gaps | 600x200 | 1.71 (2.18) | 1.07 (1.44) | 0.92 (1.16) | 0.54 | 0.63 |
| fx-filter-blur-grayscale | filter | 600x200 | 1.66 (2.14) | 1.07 (1.58) | 1.27 (1.75) | 0.77 | 0.64 |
| gap-tailwind-tw | known-gaps | 600x200 | 0.32 (0.56) | 0.29 (0.64) | 0.27 (0.46) | 0.86 | 0.90 |
| gap-oklch-color | known-gaps | 600x200 | 0.17 (0.30) | 0.24 (0.63) | 0.15 (0.24) | 0.91 | 1.41 |
| gap-svg-image | known-gaps | 600x200 | 0.29 (0.54) | 0.23 (0.53) | 0.23 (0.37) | 0.80 | 0.80 |
| gap-inline-box-decoration | known-gaps | 600x200 | 0.48 (0.81) | 0.39 (0.75) | 0.27 (0.44) | 0.56 | 0.80 |
| gap-mix-blend-mode | known-gaps | 600x200 | 0.71 (0.99) | 0.41 (0.81) | 0.38 (0.52) | 0.54 | 0.57 |
| gap-clip-path | known-gaps | 600x200 | 0.62 (0.99) | 0.42 (0.78) | 0.50 (0.81) | 0.80 | 0.68 |
| gap-background-clip-text | known-gaps | 600x200 | 1.85 (2.29) | 1.19 (1.88) | 0.32 (0.58) | 0.17 | 0.64 |
| gap-text-wrap-balance | known-gaps | 600x200 | 0.44 (0.77) | 0.33 (0.65) | 0.23 (0.36) | 0.53 | 0.76 |
| pfx-aa-shapes | aa-exact | 600x200 | 0.53 (0.83) | 0.35 (0.72) | 0.42 (0.67) | 0.79 | 0.66 |
| pfx-aa-text | aa-exact | 600x200 | 0.63 (0.96) | 0.52 (0.99) | 0.33 (0.49) | 0.52 | 0.83 |
| pfx-border-dashed | dashed-border | 600x200 | 2.35 (3.14) | 1.26 (1.89) | 1.32 (1.77) | 0.56 | 0.54 |
| pfx-border-dotted | dotted-border | 600x200 | 2.77 (3.31) | 1.56 (2.23) | 1.45 (2.07) | 0.53 | 0.56 |
| pfx-border-double-3d | double-3d-border | 600x200 | 0.57 (0.85) | 0.42 (0.85) | 0.48 (0.71) | 0.84 | 0.74 |
| pfx-border-mixed | mixed-border | 600x200 | 1.04 (1.48) | 0.58 (0.97) | 0.70 (1.00) | 0.67 | 0.56 |
| pfx-outline | outline | 600x200 | 1.48 (1.90) | 0.89 (1.42) | 0.82 (1.02) | 0.55 | 0.60 |
| pfx-clip-path-shapes | clip-path | 600x200 | 0.84 (1.19) | 0.52 (0.94) | 0.60 (0.84) | 0.72 | 0.62 |
| pfx-mask-gradient | mask | 600x200 | 1.52 (1.87) | 1.05 (1.63) | 1.16 (1.74) | 0.76 | 0.69 |
| pfx-bg-clip-text | bg-clip-text | 600x200 | 2.50 (3.01) | 1.63 (2.18) | 0.43 (0.65) | 0.17 | 0.65 |
| pfx-mix-blend | mix-blend | 600x200 | 1.72 (2.25) | 0.99 (1.56) | 1.19 (1.41) | 0.69 | 0.58 |
| pfx-bg-blend | bg-blend | 600x200 | 4.84 (5.69) | 3.68 (4.35) | 0.95 (1.33) | 0.20 | 0.76 |
| pfx-drop-shadow | drop-shadow | 600x200 | 1.44 (1.99) | 0.91 (1.31) | 1.13 (1.47) | 0.78 | 0.63 |
| pfx-backdrop-filter | backdrop-filter | 600x200 | 4.41 (6.47) | 2.46 (3.05) | 2.77 (3.76) | 0.63 | 0.56 |
| pfx-text-stroke | text-stroke | 600x200 | 0.73 (1.09) | 0.55 (1.00) | 1.18 (1.49) | 1.61 | 0.75 |
| pfx-text-decoration | text-decoration | 600x260 | 1.55 (1.97) | 1.07 (1.81) | 1.70 (1.97) | 1.10 | 0.69 |
| pfx-visibility | visibility | 600x200 | 0.28 (0.50) | 0.26 (0.58) | 0.19 (0.31) | 0.67 | 0.92 |
| pfx-opacity-layers | opacity | 600x200 | 3.00 (3.53) | 1.73 (2.20) | 2.12 (2.56) | 0.71 | 0.58 |
| pfx-svg-background | svg-image | 600x200 | 0.82 (1.46) | 0.46 (0.89) | 1.20 (1.64) | 1.46 | 0.56 |
| pfx-inline-boxes-many | inline-box | 600x300 | 2.65 (3.39) | 1.73 (2.27) | 1.87 (2.62) | 0.70 | 0.65 |
| css-class-id | css-stylesheet | 1200x630 | 2.26 (3.89) | 2.23 (4.79) | 1.75 (3.05) | 0.77 | 0.98 |
| css-nth-child | css-stylesheet | 800x500 | 1.57 (2.47) | 1.56 (3.05) | 1.11 (1.84) | 0.71 | 0.99 |
| css-media-layer | css-stylesheet | 1200x400 | 0.73 (1.59) | 1.26 (2.46) | 0.85 (1.53) | 1.16 | 1.72 |
| css-important-var | css-stylesheet | 900x400 | 0.89 (1.74) | 0.90 (2.75) | 0.67 (1.36) | 0.75 | 1.01 |
| tw-card | tailwind | 1200x630 | 1.95 (3.65) | 2.16 (4.69) | 1.55 (2.23) | 0.80 | 1.11 |
| tw-responsive | tailwind | 1200x400 | 0.65 (1.37) | 1.27 (2.32) | 0.77 (1.21) | 1.17 | 1.95 |
| tw-structural | tailwind | 800x500 | 0.69 (1.30) | 0.92 (2.77) | 0.87 (1.42) | 1.25 | 1.33 |
| tw-arbitrary | tailwind | 900x450 | 4.99 (6.08) | 3.47 (5.41) | 2.61 (3.56) | 0.52 | 0.69 |
| html-article | html | 1000x600 | 1.57 (2.74) | 1.53 (3.76) | 1.17 (2.03) | 0.75 | 0.98 |
| html-document | html | 800x400 | 0.70 (1.10) | 0.76 (2.82) | 0.55 (0.89) | 0.79 | 1.09 |
| html-flex-card | html | 1000x500 | 3.42 (4.09) | 2.58 (4.60) | 1.91 (2.84) | 0.56 | 0.75 |
| html-inline | html | 900x300 | 0.94 (1.41) | 0.92 (2.27) | 0.64 (1.04) | 0.68 | 0.98 |
| pseudo-inline | pseudo-elements | 800x300 | 0.72 (1.25) | 0.73 (1.46) | 0.41 (0.68) | 0.56 | 1.01 |
| pseudo-block | pseudo-elements | 800x400 | 0.92 (1.67) | 0.97 (2.90) | 0.71 (1.13) | 0.77 | 1.06 |
| pseudo-attr | pseudo-elements | 800x250 | 0.61 (1.05) | 0.56 (1.15) | 0.36 (0.57) | 0.59 | 0.91 |
| pseudo-tw | pseudo-elements | 800x300 | 0.59 (1.07) | 0.68 (1.30) | 0.50 (0.81) | 0.85 | 1.15 |
| anim-opacity-t0 | animation | 400x200 | 0.14 (0.25) | 0.15 (0.36) | 0.13 (0.20) | 0.88 | 1.02 |
| anim-opacity-t250 | animation | 400x200 | 0.29 (0.51) | 0.20 (0.40) | 0.14 (0.22) | 0.47 | 0.67 |
| anim-opacity-t500 | animation | 400x200 | 0.30 (0.52) | 0.20 (0.42) | 0.14 (0.22) | 0.47 | 0.68 |
| anim-opacity-t900 | animation | 400x200 | 0.34 (0.53) | 0.20 (0.47) | 0.14 (0.24) | 0.42 | 0.59 |
| anim-opacity-t1500 | animation | 400x200 | 0.15 (0.31) | 0.14 (0.33) | 0.11 (0.18) | 0.76 | 0.95 |
| anim-transform-t0 | animation | 400x200 | 0.15 (0.27) | 0.15 (0.35) | 0.16 (0.24) | 1.00 | 0.99 |
| anim-transform-t200 | animation | 400x200 | 0.16 (0.29) | 0.16 (0.37) | 0.16 (0.25) | 0.96 | 0.98 |
| anim-transform-t400 | animation | 400x200 | 0.17 (0.29) | 0.17 (0.45) | 0.16 (0.33) | 0.96 | 1.00 |
| anim-transform-t600 | animation | 400x200 | 0.17 (0.34) | 0.17 (0.47) | 0.16 (0.26) | 0.91 | 0.97 |
| anim-transform-t800 | animation | 400x200 | 0.15 (0.27) | 0.15 (0.36) | 0.14 (0.24) | 0.96 | 1.00 |
| anim-color-t0 | animation | 400x200 | 0.29 (0.47) | 0.25 (0.51) | 0.17 (0.25) | 0.58 | 0.86 |
| anim-color-t300 | animation | 400x200 | 0.28 (0.48) | 0.24 (0.49) | 0.16 (0.27) | 0.58 | 0.86 |
| anim-color-t700 | animation | 400x200 | 0.29 (0.51) | 0.25 (0.54) | 0.16 (0.26) | 0.57 | 0.87 |
| anim-color-t2000 | animation | 400x200 | 0.29 (0.55) | 0.27 (0.55) | 0.16 (0.25) | 0.57 | 0.92 |
| anim-width-t0 | animation | 400x200 | 0.16 (0.29) | 0.15 (0.38) | 0.13 (0.22) | 0.85 | 0.98 |
| anim-width-t100 | animation | 400x200 | 0.17 (0.29) | 0.16 (0.34) | 0.17 (0.26) | 1.05 | 0.96 |
| anim-width-t500 | animation | 400x200 | 0.19 (0.33) | 0.17 (0.44) | 0.22 (0.38) | 1.16 | 0.93 |
| anim-width-t999 | animation | 400x200 | 0.18 (0.31) | 0.17 (0.37) | 0.21 (0.30) | 1.17 | 0.93 |
| anim-delay-fill-t0 | animation | 400x200 | 0.32 (0.51) | 0.23 (0.52) | 0.18 (0.28) | 0.57 | 0.72 |
| anim-delay-fill-t750 | animation | 400x200 | 0.43 (0.64) | 0.27 (0.54) | 0.21 (0.28) | 0.49 | 0.62 |
| anim-delay-fill-t2000 | animation | 400x200 | 0.19 (0.32) | 0.17 (0.39) | 0.16 (0.25) | 0.87 | 0.92 |
| anim-alternate-t100 | animation | 400x200 | 0.30 (0.46) | 0.22 (0.46) | 0.13 (0.21) | 0.45 | 0.75 |
| anim-alternate-t500 | animation | 400x200 | 0.30 (0.48) | 0.23 (0.47) | 0.14 (0.22) | 0.47 | 0.76 |
| anim-alternate-t700 | animation | 400x200 | 0.30 (0.47) | 0.23 (0.48) | 0.14 (0.21) | 0.45 | 0.77 |
| anim-alternate-t1100 | animation | 400x200 | 0.30 (0.49) | 0.23 (0.46) | 0.14 (0.22) | 0.48 | 0.77 |
| anim-alternate-t1300 | animation | 400x200 | 0.15 (0.33) | 0.14 (0.36) | 0.12 (0.21) | 0.85 | 0.98 |
| anim-steps-t0 | animation | 400x200 | 0.16 (0.28) | 0.16 (0.35) | 0.14 (0.24) | 0.89 | 0.99 |
| anim-steps-t260 | animation | 400x200 | 0.16 (0.30) | 0.15 (0.35) | 0.14 (0.22) | 0.90 | 0.99 |
| anim-steps-t500 | animation | 400x200 | 0.16 (0.27) | 0.16 (0.38) | 0.14 (0.20) | 0.89 | 0.99 |
| anim-steps-t990 | animation | 400x200 | 0.16 (0.31) | 0.16 (0.40) | 0.14 (0.26) | 0.86 | 0.96 |
| anim-two-anims-t0 | animation | 400x200 | 0.29 (0.52) | 0.20 (0.40) | 0.16 (0.25) | 0.55 | 0.68 |
| anim-two-anims-t400 | animation | 400x200 | 0.57 (0.84) | 0.34 (0.62) | 0.24 (0.39) | 0.42 | 0.59 |
| anim-two-anims-t600 | animation | 400x200 | 0.62 (0.90) | 0.35 (0.62) | 0.25 (0.35) | 0.39 | 0.56 |
| anim-two-anims-t1200 | animation | 400x200 | 0.36 (0.53) | 0.26 (0.54) | 0.17 (0.26) | 0.48 | 0.73 |
| anim-inherit-t0 | animation | 400x200 | 0.33 (0.52) | 0.29 (0.63) | 0.19 (0.31) | 0.58 | 0.87 |
| anim-inherit-t500 | animation | 400x200 | 0.37 (0.57) | 0.31 (0.62) | 0.20 (0.30) | 0.54 | 0.83 |
| anim-inherit-t1000 | animation | 400x200 | 0.41 (0.66) | 0.32 (0.68) | 0.21 (0.35) | 0.52 | 0.80 |
| anim-tw-spin-t125 | animation | 400x200 | 0.31 (0.48) | 0.24 (0.49) | 0.15 (0.21) | 0.48 | 0.77 |
| anim-tw-spin-t375 | animation | 400x200 | 0.31 (0.52) | 0.23 (0.49) | 0.15 (0.23) | 0.49 | 0.76 |
| anim-tw-spin-t1600 | animation | 400x200 | 0.31 (0.48) | 0.23 (0.47) | 0.15 (0.23) | 0.48 | 0.76 |
| anim-kf-option-t0 | animation | 400x200 | 0.21 (0.42) | 0.20 (0.52) | 0.22 (0.39) | 1.05 | 0.95 |
| anim-kf-option-t500 | animation | 400x200 | 0.47 (0.72) | 0.29 (0.56) | 0.20 (0.27) | 0.43 | 0.61 |
| layout2-table-auto | table | 600x300 | 1.14 (1.53) | 0.91 (1.74) | 0.80 (1.15) | 0.70 | 0.80 |
| layout2-table-spans | table | 600x320 | 0.84 (1.19) | 0.63 (1.22) | 0.61 (1.02) | 0.72 | 0.75 |
| layout2-table-fixed | table | 600x260 | 1.06 (1.52) | 0.84 (1.33) | 0.70 (1.08) | 0.66 | 0.79 |
| layout2-table-percent | table | 600x220 | 0.60 (1.00) | 0.48 (0.92) | 0.36 (0.61) | 0.61 | 0.80 |
| layout2-table-collapse-conflicts | table | 600x300 | 1.14 (1.59) | 0.86 (1.49) | 0.74 (1.14) | 0.64 | 0.75 |
| layout2-table-col-backgrounds | table | 600x260 | 1.76 (2.21) | 1.26 (1.89) | 0.94 (1.21) | 0.54 | 0.71 |
| layout2-table-empty-cells | table | 600x240 | 1.05 (1.46) | 0.78 (1.30) | 0.60 (0.93) | 0.57 | 0.75 |
| layout2-table-caption-bottom | table | 600x300 | 1.36 (1.91) | 1.00 (1.56) | 0.88 (1.34) | 0.65 | 0.74 |
| layout2-float-image | float | 600x240 | 0.66 (1.02) | 0.52 (1.03) | 0.57 (0.86) | 0.87 | 0.80 |
| layout2-float-clear | float | 600x260 | 0.35 (0.62) | 0.29 (0.69) | 0.27 (0.47) | 0.78 | 0.83 |
| layout2-float-bfc | float | 600x260 | 0.53 (0.87) | 0.40 (0.95) | 0.30 (0.50) | 0.58 | 0.75 |
| layout2-float-wrap | float | 600x260 | 0.60 (1.04) | 0.46 (0.93) | 0.43 (0.69) | 0.72 | 0.76 |
| layout2-ib-badges | inline-block | 600x200 | 0.49 (0.76) | 0.40 (0.81) | 0.32 (0.50) | 0.66 | 0.83 |
| layout2-ib-wrap | inline-block | 600x260 | 0.62 (0.93) | 0.49 (1.05) | 0.55 (0.99) | 0.89 | 0.79 |
| layout2-ib-valign | inline-block | 600x220 | 0.51 (0.89) | 0.42 (0.94) | 0.34 (0.55) | 0.66 | 0.83 |
| layout2-ib-json | inline-block | 600x160 | 0.41 (0.73) | 0.38 (0.89) | 0.24 (0.40) | 0.59 | 0.91 |
| layout2-grid-areas | grid-areas | 600x360 | 0.66 (1.14) | 0.52 (0.99) | 0.57 (0.91) | 0.87 | 0.79 |
| layout2-grid-named-lines | grid-areas | 600x300 | 0.65 (1.11) | 0.55 (1.12) | 0.53 (0.86) | 0.80 | 0.84 |
| layout2-grid-areas-auto | grid-areas | 600x300 | 0.55 (0.96) | 0.45 (0.93) | 0.36 (0.63) | 0.65 | 0.82 |
| layout3-float-left | float-text | 520x260 | 0.61 (1.12) | 0.47 (0.96) | 0.46 (0.74) | 0.75 | 0.77 |
| layout3-float-right | float-text | 520x260 | 0.64 (0.97) | 0.47 (0.90) | 0.45 (0.72) | 0.70 | 0.73 |
| layout3-float-stacked | float-text | 560x300 | 0.89 (1.32) | 0.66 (1.23) | 0.71 (1.24) | 0.79 | 0.74 |
| layout3-float-tall | float-text | 560x330 | 1.10 (1.63) | 0.81 (1.46) | 0.78 (1.33) | 0.71 | 0.74 |
| layout3-float-in-text | float-text | 560x300 | 0.87 (1.46) | 0.65 (1.14) | 0.61 (0.93) | 0.70 | 0.74 |
| layout3-float-rtl | float-text | 560x300 | 1.29 (2.11) | 0.86 (1.49) | 0.85 (1.13) | 0.66 | 0.67 |
| layout3-float-inline-box | float-text | 560x280 | 0.68 (1.07) | 0.52 (0.99) | 0.49 (0.74) | 0.72 | 0.77 |
| layout3-inline-badges | inline-flow | 520x260 | 0.95 (1.39) | 0.75 (1.27) | 0.68 (0.86) | 0.71 | 0.79 |
| layout3-inline-image | inline-flow | 560x280 | 0.89 (1.23) | 0.69 (1.32) | 0.73 (1.05) | 0.82 | 0.77 |
| layout3-inline-flex-chip | inline-flow | 560x280 | 1.25 (1.81) | 0.91 (1.48) | 1.01 (1.49) | 0.81 | 0.73 |
| layout3-inline-br | inline-flow | 520x260 | 0.68 (0.88) | 0.54 (1.01) | 0.49 (0.80) | 0.73 | 0.79 |
| layout3-inline-abs | inline-flow | 520x220 | 0.62 (1.03) | 0.48 (0.94) | 0.41 (0.64) | 0.67 | 0.77 |
| layout3-span-edges | inline-box-model | 520x260 | 0.97 (1.48) | 0.72 (1.23) | 0.88 (1.17) | 0.91 | 0.74 |
| layout3-span-nowrap | inline-box-model | 520x240 | 0.90 (1.38) | 0.78 (1.48) | 0.66 (1.14) | 0.73 | 0.86 |
| layout3-span-valign | inline-box-model | 560x280 | 1.25 (1.91) | 0.93 (1.68) | 0.74 (1.06) | 0.59 | 0.75 |
| layout3-card-all | inline-box-model | 640x420 | 3.02 (4.00) | 2.53 (3.89) | 2.21 (3.25) | 0.73 | 0.84 |

### `format: png` — median ms (p95)

| case | feature | size | takumi-wasm | takumi-native | bm | bm / takumi-wasm | native / wasm |
| :-- | :-- | --: | --: | --: | --: | --: | --: |
| colors-solid-bg | colors | 400x300 | 1.18 (1.50) | 0.70 (0.99) | 0.46 (0.51) | 0.39 | 0.59 |
| colors-hex | colors | 1200x630 | 8.18 (8.41) | 4.25 (5.11) | 2.96 (3.52) | 0.36 | 0.52 |
| colors-functional | colors | 1200x630 | 7.52 (8.00) | 3.90 (4.49) | 2.93 (4.69) | 0.39 | 0.52 |
| colors-named | colors | 1200x630 | 7.98 (8.74) | 4.33 (5.34) | 3.02 (3.70) | 0.38 | 0.54 |
| colors-transparent-canvas | colors | 400x300 | 1.33 (1.54) | 0.76 (1.05) | 0.60 (0.79) | 0.45 | 0.57 |
| flex-row-column | flex | 1200x630 | 6.99 (7.55) | 3.29 (3.82) | 2.61 (3.52) | 0.37 | 0.47 |
| flex-justify-align | flex | 1200x630 | 6.39 (7.03) | 3.25 (4.03) | 2.80 (3.52) | 0.44 | 0.51 |
| flex-wrap-gap | flex | 1200x630 | 6.61 (7.48) | 3.45 (4.74) | 3.20 (4.05) | 0.48 | 0.52 |
| flex-grow-shrink-basis | flex | 1200x630 | 5.77 (6.96) | 2.93 (4.08) | 3.42 (4.02) | 0.59 | 0.51 |
| flex-nested-small | flex | 400x300 | 1.12 (1.39) | 0.76 (1.04) | 0.45 (0.71) | 0.40 | 0.68 |
| sizing-percent | sizing | 1200x630 | 6.74 (7.46) | 3.38 (4.08) | 3.21 (3.60) | 0.48 | 0.50 |
| sizing-minmax | sizing | 1200x630 | 6.36 (7.12) | 3.39 (4.26) | 3.06 (4.08) | 0.48 | 0.53 |
| sizing-aspect-ratio | sizing | 1200x630 | 6.83 (7.76) | 3.21 (3.67) | 2.09 (3.06) | 0.31 | 0.47 |
| sizing-padding-margin | sizing | 1200x630 | 6.69 (7.69) | 3.10 (4.08) | 3.35 (4.13) | 0.50 | 0.46 |
| sizing-auto-margin-center | sizing | 400x300 | 0.87 (1.08) | 0.49 (0.64) | 0.50 (0.60) | 0.57 | 0.56 |
| abs-inset | absolute | 1200x630 | 8.00 (8.82) | 3.87 (4.64) | 3.33 (3.98) | 0.42 | 0.48 |
| abs-zorder | absolute | 1200x630 | 14.67 (17.88) | 3.98 (4.72) | 6.46 (6.93) | 0.44 | 0.27 |
| abs-in-flow | absolute | 400x300 | 1.27 (1.83) | 0.82 (1.16) | 0.50 (0.61) | 0.39 | 0.64 |
| borders-uniform | borders | 1200x630 | 5.90 (6.52) | 3.12 (3.93) | 3.17 (3.73) | 0.54 | 0.53 |
| borders-per-side | borders | 1200x630 | 6.26 (7.30) | 3.19 (4.13) | 2.21 (3.37) | 0.35 | 0.51 |
| borders-with-radius | borders | 400x300 | 1.73 (2.04) | 0.99 (1.34) | 1.11 (1.24) | 0.64 | 0.57 |
| radius-uniform-percorner | border-radius | 1200x630 | 7.29 (8.06) | 3.61 (4.72) | 2.90 (4.32) | 0.40 | 0.50 |
| radius-elliptical | border-radius | 1200x630 | 6.72 (7.78) | 3.08 (3.61) | 2.80 (3.27) | 0.42 | 0.46 |
| radius-pill-circle | border-radius | 1200x630 | 6.04 (7.72) | 2.86 (3.59) | 2.48 (3.39) | 0.41 | 0.47 |
| radius-small | border-radius | 400x300 | 0.91 (1.17) | 0.54 (0.74) | 0.47 (0.73) | 0.52 | 0.60 |
| lingrad-angles | linear-gradient | 1200x630 | 34.96 (38.05) | 7.80 (9.11) | 10.01 (10.58) | 0.29 | 0.22 |
| lingrad-multistop | linear-gradient | 1200x630 | 24.52 (26.60) | 6.78 (7.57) | 10.53 (11.01) | 0.43 | 0.28 |
| lingrad-alpha | linear-gradient | 1200x630 | 29.52 (31.23) | 6.86 (7.45) | 9.08 (9.58) | 0.31 | 0.23 |
| lingrad-hero-small | linear-gradient | 400x300 | 3.18 (3.55) | 1.36 (1.87) | 1.81 (2.29) | 0.57 | 0.43 |
| radial-shapes | radial-gradient | 1200x630 | 36.94 (39.98) | 10.48 (10.96) | 17.84 (18.46) | 0.48 | 0.28 |
| radial-at-position | radial-gradient | 1200x630 | 39.06 (41.68) | 11.54 (12.13) | 16.48 (17.25) | 0.42 | 0.30 |
| radial-spotlight-small | radial-gradient | 400x300 | 10.09 (10.86) | 2.56 (3.01) | 5.56 (6.01) | 0.55 | 0.25 |
| shadow-offset-blur | box-shadow | 1200x630 | 29.91 (31.28) | 8.02 (8.47) | 13.55 (14.11) | 0.45 | 0.27 |
| shadow-spread-multi | box-shadow | 1200x630 | 30.17 (32.36) | 7.92 (8.32) | 14.34 (15.23) | 0.48 | 0.26 |
| shadow-inset | box-shadow | 1200x630 | 30.48 (31.27) | 9.62 (10.27) | 13.91 (14.54) | 0.46 | 0.32 |
| shadow-small | box-shadow | 400x300 | 2.18 (2.64) | 1.38 (1.66) | 1.15 (1.23) | 0.53 | 0.63 |
| opacity-basic | opacity | 1200x630 | 13.36 (14.04) | 5.40 (6.02) | 4.95 (5.60) | 0.37 | 0.40 |
| opacity-nested | opacity | 1200x630 | 14.52 (14.74) | 6.07 (6.75) | 3.61 (4.59) | 0.25 | 0.42 |
| opacity-with-radius-shadow | opacity | 400x300 | 4.65 (5.12) | 2.40 (2.79) | 1.79 (1.96) | 0.38 | 0.52 |
| overflow-hidden-clip | overflow | 1200x630 | 6.98 (7.55) | 3.62 (4.29) | 2.49 (3.19) | 0.36 | 0.52 |
| overflow-radius-clip | overflow | 1200x630 | 15.72 (17.63) | 4.66 (5.78) | 5.85 (6.35) | 0.37 | 0.30 |
| overflow-nested | overflow | 400x300 | 1.42 (1.79) | 0.89 (1.22) | 0.60 (0.72) | 0.42 | 0.63 |
| transform-basic | transform | 1200x630 | 9.03 (9.64) | 4.61 (5.73) | 3.27 (4.12) | 0.36 | 0.51 |
| transform-combined-origin | transform | 1200x630 | 8.73 (9.38) | 4.28 (5.25) | 3.16 (3.95) | 0.36 | 0.49 |
| transform-text-small | transform | 400x300 | 2.59 (3.04) | 1.63 (1.95) | 1.44 (1.66) | 0.56 | 0.63 |
| text-single-sizes | text-single-line | 1200x630 | 7.28 (8.21) | 3.65 (4.75) | 3.17 (4.16) | 0.44 | 0.50 |
| text-single-colors-small | text-single-line | 400x300 | 1.53 (1.82) | 1.05 (1.28) | 0.73 (0.86) | 0.48 | 0.69 |
| text-single-fonts | text-single-line | 1200x630 | 8.17 (9.02) | 3.70 (4.40) | 3.88 (4.95) | 0.48 | 0.45 |
| text-paragraph-wrap | text-paragraph | 1200x630 | 8.59 (8.91) | 4.36 (4.97) | 4.40 (5.10) | 0.51 | 0.51 |
| text-paragraph-lineheight | text-paragraph | 1200x630 | 9.14 (10.02) | 4.65 (5.48) | 5.17 (6.35) | 0.57 | 0.51 |
| text-paragraph-letterspacing | text-paragraph | 1200x630 | 10.01 (10.45) | 5.01 (5.47) | 5.64 (6.36) | 0.56 | 0.50 |
| text-paragraph-small | text-paragraph | 400x300 | 1.70 (2.25) | 1.06 (1.29) | 1.00 (1.11) | 0.59 | 0.63 |
| text-long-wrap | text-paragraph | 1200x630 | 10.33 (10.94) | 3.91 (4.65) | 3.64 (4.28) | 0.35 | 0.38 |
| fonts-weights-italic | fonts | 1200x630 | 9.58 (10.40) | 4.59 (5.45) | 5.40 (6.39) | 0.56 | 0.48 |
| fonts-mixed-inline | fonts | 1200x630 | 8.21 (9.97) | 4.17 (5.16) | 3.89 (4.59) | 0.47 | 0.51 |
| text-vietnamese | text-i18n | 1200x630 | 7.77 (9.49) | 3.70 (4.41) | 3.84 (4.69) | 0.49 | 0.48 |
| text-accented-latin | text-i18n | 1200x630 | 7.98 (8.98) | 3.76 (4.68) | 3.82 (4.52) | 0.48 | 0.47 |
| text-ellipsis-nowrap | text-truncation | 1200x630 | 6.62 (7.11) | 3.34 (4.21) | 2.39 (2.76) | 0.36 | 0.50 |
| text-lineclamp | text-truncation | 1200x630 | 7.89 (8.48) | 4.09 (5.20) | 3.56 (4.22) | 0.45 | 0.52 |
| text-lineclamp-small | text-truncation | 400x300 | 1.27 (1.59) | 0.78 (1.03) | 0.59 (0.72) | 0.46 | 0.62 |
| img-png-fit | images | 1200x630 | 34.34 (36.40) | 8.83 (9.60) | 17.80 (18.25) | 0.52 | 0.26 |
| img-jpeg-fit | images | 1200x630 | 52.57 (53.98) | 17.88 (18.65) | 27.57 (28.42) | 0.52 | 0.34 |
| img-intrinsic-size | images | 400x300 | 5.27 (5.79) | 1.22 (1.71) | 2.80 (3.13) | 0.53 | 0.23 |
| img-radius-clip | images | 1200x630 | 34.67 (35.37) | 9.97 (12.35) | 23.43 (25.57) | 0.68 | 0.29 |
| img-photo-bg | images | 1200x630 | 54.07 (55.51) | 11.62 (12.92) | 41.47 (51.48) | 0.77 | 0.21 |
| grid-fixed-fr | grid | 1200x630 | 6.65 (7.39) | 3.68 (4.34) | 2.85 (3.30) | 0.43 | 0.55 |
| grid-repeat-gap | grid | 1200x630 | 10.65 (11.20) | 4.10 (4.56) | 3.64 (4.32) | 0.34 | 0.38 |
| grid-spans | grid | 1200x630 | 7.65 (8.94) | 3.89 (4.69) | 2.70 (3.42) | 0.35 | 0.51 |
| grid-small-mixed | grid | 400x300 | 1.57 (1.90) | 1.03 (1.38) | 0.84 (1.05) | 0.53 | 0.65 |
| card-og | og-card | 1200x630 | 22.05 (23.93) | 7.58 (8.77) | 14.45 (14.74) | 0.66 | 0.34 |
| card-og-small | og-card | 600x315 | 8.10 (8.37) | 3.44 (4.05) | 5.64 (5.97) | 0.70 | 0.42 |
| card-blog | blog-card | 1200x630 | 48.53 (50.94) | 11.65 (12.54) | 29.89 (30.51) | 0.62 | 0.24 |
| card-flat-ui | blog-card | 1200x630 | 19.57 (20.75) | 6.73 (7.81) | 8.60 (9.10) | 0.44 | 0.34 |
| stress-600-boxes | stress | 1200x630 | 15.44 (15.82) | 9.37 (13.31) | 12.02 (14.04) | 0.78 | 0.61 |
| stress-200-labels | stress | 1200x630 | 22.55 (23.73) | 13.95 (14.97) | 14.17 (14.92) | 0.63 | 0.62 |
| stress-3000x2000-card | stress | 3000x2000 | 133.80 (137.26) | 39.95 (42.01) | 79.82 (83.21) | 0.60 | 0.30 |
| fx-text-shadow | text-shadow | 600x200 | 4.40 (5.29) | 1.83 (2.35) | 3.89 (5.40) | 0.88 | 0.42 |
| gap-dashed-dotted-border | known-gaps | 600x200 | 2.41 (3.03) | 1.43 (1.98) | 1.22 (1.41) | 0.51 | 0.59 |
| fx-filter-blur-grayscale | filter | 600x200 | 4.88 (5.41) | 1.81 (2.36) | 3.04 (3.44) | 0.62 | 0.37 |
| gap-tailwind-tw | known-gaps | 600x200 | 1.25 (1.49) | 0.79 (1.14) | 0.56 (0.72) | 0.45 | 0.64 |
| gap-oklch-color | known-gaps | 600x200 | 1.05 (1.50) | 0.64 (0.99) | 0.46 (0.57) | 0.44 | 0.61 |
| gap-svg-image | known-gaps | 600x200 | 1.03 (1.32) | 0.62 (0.87) | 0.50 (0.60) | 0.49 | 0.60 |
| gap-inline-box-decoration | known-gaps | 600x200 | 1.60 (2.00) | 1.01 (1.62) | 0.82 (0.91) | 0.51 | 0.63 |
| gap-mix-blend-mode | known-gaps | 600x200 | 1.50 (1.76) | 0.85 (1.15) | 0.69 (0.92) | 0.46 | 0.57 |
| gap-clip-path | known-gaps | 600x200 | 6.44 (7.36) | 1.20 (1.66) | 1.47 (2.01) | 0.23 | 0.19 |
| gap-background-clip-text | known-gaps | 600x200 | 5.34 (6.25) | 1.95 (2.29) | 1.41 (1.61) | 0.26 | 0.36 |
| gap-text-wrap-balance | known-gaps | 600x200 | 1.51 (1.87) | 0.98 (1.26) | 0.76 (0.85) | 0.50 | 0.65 |
| pfx-aa-shapes | aa-exact | 600x200 | 1.33 (1.55) | 0.85 (1.25) | 0.74 (0.81) | 0.56 | 0.64 |
| pfx-aa-text | aa-exact | 600x200 | 1.68 (2.04) | 1.03 (1.43) | 0.96 (1.33) | 0.57 | 0.61 |
| pfx-border-dashed | dashed-border | 600x200 | 3.24 (3.67) | 1.76 (2.27) | 1.65 (2.03) | 0.51 | 0.54 |
| pfx-border-dotted | dotted-border | 600x200 | 3.56 (4.04) | 2.00 (2.58) | 1.79 (2.12) | 0.50 | 0.56 |
| pfx-border-double-3d | double-3d-border | 600x200 | 1.29 (1.68) | 0.82 (1.17) | 0.71 (0.81) | 0.55 | 0.64 |
| pfx-border-mixed | mixed-border | 600x200 | 1.89 (2.25) | 1.09 (1.44) | 1.02 (1.14) | 0.54 | 0.58 |
| pfx-outline | outline | 600x200 | 2.60 (3.33) | 1.47 (1.96) | 1.17 (1.42) | 0.45 | 0.57 |
| pfx-clip-path-shapes | clip-path | 600x200 | 5.26 (5.61) | 1.33 (1.65) | 1.91 (2.15) | 0.36 | 0.25 |
| pfx-mask-gradient | mask | 600x200 | 6.41 (6.85) | 1.78 (2.31) | 2.27 (2.52) | 0.35 | 0.28 |
| pfx-bg-clip-text | bg-clip-text | 600x200 | 5.22 (5.85) | 2.58 (3.03) | 2.09 (2.32) | 0.40 | 0.49 |
| pfx-mix-blend | mix-blend | 600x200 | 7.63 (8.23) | 1.98 (2.58) | 4.16 (4.44) | 0.54 | 0.26 |
| pfx-bg-blend | bg-blend | 600x200 | 10.62 (11.23) | 4.70 (5.26) | 4.24 (4.57) | 0.40 | 0.44 |
| pfx-drop-shadow | drop-shadow | 600x200 | 7.04 (7.71) | 1.80 (2.46) | 3.40 (3.67) | 0.48 | 0.25 |
| pfx-backdrop-filter | backdrop-filter | 600x200 | 7.27 (7.80) | 3.19 (4.47) | 4.17 (5.43) | 0.57 | 0.44 |
| pfx-text-stroke | text-stroke | 600x200 | 2.02 (2.51) | 1.31 (1.65) | 1.82 (2.00) | 0.90 | 0.65 |
| pfx-text-decoration | text-decoration | 600x260 | 3.45 (3.80) | 1.92 (2.28) | 2.79 (2.94) | 0.81 | 0.56 |
| pfx-visibility | visibility | 600x200 | 1.11 (1.39) | 0.67 (0.98) | 0.51 (0.68) | 0.46 | 0.61 |
| pfx-opacity-layers | opacity | 600x200 | 6.87 (7.37) | 2.66 (2.97) | 3.99 (4.17) | 0.58 | 0.39 |
| pfx-svg-background | svg-image | 600x200 | 2.15 (2.59) | 1.23 (1.41) | 1.79 (2.06) | 0.83 | 0.57 |
| pfx-inline-boxes-many | inline-box | 600x300 | 5.18 (5.74) | 2.86 (3.39) | 3.63 (3.98) | 0.70 | 0.55 |
| css-class-id | css-stylesheet | 1200x630 | 7.31 (7.98) | 3.68 (4.24) | 3.36 (4.33) | 0.46 | 0.50 |
| css-nth-child | css-stylesheet | 800x500 | 4.28 (4.83) | 2.38 (3.09) | 1.81 (2.11) | 0.42 | 0.56 |
| css-media-layer | css-stylesheet | 1200x400 | 4.53 (5.09) | 2.39 (2.86) | 1.48 (1.80) | 0.33 | 0.53 |
| css-important-var | css-stylesheet | 900x400 | 3.39 (3.86) | 2.08 (2.58) | 1.04 (1.35) | 0.31 | 0.61 |
| tw-card | tailwind | 1200x630 | 7.05 (7.79) | 3.58 (4.00) | 3.32 (3.93) | 0.47 | 0.51 |
| tw-responsive | tailwind | 1200x400 | 3.49 (3.87) | 2.08 (2.67) | 1.21 (1.52) | 0.35 | 0.59 |
| tw-structural | tailwind | 800x500 | 3.03 (3.90) | 1.80 (2.41) | 1.32 (1.91) | 0.44 | 0.59 |
| tw-arbitrary | tailwind | 900x450 | 8.03 (8.73) | 4.56 (5.08) | 3.54 (4.85) | 0.44 | 0.57 |
| html-article | html | 1000x600 | 5.44 (6.04) | 2.94 (3.89) | 2.34 (3.28) | 0.43 | 0.54 |
| html-document | html | 800x400 | 2.61 (3.10) | 1.67 (2.19) | 1.02 (1.22) | 0.39 | 0.64 |
| html-flex-card | html | 1000x500 | 11.78 (12.41) | 4.29 (4.78) | 6.73 (7.17) | 0.57 | 0.36 |
| html-inline | html | 900x300 | 2.66 (3.12) | 1.82 (2.31) | 1.27 (1.59) | 0.48 | 0.69 |
| pseudo-inline | pseudo-elements | 800x300 | 2.56 (3.57) | 1.37 (1.99) | 0.99 (1.25) | 0.39 | 0.53 |
| pseudo-block | pseudo-elements | 800x400 | 2.70 (3.11) | 1.57 (2.03) | 1.18 (1.28) | 0.43 | 0.58 |
| pseudo-attr | pseudo-elements | 800x250 | 1.85 (2.24) | 1.03 (1.45) | 0.73 (0.87) | 0.40 | 0.56 |
| pseudo-tw | pseudo-elements | 800x300 | 2.16 (2.45) | 1.03 (1.40) | 0.94 (1.09) | 0.43 | 0.48 |
| anim-opacity-t0 | animation | 400x200 | 0.51 (0.70) | 0.33 (0.55) | 0.31 (0.37) | 0.62 | 0.65 |
| anim-opacity-t250 | animation | 400x200 | 0.74 (0.98) | 0.43 (0.59) | 0.34 (0.45) | 0.46 | 0.58 |
| anim-opacity-t500 | animation | 400x200 | 0.74 (1.05) | 0.44 (0.69) | 0.34 (0.40) | 0.46 | 0.59 |
| anim-opacity-t900 | animation | 400x200 | 0.74 (0.94) | 0.43 (0.70) | 0.33 (0.42) | 0.45 | 0.58 |
| anim-opacity-t1500 | animation | 400x200 | 0.60 (0.79) | 0.38 (0.51) | 0.31 (0.39) | 0.51 | 0.63 |
| anim-transform-t0 | animation | 400x200 | 0.62 (0.81) | 0.40 (0.61) | 0.40 (0.48) | 0.64 | 0.64 |
| anim-transform-t200 | animation | 400x200 | 0.64 (0.81) | 0.42 (0.63) | 0.33 (0.45) | 0.51 | 0.65 |
| anim-transform-t400 | animation | 400x200 | 0.63 (1.01) | 0.40 (0.65) | 0.32 (0.41) | 0.51 | 0.63 |
| anim-transform-t600 | animation | 400x200 | 0.64 (0.87) | 0.42 (0.59) | 0.33 (0.42) | 0.51 | 0.66 |
| anim-transform-t800 | animation | 400x200 | 0.64 (0.79) | 0.40 (0.62) | 0.39 (0.48) | 0.61 | 0.63 |
| anim-color-t0 | animation | 400x200 | 0.76 (1.05) | 0.51 (0.75) | 0.32 (0.44) | 0.42 | 0.67 |
| anim-color-t300 | animation | 400x200 | 0.79 (1.15) | 0.52 (0.81) | 0.33 (0.44) | 0.42 | 0.66 |
| anim-color-t700 | animation | 400x200 | 0.77 (1.08) | 0.53 (0.78) | 0.33 (0.38) | 0.43 | 0.69 |
| anim-color-t2000 | animation | 400x200 | 0.76 (0.99) | 0.51 (0.81) | 0.32 (0.47) | 0.42 | 0.67 |
| anim-width-t0 | animation | 400x200 | 0.55 (0.74) | 0.35 (0.56) | 0.34 (0.43) | 0.61 | 0.64 |
| anim-width-t100 | animation | 400x200 | 0.65 (0.87) | 0.42 (0.67) | 0.32 (0.38) | 0.49 | 0.65 |
| anim-width-t500 | animation | 400x200 | 0.71 (0.87) | 0.45 (0.74) | 0.41 (0.57) | 0.58 | 0.63 |
| anim-width-t999 | animation | 400x200 | 0.69 (0.98) | 0.45 (0.62) | 0.41 (0.52) | 0.60 | 0.66 |
| anim-delay-fill-t0 | animation | 400x200 | 0.78 (1.10) | 0.47 (0.71) | 0.41 (0.57) | 0.53 | 0.60 |
| anim-delay-fill-t750 | animation | 400x200 | 0.84 (1.10) | 0.48 (0.70) | 0.44 (0.54) | 0.52 | 0.57 |
| anim-delay-fill-t2000 | animation | 400x200 | 0.65 (0.99) | 0.42 (0.67) | 0.41 (0.73) | 0.62 | 0.65 |
| anim-alternate-t100 | animation | 400x200 | 0.74 (1.03) | 0.45 (0.69) | 0.34 (0.41) | 0.46 | 0.61 |
| anim-alternate-t500 | animation | 400x200 | 0.75 (0.99) | 0.46 (0.70) | 0.34 (0.46) | 0.46 | 0.61 |
| anim-alternate-t700 | animation | 400x200 | 0.75 (1.00) | 0.47 (0.83) | 0.34 (0.54) | 0.45 | 0.62 |
| anim-alternate-t1100 | animation | 400x200 | 0.74 (1.00) | 0.45 (0.69) | 0.34 (0.41) | 0.46 | 0.61 |
| anim-alternate-t1300 | animation | 400x200 | 0.56 (0.76) | 0.35 (0.59) | 0.32 (0.38) | 0.58 | 0.63 |
| anim-steps-t0 | animation | 400x200 | 0.59 (0.78) | 0.38 (0.63) | 0.35 (0.44) | 0.60 | 0.63 |
| anim-steps-t260 | animation | 400x200 | 0.59 (0.71) | 0.37 (0.58) | 0.35 (0.44) | 0.59 | 0.63 |
| anim-steps-t500 | animation | 400x200 | 0.58 (0.77) | 0.37 (0.61) | 0.35 (0.43) | 0.61 | 0.64 |
| anim-steps-t990 | animation | 400x200 | 0.60 (0.78) | 0.37 (0.57) | 0.35 (0.44) | 0.58 | 0.63 |
| anim-two-anims-t0 | animation | 400x200 | 0.75 (0.91) | 0.44 (0.67) | 0.35 (0.44) | 0.48 | 0.59 |
| anim-two-anims-t400 | animation | 400x200 | 1.06 (1.29) | 0.59 (0.76) | 0.47 (0.67) | 0.44 | 0.56 |
| anim-two-anims-t600 | animation | 400x200 | 1.09 (1.43) | 0.60 (0.87) | 0.48 (0.58) | 0.44 | 0.55 |
| anim-two-anims-t1200 | animation | 400x200 | 0.85 (1.10) | 0.54 (0.90) | 0.41 (0.49) | 0.48 | 0.64 |
| anim-inherit-t0 | animation | 400x200 | 0.82 (1.04) | 0.54 (0.81) | 0.38 (0.51) | 0.46 | 0.66 |
| anim-inherit-t500 | animation | 400x200 | 0.94 (1.37) | 0.68 (1.00) | 0.50 (0.61) | 0.53 | 0.72 |
| anim-inherit-t1000 | animation | 400x200 | 1.17 (1.57) | 0.79 (1.01) | 0.59 (0.70) | 0.51 | 0.67 |
| anim-tw-spin-t125 | animation | 400x200 | 0.76 (0.95) | 0.47 (0.69) | 0.36 (0.48) | 0.48 | 0.62 |
| anim-tw-spin-t375 | animation | 400x200 | 0.76 (0.95) | 0.47 (0.64) | 0.37 (0.45) | 0.48 | 0.61 |
| anim-tw-spin-t1600 | animation | 400x200 | 0.79 (1.20) | 0.49 (0.74) | 0.37 (0.50) | 0.47 | 0.62 |
| anim-kf-option-t0 | animation | 400x200 | 0.62 (1.03) | 0.40 (0.61) | 0.38 (0.50) | 0.61 | 0.64 |
| anim-kf-option-t500 | animation | 400x200 | 0.89 (1.08) | 0.52 (0.82) | 0.40 (0.49) | 0.45 | 0.58 |
| layout2-table-auto | table | 600x300 | 2.78 (3.12) | 1.68 (2.22) | 1.45 (1.89) | 0.52 | 0.61 |
| layout2-table-spans | table | 600x320 | 2.08 (2.53) | 1.20 (1.48) | 1.13 (1.35) | 0.55 | 0.58 |
| layout2-table-fixed | table | 600x260 | 2.44 (3.01) | 1.62 (2.28) | 1.26 (1.51) | 0.52 | 0.67 |
| layout2-table-percent | table | 600x220 | 1.39 (1.82) | 0.89 (1.36) | 0.66 (1.00) | 0.47 | 0.64 |
| layout2-table-collapse-conflicts | table | 600x300 | 2.42 (2.82) | 1.53 (2.26) | 1.24 (1.51) | 0.51 | 0.63 |
| layout2-table-col-backgrounds | table | 600x260 | 4.83 (5.51) | 2.18 (2.54) | 2.84 (3.06) | 0.59 | 0.45 |
| layout2-table-empty-cells | table | 600x240 | 1.89 (2.25) | 1.26 (1.81) | 0.87 (1.03) | 0.46 | 0.67 |
| layout2-table-caption-bottom | table | 600x300 | 2.56 (2.95) | 1.75 (2.10) | 1.37 (1.54) | 0.53 | 0.69 |
| layout2-float-image | float | 600x240 | 5.66 (5.98) | 1.52 (2.01) | 2.48 (2.87) | 0.44 | 0.27 |
| layout2-float-clear | float | 600x260 | 1.79 (2.24) | 0.98 (1.51) | 0.58 (0.68) | 0.32 | 0.55 |
| layout2-float-bfc | float | 600x260 | 1.41 (1.75) | 0.87 (1.44) | 0.81 (1.00) | 0.58 | 0.62 |
| layout2-float-wrap | float | 600x260 | 2.00 (2.38) | 1.20 (1.49) | 1.06 (1.19) | 0.53 | 0.60 |
| layout2-ib-badges | inline-block | 600x200 | 1.19 (1.48) | 0.76 (1.12) | 0.59 (0.82) | 0.49 | 0.64 |
| layout2-ib-wrap | inline-block | 600x260 | 1.86 (2.20) | 1.18 (1.57) | 0.94 (1.21) | 0.51 | 0.64 |
| layout2-ib-valign | inline-block | 600x220 | 3.03 (3.46) | 1.40 (1.75) | 2.22 (2.46) | 0.73 | 0.46 |
| layout2-ib-json | inline-block | 600x160 | 1.00 (1.33) | 0.68 (0.93) | 0.47 (0.63) | 0.47 | 0.68 |
| layout2-grid-areas | grid-areas | 600x360 | 2.11 (2.49) | 1.24 (1.57) | 1.07 (1.26) | 0.51 | 0.59 |
| layout2-grid-named-lines | grid-areas | 600x300 | 1.97 (2.36) | 1.22 (1.66) | 0.91 (1.03) | 0.46 | 0.62 |
| layout2-grid-areas-auto | grid-areas | 600x300 | 1.63 (2.20) | 1.05 (1.49) | 0.74 (0.96) | 0.45 | 0.64 |
| layout3-float-left | float-text | 520x260 | 1.98 (2.31) | 1.18 (1.41) | 1.08 (1.21) | 0.55 | 0.60 |
| layout3-float-right | float-text | 520x260 | 2.11 (2.92) | 1.22 (1.52) | 1.09 (1.21) | 0.52 | 0.58 |
| layout3-float-stacked | float-text | 560x300 | 2.87 (3.34) | 1.50 (2.02) | 1.63 (1.77) | 0.57 | 0.52 |
| layout3-float-tall | float-text | 560x330 | 3.32 (3.86) | 1.70 (2.05) | 2.02 (2.39) | 0.61 | 0.51 |
| layout3-float-in-text | float-text | 560x300 | 2.67 (3.72) | 1.56 (1.96) | 1.53 (1.81) | 0.57 | 0.59 |
| layout3-float-rtl | float-text | 560x300 | 3.39 (3.86) | 1.75 (2.17) | 2.13 (2.22) | 0.63 | 0.52 |
| layout3-float-inline-box | float-text | 560x280 | 2.18 (2.98) | 1.35 (1.75) | 1.17 (1.53) | 0.54 | 0.62 |
| layout3-inline-badges | inline-flow | 520x260 | 2.43 (2.79) | 1.53 (2.07) | 1.34 (1.53) | 0.55 | 0.63 |
| layout3-inline-image | inline-flow | 560x280 | 4.01 (4.33) | 1.80 (2.45) | 2.70 (3.06) | 0.67 | 0.45 |
| layout3-inline-flex-chip | inline-flow | 560x280 | 4.16 (4.67) | 1.98 (2.30) | 2.66 (4.28) | 0.64 | 0.47 |
| layout3-inline-br | inline-flow | 520x260 | 1.94 (3.03) | 1.12 (1.50) | 0.91 (1.18) | 0.47 | 0.57 |
| layout3-inline-abs | inline-flow | 520x220 | 1.64 (2.02) | 1.03 (1.45) | 0.93 (1.11) | 0.57 | 0.63 |
| layout3-span-edges | inline-box-model | 520x260 | 2.43 (3.34) | 1.46 (1.93) | 1.51 (1.92) | 0.62 | 0.60 |
| layout3-span-nowrap | inline-box-model | 520x240 | 2.43 (3.39) | 1.55 (2.00) | 1.37 (2.06) | 0.57 | 0.64 |
| layout3-span-valign | inline-box-model | 560x280 | 2.76 (3.05) | 1.73 (2.26) | 1.55 (1.80) | 0.56 | 0.63 |
| layout3-card-all | inline-box-model | 640x420 | 8.90 (9.24) | 3.95 (4.80) | 5.75 (6.26) | 0.65 | 0.44 |

### Per-feature summary (geometric mean of per-case median ratios)

| feature | cases | takumi-wasm raw ms (geomean) | takumi-wasm png ms (geomean) | bm/wasm raw | bm/wasm png | native/wasm raw | native/wasm png |
| :-- | --: | --: | --: | --: | --: | --: | --: |
| colors | 5 | 1.34 | 3.78 | 0.67 | 0.39 | 0.84 | 0.55 |
| flex | 5 | 1.04 | 4.53 | 1.01 | 0.45 | 1.09 | 0.53 |
| sizing | 5 | 0.80 | 4.43 | 0.98 | 0.46 | 1.20 | 0.50 |
| absolute | 3 | 1.02 | 5.30 | 0.86 | 0.42 | 0.86 | 0.44 |
| borders | 3 | 1.18 | 4.00 | 0.84 | 0.49 | 0.88 | 0.54 |
| border-radius | 4 | 0.77 | 4.06 | 1.20 | 0.43 | 1.09 | 0.50 |
| linear-gradient | 4 | 3.76 | 16.84 | 0.60 | 0.38 | 0.78 | 0.28 |
| radial-gradient | 3 | 4.62 | 24.42 | 0.36 | 0.48 | 0.85 | 0.28 |
| box-shadow | 4 | 5.79 | 15.65 | 0.55 | 0.48 | 0.68 | 0.34 |
| opacity | 4 | 5.16 | 8.87 | 0.42 | 0.38 | 0.55 | 0.43 |
| overflow | 3 | 1.46 | 5.38 | 0.66 | 0.38 | 0.91 | 0.46 |
| transform | 3 | 2.76 | 5.89 | 0.50 | 0.42 | 0.73 | 0.54 |
| text-single-line | 3 | 1.28 | 4.50 | 0.62 | 0.46 | 0.97 | 0.54 |
| text-paragraph | 5 | 2.07 | 6.73 | 0.66 | 0.51 | 0.91 | 0.50 |
| fonts | 2 | 2.65 | 8.87 | 0.57 | 0.52 | 0.87 | 0.49 |
| text-i18n | 2 | 2.41 | 7.87 | 0.64 | 0.49 | 0.93 | 0.47 |
| text-truncation | 3 | 1.49 | 4.05 | 0.63 | 0.42 | 0.87 | 0.54 |
| images | 5 | 4.57 | 28.20 | 0.37 | 0.60 | 0.75 | 0.26 |
| grid | 4 | 1.45 | 5.40 | 0.82 | 0.41 | 0.99 | 0.52 |
| og-card | 2 | 3.83 | 13.37 | 0.60 | 0.68 | 0.80 | 0.38 |
| blog-card | 2 | 10.24 | 30.82 | 0.64 | 0.52 | 0.61 | 0.29 |
| stress | 3 | 16.25 | 35.98 | 0.73 | 0.66 | 0.83 | 0.48 |
| text-shadow | 1 | 0.94 | 4.40 | 1.07 | 0.88 | 0.71 | 0.42 |
| known-gaps | 9 | 0.55 | 1.95 | 0.58 | 0.41 | 0.77 | 0.51 |
| filter | 1 | 1.66 | 4.88 | 0.77 | 0.62 | 0.64 | 0.37 |
| aa-exact | 2 | 0.58 | 1.50 | 0.64 | 0.56 | 0.74 | 0.62 |
| dashed-border | 1 | 2.35 | 3.24 | 0.56 | 0.51 | 0.54 | 0.54 |
| dotted-border | 1 | 2.77 | 3.56 | 0.53 | 0.50 | 0.56 | 0.56 |
| double-3d-border | 1 | 0.57 | 1.29 | 0.84 | 0.55 | 0.74 | 0.64 |
| mixed-border | 1 | 1.04 | 1.89 | 0.67 | 0.54 | 0.56 | 0.58 |
| outline | 1 | 1.48 | 2.60 | 0.55 | 0.45 | 0.60 | 0.57 |
| clip-path | 1 | 0.84 | 5.26 | 0.72 | 0.36 | 0.62 | 0.25 |
| mask | 1 | 1.52 | 6.41 | 0.76 | 0.35 | 0.69 | 0.28 |
| bg-clip-text | 1 | 2.50 | 5.22 | 0.17 | 0.40 | 0.65 | 0.49 |
| mix-blend | 1 | 1.72 | 7.63 | 0.69 | 0.54 | 0.58 | 0.26 |
| bg-blend | 1 | 4.84 | 10.62 | 0.20 | 0.40 | 0.76 | 0.44 |
| drop-shadow | 1 | 1.44 | 7.04 | 0.78 | 0.48 | 0.63 | 0.25 |
| backdrop-filter | 1 | 4.41 | 7.27 | 0.63 | 0.57 | 0.56 | 0.44 |
| text-stroke | 1 | 0.73 | 2.02 | 1.61 | 0.90 | 0.75 | 0.65 |
| text-decoration | 1 | 1.55 | 3.45 | 1.10 | 0.81 | 0.69 | 0.56 |
| visibility | 1 | 0.28 | 1.11 | 0.67 | 0.46 | 0.92 | 0.61 |
| svg-image | 1 | 0.82 | 2.15 | 1.46 | 0.83 | 0.56 | 0.57 |
| inline-box | 1 | 2.65 | 5.18 | 0.70 | 0.70 | 0.65 | 0.55 |
| css-stylesheet | 4 | 1.24 | 4.68 | 0.83 | 0.37 | 1.14 | 0.55 |
| tailwind | 4 | 1.45 | 4.94 | 0.89 | 0.42 | 1.19 | 0.56 |
| html | 4 | 1.37 | 4.59 | 0.69 | 0.46 | 0.94 | 0.54 |
| pseudo-elements | 4 | 0.70 | 2.29 | 0.69 | 0.41 | 1.03 | 0.54 |
| animation | 42 | 0.25 | 0.72 | 0.65 | 0.51 | 0.83 | 0.63 |
| table | 8 | 1.07 | 2.40 | 0.63 | 0.52 | 0.76 | 0.61 |
| float | 4 | 0.52 | 2.31 | 0.73 | 0.46 | 0.79 | 0.48 |
| inline-block | 4 | 0.50 | 1.61 | 0.69 | 0.54 | 0.84 | 0.60 |
| grid-areas | 3 | 0.62 | 1.89 | 0.77 | 0.47 | 0.82 | 0.62 |
| float-text | 7 | 0.84 | 2.59 | 0.72 | 0.57 | 0.74 | 0.56 |
| inline-flow | 5 | 0.85 | 2.64 | 0.75 | 0.58 | 0.77 | 0.55 |
| inline-box-model | 4 | 1.35 | 3.47 | 0.73 | 0.60 | 0.80 | 0.57 |

Overall geomean bm / takumi-wasm: raw **0.67**, png **0.49**.

### Encoders: jpeg (q85) and webp (default/lossless) — median ms (p95) and encoded bytes

| case | format | takumi-wasm | takumi-native | bm |
| :-- | :-- | --: | --: | --: |
| lingrad-angles | png | 34.96 (38.05) · 101.9 KiB | 7.80 (9.11) · 101.9 KiB | 10.01 (10.58) · 32.6 KiB |
| lingrad-angles | jpeg | 24.25 (25.46) · 52.3 KiB | 18.44 (19.73) · 52.3 KiB | 19.02 (22.81) · 52.2 KiB |
| lingrad-angles | webp | 15.13 (17.67) · 169.4 KiB | 112.39 (115.83) · 22.8 KiB | 10.50 (12.58) · 28.9 KiB |
| img-photo-bg | png | 54.07 (55.51) · 512.7 KiB | 11.62 (12.92) · 512.7 KiB | 41.47 (51.48) · 510.9 KiB |
| img-photo-bg | jpeg | 25.05 (27.90) · 55.2 KiB | 18.24 (19.11) · 55.2 KiB | 17.50 (19.26) · 55.1 KiB |
| img-photo-bg | webp | 21.02 (23.03) · 470.3 KiB | 165.54 (167.11) · 413.8 KiB | 19.88 (21.89) · 366.9 KiB |
| card-flat-ui | png | 19.57 (20.75) · 25.3 KiB | 6.73 (7.81) · 25.3 KiB | 8.60 (9.10) · 23.1 KiB |
| card-flat-ui | jpeg | 24.71 (26.16) · 49.0 KiB | 17.58 (17.90) · 49.0 KiB | 19.48 (19.88) · 48.9 KiB |
| card-flat-ui | webp | 12.08 (12.31) · 27.6 KiB | 16.89 (17.24) · 13.4 KiB | 9.23 (9.71) · 18.5 KiB |

## Errors

None.

