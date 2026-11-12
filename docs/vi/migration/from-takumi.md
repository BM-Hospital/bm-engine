# Chuyển từ takumi sang

[English](../../en/migration/from-takumi.md) · [Tiếng Việt](from-takumi.md)

bm-engine viết lại renderer của takumi 2.20 (`@takumi-rs/wasm`) bằng Zig: định dạng node, các render
option và các method của `Renderer` đều giống nhau, nên phần lớn việc chuyển đổi chỉ gồm đổi import, đăng
ký font và bọc kết quả trong một `Response`. Trang này đối chiếu từng package của takumi với thứ tương
đương bên bm-engine (hoặc nói thẳng là không có), liệt kê tên các option và kết thúc bằng một checklist.
Những khác biệt khi render còn lại nằm ở [Khác biệt so với takumi](../differences-from-takumi.md).

::: info Trạng thái kiểm chứng
Phía bm-engine của mọi dòng đối chiếu đã được kiểm tra với `js/index.d.mts` và chạy thật trên Node 26.13
(xem các ví dụ framework trong `docs/examples/frameworks/`). Phía takumi lấy từ mã nguồn và tài liệu
takumi 2.20 trong bản sao tham chiếu của repository; **không chạy bất kỳ mã takumi nào**, nên các nhận
định về hành vi của takumi là theo tài liệu của takumi.
:::

## Đối chiếu package

| Package / import của takumi | Là gì | bm-engine |
|:--|:--|:--|
| `@takumi-rs/wasm` | renderer WebAssembly (`init`, `Renderer`) | `bm-engine` (cùng API `init` / `Renderer`), hoặc một entry theo profile `bm-engine/core` · `/standard` · `/full` |
| `@takumi-rs/wasm/node`, `@takumi-rs/wasm/auto` | tự khởi tạo trên Node | `bm-engine` (hoặc một entry theo profile) trên Node: khởi tạo ngay khi import |
| `@takumi-rs/wasm/no-bundler` | glue wasm-bindgen cho trình duyệt thuần | một entry theo profile + `await init()`; không có glue nào phải nạp |
| `@takumi-rs/wasm/takumi_wasm_bg.wasm`, `@takumi-rs/wasm/wasm-url` | binary / URL của nó | `bm-engine/wasm` (= `full.wasm`), `bm-engine/core.wasm`, `/standard.wasm`, `/full.wasm`; trong Vite dùng `bm-engine/<profile>.wasm?url` |
| `@takumi-rs/wasm/next`, `@takumi-rs/wasm/vite` | entry riêng cho framework | không có; xem [Next.js](../frameworks/nextjs.md) và [Vite](../frameworks/vite-browser.md) |
| `@takumi-rs/core` | binding N-API native (đa luồng, chạy ngoài event loop) | **không có** — bm-engine chỉ có WebAssembly. Để chạy song song, dùng một [pool worker_threads](../recipes.md#pool-worker-threads). |
| `takumi-js` | `render(jsx)`, `renderSvg`, `measure`, `renderAnimation` cấp cao | `new Renderer()` + `renderer.render(node, options)` v.v.; JSX phải được chuyển đổi trước ([JSX](#jsx)) |
| `takumi-js/response`, `@takumi-rs/image-response` | `ImageResponse` (lớp con của `Response`) | **không có**; dùng [helper `imageResponse()`](../frameworks/index.md#helper-imageresponse) khoảng 30 dòng hoặc `new Response(bytes, { headers })` |
| `takumi-js/helpers`, `@takumi-rs/helpers` | `fromJsx`, `fromHtml`, các hàm dựng `container` / `text` / `image`, `googleFonts`, bộ nạp emoji | không thuộc bm-engine. Các hàm dựng trả về object node thuần theo định dạng chung; bm-engine cũng nhận thẳng chuỗi HTML. Xem bên dưới. |
| `takumi-pdf` | đầu ra PDF | `bm-engine/pdf` (`PdfRenderer`, `render`, `measure`, `prepare`, `PageNumber`, `TotalPages`, `TargetPageNumber`); xem [PDF](#pdf) |
| `takumi-paint` | đầu ra paint tree | **không có** ([So sánh Image, PDF và Paint](../outputs-compared.md)) |

## Khởi tạo

| takumi | bm-engine |
|:--|:--|
| `import init, { Renderer } from "@takumi-rs/wasm"; await init({ module_or_path: wasmUrl })` | `import { init, Renderer } from "bm-engine/full"; await init()` — hoặc giữ `init({ module_or_path: url })`, bm-engine cũng nhận dạng này |
| `initSync({ module })` | `initSync(module)` hoặc `initSync({ module })` |
| Workers: `import wasm from "@takumi-rs/wasm/takumi_wasm_bg.wasm"` | `import wasm from "bm-engine/full.wasm"` (hoặc `core.wasm` / `standard.wasm` đi với entry tương ứng) |
| export `default` là `init` | giống vậy (`import init from "bm-engine/full"`) |

Ở cả hai, `init` trả về các export thô của wasm; một ứng dụng bình thường không dùng tới chúng.

## Các method của Renderer

| Method | Trạng thái trong bm-engine 0.1.0 |
|:--|:--|
| `new Renderer({ cacheMaxBytes, fontCacheMaxBytes })` | được chấp nhận; cả hai option bị bỏ qua (ngân sách cố định 96 MiB cho ảnh / 8 MiB cho glyph) |
| `registerFont` / `loadFont` | giống; **đồng bộ** với bytes và `{ data: bytes }`, trả `Promise` với URL và dữ liệu lazy |
| `unregisterFont`, `clearFonts` | giống; `clearFonts()` không để lại font nào (takumi giữ font Geist có sẵn) |
| `render`, `renderAsDataUrl`, `renderSvg`, `measure`, `renderAnimation` | giống; mỗi method có thêm bản `*Sync` |
| `prepare`, `prepareAnimation` | cùng dạng, nhưng **không tải gì cả** (không có lượt `needs` cho ảnh từ xa / `@font-face`) |
| `cacheFont`, `cachedFonts`, `cacheFontFile`, `needs`, `animationNeeds` | không có |
| `free`, `[Symbol.dispose]` | giống |
| — | `memoryBytes()`, `features`, `profile`, `wasmUrl()` là phần bm-engine bổ sung |

## Render option

| Option | bm-engine |
|:--|:--|
| `width`, `height`, `format`, `quality`, `devicePixelRatio` | cùng ý nghĩa; `quality` chỉ áp dụng cho JPEG (WebP luôn lossless, giống bản wasm của takumi) |
| `images` (`[{ src, data }]` hoặc `{ sources }`) | giống; `data()` lazy với API async; URL chỉ là khóa tra cứu, không bao giờ được tải |
| `css`, `stylesheets`, `keyframes` | giống (`css` cần `standard` / `full`) |
| `fontFamilies`, `lang`, `timeMs`, `signal` | giống; `signal` được kiểm tra trước khi render |
| `fonts` | giống (API async) |
| `lossless`, `dithering`, `drawDebugBorder` | được chấp nhận và bỏ qua |
| `emoji` (takumi-js / `ImageResponse`) | không có: hãy đăng ký một font emoji màu (profile `full`) |
| `jsx`, `renderer`, `headers`, `status`, `onError` (`ImageResponse`) | thuộc về `ImageResponse`; helper hỗ trợ `headers`, `status`, `onError` |

## Tương thích định dạng node

Cây node dùng thay cho nhau được: `{ type: "container" | "text" | "image", style, preset, tw, tagName,
className, id, attributes, dir, lang, children / text / src }`, key style dạng camelCase, số được hiểu là
px, `{ json }` cho văn bản JSON, mọi chuỗi JS được xem là HTML. Giá trị mặc định theo takumi
(`display: inline`, `box-sizing: border-box`, canvas trong suốt). Một cây được serialise từ takumi render
được mà không cần sửa; benchmark so sánh 200 fixture giữa hai engine (xem [Benchmark](../benchmark.md)).

Điều chỉ quan trọng khi thiếu: các tính năng bị loại khỏi profile nhỏ hơn (HTML, `css`, `tw`, ảnh SVG,
WOFF2, ...) sẽ ném lỗi hoặc bị bỏ qua — hãy dùng profile `full` trong lúc chuyển đổi, rồi mới thu nhỏ
([Profile và kích thước](../profiles-and-size.md)).

## JSX

bm-engine không có JSX runtime. Có ba cách để giữ template JSX:

1. **Giữ `@takumi-rs/helpers`** để chuyển đổi: `const { node, css } = await fromJsx(<Card />)`, rồi
   `renderer.render(node, { css, width, height })`. Theo mã nguồn takumi, `fromJsx` là hàm async và trả
   về `{ node, css }`; nó tạo ra định dạng node của takumi, thứ bm-engine đọc được. Lần kiểm thử trước
   của bm-engine dùng một React element dựng tay, không phải React thật (xem
   [Khác biệt so với takumi](../differences-from-takumi.md#chuyển-đổi-trong-năm-bước)); phần `css` nó trả về
   cần profile `standard` hoặc `full`.
2. **Dùng [factory `h()`](../frameworks/index.md#node-tree-không-cần-jsx) nhỏ gọn** làm JSX factory cho các
   file template (đã kiểm chứng với esbuild). Không có hook, không có UA style.
3. **Render JSX thành HTML** bằng server renderer của framework rồi truyền chuỗi đó vào (cần `standard`
   hoặc `full`).

Các hàm dựng `container()`, `text()`, `image()` của `@takumi-rs/helpers` trả về object node thuần theo
cùng định dạng, nên cây dựng bằng chúng hẳn sẽ render được nguyên trạng (chưa kiểm thử).

## PDF

`takumi-pdf` ứng với `bm-engine/pdf` ([Đầu ra PDF](../pdf.md)). Tên và hình dạng các tùy chọn là của takumi-pdf (`size`,
`landscape`, `margin`, `header`, `footer`, `pages`, `pageRanges`, `viewport`, `metadata`, `outline`, `pdfa`, `tagged`,
`attachments`, `uncoveredText`, ...), và phần lớn thông báo kiểm tra cũng vậy. Khi chuyển mã sang cần đổi:

- Import `PdfRenderer` từ `bm-engine/pdf` thay vì `takumi-pdf`; không có JSX, nên `PageNumber()`, `TotalPages()` và
  `TargetPageNumber()` trả về object node (một `span` mang class hook), còn `header` / `footer` là chuỗi HTML hoặc cây node.
- `prepare` và `render` không tải gì và không có `needs`: hãy truyền byte ảnh qua `images` và font qua `registerFont`
  hoặc `fonts`. bm-engine không kèm font.
- Font đã đăng ký phải phủ mọi ký tự, nếu không render lỗi (`uncoveredText: "error"`, như ở takumi-pdf).
- Khác biệt đã biết: PDF/A được kiểm tra nhưng chưa chứng nhận, `list-style-image` không được hỗ trợ, và nội dung chỉ
  được dàn một lần ở một chiều rộng nên trang có tên hoặc quy tắc `@page` làm đổi chiều rộng trang không dàn lại nó
  ([Hạn chế đã biết](../pdf.md#hạn-chế-đã-biết)).

`takumi-paint` không có đối ứng ([So sánh Image, PDF và Paint](../outputs-compared.md)).

## Khác biệt đầu ra cần lường trước

Pixel khớp với takumi ở phần lớn fixture, chỗ còn lại chỉ lệch ở mức nhiễu anti-aliasing. Những trường
hợp nên kiểm tra bằng mắt sau khi chuyển đổi được liệt kê ở
[Khác biệt so với takumi → Khác biệt khi render](../differences-from-takumi.md#khác-biệt-khi-render):
gradient, viền nét đứt bo góc, chữ xoay, `-webkit-text-stroke`, flex container RTL,
`image-rendering: pixelated`, một số chuỗi emoji, SVG `<text>`. File đã mã hóa là các byte khác nhau
(encoder khác nhau) kể cả khi pixel khớp — hãy so sánh pixel sau khi giải mã, đừng so hash file.

## Checklist

- Đổi import (`@takumi-rs/wasm` → `bm-engine/<profile>`); bắt đầu với `full`.
- Giữ `init()` (trình duyệt, bundler) hoặc bỏ nó đi (Node); trên Workers hãy import `bm-engine/<profile>.wasm`.
- Đăng ký mọi font bạn dùng — không có Geist dựng sẵn. Chữ không có font sẽ âm thầm không được vẽ.
- Thay `ImageResponse` bằng `new Response(bytes, { headers })` hoặc helper `imageResponse()`; tự đặt
  `content-type`.
- Thay `emoji: "twemoji"` (v.v.) bằng một font emoji màu đã đăng ký trên `full`.
- Tự tải ảnh từ xa và truyền vào qua `images` (trước đây `prepare` của takumi tải hộ).
- Thay các URL `@font-face` trong stylesheet bằng lời gọi `registerFont`.
- Bỏ `@takumi-rs/core` khỏi `serverExternalPackages` và thêm `bm-engine` vào (Next.js).
- Bỏ phụ thuộc vào `cacheFont` / `needs`; bỏ các option kích thước cache (chúng bị bỏ qua).
- Nếu bạn dùng binding native để chạy song song, hãy thêm một worker pool.
- So sánh bằng mắt một mẫu đầu ra; sau đó thử `standard` hoặc `core` và kiểm tra `features`.
