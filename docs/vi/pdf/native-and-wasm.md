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

`bm_engine.pdf.wasm` là `full` cộng bộ ghi PDF: 3 187.8 KiB thô, 1 311.8 KiB với gzip -9 và
1 015.7 KiB với brotli -11 (`bm_engine.wasm`, `full`: 1 272.7 / 631.5 / 529.1 KiB). Nó được build theo tốc độ (Zig `ReleaseFast` + `wasm-opt -O3`): các lần render đã nóng nhanh hơn 20-27 %, đổi lại khoảng 1.3 MB wasm và 30-45 MB bộ nhớ tiến trình nhiều hơn. Mã PDF chỉ được biên dịch vào binary này và vào addon native, cùng với phần dàn trang theo trang giấy và các thuộc
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

[Xem Benchmark](../benchmark.md) để đọc số đo và cách chạy lại.
