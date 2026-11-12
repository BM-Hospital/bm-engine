# bm-engine (Zig) so với takumi 2.20.0 — benchmark và kiểm tra tương đương

> **Giai đoạn 3 (2026-11-12)** — số liệu cuối cùng của 0.1.0 ở ngay dưới; giai đoạn 2 được giữ làm lịch sử (số của giai đoạn 2 được ghi rõ). Báo cáo giai đoạn 1 được giữ nguyên ở cuối file để đối chiếu.
> Số liệu từng fixture: [RESULTS_FULL.md](RESULTS_FULL.md), [results.json](results.json). Ảnh: `bench/out/<id>/`.

## Giai đoạn 3 — trạng thái cuối cùng của 0.1.0

Đo trên bản build cuối (sau `wasm-opt`), so với `@takumi-rs/wasm` 2.20.0.

- **Kích thước (KiB, raw / gzip -9 / brotli):** core 454.5 / 211.5 / 180.3; standard 877.5 / 435.2 / 374.5; full 1 099.8 / 538.2 / 453.4;
  add-on WOFF 84.2 / 67.7 / 65.5; takumi-wasm 2.20: 4 234.9 / 1 860.9 / 1 409.3. So với takumi (raw): core nhỏ hơn 9.3×, standard 4.8×, full 3.9×.
  (Số giai đoạn 2: 428.5 / 849.6 / 1 070.0 và 9.9× / 5.0× / 4.0×.) Công việc dòng inline thêm khoảng 26–30 KB cho mỗi profile.
- **Tương đương:** **200 fixture: 74 identical, 126 equivalent, 0 close, 0 different, 0 lỗi** (giai đoạn 2: 184 = 74 / 109 / 1 close).
  Ca `layout2-float-wrap` trước đây "close" nay là equivalent. Cổng layout measure-tree: 197/197 ca không-transform khớp takumi trong 0.001 px.
- **Hiệu năng (geomean trên 191 ca không-gap):** raw 0.69 ms so với takumi 1.02 ms = 0.68× (nhanh hơn ở 171/191 ca, chậm hơn ở 20);
  png 1.59 ms so với 3.26 ms = 0.49× (nhanh hơn ở 191/191); tỉ lệ dung lượng PNG 0.78. Cold start tổng (init + font + og-card PNG đầu tiên):
  bm 70.8 ms so với takumi-wasm 178.4 ms (takumi-native 43.8 ms). Bộ nhớ wasm sau 50 lần render og-card PNG: bm 11.6 MiB so với 10.6 MiB (+9 %);
  peak RSS bm 89.1 MiB so với takumi-wasm 107.9 MiB. Unit test: 402/402.
- **Hai khoảng trống layout đã xong:** (a) chữ chảy quanh float (hộp dòng ngắn lại cạnh float và nở lại bên dưới; float trong nội dung inline; RTL);
  (b) định dạng inline thật cho nội dung hỗn hợp: inline nguyên tử (inline-block / inline-flex / inline-grid / ảnh inline) tham gia ngắt dòng giữa dòng
  với mọi giá trị `vertical-align`; padding / viền / margin ngang của span đẩy chữ (mép fragment đầu/cuối, `box-decoration-break: clone`),
  `white-space` theo từng span, `<br>` trong nội dung hỗn hợp, strut theo từng hộp (span cỡ chữ lớn hơn làm dòng cao lên khi `line-height` tường minh, như Blink).
  Fixture mới: `float-text` (7 ca), `inline-flow` (5), `inline-box-model` (4) — cả 16 ca equivalent với takumi (SSIM ≥ 0.9999).
- **Gói npm cuối (`npm pack`):** 28 file, 1 293.8 KiB nén, 2 655.8 KiB giải nén (có `README.vi.md`); `npm run test:pack` 15/15 đạt
  (Node ESM/CJS, TypeScript ×4 cấu hình, build Vite 8.3.8 + Edge 157 headless, esbuild, mô phỏng workerd). Test playground đạt trên cả ba profile (dev + dist).

Khoảng trống còn lại ở layout inline:

- Hộp inline hướng RTL bao quanh chữ LTR đặt mép start/end sai phía thị giác; fragment của hộp chưa được tách qua các đoạn bidi bị sắp xếp lại.
- RTL + `white-space: pre-wrap`: khoảng trắng treo.
- line-clamp / `-webkit-box` quanh float.
- Block-in-inline (span chứa block) vẫn biến span thành block.
- Thứ tự vẽ float chỉ xấp xỉ (float vẽ sau nội dung in-flow của stacking context).
- `text-wrap: balance/pretty` quay về ngắt dòng tham lam trong đoạn có hộp inline / inline nguyên tử hoặc cạnh float.
- padding/margin theo % trên hộp inline được tính bằng 0.
- Chuỗi inline-block lồng nhau giới hạn khoảng 255 cấp (lỗi "nested too deeply" rõ ràng), trong khi lồng thường hỗ trợ 512.

## Giai đoạn 2 — tóm tắt

Điều kiện đo như giai đoạn 1 (i3-10100, Node 26.13, `@takumi-rs/wasm` 2.20.0), bản bm **full** (mọi tính năng), 184 fixture
(87 cũ + 97 mới cho các tính năng vừa port). Sàn nhiễu vẫn bằng 0 (takumi-native ≡ takumi-wasm từng byte).

| Chỉ số | takumi-wasm | bm giai đoạn 1 | bm giai đoạn 2 (full) |
|:--|--:|--:|--:|
| Tương đương trên toàn bộ fixture | — | 78 ca: 9 identical / 69 equivalent (+9 ca "gap": 5 different, 1 lỗi) | **184 ca: 74 identical / 109 equivalent / 1 close / 0 different / 0 lỗi** |
| Render `raw`, geomean | 1.09 ms (175 ca) | 0.61× takumi (78 ca) | **0.65×** (nhanh hơn ở 155/175 ca) |
| Render `png`, geomean | 3.41 ms | 0.72× | **0.48×** (nhanh hơn ở **175/175** ca) |
| Dung lượng PNG, geomean | 1.00 | 0.75 | 0.76 |
| Cold start tổng (init + font + render og-card PNG đầu tiên) | 186.9 ms | 79.5 ms | **72.1 ms** |
| Bộ nhớ wasm sau 50 lần render og-card PNG | 10.6 MiB | 11.9 MiB (+12 %) | 11.6 MiB (**+9 %**) |
| Peak RSS tiến trình | 99.4 MiB | 77.2 MiB | 88.6 MiB |
| Độ sâu cây tối đa | 512 | 128 | **512** |

### Kích thước theo cấu hình build (sau `wasm-opt -Oz`; số cuối cùng của giai đoạn 3 — giai đoạn 2 là 428.5 / 849.6 / 1 070.0)

| Cấu hình | raw KiB | gzip -9 | brotli | so với takumi (4 234.9 KiB) | Gồm |
|:--|--:|--:|--:|:--|:--|
| `core` | **454.5** | 211.5 | 180.3 | nhỏ hơn 9.3× | node JSON + style inline, var()/calc, flex/grid/block/absolute, hàng inline, TTF/TTC tĩnh + OpenType shaper mặc định, viền mọi kiểu/outline/trang trí chữ, PNG/JPEG vào, PNG/JPEG/WebP/raw ra |
| `standard` | **877.5** | 435.2 | 374.5 | nhỏ hơn 4.8× | core + stylesheet/selector, Tailwind, HTML, ảnh SVG, WOFF/WOFF2, font biến thiên, CFF, clip-path/mask/blend/backdrop, màu oklch/lab/color-mix, bảng, float, WebP/GIF vào, text-wrap balance |
| `full` (mặc định) | **1 099.8** | 538.2 | 453.4 | nhỏ hơn 3.9× | standard + chữ phức (bidi, Ả Rập, Hebrew, Indic, Thái), emoji màu, animation + renderAnimation, VP8 lossy, ảnh động, ICO, renderSvg |
| add-on `bm_woff.wasm` | 84.2 | 67.7 | 65.5 | — | giải mã WOFF/WOFF2 tải theo yêu cầu cho bản core |
| giai đoạn 1 (một bản duy nhất) | 320.9 | 147.1 | 126.5 | nhỏ hơn 13.2× | tập tính năng giai đoạn 1 |

Chi phí biên từng tính năng (đo ở giai đoạn 2, trước công việc dòng inline vốn thêm khoảng 26–30 KB cho mỗi profile; KB sau wasm-opt, thêm vào core / bỏ khỏi full): css 62.5 / 60.7 · tw 37.5 / 32.2 · html 27.8 / 27.2 ·
ảnh SVG 100.6 / 102.7 · woff 80.1 / 79.5 (52 KB là từ điển brotli bắt buộc) · font biến thiên 15.8 / 14.4 · cff 9.7 / 8.3 ·
effects 17.4 / 17.6 · màu hiện đại 12.1 / 10.1 · bảng 48.1 / 46.1 · float 6.5 / 4.8 · emoji màu 30.9 / 35.9 ·
chữ phức 52.2 / 53.0 · animation 42.0 / 52.9 · codec phụ 0.8 / 33.5 · renderSvg 57.0 / 59.1.

**Vì sao core không về được 321 KiB:** phần lõi đã lớn lên thật (+113 KB mã): viền/outline/trang trí chữ +31 KB, engine GSUB/GPOS
đầy đủ +26 KB, style (var(), calc, grid đặt tên, thuộc tính logic) +24 KB, raster (AA trùng tiny-skia, stroker) +17 KB, layout +9 KB,
DOM/measure +20 KB; bù lại core bỏ WebP/GIF vào (−36 KB). Cắt tiếp nghĩa là đổi thuật toán hoặc đổi kết quả render của core.

**Tải lười (lazy add-on):** chỉ làm được cho phần là hàm thuần byte-vào/byte-ra — đã làm cho WOFF/WOFF2 (`js/addons.mjs`,
đầu ra trùng từng byte với bản tích hợp). Tailwind không tách được vì nó là một tầng cascade riêng, sinh pseudo-element và cần thông tin
cấu trúc phần tử bên trong engine. SVG/CSS/shaping không tách được vì đọc-ghi trực tiếp cấu trúc nội bộ (ComputedStyle, cây layout,
cache glyph) trong cùng bộ nhớ tuyến tính — cần một dynamic linker thật cho wasm.

## Các điểm thua ở giai đoạn 1: nguyên nhân và kết quả sửa

| # | Điểm thua | Nguyên nhân gốc (đã profile) | Sửa được? | Trước → sau |
|:--|:--|:--|:--|:--|
| 1 | `border-radius` raw chậm hơn (hình elip lớn) | `fillPath` dựng mặt nạ A8 trên cả bbox rồi `blendSolid` đọc lại từng byte coverage (pass mask-rồi-blend 0.78 ms so với 0.2 ms quét cạnh) | **Một phần.** Bỏ mặt nạ trung gian: phát span thẳng từ hàng tích luỹ | elip 1200×630: 0.97 → 0.43 ms. Nhưng nhóm fixture vẫn 1.18× takumi (1.00 vs 0.85 ms): phần còn lại là chi phí cố định mỗi khung (xoá canvas, un-premultiply, copy 3 MB sang JS) chứ không phải rasterizer |
| 2 | PNG chậm hơn ở ảnh nhiều chữ | Chuỗi băm deflate bị giới hạn bởi độ trễ bộ nhớ (hash 4 byte trên dữ liệu chỉ mục → chuỗi dài, yếu); thử 3 chiến lược lọc × 51 hàng; đếm palette có nhánh sai dự đoán ở mép AA; Adler-32 chậm | **Có** | bước PNG −34…−62 %: text-vietnamese 8.41 → 4.33 ms (takumi 8.32); fonts-weights-italic 11.27 → 6.10 (10.55); card-og 21.5 → 15.2 (22.7). Giờ PNG nhanh hơn takumi ở 175/175 ca |
| 3 | WebP lossless ảnh chụp chậm 2.1× | LZ77 chuỗi băm trên phần dư của ảnh chụp chiếm ~65 % thời gian và còn làm file **lớn hơn** 9 % | **Có** — tự nhận biết nội dung kiểu ảnh chụp, chỉ dùng copy trái/trên | img-photo-bg: 45.9 → 19.9 ms (takumi 21.3), 414 → 376 KB (takumi 482 KB) |
| 4 | Bộ nhớ wasm +12 % | Scratch của bộ nén PNG (bản sao ảnh đã lọc), layer nhóm cỡ canvas, mặt nạ hi-res của glyph không được giải phóng, upload cả ảnh không dùng | **Một phần** — PNG nén theo luồng, canvas ngoài arena, scratch glyph riêng, chỉ upload ảnh được tham chiếu | 11.9 → 11.6 MiB (takumi 10.6): còn **+9 %**. Phần còn lại: bộ đệm scratch của rasterizer + layer cỡ canvas + cấp phát theo trang 64 KiB; chưa giảm tiếp |
| 5 | Viền dashed/dotted vẽ thành nét liền | Chưa cài | **Có** — port `BoxBorderPainter` của Blink/takumi | card-flat-ui SSIM 0.9949 → 0.9998; nét đứt cạnh thẳng trùng takumi; cạnh **bo tròn** còn lệch pha ~0.1 px mỗi góc (0.08–0.25 % px) |
| + | Mép khử răng cưa không trùng byte | AA theo diện tích chính xác ≠ siêu lấy mẫu 4×4 của tiny-skia; và `div_255` của takumi lệch 1 ở 126/65536 tích | **Có** — port bộ quét siêu lấy mẫu (232/232 hình thử trùng từng byte) và công thức `div_255` | fixture identical: 9 → 74; sai khác trung bình ở ca chữ ~0.1 → ~0.005 |

Điểm thua **còn lại** sau giai đoạn 2: bộ nhớ wasm +9 %; nhóm `border-radius` raw 1.18×; `text-stroke` raw 1.58× và `svg-image` raw 1.55×
(đường stroker và SVG chưa tối ưu); `text-decoration` 1.07×; peak RSS tăng so với giai đoạn 1 (77 → 89 MiB, vẫn dưới takumi 99 MiB).

## Tính năng đã port ở giai đoạn 2 và mức tương đương

| Tính năng | Kết quả kiểm chứng với takumi |
|:--|:--|
| Stylesheet / selector / cascade, `@media`, `@layer`, `@supports`, nesting, `var()` | 252/252 node khớp luật thắng; 4 fixture: 1 identical, 3 equivalent |
| Tailwind `tw` | 656/657 chuỗi class khớp takumi; 4 fixture: 2 identical, 2 equivalent |
| HTML đầu vào + preset UA, `::before` / `::after` | 55/58 mẫu khớp cấu trúc cây; 8 fixture equivalent |
| Màu oklch / lab / lch / color() / color-mix, không gian nội suy gradient | 495/495 màu trùng 8-bit; gradient lệch tối đa 1–2 mức |
| WOFF / WOFF2 (brotli viết lại từ đầu) | 17/19 font WOFF2 của takumi trùng từng byte với bộ tham chiếu; 2 font khác 1 bit cờ theo đặc tả mới |
| Font biến thiên (fvar/avar/gvar/HVAR/MVAR), CFF/CFF2, TTC mọi face | 1 400 phép so bề rộng lệch ≤ 1/64 px; 196/196 chiều cao dòng |
| Shaping đầy đủ: GSUB 1–8, GPOS 1–9, bidi UAX#9, Ả Rập, Hebrew, Devanagari, Bengali, Thái, tiếng Việt tổ hợp, `text-wrap: balance/pretty` | bề rộng khớp 0.000 px ở mọi nhóm; bidi 91 679/91 679 ca chuẩn; balance/pretty 216/216; 825/825 ca Latin cũ giữ nguyên |
| Emoji màu: COLR v0/v1, CBDT, sbix | SSIM ≥ 0.991 (takumi **không** vẽ được COLR v1 — phần này vượt takumi, so với Chrome) |
| Ảnh SVG (parser + renderer riêng) | 397/422 SVG của takumi identical/equivalent, SSIM trung bình 0.9956; nhanh hơn 3–10× |
| `renderSvg` (cây node → SVG) | rasterize SVG của hai bên bằng cùng bộ rasterizer: 175/179 fixture identical/equivalent |
| Bảng (auto/fixed, span, collapse, caption), float, inline-block, grid đặt tên/areas, độ sâu 512 | layout: 339/352 bảng, 138/138 float, 168/179 inline; 19 fixture: 18 equivalent/identical, 1 close (giai đoạn 2; `layout2-float-wrap` nay là equivalent) |
| Viền dashed/dotted/double/groove/ridge/inset/outset, outline | 5 fixture: 1 identical, 4 equivalent |
| clip-path, mask-image, mix-blend-mode, background-blend-mode, background-clip:text, drop-shadow, backdrop-filter, text-stroke, trang trí chữ, hộp inline | 12 fixture: 6 identical, 6 equivalent |
| CSS animation theo `timeMs`, `renderAnimation` (WebP/APNG/GIF) | 42 fixture: 32 identical, 10 equivalent; số khung và độ trễ khớp chính xác |
| WebP lossy (VP8), GIF/APNG/WebP động (giải mã + mã hoá), ICO | VP8 trùng libwebp từng bit; khung động trùng `anim_dump` |
| Trình duyệt thật (Edge 157 headless) | 78/78 ca raw trùng từng byte với Node; PNG/WebP/JPEG giải mã đúng trong trình duyệt; takumi cũng chạy được trong Edge để so thời gian |

## Bảng theo nhóm tính năng (giai đoạn 2, bản full)

| Tính năng | số ca | raw: takumi-wasm ms | raw: bm ms | bm/takumi | png: takumi-wasm ms | png: bm ms | bm/takumi | PNG bytes bm/takumi | takumi-native raw ms | tương đương (identical/equivalent/close/different/error) | SSIM thấp nhất | % px lệch (TB) |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--|--:|--:|
| colors | 5 | 1.41 | 0.90 | 0.63 | 3.91 | 1.51 | 0.39 | 0.65 | 1.15 | 2/3/0/0/0 | 1.0000 | 0.000 |
| flex | 5 | 1.19 | 1.11 | 0.93 | 4.58 | 2.06 | 0.45 | 0.67 | 1.24 | 5/0/0/0/0 | 1.0000 | 0.000 |
| sizing | 5 | 0.90 | 0.86 | 0.95 | 4.49 | 2.09 | 0.47 | 0.40 | 1.06 | 5/0/0/0/0 | 1.0000 | 0.000 |
| absolute | 3 | 1.05 | 0.89 | 0.85 | 5.32 | 2.25 | 0.42 | 0.55 | 0.99 | 2/1/0/0/0 | 1.0000 | 0.000 |
| borders | 3 | 1.37 | 1.09 | 0.80 | 4.17 | 2.03 | 0.49 | 0.61 | 1.11 | 3/0/0/0/0 | 1.0000 | 0.000 |
| border-radius | 4 | 0.85 | 1.00 | 1.18 | 4.10 | 1.84 | 0.45 | 0.83 | 0.94 | 4/0/0/0/0 | 1.0000 | 0.000 |
| linear-gradient | 4 | 3.90 | 2.26 | 0.58 | 17.08 | 6.55 | 0.38 | 0.65 | 3.02 | 1/3/0/0/0 | 1.0000 | 0.000 |
| radial-gradient | 3 | 4.79 | 1.78 | 0.37 | 24.77 | 12.00 | 0.48 | 0.58 | 4.07 | 0/3/0/0/0 | 1.0000 | 0.000 |
| box-shadow | 4 | 5.84 | 3.30 | 0.56 | 15.74 | 7.59 | 0.48 | 0.98 | 4.15 | 2/2/0/0/0 | 1.0000 | 0.000 |
| opacity | 4 | 5.23 | 2.26 | 0.43 | 9.06 | 3.48 | 0.38 | 0.81 | 2.83 | 0/4/0/0/0 | 1.0000 | 0.000 |
| overflow | 3 | 1.61 | 1.00 | 0.62 | 5.46 | 2.07 | 0.38 | 0.77 | 1.43 | 1/2/0/0/0 | 1.0000 | 0.000 |
| transform | 3 | 3.02 | 1.67 | 0.55 | 6.37 | 2.71 | 0.43 | 0.90 | 2.69 | 0/3/0/0/0 | 0.9995 | 0.026 |
| text-single-line | 3 | 1.49 | 0.92 | 0.62 | 4.74 | 2.27 | 0.48 | 0.99 | 1.50 | 0/3/0/0/0 | 1.0000 | 0.001 |
| text-paragraph | 5 | 2.20 | 1.43 | 0.65 | 6.88 | 3.56 | 0.52 | 0.91 | 2.03 | 0/5/0/0/0 | 1.0000 | 0.000 |
| fonts | 2 | 2.71 | 1.69 | 0.63 | 8.82 | 4.65 | 0.53 | 0.99 | 2.55 | 0/2/0/0/0 | 1.0000 | 0.008 |
| text-i18n | 2 | 2.34 | 1.56 | 0.67 | 7.93 | 4.05 | 0.51 | 1.01 | 2.33 | 0/2/0/0/0 | 1.0000 | 0.001 |
| text-truncation | 3 | 1.50 | 0.90 | 0.60 | 4.16 | 1.78 | 0.43 | 0.92 | 1.35 | 0/3/0/0/0 | 1.0000 | 0.000 |
| images | 5 | 4.66 | 1.77 | 0.38 | 28.56 | 17.08 | 0.60 | 1.00 | 3.60 | 0/5/0/0/0 | 0.9994 | 0.000 |
| grid | 4 | 1.61 | 1.26 | 0.78 | 5.54 | 2.27 | 0.41 | 0.70 | 1.59 | 0/4/0/0/0 | 1.0000 | 0.000 |
| og-card | 2 | 4.24 | 2.41 | 0.57 | 13.41 | 9.23 | 0.69 | 1.00 | 3.32 | 0/2/0/0/0 | 1.0000 | 0.000 |
| blog-card | 2 | 10.51 | 6.82 | 0.65 | 31.14 | 16.47 | 0.53 | 0.95 | 6.26 | 0/2/0/0/0 | 0.9998 | 0.003 |
| stress | 3 | 16.11 | 11.84 | 0.73 | 36.71 | 24.00 | 0.65 | 0.98 | 14.07 | 1/2/0/0/0 | 1.0000 | 0.000 |
| text-shadow | 1 | 1.00 | 1.00 | 1.01 | 4.35 | 3.95 | 0.91 | 1.03 | 0.72 | 0/1/0/0/0 | 1.0000 | 0.001 |
| known-gaps | 9 | 0.57 | 0.32 | 0.56 | 2.03 | 0.82 | 0.40 | 0.71 | 0.43 | 3/6/0/0/0 | 0.9994 | 0.014 |
| filter | 1 | 1.77 | 1.30 | 0.74 | 4.89 | 3.09 | 0.63 | 0.98 | 1.19 | 1/0/0/0/0 | 1.0000 | 0.000 |
| aa-exact | 2 | 0.61 | 0.37 | 0.61 | 1.57 | 0.84 | 0.54 | 0.98 | 0.46 | 1/1/0/0/0 | 1.0000 | 0.000 |
| dashed-border | 1 | 2.40 | 1.34 | 0.56 | 3.35 | 1.67 | 0.50 | 0.91 | 1.39 | 0/1/0/0/0 | 0.9997 | 0.077 |
| dotted-border | 1 | 2.82 | 1.50 | 0.53 | 3.65 | 1.83 | 0.50 | 0.91 | 1.57 | 0/1/0/0/0 | 0.9987 | 0.248 |
| double-3d-border | 1 | 0.60 | 0.49 | 0.81 | 1.40 | 0.70 | 0.50 | 0.83 | 0.46 | 1/0/0/0/0 | 1.0000 | 0.000 |
| mixed-border | 1 | 1.07 | 0.71 | 0.66 | 1.94 | 1.05 | 0.54 | 0.92 | 0.62 | 0/1/0/0/0 | 1.0000 | 0.000 |
| outline | 1 | 1.53 | 0.82 | 0.54 | 2.64 | 1.18 | 0.45 | 0.94 | 0.93 | 0/1/0/0/0 | 0.9996 | 0.068 |
| clip-path | 1 | 0.87 | 0.63 | 0.72 | 5.44 | 1.95 | 0.36 | 0.73 | 0.58 | 1/0/0/0/0 | 1.0000 | 0.000 |
| mask | 1 | 1.57 | 1.12 | 0.71 | 6.32 | 2.29 | 0.36 | 0.70 | 1.04 | 1/0/0/0/0 | 1.0000 | 0.000 |
| bg-clip-text | 1 | 2.63 | 0.44 | 0.17 | 5.36 | 2.16 | 0.40 | 1.00 | 1.83 | 0/1/0/0/0 | 1.0000 | 0.000 |
| mix-blend | 1 | 1.80 | 1.23 | 0.69 | 7.64 | 4.15 | 0.54 | 0.95 | 1.03 | 1/0/0/0/0 | 1.0000 | 0.000 |
| bg-blend | 1 | 4.92 | 0.99 | 0.20 | 10.58 | 4.37 | 0.41 | 0.99 | 3.91 | 1/0/0/0/0 | 1.0000 | 0.000 |
| drop-shadow | 1 | 1.53 | 1.20 | 0.79 | 7.06 | 3.45 | 0.49 | 0.97 | 1.09 | 0/1/0/0/0 | 1.0000 | 0.000 |
| backdrop-filter | 1 | 4.42 | 2.79 | 0.63 | 7.36 | 4.11 | 0.56 | 0.87 | 2.43 | 1/0/0/0/0 | 1.0000 | 0.000 |
| text-stroke | 1 | 0.74 | 1.18 | 1.58 | 2.11 | 1.90 | 0.90 | 1.00 | 0.59 | 0/1/0/0/0 | 0.9986 | 0.195 |
| text-decoration | 1 | 1.68 | 1.80 | 1.07 | 3.71 | 2.85 | 0.77 | 0.96 | 1.29 | 0/1/0/0/0 | 0.9992 | 0.019 |
| visibility | 1 | 0.30 | 0.18 | 0.62 | 1.20 | 0.52 | 0.43 | 0.36 | 0.27 | 1/0/0/0/0 | 1.0000 | 0.000 |
| svg-image | 1 | 0.77 | 1.19 | 1.55 | 2.21 | 1.81 | 0.82 | 0.87 | 0.48 | 0/1/0/0/0 | 0.9989 | 0.095 |
| inline-box | 1 | 2.67 | 1.85 | 0.69 | 5.34 | 3.68 | 0.69 | 1.01 | 1.91 | 0/1/0/0/0 | 1.0000 | 0.008 |
| css-stylesheet | 4 | 1.35 | 1.05 | 0.78 | 4.78 | 1.78 | 0.37 | 0.70 | 1.48 | 1/3/0/0/0 | 1.0000 | 0.000 |
| tailwind | 4 | 1.59 | 1.35 | 0.85 | 5.17 | 2.14 | 0.41 | 0.86 | 1.81 | 2/2/0/0/0 | 1.0000 | 0.000 |
| html | 4 | 1.55 | 0.97 | 0.63 | 4.68 | 2.24 | 0.48 | 0.98 | 1.52 | 0/4/0/0/0 | 1.0000 | 0.001 |
| pseudo-elements | 4 | 0.78 | 0.50 | 0.64 | 2.41 | 0.97 | 0.40 | 0.93 | 0.76 | 0/4/0/0/0 | 1.0000 | 0.000 |
| animation | 42 | 0.25 | 0.16 | 0.64 | 0.75 | 0.37 | 0.49 | 0.62 | 0.22 | 32/10/0/0/0 | 0.9997 | 0.000 |
| table | 8 | 1.17 | 0.70 | 0.60 | 2.54 | 1.27 | 0.50 | 0.99 | 0.93 | 0/8/0/0/0 | 1.0000 | 0.000 |
| float | 4 | 0.55 | 0.40 | 0.73 | 2.44 | 1.07 | 0.44 | 0.76 | 0.45 | 1/2/1/0/0 | 0.9511 | 0.419 |
| inline-block | 4 | 0.55 | 0.34 | 0.62 | 1.80 | 0.90 | 0.50 | 0.98 | 0.45 | 0/4/0/0/0 | 1.0000 | 0.000 |
| grid-areas | 3 | 0.71 | 0.54 | 0.75 | 2.13 | 0.94 | 0.44 | 0.88 | 0.63 | 0/3/0/0/0 | 1.0000 | 0.000 |
| **Tất cả (trừ known-gaps), geomean** | 175 | 1.09 | 0.71 | **0.65** | 3.41 | 1.62 | **0.48** | **0.76** | 0.93 | | | |

## Chưa port / còn khác takumi sau giai đoạn 2

- **PDF: không port.** `takumi-pdf` là gói npm riêng (không thuộc `@takumi-rs/wasm`), ~43 500 dòng Rust: phân trang, nhúng/cắt font, form tương tác — một sản phẩm khác.
- **Dòng inline:** float + chữ và chữ trong dòng hỗn hợp đã xong ở giai đoạn 3; các khoảng trống còn lại nằm trong mục "Giai đoạn 3" ở đầu file.
- **Shaping:** Indic chỉ kiểm chứng Devanagari + Bengali (các hệ khác dùng shaper mặc định); chuỗi emoji ZWJ có ca chưa gộp thành một glyph; ưu tiên font emoji khác takumi ở vài ca (©️, VS15).
- **SVG:** `<text>` chỉ qua hook; thiếu feTurbulence/feImage/feMorphology/feConvolveMatrix/feDisplacementMap/lighting/feTile; bảng SVG trong font chưa vẽ.
- **CSS:** `@apply`, `display: contents`, counter trong `content`, list marker, `animate-*` của Tailwind, animation trên pseudo-element, `clip-path: url()`, cú pháp màu tương đối, `outline-offset` theo %.
- **Sai khác 1 mức còn lại:** phần trong của gradient (takumi cộng dồn f32 theo từng span), viền nét đứt trên cạnh bo tròn, chữ bị xoay, `text-stroke`.
- **API:** `prepare()` không tự tải URL (takumi có); `setGlyphCacheMaxBytes` là no-op.
- **An toàn:** bản phát hành tắt kiểm tra; đã fuzz từng module và toàn pipeline trên ReleaseSafe cho cả ba profile (không trap).

---

# Báo cáo giai đoạn 1 (2026-11-11) — giữ để đối chiếu

Số liệu đầy đủ từng fixture: [RESULTS_FULL.md](RESULTS_FULL.md) (sinh tự động) và [results.json](results.json).
Ảnh từng ca: `bench/out/<id>/{takumi,bm,native,diff}.png` (chạy `node bench/run.mjs` để tạo lại).

## Điều kiện đo

- Máy: Intel Core i3-10100 @ 3.6 GHz (8 luồng), 7.8 GB RAM, Windows 11, Node v26.13.0. Ngày đo: 2026-11-11.
- Đối chứng: `@takumi-rs/wasm` 2.20.0 (bản wasm chính thức trên npm) và `@takumi-rs/core` 2.20.0 (native N-API, chỉ để tham khảo).
- bm-engine: `zig build` (optimize = small, wasm32-freestanding, simd128) + `wasm-opt -Oz`.
- 87 fixture trong `bench/fixtures/` (25 nhóm tính năng), cùng một cây node, cùng 9 font TTF tĩnh (Inter, Noto Sans,
  Roboto) đăng ký giống hệt nhau vào mọi engine.
- Thời gian: median của ≥ 20 lần lặp và ≥ 300 ms sau 3 lần warm-up, các engine chạy xen kẽ theo từng ca.
  `raw` = `render(..., {format:"raw"})` (RGBA thẳng), `png` = định dạng mặc định.
- Tương đương: so buffer `raw` của bm với takumi-wasm. **identical** = 0 byte khác; **equivalent** = SSIM ≥ 0.99 và
  ≤ 0.5 % điểm ảnh vượt ngưỡng pixelmatch 0.1; **close** = SSIM ≥ 0.95 và ≤ 5 %; còn lại **different**.
  SSIM lấy giá trị thấp hơn giữa SSIM độ sáng và SSIM RGB.
- Sàn nhiễu: takumi-native so với takumi-wasm **giống hệt từng byte ở cả 87 ca**, nên mọi sai khác của bm là sai khác thật.

## Tóm tắt

| Chỉ số | takumi-wasm 2.20 | bm-engine | Tỉ lệ |
|:--|--:|--:|:--|
| Kích thước `.wasm` | 4 234.9 KiB | **320.9 KiB** | nhỏ hơn **13.2×** |
| `.wasm` gzip -9 / brotli | 1 860.9 / 1 409.3 KiB | **147.1 / 126.5 KiB** | nhỏ hơn 12.7× / 11.1× |
| JS glue | 37.5 KiB (+ phụ thuộc `@takumi-rs/helpers`) | **9.5 KiB**, không phụ thuộc | nhỏ hơn 3.9× |
| Import của module wasm | shim wasm-bindgen | **0** | |
| Compile + instantiate wasm | 34.1 ms | **2.7 ms** | nhanh hơn 12.6× |
| Render đầu tiên (og-card PNG, tiến trình mới) | 151.7 ms | **74.7 ms** | nhanh hơn 2.0× |
| Cold start tổng (init + font + render đầu) | 188.1 ms | **79.5 ms** | nhanh hơn 2.4× (takumi-native: 44.8 ms) |
| Thời gian render `raw`, geomean 78 ca | 2.38 ms | **1.45 ms** | bm = 0.61× (nhanh hơn ở 70/78 ca; takumi-native: 1.99 ms) |
| Thời gian render `png`, geomean 78 ca | 8.09 ms | **5.84 ms** | bm = 0.72× (nhanh hơn ở 70/78 ca) |
| Dung lượng PNG xuất ra, geomean | 1.00 | **0.75** | nhỏ hơn 25 % |
| Bộ nhớ tuyến tính wasm sau init + 9 font | 6.3 MiB | 6.3 MiB | bằng nhau |
| Bộ nhớ tuyến tính wasm sau 50 lần render og-card PNG | **10.6 MiB** | 11.9 MiB | bm **nhiều hơn 12 %** |
| Peak RSS của tiến trình (50 lần render) | 99.6 MiB | **77.2 MiB** | ít hơn 22 % |
| Bộ nhớ wasm cuối toàn bộ lượt chạy (có canvas 3000×2000) | 66.4 MiB | 65.8 MiB | tương đương |
| Tương đương điểm ảnh trên 78 ca thuộc phạm vi đã port | — | 9 identical, 69 equivalent | 0 close / different / lỗi |
| 9 ca “known-gaps” (tính năng chưa port) | — | 1 equivalent, 2 close, 5 different, 1 lỗi | xem mục “Chưa port” |

## Theo từng tính năng

Thời gian là geomean của median (ms) các ca trong nhóm; tỉ lệ < 1 nghĩa là bm nhanh hơn / nhỏ hơn.
Cột tương đương: identical / equivalent / close / different / error.

| Tính năng | số ca | raw takumi-wasm | raw bm | bm/takumi | png takumi-wasm | png bm | bm/takumi | PNG bytes bm/takumi | raw takumi-native | tương đương | SSIM thấp nhất | % px lệch (TB) |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--|--:|--:|
| colors | 5 | 1.52 | 0.86 | 0.57 | 3.97 | 2.57 | 0.65 | 0.63 | 1.21 | 1/4/0/0/0 | 0.9999 | 0.010 |
| flex | 5 | 1.23 | 1.05 | 0.85 | 4.56 | 3.61 | 0.79 | 0.68 | 1.23 | 1/4/0/0/0 | 1.0000 | 0.000 |
| sizing (%, min/max, aspect-ratio, margin auto) | 5 | 0.87 | 0.80 | 0.92 | 4.52 | 3.08 | 0.68 | 0.39 | 1.01 | 3/2/0/0/0 | 1.0000 | 0.000 |
| absolute | 3 | 1.06 | 0.86 | 0.81 | 5.35 | 2.95 | 0.55 | 0.48 | 0.94 | 1/2/0/0/0 | 1.0000 | 0.000 |
| borders | 3 | 1.35 | 1.15 | 0.86 | 4.13 | 3.28 | 0.79 | 0.61 | 1.17 | 1/2/0/0/0 | 0.9980 | 0.030 |
| border-radius | 4 | 0.86 | 0.98 | **1.14** | 4.08 | 3.56 | 0.87 | 0.78 | 0.96 | 0/4/0/0/0 | 0.9999 | 0.001 |
| linear-gradient | 4 | 3.95 | 2.19 | 0.55 | 17.03 | 9.49 | 0.56 | 0.66 | 3.01 | 0/4/0/0/0 | 0.9998 | 0.014 |
| radial-gradient | 3 | 4.94 | 1.76 | 0.36 | 24.75 | 15.93 | 0.64 | 0.66 | 4.31 | 0/3/0/0/0 | 1.0000 | 0.000 |
| box-shadow | 4 | 5.86 | 3.16 | 0.54 | 15.85 | 8.34 | 0.53 | 0.97 | 4.07 | 0/4/0/0/0 | 0.9999 | 0.001 |
| opacity | 3 | 6.34 | 2.10 | 0.33 | 9.76 | 4.60 | 0.47 | 0.76 | 3.28 | 0/3/0/0/0 | 0.9998 | 0.004 |
| overflow (clip) | 3 | 1.59 | 0.96 | 0.60 | 5.43 | 3.66 | 0.67 | 0.76 | 1.41 | 0/3/0/0/0 | 0.9999 | 0.015 |
| transform | 3 | 2.93 | 1.74 | 0.59 | 6.03 | 4.61 | 0.77 | 0.96 | 2.19 | 0/3/0/0/0 | 0.9988 | 0.155 |
| text một dòng | 3 | 1.36 | 0.77 | 0.56 | 4.58 | 4.30 | 0.94 | 0.93 | 1.23 | 0/3/0/0/0 | 0.9993 | 0.200 |
| text đoạn văn (wrap, align, line-height, letter-spacing) | 5 | 2.31 | 1.34 | 0.58 | 6.89 | 6.13 | 0.89 | 0.88 | 1.90 | 0/5/0/0/0 | 0.9990 | 0.142 |
| fonts (weight, italic, nhiều family, fake bold) | 2 | 2.72 | 1.58 | 0.58 | 8.85 | 9.02 | **1.02** | 0.88 | 2.53 | 0/2/0/0/0 | 0.9991 | 0.362 |
| text-i18n (tiếng Việt, Latin có dấu) | 2 | 2.46 | 1.53 | 0.62 | 7.94 | 8.44 | **1.06** | 0.95 | 2.38 | 0/2/0/0/0 | 0.9994 | 0.233 |
| text-truncation (ellipsis, line-clamp) | 3 | 1.71 | 0.96 | 0.56 | 4.50 | 3.51 | 0.78 | 0.89 | 1.46 | 0/3/0/0/0 | 0.9998 | 0.047 |
| text-shadow | 1 | 1.00 | 1.00 | 1.00 | 4.36 | 5.44 | **1.25** | 1.01 | 0.70 | 0/1/0/0/0 | 0.9996 | 0.142 |
| filter (blur, grayscale) | 1 | 1.76 | 1.12 | 0.64 | 4.95 | 3.49 | 0.70 | 0.98 | 1.14 | 1/0/0/0/0 | 1.0000 | 0.000 |
| images (PNG/JPEG, object-fit, clip bo góc, background url) | 5 | 4.91 | 1.82 | 0.37 | 28.47 | 20.06 | 0.70 | 1.00 | 3.65 | 1/4/0/0/0 | 0.9994 | 0.011 |
| grid | 4 | 1.67 | 1.02 | 0.61 | 5.53 | 3.61 | 0.65 | 0.70 | 1.54 | 0/4/0/0/0 | 0.9999 | 0.001 |
| og-card (tổng hợp) | 2 | 4.21 | 2.25 | 0.54 | 13.52 | 13.75 | **1.02** | 0.97 | 3.16 | 0/2/0/0/0 | 0.9991 | 0.261 |
| blog-card (tổng hợp, có ảnh) | 2 | 10.68 | 4.78 | 0.45 | 31.33 | 15.33 | 0.49 | 0.71 | 6.04 | 0/2/0/0/0 | 0.9949 | 0.180 |
| stress (600 hộp, 200 nhãn, canvas 3000×2000) | 3 | 16.39 | 11.05 | 0.67 | 36.80 | 33.15 | 0.90 | 0.83 | 13.43 | 0/3/0/0/0 | 0.9991 | 0.062 |
| **Tất cả, geomean (78 ca)** | 78 | 2.38 | 1.45 | **0.61** | 8.09 | 5.84 | **0.72** | **0.75** | 1.99 | 9/69/0/0/0 | | |
| known-gaps (chưa port) | 9 | — | — | — | — | — | — | — | — | 0/1/2/5/1 | 0.2611 | 20.2 |

Chỗ bm **thua**: nhóm border-radius ở `raw` (1.14×: hình elip lớn đi qua rasterizer đường cong tổng quát, takumi/tiny-skia
nhanh hơn ở hình to); PNG của các ca nhiều chữ (fonts, text-i18n, og-card: 1.02–1.06×) và text-shadow (1.25×) — bộ nén
PNG của bm chậm hơn trên dữ liệu chữ khử răng cưa dù file nhỏ hơn.

### Bộ mã hoá (3 ca đại diện, 1200×630; ms median / byte)

| Ca | Định dạng | takumi-wasm | bm-engine |
|:--|:--|--:|--:|
| card-flat-ui (UI phẳng) | PNG | 19.93 ms / 25 948 B | **7.13 ms / 13 381 B** |
| | JPEG q75 4:4:4 | 25.14 ms / 50 167 B | **17.63 ms / 47 298 B** |
| | WebP lossless | 12.33 ms / 28 238 B | **8.99 ms / 11 134 B** |
| lingrad-angles (gradient) | PNG | 35.33 ms / 104 338 B | **14.50 ms / 32 991 B** |
| | JPEG | 24.68 ms / 53 557 B | **19.28 ms / 53 465 B** |
| | WebP lossless | 15.58 ms / 173 498 B | **11.57 ms / 29 580 B** |
| img-photo-bg (ảnh chụp) | PNG | 55.27 ms / 524 989 B | **47.60 ms / 523 396 B** |
| | JPEG | 24.86 ms / 56 484 B | **17.88 ms / 56 442 B** |
| | WebP lossless | **21.50 ms** / 481 634 B | 45.94 ms / **414 512 B** (chậm hơn 2.1×, nhỏ hơn 14 %) |

## Kết quả đầu ra tương đương tới đâu

- **Layout**: `measure()` của bm khớp takumi trong 0.001 px ở toàn bộ 73 fixture không có transform
  (`node bench/probe/lay.mjs "^(?!transform)" 0.001`). Bộ test layout riêng: 839/850 cây ngẫu nhiên + viết tay khớp
  takumi; 11 ca lệch đều liên quan `aspect-ratio` trên flex container tự co giãn (liệt kê trong
  `src/layout/testdata/oracle_xfail.txt`).
- **Text**: bề rộng dòng, vị trí ngắt dòng, chiều cao dòng khớp takumi ở 825/825 phép so của module font
  (Latin, tiếng Việt, kerning, ligature, letter-spacing, 5 chế độ white-space, ellipsis, line-clamp).
- **Gradient / shadow**: 25/27 ca kiểm tra riêng của module raster trùng từng byte với takumi; 2 ca còn lại lệch tối đa 1 mức.
- **9 ca identical**: nền đặc, box có biên nguyên, filter blur/grayscale…
- **69 ca equivalent**: khác biệt còn lại nằm ở **khử răng cưa** của mép cong và glyph. takumi dùng tiny-skia
  (siêu lấy mẫu 4×4 theo cạnh fixed-point); bm rasterize theo diện tích chính xác rồi lượng tử về 17 mức, riêng glyph
  thì quét ở 4× rồi gộp 4×4 để bắt chước. Vì vậy điểm ảnh ở mép có thể lệch tới ~60/255 (một mẫu con), nhưng tỉ lệ
  điểm ảnh lệch quá ngưỡng trung bình chỉ 0.00–0.36 % mỗi nhóm, SSIM ≥ 0.9949 ở mọi ca (thấp nhất: `card-flat-ui`, do
  viền `dashed` bị vẽ thành nét liền).
- JPEG giải mã: lệch tối đa 4/255 so với takumi (khác biệt làm tròn IDCT của zune-jpeg; bm trùng mozjpeg).

## Chưa port / khác takumi (trung thực)

Có fixture chứng minh (`bench/fixtures/gaps.mjs`):

| Ca | Kết quả | Lý do |
|:--|:--|:--|
| gap-tailwind-tw | different (SSIM 0.26) | prop `tw` (Tailwind) không được hỗ trợ — bị bỏ qua |
| gap-oklch-color | **lỗi** | `oklch()`, `lab()`, `color-mix()`, `color()` bị từ chối (takumi hỗ trợ) |
| gap-svg-image | different | không có trình render SVG (takumi tự có SVG engine) |
| gap-dashed-dotted-border | different | viền dashed/dotted/double được vẽ thành nét liền |
| gap-clip-path | different | `clip-path`, `mask-*` không hỗ trợ |
| gap-background-clip-text | different | `background-clip: text` không hỗ trợ |
| gap-mix-blend-mode | close | chỉ có source-over |
| gap-text-wrap-balance | close | `text-wrap: balance/pretty` bị coi như wrap thường |
| gap-inline-box-decoration | equivalent (ngẫu nhiên) | span inline có nền/padding riêng: bm bỏ qua trang trí hộp inline |

Không có fixture nhưng đã biết:

- **Font**: chỉ TrueType tĩnh `.ttf`/`.ttc` (face đầu tiên). Không WOFF/WOFF2, không font biến thiên (variable), không
  outline CFF (`.otf`), không emoji màu (COLR/CBDT). takumi hỗ trợ tất cả và kèm sẵn font Geist; bm không kèm font nào.
- **Shaping**: chỉ LTR đơn giản — kerning GPOS cặp, GSUB loại 1/4 và ngữ cảnh dạng 3. Không bidi/RTL, không chữ phức
  (Ả Rập, Devanagari…), không định vị dấu (mark positioning; tiếng Việt dựng sẵn NFC thì ổn), ngắt dòng là tập con
  UAX #14 (CJK chỉ được test ở mức đơn vị).
- **CSS**: không stylesheet/selector/cascade (`css`, `className`, `@media`), không `var()`, không animation/keyframes
  (`timeMs`, `renderAnimation`), không HTML đầu vào, không `renderSvg`, không PDF, không bảng (table), float, list marker.
  Thuộc tính logic (`margin-inline`…), `grid-template-areas`, tên đường lưới, `outline` (parse nhưng chưa vẽ),
  `drop-shadow()`, `filter: url()`, `backdrop-filter` chưa có.
- **Ảnh**: không giải mã WebP lossy (VP8), GIF/APNG chỉ khung đầu; ảnh lớn được cache cả bản gốc lẫn bản thu nhỏ
  (takumi chỉ giữ bản thu nhỏ); không tự tải URL (`prepare()` của takumi làm việc này).
- **Xuất**: không ICO, không ảnh động; WebP chỉ lossless (giống bản wasm của takumi).
- **Giới hạn**: cây node sâu tối đa 128 cấp (takumi 512), canvas tối đa 16384 px mỗi cạnh và 40 Mpx.
- **API**: `registerFont` đồng bộ và trả về `{name, weight, style}` (takumi trả `Promise<RegisteredFamily[]>`); chưa có
  `fontFamilies`, `unicodeRange`, `unregisterFont`, `dithering`, `drawDebugBorder`, `lang`.
- **Chất lượng mã**: đã fuzz toàn pipeline trên bản ReleaseSafe (~8 000 cây ngẫu nhiên, không trap) và fuzz riêng từng
  bộ giải mã/parser, nhưng bản phát hành tắt kiểm tra an toàn (`optimize = small`), nên lỗi còn sót sẽ là hỏng bộ nhớ
  trong sandbox wasm chứ không phải panic. Chưa chạy thử trong trình duyệt thật — chỉ kiểm tra đường `init(Response)`
  + `index.mjs` bằng Node (`bench/probe/browserlike.mjs`); module không có import nên rủi ro thấp nhưng chưa được xác minh.

## Vì sao nhỏ và nhanh hơn

1. takumi 2.x là bản port LayoutNG + paint của Blink sang Rust (table, float, cascade, selector, HTML parser, SVG engine,
   ICU4X, HarfBuzz port…) ⇒ 4.2 MB. bm chỉ giữ phần phục vụ ảnh OG từ cây node với style inline (~26 000 dòng Zig).
2. Không tokenizer CSS tổng quát, không serde/wasm-bindgen: một lần `JSON.stringify`, một parser JSON ~300 dòng.
3. Bump allocator tái sử dụng chunk giữa các lần render; canvas, cache glyph, cache ảnh nằm ngoài arena; PNG nén theo
   luồng từng hàng (không tạo bản sao ảnh đã lọc).
4. Hộp bo góc lớn chỉ rasterize 4 ô góc; nhóm opacity chỉ cấp vùng bao của cây con; mask glyph được cache theo pha ¼ px.
5. PNG: tự chọn indexed/RGB/RGBA + bộ dò khớp “1 pixel trước / 1 hàng trên”.

## Kết luận

Trong phạm vi đã port (flex/grid/block, box model, gradient, shadow, opacity, clip, transform, text Latin/tiếng Việt với
font TTF tĩnh, ảnh PNG/JPEG, xuất PNG/JPEG/WebP), bản Zig **tốt hơn rõ rệt** về kích thước (13×), cold start (2.4×),
tốc độ render (raw nhanh hơn ~1.6×, PNG ~1.4×) và dung lượng PNG (−25 %), với đầu ra tương đương về thị giác (SSIM ≥ 0.994,
layout khớp tới 1/64 px) nhưng **không trùng từng byte** ở các mép khử răng cưa. Nó **thua** ở bộ nhớ tuyến tính wasm
(+12 %), WebP lossless với ảnh chụp (chậm hơn 2×), và hình bo tròn lớn.

Nó **chưa thay thế được takumi**: takumi là một engine CSS gần như đầy đủ (Tailwind, stylesheet, SVG, font biến thiên,
WOFF2, emoji màu, chữ phức, animation). Lợi thế kích thước của bm đến chủ yếu từ việc *không làm* những thứ đó, nên con
số 13× không phải là so sánh ngang tính năng; thêm font biến thiên + WOFF2 + shaping đầy đủ sẽ làm bản Zig lớn lên
đáng kể. Lựa chọn hợp lý: dùng bm-engine khi đầu vào nằm trong tập con ở trên và cần wasm nhỏ / khởi động nhanh
(edge, trình duyệt); dùng takumi khi cần độ phủ CSS.
