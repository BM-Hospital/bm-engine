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

## Addon native cho Node.js (giai đoạn 4)

Từ giai đoạn 4, `bm-engine` trên Node.js chạy bằng addon native khi có addon cho nền tảng, và tự động quay về bản
wasm khi không có. Bốn bản — bm-native, bm-wasm (`full`), takumi-native (`@takumi-rs/core`) và takumi-wasm — được đo
cùng lúc trên cùng 250 fixture. Các bảng dưới đây được sinh từ [results-native.json](../results-native.json) bởi
`node bench/run-native.mjs`; trang hướng dẫn là [Native so với WebAssembly](native-vs-wasm.md), còn bảng đầy đủ (theo
nhóm, từng fixture, phương pháp, ghi nhận nhiễu) nằm trong [docs/BENCHMARK.md](../BENCHMARK.md#giai-đoạn-4--native-nodejs).
Phần còn lại của trang này là báo cáo bản wasm (bản build cuối; các giai đoạn trước được giữ làm lịch sử).

<!-- native-bench:highlights -->
- **bm-native so với bm-wasm (sync):** raw bằng 0.60× thời gian của wasm [0.60× / 0.59× / 0.60×] (nhanh hơn ở 250/250 fixture), PNG 0.68× [0.68× / 0.68× / 0.68×] (nhanh hơn ở 250/250).
- **bm-native so với takumi-native, cùng async:** raw 0.55× [0.55× / 0.55× / 0.55×] (bm nhanh hơn ở 244/250, từng fixture 0.13×–1.21×), PNG 0.56× [0.56× / 0.58× / 0.56×] (bm nhanh hơn ở 227/250, từng fixture 0.23×–2.28×). Với API sync của bm: raw 0.50×, PNG 0.56×. Dưới 1× = bm-native tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ đó ở từng lượt.
- **Thời gian CPU mỗi ảnh (cùng async):** PNG 2.32 ms bm-native so với 3.81 ms takumi-native (1.47 so với 1.78 lõi bận trong một lần render); raw 1.42 so với 1.71 ms. takumi-native chạy một phần của một lần render (các đoạn deflate PNG, blur, WebP, khung animation) trên thread pool rayon riêng; bm render một ảnh trên một thread (bm-native sync: 0.91 lõi với PNG).
- **Hai bản build của chính takumi:** takumi-native tốn 0.75× thời gian của takumi-wasm với raw và 0.56× với PNG.
- **Trùng byte:** bm-native và bm-wasm cho cùng byte ở 1810/1810 phép so trên 250 fixture (637 MB; 0 khác biệt).
- **Nhiễu:** geomean tuyệt đối raw / PNG lệch tới 33.4 % giữa các lượt (tải của tiến trình khác thay đổi trong lúc chạy), còn tỉ lệ giữa các engine, đo xen kẽ trong từng lượt, lệch nhiều nhất 3.70 %. Hãy đọc tỉ lệ; coi số ms tuyệt đối là ±16.7 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Chỉ số | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — API sync | 0.51 ±15.5 % ⚠ | 0.85 ±16.1 % ⚠ | không có API sync | — |
| raw RGBA, geomean ms — API async | 0.56 ±15.7 % ⚠ | — | 1.02 ±15.3 % ⚠ | 1.36 ±15.8 % ⚠ |
| PNG, geomean ms — API sync | 1.05 ±14.6 % ⚠ | 1.56 ±15.0 % ⚠ | không có API sync | — |
| PNG, geomean ms — API async | 1.06 ±16.7 % ⚠ | — | 1.89 ±14.5 % ⚠ | 3.36 ±15.8 % ⚠ |
| Thời gian CPU mỗi lần render PNG, ms trung bình (số lõi dùng) | 1.42 (0.91 lõi) | 1.78 (0.77 lõi) | 3.81 (1.78 lõi) | 4.08 (0.86 lõi) |
| Dung lượng PNG, geomean so với takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start so với Node rỗng, median / p95 ms | 31.3 / 69.2 | 99.9 / 138 | 50.9 / 97.5 | 238 / 304 |
| RSS sau 1 → 10 lượt cả bộ fixture, MiB | 94.7 → 96.0 | 132 → 156 | 102 → 139 | 140 → 176 |
| RSS đỉnh, một PNG 4000×4000, MiB | 143 | 149 | 135 | 151 |
| Event loop: độ trễ lớn nhất của timer 1 ms, render nặng 2400×2400, ms | 227 (sync) · 1.50 (async) | 455 (sync) · 473 (async) | 7.30 (async) | 819 (async) |
| Event loop: như trên, animation 60 khung, ms | 476 (sync) · 1.20 (async) | 969 (sync) · 954 (async) | 21.6 (async) | 2 072 (async) |
| Thông lượng, og card PNG, 4 đồng thời, ảnh/s (cấu hình tốt nhất) | 312 (many K=4, UV 4) ⚠ | 233 (pool K=4) ⚠ | 270 (one, UV 8) ⚠ | 137 (pool K=8) ⚠ |
| Thông lượng, 8 đồng thời, ảnh/s (cấu hình tốt nhất) | 402 (many K=8, UV 8) ⚠ | 270 (pool K=8) ⚠ | 316 (one, UV 8) ⚠ | 180 (pool K=8) ⚠ |

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
| `core` | 487.6 KiB | 228.4 KiB | 194.3 KiB | nhỏ hơn 8.7× |
| `standard` | 934.4 KiB | 463.7 KiB | 398.0 KiB | nhỏ hơn 4.5× |
| `full` | 1 141.5 KiB | 559.0 KiB | 469.8 KiB | nhỏ hơn 3.7× |
| Add-on WOFF | 84.2 KiB | 67.7 KiB | 65.5 KiB | — |
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
