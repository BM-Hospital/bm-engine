# Khác biệt so với takumi và hướng dẫn chuyển đổi

[English](../en/differences-from-takumi.md) · [Tiếng Việt](differences-from-takumi.md)

bm-engine là bản viết lại bằng Zig phần renderer của [takumi](https://github.com/kane50613/takumi) 2.20
(`@takumi-rs/wasm`), không phải một bản fork: nó nhận cùng cây node, HTML, stylesheet, class Tailwind và
tùy chọn render, và được phát triển với takumi làm oracle cho tới khi đầu ra khớp (250/250 fixture
benchmark identical hoặc equivalent). Trang này liệt kê những gì thay đổi khi chuyển từ
`@takumi-rs/wasm` hay `takumi-js` sang bm-engine, các khác biệt còn lại về API và kết quả render, và các
hành vi của takumi mà bm-engine cố ý tái hiện.

- [Chuyển đổi trong năm bước](#chuyển-đổi-trong-năm-bước)
- [Ví dụ đặt cạnh nhau](#ví-dụ-đặt-cạnh-nhau)
- [Khác biệt về API](#khác-biệt-về-api)
- [Khác biệt khi render](#khác-biệt-khi-render)
- [Chưa port](#chưa-port)
- [Những hành vi của takumi được bm-engine cố ý giữ nguyên](#những-hành-vi-của-takumi-được-bm-engine-cố-ý-giữ-nguyên)

## Chuyển đổi trong năm bước

1. **Thay package.** `@takumi-rs/wasm`, `@takumi-rs/wasm/node` và `@takumi-rs/core` → `bm-engine` (hoặc
   `bm-engine/core` / `bm-engine/standard` nếu muốn binary nhỏ hơn; xem [Profile](profiles-and-size.md)).
   Lớp `Renderer` giữ nguyên tên và các phương thức.
2. **Khởi tạo.** Trên Node.js không có gì thay đổi: entry tự khởi tạo khi import (giống
   `@takumi-rs/wasm/node`). Ở môi trường khác, `init({ module_or_path })` vẫn dùng được; với các entry
   theo profile bạn chỉ cần gọi `await init()`. Trên Cloudflare Workers hãy import `bm-engine/full.wasm`
   thay cho `@takumi-rs/wasm/takumi_wasm_bg.wasm`.
3. **Đăng ký font.** takumi kèm sẵn font Geist làm font dự phòng cuối cùng; bm-engine không kèm font
   nào. Nếu không gọi `registerFont` (hoặc dùng tùy chọn `fonts`) thì chữ sẽ không được vẽ.
4. **Tự tải tài nguyên từ xa.** `prepare()` của bm-engine không tải ảnh hay file `@font-face`. Truyền byte
   ảnh qua `images`, font qua `registerFont` / `fonts`.
5. **JSX.** bm-engine nhận cây node, `{ json }` và HTML, không nhận JSX. Hãy tiếp tục dùng
   `@takumi-rs/helpers` để chuyển: `await fromJsx(element)` (hàm async) trả về `{ node, css }`, rồi truyền vào
   `render(node, { css, ... })` (đã kiểm tra với một React element dựng tay; chưa thử với chính React).
   Không có `ImageResponse`; hãy tự bọc byte vào một `Response`.

## Ví dụ đặt cạnh nhau

takumi (`@takumi-rs/wasm`, dùng bundler):

```js
import init, { Renderer } from "@takumi-rs/wasm";
import wasmUrl from "@takumi-rs/wasm/wasm-url";

await init({ module_or_path: wasmUrl });
const renderer = new Renderer();
await renderer.registerFont(await (await fetch("/Inter.ttf")).arrayBuffer()); // tùy chọn: Geist có sẵn

const png = await renderer.render(
  { type: "container", style: { display: "flex", width: "100%", height: "100%" },
    children: [{ type: "text", text: "Hello", style: { fontSize: 64 } }] },
  { width: 1200, height: 630, images: [{ src: "logo", data: logoBytes }] },
);
```

bm-engine:

```js
import { init, Renderer } from "bm-engine/full";

await init(); // tìm bm_engine.wasm cạnh module; init({ module_or_path: url }) cũng dùng được
const renderer = new Renderer();
renderer.registerFont(await (await fetch("/Inter.ttf")).arrayBuffer()); // bắt buộc: không có font dựng sẵn

const png = await renderer.render( // hoặc renderer.renderSync(...)
  { type: "container", style: { display: "flex", width: "100%", height: "100%" },
    children: [{ type: "text", text: "Hello", style: { fontSize: 64 } }] },
  { width: 1200, height: 630, images: [{ src: "logo", data: logoBytes }] },
);
```

Hàm `render(jsx, options)` cấp cao nhất của `takumi-js` tương ứng với `new Renderer()` +
`renderer.render(node, options)` sau khi chuyển JSX bằng `fromJsx` (xem bước 5).

## Khác biệt về API

| Hạng mục | takumi 2.20 | bm-engine 0.1.0 |
|:--|:--|:--|
| Package / định dạng module | `@takumi-rs/wasm` (ESM + CJS), `@takumi-rs/core` (native N-API) | `bm-engine`, chỉ ESM (CommonJS qua `require(esm)`), chỉ WebAssembly — không có binding native |
| Binary | một file wasm 4.2 MB | ba profile (454.5 KiB – 1.07 MiB) + add-on WOFF; `features` cho biết bản đang nạp |
| Import của wasm | glue wasm-bindgen | không có |
| API đồng bộ | các phương thức của wrapper đều async | mọi phương thức có bản `*Sync`; bản async resolve ngay |
| `registerFont` | trả về `Promise<RegisteredFamily[]>` (wrapper) | trả về `RegisteredFamily[]` đồng bộ với byte / `{ data: bytes }`; chỉ trả `Promise` với URL và dữ liệu lười |
| `unicodeRange`, `subsetOf`, `generic` (FontDetails) | subset tải lười, family generic | nhận nhưng bỏ qua: mọi face được đăng ký ngay; tên generic không được ánh xạ |
| `cacheFont`, `cachedFonts`, `cacheFontFile`, `needs`, `animationNeeds` | có | không có |
| Font dựng sẵn | Geist (biến thiên, `clearFonts` vẫn giữ lại) | không có |
| `prepare` / `prepareAnimation` | tải ảnh từ xa và file `@font-face` (bước needs) | chỉ xử lý `fonts` và `images` lười; không tải gì |
| URL từ xa khi `render` | không tải nếu không qua `prepare` | không bao giờ tải |
| `new Renderer({ cacheMaxBytes, fontCacheMaxBytes })`, `setGlyphCacheMaxBytes` | cache cấu hình được | nhận nhưng bỏ qua (cố định 96 MiB ảnh / 8 MiB glyph) |
| `drawDebugBorder`, `dithering` | có hỗ trợ | nhận nhưng bỏ qua |
| Kết quả `measure` | run có `text`, chiều cao theo hộp glyph | cùng cây, hộp và vị trí; run không có `text` và dùng chiều cao dòng (xem [API](api.md#measure--measuresync)) |
| `renderSvg` | takumi-svg | đã port (profile full): cùng cấu trúc, glyph dưới dạng outline, không nhúng font |
| PDF (`takumi-pdf`) | package riêng | không port |
| `ImageResponse`, `render()` JSX (`takumi-js`) | có | không có; dùng `@takumi-rs/helpers` + `new Response(...)` |
| `memoryBytes()` | — | bổ sung: kích thước bộ nhớ wasm hiện tại |
| Lỗi | `Error` với thông báo của takumi | `Error` có tiền tố `bm-engine: `; câu chữ khác |

## Khác biệt khi render

Lấy từ benchmark tương đương (xem [Benchmark](benchmark.md)); mọi thứ khác được render trùng hoặc chỉ khác
trong mức nhiễu khử răng cưa.

- **Khử răng cưa**: bm-engine port bộ quét siêu lấy mẫu 4×4 của tiny-skia và hàm `div_255` của takumi,
  nên 81/250 fixture trùng từng byte. Số còn lại khác ở mép cong và mép glyph trong phạm vi một mẫu con
  (SSIM ≥ 0.99).
- **Sai khác 1 mức**: phần trong của gradient (takumi cộng dồn `f32` theo từng span), viền nét đứt trên
  góc bo (lệch pha ~0.1 px), chữ bị xoay, `-webkit-text-stroke`.
- **Layout inline**: chữ chảy quanh float, block-in-inline tách hộp inline, hộp inline RTL được đặt theo
  vị trí thị giác, inline nguyên tử và padding của span inline tham gia ngắt dòng, equivalent với takumi
  trên mọi fixture. Còn lại: khoảng trắng treo của RTL + `pre-wrap`, line-clamp quanh float, block nằm
  trong hộp inline `position: relative` (xem [hạn chế đã biết](css-support.md#các-hạn-chế-đã-biết)).
- **Thứ tự vẽ**: float và hộp được định vị theo CSS 2.1 Phụ lục E trong đầu ra raster; `renderSvg` vẫn
  dùng thứ tự cũ, xấp xỉ.
- **Emoji màu**: bm-engine vẽ được font COLR v1 (takumi thì không); cách hiển thị `©️` (U+00A9 + VS16)
  trong takumi tuỳ ngữ cảnh nên có thể khác.
- **Ảnh SVG**: `<text>` được vẽ theo mô hình đơn giản (mỗi phần tử một run, style của `<tspan>` bị bỏ qua,
  chỉ tô màu đặc; xem [Biểu đồ](charts.md#svg-text-hỗ-trợ-những-gì)); một vài filter primitive (`feTurbulence`,
  `feImage`, `feMorphology`, `feConvolveMatrix`, `feDisplacementMap`, chiếu sáng, `feTile`) chưa được hỗ trợ.
- **Bộ mã hoá**: file mã hoá ra khác byte (bm-engine dùng bộ mã hoá riêng; file PNG nhỏ hơn 24 %, trung
  bình nhân trên các fixture); benchmark so sánh điểm ảnh sau khi giải mã.

## Khác biệt có chủ ý (bm-engine theo Chrome)

Ở những trường hợp này takumi khác trình duyệt, còn bm-engine làm như Chrome:

- **`display: contents`**: takumi không hỗ trợ giá trị này (bỏ nó khỏi stylesheet và bộ parse style
  inline ném lỗi); bm-engine bỏ hộp của phần tử và dàn các con của nó trong cha, như Chrome.
- **`margin` / `padding` theo % trên hộp inline và inline-block** được tính theo bề rộng containing
  block; takumi tính chúng bằng 0.
- **`text-indent`** chỉ thụt dòng đầu của block container; takumi thụt cả dòng đầu của block ẩn danh
  không phải đầu tiên (chữ đứng sau một con dạng block).

## Chưa port

- Xuất PDF (`takumi-pdf`, một sản phẩm riêng khoảng 43 500 dòng Rust).
- Binding native N-API (`@takumi-rs/core`).
- Mọi kiểu truy cập mạng (`prepare` tải tài nguyên, URL `@font-face`).
- Counter trong `content`, ký hiệu đầu dòng của danh sách, `@apply`, animation trên pseudo-element,
  `clip-path: url()`, cú pháp màu tương đối, `outline-offset` theo %.

## Những hành vi của takumi được bm-engine cố ý giữ nguyên

Những điểm sau theo takumi (và Blink) kể cả khi chúng gây bất ngờ cho người mới, để một cây được thiết kế
cho takumi cho ra cùng kết quả:

- `display` mặc định là **`inline`** cho mọi node, kể cả container; node gốc và các con của flex / grid
  được blockify. Một container không đặt `display` sẽ bỏ qua `width` / `height` của nó.
- `box-sizing` mặc định là **`border-box`**.
- Khoá của `style` inline phải là camelCase; khoá kebab-case và thuộc tính không biết bị bỏ qua im lặng.
- Giá trị style inline không hợp lệ thì ném lỗi, còn khai báo không hợp lệ trong stylesheet / Tailwind
  thì bị loại bỏ.
- Số không đơn vị là px với độ dài; vẫn là số với `opacity`, `lineHeight`, `flexGrow`, `fontWeight`.
- Tùy chọn `width` / `height` tính bằng điểm ảnh đầu ra; `devicePixelRatio` nhân các độ dài CSS mà không
  đổi kích thước canvas; `vw` / `vh` tính theo điểm ảnh đầu ra.
- Node gốc không bị kéo giãn theo chiều cao canvas; `height: "100%"` được tính theo canvas.
- Canvas khởi đầu trong suốt; đầu ra JPEG bỏ kênh alpha mà không trộn màu (vùng trong suốt thành đen;
  hãy cho node gốc một nền đặc); đầu ra WebP luôn lossless.
- Font dự phòng duyệt mọi family đã đăng ký theo thứ tự đăng ký. Khi dùng tùy chọn `fonts` mà không có
  `fontFamilies`, các family của những font đó trở thành bộ font gốc (root font stack).
- Mọi nguồn là chuỗi JS đều là HTML; văn bản JSON phải được bọc thành `{ json }`.
- Ảnh không tìm thấy thì không vẽ gì và không ném lỗi.
- Tailwind: bảng utility, thứ tự sắp xếp và tập variant của takumi (không có `hover:`, `dark:`, `z-*`,
  `ring-*`, ...); giữa hai class màu xung đột, class đứng sau theo thứ tự chữ cái thắng.
- Stylesheet: cách parse "lossy" của takumi (`@page`, `@container`, `@scope`, ... bị loại), pseudo-class
  động không bao giờ khớp, `@media` so với kích thước canvas tính bằng CSS px, media feature không hỗ trợ
  làm cả query thành sai.
- Animation: dòng thời gian tính bằng ms nguyên, mặc định áp dụng tại t = 0, `animation-play-state` bị
  bỏ qua, keyframes dựng sẵn `spin` / `ping` / `pulse` / `bounce`, lịch khung hình của takumi cho
  `renderAnimation`.
- Giới hạn: lồng nhau tối đa 512 cấp.
