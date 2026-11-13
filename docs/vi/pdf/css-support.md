# CSS trong PDF

[English](../../en/pdf/css-support.md) · [Tiếng Việt](css-support.md)

PDF được dàn trang bằng cùng engine với ảnh, nên phần CSS mà bm-engine hỗ trợ cho ảnh
([Hỗ trợ CSS và tính năng](../image/css-support.md)) cũng áp dụng cho đầu ra PDF, cộng thêm và trừ đi những gì
nêu trên trang này: các thuộc tính paged-media chỉ đầu ra PDF đọc, cái gì được vẽ và vẽ ra sao, và các tính
năng ảnh hoạt động khác đi trong PDF. Các đoạn mã là các phần của `docs/examples/pdf-css-support.mjs`, file này
chạy chúng trên cả backend wasm lẫn native.

- [Paged media](#paged-media)
- [Cái gì được vẽ và cái gì không](#cái-gì-được-vẽ-và-cái-gì-không)
- [Khác biệt so với đầu ra ảnh](#khác-biệt-so-với-đầu-ra-ảnh)

## Paged media

Những mục này chỉ áp dụng cho đầu ra PDF. Khi render ảnh (`render`, `renderSvg`, `measure`), chúng được chấp
nhận và bỏ qua trên mọi build, kể cả `bm-engine/pdf` và addon native:

| Tính năng | Trạng thái | Trang |
|:--|:--|:--|
| `break-before`, `break-after`, `break-inside`, `page-break-before` / `-after` / `-inside` | `auto`, `avoid`, `avoid-page`, `avoid-column`, `page`, `always`, `column`, `left`, `right`, `recto`, `verso` đều được đọc; `left`, `right`, `recto`, `verso` ngắt trang nhưng không chèn trang trắng; `column` không phải ngắt trang | [Phân trang](pagination.md#ép-ngắt-trang) |
| `orphans`, `widows` | số nguyên từ 1 trở lên, kế thừa, mặc định 2 | [Phân trang](pagination.md#orphans-và-widows) |
| Tailwind `break-before-*`, `break-inside-*`, `break-after-*` | trong trường / thuộc tính `tw` | [Phân trang](pagination.md#ép-ngắt-trang) |
| `@page` với `size`, `margin*`, `:first`, `:left`, `:right`, trang có tên (`page`, `@page tên`) | đọc từ tùy chọn `css` và `<style>` của HTML, cả bên trong `@media`, `@supports` và `@layer`; mỗi trang dàn nội dung ở chiều rộng của chính nó | [Phân trang](pagination.md#quy-tắc-trang) |
| Nhóm header và footer của bảng (`thead`, `tfoot`) | lặp lại ở đầu / cuối mọi trang mà bảng đi qua | [Phân trang](pagination.md#bảng) |
| `position: fixed` | lặp lại trên mọi trang | [Header và footer](headers-footers.md) |
| `box-decoration-break: clone` | mỗi mảnh của hộp bị trang cắt giữ viền, padding và bo góc | [Phân trang](pagination.md) |
| `background-clip: border-area` | chỉ đầu ra PDF | |
| Bộ đếm trang | phần tử `PageNumber`, `TotalPages`, `TargetPageNumber`; `counter(page)` trong `content` **không** hoạt động | [Header và footer](headers-footers.md) |
| Hộp lề trang (`@top-center`, ...) | không hỗ trợ (dùng tùy chọn `header` / `footer`) | [Header và footer](headers-footers.md) |

<!-- @example pdf-css-support#ignored-in-images -->
```js
import { Renderer } from "bm-engine/pdf";

const html = `<div style="font-family: Inter">
  <p>Page one</p><p style="break-before: page">Page two</p>
</div>`;
const doc = await pdf.render(html, page);                 // two pages
const image = new Renderer();
image.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const png = image.renderSync(html, { width: 400, height: 120 }); // one image: break-before is ignored
```

## Cái gì được vẽ và cái gì không

Bộ ghi PDF vẽ những gì painter ảnh vẽ, dưới dạng toán tử vector: nền, viền và outline, gradient (linear, radial
và conic), đổ bóng của hộp và chữ, nhóm opacity và isolation, blend mode, `clip-path`, mask, các hàm `filter`
về màu, transform, chữ cùng gạch trang trí và nét viền, bảng, float, ảnh (JPEG và PNG được nhúng nguyên trạng khi
có thể) và ảnh SVG dùng tập con được hỗ trợ, ở dạng đường vector ([Font trong PDF](fonts.md) nói về chữ).
Cấu trúc cho khả năng truy cập và các chuẩn PDF/A, PDF/UA được mô tả ở [Khả năng truy cập và lưu
trữ](accessibility.md).

Một số CSS không có tương đương trong PDF. `filter` kiểu `blur()` hoặc `drop-shadow()` làm lần render lỗi với
`A PDF cannot draw filter: blur(2px)` (thông báo nêu tên filter), như ở takumi-pdf. `backdrop-filter` bị bỏ qua.

## Khác biệt so với đầu ra ảnh

**Ký hiệu danh sách** chỉ được vẽ trong đầu ra PDF (nhiều trang và `viewport`), kèm phần tử cấu trúc `Lbl`; đầu ra
PNG, JPEG, WebP và SVG không vẽ. Xem [Khác biệt với takumi-pdf](differences-from-takumi.md#hạn-chế-đã-biết).

Dấu **`text-overflow`** được vẽ, nhưng nó không phải là chữ: khi trích chữ của trang (copy và paste, tìm kiếm,
`pdftotext`) bạn nhận được các ký tự được vẽ trước dấu đó, không có dấu và không có phần bị cắt. Đã kiểm tra bằng
`pdftotext` của poppler:

<!-- @example pdf-css-support#text-overflow -->
```js
const clipped = await pdf.render(
  `<p style="font-family: Inter; font-size: 20px; width: 200px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">
     A very long product name that does not fit
   </p>`,
  page,
);
// the page shows "A very long produc…"; the marker is drawn but is not text: extracting the text
// (pdftotext, copy and paste) gives "A very long product", not the "…" and not the cut-off rest
```

**`image-rendering`** không có tác dụng với đầu ra PDF. Ảnh trong PDF không có thiết lập này, nên `pixelated` và
`crisp-edges` cho ra cùng file với `auto`, còn việc làm mịn ảnh phóng to là do trình xem quyết định (với đầu ra
ảnh, `pixelated` phóng to theo nearest-neighbour):

<!-- @example pdf-css-support#image-rendering -->
```js
const pixels = { width: 2, height: 2, data: new Uint8Array([255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255, 255, 0, 0, 255]) };
const scaled = (rendering) => pdf.render({
  type: "image", src: pixels, style: { width: 120, height: 120, imageRendering: rendering },
}, { viewport: { width: 120, height: 120 } });
const smooth = await scaled("auto");
const pixelated = await scaled("pixelated");
// the two files are byte for byte the same: a PDF image has no image-rendering setting
```

**Filter làm nhoè** không vẽ được: `blur()` và `drop-shadow()` trong `filter` làm lần render lỗi, trong khi render
ảnh vẽ được chúng:

<!-- @example pdf-css-support#blur-error -->
```js
let blurError;
try {
  await pdf.render(`<div style="filter: blur(2px); width: 50px; height: 50px; background: red"></div>`, page);
} catch (e) {
  blurError = e.message;
}
// A PDF cannot draw filter: blur(2px)
```

**Độ nhoè của box shadow** được mô phỏng bằng hình vector (tám dải lan toả nhạt dần quanh bóng), nên bóng mềm
trông hơi khác bản PNG, giống takumi-pdf.
