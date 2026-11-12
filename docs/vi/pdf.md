# Đầu ra PDF

[English](../en/pdf.md) · [Tiếng Việt](pdf.md)

bm-engine có thể ghi file PDF. Bộ ghi PDF là bản port của `takumi-pdf`: chính engine layout đã vẽ PNG và SVG
dàn trang tài liệu, ngắt nó thành các trang rồi ghi ra dưới dạng đồ họa vector với chữ thật, bôi chọn được và
font con (subset) được nhúng. Nó cũng ghi header và footer, liên kết, bookmark, metadata, tệp đính kèm, PDF có
thẻ (tagged PDF) và PDF/A. Bộ ghi PDF chỉ có trong **profile build `pdf`** (`bm-engine/pdf`); các profile khác
và `bm-engine` cùng các điểm vào khác không cung cấp nó. Trang này nói về điểm vào, lần render đầu tiên trong Node.js và trình duyệt, khổ giấy và lề,
`measure`, kích thước của profile và những gì chưa được hỗ trợ. Mọi đoạn mã Node.js là các đoạn của
`docs/examples/pdf.mjs` trong repository và đã được chính file đó chạy. Các trang tiếp theo:
[Phân trang](pdf-pagination.md), [Header, footer và bộ đếm trang](pdf-headers-footers.md),
[Liên kết, bookmark, metadata và tệp đính kèm](pdf-links-metadata.md), [Font trong PDF](pdf-fonts.md) và
[Khả năng truy cập và lưu trữ](pdf-accessibility.md).

- [Cài đặt và điểm vào](#cài-đặt-và-điểm-vào)
- [Render HTML ra PDF](#render-html-ra-pdf)
- [Render cây node](#render-cây-node)
- [Khổ giấy, hướng trang và lề](#khổ-giấy-hướng-trang-và-lề)
- [Một trang: `viewport`](#một-trang-viewport)
- [`measure`, `prepare` và các phương thức đồng bộ](#measure-prepare-và-các-phương-thức-đồng-bộ)
- [Các tùy chọn trong một bảng](#các-tùy-chọn-trong-một-bảng)
- [Trong trình duyệt và trên edge runtime](#trong-trình-duyệt-và-trên-edge-runtime)
- [Profile `pdf` và kích thước](#profile-pdf-và-kích-thước)
- [Các profile khác làm gì](#các-profile-khác-làm-gì)
- [Cái gì được vẽ và cái gì không](#cái-gì-được-vẽ-và-cái-gì-không)
- [Hạn chế đã biết](#hạn-chế-đã-biết)

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

### Backend native trên Node.js

Trên Node.js, Bun và Deno, `bm-engine/pdf` chạy trên addon Node-API native khi nó đã được cài (cùng addon và cùng
gói tùy chọn `bm-engine-<platform>` mà `bm-engine` dùng; không có gói thêm), nếu không thì tự động và im lặng quay
về profile wasm `pdf`. `backend` được export từ `bm-engine/pdf` là `"native"` hoặc `"wasm"`, và
`BM_ENGINE_BACKEND=wasm|native` ép dùng một trong hai. Byte PDF giống hệt nhau trên cả hai backend. Ở bản native,
các phương thức async (`PdfRenderer.render` và `measure`, `Renderer.renderPdf` và `measurePdf`) chạy trên thread
pool của libuv thay vì chặn event loop; `init()` và `initSync()` không làm gì ở đó, và `profile` vẫn là `"pdf"`.
Trong trình duyệt, bundler, Workers và runtime edge không có gì thay đổi: điểm vào là profile wasm `pdf`. Xem
[Addon native và WebAssembly](native-vs-wasm.md).

## Render HTML ra PDF


`PdfRenderer` giữ các font đã đăng ký, nên hãy tạo một cái và dùng lại. bm-engine không kèm font nào, và một lần
render sẽ lỗi khi chữ cần một ký tự mà không font đã đăng ký nào vẽ được (xem [Font trong PDF](pdf-fonts.md)),
vì vậy hãy đăng ký font trước:

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
chạy tiếp sang trang sau ([Phân trang](pdf-pagination.md)). Chữ trong file này được vẽ thành chữ chứ không phải
đường viền, nên trình xem có thể bôi chọn, tìm kiếm và sao chép nó, và mỗi font được cắt xuống còn các glyph mà
tài liệu dùng.

## Render cây node

Cây node là chính các object mà `Renderer` ảnh nhận (xem [Tham chiếu API](api.md)). Các trường style dùng
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
Class Tailwind đặt trong trường `tw` của node hoặc thuộc tính `tw` của HTML ([HTML và Tailwind](html-and-tailwind.md)).

## Khổ giấy, hướng trang và lề

| Tùy chọn | Ý nghĩa |
|:--|:--|
| `size` | Tên khổ giấy hoặc `{ width, height }` tính bằng CSS px. Mặc định `"a4"`. |
| `landscape` | `true` đổi chỗ chiều rộng và chiều cao của trang, kể cả với `size` tường minh. |
| `margin` | Một số cho cả bốn phía, hoặc `{ top, right, bottom, left }`. Mỗi phía là số CSS px hoặc `"auto"`; phía bỏ trống là `"auto"`. Mặc định `"auto"` ở mọi phía. |
| `backgroundColor` | Màu giấy, một màu CSS bất kỳ, được vẽ dưới mọi thứ trên mọi trang. Bỏ trống thì trang để trống. |

Các tên khổ giấy là `a3`, `a4`, `a5`, `b4`, `b5`, `jis-b4`, `jis-b5`, `ledger`, `legal` và `letter`, không phân
biệt hoa thường và đều là trang đứng (`ledger` là 11 x 17 in, `letter` là 8.5 x 11 in). Trang PDF được đo bằng
point: một CSS px là 0.75 pt, nên `{ width: 400, height: 240 }` là trang 300 x 180 pt.

<!-- @example pdf#custom-size -->
```js
const ticket = await pdf.render(card, {
  size: { width: 400, height: 240 }, // CSS px: 300 x 180 pt
  margin: { top: 12, right: 12, bottom: 12, left: 12 },
  backgroundColor: "#ffffff",       // paper colour under everything
});
```

`"auto"` ở phía có header hoặc footer làm lề lớn bằng mức band cần (chiều cao band cộng 20 px, và tối thiểu
10 mm, tức 37.8 px); ở các phía khác, và ở phía không có band, nó là 10 mm. Xem [Header, footer và bộ đếm
trang](pdf-headers-footers.md#lề-và-band). `landscape` và quy tắc `@page` cũng có thể đặt khổ giấy; `@page { size: ... }`
của tài liệu thắng tùy chọn `size` ([Phân trang](pdf-pagination.md#quy-tắc-trang)).

Trang phải còn chỗ cho nội dung: khổ giấy và lề khiến chiều rộng hoặc chiều cao còn dưới 1 px sẽ ném lỗi
`Page size must be finite and larger than zero`. Tên khổ giấy không biết sẽ ném `unknown page size: <tên>`.

## Một trang: `viewport`

`viewport: { width, height? }` render toàn bộ tài liệu lên một trang duy nhất có kích thước đó (CSS px), không lề,
không header và không ngắt trang. Không có `height` thì trang cao bằng nội dung đã dàn. Đây là dạng dùng cho vé,
thẻ và áp phích. `viewport` không thể kết hợp với `size`, `landscape`, `margin`, `header`, `footer`, `pages` hay
`pageRanges`; làm vậy sẽ ném `viewport is mutually exclusive with the paged options (size, landscape, margin,
header, footer, pages, pageRanges)`.

<!-- @example pdf#viewport -->
```js
const poster = await pdf.render(card, { viewport: { width: 600 } }); // one page, as tall as the content
```

## `measure`, `prepare` và các phương thức đồng bộ

`measure(source, options)` trả về `{ width, height }` đã dàn, tính bằng CSS px, mà không ghi PDF. Với các tùy
chọn trang, nó dàn nguồn theo cách dàn header hoặc footer: ở đủ chiều rộng trang với chiều cao không giới hạn,
cùng bộ đếm trang ba chữ số. Lề không làm đổi kết quả. Với `viewport`, nó dàn ở kích thước viewport. Đây là công
cụ để tự đo một band ([Header, footer và bộ đếm trang](pdf-headers-footers.md#lề-và-band)):

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
| `size`, `landscape`, `margin` | [ở đây](#khổ-giấy-hướng-trang-và-lề) | Hình học của trang. |
| `viewport` | [ở đây](#một-trang-viewport) | Một trang có kích thước cố định. |
| `backgroundColor` | [ở đây](#khổ-giấy-hướng-trang-và-lề) | Màu giấy. |
| `header`, `footer`, `pages` | [Header và footer](pdf-headers-footers.md) | Band lặp lại trên mọi trang và ghi đè theo trang. |
| `pageRanges` | [Phân trang](pdf-pagination.md#giữ-lại-một-số-trang) | Chỉ giữ một số trang. |
| `outline` | [Liên kết và bookmark](pdf-links-metadata.md#bookmark) | Bookmark từ `h1`-`h6`. |
| `metadata`, `lang` | [Metadata](pdf-links-metadata.md#metadata) | Tiêu đề, tác giả, ngày, XMP tùy biến; ngôn ngữ tài liệu. |
| `attachments` | [Tệp đính kèm](pdf-links-metadata.md#tệp-đính-kèm) | Tệp được nhúng. |
| `uncoveredText`, `fontFamilies`, `fonts` | [Font trong PDF](pdf-fonts.md) | Điều gì xảy ra với ký tự không font nào vẽ được; font stack; font cần đăng ký. |
| `tagged`, `pdfa` | [Khả năng truy cập và lưu trữ](pdf-accessibility.md) | Cây cấu trúc, PDF/UA, PDF/A. |
| `css`, `cssVariables` | [HTML và Tailwind](html-and-tailwind.md) | Stylesheet và custom property của `:root` áp dụng trước khi dàn. |
| `images` | [Hình ảnh](images.md) | Byte ảnh tải sẵn cho các giá trị `src`. |
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

Xem [Bắt đầu](getting-started.md#edge-runtime-deno-bun) để biết chi tiết về bundler và runtime; chúng áp dụng cho
entry này theo cùng cách.

## Profile `pdf` và kích thước

`bm_engine.pdf.wasm` là `full` cộng bộ ghi PDF: khoảng 1.5 MB thô, nhiều hơn `bm_engine.wasm` (`full`) khoảng
0.4 MB. Mã PDF chỉ được biên dịch vào binary này và vào addon native, cùng với phần dàn trang theo trang giấy và các thuộc
tính CSS paged-media mà nó cần. (Addon native là tập tính năng `full` cộng đầu ra PDF; bản thân `bm-engine` không
bao giờ cung cấp bộ ghi PDF.) [Profile và kích thước](profiles-and-size.md) có số liệu chính xác cho mọi binary. Tự build
bằng `npm run build:pdf` (`node scripts/build.mjs --profile=pdf`) hoặc `zig build -Dprofile=pdf`
([Build từ mã nguồn](building-from-source.md)).

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

## Cái gì được vẽ và cái gì không

Bộ ghi PDF vẽ những gì painter ảnh vẽ, dưới dạng toán tử vector: nền, viền và outline, gradient (linear, radial
và conic), đổ bóng của hộp và chữ, nhóm opacity và isolation, blend mode, `clip-path`, mask, các hàm `filter`
về màu, transform, chữ cùng gạch trang trí và nét viền, bảng, float, ảnh (JPEG và PNG được nhúng nguyên trạng khi
có thể) và ảnh SVG dùng tập con được hỗ trợ, ở dạng đường vector ([Font trong PDF](pdf-fonts.md) nói về chữ).
Cấu trúc cho khả năng truy cập và các chuẩn PDF/A, PDF/UA được mô tả ở [Khả năng truy cập và lưu
trữ](pdf-accessibility.md).

Một số CSS không có tương đương trong PDF. `filter` kiểu `blur()` hoặc `drop-shadow()` làm lần render lỗi với
`A PDF cannot draw filter: blur(2px)` (thông báo nêu tên filter), như ở takumi-pdf. `backdrop-filter` bị bỏ qua.

## Hạn chế đã biết

Đây là những khác biệt với takumi-pdf đã biết tại thời điểm viết. Từng mục đã được kiểm tra với mã nguồn.

- **Ký hiệu danh sách.** Đầu ra PDF có vẽ chúng, cả trong render nhiều trang lẫn `viewport`, kèm phần tử cấu trúc
  `Lbl`; đầu ra PNG, JPEG, WebP và SVG không vẽ. Được hỗ trợ: các kiểu counter của takumi cho danh sách có thứ tự,
  các ký hiệu disc, circle, square và disclosure, `start`, `reversed`, `value`, đặt trong và ngoài. Không được hỗ
  trợ: `list-style-image` (kiểu counter được vẽ thay thế), quy tắc `::marker`, và ký hiệu của mục bắt đầu bằng hộp
  flex, grid, bảng hoặc ảnh (các mục đó không có ký hiệu).
- **Thứ tự xếp chồng.** Hộp được định vị và hộp có `z-index` được vẽ cùng stacking context của chúng, theo thứ tự vẽ
  của CSS, như takumi. Không biết khác biệt nào ở các fixture so với takumi-pdf, nhưng thứ tự này chưa được chứng minh
  là giống hệt trong mọi tài liệu.
- **`@page`.** `size`, `margin`, `:first`, `:left` và `:right` hoạt động, trang có tên cũng vậy (thuộc tính
  `page`, `@page tên`, `tên:first`): mỗi trang có tên có khổ giấy, lề và chiều cao vùng trang riêng. Nội dung chỉ
  được dàn một lần, ở chiều rộng vùng trang của các trang không tên. Trang có tên với chiều rộng khác nhận khổ riêng,
  nhưng nội dung giữ chiều rộng cũ và bắt đầu từ lề trái của trang; các quy tắc `:first`, `:left` và `:right` làm
  đổi chiều rộng bị bỏ. `@page` bên trong `@media`, `@layer` hoặc `@supports` và đơn vị viewport trong mô tả trang
  không được hỗ trợ. Xem [Phân trang](pdf-pagination.md#quy-tắc-trang).
- **Ngắt trang.** `break-before` / `break-after` với `left`, `right`, `recto` hoặc `verso` có ngắt trang nhưng
  không chèn trang trắng để rơi vào phía trái hay phải. `column` không phải ngắt trang. Dòng chữ không chảy lại
  quanh float đã chuyển sang trang khác, ô bảng trải nhiều hàng không bị chia qua các trang, và các phần của bảng
  không được cắt lát đặc biệt ở mép trang. `box-decoration-break: clone` hoạt động: mỗi mảnh của hộp bị trang cắt
  giữ viền, padding và bo góc.
- **`needs`.** Bước `needs` của takumi-pdf (liệt kê ảnh và file font mà tài liệu muốn) chưa được cài đặt; hãy tự
  truyền byte ảnh và font.
- **Glyph màu.** Glyph COLR (v0 và v1) và bitmap (CBDT, sbix) được nhúng; glyph SVG-in-OpenType được vẽ bằng
  đường viền của nó.
- **PDF/A được kiểm tra, không được chứng nhận.** Phần kiểm tra bao gồm các quy tắc chính mà krilla áp dụng (font,
  ngôn ngữ và tiêu đề tài liệu, văn bản thay thế, outline, tệp đính kèm, ngày). Nó không kiểm tra các giới hạn
  như độ dài chuỗi, mảng hay độ sâu lồng nhau. Chưa chạy validator ngoài nào (veraPDF) trên đầu ra; sự tuân thủ
  được xác lập bằng cách so file của bm-engine với file của takumi-pdf, không phải bằng chứng nhận. Xem [Khả năng
  truy cập và lưu trữ](pdf-accessibility.md#các-kiểm-tra-đi-xa-đến-đâu).
- **Chương trình font nhúng.** Các font con trong file không phải lúc nào cũng trùng từng byte với font mà
  takumi-pdf ghi, dù chúng vẽ cùng các glyph.

So với 89 file PDF golden của takumi-pdf (`node scripts/pdf-compare.mjs`), phần lớn fixture render ra cùng nội
dung trang, từng toán tử một; xem [Khác biệt với takumi](differences-from-takumi.md#đầu-ra-pdf) để biết tình trạng hiện tại.

Khi gặp một khác biệt quan trọng, [Xử lý sự cố](troubleshooting.md) liệt kê các nguyên nhân thường gặp của chữ
bị mất và layout sai; chúng áp dụng cho PDF theo cùng cách.
