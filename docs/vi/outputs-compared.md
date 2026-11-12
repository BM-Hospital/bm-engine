# So sánh Image, PDF và Paint

[English](../en/outputs-compared.md) · [Tiếng Việt](outputs-compared.md)

Tài liệu của takumi được chia thành ba phần — **Image**, **PDF** và **Paint** — vì takumi cung cấp ba
loại đầu ra, dưới dạng ba package riêng, cùng dựa trên một layout engine. bm-engine chỉ port loại đầu
tiên. Trang này giải thích mỗi đầu ra của takumi dùng để làm gì, bm-engine hiện đáp ứng tới đâu, và làm
sao tiến gần tới hai loại còn lại bằng bm-engine kết hợp với công cụ khác.

::: info Trạng thái kiểm chứng
Phần mô tả takumi đã được đối chiếu với mã nguồn và tài liệu takumi trong bản sao tham chiếu của
repository (`ref/takumi`: các crate / package `takumi-core`, `takumi-raster`, `takumi-svg`, `takumi-pdf`,
`takumi-pdf-js` và `takumi-paint` cùng `docs/content/docs/{pdf,paint}`); không chạy mã takumi nào. Các
nhận định về bm-engine được kiểm tra bằng cách tìm trong `js/` và `src/` và chạy các API được nhắc tới.
:::

## Một layout engine, ba đầu ra

```
            JSX / HTML / node tree + CSS
                        |
                takumi-core (style, layout, text)
          ______________|______________________________
         |                         |                   |
  takumi-raster / takumi-svg    takumi-pdf          takumi-paint
  -> PNG, JPEG, WebP, ICO,      -> paged PDF        -> paint tree (boxes,
     raw pixels, SVG,                                  text runs, images
     animated WebP/APNG/GIF                            in paint order)
  npm: takumi-js,               npm: takumi-pdf     npm: takumi-paint
  @takumi-rs/wasm, /core
```

| | Image | PDF | Paint |
|:--|:--|:--|:--|
| Crate của takumi | `takumi-raster` (vẽ bằng tiny-skia), `takumi-svg` (SVG vector) | `takumi-pdf` ("vector PDF output backend ... selectable, searchable text with embedded subset fonts") | `takumi-paint` |
| Package npm | `takumi-js`, `@takumi-rs/wasm`, `@takumi-rs/core` | `takumi-pdf` | `takumi-paint` |
| Bạn nhận được | byte ảnh đã mã hóa (hoặc một chuỗi SVG, hoặc một animation) | một file PDF | một cây object JavaScript để bạn tự vẽ |
| Công dụng điển hình | thẻ Open Graph, thumbnail, ảnh mạng xã hội | hóa đơn, báo cáo, vé, chứng nhận | slide chỉnh sửa được (PPTX), vẽ bằng Canvas / Skia / API native, renderer tự viết |
| bm-engine | **đã port** (raster, SVG, animation) | **không có** | **không có** (chỉ có `measure()`) |

### Image

Thứ mà mọi trang khác của bộ tài liệu này nói tới: dàn layout một canvas duy nhất có kích thước cho
trước rồi vẽ ra pixel (hoặc ra các phần tử SVG). Đầu ra là một ảnh (hoặc một chuỗi khung hình). Chữ trở
thành pixel hoặc đường viền glyph; không bôi chọn được.

### PDF (`takumi-pdf`)

Một renderer tài liệu, không phải "một ảnh nằm trong PDF". Theo tài liệu PDF của takumi:

- **Phân trang**: nội dung chảy qua các trang có kích thước tùy chọn (`a4`, `letter`, ... hoặc tự đặt),
  với lề tự động hoặc tường minh, quy tắc `@page` (`:first`, `:left`, `:right`, trang có tên) và CSS
  fragmentation (`break-before`, `break-inside: avoid`, lặp lại tiêu đề bảng).
- **Header và footer** lặp lại trên mọi trang, kèm các primitive số trang (`PageNumber`, `TotalPages`).
- **Chữ thật**: bôi chọn và tìm kiếm được, font được nhúng dạng subset.
- **Liên kết, outline và metadata**: `<a href>` bấm được, bookmark / mục lục, thuộc tính tài liệu.
- **Chuẩn tuân thủ**: các mức lưu trữ PDF/A (ví dụ `pdfa: "3b"`) và tagged PDF / kiểm tra PDF/UA.
- **Tệp đính kèm**: nhúng file, chẳng hạn XML hóa đơn Factur-X.

### Paint (`takumi-paint`)

Layout mà không raster hóa: `paint()` trả về một **paint tree** — mọi box với nền, viền và bóng đổ đã
được resolve, mọi đoạn văn dưới dạng các text run đã shape kèm font, mọi ảnh — theo thứ tự vẽ (đã xử lý
`z-index`), mỗi phần tử có một transform. Tài liệu takumi định vị nó cho việc xuất slide PPTX chỉnh sửa
được, vẽ lên Canvas / Skia / API native, hoặc đọc xem layout đặt từng box và từng dòng ở đâu.

## bm-engine đáp ứng những gì

Đã kiểm tra trong mã nguồn và typings của bm-engine 0.1.0:

| Khả năng | bm-engine |
|:--|:--|
| Đầu ra raster (PNG, JPEG, WebP, RGBA thô, ICO) | có — `render` / `renderSync`, `renderAsDataUrl` |
| Đầu ra SVG | có — `renderSvg` / `renderSvgSync` (profile `full`); chữ thành đường viền glyph, ảnh nhúng dạng URL `data:` |
| Đầu ra động | có — `renderAnimation` (`full`): WebP động, APNG, GIF |
| Đầu ra PDF | **không** — không có trình ghi PDF nào trong `src/` hay `js/` (chữ "PDF" duy nhất trong mã nguồn là ký tự điều khiển bidi Unicode U+202C POP DIRECTIONAL FORMATTING) |
| Phân trang / fragmentation qua nhiều trang | **không** — mỗi lần render là một canvas |
| Paint tree | **không** — không có API nào trả về lệnh vẽ, màu, gradient hay glyph |
| Box layout | có — `measure()` trả về cây box: `width` / `height` của border box, một `transform` 2D (vị trí tuyệt đối), `children`, và `runs` của các dòng chữ (`x`, `y`, `width`, `height`; không có chữ, không có font, không có vị trí glyph) |

## Cách xoay xở (không có sẵn)

Không cái nào dưới đây là tính năng của bm-engine; chúng kết hợp bm-engine với công cụ khác.

### Tạo PDF từ đầu ra của bm-engine

- **Mỗi trang một ảnh.** Render từng trang thành PNG ở độ phân giải in (một trang A4 ở 150 dpi là
  1240 × 1754 px; render `width: 1240, height: 1754` với `devicePixelRatio` phóng layout CSS 96 dpi của bạn
  theo tỉ lệ 150 / 96) rồi đặt các ảnh vào PDF bằng một thư viện PDF (ví dụ pdf-lib trong JavaScript).
  Chữ không bôi chọn được và file lớn; ổn cho chứng nhận hay vé, kém cho tài liệu dài.
- **Mỗi trang một SVG.** `renderSvg` cho đầu ra vector; các công cụ chuyển SVG sang PDF (`rsvg-convert`
  của librsvg, Inkscape, các thư viện svg2pdf) giữ hình sắc nét. Chữ vẫn là đường viền, không bôi chọn được.
- **Tự phân trang.** bm-engine không chia nội dung qua nhiều trang. Dùng `measure()` để biết các khối kết
  thúc ở đâu rồi tự quyết định chỗ ngắt trang, hoặc render mỗi trang từ cây node riêng của nó.

Nếu bạn cần chữ bôi chọn được, liên kết, PDF/A hay tệp đính kèm, hãy dùng một engine PDF thật sự
(takumi-pdf, một trình duyệt headless, hoặc một thư viện PDF) — bm-engine không tạo ra được những thứ đó.

### Dựng paint tree từ `measure()`

`measure()` cho bạn hình học; còn style thì bạn đã biết vì chính bạn viết cây. Duyệt song song cả hai và
vẽ bằng API của riêng bạn:

```js
const layout = renderer.measureSync(node, { width: 1200, height: 630 });

function walk(n, m, draw) {
  const [a, b, c, d, x, y] = m.transform;           // absolute 2D matrix
  draw({ node: n, x, y, width: m.width, height: m.height, matrix: [a, b, c, d, x, y] });
  for (const run of m.runs) draw({ node: n, run: { x: x + run.x, y: y + run.y, width: run.width, height: run.height } });
  const kids = (n.children ?? []).filter((k) => k && k.type === "container"); // see the caveat below
  m.children.forEach((child, i) => kids[i] && walk(kids[i], child, draw));
}
```

Đã kiểm chứng trên một cột gồm một tiêu đề xuống dòng và một box 200 × 60: lượt duyệt tạo ra ba box (box
ở x = 40, 200 × 60) và một lệnh vẽ cho mỗi dòng chữ (`docs/examples/frameworks/check-outputs.mjs`).
Lưu ý, xuất phát từ định dạng đầu ra của measure: node text nằm trong một block flow không có mục riêng
(các dòng của nó xuất hiện dưới dạng `runs` của box chứa nó), nên việc ghép con đã measure với con trong
cây nguồn cần cẩn thận; run không mang chữ hay font; màu, gradient và viền là bất cứ gì bạn đặt trong
`style`, không phải giá trị đã resolve. Trang [Measure](./measure.md) mô tả chính xác đầu ra. Muốn vẽ mọi
thứ chính xác tới từng pixel, hãy render bằng bm-engine rồi vẽ ảnh đó.

## Nên dùng gì

| Bạn cần | Dùng |
|:--|:--|
| Thẻ mạng xã hội, thumbnail, ảnh tạo tự động | bm-engine (`core` / `standard`) |
| Bản SVG của cùng tấm thẻ | bm-engine `full` + `renderSvg` |
| Animation ngắn | bm-engine `full` + `renderAnimation` |
| Co giãn chữ cho vừa, kiểm tra layout trước khi render | bm-engine `measure()` |
| Tài liệu nhiều trang với chữ bôi chọn được | takumi-pdf hoặc một engine PDF khác |
| Slide chỉnh sửa được / renderer riêng với đầy đủ thông tin style | takumi-paint |
