# Header, footer và bộ đếm trang

[English](../../en/pdf/headers-footers.md) · [Tiếng Việt](headers-footers.md)

PDF nhiều trang có thể lặp lại header ở đầu và footer ở cuối mỗi trang, kèm số trang, tổng số trang và, cho các
tham chiếu chéo, số trang mà một phần tử khác rơi vào. Header hoặc footer (một *band*) là một chuỗi HTML hay một
cây node bình thường, nên mọi thứ engine dàn được đều dùng được trong đó. Trang này nói về cách viết một band, các
bộ đếm, ghi đè theo trang, cách lề bám theo band, và bộ đếm trong chính nội dung tài liệu. Nó cần [profile
`pdf`](index.md). Mọi đoạn mã Node.js là các đoạn của `docs/examples/pdf-headers-footers.mjs` trong repository và
đã được chính file đó chạy.

- [Chuẩn bị](#chuẩn-bị)
- [Footer có số trang](#footer-có-số-trang)
- [Bộ đếm trong cây node](#bộ-đếm-trong-cây-node)
- [Header](#header)
- [Band khác nhau ở một số trang](#band-khác-nhau-ở-một-số-trang)
- [Lề và band](#lề-và-band)
- [Bộ đếm trong nội dung](#bộ-đếm-trong-nội-dung)
- [Bộ đếm trong hộp fixed lặp lại](#bộ-đếm-trong-hộp-fixed-lặp-lại)
- [Quy tắc và giới hạn](#quy-tắc-và-giới-hạn)

## Chuẩn bị

<!-- @example pdf-headers-footers#setup -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer, PageNumber, TotalPages } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const lines = Array.from({ length: 40 }, (_, k) => `<p>Line ${k + 1} of the report</p>`).join("");
const body = `<div style="font-family: Inter; font-size: 14px">${lines}</div>`;
const page = { size: { width: 400, height: 300 }, margin: 24 };
```

## Footer có số trang

`footer` và `header` nhận một chuỗi HTML, một cây node hoặc `false` (không có band). Phần tử của band có danh sách
class chứa `pageNumber` nhận số của trang đang vẽ, và phần tử có class `totalPages` nhận tổng số trang. Đó là
tên class, không phải tên thẻ, nên dùng được trên `span` trong HTML; nội dung của phần tử bị thay bằng con số.

<!-- @example pdf-headers-footers#footer-html -->
```js
const footer = `<div style="font: 11px Inter; color: #475569">
  Page <span class="pageNumber"></span> of <span class="totalPages"></span>
</div>`;
const numbered = await pdf.render(body, { ...page, footer });
```

Band được dàn riêng, tách khỏi tài liệu, nên hãy đặt font và cỡ chữ trên chính các phần tử của band (ví dụ dùng
cách viết tắt `font`). Nó dùng các font đã đăng ký trên renderer.

## Bộ đếm trong cây node

Trong cây node, `PageNumber()`, `TotalPages()` và `TargetPageNumber()` tạo các node với class đúng. Mỗi hàm nhận
`{ format, className, style, tw }`. `format` là tên counter style và mặc định là `decimal`: `decimal`,
`decimal-leading-zero`, `lower-roman`, `upper-roman`, `lower-alpha`, `lower-latin`, `upper-alpha`, `upper-latin`,
`lower-greek`, `hiragana`, `katakana`, `trad-chinese-informal`, `cjk-ideographic`, `cjk-decimal`, và các hệ chữ
số `arabic-indic`, `bengali`, `cambodian`, `khmer`, `devanagari`, `gujarati`, `gurmukhi`, `kannada`, `lao`,
`malayalam`, `mongolian`, `myanmar`, `oriya`, `persian`, `urdu`, `tamil`, `telugu`, `thai` và `tibetan`. Trong
HTML, đặt cùng tên đó làm class phụ: `<span class="pageNumber lower-roman">`.

<!-- @example pdf-headers-footers#footer-node -->
```js
const nodeFooter = {
  type: "container",
  style: { display: "flex", columnGap: 4, fontFamily: "Inter", fontSize: 11, color: "#475569" },
  children: [
    { type: "text", text: "Sheet" },
    PageNumber({ format: "upper-roman" }), // I, II, III
    { type: "text", text: "/" },
    TotalPages(),
  ],
};
const roman = await pdf.render(body, { ...page, footer: nodeFooter });
```

## Header

Header hoạt động y như footer. Nó được vẽ trước nội dung trang, còn footer vẽ sau.

<!-- @example pdf-headers-footers#header -->
```js
const header = `<div style="font: 11px Inter; display: flex; justify-content: space-between">
  <span>ACME Corp</span><span>Confidential</span>
</div>`;
const both = await pdf.render(body, { ...page, header, footer });
```

## Band khác nhau ở một số trang

`pages` thay band ở một số trang. Các khóa là `first`, `last`, `odd` và `even`, mỗi khóa là một object với `header`
và `footer` tùy chọn. `first` và `last` thắng `odd` và `even`. Trường bạn bỏ trống rơi xuống quy tắc kế tiếp và
cuối cùng đến `header` / `footer` của chính tài liệu; `false` không vẽ gì ở các trang đó. Tài liệu một trang tính
vừa là `first` vừa là `last`.

<!-- @example pdf-headers-footers#pages -->
```js
const ruled = await pdf.render(body, {
  ...page,
  header,
  footer,
  pages: {
    first: { header: false },                         // no header on the cover page
    last: { footer: "<b>End of document</b>" },       // the last page ends differently
    even: { header: "<span style=\"font: 11px Inter\">Even pages</span>" },
  },
});
```

## Lề và band

Band được vẽ trong lề trang. Band được dàn ở đủ chiều rộng trang, bắt đầu cách mép trên 15 pt (20 px) với header
và kết thúc cách mép dưới 15 pt với footer, và bị cắt theo vùng đó. Lề `auto` của phía chứa nó lớn lên cho vừa:
chiều cao band cộng 20 px, nhưng không bao giờ dưới 10 mm (37.8 px). Các phía khác giữ 10 mm. Một con số cụ thể
sẽ ghi đè điều này.

<!-- @example pdf-headers-footers#margins -->
```js
const roomy = await pdf.render(body, {
  ...page,
  margin: { top: "auto", bottom: 60, left: 24, right: 24 }, // top follows the header, bottom is fixed
  header,
});
```

`measure()` cho chiều cao của một band, dàn ở chiều rộng trang với bộ đếm ba chữ số (nên band xuống dòng khi có
`100` trang được đo đúng như lúc dùng thật). Nhờ đó phép tính trở nên tường minh; hai lần render dưới đây cho cùng
một file:

<!-- @example pdf-headers-footers#measure -->
```js
const tall = `<div style="height: 64px; font: 11px Inter">Letterhead</div>`;
const bandHeight = (await pdf.measure(tall, { size: page.size })).height; // 64: the band laid out at the page width
const automatic = await pdf.render(body, { size: page.size, header: tall }); // every margin "auto"
const manual = await pdf.render(body, { size: page.size, header: tall, margin: { top: bandHeight + 20 } });
// the same file: an auto margin is the band height + 20 px (but at least 37.8 px, 10 mm)
```

Khi kích thước band phụ thuộc số trang, engine đo lại nó với số trang thật, và nếu điều đó làm dịch một lề `auto`
thì nội dung được dàn lại, tối đa ba lần.

## Bộ đếm trong nội dung

Cùng các class đó hoạt động trong chính tài liệu. Phần tử hiển thị trang mà nó rơi vào:

<!-- @example pdf-headers-footers#flow-counters -->
```js
const toc = await pdf.render(
  `<div style="font-family: Inter; font-size: 14px">
     <p><a href="#results">Results</a> on page <a href="#results"><span class="targetPageNumber"></span></a></p>
     <h2 id="results" style="break-before: page">Results</h2>
     <p>This is page <span class="pageNumber"></span> of <span class="totalPages"></span>.</p>
   </div>`,
  page,
);
```

`targetPageNumber` cho trang của phần tử mà `<a href="#id">` bao quanh gần nhất trỏ tới (hoặc `href` của chính
phần tử, với `TargetPageNumber({ href })`, tự render ra liên kết của nó). Dùng cho "xem trang 12" và mục lục. Các
con số được ổn định qua tối đa ba lượt dàn, vì chèn một con số có thể làm đổi chỗ rơi của nội dung phía sau.

## Bộ đếm trong hộp fixed lặp lại

Hộp `position: fixed` được vẽ trên mọi trang, và bộ đếm bên trong nó hiển thị số của từng trang:

<!-- @example pdf-headers-footers#fixed -->
```js
const stamped = await pdf.render(
  `<div style="font-family: Inter; font-size: 14px">
     <div style="position: fixed; top: 4px; right: 8px; font-size: 10px">Sheet <span class="pageNumber"></span>/<span class="totalPages"></span></div>
     ${lines}
   </div>`,
  page,
);
```

## Quy tắc và giới hạn

- Band có thể chứa ảnh (truyền byte hoặc một khóa từ `images`), chữ, flex và grid. Band không có bộ đếm và không
  có quy tắc `pages` được dàn một lần và vẽ trên mọi trang.
- Band không bao giờ mang annotation liên kết, và trong PDF có thẻ chúng được đánh dấu là artifact, nên trình đọc
  màn hình bỏ qua ([Khả năng truy cập và lưu trữ](accessibility.md)).
- `pageRanges` giữ số của tài liệu đầy đủ: với `pageRanges: [1, 3]` của tài liệu ba trang, trang thứ hai của file
  ghi "Page 3 of 3".
- Bộ đếm CSS trong nội dung sinh ra hoạt động ở đầu ra PDF: `counter()`, `counters()`, `counter-reset`,
  `counter-increment`, `counter-set`, `counter(page)` và `target-counter()`, trong tài liệu lẫn trong band. Các
  class hook ở trên vẫn là cách đưa số trang vào một cây node.
- Đơn vị viewport (`vw`, `vh`, ...) trong band được đo theo cả trang, không phải theo band.
- Ở dạng viewport (`viewport`) không có band.
