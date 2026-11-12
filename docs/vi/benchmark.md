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
| `core` | 454.9 KiB | 211.6 KiB | 180.4 KiB | nhỏ hơn 9.3× |
| `standard` | 878.1 KiB | 435.5 KiB | 374.6 KiB | nhỏ hơn 4.8× |
| `full` | 1 100.9 KiB | 538.3 KiB | 453.7 KiB | nhỏ hơn 3.8× |
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
