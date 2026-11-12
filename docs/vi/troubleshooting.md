# Xử lý sự cố và câu hỏi thường gặp

[English](../en/troubleshooting.md) · [Tiếng Việt](troubleshooting.md)

Những triệu chứng bạn dễ gặp với bm-engine 0.1.0, nguyên nhân và cách khắc phục. Phần lớn xuất phát từ
hai quyết định thiết kế kế thừa từ takumi (`display` mặc định là `inline`; đầu vào không bao giờ được tải
về) và một quyết định riêng của bm-engine (không kèm font).

- [Chữ không hiện, hoặc hiện thành ô vuông](#chữ-không-hiện-hoặc-hiện-thành-ô-vuông)
- [Khối chứa bị co về chiều cao 0](#khối-chứa-bị-co-về-chiều-cao-0)
- ["this build has no ... support"](#this-build-has-no--support)
- [Ảnh không hiện](#ảnh-không-hiện)
- [Không tìm thấy file .wasm (bundler, worker)](#không-tìm-thấy-file-wasm)
- [Bộ nhớ tăng mãi](#bộ-nhớ-tăng-mãi)
- [Ảnh bị mờ trên màn hình DPI cao](#ảnh-bị-mờ-trên-màn-hình-dpi-cao)
- [Tiếng Việt](#tiếng-việt)
- [Emoji không có màu](#emoji-không-có-màu)
- [Một style bị bỏ qua](#một-style-bị-bỏ-qua)
- ["invalid value for style property"](#invalid-value-for-style-property)
- [Các lỗi khác](#các-lỗi-khác)

## Chữ không hiện, hoặc hiện thành ô vuông

- **Hoàn toàn không vẽ gì**: chưa có font nào được đăng ký trên `Renderer` này (hoặc đã gọi
  `clearFonts()`). bm-engine không kèm font và không bao giờ đọc font hệ thống. Hãy đăng ký một font:
  `renderer.registerFont(readFileSync("Inter-Regular.ttf"))`. Font được giữ riêng theo từng renderer.
- **Một số ký tự thành ô vuông (tofu)**: không font nào đã đăng ký chứa các ký tự đó; chúng được vẽ bằng
  glyph `.notdef`. Hãy đăng ký font phủ hệ chữ đó (ví dụ Noto Sans JP cho tiếng Nhật). Font dự phòng vốn
  đã duyệt mọi family đã đăng ký theo thứ tự đăng ký (kể cả khi bạn truyền `fontFamilies`, tùy chọn này
  chỉ đặt bộ font gốc).
- **Sai font**: tên family dùng trong `fontFamily` phải trùng với tên đã đăng ký — tức `name` bạn truyền
  vào, hoặc tên family của chính font (`registerFont` trả về tên này).
- **Font `.woff2` / `.otf` ném lỗi**: `core` không có WOFF và CFF; dùng `standard` / `full`, hoặc add-on
  WOFF cho WOFF (outline CFF vẫn cần `standard`).

## Khối chứa bị co về chiều cao 0

`display` mặc định là `inline` cho mọi node, giống takumi và CSS. Một container inline bỏ qua
`width` / `height`, nên hai con có kích thước bên trong một block container sẽ nằm trên một dòng rỗng:

```js
r.measureSync({ type: "container", style: { display: "block" }, children: [
  { type: "container", style: { width: 50, height: 50 } },
  { type: "container", style: { width: 50, height: 50 } },
] }, { width: 200, height: 200 });
// -> { width: 200, height: 0, ... }   (takumi cho cùng kết quả)
```

Hãy đặt `display: "flex"`, `"block"` hoặc `"grid"` tường minh cho các container. Con của flex hoặc grid
container được blockify tự động, nên chỉ chính các container cần đặt. Node chữ trong flex container
không cần gì thêm.

## "this build has no ... support"

Profile đang nạp không có tính năng đó. Các thông báo và profile nhỏ nhất có tính năng:

| Thông báo (tiền tố `bm-engine: `) | Cần |
|:--|:--|
| `this build has no HTML input support` | `standard` |
| `this build has no stylesheet (\`css\` option) support` | `standard` |
| `Tailwind (\`tw\`) is not supported by this build` | `standard` |
| `this build has no WOFF/WOFF2 font support` | `standard`, hoặc `loadWoff()` từ `bm-engine/woff` |
| `unsupported font format` (một file `.otf`) | `standard` (CFF) |
| `invalid value for style property backgroundColor` với `oklch()` / `lab()` / `color-mix()` trên core | `standard` |
| `this build has no ICO output support`, `... renderSvg support`, `... animation support` | `full` (thông báo ghi "use the full build") |

Kiểm tra `features` khi khởi động, import profile lớn hơn (`bm-engine/standard`, `bm-engine/full`), hoặc
xem [Profile và kích thước](profiles-and-size.md).

## Ảnh không hiện

- **URL không bao giờ được tải về.** `src: "https://..."` chỉ dùng để tra một mục trong tùy chọn `images`.
  Hãy tự tải byte rồi truyền `images: [{ src: "https://...", data: bytes }]`.
- **`Buffer` của Node truyền thẳng vào `src`** dùng được; không cần bọc `new Uint8Array(buffer)` (chuỗi URL vẫn cần tùy chọn `images`).
- **SVG, WebP hoặc GIF trên `core`**: không được giải mã ở đó; dùng `standard`.
- **WebP lossy hoặc nguồn ảnh động trên `standard`**: cần `full`.
- **`images[].data` dạng lười với phương thức sync** sẽ ném lỗi `lazy images[].data() needs the async
  API`; dùng `render()` / `prepare()`.
- **Node ảnh không có kích thước**: ảnh có `src` không biết hoặc không giải mã được có kích thước nội tại
  0 × 0; đặt `width` / `height` nếu layout không được phụ thuộc vào nó.

## Không tìm thấy file .wasm

- **Trình duyệt / bundler**: import một entry theo profile (`bm-engine/full`, `/standard`, `/core`) rồi
  gọi `await init()`. Các entry này tham chiếu binary bằng `new URL("./bm_engine....wasm",
  import.meta.url)`, được Vite, webpack 5, Rollup (kèm plugin asset) và Parcel xuất thành asset. Nếu
  bundler của bạn không làm vậy, hãy import URL của binary một cách tường minh (`import wasmUrl from
  "bm-engine/full.wasm?url"` trong Vite) hoặc chép file vào thư mục public rồi gọi
  `init("/bm_engine.wasm")`.
- **Entry chung `bm-engine` bên ngoài Node** không có vị trí mặc định: `init()` không đối số sẽ ném lỗi
  `bm-engine: init() needs the wasm binary ...`. Hãy truyền byte, URL / `Response` hoặc
  `WebAssembly.Module`, hoặc chuyển sang entry theo profile.
- **Cloudflare Workers** không cho biên dịch WebAssembly từ byte lúc chạy: hãy import module
  (`import wasm from "bm-engine/full.wasm"`) rồi truyền vào `init` / `initSync`.
- **Sai content type**: nếu server không gửi `application/wasm`, `init` chuyển sang đường không
  streaming. Cách đó vẫn chạy, nhưng một trang HTML 404 sẽ không biên dịch được — hãy kiểm tra URL.
- **Node trong môi trường tùy biến**: `BM_WASM=/path/to/bm_engine.wasm` thay binary của entry
  `bm-engine`.

## Bộ nhớ tăng mãi

Bộ nhớ WebAssembly chỉ tăng chứ không bao giờ co lại. bm-engine tái sử dụng bộ nhớ giữa các lần render
(một arena cho mỗi lần render, các cache có ngân sách cố định: ảnh đã giải mã bị xoá khi vượt 96 MiB,
glyph khi vượt 8 MiB), nên một tải ổn định sẽ dừng ở một mức — khoảng 6 MiB với thẻ 1200 × 630 và một
font. Những gì làm nó tăng:

- **Canvas lớn**: một lần render 3000 × 2000 đẩy instance lên khoảng 29 MiB và giữ nguyên ở đó. Nếu điều
  này quan trọng, hãy render ảnh lớn trong một instance riêng (worker).
- **Nhiều renderer**: mỗi renderer giữ font và cache riêng. Dùng lại một renderer cho mỗi bộ font; gọi
  `free()` (hoặc `using`) khi không dùng nữa. Bộ nhớ đã giải phóng được tái sử dụng cho lần render sau
  nhưng không trả lại cho hệ điều hành.
- **Nhiều ảnh lớn**: mỗi renderer cache tới 96 MiB ảnh đã giải mã.

`renderer.memoryBytes()` cho biết kích thước bộ nhớ tuyến tính hiện tại. Muốn reset hoàn toàn, hãy bỏ cả
instance (một worker thread hoặc một isolate mới).

## Ảnh bị mờ trên màn hình DPI cao

Render nhiều điểm ảnh hơn mà giữ nguyên layout CSS: đặt canvas bằng kích thước thiết bị và
`devicePixelRatio` bằng hệ số tỉ lệ. `devicePixelRatio` nhân các độ dài CSS px và cỡ chữ nhưng không đổi
kích thước canvas:

```js
// a 1200 × 630 design rendered for a 2× screen
const png = renderer.renderSync(node, { width: 2400, height: 1260, devicePixelRatio: 2 });
```

`%`, `vw` và `vh` vốn đã tính theo canvas nên không cần đổi. Sau đó hiển thị ảnh ở một nửa kích thước
điểm ảnh (`<img width="1200">`).

## Tiếng Việt

- Dùng font phủ đủ tiếng Việt (Inter, Noto Sans, Roboto, Be Vietnam Pro, ...). Chữ dựng sẵn bị thiếu
  (`ắ`, `ợ`, ...) sẽ hiện thành ô vuông.
- Chuẩn hoá đầu vào của người dùng về NFC (`text.normalize("NFC")`). Chữ dựng sẵn hiển thị đúng trên mọi
  profile; chữ tổ hợp (NFD) phụ thuộc vào định vị dấu (mark positioning) của font, và chỉ profile `full`
  tự chuẩn hoá giúp bạn.
- Ngắt dòng theo UAX #14 và ngắt tại dấu cách, đúng như tiếng Việt cần; `text-wrap: balance`
  (standard / full) cho tiêu đề cân đối hơn.
- Các fixture `text-vietnamese*` trong repository render tương đương takumi.

## Emoji không có màu

Emoji màu cần **cả** profile `full` (`features.colorFonts`) lẫn một font emoji màu đã đăng ký (COLR,
CBDT hoặc sbix, ví dụ Noto Color Emoji). Không có font, emoji hiện thành ô vuông hoặc glyph của font
khác; trên `core` / `standard` font màu được vẽ không màu. Chỉ cần đăng ký font là đủ — font dự phòng
duyệt mọi family đã đăng ký.

## Một style bị bỏ qua

- Khoá của `style` inline phải là **camelCase**: `backgroundColor`, không phải `"background-color"` (khoá
  kebab-case bị bỏ qua im lặng, giống takumi). Trong stylesheet, HTML và `tw` thì dùng cú pháp CSS bình
  thường.
- Thuộc tính cần profile lớn hơn (ví dụ `float`, `clipPath` hay `mixBlendMode` trên `core` được chấp
  nhận nhưng bị bỏ qua).
- Khai báo trong stylesheet hoặc Tailwind có giá trị không hợp lệ bị loại im lặng. Hãy thử nó dưới dạng
  style inline, vốn ném lỗi với giá trị không hợp lệ.
- Các variant Tailwind ngoài breakpoint, variant cấu trúc và `before:` / `after:` (`hover:`, `dark:`,
  `group-*:`) không bao giờ được áp dụng, và `animate-*` không được hỗ trợ — giống takumi.
- Xem danh sách [thuộc tính parse được nhưng chưa cài đặt](css-support.md#phụ-lục-danh-sách-thuộc-tính-được-hỗ-trợ).

## "invalid value for style property"

Một giá trị trong `style` (hoặc `preset`) inline không parse được; toàn bộ lần render ném lỗi, giống
takumi. Nguyên nhân thường gặp: gõ sai (`"10 px"`), transform 3D (`rotateX()`), cú pháp màu tương đối,
hàm màu hiện đại trên `core`. Khai báo trong stylesheet không ném lỗi; chúng bị loại bỏ.

## Các lỗi khác

| Thông báo (tiền tố `bm-engine: `) | Nguyên nhân |
|:--|:--|
| `call init()/initSync() before creating a Renderer` | ngoài Node, entry chưa được khởi tạo |
| `renderer has been freed` | dùng renderer sau khi đã `free()` |
| `invalid viewport: width/height must be > 0` | `width` hoặc `height` bằng 0 |
| `invalid viewport: content has zero size and no width/height was given` | không có kích thước canvas và không có gì để đo |
| `canvas too large` | hơn 16384 px mỗi cạnh hoặc 40 megapixel |
| `node tree is nested too deeply` | lồng quá 512 cấp |
| `node is missing \`type\`` / `text node is missing \`text\`` | node sai định dạng |
| `invalid node JSON` | nguồn `{ json }` sai định dạng |
| `unsupported format: <x>` | `format` không phải png / jpeg / webp / raw / ico |
| `raw image data length must be width*height*4` | object ảnh RGBA có độ dài sai |
| `renderAsDataUrl needs an encoded format` | `format: "raw"` với `renderAsDataUrl` (`"jpg"` vẫn dùng được: đó là bí danh của `"jpeg"`) |
| `Frame rate N fps exceeds the maximum ...` | GIF > 50 fps, WebP / APNG > 90 fps |
| `invalid font data` | không phải file font |
