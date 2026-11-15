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
- **Thời gian render, bm-native so với takumi-pdf:** sync 0,32× [0,33× / 0,32× / 0,32×] (nhanh hơn ở 159/159, 0,16×–0,62×); async 0,37× [0,39× / 0,49× / 0,37×] (nhanh hơn ở 158/159, 0,16×–1,12×). Dưới 1× = bm tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ ở từng lượt.
- **bm-wasm vs takumi-pdf (cả hai là wasm):** 0,51× [0,51× / 0,51× / 0,51×] (nhanh hơn ở 158/159, 0,27×–1,13×). **bm-native vs bm-wasm (sync):** 0,64× [0,65× / 0,62× / 0,63×] (nhanh hơn ở 159/159, 0,45×–0,83×).
- **Trang mỗi giây ở 1 / 10 / 100 / 500 trang:** bm-native 193 / 291 / 333 / 456; bm-wasm 62 / 170 / 243 / 224; takumi-pdf 33 / 66 / 43 / 88.
- **Trùng byte:** bm-native == bm-wasm 161/161 tài liệu.
- **Bộ kiểm tra:** bm-native 152/161 PDF không có lỗi hay cảnh báo nào (takumi-pdf 152/161); veraPDF bm-native 45/45, takumi-pdf 45/45; cùng chữ, liên kết, mục lục và thẻ như takumi-pdf: 153/161.
- **Kết luận hình ảnh so với takumi-pdf (tốt nhất trong các bộ raster):** identical 117, equivalent 35, different 8, close 1 (161 tài liệu, pdfium + mupdf).
- **Nhiễu:** geomean tuyệt đối lệch giữa các lượt bm-native:sync 24,5 %, bm-native:async 55,3 %, bm-wasm:sync 28,0 %, bm-wasm:async 28,1 %, takumi-pdf:async 27,2 % ⚠; hãy đọc tỉ lệ (đo xen kẽ).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:speed -->
| Biến thể | geomean ms | từng lượt | độ lệch |
|:--|--:|--:|--:|
| bm-native:sync | 1,14 | 0,97 / 1,28 / 1,27 | 24,5 % ⚠ |
| bm-native:async | 1,29 | 1,13 / 1,96 / 1,50 | 55,3 % ⚠ |
| bm-wasm:sync | 1,80 | 1,49 / 2,06 / 2,03 | 28,0 % ⚠ |
| bm-wasm:async | 1,61 | 1,32 / 1,84 / 1,84 | 28,1 % ⚠ |
| takumi-pdf:async | 3,54 | 2,93 / 4,01 / 3,99 | 27,2 % ⚠ |

| Tỉ lệ (thời gian) | geomean | từng lượt | nhanh hơn | khoảng | độ lệch |
|:--|--:|--:|--:|--:|--:|
| bm-native:sync / takumi-pdf:async | 0,32× | 0,33× / 0,32× / 0,32× | 159/159 | 0,16×–0,62× | 4,1 % |
| bm-native:async / takumi-pdf:async | 0,37× | 0,39× / 0,49× / 0,37× | 158/159 | 0,16×–1,12× | 29,5 % ⚠ |
| bm-wasm:sync / takumi-pdf:async | 0,51× | 0,51× / 0,51× / 0,51× | 158/159 | 0,27×–1,13× | 0,8 % |
| bm-native:sync / bm-wasm:sync | 0,64× | 0,65× / 0,62× / 0,63× | 159/159 | 0,45×–0,83× | 4,5 % |
| bm-native:async / bm-native:sync | 1,13× | 1,17× / 1,53× / 1,18× | 33/159 | 0,78×–3,61× | 30,6 % ⚠ |

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
