# Khổ giấy, lề và viewport

[English](../../en/pdf/page-size-and-viewport.md) · [Tiếng Việt](page-size-and-viewport.md)

PDF do bm-engine tạo ra hoặc là **nhiều trang** (mặc định: trang A4, lề 10 mm, nội dung chảy từ trang này
sang trang sau) hoặc là **một trang duy nhất** với kích thước bạn chọn (`viewport`). Trang này nói về các tùy
chọn đặt hình dạng trang và màu giấy, và cách các quy tắc `@page` của chính tài liệu tham gia vào. Các đoạn
mã là các phần của `docs/examples/pdf.mjs` và đã được file đó chạy; `pdf` là một `PdfRenderer` đã đăng ký
Inter và `card` là một cây node nhỏ ([Bắt đầu nhanh với PDF](index.md)).

- [Khổ giấy, hướng trang và lề](#khổ-giấy-hướng-trang-và-lề)
- [Một trang: `viewport`](#một-trang-viewport)
- [Quy tắc trang: `@page`](#quy-tắc-trang-page)

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
trang](headers-footers.md#lề-và-band). `landscape` và quy tắc `@page` cũng có thể đặt khổ giấy; `@page { size: ... }`
của tài liệu thắng tùy chọn `size` ([Quy tắc trang](#quy-tắc-trang-page)).

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

## Quy tắc trang: `@page`

Tài liệu có thể tự đặt hình dạng trang bằng quy tắc `@page` trong phần tử `<style>` của HTML hoặc trong tùy chọn
`css` (dùng được cho cả cây node). `@page { size; margin }` của tài liệu thắng các tùy chọn `size` và `margin`,
giống `preferCSSPageSize` của Chromium. Trang `:first`, `:left`, `:right`, trang có tên (thuộc tính `page`
cùng `@page tên`) và `@page` bên trong `@media`, `@layer` hoặc `@supports` đều được hỗ trợ; các hộp lề trang
(`@top-center`, ...) bị bỏ qua. Các trang khác chiều rộng dàn nội dung ở chiều rộng của chính chúng.
[Phân trang → Quy tắc trang](pagination.md#quy-tắc-trang) có ví dụ và mọi descriptor được hỗ trợ, còn
[Trang có tên](pagination.md#trang-có-tên) nói về cách các trang khác chiều rộng hoạt động.

| Bạn muốn | Dùng |
|:--|:--|
| Cùng một loại giấy cho mọi tài liệu của ứng dụng | tùy chọn `size` / `margin` |
| Tài liệu tự quyết định (mẫu do người khác viết) | `@page` trong tài liệu |
| Trang đầu khác đi (bìa, tiêu đề thư) | `@page :first { margin-top: ... }` |
| Một trang cao đúng bằng nội dung | `viewport: { width }` |
