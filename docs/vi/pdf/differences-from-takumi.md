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
- **Không có bước `needs`.** `prepare` không tải gì về và file của `@font-face` không được tải: hãy truyền byte ảnh
  qua `images` và font qua `fonts` / `registerFont`.
- **Bộ đếm trong nội dung sinh ra** (`counter(page)`, `target-counter()`) không hoạt động, giống takumi; hãy dùng
  `PageNumber`, `TotalPages` và `TargetPageNumber` ([Header, footer và bộ đếm trang](headers-footers.md)).

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
  không được hỗ trợ. Xem [Phân trang](pagination.md#quy-tắc-trang).
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
  truy cập và lưu trữ](accessibility.md#các-kiểm-tra-đi-xa-đến-đâu).
- **Chương trình font nhúng.** Các font con trong file không phải lúc nào cũng trùng từng byte với font mà
  takumi-pdf ghi, dù chúng vẽ cùng các glyph.


## So với golden của takumi-pdf

`node scripts/pdf-compare.mjs` render đầu vào của từng fixture trong 89 fixture golden của takumi-pdf
(`takumi-pdf/tests/fixtures-generated/*.pdf`) bằng `bm-engine/pdf`, phân tích cả hai file và so từng trang theo
từng toán tử sau khi thay số hiệu object và tên resource bằng thứ chúng trỏ tới (font, ảnh, shading, soft mask,
form XObject). Font, cây cấu trúc, annotation, outline, metadata và tệp đính kèm được so riêng. Trong lần chạy
cho trang này:

| Kết quả | Số fixture |
|:--|--:|
| nội dung trang giống hệt | 73 |
| gần giống: cùng toán tử, số lệch trong khoảng 0.01 | 3 |
| khác | 13 |
| lỗi render | 0 |
| bố cục object giống hệt | 89 |
| chương trình font nhúng giống hệt | 42 |
| cây cấu trúc giống hệt | 88 |

13 khác biệt, theo fixture:

| Fixture | Khác ở đâu |
|:--|:--|
| `text-shadow-stroke`, `text-decoration-shadow`, `color-glyph-text-shadow`, `text-stroke-paint-order`, `svg-background-image` | toạ độ đường viền glyph lệch ở chữ số có nghĩa thứ ba hoặc thứ tư (độ chính xác của outline) |
| `text-decoration-styles` | độ rộng một nét gạch trong gạch trang trí kiểu dashed |
| `bitmap-glyph-text-shadow` | soft mask của bóng một glyph bitmap |
| `report-links-outline`, `report-tagged-ua1`, `report-tagged-a2a` | các điều chỉnh kerning rất nhỏ và hình chữ nhật của liên kết (annotation) |
| `stream-content-counters` | độ rộng chỗ giữ chỗ của bộ đếm trang |
| `named-pages`, `at-page-first-left-right` | các trang có chiều rộng khác nhau: bm-engine dàn nội dung một lần ở một chiều rộng ([Trang có tên](pagination.md#trang-có-tên)) |

Ba fixture gần giống là `text-shadow-page-cut`, `content-page-counters` và `at-page-root-element`. Các fixture
hoá đơn, header và footer bảng lặp lại, và các fixture danh sách đều giống hệt. Chương trình font khác nhau ở các
fixture còn lại vì bộ subset không ghi ra font con trùng từng byte, dù chúng vẽ cùng các glyph. Các con số này là
của một lần chạy tại thời điểm viết và thay đổi theo build; script cần mã nguồn takumi trong `ref/takumi`.

Khi gặp một khác biệt quan trọng, [Xử lý sự cố](../troubleshooting.md) liệt kê các nguyên nhân thường gặp của chữ
bị mất và layout sai; chúng áp dụng cho PDF theo cùng cách.
