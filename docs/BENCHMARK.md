# bm-engine (Zig) so với takumi 2.20.0 — benchmark và kiểm tra tương đương

> **Giai đoạn 4 (2026-11-12)** — addon native cho Node.js: bm-native, bm-wasm, takumi-native và takumi-wasm đo cùng lúc; ở ngay dưới, mọi bảng sinh từ [results-native.json](results-native.json).
> **Giai đoạn 3 (2026-11-12)** — số liệu cuối cùng của 0.1.0 (bản wasm) ở sau đó; giai đoạn 2 được giữ làm lịch sử (số của giai đoạn 2 được ghi rõ). Báo cáo giai đoạn 1 được giữ nguyên ở cuối file để đối chiếu.
> Số liệu từng fixture: [RESULTS_FULL.md](RESULTS_FULL.md), [results.json](results.json). Ảnh: `bench/out/<id>/`.

## Giai đoạn 6 — PDF

Đầu ra PDF (`bm-engine/pdf`) được đo với ba engine trên cùng máy, cùng Node, cùng font, cùng ảnh và cùng đầu vào:
**bm-native** (addon Node-API, API sync và async), **bm-wasm** (`js/bm_engine.pdf.wasm`, profile `pdf`) và
**takumi-pdf** (npm `takumi-pdf`, chỉ có bản wasm; không có gói native nào được phát hành). Bộ tài liệu
(`bench/pdf/corpus/`) gồm đầu vào của 89 golden của takumi-pdf (dựng như `scripts/pdf-compare.mjs`), các tài liệu
trong hướng dẫn PDF (hoá đơn, báo cáo lặp header bảng, vé, văn bản nhiều trang, header/footer có số trang, liên kết
và mục lục, ảnh PNG/JPEG/SVG, gradient/bóng đổ, RTL/CJK/emoji, PDF/UA, các mức PDF/A, tệp đính kèm) và tài liệu stress
1, 10, 100, 500 trang. Mọi bảng dưới đây được sinh từ [results-pdf.json](results-pdf.json) bởi
`node bench/pdf/bench.mjs` (giữa các comment `pdf-bench`); không con số nào được gõ tay. Kiểm tra bằng công cụ bên
ngoài (qpdf, pdfcpu, poppler, MuPDF, pdf.js, veraPDF) và so sánh hình ảnh: `node bench/pdf/validate.mjs`,
`node bench/pdf/visual.mjs`; cách cài và giới hạn của từng công cụ: `bench/pdf/README.md`.

**Phương pháp.** Thời gian render đo khi đã nóng (font đăng ký trước, đầu ra giữ trong bộ nhớ); trong mỗi tài liệu các
biến thể chạy xen kẽ, đổi thứ tự mỗi vòng, nên một đợt tải từ tiến trình khác ảnh hưởng mọi biến thể như nhau; bộ đo
tốc độ chạy nhiều lượt ở các thời điểm khác nhau (xen giữa các giai đoạn khác) và độ lệch giữa các lượt được ghi lại;
số nào lệch quá 10 % được đánh dấu ⚠. Khởi động lạnh, bộ nhớ, event loop, khả năng mở rộng theo số trang và thông
lượng song song: mỗi điểm chạy trong một tiến trình mới. Mỗi giai đoạn ghi lại mức CPU bận của máy trước và trong lúc đo.
Kích thước file: không engine nào có tuỳ chọn nén, nên ngoài kích thước gốc còn có kích thước sau khi qpdf nén lại cả
hai bằng cùng thiết lập.

### Điều kiện đo

<!-- pdf-bench:env -->
| Mục | Giá trị |
|:--|:--|
| Máy | 11th Gen Intel(R) Core(TM) i5-1145G7 @ 2.60GHz, 8 CPU logic, 31.7 GiB, win32 10.0.19045 x64 |
| Node.js | v24.21.0 (V8 13.6.233.17-node.53, libuv 1.52.1) |
| bm-engine | 0.1.0, git `a24ad8cc12` (main, 224 file đang sửa) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 3.583 KiB, sha256 `9246a08cdfb9` |
| bm-wasm | `js/bm_engine.pdf.wasm` (profile pdf), 1.838 KiB, sha256 `223aacd2f1cd` |
| takumi-pdf | npm `takumi-pdf` 0.20.0 (wasm, 4.335 KiB); không có bản native nào được phát hành |
| Lần chạy | 2026-11-15 07:58 UTC, full, 6.2 min; CPU bận trước khi chạy: 4 % |
<!-- /pdf-bench:env -->

### Tóm tắt

<!-- pdf-bench:summary -->
- **Thời gian render, bm-native so với takumi-pdf:** sync 0,33× [0,33× / 0,33× / 0,33×] (nhanh hơn ở 159/159, 0,16×–0,69×); async 0,42× [0,42× / 0,42× / 0,42×] (nhanh hơn ở 159/159, 0,18×–0,83×). Dưới 1× = bm tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ ở từng lượt.
- **bm-wasm vs takumi-pdf (cả hai là wasm):** 0,51× [0,51× / 0,51× / 0,51×] (nhanh hơn ở 159/159, 0,26×–0,94×). **bm-native vs bm-wasm (sync):** 0,66× [0,65× / 0,66× / 0,66×] (nhanh hơn ở 159/159, 0,49×–0,79×).
- **Trang mỗi giây ở 1 / 10 / 100 / 500 trang:** bm-native 408 / 611 / 615 / 568; bm-wasm 114 / 328 / 376 / 314; takumi-pdf 59 / 116 / 128 / 115.
- **Trùng byte:** bm-native == bm-wasm 161/161 tài liệu.
- **Bộ kiểm tra:** bm-native 152/161 PDF không có lỗi hay cảnh báo nào (takumi-pdf 152/161); veraPDF bm-native 45/45, takumi-pdf 45/45; cùng chữ, liên kết, mục lục và thẻ như takumi-pdf: 153/161.
- **Kết luận hình ảnh so với takumi-pdf (tốt nhất trong các bộ raster):** identical 117, equivalent 35, different 8, close 1 (161 tài liệu, pdfium + mupdf).
<!-- /pdf-bench:summary -->

### Thời gian render

<!-- pdf-bench:speed -->
| Biến thể | geomean ms | từng lượt | độ lệch |
|:--|--:|--:|--:|
| bm-native:sync | 0,75 | 0,75 / 0,75 / 0,75 | 0,3 % |
| bm-native:async | 0,95 | 0,95 / 0,95 / 0,96 | 0,6 % |
| bm-wasm:sync | 1,15 | 1,15 / 1,15 / 1,15 | 0,3 % |
| bm-wasm:async | 1,00 | 1,00 / 1,01 / 1,01 | 0,3 % |
| takumi-pdf:async | 2,26 | 2,27 / 2,26 / 2,27 | 0,4 % |

| Tỉ lệ (thời gian) | geomean | từng lượt | nhanh hơn | khoảng | độ lệch |
|:--|--:|--:|--:|--:|--:|
| bm-native:sync / takumi-pdf:async | 0,33× | 0,33× / 0,33× / 0,33× | 159/159 | 0,16×–0,69× | 0,3 % |
| bm-native:async / takumi-pdf:async | 0,42× | 0,42× / 0,42× / 0,42× | 159/159 | 0,18×–0,83× | 0,5 % |
| bm-wasm:sync / takumi-pdf:async | 0,51× | 0,51× / 0,51× / 0,51× | 159/159 | 0,26×–0,94× | 0,2 % |
| bm-native:sync / bm-wasm:sync | 0,66× | 0,65× / 0,66× / 0,66× | 159/159 | 0,49×–0,79× | 0,5 % |
| bm-native:async / bm-native:sync | 1,27× | 1,27× / 1,27× / 1,27× | 1/159 | 0,92×–2,66× | 0,5 % |

Thời gian render khi đã nóng cho mỗi tài liệu (font đăng ký trước, đầu ra giữ trong bộ nhớ), 159 tài liệu, 3 lượt; các biến thể chạy xen kẽ, đổi thứ tự mỗi vòng.
<!-- /pdf-bench:speed -->

### Kích thước file

<!-- pdf-bench:sizes -->
| Nhóm | tài liệu | bm | takumi-pdf | tỉ lệ tổng | tỉ lệ geomean | sau cùng một lần nén lại bằng qpdf |
|:--|--:|--:|--:|--:|--:|--:|
| golden | 136 | 1.652 KiB | 1.609 KiB | 1,03× | 1,01× | 1.444 KiB / 1.419 KiB (1,02×) |
| docs | 21 | 1.315 KiB | 1.311 KiB | 1,00× | 1,01× | 1.343 KiB / 1.343 KiB (1,00×) |
| stress | 4 | 2.345 KiB | 2.697 KiB | 0,87× | 0,95× | 1.841 KiB / 2.314 KiB (0,80×) |

Tỉ lệ kích thước bm / takumi-pdf lớn nhất: `golden/text-stroke-paint-order` 1,80× (16 KiB / 8,8 KiB), `golden/text-shadow-stroke` 1,23× (115 KiB / 93 KiB), `golden/paged-landscape` 1,16× (16 KiB / 14 KiB), `golden/at-page-first-left-right` 1,11× (17 KiB / 15 KiB), `golden/at-page-root-element` 1,09× (15 KiB / 14 KiB), `golden/floated-flex-item-break-after` 1,08× (5,7 KiB / 5,3 KiB).

Không engine nào có tuỳ chọn nén (cả hai ghi luồng Flate và object stream); cột cuối nén lại file của cả hai engine bằng cùng thiết lập qpdf (zlib mức 9, object stream).
<!-- /pdf-bench:sizes -->

### Theo số trang (1 / 10 / 100 / 500)

<!-- pdf-bench:scale -->
| Trang | bm-native ms | trang/s | kích thước | RSS đỉnh | bm-wasm ms | trang/s | kích thước | RSS đỉnh | takumi-pdf ms | trang/s | kích thước | RSS đỉnh |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| 1 | 2,50 ms | 407,5 | 27 KiB | 62 MiB | 8,80 ms | 114,3 | 27 KiB | 93 MiB | 17,0 ms | 58,9 | 27 KiB | 121 MiB |
| 10 | 16,4 ms | 610,6 | 60 KiB | 70 MiB | 30,5 ms | 327,9 | 60 KiB | 94 MiB | 86,6 ms | 115,5 | 58 KiB | 131 MiB |
| 100 | 163 ms | 615,1 | 390 KiB | 127 MiB | 266 ms | 375,5 | 390 KiB | 137 MiB | 780 ms | 128,2 | 426 KiB | 144 MiB |
| 500 | 880 ms | 568,4 | 1.868 KiB | 339 MiB | 1.592 ms | 314,0 | 1.868 KiB | 306 MiB | 4.334 ms | 115,4 | 2.186 KiB | 202 MiB |

Một lần render tài liệu stress (mỗi trang: tiêu đề, đoạn văn, bảng 14 dòng, một ảnh; `break-after: page`) trong một tiến trình mới cho mỗi điểm; làm nóng bằng tài liệu 1 trang. Độ siêu tuyến tính (thời gian mỗi trang ở 100 trang / ở 10 trang; 1× = tuyến tính): bm-native 0,99×, bm-wasm 0,87×, takumi-pdf 0,90×.
<!-- /pdf-bench:scale -->

### Khởi động lạnh

<!-- pdf-bench:cold -->
| Engine | wall median ms | p95 | hơn Node trống | import | font | PDF đầu tiên | RSS đỉnh |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Node.js trống | 51,6 | 69,3 | — | — | — | — | 52 MiB |
| bm-native | 66,0 | 73,9 | 14,4 | 7,30 | 0,51 | 3,90 | 56 MiB |
| bm-wasm | 147 | 174 | 95,6 | 11,4 | 2,81 | 57,2 | 81 MiB |
| takumi-pdf | 217 | 273 | 166 | 37,5 | 3,09 | 105 | 88 MiB |

30 lần mỗi engine, xen kẽ: khởi động Node -> import -> đăng ký Inter Regular -> hoá đơn A4 một trang -> thoát. CPU bận trong lúc đo 33 %.
<!-- /pdf-bench:cold -->

### Bộ nhớ

<!-- pdf-bench:memory -->
| Engine | RSS sau lượt 1 | RSS sau lượt 10 | bộ nhớ engine (lượt 1 → cuối) | RSS đỉnh, tài liệu stress lớn nhất |
|:--|--:|--:|--:|--:|
| bm-native | 97 MiB | 98 MiB | 30,0 → 29,7 MiB | 500 trang: 339 MiB |
| bm-wasm | 127 MiB | 127 MiB | 59,1 → 59,1 MiB | 500 trang: 306 MiB |
| takumi-pdf | 130 MiB | 129 MiB | 46,3 → 46,3 MiB | 500 trang: 202 MiB |

Mọi tài liệu hướng dẫn (21) render 10 lần, GC trước mỗi lần đọc; Node.js trống: 50.4 MiB RSS. Bộ nhớ engine: bm Renderer.memoryBytes (bộ nhớ tuyến tính wasm, hoặc phần cấp phát đang sống của addon native), takumi-pdf: bộ nhớ wasm.
<!-- /pdf-bench:memory -->

### Chặn event loop

<!-- pdf-bench:eventloop -->
| Engine | API | render ms | độ trễ timer lớn nhất | p99 | số tick |
|:--|--:|--:|--:|--:|--:|
| bm-native | sync | 162 | 162 ms | 162 ms | 1 |
| bm-native | async | 173 | 1,40 ms | 1,10 ms | 175 |
| bm-wasm | sync | 359 | 359 ms | 359 ms | 1 |
| bm-wasm | async | 356 | 356 ms | 356 ms | 1 |
| takumi-pdf | async | 979 | 979 ms | 979 ms | 1 |

Một lần render 100 trang trong khi một timer 1 ms chạy; độ trễ gần bằng thời gian render nghĩa là event loop bị chặn suốt lần render.
<!-- /pdf-bench:eventloop -->

### Thông lượng song song

<!-- pdf-bench:throughput -->
| Cấu hình | N=1 | N=2 | N=4 | N=8 |
|:--|--:|--:|--:|--:|
| bm-native seq uv=4 | 548 |  |  |  |
| bm-wasm seq | 337 |  |  |  |
| takumi-pdf seq | 164 |  |  |  |
| bm-native many k=1 uv=4 | 476 | 523 | 524 | 524 |
| bm-native many k=2 uv=4 | 467 | 984 | 1.011 | 1.020 |
| bm-native many k=4 uv=4 | 477 | 983 | 1.848 | 1.893 |
| bm-native many k=8 uv=4 | 495 | 962 | 1.786 | 1.378 |
| bm-native many k=1 uv=8 | 468 | 511 | 523 | 524 |
| bm-native many k=2 uv=8 | 477 | 983 | 1.019 | 1.023 |
| bm-native many k=4 uv=8 | 486 | 968 | 1.449 | 1.370 |
| bm-native many k=8 uv=8 | 486 | 924 | 1.405 | 1.820 |
| bm-wasm pool k=1 | 304 | 331 | 333 | 328 |
| bm-wasm pool k=2 | 316 | 575 | 548 | 542 |
| bm-wasm pool k=4 | 299 | 543 | 816 | 808 |
| bm-wasm pool k=8 | 299 | 552 | 813 | 974 |
| takumi-pdf pool k=1 | 147 | 171 | 175 | 176 |
| takumi-pdf pool k=2 | 155 | 280 | 291 | 288 |
| takumi-pdf pool k=4 | 136 | 279 | 434 | 433 |
| takumi-pdf pool k=8 | 147 | 284 | 425 | 527 |

Số PDF mỗi giây, docs/invoice (one-page A4 invoice, HTML + footer), closed loop: N clients each with one request in flight; 2000 ms mỗi điểm, 8 CPU logic. seq = một client với API sync (takumi-pdf: await render), many = N client trên K renderer bm-native (API async trên pool libuv, UV_THREADPOOL_SIZE = uv), pool = pool worker_threads gồm K worker, mỗi worker có engine riêng.
<!-- /pdf-bench:throughput -->

### Kiểm tra và tương đương

<!-- pdf-bench:equiv -->
| Engine | PDF | sạch | lỗi | cảnh báo | bm-only | chung với takumi-pdf | veraPDF |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 161 | 152 | 12 | 0 | 0 | 12 | 45/45 |
| bm-wasm | 161 | 152 | 12 | 0 | 0 | 12 | 45/45 |
| takumi-pdf | 161 | 152 | 12 | 0 | — | — | 45/45 |

Bộ kiểm tra: qpdf 12.4.2, pdfcpu 0.16.4 (strict), poppler 26.09.0 (oschwartz10612/poppler-windows Release-26.09.0-0) (pdfinfo, pdffonts), MuPDF 1.28.6 (wasm), pdf.js 6.5.438, veraPDF 1.28.2 (greenfield-apps, the shaded CLI jar published to Maven Central). Ngữ nghĩa (pdf.js: chữ từng trang, liên kết, mục lục, tệp đính kèm, thẻ, metadata) trùng với takumi-pdf ở 153/161 tài liệu.

| Bộ raster | identical | equivalent | close | different |
|:--|--:|--:|--:|--:|
| pdfium | 108 | 44 | 1 | 8 |
| mupdf | 108 | 43 | 2 | 8 |
| tốt nhất trong các bộ raster | 117 | 35 | 1 | 8 |

bm-native so với takumi-pdf, cùng bộ raster, 96 và 144 dpi, 161 tài liệu (tính theo trang tệ nhất). PDF của bm so với ảnh bm render cùng cây (tài liệu viewport, 96 dpi): pdfium equivalent 7, different 18, close 22, identical 2; mupdf equivalent 21, different 17, close 11.

bm-native == bm-wasm từng byte: 161/161. Lỗi render: không có.
<!-- /pdf-bench:equiv -->

### Nhiễu

<!-- pdf-bench:noise -->
| Giai đoạn | CPU bận trước | CPU bận trong lúc đo | tiến trình khác (lõi) |
|:--|--:|--:|--:|
| speed lượt 1 | 8,8 % | 17,3 % | 0,34 |
| speed lượt 2 | 8,0 % | 17,3 % | 0,35 |
| speed lượt 3 | 4,3 % | 17,7 % | 0,37 |
| scale | — | 24,8 % | — |
| cold | — | 33,0 % | 1,37 |
| memory | — | 23,8 % | 0,40 |
| eventloop | — | 26,2 % | — |
| throughput | — | 32,4 % | 0,84 |

Median từng tài liệu có độ lệch giữa các lượt vượt 10 %: 66 (ví dụ golden/box-chrome bm-native:async, golden/box-chrome takumi-pdf:async, golden/gradients bm-native:sync, golden/gradients bm-native:async, golden/gradients takumi-pdf:async).
<!-- /pdf-bench:noise -->

<details><summary>Từng tài liệu</summary>

<!-- pdf-bench:per-doc -->
| Tài liệu | bm-native:sync | bm-native:async | bm-wasm:sync | bm-wasm:async | takumi-pdf:async | bm-n sync / tk | byte bm / tk |
|:--|--:|--:|--:|--:|--:|--:|--:|
| `golden/box-chrome` | 0,70 / 1,25 | 0,64 / 1,23 | 1,05 / 1,38 | 0,87 / 1,30 | 2,00 / 2,52 | 0,35× | 5441 / 5453 |
| `golden/gradients` | 0,41 / 1,00 | 0,42 / 1,07 | 0,54 / 1,00 | 0,45 / 1,00 | 0,93 / 1,90 | 0,44× | 4506 / 4483 |
| `golden/repeating-gradients` | 0,38 / 0,48 | 0,49 / 0,63 | 0,53 / 0,71 | 0,48 / 0,64 | 0,89 / 1,10 | 0,43× | 8558 / 8454 |
| `golden/box-shadows` | 0,24 / 0,31 | 0,40 / 0,51 | 0,39 / 0,50 | 0,33 / 0,50 | 0,67 / 0,82 | 0,36× | 4120 / 4128 |
| `golden/blend-opacity` | 0,16 / 0,23 | 0,31 / 0,46 | 0,25 / 0,35 | 0,20 / 0,28 | 0,49 / 0,65 | 0,32× | 3156 / 3172 |
| `golden/overflow-clip` | 0,15 / 0,26 | 0,31 / 0,44 | 0,23 / 0,35 | 0,18 / 0,29 | 0,47 / 0,72 | 0,32× | 2492 / 2505 |
| `golden/transformed-overflow-clip` | 0,09 / 0,15 | 0,24 / 0,30 | 0,14 / 0,20 | 0,11 / 0,18 | 0,29 / 0,43 | 0,31× | 1828 / 1846 |
| `golden/clip-path-shapes` | 0,19 / 0,28 | 0,31 / 0,47 | 0,32 / 0,43 | 0,27 / 0,37 | 0,58 / 0,74 | 0,33× | 4348 / 4367 |
| `golden/mask-image` | 0,25 / 0,33 | 0,44 / 0,53 | 0,43 / 0,54 | 0,36 / 0,49 | 0,78 / 1,02 | 0,32× | 9341 / 9354 |
| `golden/color-filters` | 0,13 / 0,19 | 0,28 / 0,38 | 0,22 / 0,30 | 0,18 / 0,26 | 0,41 / 0,60 | 0,33× | 1924 / 1939 |
| `golden/outlines` | 0,14 / 0,21 | 0,27 / 0,37 | 0,22 / 0,31 | 0,18 / 0,27 | 0,40 / 0,53 | 0,36× | 2417 / 2421 |
| `golden/background-boxes` | 0,17 / 0,24 | 0,32 / 0,42 | 0,30 / 0,42 | 0,25 / 0,36 | 0,49 / 0,66 | 0,34× | 3938 / 3954 |
| `golden/background-placement` | 0,17 / 0,24 | 0,30 / 0,42 | 0,30 / 0,38 | 0,25 / 0,34 | 0,51 / 0,70 | 0,34× | 4681 / 4694 |
| `golden/url-layers` | 0,17 / 0,25 | 0,32 / 0,48 | 0,27 / 0,37 | 0,22 / 0,31 | 0,54 / 0,75 | 0,32× | 3489 / 3501 |
| `golden/edge-degenerate` | 0,48 / 0,59 | 0,61 / 0,86 | 0,71 / 0,89 | 0,60 / 0,79 | 1,32 / 1,69 | 0,36× | 5511 / 5520 |
| `golden/image-object-fit` | 0,14 / 0,20 | 0,28 / 0,41 | 0,20 / 0,32 | 0,15 / 0,24 | 0,70 / 0,99 | 0,20× | 2290 / 2302 |
| `golden/encoded-bitmaps` | 0,13 / 0,20 | 0,28 / 0,39 | 0,19 / 0,26 | 0,14 / 0,23 | 0,43 / 0,63 | 0,30× | 3213 / 3228 |
| `golden/png-streams` | 0,11 / 0,17 | 0,23 / 0,34 | 0,15 / 0,22 | 0,12 / 0,19 | 0,33 / 0,50 | 0,33× | 2561 / 2576 |
| `golden/border-mixed-sides` | 0,16 / 0,23 | 0,31 / 0,43 | 0,25 / 0,36 | 0,19 / 0,31 | 0,55 / 0,72 | 0,29× | 2436 / 2442 |
| `golden/inline-span-background` | 0,52 / 0,60 | 0,64 / 0,89 | 0,80 / 0,97 | 0,68 / 0,91 | 1,44 / 1,74 | 0,36× | 6529 / 6537 |
| `golden/inline-span-border` | 0,47 / 0,55 | 0,61 / 0,76 | 0,71 / 0,89 | 0,59 / 0,78 | 1,25 / 1,45 | 0,37× | 6236 / 6246 |
| `golden/inline-images` | 0,46 / 0,53 | 0,58 / 0,73 | 0,66 / 0,75 | 0,53 / 0,69 | 1,37 / 1,57 | 0,33× | 6312 / 6330 |
| `golden/inline-image-decorations` | 0,44 / 0,53 | 0,57 / 0,73 | 0,64 / 0,84 | 0,52 / 0,68 | 1,23 / 1,53 | 0,36× | 6129 / 6141 |
| `golden/page-background` | 0,38 / 0,47 | 0,52 / 0,61 | 0,56 / 0,69 | 0,43 / 0,61 | 1,21 / 1,44 | 0,32× | 5464 / 5488 |
| `golden/svg-background-image` | 0,39 / 0,51 | 0,53 / 0,64 | 0,58 / 0,75 | 0,46 / 0,62 | 1,05 / 1,28 | 0,37× | 5968 / 5980 |
| `golden/collapsed-table` | 0,94 / 1,07 | 1,08 / 1,29 | 1,53 / 1,72 | 1,40 / 1,72 | 3,05 / 3,90 | 0,31× | 9638 / 9618 |
| `golden/text-decorations` | 0,66 / 0,80 | 0,79 / 0,93 | 1,02 / 1,25 | 0,90 / 1,08 | 1,60 / 1,88 | 0,41× | 8906 / 8924 |
| `golden/text-decoration-styles` | 0,51 / 0,61 | 0,66 / 0,87 | 0,80 / 1,03 | 0,68 / 0,88 | 1,22 / 1,45 | 0,42× | 6068 / 6082 |
| `golden/svg-vector-image` | 0,12 / 0,20 | 0,25 / 0,35 | 0,19 / 0,29 | 0,14 / 0,26 | 0,43 / 0,63 | 0,28× | 2460 / 2473 |
| `golden/text-basic` | 0,32 / 0,43 | 0,47 / 0,66 | 0,46 / 0,62 | 0,37 / 0,57 | 0,90 / 1,16 | 0,36× | 5099 / 5113 |
| `golden/text-ligatures` | 0,31 / 0,39 | 0,46 / 0,60 | 0,46 / 0,55 | 0,35 / 0,49 | 0,88 / 1,08 | 0,35× | 4966 / 4983 |
| `golden/text-decoration-shadow` | 1,99 / 2,15 | 2,14 / 2,39 | 2,72 / 2,92 | 2,56 / 3,05 | 4,10 / 4,95 | 0,48× | 42120 / 41576 |
| `golden/text-shadow-stroke` | 6,20 / 6,46 | 6,42 / 6,59 | 8,47 / 9,15 | 8,47 / 8,61 | 9,28 / 9,57 | 0,67× | 117714 / 95472 |
| `golden/color-glyph-text-shadow` | 3,97 / 4,05 | 4,19 / 4,53 | 5,03 / 5,33 | 4,96 / 5,13 | 6,78 / 7,05 | 0,59× | 81054 / 80275 |
| `golden/bitmap-glyph-text-shadow` | 1,26 / 1,43 | 1,40 / 1,73 | 1,78 / 2,04 | 1,69 / 1,87 | 2,29 / 2,62 | 0,55× | 15158 / 15247 |
| `golden/text-stroke-paint-order` | 0,98 / 1,10 | 1,13 / 1,36 | 1,33 / 1,45 | 1,21 / 1,46 | 1,41 / 1,65 | 0,69× | 16178 / 8977 |
| `golden/cluster-closing-on-a-mark` | 0,21 / 0,27 | 0,35 / 0,47 | 0,29 / 0,39 | 0,23 / 0,35 | 0,58 / 0,73 | 0,35× | 4991 / 5003 |
| `golden/font-weights` | 3,02 / 3,39 | 3,20 / 3,49 | 4,79 / 5,02 | 4,72 / 4,98 | 7,48 / 7,84 | 0,40× | 57268 / 57162 |
| `golden/certificate` | 1,21 / 1,29 | 1,35 / 1,74 | 1,92 / 2,07 | 1,82 / 2,05 | 3,07 / 3,53 | 0,39× | 14358 / 14304 |
| `golden/paged-lines` | 1,50 / 1,71 | 1,62 / 1,85 | 2,35 / 2,70 | 2,27 / 2,52 | 5,81 / 6,43 | 0,26× | 8817 / 8688 |
| `golden/paged-page-ranges` | 1,02 / 1,15 | 1,13 / 1,30 | 1,63 / 1,95 | 1,52 / 1,88 | 6,38 / 7,06 | 0,16× | 7197 / 7192 |
| `golden/paged-table` | 2,53 / 2,77 | 2,64 / 2,76 | 4,10 / 4,43 | 4,07 / 4,39 | 7,57 / 8,28 | 0,33× | 14858 / 14664 |
| `golden/paged-breaks` | 0,47 / 0,58 | 0,60 / 0,79 | 0,70 / 0,87 | 0,56 / 0,79 | 1,74 / 2,06 | 0,27× | 5929 / 5948 |
| `golden/paged-widows-orphans` | 0,75 / 0,91 | 0,88 / 1,02 | 1,15 / 1,40 | 1,02 / 1,24 | 2,48 / 2,66 | 0,30× | 8308 / 8296 |
| `golden/paged-narrow` | 1,30 / 1,39 | 1,48 / 1,59 | 2,04 / 2,30 | 1,94 / 2,17 | 4,38 / 4,75 | 0,30× | 9459 / 9266 |
| `golden/paged-landscape` | 4,94 / 5,17 | 5,17 / 5,43 | 7,63 / 7,80 | 7,61 / 7,70 | 12,1 / 12,7 | 0,41× | 16412 / 14122 |
| `golden/legacy-page-break` | 0,66 / 0,85 | 0,79 / 0,97 | 1,03 / 1,18 | 0,89 / 1,07 | 2,13 / 2,41 | 0,31× | 7815 / 7826 |
| `golden/text-shadow-page-cut` | 0,67 / 0,76 | 0,80 / 0,99 | 0,93 / 1,10 | 0,80 / 1,00 | 1,59 / 1,84 | 0,42× | 10645 / 10562 |
| `golden/fixed-repeats-per-page` | 0,49 / 0,59 | 0,62 / 0,78 | 0,72 / 0,88 | 0,60 / 0,81 | 1,52 / 1,78 | 0,32× | 6382 / 6402 |
| `golden/invoice` | 6,90 / 7,11 | 7,03 / 7,45 | 11,9 / 12,1 | 11,8 / 12,2 | 37,5 / 38,2 | 0,18× | 29571 / 28723 |
| `golden/report-links-outline` | 1,11 / 1,25 | 1,22 / 1,42 | 1,71 / 1,92 | 1,59 / 1,90 | 4,07 / 4,30 | 0,27× | 14252 / 14223 |
| `golden/paged-footer` | 1,51 / 1,63 | 1,63 / 1,88 | 2,50 / 2,80 | 2,42 / 2,78 | 7,50 / 7,87 | 0,20× | 11459 / 11427 |
| `golden/paged-band-remeasure` | 0,71 / 0,80 | 0,83 / 1,01 | 1,08 / 1,25 | 0,93 / 1,19 | 3,10 / 3,44 | 0,23× | 6868 / 6879 |
| `golden/paged-header-footer` | 1,92 / 2,01 | 2,06 / 2,22 | 3,30 / 3,52 | 3,22 / 3,37 | 10,1 / 10,7 | 0,19× | 10707 / 10657 |
| `golden/auto-margin-bands` | 1,53 / 1,76 | 1,69 / 1,80 | 2,59 / 2,82 | 2,47 / 2,77 | 7,35 / 7,76 | 0,21× | 8765 / 8727 |
| `golden/page-rules` | 1,22 / 1,37 | 1,35 / 1,46 | 1,99 / 2,16 | 1,86 / 2,05 | 6,33 / 6,81 | 0,19× | 10578 / 10542 |
| `golden/paged-target-counters` | 0,69 / 0,81 | 0,81 / 0,96 | 1,07 / 1,28 | 0,93 / 1,15 | 3,62 / 4,01 | 0,19× | 7539 / 7555 |
| `golden/content-page-counters` | 0,40 / 0,48 | 0,51 / 0,67 | 0,59 / 0,71 | 0,46 / 0,63 | 1,49 / 1,74 | 0,27× | 5130 / 5145 |
| `golden/fixed-page-counters` | 0,39 / 0,52 | 0,51 / 0,65 | 0,59 / 0,77 | 0,46 / 0,60 | 1,31 / 1,65 | 0,30× | 4271 / 4292 |
| `golden/stream-total-pages-band` | 1,71 / 1,89 | 1,84 / 2,09 | 2,88 / 3,09 | 2,76 / 2,92 | 5,81 / 6,30 | 0,29× | 11138 / 11120 |
| `golden/stream-content-counters` | 1,38 / 1,59 | 1,45 / 1,63 | 2,21 / 2,28 | 2,09 / 2,28 | 7,78 / 8,31 | 0,18× | 11989 / 11979 |
| `golden/stream-page-ranges-middle` | 0,89 / 0,95 | 1,00 / 1,18 | 1,38 / 1,57 | 1,26 / 1,53 | 3,45 / 3,76 | 0,26× | 10529 / 10540 |
| `golden/at-page-first-left-right` | 7,54 / 7,97 | 7,66 / 8,12 | 12,6 / 12,9 | 12,6 / 12,7 | 18,3 / 18,7 | 0,41× | 17311 / 15653 |
| `golden/at-page-root-element` | 5,96 / 6,08 | 6,08 / 6,30 | 9,98 / 10,1 | 10,0 / 10,1 | 11,1 / 11,5 | 0,54× | 15697 / 14404 |
| `golden/named-pages` | 10,8 / 11,2 | 11,1 / 12,5 | 20,1 / 20,6 | 19,8 / 20,3 | 26,1 / 26,5 | 0,41× | 17572 / 17129 |
| `golden/stream-forward-link` | 1,01 / 1,10 | 1,12 / 1,48 | 1,56 / 1,75 | 1,44 / 1,59 | 4,88 / 5,31 | 0,21× | 12436 / 12432 |
| `golden/stream-tagged-outline` | 1,04 / 1,20 | 1,17 / 1,60 | 1,63 / 1,82 | 1,48 / 1,66 | 3,90 / 4,41 | 0,27× | 12433 / 12416 |
| `golden/invoice-pdfa-3b-attachment` | 6,99 / 7,19 | 7,13 / 7,53 | 12,1 / 12,2 | 11,8 / 12,2 | 35,3 / 36,2 | 0,20× | 34751 / 33899 |
| `golden/font-formats-pdfa-2b` | 1,43 / 1,51 | 1,55 / 1,79 | 2,14 / 2,36 | 2,00 / 2,28 | 3,45 / 3,85 | 0,41× | 35336 / 35291 |
| `golden/font-formats-pdfa-2u` | 1,44 / 1,58 | 1,56 / 1,77 | 2,11 / 2,48 | 2,03 / 2,22 | 3,46 / 3,78 | 0,42× | 35336 / 35291 |
| `golden/font-formats-pdfa-2a` | 1,43 / 1,66 | 1,58 / 1,78 | 2,12 / 2,36 | 2,02 / 2,25 | 3,46 / 3,79 | 0,41× | 35336 / 35291 |
| `golden/font-formats-pdfa-3b` | 1,44 / 1,59 | 1,58 / 1,93 | 2,13 / 2,28 | 1,98 / 2,31 | 3,48 / 3,67 | 0,41× | 35336 / 35291 |
| `golden/font-formats-pdfa-3u` | 1,44 / 1,59 | 1,61 / 1,79 | 2,13 / 2,42 | 2,00 / 2,31 | 3,44 / 3,71 | 0,42× | 35336 / 35291 |
| `golden/font-formats-pdfa-3a` | 1,44 / 1,55 | 1,56 / 1,81 | 2,10 / 2,40 | 2,01 / 2,34 | 3,46 / 3,69 | 0,42× | 35336 / 35291 |
| `golden/font-formats-pdfa-4` | 1,43 / 1,55 | 1,54 / 1,79 | 2,11 / 2,50 | 1,97 / 2,26 | 3,33 / 3,57 | 0,43× | 31963 / 31906 |
| `golden/invoice-pdfa-2b` | 6,87 / 7,09 | 7,16 / 7,47 | 11,9 / 12,1 | 11,8 / 12,3 | 35,4 / 37,3 | 0,19× | 32804 / 31953 |
| `golden/invoice-pdfa-4` | 6,89 / 7,15 | 7,07 / 7,34 | 11,9 / 12,3 | 11,8 / 12,1 | 35,2 / 36,3 | 0,20× | 30497 / 29644 |
| `golden/invoice-pdfa-4f-attachment` | 6,94 / 7,24 | 7,11 / 7,50 | 11,9 / 12,1 | 11,8 / 12,2 | 35,1 / 35,4 | 0,20× | 32656 / 31803 |
| `golden/report-tagged-ua1` | 1,15 / 1,32 | 1,26 / 1,51 | 1,78 / 2,06 | 1,63 / 1,90 | 4,08 / 4,40 | 0,28× | 18501 / 18461 |
| `golden/report-tagged-a2a` | 1,13 / 1,29 | 1,26 / 1,45 | 1,74 / 1,97 | 1,60 / 1,81 | 3,98 / 4,50 | 0,28× | 17197 / 17166 |
| `golden/list-tagged-ua1` | 0,84 / 0,96 | 0,93 / 1,22 | 1,26 / 1,47 | 1,11 / 1,35 | 2,57 / 2,78 | 0,32× | 10525 / 10522 |
| `golden/inline-block-tagged` | 0,57 / 0,67 | 0,70 / 0,83 | 0,83 / 0,91 | 0,69 / 0,85 | 1,64 / 1,94 | 0,35× | 8607 / 8630 |
| `golden/structure-types-a4` | 1,12 / 1,19 | 1,25 / 1,41 | 1,69 / 1,90 | 1,56 / 1,80 | 4,36 / 4,72 | 0,26× | 13767 / 13724 |
| `golden/table-tagged-ua2` | 0,91 / 1,09 | 1,03 / 1,25 | 1,37 / 1,60 | 1,25 / 1,47 | 2,55 / 2,85 | 0,36× | 12349 / 12319 |
| `golden/report-tagged-ua2` | 0,85 / 1,04 | 0,96 / 1,19 | 1,26 / 1,43 | 1,10 / 1,28 | 2,42 / 2,73 | 0,35× | 12570 / 12555 |
| `golden/borders-tagged-ua1` | 0,56 / 0,66 | 0,69 / 0,85 | 0,82 / 0,97 | 0,68 / 0,84 | 1,57 / 1,80 | 0,36× | 12943 / 12955 |
| `golden/decorative-image-ua1` | 0,36 / 0,43 | 0,52 / 0,64 | 0,51 / 0,64 | 0,39 / 0,58 | 1,10 / 1,31 | 0,33× | 5737 / 5762 |
| `golden/inline-box-lang-ua1` | 0,56 / 0,67 | 0,70 / 0,98 | 0,82 / 1,00 | 0,67 / 0,90 | 1,59 / 1,81 | 0,35× | 12819 / 12835 |
| `golden/heading-levels-ua1` | 0,85 / 0,99 | 0,96 / 1,17 | 1,25 / 1,49 | 1,09 / 1,43 | 2,36 / 2,68 | 0,36× | 16979 / 16995 |
| `golden/media-print` | 0,30 / 0,52 | 0,45 / 0,57 | 0,42 / 0,70 | 0,33 / 0,66 | 0,84 / 1,26 | 0,35× | 4601 / 4617 |
| `golden/inline-span-background-image` | 0,75 / 0,85 | 0,86 / 1,01 | 1,10 / 1,24 | 0,96 / 1,16 | 1,71 / 1,99 | 0,43× | 12584 / 12542 |
| `golden/inline-span-background-clip-text-nested` | 1,12 / 1,27 | 1,25 / 1,74 | 1,54 / 1,91 | 1,41 / 1,83 | 2,15 / 2,55 | 0,52× | 19352 / 19194 |
| `golden/inline-span-background-clip-text-decoration` | 1,15 / 1,27 | 1,26 / 1,46 | 1,63 / 1,85 | 1,53 / 1,75 | 2,28 / 2,60 | 0,51× | 19111 / 18973 |
| `golden/background-clip-text-descendants` | 2,26 / 2,47 | 2,44 / 2,50 | 3,10 / 3,37 | 3,03 / 3,25 | 3,81 / 4,14 | 0,59× | 38990 / 38302 |
| `golden/background-clip-text-reach` | 1,07 / 1,21 | 1,19 / 1,40 | 1,45 / 1,68 | 1,31 / 1,57 | 2,03 / 2,35 | 0,53× | 17665 / 17505 |
| `golden/inline-span-box-decoration-break-clone` | 0,44 / 0,55 | 0,54 / 0,66 | 0,65 / 0,75 | 0,55 / 0,70 | 1,09 / 1,30 | 0,40× | 6218 / 6233 |
| `golden/sided-avoid-page-breaks` | 0,65 / 0,79 | 0,78 / 0,92 | 1,03 / 1,09 | 0,88 / 1,10 | 2,03 / 2,36 | 0,32× | 7854 / 7864 |
| `golden/avoid-break-out-of-flow-overflow` | 0,53 / 0,62 | 0,66 / 0,78 | 0,81 / 0,98 | 0,67 / 0,98 | 1,62 / 1,86 | 0,33× | 6622 / 6647 |
| `golden/img-without-source-past-page` | 0,39 / 0,48 | 0,54 / 0,70 | 0,57 / 0,68 | 0,45 / 0,59 | 1,14 / 1,36 | 0,34× | 5627 / 5639 |
| `golden/flex-item-margin-past-page` | 0,42 / 0,48 | 0,52 / 0,68 | 0,58 / 0,69 | 0,47 / 0,63 | 1,22 / 1,46 | 0,34× | 5588 / 5521 |
| `golden/flex-item-child-break-after` | 0,52 / 0,61 | 0,63 / 0,74 | 0,78 / 0,92 | 0,65 / 0,83 | 1,44 / 1,73 | 0,36× | 6634 / 6185 |
| `golden/flex-item-table-row-break-after` | 0,53 / 0,65 | 0,65 / 0,87 | 0,78 / 0,93 | 0,64 / 0,86 | 1,45 / 1,62 | 0,37× | 6290 / 5859 |
| `golden/floated-flex-item-break-after` | 0,43 / 0,54 | 0,55 / 0,69 | 0,62 / 0,75 | 0,50 / 0,67 | 1,17 / 1,37 | 0,37× | 5884 / 5431 |
| `golden/break-after-with-running-absolute` | 0,51 / 0,62 | 0,61 / 0,85 | 0,76 / 0,87 | 0,63 / 0,86 | 1,60 / 1,94 | 0,32× | 6240 / 6728 |
| `golden/paged-offpage-clips` | 0,72 / 0,80 | 0,87 / 0,99 | 1,18 / 1,30 | 1,04 / 1,19 | 2,07 / 2,31 | 0,35× | 11121 / 10685 |
| `golden/paged-nested-flex-forced-break` | 0,38 / 0,49 | 0,52 / 0,67 | 0,56 / 0,67 | 0,45 / 0,60 | 1,28 / 1,51 | 0,30× | 5308 / 5328 |
| `golden/svg-singular-gradient-transform` | 0,16 / 0,25 | 0,28 / 0,37 | 0,25 / 0,36 | 0,19 / 0,31 | 0,53 / 0,75 | 0,31× | 3154 / 3169 |
| `golden/svg-filters-masks-and-patterns` | 0,15 / 0,22 | 0,27 / 0,36 | 0,23 / 0,30 | 0,18 / 0,27 | 0,49 / 0,69 | 0,31× | 3137 / 3153 |
| `golden/svg-embedded-png` | 0,21 / 0,30 | 0,37 / 0,46 | 0,42 / 0,51 | 0,35 / 0,48 | 0,66 / 0,87 | 0,32× | 9031 / 9048 |
| `golden/svg-with-color-filter` | 0,55 / 0,68 | 0,70 / 0,82 | 0,91 / 1,06 | 0,81 / 1,01 | 1,84 / 2,05 | 0,30× | 8290 / 8312 |
| `golden/inline-outlines` | 0,47 / 0,57 | 0,59 / 0,71 | 0,71 / 0,89 | 0,59 / 0,80 | 1,20 / 1,39 | 0,39× | 6733 / 6747 |
| `golden/inline-zero-sized-parents` | 0,47 / 0,56 | 0,58 / 0,76 | 0,70 / 0,80 | 0,59 / 0,75 | 1,24 / 1,45 | 0,38× | 6165 / 6183 |
| `golden/background-clip-border-area-gaps` | 0,20 / 0,28 | 0,34 / 0,45 | 0,32 / 0,41 | 0,26 / 0,36 | 0,61 / 0,82 | 0,34× | 4946 / 4960 |
| `golden/paged-clone-decorations` | 1,18 / 1,23 | 1,27 / 1,50 | 1,91 / 2,16 | 1,77 / 2,10 | 3,61 / 3,90 | 0,33× | 9632 / 9553 |
| `golden/paged-transforms` | 0,21 / 0,29 | 0,38 / 0,46 | 0,32 / 0,40 | 0,25 / 0,37 | 0,72 / 0,92 | 0,28× | 2802 / 2814 |
| `golden/paged-overflow-clip-stitched` | 0,11 / 0,18 | 0,23 / 0,31 | 0,15 / 0,23 | 0,11 / 0,19 | 0,42 / 0,61 | 0,25× | 2162 / 2181 |
| `golden/paged-rounded-clip-stitched` | 0,15 / 0,22 | 0,27 / 0,39 | 0,22 / 0,29 | 0,16 / 0,25 | 0,55 / 0,77 | 0,27× | 3064 / 3080 |
| `golden/paged-transform-past-the-last-page` | 0,11 / 0,16 | 0,23 / 0,32 | 0,15 / 0,23 | 0,11 / 0,18 | 0,41 / 0,58 | 0,26× | 2457 / 2472 |
| `golden/paged-monolithic-overflow` | 0,58 / 0,70 | 0,69 / 0,83 | 0,88 / 1,09 | 0,74 / 1,00 | 1,72 / 2,06 | 0,34× | 7149 / 7152 |
| `golden/paged-clipped-overflow` | 0,13 / 0,18 | 0,29 / 0,37 | 0,20 / 0,27 | 0,15 / 0,22 | 0,46 / 0,61 | 0,29× | 2174 / 2171 |
| `golden/paged-images` | 0,46 / 0,57 | 0,59 / 0,74 | 0,66 / 0,86 | 0,54 / 0,71 | 1,53 / 1,85 | 0,30× | 6895 / 6919 |
| `golden/list-marker-pagination` | 0,47 / 0,56 | 0,60 / 0,74 | 0,70 / 0,90 | 0,57 / 0,76 | 1,52 / 1,81 | 0,31× | 5713 / 5723 |
| `golden/outline-over-content` | 0,24 / 0,33 | 0,36 / 0,48 | 0,33 / 0,43 | 0,25 / 0,38 | 0,72 / 0,94 | 0,33× | 4092 / 4109 |
| `golden/outline-under-transform` | 0,24 / 0,32 | 0,37 / 0,52 | 0,32 / 0,46 | 0,24 / 0,38 | 0,74 / 0,94 | 0,33× | 4105 / 4124 |
| `golden/inline-containers` | 0,54 / 0,64 | 0,66 / 0,81 | 0,82 / 0,99 | 0,68 / 0,90 | 1,64 / 1,97 | 0,33× | 5629 / 5634 |
| `golden/font-variation-settings` | 0,70 / 0,83 | 0,85 / 1,01 | 1,05 / 1,15 | 0,92 / 1,13 | 1,78 / 2,00 | 0,39× | 11311 / 11329 |
| `golden/font-optical-sizing` | 0,44 / 0,56 | 0,58 / 0,82 | 0,63 / 0,78 | 0,52 / 0,69 | 1,25 / 1,67 | 0,35× | 7728 / 7738 |
| `golden/page-sized-boxes` | 0,13 / 0,19 | 0,28 / 0,37 | 0,19 / 0,26 | 0,14 / 0,21 | 0,48 / 0,68 | 0,27× | 2646 / 2660 |
| `golden/page-area-viewport-units` | 0,13 / 0,19 | 0,27 / 0,35 | 0,18 / 0,26 | 0,14 / 0,23 | 0,47 / 0,65 | 0,27× | 2646 / 2660 |
| `golden/stream-transform-three-pages-back` | 0,86 / 1,01 | 0,98 / 1,16 | 1,34 / 1,54 | 1,19 / 1,40 | 3,06 / 3,35 | 0,28× | 10540 / 10539 |
| `golden/stream-relative-body-bottom` | 0,98 / 1,06 | 1,09 / 1,36 | 1,55 / 1,68 | 1,42 / 1,56 | 3,53 / 3,91 | 0,28× | 8333 / 8322 |
| `golden/paged-rotated-text` | 0,50 / 0,62 | 0,63 / 0,79 | 0,70 / 0,91 | 0,56 / 0,73 | 1,30 / 1,52 | 0,39× | 7652 / 7644 |
| `golden/paged-clipped-line` | 0,43 / 0,52 | 0,58 / 0,69 | 0,64 / 0,73 | 0,53 / 0,68 | 1,16 / 1,34 | 0,37× | 6308 / 6322 |
| `golden/paged-clipped-line-at-page-edge` | 0,37 / 0,46 | 0,52 / 0,62 | 0,53 / 0,67 | 0,42 / 0,61 | 1,07 / 1,34 | 0,35× | 5239 / 5264 |
| `golden/paged-translated-text-past-the-end` | 0,49 / 0,58 | 0,63 / 0,80 | 0,65 / 0,79 | 0,54 / 0,69 | 1,17 / 1,45 | 0,41× | 8235 / 8182 |
| `golden/paged-translated-text-across-pages` | 0,51 / 0,60 | 0,64 / 0,76 | 0,67 / 0,82 | 0,56 / 0,71 | 1,24 / 1,42 | 0,41× | 8235 / 8182 |
| `docs/invoice` | 1,88 / 2,07 | 2,04 / 2,24 | 2,99 / 3,21 | 2,94 / 3,11 | 5,88 / 6,14 | 0,32× | 26208 / 26094 |
| `docs/report-repeating-header` | 7,16 / 7,34 | 7,26 / 8,10 | 13,1 / 13,3 | 13,1 / 13,8 | 25,8 / 27,3 | 0,28× | 34497 / 34052 |
| `docs/ticket` | 0,78 / 0,91 | 0,93 / 1,12 | 1,13 / 1,29 | 1,00 / 1,29 | 1,74 / 1,98 | 0,45× | 19058 / 19063 |
| `docs/multipage-text` | 6,76 / 6,99 | 7,03 / 7,29 | 12,6 / 13,2 | 12,5 / 13,0 | 13,9 / 14,3 | 0,49× | 24302 / 23586 |
| `docs/headers-footers` | 5,38 / 5,65 | 5,66 / 6,15 | 9,96 / 10,1 | 9,78 / 10,1 | 18,7 / 19,3 | 0,29× | 16361 / 15898 |
| `docs/links-outline` | 4,41 / 4,62 | 4,57 / 4,79 | 7,99 / 8,28 | 7,93 / 8,21 | 16,1 / 16,7 | 0,27× | 29168 / 28260 |
| `docs/images` | 1,16 / 1,45 | 1,44 / 1,78 | 1,66 / 1,95 | 1,61 / 1,80 | 2,17 / 2,60 | 0,53× | 407889 / 407901 |
| `docs/images-viewport` | 1,11 / 1,28 | 1,39 / 1,59 | 1,60 / 1,89 | 1,58 / 1,81 | 2,03 / 2,30 | 0,55× | 407778 / 407788 |
| `docs/effects` | 1,01 / 1,12 | 1,15 / 1,34 | 1,42 / 1,58 | 1,29 / 1,55 | 2,02 / 2,19 | 0,50× | 19733 / 19643 |
| `docs/intl-rtl-cjk-emoji` | 1,90 / 2,09 | 2,06 / 2,18 | 2,92 / 3,17 | 2,76 / 2,97 | 4,24 / 4,52 | 0,45× | 39593 / 39475 |
| `docs/tagged-ua1` | 1,15 / 1,33 | 1,28 / 1,94 | 1,72 / 2,05 | 1,58 / 1,91 | 3,02 / 3,65 | 0,38× | 27462 / 27439 |
| `docs/tagged-ua2-pdfa4` | 1,17 / 1,27 | 1,31 / 1,52 | 1,74 / 1,98 | 1,60 / 1,84 | 2,95 / 3,32 | 0,40× | 28791 / 28758 |
| `docs/attachments` | 1,95 / 2,08 | 2,07 / 2,39 | 3,03 / 3,27 | 2,86 / 3,05 | 5,92 / 6,19 | 0,33× | 26817 / 26698 |
| `docs/invoice-pdfa-2b` | 1,93 / 2,07 | 2,08 / 2,26 | 3,03 / 3,25 | 2,91 / 3,13 | 5,85 / 6,27 | 0,33× | 29859 / 29736 |
| `docs/invoice-pdfa-2u` | 1,93 / 2,06 | 2,08 / 2,34 | 3,06 / 3,18 | 2,87 / 3,20 | 5,85 / 6,16 | 0,33× | 29859 / 29736 |
| `docs/invoice-pdfa-2a` | 1,92 / 1,97 | 2,07 / 2,53 | 3,03 / 3,27 | 2,97 / 3,09 | 5,82 / 6,14 | 0,33× | 29867 / 29741 |
| `docs/invoice-pdfa-3b` | 1,94 / 2,14 | 2,10 / 2,30 | 3,07 / 3,33 | 2,89 / 3,16 | 5,83 / 6,09 | 0,33× | 30977 / 30848 |
| `docs/invoice-pdfa-3u` | 1,94 / 2,17 | 2,09 / 2,28 | 3,10 / 3,25 | 2,94 / 3,31 | 5,82 / 6,31 | 0,33× | 30977 / 30848 |
| `docs/invoice-pdfa-3a` | 1,98 / 2,22 | 2,12 / 2,44 | 3,04 / 3,22 | 2,94 / 3,12 | 5,80 / 6,16 | 0,34× | 30985 / 30857 |
| `docs/invoice-pdfa-4` | 1,93 / 2,08 | 2,01 / 2,23 | 3,04 / 3,34 | 2,87 / 3,17 | 5,87 / 6,24 | 0,33× | 27489 / 27351 |
| `docs/invoice-pdfa-4f` | 1,95 / 2,06 | 2,13 / 2,33 | 3,07 / 3,40 | 2,91 / 3,14 | 5,89 / 6,26 | 0,33× | 28893 / 28754 |
| `stress/1p` | 1,95 / 2,03 | 2,17 / 2,34 | 3,22 / 3,45 | 3,11 / 3,29 | 6,90 / 7,28 | 0,28× | 27560 / 27389 |
| `stress/10p` | 13,9 / 15,0 | 14,3 / 14,7 | 24,8 / 25,0 | 24,8 / 25,2 | 68,2 / 69,6 | 0,20× | 61623 / 59608 |

median / p95 ms.
<!-- /pdf-bench:per-doc -->

</details>

## Giai đoạn 4 — native Node.js

Bốn engine trên cùng một máy, cùng Node, cùng 250 fixture, cùng font, cùng ảnh, cùng kích thước đầu ra:
**bm-native** (addon Node-API của bm-engine, `native/dist/win32-x64-msvc`), **bm-wasm** (bản wasm profile `full`),
**takumi-native** (`@takumi-rs/core`) và **takumi-wasm** (`@takumi-rs/wasm`). Mọi bảng trong phần này được sinh từ
`docs/results-native.json` bởi `node bench/run-native.mjs` (giữa các comment `native-bench`); không con số nào được gõ tay.
Trang tóm tắt bằng tiếng Anh và tiếng Việt: [en/native-vs-wasm.md](en/native-vs-wasm.md), [vi/native-vs-wasm.md](vi/native-vs-wasm.md).

### Điều kiện đo

<!-- native-bench:env -->
| Mục | Giá trị |
|:--|:--|
| Máy | Intel(R) Core(TM) i3-10100 CPU @ 3.60GHz, 8 CPU logic, 7.80 GiB, win32 10.0.26200 x64 |
| Node.js | v26.13.0 (V8 14.6.202.34-node.40, N-API 10, libuv 1.52.1) |
| bm-engine | 0.1.0, git `e5c535cbbf` (main, 3 file đang sửa) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 3 327 KiB, Zig 0.17.1, ReleaseFast, sha256 `1d5ff5ea0a4f` |
| bm-wasm | `js/bm_engine.wasm` (profile full), 1 144 KiB, sha256 `a7e1528586ac` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Lần chạy | 2026-11-13 04:23 UTC, chế độ full, 250 fixtures, 16.0 min; CPU bận trước khi chạy: 5.00 % |
<!-- /native-bench:env -->

### Tóm tắt

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

### Phương pháp

- **API và tính công bằng.** bm có `renderSync` (thread gọi) và `render` (bản native: thread pool libuv; bản wasm:
  cùng công việc trên main thread). takumi-native chỉ có `render` async (một `AsyncTask` của napi-rs trên pool libuv,
  bên trong dùng thread pool rayon riêng cho một phần công việc). takumi-wasm được gọi qua `render` công khai (wrapper
  async, mỗi lần gọi chạy thêm bước `needs` rồi render trên main thread). Vì vậy có năm biến thể: bm-native sync,
  bm-native async, bm-wasm sync, takumi-native async, takumi-wasm; phép so "cùng kiểu API" với takumi-native là
  bm-native **async**.
- **Tuỳ chọn giống hệt nhau:** `devicePixelRatio: 1`, cùng `width`/`height`, cùng `images` và `css` từng fixture
  (`bench/lib/pipeline.mjs` `renderOpts`), JPEG quality 85, WebP không có `quality` (lossless ở mọi engine). Font
  (9 file TTF) được đăng ký trước mọi phép đo, một renderer cho mỗi bộ font, cho mỗi engine.
- **PNG:** không engine nào cho chỉnh mức nén. bm dùng bộ deflate riêng (mức mặc định duy nhất); takumi dùng `png` +
  `zlib-rs`, thử trên mẫu 1/32 số hàng giữa level 7 / không lọc và level 3 / lọc thích ứng rồi chọn cái nhỏ hơn, nén
  thành nhiều đoạn — song song trên bản native. Không thể đặt hai bên về cùng một mức, nên thời gian PNG luôn được
  ghi kèm dung lượng file.
- **Đo thời gian:** mỗi fixture, mỗi định dạng (raw, png; thêm jpeg và webp cho 3 fixture): 3 lần khởi động mỗi biến
  thể, sau đó các vòng mà trong mỗi vòng mọi biến thể render một lần theo thứ tự xoay vòng (A,B,C,D,E rồi B,C,D,E,A…),
  tối thiểu 15 vòng và 150 ms, tối đa 2.5 s. Ghi median, p95, min, số byte đầu ra, và thời gian CPU của tiến trình
  trong các lời gọi (để thấy một lần render dùng bao nhiêu lõi).
- **Ba lượt** toàn bộ bộ fixture, mỗi lượt là một tiến trình mới, ở ba thời điểm khác nhau (xen giữa các giai đoạn
  đo khác). Số của từng fixture = median của ba median; geomean tính trên các fixture mà cả năm biến thể đều đo được;
  "±" = nửa khoảng chênh giữa geomean của ba lượt so với median; ⚠ khi khoảng chênh vượt 10 %.
- **Tải hệ thống:** trước và trong mỗi giai đoạn, `os.cpus()` được lấy mẫu mỗi giây; "tiến trình khác" = lõi-giây
  bận của cả máy trừ thời gian CPU của chính benchmark. Các agent khác build/test trên cùng máy trong lúc đo, nên số
  tuyệt đối có nhiễu; tỉ lệ giữa các engine (đo xen kẽ trong cùng fixture) ổn định hơn số tuyệt đối.
- **Cold start:** spawn `node` → import engine như người dùng (`bm-engine` = `js/node.mjs`, wasm qua
  `BM_ENGINE_BACKEND=wasm`; `@takumi-rs/core`; `@takumi-rs/wasm` + `initSync`) → đăng ký Inter Regular → PNG og card
  1200×630 → thoát; ≥ 30 lần mỗi engine, xen kẽ; trừ median của một tiến trình Node rỗng đọc cùng file.
- **Bộ nhớ:** một tiến trình mỗi engine, render cả bộ (raw + PNG) 10 lượt, đo sau GC cưỡng bức; RSS đỉnh của một PNG
  4000×4000 trong tiến trình riêng.
- **Event loop:** một `setInterval` 1 ms ghi khoảng cách giữa các lần chạy trong lúc một việc nặng chạy, với một chuỗi
  `setImmediate` để vòng lặp không ngủ (trên Windows, vòng lặp rảnh thức theo đồng hồ 15.6 ms).
- **Thông lượng:** og card PNG, N client vòng kín (N = 1, 2, 4, 8, 16), mỗi điểm 2 s sau khi khởi động; bm-native một
  renderer, K renderer (K = 1, 2, 4, 8) với `UV_THREADPOOL_SIZE` 4 (mặc định) và 8; takumi-native một renderer và
  K renderer; bm-wasm và takumi-wasm trong pool `worker_threads` K worker (công thức của
  `docs/examples/frameworks/lib/pool.mjs`).
- **Tương đương:** bộ so sánh có sẵn (`bench/lib/metrics.mjs`) cho raw RGBA của từng engine so với takumi-wasm; thêm so
  từng byte raw và PNG giữa hai bản build của mỗi engine; và `bench/native-identity.mjs` (bm-native == bm-wasm trên
  raw, PNG, JPEG, WebP, measure, SVG, animation, ICO, HTML, ảnh, WOFF2, lỗi).

### So với số đo takumi-native ở giai đoạn 1

<!-- native-bench:phase1 -->
<!-- /native-bench:phase1 -->

Giai đoạn 1 đo takumi-native một lần trên 78 fixture, bằng `await render()` từng engine một (không xen kẽ từng vòng),
với bản bm wasm của giai đoạn 1; cold start khi đó là thời gian trong tiến trình (init + font + PNG đầu tiên), không
gồm khởi động Node. Bộ fixture nay là 200 ca (thêm stylesheet, Tailwind, HTML, bảng, float, 42 ca animation, layout
inline…), nên geomean không so trực tiếp được với số cũ; cột "bỏ known-gaps" bỏ 9 ca vốn là khoảng trống của giai
đoạn 1.

### Thời gian render

<!-- native-bench:speed -->
| Định dạng (số fixture) | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| raw (250) | 0.45 ±2.15 % | 0.47 ±2.25 % | 0.74 ±2.15 % | 0.86 ±2.10 % | 1.19 ±2.35 % |
| png (250) | 0.95 ±1.95 % | 0.90 ±2.30 % | 1.41 ±1.55 % | 1.66 ±1.55 % | 3.03 ±1.65 % |
| jpeg (3) | 11.1 ±2.90 % | 11.3 ±2.40 % | 18.3 ±1.95 % | 17.5 ±2.45 % | 24.2 ±2.50 % |
| webp (3) | 8.71 ±3.15 % | 8.87 ±2.65 % | 12.4 ±2.55 % | 66.6 ±2.20 % | 15.8 ±2.35 % |
| raw, bỏ known-gaps | 0.47 | 0.48 | 0.76 | 0.87 | 1.21 |
| png, bỏ known-gaps | 0.97 | 0.92 | 1.44 | 1.69 | 3.07 |
| raw, từng lượt | 0.46 / 0.47 / 0.45 | 0.47 / 0.48 / 0.46 | 0.74 / 0.76 / 0.73 | 0.86 / 0.89 / 0.85 | 1.19 / 1.23 / 1.17 |
| png, từng lượt | 0.96 / 0.98 / 0.94 | 0.91 / 0.94 / 0.90 | 1.42 / 1.45 / 1.41 | 1.67 / 1.70 / 1.65 | 3.04 / 3.11 / 3.01 |

Trung bình nhân của thời gian render median từng fixture, ms. jpeg (quality 85) và webp (lossless; takumi-wasm dùng bộ mã hoá WebP khác takumi-native, xem bảng định dạng) chỉ đo trên ba fixture.
<!-- /native-bench:speed -->

<!-- native-bench:cpu -->
| Biến thể | raw: thực / CPU ms / lõi | PNG: thực / CPU ms / lõi |
|:--|--:|--:|
| bm-native sync | 0.41 / 0.38 / 0.91 | 1.16 / 1.00 / 0.87 |
| bm-native async | 0.46 / 1.30 / 2.81 | 1.15 / 1.98 / 1.73 |
| bm-wasm sync | 0.66 / 0.51 / 0.77 | 1.71 / 1.30 / 0.76 |
| takumi-native async | 0.78 / 1.41 / 1.80 | 1.61 / 3.20 / 1.98 |
| takumi-wasm | 1.06 / 0.78 / 0.73 | 3.50 / 2.84 / 0.81 |

Trung bình trên mọi lần render được đo (không phải geomean): thời gian thực mỗi lần render, thời gian CPU của tiến trình (mọi thread) trong lúc đó, và tỉ số. Tỉ số trên 1 nghĩa là một lần render dùng hơn một lõi.
<!-- /native-bench:cpu -->

Theo nhóm fixture:

<!-- native-bench:categories -->
| Nhóm | n | raw bm-n sync | raw bm-n async | raw bm-w | raw tk-n | raw tk-w | raw bm-n/tk-n | png bm-n sync | png bm-n async | png bm-w | png tk-n | png tk-w | png bm-n/tk-n |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| aa-exact | 2 | 0.29 | 0.29 | 0.46 | 0.54 | 0.75 | 0.53× | 0.63 | 0.61 | 0.92 | 1.09 | 1.68 | 0.56× |
| absolute | 3 | 0.66 | 0.67 | 1.02 | 0.84 | 1.23 | 0.80× | 1.33 | 1.21 | 2.02 | 2.33 | 5.46 | 0.52× |
| animation | 44 | 0.14 | 0.15 | 0.23 | 0.30 | 0.39 | 0.49× | 0.22 | 0.21 | 0.33 | 0.57 | 0.84 | 0.36× |
| backdrop-filter | 1 | 1.33 | 1.34 | 2.59 | 2.46 | 4.25 | 0.54× | 2.18 | 2.17 | 3.98 | 3.21 | 7.36 | 0.68× |
| bg-blend | 1 | 0.69 | 0.71 | 1.07 | 3.70 | 4.84 | 0.19× | 2.92 | 2.95 | 4.25 | 4.75 | 10.4 | 0.62× |
| bg-clip-text | 1 | 0.42 | 0.41 | 0.59 | 1.81 | 2.75 | 0.23× | 1.50 | 1.49 | 2.15 | 2.66 | 5.31 | 0.56× |
| block-in-inline | 4 | 0.34 | 0.32 | 0.52 | 0.75 | 0.98 | 0.43× | 0.62 | 0.57 | 0.89 | 1.25 | 1.78 | 0.46× |
| blog-card | 2 | 3.76 | 3.82 | 6.46 | 4.96 | 10.3 | 0.77× | 10.1 | 10.1 | 15.7 | 8.73 | 30.4 | 1.15× |
| border-radius | 4 | 0.72 | 0.73 | 1.08 | 0.78 | 1.02 | 0.93× | 1.33 | 1.21 | 1.87 | 2.14 | 4.23 | 0.57× |
| borders | 3 | 0.72 | 0.75 | 1.10 | 0.98 | 1.36 | 0.76× | 1.20 | 1.06 | 1.78 | 2.19 | 4.12 | 0.49× |
| box-shadow | 4 | 1.79 | 1.83 | 3.30 | 3.84 | 5.99 | 0.48× | 4.50 | 4.52 | 7.48 | 5.52 | 15.9 | 0.82× |
| clip-path | 1 | 0.41 | 0.42 | 0.72 | 0.65 | 1.01 | 0.66× | 1.31 | 1.30 | 1.99 | 1.46 | 5.38 | 0.89× |
| colors | 5 | 0.65 | 0.69 | 1.04 | 1.07 | 1.64 | 0.65× | 0.96 | 0.89 | 1.46 | 2.23 | 3.98 | 0.40× |
| css-stylesheet | 8 | 0.52 | 0.52 | 0.79 | 0.82 | 1.06 | 0.63× | 0.86 | 0.79 | 1.27 | 1.80 | 3.03 | 0.44× |
| dashed-border | 1 | 0.86 | 0.87 | 1.41 | 1.36 | 2.48 | 0.63× | 1.07 | 1.07 | 1.70 | 1.88 | 3.29 | 0.57× |
| dotted-border | 1 | 0.87 | 0.91 | 1.55 | 1.56 | 2.83 | 0.59× | 1.15 | 1.14 | 1.88 | 2.10 | 3.68 | 0.54× |
| double-3d-border | 1 | 0.30 | 0.32 | 0.55 | 0.52 | 0.74 | 0.61× | 0.51 | 0.48 | 0.78 | 0.98 | 1.46 | 0.49× |
| drop-shadow | 1 | 0.79 | 0.78 | 1.29 | 1.09 | 1.65 | 0.71× | 2.21 | 2.17 | 3.44 | 1.88 | 6.89 | 1.15× |
| emoji | 5 | 0.13 | 0.13 | 0.20 | 0.45 | 0.59 | 0.28× | 0.50 | 0.47 | 0.71 | 0.76 | 0.99 | 0.62× |
| filter | 1 | 0.66 | 0.66 | 1.31 | 1.25 | 1.91 | 0.52× | 1.74 | 1.73 | 2.94 | 1.93 | 4.90 | 0.89× |
| flex | 5 | 0.79 | 0.81 | 1.23 | 0.98 | 1.34 | 0.82× | 1.29 | 1.15 | 1.97 | 2.36 | 4.64 | 0.49× |
| float | 4 | 0.26 | 0.28 | 0.48 | 0.53 | 0.70 | 0.53× | 0.69 | 0.65 | 1.05 | 1.24 | 2.49 | 0.52× |
| float-paint-order | 3 | 0.36 | 0.35 | 0.57 | 0.72 | 0.95 | 0.49× | 0.66 | 0.63 | 0.96 | 1.19 | 1.63 | 0.53× |
| float-text | 7 | 0.48 | 0.48 | 0.75 | 0.77 | 1.07 | 0.62× | 1.10 | 1.06 | 1.57 | 1.58 | 2.73 | 0.67× |
| font-variant | 3 | 0.39 | 0.39 | 0.58 | 0.88 | 1.13 | 0.44× | 1.12 | 1.08 | 1.56 | 1.76 | 3.04 | 0.61× |
| fonts | 2 | 1.20 | 1.23 | 1.63 | 1.95 | 2.68 | 0.63× | 3.30 | 3.17 | 4.55 | 4.13 | 8.64 | 0.77× |
| grid | 4 | 0.84 | 0.88 | 1.33 | 1.28 | 1.73 | 0.69× | 1.53 | 1.42 | 2.29 | 2.83 | 5.62 | 0.50× |
| grid-areas | 3 | 0.32 | 0.32 | 0.58 | 0.61 | 0.83 | 0.52× | 0.67 | 0.60 | 1.01 | 1.33 | 2.09 | 0.46× |
| html | 4 | 0.71 | 0.73 | 1.04 | 1.20 | 1.59 | 0.61× | 1.60 | 1.51 | 2.27 | 2.61 | 4.73 | 0.58× |
| images | 7 | 0.86 | 0.94 | 1.64 | 2.62 | 3.67 | 0.36× | 7.88 | 7.98 | 12.0 | 5.75 | 21.1 | 1.39× |
| inline-bidi | 3 | 0.50 | 0.48 | 0.79 | 1.00 | 1.34 | 0.48× | 0.89 | 0.85 | 1.31 | 1.61 | 2.37 | 0.53× |
| inline-block | 4 | 0.28 | 0.29 | 0.47 | 0.56 | 0.73 | 0.52× | 0.67 | 0.63 | 1.00 | 1.13 | 1.84 | 0.56× |
| inline-box | 1 | 1.27 | 1.28 | 2.09 | 1.93 | 2.84 | 0.66× | 2.43 | 2.40 | 3.75 | 2.88 | 5.32 | 0.83× |
| inline-box-model | 4 | 0.69 | 0.69 | 1.10 | 1.15 | 1.54 | 0.60× | 1.45 | 1.41 | 2.15 | 2.02 | 3.57 | 0.70× |
| inline-flow | 5 | 0.45 | 0.45 | 0.77 | 0.82 | 1.08 | 0.55× | 1.07 | 1.03 | 1.61 | 1.55 | 2.78 | 0.67× |
| inline-relative | 1 | 0.47 | 0.46 | 0.71 | 1.00 | 1.26 | 0.47× | 0.84 | 0.82 | 1.21 | 1.53 | 2.01 | 0.53× |
| known-gaps | 9 | 0.24 | 0.26 | 0.41 | 0.52 | 0.74 | 0.51× | 0.55 | 0.53 | 0.82 | 1.10 | 2.12 | 0.48× |
| linear-gradient | 4 | 1.43 | 1.48 | 2.37 | 2.80 | 4.04 | 0.53× | 4.25 | 4.22 | 6.44 | 4.75 | 17.0 | 0.89× |
| mask | 1 | 0.71 | 0.73 | 1.20 | 1.06 | 1.64 | 0.69× | 1.55 | 1.53 | 2.30 | 1.92 | 6.30 | 0.79× |
| mix-blend | 1 | 0.77 | 0.77 | 1.32 | 1.11 | 1.92 | 0.69× | 2.70 | 2.72 | 4.12 | 2.15 | 7.59 | 1.27× |
| mixed-border | 1 | 0.46 | 0.46 | 0.78 | 0.71 | 1.22 | 0.65× | 0.73 | 0.69 | 1.11 | 1.25 | 2.08 | 0.55× |
| og-card | 2 | 1.58 | 1.60 | 2.42 | 2.87 | 4.13 | 0.56× | 6.09 | 6.12 | 8.95 | 5.11 | 13.1 | 1.20× |
| opacity | 4 | 1.28 | 1.26 | 2.31 | 2.56 | 5.19 | 0.49× | 2.07 | 1.96 | 3.41 | 3.84 | 8.84 | 0.51× |
| outline | 1 | 0.53 | 0.55 | 0.90 | 1.02 | 1.70 | 0.54× | 0.80 | 0.79 | 1.23 | 1.59 | 2.66 | 0.50× |
| overflow | 3 | 0.72 | 0.75 | 1.10 | 1.25 | 1.69 | 0.60× | 1.50 | 1.42 | 2.15 | 2.66 | 5.58 | 0.53× |
| pseudo-elements | 4 | 0.36 | 0.39 | 0.61 | 0.69 | 0.94 | 0.56× | 0.73 | 0.65 | 1.05 | 1.38 | 2.45 | 0.47× |
| radial-gradient | 3 | 1.22 | 1.27 | 1.88 | 3.90 | 4.83 | 0.33× | 8.35 | 8.35 | 11.5 | 6.81 | 24.2 | 1.23× |
| rtl | 5 | 0.28 | 0.28 | 0.49 | 0.57 | 0.71 | 0.50× | 0.45 | 0.43 | 0.70 | 0.98 | 1.36 | 0.44× |
| sizing | 5 | 0.60 | 0.62 | 0.87 | 0.75 | 1.00 | 0.83× | 1.01 | 0.92 | 1.48 | 2.36 | 4.58 | 0.39× |
| stress | 3 | 7.14 | 7.78 | 11.6 | 11.6 | 16.0 | 0.67× | 15.3 | 15.4 | 23.4 | 16.5 | 35.6 | 0.93× |
| svg-image | 1 | 0.66 | 0.65 | 1.37 | 0.61 | 0.94 | 1.08× | 1.08 | 1.05 | 1.89 | 1.28 | 2.26 | 0.82× |
| table | 8 | 0.50 | 0.50 | 0.84 | 1.00 | 1.35 | 0.50× | 0.89 | 0.83 | 1.36 | 1.62 | 2.62 | 0.51× |
| tailwind | 8 | 0.62 | 0.64 | 0.94 | 0.91 | 1.26 | 0.70× | 0.95 | 0.88 | 1.40 | 1.77 | 2.95 | 0.50× |
| text-decoration | 1 | 1.09 | 1.09 | 1.83 | 1.27 | 1.80 | 0.86× | 1.85 | 1.81 | 2.84 | 2.03 | 3.62 | 0.89× |
| text-i18n | 2 | 1.13 | 1.19 | 1.52 | 1.73 | 2.35 | 0.69× | 2.82 | 2.65 | 3.83 | 3.75 | 7.70 | 0.71× |
| text-indent | 4 | 0.47 | 0.46 | 0.73 | 0.88 | 1.18 | 0.52× | 1.00 | 0.97 | 1.42 | 1.58 | 2.50 | 0.62× |
| text-overflow | 4 | 0.32 | 0.31 | 0.47 | 0.80 | 1.02 | 0.38× | 0.64 | 0.61 | 0.89 | 1.33 | 1.97 | 0.46× |
| text-paragraph | 5 | 1.06 | 1.14 | 1.56 | 1.66 | 2.33 | 0.69× | 2.50 | 2.39 | 3.53 | 3.48 | 6.88 | 0.69× |
| text-shadow | 1 | 0.61 | 0.61 | 1.10 | 0.83 | 1.15 | 0.73× | 2.67 | 2.67 | 4.00 | 2.03 | 4.39 | 1.32× |
| text-single-line | 3 | 0.63 | 0.64 | 0.88 | 1.08 | 1.47 | 0.59× | 1.57 | 1.48 | 2.19 | 2.52 | 4.63 | 0.59× |
| text-stroke | 2 | 0.80 | 0.82 | 1.33 | 0.70 | 0.95 | 1.16× | 1.34 | 1.33 | 2.06 | 1.40 | 2.39 | 0.95× |
| text-truncation | 3 | 0.72 | 0.75 | 1.06 | 1.23 | 1.69 | 0.61× | 1.30 | 1.17 | 1.87 | 2.35 | 4.31 | 0.50× |
| text-wrap-balance | 3 | 0.63 | 0.60 | 0.97 | 1.13 | 1.55 | 0.53× | 1.15 | 1.13 | 1.67 | 1.79 | 2.84 | 0.63× |
| transform | 5 | 0.59 | 0.62 | 0.96 | 1.31 | 2.11 | 0.47× | 1.07 | 1.02 | 1.59 | 2.22 | 4.14 | 0.46× |
| visibility | 1 | 0.16 | 0.17 | 0.26 | 0.38 | 0.48 | 0.47× | 0.26 | 0.23 | 0.38 | 0.84 | 1.26 | 0.28× |

Geomean ms theo nhóm fixture. bm-n = bm-native, bm-w = bm-wasm (sync), tk-n = takumi-native (async), tk-w = takumi-wasm; tỉ lệ = bm-native async / takumi-native async (dưới 1× = bm nhanh hơn).
<!-- /native-bench:categories -->

bm-native so với takumi-native (cùng async):

<!-- native-bench:best-worst -->
**raw — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-jpeg-fit` | 1.37 | 1.45 | 11.9 | 1.30 | 0.12× |
| `pfx-bg-blend` | 0.69 | 0.71 | 3.70 | 0.92 | 0.19× |
| `pfx-bg-clip-text` | 0.42 | 0.41 | 1.81 | 1.07 | 0.23× |
| `gap-background-clip-text` | 0.27 | 0.30 | 1.30 | 1.28 | 0.23× |
| `fix-text-emoji-spacing` | 0.13 | 0.14 | 0.52 | 1.72 | 0.26× |
| `fix-text-emoji-wrap` | 0.12 | 0.13 | 0.48 | 1.66 | 0.26× |
| `fix-text-emoji-zwj` | 0.13 | 0.13 | 0.48 | 2.46 | 0.27× |
| `fix-text-emoji-flags-skin` | 0.12 | 0.12 | 0.41 | 2.05 | 0.29× |
| `fix-text-emoji-keycap-vs` | 0.12 | 0.12 | 0.39 | 2.31 | 0.31× |
| `radial-shapes` | 1.97 | 1.99 | 6.30 | 1.26 | 0.32× |

**raw — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `fix-text-paint-order` | 0.77 | 0.80 | 0.67 | 2.24 | 1.20× |
| `abs-zorder` | 1.38 | 1.42 | 1.20 | 1.76 | 1.19× |
| `pfx-text-stroke` | 0.83 | 0.83 | 0.75 | 1.31 | 1.12× |
| `pfx-svg-background` | 0.66 | 0.65 | 0.61 | 2.75 | 1.08× |
| `radius-uniform-percorner` | 1.07 | 1.10 | 1.07 | 1.46 | 1.03× |
| `radius-pill-circle` | 1.09 | 1.07 | 1.06 | 3.75 | 1.01× |
| `flex-wrap-gap` | 1.34 | 1.37 | 1.42 | 1.78 | 0.97× |
| `flex-row-column` | 1.09 | 1.07 | 1.12 | 1.55 | 0.96× |
| `tw-structural` | 0.64 | 0.66 | 0.69 | 2.94 | 0.95× |
| `radius-elliptical` | 1.07 | 1.10 | 1.15 | 1.60 | 0.95× |

**png — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `colors-solid-bg` | 0.20 | 0.19 | 0.82 | 1.30 | 0.23× |
| `gap-oklch-color` | 0.18 | 0.17 | 0.72 | 0.83 | 0.24× |
| `anim-kf-option-t500` | 0.19 | 0.17 | 0.64 | 1.12 | 0.27× |
| `pfx-visibility` | 0.26 | 0.23 | 0.84 | 0.72 | 0.28× |
| `anim-alternate-t100` | 0.18 | 0.17 | 0.59 | 1.23 | 0.29× |
| `anim-opacity-t900` | 0.17 | 0.16 | 0.55 | 1.31 | 0.29× |
| `anim-opacity-t500` | 0.17 | 0.16 | 0.55 | 1.76 | 0.29× |
| `anim-alternate-t1100` | 0.18 | 0.17 | 0.58 | 1.53 | 0.29× |
| `anim-opacity-t250` | 0.17 | 0.16 | 0.54 | 1.79 | 0.30× |
| `anim-alternate-t700` | 0.17 | 0.17 | 0.56 | 1.91 | 0.30× |

**png — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-photo-bg` | 28.5 | 28.7 | 11.3 | 4.33 | 2.54× |
| `card-blog` | 18.9 | 19.1 | 11.8 | 2.51 | 1.62× |
| `radial-spotlight-small` | 4.14 | 4.14 | 2.62 | 2.80 | 1.58× |
| `img-radius-clip` | 14.6 | 14.7 | 9.53 | 2.69 | 1.54× |
| `stress-3000x2000-card` | 52.6 | 53.6 | 39.6 | 2.88 | 1.35× |
| `fx-text-shadow` | 2.67 | 2.67 | 2.03 | 3.35 | 1.32× |
| `img-intrinsic-size` | 1.76 | 1.83 | 1.40 | 2.38 | 1.31× |
| `img-png-fit` | 11.2 | 11.3 | 8.65 | 1.75 | 1.31× |
| `card-og` | 9.61 | 9.70 | 7.50 | 2.49 | 1.29× |
| `pfx-mix-blend` | 2.70 | 2.72 | 2.15 | 4.14 | 1.27× |
<!-- /native-bench:best-worst -->

<!-- native-bench:formats -->
| Fixture | Định dạng | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|--:|
| `lingrad-angles` | raw | 2.13 ms · 2 953 KiB | 2.22 ms · 2 953 KiB | 3.81 ms · 2 953 KiB | 4.47 ms · 2 953 KiB | 6.53 ms · 2 953 KiB |
| `lingrad-angles` | png | 6.49 ms · 32.6 KiB | 6.40 ms · 32.6 KiB | 9.84 ms · 32.6 KiB | 7.78 ms · 102 KiB | 34.6 ms · 102 KiB |
| `lingrad-angles` | jpeg | 11.0 ms · 52.2 KiB | 11.3 ms · 52.2 KiB | 18.7 ms · 52.2 KiB | 17.8 ms · 52.3 KiB | 24.0 ms · 52.3 KiB |
| `lingrad-angles` | webp | 7.02 ms · 28.9 KiB | 7.27 ms · 28.9 KiB | 10.4 ms · 28.9 KiB | 109 ms · 22.8 KiB | 15.3 ms · 169 KiB |
| `img-photo-bg` | raw | 1.17 ms · 2 953 KiB | 1.24 ms · 2 953 KiB | 1.66 ms · 2 953 KiB | 3.76 ms · 2 953 KiB | 5.89 ms · 2 953 KiB |
| `img-photo-bg` | png | 28.5 ms · 511 KiB | 28.7 ms · 511 KiB | 39.9 ms · 511 KiB | 11.3 ms · 513 KiB | 53.4 ms · 513 KiB |
| `img-photo-bg` | jpeg | 10.6 ms · 55.1 KiB | 10.8 ms · 55.1 KiB | 17.2 ms · 55.1 KiB | 17.6 ms · 55.2 KiB | 24.2 ms · 55.2 KiB |
| `img-photo-bg` | webp | 13.6 ms · 367 KiB | 13.8 ms · 367 KiB | 19.2 ms · 367 KiB | 160 ms · 414 KiB | 20.7 ms · 470 KiB |
| `card-flat-ui` | raw | 2.68 ms · 2 953 KiB | 2.68 ms · 2 953 KiB | 4.45 ms · 2 953 KiB | 3.65 ms · 2 953 KiB | 6.72 ms · 2 953 KiB |
| `card-flat-ui` | png | 5.39 ms · 23.1 KiB | 5.31 ms · 23.1 KiB | 8.40 ms · 23.1 KiB | 6.48 ms · 25.3 KiB | 19.2 ms · 25.3 KiB |
| `card-flat-ui` | jpeg | 11.6 ms · 48.9 KiB | 11.8 ms · 48.9 KiB | 19.1 ms · 48.9 KiB | 17.1 ms · 49.0 KiB | 24.5 ms · 49.0 KiB |
| `card-flat-ui` | webp | 6.91 ms · 18.5 KiB | 6.96 ms · 18.5 KiB | 9.66 ms · 18.5 KiB | 16.8 ms · 13.4 KiB | 12.6 ms · 27.6 KiB |

Thời gian median và dung lượng đầu ra. JPEG: quality 85 cho mọi engine. WebP: lossless cho mọi engine (không có `quality`); takumi-native mã hoá bằng libwebp, takumi-wasm bằng crate `image-webp` (nên file lớn hơn). PNG: không engine nào cho chỉnh mức nén; mỗi engine dùng mức mặc định của nó (bm: deflate riêng; takumi: `png` + `zlib-rs`, chọn giữa level 7 / không lọc và level 3 / lọc thích ứng trên một mẫu, nén thành tối đa 8 đoạn song song ở bản native), nên thời gian PNG được so kèm dung lượng file.
<!-- /native-bench:formats -->

#### bm-native thua ở đâu, và vì sao

Những gì phép đo cho thấy (bảng chẩn đoán bên dưới là một phần của mỗi lần chạy; điều gì không được nó chứng minh
thì được ghi là giả thuyết):

- **`filter: blur()` chậm hơn nhiều ở bm-engine, trên cả hai backend.** Trong cảnh animation, bỏ filter blur thì
  thời gian một khung của bm xuống dưới takumi, và riêng blur chiếm gần hết thời gian của bm; blur của takumi rẻ.
  Chính hiệu ứng này làm animation 60 khung trong bảng event loop của bm lâu hơn nhiều (takumi-native còn render
  các khung song song). *Giả thuyết, chưa profile:* bước filter của bm xử lý một vùng lớn hơn nhiều so với phần
  tử bị làm mờ. Đây là vấn đề của engine, không phải của native so với wasm.
- **Khung raw lớn, ít nội dung.** Các fixture raw thua takumi-native nhiều nhất là khung 1200×630 với các hộp
  đơn giản. Khung rỗng cho thấy cùng khoảng cách: chi phí cố định theo điểm ảnh để tạo đầu ra raw của bm (xoá,
  đổi alpha, chép ra) cao hơn takumi-native, và với API **async** của bm nó còn tăng theo kích thước khung, trong
  khi đầu ra PNG (kết quả nhỏ) không bị thiệt gì khi async. *Giả thuyết:* đường async chép hoặc cấp phát mới thêm
  một lần kết quả nhiều megabyte. Dù sao điều này chỉ ảnh hưởng `raw`.
- **PNG của ảnh lớn kiểu ảnh chụp.** takumi-native nén deflate một PNG thành nhiều đoạn trên nhiều lõi (cột "lõi
  takumi" trong bảng PNG kém nhất lớn hơn 1 khá nhiều ở phần lớn các fixture đó); bm mã hoá trên một thread. Tính chung bm
  vẫn tốn ít CPU hơn cho mỗi PNG (dòng CPU trong bảng tóm tắt), và file trung bình nhỏ hơn.
- **WebP** thì ngược lại: WebP lossless của takumi-native (libwebp, theo mã nguồn takumi) chậm hơn bm vài lần,
  file nhỏ hơn với ảnh phẳng và lớn hơn với ảnh chụp (bảng định dạng).

<!-- native-bench:diagnose -->
| Khung trắng rỗng | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| 300×200 raw | 0.10 | 0.11 | 0.18 | 0.22 | 0.29 |
| 300×200 png | 0.15 | 0.12 | 0.18 | 0.45 | 0.53 |
| 1200×630 raw | 0.70 | 0.70 | 0.97 | 0.78 | 1.09 |
| 1200×630 png | 1.11 | 0.69 | 1.24 | 2.94 | 4.88 |
| 2400×1260 raw | 2.50 | 2.66 | 4.50 | 2.77 | 4.91 |
| 2400×1260 png | 4.60 | 4.32 | 5.78 | 10.3 | 19.3 |

| Cảnh animation, một khung raw 800×420 | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| shadow + blur (as animated) | 6.85 | 6.87 | 12.9 | 16.9 | 30.1 |
| shadow only | 2.18 | 2.13 | 4.10 | 4.86 | 7.78 |
| blur only | 2.15 | 2.14 | 3.80 | 3.53 | 6.12 |
| neither | 0.93 | 0.96 | 1.50 | 1.30 | 2.04 |

Median ms, các biến thể chạy xen kẽ (40 lần cho khung rỗng, ít hơn cho cảnh). Khung rỗng không vẽ gì, nên thời gian của nó là chi phí theo điểm ảnh mà khung nào cũng trả (xoá canvas, đổi alpha, chép kết quả ra) cộng, với PNG, việc mã hoá một ảnh phẳng. Cảnh là cảnh của animation trong phép đo event loop: 12 hình tròn 60×60 xoay, có `box-shadow: 0 8px 30px` và `filter: blur(2px)`.
<!-- /native-bench:diagnose -->

### Tương đương và trùng byte

<!-- native-bench:equiv -->
| Engine so với takumi-wasm (250 fixture, raw RGBA) | identical | equivalent | close | different | error/unsupported |
|:--|--:|--:|--:|--:|--:|
| bm-native | 81 | 169 | 0 | 0 | 0 |
| bm-wasm | 81 | 169 | 0 | 0 | 0 |
| takumi-native | 250 | 0 | 0 | 0 | 0 |

| Cùng engine, hai bản build | raw RGBA trùng byte | file PNG trùng byte |
|:--|--:|--:|
| bm-native = bm-wasm | 250/250 | 250/250 |
| takumi-native = takumi-wasm | 250/250 | 250/250 |

`bench/native-identity.mjs`: 250 fixture, 2626 phép so (raw, PNG, JPEG, WebP, measure, SVG, animation, ICO, HTML, ảnh, WOFF2, thông báo lỗi, native async so với sync), 2626 trùng (121 trong số đó là cùng thông báo lỗi ở cả hai), 0 khác, 802 MB đã so.
<!-- /native-bench:equiv -->

### Cold start

<!-- native-bench:cold -->
| Engine | thực median | wall p95 | hơn Node, median | hơn Node, p95 | import | registerFont | PNG đầu tiên |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Node rỗng (mốc) | 49.1 | 68.5 | 0 | 0 | — | — | — |
| bm-native | 71.0 | 94.7 | 21.8 | 45.5 | 4.70 | 0.34 | 17.9 |
| bm-wasm | 125 | 142 | 75.5 | 93.0 | 7.10 | 2.43 | 65.4 |
| takumi-native | 95.4 | 118 | 46.2 | 69.2 | 23.1 | 0.92 | 20.2 |
| takumi-wasm | 234 | 298 | 185 | 249 | 33.7 | 3.29 | 146 |

ms. 30 lần mỗi engine, xen kẽ các engine; spawn node → import engine như người dùng → registerFont(Inter Regular) → PNG og card 1200×630 → thoát; thời gian thực = đồng hồ của tiến trình cha từ spawn tới khi thoát. Các cột import / registerFont / PNG đầu tiên là median đo bên trong tiến trình con. CPU bận trong lúc đo: trung bình 33.3 % (tiến trình khác ≈ 1.20 lõi). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 1.20 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:cold -->

### Bộ nhớ

<!-- native-bench:memory -->
| Engine | RSS sau khởi tạo | RSS sau lượt 1 → 10 | bộ nhớ engine 1 → N | JS heap 1 → N | RSS đỉnh, cả bộ | RSS đỉnh PNG 4000×4000 (tăng thêm) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 63.2 | 90.7 → 91.4 | 31.6 → 31.6 | 6.40 → 6.50 | 183 | 140 (85.6) |
| bm-wasm | 75.4 | 127 → 150 | 63.8 → 86.8 | 6.60 → 6.70 | 247 | 146 (88.9) |
| takumi-native | 67.0 | 118 → 124 | — → — | 6.60 → 6.70 | 199 | 133 (74.5) |
| takumi-wasm | 83.5 | 138 → 172 | 71.5 → 71.5 | 7.40 → 7.50 | 237 | 148 (83.3) |

MiB, sau khi ép GC. Một tiến trình cho mỗi engine; mỗi lượt render mọi fixture ra raw và PNG (API async), một renderer cho mỗi bộ font. Bộ nhớ engine: bm-native = số byte addon đang cấp phát (`memoryBytes()`), bm-wasm / takumi-wasm = bộ nhớ tuyến tính wasm, takumi-native = không công bố. Node rỗng: 41.5 MiB RSS. "Tăng thêm" = RSS đỉnh trừ RSS ngay trước lần render 4000×4000.
<!-- /native-bench:memory -->

### Event loop

<!-- native-bench:eventloop -->
| Việc | Engine | API | ms của việc | CPU ms | trễ timer lớn nhất ms | trễ p99 ms | số lần timer chạy |
|:--|--:|--:|--:|--:|--:|--:|--:|
| heavy | bm-native | sync | 211 | 219 | 211 | 211 | 1 |
| heavy | bm-native | async | 247 | 500 | 1.20 | 1.10 | 248 |
| heavy | bm-wasm | sync | 401 | 579 | 401 | 401 | 1 |
| heavy | bm-wasm | async (chạy trên main thread) | 391 | 563 | 392 | 392 | 1 |
| heavy | takumi-native | async | 242 | 671 | 13.4 | 2.00 | 231 |
| heavy | takumi-wasm | async (chạy trên main thread) | 745 | 814 | 746 | 746 | 1 |
| anim | bm-native | sync | 437 | 437 | 438 | 438 | 1 |
| anim | bm-native | async | 448 | 875 | 1.10 | 1.00 | 450 |
| anim | bm-wasm | sync | 848 | 1 015 | 848 | 848 | 1 |
| anim | bm-wasm | async (chạy trên main thread) | 872 | 1 031 | 873 | 873 | 1 |
| anim | takumi-native | async | 367 | 2 141 | 11.5 | 8.90 | 312 |
| anim | takumi-wasm | async (chạy trên main thread) | 1 848 | 2 218 | 1 848 | 1 848 | 1 |

heavy = một PNG 2400×2400: gradient, 24 thẻ với box-shadow mờ lớn, cứ ba thẻ có một thẻ `filter: blur(6px)`, chữ; anim = renderAnimation: 60 khung (2 s ở 30 fps) WebP lossless 800×420, 12 hình tròn có bóng, mờ, xoay (cảnh tĩnh). Một `setInterval` 1 ms ghi khoảng cách giữa các lần chạy trong lúc lời gọi chạy. Một chuỗi setImmediate giữ cho vòng lặp không ngủ, vì vòng lặp Node rảnh trên Windows thức theo đồng hồ hệ thống 15,6 ms và timer sẽ không bao giờ cho thấy dưới ~16 ms. Lời gọi chặn vòng lặp cho thấy một lần chạy có độ trễ bằng cả lời gọi. CPU ms là của cả tiến trình trong lúc gọi, kể cả chuỗi setImmediate trên main thread (khoảng một lõi mỗi khi vòng lặp rảnh).
<!-- /native-bench:eventloop -->

### Thông lượng khi chạy đồng thời

<!-- native-bench:throughput -->
| Engine | Cách chạy | UV_THREADPOOL_SIZE | N=1 | N=2 | N=4 | N=8 | N=16 |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 1 client, tuần tự | 4 | 109 |  |  |  |  |
| bm-wasm | 1 client, tuần tự | — | 72.3 |  |  |  |  |
| takumi-native | 1 client, tuần tự | 4 | 123 |  |  |  |  |
| takumi-wasm | 1 client, tuần tự | — | 45.6 |  |  |  |  |
| bm-native | 1 renderer, async | 4 | 104 (0.96×, 96 %) | 106 (0.98×, 98 %) | 104 (0.96×, 96 %) | 105 (0.96×, 96 %) | 105 (0.97×, 97 %) |
| bm-native | 2 renderer, async | 4 | 104 (0.95×, 95 %) | 194 (1.79×, 89 %) | 197 (1.82×, 91 %) | 205 (1.89×, 94 %) | 200 (1.84×, 92 %) |
| bm-native | 4 renderer, async | 4 | 101 (0.93×, 93 %) | 197 (1.81×, 91 %) | 371 (3.42×, 85 %) | 367 (3.39×, 85 %) | 359 (3.31×, 83 %) |
| bm-native | 8 renderer, async | 4 | 99.6 (0.92×, 92 %) | 198 (1.82×, 91 %) | 372 (3.43×, 86 %) | 369 (3.40×, 85 %) | 366 (3.38×, 84 %) |
| bm-native | 1 renderer, async | 8 | 103 (0.95×, 95 %) | 106 (0.97×, 97 %) | 105 (0.96×, 96 %) | 104 (0.95×, 95 %) | 106 (0.97×, 97 %) |
| bm-native | 2 renderer, async | 8 | 104 (0.95×, 95 %) | 195 (1.79×, 90 %) | 197 (1.82×, 91 %) | 199 (1.84×, 92 %) | 202 (1.86×, 93 %) |
| bm-native | 4 renderer, async | 8 | 103 (0.95×, 95 %) | 197 (1.81×, 91 %) | 360 (3.32×, 83 %) | 371 (3.42×, 85 %) | 356 (3.28×, 82 %) |
| bm-native | 8 renderer, async | 8 | 104 (0.96×, 96 %) | 198 (1.82×, 91 %) | 365 (3.36×, 84 %) | 408 (3.76×, 47 %) | 406 (3.74×, 47 %) |
| takumi-native | 1 renderer, async | 4 | 130 (1.06×, 106 %) | 210 (1.71×, 85 %) | 296 (2.40×, 60 %) | 296 (2.40×, 60 %) | 298 (2.42×, 60 %) |
| takumi-native | 1 renderer, async | 8 | 129 (1.04×, 104 %) | 209 (1.69×, 85 %) | 273 (2.21×, 55 %) | 336 (2.72×, 34 %) | 338 (2.74×, 34 %) |
| takumi-native | 2 renderer, async | 4 | 132 (1.07×, 107 %) | 212 (1.72×, 86 %) | 298 (2.41×, 121 %) | 293 (2.38×, 119 %) | 300 (2.43×, 122 %) |
| takumi-native | 4 renderer, async | 4 | 132 (1.07×, 107 %) | 212 (1.72×, 86 %) | 295 (2.39×, 60 %) | 298 (2.42×, 60 %) | 264 (2.14×, 54 %) |
| takumi-native | 2 renderer, async | 8 | 131 (1.06×, 106 %) | 211 (1.71×, 85 %) | 298 (2.42×, 121 %) | 327 (2.65×, 133 %) | 305 (2.47×, 124 %) |
| takumi-native | 4 renderer, async | 8 | 130 (1.06×, 106 %) | 210 (1.70×, 85 %) | 294 (2.38×, 60 %) | 333 (2.70×, 68 %) | 324 (2.63×, 66 %) |
| bm-wasm | worker pool, 1 worker | — | 70.5 (0.98×, 98 %) | 67.8 (0.94×, 94 %) | 69.9 (0.97×, 97 %) | 71.1 (0.98×, 98 %) | 71.0 (0.98×, 98 %) |
| bm-wasm | worker pool, 2 worker | — | 69.0 (0.95×, 95 %) | 137 (1.89×, 95 %) | 137 (1.90×, 95 %) | 139 (1.92×, 96 %) | 137 (1.89×, 95 %) |
| bm-wasm | worker pool, 4 worker | — | 70.7 (0.98×, 98 %) | 138 (1.91×, 95 %) | 263 (3.64×, 91 %) | 249 (3.45×, 86 %) | 263 (3.63×, 91 %) |
| bm-wasm | worker pool, 8 worker | — | 70.7 (0.98×, 98 %) | 138 (1.91×, 95 %) | 236 (3.27×, 82 %) | 291 (4.03×, 50 %) | 309 (4.27×, 53 %) |
| takumi-wasm | worker pool, 1 worker | — | 46.0 (1.01×, 101 %) | 46.4 (1.02×, 102 %) | 47.0 (1.03×, 103 %) | 47.4 (1.04×, 104 %) | 47.1 (1.03×, 103 %) |
| takumi-wasm | worker pool, 2 worker | — | 44.5 (0.98×, 98 %) | 90.3 (1.98×, 99 %) | 88.9 (1.95×, 97 %) | 92.4 (2.03×, 101 %) | 91.8 (2.01×, 101 %) |
| takumi-wasm | worker pool, 4 worker | — | 46.1 (1.01×, 101 %) | 91.3 (2.00×, 100 %) | 170 (3.72×, 93 %) | 174 (3.82×, 96 %) | 179 (3.92×, 98 %) |
| takumi-wasm | worker pool, 8 worker | — | 46.4 (1.02×, 102 %) | 90.1 (1.98×, 99 %) | 173 (3.80×, 95 %) | 202 (4.43×, 55 %) | 213 (4.67×, 58 %) |

Ảnh mỗi giây; trong ngoặc là mức tăng so với tốc độ tuần tự một client của cùng engine (các dòng đầu) và hiệu suất mở rộng = mức tăng / min(N, số thread có thể render các ảnh khác nhau cùng lúc, 8 CPU logic); một renderer bm tính là 1, K renderer là min(K, UV_THREADPOOL_SIZE), renderer của takumi-native là UV_THREADPOOL_SIZE, pool worker là K. og card 1200×630 PNG, vòng kín: N client, mỗi client luôn có một yêu cầu đang chạy; 2000 ms mỗi điểm sau khi khởi động. CPU bận trong lúc đo: trung bình 42.8 % (tiến trình khác ≈ 0.90 lõi).
<!-- /native-bench:throughput -->

### Kích thước

<!-- native-bench:sizes -->
| File | Target | KiB | gzip -9 KiB | brotli KiB | Trạng thái |
|:--|--:|--:|--:|--:|--:|
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 3 327 | 1 765 | 1 389 | đã chạy (benchmark này) |
| `bm-engine.win32-arm64-msvc.node` | `aarch64-windows-gnu` | 2 627 | 1 577 | 1 179 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-x64-gnu.node` | `x86_64-linux-gnu.2.17` | 3 185 | 1 720 | 1 361 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-x64-musl.node` | `x86_64-linux-musl` | 3 185 | 1 720 | 1 362 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-arm64-gnu.node` | `aarch64-linux-gnu.2.17` | 2 634 | 1 579 | 1 180 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-arm64-musl.node` | `aarch64-linux-musl` | 2 633 | 1 579 | 1 180 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.darwin-x64.node` | `x86_64-macos.10.15` | 3 175 | 1 719 | 1 360 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.darwin-arm64.node` | `aarch64-macos.11.0` | 2 652 | 1 536 | 1 128 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| bm wasm `core` | wasm32 | 490 | 229 | 195 |  |
| bm wasm `standard` | wasm32 | 937 | 465 | 399 |  |
| bm wasm `full` | wasm32 | 1 144 | 560 | 471 |  |
| bm wasm `add-on WOFF` | wasm32 | 84.4 | 67.8 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Addon native lấy từ `native/dist/manifest.json` (build ngày 2026-11-13 với Zig 0.17.1, ReleaseFast). Mỗi người dùng chỉ tải một addon (gói optional cho nền tảng của họ) cộng với bản wasm dự phòng nằm trong gói chính.
<!-- /native-bench:sizes -->

### Nhiễu

<!-- native-bench:noise -->
| Giai đoạn | bắt đầu (UTC) | thời lượng | CPU bận ngay trước | CPU bận trong lúc đo | tiến trình khác, lõi |
|:--|--:|--:|--:|--:|--:|
| speed lượt 1 | 04:23 | 144 s | 2.80 % | 20.1 % (max 49.8 %) | 0.44 |
| speed lượt 2 | 04:26 | 147 s | 6.80 % | 22.0 % (max 45.1 %) | 0.60 |
| speed lượt 3 | 04:30 | 143 s | 6.00 % | 18.4 % (max 44.0 %) | 0.30 |
| cold |  | 17.8 s |  | 33.3 % (max 59.9 %) | 1.20 |
| memory |  | 56.7 s |  | 22.1 % (max 41.1 %) | 0.58 |
| eventloop |  | 11.9 s |  | 20.1 % (max 39.2 %) | 0.68 |
| throughput |  | 284.2 s |  | 42.8 % (max 100 %) | 0.90 |

"Tiến trình khác" = số lõi-giây bận của cả máy trừ thời gian CPU của chính benchmark, chia cho thời gian thực (8 CPU logic). Số fixture có median lệch quá 10 % giữa các lượt: bm-native:sync raw: 109, bm-native:sync png: 49, bm-native:async raw: 141, bm-native:async png: 79, bm-wasm:sync raw: 76, bm-wasm:sync png: 19, takumi-native:async raw: 84, takumi-native:async png: 36, takumi-wasm:async raw: 72, takumi-wasm:async png: 21. 0 geomean tuyệt đối (biến thể × định dạng) lệch quá 10 % giữa các lượt (khoảng lệch lớn nhất: 6.30 %), vì vậy các bảng ưu tiên tỉ lệ đo trong từng lượt. Tỉ lệ giữa engine lệch quá 10 %: không có.
<!-- /native-bench:noise -->

### Chạy lại

```sh
node bench/run-native.mjs                 # đầy đủ: 3 lượt speed, 30 cold start, 10 lượt bộ nhớ, ...
node bench/run-native.mjs --quick         # chạy thử ngắn (1 lượt, ngân sách nhỏ)
node bench/run-native.mjs --stages=cold,eventloop   # chỉ đo lại vài giai đoạn; phần còn lại giữ từ JSON
node bench/native/report.mjs              # chỉ sinh lại Markdown và bảng trong docs từ JSON
```

### Từng fixture

<!-- native-bench:per-fixture -->
| Fixture | Nhóm | raw bm-n sync | raw bm-n async | raw bm-w | raw tk-n | raw tk-w | raw bm-n/tk-n | raw bm-n/bm-w | png bm-n sync | png bm-n async | png bm-w | png tk-n | png tk-w | png bm-n/tk-n | png bm-n/bm-w |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| `colors-solid-bg` | colors | 0.17 / 0.28 | 0.21 / 0.87 | 0.29 / 0.44 | 0.34 / 0.55 | 0.43 / 0.73 | 0.61× | 0.61× | 0.20 / 0.32 | 0.19 / 0.36 | 0.32 / 0.44 | 0.82 / 1.19 | 1.31 / 1.57 | 0.23× | 0.64× |
| `colors-hex` | colors | 1.41 / 2.34 | 1.59 / 2.47 | 2.44 / 3.82 | 2.32 / 4.29 | 4.25 / 7.14 | 0.69× | 0.58× | 2.12 / 2.71 | 1.94 / 3.26 | 3.26 / 3.66 | 4.36 / 4.55 | 8.40 / 8.68 | 0.45× | 0.65× |
| `colors-functional` | colors | 1.22 / 1.39 | 1.23 / 1.48 | 1.88 / 2.24 | 1.95 / 3.35 | 2.99 / 3.56 | 0.63× | 0.65× | 2.01 / 2.15 | 1.82 / 2.20 | 3.01 / 3.39 | 3.95 / 4.08 | 7.80 / 8.18 | 0.46× | 0.67× |
| `colors-named` | colors | 1.23 / 1.62 | 1.25 / 2.48 | 1.93 / 2.08 | 1.78 / 2.67 | 2.86 / 3.39 | 0.71× | 0.64× | 2.15 / 2.31 | 1.92 / 2.49 | 3.15 / 3.31 | 4.27 / 4.61 | 8.04 / 8.44 | 0.45× | 0.68× |
| `colors-transparent-canvas` | colors | 0.31 / 0.43 | 0.32 / 0.62 | 0.48 / 0.56 | 0.51 / 0.71 | 0.75 / 0.83 | 0.62× | 0.64× | 0.44 / 0.50 | 0.42 / 0.50 | 0.67 / 0.76 | 0.91 / 1.00 | 1.46 / 1.66 | 0.46× | 0.66× |
| `flex-row-column` | flex | 1.09 / 1.26 | 1.07 / 2.25 | 1.59 / 2.40 | 1.12 / 1.74 | 1.60 / 2.56 | 0.96× | 0.68× | 1.85 / 2.01 | 1.60 / 1.89 | 2.70 / 2.95 | 3.08 / 3.60 | 6.93 / 7.13 | 0.52× | 0.68× |
| `flex-justify-align` | flex | 1.15 / 1.58 | 1.22 / 2.64 | 1.87 / 2.87 | 1.50 / 1.92 | 2.00 / 2.59 | 0.82× | 0.62× | 1.89 / 2.06 | 1.67 / 1.95 | 2.90 / 3.24 | 3.27 / 3.47 | 6.66 / 6.84 | 0.51× | 0.65× |
| `flex-wrap-gap` | flex | 1.34 / 1.64 | 1.37 / 2.84 | 2.22 / 3.05 | 1.42 / 1.94 | 1.94 / 2.92 | 0.97× | 0.60× | 2.16 / 2.23 | 1.94 / 2.25 | 3.34 / 3.48 | 3.27 / 3.84 | 6.64 / 6.82 | 0.59× | 0.65× |
| `flex-grow-shrink-basis` | flex | 0.85 / 1.24 | 0.86 / 2.52 | 1.23 / 1.92 | 1.05 / 1.88 | 1.42 / 2.67 | 0.82× | 0.69× | 1.44 / 1.74 | 1.28 / 1.60 | 2.20 / 2.57 | 2.83 / 3.02 | 5.77 / 6.20 | 0.45× | 0.66× |
| `flex-nested-small` | flex | 0.21 / 0.32 | 0.22 / 0.46 | 0.34 / 0.46 | 0.37 / 0.71 | 0.49 / 0.74 | 0.59× | 0.62× | 0.33 / 0.35 | 0.31 / 0.39 | 0.51 / 0.53 | 0.79 / 0.88 | 1.22 / 1.27 | 0.39× | 0.64× |
| `sizing-percent` | sizing | 0.82 / 3.71 | 0.84 / 2.33 | 1.18 / 2.47 | 1.02 / 1.75 | 1.37 / 1.52 | 0.82× | 0.70× | 1.42 / 1.53 | 1.19 / 1.52 | 2.06 / 2.26 | 3.43 / 3.64 | 6.80 / 7.38 | 0.35× | 0.69× |
| `sizing-minmax` | sizing | 0.76 / 1.62 | 0.80 / 1.88 | 1.05 / 1.82 | 0.89 / 1.84 | 1.16 / 2.39 | 0.90× | 0.72× | 1.34 / 2.31 | 1.33 / 1.70 | 1.90 / 2.40 | 3.38 / 3.84 | 6.64 / 6.97 | 0.39× | 0.70× |
| `sizing-aspect-ratio` | sizing | 0.86 / 1.90 | 0.89 / 1.95 | 1.23 / 2.71 | 0.94 / 1.78 | 1.28 / 2.03 | 0.94× | 0.70× | 1.58 / 1.82 | 1.36 / 1.72 | 2.23 / 2.46 | 3.32 / 4.13 | 6.83 / 7.08 | 0.41× | 0.71× |
| `sizing-padding-margin` | sizing | 0.87 / 1.95 | 0.89 / 2.26 | 1.24 / 2.24 | 1.02 / 2.14 | 1.35 / 2.38 | 0.87× | 0.70× | 1.45 / 1.89 | 1.33 / 1.87 | 2.14 / 2.55 | 3.18 / 3.65 | 6.59 / 7.38 | 0.42× | 0.68× |
| `sizing-auto-margin-center` | sizing | 0.16 / 0.21 | 0.18 / 0.57 | 0.27 / 0.43 | 0.27 / 0.49 | 0.36 / 0.56 | 0.66× | 0.61× | 0.24 / 0.26 | 0.23 / 0.28 | 0.38 / 0.40 | 0.60 / 0.67 | 0.99 / 1.11 | 0.38× | 0.63× |
| `abs-inset` | absolute | 0.89 / 4.06 | 0.90 / 1.96 | 1.27 / 1.87 | 1.17 / 2.11 | 1.91 / 2.64 | 0.77× | 0.70× | 1.53 / 2.04 | 1.29 / 1.66 | 2.21 / 2.35 | 3.42 / 3.95 | 7.78 / 8.17 | 0.38× | 0.69× |
| `abs-zorder` | absolute | 1.38 / 1.84 | 1.42 / 2.74 | 2.18 / 3.45 | 1.20 / 1.66 | 1.74 / 2.74 | 1.19× | 0.63× | 4.10 / 4.74 | 4.01 / 4.90 | 6.44 / 7.21 | 3.97 / 4.57 | 14.6 / 15.0 | 1.01× | 0.64× |
| `abs-in-flow` | absolute | 0.23 / 0.28 | 0.24 / 0.35 | 0.38 / 0.42 | 0.42 / 0.59 | 0.56 / 0.65 | 0.56× | 0.61× | 0.37 / 0.41 | 0.34 / 0.43 | 0.58 / 0.62 | 0.94 / 1.23 | 1.43 / 1.52 | 0.37× | 0.64× |
| `borders-uniform` | borders | 0.83 / 3.88 | 0.87 / 1.49 | 1.19 / 1.55 | 1.34 / 2.51 | 1.73 / 2.59 | 0.65× | 0.69× | 1.42 / 1.56 | 1.20 / 1.52 | 2.06 / 2.18 | 3.09 / 3.16 | 5.93 / 6.19 | 0.39× | 0.69× |
| `borders-per-side` | borders | 0.89 / 3.92 | 0.92 / 1.92 | 1.33 / 2.93 | 1.20 / 2.01 | 1.52 / 2.24 | 0.77× | 0.66× | 1.63 / 1.79 | 1.39 / 1.86 | 2.36 / 2.58 | 3.02 / 3.26 | 6.33 / 6.74 | 0.46× | 0.69× |
| `borders-with-radius` | borders | 0.51 / 0.57 | 0.52 / 0.61 | 0.84 / 0.92 | 0.58 / 0.75 | 0.95 / 1.34 | 0.90× | 0.61× | 0.74 / 1.12 | 0.73 / 1.11 | 1.16 / 1.79 | 1.13 / 1.27 | 1.87 / 2.79 | 0.64× | 0.64× |
| `radius-uniform-percorner` | border-radius | 1.07 / 4.18 | 1.10 / 2.18 | 1.59 / 3.16 | 1.07 / 1.80 | 1.41 / 1.52 | 1.03× | 0.67× | 2.06 / 2.26 | 1.80 / 2.17 | 2.96 / 3.12 | 3.22 / 3.76 | 7.25 / 7.53 | 0.56× | 0.69× |
| `radius-elliptical` | border-radius | 1.07 / 1.35 | 1.10 / 2.27 | 1.61 / 2.82 | 1.15 / 1.66 | 1.38 / 2.35 | 0.95× | 0.66× | 2.33 / 2.64 | 2.09 / 2.48 | 2.91 / 3.25 | 3.24 / 3.70 | 6.80 / 6.93 | 0.64× | 0.80× |
| `radius-pill-circle` | border-radius | 1.09 / 4.80 | 1.07 / 1.98 | 1.57 / 2.35 | 1.06 / 2.36 | 1.49 / 2.32 | 1.01× | 0.69× | 1.82 / 2.18 | 1.70 / 1.96 | 2.59 / 2.75 | 2.85 / 3.26 | 6.02 / 6.23 | 0.59× | 0.70× |
| `radius-small` | border-radius | 0.21 / 0.31 | 0.22 / 0.39 | 0.34 / 0.51 | 0.29 / 0.61 | 0.37 / 0.51 | 0.76× | 0.62× | 0.36 / 0.44 | 0.33 / 0.51 | 0.54 / 0.71 | 0.70 / 0.85 | 1.08 / 1.28 | 0.48× | 0.67× |
| `lingrad-angles` | linear-gradient | 2.13 / 2.44 | 2.22 / 4.00 | 3.81 / 4.50 | 4.47 / 4.81 | 6.53 / 6.99 | 0.50× | 0.56× | 6.49 / 6.88 | 6.40 / 6.86 | 9.84 / 10.1 | 7.78 / 8.31 | 34.6 / 35.0 | 0.82× | 0.66× |
| `lingrad-multistop` | linear-gradient | 1.87 / 2.28 | 1.94 / 3.68 | 3.10 / 3.77 | 4.71 / 4.83 | 6.19 / 6.48 | 0.41× | 0.60× | 6.38 / 6.56 | 6.21 / 7.06 | 10.3 / 11.3 | 6.79 / 7.35 | 24.2 / 25.8 | 0.91× | 0.62× |
| `lingrad-alpha` | linear-gradient | 3.02 / 3.65 | 3.11 / 4.99 | 5.02 / 5.60 | 4.50 / 6.01 | 7.12 / 7.29 | 0.69× | 0.60× | 5.88 / 6.52 | 6.00 / 6.81 | 9.23 / 9.56 | 6.77 / 7.44 | 29.5 / 30.4 | 0.89× | 0.64× |
| `lingrad-hero-small` | linear-gradient | 0.35 / 0.44 | 0.36 / 0.52 | 0.54 / 0.57 | 0.65 / 0.89 | 0.92 / 1.07 | 0.55× | 0.65× | 1.33 / 1.64 | 1.33 / 1.62 | 1.84 / 1.97 | 1.43 / 1.72 | 3.36 / 3.51 | 0.93× | 0.72× |
| `radial-shapes` | radial-gradient | 1.97 / 2.36 | 1.99 / 3.53 | 3.30 / 4.47 | 6.30 / 6.94 | 7.97 / 8.31 | 0.32× | 0.60× | 12.4 / 13.0 | 12.2 / 13.0 | 17.5 / 18.3 | 10.4 / 10.9 | 36.4 / 38.2 | 1.18× | 0.71× |
| `radial-at-position` | radial-gradient | 2.18 / 2.40 | 2.35 / 4.07 | 3.83 / 4.66 | 7.15 / 7.45 | 9.44 / 9.96 | 0.33× | 0.57× | 11.4 / 12.0 | 11.5 / 12.2 | 16.2 / 17.1 | 11.6 / 12.2 | 39.1 / 40.1 | 0.99× | 0.70× |
| `radial-spotlight-small` | radial-gradient | 0.42 / 0.47 | 0.44 / 0.62 | 0.53 / 0.62 | 1.31 / 1.59 | 1.49 / 1.75 | 0.33× | 0.81× | 4.14 / 4.29 | 4.14 / 4.22 | 5.44 / 5.54 | 2.62 / 2.78 | 9.97 / 10.3 | 1.58× | 0.76× |
| `shadow-offset-blur` | box-shadow | 2.54 / 2.73 | 2.64 / 4.43 | 4.76 / 5.23 | 5.52 / 6.52 | 8.50 / 9.08 | 0.48× | 0.53× | 7.88 / 8.44 | 7.78 / 8.36 | 13.3 / 13.7 | 7.84 / 8.32 | 29.3 / 29.9 | 0.99× | 0.59× |
| `shadow-spread-multi` | box-shadow | 2.94 / 3.28 | 3.03 / 5.08 | 5.33 / 5.74 | 5.35 / 7.10 | 8.40 / 8.88 | 0.57× | 0.55× | 8.93 / 9.42 | 8.78 / 9.66 | 14.5 / 15.0 | 8.07 / 8.66 | 30.2 / 31.4 | 1.09× | 0.61× |
| `shadow-inset` | box-shadow | 2.96 / 3.36 | 3.07 / 4.81 | 5.38 / 5.54 | 7.20 / 7.93 | 11.6 / 12.0 | 0.43× | 0.55× | 8.11 / 9.09 | 8.05 / 8.80 | 13.4 / 14.3 | 9.46 / 10.3 | 30.4 / 31.5 | 0.85× | 0.60× |
| `shadow-small` | box-shadow | 0.47 / 0.65 | 0.46 / 0.60 | 0.86 / 1.02 | 1.02 / 1.44 | 1.56 / 1.79 | 0.45× | 0.54× | 0.72 / 0.80 | 0.76 / 0.84 | 1.21 / 1.31 | 1.55 / 1.59 | 2.37 / 3.27 | 0.49× | 0.60× |
| `opacity-basic` | opacity | 2.26 / 2.98 | 2.29 / 4.16 | 3.63 / 4.19 | 3.09 / 3.41 | 6.72 / 7.28 | 0.74× | 0.62× | 3.27 / 3.37 | 3.10 / 3.70 | 5.02 / 5.62 | 5.36 / 5.62 | 13.0 / 13.2 | 0.58× | 0.65× |
| `opacity-nested` | opacity | 1.62 / 1.85 | 1.52 / 3.14 | 2.47 / 3.53 | 4.06 / 4.32 | 9.49 / 10.3 | 0.37× | 0.66× | 2.42 / 2.71 | 2.12 / 2.96 | 3.56 / 3.85 | 6.11 / 6.32 | 14.1 / 14.3 | 0.35× | 0.68× |
| `opacity-with-radius-shadow` | opacity | 0.70 / 0.74 | 0.69 / 0.81 | 1.43 / 1.63 | 1.88 / 2.21 | 3.72 / 3.78 | 0.37× | 0.49× | 1.02 / 1.11 | 1.00 / 1.21 | 1.86 / 1.93 | 2.43 / 2.67 | 4.76 / 4.82 | 0.41× | 0.55× |
| `overflow-hidden-clip` | overflow | 0.99 / 3.84 | 0.98 / 1.68 | 1.36 / 1.90 | 1.78 / 2.77 | 2.31 / 2.93 | 0.55× | 0.72× | 1.76 / 1.99 | 1.57 / 1.85 | 2.46 / 2.60 | 3.59 / 3.87 | 6.96 / 7.10 | 0.44× | 0.72× |
| `overflow-radius-clip` | overflow | 1.50 / 1.70 | 1.54 / 2.96 | 2.19 / 3.03 | 2.51 / 3.08 | 3.51 / 3.80 | 0.61× | 0.68× | 4.07 / 4.57 | 3.99 / 4.51 | 5.97 / 6.37 | 4.71 / 5.31 | 14.9 / 15.4 | 0.85× | 0.68× |
| `overflow-nested` | overflow | 0.25 / 0.32 | 0.28 / 0.38 | 0.44 / 0.61 | 0.44 / 0.64 | 0.60 / 0.79 | 0.63× | 0.57× | 0.47 / 0.72 | 0.46 / 0.72 | 0.68 / 1.13 | 1.12 / 1.78 | 1.67 / 2.59 | 0.41× | 0.69× |
| `transform-basic` | transform | 1.35 / 1.75 | 1.38 / 2.79 | 2.01 / 2.86 | 2.60 / 2.86 | 4.19 / 4.55 | 0.53× | 0.67× | 2.34 / 2.60 | 2.15 / 2.50 | 3.38 / 3.67 | 4.43 / 4.70 | 9.13 / 9.36 | 0.48× | 0.69× |
| `transform-combined-origin` | transform | 1.27 / 1.72 | 1.30 / 2.18 | 1.86 / 2.31 | 2.49 / 3.40 | 3.72 / 4.31 | 0.52× | 0.68× | 2.28 / 2.58 | 2.29 / 2.69 | 3.29 / 3.78 | 4.41 / 4.75 | 9.37 / 9.71 | 0.52× | 0.69× |
| `transform-text-small` | transform | 0.49 / 0.56 | 0.51 / 0.73 | 0.97 / 1.11 | 1.06 / 1.17 | 1.75 / 1.92 | 0.49× | 0.50× | 0.92 / 1.05 | 0.89 / 1.09 | 1.51 / 1.64 | 1.64 / 1.77 | 2.78 / 2.94 | 0.54× | 0.61× |
| `text-single-sizes` | text-single-line | 1.02 / 4.13 | 1.00 / 2.14 | 1.30 / 1.96 | 1.46 / 2.43 | 1.98 / 2.51 | 0.68× | 0.78× | 2.35 / 2.88 | 2.19 / 2.81 | 3.30 / 3.50 | 3.51 / 3.77 | 7.03 / 7.29 | 0.62× | 0.71× |
| `text-single-colors-small` | text-single-line | 0.24 / 0.30 | 0.25 / 0.38 | 0.38 / 0.48 | 0.60 / 0.95 | 0.81 / 0.92 | 0.42× | 0.62× | 0.57 / 0.59 | 0.54 / 0.65 | 0.81 / 0.87 | 1.19 / 1.31 | 1.75 / 1.96 | 0.45× | 0.71× |
| `text-single-fonts` | text-single-line | 1.01 / 2.14 | 1.03 / 2.34 | 1.35 / 3.19 | 1.43 / 1.82 | 1.98 / 2.11 | 0.72× | 0.75× | 2.86 / 3.38 | 2.76 / 3.65 | 3.94 / 4.44 | 3.84 / 4.16 | 8.08 / 8.50 | 0.72× | 0.73× |
| `text-paragraph-wrap` | text-paragraph | 1.39 / 1.52 | 1.41 / 2.97 | 2.00 / 2.72 | 2.11 / 2.38 | 3.11 / 3.35 | 0.67× | 0.69× | 3.24 / 3.75 | 3.06 / 3.50 | 4.67 / 5.41 | 4.35 / 4.66 | 8.62 / 9.70 | 0.70× | 0.69× |
| `text-paragraph-lineheight` | text-paragraph | 1.58 / 2.00 | 1.64 / 3.22 | 2.25 / 2.73 | 2.43 / 2.66 | 3.60 / 4.02 | 0.68× | 0.70× | 3.51 / 3.77 | 3.33 / 3.90 | 4.90 / 5.26 | 4.61 / 4.76 | 9.11 / 9.53 | 0.72× | 0.72× |
| `text-paragraph-letterspacing` | text-paragraph | 1.61 / 2.04 | 1.66 / 3.22 | 2.32 / 3.13 | 2.52 / 3.15 | 3.63 / 3.87 | 0.66× | 0.69× | 4.07 / 4.79 | 3.89 / 4.39 | 5.82 / 6.15 | 5.05 / 5.48 | 9.94 / 10.8 | 0.77× | 0.70× |
| `text-paragraph-small` | text-paragraph | 0.32 / 0.40 | 0.33 / 0.58 | 0.47 / 0.51 | 0.58 / 0.70 | 0.77 / 0.89 | 0.57× | 0.68× | 0.79 / 0.88 | 0.78 / 1.00 | 1.10 / 1.25 | 1.29 / 1.45 | 1.97 / 2.43 | 0.60× | 0.72× |
| `text-long-wrap` | text-paragraph | 1.18 / 1.90 | 1.53 / 2.37 | 1.86 / 3.13 | 1.71 / 2.44 | 2.20 / 2.57 | 0.90× | 0.64× | 2.67 / 2.83 | 2.51 / 2.75 | 3.74 / 4.08 | 3.93 / 4.48 | 10.1 / 10.4 | 0.64× | 0.71× |
| `fonts-weights-italic` | fonts | 1.36 / 1.60 | 1.45 / 2.86 | 1.84 / 2.52 | 2.26 / 2.44 | 3.09 / 3.58 | 0.64× | 0.74× | 3.90 / 4.79 | 3.79 / 4.21 | 5.40 / 6.01 | 4.40 / 4.73 | 9.56 / 9.90 | 0.86× | 0.72× |
| `fonts-mixed-inline` | fonts | 1.06 / 1.25 | 1.05 / 2.62 | 1.44 / 2.91 | 1.68 / 2.06 | 2.32 / 3.43 | 0.62× | 0.74× | 2.79 / 2.94 | 2.66 / 3.14 | 3.83 / 4.07 | 3.87 / 4.15 | 7.81 / 8.16 | 0.69× | 0.73× |
| `text-vietnamese` | text-i18n | 1.14 / 1.30 | 1.24 / 2.26 | 1.54 / 2.72 | 1.78 / 2.56 | 2.42 / 2.79 | 0.70× | 0.74× | 2.84 / 3.00 | 2.71 / 3.12 | 3.85 / 4.12 | 3.80 / 4.10 | 7.79 / 8.21 | 0.71× | 0.74× |
| `text-accented-latin` | text-i18n | 1.12 / 1.63 | 1.14 / 2.40 | 1.51 / 2.72 | 1.69 / 2.15 | 2.28 / 2.77 | 0.68× | 0.74× | 2.81 / 2.99 | 2.60 / 2.93 | 3.81 / 4.03 | 3.71 / 4.06 | 7.60 / 7.96 | 0.70× | 0.74× |
| `text-ellipsis-nowrap` | text-truncation | 0.94 / 1.36 | 0.96 / 2.35 | 1.30 / 2.83 | 1.48 / 1.98 | 1.91 / 2.72 | 0.65× | 0.72× | 1.82 / 1.96 | 1.59 / 1.92 | 2.53 / 2.84 | 3.27 / 3.47 | 6.65 / 6.74 | 0.49× | 0.72× |
| `text-lineclamp` | text-truncation | 1.51 / 1.69 | 1.59 / 2.61 | 2.27 / 3.63 | 2.22 / 2.57 | 3.35 / 3.84 | 0.72× | 0.67× | 2.63 / 3.28 | 2.39 / 2.88 | 3.90 / 4.28 | 4.07 / 4.51 | 8.18 / 8.80 | 0.59× | 0.67× |
| `text-lineclamp-small` | text-truncation | 0.27 / 0.32 | 0.28 / 0.46 | 0.40 / 0.50 | 0.57 / 0.91 | 0.75 / 0.87 | 0.48× | 0.66× | 0.46 / 0.49 | 0.43 / 0.51 | 0.66 / 0.72 | 0.98 / 1.04 | 1.47 / 1.61 | 0.44× | 0.70× |
| `img-png-fit` | images | 1.36 / 1.57 | 1.42 / 2.64 | 2.52 / 3.28 | 4.08 / 4.83 | 5.88 / 6.26 | 0.35× | 0.54× | 11.2 / 11.7 | 11.3 / 12.2 | 17.6 / 18.9 | 8.65 / 9.83 | 33.7 / 35.3 | 1.31× | 0.63× |
| `img-jpeg-fit` | images | 1.37 / 1.57 | 1.45 / 1.83 | 2.47 / 3.07 | 11.9 / 13.2 | 18.7 / 19.4 | 0.12× | 0.56× | 18.7 / 19.3 | 18.6 / 19.7 | 27.5 / 28.1 | 17.9 / 19.0 | 51.5 / 56.5 | 1.04× | 0.68× |
| `img-intrinsic-size` | images | 0.17 / 0.24 | 0.22 / 0.94 | 0.44 / 0.66 | 0.43 / 0.76 | 0.58 / 0.82 | 0.51× | 0.39× | 1.76 / 1.81 | 1.83 / 1.98 | 2.79 / 2.88 | 1.40 / 1.63 | 5.19 / 5.38 | 1.31× | 0.63× |
| `img-radius-clip` | images | 2.32 / 2.75 | 2.39 / 2.94 | 4.22 / 4.30 | 4.71 / 5.93 | 7.24 / 7.54 | 0.51× | 0.55× | 14.6 / 15.3 | 14.7 / 15.2 | 22.4 / 22.6 | 9.53 / 10.3 | 34.1 / 34.3 | 1.54× | 0.65× |
| `img-photo-bg` | images | 1.17 / 1.44 | 1.24 / 2.53 | 1.66 / 3.22 | 3.76 / 4.05 | 5.89 / 6.36 | 0.33× | 0.70× | 28.5 / 30.2 | 28.7 / 29.5 | 39.9 / 41.5 | 11.3 / 12.6 | 53.4 / 57.1 | 2.54× | 0.71× |
| `grid-fixed-fr` | grid | 1.12 / 1.44 | 1.17 / 2.45 | 1.73 / 2.94 | 1.60 / 2.63 | 2.07 / 3.36 | 0.74× | 0.65× | 2.01 / 2.29 | 1.84 / 2.23 | 2.97 / 3.15 | 3.36 / 3.81 | 6.74 / 6.80 | 0.55× | 0.68× |
| `grid-repeat-gap` | grid | 1.26 / 1.73 | 1.29 / 2.29 | 1.97 / 2.82 | 1.73 / 3.33 | 2.39 / 3.13 | 0.74× | 0.64× | 2.35 / 2.49 | 2.20 / 2.62 | 3.51 / 3.77 | 4.19 / 4.45 | 10.6 / 10.8 | 0.53× | 0.67× |
| `grid-spans` | grid | 1.06 / 1.53 | 1.10 / 2.03 | 1.54 / 2.88 | 1.43 / 2.58 | 1.91 / 2.20 | 0.77× | 0.69× | 1.92 / 2.62 | 1.80 / 2.55 | 2.81 / 3.54 | 3.82 / 4.34 | 7.80 / 8.54 | 0.47× | 0.68× |
| `grid-small-mixed` | grid | 0.34 / 0.43 | 0.36 / 0.63 | 0.59 / 0.69 | 0.68 / 0.97 | 0.93 / 1.19 | 0.52× | 0.57× | 0.61 / 0.75 | 0.57 / 0.66 | 0.93 / 1.03 | 1.20 / 1.30 | 1.78 / 2.01 | 0.47× | 0.65× |
| `card-og` | og-card | 2.36 / 2.51 | 2.41 / 4.06 | 3.50 / 3.95 | 4.01 / 4.50 | 5.89 / 6.54 | 0.60× | 0.68× | 9.61 / 10.2 | 9.70 / 9.90 | 14.0 / 14.6 | 7.50 / 7.97 | 21.2 / 22.4 | 1.29× | 0.68× |
| `card-og-small` | og-card | 1.06 / 1.10 | 1.06 / 1.41 | 1.68 / 1.77 | 2.05 / 2.28 | 2.89 / 2.97 | 0.52× | 0.63× | 3.86 / 4.03 | 3.86 / 4.23 | 5.71 / 5.83 | 3.48 / 3.62 | 8.15 / 8.48 | 1.11× | 0.68× |
| `card-blog` | blog-card | 5.27 / 5.90 | 5.43 / 7.41 | 9.39 / 10.2 | 6.72 / 7.53 | 15.8 / 16.0 | 0.81× | 0.56× | 18.9 / 19.5 | 19.1 / 20.3 | 29.4 / 30.7 | 11.8 / 13.8 | 48.2 / 49.6 | 1.62× | 0.65× |
| `card-flat-ui` | blog-card | 2.68 / 2.95 | 2.68 / 4.65 | 4.45 / 4.90 | 3.65 / 4.12 | 6.72 / 7.06 | 0.73× | 0.60× | 5.39 / 5.61 | 5.31 / 7.45 | 8.40 / 8.81 | 6.48 / 6.79 | 19.2 / 19.7 | 0.82× | 0.64× |
| `stress-600-boxes` | stress | 5.47 / 7.15 | 5.90 / 7.02 | 8.83 / 9.79 | 7.06 / 8.50 | 9.02 / 9.48 | 0.84× | 0.62× | 7.41 / 7.67 | 7.30 / 7.61 | 11.9 / 12.2 | 8.81 / 9.38 | 15.2 / 15.4 | 0.83× | 0.62× |
| `stress-200-labels` | stress | 5.18 / 5.70 | 5.42 / 7.43 | 8.56 / 9.39 | 10.5 / 11.5 | 14.8 / 15.1 | 0.51× | 0.60× | 9.23 / 10.0 | 9.26 / 9.52 | 14.1 / 15.1 | 12.9 / 13.6 | 22.5 / 23.5 | 0.72× | 0.65× |
| `stress-3000x2000-card` | stress | 12.9 / 13.9 | 14.7 / 15.7 | 20.7 / 23.4 | 20.9 / 23.2 | 30.5 / 32.0 | 0.70× | 0.62× | 52.6 / 54.8 | 53.6 / 55.4 | 76.6 / 79.4 | 39.6 / 42.2 | 132 / 136 | 1.35× | 0.69× |
| `fx-text-shadow` | text-shadow | 0.61 / 0.71 | 0.61 / 0.70 | 1.10 / 1.23 | 0.83 / 0.90 | 1.15 / 1.30 | 0.73× | 0.56× | 2.67 / 2.86 | 2.67 / 2.95 | 4.00 / 4.26 | 2.03 / 2.43 | 4.39 / 4.93 | 1.32× | 0.67× |
| `gap-dashed-dotted-border` | known-gaps | 0.62 / 0.74 | 0.61 / 0.84 | 1.05 / 1.19 | 1.13 / 1.60 | 1.87 / 2.25 | 0.54× | 0.59× | 0.79 / 0.96 | 0.78 / 0.99 | 1.28 / 1.47 | 1.54 / 1.93 | 2.57 / 2.92 | 0.50× | 0.62× |
| `fx-filter-blur-grayscale` | filter | 0.66 / 0.76 | 0.66 / 0.79 | 1.31 / 1.56 | 1.25 / 1.71 | 1.91 / 2.35 | 0.52× | 0.50× | 1.74 / 1.81 | 1.73 / 1.87 | 2.94 / 3.00 | 1.93 / 2.04 | 4.90 / 4.97 | 0.89× | 0.59× |
| `gap-tailwind-tw` | known-gaps | 0.23 / 0.31 | 0.25 / 0.54 | 0.38 / 0.56 | 0.42 / 0.76 | 0.53 / 0.76 | 0.59× | 0.61× | 0.45 / 0.50 | 0.41 / 0.59 | 0.65 / 0.72 | 0.97 / 1.16 | 1.43 / 1.57 | 0.42× | 0.69× |
| `gap-oklch-color` | known-gaps | 0.10 / 0.18 | 0.12 / 0.34 | 0.19 / 0.31 | 0.23 / 0.43 | 0.29 / 0.49 | 0.54× | 0.51× | 0.18 / 0.22 | 0.17 / 0.26 | 0.27 / 0.35 | 0.72 / 0.78 | 1.14 / 1.25 | 0.24× | 0.66× |
| `gap-svg-image` | known-gaps | 0.15 / 0.26 | 0.17 / 0.37 | 0.29 / 0.47 | 0.29 / 0.51 | 0.42 / 0.61 | 0.59× | 0.50× | 0.37 / 0.46 | 0.34 / 0.59 | 0.57 / 0.66 | 0.73 / 1.17 | 1.17 / 1.39 | 0.47× | 0.64× |
| `gap-inline-box-decoration` | known-gaps | 0.24 / 0.30 | 0.26 / 0.48 | 0.38 / 0.63 | 0.54 / 0.78 | 0.71 / 0.89 | 0.48× | 0.63× | 0.64 / 0.74 | 0.62 / 0.73 | 0.90 / 0.97 | 1.12 / 1.23 | 1.77 / 1.90 | 0.55× | 0.71× |
| `gap-mix-blend-mode` | known-gaps | 0.28 / 0.33 | 0.29 / 0.43 | 0.45 / 0.57 | 0.50 / 0.63 | 0.85 / 0.95 | 0.58× | 0.62× | 0.52 / 0.60 | 0.48 / 0.60 | 0.77 / 0.84 | 0.99 / 1.10 | 1.65 / 1.75 | 0.48× | 0.67× |
| `gap-clip-path` | known-gaps | 0.36 / 0.43 | 0.37 / 0.55 | 0.60 / 0.65 | 0.50 / 0.65 | 0.79 / 1.04 | 0.74× | 0.60× | 1.00 / 1.04 | 0.98 / 1.08 | 1.52 / 1.55 | 1.23 / 1.67 | 6.46 / 6.52 | 0.80× | 0.66× |
| `gap-background-clip-text` | known-gaps | 0.27 / 0.34 | 0.30 / 0.37 | 0.41 / 0.51 | 1.30 / 1.44 | 1.90 / 2.22 | 0.23× | 0.66× | 1.01 / 1.04 | 0.99 / 1.17 | 1.47 / 1.55 | 1.98 / 2.29 | 5.30 / 5.37 | 0.50× | 0.69× |
| `gap-text-wrap-balance` | known-gaps | 0.21 / 0.27 | 0.24 / 0.38 | 0.33 / 0.40 | 0.49 / 0.68 | 0.64 / 0.83 | 0.48× | 0.62× | 0.62 / 0.73 | 0.62 / 1.04 | 0.85 / 0.96 | 1.07 / 1.50 | 1.73 / 2.17 | 0.58× | 0.72× |
| `pfx-aa-shapes` | aa-exact | 0.29 / 0.39 | 0.32 / 0.61 | 0.51 / 0.65 | 0.45 / 0.72 | 0.65 / 0.83 | 0.70× | 0.57× | 0.53 / 0.64 | 0.51 / 0.68 | 0.81 / 0.87 | 0.95 / 1.06 | 1.49 / 1.75 | 0.54× | 0.65× |
| `pfx-aa-text` | aa-exact | 0.28 / 0.41 | 0.26 / 0.46 | 0.42 / 0.60 | 0.65 / 0.96 | 0.85 / 1.04 | 0.40× | 0.66× | 0.75 / 0.85 | 0.72 / 0.93 | 1.03 / 1.11 | 1.25 / 1.43 | 1.91 / 2.00 | 0.58× | 0.72× |
| `pfx-border-dashed` | dashed-border | 0.86 / 0.91 | 0.87 / 0.94 | 1.41 / 1.50 | 1.36 / 1.66 | 2.48 / 2.63 | 0.63× | 0.61× | 1.07 / 1.13 | 1.07 / 1.20 | 1.70 / 1.90 | 1.88 / 2.02 | 3.29 / 3.44 | 0.57× | 0.63× |
| `pfx-border-dotted` | dotted-border | 0.87 / 0.97 | 0.91 / 1.00 | 1.55 / 1.69 | 1.56 / 1.71 | 2.83 / 2.99 | 0.59× | 0.56× | 1.15 / 1.22 | 1.14 / 1.20 | 1.88 / 2.00 | 2.10 / 2.22 | 3.68 / 4.00 | 0.54× | 0.61× |
| `pfx-border-double-3d` | double-3d-border | 0.30 / 0.40 | 0.32 / 0.53 | 0.55 / 0.66 | 0.52 / 0.81 | 0.74 / 0.92 | 0.61× | 0.55× | 0.51 / 0.54 | 0.48 / 0.58 | 0.78 / 0.85 | 0.98 / 1.17 | 1.46 / 1.59 | 0.49× | 0.65× |
| `pfx-border-mixed` | mixed-border | 0.46 / 0.55 | 0.46 / 0.66 | 0.78 / 0.90 | 0.71 / 0.82 | 1.22 / 1.46 | 0.65× | 0.59× | 0.73 / 0.82 | 0.69 / 0.83 | 1.11 / 1.20 | 1.25 / 1.37 | 2.08 / 2.18 | 0.55× | 0.66× |
| `pfx-outline` | outline | 0.53 / 0.59 | 0.55 / 0.69 | 0.90 / 0.97 | 1.02 / 1.17 | 1.70 / 1.91 | 0.54× | 0.59× | 0.80 / 0.84 | 0.79 / 0.95 | 1.23 / 1.34 | 1.59 / 2.09 | 2.66 / 3.27 | 0.50× | 0.65× |
| `pfx-clip-path-shapes` | clip-path | 0.41 / 0.48 | 0.42 / 0.65 | 0.72 / 0.87 | 0.65 / 0.75 | 1.01 / 1.20 | 0.66× | 0.57× | 1.31 / 1.34 | 1.30 / 1.51 | 1.99 / 2.41 | 1.46 / 1.60 | 5.38 / 5.70 | 0.89× | 0.66× |
| `pfx-mask-gradient` | mask | 0.71 / 0.97 | 0.73 / 0.93 | 1.20 / 1.57 | 1.06 / 1.43 | 1.64 / 1.93 | 0.69× | 0.59× | 1.55 / 1.68 | 1.53 / 1.74 | 2.30 / 2.48 | 1.92 / 2.11 | 6.30 / 7.25 | 0.79× | 0.67× |
| `pfx-bg-clip-text` | bg-clip-text | 0.42 / 0.44 | 0.41 / 0.53 | 0.59 / 0.72 | 1.81 / 2.35 | 2.75 / 2.84 | 0.23× | 0.71× | 1.50 / 1.57 | 1.49 / 1.58 | 2.15 / 2.30 | 2.66 / 2.79 | 5.31 / 5.54 | 0.56× | 0.70× |
| `pfx-mix-blend` | mix-blend | 0.77 / 0.85 | 0.77 / 0.86 | 1.32 / 1.45 | 1.11 / 1.25 | 1.92 / 2.22 | 0.69× | 0.58× | 2.70 / 2.75 | 2.72 / 2.89 | 4.12 / 4.51 | 2.15 / 2.20 | 7.59 / 8.57 | 1.27× | 0.66× |
| `pfx-bg-blend` | bg-blend | 0.69 / 0.72 | 0.71 / 0.76 | 1.07 / 1.12 | 3.70 / 3.79 | 4.84 / 4.90 | 0.19× | 0.64× | 2.92 / 3.23 | 2.95 / 3.33 | 4.25 / 4.86 | 4.75 / 5.08 | 10.4 / 11.1 | 0.62× | 0.69× |
| `pfx-drop-shadow` | drop-shadow | 0.79 / 0.95 | 0.78 / 1.06 | 1.29 / 1.66 | 1.09 / 1.45 | 1.65 / 1.89 | 0.71× | 0.61× | 2.21 / 2.39 | 2.17 / 2.40 | 3.44 / 3.81 | 1.88 / 2.04 | 6.89 / 7.56 | 1.15× | 0.64× |
| `pfx-backdrop-filter` | backdrop-filter | 1.33 / 1.49 | 1.34 / 1.68 | 2.59 / 2.87 | 2.46 / 2.68 | 4.25 / 4.49 | 0.54× | 0.51× | 2.18 / 2.27 | 2.17 / 2.38 | 3.98 / 4.36 | 3.21 / 3.45 | 7.36 / 7.67 | 0.68× | 0.55× |
| `pfx-text-stroke` | text-stroke | 0.83 / 0.89 | 0.83 / 0.95 | 1.33 / 1.52 | 0.75 / 0.90 | 0.98 / 1.18 | 1.12× | 0.62× | 1.28 / 1.39 | 1.29 / 1.51 | 1.99 / 2.40 | 1.41 / 1.69 | 2.30 / 2.63 | 0.91× | 0.64× |
| `pfx-text-decoration` | text-decoration | 1.09 / 1.20 | 1.09 / 1.27 | 1.83 / 1.89 | 1.27 / 1.40 | 1.80 / 1.91 | 0.86× | 0.60× | 1.85 / 1.90 | 1.81 / 2.04 | 2.84 / 3.06 | 2.03 / 2.14 | 3.62 / 3.75 | 0.89× | 0.65× |
| `pfx-visibility` | visibility | 0.16 / 0.24 | 0.17 / 0.31 | 0.26 / 0.38 | 0.38 / 0.61 | 0.48 / 0.63 | 0.47× | 0.59× | 0.26 / 0.29 | 0.23 / 0.30 | 0.38 / 0.45 | 0.84 / 0.92 | 1.26 / 1.38 | 0.28× | 0.69× |
| `pfx-opacity-layers` | opacity | 1.04 / 1.07 | 1.04 / 1.18 | 2.23 / 2.37 | 1.83 / 1.99 | 3.05 / 3.42 | 0.57× | 0.46× | 2.29 / 2.44 | 2.25 / 2.44 | 4.07 / 4.18 | 2.75 / 2.83 | 7.05 / 7.18 | 0.82× | 0.56× |
| `pfx-svg-background` | svg-image | 0.66 / 0.75 | 0.65 / 1.02 | 1.37 / 1.54 | 0.61 / 0.75 | 0.94 / 0.98 | 1.08× | 0.48× | 1.08 / 1.35 | 1.05 / 1.19 | 1.89 / 2.07 | 1.28 / 1.48 | 2.26 / 2.43 | 0.82× | 0.57× |
| `pfx-inline-boxes-many` | inline-box | 1.27 / 1.34 | 1.28 / 1.39 | 2.09 / 2.18 | 1.93 / 2.03 | 2.84 / 2.93 | 0.66× | 0.61× | 2.43 / 2.47 | 2.40 / 2.52 | 3.75 / 3.87 | 2.88 / 3.11 | 5.32 / 5.47 | 0.83× | 0.65× |
| `css-class-id` | css-stylesheet | 1.20 / 1.42 | 1.24 / 2.69 | 1.76 / 2.31 | 1.80 / 2.19 | 2.40 / 3.04 | 0.69× | 0.68× | 2.36 / 2.53 | 2.18 / 2.51 | 3.38 / 3.50 | 3.67 / 3.82 | 7.25 / 7.42 | 0.59× | 0.70× |
| `css-nth-child` | css-stylesheet | 0.75 / 1.11 | 0.77 / 1.66 | 1.17 / 2.04 | 1.23 / 2.22 | 1.69 / 2.23 | 0.63× | 0.64× | 1.24 / 1.26 | 1.13 / 1.30 | 1.86 / 1.89 | 2.25 / 2.39 | 4.27 / 4.35 | 0.50× | 0.66× |
| `css-media-layer` | css-stylesheet | 0.63 / 3.42 | 0.64 / 1.31 | 0.93 / 1.28 | 0.72 / 1.51 | 0.89 / 1.84 | 0.89× | 0.67× | 1.08 / 1.37 | 0.96 / 1.28 | 1.57 / 1.69 | 2.50 / 3.05 | 4.62 / 5.16 | 0.38× | 0.69× |
| `css-important-var` | css-stylesheet | 0.49 / 0.81 | 0.52 / 1.18 | 0.75 / 1.21 | 0.80 / 1.89 | 1.06 / 1.78 | 0.66× | 0.66× | 0.80 / 0.89 | 0.74 / 1.01 | 1.20 / 1.33 | 2.28 / 2.63 | 3.47 / 4.06 | 0.33× | 0.67× |
| `tw-card` | tailwind | 1.20 / 1.61 | 1.28 / 2.34 | 1.62 / 2.67 | 1.65 / 2.44 | 2.28 / 2.82 | 0.78× | 0.74× | 2.72 / 3.10 | 2.58 / 3.15 | 3.62 / 4.10 | 3.66 / 4.02 | 7.25 / 7.65 | 0.70× | 0.75× |
| `tw-responsive` | tailwind | 0.61 / 1.28 | 0.62 / 1.13 | 0.83 / 1.37 | 0.66 / 1.85 | 0.82 / 1.53 | 0.94× | 0.73× | 0.93 / 1.04 | 0.81 / 0.98 | 1.30 / 1.40 | 2.21 / 2.38 | 3.61 / 3.76 | 0.36× | 0.71× |
| `tw-structural` | tailwind | 0.64 / 1.08 | 0.66 / 1.12 | 0.94 / 1.27 | 0.69 / 1.34 | 0.89 / 1.58 | 0.95× | 0.68× | 0.94 / 1.10 | 0.85 / 1.08 | 1.42 / 1.60 | 1.96 / 2.19 | 3.15 / 3.27 | 0.44× | 0.66× |
| `tw-arbitrary` | tailwind | 1.60 / 2.04 | 1.65 / 2.81 | 2.77 / 3.22 | 3.37 / 4.51 | 5.32 / 5.78 | 0.49× | 0.58× | 2.25 / 2.65 | 2.13 / 2.47 | 3.69 / 4.12 | 4.62 / 5.06 | 8.25 / 8.73 | 0.46× | 0.61× |
| `html-article` | html | 0.88 / 1.24 | 0.92 / 4.06 | 1.28 / 1.82 | 1.32 / 2.09 | 1.72 / 2.14 | 0.70× | 0.69× | 1.75 / 2.20 | 1.61 / 2.20 | 2.44 / 2.92 | 2.89 / 3.41 | 5.56 / 6.01 | 0.56× | 0.72× |
| `html-document` | html | 0.42 / 0.63 | 0.45 / 1.03 | 0.63 / 1.08 | 0.73 / 1.22 | 0.88 / 1.37 | 0.62× | 0.67× | 0.82 / 1.11 | 0.76 / 0.99 | 1.14 / 1.25 | 1.83 / 2.03 | 2.71 / 2.95 | 0.42× | 0.72× |
| `html-flex-card` | html | 1.35 / 1.55 | 1.42 / 2.02 | 2.01 / 2.44 | 2.46 / 3.04 | 3.68 / 4.16 | 0.58× | 0.67× | 4.55 / 5.23 | 4.54 / 5.02 | 6.73 / 7.08 | 4.32 / 4.82 | 11.6 / 12.1 | 1.05× | 0.68× |
| `html-inline` | html | 0.50 / 0.63 | 0.49 / 1.07 | 0.73 / 1.13 | 0.89 / 1.26 | 1.14 / 1.56 | 0.55× | 0.69× | 1.00 / 1.16 | 0.92 / 1.11 | 1.42 / 1.48 | 2.02 / 2.12 | 2.87 / 3.03 | 0.46× | 0.70× |
| `pseudo-inline` | pseudo-elements | 0.31 / 0.44 | 0.38 / 1.11 | 0.53 / 0.80 | 0.74 / 1.25 | 1.04 / 1.37 | 0.52× | 0.59× | 0.76 / 0.86 | 0.70 / 0.83 | 1.09 / 1.21 | 1.42 / 1.60 | 2.57 / 2.68 | 0.49× | 0.70× |
| `pseudo-block` | pseudo-elements | 0.54 / 0.76 | 0.53 / 1.24 | 0.81 / 1.12 | 0.85 / 1.41 | 1.11 / 1.67 | 0.63× | 0.67× | 0.88 / 1.01 | 0.77 / 0.93 | 1.28 / 1.41 | 1.75 / 1.92 | 2.87 / 3.15 | 0.44× | 0.69× |
| `pseudo-attr` | pseudo-elements | 0.27 / 0.39 | 0.27 / 0.75 | 0.48 / 0.64 | 0.59 / 1.01 | 0.81 / 1.20 | 0.45× | 0.57× | 0.59 / 0.84 | 0.53 / 0.75 | 0.85 / 0.95 | 1.20 / 1.63 | 2.12 / 2.55 | 0.45× | 0.69× |
| `pseudo-tw` | pseudo-elements | 0.38 / 0.77 | 0.41 / 1.51 | 0.66 / 0.95 | 0.60 / 1.04 | 0.84 / 0.98 | 0.69× | 0.57× | 0.72 / 0.85 | 0.64 / 0.78 | 1.03 / 1.14 | 1.23 / 1.49 | 2.32 / 2.41 | 0.52× | 0.70× |
| `anim-opacity-t0` | animation | 0.10 / 0.16 | 0.11 / 0.23 | 0.18 / 0.27 | 0.22 / 0.39 | 0.26 / 0.37 | 0.49× | 0.55× | 0.15 / 0.20 | 0.14 / 0.22 | 0.23 / 0.29 | 0.42 / 0.58 | 0.63 / 0.75 | 0.34× | 0.68× |
| `anim-opacity-t250` | animation | 0.12 / 0.18 | 0.14 / 0.23 | 0.21 / 0.28 | 0.29 / 0.50 | 0.43 / 0.52 | 0.48× | 0.58× | 0.17 / 0.20 | 0.16 / 0.22 | 0.26 / 0.30 | 0.54 / 0.64 | 0.87 / 0.94 | 0.30× | 0.67× |
| `anim-opacity-t500` | animation | 0.12 / 0.17 | 0.14 / 0.23 | 0.21 / 0.27 | 0.28 / 0.47 | 0.42 / 0.54 | 0.48× | 0.57× | 0.17 / 0.21 | 0.16 / 0.24 | 0.26 / 0.29 | 0.55 / 0.73 | 0.87 / 1.04 | 0.29× | 0.67× |
| `anim-opacity-t900` | animation | 0.12 / 0.18 | 0.14 / 0.23 | 0.21 / 0.30 | 0.28 / 0.48 | 0.42 / 0.54 | 0.50× | 0.57× | 0.17 / 0.22 | 0.16 / 0.26 | 0.26 / 0.29 | 0.55 / 0.65 | 0.87 / 0.99 | 0.29× | 0.66× |
| `anim-opacity-t1500` | animation | 0.09 / 0.16 | 0.11 / 0.23 | 0.16 / 0.25 | 0.22 / 0.44 | 0.26 / 0.40 | 0.50× | 0.55× | 0.15 / 0.19 | 0.14 / 0.20 | 0.22 / 0.26 | 0.48 / 0.59 | 0.71 / 0.82 | 0.30× | 0.68× |
| `anim-transform-t0` | animation | 0.13 / 0.21 | 0.15 / 0.26 | 0.24 / 0.32 | 0.24 / 0.36 | 0.29 / 0.38 | 0.62× | 0.57× | 0.22 / 0.33 | 0.21 / 0.34 | 0.35 / 0.48 | 0.52 / 0.64 | 0.75 / 0.87 | 0.41× | 0.64× |
| `anim-transform-t200` | animation | 0.14 / 0.22 | 0.16 / 0.30 | 0.24 / 0.33 | 0.26 / 0.42 | 0.32 / 0.48 | 0.61× | 0.59× | 0.26 / 0.40 | 0.25 / 0.38 | 0.41 / 0.54 | 0.55 / 0.78 | 0.78 / 1.18 | 0.46× | 0.65× |
| `anim-transform-t400` | animation | 0.15 / 0.19 | 0.15 / 0.25 | 0.24 / 0.30 | 0.25 / 0.37 | 0.30 / 0.40 | 0.63× | 0.62× | 0.25 / 0.30 | 0.24 / 0.31 | 0.40 / 0.42 | 0.52 / 0.63 | 0.74 / 0.84 | 0.46× | 0.64× |
| `anim-transform-t600` | animation | 0.13 / 0.18 | 0.14 / 0.25 | 0.23 / 0.29 | 0.25 / 0.40 | 0.30 / 0.45 | 0.58× | 0.54× | 0.26 / 0.28 | 0.24 / 0.30 | 0.40 / 0.50 | 0.53 / 0.60 | 0.76 / 0.80 | 0.46× | 0.66× |
| `anim-transform-t800` | animation | 0.12 / 0.19 | 0.12 / 0.24 | 0.21 / 0.27 | 0.23 / 0.38 | 0.29 / 0.37 | 0.54× | 0.56× | 0.22 / 0.24 | 0.21 / 0.28 | 0.34 / 0.39 | 0.51 / 0.62 | 0.75 / 0.82 | 0.40× | 0.65× |
| `anim-color-t0` | animation | 0.18 / 0.24 | 0.18 / 0.25 | 0.28 / 0.35 | 0.40 / 0.55 | 0.49 / 0.59 | 0.45× | 0.64× | 0.28 / 0.36 | 0.25 / 0.36 | 0.42 / 0.46 | 0.68 / 0.79 | 0.96 / 1.05 | 0.37× | 0.68× |
| `anim-color-t300` | animation | 0.16 / 0.24 | 0.17 / 0.26 | 0.27 / 0.31 | 0.39 / 0.51 | 0.48 / 0.57 | 0.45× | 0.61× | 0.28 / 0.30 | 0.25 / 0.33 | 0.42 / 0.49 | 0.69 / 0.86 | 0.95 / 1.05 | 0.37× | 0.67× |
| `anim-color-t700` | animation | 0.17 / 0.22 | 0.18 / 0.24 | 0.27 / 0.36 | 0.38 / 0.46 | 0.48 / 0.58 | 0.46× | 0.62× | 0.28 / 0.30 | 0.25 / 0.32 | 0.42 / 0.44 | 0.68 / 0.75 | 0.96 / 1.04 | 0.37× | 0.68× |
| `anim-color-t2000` | animation | 0.16 / 0.22 | 0.16 / 0.24 | 0.26 / 0.35 | 0.38 / 0.49 | 0.48 / 0.58 | 0.42× | 0.60× | 0.29 / 0.35 | 0.26 / 0.39 | 0.42 / 0.54 | 0.70 / 0.90 | 0.96 / 1.16 | 0.37× | 0.68× |
| `anim-width-t0` | animation | 0.13 / 0.21 | 0.14 / 0.23 | 0.21 / 0.33 | 0.25 / 0.42 | 0.29 / 0.44 | 0.59× | 0.62× | 0.18 / 0.20 | 0.17 / 0.23 | 0.27 / 0.32 | 0.47 / 0.54 | 0.68 / 0.77 | 0.36× | 0.67× |
| `anim-width-t100` | animation | 0.15 / 0.23 | 0.17 / 0.34 | 0.26 / 0.33 | 0.25 / 0.42 | 0.31 / 0.41 | 0.66× | 0.60× | 0.24 / 0.28 | 0.23 / 0.30 | 0.38 / 0.41 | 0.54 / 0.59 | 0.77 / 0.85 | 0.43× | 0.63× |
| `anim-width-t500` | animation | 0.16 / 0.23 | 0.16 / 0.25 | 0.28 / 0.37 | 0.25 / 0.41 | 0.31 / 0.43 | 0.64× | 0.56× | 0.31 / 0.40 | 0.29 / 0.40 | 0.48 / 0.55 | 0.58 / 0.70 | 0.82 / 1.02 | 0.51× | 0.64× |
| `anim-width-t999` | animation | 0.19 / 0.26 | 0.20 / 0.37 | 0.31 / 0.45 | 0.28 / 0.48 | 0.34 / 0.51 | 0.71× | 0.60× | 0.32 / 0.36 | 0.30 / 0.38 | 0.49 / 0.55 | 0.58 / 0.67 | 0.84 / 0.95 | 0.52× | 0.65× |
| `anim-delay-fill-t0` | animation | 0.15 / 0.26 | 0.16 / 0.30 | 0.26 / 0.37 | 0.33 / 0.49 | 0.47 / 0.62 | 0.48× | 0.58× | 0.24 / 0.27 | 0.23 / 0.29 | 0.38 / 0.43 | 0.59 / 0.69 | 0.90 / 0.97 | 0.38× | 0.64× |
| `anim-delay-fill-t750` | animation | 0.16 / 0.23 | 0.17 / 0.28 | 0.29 / 0.34 | 0.37 / 0.51 | 0.57 / 0.71 | 0.46× | 0.55× | 0.25 / 0.31 | 0.24 / 0.30 | 0.40 / 0.54 | 0.61 / 0.80 | 0.99 / 1.17 | 0.39× | 0.63× |
| `anim-delay-fill-t2000` | animation | 0.13 / 0.23 | 0.14 / 0.24 | 0.23 / 0.31 | 0.26 / 0.39 | 0.33 / 0.44 | 0.56× | 0.56× | 0.23 / 0.29 | 0.22 / 0.33 | 0.36 / 0.42 | 0.55 / 0.68 | 0.79 / 1.06 | 0.40× | 0.64× |
| `anim-alternate-t100` | animation | 0.14 / 0.19 | 0.16 / 0.23 | 0.22 / 0.29 | 0.33 / 0.52 | 0.45 / 0.64 | 0.49× | 0.64× | 0.18 / 0.25 | 0.17 / 0.25 | 0.27 / 0.30 | 0.59 / 0.72 | 0.90 / 1.02 | 0.29× | 0.67× |
| `anim-alternate-t500` | animation | 0.11 / 0.16 | 0.12 / 0.19 | 0.19 / 0.25 | 0.29 / 0.41 | 0.41 / 0.53 | 0.40× | 0.58× | 0.18 / 0.20 | 0.17 / 0.22 | 0.26 / 0.28 | 0.56 / 0.62 | 0.86 / 0.96 | 0.30× | 0.69× |
| `anim-alternate-t700` | animation | 0.13 / 0.17 | 0.15 / 0.29 | 0.21 / 0.29 | 0.31 / 0.51 | 0.44 / 0.56 | 0.46× | 0.63× | 0.17 / 0.22 | 0.17 / 0.23 | 0.25 / 0.31 | 0.56 / 0.70 | 0.87 / 1.01 | 0.30× | 0.69× |
| `anim-alternate-t1100` | animation | 0.12 / 0.25 | 0.14 / 0.27 | 0.21 / 0.30 | 0.32 / 0.56 | 0.45 / 0.69 | 0.44× | 0.57× | 0.18 / 0.22 | 0.17 / 0.25 | 0.26 / 0.30 | 0.58 / 0.71 | 0.88 / 1.02 | 0.29× | 0.67× |
| `anim-alternate-t1300` | animation | 0.10 / 0.16 | 0.11 / 0.21 | 0.18 / 0.24 | 0.22 / 0.35 | 0.26 / 0.40 | 0.48× | 0.56× | 0.16 / 0.21 | 0.16 / 0.23 | 0.24 / 0.27 | 0.46 / 0.55 | 0.68 / 0.80 | 0.34× | 0.67× |
| `anim-steps-t0` | animation | 0.11 / 0.19 | 0.12 / 0.25 | 0.20 / 0.28 | 0.24 / 0.47 | 0.28 / 0.45 | 0.52× | 0.56× | 0.19 / 0.23 | 0.18 / 0.25 | 0.28 / 0.32 | 0.49 / 0.63 | 0.71 / 0.84 | 0.36× | 0.67× |
| `anim-steps-t260` | animation | 0.12 / 0.18 | 0.13 / 0.21 | 0.21 / 0.28 | 0.25 / 0.43 | 0.29 / 0.39 | 0.53× | 0.58× | 0.18 / 0.21 | 0.17 / 0.23 | 0.28 / 0.32 | 0.48 / 0.56 | 0.70 / 0.76 | 0.36× | 0.66× |
| `anim-steps-t500` | animation | 0.11 / 0.17 | 0.12 / 0.21 | 0.20 / 0.28 | 0.24 / 0.38 | 0.29 / 0.39 | 0.51× | 0.56× | 0.18 / 0.20 | 0.17 / 0.23 | 0.28 / 0.29 | 0.49 / 0.53 | 0.70 / 0.76 | 0.36× | 0.67× |
| `anim-steps-t990` | animation | 0.11 / 0.19 | 0.12 / 0.20 | 0.20 / 0.28 | 0.23 / 0.49 | 0.27 / 0.40 | 0.51× | 0.58× | 0.19 / 0.23 | 0.18 / 0.25 | 0.28 / 0.31 | 0.49 / 0.60 | 0.70 / 0.82 | 0.36× | 0.66× |
| `anim-two-anims-t0` | animation | 0.13 / 0.19 | 0.13 / 0.27 | 0.23 / 0.30 | 0.28 / 0.50 | 0.42 / 0.64 | 0.46× | 0.56× | 0.19 / 0.25 | 0.18 / 0.28 | 0.29 / 0.34 | 0.56 / 0.67 | 0.89 / 1.00 | 0.33× | 0.65× |
| `anim-two-anims-t400` | animation | 0.16 / 0.23 | 0.18 / 0.27 | 0.27 / 0.33 | 0.43 / 0.52 | 0.70 / 0.83 | 0.42× | 0.59× | 0.24 / 0.26 | 0.22 / 0.32 | 0.35 / 0.41 | 0.71 / 0.82 | 1.17 / 1.43 | 0.31× | 0.68× |
| `anim-two-anims-t600` | animation | 0.18 / 0.22 | 0.18 / 0.27 | 0.30 / 0.34 | 0.45 / 0.56 | 0.76 / 0.85 | 0.41× | 0.61× | 0.25 / 0.32 | 0.24 / 0.30 | 0.37 / 0.43 | 0.73 / 0.85 | 1.24 / 1.37 | 0.32× | 0.68× |
| `anim-two-anims-t1200` | animation | 0.14 / 0.21 | 0.16 / 0.23 | 0.24 / 0.29 | 0.34 / 0.49 | 0.49 / 0.62 | 0.46× | 0.60× | 0.22 / 0.24 | 0.21 / 0.26 | 0.32 / 0.35 | 0.62 / 0.69 | 0.95 / 1.01 | 0.34× | 0.69× |
| `anim-inherit-t0` | animation | 0.19 / 0.26 | 0.20 / 0.31 | 0.31 / 0.37 | 0.44 / 0.69 | 0.54 / 0.70 | 0.46× | 0.63× | 0.33 / 0.39 | 0.31 / 0.41 | 0.49 / 0.56 | 0.74 / 0.90 | 1.01 / 1.21 | 0.42× | 0.69× |
| `anim-inherit-t500` | animation | 0.21 / 0.27 | 0.22 / 0.29 | 0.33 / 0.38 | 0.45 / 0.53 | 0.56 / 0.63 | 0.49× | 0.64× | 0.41 / 0.45 | 0.38 / 0.47 | 0.59 / 0.66 | 0.84 / 0.92 | 1.13 / 1.26 | 0.45× | 0.70× |
| `anim-inherit-t1000` | animation | 0.20 / 0.27 | 0.19 / 0.30 | 0.31 / 0.39 | 0.46 / 0.56 | 0.59 / 0.71 | 0.41× | 0.64× | 0.50 / 0.59 | 0.47 / 0.58 | 0.69 / 0.79 | 0.99 / 1.08 | 1.36 / 1.48 | 0.47× | 0.73× |
| `anim-tw-spin-t125` | animation | 0.14 / 0.18 | 0.15 / 0.23 | 0.22 / 0.29 | 0.32 / 0.47 | 0.45 / 0.58 | 0.47× | 0.63× | 0.20 / 0.24 | 0.19 / 0.28 | 0.29 / 0.34 | 0.59 / 0.68 | 0.90 / 1.07 | 0.32× | 0.69× |
| `anim-tw-spin-t375` | animation | 0.13 / 0.20 | 0.13 / 0.23 | 0.21 / 0.28 | 0.32 / 0.54 | 0.45 / 0.60 | 0.41× | 0.61× | 0.20 / 0.25 | 0.19 / 0.28 | 0.29 / 0.32 | 0.59 / 0.66 | 0.89 / 0.99 | 0.32× | 0.69× |
| `anim-tw-spin-t1600` | animation | 0.12 / 0.20 | 0.13 / 0.23 | 0.21 / 0.28 | 0.33 / 0.53 | 0.45 / 0.59 | 0.41× | 0.58× | 0.21 / 0.27 | 0.20 / 0.32 | 0.30 / 0.35 | 0.60 / 0.81 | 0.91 / 1.04 | 0.33× | 0.70× |
| `anim-kf-option-t0` | animation | 0.11 / 0.17 | 0.12 / 0.22 | 0.18 / 0.28 | 0.28 / 0.48 | 0.36 / 0.57 | 0.42× | 0.59× | 0.17 / 0.20 | 0.15 / 0.24 | 0.24 / 0.27 | 0.50 / 0.58 | 0.74 / 0.87 | 0.31× | 0.70× |
| `anim-kf-option-t500` | animation | 0.12 / 0.18 | 0.13 / 0.20 | 0.20 / 0.26 | 0.37 / 0.52 | 0.57 / 0.76 | 0.34× | 0.59× | 0.19 / 0.25 | 0.17 / 0.27 | 0.27 / 0.31 | 0.64 / 0.80 | 1.03 / 1.16 | 0.27× | 0.70× |
| `layout2-table-auto` | table | 0.61 / 0.68 | 0.59 / 0.91 | 1.01 / 1.23 | 1.07 / 1.45 | 1.45 / 1.60 | 0.55× | 0.61× | 1.05 / 1.23 | 1.00 / 1.19 | 1.58 / 1.63 | 1.84 / 1.93 | 3.01 / 3.45 | 0.55× | 0.66× |
| `layout2-table-spans` | table | 0.48 / 0.59 | 0.47 / 0.99 | 0.77 / 1.03 | 0.81 / 1.10 | 1.08 / 1.58 | 0.58× | 0.62× | 0.82 / 0.90 | 0.76 / 0.93 | 1.23 / 1.32 | 1.41 / 1.56 | 2.30 / 2.50 | 0.53× | 0.67× |
| `layout2-table-fixed` | table | 0.49 / 0.58 | 0.51 / 0.64 | 0.80 / 0.96 | 1.03 / 1.21 | 1.38 / 1.56 | 0.49× | 0.62× | 0.94 / 1.01 | 0.90 / 1.09 | 1.38 / 1.45 | 1.76 / 2.02 | 2.65 / 2.98 | 0.51× | 0.68× |
| `layout2-table-percent` | table | 0.34 / 0.37 | 0.33 / 0.46 | 0.54 / 0.68 | 0.68 / 1.05 | 0.86 / 0.99 | 0.48× | 0.63× | 0.53 / 0.67 | 0.48 / 0.60 | 0.78 / 0.89 | 1.09 / 1.30 | 1.63 / 1.76 | 0.44× | 0.68× |
| `layout2-table-collapse-conflicts` | table | 0.51 / 0.60 | 0.53 / 0.79 | 0.89 / 1.01 | 1.02 / 1.32 | 1.40 / 1.55 | 0.52× | 0.58× | 0.88 / 1.09 | 0.81 / 0.95 | 1.35 / 1.38 | 1.69 / 1.91 | 2.57 / 2.67 | 0.48× | 0.65× |
| `layout2-table-col-backgrounds` | table | 0.65 / 0.77 | 0.63 / 0.79 | 1.09 / 1.19 | 1.45 / 1.81 | 2.04 / 2.30 | 0.44× | 0.60× | 1.85 / 2.00 | 1.79 / 1.93 | 2.97 / 3.15 | 2.27 / 2.47 | 4.93 / 5.07 | 0.79× | 0.62× |
| `layout2-table-empty-cells` | table | 0.42 / 0.50 | 0.42 / 0.65 | 0.73 / 0.92 | 0.95 / 1.17 | 1.30 / 1.50 | 0.45× | 0.58× | 0.62 / 0.68 | 0.56 / 0.69 | 0.97 / 1.01 | 1.40 / 1.55 | 2.09 / 2.41 | 0.40× | 0.64× |
| `layout2-table-caption-bottom` | table | 0.58 / 0.72 | 0.57 / 0.70 | 1.03 / 1.28 | 1.17 / 1.46 | 1.63 / 1.83 | 0.49× | 0.56× | 0.95 / 1.04 | 0.89 / 1.01 | 1.49 / 1.59 | 1.79 / 1.86 | 2.83 / 3.15 | 0.50× | 0.64× |
| `layout2-float-image` | float | 0.32 / 0.47 | 0.34 / 0.59 | 0.68 / 0.84 | 0.66 / 0.95 | 0.86 / 1.28 | 0.51× | 0.48× | 1.58 / 1.77 | 1.58 / 1.69 | 2.48 / 2.73 | 1.57 / 1.74 | 5.65 / 5.92 | 1.01× | 0.64× |
| `layout2-float-clear` | float | 0.21 / 0.30 | 0.24 / 0.66 | 0.39 / 0.58 | 0.43 / 0.78 | 0.55 / 0.71 | 0.55× | 0.55× | 0.45 / 0.52 | 0.40 / 0.56 | 0.67 / 0.72 | 1.14 / 1.22 | 1.96 / 2.12 | 0.35× | 0.67× |
| `layout2-float-bfc` | float | 0.20 / 0.29 | 0.22 / 0.43 | 0.39 / 0.63 | 0.48 / 0.83 | 0.66 / 0.91 | 0.46× | 0.50× | 0.39 / 0.43 | 0.36 / 0.43 | 0.63 / 0.66 | 0.99 / 1.14 | 1.57 / 1.63 | 0.36× | 0.62× |
| `layout2-float-wrap` | float | 0.33 / 0.41 | 0.36 / 0.50 | 0.52 / 0.66 | 0.59 / 0.71 | 0.79 / 0.91 | 0.61× | 0.64× | 0.81 / 0.92 | 0.76 / 0.87 | 1.15 / 1.21 | 1.32 / 1.44 | 2.21 / 2.37 | 0.58× | 0.71× |
| `layout2-ib-badges` | inline-block | 0.26 / 0.34 | 0.27 / 0.44 | 0.44 / 0.60 | 0.55 / 0.61 | 0.70 / 0.85 | 0.50× | 0.59× | 0.49 / 0.56 | 0.44 / 0.60 | 0.71 / 0.77 | 1.00 / 1.17 | 1.44 / 1.66 | 0.44× | 0.69× |
| `layout2-ib-wrap` | inline-block | 0.36 / 0.50 | 0.35 / 0.49 | 0.63 / 0.95 | 0.63 / 0.78 | 0.85 / 1.01 | 0.56× | 0.57× | 0.70 / 0.82 | 0.65 / 0.88 | 1.07 / 1.28 | 1.27 / 1.43 | 2.10 / 2.36 | 0.52× | 0.66× |
| `layout2-ib-valign` | inline-block | 0.27 / 0.34 | 0.31 / 0.44 | 0.48 / 0.58 | 0.56 / 0.63 | 0.73 / 0.84 | 0.56× | 0.58× | 1.51 / 1.58 | 1.52 / 1.60 | 2.30 / 2.39 | 1.47 / 1.57 | 3.23 / 3.42 | 1.03× | 0.66× |
| `layout2-ib-json` | inline-block | 0.24 / 0.30 | 0.25 / 0.44 | 0.38 / 0.50 | 0.53 / 0.69 | 0.66 / 0.84 | 0.47× | 0.64× | 0.39 / 0.47 | 0.36 / 0.50 | 0.57 / 0.65 | 0.87 / 0.96 | 1.19 / 1.27 | 0.42× | 0.69× |
| `layout2-grid-areas` | grid-areas | 0.38 / 0.56 | 0.41 / 0.70 | 0.71 / 0.98 | 0.65 / 1.09 | 0.90 / 1.35 | 0.63× | 0.54× | 0.78 / 0.87 | 0.71 / 0.85 | 1.19 / 1.25 | 1.42 / 1.52 | 2.29 / 2.61 | 0.50× | 0.66× |
| `layout2-grid-named-lines` | grid-areas | 0.33 / 0.47 | 0.31 / 0.48 | 0.60 / 0.79 | 0.62 / 0.92 | 0.85 / 0.96 | 0.51× | 0.55× | 0.67 / 0.74 | 0.62 / 0.79 | 1.02 / 1.14 | 1.40 / 1.63 | 2.16 / 2.30 | 0.44× | 0.66× |
| `layout2-grid-areas-auto` | grid-areas | 0.26 / 0.36 | 0.25 / 0.65 | 0.47 / 0.63 | 0.56 / 0.81 | 0.76 / 0.99 | 0.44× | 0.55× | 0.56 / 0.79 | 0.50 / 0.85 | 0.84 / 1.00 | 1.18 / 1.85 | 1.85 / 2.27 | 0.43× | 0.67× |
| `layout3-float-left` | float-text | 0.36 / 0.45 | 0.38 / 0.79 | 0.58 / 0.79 | 0.61 / 0.98 | 0.83 / 1.00 | 0.62× | 0.62× | 0.83 / 0.90 | 0.79 / 0.88 | 1.20 / 1.36 | 1.32 / 1.41 | 2.18 / 2.40 | 0.60× | 0.69× |
| `layout3-float-right` | float-text | 0.42 / 0.48 | 0.40 / 0.52 | 0.64 / 0.72 | 0.67 / 1.12 | 0.92 / 1.24 | 0.60× | 0.65× | 0.83 / 0.96 | 0.79 / 0.94 | 1.19 / 1.38 | 1.34 / 1.64 | 2.20 / 2.35 | 0.59× | 0.70× |
| `layout3-float-stacked` | float-text | 0.49 / 0.80 | 0.51 / 0.88 | 0.78 / 1.08 | 0.80 / 1.17 | 1.12 / 1.60 | 0.64× | 0.63× | 1.20 / 1.30 | 1.18 / 1.39 | 1.72 / 1.92 | 1.66 / 1.82 | 3.01 / 3.20 | 0.71× | 0.70× |
| `layout3-float-tall` | float-text | 0.57 / 0.69 | 0.59 / 1.11 | 0.90 / 1.07 | 0.94 / 1.18 | 1.33 / 1.52 | 0.63× | 0.64× | 1.47 / 1.51 | 1.43 / 1.54 | 2.11 / 2.18 | 1.89 / 1.96 | 3.46 / 3.55 | 0.76× | 0.70× |
| `layout3-float-in-text` | float-text | 0.52 / 0.61 | 0.51 / 0.71 | 0.79 / 0.89 | 0.82 / 1.13 | 1.13 / 1.60 | 0.62× | 0.65× | 1.13 / 1.27 | 1.10 / 1.19 | 1.61 / 1.83 | 1.66 / 1.78 | 2.74 / 2.98 | 0.66× | 0.70× |
| `layout3-float-rtl` | float-text | 0.67 / 0.87 | 0.67 / 0.78 | 1.02 / 1.49 | 1.03 / 1.32 | 1.45 / 1.63 | 0.65× | 0.66× | 1.54 / 1.64 | 1.51 / 1.60 | 2.21 / 2.29 | 1.88 / 2.02 | 3.57 / 3.81 | 0.80× | 0.70× |
| `layout3-float-inline-box` | float-text | 0.38 / 0.47 | 0.38 / 0.79 | 0.61 / 0.80 | 0.65 / 0.88 | 0.88 / 1.13 | 0.58× | 0.62× | 0.89 / 1.03 | 0.84 / 0.98 | 1.27 / 1.39 | 1.43 / 1.74 | 2.33 / 2.79 | 0.59× | 0.70× |
| `layout3-inline-badges` | inline-flow | 0.47 / 0.56 | 0.47 / 0.57 | 0.75 / 0.84 | 0.87 / 0.99 | 1.19 / 1.40 | 0.55× | 0.63× | 1.00 / 1.09 | 0.96 / 1.05 | 1.43 / 1.52 | 1.60 / 1.72 | 2.60 / 2.81 | 0.60× | 0.70× |
| `layout3-inline-image` | inline-flow | 0.46 / 0.56 | 0.50 / 0.61 | 0.89 / 1.14 | 0.85 / 1.04 | 1.12 / 1.32 | 0.58× | 0.52× | 1.75 / 1.87 | 1.75 / 1.85 | 2.76 / 2.91 | 1.83 / 1.97 | 4.12 / 4.24 | 0.96× | 0.63× |
| `layout3-inline-flex-chip` | inline-flow | 0.56 / 0.65 | 0.57 / 0.76 | 1.17 / 1.29 | 1.07 / 1.34 | 1.47 / 1.65 | 0.53× | 0.48× | 1.63 / 1.75 | 1.62 / 1.78 | 2.66 / 2.74 | 2.15 / 2.34 | 4.33 / 4.67 | 0.75× | 0.62× |
| `layout3-inline-br` | inline-flow | 0.39 / 0.47 | 0.40 / 0.51 | 0.59 / 0.78 | 0.72 / 1.00 | 0.89 / 1.09 | 0.55× | 0.66× | 0.69 / 0.81 | 0.64 / 0.81 | 1.00 / 1.10 | 1.22 / 1.45 | 1.94 / 2.71 | 0.53× | 0.69× |
| `layout3-inline-abs` | inline-flow | 0.37 / 0.49 | 0.36 / 0.59 | 0.57 / 0.72 | 0.65 / 0.97 | 0.86 / 1.13 | 0.56× | 0.65× | 0.72 / 0.78 | 0.67 / 0.91 | 1.02 / 1.19 | 1.15 / 1.49 | 1.85 / 2.14 | 0.58× | 0.71× |
| `layout3-span-edges` | inline-box-model | 0.58 / 0.63 | 0.58 / 0.69 | 0.93 / 1.03 | 0.79 / 0.94 | 1.11 / 1.22 | 0.74× | 0.62× | 1.03 / 1.04 | 1.00 / 1.09 | 1.53 / 1.59 | 1.51 / 1.62 | 2.41 / 2.51 | 0.66× | 0.67× |
| `layout3-span-nowrap` | inline-box-model | 0.48 / 0.68 | 0.49 / 0.67 | 0.75 / 0.86 | 0.85 / 1.04 | 1.10 / 1.24 | 0.57× | 0.65× | 0.99 / 1.18 | 0.94 / 1.27 | 1.42 / 1.64 | 1.54 / 1.78 | 2.45 / 2.86 | 0.61× | 0.70× |
| `layout3-span-valign` | inline-box-model | 0.57 / 0.70 | 0.56 / 0.68 | 0.91 / 1.02 | 1.12 / 1.37 | 1.48 / 1.57 | 0.50× | 0.63× | 1.16 / 1.22 | 1.12 / 1.23 | 1.68 / 1.74 | 1.81 / 1.99 | 3.00 / 3.26 | 0.62× | 0.69× |
| `layout3-card-all` | inline-box-model | 1.40 / 1.68 | 1.41 / 2.25 | 2.37 / 2.50 | 2.31 / 2.95 | 3.13 / 3.61 | 0.61× | 0.59× | 3.76 / 4.23 | 3.75 / 4.17 | 5.80 / 6.32 | 3.94 / 4.42 | 9.17 / 9.58 | 0.95× | 0.65× |
| `fix-css-struct-text-nodes` | css-stylesheet | 0.57 / 0.70 | 0.54 / 1.03 | 0.86 / 1.17 | 1.06 / 1.72 | 1.37 / 1.64 | 0.51× | 0.66× | 0.85 / 0.96 | 0.78 / 0.90 | 1.27 / 1.44 | 1.93 / 2.30 | 3.08 / 3.22 | 0.41× | 0.67× |
| `fix-css-blank-text-dropped` | css-stylesheet | 0.25 / 0.30 | 0.23 / 0.30 | 0.42 / 0.63 | 0.53 / 0.79 | 0.69 / 0.82 | 0.44× | 0.60× | 0.40 / 0.45 | 0.36 / 0.45 | 0.60 / 0.65 | 0.91 / 1.01 | 1.34 / 1.43 | 0.39× | 0.67× |
| `fix-css-tw-structural-text` | tailwind | 0.52 / 0.64 | 0.51 / 0.63 | 0.82 / 0.97 | 0.86 / 1.51 | 1.21 / 1.53 | 0.59× | 0.64× | 0.79 / 0.82 | 0.72 / 0.87 | 1.16 / 1.19 | 1.44 / 1.52 | 2.26 / 2.40 | 0.50× | 0.68× |
| `fix-css-playground-css-demo` | css-stylesheet | 0.78 / 1.12 | 0.77 / 1.47 | 1.14 / 1.65 | 1.21 / 2.27 | 1.59 / 1.97 | 0.63× | 0.68× | 1.47 / 1.62 | 1.36 / 1.53 | 2.12 / 2.32 | 2.49 / 2.56 | 4.64 / 4.82 | 0.55× | 0.69× |
| `fix-css-transform-nested` | transform | 0.25 / 0.34 | 0.27 / 0.45 | 0.41 / 0.59 | 0.70 / 0.98 | 1.18 / 1.33 | 0.39× | 0.60× | 0.49 / 0.56 | 0.47 / 0.68 | 0.72 / 0.80 | 1.27 / 1.48 | 2.22 / 2.59 | 0.37× | 0.68× |
| `fix-css-transform-abs-text` | transform | 0.35 / 0.47 | 0.36 / 0.68 | 0.55 / 0.76 | 0.82 / 1.14 | 1.31 / 1.75 | 0.45× | 0.63× | 0.58 / 0.78 | 0.54 / 0.76 | 0.84 / 1.04 | 1.32 / 1.56 | 2.31 / 2.58 | 0.41× | 0.70× |
| `fix-css-image-rendering-pixelated` | images | 0.43 / 0.49 | 0.48 / 0.76 | 0.87 / 1.07 | 1.05 / 1.30 | 1.22 / 1.45 | 0.46× | 0.49× | 2.42 / 2.50 | 2.47 / 2.62 | 3.74 / 4.06 | 2.15 / 2.26 | 7.55 / 7.95 | 1.15× | 0.65× |
| `fix-css-image-rendering-modes` | images | 0.95 / 1.38 | 1.03 / 1.45 | 1.94 / 2.11 | 2.18 / 3.38 | 2.72 / 2.99 | 0.47× | 0.49× | 5.08 / 5.78 | 5.09 / 5.34 | 8.08 / 8.42 | 4.17 / 4.63 | 15.3 / 15.7 | 1.22× | 0.63× |
| `fix-css-tw-theme` | tailwind | 0.55 / 0.85 | 0.62 / 1.00 | 0.90 / 1.28 | 0.93 / 1.21 | 1.26 / 1.53 | 0.66× | 0.61× | 0.86 / 0.98 | 0.83 / 1.17 | 1.28 / 1.38 | 1.48 / 1.61 | 2.63 / 3.37 | 0.56× | 0.67× |
| `fix-css-tw-theme-node-vars` | tailwind | 0.23 / 0.30 | 0.25 / 0.39 | 0.36 / 0.57 | 0.38 / 0.52 | 0.46 / 0.63 | 0.65× | 0.64× | 0.31 / 0.36 | 0.30 / 0.38 | 0.48 / 0.51 | 0.64 / 0.72 | 0.91 / 1.01 | 0.47× | 0.66× |
| `fix-css-tw-animate` | tailwind | 0.43 / 0.48 | 0.42 / 0.57 | 0.68 / 0.73 | 0.62 / 0.81 | 1.03 / 1.20 | 0.67× | 0.63× | 0.56 / 0.60 | 0.54 / 0.60 | 0.85 / 0.92 | 0.95 / 1.10 | 1.56 / 1.64 | 0.57× | 0.66× |
| `fix-css-cascade-layers-tw` | css-stylesheet | 0.16 / 0.24 | 0.16 / 0.27 | 0.27 / 0.44 | 0.24 / 0.38 | 0.29 / 0.41 | 0.69× | 0.62× | 0.23 / 0.31 | 0.22 / 0.31 | 0.34 / 0.44 | 0.54 / 0.63 | 0.75 / 0.91 | 0.40× | 0.67× |
| `fix-css-anim-font-size-em-t0` | animation | 0.12 / 0.20 | 0.12 / 0.17 | 0.20 / 0.25 | 0.25 / 0.40 | 0.29 / 0.45 | 0.47× | 0.60× | 0.20 / 0.22 | 0.19 / 0.25 | 0.30 / 0.35 | 0.47 / 0.53 | 0.57 / 0.69 | 0.41× | 0.66× |
| `fix-css-anim-font-size-em-t500` | animation | 0.12 / 0.17 | 0.12 / 0.22 | 0.20 / 0.26 | 0.25 / 0.39 | 0.30 / 0.42 | 0.48× | 0.59× | 0.21 / 0.33 | 0.20 / 0.28 | 0.31 / 0.38 | 0.51 / 0.66 | 0.61 / 0.78 | 0.39× | 0.68× |
| `fix-text-overflow-string` | text-overflow | 0.38 / 0.47 | 0.36 / 0.50 | 0.56 / 0.83 | 0.91 / 1.04 | 1.17 / 1.53 | 0.39× | 0.68× | 0.68 / 0.73 | 0.64 / 0.79 | 0.96 / 0.99 | 1.46 / 1.58 | 2.12 / 2.31 | 0.44× | 0.70× |
| `fix-text-overflow-string-fallback` | text-overflow | 0.28 / 0.34 | 0.28 / 0.35 | 0.41 / 0.50 | 0.75 / 0.95 | 0.92 / 1.18 | 0.37× | 0.69× | 0.65 / 0.86 | 0.65 / 0.78 | 0.90 / 1.01 | 1.32 / 1.50 | 1.86 / 2.11 | 0.49× | 0.73× |
| `fix-text-overflow-string-rtl` | text-overflow | 0.26 / 0.31 | 0.24 / 0.33 | 0.39 / 0.44 | 0.67 / 0.79 | 0.87 / 0.97 | 0.36× | 0.67× | 0.50 / 0.58 | 0.48 / 0.62 | 0.69 / 0.81 | 1.09 / 1.29 | 1.60 / 1.93 | 0.44× | 0.73× |
| `fix-text-line-clamp-marker` | text-overflow | 0.37 / 0.42 | 0.37 / 0.48 | 0.56 / 0.73 | 0.89 / 1.06 | 1.17 / 1.45 | 0.41× | 0.66× | 0.74 / 0.79 | 0.71 / 0.88 | 1.07 / 1.31 | 1.51 / 1.98 | 2.39 / 2.60 | 0.47× | 0.69× |
| `fix-text-paint-order` | text-stroke | 0.77 / 0.96 | 0.80 / 1.20 | 1.32 / 1.75 | 0.67 / 1.07 | 0.92 / 1.26 | 1.20× | 0.58× | 1.40 / 1.56 | 1.39 / 1.55 | 2.14 / 2.35 | 1.39 / 1.51 | 2.48 / 2.66 | 1.00× | 0.65× |
| `fix-text-small-caps` | font-variant | 0.26 / 0.36 | 0.25 / 0.50 | 0.41 / 0.55 | 0.65 / 0.85 | 0.83 / 1.02 | 0.38× | 0.62× | 0.80 / 0.86 | 0.78 / 0.97 | 1.12 / 1.23 | 1.36 / 1.44 | 2.14 / 2.24 | 0.57× | 0.71× |
| `fix-text-all-small-caps` | font-variant | 0.36 / 0.49 | 0.38 / 0.54 | 0.55 / 0.69 | 0.83 / 1.16 | 1.08 / 1.33 | 0.46× | 0.65× | 1.01 / 1.08 | 0.98 / 1.09 | 1.41 / 1.46 | 1.65 / 1.81 | 2.86 / 3.11 | 0.59× | 0.72× |
| `fix-text-petite-unicase-caps` | font-variant | 0.64 / 0.94 | 0.62 / 1.07 | 0.88 / 1.11 | 1.24 / 2.23 | 1.60 / 2.51 | 0.50× | 0.72× | 1.74 / 1.86 | 1.66 / 1.82 | 2.41 / 2.54 | 2.44 / 2.69 | 4.61 / 4.84 | 0.68× | 0.72× |
| `fix-text-emoji-zwj` | emoji | 0.13 / 0.17 | 0.13 / 0.22 | 0.20 / 0.24 | 0.48 / 0.64 | 0.65 / 0.80 | 0.27× | 0.66× | 0.98 / 1.19 | 0.94 / 1.07 | 1.43 / 1.75 | 0.81 / 0.97 | 1.07 / 1.20 | 1.17× | 0.68× |
| `fix-text-emoji-flags-skin` | emoji | 0.12 / 0.18 | 0.12 / 0.23 | 0.19 / 0.28 | 0.41 / 0.59 | 0.51 / 0.77 | 0.29× | 0.64× | 0.24 / 0.30 | 0.22 / 0.34 | 0.33 / 0.41 | 0.67 / 0.81 | 0.88 / 1.19 | 0.32× | 0.72× |
| `fix-text-emoji-keycap-vs` | emoji | 0.12 / 0.19 | 0.12 / 0.18 | 0.19 / 0.22 | 0.39 / 0.48 | 0.49 / 0.76 | 0.31× | 0.64× | 0.29 / 0.31 | 0.26 / 0.35 | 0.40 / 0.43 | 0.69 / 0.76 | 0.89 / 1.02 | 0.38× | 0.72× |
| `fix-text-emoji-spacing` | emoji | 0.13 / 0.21 | 0.14 / 0.26 | 0.21 / 0.34 | 0.52 / 0.81 | 0.70 / 0.99 | 0.26× | 0.64× | 1.06 / 1.44 | 1.06 / 1.37 | 1.52 / 1.73 | 0.91 / 1.05 | 1.15 / 1.67 | 1.17× | 0.70× |
| `fix-text-emoji-wrap` | emoji | 0.12 / 0.20 | 0.13 / 0.21 | 0.19 / 0.26 | 0.48 / 0.65 | 0.64 / 0.85 | 0.26× | 0.64× | 0.43 / 0.61 | 0.41 / 0.53 | 0.62 / 0.71 | 0.74 / 0.99 | 0.98 / 1.19 | 0.55× | 0.70× |
| `fix-layout-rtl-flex` | rtl | 0.35 / 0.43 | 0.37 / 0.51 | 0.65 / 0.75 | 0.61 / 0.78 | 0.77 / 0.84 | 0.61× | 0.54× | 0.52 / 0.58 | 0.48 / 0.56 | 0.85 / 0.88 | 1.06 / 1.19 | 1.51 / 1.59 | 0.45× | 0.61× |
| `fix-layout-rtl-flex-wrap-abs` | rtl | 0.32 / 0.41 | 0.31 / 0.42 | 0.58 / 0.68 | 0.55 / 0.69 | 0.71 / 0.83 | 0.56× | 0.54× | 0.49 / 0.52 | 0.46 / 0.54 | 0.80 / 0.93 | 1.02 / 1.10 | 1.47 / 1.54 | 0.45× | 0.62× |
| `fix-layout-rtl-grid-block` | rtl | 0.34 / 0.45 | 0.32 / 0.53 | 0.61 / 0.72 | 0.64 / 0.88 | 0.82 / 1.13 | 0.50× | 0.56× | 0.59 / 0.68 | 0.53 / 0.72 | 0.90 / 1.13 | 1.21 / 1.30 | 1.66 / 1.80 | 0.44× | 0.66× |
| `fix-layout-rtl-table` | rtl | 0.72 / 0.79 | 0.69 / 0.95 | 1.21 / 1.33 | 1.67 / 1.90 | 2.28 / 2.56 | 0.41× | 0.59× | 1.13 / 1.21 | 1.09 / 1.26 | 1.77 / 1.82 | 2.33 / 2.39 | 3.60 / 3.71 | 0.47× | 0.64× |
| `fix-layout-rtl-node-dir` | rtl | 0.06 / 0.11 | 0.07 / 0.15 | 0.10 / 0.16 | 0.17 / 0.31 | 0.18 / 0.29 | 0.45× | 0.60× | 0.11 / 0.13 | 0.11 / 0.14 | 0.16 / 0.18 | 0.30 / 0.38 | 0.35 / 0.43 | 0.38× | 0.71× |
| `fix-layout-text-indent` | text-indent | 0.55 / 0.63 | 0.53 / 0.65 | 0.85 / 1.00 | 0.91 / 1.04 | 1.27 / 1.47 | 0.58× | 0.65× | 1.28 / 1.37 | 1.24 / 1.57 | 1.84 / 1.89 | 1.67 / 2.10 | 3.08 / 3.49 | 0.74× | 0.70× |
| `fix-layout-text-indent-keywords` | text-indent | 0.67 / 0.80 | 0.64 / 0.78 | 1.03 / 1.19 | 1.08 / 1.24 | 1.53 / 1.68 | 0.60× | 0.65× | 1.44 / 1.48 | 1.40 / 1.49 | 2.05 / 2.09 | 1.97 / 2.03 | 3.34 / 3.51 | 0.71× | 0.70× |
| `fix-layout-text-indent-sizing` | text-indent | 0.48 / 0.62 | 0.45 / 0.72 | 0.76 / 1.04 | 0.95 / 1.20 | 1.28 / 1.43 | 0.48× | 0.63× | 0.96 / 1.18 | 0.97 / 1.30 | 1.37 / 1.73 | 1.76 / 2.12 | 2.61 / 3.07 | 0.55× | 0.70× |
| `fix-layout-text-indent-node` | text-indent | 0.29 / 0.39 | 0.29 / 0.51 | 0.43 / 0.56 | 0.63 / 0.89 | 0.78 / 0.99 | 0.45× | 0.67× | 0.56 / 0.63 | 0.53 / 0.61 | 0.79 / 0.89 | 1.07 / 1.17 | 1.44 / 1.69 | 0.50× | 0.71× |
| `fix-layout-inline-rtl-box` | inline-bidi | 0.53 / 0.60 | 0.52 / 0.70 | 0.83 / 0.99 | 1.00 / 1.17 | 1.33 / 1.59 | 0.52× | 0.64× | 0.92 / 1.03 | 0.88 / 1.16 | 1.35 / 1.62 | 1.57 / 1.73 | 2.32 / 2.57 | 0.56× | 0.69× |
| `fix-layout-inline-bidi-fragments` | inline-bidi | 0.46 / 0.48 | 0.44 / 0.51 | 0.73 / 0.90 | 0.95 / 1.11 | 1.27 / 1.51 | 0.46× | 0.63× | 0.79 / 0.89 | 0.74 / 0.86 | 1.17 / 1.26 | 1.51 / 1.62 | 2.10 / 2.28 | 0.49× | 0.68× |
| `fix-layout-inline-bidi-wrap` | inline-bidi | 0.52 / 0.60 | 0.49 / 0.58 | 0.82 / 0.89 | 1.05 / 1.24 | 1.42 / 1.57 | 0.47× | 0.63× | 0.97 / 1.10 | 0.94 / 1.21 | 1.43 / 1.51 | 1.75 / 2.04 | 2.75 / 3.39 | 0.54× | 0.68× |
| `fix-layout-balance-inline-boxes` | text-wrap-balance | 0.67 / 1.01 | 0.64 / 1.12 | 1.05 / 1.27 | 1.25 / 1.73 | 1.74 / 2.20 | 0.51× | 0.63× | 1.20 / 1.29 | 1.17 / 1.30 | 1.75 / 1.93 | 1.90 / 2.02 | 3.14 / 3.18 | 0.61× | 0.68× |
| `fix-layout-balance-atomic` | text-wrap-balance | 0.76 / 0.81 | 0.72 / 0.87 | 1.15 / 1.31 | 1.34 / 1.48 | 1.84 / 2.03 | 0.53× | 0.66× | 1.40 / 1.67 | 1.41 / 1.53 | 2.02 / 2.24 | 2.08 / 2.46 | 3.31 / 3.73 | 0.68× | 0.70× |
| `fix-layout-balance-floats` | text-wrap-balance | 0.48 / 0.59 | 0.46 / 0.74 | 0.75 / 0.83 | 0.85 / 1.17 | 1.17 / 1.50 | 0.54× | 0.64× | 0.91 / 1.03 | 0.87 / 1.02 | 1.32 / 1.57 | 1.45 / 1.68 | 2.20 / 2.49 | 0.60× | 0.69× |
| `fix-layout-block-in-inline` | block-in-inline | 0.35 / 0.39 | 0.34 / 0.43 | 0.54 / 0.66 | 0.74 / 0.97 | 0.97 / 1.23 | 0.47× | 0.64× | 0.60 / 0.79 | 0.56 / 0.76 | 0.87 / 1.02 | 1.19 / 1.45 | 1.69 / 1.83 | 0.47× | 0.69× |
| `fix-layout-block-in-inline-nested` | block-in-inline | 0.52 / 0.69 | 0.51 / 0.66 | 0.82 / 0.88 | 1.07 / 1.36 | 1.44 / 1.81 | 0.47× | 0.64× | 1.01 / 1.40 | 0.93 / 1.37 | 1.45 / 1.68 | 1.84 / 1.99 | 2.80 / 3.04 | 0.51× | 0.69× |
| `fix-layout-block-in-inline-align` | block-in-inline | 0.40 / 0.44 | 0.37 / 0.54 | 0.64 / 0.88 | 0.91 / 1.18 | 1.21 / 1.42 | 0.41× | 0.62× | 0.72 / 0.81 | 0.68 / 0.96 | 1.07 / 1.19 | 1.50 / 1.78 | 2.29 / 2.51 | 0.45× | 0.67× |
| `fix-layout-block-in-inline-node` | block-in-inline | 0.17 / 0.26 | 0.16 / 0.28 | 0.26 / 0.37 | 0.44 / 0.68 | 0.54 / 0.77 | 0.36× | 0.67× | 0.33 / 0.42 | 0.30 / 0.43 | 0.46 / 0.53 | 0.75 / 0.87 | 0.93 / 1.07 | 0.40× | 0.72× |
| `fix-layout-float-paint-text` | float-paint-order | 0.31 / 0.39 | 0.32 / 0.47 | 0.48 / 0.66 | 0.62 / 0.82 | 0.78 / 1.02 | 0.51× | 0.64× | 0.62 / 0.68 | 0.59 / 0.71 | 0.88 / 0.95 | 1.06 / 1.14 | 1.36 / 1.46 | 0.55× | 0.70× |
| `fix-layout-float-paint-layers` | float-paint-order | 0.40 / 0.49 | 0.38 / 0.51 | 0.65 / 0.78 | 0.81 / 1.00 | 1.12 / 1.25 | 0.47× | 0.62× | 0.70 / 0.85 | 0.67 / 0.80 | 1.05 / 1.20 | 1.30 / 1.45 | 1.86 / 2.12 | 0.51× | 0.67× |
| `fix-layout-float-paint-nested` | float-paint-order | 0.37 / 0.45 | 0.36 / 0.46 | 0.58 / 0.68 | 0.75 / 1.01 | 0.99 / 1.26 | 0.48× | 0.63× | 0.67 / 0.82 | 0.63 / 0.86 | 0.96 / 1.08 | 1.22 / 1.55 | 1.72 / 1.89 | 0.52× | 0.69× |
| `fix-layout-inline-relative` | inline-relative | 0.47 / 0.55 | 0.46 / 0.55 | 0.71 / 0.81 | 1.00 / 1.13 | 1.26 / 1.45 | 0.47× | 0.66× | 0.84 / 0.92 | 0.82 / 0.98 | 1.21 / 1.27 | 1.53 / 1.68 | 2.01 / 2.43 | 0.53× | 0.70× |

median / p95 ms từng fixture (median qua các lượt của median và p95 mỗi lượt). Tỉ lệ: bm-native async / takumi-native async, bm-native sync / bm-wasm sync.
<!-- /native-bench:per-fixture -->

## Giai đoạn 3 — trạng thái cuối cùng của 0.1.0

> **Ghi chú (2026-11-12): số liệu giai đoạn 3 bên dưới là lịch sử (200 fixture).** Bản build cuối (wasm, so với `@takumi-rs/wasm` 2.20.0, 250 fixture) cho: kích thước (KiB, raw / gzip -9 / brotli) core 487.6 / 228.4 / 194.3, standard 934.4 / 463.7 / 398.0, full 1 141.5 / 559.0 / 469.8 (nhỏ hơn takumi 8.7× / 4.5× / 3.7×);
> tương đương 81 identical / 169 equivalent / 0 close / 0 different / 0 lỗi; tỉ lệ thời gian bm / takumi-wasm (geomean) raw 0.63×, PNG 0.45×; cold start 78.1 ms so với 193.8 ms; bộ nhớ wasm sau 50 lần render 11.6 so với 10.6 MiB; 436 unit test.
> Số liệu native của giai đoạn 4 ở đầu file là số hiện hành.

Đo trên bản build cuối (sau `wasm-opt`), so với `@takumi-rs/wasm` 2.20.0.

- **Kích thước (KiB, raw / gzip -9 / brotli):** core 454.9 / 211.6 / 180.4; standard 878.1 / 435.5 / 374.6; full 1 100.9 / 538.3 / 453.7;
  add-on WOFF 84.2 / 67.7 / 65.5; takumi-wasm 2.20: 4 234.9 / 1 860.9 / 1 409.3. So với takumi (raw): core nhỏ hơn 9.3×, standard 4.8×, full 3.8×.
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
| `core` | **454.9** | 211.6 | 180.4 | nhỏ hơn 9.3× | node JSON + style inline, var()/calc, flex/grid/block/absolute, hàng inline, TTF/TTC tĩnh + OpenType shaper mặc định, viền mọi kiểu/outline/trang trí chữ, PNG/JPEG vào, PNG/JPEG/WebP/raw ra |
| `standard` | **878.1** | 435.5 | 374.6 | nhỏ hơn 4.8× | core + stylesheet/selector, Tailwind, HTML, ảnh SVG, WOFF/WOFF2, font biến thiên, CFF, clip-path/mask/blend/backdrop, màu oklch/lab/color-mix, bảng, float, WebP/GIF vào, text-wrap balance |
| `full` (mặc định) | **1 100.9** | 538.3 | 453.7 | nhỏ hơn 3.8× | standard + chữ phức (bidi, Ả Rập, Hebrew, Indic, Thái), emoji màu, animation + renderAnimation, VP8 lossy, ảnh động, ICO, renderSvg |
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

- **PDF: không có trong các profile `core` / `standard` / `full` và không nằm trong benchmark này.** `takumi-pdf` là gói npm riêng (không thuộc `@takumi-rs/wasm`), ~43 500 dòng Rust. Sau giai đoạn đo này, bm-engine đã thêm nó thành profile `pdf` riêng (`bm-engine/pdf`; xem [Đầu ra PDF](en/pdf/index.md) và [bản tiếng Việt](vi/pdf/index.md)). Các con số speed / size / SSIM trong báo cáo này chỉ nói về đầu ra ảnh; đầu ra PDF chưa được benchmark về tốc độ và kích thước.
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
  (`timeMs`, `renderAnimation`), không HTML đầu vào, không `renderSvg`, không PDF (về sau đã thêm thành profile `pdf` riêng), không bảng (table), float, list marker.
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
