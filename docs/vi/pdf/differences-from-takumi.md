# Khác biệt với takumi-pdf

[English](../../en/pdf/differences-from-takumi.md) · [Tiếng Việt](differences-from-takumi.md)

`bm-engine/pdf` là bản port của [takumi-pdf](https://github.com/kane50613/takumi): tên tùy chọn, giá trị mặc định,
quy tắc kiểm tra và phần lớn thông báo lỗi là của takumi-pdf, và trong đa số trường hợp một tài liệu được render
ra cùng nội dung trang. Trang này liệt kê những gì khác, rồi cách đầu ra đã được so sánh. Phía ảnh có trang riêng:
[Khác biệt với takumi](../image/differences-from-takumi.md).

- [API và cách đóng gói](#api-và-cách-đóng-gói)
- [Hạn chế đã biết](#hạn-chế-đã-biết)
- [So với golden của takumi-pdf](#so-với-golden-của-takumi-pdf)

## API và cách đóng gói

- **Điểm vào riêng.** Đầu ra PDF chỉ có trong `bm-engine/pdf`; `renderPdf` trên mọi build khác đều ném lỗi, kể cả
  khi `bm-engine` chạy trên addon native ([Native và WebAssembly](native-and-wasm.md#các-profile-khác-làm-gì)).
  Trên Node.js, bản thân `bm-engine/pdf` dùng addon native khi nó đã được cài và profile wasm `pdf` trong trường
  hợp còn lại.
- **`prepare` tải ảnh, không tải font.** `prepare` tải về các ảnh từ xa mà tài liệu và các band nhắc tới và
  `images` chưa cung cấp (bằng `images.fetch` hoặc `fetch` toàn cục). Nó tìm các ảnh đó bằng cách quét nguồn trong
  JavaScript, không phải bằng bước `needs` native của takumi-pdf. File của `@font-face` không được tải: hãy truyền
  font qua `fonts` / `registerFont`.
- **JSX.** Phần tử React được chấp nhận làm tài liệu và làm band. Nó được chuyển thành HTML; component chạy một
  lần mà không có React dispatcher, nên các hook ngoài việc đọc đơn thuần không hoạt động.
- **Bộ đếm trong nội dung sinh ra.** Bộ đếm CSS hoạt động trong đầu ra PDF: `counter()`, `counters()`,
  `counter-reset`, `counter-increment`, `counter-set`, `counter(page)` và `target-counter()`. `PageNumber`,
  `TotalPages` và `TargetPageNumber` vẫn dùng được ([Header, footer và bộ đếm trang](headers-footers.md)).
- **Lỗi của tùy chọn.** Thông báo là của takumi-pdf, có thêm tiền tố `bm-engine: `. Khi thông báo của takumi-pdf
  là lỗi serde (`unknown variant ...`), bm-engine ghi cùng nội dung ở các trường hợp được liệt kê trong [tài liệu
  API](api.md#lỗi); với các giá trị sai kiểu khác, nó từ chối đầu vào bằng câu chữ riêng.
- **Ảnh.** PNG và JPEG được nhúng bằng chính byte gốc khi có thể, nên file nhỏ hơn và ảnh 16-bit, thang xám, có
  profile ICC hay CMYK giữ nguyên dữ liệu. Ảnh SVG được vẽ dạng vector.

## Hạn chế đã biết

Đây là những khác biệt với takumi-pdf đã biết tại thời điểm viết, lấy từ `docs/PDF_AUDIT.md`, bản kiểm toán từng
tính năng so với takumi-pdf 0.20.0.

**Font và chữ**

- **Không có font dự phòng đi kèm.** takumi-pdf dự phòng bằng Geist; bm-engine không kèm font nào. Khi hoàn toàn
  chưa đăng ký font, render có chữ sẽ báo lỗi (`No font is registered to draw ...`) trừ khi
  `uncoveredText` là `"blank"`; khi đã có ít nhất một font, ký tự không font nào vẽ được sẽ theo
  `uncoveredText`. Hãy đăng ký font ([Font trong PDF](fonts.md)).
- **`unicode-bidi: bidi-override`** được phân tích nhưng không có tác dụng. Văn bản hai chiều thông thường, nối
  chữ Ả Rập, CJK và emoji hoạt động và trích xuất ra cùng văn bản như takumi-pdf.
- **Form control.** Hộp và viền của `input`, `textarea` và `select` được vẽ; giá trị, placeholder và các dòng của
  `textarea` không được vẽ, còn chữ của `select` bị lệch.
- **Chữ SVG** chỉ dùng giá trị đầu tiên của các danh sách `x`, `y`, `dx` và `dy`; `rotate`, `textPath` và gạch
  trang trí chữ không được vẽ. Glyph SVG-in-OpenType được vẽ bằng đường viền của nó. Glyph COLR (v0 và v1) và
  bitmap (CBDT, sbix) được nhúng.
- **CSS trang bên trong `<svg>` nội tuyến** (một `<style>` trong phần tử `svg`) không được áp dụng.
- **Không gian nội suy của gradient.** `in oklch`, `in oklab` và tương tự được lấy mẫu trong đúng không gian được
  yêu cầu (hành vi của CSS); takumi-pdf 0.20.0 ghi các điểm dừng sRGB và bỏ qua không gian đó, nên màu khác nhau.
- **Chương trình font nhúng.** Các font con trong file không phải lúc nào cũng trùng từng byte với font mà
  takumi-pdf ghi (71 trên 136 fixture là trùng), dù chúng vẽ cùng các glyph.

**Tính năng CSS chưa được hỗ trợ**

- **Ký hiệu danh sách.** Đầu ra PDF có vẽ chúng, cả trong render nhiều trang lẫn `viewport`, kèm phần tử cấu trúc
  `Lbl`; đầu ra PNG, JPEG, WebP và SVG không vẽ. Được hỗ trợ: các kiểu counter của takumi cho danh sách có thứ tự,
  các ký hiệu disc, circle, square và disclosure, `start`, `reversed`, `value`, đặt trong và ngoài. Không được hỗ
  trợ: `list-style-image` (kiểu counter được vẽ thay thế), quy tắc `::marker`, và ký hiệu của mục bắt đầu bằng hộp
  flex, grid, bảng hoặc ảnh (các mục đó không có ký hiệu).
- **`content: url()`** không vẽ gì.
- **Không được hỗ trợ:** `offset-path` và cú pháp màu tương đối (`rgb(from ...)`).
- **Thứ tự xếp chồng.** Hộp được định vị và hộp có `z-index` được vẽ cùng stacking context của chúng, theo thứ tự vẽ
  của CSS, như takumi (kể cả lớp `z-index` âm). Không biết khác biệt nào ở các fixture so với takumi-pdf, nhưng
  thứ tự này chưa được chứng minh là giống hệt trong mọi tài liệu.

**Trang**

- **`@page`.** `size`, `margin`, `:first`, `:left` và `:right` hoạt động, trang có tên cũng vậy (thuộc tính
  `page`, `@page tên`, `tên:first`), cùng với `@page` bên trong `@media`, `@layer` và `@supports`, `!important`,
  layer và độ ưu tiên (specificity), và độ dài theo mọi đơn vị, kể cả `calc()`, đơn vị viewport và `var()`. Mỗi
  trang dàn nội dung ở chiều rộng của chính nó, kể cả khi `:first`, `:left`, `:right` hoặc một trang có tên có
  chiều rộng khác, giống takumi. Khi ranh giới trang nằm giữa một hàng bảng hoặc một dòng flex mà chiều rộng đổi,
  hàng hay dòng được tiếp tục giữ chiều rộng trước đó. Custom property mà tùy chọn `cssVariables` đặt cho một
  tài liệu HTML đầy đủ có tác dụng lên quy tắc trang ở bm-engine, còn ở takumi thì không. Hộp lề trang
  (`@top-center` ...) được phân tích rồi bỏ qua, như ở takumi-pdf. Xem [Phân trang](pagination.md#quy-tắc-trang).
- **Ngắt trang.** `break-before` / `break-after` với `left`, `right`, `recto` hoặc `verso` có ngắt trang nhưng
  không chèn trang trắng để rơi vào phía trái hay phải. `column` không phải ngắt trang. Các tiện ích Tailwind
  `break-before-*`, `break-after-*` và `break-inside-*` hoạt động đúng như Tailwind định nghĩa; takumi không có
  (đây là phần mở rộng). `box-decoration-break: clone` hoạt động: mỗi mảnh của hộp bị trang cắt giữ viền, padding
  và bo góc.
- **Bảng.** `thead` / `tfoot` lặp lại, việc chia hàng và ô trải nhiều hàng (`rowspan`) được xử lý qua các trang.
  Viền gộp (collapsed) kết thúc mỗi mảnh bằng viền dưới riêng của nó; còn lệch nhỏ ở viền 4 px và header lặp lại.
  Caption của bảng qua nhiều trang có khác biệt (takumi bỏ các dòng caption ở trang 1).
- **Float.** Dòng chữ không chảy lại cạnh float đã chuyển sang trang khác: bm-engine phân trang một bố cục đã dàn
  xong.
- **Hộp bị xoay hoặc nghiêng bị ranh giới trang cắt** được vẽ nguyên vẹn ở trang nơi nó bắt đầu; takumi cắt lát
  chúng theo từng mảnh.
- **Flex và grid.** Hàng flex qua nhiều trang giống takumi-pdf. Với grid, một mục `align-items: end` bị ngắt
  trước hàng của nó thì khác, vì bm-engine không có mảnh theo hàng grid.
- **Ký hiệu danh sách qua nhiều trang.** Ký hiệu của mục bị chia qua các trang nằm ở dòng đầu của mục (như
  Chrome); takumi đặt nó ở dòng đầu của mảnh cuối. Đây là chủ ý.
- **Tài liệu dài.** Thời gian mỗi trang không đổi (3,1 ms mỗi trang ở 100 và ở 500 trang trên WebAssembly) và
  file bằng 0,81 đến 0,87 lần kích thước file của takumi-pdf. Bộ nhớ thì cao hơn: ở 500 trang, engine wasm giữ
  khoảng 260 MiB so với 76 MiB của takumi-pdf, vì bm-engine giữ cả tài liệu đã dàn cho đến khi file được ghi.

**File**

- **PDF/A và PDF/UA được kiểm tra và đã được veraPDF xác nhận, nhưng không phải là chứng nhận.** Phần kiểm tra là
  bản port các quy tắc của krilla (font, ngôn ngữ và tiêu đề tài liệu, văn bản thay thế, outline, tệp đính kèm,
  ngày, cùng các giới hạn về chuỗi, tên và độ sâu lồng nhau). veraPDF 1.28.2 báo cả 45 file của bm-engine đều
  tuân thủ (PDF/A-2a, 2b, 2u, 3a, 3b, 3u, 4, 4f và PDF/UA-1, PDF/UA-2), giống với file của takumi-pdf. pdfcpu ở
  chế độ strict báo 12 vấn đề trên file của cả hai engine (khóa `AFRelationship` của PDF/A-3, mà nó coi là chỉ
  có ở PDF 2.0, và các structure destination trong mục outline của PDF/UA-2); không vấn đề nào riêng của
  bm-engine. qpdf, poppler, MuPDF và pdf.js đọc các file mà không phàn nàn. Tất cả những điều này không phải là
  chứng nhận; xem [Khả năng truy cập và lưu trữ](accessibility.md#các-kiểm-tra-đi-xa-đến-đâu).
- **Lỗi.** Kích thước rất lớn mà takumi-pdf vẫn render (trang 750.000.000 pt, viewport 100.000 px) bị bm-engine từ
  chối. Font bị cắt cụt hoặc không có `cmap` bị từ chối; takumi chấp nhận chúng. Giá trị `margin` là NaN trở
  thành `null` trong JSON nên có nghĩa là lề mặc định.

## So với golden của takumi-pdf

`node scripts/pdf-compare.mjs` render đầu vào của từng fixture trong 136 fixture golden của takumi-pdf
(`takumi-pdf/tests/fixtures-generated/*.pdf`) bằng `bm-engine/pdf`, phân tích cả hai file và so từng trang theo
từng toán tử sau khi thay số hiệu object và tên resource bằng thứ chúng trỏ tới (font, ảnh, shading, soft mask,
form XObject). Font, cây cấu trúc, annotation, outline, metadata và tệp đính kèm được so riêng. Trong lần chạy
cho trang này:

| Kết quả | Số fixture |
|:--|--:|
| nội dung trang giống hệt | 118 |
| gần giống: cùng toán tử, số lệch trong khoảng 0.01 | 7 |
| khác | 11 |
| lỗi render | 0 |
| bố cục object giống hệt | 134 |
| chương trình font nhúng giống hệt | 71 |

Bảy golden được ghi bởi một bản takumi mới hơn gói 0.20.0 đã phát hành; bm-engine khớp cả bảy. 18 fixture không
giống hệt, theo nguyên nhân:

| Fixture | Khác ở đâu |
|:--|:--|
| `text-stroke-paint-order` (gần giống) | thứ tự cộng các độ rộng f32: `50.000122` so với `50.00006` |
| `content-page-counters`, `report-links-outline`, `report-tagged-ua1`, `report-tagged-a2a` (gần giống) | takumi xếp các trang theo chiều cao chính xác nhưng ngắt theo chiều cao đã cắt xuống 1/64 px; nội dung sau một hộp bị ranh giới trang cắt, và điểm đích outline của một tiêu đề ở trang 2, lệch 0,005 đến 0,0073 px |
| `at-page-first-left-right`, `svg-filters-masks-and-patterns` (gần giống) | số lệch trong khoảng 0.01 |
| `color-glyph-text-shadow` | một `/BBox` của form (124,51 so với 124,546), takumi đo nó trên đường viền đã nét của tiny-skia |
| `named-pages` | trang thân bài ngay trước bảng rộng còn vẽ thêm, ngoài vùng cắt của trang, mấy đoạn viền đầu tiên của bảng (không nhìn thấy); bm-engine dàn trang rộng thành một frame khác ở chiều rộng của nó |
| `inline-span-background-image` | phạm vi nền của một span nội tuyến: 3 mảnh gradient so với 2 |
| `inline-span-background-clip-text-nested`, `background-clip-text-reach` | glyph của span lồng nhau trong mặt nạ `background-clip: text` lệch nhau 41/64 px (chữ nhìn thấy giống nhau); mặt nạ clip-text với tới ngoài hộp bao xa |
| `svg-singular-gradient-transform` | `gradientTransform="scale(0)"`: ma trận suy biến được ghi khác đi, không thấy gì |
| `paged-transforms`, `paged-rotated-text` | hộp bị xoay bị ranh giới trang cắt (xem [Trang](#hạn-chế-đã-biết)) |
| `paged-monolithic-overflow`, `paged-clipped-overflow` | bố cục giống hệt; vùng marked-content và chi tiết clip ở ranh giới trang |
| `list-marker-pagination` | chủ ý: ký hiệu của mục bị chia nằm ở dòng đầu của nó |

118 fixture còn lại, gồm các fixture hoá đơn, header và footer bảng lặp lại và các fixture danh sách, đều giống
hệt. Chương trình font khác nhau ở những fixture mà bộ subset không ghi ra font con trùng từng byte, dù chúng vẽ
cùng các glyph. Các con số này là của một lần chạy tại thời điểm viết và thay đổi theo build; script cần mã nguồn
takumi trong `ref/takumi`. Phân tích theo từng fixture nằm trong `docs/PDF_AUDIT.md` và
`docs/PDF_GOLDEN_DIFFS.md`.

Khi gặp một khác biệt quan trọng, [Xử lý sự cố](../troubleshooting.md) liệt kê các nguyên nhân thường gặp của chữ
bị mất và layout sai; chúng áp dụng cho PDF theo cùng cách.
