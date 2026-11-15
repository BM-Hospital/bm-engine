# Benchmark: bm-engine and Takumi

This is the guide’s comparison with Takumi. Measurements describe the test machine, not a performance guarantee for every application. Image and PDF tables come from separate runs; do not compare timings across those tables.

A time ratio **below 1×** means bm-engine takes less time. **Geomean** is the geometric mean of per-fixture timings; **cold start** includes initialization and the first result. `identical` means byte-identical; `equivalent` allows small differences under the measurement thresholds and does not establish equivalence for every input.

## Images

250 fixtures use the same node trees, fonts and images. Native run on 2026-11-12: Intel Core i3-10100, Windows 11, Node 26.13.0; Takumi 2.20.0. Variants are interleaved over multiple warmed passes.

<!-- native-bench:summary -->
| Metric | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — sync API | 0.45 ±2.15 % | 0.74 ±2.15 % | no sync API | — |
| raw RGBA, geomean ms — async API | 0.47 ±2.25 % | — | 0.86 ±2.10 % | 1.19 ±2.35 % |
| PNG, geomean ms — sync API | 0.95 ±1.95 % | 1.41 ±1.55 % | no sync API | — |
| PNG, geomean ms — async API | 0.90 ±2.30 % | — | 1.66 ±1.55 % | 3.03 ±1.65 % |
| CPU time per PNG render, mean ms (cores used) | 1.00 (0.87 cores) | 1.30 (0.76 cores) | 3.20 (1.98 cores) | 2.84 (0.81 cores) |
| PNG file size, geomean vs takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start over empty Node, median / p95 ms | 21.8 / 45.5 | 75.5 / 93.0 | 46.2 / 69.2 | 185 / 249 |
| RSS after 1 → 10 suite passes, MiB | 90.7 → 91.4 | 127 → 150 | 118 → 124 | 138 → 172 |
| Peak RSS, one 4000×4000 PNG, MiB | 140 | 146 | 133 | 148 |
| Event loop: max 1 ms-timer delay, heavy 2400×2400 render, ms | 211 (sync) · 1.20 (async) | 401 (sync) · 392 (async) | 13.4 (async) | 746 (async) |
| Event loop: same, 60-frame animation, ms | 438 (sync) · 1.10 (async) | 848 (sync) · 873 (async) | 11.5 (async) | 1 848 (async) |
| Throughput, og card PNG, 4 concurrent, images/s (best config) | 372 (many K=8, UV 4) | 263 (pool K=4) | 298 (many K=2, UV 8) | 173 (pool K=8) |
| Throughput, 8 concurrent, images/s (best config) | 408 (many K=8, UV 8) | 291 (pool K=8) | 336 (one, UV 8) | 202 (pool K=8) |

Geomeans over the 250 fixtures every engine rendered; ± = half the range of the 3 passes' geomeans relative to their median; ⚠ = more than 10 % range. Cold start: median / p95 of 30 fresh processes minus the empty-Node median. Event-loop, memory and throughput are single runs; on the throughput rows ⚠ = other processes used more than one core on average during that stage.
<!-- /native-bench:summary -->

Image wasm verdicts: 81 identical, 169 equivalent, 0 close, 0 different and 0 errors across 250 fixtures. Equivalent requires SSIM ≥ 0.99 and at most 0.5% of pixels exceeding the pixelmatch 0.1 threshold. Data: [image wasm](../results.json), [image native](../results-native.json).

## PDF

2026-11-14 · 11th Gen Intel(R) Core(TM) i5-1145G7 @ 2.60GHz · win32 10.0.19045 x64 · Node v24.21.0 · 31.7 GiB RAM.

Engines use the same documents, fonts and images. Render timing is warm; file validation and visual comparison use separate tools. Timing and output equivalence are independent results.

<!-- pdf-bench:summary -->
- **Render time, bm-native vs takumi-pdf:** sync 0.33× [0.33× / 0.33× / 0.33×] (faster on 159/159, 0.16×–0.69×); async 0.42× [0.42× / 0.42× / 0.42×] (faster on 159/159, 0.18×–0.83×). Below 1× = bm takes less time; in brackets the same ratio per pass.
- **bm-wasm vs takumi-pdf (both wasm):** 0.51× [0.51× / 0.51× / 0.51×] (faster on 159/159, 0.26×–0.94×). **bm-native vs bm-wasm (sync):** 0.66× [0.65× / 0.66× / 0.66×] (faster on 159/159, 0.49×–0.79×).
- **Pages per second at 1 / 10 / 100 / 500 pages:** bm-native 408 / 611 / 615 / 568; bm-wasm 114 / 328 / 376 / 314; takumi-pdf 59 / 116 / 128 / 115.
- **Identity:** bm-native == bm-wasm 161/161 documents.
- **Validators:** bm-native 152/161 PDFs without any error or warning (takumi-pdf 152/161); veraPDF bm-native 45/45, takumi-pdf 45/45; same text, links, outline and tags as takumi-pdf: 153/161.
- **Visual verdicts vs takumi-pdf (best over the rasterisers):** identical 117, equivalent 35, different 8, close 1 (161 documents, pdfium + mupdf).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:speed -->
| Variant | geomean ms | per pass | spread |
|:--|--:|--:|--:|
| bm-native:sync | 0.75 | 0.75 / 0.75 / 0.75 | 0.3 % |
| bm-native:async | 0.95 | 0.95 / 0.95 / 0.96 | 0.6 % |
| bm-wasm:sync | 1.15 | 1.15 / 1.15 / 1.15 | 0.3 % |
| bm-wasm:async | 1.00 | 1.00 / 1.01 / 1.01 | 0.3 % |
| takumi-pdf:async | 2.26 | 2.27 / 2.26 / 2.27 | 0.4 % |

| Ratio (time) | geomean | per pass | faster | range | spread |
|:--|--:|--:|--:|--:|--:|
| bm-native:sync / takumi-pdf:async | 0.33× | 0.33× / 0.33× / 0.33× | 159/159 | 0.16×–0.69× | 0.3 % |
| bm-native:async / takumi-pdf:async | 0.42× | 0.42× / 0.42× / 0.42× | 159/159 | 0.18×–0.83× | 0.5 % |
| bm-wasm:sync / takumi-pdf:async | 0.51× | 0.51× / 0.51× / 0.51× | 159/159 | 0.26×–0.94× | 0.2 % |
| bm-native:sync / bm-wasm:sync | 0.66× | 0.65× / 0.66× / 0.66× | 159/159 | 0.49×–0.79× | 0.5 % |
| bm-native:async / bm-native:sync | 1.27× | 1.27× / 1.27× / 1.27× | 1/159 | 0.92×–2.66× | 0.5 % |

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
