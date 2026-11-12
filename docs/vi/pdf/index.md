# Bắt đầu nhanh với PDF

[English](../../en/pdf/index.md) · [Tiếng Việt](index.md)

bm-engine có thể ghi file PDF. Bộ ghi PDF là bản port của `takumi-pdf`: chính engine layout đã vẽ PNG và SVG
dàn trang tài liệu, ngắt nó thành các trang rồi ghi ra dưới dạng đồ họa vector với chữ thật, bôi chọn được và
font con (subset) được nhúng. Nó cũng ghi header và footer, liên kết, bookmark, metadata, tệp đính kèm, PDF có
thẻ (tagged PDF) và PDF/A. Bộ ghi PDF chỉ có trong **profile build `pdf`** (`bm-engine/pdf`); `bm-engine` và
các điểm vào khác không cung cấp nó. Trang này nói về điểm vào, lần render đầu tiên trong Node.js và trình
duyệt, `measure` và các tùy chọn; mọi đoạn mã Node.js là các đoạn của `docs/examples/pdf.mjs` trong
repository và đã được chính file đó chạy. Cách cài package nằm ở [Bắt đầu](../getting-started.md).
[Playground](../image/playground.md) chỉ có đầu ra ảnh; chưa có playground cho PDF.

- [Cài đặt và điểm vào](#cài-đặt-và-điểm-vào)
- [Render HTML ra PDF](#render-html-ra-pdf)
- [Render cây node](#render-cây-node)
- [`measure`, `prepare` và các phương thức đồng bộ](#measure-prepare-và-các-phương-thức-đồng-bộ)
- [Các tùy chọn trong một bảng](#các-tùy-chọn-trong-một-bảng)
- [Trong trình duyệt và trên edge runtime](#trong-trình-duyệt-và-trên-edge-runtime)
- [Bước tiếp theo](#bước-tiếp-theo)

## Cài đặt và điểm vào

Đầu ra PDF nằm trong cùng gói npm với engine ảnh:

```sh
npm install bm-engine
```

| Import | Node.js | Mọi nơi khác |
|:--|:--|:--|
| `bm-engine/pdf` | addon native khi đã cài, nếu không thì binary `pdf` (`bm_engine.pdf.wasm`); khởi tạo ngay khi import | `await init()` nạp `bm_engine.pdf.wasm` nằm cạnh module, hoặc truyền binary vào: `await init(wasm)` |
| `bm-engine/pdf.wasm` | binary thô, để import asset trong bundler và import module trong Workers | giống vậy |

`bm-engine/pdf` export mọi thứ mà các entry ảnh export (`init`, `initSync`, `Renderer`, `features`, ...) và
thêm `PdfRenderer`, các hàm dùng chung `render`, `measure` và `prepare`, cùng các hàm tạo bộ đếm trang
`PageNumber`, `TotalPages` và `TargetPageNumber`. Giống các entry profile khác, nó có **module instance riêng**,
nên có thể nạp cạnh `bm-engine/full` trong cùng một process. `profile` là `"pdf"` và `features.pdf` là `true`
(mọi tính năng khác cũng bật: profile này là `full` cộng PDF).

## Render HTML ra PDF


`PdfRenderer` giữ các font đã đăng ký, nên hãy tạo một cái và dùng lại. bm-engine không kèm font nào, và một lần
render sẽ lỗi khi chữ cần một ký tự mà không font đã đăng ký nào vẽ được (xem [Font trong PDF](fonts.md)).
Nếu chưa đăng ký font nào thì không có lỗi: chữ bị bỏ khỏi trang mà không báo gì. Vì vậy hãy đăng ký font
trước:

<!-- @example pdf#setup -->
```js
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

Nguồn dạng chuỗi là HTML, như ở mọi nơi trong bm-engine. Kết quả là một `Uint8Array`:

<!-- @example pdf#html -->
```js
const bytes = await pdf.render(
  `<style>
     body { font-family: Inter; font-size: 14px; color: #0f172a; }
     h1 { font-size: 28px; }
   </style>
   <h1>Quarterly report</h1>
   <p>This page is vector text: it can be selected, searched and copied.</p>`,
);
writeFileSync("report.pdf", bytes); // A4, 10 mm margins
```

Không có tùy chọn nào thì đầu ra được chia trang: A4, lề 10 mm cả bốn phía, và nội dung không vừa một trang sẽ
chạy tiếp sang trang sau ([Phân trang](pagination.md)). Chữ trong file này được vẽ thành chữ chứ không phải
đường viền, nên trình xem có thể bôi chọn, tìm kiếm và sao chép nó, và mỗi font được cắt xuống còn các glyph mà
tài liệu dùng.

## Render cây node

Cây node là chính các object mà `Renderer` ảnh nhận (xem [Tham chiếu API](../image/api.md)). Các trường style dùng
camelCase và chữ nhận `fontFamily` của một font đã đăng ký:

<!-- @example pdf#node-tree -->
```js
const card = {
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 8, padding: 24, backgroundColor: "#f1f5f9" },
  children: [
    { type: "text", text: "Hello PDF", style: { fontFamily: "Inter", fontSize: 32, fontWeight: 700 } },
    { type: "text", text: "A node tree renders the same way as HTML.", style: { fontFamily: "Inter", fontSize: 14 } },
  ],
};
const letter = await pdf.render(card, { size: "letter", landscape: true, margin: 24 });
```

Nguồn có thể là chuỗi HTML, cây node, `{ json: "<cây node dạng văn bản JSON>" }`, hoặc handle từ `prepare()`.
Class Tailwind đặt trong trường `tw` của node hoặc thuộc tính `tw` của HTML ([HTML và Tailwind](../image/html-and-tailwind.md)).

## `measure`, `prepare` và các phương thức đồng bộ

`measure(source, options)` trả về `{ width, height }` đã dàn, tính bằng CSS px, mà không ghi PDF. Với các tùy
chọn trang, nó dàn nguồn theo cách dàn header hoặc footer: ở đủ chiều rộng trang với chiều cao không giới hạn,
cùng bộ đếm trang ba chữ số. Lề không làm đổi kết quả. Với `viewport`, nó dàn ở kích thước viewport. Đây là công
cụ để tự đo một band ([Header, footer và bộ đếm trang](headers-footers.md#lề-và-band)):

<!-- @example pdf#measure -->
```js
const { width, height } = await pdf.measure(card, { size: "a4" });
```

`renderSync` và `measureSync` làm cùng việc mà không cần await; dạng async tồn tại cho `fonts` và `images` nạp
lười. `prepare(source, options)` giải quyết font và ảnh một lần và trả về handle mà `render` và `measure` nhận;
các tùy chọn truyền cho `render` được gộp đè lên tùy chọn đã đưa cho `prepare`. Nó không tải gì cả: bm-engine
không có bước tương đương `needs` của takumi-pdf, nên byte ảnh đi qua tùy chọn `images` (`[{ src, data }]`) và
file font qua `fonts` hoặc `registerFont`. File của quy tắc `@font-face` không được tải.

<!-- @example pdf#sync -->
```js
const same = pdf.renderSync(card, { viewport: { width: 600 } });
```

Các hàm `render`, `measure` và `prepare` ở cấp module dùng một `PdfRenderer` được tạo lười mà bạn không với tới
được để đăng ký font; hãy dùng chúng cho tài liệu không có chữ hoặc có tùy chọn `fonts`, còn lại dùng
`PdfRenderer`. Gọi `free()` trên renderer không còn cần nữa (nó cũng dispose được bằng `using`).

## Các tùy chọn trong một bảng

| Tùy chọn | Trang | Ý nghĩa |
|:--|:--|:--|
| `size`, `landscape`, `margin` | [ở đây](page-size-and-viewport.md#khổ-giấy-hướng-trang-và-lề) | Hình học của trang. |
| `viewport` | [ở đây](page-size-and-viewport.md#một-trang-viewport) | Một trang có kích thước cố định. |
| `backgroundColor` | [ở đây](page-size-and-viewport.md#khổ-giấy-hướng-trang-và-lề) | Màu giấy. |
| `header`, `footer`, `pages` | [Header và footer](headers-footers.md) | Band lặp lại trên mọi trang và ghi đè theo trang. |
| `pageRanges` | [Phân trang](pagination.md#giữ-lại-một-số-trang) | Chỉ giữ một số trang. |
| `outline` | [Liên kết và bookmark](links-metadata.md#bookmark) | Bookmark từ `h1`-`h6`. |
| `metadata`, `lang` | [Metadata](links-metadata.md#metadata) | Tiêu đề, tác giả, ngày, XMP tùy biến; ngôn ngữ tài liệu. |
| `attachments` | [Tệp đính kèm](links-metadata.md#tệp-đính-kèm) | Tệp được nhúng. |
| `uncoveredText`, `fontFamilies`, `fonts` | [Font trong PDF](fonts.md) | Điều gì xảy ra với ký tự không font nào vẽ được; font stack; font cần đăng ký. |
| `tagged`, `pdfa` | [Khả năng truy cập và lưu trữ](accessibility.md) | Cây cấu trúc, PDF/UA, PDF/A. |
| `css`, `cssVariables` | [HTML và Tailwind](../image/html-and-tailwind.md) | Stylesheet và custom property của `:root` áp dụng trước khi dàn. |
| `images` | [Hình ảnh](../image/images.md) | Byte ảnh tải sẵn cho các giá trị `src`. |
| `signal` | | Một `AbortSignal` được kiểm tra trước khi render đọc và vẽ tài liệu. |

Tùy chọn không biết hoặc gõ sai tên không bị báo lỗi; giá trị sai của một tùy chọn đã biết sẽ ném lỗi có tên nó
(ví dụ `invalid margin: expected a number or "auto"`).

## Trong trình duyệt và trên edge runtime

Entry này không phụ thuộc Node.js. Trong trình duyệt, gọi `init()` một lần (nó tải binary nằm cạnh module) rồi
dùng cùng API; trong Cloudflare Worker, import binary như một module. Các đoạn dưới đây chưa được chạy ở đây (entry
Node.js dùng cùng mã):

```js
// Browser, ES modules
import { init, PdfRenderer } from "bm-engine/pdf";
await init(); // fetches bm_engine.pdf.wasm

const pdf = new PdfRenderer();
const font = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
pdf.registerFont({ name: "Inter", data: font });

const bytes = await pdf.render(`<h1 style="font-family: Inter">Hello</h1>`);
const url = URL.createObjectURL(new Blob([bytes], { type: "application/pdf" }));
window.open(url); // or set it as an <a download> / <iframe> source
```

```js
// Cloudflare Workers
import wasm from "bm-engine/pdf.wasm";
import { init, PdfRenderer } from "bm-engine/pdf";

await init(wasm);
```

Xem [Bắt đầu](../getting-started.md#edge-runtime-deno-bun) để biết chi tiết về bundler và runtime; chúng áp dụng cho
entry này theo cùng cách.

## Bước tiếp theo

| Chủ đề | Trang |
|:--|:--|
| Khổ giấy, hướng trang, lề, tài liệu một trang | [Khổ giấy, lề và viewport](page-size-and-viewport.md) |
| Nội dung qua nhiều trang, ngắt trang bắt buộc và tránh ngắt, `@page` | [Phân trang](pagination.md) |
| Header và footer lặp lại, số trang | [Header, footer và bộ đếm trang](headers-footers.md) |
| Liên kết, bookmark, metadata, tệp đính kèm | [Liên kết, bookmark, metadata và tệp đính kèm](links-metadata.md) |
| Subset font, font dự phòng, ký tự không font nào có | [Font trong PDF](fonts.md) |
| Tagged PDF, PDF/UA, PDF/A | [Khả năng truy cập và lưu trữ](accessibility.md) |
| Tài liệu hoàn chỉnh: hoá đơn, báo cáo, vé | [Công thức](recipes.md) |
| HTTP handler trong Next.js, Hono, Workers, ... | [Trả PDF từ framework](frameworks.md) |
| Addon native, WebAssembly, kích thước profile `pdf` | [Native và WebAssembly](native-and-wasm.md) |
| Mọi export, phương thức và tùy chọn | [Tham chiếu API PDF](api.md) |
| CSS làm gì trong PDF | [CSS trong PDF](css-support.md) |
| So với takumi-pdf | [Khác biệt với takumi-pdf](differences-from-takumi.md) |
