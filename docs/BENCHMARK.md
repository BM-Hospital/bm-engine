# bm-render (Zig) so với takumi 2.20.0 — benchmark và kiểm tra tương đương

> **Giai đoạn 4 (2026-11-12)** — addon native cho Node.js: bm-native, bm-wasm, takumi-native và takumi-wasm đo cùng lúc; ở ngay dưới, mọi bảng sinh từ [results-native.json](results-native.json).
> **Giai đoạn 3 (2026-11-12)** — số liệu cuối cùng của 0.1.0 (bản wasm) ở sau đó; giai đoạn 2 được giữ làm lịch sử (số của giai đoạn 2 được ghi rõ). Báo cáo giai đoạn 1 được giữ nguyên ở cuối file để đối chiếu.
> Số liệu từng fixture: [RESULTS_FULL.md](RESULTS_FULL.md), [results.json](results.json). Ảnh: `bench/out/<id>/`.

## Giai đoạn 6 — PDF

Đầu ra PDF (`bm-render/pdf`) được đo với ba engine trên cùng máy, cùng Node, cùng font, cùng ảnh và cùng đầu vào:
**bm-native** (addon Node-API, API sync và async), **bm-wasm** (`js/bm_render.pdf.wasm`, profile `pdf`) và
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
| bm-render | 0.1.1, git `67c0f368a2` (main, 14 file đang sửa) |
| bm-native | `native/dist/win32-x64-msvc/bm-render.win32-x64-msvc.node`, 3.684 KiB, sha256 `664ed6bd9520` |
| bm-wasm | `js/bm_render.pdf.wasm` (profile pdf), 1.910 KiB, sha256 `86b1e5af54b2` |
| takumi-pdf | npm `takumi-pdf` 0.20.0 (wasm, 4.335 KiB); không có bản native nào được phát hành |
| Lần chạy | 2026-11-16 20:42 UTC, full, 6.4 min; CPU bận trước khi chạy: 20.7 % |
| Chạy lại một phần | 2026-11-16 21:11 (equiv) |
<!-- /pdf-bench:env -->

### Tóm tắt

<!-- pdf-bench:summary -->
- **Thời gian render, bm-native so với takumi-pdf:** sync 0,31× [0,31× / 0,31× / 0,31×] (nhanh hơn ở 159/159, 0,14×–0,69×); async 0,38× [0,38× / 0,38× / 0,37×] (nhanh hơn ở 159/159, 0,15×–0,78×). Dưới 1× = bm tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ ở từng lượt.
- **bm-wasm vs takumi-pdf (cả hai là wasm):** 0,47× [0,47× / 0,47× / 0,47×] (nhanh hơn ở 159/159, 0,25×–0,91×). **bm-native vs bm-wasm (sync):** 0,66× [0,65× / 0,66× / 0,66×] (nhanh hơn ở 159/159, 0,42×–0,79×).
- **Trang mỗi giây ở 1 / 10 / 100 / 500 trang:** bm-native 408 / 677 / 761 / 405; bm-wasm 119 / 278 / 373 / 231; takumi-pdf 40 / 73 / 107 / 94.
- **Trùng byte:** bm-native == bm-wasm 161/161 tài liệu.
- **Bộ kiểm tra:** bm-native 152/161 PDF không có lỗi hay cảnh báo nào (takumi-pdf 152/161); veraPDF bm-native 45/45, takumi-pdf 45/45; cùng chữ, liên kết, mục lục và thẻ như takumi-pdf: 153/161.
- **Kết luận hình ảnh so với takumi-pdf (tốt nhất trong các bộ raster):** identical 117, equivalent 35, different 8, close 1 (161 tài liệu, pdfium + mupdf).
<!-- /pdf-bench:summary -->

### Thời gian render

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
| 1 | 2,50 ms | 407,9 | 27 KiB | 63 MiB | 8,40 ms | 118,6 | 27 KiB | 95 MiB | 25,0 ms | 40,0 | 27 KiB | 122 MiB |
| 10 | 14,8 ms | 676,9 | 60 KiB | 68 MiB | 35,9 ms | 278,2 | 60 KiB | 99 MiB | 136 ms | 73,3 | 58 KiB | 133 MiB |
| 100 | 131 ms | 760,9 | 390 KiB | 101 MiB | 269 ms | 372,5 | 390 KiB | 113 MiB | 936 ms | 106,8 | 426 KiB | 145 MiB |
| 500 | 1.235 ms | 404,7 | 1.868 KiB | 205 MiB | 2.170 ms | 230,5 | 1.868 KiB | 209 MiB | 5.348 ms | 93,5 | 2.186 KiB | 205 MiB |

Một lần render tài liệu stress (mỗi trang: tiêu đề, đoạn văn, bảng 14 dòng, một ảnh; `break-after: page`) trong một tiến trình mới cho mỗi điểm; làm nóng bằng tài liệu 1 trang. Độ siêu tuyến tính (thời gian mỗi trang ở 100 trang / ở 10 trang; 1× = tuyến tính): bm-native 0,89×, bm-wasm 0,75×, takumi-pdf 0,69×.
<!-- /pdf-bench:scale -->

### Khởi động lạnh

<!-- pdf-bench:cold -->
| Engine | wall median ms | p95 | hơn Node trống | import | font | PDF đầu tiên | RSS đỉnh |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Node.js trống | 59,7 | 64,7 | — | — | — | — | 53 MiB |
| bm-native | 74,9 | 86,4 | 15,1 | 8,50 | 0,58 | 4,20 | 58 MiB |
| bm-wasm | 168 | 201 | 109 | 12,8 | 3,24 | 67,4 | 82 MiB |
| takumi-pdf | 250 | 312 | 190 | 42,3 | 3,57 | 121 | 90 MiB |

30 lần mỗi engine, xen kẽ: khởi động Node -> import -> đăng ký Inter Regular -> hoá đơn A4 một trang -> thoát. CPU bận trong lúc đo 48.4 %.
<!-- /pdf-bench:cold -->

### Bộ nhớ

<!-- pdf-bench:memory -->
| Engine | RSS sau lượt 1 | RSS sau lượt 10 | bộ nhớ engine (lượt 1 → cuối) | RSS đỉnh, tài liệu stress lớn nhất |
|:--|--:|--:|--:|--:|
| bm-native | 99 MiB | 100 MiB | 30,7 → 30,4 MiB | 500 trang: 205 MiB |
| bm-wasm | 128 MiB | 129 MiB | 60,1 → 60,1 MiB | 500 trang: 209 MiB |
| takumi-pdf | 130 MiB | 132 MiB | 46,3 → 46,3 MiB | 500 trang: 205 MiB |

Mọi tài liệu hướng dẫn (21) render 10 lần, GC trước mỗi lần đọc; Node.js trống: 51.4 MiB RSS. Bộ nhớ engine: bm Renderer.memoryBytes (bộ nhớ tuyến tính wasm, hoặc phần cấp phát đang sống của addon native), takumi-pdf: bộ nhớ wasm.
<!-- /pdf-bench:memory -->

### Chặn event loop

<!-- pdf-bench:eventloop -->
| Engine | API | render ms | độ trễ timer lớn nhất | p99 | số tick |
|:--|--:|--:|--:|--:|--:|
| bm-native | sync | 158 | 158 ms | 158 ms | 1 |
| bm-native | async | 169 | 1,10 ms | 1,00 ms | 171 |
| bm-wasm | sync | 393 | 393 ms | 393 ms | 1 |
| bm-wasm | async | 402 | 402 ms | 402 ms | 1 |
| takumi-pdf | async | 1.173 | 1.173 ms | 1.173 ms | 1 |

Một lần render 100 trang trong khi một timer 1 ms chạy; độ trễ gần bằng thời gian render nghĩa là event loop bị chặn suốt lần render.
<!-- /pdf-bench:eventloop -->

### Thông lượng song song

<!-- pdf-bench:throughput -->
| Cấu hình | N=1 | N=2 | N=4 | N=8 |
|:--|--:|--:|--:|--:|
| bm-native seq uv=4 | 520 |  |  |  |
| bm-wasm seq | 295 |  |  |  |
| takumi-pdf seq | 125 |  |  |  |
| bm-native many k=1 uv=4 | 417 | 506 | 454 | 514 |
| bm-native many k=2 uv=4 | 453 | 798 | 801 | 855 |
| bm-native many k=4 uv=4 | 459 | 793 | 1.252 | 1.374 |
| bm-native many k=8 uv=4 | 475 | 760 | 1.147 | 1.306 |
| bm-native many k=1 uv=8 | 489 | 476 | 490 | 471 |
| bm-native many k=2 uv=8 | 445 | 843 | 724 | 670 |
| bm-native many k=4 uv=8 | 365 | 858 | 1.286 | 1.328 |
| bm-native many k=8 uv=8 | 489 | 822 | 1.225 | 1.851 |
| bm-wasm pool k=1 | 290 | 300 | 308 | 314 |
| bm-wasm pool k=2 | 249 | 315 | 337 | 385 |
| bm-wasm pool k=4 | 255 | 301 | 574 | 523 |
| bm-wasm pool k=8 | 248 | 528 | 705 | 977 |
| takumi-pdf pool k=1 | 95 | 144 | 143 | 157 |
| takumi-pdf pool k=2 | 127 | 243 | 253 | 262 |
| takumi-pdf pool k=4 | 125 | 243 | 365 | 379 |
| takumi-pdf pool k=8 | 124 | 244 | 344 | 338 |

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
| speed lượt 1 | 23,2 % | 33,8 % | 1,65 |
| speed lượt 2 | 17,1 % | 33,8 % | 1,65 |
| speed lượt 3 | 16,2 % | 35,1 % | 1,74 |
| scale | — | 47,7 % | — |
| cold | — | 48,4 % | 2,59 |
| memory | — | 41,0 % | 1,70 |
| eventloop | — | 42,8 % | — |
| throughput | — | 63,3 % | 3,34 |

Median từng tài liệu có độ lệch giữa các lượt vượt 10 %: 206 (ví dụ golden/box-chrome bm-native:async, golden/gradients bm-native:sync, golden/gradients bm-native:async, golden/gradients bm-wasm:sync, golden/gradients bm-wasm:async).
<!-- /pdf-bench:noise -->

<details><summary>Từng tài liệu</summary>

<!-- pdf-bench:per-doc -->
| Tài liệu | bm-native:sync | bm-native:async | bm-wasm:sync | bm-wasm:async | takumi-pdf:async | bm-n sync / tk | byte bm / tk |
|:--|--:|--:|--:|--:|--:|--:|--:|
| `golden/box-chrome` | 0,68 / 1,45 | 0,68 / 1,37 | 1,15 / 1,60 | 1,07 / 1,36 | 2,16 / 2,73 | 0,32× | 5441 / 5453 |
| `golden/gradients` | 0,58 / 1,36 | 0,54 / 1,37 | 0,86 / 1,15 | 0,72 / 1,00 | 1,71 / 2,30 | 0,34× | 4506 / 4483 |
| `golden/repeating-gradients` | 0,44 / 0,56 | 0,50 / 0,94 | 0,60 / 1,01 | 0,51 / 0,86 | 1,03 / 1,48 | 0,42× | 8558 / 8454 |
| `golden/box-shadows` | 0,29 / 0,42 | 0,38 / 0,57 | 0,44 / 0,64 | 0,35 / 0,57 | 0,76 / 1,08 | 0,37× | 4120 / 4128 |
| `golden/blend-opacity` | 0,19 / 0,28 | 0,29 / 0,47 | 0,27 / 0,43 | 0,21 / 0,34 | 0,57 / 0,85 | 0,33× | 3156 / 3172 |
| `golden/overflow-clip` | 0,18 / 0,32 | 0,30 / 0,45 | 0,26 / 0,46 | 0,19 / 0,35 | 0,56 / 0,87 | 0,33× | 2492 / 2505 |
| `golden/transformed-overflow-clip` | 0,11 / 0,18 | 0,24 / 0,39 | 0,15 / 0,26 | 0,11 / 0,22 | 0,34 / 0,54 | 0,31× | 1828 / 1846 |
| `golden/clip-path-shapes` | 0,24 / 0,33 | 0,38 / 0,54 | 0,37 / 0,57 | 0,28 / 0,46 | 0,69 / 0,93 | 0,34× | 4348 / 4367 |
| `golden/mask-image` | 0,31 / 0,45 | 0,40 / 0,56 | 0,46 / 0,67 | 0,36 / 0,65 | 0,93 / 1,35 | 0,33× | 9341 / 9354 |
| `golden/color-filters` | 0,16 / 0,27 | 0,28 / 0,44 | 0,23 / 0,35 | 0,18 / 0,31 | 0,48 / 0,77 | 0,34× | 1924 / 1939 |
| `golden/outlines` | 0,17 / 0,27 | 0,29 / 0,42 | 0,24 / 0,37 | 0,19 / 0,30 | 0,49 / 0,76 | 0,35× | 2417 / 2421 |
| `golden/background-boxes` | 0,20 / 0,31 | 0,31 / 0,44 | 0,31 / 0,49 | 0,24 / 0,39 | 0,60 / 0,96 | 0,34× | 3938 / 3954 |
| `golden/background-placement` | 0,21 / 0,33 | 0,35 / 0,51 | 0,32 / 0,49 | 0,25 / 0,40 | 0,62 / 0,82 | 0,34× | 4681 / 4694 |
| `golden/url-layers` | 0,25 / 0,38 | 0,37 / 0,51 | 0,33 / 0,59 | 0,25 / 0,49 | 0,73 / 1,06 | 0,34× | 3489 / 3501 |
| `golden/edge-degenerate` | 0,52 / 0,76 | 0,57 / 1,05 | 0,77 / 1,26 | 0,65 / 1,08 | 1,51 / 2,37 | 0,34× | 5511 / 5520 |
| `golden/image-object-fit` | 0,17 / 0,25 | 0,26 / 0,45 | 0,22 / 0,37 | 0,16 / 0,30 | 0,80 / 1,20 | 0,21× | 2290 / 2302 |
| `golden/encoded-bitmaps` | 0,15 / 0,28 | 0,27 / 0,44 | 0,21 / 0,38 | 0,15 / 0,29 | 0,53 / 0,92 | 0,29× | 3213 / 3228 |
| `golden/png-streams` | 0,13 / 0,20 | 0,27 / 0,40 | 0,18 / 0,30 | 0,13 / 0,26 | 0,42 / 0,62 | 0,31× | 2561 / 2576 |
| `golden/border-mixed-sides` | 0,20 / 0,36 | 0,31 / 0,54 | 0,28 / 0,48 | 0,20 / 0,40 | 0,69 / 1,08 | 0,29× | 2436 / 2442 |
| `golden/inline-span-background` | 0,56 / 0,78 | 0,65 / 0,87 | 0,86 / 1,35 | 0,73 / 1,22 | 1,61 / 2,28 | 0,35× | 6529 / 6537 |
| `golden/inline-span-border` | 0,50 / 0,70 | 0,60 / 0,88 | 0,75 / 1,11 | 0,62 / 0,94 | 1,42 / 1,99 | 0,35× | 6236 / 6246 |
| `golden/inline-images` | 0,50 / 0,69 | 0,58 / 0,79 | 0,71 / 0,87 | 0,57 / 0,90 | 1,50 / 1,88 | 0,34× | 6312 / 6330 |
| `golden/inline-image-decorations` | 0,49 / 0,63 | 0,58 / 0,74 | 0,69 / 0,94 | 0,55 / 0,81 | 1,39 / 1,79 | 0,35× | 6129 / 6141 |
| `golden/page-background` | 0,42 / 0,58 | 0,52 / 0,99 | 0,60 / 0,90 | 0,47 / 0,75 | 1,36 / 2,04 | 0,31× | 5464 / 5488 |
| `golden/svg-background-image` | 0,48 / 0,63 | 0,56 / 0,74 | 0,66 / 0,98 | 0,50 / 0,84 | 1,27 / 1,71 | 0,38× | 5968 / 5980 |
| `golden/collapsed-table` | 1,00 / 1,51 | 1,08 / 1,41 | 1,65 / 2,23 | 1,61 / 2,18 | 3,67 / 4,66 | 0,27× | 9638 / 9618 |
| `golden/text-decorations` | 0,70 / 0,86 | 0,80 / 1,13 | 1,14 / 1,55 | 0,97 / 1,18 | 1,81 / 2,44 | 0,39× | 8906 / 8924 |
| `golden/text-decoration-styles` | 0,54 / 0,75 | 0,67 / 0,92 | 0,86 / 1,12 | 0,73 / 1,00 | 1,37 / 1,73 | 0,39× | 6068 / 6082 |
| `golden/svg-vector-image` | 0,14 / 0,21 | 0,29 / 0,44 | 0,22 / 0,37 | 0,15 / 0,27 | 0,52 / 0,76 | 0,27× | 2460 / 2473 |
| `golden/text-basic` | 0,35 / 0,47 | 0,46 / 0,62 | 0,50 / 0,73 | 0,38 / 0,60 | 1,01 / 1,40 | 0,35× | 5099 / 5113 |
| `golden/text-ligatures` | 0,33 / 0,44 | 0,45 / 0,60 | 0,48 / 0,64 | 0,38 / 0,54 | 0,99 / 1,32 | 0,34× | 4966 / 4983 |
| `golden/text-decoration-shadow` | 2,17 / 2,69 | 2,39 / 2,56 | 2,85 / 3,17 | 2,71 / 2,97 | 4,48 / 5,03 | 0,49× | 42120 / 41576 |
| `golden/text-shadow-stroke` | 6,65 / 7,42 | 6,81 / 7,27 | 8,76 / 9,27 | 8,94 / 9,70 | 9,77 / 10,5 | 0,68× | 117714 / 95472 |
| `golden/color-glyph-text-shadow` | 4,26 / 4,56 | 4,46 / 4,78 | 5,41 / 5,53 | 5,10 / 5,40 | 7,39 / 7,58 | 0,58× | 81054 / 80275 |
| `golden/bitmap-glyph-text-shadow` | 1,37 / 1,58 | 1,52 / 2,26 | 2,00 / 2,28 | 1,80 / 2,54 | 2,49 / 3,87 | 0,55× | 15158 / 15247 |
| `golden/text-stroke-paint-order` | 1,06 / 1,33 | 1,19 / 1,58 | 1,40 / 1,85 | 1,26 / 1,52 | 1,54 / 1,81 | 0,69× | 16178 / 8977 |
| `golden/cluster-closing-on-a-mark` | 0,23 / 0,34 | 0,37 / 0,51 | 0,33 / 0,45 | 0,25 / 0,38 | 0,70 / 0,94 | 0,33× | 4991 / 5003 |
| `golden/font-weights` | 3,08 / 3,29 | 3,25 / 3,64 | 4,98 / 5,16 | 4,86 / 5,03 | 7,97 / 9,40 | 0,39× | 57268 / 57162 |
| `golden/certificate` | 1,25 / 1,61 | 1,29 / 1,74 | 1,87 / 2,43 | 1,84 / 2,29 | 3,21 / 4,03 | 0,39× | 14358 / 14304 |
| `golden/paged-lines` | 1,32 / 1,44 | 1,41 / 1,75 | 2,27 / 2,80 | 2,20 / 2,60 | 6,49 / 7,85 | 0,20× | 8817 / 8688 |
| `golden/paged-page-ranges` | 1,01 / 1,20 | 1,15 / 1,29 | 1,79 / 2,08 | 1,61 / 2,03 | 7,03 / 7,34 | 0,14× | 7197 / 7192 |
| `golden/paged-table` | 2,30 / 2,62 | 2,52 / 2,91 | 4,27 / 4,68 | 4,15 / 4,41 | 8,38 / 9,03 | 0,27× | 14858 / 14664 |
| `golden/paged-breaks` | 0,50 / 0,77 | 0,62 / 0,81 | 0,72 / 1,00 | 0,59 / 0,85 | 1,85 / 2,39 | 0,27× | 5929 / 5948 |
| `golden/paged-widows-orphans` | 0,81 / 1,14 | 0,88 / 1,31 | 1,20 / 2,17 | 1,08 / 1,62 | 2,67 / 3,71 | 0,30× | 8308 / 8296 |
| `golden/paged-narrow` | 1,18 / 1,60 | 1,31 / 1,52 | 1,97 / 2,44 | 1,89 / 2,07 | 4,80 / 5,44 | 0,25× | 9459 / 9266 |
| `golden/paged-landscape` | 3,86 / 4,36 | 3,94 / 4,70 | 7,01 / 7,62 | 6,93 / 7,30 | 12,8 / 15,6 | 0,30× | 16412 / 14122 |
| `golden/legacy-page-break` | 0,75 / 1,07 | 0,84 / 1,30 | 1,15 / 2,05 | 1,10 / 1,70 | 2,56 / 3,70 | 0,29× | 7815 / 7826 |
| `golden/text-shadow-page-cut` | 0,74 / 1,06 | 0,83 / 1,23 | 1,06 / 1,66 | 0,87 / 1,07 | 1,77 / 2,87 | 0,42× | 10645 / 10562 |
| `golden/fixed-repeats-per-page` | 0,53 / 0,69 | 0,64 / 0,96 | 0,78 / 1,11 | 0,65 / 1,04 | 1,71 / 2,29 | 0,31× | 6382 / 6402 |
| `golden/invoice` | 6,88 / 7,48 | 6,88 / 8,78 | 12,2 / 15,6 | 12,0 / 12,9 | 42,7 / 46,4 | 0,16× | 29571 / 28723 |
| `golden/report-links-outline` | 1,11 / 1,34 | 1,24 / 1,66 | 1,76 / 2,12 | 1,67 / 2,15 | 4,45 / 4,90 | 0,25× | 14252 / 14223 |
| `golden/paged-footer` | 1,57 / 1,71 | 1,64 / 2,01 | 2,64 / 2,99 | 2,54 / 2,79 | 8,13 / 8,82 | 0,19× | 11459 / 11427 |
| `golden/paged-band-remeasure` | 0,75 / 1,14 | 0,89 / 1,58 | 1,16 / 1,84 | 1,01 / 1,58 | 3,49 / 5,60 | 0,21× | 6868 / 6879 |
| `golden/paged-header-footer` | 1,99 / 2,25 | 2,16 / 2,70 | 3,85 / 5,63 | 3,54 / 4,75 | 13,0 / 13,8 | 0,15× | 10707 / 10657 |
| `golden/auto-margin-bands` | 1,50 / 1,73 | 1,66 / 1,75 | 2,72 / 3,04 | 2,59 / 2,84 | 8,45 / 9,63 | 0,18× | 8765 / 8727 |
| `golden/page-rules` | 1,19 / 1,47 | 1,35 / 1,71 | 2,10 / 2,47 | 1,95 / 2,27 | 7,23 / 8,94 | 0,16× | 10578 / 10542 |
| `golden/paged-target-counters` | 0,71 / 1,07 | 0,83 / 1,16 | 1,12 / 1,40 | 0,97 / 1,33 | 3,96 / 5,42 | 0,18× | 7539 / 7555 |
| `golden/content-page-counters` | 0,44 / 0,62 | 0,57 / 0,87 | 0,64 / 1,00 | 0,50 / 0,82 | 1,68 / 2,52 | 0,26× | 5130 / 5145 |
| `golden/fixed-page-counters` | 0,44 / 0,58 | 0,57 / 0,80 | 0,63 / 0,85 | 0,49 / 0,75 | 1,49 / 2,02 | 0,29× | 4271 / 4292 |
| `golden/stream-total-pages-band` | 1,60 / 2,25 | 1,68 / 1,89 | 2,84 / 3,10 | 2,82 / 2,97 | 6,45 / 7,08 | 0,25× | 11138 / 11120 |
| `golden/stream-content-counters` | 1,41 / 1,68 | 1,45 / 1,70 | 2,27 / 3,41 | 2,25 / 3,06 | 8,70 / 13,6 | 0,16× | 11989 / 11979 |
| `golden/stream-page-ranges-middle` | 0,91 / 1,30 | 1,09 / 1,34 | 1,45 / 2,01 | 1,33 / 2,09 | 3,99 / 6,13 | 0,23× | 10529 / 10540 |
| `golden/at-page-first-left-right` | 5,38 / 6,19 | 5,51 / 6,12 | 11,2 / 13,1 | 11,2 / 13,8 | 20,9 / 23,0 | 0,26× | 17311 / 15653 |
| `golden/at-page-root-element` | 4,57 / 4,90 | 4,61 / 4,90 | 9,02 / 10,0 | 8,93 / 9,53 | 12,5 / 16,5 | 0,37× | 15697 / 14404 |
| `golden/named-pages` | 9,13 / 10,2 | 9,60 / 11,2 | 19,6 / 21,8 | 19,5 / 20,5 | 29,6 / 31,7 | 0,31× | 17572 / 17129 |
| `golden/stream-forward-link` | 1,01 / 1,22 | 1,18 / 1,32 | 1,63 / 1,80 | 1,52 / 1,76 | 5,32 / 6,65 | 0,19× | 12436 / 12432 |
| `golden/stream-tagged-outline` | 1,04 / 1,26 | 1,17 / 1,81 | 1,72 / 2,31 | 1,59 / 2,39 | 4,34 / 5,54 | 0,24× | 12433 / 12416 |
| `golden/invoice-pdfa-3b-attachment` | 6,75 / 8,75 | 6,97 / 7,77 | 11,9 / 12,6 | 12,0 / 12,8 | 39,8 / 45,5 | 0,17× | 34751 / 33899 |
| `golden/font-formats-pdfa-2b` | 1,50 / 1,67 | 1,64 / 1,94 | 2,21 / 2,69 | 2,10 / 2,67 | 3,77 / 4,42 | 0,40× | 35336 / 35291 |
| `golden/font-formats-pdfa-2u` | 1,50 / 1,69 | 1,64 / 1,88 | 2,20 / 3,34 | 2,08 / 2,46 | 3,75 / 5,05 | 0,40× | 35336 / 35291 |
| `golden/font-formats-pdfa-2a` | 1,48 / 1,66 | 1,65 / 1,97 | 2,24 / 2,56 | 2,10 / 2,37 | 3,73 / 4,76 | 0,40× | 35336 / 35291 |
| `golden/font-formats-pdfa-3b` | 1,53 / 1,93 | 1,64 / 2,37 | 2,26 / 2,86 | 2,09 / 2,27 | 3,81 / 4,52 | 0,40× | 35336 / 35291 |
| `golden/font-formats-pdfa-3u` | 1,50 / 1,87 | 1,68 / 2,17 | 2,23 / 2,62 | 2,14 / 2,48 | 3,84 / 4,30 | 0,39× | 35336 / 35291 |
| `golden/font-formats-pdfa-3a` | 1,60 / 2,21 | 1,68 / 2,10 | 2,24 / 3,31 | 2,22 / 3,12 | 3,95 / 5,21 | 0,40× | 35336 / 35291 |
| `golden/font-formats-pdfa-4` | 1,49 / 2,41 | 1,63 / 2,40 | 2,32 / 2,67 | 2,12 / 2,76 | 3,80 / 5,27 | 0,39× | 31963 / 31906 |
| `golden/invoice-pdfa-2b` | 6,69 / 7,11 | 7,02 / 7,52 | 11,8 / 12,9 | 11,8 / 12,3 | 40,6 / 42,6 | 0,16× | 32804 / 31953 |
| `golden/invoice-pdfa-4` | 6,89 / 8,40 | 7,47 / 8,91 | 12,1 / 15,3 | 11,9 / 14,4 | 41,1 / 43,1 | 0,17× | 30497 / 29644 |
| `golden/invoice-pdfa-4f-attachment` | 6,85 / 7,37 | 7,15 / 7,43 | 12,0 / 13,1 | 11,7 / 12,9 | 40,8 / 43,2 | 0,17× | 32656 / 31803 |
| `golden/report-tagged-ua1` | 1,19 / 1,47 | 1,31 / 1,78 | 1,87 / 2,18 | 1,77 / 2,29 | 4,58 / 5,14 | 0,26× | 18501 / 18461 |
| `golden/report-tagged-a2a` | 1,17 / 1,82 | 1,30 / 1,58 | 1,83 / 2,13 | 1,68 / 2,07 | 4,57 / 5,74 | 0,26× | 17197 / 17166 |
| `golden/list-tagged-ua1` | 0,88 / 1,18 | 1,02 / 1,25 | 1,33 / 1,88 | 1,25 / 1,62 | 2,84 / 3,71 | 0,31× | 10525 / 10522 |
| `golden/inline-block-tagged` | 0,62 / 0,86 | 0,73 / 1,22 | 0,90 / 1,28 | 0,74 / 1,04 | 1,86 / 2,17 | 0,33× | 8607 / 8630 |
| `golden/structure-types-a4` | 1,15 / 1,40 | 1,22 / 1,68 | 1,71 / 2,19 | 1,65 / 2,28 | 4,91 / 6,35 | 0,24× | 13767 / 13724 |
| `golden/table-tagged-ua2` | 0,95 / 1,32 | 1,06 / 1,31 | 1,45 / 2,07 | 1,37 / 1,93 | 2,78 / 4,09 | 0,34× | 12349 / 12319 |
| `golden/report-tagged-ua2` | 0,92 / 1,09 | 1,04 / 1,49 | 1,35 / 1,56 | 1,24 / 1,65 | 2,67 / 3,12 | 0,34× | 12570 / 12555 |
| `golden/borders-tagged-ua1` | 0,61 / 0,78 | 0,70 / 0,96 | 0,87 / 1,05 | 0,73 / 0,99 | 1,76 / 2,19 | 0,35× | 12943 / 12955 |
| `golden/decorative-image-ua1` | 0,40 / 0,51 | 0,51 / 0,68 | 0,55 / 0,72 | 0,43 / 0,60 | 1,25 / 1,52 | 0,32× | 5737 / 5762 |
| `golden/inline-box-lang-ua1` | 0,60 / 0,82 | 0,71 / 0,91 | 0,85 / 1,01 | 0,70 / 0,93 | 1,74 / 2,08 | 0,35× | 12819 / 12835 |
| `golden/heading-levels-ua1` | 0,86 / 1,03 | 1,00 / 1,62 | 1,32 / 1,68 | 1,17 / 1,54 | 2,50 / 3,13 | 0,35× | 16979 / 16995 |
| `golden/media-print` | 0,32 / 0,44 | 0,45 / 0,57 | 0,44 / 0,60 | 0,32 / 0,49 | 0,91 / 1,23 | 0,34× | 4601 / 4617 |
| `golden/inline-span-background-image` | 0,79 / 1,00 | 0,90 / 1,09 | 1,14 / 1,38 | 1,02 / 1,34 | 1,85 / 2,28 | 0,43× | 12584 / 12542 |
| `golden/inline-span-background-clip-text-nested` | 1,17 / 1,42 | 1,30 / 1,51 | 1,61 / 2,43 | 1,54 / 1,97 | 2,31 / 3,29 | 0,51× | 19352 / 19194 |
| `golden/inline-span-background-clip-text-decoration` | 1,21 / 1,39 | 1,33 / 1,90 | 1,72 / 1,92 | 1,56 / 1,94 | 2,48 / 2,91 | 0,49× | 19111 / 18973 |
| `golden/background-clip-text-descendants` | 2,35 / 2,83 | 2,58 / 2,94 | 3,30 / 3,69 | 3,21 / 3,63 | 4,05 / 4,52 | 0,58× | 38990 / 38302 |
| `golden/background-clip-text-reach` | 1,13 / 1,41 | 1,28 / 1,67 | 1,53 / 2,11 | 1,44 / 2,14 | 2,24 / 2,66 | 0,50× | 17665 / 17505 |
| `golden/inline-span-box-decoration-break-clone` | 0,46 / 0,60 | 0,60 / 0,84 | 0,68 / 0,86 | 0,55 / 0,78 | 1,21 / 1,51 | 0,38× | 6218 / 6233 |
| `golden/sided-avoid-page-breaks` | 0,70 / 0,90 | 0,79 / 0,94 | 1,07 / 1,39 | 0,92 / 1,23 | 2,25 / 2,86 | 0,31× | 7854 / 7864 |
| `golden/avoid-break-out-of-flow-overflow` | 0,57 / 0,76 | 0,67 / 0,93 | 0,85 / 1,00 | 0,70 / 1,06 | 1,79 / 2,18 | 0,32× | 6622 / 6647 |
| `golden/img-without-source-past-page` | 0,43 / 0,58 | 0,53 / 0,74 | 0,61 / 0,90 | 0,48 / 0,78 | 1,29 / 1,78 | 0,33× | 5627 / 5639 |
| `golden/flex-item-margin-past-page` | 0,46 / 0,65 | 0,55 / 0,81 | 0,63 / 0,80 | 0,50 / 0,74 | 1,39 / 1,68 | 0,33× | 5588 / 5521 |
| `golden/flex-item-child-break-after` | 0,57 / 0,77 | 0,66 / 0,90 | 0,82 / 1,14 | 0,67 / 1,11 | 1,60 / 1,91 | 0,35× | 6634 / 6185 |
| `golden/flex-item-table-row-break-after` | 0,56 / 0,76 | 0,66 / 0,89 | 0,80 / 1,01 | 0,65 / 0,91 | 1,58 / 1,91 | 0,35× | 6290 / 5859 |
| `golden/floated-flex-item-break-after` | 0,47 / 0,67 | 0,58 / 0,74 | 0,65 / 0,86 | 0,52 / 0,73 | 1,31 / 1,62 | 0,35× | 5884 / 5431 |
| `golden/break-after-with-running-absolute` | 0,56 / 0,82 | 0,64 / 0,87 | 0,81 / 1,14 | 0,67 / 0,96 | 1,81 / 2,24 | 0,31× | 6240 / 6728 |
| `golden/paged-offpage-clips` | 0,76 / 1,01 | 0,88 / 1,07 | 1,19 / 1,45 | 1,12 / 1,74 | 2,36 / 3,37 | 0,32× | 11121 / 10685 |
| `golden/paged-nested-flex-forced-break` | 0,45 / 0,67 | 0,55 / 0,80 | 0,62 / 0,88 | 0,48 / 0,79 | 1,50 / 2,10 | 0,30× | 5308 / 5328 |
| `golden/svg-singular-gradient-transform` | 0,21 / 0,44 | 0,32 / 0,52 | 0,34 / 0,62 | 0,23 / 0,48 | 0,72 / 1,33 | 0,30× | 3154 / 3169 |
| `golden/svg-filters-masks-and-patterns` | 0,17 / 0,26 | 0,29 / 0,50 | 0,27 / 0,38 | 0,20 / 0,31 | 0,60 / 0,80 | 0,29× | 3137 / 3153 |
| `golden/svg-embedded-png` | 0,25 / 0,40 | 0,35 / 0,52 | 0,38 / 0,61 | 0,28 / 0,48 | 0,80 / 1,04 | 0,31× | 9031 / 9048 |
| `golden/svg-with-color-filter` | 0,62 / 0,80 | 0,72 / 0,89 | 0,95 / 1,20 | 0,87 / 1,03 | 1,99 / 2,73 | 0,31× | 8290 / 8312 |
| `golden/inline-outlines` | 0,51 / 0,60 | 0,60 / 0,78 | 0,72 / 0,89 | 0,59 / 0,79 | 1,32 / 1,60 | 0,39× | 6733 / 6747 |
| `golden/inline-zero-sized-parents` | 0,51 / 0,78 | 0,62 / 0,84 | 0,74 / 0,99 | 0,63 / 0,89 | 1,40 / 1,81 | 0,37× | 6165 / 6183 |
| `golden/background-clip-border-area-gaps` | 0,24 / 0,32 | 0,39 / 0,52 | 0,36 / 0,49 | 0,27 / 0,44 | 0,72 / 0,94 | 0,34× | 4946 / 4960 |
| `golden/paged-clone-decorations` | 1,09 / 1,29 | 1,22 / 1,37 | 1,82 / 2,16 | 1,69 / 2,26 | 3,96 / 4,91 | 0,27× | 9632 / 9553 |
| `golden/paged-transforms` | 0,26 / 0,33 | 0,40 / 0,59 | 0,36 / 0,55 | 0,26 / 0,48 | 0,87 / 1,11 | 0,30× | 2802 / 2814 |
| `golden/paged-overflow-clip-stitched` | 0,14 / 0,25 | 0,24 / 0,40 | 0,18 / 0,32 | 0,12 / 0,25 | 0,54 / 0,87 | 0,25× | 2162 / 2181 |
| `golden/paged-rounded-clip-stitched` | 0,21 / 0,33 | 0,30 / 0,53 | 0,27 / 0,66 | 0,18 / 0,34 | 0,76 / 1,11 | 0,27× | 3064 / 3080 |
| `golden/paged-transform-past-the-last-page` | 0,14 / 0,22 | 0,24 / 0,39 | 0,18 / 0,28 | 0,12 / 0,23 | 0,50 / 0,68 | 0,28× | 2457 / 2472 |
| `golden/paged-monolithic-overflow` | 0,62 / 0,76 | 0,70 / 0,92 | 0,92 / 1,30 | 0,76 / 1,10 | 1,87 / 2,32 | 0,33× | 7149 / 7152 |
| `golden/paged-clipped-overflow` | 0,15 / 0,23 | 0,27 / 0,42 | 0,21 / 0,32 | 0,15 / 0,26 | 0,53 / 0,78 | 0,28× | 2174 / 2171 |
| `golden/paged-images` | 0,49 / 0,71 | 0,60 / 0,93 | 0,70 / 1,09 | 0,57 / 0,85 | 1,67 / 2,14 | 0,30× | 6895 / 6919 |
| `golden/list-marker-pagination` | 0,50 / 0,67 | 0,62 / 0,77 | 0,74 / 1,07 | 0,60 / 0,88 | 1,66 / 2,59 | 0,30× | 5713 / 5723 |
| `golden/outline-over-content` | 0,27 / 0,40 | 0,40 / 0,53 | 0,38 / 0,51 | 0,26 / 0,45 | 0,85 / 1,17 | 0,32× | 4092 / 4109 |
| `golden/outline-under-transform` | 0,28 / 0,36 | 0,41 / 0,54 | 0,37 / 0,51 | 0,26 / 0,43 | 0,86 / 1,10 | 0,32× | 4105 / 4124 |
| `golden/inline-containers` | 0,56 / 0,68 | 0,68 / 0,90 | 0,85 / 0,98 | 0,69 / 0,95 | 1,77 / 2,18 | 0,32× | 5629 / 5634 |
| `golden/font-variation-settings` | 0,73 / 0,85 | 0,87 / 1,14 | 1,10 / 1,33 | 0,97 / 1,30 | 1,90 / 2,21 | 0,38× | 11311 / 11329 |
| `golden/font-optical-sizing` | 0,51 / 0,60 | 0,59 / 0,80 | 0,70 / 1,02 | 0,55 / 0,80 | 1,42 / 1,73 | 0,36× | 7728 / 7738 |
| `golden/page-sized-boxes` | 0,16 / 0,28 | 0,29 / 0,50 | 0,22 / 0,41 | 0,15 / 0,27 | 0,60 / 0,89 | 0,27× | 2646 / 2660 |
| `golden/page-area-viewport-units` | 0,15 / 0,25 | 0,29 / 0,41 | 0,22 / 0,31 | 0,15 / 0,28 | 0,59 / 0,78 | 0,26× | 2646 / 2660 |
| `golden/stream-transform-three-pages-back` | 0,88 / 1,07 | 1,00 / 1,21 | 1,40 / 1,68 | 1,23 / 1,45 | 3,35 / 3,91 | 0,26× | 10540 / 10539 |
| `golden/stream-relative-body-bottom` | 0,97 / 1,19 | 1,08 / 1,34 | 1,60 / 2,07 | 1,45 / 2,22 | 4,02 / 5,10 | 0,24× | 8333 / 8322 |
| `golden/paged-rotated-text` | 0,54 / 0,75 | 0,65 / 0,81 | 0,74 / 1,02 | 0,60 / 0,81 | 1,43 / 1,86 | 0,38× | 7652 / 7644 |
| `golden/paged-clipped-line` | 0,48 / 0,64 | 0,56 / 0,71 | 0,67 / 0,99 | 0,54 / 0,77 | 1,30 / 1,63 | 0,36× | 6308 / 6322 |
| `golden/paged-clipped-line-at-page-edge` | 0,40 / 0,53 | 0,52 / 0,68 | 0,56 / 0,72 | 0,43 / 0,59 | 1,20 / 1,39 | 0,33× | 5239 / 5264 |
| `golden/paged-translated-text-past-the-end` | 0,52 / 0,62 | 0,67 / 0,87 | 0,70 / 0,83 | 0,57 / 0,71 | 1,29 / 1,52 | 0,40× | 8235 / 8182 |
| `golden/paged-translated-text-across-pages` | 0,57 / 0,82 | 0,66 / 0,89 | 0,74 / 1,09 | 0,60 / 0,83 | 1,42 / 2,01 | 0,40× | 8235 / 8182 |
| `docs/invoice` | 1,79 / 2,01 | 1,93 / 2,14 | 2,87 / 3,23 | 2,79 / 3,12 | 6,51 / 7,45 | 0,27× | 26208 / 26094 |
| `docs/report-repeating-header` | 7,33 / 8,14 | 7,47 / 8,54 | 13,1 / 15,2 | 13,0 / 13,5 | 28,1 / 30,1 | 0,26× | 34497 / 34052 |
| `docs/ticket` | 0,77 / 1,02 | 0,92 / 1,14 | 1,12 / 1,48 | 1,05 / 1,35 | 1,82 / 2,17 | 0,42× | 19058 / 19063 |
| `docs/multipage-text` | 3,99 / 4,53 | 4,25 / 5,17 | 9,44 / 10,3 | 9,54 / 9,86 | 14,6 / 15,6 | 0,27× | 24302 / 23586 |
| `docs/headers-footers` | 3,35 / 3,84 | 3,46 / 3,63 | 7,78 / 7,98 | 7,52 / 9,30 | 20,8 / 24,2 | 0,16× | 16361 / 15898 |
| `docs/links-outline` | 3,01 / 3,50 | 3,17 / 3,72 | 6,35 / 6,74 | 6,41 / 7,78 | 17,1 / 19,2 | 0,18× | 29168 / 28260 |
| `docs/images` | 1,21 / 1,55 | 1,58 / 2,16 | 1,76 / 2,15 | 1,70 / 2,28 | 2,37 / 3,19 | 0,51× | 407889 / 407901 |
| `docs/images-viewport` | 1,24 / 1,92 | 1,62 / 1,86 | 1,83 / 2,40 | 1,77 / 2,16 | 2,31 / 3,38 | 0,54× | 407778 / 407788 |
| `docs/effects` | 1,11 / 1,65 | 1,25 / 1,66 | 1,58 / 2,14 | 1,45 / 1,99 | 2,27 / 3,37 | 0,49× | 19733 / 19643 |
| `docs/intl-rtl-cjk-emoji` | 1,91 / 2,05 | 2,11 / 2,35 | 2,90 / 3,22 | 2,80 / 3,16 | 4,77 / 5,31 | 0,40× | 39593 / 39475 |
| `docs/tagged-ua1` | 1,12 / 1,30 | 1,26 / 1,49 | 1,73 / 2,01 | 1,56 / 1,78 | 3,20 / 3,73 | 0,35× | 27462 / 27439 |
| `docs/tagged-ua2-pdfa4` | 1,15 / 1,72 | 1,31 / 1,80 | 1,87 / 2,28 | 1,69 / 1,94 | 3,25 / 4,24 | 0,35× | 28791 / 28758 |
| `docs/attachments` | 1,84 / 2,00 | 1,93 / 2,25 | 2,87 / 3,18 | 2,72 / 3,13 | 6,31 / 6,78 | 0,29× | 26817 / 26698 |
| `docs/invoice-pdfa-2b` | 2,21 / 2,59 | 2,06 / 2,60 | 3,14 / 4,37 | 3,02 / 4,04 | 6,91 / 10,1 | 0,32× | 29859 / 29736 |
| `docs/invoice-pdfa-2u` | 1,88 / 2,02 | 1,97 / 2,21 | 3,04 / 4,03 | 2,94 / 3,70 | 7,03 / 8,79 | 0,27× | 29859 / 29736 |
| `docs/invoice-pdfa-2a` | 1,85 / 2,10 | 1,97 / 2,40 | 3,00 / 3,57 | 2,94 / 4,00 | 6,42 / 7,44 | 0,29× | 29867 / 29741 |
| `docs/invoice-pdfa-3b` | 1,86 / 2,00 | 1,99 / 2,16 | 2,98 / 3,52 | 2,90 / 4,07 | 6,52 / 7,43 | 0,29× | 30977 / 30848 |
| `docs/invoice-pdfa-3u` | 1,86 / 2,25 | 1,99 / 2,69 | 2,96 / 3,60 | 2,83 / 3,06 | 6,57 / 8,13 | 0,28× | 30977 / 30848 |
| `docs/invoice-pdfa-3a` | 1,83 / 1,94 | 1,97 / 2,10 | 2,86 / 3,04 | 2,85 / 3,10 | 6,41 / 8,11 | 0,29× | 30985 / 30857 |
| `docs/invoice-pdfa-4` | 2,00 / 2,68 | 2,13 / 2,71 | 3,37 / 4,08 | 3,08 / 3,81 | 6,70 / 9,69 | 0,30× | 27489 / 27351 |
| `docs/invoice-pdfa-4f` | 1,90 / 2,27 | 2,02 / 2,42 | 3,08 / 3,19 | 2,87 / 3,01 | 6,78 / 7,33 | 0,28× | 28893 / 28754 |
| `stress/1p` | 1,89 / 2,77 | 1,99 / 2,10 | 3,30 / 3,57 | 3,16 / 3,30 | 8,26 / 10,1 | 0,23× | 27560 / 27389 |
| `stress/10p` | 12,0 / 14,0 | 12,5 / 14,0 | 24,0 / 26,0 | 24,2 / 25,9 | 82,0 / 88,3 | 0,15× | 61623 / 59608 |

median / p95 ms.
<!-- /pdf-bench:per-doc -->

</details>

## Giai đoạn 4 — native Node.js

Bốn engine trên cùng một máy, cùng Node, cùng 250 fixture, cùng font, cùng ảnh, cùng kích thước đầu ra:
**bm-native** (addon Node-API của bm-render, `native/dist/win32-x64-msvc`), **bm-wasm** (bản wasm profile `full`),
**takumi-native** (`@takumi-rs/core`) và **takumi-wasm** (`@takumi-rs/wasm`). Mọi bảng trong phần này được sinh từ
`docs/results-native.json` bởi `node bench/run-native.mjs` (giữa các comment `native-bench`); không con số nào được gõ tay.
Trang tóm tắt bằng tiếng Anh và tiếng Việt: [en/native-vs-wasm.md](en/native-vs-wasm.md), [vi/native-vs-wasm.md](vi/native-vs-wasm.md).

### Điều kiện đo

<!-- native-bench:env -->
| Mục | Giá trị |
|:--|:--|
| Máy | 11th Gen Intel(R) Core(TM) i5-1145G7 @ 2.60GHz, 8 CPU logic, 31.7 GiB, win32 10.0.19045 x64 |
| Node.js | v24.21.0 (V8 13.6.233.17-node.53, N-API 10, libuv 1.52.1) |
| bm-render | 0.1.1, git `67c0f368a2` (main, 15 file đang sửa) |
| bm-native | `native/dist/win32-x64-msvc/bm-render.win32-x64-msvc.node`, 3 684 KiB, Zig 0.17.0, ReleaseFast, sha256 `664ed6bd9520` |
| bm-wasm | `js/bm_render.wasm` (profile full), 1 275 KiB, sha256 `313be1922a30` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Lần chạy | 2026-11-16 21:11 UTC, chế độ full, 250 fixtures, 15.4 min; CPU bận trước khi chạy: 15.3 % |
<!-- /native-bench:env -->

### Tóm tắt

<!-- native-bench:highlights -->
- **bm-native so với bm-wasm (sync):** raw bằng 0.64× thời gian của wasm [0.64× / 0.64× / 0.64×] (nhanh hơn ở 250/250 fixture), PNG 0.72× [0.72× / 0.72× / 0.72×] (nhanh hơn ở 250/250).
- **bm-native so với takumi-native, cùng async:** raw 0.54× [0.53× / 0.53× / 0.54×] (bm nhanh hơn ở 248/250, từng fixture 0.09×–1.00×), PNG 0.53× [0.53× / 0.52× / 0.53×] (bm nhanh hơn ở 236/250, từng fixture 0.24×–2.16×). Với API sync của bm: raw 0.40×, PNG 0.45×. Dưới 1× = bm-native tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ đó ở từng lượt.
- **Thời gian CPU mỗi ảnh (cùng async):** PNG 1.56 ms bm-native so với 3.65 ms takumi-native (1.00 so với 1.51 lõi bận trong một lần render); raw 0.96 so với 1.64 ms. takumi-native chạy một phần của một lần render (các đoạn deflate PNG, blur, WebP, khung animation) trên thread pool rayon riêng; bm render một ảnh trên một thread (bm-native sync: 1.03 lõi với PNG).
- **Hai bản build của chính takumi:** takumi-native tốn 0.95× thời gian của takumi-wasm với raw và 0.70× với PNG.
- **Trùng byte:** bm-native và bm-wasm cho cùng byte ở 2374/2376 phép so trên 250 fixture (800 MB; 2 khác biệt).
- **Nhiễu:** geomean tuyệt đối raw / PNG lệch tới 2.80 % giữa các lượt (tải của tiến trình khác thay đổi trong lúc chạy), còn tỉ lệ giữa các engine, đo xen kẽ trong từng lượt, lệch nhiều nhất 2.10 %. Hãy đọc tỉ lệ; coi số ms tuyệt đối là ±1.40 %.
<!-- /native-bench:highlights -->

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
- **Cold start:** spawn `node` → import engine như người dùng (`bm-render` = `js/node.mjs`, wasm qua
  `BM_RENDER_BACKEND=wasm`; `@takumi-rs/core`; `@takumi-rs/wasm` + `initSync`) → đăng ký Inter Regular → PNG og card
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
| raw (250) | 0.56 ±1.40 % | 0.74 ±1.20 % | 0.87 ±1.30 % | 1.38 ±0.45 % | 1.45 ±1.20 % |
| png (250) | 1.04 ±0.75 % | 1.21 ±0.05 % | 1.45 ±0.80 % | 2.30 ±0.55 % | 3.29 ±1.00 % |
| jpeg (3) | 11.4 ±1.00 % | 11.8 ±0.55 % | 18.3 ±0.65 % | 18.6 ±1.80 % | 24.4 ±1.05 % |
| webp (3) | 9.18 ±1.45 % | 9.54 ±2.15 % | 12.6 ±0.60 % | 75.4 ±1.20 % | 16.1 ±1.45 % |
| raw, bỏ known-gaps | 0.57 | 0.76 | 0.89 | 1.41 | 1.48 |
| png, bỏ known-gaps | 1.06 | 1.23 | 1.48 | 2.33 | 3.33 |
| raw, từng lượt | 0.57 / 0.56 / 0.57 | 0.74 / 0.74 / 0.76 | 0.90 / 0.87 / 0.88 | 1.40 / 1.38 / 1.39 | 1.50 / 1.46 / 1.47 |
| png, từng lượt | 1.07 / 1.05 / 1.05 | 1.22 / 1.22 / 1.22 | 1.48 / 1.46 / 1.46 | 2.31 / 2.32 / 2.30 | 3.37 / 3.33 / 3.30 |

Trung bình nhân của thời gian render median từng fixture, ms. jpeg (quality 85) và webp (lossless; takumi-wasm dùng bộ mã hoá WebP khác takumi-native, xem bảng định dạng) chỉ đo trên ba fixture.
<!-- /native-bench:speed -->

<!-- native-bench:cpu -->
| Biến thể | raw: thực / CPU ms / lõi | PNG: thực / CPU ms / lõi |
|:--|--:|--:|
| bm-native sync | 0.56 / 0.65 / 1.14 | 1.43 / 1.48 / 1.03 |
| bm-native async | 0.73 / 0.96 / 1.31 | 1.55 / 1.56 / 1.00 |
| bm-wasm sync | 0.88 / 1.08 / 1.22 | 2.00 / 2.03 / 1.02 |
| takumi-native async | 1.35 / 1.64 / 1.21 | 2.42 / 3.65 / 1.51 |
| takumi-wasm | 1.46 / 1.75 / 1.20 | 4.24 / 4.27 / 1.01 |

Trung bình trên mọi lần render được đo (không phải geomean): thời gian thực mỗi lần render, thời gian CPU của tiến trình (mọi thread) trong lúc đó, và tỉ số. Tỉ số trên 1 nghĩa là một lần render dùng hơn một lõi.
<!-- /native-bench:cpu -->

Theo nhóm fixture:

<!-- native-bench:categories -->
| Nhóm | n | raw bm-n sync | raw bm-n async | raw bm-w | raw tk-n | raw tk-w | raw bm-n/tk-n | png bm-n sync | png bm-n async | png bm-w | png tk-n | png tk-w | png bm-n/tk-n |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| aa-exact | 2 | 0.34 | 0.52 | 0.52 | 0.89 | 0.90 | 0.58× | 0.69 | 0.85 | 0.94 | 1.54 | 1.89 | 0.55× |
| absolute | 3 | 0.93 | 1.13 | 1.39 | 1.44 | 1.65 | 0.78× | 1.45 | 1.59 | 2.05 | 3.03 | 5.77 | 0.52× |
| animation | 44 | 0.18 | 0.31 | 0.28 | 0.55 | 0.51 | 0.56× | 0.27 | 0.39 | 0.36 | 0.85 | 0.97 | 0.46× |
| backdrop-filter | 1 | 1.33 | 1.45 | 2.55 | 2.53 | 4.56 | 0.57× | 2.18 | 2.31 | 3.67 | 3.62 | 7.30 | 0.64× |
| bg-blend | 1 | 0.81 | 0.96 | 1.16 | 4.92 | 4.51 | 0.19× | 3.08 | 3.29 | 4.22 | 6.38 | 9.96 | 0.52× |
| bg-clip-text | 1 | 0.42 | 0.52 | 0.61 | 2.75 | 3.05 | 0.19× | 1.63 | 1.76 | 2.19 | 3.75 | 5.48 | 0.47× |
| block-in-inline | 4 | 0.36 | 0.49 | 0.57 | 1.23 | 1.16 | 0.40× | 0.66 | 0.79 | 0.92 | 1.86 | 1.97 | 0.43× |
| blog-card | 2 | 4.18 | 4.50 | 6.91 | 6.40 | 10.9 | 0.70× | 10.9 | 11.2 | 15.9 | 10.8 | 32.0 | 1.04× |
| border-radius | 4 | 1.01 | 1.22 | 1.45 | 1.43 | 1.33 | 0.85× | 1.37 | 1.44 | 1.83 | 2.72 | 4.41 | 0.53× |
| borders | 3 | 0.98 | 1.19 | 1.47 | 1.46 | 1.72 | 0.82× | 1.27 | 1.32 | 1.75 | 2.93 | 4.28 | 0.45× |
| box-shadow | 4 | 1.99 | 2.29 | 3.34 | 4.34 | 6.19 | 0.53× | 4.62 | 4.87 | 7.11 | 6.36 | 15.6 | 0.77× |
| clip-path | 1 | 0.48 | 0.67 | 0.80 | 0.99 | 1.16 | 0.68× | 1.49 | 1.57 | 2.07 | 2.03 | 5.86 | 0.77× |
| colors | 5 | 0.91 | 1.11 | 1.40 | 1.81 | 2.05 | 0.62× | 1.04 | 1.14 | 1.47 | 2.99 | 4.17 | 0.38× |
| css-stylesheet | 8 | 0.69 | 0.87 | 1.05 | 1.42 | 1.41 | 0.61× | 0.97 | 1.06 | 1.33 | 2.50 | 3.34 | 0.42× |
| dashed-border | 1 | 0.83 | 0.99 | 1.42 | 1.62 | 2.64 | 0.61× | 1.11 | 1.28 | 1.71 | 2.20 | 3.37 | 0.58× |
| dotted-border | 1 | 0.93 | 1.09 | 1.68 | 1.97 | 3.06 | 0.55× | 1.22 | 1.37 | 1.89 | 2.47 | 3.92 | 0.56× |
| double-3d-border | 1 | 0.36 | 0.53 | 0.62 | 0.79 | 0.83 | 0.67× | 0.53 | 0.68 | 0.79 | 1.21 | 1.50 | 0.56× |
| drop-shadow | 1 | 0.93 | 1.01 | 1.39 | 1.53 | 1.94 | 0.66× | 2.29 | 2.43 | 3.34 | 2.63 | 7.13 | 0.92× |
| emoji | 5 | 0.15 | 0.25 | 0.24 | 0.73 | 0.75 | 0.34× | 0.57 | 0.68 | 0.77 | 1.06 | 1.16 | 0.64× |
| filter | 1 | 0.69 | 0.83 | 1.30 | 1.56 | 2.00 | 0.53× | 1.83 | 1.94 | 2.88 | 2.38 | 4.93 | 0.81× |
| flex | 5 | 1.08 | 1.31 | 1.69 | 1.65 | 1.75 | 0.80× | 1.41 | 1.50 | 1.96 | 3.25 | 4.88 | 0.46× |
| float | 4 | 0.36 | 0.49 | 0.57 | 0.90 | 0.94 | 0.54× | 0.75 | 0.90 | 1.08 | 1.68 | 2.66 | 0.53× |
| float-paint-order | 3 | 0.36 | 0.51 | 0.58 | 1.15 | 1.10 | 0.44× | 0.70 | 0.81 | 0.98 | 1.73 | 1.81 | 0.47× |
| float-text | 7 | 0.50 | 0.65 | 0.78 | 1.21 | 1.30 | 0.54× | 1.14 | 1.27 | 1.56 | 2.22 | 2.96 | 0.57× |
| font-variant | 3 | 0.46 | 0.59 | 0.67 | 1.35 | 1.41 | 0.43× | 1.21 | 1.34 | 1.59 | 2.50 | 3.33 | 0.54× |
| fonts | 2 | 1.63 | 1.79 | 2.22 | 2.89 | 3.41 | 0.62× | 3.54 | 3.50 | 4.56 | 5.47 | 9.60 | 0.64× |
| grid | 4 | 1.17 | 1.38 | 1.80 | 2.11 | 2.15 | 0.66× | 1.74 | 1.82 | 2.44 | 3.81 | 6.09 | 0.48× |
| grid-areas | 3 | 0.39 | 0.59 | 0.70 | 1.05 | 1.09 | 0.56× | 0.71 | 0.84 | 1.05 | 1.76 | 2.27 | 0.48× |
| html | 4 | 0.86 | 1.03 | 1.31 | 1.80 | 1.96 | 0.57× | 1.75 | 1.81 | 2.31 | 3.34 | 5.05 | 0.54× |
| images | 7 | 1.08 | 1.37 | 1.73 | 3.77 | 4.18 | 0.36× | 8.26 | 8.57 | 11.7 | 7.56 | 21.5 | 1.13× |
| inline-bidi | 3 | 0.51 | 0.63 | 0.85 | 1.62 | 1.50 | 0.39× | 0.93 | 1.06 | 1.32 | 2.37 | 2.57 | 0.45× |
| inline-block | 4 | 0.32 | 0.48 | 0.53 | 0.93 | 0.87 | 0.52× | 0.73 | 0.86 | 1.00 | 1.60 | 1.97 | 0.54× |
| inline-box | 1 | 1.31 | 1.48 | 2.13 | 3.01 | 3.18 | 0.49× | 2.56 | 2.65 | 3.79 | 4.22 | 5.89 | 0.63× |
| inline-box-model | 4 | 0.69 | 0.87 | 1.09 | 1.75 | 1.81 | 0.50× | 1.52 | 1.69 | 2.12 | 2.85 | 3.84 | 0.59× |
| inline-flow | 5 | 0.47 | 0.64 | 0.75 | 1.33 | 1.31 | 0.49× | 1.12 | 1.27 | 1.56 | 2.21 | 3.00 | 0.57× |
| inline-relative | 1 | 0.46 | 0.58 | 0.74 | 1.62 | 1.44 | 0.36× | 0.87 | 1.05 | 1.26 | 2.22 | 2.18 | 0.47× |
| known-gaps | 9 | 0.34 | 0.48 | 0.52 | 0.87 | 0.93 | 0.55× | 0.63 | 0.77 | 0.86 | 1.51 | 2.30 | 0.51× |
| linear-gradient | 4 | 1.55 | 1.80 | 2.60 | 3.99 | 4.54 | 0.45× | 4.25 | 4.49 | 6.25 | 6.42 | 16.8 | 0.70× |
| mask | 1 | 0.79 | 1.00 | 1.27 | 1.71 | 1.89 | 0.58× | 1.68 | 1.82 | 2.39 | 2.74 | 6.52 | 0.66× |
| mix-blend | 1 | 0.71 | 0.89 | 1.28 | 1.48 | 2.17 | 0.60× | 2.77 | 3.00 | 4.04 | 2.91 | 7.49 | 1.03× |
| mixed-border | 1 | 0.52 | 0.68 | 0.82 | 0.98 | 1.30 | 0.70× | 0.77 | 0.91 | 1.08 | 1.58 | 2.16 | 0.57× |
| og-card | 2 | 1.59 | 1.79 | 2.54 | 3.98 | 4.41 | 0.45× | 6.51 | 6.76 | 9.05 | 6.51 | 13.6 | 1.04× |
| opacity | 4 | 1.44 | 1.65 | 2.59 | 3.28 | 5.75 | 0.50× | 2.18 | 2.36 | 3.41 | 4.76 | 9.22 | 0.50× |
| outline | 1 | 0.54 | 0.72 | 0.91 | 1.22 | 1.76 | 0.59× | 0.83 | 0.99 | 1.21 | 1.89 | 2.74 | 0.52× |
| overflow | 3 | 0.93 | 1.14 | 1.40 | 1.98 | 2.13 | 0.57× | 1.53 | 1.70 | 2.14 | 3.50 | 5.82 | 0.49× |
| pseudo-elements | 4 | 0.57 | 0.73 | 0.84 | 1.22 | 1.30 | 0.60× | 0.81 | 0.90 | 1.09 | 2.02 | 2.76 | 0.45× |
| radial-gradient | 3 | 1.32 | 1.58 | 2.04 | 7.40 | 5.14 | 0.21× | 8.87 | 9.11 | 11.6 | 10.8 | 24.3 | 0.84× |
| rtl | 5 | 0.35 | 0.53 | 0.59 | 1.06 | 0.91 | 0.50× | 0.52 | 0.64 | 0.77 | 1.46 | 1.55 | 0.44× |
| sizing | 5 | 0.93 | 1.16 | 1.31 | 1.33 | 1.36 | 0.87× | 1.09 | 1.14 | 1.48 | 3.06 | 4.77 | 0.37× |
| stress | 3 | 8.39 | 8.78 | 13.2 | 15.3 | 16.9 | 0.58× | 16.8 | 17.3 | 24.1 | 20.6 | 37.0 | 0.84× |
| svg-image | 1 | 0.64 | 0.83 | 1.34 | 0.86 | 1.09 | 0.96× | 1.14 | 1.28 | 1.83 | 1.75 | 2.46 | 0.73× |
| table | 8 | 0.59 | 0.76 | 0.96 | 1.60 | 1.64 | 0.47× | 0.95 | 1.09 | 1.39 | 2.33 | 2.89 | 0.47× |
| tailwind | 8 | 0.75 | 0.94 | 1.14 | 1.44 | 1.58 | 0.65× | 1.04 | 1.15 | 1.44 | 2.37 | 3.25 | 0.49× |
| text-decoration | 1 | 1.16 | 1.25 | 1.99 | 1.76 | 2.17 | 0.71× | 1.96 | 2.06 | 2.82 | 2.76 | 3.87 | 0.75× |
| text-i18n | 2 | 1.46 | 1.61 | 2.11 | 2.57 | 3.10 | 0.63× | 2.97 | 3.04 | 3.80 | 4.83 | 8.11 | 0.63× |
| text-indent | 4 | 0.47 | 0.61 | 0.76 | 1.40 | 1.37 | 0.44× | 1.01 | 1.16 | 1.40 | 2.24 | 2.68 | 0.52× |
| text-overflow | 4 | 0.32 | 0.44 | 0.50 | 1.29 | 1.19 | 0.34× | 0.63 | 0.77 | 0.84 | 1.98 | 2.08 | 0.39× |
| text-paragraph | 5 | 1.22 | 1.48 | 1.86 | 2.56 | 2.86 | 0.58× | 2.62 | 2.73 | 3.48 | 4.67 | 7.28 | 0.58× |
| text-shadow | 1 | 0.61 | 0.79 | 1.06 | 1.16 | 1.36 | 0.68× | 2.69 | 2.93 | 3.76 | 2.40 | 4.50 | 1.22× |
| text-single-line | 3 | 0.82 | 1.01 | 1.21 | 1.72 | 1.95 | 0.59× | 1.71 | 1.82 | 2.20 | 3.41 | 5.11 | 0.53× |
| text-stroke | 2 | 0.85 | 1.00 | 1.37 | 1.03 | 1.14 | 0.96× | 1.38 | 1.58 | 2.05 | 1.96 | 2.52 | 0.80× |
| text-truncation | 3 | 0.84 | 1.01 | 1.30 | 1.88 | 2.09 | 0.54× | 1.32 | 1.38 | 1.83 | 3.24 | 4.68 | 0.43× |
| text-wrap-balance | 3 | 0.57 | 0.73 | 0.98 | 1.84 | 1.70 | 0.40× | 1.17 | 1.34 | 1.73 | 2.81 | 3.06 | 0.48× |
| transform | 5 | 0.72 | 0.92 | 1.10 | 1.90 | 2.52 | 0.48× | 1.17 | 1.34 | 1.61 | 2.99 | 4.51 | 0.45× |
| visibility | 1 | 0.27 | 0.39 | 0.39 | 0.72 | 0.67 | 0.54× | 0.30 | 0.44 | 0.40 | 1.16 | 1.41 | 0.38× |

Geomean ms theo nhóm fixture. bm-n = bm-native, bm-w = bm-wasm (sync), tk-n = takumi-native (async), tk-w = takumi-wasm; tỉ lệ = bm-native async / takumi-native async (dưới 1× = bm nhanh hơn).
<!-- /native-bench:categories -->

bm-native so với takumi-native (cùng async):

<!-- native-bench:best-worst -->
**raw — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-jpeg-fit` | 1.87 | 2.14 | 22.8 | 1.01 | 0.09× |
| `pfx-bg-clip-text` | 0.42 | 0.52 | 2.75 | 1.20 | 0.19× |
| `pfx-bg-blend` | 0.81 | 0.96 | 4.92 | 0.66 | 0.19× |
| `radial-shapes` | 2.06 | 2.25 | 10.8 | 1.20 | 0.21× |
| `radial-at-position` | 2.31 | 2.63 | 12.6 | 1.09 | 0.21× |
| `radial-spotlight-small` | 0.49 | 0.66 | 2.96 | 1.28 | 0.22× |
| `gap-background-clip-text` | 0.40 | 0.56 | 2.04 | 0.67 | 0.28× |
| `fix-text-emoji-zwj` | 0.16 | 0.22 | 0.79 | 0.73 | 0.28× |
| `img-png-fit` | 1.77 | 2.08 | 6.68 | 1.34 | 0.31× |
| `fix-text-line-clamp-marker` | 0.40 | 0.49 | 1.49 | 1.06 | 0.33× |

**raw — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `sizing-minmax` | 1.20 | 1.53 | 1.52 | 1.53 | 1.00× |
| `fix-text-paint-order` | 0.83 | 0.99 | 0.99 | 0.91 | 1.00× |
| `radius-uniform-percorner` | 1.48 | 1.77 | 1.78 | 0.86 | 0.99× |
| `abs-zorder` | 1.84 | 1.91 | 1.96 | 0.78 | 0.98× |
| `pfx-svg-background` | 0.64 | 0.83 | 0.86 | 0.58 | 0.96× |
| `sizing-aspect-ratio` | 1.33 | 1.57 | 1.66 | 1.01 | 0.94× |
| `pfx-text-stroke` | 0.88 | 1.00 | 1.08 | 1.95 | 0.93× |
| `tw-responsive` | 0.85 | 1.07 | 1.15 | 2.69 | 0.92× |
| `flex-row-column` | 1.39 | 1.66 | 1.81 | 1.33 | 0.92× |
| `radius-pill-circle` | 1.50 | 1.60 | 1.76 | 2.26 | 0.91× |

**png — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `colors-solid-bg` | 0.26 | 0.29 | 1.20 | 1.48 | 0.24× |
| `sizing-minmax` | 1.44 | 1.42 | 4.28 | 1.89 | 0.33× |
| `css-important-var` | 0.92 | 0.95 | 2.84 | 1.32 | 0.33× |
| `sizing-percent` | 1.50 | 1.48 | 4.32 | 1.17 | 0.34× |
| `gap-oklch-color` | 0.24 | 0.35 | 1.02 | 1.21 | 0.34× |
| `borders-uniform` | 1.48 | 1.39 | 4.04 | 0.52 | 0.34× |
| `abs-inset` | 1.58 | 1.53 | 4.44 | 0.84 | 0.35× |
| `fix-text-emoji-flags-skin` | 0.29 | 0.35 | 0.99 | 1.34 | 0.36× |
| `sizing-aspect-ratio` | 1.64 | 1.52 | 4.23 | 1.07 | 0.36× |
| `fix-css-struct-text-nodes` | 0.99 | 1.05 | 2.87 | 0.78 | 0.36× |

**png — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-photo-bg` | 30.0 | 30.5 | 14.2 | 3.18 | 2.16× |
| `img-radius-clip` | 15.5 | 15.7 | 10.5 | 1.92 | 1.50× |
| `card-blog` | 19.8 | 20.2 | 14.4 | 2.00 | 1.40× |
| `stress-3000x2000-card` | 55.5 | 56.3 | 44.2 | 2.53 | 1.27× |
| `fx-text-shadow` | 2.69 | 2.93 | 2.40 | 1.52 | 1.22× |
| `card-og` | 10.3 | 10.6 | 9.08 | 2.66 | 1.17× |
| `fix-text-emoji-zwj` | 1.10 | 1.21 | 1.15 | 0.99 | 1.06× |
| `fix-css-image-rendering-modes` | 5.27 | 5.51 | 5.22 | 2.73 | 1.06× |
| `fix-text-emoji-spacing` | 1.11 | 1.23 | 1.17 | 1.37 | 1.05× |
| `pfx-mix-blend` | 2.77 | 3.00 | 2.91 | 2.15 | 1.03× |
<!-- /native-bench:best-worst -->

<!-- native-bench:formats -->
| Fixture | Định dạng | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|--:|
| `lingrad-angles` | raw | 2.29 ms · 2 953 KiB | 2.49 ms · 2 953 KiB | 4.14 ms · 2 953 KiB | 5.35 ms · 2 953 KiB | 7.24 ms · 2 953 KiB |
| `lingrad-angles` | png | 6.69 ms · 32.6 KiB | 6.89 ms · 32.6 KiB | 9.72 ms · 32.6 KiB | 9.66 ms · 102 KiB | 34.6 ms · 102 KiB |
| `lingrad-angles` | jpeg | 10.9 ms · 52.2 KiB | 11.5 ms · 52.2 KiB | 18.6 ms · 52.2 KiB | 18.8 ms · 52.3 KiB | 24.0 ms · 52.3 KiB |
| `lingrad-angles` | webp | 7.41 ms · 28.9 KiB | 7.40 ms · 28.9 KiB | 10.1 ms · 28.9 KiB | 121 ms · 22.8 KiB | 15.4 ms · 169 KiB |
| `img-photo-bg` | raw | 1.66 ms · 2 953 KiB | 1.76 ms · 2 953 KiB | 2.38 ms · 2 953 KiB | 4.59 ms · 2 953 KiB | 6.83 ms · 2 953 KiB |
| `img-photo-bg` | png | 30.0 ms · 511 KiB | 30.5 ms · 511 KiB | 40.5 ms · 511 KiB | 14.2 ms · 513 KiB | 53.8 ms · 513 KiB |
| `img-photo-bg` | jpeg | 11.1 ms · 55.1 KiB | 11.3 ms · 55.1 KiB | 17.1 ms · 55.1 KiB | 18.4 ms · 55.2 KiB | 24.4 ms · 55.2 KiB |
| `img-photo-bg` | webp | 15.0 ms · 367 KiB | 15.8 ms · 367 KiB | 20.9 ms · 367 KiB | 175 ms · 414 KiB | 21.8 ms · 470 KiB |
| `card-flat-ui` | raw | 3.08 ms · 2 953 KiB | 3.30 ms · 2 953 KiB | 4.93 ms · 2 953 KiB | 4.81 ms · 2 953 KiB | 7.36 ms · 2 953 KiB |
| `card-flat-ui` | png | 5.99 ms · 23.1 KiB | 6.20 ms · 23.1 KiB | 8.84 ms · 23.1 KiB | 8.06 ms · 25.3 KiB | 21.0 ms · 25.3 KiB |
| `card-flat-ui` | jpeg | 12.3 ms · 48.9 KiB | 12.6 ms · 48.9 KiB | 19.2 ms · 48.9 KiB | 18.6 ms · 49.0 KiB | 24.7 ms · 49.0 KiB |
| `card-flat-ui` | webp | 6.94 ms · 18.5 KiB | 7.45 ms · 18.5 KiB | 9.43 ms · 18.5 KiB | 20.2 ms · 13.4 KiB | 12.3 ms · 27.6 KiB |

Thời gian median và dung lượng đầu ra. JPEG: quality 85 cho mọi engine. WebP: lossless cho mọi engine (không có `quality`); takumi-native mã hoá bằng libwebp, takumi-wasm bằng crate `image-webp` (nên file lớn hơn). PNG: không engine nào cho chỉnh mức nén; mỗi engine dùng mức mặc định của nó (bm: deflate riêng; takumi: `png` + `zlib-rs`, chọn giữa level 7 / không lọc và level 3 / lọc thích ứng trên một mẫu, nén thành tối đa 8 đoạn song song ở bản native), nên thời gian PNG được so kèm dung lượng file.
<!-- /native-bench:formats -->

#### bm-native thua ở đâu, và vì sao

Những gì phép đo cho thấy (bảng chẩn đoán bên dưới là một phần của mỗi lần chạy; điều gì không được nó chứng minh
thì được ghi là giả thuyết):

- **`filter: blur()` chậm hơn nhiều ở bm-render, trên cả hai backend.** Trong cảnh animation, bỏ filter blur thì
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
| 300×200 raw | 0.13 | 0.23 | 0.22 | 0.36 | 0.34 |
| 300×200 png | 0.19 | 0.27 | 0.21 | 0.73 | 0.61 |
| 1200×630 raw | 1.08 | 1.29 | 1.63 | 1.53 | 1.53 |
| 1200×630 png | 1.16 | 0.87 | 1.24 | 3.76 | 5.39 |
| 2400×1260 raw | 4.15 | 4.56 | 6.78 | 4.24 | 6.51 |
| 2400×1260 png | 5.59 | 5.92 | 6.01 | 12.4 | 20.0 |

| Cảnh animation, một khung raw 800×420 | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| shadow + blur (as animated) | 7.05 | 7.12 | 12.1 | 17.2 | 29.7 |
| shadow only | 2.33 | 2.50 | 3.96 | 5.51 | 8.01 |
| blur only | 2.36 | 2.50 | 3.73 | 4.52 | 5.81 |
| neither | 1.01 | 1.23 | 1.69 | 1.87 | 2.19 |

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

`bench/native-identity.mjs`: 250 fixture, 2376 phép so (raw, PNG, JPEG, WebP, measure, SVG, animation, ICO, HTML, ảnh, WOFF2, thông báo lỗi, native async so với sync), 2374 trùng (31 trong số đó là cùng thông báo lỗi ở cả hai), 2 khác, 800 MB đã so.
<!-- /native-bench:equiv -->

### Cold start

<!-- native-bench:cold -->
| Engine | thực median | wall p95 | hơn Node, median | hơn Node, p95 | import | registerFont | PNG đầu tiên |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Node rỗng (mốc) | 61.9 | 72.2 | 0 | 0 | — | — | — |
| bm-native | 89.9 | 119 | 28.0 | 56.9 | 6.50 | 0.56 | 20.6 |
| bm-wasm | 154 | 175 | 92.5 | 113 | 9.60 | 3.45 | 76.7 |
| takumi-native | 115 | 130 | 52.7 | 68.1 | 26.0 | 1.50 | 23.1 |
| takumi-wasm | 266 | 311 | 204 | 249 | 40.3 | 3.58 | 155 |

ms. 30 lần mỗi engine, xen kẽ các engine; spawn node → import engine như người dùng → registerFont(Inter Regular) → PNG og card 1200×630 → thoát; thời gian thực = đồng hồ của tiến trình cha từ spawn tới khi thoát. Các cột import / registerFont / PNG đầu tiên là median đo bên trong tiến trình con. CPU bận trong lúc đo: trung bình 45.5 % (tiến trình khác ≈ 2.26 lõi). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 2.26 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:cold -->

### Bộ nhớ

<!-- native-bench:memory -->
| Engine | RSS sau khởi tạo | RSS sau lượt 1 → 10 | bộ nhớ engine 1 → N | JS heap 1 → N | RSS đỉnh, cả bộ | RSS đỉnh PNG 4000×4000 (tăng thêm) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 72.6 | 102 → 101 | 32.2 → 32.2 | 6.20 → 6.20 | 194 | 149 (85.7) |
| bm-wasm | 81.7 | 138 → 139 | 68.5 → 68.5 | 6.40 → 6.50 | 211 | 153 (87.5) |
| takumi-native | 76.1 | 142 → 154 | — → — | 7.40 → 6.50 | 209 | 141 (74.3) |
| takumi-wasm | 91.5 | 144 → 179 | 71.5 → 71.5 | 7.20 → 7.30 | 241 | 156 (84.1) |

MiB, sau khi ép GC. Một tiến trình cho mỗi engine; mỗi lượt render mọi fixture ra raw và PNG (API async), một renderer cho mỗi bộ font. Bộ nhớ engine: bm-native = số byte addon đang cấp phát (`memoryBytes()`), bm-wasm / takumi-wasm = bộ nhớ tuyến tính wasm, takumi-native = không công bố. Node rỗng: 51.5 MiB RSS. "Tăng thêm" = RSS đỉnh trừ RSS ngay trước lần render 4000×4000.
<!-- /native-bench:memory -->

### Event loop

<!-- native-bench:eventloop -->
| Việc | Engine | API | ms của việc | CPU ms | trễ timer lớn nhất ms | trễ p99 ms | số lần timer chạy |
|:--|--:|--:|--:|--:|--:|--:|--:|
| heavy | bm-native | sync | 291 | 297 | 291 | 291 | 1 |
| heavy | bm-native | async | 275 | 594 | 1.70 | 1.10 | 276 |
| heavy | bm-wasm | sync | 422 | 640 | 422 | 422 | 1 |
| heavy | bm-wasm | async (chạy trên main thread) | 527 | 719 | 527 | 527 | 1 |
| heavy | takumi-native | async | 295 | 845 | 14.3 | 2.10 | 278 |
| heavy | takumi-wasm | async (chạy trên main thread) | 894 | 1 124 | 894 | 894 | 1 |
| anim | bm-native | sync | 502 | 515 | 502 | 502 | 1 |
| anim | bm-native | async | 543 | 1 094 | 1.20 | 1.20 | 545 |
| anim | bm-wasm | sync | 920 | 1 250 | 920 | 920 | 1 |
| anim | bm-wasm | async (chạy trên main thread) | 905 | 1 172 | 905 | 905 | 1 |
| anim | takumi-native | async | 503 | 2 625 | 29.2 | 4.40 | 426 |
| anim | takumi-wasm | async (chạy trên main thread) | 1 859 | 2 281 | 1 859 | 1 859 | 1 |

heavy = một PNG 2400×2400: gradient, 24 thẻ với box-shadow mờ lớn, cứ ba thẻ có một thẻ `filter: blur(6px)`, chữ; anim = renderAnimation: 60 khung (2 s ở 30 fps) WebP lossless 800×420, 12 hình tròn có bóng, mờ, xoay (cảnh tĩnh). Một `setInterval` 1 ms ghi khoảng cách giữa các lần chạy trong lúc lời gọi chạy. Một chuỗi setImmediate giữ cho vòng lặp không ngủ, vì vòng lặp Node rảnh trên Windows thức theo đồng hồ hệ thống 15,6 ms và timer sẽ không bao giờ cho thấy dưới ~16 ms. Lời gọi chặn vòng lặp cho thấy một lần chạy có độ trễ bằng cả lời gọi. CPU ms là của cả tiến trình trong lúc gọi, kể cả chuỗi setImmediate trên main thread (khoảng một lõi mỗi khi vòng lặp rảnh). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 2.44 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:eventloop -->

### Thông lượng khi chạy đồng thời

<!-- native-bench:throughput -->
| Engine | Cách chạy | UV_THREADPOOL_SIZE | N=1 | N=2 | N=4 | N=8 | N=16 |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 1 client, tuần tự | 4 | 92.2 |  |  |  |  |
| bm-wasm | 1 client, tuần tự | — | 65.9 |  |  |  |  |
| takumi-native | 1 client, tuần tự | 4 | 99.2 |  |  |  |  |
| takumi-wasm | 1 client, tuần tự | — | 43.4 |  |  |  |  |
| bm-native | 1 renderer, async | 4 | 90.1 (0.98×, 98 %) | 95.0 (1.03×, 103 %) | 98.0 (1.06×, 106 %) | 98.9 (1.07×, 107 %) | 86.1 (0.93×, 93 %) |
| bm-native | 2 renderer, async | 4 | 93.8 (1.02×, 102 %) | 164 (1.78×, 89 %) | 164 (1.78×, 89 %) | 156 (1.69×, 85 %) | 162 (1.75×, 88 %) |
| bm-native | 4 renderer, async | 4 | 95.9 (1.04×, 104 %) | 162 (1.75×, 88 %) | 227 (2.46×, 62 %) | 238 (2.58×, 64 %) | 243 (2.64×, 66 %) |
| bm-native | 8 renderer, async | 4 | 96.0 (1.04×, 104 %) | 148 (1.60×, 80 %) | 235 (2.54×, 64 %) | 240 (2.60×, 65 %) | 236 (2.56×, 64 %) |
| bm-native | 1 renderer, async | 8 | 90.8 (0.98×, 98 %) | 96.1 (1.04×, 104 %) | 98.9 (1.07×, 107 %) | 95.5 (1.04×, 104 %) | 91.0 (0.99×, 99 %) |
| bm-native | 2 renderer, async | 8 | 95.0 (1.03×, 103 %) | 162 (1.76×, 88 %) | 169 (1.83×, 91 %) | 152 (1.65×, 82 %) | 149 (1.62×, 81 %) |
| bm-native | 4 renderer, async | 8 | 96.5 (1.05×, 105 %) | 161 (1.75×, 87 %) | 228 (2.48×, 62 %) | 234 (2.54×, 63 %) | 243 (2.64×, 66 %) |
| bm-native | 8 renderer, async | 8 | 91.5 (0.99×, 99 %) | 153 (1.66×, 83 %) | 236 (2.56×, 64 %) | 310 (3.36×, 42 %) | 316 (3.43×, 43 %) |
| takumi-native | 1 renderer, async | 4 | 95.5 (0.96×, 96 %) | 136 (1.37×, 69 %) | 180 (1.81×, 45 %) | 170 (1.72×, 43 %) | 148 (1.49×, 37 %) |
| takumi-native | 1 renderer, async | 8 | 85.7 (0.86×, 86 %) | 134 (1.35×, 67 %) | 168 (1.70×, 42 %) | 194 (1.96×, 24 %) | 207 (2.08×, 26 %) |
| takumi-native | 2 renderer, async | 4 | 99.8 (1.01×, 101 %) | 145 (1.46×, 73 %) | 169 (1.70×, 85 %) | 174 (1.75×, 88 %) | 184 (1.86×, 93 %) |
| takumi-native | 4 renderer, async | 4 | 98.1 (0.99×, 99 %) | 133 (1.34×, 67 %) | 173 (1.74×, 44 %) | 185 (1.86×, 47 %) | 186 (1.88×, 47 %) |
| takumi-native | 2 renderer, async | 8 | 93.3 (0.94×, 94 %) | 126 (1.27×, 63 %) | 180 (1.81×, 90 %) | 207 (2.08×, 104 %) | 194 (1.95×, 98 %) |
| takumi-native | 4 renderer, async | 8 | 94.9 (0.96×, 96 %) | 140 (1.42×, 71 %) | 178 (1.79×, 45 %) | 193 (1.95×, 49 %) | 206 (2.08×, 52 %) |
| bm-wasm | worker pool, 1 worker | — | 64.5 (0.98×, 98 %) | 67.5 (1.02×, 102 %) | 63.9 (0.97×, 97 %) | 63.4 (0.96×, 96 %) | 68.7 (1.04×, 104 %) |
| bm-wasm | worker pool, 2 worker | — | 67.1 (1.02×, 102 %) | 108 (1.63×, 82 %) | 109 (1.66×, 83 %) | 116 (1.75×, 88 %) | 111 (1.68×, 84 %) |
| bm-wasm | worker pool, 4 worker | — | 63.6 (0.97×, 97 %) | 111 (1.68×, 84 %) | 168 (2.56×, 64 %) | 159 (2.42×, 60 %) | 155 (2.36×, 59 %) |
| bm-wasm | worker pool, 8 worker | — | 62.3 (0.95×, 95 %) | 114 (1.72×, 86 %) | 166 (2.52×, 63 %) | 191 (2.89×, 36 %) | 203 (3.07×, 38 %) |
| takumi-wasm | worker pool, 1 worker | — | 43.9 (1.01×, 101 %) | 44.8 (1.03×, 103 %) | 45.1 (1.04×, 104 %) | 46.1 (1.06×, 106 %) | 46.0 (1.06×, 106 %) |
| takumi-wasm | worker pool, 2 worker | — | 40.7 (0.94×, 94 %) | 73.0 (1.68×, 84 %) | 77.5 (1.79×, 89 %) | 76.7 (1.77×, 88 %) | 72.9 (1.68×, 84 %) |
| takumi-wasm | worker pool, 4 worker | — | 41.2 (0.95×, 95 %) | 78.0 (1.80×, 90 %) | 110 (2.52×, 63 %) | 106 (2.44×, 61 %) | 109 (2.51×, 63 %) |
| takumi-wasm | worker pool, 8 worker | — | 44.2 (1.02×, 102 %) | 73.7 (1.70×, 85 %) | 104 (2.39×, 60 %) | 124 (2.86×, 36 %) | 143 (3.30×, 41 %) |

Ảnh mỗi giây; trong ngoặc là mức tăng so với tốc độ tuần tự một client của cùng engine (các dòng đầu) và hiệu suất mở rộng = mức tăng / min(N, số thread có thể render các ảnh khác nhau cùng lúc, 8 CPU logic); một renderer bm tính là 1, K renderer là min(K, UV_THREADPOOL_SIZE), renderer của takumi-native là UV_THREADPOOL_SIZE, pool worker là K. og card 1200×630 PNG, vòng kín: N client, mỗi client luôn có một yêu cầu đang chạy; 2000 ms mỗi điểm sau khi khởi động. CPU bận trong lúc đo: trung bình 57.9 % (tiến trình khác ≈ 2.35 lõi). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 2.35 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:throughput -->

### Kích thước

<!-- native-bench:sizes -->
| File | Target | KiB | gzip -9 KiB | brotli KiB | Trạng thái |
|:--|--:|--:|--:|--:|--:|
| `bm-render.win32-x64-msvc.node` | `x86_64-windows-gnu` | 3 684 | 1 954 | 1 537 | đã chạy (benchmark này) |
| `bm-render.linux-x64-gnu.node` | `x86_64-linux-gnu.2.17` | 3 555 | 1 916 | 1 517 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-render.win32-arm64-msvc.node` | `aarch64-windows-gnu` | 2 939 | 1 766 | 1 321 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-render.linux-x64-musl.node` | `x86_64-linux-musl` | 3 554 | 1 916 | 1 518 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-render.linux-arm64-gnu.node` | `aarch64-linux-gnu.2.17` | 2 950 | 1 765 | 1 324 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-render.linux-arm64-musl.node` | `aarch64-linux-musl` | 2 950 | 1 765 | 1 322 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-render.darwin-x64.node` | `x86_64-macos.10.15` | 3 535 | 1 911 | 1 510 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-render.darwin-arm64.node` | `aarch64-macos.11.0` | 3 006 | 1 750 | 1 284 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| bm wasm `core` | wasm32 | 628 | 302 | 255 |  |
| bm wasm `standard` | wasm32 | 1 078 | 538 | 459 |  |
| bm wasm `full` | wasm32 | 1 275 | 633 | 530 |  |
| bm wasm `add-on WOFF` | wasm32 | 84.4 | 67.8 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Addon native lấy từ `native/dist/manifest.json` (build ngày 2026-11-16 với Zig 0.17.0, ReleaseFast). Mỗi người dùng chỉ tải một addon (gói optional cho nền tảng của họ) cộng với bản wasm dự phòng nằm trong gói chính.
<!-- /native-bench:sizes -->

### Nhiễu

<!-- native-bench:noise -->
| Giai đoạn | bắt đầu (UTC) | thời lượng | CPU bận ngay trước | CPU bận trong lúc đo | tiến trình khác, lõi |
|:--|--:|--:|--:|--:|--:|
| speed lượt 1 | 21:11 | 154 s | 16.5 % | 36.3 % (max 75.1 %) | 1.74 |
| speed lượt 2 | 21:15 | 155 s | 22.4 % | 35.8 % (max 59.1 %) | 1.73 |
| speed lượt 3 | 21:19 | 155 s | 20.6 % | 35.1 % (max 59.4 %) | 1.67 |
| cold |  | 21.1 s |  | 45.5 % (max 57.2 %) | 2.26 |
| memory |  | 65.4 s |  | 37.9 % (max 60.0 %) | 1.85 |
| eventloop |  | 13.3 s |  | 42.9 % (max 67.6 %) | 2.44 |
| throughput |  | 288.4 s |  | 57.9 % (max 100 %) | 2.35 |

"Tiến trình khác" = số lõi-giây bận của cả máy trừ thời gian CPU của chính benchmark, chia cho thời gian thực (8 CPU logic). Số fixture có median lệch quá 10 % giữa các lượt: bm-native:sync raw: 149, bm-native:sync png: 62, bm-native:async raw: 142, bm-native:async png: 80, bm-wasm:sync raw: 118, bm-wasm:sync png: 48, takumi-native:async raw: 110, takumi-native:async png: 65, takumi-wasm:async raw: 100, takumi-wasm:async png: 65. 0 geomean tuyệt đối (biến thể × định dạng) lệch quá 10 % giữa các lượt (khoảng lệch lớn nhất: 4.30 %), vì vậy các bảng ưu tiên tỉ lệ đo trong từng lượt. Tỉ lệ giữa engine lệch quá 10 %: không có.
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
| `colors-solid-bg` | colors | 0.30 / 0.71 | 0.46 / 1.60 | 0.46 / 0.82 | 0.66 / 1.58 | 0.66 / 1.25 | 0.70× | 0.65× | 0.26 / 0.58 | 0.29 / 0.57 | 0.32 / 0.54 | 1.20 / 1.77 | 1.41 / 2.16 | 0.24× | 0.80× |
| `colors-hex` | colors | 2.02 / 2.76 | 2.07 / 3.73 | 3.11 / 4.80 | 3.84 / 4.45 | 5.17 / 6.93 | 0.54× | 0.65× | 2.21 / 2.95 | 2.31 / 3.68 | 3.26 / 3.64 | 5.89 / 6.64 | 8.53 / 9.79 | 0.39× | 0.68× |
| `colors-functional` | colors | 1.48 / 2.39 | 1.65 / 1.90 | 2.40 / 2.82 | 3.02 / 3.97 | 3.49 / 4.22 | 0.54× | 0.62× | 2.08 / 2.32 | 2.02 / 2.59 | 2.91 / 3.12 | 5.24 / 5.59 | 8.10 / 9.04 | 0.38× | 0.72× |
| `colors-named` | colors | 1.62 / 2.20 | 1.81 / 2.67 | 2.64 / 3.38 | 3.10 / 3.59 | 3.29 / 3.58 | 0.58× | 0.61× | 2.12 / 2.30 | 2.29 / 2.80 | 3.30 / 4.55 | 5.70 / 7.00 | 8.30 / 9.00 | 0.40× | 0.64× |
| `colors-transparent-canvas` | colors | 0.42 / 0.62 | 0.61 / 0.99 | 0.60 / 1.02 | 0.81 / 1.28 | 0.92 / 1.30 | 0.75× | 0.70× | 0.49 / 0.66 | 0.63 / 0.91 | 0.68 / 0.85 | 1.14 / 1.44 | 1.56 / 1.88 | 0.55× | 0.72× |
| `flex-row-column` | flex | 1.39 / 2.00 | 1.66 / 2.67 | 2.34 / 2.85 | 1.81 / 2.61 | 1.88 / 2.50 | 0.92× | 0.59× | 1.97 / 3.18 | 2.03 / 3.12 | 2.67 / 3.25 | 4.28 / 4.70 | 7.13 / 10.3 | 0.47× | 0.74× |
| `flex-justify-align` | flex | 1.56 / 1.91 | 1.87 / 3.13 | 2.54 / 3.27 | 2.34 / 2.96 | 2.67 / 3.57 | 0.80× | 0.61× | 2.02 / 2.31 | 2.01 / 2.25 | 2.89 / 3.31 | 4.47 / 4.78 | 6.83 / 8.01 | 0.45× | 0.70× |
| `flex-wrap-gap` | flex | 1.74 / 2.79 | 1.80 / 2.53 | 2.77 / 3.32 | 2.23 / 2.79 | 2.53 / 3.42 | 0.81× | 0.63× | 2.33 / 2.48 | 2.26 / 2.60 | 3.20 / 3.74 | 4.46 / 4.81 | 7.09 / 8.28 | 0.51× | 0.73× |
| `flex-grow-shrink-basis` | flex | 1.25 / 1.98 | 1.52 / 2.37 | 1.87 / 2.24 | 1.83 / 2.40 | 2.00 / 2.68 | 0.83× | 0.67× | 1.53 / 1.92 | 1.54 / 2.07 | 2.14 / 2.70 | 3.88 / 4.52 | 5.93 / 6.33 | 0.40× | 0.72× |
| `flex-nested-small` | flex | 0.31 / 0.52 | 0.46 / 0.68 | 0.44 / 0.59 | 0.71 / 1.12 | 0.64 / 1.03 | 0.65× | 0.70× | 0.39 / 0.57 | 0.54 / 0.91 | 0.55 / 0.83 | 1.10 / 1.41 | 1.35 / 1.81 | 0.49× | 0.71× |
| `sizing-percent` | sizing | 1.26 / 1.79 | 1.51 / 2.21 | 1.86 / 2.46 | 1.68 / 2.36 | 1.84 / 2.72 | 0.90× | 0.68× | 1.50 / 1.98 | 1.48 / 2.02 | 2.06 / 2.67 | 4.32 / 5.09 | 7.05 / 8.80 | 0.34× | 0.73× |
| `sizing-minmax` | sizing | 1.20 / 1.65 | 1.53 / 2.30 | 1.69 / 2.15 | 1.52 / 2.10 | 1.72 / 2.69 | 1.00× | 0.71× | 1.44 / 1.60 | 1.42 / 2.16 | 1.93 / 2.24 | 4.28 / 4.83 | 6.65 / 7.78 | 0.33× | 0.75× |
| `sizing-aspect-ratio` | sizing | 1.33 / 1.79 | 1.57 / 2.26 | 1.84 / 2.64 | 1.66 / 2.14 | 1.70 / 2.24 | 0.94× | 0.72× | 1.64 / 2.23 | 1.52 / 1.90 | 2.19 / 2.53 | 4.23 / 4.50 | 7.01 / 8.13 | 0.36× | 0.75× |
| `sizing-padding-margin` | sizing | 1.33 / 2.05 | 1.49 / 2.12 | 1.81 / 2.09 | 1.73 / 2.26 | 1.81 / 2.52 | 0.86× | 0.73× | 1.55 / 1.77 | 1.52 / 1.80 | 2.18 / 2.58 | 3.95 / 5.07 | 6.90 / 7.88 | 0.38× | 0.71× |
| `sizing-auto-margin-center` | sizing | 0.26 / 0.41 | 0.39 / 0.74 | 0.37 / 0.57 | 0.56 / 0.81 | 0.47 / 0.70 | 0.70× | 0.71× | 0.28 / 0.46 | 0.40 / 0.50 | 0.38 / 0.57 | 0.87 / 1.07 | 1.09 / 1.37 | 0.46× | 0.74× |
| `abs-inset` | absolute | 1.28 / 1.85 | 1.59 / 2.18 | 1.95 / 2.45 | 1.91 / 2.57 | 2.53 / 3.36 | 0.83× | 0.66× | 1.58 / 2.38 | 1.53 / 2.60 | 2.14 / 3.06 | 4.44 / 5.16 | 8.09 / 10.1 | 0.35× | 0.74× |
| `abs-zorder` | absolute | 1.84 / 2.56 | 1.91 / 2.66 | 2.83 / 3.80 | 1.96 / 2.88 | 2.39 / 2.99 | 0.98× | 0.65× | 4.37 / 5.01 | 4.47 / 5.30 | 6.51 / 7.48 | 4.97 / 5.41 | 15.1 / 16.9 | 0.90× | 0.67× |
| `abs-in-flow` | absolute | 0.34 / 0.53 | 0.47 / 0.94 | 0.49 / 0.86 | 0.81 / 1.46 | 0.74 / 1.50 | 0.58× | 0.70× | 0.44 / 0.56 | 0.58 / 0.75 | 0.62 / 0.87 | 1.26 / 1.59 | 1.57 / 1.99 | 0.46× | 0.71× |
| `borders-uniform` | borders | 1.22 / 1.74 | 1.49 / 2.16 | 1.74 / 2.26 | 1.88 / 2.46 | 2.24 / 3.08 | 0.79× | 0.70× | 1.48 / 1.84 | 1.39 / 1.74 | 2.00 / 2.32 | 4.04 / 4.39 | 6.22 / 6.57 | 0.34× | 0.74× |
| `borders-per-side` | borders | 1.25 / 1.78 | 1.45 / 2.15 | 1.91 / 2.24 | 1.75 / 2.73 | 1.98 / 2.54 | 0.83× | 0.66× | 1.71 / 2.53 | 1.73 / 2.03 | 2.28 / 3.43 | 4.16 / 4.73 | 6.39 / 7.98 | 0.42× | 0.75× |
| `borders-with-radius` | borders | 0.62 / 0.87 | 0.79 / 0.98 | 0.96 / 1.34 | 0.93 / 1.58 | 1.15 / 1.69 | 0.84× | 0.64× | 0.81 / 0.96 | 0.96 / 1.14 | 1.17 / 1.71 | 1.49 / 1.87 | 1.97 / 2.35 | 0.64× | 0.69× |
| `radius-uniform-percorner` | border-radius | 1.48 / 2.05 | 1.77 / 2.80 | 2.21 / 2.88 | 1.78 / 2.74 | 1.80 / 2.69 | 0.99× | 0.67× | 2.20 / 2.76 | 2.16 / 2.57 | 3.06 / 3.42 | 4.21 / 4.90 | 7.63 / 7.96 | 0.51× | 0.72× |
| `radius-elliptical` | border-radius | 1.46 / 1.82 | 1.69 / 3.01 | 2.18 / 3.02 | 2.12 / 2.55 | 1.93 / 2.65 | 0.80× | 0.67× | 2.20 / 2.36 | 2.06 / 2.55 | 2.81 / 3.21 | 3.84 / 4.29 | 7.07 / 7.48 | 0.54× | 0.78× |
| `radius-pill-circle` | border-radius | 1.50 / 1.87 | 1.60 / 2.24 | 2.08 / 2.54 | 1.76 / 2.51 | 1.67 / 2.48 | 0.91× | 0.72× | 1.90 / 2.36 | 1.81 / 2.46 | 2.44 / 2.79 | 3.80 / 4.07 | 6.16 / 6.76 | 0.48× | 0.78× |
| `radius-small` | border-radius | 0.32 / 0.50 | 0.46 / 0.65 | 0.44 / 0.72 | 0.63 / 1.02 | 0.53 / 0.96 | 0.73× | 0.72× | 0.39 / 0.54 | 0.53 / 0.73 | 0.53 / 0.70 | 0.89 / 1.11 | 1.14 / 1.33 | 0.60× | 0.74× |
| `lingrad-angles` | linear-gradient | 2.29 / 3.34 | 2.49 / 3.72 | 4.14 / 4.55 | 5.35 / 6.42 | 7.24 / 8.06 | 0.46× | 0.55× | 6.69 / 8.27 | 6.89 / 7.97 | 9.72 / 11.3 | 9.66 / 11.5 | 34.6 / 37.0 | 0.71× | 0.69× |
| `lingrad-multistop` | linear-gradient | 2.08 / 2.97 | 2.25 / 2.86 | 3.71 / 4.22 | 6.40 / 8.45 | 7.10 / 8.49 | 0.35× | 0.56× | 6.18 / 6.61 | 6.41 / 6.98 | 9.75 / 10.9 | 9.15 / 9.35 | 24.0 / 25.0 | 0.70× | 0.63× |
| `lingrad-alpha` | linear-gradient | 2.99 / 4.43 | 3.32 / 4.17 | 5.22 / 7.91 | 6.89 / 8.17 | 8.34 / 10.1 | 0.48× | 0.57× | 5.68 / 6.48 | 5.89 / 6.57 | 8.64 / 9.30 | 9.72 / 10.4 | 29.3 / 33.7 | 0.61× | 0.66× |
| `lingrad-hero-small` | linear-gradient | 0.40 / 0.62 | 0.57 / 0.81 | 0.57 / 0.90 | 1.08 / 1.46 | 0.99 / 1.24 | 0.53× | 0.70× | 1.39 / 1.50 | 1.57 / 1.73 | 1.87 / 2.01 | 1.98 / 2.44 | 3.28 / 3.68 | 0.79× | 0.75× |
| `radial-shapes` | radial-gradient | 2.06 / 2.86 | 2.25 / 2.58 | 3.50 / 3.88 | 10.8 / 12.1 | 8.48 / 9.31 | 0.21× | 0.59× | 13.3 / 15.1 | 13.4 / 14.3 | 17.4 / 18.9 | 15.6 / 17.7 | 36.9 / 40.0 | 0.86× | 0.76× |
| `radial-at-position` | radial-gradient | 2.31 / 3.20 | 2.63 / 3.77 | 4.06 / 4.43 | 12.6 / 13.1 | 9.93 / 10.9 | 0.21× | 0.57× | 12.1 / 12.7 | 12.2 / 13.0 | 16.2 / 18.4 | 17.9 / 20.9 | 39.6 / 44.5 | 0.68× | 0.75× |
| `radial-spotlight-small` | radial-gradient | 0.49 / 0.57 | 0.66 / 0.84 | 0.59 / 0.90 | 2.96 / 3.39 | 1.61 / 2.22 | 0.22× | 0.82× | 4.35 / 5.04 | 4.63 / 4.90 | 5.55 / 5.96 | 4.55 / 4.98 | 9.79 / 10.5 | 1.02× | 0.78× |
| `shadow-offset-blur` | box-shadow | 2.90 / 4.12 | 3.18 / 4.77 | 5.19 / 6.20 | 6.28 / 8.63 | 9.39 / 13.5 | 0.51× | 0.56× | 8.17 / 8.63 | 8.17 / 9.06 | 12.6 / 12.8 | 8.85 / 9.32 | 28.8 / 29.5 | 0.92× | 0.65× |
| `shadow-spread-multi` | box-shadow | 3.13 / 3.45 | 3.41 / 4.71 | 5.24 / 6.09 | 5.61 / 6.21 | 8.51 / 9.04 | 0.61× | 0.60× | 9.16 / 11.5 | 9.05 / 9.68 | 13.6 / 14.7 | 8.84 / 9.63 | 29.3 / 32.0 | 1.02× | 0.67× |
| `shadow-inset` | box-shadow | 3.33 / 3.91 | 3.60 / 4.65 | 5.32 / 5.97 | 7.68 / 8.26 | 11.4 / 12.4 | 0.47× | 0.63× | 8.19 / 9.38 | 8.46 / 9.95 | 12.8 / 13.3 | 10.6 / 11.4 | 28.9 / 30.1 | 0.80× | 0.64× |
| `shadow-small` | box-shadow | 0.52 / 0.83 | 0.71 / 0.91 | 0.86 / 1.31 | 1.31 / 1.81 | 1.60 / 2.10 | 0.54× | 0.60× | 0.74 / 1.04 | 0.90 / 1.06 | 1.17 / 1.42 | 1.98 / 2.46 | 2.41 / 2.77 | 0.45× | 0.64× |
| `opacity-basic` | opacity | 2.39 / 3.09 | 2.63 / 3.65 | 4.06 / 4.49 | 3.83 / 4.53 | 7.50 / 7.96 | 0.68× | 0.59× | 3.35 / 3.67 | 3.43 / 4.01 | 4.89 / 5.64 | 6.39 / 7.29 | 13.8 / 15.0 | 0.54× | 0.69× |
| `opacity-nested` | opacity | 1.91 / 2.67 | 2.13 / 3.01 | 3.29 / 4.03 | 4.55 / 5.49 | 10.8 / 13.3 | 0.47× | 0.58× | 2.56 / 3.44 | 2.74 / 3.19 | 3.78 / 4.58 | 6.89 / 8.02 | 14.8 / 16.3 | 0.40× | 0.68× |
| `opacity-with-radius-shadow` | opacity | 0.83 / 1.12 | 1.00 / 1.19 | 1.47 / 2.03 | 2.36 / 2.96 | 3.95 / 4.61 | 0.42× | 0.57× | 1.11 / 1.38 | 1.27 / 1.86 | 1.80 / 2.13 | 2.93 / 3.40 | 4.87 / 5.18 | 0.43× | 0.62× |
| `overflow-hidden-clip` | overflow | 1.30 / 2.06 | 1.57 / 2.22 | 2.05 / 2.59 | 2.58 / 3.13 | 3.19 / 4.03 | 0.61× | 0.63× | 1.86 / 2.21 | 1.82 / 2.25 | 2.50 / 3.29 | 4.63 / 5.10 | 7.49 / 8.46 | 0.39× | 0.74× |
| `overflow-radius-clip` | overflow | 1.94 / 3.04 | 2.09 / 2.61 | 2.76 / 3.13 | 4.29 / 5.53 | 4.27 / 5.02 | 0.49× | 0.70× | 4.04 / 4.35 | 4.28 / 4.55 | 5.77 / 6.71 | 7.00 / 7.37 | 15.5 / 16.9 | 0.61× | 0.70× |
| `overflow-nested` | overflow | 0.32 / 0.49 | 0.45 / 0.65 | 0.49 / 0.68 | 0.71 / 1.02 | 0.71 / 1.03 | 0.64× | 0.66× | 0.48 / 0.63 | 0.64 / 0.94 | 0.68 / 0.93 | 1.32 / 1.84 | 1.69 / 1.99 | 0.48× | 0.70× |
| `transform-basic` | transform | 1.72 / 2.40 | 2.01 / 2.88 | 2.58 / 4.00 | 4.01 / 5.50 | 5.21 / 7.48 | 0.50× | 0.67× | 2.56 / 3.12 | 2.62 / 3.35 | 3.55 / 4.77 | 6.46 / 7.32 | 10.1 / 11.8 | 0.41× | 0.72× |
| `transform-combined-origin` | transform | 1.60 / 2.64 | 1.78 / 2.25 | 2.42 / 2.89 | 3.61 / 4.63 | 4.55 / 5.47 | 0.49× | 0.66× | 2.37 / 2.97 | 2.49 / 3.04 | 3.21 / 3.83 | 5.81 / 6.38 | 9.67 / 9.98 | 0.43× | 0.74× |
| `transform-text-small` | transform | 0.54 / 0.72 | 0.70 / 0.81 | 0.94 / 1.17 | 1.43 / 1.65 | 1.88 / 2.15 | 0.49× | 0.58× | 1.01 / 1.20 | 1.17 / 1.37 | 1.49 / 1.67 | 2.40 / 2.66 | 3.01 / 3.30 | 0.49× | 0.67× |
| `text-single-sizes` | text-single-line | 1.36 / 1.84 | 1.49 / 2.17 | 1.91 / 2.63 | 2.29 / 3.02 | 2.75 / 3.33 | 0.65× | 0.71× | 2.49 / 3.01 | 2.48 / 2.99 | 3.25 / 3.79 | 4.67 / 5.43 | 7.76 / 9.03 | 0.53× | 0.77× |
| `text-single-colors-small` | text-single-line | 0.30 / 0.49 | 0.46 / 0.65 | 0.46 / 0.75 | 1.01 / 1.37 | 0.96 / 1.27 | 0.46× | 0.65× | 0.64 / 1.01 | 0.76 / 1.19 | 0.84 / 1.33 | 1.74 / 2.08 | 2.02 / 2.73 | 0.44× | 0.76× |
| `text-single-fonts` | text-single-line | 1.34 / 1.70 | 1.51 / 2.42 | 2.00 / 2.64 | 2.22 / 3.29 | 2.77 / 3.68 | 0.68× | 0.67× | 3.14 / 3.29 | 3.21 / 4.04 | 3.93 / 4.58 | 4.90 / 5.31 | 8.54 / 9.79 | 0.66× | 0.80× |
| `text-paragraph-wrap` | text-paragraph | 1.64 / 2.70 | 1.88 / 2.63 | 2.59 / 3.22 | 3.34 / 4.06 | 3.78 / 5.15 | 0.56× | 0.63× | 3.30 / 4.21 | 3.45 / 3.91 | 4.32 / 4.96 | 5.61 / 6.38 | 8.93 / 9.68 | 0.61× | 0.76× |
| `text-paragraph-lineheight` | text-paragraph | 1.81 / 3.17 | 2.23 / 2.93 | 2.74 / 3.00 | 3.88 / 4.23 | 4.43 / 4.90 | 0.58× | 0.66× | 3.56 / 3.98 | 3.68 / 4.07 | 4.86 / 5.14 | 6.16 / 6.72 | 9.76 / 10.7 | 0.60× | 0.73× |
| `text-paragraph-letterspacing` | text-paragraph | 1.81 / 3.07 | 2.03 / 3.00 | 2.86 / 3.22 | 3.69 / 4.17 | 4.32 / 4.91 | 0.55× | 0.63× | 4.26 / 4.83 | 4.34 / 4.84 | 5.66 / 7.13 | 6.59 / 8.41 | 10.7 / 11.4 | 0.66× | 0.75× |
| `text-paragraph-small` | text-paragraph | 0.35 / 0.46 | 0.51 / 0.70 | 0.52 / 0.76 | 0.92 / 1.36 | 0.91 / 1.24 | 0.56× | 0.67× | 0.80 / 1.15 | 0.93 / 1.19 | 1.04 / 1.23 | 1.83 / 2.43 | 2.07 / 2.32 | 0.51× | 0.77× |
| `text-long-wrap` | text-paragraph | 1.42 / 1.73 | 1.61 / 2.17 | 2.13 / 2.39 | 2.47 / 2.89 | 2.90 / 3.58 | 0.65× | 0.67× | 3.06 / 3.50 | 2.97 / 4.18 | 4.15 / 5.30 | 5.35 / 5.91 | 10.6 / 12.1 | 0.56× | 0.74× |
| `fonts-weights-italic` | fonts | 1.67 / 2.83 | 1.78 / 2.48 | 2.28 / 2.70 | 3.15 / 3.81 | 3.71 / 4.36 | 0.56× | 0.73× | 4.16 / 4.42 | 4.15 / 4.78 | 5.28 / 5.73 | 5.85 / 6.34 | 10.3 / 11.1 | 0.71× | 0.79× |
| `fonts-mixed-inline` | fonts | 1.60 / 2.11 | 1.80 / 2.58 | 2.16 / 2.63 | 2.64 / 3.49 | 3.14 / 3.66 | 0.68× | 0.74× | 3.02 / 4.67 | 2.96 / 3.94 | 3.93 / 5.38 | 5.12 / 5.76 | 8.97 / 10.7 | 0.58× | 0.77× |
| `text-vietnamese` | text-i18n | 1.48 / 1.74 | 1.63 / 2.10 | 2.12 / 2.53 | 2.58 / 3.36 | 3.29 / 3.56 | 0.63× | 0.70× | 2.97 / 3.49 | 3.02 / 3.54 | 3.84 / 4.36 | 4.82 / 5.37 | 8.25 / 10.1 | 0.63× | 0.77× |
| `text-accented-latin` | text-i18n | 1.44 / 1.65 | 1.59 / 2.32 | 2.10 / 2.53 | 2.56 / 3.38 | 2.92 / 3.38 | 0.62× | 0.69× | 2.97 / 3.24 | 3.07 / 3.41 | 3.76 / 4.18 | 4.84 / 5.30 | 7.98 / 8.71 | 0.63× | 0.79× |
| `text-ellipsis-nowrap` | text-truncation | 1.26 / 1.59 | 1.66 / 2.13 | 1.96 / 2.40 | 2.39 / 3.17 | 2.66 / 3.36 | 0.69× | 0.64× | 1.97 / 2.86 | 1.92 / 2.43 | 2.56 / 3.60 | 4.54 / 4.84 | 7.25 / 8.22 | 0.42× | 0.77× |
| `text-lineclamp` | text-truncation | 1.64 / 2.01 | 1.63 / 1.99 | 2.52 / 3.26 | 3.31 / 4.67 | 3.84 / 5.16 | 0.49× | 0.65× | 2.44 / 2.82 | 2.48 / 3.28 | 3.67 / 5.24 | 5.65 / 6.64 | 8.68 / 9.55 | 0.44× | 0.67× |
| `text-lineclamp-small` | text-truncation | 0.29 / 0.40 | 0.38 / 0.65 | 0.44 / 0.72 | 0.84 / 1.27 | 0.89 / 1.29 | 0.46× | 0.65× | 0.47 / 0.70 | 0.56 / 0.70 | 0.65 / 0.79 | 1.33 / 1.72 | 1.63 / 1.99 | 0.42× | 0.73× |
| `img-png-fit` | images | 1.77 / 2.04 | 2.08 / 3.47 | 2.68 / 3.17 | 6.68 / 7.30 | 6.70 / 7.39 | 0.31× | 0.66× | 11.6 / 13.5 | 11.8 / 13.6 | 16.8 / 17.6 | 11.7 / 12.8 | 34.2 / 36.3 | 1.01× | 0.69× |
| `img-jpeg-fit` | images | 1.87 / 2.14 | 2.14 / 2.91 | 2.80 / 3.38 | 22.8 / 24.3 | 20.2 / 21.2 | 0.09× | 0.67× | 19.2 / 22.0 | 20.0 / 21.9 | 26.6 / 28.5 | 28.3 / 30.9 | 52.8 / 59.2 | 0.71× | 0.72× |
| `img-intrinsic-size` | images | 0.22 / 0.37 | 0.42 / 1.19 | 0.42 / 0.66 | 0.67 / 1.01 | 0.70 / 1.02 | 0.63× | 0.53× | 1.88 / 2.05 | 1.99 / 2.18 | 2.76 / 3.05 | 1.96 / 2.50 | 5.37 / 6.14 | 1.02× | 0.68× |
| `img-radius-clip` | images | 2.63 / 3.10 | 3.01 / 3.98 | 4.47 / 4.96 | 5.31 / 6.93 | 7.97 / 8.45 | 0.57× | 0.59× | 15.5 / 18.2 | 15.7 / 18.1 | 22.3 / 24.3 | 10.5 / 12.3 | 34.6 / 44.0 | 1.50× | 0.70× |
| `img-photo-bg` | images | 1.66 / 2.38 | 1.76 / 2.56 | 2.38 / 2.77 | 4.59 / 5.97 | 6.83 / 7.32 | 0.38× | 0.70× | 30.0 / 32.4 | 30.5 / 33.2 | 40.5 / 46.0 | 14.2 / 14.9 | 53.8 / 58.9 | 2.16× | 0.74× |
| `grid-fixed-fr` | grid | 1.52 / 1.84 | 1.82 / 2.98 | 2.48 / 3.00 | 2.63 / 3.69 | 2.64 / 4.15 | 0.69× | 0.61× | 2.20 / 2.45 | 2.16 / 2.87 | 3.08 / 3.92 | 4.54 / 5.04 | 7.22 / 7.92 | 0.47× | 0.72× |
| `grid-repeat-gap` | grid | 1.76 / 2.01 | 1.86 / 2.82 | 2.71 / 3.18 | 2.78 / 3.49 | 2.80 / 3.36 | 0.67× | 0.65× | 2.80 / 4.76 | 2.79 / 4.60 | 4.04 / 6.62 | 5.75 / 6.83 | 12.2 / 15.2 | 0.49× | 0.69× |
| `grid-spans` | grid | 1.58 / 2.30 | 1.75 / 2.97 | 2.35 / 3.21 | 2.38 / 3.39 | 2.60 / 3.52 | 0.74× | 0.67× | 2.17 / 2.60 | 2.22 / 2.53 | 2.93 / 3.40 | 4.86 / 5.55 | 7.89 / 8.48 | 0.46× | 0.74× |
| `grid-small-mixed` | grid | 0.44 / 0.65 | 0.62 / 1.08 | 0.67 / 0.93 | 1.13 / 1.51 | 1.11 / 1.76 | 0.55× | 0.66× | 0.69 / 0.86 | 0.82 / 1.08 | 0.98 / 1.23 | 1.65 / 2.05 | 1.99 / 2.51 | 0.49× | 0.70× |
| `card-og` | og-card | 2.56 / 2.95 | 2.70 / 3.11 | 3.92 / 4.54 | 5.29 / 6.02 | 6.15 / 6.96 | 0.51× | 0.65× | 10.3 / 12.8 | 10.6 / 12.7 | 14.4 / 15.6 | 9.08 / 9.94 | 21.7 / 22.6 | 1.17× | 0.72× |
| `card-og-small` | og-card | 0.99 / 1.18 | 1.19 / 1.29 | 1.65 / 2.19 | 2.99 / 3.92 | 3.16 / 3.40 | 0.40× | 0.60× | 4.12 / 4.80 | 4.32 / 4.69 | 5.70 / 6.71 | 4.67 / 5.14 | 8.49 / 9.56 | 0.92× | 0.72× |
| `card-blog` | blog-card | 5.67 / 6.88 | 6.14 / 7.20 | 9.68 / 10.4 | 8.51 / 10.1 | 16.0 / 17.4 | 0.72× | 0.59× | 19.8 / 20.8 | 20.2 / 22.1 | 28.6 / 31.2 | 14.4 / 17.8 | 48.8 / 53.9 | 1.40× | 0.69× |
| `card-flat-ui` | blog-card | 3.08 / 4.06 | 3.30 / 4.03 | 4.93 / 5.35 | 4.81 / 5.49 | 7.36 / 7.77 | 0.69× | 0.63× | 5.99 / 7.78 | 6.20 / 8.77 | 8.84 / 10.6 | 8.06 / 11.8 | 21.0 / 21.7 | 0.77× | 0.68× |
| `stress-600-boxes` | stress | 6.86 / 8.98 | 7.25 / 9.64 | 10.2 / 10.9 | 8.97 / 12.6 | 9.83 / 13.3 | 0.81× | 0.68× | 8.76 / 11.2 | 9.20 / 11.2 | 12.9 / 15.1 | 11.2 / 12.5 | 16.3 / 17.8 | 0.82× | 0.68× |
| `stress-200-labels` | stress | 5.72 / 6.89 | 6.07 / 8.71 | 9.46 / 9.80 | 15.1 / 20.0 | 15.9 / 18.7 | 0.40× | 0.60× | 9.84 / 10.3 | 9.99 / 10.7 | 14.4 / 15.4 | 17.6 / 22.6 | 23.5 / 26.2 | 0.57× | 0.68× |
| `stress-3000x2000-card` | stress | 15.1 / 17.0 | 15.4 / 17.2 | 23.8 / 25.0 | 26.2 / 28.6 | 31.2 / 33.4 | 0.59× | 0.63× | 55.5 / 65.6 | 56.3 / 66.2 | 75.7 / 80.9 | 44.2 / 48.1 | 132 / 149 | 1.27× | 0.73× |
| `fx-text-shadow` | text-shadow | 0.61 / 1.13 | 0.79 / 1.16 | 1.06 / 1.61 | 1.16 / 1.53 | 1.36 / 1.77 | 0.68× | 0.58× | 2.69 / 2.86 | 2.93 / 3.30 | 3.76 / 4.04 | 2.40 / 3.01 | 4.50 / 4.75 | 1.22× | 0.71× |
| `gap-dashed-dotted-border` | known-gaps | 0.72 / 0.94 | 0.86 / 1.22 | 1.16 / 1.42 | 1.45 / 2.62 | 2.09 / 3.03 | 0.59× | 0.62× | 0.84 / 1.34 | 1.03 / 1.34 | 1.31 / 1.69 | 1.89 / 2.43 | 2.71 / 3.25 | 0.54× | 0.64× |
| `fx-filter-blur-grayscale` | filter | 0.69 / 0.94 | 0.83 / 1.26 | 1.30 / 2.27 | 1.56 / 1.85 | 2.00 / 2.90 | 0.53× | 0.53× | 1.83 / 1.99 | 1.94 / 2.09 | 2.88 / 3.14 | 2.38 / 2.88 | 4.93 / 5.32 | 0.81× | 0.63× |
| `gap-tailwind-tw` | known-gaps | 0.32 / 0.49 | 0.46 / 0.74 | 0.48 / 0.70 | 0.77 / 1.11 | 0.71 / 0.97 | 0.60× | 0.67× | 0.53 / 0.73 | 0.69 / 1.60 | 0.72 / 1.12 | 1.37 / 1.91 | 1.62 / 2.33 | 0.50× | 0.73× |
| `gap-oklch-color` | known-gaps | 0.23 / 0.40 | 0.35 / 0.75 | 0.33 / 0.50 | 0.53 / 0.92 | 0.47 / 0.81 | 0.67× | 0.69× | 0.24 / 0.37 | 0.35 / 0.50 | 0.31 / 0.45 | 1.02 / 1.36 | 1.33 / 1.67 | 0.34× | 0.78× |
| `gap-svg-image` | known-gaps | 0.20 / 0.33 | 0.33 / 0.59 | 0.34 / 0.61 | 0.54 / 0.91 | 0.51 / 0.85 | 0.62× | 0.60× | 0.45 / 0.62 | 0.56 / 0.76 | 0.62 / 0.76 | 0.99 / 1.35 | 1.33 / 1.83 | 0.56× | 0.73× |
| `gap-inline-box-decoration` | known-gaps | 0.31 / 0.43 | 0.44 / 0.74 | 0.43 / 0.72 | 0.90 / 1.30 | 0.85 / 1.37 | 0.49× | 0.72× | 0.71 / 1.00 | 0.85 / 1.03 | 0.94 / 1.46 | 1.59 / 1.85 | 1.97 / 2.76 | 0.54× | 0.76× |
| `gap-mix-blend-mode` | known-gaps | 0.42 / 0.58 | 0.49 / 0.87 | 0.59 / 0.95 | 0.78 / 1.14 | 1.05 / 1.49 | 0.62× | 0.71× | 0.58 / 0.71 | 0.69 / 0.91 | 0.79 / 1.14 | 1.26 / 1.56 | 1.81 / 2.26 | 0.55× | 0.74× |
| `gap-clip-path` | known-gaps | 0.47 / 0.72 | 0.61 / 0.93 | 0.70 / 0.92 | 0.81 / 1.13 | 0.97 / 1.25 | 0.76× | 0.68× | 1.11 / 1.19 | 1.27 / 1.74 | 1.54 / 1.78 | 1.84 / 2.19 | 6.41 / 6.63 | 0.69× | 0.72× |
| `gap-background-clip-text` | known-gaps | 0.40 / 0.57 | 0.56 / 0.79 | 0.56 / 0.83 | 2.04 / 2.41 | 2.17 / 2.57 | 0.28× | 0.72× | 1.11 / 1.29 | 1.24 / 1.35 | 1.47 / 1.64 | 2.97 / 3.46 | 5.42 / 5.82 | 0.42× | 0.75× |
| `gap-text-wrap-balance` | known-gaps | 0.25 / 0.47 | 0.38 / 0.57 | 0.43 / 0.62 | 0.80 / 1.16 | 0.81 / 1.55 | 0.48× | 0.59× | 0.67 / 0.94 | 0.77 / 1.11 | 0.85 / 1.11 | 1.43 / 1.84 | 1.91 / 2.16 | 0.54× | 0.79× |
| `pfx-aa-shapes` | aa-exact | 0.32 / 0.54 | 0.51 / 0.97 | 0.52 / 0.93 | 0.73 / 0.97 | 0.74 / 1.39 | 0.70× | 0.62× | 0.58 / 0.79 | 0.75 / 1.12 | 0.81 / 1.10 | 1.24 / 1.94 | 1.61 / 2.11 | 0.61× | 0.71× |
| `pfx-aa-text` | aa-exact | 0.36 / 0.52 | 0.53 / 0.69 | 0.53 / 0.77 | 1.10 / 1.48 | 1.09 / 1.55 | 0.48× | 0.69× | 0.82 / 0.96 | 0.96 / 1.25 | 1.07 / 1.58 | 1.91 / 2.72 | 2.21 / 2.70 | 0.50× | 0.76× |
| `pfx-border-dashed` | dashed-border | 0.83 / 1.12 | 0.99 / 1.28 | 1.42 / 2.24 | 1.62 / 2.36 | 2.64 / 3.37 | 0.61× | 0.58× | 1.11 / 1.42 | 1.28 / 1.45 | 1.71 / 1.91 | 2.20 / 2.90 | 3.37 / 3.77 | 0.58× | 0.65× |
| `pfx-border-dotted` | dotted-border | 0.93 / 1.37 | 1.09 / 1.57 | 1.68 / 2.13 | 1.97 / 2.70 | 3.06 / 4.53 | 0.55× | 0.56× | 1.22 / 1.37 | 1.37 / 1.73 | 1.89 / 2.76 | 2.47 / 3.13 | 3.92 / 4.52 | 0.56× | 0.64× |
| `pfx-border-double-3d` | double-3d-border | 0.36 / 0.65 | 0.53 / 0.88 | 0.62 / 0.88 | 0.79 / 1.19 | 0.83 / 1.29 | 0.67× | 0.58× | 0.53 / 0.62 | 0.68 / 0.88 | 0.79 / 1.06 | 1.21 / 1.66 | 1.50 / 1.73 | 0.56× | 0.67× |
| `pfx-border-mixed` | mixed-border | 0.52 / 0.71 | 0.68 / 1.34 | 0.82 / 1.05 | 0.98 / 1.28 | 1.30 / 1.60 | 0.70× | 0.64× | 0.77 / 0.93 | 0.91 / 1.27 | 1.08 / 1.22 | 1.58 / 2.13 | 2.16 / 2.62 | 0.57× | 0.72× |
| `pfx-outline` | outline | 0.54 / 0.66 | 0.72 / 1.03 | 0.91 / 1.62 | 1.22 / 1.63 | 1.76 / 2.19 | 0.59× | 0.60× | 0.83 / 1.09 | 0.99 / 1.22 | 1.21 / 1.44 | 1.89 / 2.43 | 2.74 / 3.08 | 0.52× | 0.69× |
| `pfx-clip-path-shapes` | clip-path | 0.48 / 0.82 | 0.67 / 0.97 | 0.80 / 1.28 | 0.99 / 1.54 | 1.16 / 1.61 | 0.68× | 0.60× | 1.49 / 1.95 | 1.57 / 1.79 | 2.07 / 2.62 | 2.03 / 2.46 | 5.86 / 6.62 | 0.77× | 0.72× |
| `pfx-mask-gradient` | mask | 0.79 / 0.87 | 1.00 / 1.49 | 1.27 / 1.70 | 1.71 / 2.24 | 1.89 / 2.06 | 0.58× | 0.62× | 1.68 / 1.79 | 1.82 / 2.32 | 2.39 / 2.65 | 2.74 / 3.19 | 6.52 / 7.29 | 0.66× | 0.70× |
| `pfx-bg-clip-text` | bg-clip-text | 0.42 / 0.54 | 0.52 / 0.82 | 0.61 / 0.92 | 2.75 / 3.26 | 3.05 / 3.30 | 0.19× | 0.69× | 1.63 / 1.90 | 1.76 / 1.89 | 2.19 / 2.46 | 3.75 / 4.29 | 5.48 / 5.83 | 0.47× | 0.74× |
| `pfx-mix-blend` | mix-blend | 0.71 / 0.85 | 0.89 / 1.38 | 1.28 / 1.73 | 1.48 / 1.97 | 2.17 / 2.37 | 0.60× | 0.56× | 2.77 / 2.94 | 3.00 / 3.41 | 4.04 / 4.46 | 2.91 / 3.58 | 7.49 / 8.01 | 1.03× | 0.69× |
| `pfx-bg-blend` | bg-blend | 0.81 / 1.21 | 0.96 / 1.07 | 1.16 / 1.61 | 4.92 / 5.86 | 4.51 / 5.19 | 0.19× | 0.69× | 3.08 / 3.80 | 3.29 / 3.49 | 4.22 / 4.55 | 6.38 / 6.99 | 9.96 / 11.3 | 0.52× | 0.73× |
| `pfx-drop-shadow` | drop-shadow | 0.93 / 1.28 | 1.01 / 1.22 | 1.39 / 2.09 | 1.53 / 1.90 | 1.94 / 2.48 | 0.66× | 0.67× | 2.29 / 2.81 | 2.43 / 2.62 | 3.34 / 3.70 | 2.63 / 3.08 | 7.13 / 8.61 | 0.92× | 0.68× |
| `pfx-backdrop-filter` | backdrop-filter | 1.33 / 1.56 | 1.45 / 1.80 | 2.55 / 2.73 | 2.53 / 2.73 | 4.56 / 5.01 | 0.57× | 0.52× | 2.18 / 2.44 | 2.31 / 2.71 | 3.67 / 4.09 | 3.62 / 4.43 | 7.30 / 8.04 | 0.64× | 0.59× |
| `pfx-text-stroke` | text-stroke | 0.88 / 1.19 | 1.00 / 1.32 | 1.40 / 1.70 | 1.08 / 1.60 | 1.19 / 1.70 | 0.93× | 0.62× | 1.32 / 1.50 | 1.48 / 1.72 | 1.94 / 2.65 | 1.98 / 2.45 | 2.44 / 3.28 | 0.75× | 0.68× |
| `pfx-text-decoration` | text-decoration | 1.16 / 1.33 | 1.25 / 1.70 | 1.99 / 2.66 | 1.76 / 2.33 | 2.17 / 2.81 | 0.71× | 0.59× | 1.96 / 2.16 | 2.06 / 2.30 | 2.82 / 3.07 | 2.76 / 3.56 | 3.87 / 4.61 | 0.75× | 0.70× |
| `pfx-visibility` | visibility | 0.27 / 0.37 | 0.39 / 0.64 | 0.39 / 0.56 | 0.72 / 1.10 | 0.67 / 1.02 | 0.54× | 0.68× | 0.30 / 0.39 | 0.44 / 0.72 | 0.40 / 0.63 | 1.16 / 1.31 | 1.41 / 1.83 | 0.38× | 0.76× |
| `pfx-opacity-layers` | opacity | 1.12 / 1.34 | 1.32 / 1.81 | 2.27 / 2.68 | 2.79 / 3.23 | 3.44 / 3.70 | 0.47× | 0.50× | 2.36 / 2.55 | 2.61 / 2.91 | 4.08 / 4.29 | 3.99 / 4.54 | 7.29 / 9.22 | 0.65× | 0.58× |
| `pfx-svg-background` | svg-image | 0.64 / 1.00 | 0.83 / 1.21 | 1.34 / 2.13 | 0.86 / 1.39 | 1.09 / 1.74 | 0.96× | 0.48× | 1.14 / 1.28 | 1.28 / 1.43 | 1.83 / 2.13 | 1.75 / 2.02 | 2.46 / 2.81 | 0.73× | 0.62× |
| `pfx-inline-boxes-many` | inline-box | 1.31 / 1.52 | 1.48 / 1.70 | 2.13 / 2.44 | 3.01 / 3.72 | 3.18 / 3.44 | 0.49× | 0.62× | 2.56 / 3.01 | 2.65 / 3.56 | 3.79 / 4.58 | 4.22 / 4.65 | 5.89 / 6.54 | 0.63× | 0.68× |
| `css-class-id` | css-stylesheet | 1.70 / 2.20 | 1.84 / 3.22 | 2.45 / 2.77 | 2.81 / 3.85 | 3.14 / 3.82 | 0.65× | 0.69× | 2.48 / 2.77 | 2.51 / 2.86 | 3.35 / 3.70 | 4.97 / 5.39 | 7.79 / 8.74 | 0.50× | 0.74× |
| `css-nth-child` | css-stylesheet | 0.93 / 1.24 | 1.16 / 1.44 | 1.57 / 2.02 | 1.88 / 2.76 | 2.13 / 2.94 | 0.62× | 0.59× | 1.35 / 1.75 | 1.35 / 1.96 | 1.86 / 2.77 | 3.27 / 3.85 | 4.62 / 5.37 | 0.41× | 0.72× |
| `css-media-layer` | css-stylesheet | 0.89 / 1.36 | 1.01 / 1.96 | 1.37 / 1.83 | 1.33 / 2.10 | 1.29 / 1.74 | 0.76× | 0.65× | 1.21 / 1.32 | 1.22 / 1.58 | 1.58 / 1.78 | 3.12 / 3.49 | 4.84 / 5.67 | 0.39× | 0.77× |
| `css-important-var` | css-stylesheet | 0.69 / 1.10 | 0.83 / 1.52 | 0.95 / 1.37 | 1.29 / 1.82 | 1.36 / 1.88 | 0.65× | 0.73× | 0.92 / 1.46 | 0.95 / 1.25 | 1.31 / 1.58 | 2.84 / 3.52 | 3.70 / 4.08 | 0.33× | 0.71× |
| `tw-card` | tailwind | 1.54 / 1.83 | 1.72 / 3.06 | 2.28 / 3.31 | 2.67 / 3.21 | 2.88 / 3.82 | 0.64× | 0.68× | 2.61 / 2.92 | 2.71 / 3.44 | 3.39 / 4.02 | 4.89 / 5.17 | 7.79 / 8.71 | 0.55× | 0.77× |
| `tw-responsive` | tailwind | 0.85 / 1.20 | 1.07 / 1.58 | 1.26 / 1.72 | 1.15 / 1.97 | 1.30 / 1.70 | 0.92× | 0.67× | 1.02 / 1.28 | 1.01 / 1.34 | 1.35 / 1.51 | 2.71 / 2.92 | 3.87 / 4.59 | 0.37× | 0.76× |
| `tw-structural` | tailwind | 0.84 / 1.18 | 1.07 / 1.67 | 1.32 / 1.68 | 1.24 / 2.21 | 1.19 / 1.66 | 0.86× | 0.64× | 1.05 / 1.22 | 1.13 / 1.49 | 1.40 / 1.64 | 2.46 / 2.89 | 3.35 / 4.12 | 0.46× | 0.75× |
| `tw-arbitrary` | tailwind | 1.60 / 1.88 | 1.76 / 2.42 | 2.75 / 3.11 | 3.92 / 4.61 | 5.63 / 6.56 | 0.45× | 0.58× | 2.47 / 3.33 | 2.37 / 2.78 | 4.06 / 5.11 | 5.76 / 7.71 | 9.68 / 11.9 | 0.41× | 0.61× |
| `html-article` | html | 1.13 / 1.44 | 1.32 / 2.12 | 1.77 / 2.08 | 2.08 / 2.73 | 2.16 / 2.66 | 0.63× | 0.64× | 1.81 / 2.06 | 1.84 / 2.21 | 2.39 / 2.98 | 3.87 / 4.53 | 5.88 / 6.84 | 0.48× | 0.76× |
| `html-document` | html | 0.55 / 0.83 | 0.71 / 1.53 | 0.81 / 1.02 | 1.16 / 1.50 | 1.17 / 1.74 | 0.61× | 0.68× | 0.94 / 1.45 | 0.93 / 1.14 | 1.18 / 1.52 | 2.29 / 2.76 | 2.88 / 3.56 | 0.41× | 0.80× |
| `html-flex-card` | html | 1.40 / 1.69 | 1.61 / 2.27 | 2.22 / 2.77 | 3.08 / 3.54 | 3.83 / 4.62 | 0.52× | 0.63× | 4.87 / 6.11 | 5.02 / 5.31 | 6.80 / 7.50 | 5.32 / 5.79 | 11.8 / 13.3 | 0.94× | 0.72× |
| `html-inline` | html | 0.65 / 0.87 | 0.76 / 1.36 | 0.92 / 1.12 | 1.41 / 1.90 | 1.52 / 2.02 | 0.54× | 0.70× | 1.13 / 1.60 | 1.26 / 1.65 | 1.50 / 2.07 | 2.63 / 3.54 | 3.25 / 3.57 | 0.48× | 0.75× |
| `pseudo-inline` | pseudo-elements | 0.62 / 0.80 | 0.72 / 1.07 | 0.82 / 1.21 | 1.34 / 2.16 | 1.45 / 2.05 | 0.54× | 0.75× | 0.88 / 1.26 | 0.96 / 1.42 | 1.13 / 1.58 | 1.99 / 2.43 | 2.86 / 4.08 | 0.48× | 0.78× |
| `pseudo-block` | pseudo-elements | 0.71 / 0.93 | 0.93 / 1.61 | 1.00 / 1.55 | 1.50 / 2.04 | 1.53 / 1.98 | 0.62× | 0.71× | 0.97 / 1.14 | 1.02 / 1.24 | 1.34 / 1.76 | 2.61 / 2.89 | 3.36 / 3.60 | 0.39× | 0.73× |
| `pseudo-attr` | pseudo-elements | 0.49 / 0.73 | 0.61 / 1.02 | 0.73 / 1.11 | 1.09 / 1.72 | 1.15 / 1.57 | 0.56× | 0.67× | 0.63 / 0.77 | 0.74 / 0.91 | 0.84 / 0.98 | 1.81 / 2.31 | 2.31 / 2.73 | 0.41× | 0.75× |
| `pseudo-tw` | pseudo-elements | 0.50 / 0.91 | 0.71 / 1.56 | 0.84 / 1.36 | 1.03 / 1.52 | 1.11 / 1.59 | 0.69× | 0.60× | 0.81 / 1.03 | 0.91 / 1.29 | 1.09 / 1.31 | 1.78 / 2.32 | 2.62 / 3.12 | 0.51× | 0.74× |
| `anim-opacity-t0` | animation | 0.14 / 0.25 | 0.27 / 0.42 | 0.22 / 0.33 | 0.43 / 0.63 | 0.35 / 0.56 | 0.63× | 0.63× | 0.18 / 0.36 | 0.29 / 0.46 | 0.25 / 0.33 | 0.63 / 0.83 | 0.72 / 1.07 | 0.46× | 0.74× |
| `anim-opacity-t250` | animation | 0.20 / 0.32 | 0.34 / 0.52 | 0.30 / 0.50 | 0.58 / 0.85 | 0.56 / 0.83 | 0.59× | 0.68× | 0.23 / 0.32 | 0.34 / 0.58 | 0.30 / 0.52 | 0.83 / 1.09 | 0.99 / 1.23 | 0.41× | 0.76× |
| `anim-opacity-t500` | animation | 0.16 / 0.26 | 0.29 / 0.44 | 0.25 / 0.43 | 0.52 / 0.70 | 0.53 / 0.86 | 0.56× | 0.63× | 0.23 / 0.32 | 0.33 / 0.50 | 0.29 / 0.40 | 0.79 / 1.24 | 1.00 / 1.26 | 0.42× | 0.78× |
| `anim-opacity-t900` | animation | 0.20 / 0.33 | 0.32 / 0.45 | 0.30 / 0.46 | 0.56 / 0.78 | 0.54 / 0.76 | 0.57× | 0.67× | 0.22 / 0.27 | 0.32 / 0.52 | 0.29 / 0.36 | 0.80 / 1.02 | 0.99 / 1.31 | 0.40× | 0.76× |
| `anim-opacity-t1500` | animation | 0.13 / 0.25 | 0.27 / 0.44 | 0.21 / 0.38 | 0.44 / 0.60 | 0.35 / 0.65 | 0.61× | 0.61× | 0.19 / 0.36 | 0.30 / 0.50 | 0.26 / 0.45 | 0.74 / 0.95 | 0.85 / 1.05 | 0.40× | 0.75× |
| `anim-transform-t0` | animation | 0.20 / 0.32 | 0.33 / 0.53 | 0.30 / 0.44 | 0.50 / 0.68 | 0.41 / 0.68 | 0.66× | 0.67× | 0.27 / 0.38 | 0.41 / 0.54 | 0.38 / 0.47 | 0.79 / 0.93 | 0.86 / 1.04 | 0.52× | 0.71× |
| `anim-transform-t200` | animation | 0.21 / 0.32 | 0.33 / 0.58 | 0.32 / 0.49 | 0.52 / 0.75 | 0.42 / 0.67 | 0.64× | 0.66× | 0.31 / 0.37 | 0.45 / 0.69 | 0.42 / 0.70 | 0.83 / 1.07 | 0.87 / 1.10 | 0.55× | 0.74× |
| `anim-transform-t400` | animation | 0.17 / 0.32 | 0.31 / 0.48 | 0.28 / 0.47 | 0.50 / 0.95 | 0.40 / 0.74 | 0.62× | 0.61× | 0.31 / 0.41 | 0.45 / 0.73 | 0.42 / 0.60 | 0.82 / 1.10 | 0.88 / 1.12 | 0.55× | 0.73× |
| `anim-transform-t600` | animation | 0.17 / 0.32 | 0.30 / 0.52 | 0.29 / 0.55 | 0.46 / 0.68 | 0.39 / 0.62 | 0.65× | 0.61× | 0.32 / 0.51 | 0.44 / 0.58 | 0.43 / 0.60 | 0.80 / 1.06 | 0.88 / 1.17 | 0.55× | 0.74× |
| `anim-transform-t800` | animation | 0.18 / 0.33 | 0.31 / 0.50 | 0.27 / 0.39 | 0.48 / 0.72 | 0.39 / 0.67 | 0.64× | 0.67× | 0.26 / 0.42 | 0.41 / 0.52 | 0.36 / 0.45 | 0.77 / 1.08 | 0.84 / 1.03 | 0.52× | 0.73× |
| `anim-color-t0` | animation | 0.20 / 0.31 | 0.32 / 0.56 | 0.31 / 0.48 | 0.66 / 0.95 | 0.61 / 0.84 | 0.49× | 0.65× | 0.34 / 0.42 | 0.44 / 0.56 | 0.45 / 0.64 | 0.95 / 1.24 | 1.10 / 1.34 | 0.47× | 0.76× |
| `anim-color-t300` | animation | 0.20 / 0.31 | 0.31 / 0.53 | 0.31 / 0.44 | 0.63 / 1.11 | 0.60 / 0.87 | 0.49× | 0.66× | 0.34 / 0.51 | 0.45 / 0.63 | 0.45 / 0.54 | 0.96 / 1.37 | 1.10 / 1.44 | 0.47× | 0.75× |
| `anim-color-t700` | animation | 0.23 / 0.38 | 0.33 / 0.57 | 0.33 / 0.52 | 0.67 / 0.97 | 0.63 / 0.95 | 0.49× | 0.71× | 0.34 / 0.48 | 0.47 / 0.61 | 0.46 / 0.78 | 1.00 / 1.24 | 1.08 / 1.63 | 0.47× | 0.74× |
| `anim-color-t2000` | animation | 0.20 / 0.38 | 0.33 / 0.59 | 0.33 / 0.51 | 0.66 / 0.91 | 0.61 / 0.89 | 0.50× | 0.62× | 0.33 / 0.47 | 0.47 / 0.62 | 0.45 / 0.58 | 0.97 / 1.19 | 1.09 / 1.42 | 0.48× | 0.74× |
| `anim-width-t0` | animation | 0.15 / 0.29 | 0.27 / 0.42 | 0.23 / 0.41 | 0.46 / 0.62 | 0.37 / 0.62 | 0.59× | 0.63× | 0.23 / 0.32 | 0.31 / 0.43 | 0.30 / 0.47 | 0.73 / 0.96 | 0.79 / 0.98 | 0.42× | 0.76× |
| `anim-width-t100` | animation | 0.20 / 0.30 | 0.33 / 0.55 | 0.29 / 0.56 | 0.52 / 0.76 | 0.40 / 0.68 | 0.63× | 0.68× | 0.31 / 0.47 | 0.43 / 0.72 | 0.41 / 0.77 | 0.82 / 1.36 | 0.91 / 1.52 | 0.52× | 0.75× |
| `anim-width-t500` | animation | 0.23 / 0.38 | 0.37 / 0.52 | 0.37 / 0.51 | 0.54 / 0.84 | 0.44 / 0.72 | 0.69× | 0.63× | 0.38 / 0.49 | 0.47 / 0.84 | 0.53 / 0.81 | 0.85 / 1.12 | 0.97 / 1.11 | 0.55× | 0.71× |
| `anim-width-t999` | animation | 0.21 / 0.37 | 0.33 / 0.61 | 0.32 / 0.54 | 0.50 / 0.70 | 0.40 / 0.65 | 0.66× | 0.64× | 0.37 / 0.45 | 0.49 / 0.80 | 0.52 / 0.79 | 0.81 / 1.01 | 0.95 / 1.23 | 0.60× | 0.71× |
| `anim-delay-fill-t0` | animation | 0.18 / 0.33 | 0.32 / 0.54 | 0.30 / 0.50 | 0.55 / 0.85 | 0.53 / 0.82 | 0.57× | 0.60× | 0.28 / 0.43 | 0.43 / 0.63 | 0.41 / 0.58 | 0.87 / 1.24 | 1.00 / 1.27 | 0.49× | 0.70× |
| `anim-delay-fill-t750` | animation | 0.21 / 0.37 | 0.35 / 0.49 | 0.34 / 0.51 | 0.62 / 0.84 | 0.66 / 0.88 | 0.57× | 0.61× | 0.31 / 0.45 | 0.46 / 0.66 | 0.43 / 0.65 | 0.92 / 1.27 | 1.12 / 1.68 | 0.50× | 0.72× |
| `anim-delay-fill-t2000` | animation | 0.21 / 0.35 | 0.35 / 0.56 | 0.33 / 0.58 | 0.56 / 0.92 | 0.46 / 0.74 | 0.63× | 0.65× | 0.29 / 0.50 | 0.41 / 0.61 | 0.40 / 0.67 | 0.85 / 1.13 | 0.92 / 1.36 | 0.49× | 0.73× |
| `anim-alternate-t100` | animation | 0.15 / 0.25 | 0.26 / 0.49 | 0.23 / 0.42 | 0.50 / 0.71 | 0.52 / 0.84 | 0.52× | 0.66× | 0.22 / 0.28 | 0.31 / 0.59 | 0.28 / 0.37 | 0.82 / 1.18 | 0.99 / 1.17 | 0.37× | 0.77× |
| `anim-alternate-t500` | animation | 0.20 / 0.31 | 0.30 / 0.50 | 0.28 / 0.44 | 0.54 / 0.71 | 0.58 / 0.89 | 0.56× | 0.71× | 0.22 / 0.29 | 0.30 / 0.44 | 0.28 / 0.36 | 0.82 / 0.97 | 0.98 / 1.20 | 0.37× | 0.76× |
| `anim-alternate-t700` | animation | 0.15 / 0.26 | 0.27 / 0.49 | 0.24 / 0.41 | 0.52 / 0.81 | 0.54 / 0.83 | 0.52× | 0.62× | 0.22 / 0.33 | 0.29 / 0.50 | 0.28 / 0.36 | 0.78 / 1.00 | 1.01 / 1.33 | 0.37× | 0.79× |
| `anim-alternate-t1100` | animation | 0.15 / 0.30 | 0.24 / 0.40 | 0.23 / 0.41 | 0.47 / 0.77 | 0.53 / 0.82 | 0.52× | 0.64× | 0.22 / 0.34 | 0.32 / 0.51 | 0.29 / 0.45 | 0.78 / 1.05 | 1.00 / 1.26 | 0.41× | 0.76× |
| `anim-alternate-t1300` | animation | 0.20 / 0.30 | 0.31 / 0.52 | 0.28 / 0.42 | 0.51 / 0.97 | 0.41 / 0.64 | 0.61× | 0.71× | 0.21 / 0.35 | 0.32 / 0.48 | 0.27 / 0.51 | 0.73 / 1.01 | 0.78 / 1.13 | 0.44× | 0.79× |
| `anim-steps-t0` | animation | 0.16 / 0.27 | 0.30 / 0.48 | 0.26 / 0.50 | 0.49 / 0.70 | 0.39 / 0.60 | 0.62× | 0.62× | 0.23 / 0.31 | 0.32 / 0.57 | 0.32 / 0.53 | 0.74 / 1.05 | 0.85 / 1.03 | 0.44× | 0.73× |
| `anim-steps-t260` | animation | 0.15 / 0.28 | 0.29 / 0.47 | 0.26 / 0.48 | 0.48 / 0.72 | 0.38 / 0.58 | 0.62× | 0.58× | 0.23 / 0.33 | 0.33 / 0.61 | 0.31 / 0.46 | 0.79 / 1.05 | 0.82 / 1.08 | 0.42× | 0.74× |
| `anim-steps-t500` | animation | 0.16 / 0.34 | 0.29 / 0.48 | 0.26 / 0.44 | 0.47 / 0.70 | 0.40 / 0.71 | 0.61× | 0.62× | 0.23 / 0.31 | 0.36 / 0.48 | 0.32 / 0.44 | 0.77 / 1.00 | 0.86 / 1.09 | 0.47× | 0.74× |
| `anim-steps-t990` | animation | 0.16 / 0.33 | 0.30 / 0.47 | 0.27 / 0.44 | 0.50 / 0.71 | 0.40 / 0.66 | 0.59× | 0.62× | 0.24 / 0.32 | 0.37 / 0.65 | 0.32 / 0.41 | 0.76 / 1.09 | 0.84 / 1.09 | 0.49× | 0.74× |
| `anim-two-anims-t0` | animation | 0.16 / 0.29 | 0.29 / 0.43 | 0.27 / 0.45 | 0.50 / 0.79 | 0.50 / 0.70 | 0.58× | 0.58× | 0.23 / 0.30 | 0.36 / 0.56 | 0.31 / 0.42 | 0.81 / 0.91 | 0.97 / 1.17 | 0.45× | 0.75× |
| `anim-two-anims-t400` | animation | 0.24 / 0.34 | 0.37 / 0.54 | 0.35 / 0.56 | 0.72 / 1.11 | 0.84 / 1.13 | 0.52× | 0.68× | 0.28 / 0.41 | 0.43 / 0.55 | 0.38 / 0.51 | 0.98 / 1.27 | 1.28 / 1.58 | 0.43× | 0.74× |
| `anim-two-anims-t600` | animation | 0.25 / 0.43 | 0.37 / 0.61 | 0.37 / 0.58 | 0.72 / 1.08 | 0.93 / 1.40 | 0.51× | 0.69× | 0.30 / 0.41 | 0.42 / 0.71 | 0.39 / 0.55 | 0.99 / 1.34 | 1.35 / 1.61 | 0.43× | 0.77× |
| `anim-two-anims-t1200` | animation | 0.19 / 0.31 | 0.32 / 0.56 | 0.28 / 0.46 | 0.59 / 0.96 | 0.59 / 0.99 | 0.54× | 0.67× | 0.28 / 0.47 | 0.42 / 0.70 | 0.36 / 0.63 | 0.91 / 1.21 | 1.11 / 1.61 | 0.46× | 0.77× |
| `anim-inherit-t0` | animation | 0.27 / 0.40 | 0.39 / 0.59 | 0.40 / 0.62 | 0.79 / 1.11 | 0.73 / 0.94 | 0.49× | 0.68× | 0.39 / 0.47 | 0.52 / 0.70 | 0.51 / 0.68 | 1.05 / 1.29 | 1.18 / 1.61 | 0.49× | 0.76× |
| `anim-inherit-t500` | animation | 0.23 / 0.37 | 0.36 / 0.54 | 0.34 / 0.58 | 0.74 / 0.93 | 0.67 / 1.03 | 0.48× | 0.67× | 0.47 / 0.71 | 0.61 / 0.84 | 0.61 / 0.80 | 1.25 / 1.49 | 1.29 / 1.55 | 0.49× | 0.78× |
| `anim-inherit-t1000` | animation | 0.25 / 0.50 | 0.36 / 0.56 | 0.36 / 0.59 | 0.79 / 1.24 | 0.75 / 1.23 | 0.46× | 0.70× | 0.57 / 0.81 | 0.65 / 0.81 | 0.74 / 1.15 | 1.39 / 1.84 | 1.57 / 2.03 | 0.47× | 0.77× |
| `anim-tw-spin-t125` | animation | 0.15 / 0.24 | 0.29 / 0.43 | 0.24 / 0.40 | 0.53 / 0.73 | 0.54 / 0.79 | 0.54× | 0.64× | 0.24 / 0.32 | 0.35 / 0.49 | 0.31 / 0.38 | 0.85 / 1.04 | 1.01 / 1.30 | 0.41× | 0.78× |
| `anim-tw-spin-t375` | animation | 0.19 / 0.29 | 0.28 / 0.46 | 0.27 / 0.39 | 0.55 / 0.73 | 0.57 / 0.83 | 0.52× | 0.69× | 0.24 / 0.33 | 0.37 / 0.65 | 0.31 / 0.53 | 0.89 / 1.34 | 1.04 / 1.37 | 0.42× | 0.78× |
| `anim-tw-spin-t1600` | animation | 0.16 / 0.29 | 0.26 / 0.46 | 0.24 / 0.38 | 0.52 / 0.99 | 0.56 / 0.92 | 0.51× | 0.66× | 0.25 / 0.32 | 0.37 / 0.50 | 0.32 / 0.42 | 0.85 / 0.99 | 1.02 / 1.32 | 0.43× | 0.78× |
| `anim-kf-option-t0` | animation | 0.14 / 0.26 | 0.28 / 0.40 | 0.22 / 0.44 | 0.54 / 0.74 | 0.45 / 0.84 | 0.52× | 0.66× | 0.21 / 0.28 | 0.32 / 0.47 | 0.26 / 0.40 | 0.76 / 1.01 | 0.87 / 1.09 | 0.41× | 0.78× |
| `anim-kf-option-t500` | animation | 0.16 / 0.26 | 0.31 / 0.49 | 0.25 / 0.39 | 0.63 / 0.90 | 0.70 / 0.98 | 0.49× | 0.66× | 0.23 / 0.37 | 0.33 / 0.55 | 0.29 / 0.44 | 0.90 / 1.22 | 1.14 / 1.52 | 0.37× | 0.80× |
| `layout2-table-auto` | table | 0.62 / 1.10 | 0.79 / 1.55 | 1.09 / 1.59 | 1.76 / 2.40 | 1.75 / 2.05 | 0.45× | 0.57× | 1.07 / 1.24 | 1.24 / 1.39 | 1.54 / 1.66 | 2.67 / 3.19 | 3.27 / 3.49 | 0.46× | 0.69× |
| `layout2-table-spans` | table | 0.58 / 0.78 | 0.75 / 1.22 | 0.88 / 1.25 | 1.27 / 1.91 | 1.31 / 1.67 | 0.59× | 0.66× | 0.87 / 0.99 | 1.02 / 1.27 | 1.29 / 1.80 | 1.99 / 2.82 | 2.51 / 3.05 | 0.51× | 0.67× |
| `layout2-table-fixed` | table | 0.65 / 0.92 | 0.81 / 1.25 | 0.97 / 1.23 | 1.71 / 2.14 | 1.70 / 2.01 | 0.47× | 0.67× | 0.97 / 1.14 | 1.17 / 1.41 | 1.37 / 1.68 | 2.47 / 3.07 | 2.95 / 3.63 | 0.47× | 0.71× |
| `layout2-table-percent` | table | 0.39 / 0.59 | 0.58 / 1.10 | 0.66 / 0.92 | 1.10 / 1.51 | 1.11 / 1.75 | 0.53× | 0.59× | 0.59 / 0.80 | 0.69 / 1.00 | 0.82 / 1.25 | 1.54 / 1.82 | 1.88 / 2.11 | 0.45× | 0.72× |
| `layout2-table-collapse-conflicts` | table | 0.67 / 1.15 | 0.80 / 1.27 | 1.04 / 1.75 | 1.69 / 2.92 | 1.72 / 2.21 | 0.47× | 0.64× | 0.99 / 1.65 | 1.04 / 1.48 | 1.50 / 2.19 | 2.67 / 4.07 | 2.99 / 4.05 | 0.39× | 0.66× |
| `layout2-table-col-backgrounds` | table | 0.70 / 0.92 | 0.91 / 1.12 | 1.21 / 1.79 | 2.21 / 3.04 | 2.42 / 2.78 | 0.41× | 0.58× | 1.87 / 1.98 | 2.02 / 2.60 | 2.87 / 3.29 | 3.21 / 4.35 | 5.08 / 5.39 | 0.63× | 0.65× |
| `layout2-table-empty-cells` | table | 0.49 / 0.86 | 0.66 / 1.17 | 0.84 / 1.38 | 1.51 / 1.96 | 1.50 / 2.07 | 0.44× | 0.58× | 0.67 / 0.88 | 0.83 / 1.06 | 0.99 / 1.22 | 1.93 / 2.36 | 2.29 / 2.92 | 0.43× | 0.67× |
| `layout2-table-caption-bottom` | table | 0.67 / 0.99 | 0.84 / 1.22 | 1.13 / 1.70 | 1.85 / 2.51 | 1.92 / 2.78 | 0.46× | 0.59× | 1.01 / 1.15 | 1.12 / 1.30 | 1.49 / 1.79 | 2.60 / 3.25 | 3.05 / 3.35 | 0.43× | 0.68× |
| `layout2-float-image` | float | 0.37 / 0.61 | 0.57 / 1.28 | 0.66 / 1.09 | 1.05 / 1.35 | 1.05 / 1.64 | 0.55× | 0.56× | 1.73 / 2.19 | 2.00 / 2.40 | 2.61 / 2.99 | 2.21 / 2.60 | 6.01 / 6.87 | 0.90× | 0.66× |
| `layout2-float-clear` | float | 0.31 / 0.49 | 0.42 / 0.85 | 0.47 / 0.84 | 0.74 / 1.14 | 0.77 / 1.18 | 0.57× | 0.67× | 0.50 / 0.84 | 0.60 / 1.03 | 0.72 / 1.30 | 1.56 / 1.90 | 2.12 / 2.34 | 0.38× | 0.69× |
| `layout2-float-bfc` | float | 0.36 / 0.66 | 0.45 / 0.74 | 0.58 / 1.10 | 0.84 / 1.37 | 0.92 / 1.40 | 0.54× | 0.63× | 0.43 / 0.54 | 0.56 / 0.74 | 0.64 / 0.85 | 1.28 / 1.58 | 1.65 / 1.90 | 0.44× | 0.67× |
| `layout2-float-wrap` | float | 0.39 / 0.69 | 0.52 / 0.77 | 0.61 / 1.03 | 1.00 / 1.37 | 1.04 / 1.52 | 0.52× | 0.64× | 0.84 / 1.14 | 0.97 / 1.13 | 1.14 / 1.49 | 1.80 / 2.18 | 2.38 / 2.93 | 0.54× | 0.74× |
| `layout2-ib-badges` | inline-block | 0.31 / 0.49 | 0.46 / 0.61 | 0.49 / 0.66 | 0.91 / 1.27 | 0.83 / 1.08 | 0.51× | 0.64× | 0.52 / 0.67 | 0.64 / 0.77 | 0.71 / 1.10 | 1.43 / 2.28 | 1.51 / 2.37 | 0.45× | 0.73× |
| `layout2-ib-wrap` | inline-block | 0.38 / 0.60 | 0.59 / 1.28 | 0.67 / 0.95 | 1.06 / 1.61 | 1.01 / 1.28 | 0.56× | 0.57× | 0.75 / 1.12 | 0.89 / 1.13 | 1.05 / 1.40 | 1.91 / 2.31 | 2.19 / 2.82 | 0.47× | 0.72× |
| `layout2-ib-valign` | inline-block | 0.34 / 0.69 | 0.55 / 1.20 | 0.59 / 0.90 | 0.98 / 1.35 | 0.92 / 1.46 | 0.56× | 0.59× | 1.59 / 2.05 | 1.77 / 2.11 | 2.30 / 2.73 | 2.03 / 2.33 | 3.35 / 3.85 | 0.87× | 0.69× |
| `layout2-ib-json` | inline-block | 0.26 / 0.37 | 0.35 / 0.60 | 0.40 / 0.67 | 0.79 / 1.14 | 0.75 / 1.10 | 0.45× | 0.65× | 0.44 / 0.63 | 0.54 / 0.80 | 0.59 / 0.81 | 1.17 / 1.66 | 1.35 / 1.74 | 0.46× | 0.75× |
| `layout2-grid-areas` | grid-areas | 0.54 / 1.03 | 0.78 / 1.31 | 0.93 / 1.25 | 1.24 / 2.02 | 1.27 / 1.81 | 0.63× | 0.58× | 0.87 / 1.01 | 0.95 / 1.12 | 1.28 / 1.51 | 1.89 / 2.08 | 2.55 / 2.76 | 0.50× | 0.68× |
| `layout2-grid-named-lines` | grid-areas | 0.36 / 0.73 | 0.53 / 0.92 | 0.65 / 0.93 | 0.99 / 1.33 | 1.06 / 1.58 | 0.54× | 0.55× | 0.70 / 0.93 | 0.85 / 1.04 | 1.03 / 1.17 | 1.85 / 2.10 | 2.32 / 2.88 | 0.46× | 0.68× |
| `layout2-grid-areas-auto` | grid-areas | 0.31 / 0.60 | 0.50 / 0.80 | 0.56 / 0.90 | 0.95 / 1.42 | 0.96 / 1.33 | 0.52× | 0.56× | 0.60 / 0.70 | 0.74 / 0.93 | 0.88 / 1.11 | 1.56 / 2.05 | 1.97 / 2.58 | 0.48× | 0.68× |
| `layout3-float-left` | float-text | 0.45 / 0.71 | 0.59 / 0.82 | 0.67 / 1.01 | 1.05 / 1.41 | 1.07 / 1.62 | 0.56× | 0.67× | 0.90 / 1.22 | 1.00 / 1.39 | 1.24 / 1.61 | 1.89 / 2.24 | 2.49 / 3.09 | 0.53× | 0.73× |
| `layout3-float-right` | float-text | 0.38 / 0.67 | 0.52 / 1.07 | 0.67 / 1.01 | 0.97 / 1.43 | 1.03 / 1.36 | 0.54× | 0.57× | 0.86 / 1.05 | 0.99 / 1.20 | 1.20 / 1.43 | 1.93 / 2.14 | 2.43 / 2.62 | 0.51× | 0.72× |
| `layout3-float-stacked` | float-text | 0.51 / 0.80 | 0.65 / 0.90 | 0.79 / 1.23 | 1.23 / 1.48 | 1.37 / 1.87 | 0.52× | 0.64× | 1.22 / 1.66 | 1.37 / 1.67 | 1.67 / 2.09 | 2.22 / 2.64 | 3.14 / 3.34 | 0.62× | 0.73× |
| `layout3-float-tall` | float-text | 0.60 / 1.02 | 0.77 / 1.04 | 0.92 / 1.39 | 1.42 / 1.92 | 1.56 / 2.42 | 0.54× | 0.65× | 1.50 / 1.66 | 1.61 / 1.85 | 2.03 / 2.25 | 2.56 / 2.88 | 3.66 / 4.05 | 0.63× | 0.74× |
| `layout3-float-in-text` | float-text | 0.59 / 0.92 | 0.68 / 1.01 | 0.80 / 1.55 | 1.30 / 2.02 | 1.37 / 2.09 | 0.53× | 0.73× | 1.19 / 1.40 | 1.31 / 1.65 | 1.62 / 2.05 | 2.28 / 2.55 | 2.99 / 3.22 | 0.57× | 0.73× |
| `layout3-float-rtl` | float-text | 0.58 / 0.84 | 0.75 / 1.17 | 0.94 / 1.32 | 1.54 / 2.17 | 1.72 / 2.72 | 0.49× | 0.62× | 1.58 / 1.83 | 1.76 / 1.92 | 2.19 / 2.48 | 2.63 / 3.16 | 3.81 / 4.33 | 0.67× | 0.72× |
| `layout3-float-inline-box` | float-text | 0.46 / 0.70 | 0.64 / 0.90 | 0.72 / 0.96 | 1.07 / 1.40 | 1.16 / 1.47 | 0.60× | 0.64× | 0.91 / 1.05 | 1.08 / 1.25 | 1.25 / 1.94 | 2.13 / 2.71 | 2.51 / 3.67 | 0.51× | 0.73× |
| `layout3-inline-badges` | inline-flow | 0.48 / 0.80 | 0.69 / 1.23 | 0.77 / 1.34 | 1.40 / 1.84 | 1.41 / 2.05 | 0.49× | 0.62× | 1.01 / 1.43 | 1.16 / 1.39 | 1.42 / 1.79 | 2.38 / 2.91 | 2.83 / 3.23 | 0.49× | 0.71× |
| `layout3-inline-image` | inline-flow | 0.47 / 0.66 | 0.64 / 1.18 | 0.80 / 1.04 | 1.35 / 2.10 | 1.34 / 1.89 | 0.48× | 0.59× | 1.87 / 2.12 | 2.04 / 2.45 | 2.64 / 2.87 | 2.54 / 2.82 | 4.43 / 4.85 | 0.81× | 0.71× |
| `layout3-inline-flex-chip` | inline-flow | 0.59 / 0.81 | 0.81 / 1.40 | 1.01 / 1.58 | 1.79 / 2.33 | 1.79 / 2.33 | 0.46× | 0.58× | 1.71 / 2.15 | 1.86 / 2.16 | 2.44 / 2.99 | 2.84 / 3.34 | 4.63 / 4.88 | 0.66× | 0.70× |
| `layout3-inline-br` | inline-flow | 0.39 / 0.63 | 0.54 / 0.78 | 0.62 / 0.89 | 1.12 / 1.59 | 1.07 / 1.45 | 0.49× | 0.63× | 0.72 / 0.91 | 0.85 / 1.09 | 0.99 / 1.19 | 1.81 / 2.29 | 2.09 / 2.47 | 0.47× | 0.72× |
| `layout3-inline-abs` | inline-flow | 0.43 / 0.53 | 0.57 / 0.76 | 0.63 / 0.75 | 1.08 / 1.36 | 1.08 / 1.42 | 0.52× | 0.67× | 0.75 / 0.95 | 0.87 / 1.15 | 1.01 / 1.47 | 1.68 / 2.21 | 2.00 / 2.30 | 0.52× | 0.74× |
| `layout3-span-edges` | inline-box-model | 0.59 / 1.04 | 0.73 / 1.29 | 0.95 / 1.53 | 1.22 / 1.75 | 1.39 / 1.69 | 0.60× | 0.62× | 1.12 / 1.51 | 1.22 / 1.46 | 1.64 / 2.08 | 2.17 / 2.49 | 2.78 / 3.17 | 0.56× | 0.69× |
| `layout3-span-nowrap` | inline-box-model | 0.47 / 0.70 | 0.60 / 1.06 | 0.76 / 1.05 | 1.29 / 1.73 | 1.31 / 1.59 | 0.47× | 0.62× | 0.98 / 1.21 | 1.15 / 1.31 | 1.36 / 1.75 | 2.18 / 2.47 | 2.65 / 3.08 | 0.53× | 0.72× |
| `layout3-span-valign` | inline-box-model | 0.59 / 0.90 | 0.80 / 1.37 | 0.96 / 1.27 | 1.88 / 2.25 | 1.73 / 2.38 | 0.43× | 0.61× | 1.22 / 1.38 | 1.38 / 1.64 | 1.66 / 1.86 | 2.77 / 3.27 | 3.21 / 3.60 | 0.50× | 0.74× |
| `layout3-card-all` | inline-box-model | 1.36 / 1.59 | 1.61 / 2.11 | 2.04 / 2.57 | 3.19 / 3.61 | 3.44 / 4.09 | 0.51× | 0.67× | 3.92 / 4.50 | 4.18 / 5.54 | 5.50 / 7.75 | 5.05 / 5.91 | 9.25 / 12.7 | 0.83× | 0.71× |
| `fix-css-struct-text-nodes` | css-stylesheet | 0.77 / 0.94 | 0.92 / 1.34 | 1.09 / 1.59 | 1.89 / 2.71 | 1.81 / 2.58 | 0.49× | 0.71× | 0.99 / 1.46 | 1.05 / 1.46 | 1.45 / 1.90 | 2.87 / 3.48 | 3.65 / 4.47 | 0.36× | 0.68× |
| `fix-css-blank-text-dropped` | css-stylesheet | 0.35 / 0.59 | 0.49 / 0.97 | 0.54 / 0.80 | 0.93 / 1.16 | 0.87 / 1.31 | 0.53× | 0.65× | 0.47 / 0.65 | 0.59 / 0.83 | 0.63 / 0.99 | 1.28 / 1.71 | 1.53 / 2.16 | 0.46× | 0.75× |
| `fix-css-tw-structural-text` | tailwind | 0.70 / 1.08 | 0.80 / 1.12 | 0.91 / 1.52 | 1.54 / 2.23 | 1.49 / 2.22 | 0.52× | 0.76× | 0.87 / 1.23 | 0.98 / 1.12 | 1.22 / 1.48 | 1.99 / 2.56 | 2.50 / 3.01 | 0.49× | 0.72× |
| `fix-css-playground-css-demo` | css-stylesheet | 0.95 / 1.33 | 1.11 / 1.49 | 1.53 / 2.23 | 1.97 / 3.32 | 2.15 / 3.02 | 0.56× | 0.62× | 1.52 / 1.76 | 1.59 / 2.08 | 2.09 / 2.35 | 3.41 / 3.56 | 5.02 / 5.35 | 0.46× | 0.73× |
| `fix-css-transform-nested` | transform | 0.33 / 0.70 | 0.50 / 0.77 | 0.48 / 0.89 | 1.06 / 1.56 | 1.50 / 2.20 | 0.47× | 0.68× | 0.56 / 0.66 | 0.75 / 1.14 | 0.72 / 1.32 | 1.59 / 1.81 | 2.40 / 3.21 | 0.47× | 0.77× |
| `fix-css-transform-abs-text` | transform | 0.39 / 0.54 | 0.52 / 0.71 | 0.56 / 0.80 | 1.12 / 1.40 | 1.51 / 1.94 | 0.47× | 0.69× | 0.66 / 0.87 | 0.76 / 1.03 | 0.89 / 1.38 | 1.68 / 2.42 | 2.63 / 3.58 | 0.45× | 0.74× |
| `fix-css-image-rendering-pixelated` | images | 0.49 / 0.60 | 0.71 / 1.15 | 0.81 / 1.33 | 1.45 / 1.72 | 1.39 / 1.70 | 0.49× | 0.60× | 2.55 / 2.69 | 2.74 / 3.00 | 3.59 / 4.95 | 2.83 / 3.31 | 7.66 / 8.81 | 0.97× | 0.71× |
| `fix-css-image-rendering-modes` | images | 1.11 / 1.33 | 1.30 / 2.10 | 1.68 / 2.07 | 3.01 / 3.96 | 3.12 / 3.82 | 0.43× | 0.66× | 5.27 / 5.68 | 5.51 / 5.88 | 7.63 / 8.62 | 5.22 / 5.87 | 15.5 / 16.8 | 1.06× | 0.69× |
| `fix-css-tw-theme` | tailwind | 0.68 / 1.03 | 0.86 / 1.64 | 1.08 / 1.58 | 1.45 / 2.08 | 1.64 / 2.32 | 0.60× | 0.63× | 0.97 / 1.26 | 1.11 / 1.29 | 1.32 / 1.82 | 2.14 / 2.48 | 2.87 / 3.27 | 0.52× | 0.74× |
| `fix-css-tw-theme-node-vars` | tailwind | 0.25 / 0.39 | 0.38 / 0.53 | 0.39 / 0.60 | 0.57 / 0.77 | 0.53 / 0.75 | 0.67× | 0.65× | 0.37 / 0.45 | 0.51 / 0.64 | 0.50 / 0.69 | 0.94 / 1.20 | 1.05 / 1.46 | 0.54× | 0.74× |
| `fix-css-tw-animate` | tailwind | 0.49 / 0.62 | 0.66 / 1.12 | 0.73 / 0.88 | 0.96 / 1.31 | 1.20 / 1.43 | 0.69× | 0.68× | 0.63 / 0.86 | 0.76 / 0.92 | 0.87 / 1.40 | 1.32 / 1.84 | 1.71 / 2.07 | 0.57× | 0.73× |
| `fix-css-cascade-layers-tw` | css-stylesheet | 0.21 / 0.33 | 0.35 / 0.62 | 0.33 / 0.53 | 0.53 / 0.73 | 0.40 / 0.55 | 0.65× | 0.62× | 0.29 / 0.38 | 0.42 / 0.53 | 0.39 / 0.73 | 0.85 / 1.06 | 0.87 / 1.16 | 0.49× | 0.73× |
| `fix-css-anim-font-size-em-t0` | animation | 0.16 / 0.33 | 0.27 / 0.44 | 0.26 / 0.45 | 0.53 / 0.76 | 0.45 / 0.79 | 0.50× | 0.62× | 0.26 / 0.40 | 0.38 / 0.50 | 0.36 / 0.47 | 0.79 / 1.06 | 0.72 / 1.07 | 0.48× | 0.73× |
| `fix-css-anim-font-size-em-t500` | animation | 0.16 / 0.27 | 0.30 / 0.50 | 0.26 / 0.42 | 0.57 / 0.82 | 0.43 / 0.78 | 0.53× | 0.61× | 0.25 / 0.35 | 0.40 / 0.56 | 0.36 / 0.52 | 0.82 / 1.06 | 0.76 / 1.01 | 0.49× | 0.70× |
| `fix-text-overflow-string` | text-overflow | 0.32 / 0.45 | 0.50 / 0.98 | 0.55 / 0.72 | 1.42 / 1.89 | 1.28 / 2.08 | 0.35× | 0.60× | 0.65 / 0.95 | 0.81 / 0.93 | 0.88 / 1.39 | 2.22 / 2.49 | 2.28 / 2.79 | 0.37× | 0.74× |
| `fix-text-overflow-string-fallback` | text-overflow | 0.32 / 0.48 | 0.44 / 0.79 | 0.46 / 0.59 | 1.21 / 1.55 | 1.15 / 1.86 | 0.36× | 0.69× | 0.72 / 1.11 | 0.82 / 0.97 | 0.92 / 1.20 | 1.98 / 2.39 | 1.99 / 2.83 | 0.41× | 0.79× |
| `fix-text-overflow-string-rtl` | text-overflow | 0.24 / 0.34 | 0.36 / 0.57 | 0.39 / 0.56 | 1.08 / 1.36 | 1.00 / 1.45 | 0.33× | 0.63× | 0.49 / 0.61 | 0.61 / 0.79 | 0.64 / 1.19 | 1.59 / 2.16 | 1.64 / 1.98 | 0.38× | 0.77× |
| `fix-text-line-clamp-marker` | text-overflow | 0.40 / 0.56 | 0.49 / 0.68 | 0.62 / 0.84 | 1.49 / 2.28 | 1.38 / 1.89 | 0.33× | 0.64× | 0.70 / 0.91 | 0.88 / 1.19 | 0.98 / 1.15 | 2.21 / 2.59 | 2.51 / 3.19 | 0.40× | 0.72× |
| `fix-text-paint-order` | text-stroke | 0.83 / 1.28 | 0.99 / 1.36 | 1.34 / 1.89 | 0.99 / 1.54 | 1.10 / 2.04 | 1.00× | 0.62× | 1.45 / 1.71 | 1.68 / 1.95 | 2.18 / 2.59 | 1.95 / 2.46 | 2.60 / 2.87 | 0.86× | 0.67× |
| `fix-text-small-caps` | font-variant | 0.31 / 0.55 | 0.44 / 0.73 | 0.46 / 0.76 | 1.01 / 1.61 | 1.03 / 1.50 | 0.44× | 0.66× | 0.87 / 1.06 | 1.02 / 1.26 | 1.14 / 1.32 | 1.98 / 2.82 | 2.35 / 3.24 | 0.52× | 0.77× |
| `fix-text-all-small-caps` | font-variant | 0.41 / 0.74 | 0.52 / 0.82 | 0.62 / 0.88 | 1.29 / 1.88 | 1.34 / 1.81 | 0.40× | 0.66× | 1.09 / 1.26 | 1.21 / 1.46 | 1.43 / 1.68 | 2.38 / 2.77 | 3.13 / 3.45 | 0.51× | 0.76× |
| `fix-text-petite-unicase-caps` | font-variant | 0.79 / 1.10 | 0.88 / 1.78 | 1.06 / 1.54 | 1.90 / 2.38 | 2.02 / 2.88 | 0.46× | 0.75× | 1.89 / 2.05 | 1.95 / 2.29 | 2.49 / 2.70 | 3.34 / 3.80 | 5.01 / 6.80 | 0.58× | 0.76× |
| `fix-text-emoji-zwj` | emoji | 0.16 / 0.26 | 0.22 / 0.46 | 0.24 / 0.35 | 0.79 / 1.12 | 0.83 / 1.30 | 0.28× | 0.67× | 1.10 / 1.39 | 1.21 / 1.51 | 1.56 / 1.92 | 1.15 / 1.41 | 1.25 / 1.53 | 1.06× | 0.70× |
| `fix-text-emoji-flags-skin` | emoji | 0.16 / 0.25 | 0.24 / 0.42 | 0.24 / 0.47 | 0.67 / 0.89 | 0.68 / 1.11 | 0.36× | 0.65× | 0.29 / 0.41 | 0.35 / 0.67 | 0.37 / 0.55 | 0.99 / 1.38 | 1.02 / 1.43 | 0.36× | 0.79× |
| `fix-text-emoji-keycap-vs` | emoji | 0.16 / 0.26 | 0.24 / 0.34 | 0.24 / 0.39 | 0.65 / 0.99 | 0.66 / 0.88 | 0.37× | 0.64× | 0.34 / 0.60 | 0.46 / 0.89 | 0.43 / 0.69 | 0.99 / 1.37 | 1.06 / 1.53 | 0.47× | 0.80× |
| `fix-text-emoji-spacing` | emoji | 0.16 / 0.25 | 0.29 / 0.43 | 0.24 / 0.47 | 0.82 / 1.09 | 0.84 / 1.31 | 0.36× | 0.67× | 1.11 / 1.30 | 1.23 / 1.34 | 1.58 / 1.87 | 1.17 / 1.46 | 1.30 / 1.71 | 1.05× | 0.70× |
| `fix-text-emoji-wrap` | emoji | 0.14 / 0.21 | 0.26 / 0.36 | 0.22 / 0.35 | 0.72 / 0.95 | 0.76 / 1.13 | 0.36× | 0.64× | 0.50 / 0.77 | 0.61 / 0.78 | 0.67 / 0.98 | 1.04 / 1.36 | 1.18 / 1.44 | 0.58× | 0.74× |
| `fix-layout-rtl-flex` | rtl | 0.40 / 0.68 | 0.60 / 0.76 | 0.71 / 1.01 | 1.03 / 1.39 | 0.88 / 1.23 | 0.58× | 0.57× | 0.58 / 0.73 | 0.71 / 0.98 | 0.89 / 1.08 | 1.51 / 1.76 | 1.65 / 1.90 | 0.47× | 0.65× |
| `fix-layout-rtl-flex-wrap-abs` | rtl | 0.37 / 0.61 | 0.54 / 0.73 | 0.65 / 1.08 | 0.97 / 1.42 | 0.86 / 1.36 | 0.55× | 0.57× | 0.55 / 0.74 | 0.68 / 0.99 | 0.86 / 1.22 | 1.45 / 1.88 | 1.61 / 2.16 | 0.47× | 0.64× |
| `fix-layout-rtl-grid-block` | rtl | 0.48 / 0.65 | 0.64 / 0.85 | 0.78 / 1.10 | 1.13 / 1.42 | 1.11 / 1.52 | 0.56× | 0.62× | 0.66 / 1.02 | 0.80 / 1.09 | 0.96 / 1.31 | 1.73 / 2.32 | 1.82 / 2.34 | 0.46× | 0.69× |
| `fix-layout-rtl-table` | rtl | 0.76 / 1.33 | 0.97 / 1.19 | 1.32 / 1.65 | 2.75 / 3.42 | 2.62 / 3.10 | 0.35× | 0.57× | 1.25 / 1.79 | 1.34 / 2.11 | 1.80 / 2.15 | 3.62 / 3.94 | 3.89 / 5.35 | 0.37× | 0.69× |
| `fix-layout-rtl-node-dir` | rtl | 0.09 / 0.18 | 0.22 / 0.36 | 0.15 / 0.26 | 0.43 / 0.58 | 0.28 / 0.61 | 0.51× | 0.62× | 0.15 / 0.24 | 0.21 / 0.40 | 0.20 / 0.31 | 0.49 / 0.70 | 0.47 / 0.71 | 0.43× | 0.74× |
| `fix-layout-text-indent` | text-indent | 0.57 / 0.90 | 0.72 / 1.08 | 0.91 / 1.46 | 1.52 / 1.97 | 1.58 / 2.02 | 0.48× | 0.63× | 1.28 / 1.64 | 1.45 / 1.72 | 1.82 / 2.08 | 2.47 / 2.92 | 3.23 / 3.53 | 0.59× | 0.70× |
| `fix-layout-text-indent-keywords` | text-indent | 0.69 / 1.06 | 0.79 / 1.00 | 1.12 / 1.67 | 1.83 / 2.25 | 1.82 / 2.23 | 0.43× | 0.62× | 1.43 / 1.94 | 1.58 / 1.70 | 2.04 / 2.38 | 2.81 / 3.16 | 3.63 / 3.91 | 0.56× | 0.70× |
| `fix-layout-text-indent-sizing` | text-indent | 0.47 / 0.68 | 0.63 / 1.10 | 0.82 / 1.16 | 1.51 / 1.78 | 1.45 / 1.76 | 0.42× | 0.57× | 0.96 / 1.22 | 1.07 / 1.39 | 1.34 / 2.04 | 2.48 / 2.73 | 2.72 / 3.26 | 0.43× | 0.72× |
| `fix-layout-text-indent-node` | text-indent | 0.27 / 0.50 | 0.39 / 0.73 | 0.40 / 0.69 | 0.92 / 1.29 | 0.85 / 1.28 | 0.42× | 0.67× | 0.59 / 0.75 | 0.73 / 1.00 | 0.78 / 0.91 | 1.46 / 1.86 | 1.61 / 1.84 | 0.50× | 0.76× |
| `fix-layout-inline-rtl-box` | inline-bidi | 0.53 / 0.80 | 0.68 / 1.08 | 0.90 / 1.36 | 1.63 / 2.19 | 1.46 / 1.91 | 0.42× | 0.59× | 0.95 / 1.27 | 1.09 / 1.33 | 1.41 / 1.84 | 2.36 / 3.06 | 2.50 / 3.18 | 0.46× | 0.68× |
| `fix-layout-inline-bidi-fragments` | inline-bidi | 0.48 / 0.75 | 0.58 / 0.96 | 0.78 / 1.17 | 1.53 / 1.95 | 1.45 / 1.76 | 0.38× | 0.62× | 0.83 / 1.18 | 0.97 / 1.18 | 1.17 / 1.64 | 2.19 / 2.50 | 2.33 / 2.85 | 0.44× | 0.71× |
| `fix-layout-inline-bidi-wrap` | inline-bidi | 0.51 / 0.69 | 0.65 / 0.86 | 0.86 / 1.17 | 1.71 / 2.11 | 1.61 / 2.05 | 0.38× | 0.59× | 1.01 / 1.17 | 1.12 / 1.36 | 1.40 / 1.73 | 2.56 / 2.93 | 2.93 / 3.43 | 0.44× | 0.72× |
| `fix-layout-balance-inline-boxes` | text-wrap-balance | 0.63 / 0.83 | 0.79 / 1.12 | 1.09 / 1.41 | 2.10 / 2.64 | 1.89 / 2.24 | 0.38× | 0.58× | 1.18 / 1.40 | 1.27 / 1.63 | 1.73 / 1.85 | 2.91 / 3.41 | 3.31 / 3.74 | 0.44× | 0.68× |
| `fix-layout-balance-atomic` | text-wrap-balance | 0.67 / 0.86 | 0.82 / 1.09 | 1.12 / 1.49 | 2.10 / 2.62 | 1.99 / 2.25 | 0.39× | 0.60× | 1.41 / 2.01 | 1.58 / 1.84 | 2.08 / 2.28 | 3.18 / 3.80 | 3.57 / 4.96 | 0.50× | 0.68× |
| `fix-layout-balance-floats` | text-wrap-balance | 0.45 / 0.64 | 0.61 / 0.75 | 0.77 / 1.01 | 1.43 / 1.67 | 1.32 / 1.67 | 0.43× | 0.59× | 0.96 / 1.35 | 1.20 / 1.61 | 1.44 / 2.03 | 2.39 / 2.76 | 2.42 / 3.33 | 0.50× | 0.66× |
| `fix-layout-block-in-inline` | block-in-inline | 0.37 / 0.52 | 0.46 / 0.66 | 0.58 / 0.91 | 1.17 / 1.82 | 1.13 / 1.69 | 0.39× | 0.63× | 0.64 / 0.76 | 0.75 / 0.89 | 0.89 / 1.15 | 1.81 / 2.13 | 1.88 / 2.12 | 0.41× | 0.72× |
| `fix-layout-block-in-inline-nested` | block-in-inline | 0.52 / 0.75 | 0.71 / 1.29 | 0.86 / 1.31 | 1.77 / 2.10 | 1.65 / 1.90 | 0.40× | 0.61× | 1.02 / 1.11 | 1.16 / 1.45 | 1.47 / 1.69 | 2.76 / 3.03 | 3.01 / 3.33 | 0.42× | 0.69× |
| `fix-layout-block-in-inline-align` | block-in-inline | 0.43 / 0.50 | 0.58 / 0.92 | 0.67 / 0.93 | 1.40 / 1.85 | 1.38 / 1.62 | 0.41× | 0.64× | 0.77 / 0.96 | 0.90 / 1.11 | 1.11 / 1.38 | 2.18 / 2.79 | 2.45 / 2.97 | 0.41× | 0.69× |
| `fix-layout-block-in-inline-node` | block-in-inline | 0.21 / 0.33 | 0.32 / 0.44 | 0.31 / 0.45 | 0.79 / 1.17 | 0.71 / 1.03 | 0.40× | 0.69× | 0.38 / 0.59 | 0.51 / 0.70 | 0.49 / 0.70 | 1.10 / 1.31 | 1.09 / 1.46 | 0.47× | 0.78× |
| `fix-layout-float-paint-text` | float-paint-order | 0.29 / 0.39 | 0.44 / 0.53 | 0.48 / 0.67 | 0.97 / 1.23 | 0.90 / 1.18 | 0.45× | 0.60× | 0.65 / 0.76 | 0.75 / 1.01 | 0.89 / 1.20 | 1.51 / 1.86 | 1.50 / 1.90 | 0.50× | 0.73× |
| `fix-layout-float-paint-layers` | float-paint-order | 0.42 / 0.68 | 0.56 / 0.99 | 0.67 / 0.89 | 1.26 / 1.56 | 1.29 / 1.58 | 0.44× | 0.63× | 0.75 / 0.94 | 0.86 / 1.03 | 1.05 / 1.24 | 1.86 / 2.23 | 2.09 / 2.79 | 0.46× | 0.72× |
| `fix-layout-float-paint-nested` | float-paint-order | 0.39 / 0.67 | 0.54 / 0.98 | 0.62 / 0.98 | 1.24 / 1.76 | 1.15 / 1.47 | 0.44× | 0.63× | 0.70 / 0.90 | 0.81 / 1.05 | 1.02 / 1.27 | 1.84 / 2.12 | 1.90 / 2.11 | 0.44× | 0.69× |
| `fix-layout-inline-relative` | inline-relative | 0.46 / 0.67 | 0.58 / 0.73 | 0.74 / 1.21 | 1.62 / 2.06 | 1.44 / 2.08 | 0.36× | 0.63× | 0.87 / 1.09 | 1.05 / 1.50 | 1.26 / 1.61 | 2.22 / 2.54 | 2.18 / 2.58 | 0.47× | 0.69× |

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

- **PDF: không có trong các profile `core` / `standard` / `full` và không nằm trong benchmark này.** `takumi-pdf` là gói npm riêng (không thuộc `@takumi-rs/wasm`), ~43 500 dòng Rust. Sau giai đoạn đo này, bm-render đã thêm nó thành profile `pdf` riêng (`bm-render/pdf`; xem [Đầu ra PDF](en/pdf/index.md) và [bản tiếng Việt](vi/pdf/index.md)). Các con số speed / size / SSIM trong báo cáo này chỉ nói về đầu ra ảnh; đầu ra PDF chưa được benchmark về tốc độ và kích thước.
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
- bm-render: `zig build` (optimize = small, wasm32-freestanding, simd128) + `wasm-opt -Oz`.
- 87 fixture trong `bench/fixtures/` (25 nhóm tính năng), cùng một cây node, cùng 9 font TTF tĩnh (Inter, Noto Sans,
  Roboto) đăng ký giống hệt nhau vào mọi engine.
- Thời gian: median của ≥ 20 lần lặp và ≥ 300 ms sau 3 lần warm-up, các engine chạy xen kẽ theo từng ca.
  `raw` = `render(..., {format:"raw"})` (RGBA thẳng), `png` = định dạng mặc định.
- Tương đương: so buffer `raw` của bm với takumi-wasm. **identical** = 0 byte khác; **equivalent** = SSIM ≥ 0.99 và
  ≤ 0.5 % điểm ảnh vượt ngưỡng pixelmatch 0.1; **close** = SSIM ≥ 0.95 và ≤ 5 %; còn lại **different**.
  SSIM lấy giá trị thấp hơn giữa SSIM độ sáng và SSIM RGB.
- Sàn nhiễu: takumi-native so với takumi-wasm **giống hệt từng byte ở cả 87 ca**, nên mọi sai khác của bm là sai khác thật.

## Tóm tắt

| Chỉ số | takumi-wasm 2.20 | bm-render | Tỉ lệ |
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

| Ca | Định dạng | takumi-wasm | bm-render |
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
đáng kể. Lựa chọn hợp lý: dùng bm-render khi đầu vào nằm trong tập con ở trên và cần wasm nhỏ / khởi động nhanh
(edge, trình duyệt); dùng takumi khi cần độ phủ CSS.
