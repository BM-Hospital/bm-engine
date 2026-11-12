# Native và WebAssembly

[English](../../en/pdf/native-and-wasm.md) · [Tiếng Việt](native-and-wasm.md)

`bm-engine/pdf` chạy trên hai engine với cùng một API: addon Node-API native trên Node.js (khi gói nền tảng đã
được cài) và binary WebAssembly `bm_engine.pdf.wasm` ở mọi nơi khác, đồng thời là phương án dự phòng tự động.
Cả hai ghi ra **cùng các byte** cho cùng một đầu vào. Trang này nói về việc bạn nhận được backend nào, cách
kiểm tra và ép chọn, kích thước của binary `pdf`, và các build khác làm gì với `renderPdf`. Các đoạn mã là các
phần của `docs/examples/pdf-native-and-wasm.mjs` và `docs/examples/pdf.mjs`, và đã được chạy; phép so sánh hai
backend chạy trên Windows x64 (Node.js 26), nền tảng duy nhất có addon đã được chạy thật (xem
[Bắt đầu](../getting-started.md#native-trên-nodejs-webassembly-ở-mọi-nơi-khác)).

- [Backend native trên Node.js](#backend-native-trên-nodejs)
- [Byte giống nhau trên cả hai backend](#byte-giống-nhau-trên-cả-hai-backend)
- [Profile `pdf` và kích thước](#profile-pdf-và-kích-thước)
- [Các profile khác làm gì](#các-profile-khác-làm-gì)

## Backend native trên Node.js

Trên Node.js, Bun và Deno, `bm-engine/pdf` chạy trên addon Node-API native khi nó đã được cài (cùng addon và cùng
gói tùy chọn `bm-engine-<platform>` mà `bm-engine` dùng; không có gói thêm), nếu không thì tự động và im lặng quay
về profile wasm `pdf`. `backend` được export từ `bm-engine/pdf` là `"native"` hoặc `"wasm"`, và
`BM_ENGINE_BACKEND=wasm|native` ép dùng một trong hai. Byte PDF giống hệt nhau trên cả hai backend. Ở bản native,
các phương thức async (`PdfRenderer.render` và `measure`, `Renderer.renderPdf` và `measurePdf`) chạy trên thread
pool của libuv thay vì chặn event loop; `init()` và `initSync()` không làm gì ở đó, và `profile` vẫn là `"pdf"`.
Trong trình duyệt, bundler, Workers và runtime edge không có gì thay đổi: điểm vào là profile wasm `pdf`. Xem
[Addon native và WebAssembly](../native-vs-wasm.md).

## Byte giống nhau trên cả hai backend

`backend`, `profile` và `features` cho biết cái gì đang phục vụ điểm vào:

<!-- @example pdf-native-and-wasm#backend -->
```js
const { backend, profile, features, PdfRenderer } = await import("bm-engine/pdf");
console.log(backend, profile, features.pdf); // "native" pdf true  (or "wasm" pdf true without the addon)
```

Script ví dụ render tài liệu này một lần với `BM_ENGINE_BACKEND=wasm` và một lần với
`BM_ENGINE_BACKEND=native`, mỗi lần trong một process riêng (backend được chọn lúc import module), rồi kiểm tra
hai file có cùng SHA-256:

<!-- @example pdf-native-and-wasm#same-bytes -->
```js
const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const bytes = await pdf.render(
  `<h1 style="font-family: Inter">Same bytes</h1><p style="font-family: Inter">on every backend</p>`,
);
// no date is written unless you pass one, so the same input gives the same bytes on every run and backend
```

Trong lần chạy cho trang này, cả hai file đều dài 8 943 byte với cùng một hash. bm-engine không ghi ngày tháng
và không ghi mã định danh file ngẫu nhiên nếu bạn không truyền vào (`metadata.creationDate`, ...), nên đầu ra
cũng giống nhau giữa các lần chạy, giúp PDF dễ cache và dễ so sánh trong test.

## Profile `pdf` và kích thước

`bm_engine.pdf.wasm` là `full` cộng bộ ghi PDF: 1 555.8 KiB thô, 761.6 KiB với gzip -9 và
625.1 KiB với brotli -11, nhiều hơn `bm_engine.wasm` (`full`: 1 141.5 / 559.0 / 469.8 KiB) khoảng 0.4 MB. Mã PDF chỉ được biên dịch vào binary này và vào addon native, cùng với phần dàn trang theo trang giấy và các thuộc
tính CSS paged-media mà nó cần. (Addon native là tập tính năng `full` cộng đầu ra PDF; bản thân `bm-engine` không
bao giờ cung cấp bộ ghi PDF.) [Profile và kích thước](../profiles-and-size.md) có số liệu chính xác cho mọi binary. Tự build
bằng `npm run build:pdf` (`node scripts/build.mjs --profile=pdf`) hoặc `zig build -Dprofile=pdf`
([Build từ mã nguồn](../building-from-source.md)).

Vì mã phân trang chỉ có trong profile này, các thuộc tính CSS `break-before`, `break-after`, `break-inside`,
`page-break-*`, `orphans` và `widows`, cùng các utility Tailwind `break-before-*`, `break-inside-*` và
`break-after-*`, chỉ có tác dụng trong đầu ra PDF (`bm-engine/pdf`). Các lần render ảnh (`render`, `renderSvg`,
`measure`) chấp nhận và bỏ qua chúng trên mọi build, kể cả `bm-engine/pdf` và addon native, nên một ảnh giống nhau
trên mọi build. `background-clip: border-area` cũng theo quy tắc này.

## Các profile khác làm gì

Mọi `Renderer` đều có `renderPdf`, `renderPdfSync`, `measurePdf` và `measurePdfSync`, nhưng chỉ build `pdf` cung cấp
bộ ghi PDF. Trên mọi build khác chúng ném lỗi, kể cả `bm-engine` chạy trên addon native (binary addon có chứa bộ ghi
PDF nhưng `bm-engine` ẩn nó đi: `features.pdf` là `false`):

<!-- @example pdf#not-supported -->
```js
import { Renderer } from "bm-engine/full"; // the full profile has no PDF writer
let message;
try {
  new Renderer().renderPdfSync(card);
} catch (e) {
  message = e.message;
}
// message: bm-engine: renderPdf is not supported by this build (use the pdf build: import from "bm-engine/pdf")
```

Hãy kiểm tra `features.pdf` trước khi gọi nếu build của bạn có thể thay đổi.

Trong trình duyệt hay Worker, chỉ binary này được tải về cho đầu ra PDF: chỉ import `bm-engine/pdf` và không
import gì khác từ bm-engine, vì mỗi điểm vào khác có module instance và binary riêng
([Bắt đầu nhanh với PDF → Trong trình duyệt](index.md#trong-trình-duyệt-và-trên-edge-runtime)).

## Hiệu năng và kiểm tra

Đo bằng `node bench/pdf/bench.mjs`, so với takumi-pdf trên cùng máy và cùng đầu vào (bảng sinh từ
[results-pdf.json](../../results-pdf.json); báo cáo đầy đủ ở [Benchmark](../benchmark.md)). bm-native và bm-wasm được
so từng byte trên mọi tài liệu của bộ đo, và mọi PDF đi qua các công cụ kiểm tra bên ngoài
(`node bench/pdf/validate.mjs`) cùng phép so sánh hình ảnh với takumi-pdf (`node bench/pdf/visual.mjs`).

<!-- pdf-bench:summary -->
- **Thời gian render, bm-native so với takumi-pdf:** sync 0,30× [0,31× / 0,30× / 0,31×] (nhanh hơn ở 112/112, 0,12×–0,97×); async 0,32× [0,32× / 0,31× / 0,32×] (nhanh hơn ở 112/112, 0,12×–0,94×). Dưới 1× = bm tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ ở từng lượt.
- **bm-wasm vs takumi-pdf (cả hai là wasm):** 0,49× [0,50× / 0,49× / 0,49×] (nhanh hơn ở 107/112, 0,20×–1,36×). **bm-native vs bm-wasm (sync):** 0,62× [0,61× / 0,61× / 0,62×] (nhanh hơn ở 112/112, 0,38×–0,77×).
- **Trang mỗi giây ở 1 / 10 / 100 / 500 trang:** bm-native 284 / 206 / 28 / lỗi; bm-wasm 108 / 89 / 14 / lỗi; takumi-pdf 29 / 46 / 75 / 83.
- **Trùng byte:** bm-native == bm-wasm 113/114 tài liệu, cùng lỗi ở cả hai: 1.
- **Bộ kiểm tra:** bm-native 104/113 PDF không có lỗi hay cảnh báo nào (takumi-pdf 105/114); veraPDF bm-native 45/45, takumi-pdf 45/45; cùng chữ, liên kết, mục lục và thẻ như takumi-pdf: 101/113.
- **Kết luận hình ảnh so với takumi-pdf (tốt nhất trong các bộ raster):** identical 79, equivalent 30, different 3, close 1 (113 tài liệu, pdfium + mupdf).
- **Nhiễu:** geomean tuyệt đối lệch giữa các lượt bm-native:sync 10,1 %, bm-native:async 10,2 %, bm-wasm:sync 10,2 %, bm-wasm:async 11,6 %, takumi-pdf:async 12,9 % ⚠; hãy đọc tỉ lệ (đo xen kẽ).
<!-- /pdf-bench:summary -->

<!-- pdf-bench:cold -->
| Engine | wall median ms | p95 | hơn Node trống | import | font | PDF đầu tiên | RSS đỉnh |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Node.js trống | 55,9 | 88,6 | — | — | — | — | 45 MiB |
| bm-native | 67,7 | 106 | 11,8 | 6,80 | 0,36 | 3,10 | 50 MiB |
| bm-wasm | 162 | 209 | 106 | 9,90 | 2,56 | 58,7 | 74 MiB |
| takumi-pdf | 268 | 296 | 213 | 42,4 | 3,49 | 128 | 76 MiB |

30 lần mỗi engine, xen kẽ: khởi động Node -> import -> đăng ký Inter Regular -> hoá đơn A4 một trang -> thoát. CPU bận trong lúc đo 52 %.
<!-- /pdf-bench:cold -->

<!-- pdf-bench:eventloop -->
| Engine | API | render ms | độ trễ timer lớn nhất | p99 | số tick |
|:--|--:|--:|--:|--:|--:|
| bm-native | sync | 3.899 | 3.899 ms | 3.899 ms | 1 |
| bm-native | async | 3.765 | 15,9 ms | 1,40 ms | 3681 |
| bm-wasm | sync | 10.694 | 10.694 ms | 10.694 ms | 1 |
| bm-wasm | async | 10.366 | 10.366 ms | 10.366 ms | 1 |
| takumi-pdf | async | 1.511 | 1.511 ms | 1.511 ms | 1 |

Một lần render 100 trang trong khi một timer 1 ms chạy; độ trễ gần bằng thời gian render nghĩa là event loop bị chặn suốt lần render.
<!-- /pdf-bench:eventloop -->

<!-- pdf-bench:throughput -->
| Cấu hình | N=1 | N=2 | N=4 | N=8 |
|:--|--:|--:|--:|--:|
| bm-native seq uv=4 | 464 |  |  |  |
| bm-wasm seq | 277 |  |  |  |
| takumi-pdf seq | 129 |  |  |  |
| bm-native many k=1 uv=4 | 521 | 529 | 473 | 513 |
| bm-native many k=2 uv=4 | 503 | 976 | 925 | 738 |
| bm-native many k=4 uv=4 | 347 | 722 | 1.299 | 1.370 |
| bm-native many k=8 uv=4 | 430 | 827 | 1.380 | 1.495 |
| bm-native many k=1 uv=8 | 477 | 492 | 460 | 492 |
| bm-native many k=2 uv=8 | 485 | 798 | 941 | 914 |
| bm-native many k=4 uv=8 | 474 | 888 | 1.523 | 1.639 |
| bm-native many k=8 uv=8 | 513 | 951 | 1.684 | 2.295 |
| bm-wasm pool k=1 | 308 | 314 | 314 | 321 |
| bm-wasm pool k=2 | 297 | 620 | 638 | 630 |
| bm-wasm pool k=4 | 308 | 618 | 981 | 981 |
| bm-wasm pool k=8 | 321 | 576 | 719 | 1.154 |
| takumi-pdf pool k=1 | 107 | 129 | 127 | 139 |
| takumi-pdf pool k=2 | 122 | 293 | 283 | 297 |
| takumi-pdf pool k=4 | 123 | 282 | 404 | 497 |
| takumi-pdf pool k=8 | 129 | 288 | 510 | 635 |

Số PDF mỗi giây, docs/invoice (one-page A4 invoice, HTML + footer), closed loop: N clients each with one request in flight; 2000 ms mỗi điểm, 8 CPU logic. seq = một client với API sync (takumi-pdf: await render), many = N client trên K renderer bm-native (API async trên pool libuv, UV_THREADPOOL_SIZE = uv), pool = pool worker_threads gồm K worker, mỗi worker có engine riêng.
<!-- /pdf-bench:throughput -->
