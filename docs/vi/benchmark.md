# Benchmark: bm-render và Takumi

Trang duy nhất trong bộ hướng dẫn dành cho so sánh với Takumi. Các số đo là kết quả trên máy thử, không phải cam kết tốc độ cho mọi ứng dụng. Bảng ảnh và bảng PDF đến từ hai lượt chạy khác nhau; không so thời gian giữa hai bảng.

::: tip Kết quả chính (bm-render 0.1.1, đo ngày 2026-11-17)
- **Ảnh PNG:** bm-render native tốn **ít hơn 1,9 lần** thời gian so với Takumi native (API async, geomean 1,21 so với 2,30 ms trên 250 fixture); giữa hai bản WebAssembly: **2,3 lần** (1,45 so với 3,29 ms). File PNG nhỏ hơn 20 %.
- **PDF:** bm-render native tốn **ít hơn 3,2 lần** thời gian so với takumi-pdf (0,31× trên 159 tài liệu, nhanh hơn ở mọi tài liệu); bm-wasm so với takumi-pdf: **2,1 lần**.
- **Đầu ra giống nhau:** so với Takumi, 81 ảnh trùng từng byte và 169 ảnh tương đương (0 khác); PDF: 117 trùng, 35 tương đương, 1 gần giống, 8 khác trên 161 tài liệu.
- **Cold start:** 28 ms với addon native, 92 ms với WebAssembly (Takumi: 53 / 204 ms).
:::

Tỉ lệ thời gian **dưới 1×** nghĩa là bm-render dùng ít thời gian hơn. **Geomean** là trung bình nhân của thời gian từng mẫu; **cold start** gồm khởi tạo và kết quả đầu tiên. `identical` là trùng từng byte; `equivalent` cho phép sai khác nhỏ theo ngưỡng của phép đo, không có nghĩa mọi đầu vào đều giống nhau.

## Ảnh

250 fixture dùng cùng cây node, font và ảnh. Chạy ngày 2026-11-17 với bm-render 0.1.1: Intel Core i5-1145G7 thế hệ 11 (laptop), Windows 10, Node 24.21.0; Takumi 2.20.0. Các biến thể được đo xen kẽ, nhiều lượt sau khi làm nóng.

<!-- native-bench:summary -->
| Chỉ số | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — API sync | 0.56 ±1.40 % | 0.87 ±1.30 % | không có API sync | — |
| raw RGBA, geomean ms — API async | 0.74 ±1.20 % | — | 1.38 ±0.45 % | 1.45 ±1.20 % |
| PNG, geomean ms — API sync | 1.04 ±0.75 % | 1.45 ±0.80 % | không có API sync | — |
| PNG, geomean ms — API async | 1.21 ±0.05 % | — | 2.30 ±0.55 % | 3.29 ±1.00 % |
| Thời gian CPU mỗi lần render PNG, ms trung bình (số lõi dùng) | 1.48 (1.03 lõi) | 2.03 (1.02 lõi) | 3.65 (1.51 lõi) | 4.27 (1.01 lõi) |
| Dung lượng PNG, geomean so với takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start so với Node rỗng, median / p95 ms | 28.0 / 56.9 | 92.5 / 113 | 52.7 / 68.1 | 204 / 249 |
| RSS sau 1 → 10 lượt cả bộ fixture, MiB | 102 → 101 | 138 → 139 | 142 → 154 | 144 → 179 |
| RSS đỉnh, một PNG 4000×4000, MiB | 149 | 153 | 141 | 156 |
| Event loop: độ trễ lớn nhất của timer 1 ms, render nặng 2400×2400, ms | 291 (sync) · 1.70 (async) | 422 (sync) · 527 (async) | 14.3 (async) | 894 (async) |
| Event loop: như trên, animation 60 khung, ms | 502 (sync) · 1.20 (async) | 920 (sync) · 905 (async) | 29.2 (async) | 1 859 (async) |
| Thông lượng, og card PNG, 4 đồng thời, ảnh/s (cấu hình tốt nhất) | 236 (many K=8, UV 8) ⚠ | 168 (pool K=4) ⚠ | 180 (one, UV 4) ⚠ | 110 (pool K=4) ⚠ |
| Thông lượng, 8 đồng thời, ảnh/s (cấu hình tốt nhất) | 310 (many K=8, UV 8) ⚠ | 191 (pool K=8) ⚠ | 207 (many K=2, UV 8) ⚠ | 124 (pool K=8) ⚠ |

Geomean trên 250 fixture mà cả bốn engine đều render được; ± = nửa khoảng chênh giữa geomean của 3 lượt so với median của chúng; ⚠ = chênh quá 10 %. Cold start: median / p95 của 30 tiến trình mới trừ median của Node rỗng. Event loop, bộ nhớ và thông lượng là một lần đo; ở các dòng thông lượng ⚠ = tiến trình khác dùng trung bình hơn một lõi trong lúc đo.
<!-- /native-bench:summary -->

Kết quả so với takumi-wasm (RGBA thô, cùng lượt chạy): bm-native và bm-wasm đều 81 identical, 169 equivalent, 0 close, 0 different, 0 lỗi trên 250 fixture. Ngưỡng equivalent: SSIM ≥ 0.99 và tối đa 0.5% điểm ảnh vượt ngưỡng pixelmatch 0.1. Dữ liệu: [ảnh wasm](../results.json), [ảnh native](../results-native.json).

## PDF

2026-11-17 · bm-render 0.1.1 · 11th Gen Intel(R) Core(TM) i5-1145G7 @ 2.60GHz · win32 10.0.19045 x64 · Node v24.21.0 · 31.7 GiB RAM.

Các engine dùng cùng tài liệu, font và ảnh. Thời gian render được đo sau khi làm nóng; kiểm tra file và hình ảnh dùng công cụ riêng. Không gộp tốc độ với mức giống nhau của kết quả.

<!-- pdf-bench:summary -->
- **Thời gian render, bm-native so với takumi-pdf:** sync 0,31× [0,31× / 0,31× / 0,31×] (nhanh hơn ở 159/159, 0,14×–0,69×); async 0,38× [0,38× / 0,38× / 0,37×] (nhanh hơn ở 159/159, 0,15×–0,78×). Dưới 1× = bm tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ ở từng lượt.
- **bm-wasm vs takumi-pdf (cả hai là wasm):** 0,47× [0,47× / 0,47× / 0,47×] (nhanh hơn ở 159/159, 0,25×–0,91×). **bm-native vs bm-wasm (sync):** 0,66× [0,65× / 0,66× / 0,66×] (nhanh hơn ở 159/159, 0,42×–0,79×).
- **Trang mỗi giây ở 1 / 10 / 100 / 500 trang:** bm-native 408 / 677 / 761 / 405; bm-wasm 119 / 278 / 373 / 231; takumi-pdf 40 / 73 / 107 / 94.
- **Trùng byte:** bm-native == bm-wasm 161/161 tài liệu.
- **Bộ kiểm tra:** bm-native 152/161 PDF không có lỗi hay cảnh báo nào (takumi-pdf 152/161); veraPDF bm-native 45/45, takumi-pdf 45/45; cùng chữ, liên kết, mục lục và thẻ như takumi-pdf: 153/161.
- **Kết luận hình ảnh so với takumi-pdf (tốt nhất trong các bộ raster):** identical 117, equivalent 35, different 8, close 1 (161 tài liệu, pdfium + mupdf).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:speed -->
| Biến thể | geomean ms | từng lượt | độ lệch |
|:--|--:|--:|--:|
| bm-native:sync | 0,80 | 0,79 / 0,81 / 0,80 | 1,6 % |
| bm-native:async | 0,96 | 0,97 / 0,97 / 0,97 | 0,7 % |
| bm-wasm:sync | 1,21 | 1,22 / 1,22 / 1,23 | 0,7 % |
| bm-wasm:async | 1,05 | 1,05 / 1,06 / 1,07 | 1,1 % |
| takumi-pdf:async | 2,57 | 2,58 / 2,58 / 2,63 | 2,2 % |

| Tỉ lệ (thời gian) | geomean | từng lượt | nhanh hơn | khoảng | độ lệch |
|:--|--:|--:|--:|--:|--:|
| bm-native:sync / takumi-pdf:async | 0,31× | 0,31× / 0,31× / 0,31× | 159/159 | 0,14×–0,69× | 2,3 % |
| bm-native:async / takumi-pdf:async | 0,38× | 0,38× / 0,38× / 0,37× | 159/159 | 0,15×–0,78× | 1,3 % |
| bm-wasm:sync / takumi-pdf:async | 0,47× | 0,47× / 0,47× / 0,47× | 159/159 | 0,25×–0,91× | 1,3 % |
| bm-native:sync / bm-wasm:sync | 0,66× | 0,65× / 0,66× / 0,66× | 159/159 | 0,42×–0,79× | 1,8 % |
| bm-native:async / bm-native:sync | 1,21× | 1,22× / 1,20× / 1,21× | 4/159 | 0,92×–2,21× | 1,6 % |

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
