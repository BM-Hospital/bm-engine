# Font trong PDF

[English](../../en/pdf/fonts.md) · [Tiếng Việt](fonts.md)

Trong PDF, chữ vẫn là chữ: file chứa các glyph của những font bạn đã đăng ký, được cắt xuống còn các ký tự mà
tài liệu dùng, cộng với bảng ánh xạ để trình xem bôi chọn, tìm kiếm và sao chép được các từ. Trang này nói về cách
font đi vào file (cắt subset, font biến thiên, glyph màu và glyph bitmap), quy tắc fallback, và chuyện gì xảy ra
khi không font nào có một ký tự. Bạn đăng ký font đúng như với ảnh ([Font](../image/fonts.md)); trang này chỉ nói những gì
riêng cho PDF. Nó cần [profile `pdf`](index.md). Mọi đoạn mã Node.js là các đoạn của `docs/examples/pdf-fonts.mjs`
trong repository và đã được chính file đó chạy.

- [Cắt subset](#cắt-subset)
- [Font biến thiên](#font-biến-thiên)
- [Glyph màu và glyph bitmap](#glyph-màu-và-glyph-bitmap)
- [Trích xuất chữ](#trích-xuất-chữ)
- [Font dự phòng](#font-dự-phòng)
- [Ký tự không font nào có](#ký-tự-không-font-nào-có)
- [PDF/A và giấy phép font](#pdfa-và-giấy-phép-font)

## Cắt subset

bm-engine không kèm font và trình xem PDF nào cũng không có font của bạn, nên mọi font mà trang dùng đều được
nhúng. Nó được nhúng dưới dạng subset: chỉ các glyph mà tài liệu thực sự vẽ, được đánh số lại và ghi thành font
CID-keyed. Bộ cắt subset là bản port của crate Rust `subsetter` và đọc font TrueType
(`glyf`), TrueType collection và font CFF (`.otf`); WOFF và WOFF2 được giải mã trước. Bảng `cmap` và các bảng layout
bị bỏ khỏi đầu ra, vì chữ đã được shaping xong.

<!-- @example pdf-fonts#subset -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
const inter = readFileSync("assets/fonts/Inter-Regular.ttf"); // about 400 KB
pdf.registerFont({ name: "Inter", data: inter });

const small = await pdf.render(`<p style="font: 16px Inter">Hello, subset</p>`, { viewport: { width: 300 } });
// small.length is a few KB: only the glyphs the document uses are embedded
```

Trong ví dụ, một font 400 KB cho ra file vài KB. Tập glyph tính theo từng font instance và từng tài liệu: tài liệu
dài hơn nhúng thêm glyph của cùng một font, không phải thêm font.

## Font biến thiên

Font biến thiên theo `font-weight`, `font-stretch`, `font-optical-sizing` và `font-variation-settings` như với
ảnh. Trong PDF, mỗi vị trí khác nhau của font mà tài liệu dùng được **instance hóa**: các glyph được vẽ tại vị trí
đó và ghi thành chương trình font tĩnh riêng. Vì vậy hai độ đậm của một font biến thiên là hai font được nhúng.
Font biến thiên CFF2 được ghi thành font TrueType. Hãy đăng ký font biến thiên mà không có `weight` để nó phục vụ
được mọi độ đậm, như mô tả ở [Font](../image/fonts.md#font-biến-thiên).

<!-- @example pdf-fonts#variable -->
```js
const archivo = readFileSync("./fonts/Archivo-Variable.ttf");
pdf.registerFont({ name: "Archivo", data: archivo }); // no weight: the axes stay free

const weights = await pdf.render(
  `<div style="font: 20px Archivo">
     <p style="font-weight: 300">Light 300</p>
     <p style="font-weight: 700">Bold 700</p>
   </div>`,
  { viewport: { width: 300 } },
);
// each weight actually used is an instance of the variable font: two separate font programs
```

## Glyph màu và glyph bitmap

Font màu cần tính năng `colorFonts`, mà profile `pdf` có. Glyph COLR v0 và v1 (layer, gradient, composite) được vẽ
thành đồ họa vector, còn glyph bitmap (ảnh PNG CBDT và sbix) thành ảnh. Cả hai được đưa vào font Type 3, tối đa 256
glyph mỗi font Type 3, nên một đoạn emoji dài có thể dùng nhiều font. Chữ của chúng vẫn được ánh xạ về Unicode.
Glyph SVG-in-OpenType không được render: các glyph đó được vẽ bằng đường viền thường của chúng, nếu font có.

## Trích xuất chữ

Mọi font mang một bảng `ToUnicode`, và các đoạn sẽ trích xuất sai (ligature và cụm một glyph ứng với nhiều ký tự)
mang `/ActualText` chứa chữ nguồn. Vì vậy sao chép "difficult office" từ trình xem cho ra các chữ cái, không phải
glyph ligature `ffi`, và chữ Ả Rập hay tiếng Việt được trích xuất đúng như đã gõ. Khi một dòng chữ bị chỗ ngắt
trang cắt ngang, trang chứa baseline của nó có chữ còn trang kia hiện phần nhìn thấy dưới dạng đường viền, phần này
không trích xuất được.

## Font dự phòng

Với mỗi ký tự, engine lấy font đầu tiên trong font stack có ký tự đó, rồi đến các font đã đăng ký khác. Bạn không
cần gọi tên family dự phòng: đăng ký thêm một font là đủ.

<!-- @example pdf-fonts#fallback -->
```js
pdf.registerFont({ name: "Noto Sans", data: readFileSync("assets/fonts/NotoSans-Regular.ttf") });
// "ⱥ" (U+2C65) is not in Inter but is in Noto Sans: every registered family is a fallback
const mixed = pdf.renderSync(`<p style="font: 20px Inter">Inter text and ⱥ</p>`, { viewport: { width: 400 } });
// Inter draws the Latin text and Noto Sans draws ⱥ: two font programs in the file
```

Dùng `unicodeRange` khi một file font chỉ chứa một phần của family. Có thể truyền các cặp mã Unicode
hoặc chuỗi theo cú pháp CSS `unicode-range`; ký tự ngoài phạm vi sẽ tiếp tục đi qua chuỗi font dự phòng.
Thuộc tính `unicode-range` trong CSS `@font-face` cũng có tác dụng tương tự:

```js
pdf.registerFont({ name: "Inter", data: inter, unicodeRange: "U+0000-00FF" });
```

`fontFamilies: ["Inter", "Noto Sans"]` đặt font stack có thứ tự cho một lần render khi tài liệu không nêu tên font
nào (ví dụ node không có `fontFamily`):

<!-- @example pdf-fonts#font-families -->
```js
const stacked = pdf.renderSync(`<p>No font-family on this paragraph</p>`, {
  viewport: { width: 400 },
  fontFamilies: ["Noto Sans"], // the font stack used where the document names none
});
```

Font chưa đăng ký không bao giờ được tìm trong hệ thống; không có font mặc định.

## Ký tự không font nào có

Ký tự mà không font đã đăng ký nào vẽ được sẽ do `uncoveredText` xử lý:

| Giá trị | Chuyện gì xảy ra |
|:--|:--|
| `"error"` (mặc định) | Render lỗi và nêu tên ký tự. |
| `"placeholder"` | Vẽ glyph 0 của font (`.notdef`, thường là một ô trống). |
| `"blank"` | Không vẽ gì cho nó. |

<!-- @example pdf-fonts#uncovered-error -->
```js
const devanagari = `<p style="font: 20px Inter">abक</p>`;
let message;
try {
  await pdf.render(devanagari, { viewport: { width: 300 } });
} catch (e) {
  message = e.message;
}
// bm-engine: No font the text can use draws क (U+0915). Check each font's unicodeRange and the font-family stack,
// or register a font that draws them.
```

<!-- @example pdf-fonts#uncovered-modes -->
```js
const blank = await pdf.render(devanagari, { viewport: { width: 300 }, uncoveredText: "blank" });             // draws "ab"
const boxes = await pdf.render(devanagari, { viewport: { width: 300 }, uncoveredText: "placeholder" });       // draws "ab" and the font's .notdef box
```

Lỗi là mặc định vì lặng lẽ làm rơi ký tự trong một tài liệu còn tệ hơn một lỗi mà bạn thấy khi thử. `placeholder`
bị từ chối, kèm thông báo nêu tên chuẩn, bất cứ khi nào đặt `pdfa` hoặc `tagged` là `"ua1"` hay `"ua2"`, vì các
chuẩn đó cấm glyph 0 (chỉ khi tài liệu thực sự có ký tự không được phủ):

<!-- @example pdf-fonts#archival-placeholder -->
```js
let archival;
try {
  await pdf.render(devanagari, { viewport: { width: 300 }, pdfa: "2b", uncoveredText: "placeholder" });
} catch (e) {
  archival = e.message;
}
// bm-engine: No font the text can use draws क (U+0915), and PDF/A-2b forbids the placeholder glyph. Register a font that draws them, or set uncoveredText to "blank".
```

## PDF/A và giấy phép font

PDF/A và PDF/UA cũng kiểm tra font bạn nhúng. Font có `fsType` trong OS/2 ghi "restricted license embedding" làm
render lỗi bằng một lỗi kiểm tra ở mọi mức `pdfa` hoặc `tagged: "ua1"` / `"ua2"` (PDF thường vẫn nhúng nó: hãy tự
kiểm tra giấy phép font). Glyph không có ánh xạ Unicode và glyph `.notdef` cũng là vi phạm. Lỗi không nêu tên font;
thông báo chỉ là số lượng vi phạm ([Khả năng truy cập và lưu trữ](accessibility.md#các-kiểm-tra-đi-xa-đến-đâu)).
