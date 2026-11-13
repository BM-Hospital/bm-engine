# Tóm tắt benchmark

[English](../en/benchmark.md) · [Tiếng Việt](benchmark.md)

> **Báo cáo đầy đủ bằng tiếng Việt: [docs/BENCHMARK.md](../BENCHMARK.md)** (phần "Giai đoạn 3" ở đầu
> file là số liệu cuối cùng của 0.1.0, tiếp theo là giai đoạn 2; báo cáo giai đoạn 1 được giữ ở cuối). Số liệu từng fixture:
> [RESULTS_FULL.md](../RESULTS_FULL.md) và [results.json](../results.json).

Trang này chỉ tóm tắt các con số chính (số liệu cuối cùng của 0.1.0, giai đoạn 3). bm-engine (profile `full`) được so với `@takumi-rs/wasm` 2.20.0
trên 250 fixture dùng chung (i3-10100, Windows 11, Node 26.13, ngày 2026-11-12): 81 fixture identical (trùng từng byte) và
169 equivalent (tương đương: SSIM ≥ 0.99 và ≤ 0.5 % điểm ảnh lệch, chủ yếu ở mép khử răng cưa); 0 close, 0 different, 0 lỗi;
render PNG nhanh hơn ở 248/250 ca đo thời gian (0.45× thời gian của takumi), render raw nhanh hơn ở 229/250 ca (0.63×); cold start nhanh hơn 2.5× (78.1 so với 193.8 ms); binary nhỏ hơn 4–9×.
bm-engine vẫn dùng nhiều hơn takumi 9 % bộ nhớ wasm và chậm hơn ở vài ca raw.

## Đầu ra PDF (giai đoạn 6)

`bm-engine/pdf` được đo cùng takumi-pdf trên cùng máy, Node.js, font, ảnh và đầu vào: **bm-native** (addon Node-API,
API sync và async), **bm-wasm** (`bm_engine.pdf.wasm`, profile `pdf`) và **takumi-pdf** (npm `takumi-pdf`, chỉ có
wasm; không có bản native nào được phát hành). Bộ tài liệu gồm đầu vào của 89 golden của takumi-pdf, các tài liệu
trong [hướng dẫn PDF](pdf/index.md) và tài liệu stress 1, 10, 100, 500 trang. Mọi bảng được sinh từ
[results-pdf.json](../results-pdf.json) bởi `node bench/pdf/bench.mjs`; các PDF được kiểm tra bằng công cụ bên ngoài
(`node bench/pdf/validate.mjs`: qpdf, pdfcpu, poppler, MuPDF, pdf.js, veraPDF) và so sánh hình ảnh với takumi-pdf
(`node bench/pdf/visual.mjs`). Thời gian render đo khi đã nóng, các engine chạy xen kẽ trong từng tài liệu, qua
nhiều lượt; khởi động lạnh, bộ nhớ, event loop, theo số trang và thông lượng: mỗi điểm chạy trong một tiến trình mới.

<!-- pdf-bench:summary -->
- **Thời gian render, bm-native so với takumi-pdf:** sync 0,33× [0,33× / 0,34× / 0,34×] (nhanh hơn ở 112/112, 0,14×–0,91×); async 0,33× [0,33× / 0,33× / 0,33×] (nhanh hơn ở 112/112, 0,13×–0,92×). Dưới 1× = bm tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ ở từng lượt.
- **bm-wasm vs takumi-pdf (cả hai là wasm):** 0,54× [0,54× / 0,54× / 0,54×] (nhanh hơn ở 107/112, 0,23×–1,34×). **bm-native vs bm-wasm (sync):** 0,62× [0,62× / 0,63× / 0,62×] (nhanh hơn ở 112/112, 0,43×–0,75×).
- **Trang mỗi giây ở 1 / 10 / 100 / 500 trang:** bm-native 409 / 559 / 553 / 504; bm-wasm 128 / 306 / 342 / 295; takumi-pdf 57 / 100 / 117 / 110.
- **Trùng byte:** bm-native == bm-wasm 114/114 tài liệu.
- **Bộ kiểm tra:** bm-native 105/114 PDF không có lỗi hay cảnh báo nào (takumi-pdf 105/114); veraPDF bm-native 45/45, takumi-pdf 45/45; cùng chữ, liên kết, mục lục và thẻ như takumi-pdf: 114/114.
- **Kết luận hình ảnh so với takumi-pdf (tốt nhất trong các bộ raster):** identical 86, equivalent 27, different 1 (114 tài liệu, pdfium + mupdf).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:speed -->
| Biến thể | geomean ms | từng lượt | độ lệch |
|:--|--:|--:|--:|
| bm-native:sync | 1,04 | 1,05 / 1,05 / 1,04 | 0,7 % |
| bm-native:async | 1,03 | 1,04 / 1,05 / 1,04 | 0,3 % |
| bm-wasm:sync | 1,67 | 1,68 / 1,68 / 1,68 | 0,4 % |
| bm-wasm:async | 1,56 | 1,56 / 1,56 / 1,56 | 0,4 % |
| takumi-pdf:async | 3,11 | 3,13 / 3,14 / 3,12 | 0,5 % |

| Tỉ lệ (thời gian) | geomean | từng lượt | nhanh hơn | khoảng | độ lệch |
|:--|--:|--:|--:|--:|--:|
| bm-native:sync / takumi-pdf:async | 0,33× | 0,33× / 0,34× / 0,34× | 112/112 | 0,14×–0,91× | 0,3 % |
| bm-native:async / takumi-pdf:async | 0,33× | 0,33× / 0,33× / 0,33× | 112/112 | 0,13×–0,92× | 0,3 % |
| bm-wasm:sync / takumi-pdf:async | 0,54× | 0,54× / 0,54× / 0,54× | 107/112 | 0,23×–1,34× | 0,2 % |
| bm-native:sync / bm-wasm:sync | 0,62× | 0,62× / 0,63× / 0,62× | 112/112 | 0,43×–0,75× | 0,6 % |
| bm-native:async / bm-native:sync | 0,99× | 1,00× / 0,99× / 1,00× | 68/112 | 0,91×–1,09× | 0,4 % |

Thời gian render khi đã nóng cho mỗi tài liệu (font đăng ký trước, đầu ra giữ trong bộ nhớ), 112 tài liệu, 3 lượt; các biến thể chạy xen kẽ, đổi thứ tự mỗi vòng.
<!-- /pdf-bench:speed -->

<!-- pdf-bench:scale -->
| Trang | bm-native ms | trang/s | kích thước | RSS đỉnh | bm-wasm ms | trang/s | kích thước | RSS đỉnh | takumi-pdf ms | trang/s | kích thước | RSS đỉnh |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| 1 | 2,40 ms | 408,8 | 27 KiB | 53 MiB | 7,80 ms | 128,0 | 27 KiB | 81 MiB | 17,5 ms | 57,3 | 27 KiB | 106 MiB |
| 10 | 17,9 ms | 558,9 | 58 KiB | 60 MiB | 32,7 ms | 306,0 | 58 KiB | 81 MiB | 99,8 ms | 100,2 | 58 KiB | 115 MiB |
| 100 | 181 ms | 553,1 | 369 KiB | 114 MiB | 292 ms | 342,2 | 369 KiB | 126 MiB | 854 ms | 117,2 | 426 KiB | 127 MiB |
| 500 | 993 ms | 503,6 | 1.772 KiB | 317 MiB | 1.693 ms | 295,3 | 1.772 KiB | 286 MiB | 4.534 ms | 110,3 | 2.186 KiB | 190 MiB |

Một lần render tài liệu stress (mỗi trang: tiêu đề, đoạn văn, bảng 14 dòng, một ảnh; `break-after: page`) trong một tiến trình mới cho mỗi điểm; làm nóng bằng tài liệu 1 trang. Độ siêu tuyến tính (thời gian mỗi trang ở 100 trang / ở 10 trang; 1× = tuyến tính): bm-native 1,01×, bm-wasm 0,89×, takumi-pdf 0,86×.
<!-- /pdf-bench:scale -->

<!-- pdf-bench:equiv -->
| Engine | PDF | sạch | lỗi | cảnh báo | bm-only | chung với takumi-pdf | veraPDF |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 114 | 105 | 12 | 0 | 0 | 12 | 45/45 |
| bm-wasm | 114 | 105 | 12 | 0 | 0 | 12 | 45/45 |
| takumi-pdf | 114 | 105 | 12 | 0 | — | — | 45/45 |

Bộ kiểm tra: qpdf 12.4.2, pdfcpu 0.16.4 (strict), poppler 26.09.0 (oschwartz10612/poppler-windows Release-26.09.0-0) (pdfinfo, pdffonts), MuPDF 1.28.6 (wasm), pdf.js 6.5.438, veraPDF 1.28.2 (greenfield-apps, the shaded CLI jar published to Maven Central). Ngữ nghĩa (pdf.js: chữ từng trang, liên kết, mục lục, tệp đính kèm, thẻ, metadata) trùng với takumi-pdf ở 114/114 tài liệu.

| Bộ raster | identical | equivalent | close | different |
|:--|--:|--:|--:|--:|
| pdfium | 78 | 35 | 0 | 1 |
| mupdf | 78 | 34 | 1 | 1 |
| tốt nhất trong các bộ raster | 86 | 27 | 0 | 1 |

bm-native so với takumi-pdf, cùng bộ raster, 96 và 144 dpi, 114 tài liệu (tính theo trang tệ nhất). PDF của bm so với ảnh bm render cùng cây (tài liệu viewport, 96 dpi): pdfium equivalent 7, different 11, close 16, identical 2; mupdf equivalent 19, different 11, close 6.

bm-native == bm-wasm từng byte: 114/114. Lỗi render: không có.
<!-- /pdf-bench:equiv -->

## Addon native cho Node.js (giai đoạn 4)

Từ giai đoạn 4, `bm-engine` trên Node.js chạy bằng addon native khi có addon cho nền tảng, và tự động quay về bản
wasm khi không có. Bốn bản — bm-native, bm-wasm (`full`), takumi-native (`@takumi-rs/core`) và takumi-wasm — được đo
cùng lúc trên cùng 250 fixture. Các bảng dưới đây được sinh từ [results-native.json](../results-native.json) bởi
`node bench/run-native.mjs`; trang hướng dẫn là [Native so với WebAssembly](native-vs-wasm.md), còn bảng đầy đủ (theo
nhóm, từng fixture, phương pháp, ghi nhận nhiễu) nằm trong [docs/BENCHMARK.md](../BENCHMARK.md#giai-đoạn-4--native-nodejs).
Phần còn lại của trang này là báo cáo bản wasm (bản build cuối; các giai đoạn trước được giữ làm lịch sử).

<!-- native-bench:highlights -->
- **bm-native so với bm-wasm (sync):** raw bằng 0.61× thời gian của wasm [0.62× / 0.61× / 0.61×] (nhanh hơn ở 250/250 fixture), PNG 0.67× [0.68× / 0.68× / 0.67×] (nhanh hơn ở 250/250).
- **bm-native so với takumi-native, cùng async:** raw 0.55× [0.55× / 0.55× / 0.55×] (bm nhanh hơn ở 244/250, từng fixture 0.12×–1.20×), PNG 0.54× [0.55× / 0.55× / 0.54×] (bm nhanh hơn ở 227/250, từng fixture 0.23×–2.54×). Với API sync của bm: raw 0.53×, PNG 0.57×. Dưới 1× = bm-native tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ đó ở từng lượt.
- **Thời gian CPU mỗi ảnh (cùng async):** PNG 1.98 ms bm-native so với 3.20 ms takumi-native (1.73 so với 1.98 lõi bận trong một lần render); raw 1.30 so với 1.41 ms. takumi-native chạy một phần của một lần render (các đoạn deflate PNG, blur, WebP, khung animation) trên thread pool rayon riêng; bm render một ảnh trên một thread (bm-native sync: 0.87 lõi với PNG).
- **Hai bản build của chính takumi:** takumi-native tốn 0.72× thời gian của takumi-wasm với raw và 0.55× với PNG.
- **Trùng byte:** bm-native và bm-wasm cho cùng byte ở 2626/2626 phép so trên 250 fixture (802 MB; 0 khác biệt).
- **Nhiễu:** geomean tuyệt đối raw / PNG lệch tới 4.70 % giữa các lượt (tải của tiến trình khác thay đổi trong lúc chạy), còn tỉ lệ giữa các engine, đo xen kẽ trong từng lượt, lệch nhiều nhất 1.50 %. Hãy đọc tỉ lệ; coi số ms tuyệt đối là ±2.35 %.
<!-- /native-bench:highlights -->

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

## Điều kiện đo

- Intel Core i3-10100 @ 3.6 GHz (8 luồng), 7.8 GB RAM, Windows 11, Node 26.13.0; đối chứng `@takumi-rs/wasm` 2.20.0
  (và `@takumi-rs/core` 2.20.0 native, chỉ để đo sàn nhiễu).
- 250 fixture trong `bench/fixtures/` (200 fixture tới hết giai đoạn 3, gồm 16 fixture layout inline của giai đoạn 3; thêm 50 fixture sau đó), cùng cây node và cùng 9 font TTF tĩnh đăng ký giống hệt nhau ở mọi engine.
- Thời gian: median của ≥ 20 lần lặp và ≥ 300 ms sau 3 lần khởi động, các engine chạy xen kẽ theo từng ca.
- Tương đương: so buffer `raw` của bm-engine với takumi-wasm. **identical** = 0 byte khác; **equivalent** =
  SSIM ≥ 0.99 và ≤ 0.5 % điểm ảnh vượt ngưỡng pixelmatch 0.1; **close** = SSIM ≥ 0.95 và ≤ 5 %; còn lại là
  **different**. SSIM lấy giá trị thấp hơn giữa SSIM độ sáng và SSIM RGB.
- Sàn nhiễu: takumi-native và takumi-wasm trùng từng byte ở mọi ca, nên mọi khác biệt của bm-engine là khác biệt thật.

## Số liệu chính

| Chỉ số | takumi-wasm (bản build cuối) | bm giai đoạn 1 | bm giai đoạn 2 (`full`) | bm giai đoạn 3 (`full`, 200 fixture) | bm cuối 0.1.0 (`full`, 250 fixture) |
|:--|--:|--:|--:|--:|--:|
| Tương đương trên toàn bộ fixture | — | 78 ca: 9 identical / 69 equivalent (+ 9 ca "gap": 5 different, 1 lỗi) | 184 ca: 74 / 109 / 1 close / 0 / 0 | 200 ca: 74 / 126 / 0 / 0 / 0 | **250 ca: 81 identical / 169 equivalent / 0 close / 0 different / 0 lỗi** |
| Render `raw`, trung bình nhân | 1.01 ms (250 ca) | 0.61× takumi (78 ca) | 0.65× (nhanh hơn ở 155/175) | 0.68× (0.69 ms; nhanh hơn ở 171/191) | **0.63×** (0.64 ms; nhanh hơn ở 229/250) |
| Render `png`, trung bình nhân | 2.95 ms | 0.72× | 0.48× (nhanh hơn ở 175/175) | 0.49× (1.59 ms; nhanh hơn ở 191/191) | **0.45×** (1.33 ms; nhanh hơn ở **248/250**) |
| Dung lượng file PNG, trung bình nhân | 1.00 | 0.75 | 0.76 | 0.78 | 0.80 |
| Cold start (init + font + PNG og-card đầu tiên) | 193.8 ms (native 44.2 ms) | 79.5 ms | 72.1 ms | 70.8 ms | **78.1 ms** |
| Bộ nhớ wasm sau 50 lần render PNG og-card | 10.6 MiB | 11.9 MiB (+12 %) | 11.6 MiB (+9 %) | 11.6 MiB (+9 %) | 11.6 MiB (**+9 %**) |
| Peak RSS của tiến trình | 105.0 MiB | 77.2 MiB | 88.6 MiB | 89.1 MiB | 92.3 MiB |
| Độ sâu cây tối đa | 512 | 128 | 512 | 512 | **512** |

## Kích thước binary

| Bản build | Thô | gzip -9 | brotli | so với takumi (4 234.9 KiB) |
|:--|--:|--:|--:|:--|
| `core` | 489.6 KiB | 229.5 KiB | 195.3 KiB | nhỏ hơn 8.7× |
| `standard` | 936.5 KiB | 465.1 KiB | 398.6 KiB | nhỏ hơn 4.5× |
| `full` | 1 143.6 KiB | 560.0 KiB | 470.8 KiB | nhỏ hơn 3.7× |
| Add-on WOFF | 84.4 KiB | 67.8 KiB | 65.5 KiB | — |
| giai đoạn 1 (một bản duy nhất) | 320.9 KiB | 147.1 KiB | 126.5 KiB | nhỏ hơn 13.2× |

Kích thước giai đoạn 2 là 428.5 / 849.6 / 1 070.0 KiB (nhỏ hơn 9.9× / 5.0× / 4.0×) và giai đoạn 3 là 454.5 / 877.5 / 1 099.8 KiB; công việc định dạng inline thêm khoảng 26–30 KB cho mỗi profile, các bản sửa sau đó thêm khoảng 33–56 KB nữa.
Chi phí từng tính năng (đo ở giai đoạn 2): [Profile và kích thước](profiles-and-size.md#chi-phí-biên-của-từng-tính-năng).

## Chỗ bm-engine còn thua

- **Bộ nhớ wasm: +9 %** (11.6 so với 10.6 MiB sau 50 lần render og-card). Phần còn lại là bộ đệm scratch
  của rasterizer, các layer cỡ canvas và việc cấp phát theo trang 64 KiB.
- **Nhóm `border-radius`, raw: 1.20×** takumi (1.18× ở lần đo giai đoạn 2: 1.00 so với 0.85 ms). Bản thân rasterizer đã được sửa
  (elip lớn 0.97 → 0.43 ms); phần còn lại là chi phí cố định mỗi khung (xoá canvas, bỏ premultiply, chép
  3 MB sang JS).
- **`text-stroke` raw 1.58×** và **`svg-image` raw 1.48×** (stroker và đường vẽ SVG chưa tối ưu);
  **`text-decoration` raw 1.12×**.
- Peak RSS tăng so với giai đoạn 1 (77 → 92 MiB) nhưng vẫn dưới takumi-wasm (105.0 MiB).

## Trình duyệt

`bench/browser` chạy engine trong Edge / Chrome headless qua `puppeteer-core` và so với Node. Báo cáo giai
đoạn 2 ghi nhận 78/78 lần render raw trùng từng byte với Node và PNG / WebP / JPEG giải mã đúng trong
trình duyệt. Lần chạy nhanh gần nhất (`bench/out/BROWSER.md`, Edge 157.0.4341.46, 12 ca) đạt: 12/12 lần
render raw trùng khớp, mọi lần giải mã PNG / WebP / JPEG đều đúng, 0 lỗi console, biên dịch theo luồng +
khởi tạo mất 20.4 ms.

## Tái lập kết quả

Từ một bản checkout mã nguồn (xem [Build từ mã nguồn](building-from-source.md)):

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

Ảnh của từng ca được ghi vào `bench/out/<id>/{takumi,bm,native,diff}.png`. Con số phụ thuộc vào máy; tỉ lệ
ổn định hơn thời gian tuyệt đối. Điều kiện đo, bảng theo từng nhóm tính năng và chi tiết các điểm thua đã
sửa nằm trong [báo cáo đầy đủ](../BENCHMARK.md).
