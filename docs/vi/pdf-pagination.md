# Phân trang

[English](../en/pdf-pagination.md) · [Tiếng Việt](pdf-pagination.md)

PDF nhiều trang dàn tài liệu một lần ở chiều rộng của vùng trang rồi cắt thành các trang theo quy tắc ngắt của
Chromium (takumi-core port cách phân mảnh khối của Blink, và bm-engine port takumi-core). Trang này trình bày
nội dung chảy từ trang này sang trang khác ra sao, cách ép và cấm ngắt trang bằng CSS, Tailwind hoặc cây node,
cách bảng lặp lại phần đầu và phần cuối, `@page` đặt được những gì, và cách chỉ giữ một số trang. Nó cần [profile
`pdf`](pdf.md); các thuộc tính ngắt trang bị mọi profile khác bỏ qua. Mọi đoạn mã Node.js là các đoạn của
`docs/examples/pdf-pagination.mjs` trong repository và đã được chính file đó chạy.

- [Chuẩn bị](#chuẩn-bị)
- [Nội dung chảy sang trang mới](#nội-dung-chảy-sang-trang-mới)
- [Ép ngắt trang](#ép-ngắt-trang)
- [Giữ các phần đi cùng nhau](#giữ-các-phần-đi-cùng-nhau)
- [Orphans và widows](#orphans-và-widows)
- [Bảng](#bảng)
- [Quy tắc trang](#quy-tắc-trang)
  - [Trang có tên](#trang-có-tên)
- [Giữ lại một số trang](#giữ-lại-một-số-trang)
- [Giới hạn và những gì còn gần đúng](#giới-hạn-và-những-gì-còn-gần-đúng)

## Chuẩn bị

Các ví dụ dùng trang nhỏ 400 x 300 px với lề 24 px để chỉ vài dòng đã đầy một trang:

<!-- @example pdf-pagination#setup -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const small = { size: { width: 400, height: 300 }, margin: 24 }; // pages of 400 x 300 CSS px
```

## Nội dung chảy sang trang mới

Không cần làm gì cả: khi nội dung cao hơn vùng trang, nó chạy tiếp sang trang sau. Một dòng chữ không bao giờ bị
chia, một khối có thể bị chia giữa các dòng, và chỗ ngắt được chọn ở nơi Chromium sẽ chọn (ưu tiên giữa các
khối, trong một đoạn thì giữa các dòng, theo quy tắc `orphans` và `widows` bên dưới).

<!-- @example pdf-pagination#flow -->
```js
const lines = Array.from({ length: 40 }, (_, k) => `<p>Line ${k + 1} of the report</p>`).join("");
const flowing = await pdf.render(`<div style="font-family: Inter; font-size: 14px">${lines}</div>`, small);
```

Tài liệu có tối đa 20 000 trang; vượt quá thì render ném lỗi `too many pages`.

## Ép ngắt trang

`break-before` và `break-after` với `page` (hoặc `always` cũ hơn) ép ngắt trang. Tên cũ `page-break-before` và
`page-break-after` cũng hoạt động như vậy.

| Giá trị | Hiệu ứng trong PDF |
|:--|:--|
| `auto` | Chỉ ngắt khi nội dung cần (mặc định). |
| `page`, `always` | Luôn ngắt. |
| `left`, `right`, `recto`, `verso` | Luôn ngắt. **Không chèn trang trắng** để rơi vào trang trái hay phải. |
| `avoid`, `avoid-page` | Tránh ngắt ở đây khi còn lựa chọn nào khác. |
| `column`, `avoid-column` | Không phải ngắt trang (`avoid-column` là `auto`). |

Ngắt bắt buộc ngay đầu tài liệu không tạo thêm một trang đầu trống.

<!-- @example pdf-pagination#break-before -->
```js
const chapters = ["Intro", "Method", "Results"]
  .map((t) => `<h1 style="break-before: page">${t}</h1><p>Text of ${t}.</p>`)
  .join("");
const book = await pdf.render(`<div style="font-family: Inter">${chapters}</div>`, small);
// a forced break at the very start of the document adds no empty first page
```

Trong HTML, các utility ngắt trang của Tailwind v4 được chấp nhận trong thuộc tính `tw` (không phải `class`) trên
profile `pdf`: `break-before-auto`, `break-before-avoid`, `break-before-page` (cũng là `break-before-all`),
`break-before-avoid-page`, `break-before-left`, `break-before-right`, `break-before-column`, tương tự cho
`break-after-*`, và `break-inside-auto`, `break-inside-avoid`, `break-inside-avoid-page`,
`break-inside-avoid-column`.

<!-- @example pdf-pagination#tailwind -->
```js
const tw = await pdf.render(
  `<div style="font-family: Inter">
     <section tw="break-after-page"><h1>Cover</h1></section>
     <section tw="break-inside-avoid"><h2>Summary</h2><p>Kept together on one page.</p></section>
   </div>`,
  small,
);
```

Trong cây node, dùng thuộc tính style camelCase, giống thuộc tính CSS:

<!-- @example pdf-pagination#node-tree -->
```js
const tree = {
  type: "container",
  style: { display: "flex", flexDirection: "column", fontFamily: "Inter", fontSize: 16 },
  children: [
    { type: "text", text: "Page one" },
    { type: "text", text: "Page two", style: { breakBefore: "page" } },
  ],
};
const twoPages = await pdf.render(tree, small);
```

## Giữ các phần đi cùng nhau

`break-inside: avoid` (hoặc `avoid-page`) yêu cầu không chia một hộp. Khi đó chỗ ngắt trang dời lên trước hộp nếu
không nó sẽ bị cắt. Trong ví dụ, các thẻ cao 90 px trên vùng trang 252 px: không có quy tắc thì thẻ 3 bắt đầu ở
trang 1 và tiếp tục sang trang 2, có quy tắc thì thẻ 3 dời nguyên sang trang 2.

<!-- @example pdf-pagination#avoid -->
```js
const cards = (rule) => Array.from({ length: 6 }, (_, k) =>
  `<div style="${rule} margin-bottom: 8px; height: 90px; border: 1px solid #94a3b8"><b>Card ${k + 1}</b></div>`).join("");
const cut = await pdf.render(`<div style="font-family: Inter">${cards("")}</div>`, small);
// page 1 shows cards 1, 2 and the top of card 3
const whole = await pdf.render(`<div style="font-family: Inter">${cards("break-inside: avoid;")}</div>`, small);
// card 3 does not fit in what is left of page 1, so it moves to page 2 whole: two cards per page
```

`break-before: avoid` và `break-after: avoid` yêu cầu không ngắt ngay trước hoặc sau hộp, đó là cách giữ tiêu đề
đi cùng đoạn văn theo sau. Nội dung thay thế (ảnh) và hộp `line-clamp` không bao giờ bị chia.

## Orphans và widows

`orphans` là số dòng tối thiểu của một đoạn còn lại ở cuối trang, `widows` là số dòng tối thiểu được chuyển sang
trang sau. Cả hai nhận số nguyên từ 1 trở lên, được kế thừa và mặc định là 2. Ở đây đoạn văn chỉ còn chỗ đúng
một dòng ở trang 1; với mặc định 2 cả đoạn chuyển sang trang 2, với `orphans: 1` một dòng ở lại:

<!-- @example pdf-pagination#widows -->
```js
const paragraph = "The quick brown fox jumps over the lazy dog. ".repeat(12);
const flow = (rule) =>
  `<div style="height: 230px"></div>
   <p style="margin: 0; font: 13px/16px Inter; ${rule}">${paragraph}</p>`;
const oneLine = await pdf.render(flow("orphans: 1"), small); // one line of the paragraph at the bottom of page 1
const moved = await pdf.render(flow("orphans: 2"), small);   // the default: the paragraph starts on page 2
```

## Bảng

`thead` được vẽ lại ở đầu mỗi trang mà bảng chạy tiếp sang, và `tfoot` được vẽ lại ở cuối mỗi trang trước trang
cuối của nó. Bảng cần tính năng `tables`, mà profile `pdf` có.

<!-- @example pdf-pagination#table -->
```js
const rows = Array.from({ length: 30 }, (_, k) => `<tr><td>Item ${k + 1}</td><td>${(k + 1) * 3}</td></tr>`).join("");
const table = await pdf.render(
  `<table style="width: 100%; font-family: Inter; font-size: 12px">
     <thead><tr style="background: #e2e8f0"><th>Name</th><th>Qty</th></tr></thead>
     <tbody>${rows}</tbody>
     <tfoot><tr><td>Total</td><td>1395</td></tr></tfoot>
   </table>`,
  small,
);
// the header group is drawn again at the top of every page, the footer group at the bottom of every page
```

Ô trải nhiều hàng (`rowspan`) không bị chia.

## Quy tắc trang

Ngoài các tùy chọn `size` và `margin`, trang có thể được đặt từ CSS. Quy tắc được đọc từ các phần tử `<style>`
của nguồn HTML và từ các chuỗi của tùy chọn `css` (cả với cây node). `@page` của tài liệu thắng các tùy chọn
`size` và `margin`, như `preferCSSPageSize` của Chromium.

<!-- @example pdf-pagination#at-page -->
```js
const styled = await pdf.render(
  `<style>
     @page { size: A5 landscape; margin: 12mm }
     @page :first { margin-top: 40mm }
   </style>
   <div style="font-family: Inter">${lines}</div>`,
);
```

<!-- @example pdf-pagination#at-page-css -->
```js
const viaOption = await pdf.render(`<div style="font-family: Inter">${lines}</div>`, {
  css: "@page { size: letter; margin: 0.5in }", // the css option works for node trees too
});
```

Được hỗ trợ:

- `@page`, `@page :first`, `@page :left` và `@page :right`, ở cấp cao nhất của stylesheet. Trang đầu tính là trang
  phải (trang trái khi phần tử gốc có `direction: rtl`). Các quy tắc xếp tầng theo loại trang như ở Blink: tên trang
  hơn `:first` hơn `:left` / `:right` hơn không có, rồi đến thứ tự trong nguồn.
- **Trang có tên**: thuộc tính `page` (`auto` hoặc một định danh tùy ý; không được kế thừa), `@page tên { ... }`
  và `@page tên:first` (cả `:left` / `:right`). Khi tên trang đang dùng đổi giữa các phần tử block anh em, trang
  bị ngắt, và mỗi trang lấy `size`, lề và chiều cao vùng trang của tên đó (xem [Trang có tên](#trang-có-tên)).
- `size`: `auto`, một tên trong danh sách ở [Đầu ra PDF](pdf.md#khổ-giấy-hướng-trang-và-lề) có thể kèm `portrait`
  hoặc `landscape`, chỉ hướng trang, hoặc một hay hai độ dài.
- `margin` (một đến bốn giá trị) và `margin-top`, `margin-right`, `margin-bottom`, `margin-left`. Độ dài theo
  `px`, `mm`, `cm`, `in`, `pt`, `pc`, `q`, và `em` / `rem` (theo cỡ chữ của phần tử gốc); `var()` của custom
  property của phần tử gốc; phần trăm của kích thước trang theo trục của phía đó; `auto` là 0.

Trang có lề không để lại vùng trang nào thì giữ hình học của các tùy chọn.

Không được hỗ trợ: `@page` bên trong `@media`, `@layer` hoặc `@supports`, đơn vị viewport trong mô tả trang,
đối tượng quy tắc trong `css`, và các hộp lề trang như `@top-center` (takumi cũng không vẽ chúng).

### Trang có tên

Đặt `page: tên` cho một phần tử cùng một quy tắc `@page tên` tương ứng, và nội dung của nó được in trên các trang
mang tên đó. Trang bị ngắt ở chỗ tên đổi, ở đây là trước và sau phần phụ lục:

<!-- @example pdf-pagination#named-pages -->
```js
const named = await pdf.render(
  `<style>
     @page wide { size: 600px 300px; margin: 24px }
     .annex { page: wide }
   </style>
   <div style="font-family: Inter">
     <p>Body text on a normal page.</p>
     <section class="annex"><h2>Annex</h2><p>This section is printed on a wider page.</p></section>
     <p>Back to a normal page.</p>
   </div>`,
  small,
);
// the used page name changes twice, so there is a break before and after the annex
```

Nội dung chỉ được dàn một lần, ở chiều rộng vùng trang của các trang không tên. Điều đó quyết định việc đổi
chiều rộng làm gì:

- **Trang có tên với chiều rộng khác** nhận khổ trang riêng, nhưng nội dung không được dàn lại: nó giữ chiều rộng
  lúc dàn và bắt đầu từ lề trái của trang có tên. Chiều cao và lề khác nhau theo tên thì hoạt động đầy đủ (mỗi
  tên có chiều cao vùng trang riêng).
- **Quy tắc `:first`, `:left` và `:right` làm đổi chiều rộng vùng trang** bị bỏ. Khi quy tắc `:left` và `:right`
  cho trang trái và phải các chiều rộng khác nhau, chúng bị bỏ qua toàn bộ; khi trang đầu vẫn khác thì các quy tắc
  `:first` của nó bị bỏ qua. Việc này được quyết định trên các trang không tên và áp dụng cả cho các quy tắc
  `:first` / `:left` / `:right` riêng của trang có tên.

Nội dung cần dàn lại cho chiều rộng trang khác thì phải render riêng.

## Giữ lại một số trang

`pageRanges` chỉ giữ các trang được liệt kê. Mỗi phần tử là số trang hoặc `{ from, to }`; cả hai cận đều bao gồm
và không bắt buộc (`from` bỏ trống là trang đầu, `to` bỏ trống là trang cuối). Trang được đánh số từ 1. Bộ đếm
trang giữ số của tài liệu đầy đủ ([Header, footer và bộ đếm trang](pdf-headers-footers.md)).

<!-- @example pdf-pagination#ranges -->
```js
const part = await pdf.render(`<div style="font-family: Inter; font-size: 14px">${lines}</div>`, {
  ...small,
  pageRanges: [1, { from: 3 }], // page 1 and page 3 to the end; pages are numbered from 1
});
```

Một khoảng không hợp lệ (`0`, `1.5`, hoặc `from` sau `to`) ném `Page range is invalid: ...`, và danh sách không giữ
trang nào của tài liệu thì ném:

<!-- @example pdf-pagination#ranges-error -->
```js
let rangeError;
try {
  await pdf.render(`<p style="font-family: Inter">one page</p>`, { pageRanges: [{ from: 5 }] });
} catch (e) {
  rangeError = e.message;
}
// bm-engine: The page ranges select none of the document's 1 pages
```

## Giới hạn và những gì còn gần đúng

Các trang được cắt sau khi dàn, từ một layout cao duy nhất, theo cách Blink xử lý phân mảnh flex và grid. Điều đó
kéo theo:

- Phần trăm và việc giãn không bao giờ thấy kích thước trang.
- Hộp có `height` xác định giữ nguyên nó kể cả khi nội dung bị đẩy qua trang; các hộp khác lớn thêm đúng phần mà
  một chỗ ngắt đã đẩy xuống.
- Dòng chữ không chảy lại quanh float đã chuyển sang trang khác.
- Nội dung được dàn ở một chiều rộng, chiều rộng vùng trang của các trang không tên. Trang có tên có thể có khổ khác,
  nhưng nội dung không được dàn lại (xem [Trang có tên](#trang-có-tên)).
- Nền hoặc viền của hộp trải qua mép trang bị trang cắt. Với `box-decoration-break: slice` (mặc định) các cạnh bị cắt
  mất viền, padding và bo góc; với `clone` mỗi mảnh giữ viền, padding và bo góc. Các phần của bảng (hàng, ô, nhóm)
  không được cắt lát đặc biệt ở mép trang.
