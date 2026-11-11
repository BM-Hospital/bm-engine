# bm-engine vs takumi — benchmark & equivalence results

- Date: 2026-11-11T16:14:24.391Z  |  Node v26.13.0  |  win32 10.0.26200 x64
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
| bm | binary (zig-out/bin/bm_engine.wasm) | 320.9 KiB | 147.1 KiB | 126.5 KiB |
| bm | JS glue (js/*.mjs) | 9.5 KiB | 3.2 KiB | 2.8 KiB |

## Cold start (fresh `node` process, median of runs)

| engine | runs | wasm compile+instantiate (native: addon load) ms | register Inter-Regular ms | first render (og-card, png) ms | total ms |
| :-- | --: | --: | --: | --: | --: |
| takumi-wasm | 7 | 34.07 | 3.66 | 151.70 | 188.05 |
| takumi-native | 7 | 22.98 | 1.46 | 19.86 | 44.75 |
| bm | 7 | 2.70 | 1.54 | 74.71 | 79.51 |

## Memory (child process: all fonts, 50 og-card PNG renders)

| engine | peak RSS (maxRSS) | wasm linear memory after init+fonts | wasm linear memory after 50 renders |
| :-- | --: | --: | --: |
| takumi-wasm | 99.6 MiB | 6.3 MiB | 10.6 MiB |
| takumi-native | 84.2 MiB | – | – |
| bm | 77.2 MiB | 6.3 MiB | 11.9 MiB |

Bare `node` baseline peak RSS: 44.6 MiB.

Wasm linear memory at end of the full case run (largest instance): takumi-wasm 66.4 MiB, bm 65.8 MiB.

## Output equivalence (reference = takumi-wasm, `format: raw`)

Verdict rules: **identical** = 0 differing bytes; **equivalent** = SSIM >= 0.99 and <= 0.5% pixels differing (pixelmatch thr 0.1, includeAA=true); **close** = SSIM >= 0.95 and <= 5% pixels differing; else **different**. `error/unsupported` when an engine threw. SSIM = mean over uniform 8x8 windows (stride 1) of luma over white; `SSIM RGB` = mean of per-channel SSIMs (catches chroma-only changes). Verdicts use min(luma, RGB). `px strict/AA` = pixelmatch count with includeAA true / false. `native` rows are the noise-floor baseline (same Rust code, different build).

### Verdict summary

| candidate | identical | equivalent | close | different | error/unsupported |
| :-- | --: | --: | --: | --: | --: |
| bm | 9 | 70 | 2 | 5 | 1 |
| takumi-native | 87 | 0 | 0 | 0 | 0 |

### bm vs takumi-wasm

| case | feature | verdict | SSIM luma | SSIM RGB | % diff strict | % diff AA-tol | px strict / AA | mean abs | max abs | PSNR dB |
| :-- | :-- | :-- | --: | --: | --: | --: | --: | --: | --: | :-- |
| colors-solid-bg | colors | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| colors-hex | colors | equivalent | 0.9999 | 0.9999 | 0.040 | 0.012 | 304 / 94 | 0.024 | 57 | 49.6 |
| colors-functional | colors | equivalent | 1.0000 | 1.0000 | 0.009 | 0.002 | 66 / 16 | 0.010 | 56 | 55.4 |
| colors-named | colors | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 1 / 1 | 0.006 | 26 | 59.5 |
| colors-transparent-canvas | colors | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.018 | 255 | 44.2 |
| flex-row-column | flex | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 15 | 66.6 |
| flex-justify-align | flex | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 15 | 63.4 |
| flex-wrap-gap | flex | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.006 | 16 | 60.2 |
| flex-grow-shrink-basis | flex | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| flex-nested-small | flex | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 15 | 63.0 |
| sizing-percent | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-minmax | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-aspect-ratio | sizing | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 15 | 70.3 |
| sizing-padding-margin | sizing | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| sizing-auto-margin-center | sizing | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 15 | 68.5 |
| abs-inset | absolute | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| abs-zorder | absolute | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.007 | 29 | 60.4 |
| abs-in-flow | absolute | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.007 | 24 | 59.4 |
| borders-uniform | borders | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| borders-per-side | borders | equivalent | 0.9998 | 0.9999 | 0.009 | 0.000 | 72 / 1 | 0.002 | 63 | 58.6 |
| borders-with-radius | borders | equivalent | 0.9980 | 0.9981 | 0.080 | 0.017 | 96 / 20 | 0.069 | 163 | 43.0 |
| radius-uniform-percorner | border-radius | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.005 | 31 | 60.3 |
| radius-elliptical | border-radius | equivalent | 0.9999 | 0.9999 | 0.002 | 0.000 | 18 / 0 | 0.009 | 31 | 57.9 |
| radius-pill-circle | border-radius | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.007 | 30 | 58.9 |
| radius-small | border-radius | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.008 | 14 | 59.3 |
| lingrad-angles | linear-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.003 | 16 | 67.3 |
| lingrad-multistop | linear-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 17 | 67.9 |
| lingrad-alpha | linear-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.002 | 14 | 71.4 |
| lingrad-hero-small | linear-gradient | equivalent | 0.9998 | 0.9998 | 0.056 | 0.000 | 67 / 0 | 0.030 | 46 | 50.7 |
| radial-shapes | radial-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 14 | 72.0 |
| radial-at-position | radial-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 16 | 69.0 |
| radial-spotlight-small | radial-gradient | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 1 | 82.2 |
| shadow-offset-blur | box-shadow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 2 / 0 | 0.002 | 24 | 67.0 |
| shadow-spread-multi | box-shadow | equivalent | 1.0000 | 0.9999 | 0.003 | 0.000 | 23 / 0 | 0.007 | 28 | 60.0 |
| shadow-inset | box-shadow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.005 | 16 | 63.1 |
| shadow-small | box-shadow | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.001 | 4 | 76.9 |
| opacity-basic | opacity | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 2 / 0 | 0.018 | 47 | 61.0 |
| opacity-nested | opacity | equivalent | 0.9999 | 1.0000 | 0.005 | 0.000 | 40 / 0 | 0.088 | 28 | 57.2 |
| opacity-with-radius-shadow | opacity | equivalent | 0.9999 | 0.9998 | 0.007 | 0.000 | 9 / 0 | 0.154 | 43 | 51.4 |
| overflow-hidden-clip | overflow | equivalent | 1.0000 | 1.0000 | 0.017 | 0.000 | 128 / 0 | 0.008 | 45 | 55.5 |
| overflow-radius-clip | overflow | equivalent | 0.9999 | 0.9999 | 0.028 | 0.000 | 215 / 0 | 0.017 | 46 | 52.7 |
| overflow-nested | overflow | equivalent | 1.0000 | 0.9999 | 0.000 | 0.000 | 0 / 0 | 0.003 | 26 | 64.5 |
| transform-basic | transform | equivalent | 0.9994 | 0.9995 | 0.064 | 0.000 | 485 / 1 | 0.031 | 84 | 48.7 |
| transform-combined-origin | transform | equivalent | 0.9988 | 0.9991 | 0.117 | 0.000 | 887 / 1 | 0.045 | 100 | 45.3 |
| transform-text-small | transform | equivalent | 0.9990 | 0.9991 | 0.284 | 0.012 | 341 / 14 | 0.104 | 77 | 43.5 |
| text-single-sizes | text-single-line | equivalent | 0.9995 | 0.9995 | 0.172 | 0.000 | 1302 / 2 | 0.077 | 60 | 44.5 |
| text-single-colors-small | text-single-line | equivalent | 0.9995 | 0.9996 | 0.116 | 0.009 | 139 / 11 | 0.073 | 60 | 46.8 |
| text-single-fonts | text-single-line | equivalent | 0.9993 | 0.9993 | 0.311 | 0.000 | 2349 / 0 | 0.140 | 75 | 42.0 |
| text-paragraph-wrap | text-paragraph | equivalent | 0.9996 | 0.9996 | 0.120 | 0.013 | 911 / 96 | 0.089 | 91 | 44.1 |
| text-paragraph-lineheight | text-paragraph | equivalent | 0.9997 | 0.9997 | 0.101 | 0.011 | 765 / 87 | 0.093 | 61 | 44.5 |
| text-paragraph-letterspacing | text-paragraph | equivalent | 0.9996 | 0.9996 | 0.123 | 0.011 | 927 / 82 | 0.099 | 61 | 44.2 |
| text-paragraph-small | text-paragraph | equivalent | 0.9990 | 0.9990 | 0.318 | 0.017 | 382 / 20 | 0.226 | 90 | 39.5 |
| text-long-wrap | text-paragraph | equivalent | 0.9999 | 0.9999 | 0.046 | 0.000 | 350 / 0 | 0.042 | 60 | 49.4 |
| fonts-weights-italic | fonts | equivalent | 0.9993 | 0.9993 | 0.381 | 0.000 | 2878 / 3 | 0.198 | 65 | 40.6 |
| fonts-mixed-inline | fonts | equivalent | 0.9991 | 0.9992 | 0.344 | 0.001 | 2603 / 4 | 0.131 | 108 | 42.6 |
| text-vietnamese | text-i18n | equivalent | 0.9996 | 0.9996 | 0.195 | 0.002 | 1471 / 14 | 0.114 | 60 | 43.5 |
| text-accented-latin | text-i18n | equivalent | 0.9994 | 0.9994 | 0.271 | 0.002 | 2052 / 11 | 0.132 | 60 | 42.0 |
| text-ellipsis-nowrap | text-truncation | equivalent | 0.9998 | 0.9998 | 0.073 | 0.001 | 551 / 9 | 0.044 | 60 | 46.0 |
| text-lineclamp | text-truncation | equivalent | 0.9999 | 0.9999 | 0.031 | 0.001 | 235 / 9 | 0.043 | 60 | 48.9 |
| text-lineclamp-small | text-truncation | equivalent | 0.9999 | 0.9999 | 0.038 | 0.003 | 46 / 4 | 0.038 | 60 | 48.2 |
| img-png-fit | images | equivalent | 0.9999 | 0.9999 | 0.002 | 0.000 | 12 / 0 | 0.027 | 51 | 57.2 |
| img-jpeg-fit | images | equivalent | 0.9996 | 0.9994 | 0.000 | 0.000 | 1 / 1 | 0.114 | 28 | 51.6 |
| img-intrinsic-size | images | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| img-radius-clip | images | equivalent | 0.9999 | 0.9999 | 0.000 | 0.000 | 0 / 0 | 0.023 | 17 | 62.6 |
| img-photo-bg | images | equivalent | 0.9998 | 0.9997 | 0.054 | 0.001 | 407 / 5 | 0.034 | 60 | 50.5 |
| grid-fixed-fr | grid | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 1 / 0 | 0.002 | 49 | 64.1 |
| grid-repeat-gap | grid | equivalent | 1.0000 | 1.0000 | 0.002 | 0.000 | 13 / 0 | 0.005 | 58 | 59.1 |
| grid-spans | grid | equivalent | 1.0000 | 1.0000 | 0.000 | 0.000 | 2 / 0 | 0.002 | 38 | 63.6 |
| grid-small-mixed | grid | equivalent | 0.9999 | 0.9999 | 0.001 | 0.000 | 1 / 0 | 0.013 | 49 | 56.0 |
| card-og | og-card | equivalent | 0.9991 | 0.9991 | 0.334 | 0.007 | 2524 / 55 | 0.143 | 59 | 42.3 |
| card-og-small | og-card | equivalent | 0.9995 | 0.9995 | 0.188 | 0.007 | 355 / 14 | 0.142 | 58 | 44.2 |
| card-blog | blog-card | equivalent | 0.9996 | 0.9995 | 0.141 | 0.000 | 1064 / 1 | 0.086 | 61 | 43.8 |
| card-flat-ui | blog-card | equivalent | 0.9949 | 0.9949 | 0.219 | 0.135 | 1659 / 1018 | 0.140 | 107 | 38.1 |
| stress-600-boxes | stress | equivalent | 0.9995 | 0.9996 | 0.000 | 0.000 | 0 / 0 | 0.070 | 28 | 49.1 |
| stress-200-labels | stress | equivalent | 0.9991 | 0.9991 | 0.093 | 0.001 | 704 / 7 | 0.152 | 54 | 44.3 |
| stress-3000x2000-card | stress | equivalent | 0.9997 | 0.9997 | 0.092 | 0.000 | 5510 / 1 | 0.044 | 60 | 48.1 |
| fx-text-shadow | text-shadow | equivalent | 0.9996 | 0.9996 | 0.142 | 0.001 | 170 / 1 | 0.105 | 60 | 45.2 |
| gap-dashed-dotted-border | known-gaps | different | 0.9335 | 0.9352 | 3.516 | 2.835 | 4219 / 3402 | 3.789 | 233 | 19.7 |
| fx-filter-blur-grayscale | filter | identical | 1.0000 | 1.0000 | 0.000 | 0.000 | 0 / 0 | 0.000 | 0 | 100.0 |
| gap-tailwind-tw | known-gaps | different | 0.2611 | 0.2893 | 99.992 | 98.494 | 119990 / 118193 | 105.110 | 255 | 4.7 |
| gap-oklch-color | known-gaps | error/unsupported |  |  |  |  |  |  |  | bm-engine: invalid value for style property backgroundColor |
| gap-svg-image | known-gaps | different | 0.9344 | 0.9257 | 12.690 | 12.235 | 15228 / 14682 | 11.843 | 233 | 14.5 |
| gap-inline-box-decoration | known-gaps | equivalent | 0.9990 | 0.9990 | 0.323 | 0.001 | 388 / 1 | 0.195 | 60 | 40.9 |
| gap-mix-blend-mode | known-gaps | close | 0.9677 | 0.9722 | 4.400 | 4.234 | 5280 / 5081 | 3.047 | 180 | 21.6 |
| gap-clip-path | known-gaps | different | 0.8594 | 0.8627 | 20.167 | 19.019 | 24200 / 22823 | 18.125 | 233 | 13.6 |
| gap-background-clip-text | known-gaps | different | 0.7373 | 0.7583 | 19.975 | 18.832 | 23970 / 22599 | 17.577 | 234 | 14.2 |
| gap-text-wrap-balance | known-gaps | close | 0.9981 | 0.9981 | 0.679 | 0.000 | 815 / 0 | 0.331 | 60 | 36.8 |

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

Noise floor (native vs wasm): 87/87 identical; lowest SSIM 1.00000 on `colors-solid-bg`.

## Performance

### `format: raw` — median ms (p95)

| case | feature | size | takumi-wasm | takumi-native | bm | bm / takumi-wasm | native / wasm |
| :-- | :-- | --: | --: | --: | :-- | --: | --: |
| colors-solid-bg | colors | 400x300 | 0.37 (0.93) | 0.32 (0.63) | 0.22 (0.43) | 0.61 | 0.88 |
| colors-hex | colors | 1200x630 | 4.23 (7.27) | 2.70 (5.09) | 1.96 (3.27) | 0.46 | 0.64 |
| colors-functional | colors | 1200x630 | 3.07 (4.30) | 2.56 (4.49) | 1.82 (3.36) | 0.59 | 0.83 |
| colors-named | colors | 1200x630 | 2.72 (4.11) | 2.46 (3.57) | 1.54 (2.69) | 0.57 | 0.90 |
| colors-transparent-canvas | colors | 400x300 | 0.62 (0.83) | 0.48 (0.89) | 0.39 (0.56) | 0.63 | 0.78 |
| flex-row-column | flex | 1200x630 | 1.72 (3.71) | 1.83 (3.83) | 1.35 (2.15) | 0.78 | 1.06 |
| flex-justify-align | flex | 1200x630 | 1.97 (3.83) | 1.98 (3.58) | 1.70 (2.74) | 0.86 | 1.00 |
| flex-wrap-gap | flex | 1200x630 | 1.85 (3.56) | 1.89 (3.48) | 1.69 (3.48) | 0.92 | 1.02 |
| flex-grow-shrink-basis | flex | 1200x630 | 1.41 (2.73) | 1.60 (3.75) | 1.28 (2.29) | 0.90 | 1.13 |
| flex-nested-small | flex | 400x300 | 0.32 (0.51) | 0.26 (0.60) | 0.26 (0.35) | 0.81 | 0.82 |
| sizing-percent | sizing | 1200x630 | 1.43 (2.89) | 1.68 (3.40) | 1.19 (2.05) | 0.83 | 1.17 |
| sizing-minmax | sizing | 1200x630 | 1.23 (2.82) | 1.39 (3.22) | 1.05 (1.85) | 0.86 | 1.13 |
| sizing-aspect-ratio | sizing | 1200x630 | 1.21 (2.70) | 1.53 (3.49) | 1.19 (2.45) | 0.98 | 1.26 |
| sizing-padding-margin | sizing | 1200x630 | 1.36 (3.42) | 1.64 (3.91) | 1.44 (2.56) | 1.06 | 1.21 |
| sizing-auto-margin-center | sizing | 400x300 | 0.18 (0.33) | 0.18 (0.48) | 0.15 (0.30) | 0.88 | 1.02 |
| abs-inset | absolute | 1200x630 | 2.07 (3.46) | 1.69 (3.66) | 1.38 (2.37) | 0.67 | 0.82 |
| abs-zorder | absolute | 1200x630 | 1.74 (3.27) | 1.77 (3.22) | 2.21 (3.31) | 1.27 | 1.02 |
| abs-in-flow | absolute | 400x300 | 0.33 (0.60) | 0.28 (0.62) | 0.21 (0.42) | 0.64 | 0.84 |
| borders-uniform | borders | 1200x630 | 1.96 (3.41) | 1.78 (3.59) | 1.23 (2.54) | 0.63 | 0.91 |
| borders-per-side | borders | 1200x630 | 1.54 (3.29) | 1.93 (3.47) | 2.29 (3.59) | 1.49 | 1.26 |
| borders-with-radius | borders | 400x300 | 0.81 (1.13) | 0.47 (0.89) | 0.55 (0.70) | 0.68 | 0.58 |
| radius-uniform-percorner | border-radius | 1200x630 | 1.42 (2.86) | 1.67 (3.58) | 1.67 (2.64) | 1.18 | 1.18 |
| radius-elliptical | border-radius | 1200x630 | 1.41 (3.21) | 1.55 (3.54) | 1.63 (2.80) | 1.16 | 1.10 |
| radius-pill-circle | border-radius | 1200x630 | 1.27 (2.79) | 1.60 (3.10) | 1.45 (2.51) | 1.14 | 1.26 |
| radius-small | border-radius | 400x300 | 0.21 (0.42) | 0.20 (0.49) | 0.23 (0.37) | 1.08 | 0.95 |
| lingrad-angles | linear-gradient | 1200x630 | 6.73 (7.95) | 5.73 (7.82) | 3.68 (5.22) | 0.55 | 0.85 |
| lingrad-multistop | linear-gradient | 1200x630 | 6.57 (9.95) | 5.50 (6.85) | 3.25 (4.61) | 0.49 | 0.84 |
| lingrad-alpha | linear-gradient | 1200x630 | 7.44 (9.52) | 5.08 (6.63) | 4.93 (6.61) | 0.66 | 0.68 |
| lingrad-hero-small | linear-gradient | 400x300 | 0.74 (1.09) | 0.51 (0.79) | 0.39 (0.50) | 0.52 | 0.69 |
| radial-shapes | radial-gradient | 1200x630 | 8.20 (9.75) | 6.79 (7.94) | 3.05 (3.72) | 0.37 | 0.83 |
| radial-at-position | radial-gradient | 1200x630 | 10.38 (11.98) | 8.92 (12.49) | 4.14 (5.86) | 0.40 | 0.86 |
| radial-spotlight-small | radial-gradient | 400x300 | 1.42 (1.72) | 1.32 (1.78) | 0.43 (0.57) | 0.30 | 0.93 |
| shadow-offset-blur | box-shadow | 1200x630 | 8.98 (11.40) | 6.22 (8.46) | 5.00 (6.89) | 0.56 | 0.69 |
| shadow-spread-multi | box-shadow | 1200x630 | 8.34 (9.66) | 6.07 (8.54) | 5.24 (5.93) | 0.63 | 0.73 |
| shadow-inset | box-shadow | 1200x630 | 11.78 (13.14) | 8.06 (9.41) | 5.41 (6.65) | 0.46 | 0.68 |
| shadow-small | box-shadow | 400x300 | 1.34 (1.62) | 0.90 (1.30) | 0.70 (0.88) | 0.52 | 0.68 |
| opacity-basic | opacity | 1200x630 | 7.27 (9.09) | 3.82 (5.10) | 3.54 (4.93) | 0.49 | 0.53 |
| opacity-nested | opacity | 1200x630 | 9.75 (10.38) | 4.88 (6.60) | 2.50 (3.40) | 0.26 | 0.50 |
| opacity-with-radius-shadow | opacity | 400x300 | 3.60 (3.96) | 1.89 (2.35) | 1.05 (1.30) | 0.29 | 0.52 |
| overflow-hidden-clip | overflow | 1200x630 | 2.41 (4.05) | 2.42 (4.21) | 1.36 (2.31) | 0.56 | 1.01 |
| overflow-radius-clip | overflow | 1200x630 | 3.88 (5.10) | 3.21 (5.49) | 2.34 (3.30) | 0.60 | 0.83 |
| overflow-nested | overflow | 400x300 | 0.43 (0.58) | 0.36 (0.69) | 0.28 (0.38) | 0.64 | 0.83 |
| transform-basic | transform | 1200x630 | 4.61 (6.06) | 3.33 (5.15) | 2.14 (3.93) | 0.46 | 0.72 |
| transform-combined-origin | transform | 1200x630 | 3.58 (5.28) | 3.03 (4.45) | 1.93 (2.74) | 0.54 | 0.85 |
| transform-text-small | transform | 400x300 | 1.53 (1.80) | 1.03 (1.45) | 1.27 (1.56) | 0.83 | 0.68 |
| text-single-sizes | text-single-line | 1200x630 | 2.11 (3.45) | 1.96 (3.89) | 1.39 (2.94) | 0.66 | 0.93 |
| text-single-colors-small | text-single-line | 400x300 | 0.60 (0.85) | 0.46 (0.83) | 0.23 (0.39) | 0.39 | 0.77 |
| text-single-fonts | text-single-line | 1200x630 | 2.00 (3.16) | 2.04 (3.67) | 1.39 (2.61) | 0.70 | 1.02 |
| text-paragraph-wrap | text-paragraph | 1200x630 | 3.12 (4.63) | 2.69 (4.51) | 1.85 (2.78) | 0.59 | 0.86 |
| text-paragraph-lineheight | text-paragraph | 1200x630 | 3.83 (5.34) | 3.08 (5.06) | 2.08 (3.02) | 0.54 | 0.80 |
| text-paragraph-letterspacing | text-paragraph | 1200x630 | 3.82 (4.76) | 3.11 (5.23) | 2.18 (3.95) | 0.57 | 0.82 |
| text-paragraph-small | text-paragraph | 400x300 | 0.62 (0.94) | 0.46 (0.88) | 0.31 (0.48) | 0.50 | 0.74 |
| text-long-wrap | text-paragraph | 1200x630 | 2.34 (3.69) | 2.11 (3.91) | 1.70 (2.92) | 0.72 | 0.90 |
| fonts-weights-italic | fonts | 1200x630 | 3.09 (5.02) | 2.71 (4.79) | 1.81 (2.53) | 0.58 | 0.88 |
| fonts-mixed-inline | fonts | 1200x630 | 2.39 (3.64) | 2.35 (4.50) | 1.37 (2.93) | 0.57 | 0.98 |
| text-vietnamese | text-i18n | 1200x630 | 2.35 (3.66) | 2.21 (3.76) | 1.46 (2.52) | 0.62 | 0.94 |
| text-accented-latin | text-i18n | 1200x630 | 2.57 (5.30) | 2.55 (4.37) | 1.60 (2.97) | 0.62 | 0.99 |
| text-ellipsis-nowrap | text-truncation | 1200x630 | 2.29 (4.81) | 2.15 (3.98) | 1.53 (2.53) | 0.67 | 0.94 |
| text-lineclamp | text-truncation | 1200x630 | 3.02 (4.44) | 2.73 (4.95) | 2.20 (3.62) | 0.73 | 0.90 |
| text-lineclamp-small | text-truncation | 400x300 | 0.72 (1.41) | 0.53 (0.91) | 0.26 (0.42) | 0.36 | 0.73 |
| img-png-fit | images | 1200x630 | 7.72 (9.37) | 5.99 (8.60) | 3.09 (4.65) | 0.40 | 0.78 |
| img-jpeg-fit | images | 1200x630 | 20.27 (23.31) | 12.97 (14.40) | 2.53 (3.65) | 0.12 | 0.64 |
| img-intrinsic-size | images | 400x300 | 0.39 (0.65) | 0.33 (0.57) | 0.34 (0.57) | 0.88 | 0.84 |
| img-radius-clip | images | 1200x630 | 7.47 (8.71) | 5.59 (7.11) | 4.28 (5.52) | 0.57 | 0.75 |
| img-photo-bg | images | 1200x630 | 6.29 (8.31) | 4.59 (6.32) | 1.73 (2.78) | 0.28 | 0.73 |
| grid-fixed-fr | grid | 1200x630 | 2.02 (3.78) | 2.11 (4.37) | 1.42 (3.02) | 0.70 | 1.05 |
| grid-repeat-gap | grid | 1200x630 | 2.57 (4.09) | 2.41 (4.55) | 1.64 (2.77) | 0.64 | 0.94 |
| grid-spans | grid | 1200x630 | 1.95 (3.08) | 1.99 (3.86) | 1.39 (2.52) | 0.71 | 1.02 |
| grid-small-mixed | grid | 400x300 | 0.78 (1.21) | 0.55 (0.95) | 0.33 (0.54) | 0.43 | 0.71 |
| card-og | og-card | 1200x630 | 6.17 (7.67) | 4.82 (6.82) | 3.60 (4.08) | 0.58 | 0.78 |
| card-og-small | og-card | 600x315 | 2.87 (3.33) | 2.07 (2.60) | 1.41 (1.82) | 0.49 | 0.72 |
| card-blog | blog-card | 1200x630 | 15.97 (17.17) | 7.69 (9.48) | 9.61 (10.78) | 0.60 | 0.48 |
| card-flat-ui | blog-card | 1200x630 | 7.14 (8.93) | 4.74 (7.77) | 2.38 (3.46) | 0.33 | 0.66 |
| stress-600-boxes | stress | 1200x630 | 8.79 (10.82) | 7.24 (9.57) | 7.91 (10.96) | 0.90 | 0.82 |
| stress-200-labels | stress | 1200x630 | 15.79 (17.21) | 12.24 (15.10) | 7.54 (9.70) | 0.48 | 0.78 |
| stress-3000x2000-card | stress | 3000x2000 | 31.72 (35.31) | 27.33 (29.24) | 22.60 (26.33) | 0.71 | 0.86 |
| fx-text-shadow | text-shadow | 600x200 | 1.00 (1.33) | 0.70 (1.13) | 1.00 (1.25) | 1.00 | 0.70 |
| gap-dashed-dotted-border | known-gaps | 600x200 | 1.79 (2.15) | 1.06 (1.51) | 0.19 (0.35) | 0.11 | 0.59 |
| fx-filter-blur-grayscale | filter | 600x200 | 1.76 (2.09) | 1.14 (1.58) | 1.12 (1.51) | 0.64 | 0.64 |
| gap-tailwind-tw | known-gaps | 600x200 | 0.33 (0.57) | 0.29 (0.66) | 0.14 (0.31) | 0.44 | 0.89 |
| gap-oklch-color | known-gaps | 600x200 | 0.22 (0.42) | 0.21 (0.53) | error | – | 0.94 |
| gap-svg-image | known-gaps | 600x200 | 0.29 (0.52) | 0.23 (0.52) | 0.14 (0.27) | 0.48 | 0.79 |
| gap-inline-box-decoration | known-gaps | 600x200 | 0.55 (0.96) | 0.43 (0.83) | 0.24 (0.38) | 0.44 | 0.78 |
| gap-mix-blend-mode | known-gaps | 600x200 | 0.73 (0.99) | 0.43 (0.80) | 0.32 (0.46) | 0.45 | 0.60 |
| gap-clip-path | known-gaps | 600x200 | 0.62 (0.99) | 0.45 (0.88) | 0.26 (0.40) | 0.42 | 0.73 |
| gap-background-clip-text | known-gaps | 600x200 | 1.91 (2.69) | 1.39 (2.10) | 0.24 (0.35) | 0.12 | 0.73 |
| gap-text-wrap-balance | known-gaps | 600x200 | 0.48 (0.79) | 0.38 (0.73) | 0.22 (0.37) | 0.45 | 0.79 |

### `format: png` — median ms (p95)

| case | feature | size | takumi-wasm | takumi-native | bm | bm / takumi-wasm | native / wasm |
| :-- | :-- | --: | --: | --: | :-- | --: | --: |
| colors-solid-bg | colors | 400x300 | 1.33 (2.10) | 0.79 (1.18) | 0.61 (0.78) | 0.46 | 0.59 |
| colors-hex | colors | 1200x630 | 8.43 (9.11) | 4.52 (5.43) | 5.61 (6.66) | 0.67 | 0.54 |
| colors-functional | colors | 1200x630 | 8.10 (10.87) | 4.33 (5.72) | 5.59 (6.35) | 0.69 | 0.53 |
| colors-named | colors | 1200x630 | 7.98 (8.63) | 4.31 (5.00) | 5.65 (6.55) | 0.71 | 0.54 |
| colors-transparent-canvas | colors | 400x300 | 1.37 (1.60) | 0.83 (1.09) | 1.04 (1.21) | 0.76 | 0.61 |
| flex-row-column | flex | 1200x630 | 7.11 (9.41) | 3.80 (4.55) | 5.12 (7.15) | 0.72 | 0.53 |
| flex-justify-align | flex | 1200x630 | 6.67 (7.82) | 3.37 (4.41) | 5.69 (6.95) | 0.85 | 0.51 |
| flex-wrap-gap | flex | 1200x630 | 6.60 (7.52) | 3.52 (4.57) | 5.67 (6.09) | 0.86 | 0.53 |
| flex-grow-shrink-basis | flex | 1200x630 | 5.72 (6.04) | 2.92 (3.51) | 4.46 (5.00) | 0.78 | 0.51 |
| flex-nested-small | flex | 400x300 | 1.10 (1.35) | 0.70 (0.97) | 0.83 (1.02) | 0.75 | 0.63 |
| sizing-percent | sizing | 1200x630 | 6.93 (7.65) | 3.58 (4.28) | 4.36 (5.22) | 0.63 | 0.52 |
| sizing-minmax | sizing | 1200x630 | 6.42 (6.91) | 3.44 (4.23) | 4.39 (5.10) | 0.68 | 0.53 |
| sizing-aspect-ratio | sizing | 1200x630 | 7.01 (7.95) | 3.53 (4.65) | 4.58 (5.18) | 0.65 | 0.50 |
| sizing-padding-margin | sizing | 1200x630 | 6.70 (7.23) | 3.25 (4.27) | 4.55 (5.73) | 0.68 | 0.49 |
| sizing-auto-margin-center | sizing | 400x300 | 0.90 (1.18) | 0.53 (0.81) | 0.70 (1.01) | 0.78 | 0.59 |
| abs-inset | absolute | 1200x630 | 7.88 (8.54) | 3.81 (4.88) | 4.51 (4.96) | 0.57 | 0.48 |
| abs-zorder | absolute | 1200x630 | 14.85 (16.41) | 4.17 (4.86) | 6.78 (8.21) | 0.46 | 0.28 |
| abs-in-flow | absolute | 400x300 | 1.31 (1.63) | 0.83 (1.09) | 0.84 (1.01) | 0.64 | 0.63 |
| borders-uniform | borders | 1200x630 | 6.10 (6.83) | 3.19 (3.63) | 4.42 (4.92) | 0.72 | 0.52 |
| borders-per-side | borders | 1200x630 | 6.40 (7.09) | 3.11 (4.20) | 5.61 (6.90) | 0.88 | 0.49 |
| borders-with-radius | borders | 400x300 | 1.81 (2.09) | 1.01 (1.26) | 1.42 (1.55) | 0.79 | 0.56 |
| radius-uniform-percorner | border-radius | 1200x630 | 7.24 (7.82) | 3.61 (4.41) | 5.72 (6.52) | 0.79 | 0.50 |
| radius-elliptical | border-radius | 1200x630 | 6.76 (7.94) | 3.22 (3.99) | 5.80 (6.30) | 0.86 | 0.48 |
| radius-pill-circle | border-radius | 1200x630 | 6.01 (6.66) | 3.16 (3.94) | 5.50 (6.47) | 0.91 | 0.53 |
| radius-small | border-radius | 400x300 | 0.94 (1.14) | 0.56 (0.75) | 0.88 (1.04) | 0.94 | 0.60 |
| lingrad-angles | linear-gradient | 1200x630 | 35.33 (36.05) | 8.39 (9.61) | 14.50 (15.25) | 0.41 | 0.24 |
| lingrad-multistop | linear-gradient | 1200x630 | 24.63 (25.22) | 7.15 (7.88) | 12.12 (12.94) | 0.49 | 0.29 |
| lingrad-alpha | linear-gradient | 1200x630 | 29.58 (30.12) | 7.10 (7.72) | 15.51 (17.21) | 0.52 | 0.24 |
| lingrad-hero-small | linear-gradient | 400x300 | 3.27 (3.69) | 1.42 (1.89) | 2.98 (3.17) | 0.91 | 0.43 |
| radial-shapes | radial-gradient | 1200x630 | 37.28 (40.43) | 11.22 (13.73) | 22.96 (25.71) | 0.62 | 0.30 |
| radial-at-position | radial-gradient | 1200x630 | 39.62 (42.57) | 12.37 (13.61) | 23.20 (25.10) | 0.59 | 0.31 |
| radial-spotlight-small | radial-gradient | 400x300 | 10.26 (10.59) | 2.83 (3.46) | 7.60 (8.43) | 0.74 | 0.28 |
| shadow-offset-blur | box-shadow | 1200x630 | 29.77 (30.31) | 8.61 (11.26) | 13.58 (14.00) | 0.46 | 0.29 |
| shadow-spread-multi | box-shadow | 1200x630 | 31.31 (34.54) | 8.24 (8.95) | 16.74 (17.57) | 0.53 | 0.26 |
| shadow-inset | box-shadow | 1200x630 | 30.23 (31.24) | 10.00 (11.43) | 13.17 (13.76) | 0.44 | 0.33 |
| shadow-small | box-shadow | 400x300 | 2.24 (2.55) | 1.44 (1.84) | 1.62 (1.84) | 0.72 | 0.64 |
| opacity-basic | opacity | 1200x630 | 13.45 (15.37) | 5.68 (6.63) | 7.17 (7.64) | 0.53 | 0.42 |
| opacity-nested | opacity | 1200x630 | 14.65 (14.95) | 6.84 (7.88) | 6.24 (7.19) | 0.43 | 0.47 |
| opacity-with-radius-shadow | opacity | 400x300 | 4.72 (5.08) | 2.49 (2.96) | 2.18 (2.37) | 0.46 | 0.53 |
| overflow-hidden-clip | overflow | 1200x630 | 7.13 (7.88) | 3.80 (4.58) | 4.88 (6.22) | 0.68 | 0.53 |
| overflow-radius-clip | overflow | 1200x630 | 15.09 (15.82) | 5.62 (7.14) | 10.65 (12.40) | 0.71 | 0.37 |
| overflow-nested | overflow | 400x300 | 1.49 (1.76) | 0.94 (1.16) | 0.94 (1.16) | 0.63 | 0.63 |
| transform-basic | transform | 1200x630 | 9.32 (9.91) | 4.89 (5.80) | 6.09 (6.90) | 0.65 | 0.53 |
| transform-combined-origin | transform | 1200x630 | 8.89 (9.30) | 4.63 (5.44) | 6.35 (7.69) | 0.71 | 0.52 |
| transform-text-small | transform | 400x300 | 2.65 (3.06) | 1.75 (2.34) | 2.54 (2.74) | 0.96 | 0.66 |
| text-single-sizes | text-single-line | 1200x630 | 7.16 (7.62) | 3.74 (4.30) | 6.88 (7.73) | 0.96 | 0.52 |
| text-single-colors-small | text-single-line | 400x300 | 1.65 (2.17) | 1.15 (1.56) | 1.27 (1.48) | 0.77 | 0.70 |
| text-single-fonts | text-single-line | 1200x630 | 8.13 (8.71) | 4.16 (4.99) | 9.08 (10.21) | 1.12 | 0.51 |
| text-paragraph-wrap | text-paragraph | 1200x630 | 8.85 (10.89) | 4.52 (5.17) | 8.25 (9.12) | 0.93 | 0.51 |
| text-paragraph-lineheight | text-paragraph | 1200x630 | 9.24 (9.66) | 5.02 (6.22) | 8.44 (9.18) | 0.91 | 0.54 |
| text-paragraph-letterspacing | text-paragraph | 1200x630 | 10.18 (10.79) | 5.27 (6.00) | 10.24 (11.44) | 1.01 | 0.52 |
| text-paragraph-small | text-paragraph | 400x300 | 1.82 (2.23) | 1.26 (1.66) | 1.84 (1.97) | 1.01 | 0.69 |
| text-long-wrap | text-paragraph | 1200x630 | 10.23 (11.02) | 4.36 (5.33) | 6.62 (7.23) | 0.65 | 0.43 |
| fonts-weights-italic | fonts | 1200x630 | 9.76 (10.29) | 4.66 (5.45) | 10.52 (11.02) | 1.08 | 0.48 |
| fonts-mixed-inline | fonts | 1200x630 | 8.03 (8.98) | 4.00 (4.51) | 7.74 (8.57) | 0.96 | 0.50 |
| text-vietnamese | text-i18n | 1200x630 | 8.08 (9.56) | 4.62 (5.98) | 9.17 (10.91) | 1.14 | 0.57 |
| text-accented-latin | text-i18n | 1200x630 | 7.80 (8.27) | 4.10 (5.21) | 7.76 (9.35) | 0.99 | 0.53 |
| text-ellipsis-nowrap | text-truncation | 1200x630 | 7.09 (8.75) | 4.03 (4.94) | 5.74 (7.34) | 0.81 | 0.57 |
| text-lineclamp | text-truncation | 1200x630 | 8.67 (10.29) | 4.52 (5.44) | 7.01 (7.95) | 0.81 | 0.52 |
| text-lineclamp-small | text-truncation | 400x300 | 1.48 (1.78) | 1.05 (1.63) | 1.08 (1.32) | 0.73 | 0.71 |
| img-png-fit | images | 1200x630 | 34.64 (40.31) | 9.29 (15.84) | 22.03 (27.76) | 0.64 | 0.27 |
| img-jpeg-fit | images | 1200x630 | 53.01 (57.41) | 18.48 (19.06) | 32.33 (32.90) | 0.61 | 0.35 |
| img-intrinsic-size | images | 400x300 | 5.25 (5.46) | 1.35 (1.75) | 3.58 (4.95) | 0.68 | 0.26 |
| img-radius-clip | images | 1200x630 | 35.14 (36.75) | 10.43 (12.94) | 26.76 (29.34) | 0.76 | 0.30 |
| img-photo-bg | images | 1200x630 | 55.27 (56.34) | 13.04 (14.41) | 47.60 (49.22) | 0.86 | 0.24 |
| grid-fixed-fr | grid | 1200x630 | 6.84 (7.64) | 3.65 (4.81) | 5.06 (5.49) | 0.74 | 0.53 |
| grid-repeat-gap | grid | 1200x630 | 10.79 (11.17) | 4.83 (5.99) | 5.48 (5.89) | 0.51 | 0.45 |
| grid-spans | grid | 1200x630 | 7.65 (8.27) | 4.01 (4.87) | 5.35 (6.89) | 0.70 | 0.52 |
| grid-small-mixed | grid | 400x300 | 1.66 (1.97) | 1.14 (1.41) | 1.14 (1.31) | 0.69 | 0.68 |
| card-og | og-card | 1200x630 | 21.98 (24.75) | 7.93 (8.75) | 20.94 (21.90) | 0.95 | 0.36 |
| card-og-small | og-card | 600x315 | 8.32 (8.89) | 3.65 (4.60) | 9.03 (9.56) | 1.09 | 0.44 |
| card-blog | blog-card | 1200x630 | 49.24 (62.14) | 12.87 (13.88) | 32.98 (35.10) | 0.67 | 0.26 |
| card-flat-ui | blog-card | 1200x630 | 19.93 (22.13) | 7.17 (8.91) | 7.13 (8.09) | 0.36 | 0.36 |
| stress-600-boxes | stress | 1200x630 | 15.85 (16.40) | 9.22 (10.38) | 14.66 (15.32) | 0.92 | 0.58 |
| stress-200-labels | stress | 1200x630 | 23.19 (25.38) | 14.67 (17.53) | 18.33 (22.16) | 0.79 | 0.63 |
| stress-3000x2000-card | stress | 3000x2000 | 135.48 (140.19) | 42.20 (45.83) | 135.59 (140.56) | 1.00 | 0.31 |
| fx-text-shadow | text-shadow | 600x200 | 4.36 (5.61) | 1.87 (2.43) | 5.44 (6.62) | 1.25 | 0.43 |
| gap-dashed-dotted-border | known-gaps | 600x200 | 2.61 (2.90) | 1.48 (1.82) | 0.79 (0.95) | 0.30 | 0.57 |
| fx-filter-blur-grayscale | filter | 600x200 | 4.95 (5.52) | 1.95 (2.57) | 3.49 (5.43) | 0.70 | 0.39 |
| gap-tailwind-tw | known-gaps | 600x200 | 1.36 (1.58) | 0.82 (1.07) | 0.80 (1.00) | 0.59 | 0.60 |
| gap-oklch-color | known-gaps | 600x200 | 1.09 (1.25) | 0.65 (0.84) | error | – | 0.60 |
| gap-svg-image | known-gaps | 600x200 | 1.09 (1.27) | 0.64 (0.81) | 0.57 (0.67) | 0.53 | 0.58 |
| gap-inline-box-decoration | known-gaps | 600x200 | 1.75 (2.43) | 1.08 (1.36) | 1.51 (1.63) | 0.86 | 0.62 |
| gap-mix-blend-mode | known-gaps | 600x200 | 1.65 (2.04) | 0.92 (1.19) | 1.12 (1.25) | 0.68 | 0.56 |
| gap-clip-path | known-gaps | 600x200 | 6.46 (6.90) | 1.20 (1.61) | 1.87 (2.19) | 0.29 | 0.19 |
| gap-background-clip-text | known-gaps | 600x200 | 5.39 (5.96) | 2.11 (2.82) | 1.86 (2.02) | 0.34 | 0.39 |
| gap-text-wrap-balance | known-gaps | 600x200 | 1.56 (1.91) | 1.03 (1.30) | 1.50 (1.89) | 0.96 | 0.66 |

### Per-feature summary (geometric mean of per-case median ratios)

| feature | cases | takumi-wasm raw ms (geomean) | takumi-wasm png ms (geomean) | bm/wasm raw | bm/wasm png | native/wasm raw | native/wasm png |
| :-- | --: | --: | --: | --: | --: | --: | --: |
| colors | 5 | 1.52 | 3.97 | 0.57 | 0.65 | 0.80 | 0.56 |
| flex | 5 | 1.23 | 4.56 | 0.85 | 0.79 | 1.00 | 0.54 |
| sizing | 5 | 0.87 | 4.52 | 0.92 | 0.68 | 1.16 | 0.53 |
| absolute | 3 | 1.06 | 5.35 | 0.81 | 0.55 | 0.89 | 0.44 |
| borders | 3 | 1.35 | 4.13 | 0.86 | 0.79 | 0.87 | 0.52 |
| border-radius | 4 | 0.86 | 4.08 | 1.14 | 0.87 | 1.12 | 0.52 |
| linear-gradient | 4 | 3.95 | 17.03 | 0.55 | 0.56 | 0.76 | 0.29 |
| radial-gradient | 3 | 4.94 | 24.75 | 0.36 | 0.64 | 0.87 | 0.30 |
| box-shadow | 4 | 5.86 | 15.85 | 0.54 | 0.53 | 0.69 | 0.36 |
| opacity | 3 | 6.34 | 9.76 | 0.33 | 0.47 | 0.52 | 0.47 |
| overflow | 3 | 1.59 | 5.43 | 0.60 | 0.67 | 0.88 | 0.50 |
| transform | 3 | 2.93 | 6.03 | 0.59 | 0.77 | 0.75 | 0.57 |
| text-single-line | 3 | 1.36 | 4.58 | 0.56 | 0.94 | 0.90 | 0.57 |
| text-paragraph | 5 | 2.31 | 6.89 | 0.58 | 0.89 | 0.82 | 0.53 |
| fonts | 2 | 2.72 | 8.85 | 0.58 | 1.02 | 0.93 | 0.49 |
| text-i18n | 2 | 2.46 | 7.94 | 0.62 | 1.06 | 0.97 | 0.55 |
| text-truncation | 3 | 1.71 | 4.50 | 0.56 | 0.78 | 0.85 | 0.59 |
| images | 5 | 4.91 | 28.47 | 0.37 | 0.70 | 0.74 | 0.28 |
| grid | 4 | 1.67 | 5.53 | 0.61 | 0.65 | 0.92 | 0.54 |
| og-card | 2 | 4.21 | 13.52 | 0.54 | 1.02 | 0.75 | 0.40 |
| blog-card | 2 | 10.68 | 31.33 | 0.45 | 0.49 | 0.57 | 0.31 |
| stress | 3 | 16.39 | 36.80 | 0.67 | 0.90 | 0.82 | 0.49 |
| text-shadow | 1 | 1.00 | 4.36 | 1.00 | 1.25 | 0.70 | 0.43 |
| known-gaps | 9 | 0.59 | 2.06 | 0.32 | 0.52 | 0.75 | 0.50 |
| filter | 1 | 1.76 | 4.95 | 0.64 | 0.70 | 0.64 | 0.39 |

Overall geomean bm / takumi-wasm: raw **0.57**, png **0.70**.

### Encoders: jpeg (q85) and webp (default/lossless) — median ms (p95) and encoded bytes

| case | format | takumi-wasm | takumi-native | bm |
| :-- | :-- | --: | --: | --: |
| lingrad-angles | png | 35.33 (36.05) · 101.9 KiB | 8.39 (9.61) · 101.9 KiB | 14.50 (15.25) · 32.2 KiB |
| lingrad-angles | jpeg | 24.68 (25.44) · 52.3 KiB | 18.75 (19.48) · 52.3 KiB | 19.28 (20.57) · 52.2 KiB |
| lingrad-angles | webp | 15.58 (16.62) · 169.4 KiB | 113.32 (114.01) · 22.8 KiB | 11.57 (15.06) · 28.9 KiB |
| img-photo-bg | png | 55.27 (56.34) · 512.7 KiB | 13.04 (14.41) · 512.7 KiB | 47.60 (49.22) · 511.1 KiB |
| img-photo-bg | jpeg | 24.86 (25.83) · 55.2 KiB | 18.23 (19.52) · 55.2 KiB | 17.88 (21.10) · 55.1 KiB |
| img-photo-bg | webp | 21.50 (23.41) · 470.3 KiB | 166.46 (175.87) · 413.8 KiB | 45.94 (50.67) · 404.8 KiB |
| card-flat-ui | png | 19.93 (22.13) · 25.3 KiB | 7.17 (8.91) · 25.3 KiB | 7.13 (8.09) · 13.1 KiB |
| card-flat-ui | jpeg | 25.14 (27.73) · 49.0 KiB | 17.68 (18.46) · 49.0 KiB | 17.63 (18.67) · 46.2 KiB |
| card-flat-ui | webp | 12.33 (13.33) · 27.6 KiB | 17.05 (18.67) · 13.4 KiB | 8.99 (9.97) · 10.9 KiB |

## Errors

| case | engine / stage | message |
| :-- | :-- | :-- |
| gap-oklch-color | bm (render raw) | bm-engine: invalid value for style property backgroundColor |
| gap-oklch-color | bm (perf raw) | bm-engine: invalid value for style property backgroundColor |
| gap-oklch-color | bm (perf png) | bm-engine: invalid value for style property backgroundColor |

