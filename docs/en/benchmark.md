# Benchmark: bm-render and Takumi

This is the guide’s comparison with Takumi. Measurements describe the test machine, not a performance guarantee for every application. Image and PDF tables come from separate runs; do not compare timings across those tables.

::: tip Key results (bm-render 0.1.1, measured 2026-11-17)
- **PNG images:** bm-render native takes **1.9× less time** than Takumi native (async API, 1.21 vs 2.30 ms geomean over 250 fixtures); the WebAssembly builds: **2.3×** (1.45 vs 3.29 ms). PNG files are 20 % smaller.
- **PDF:** bm-render native takes **3.2× less time** than takumi-pdf (0.31× over 159 documents, faster on every one); bm-wasm vs takumi-pdf: **2.1×**.
- **Same output:** against Takumi, 81 images are byte-identical and 169 equivalent (0 different); PDFs: 117 identical, 35 equivalent, 1 close, 8 different out of 161.
- **Cold start:** 28 ms for the native addon, 92 ms for WebAssembly (Takumi: 53 / 204 ms).
:::

A time ratio **below 1×** means bm-render takes less time. **Geomean** is the geometric mean of per-fixture timings; **cold start** includes initialization and the first result. `identical` means byte-identical; `equivalent` allows small differences under the measurement thresholds and does not establish equivalence for every input.

## Images

250 fixtures use the same node trees, fonts and images. Run on 2026-11-17 with bm-render 0.1.1: 11th Gen Intel Core i5-1145G7 (laptop), Windows 10, Node 24.21.0; Takumi 2.20.0. Variants are interleaved over multiple warmed passes.

<!-- native-bench:summary -->
| Metric | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — sync API | 0.56 ±1.40 % | 0.87 ±1.30 % | no sync API | — |
| raw RGBA, geomean ms — async API | 0.74 ±1.20 % | — | 1.38 ±0.45 % | 1.45 ±1.20 % |
| PNG, geomean ms — sync API | 1.04 ±0.75 % | 1.45 ±0.80 % | no sync API | — |
| PNG, geomean ms — async API | 1.21 ±0.05 % | — | 2.30 ±0.55 % | 3.29 ±1.00 % |
| CPU time per PNG render, mean ms (cores used) | 1.48 (1.03 cores) | 2.03 (1.02 cores) | 3.65 (1.51 cores) | 4.27 (1.01 cores) |
| PNG file size, geomean vs takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start over empty Node, median / p95 ms | 28.0 / 56.9 | 92.5 / 113 | 52.7 / 68.1 | 204 / 249 |
| RSS after 1 → 10 suite passes, MiB | 102 → 101 | 138 → 139 | 142 → 154 | 144 → 179 |
| Peak RSS, one 4000×4000 PNG, MiB | 149 | 153 | 141 | 156 |
| Event loop: max 1 ms-timer delay, heavy 2400×2400 render, ms | 291 (sync) · 1.70 (async) | 422 (sync) · 527 (async) | 14.3 (async) | 894 (async) |
| Event loop: same, 60-frame animation, ms | 502 (sync) · 1.20 (async) | 920 (sync) · 905 (async) | 29.2 (async) | 1 859 (async) |
| Throughput, og card PNG, 4 concurrent, images/s (best config) | 236 (many K=8, UV 8) ⚠ | 168 (pool K=4) ⚠ | 180 (one, UV 4) ⚠ | 110 (pool K=4) ⚠ |
| Throughput, 8 concurrent, images/s (best config) | 310 (many K=8, UV 8) ⚠ | 191 (pool K=8) ⚠ | 207 (many K=2, UV 8) ⚠ | 124 (pool K=8) ⚠ |

Geomeans over the 250 fixtures every engine rendered; ± = half the range of the 3 passes' geomeans relative to their median; ⚠ = more than 10 % range. Cold start: median / p95 of 30 fresh processes minus the empty-Node median. Event-loop, memory and throughput are single runs; on the throughput rows ⚠ = other processes used more than one core on average during that stage.
<!-- /native-bench:summary -->

Verdicts against takumi-wasm (raw RGBA, same run): bm-native and bm-wasm each 81 identical, 169 equivalent, 0 close, 0 different and 0 errors across 250 fixtures. Equivalent requires SSIM ≥ 0.99 and at most 0.5% of pixels exceeding the pixelmatch 0.1 threshold. Data: [image wasm](../results.json), [image native](../results-native.json).

## PDF

2026-11-17 · bm-render 0.1.1 · 11th Gen Intel(R) Core(TM) i5-1145G7 @ 2.60GHz · win32 10.0.19045 x64 · Node v24.21.0 · 31.7 GiB RAM.

Engines use the same documents, fonts and images. Render timing is warm; file validation and visual comparison use separate tools. Timing and output equivalence are independent results.

<!-- pdf-bench:summary -->
- **Render time, bm-native vs takumi-pdf:** sync 0.31× [0.31× / 0.31× / 0.31×] (faster on 159/159, 0.14×–0.69×); async 0.38× [0.38× / 0.38× / 0.37×] (faster on 159/159, 0.15×–0.78×). Below 1× = bm takes less time; in brackets the same ratio per pass.
- **bm-wasm vs takumi-pdf (both wasm):** 0.47× [0.47× / 0.47× / 0.47×] (faster on 159/159, 0.25×–0.91×). **bm-native vs bm-wasm (sync):** 0.66× [0.65× / 0.66× / 0.66×] (faster on 159/159, 0.42×–0.79×).
- **Pages per second at 1 / 10 / 100 / 500 pages:** bm-native 408 / 677 / 761 / 405; bm-wasm 119 / 278 / 373 / 231; takumi-pdf 40 / 73 / 107 / 94.
- **Identity:** bm-native == bm-wasm 161/161 documents.
- **Validators:** bm-native 152/161 PDFs without any error or warning (takumi-pdf 152/161); veraPDF bm-native 45/45, takumi-pdf 45/45; same text, links, outline and tags as takumi-pdf: 153/161.
- **Visual verdicts vs takumi-pdf (best over the rasterisers):** identical 117, equivalent 35, different 8, close 1 (161 documents, pdfium + mupdf).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:speed -->
| Variant | geomean ms | per pass | spread |
|:--|--:|--:|--:|
| bm-native:sync | 0.80 | 0.79 / 0.81 / 0.80 | 1.6 % |
| bm-native:async | 0.96 | 0.97 / 0.97 / 0.97 | 0.7 % |
| bm-wasm:sync | 1.21 | 1.22 / 1.22 / 1.23 | 0.7 % |
| bm-wasm:async | 1.05 | 1.05 / 1.06 / 1.07 | 1.1 % |
| takumi-pdf:async | 2.57 | 2.58 / 2.58 / 2.63 | 2.2 % |

| Ratio (time) | geomean | per pass | faster | range | spread |
|:--|--:|--:|--:|--:|--:|
| bm-native:sync / takumi-pdf:async | 0.31× | 0.31× / 0.31× / 0.31× | 159/159 | 0.14×–0.69× | 2.3 % |
| bm-native:async / takumi-pdf:async | 0.38× | 0.38× / 0.38× / 0.37× | 159/159 | 0.15×–0.78× | 1.3 % |
| bm-wasm:sync / takumi-pdf:async | 0.47× | 0.47× / 0.47× / 0.47× | 159/159 | 0.25×–0.91× | 1.3 % |
| bm-native:sync / bm-wasm:sync | 0.66× | 0.65× / 0.66× / 0.66× | 159/159 | 0.42×–0.79× | 1.8 % |
| bm-native:async / bm-native:sync | 1.21× | 1.22× / 1.20× / 1.21× | 4/159 | 0.92×–2.21× | 1.6 % |

Warm render time per document (fonts registered beforehand, the output kept in memory), 159 documents, 3 pass(es); variants interleaved in rotating order every round.
<!-- /pdf-bench:speed -->

Full data: [results-pdf.json](../results-pdf.json). Usage constraints are documented under [image limitations](image/limitations.md) and [PDF limitations](pdf/limitations.md).

## Reproducing

```sh
# Image benchmark
node bench/run-native.mjs

# PDF timing, validation and visual comparison
node bench/pdf/bench.mjs
node bench/pdf/validate.mjs
node bench/pdf/visual.mjs
```

[Image benchmark setup](../../bench/README.md) · [PDF benchmark setup](../../bench/pdf/README.md). Historical reports remain in the repository: [detailed report](../BENCHMARK.md), [per-fixture results](../RESULTS_FULL.md).
