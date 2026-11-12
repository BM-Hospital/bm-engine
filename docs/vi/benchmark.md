# Tóm tắt benchmark

[English](../en/benchmark.md) · [Tiếng Việt](benchmark.md)

> **Báo cáo đầy đủ bằng tiếng Việt: [docs/BENCHMARK.md](../BENCHMARK.md)** (phần "Giai đoạn 3" ở đầu
> file là số liệu cuối cùng của 0.1.0, tiếp theo là giai đoạn 2; báo cáo giai đoạn 1 được giữ ở cuối). Số liệu từng fixture:
> [RESULTS_FULL.md](../RESULTS_FULL.md) và [results.json](../results.json).

Trang này chỉ tóm tắt các con số chính (số liệu cuối cùng của 0.1.0, giai đoạn 3). bm-engine (profile `full`) được so với `@takumi-rs/wasm` 2.20.0
trên 200 fixture dùng chung (i3-10100, Windows 11, Node 26.13, ngày 2026-11-12): 74 fixture identical (trùng từng byte) và
126 equivalent (tương đương: SSIM ≥ 0.99 và ≤ 0.5 % điểm ảnh lệch, chủ yếu ở mép khử răng cưa); 0 close, 0 different, 0 lỗi;
render PNG nhanh hơn ở 191/191 ca đo thời gian, render raw nhanh hơn ở 171/191 ca; cold start nhanh hơn 2.5×; binary nhỏ hơn 4–9×.
bm-engine vẫn dùng nhiều hơn takumi 9 % bộ nhớ wasm và chậm hơn ở vài ca raw.

## Addon native cho Node.js (giai đoạn 4)

Từ giai đoạn 4, `bm-engine` trên Node.js chạy bằng addon native khi có addon cho nền tảng, và tự động quay về bản
wasm khi không có. Bốn bản — bm-native, bm-wasm (`full`), takumi-native (`@takumi-rs/core`) và takumi-wasm — được đo
cùng lúc trên cùng 200 fixture. Các bảng dưới đây được sinh từ [results-native.json](../results-native.json) bởi
`node bench/run-native.mjs`; trang hướng dẫn là [Native so với WebAssembly](native-vs-wasm.md), còn bảng đầy đủ (theo
nhóm, từng fixture, phương pháp, ghi nhận nhiễu) nằm trong [docs/BENCHMARK.md](../BENCHMARK.md#giai-đoạn-4--native-nodejs).
Phần còn lại của trang này là báo cáo bản wasm của giai đoạn 3.

<!-- native-bench:highlights -->
- **bm-native so với bm-wasm (sync):** raw bằng 0.76× thời gian của wasm [0.77× / 0.75× / 0.80×] (nhanh hơn ở 192/200 fixture), PNG 0.67× [0.68× / 0.67× / 0.68×] (nhanh hơn ở 200/200).
- **bm-native so với takumi-native, cùng async:** raw 0.89× [0.90× / 0.88× / 0.95×] (bm nhanh hơn ở 136/200, từng fixture 0.22×–2.78×), PNG 0.68× [0.67× / 0.65× / 0.66×] (bm nhanh hơn ở 170/200, từng fixture 0.28×–2.21×). Với API sync của bm: raw 0.69×, PNG 0.66×. Dưới 1× = bm-native tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ đó ở từng lượt.
- **Thời gian CPU mỗi ảnh (cùng async):** PNG 3.29 ms bm-native so với 5.28 ms takumi-native (1.11 so với 1.45 lõi bận trong một lần render); raw 2.25 so với 2.30 ms. takumi-native chạy một phần của một lần render (các đoạn deflate PNG, blur, WebP, khung animation) trên thread pool rayon riêng; bm render một ảnh trên một thread (bm-native sync: 0.88 lõi với PNG).
- **Hai bản build của chính takumi:** takumi-native tốn 0.69× thời gian của takumi-wasm với raw và 0.48× với PNG.
- **Trùng byte:** bm-native và bm-wasm cho cùng byte ở 1457/1457 phép so trên 200 fixture (586 MB; 0 khác biệt).
- **Nhiễu:** geomean tuyệt đối raw / PNG lệch tới 40.1 % giữa các lượt (tải của tiến trình khác thay đổi trong lúc chạy), còn tỉ lệ giữa các engine, đo xen kẽ trong từng lượt, lệch nhiều nhất 17.9 %. Hãy đọc tỉ lệ; coi số ms tuyệt đối là ±20.1 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Chỉ số | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — API sync | 0.96 ±7.00 % ⚠ | 1.26 ±5.20 % ⚠ | không có API sync | — |
| raw RGBA, geomean ms — API async | 1.25 ±20.1 % ⚠ | — | 1.40 ±15.3 % ⚠ | 2.02 ±6.45 % ⚠ |
| PNG, geomean ms — API sync | 1.80 ±5.85 % ⚠ | 2.67 ±5.50 % ⚠ | không có API sync | — |
| PNG, geomean ms — API async | 1.83 ±11.8 % ⚠ | — | 2.71 ±11.1 % ⚠ | 5.63 ±5.45 % ⚠ |
| Thời gian CPU mỗi lần render PNG, ms trung bình (số lõi dùng) | 2.46 (0.88 lõi) | 3.19 (0.78 lõi) | 5.28 (1.45 lõi) | 7.29 (0.85 lõi) |
| Dung lượng PNG, geomean so với takumi | 0.78× | 0.78× | 1.00× | 1.00× |
| Cold start so với Node rỗng, median / p95 ms | 28.6 / 75.5 | 96.5 / 139 | 60.2 / 83.8 | 238 / 282 |
| RSS sau 1 → 10 lượt cả bộ fixture, MiB | 91.9 → 93.4 | 126 → 126 | 147 → 160 | 132 → 161 |
| RSS đỉnh, một PNG 4000×4000, MiB | 146 | 149 | 137 | 151 |
| Event loop: độ trễ lớn nhất của timer 1 ms, render nặng 2400×2400, ms | 299 (sync) · 3.90 (async) | 700 (sync) · 604 (async) | 15.3 (async) | 1 095 (async) |
| Event loop: như trên, animation 60 khung, ms | 5 376 (sync) · 6.50 (async) | 10 866 (sync) · 9 086 (async) | 30.1 (async) | 2 563 (async) |
| Thông lượng, og card PNG, 4 đồng thời, ảnh/s (cấu hình tốt nhất) | 177 (many K=4, UV 4) ⚠ | 119 (pool K=8) ⚠ | 170 (many K=2, UV 4) ⚠ | 78.5 (pool K=4) ⚠ |
| Thông lượng, 8 đồng thời, ảnh/s (cấu hình tốt nhất) | 247 (many K=8, UV 8) ⚠ | 157 (pool K=8) ⚠ | 200 (one, UV 8) ⚠ | 88.9 (pool K=8) ⚠ |

Geomean trên 200 fixture mà cả bốn engine đều render được; ± = nửa khoảng chênh giữa geomean của 3 lượt so với median của chúng; ⚠ = chênh quá 10 %. Cold start: median / p95 của 30 tiến trình mới trừ median của Node rỗng. Event loop, bộ nhớ và thông lượng là một lần đo; ở các dòng thông lượng ⚠ = tiến trình khác dùng trung bình hơn một lõi trong lúc đo.
<!-- /native-bench:summary -->

## Điều kiện đo

- Intel Core i3-10100 @ 3.6 GHz (8 luồng), 7.8 GB RAM, Windows 11, Node 26.13.0; đối chứng `@takumi-rs/wasm` 2.20.0
  (và `@takumi-rs/core` 2.20.0 native, chỉ để đo sàn nhiễu).
- 200 fixture trong `bench/fixtures/` (gồm 16 fixture layout inline của giai đoạn 3), cùng cây node và cùng 9 font TTF tĩnh đăng ký giống hệt nhau ở mọi engine.
- Thời gian: median của ≥ 20 lần lặp và ≥ 300 ms sau 3 lần khởi động, các engine chạy xen kẽ theo từng ca.
- Tương đương: so buffer `raw` của bm-engine với takumi-wasm. **identical** = 0 byte khác; **equivalent** =
  SSIM ≥ 0.99 và ≤ 0.5 % điểm ảnh vượt ngưỡng pixelmatch 0.1; **close** = SSIM ≥ 0.95 và ≤ 5 %; còn lại là
  **different**. SSIM lấy giá trị thấp hơn giữa SSIM độ sáng và SSIM RGB.
- Sàn nhiễu: takumi-native và takumi-wasm trùng từng byte ở mọi ca, nên mọi khác biệt của bm-engine là khác biệt thật.

## Số liệu chính

| Chỉ số | takumi-wasm | bm giai đoạn 1 | bm giai đoạn 2 (`full`) | bm cuối 0.1.0 (`full`) |
|:--|--:|--:|--:|--:|
| Tương đương trên toàn bộ fixture | — | 78 ca: 9 identical / 69 equivalent (+ 9 ca "gap": 5 different, 1 lỗi) | 184 ca: 74 / 109 / 1 close / 0 / 0 | **200 ca: 74 identical / 126 equivalent / 0 close / 0 different / 0 lỗi** |
| Render `raw`, trung bình nhân | 1.02 ms (191 ca) | 0.61× takumi (78 ca) | 0.65× (nhanh hơn ở 155/175) | **0.68×** (0.69 ms; nhanh hơn ở 171/191) |
| Render `png`, trung bình nhân | 3.26 ms | 0.72× | 0.48× (nhanh hơn ở 175/175) | **0.49×** (1.59 ms; nhanh hơn ở **191/191**) |
| Dung lượng file PNG, trung bình nhân | 1.00 | 0.75 | 0.76 | 0.78 |
| Cold start (init + font + PNG og-card đầu tiên) | 178.4 ms (native 43.8 ms) | 79.5 ms | 72.1 ms | **70.8 ms** |
| Bộ nhớ wasm sau 50 lần render PNG og-card | 10.6 MiB | 11.9 MiB (+12 %) | 11.6 MiB (+9 %) | 11.6 MiB (**+9 %**) |
| Peak RSS của tiến trình | 107.9 MiB | 77.2 MiB | 88.6 MiB | 89.1 MiB |
| Độ sâu cây tối đa | 512 | 128 | 512 | **512** |

## Kích thước binary

| Bản build | Thô | gzip -9 | brotli | so với takumi (4 234.9 KiB) |
|:--|--:|--:|--:|:--|
| `core` | 454.5 KiB | 211.5 KiB | 180.3 KiB | nhỏ hơn 9.3× |
| `standard` | 877.5 KiB | 435.2 KiB | 374.5 KiB | nhỏ hơn 4.8× |
| `full` | 1 099.8 KiB | 538.2 KiB | 453.4 KiB | nhỏ hơn 3.9× |
| Add-on WOFF | 84.2 KiB | 67.7 KiB | 65.5 KiB | — |
| giai đoạn 1 (một bản duy nhất) | 320.9 KiB | 147.1 KiB | 126.5 KiB | nhỏ hơn 13.2× |

Kích thước giai đoạn 2 là 428.5 / 849.6 / 1 070.0 KiB (nhỏ hơn 9.9× / 5.0× / 4.0×); công việc định dạng inline thêm khoảng 26–30 KB cho mỗi profile.
Chi phí từng tính năng (đo ở giai đoạn 2): [Profile và kích thước](profiles-and-size.md#chi-phí-biên-của-từng-tính-năng).

## Chỗ bm-engine còn thua

- **Bộ nhớ wasm: +9 %** (11.6 so với 10.6 MiB sau 50 lần render og-card). Phần còn lại là bộ đệm scratch
  của rasterizer, các layer cỡ canvas và việc cấp phát theo trang 64 KiB.
- **Nhóm `border-radius`, raw: 1.20×** takumi (1.18× ở lần đo giai đoạn 2: 1.00 so với 0.85 ms). Bản thân rasterizer đã được sửa
  (elip lớn 0.97 → 0.43 ms); phần còn lại là chi phí cố định mỗi khung (xoá canvas, bỏ premultiply, chép
  3 MB sang JS).
- **`text-stroke` raw 1.61×** và **`svg-image` raw 1.46×** (stroker và đường vẽ SVG chưa tối ưu);
  **`text-decoration` raw 1.10×**.
- Peak RSS tăng so với giai đoạn 1 (77 → 89 MiB) nhưng vẫn dưới takumi-wasm (107.9 MiB).

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
