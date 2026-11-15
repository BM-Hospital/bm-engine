# Benchmark: bm-engine và Takumi

Trang duy nhất trong bộ hướng dẫn dành cho so sánh với Takumi. Các số đo là kết quả trên máy thử, không phải cam kết tốc độ cho mọi ứng dụng. Bảng ảnh và bảng PDF đến từ hai lượt chạy khác nhau; không so thời gian giữa hai bảng.

Tỉ lệ thời gian **dưới 1×** nghĩa là bm-engine dùng ít thời gian hơn. **Geomean** là trung bình nhân của thời gian từng mẫu; **cold start** gồm khởi tạo và kết quả đầu tiên. `identical` là trùng từng byte; `equivalent` cho phép sai khác nhỏ theo ngưỡng của phép đo, không có nghĩa mọi đầu vào đều giống nhau.

## Ảnh

250 fixture dùng cùng cây node, font và ảnh. Lượt native ngày 2026-11-12: Intel Core i3-10100, Windows 11, Node 26.13.0; Takumi 2.20.0. Các biến thể được đo xen kẽ, nhiều lượt sau khi làm nóng.

<!-- native-bench:summary -->
| Chỉ số | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — API sync | 0.45 ±2.15 % | 0.74 ±2.15 % | không có API sync | — |
| raw RGBA, geomean ms — API async | 0.47 ±2.25 % | — | 0.86 ±2.10 % | 1.19 ±2.35 % |
| PNG, geomean ms — API sync | 0.95 ±1.95 % | 1.41 ±1.55 % | không có API sync | — |
| PNG, geomean ms — API async | 0.90 ±2.30 % | — | 1.66 ±1.55 % | 3.03 ±1.65 % |
| Thời gian CPU mỗi lần render PNG, ms trung bình (số lõi dùng) | 1.00 (0.87 lõi) | 1.30 (0.76 lõi) | 3.20 (1.98 lõi) | 2.84 (0.81 lõi) |
| Dung lượng PNG, geomean so với takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start so với Node rỗng, median / p95 ms | 21.8 / 45.5 | 75.5 / 93.0 | 46.2 / 69.2 | 185 / 249 |
| RSS sau 1 → 10 lượt cả bộ fixture, MiB | 90.7 → 91.4 | 127 → 150 | 118 → 124 | 138 → 172 |
| RSS đỉnh, một PNG 4000×4000, MiB | 140 | 146 | 133 | 148 |
| Event loop: độ trễ lớn nhất của timer 1 ms, render nặng 2400×2400, ms | 211 (sync) · 1.20 (async) | 401 (sync) · 392 (async) | 13.4 (async) | 746 (async) |
| Event loop: như trên, animation 60 khung, ms | 438 (sync) · 1.10 (async) | 848 (sync) · 873 (async) | 11.5 (async) | 1 848 (async) |
| Thông lượng, og card PNG, 4 đồng thời, ảnh/s (cấu hình tốt nhất) | 372 (many K=8, UV 4) | 263 (pool K=4) | 298 (many K=2, UV 8) | 173 (pool K=8) |
| Thông lượng, 8 đồng thời, ảnh/s (cấu hình tốt nhất) | 408 (many K=8, UV 8) | 291 (pool K=8) | 336 (one, UV 8) | 202 (pool K=8) |

Geomean trên 250 fixture mà cả bốn engine đều render được; ± = nửa khoảng chênh giữa geomean của 3 lượt so với median của chúng; ⚠ = chênh quá 10 %. Cold start: median / p95 của 30 tiến trình mới trừ median của Node rỗng. Event loop, bộ nhớ và thông lượng là một lần đo; ở các dòng thông lượng ⚠ = tiến trình khác dùng trung bình hơn một lõi trong lúc đo.
<!-- /native-bench:summary -->

Kết quả wasm ảnh: 81 identical, 169 equivalent, 0 close, 0 different, 0 lỗi trên 250 fixture. Ngưỡng equivalent: SSIM ≥ 0.99 và tối đa 0.5% điểm ảnh vượt ngưỡng pixelmatch 0.1. Dữ liệu: [ảnh wasm](../results.json), [ảnh native](../results-native.json).

## PDF

2026-11-14 · 11th Gen Intel(R) Core(TM) i5-1145G7 @ 2.60GHz · win32 10.0.19045 x64 · Node v24.21.0 · 31.7 GiB RAM.

Các engine dùng cùng tài liệu, font và ảnh. Thời gian render được đo sau khi làm nóng; kiểm tra file và hình ảnh dùng công cụ riêng. Không gộp tốc độ với mức giống nhau của kết quả.

<!-- pdf-bench:summary -->
- **Thời gian render, bm-native so với takumi-pdf:** sync 0,32× [0,31× / 0,32× / 0,32×] (nhanh hơn ở 159/159, 0,15×–0,69×); async 0,39× [0,39× / 0,39× / 0,40×] (nhanh hơn ở 159/159, 0,16×–0,79×). Dưới 1× = bm tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ ở từng lượt.
- **bm-wasm vs takumi-pdf (cả hai là wasm):** 0,40× [0,40× / 0,40× / 0,40×] (nhanh hơn ở 159/159, 0,21×–0,81×). **bm-native vs bm-wasm (sync):** 0,80× [0,79× / 0,80× / 0,80×] (nhanh hơn ở 159/159, 0,59×–0,96×).
- **Trang mỗi giây ở 1 / 10 / 100 / 500 trang:** bm-native 498 / 796 / 851 / 756; bm-wasm 152 / 217 / 550 / 447; takumi-pdf 54 / 105 / 133 / 118.
- **Trùng byte:** bm-native == bm-wasm 161/161 tài liệu.
- **Bộ kiểm tra:** bm-native 152/161 PDF không có lỗi hay cảnh báo nào (takumi-pdf 152/161); veraPDF bm-native 45/45, takumi-pdf 45/45; cùng chữ, liên kết, mục lục và thẻ như takumi-pdf: 153/161.
- **Kết luận hình ảnh so với takumi-pdf (tốt nhất trong các bộ raster):** identical 117, equivalent 35, different 8, close 1 (161 tài liệu, pdfium + mupdf).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:speed -->
| Biến thể | geomean ms | từng lượt | độ lệch |
|:--|--:|--:|--:|
| bm-native:sync | 0,69 | 0,68 / 0,70 / 0,69 | 2,9 % |
| bm-native:async | 0,86 | 0,86 / 0,86 / 0,86 | 0,2 % |
| bm-wasm:sync | 0,87 | 0,87 / 0,88 / 0,86 | 2,4 % |
| bm-wasm:async | 0,73 | 0,74 / 0,75 / 0,73 | 2,0 % |
| takumi-pdf:async | 2,18 | 2,18 / 2,23 / 2,17 | 2,6 % |

| Tỉ lệ (thời gian) | geomean | từng lượt | nhanh hơn | khoảng | độ lệch |
|:--|--:|--:|--:|--:|--:|
| bm-native:sync / takumi-pdf:async | 0,32× | 0,31× / 0,32× / 0,32× | 159/159 | 0,15×–0,69× | 1,6 % |
| bm-native:async / takumi-pdf:async | 0,39× | 0,39× / 0,39× / 0,40× | 159/159 | 0,16×–0,79× | 2,3 % |
| bm-wasm:sync / takumi-pdf:async | 0,40× | 0,40× / 0,40× / 0,40× | 159/159 | 0,21×–0,81× | 0,8 % |
| bm-native:sync / bm-wasm:sync | 0,80× | 0,79× / 0,80× / 0,80× | 159/159 | 0,59×–0,96× | 1,9 % |
| bm-native:async / bm-native:sync | 1,25× | 1,25× / 1,22× / 1,25× | 2/159 | 0,95×–2,43× | 2,7 % |

Thời gian render khi đã nóng cho mỗi tài liệu (font đăng ký trước, đầu ra giữ trong bộ nhớ), 159 tài liệu, 3 lượt; các biến thể chạy xen kẽ, đổi thứ tự mỗi vòng.
<!-- /pdf-bench:speed -->

Dữ liệu đầy đủ: [results-pdf.json](../results-pdf.json). Các hạn chế sử dụng nằm tại [hạn chế ảnh](image/limitations.md) và [hạn chế PDF](pdf/limitations.md).

## Chạy lại

```sh
# Image benchmark
node bench/run-native.mjs

# PDF timing, validation and visual comparison
node bench/pdf/bench.mjs
node bench/pdf/validate.mjs
node bench/pdf/visual.mjs
```

[Thiết lập benchmark ảnh](../../bench/README.md) · [Thiết lập benchmark PDF](../../bench/pdf/README.md). Các báo cáo lịch sử được lưu trong repository: [báo cáo chi tiết](../BENCHMARK.md), [từng fixture](../RESULTS_FULL.md).
