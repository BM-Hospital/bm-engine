# bm-engine

[English](README.md) · [Tiếng Việt](README.vi.md)

Render cây node, HTML và Tailwind/CSS thành PNG, JPEG, WebP, ICO, RGBA thô, SVG, WebP / APNG / GIF động và PDF nhiều trang
bằng một engine WebAssembly không phụ thuộc thư viện nào. bm-engine là bản port bộ render
[takumi](https://github.com/kane50613/takumi) (2.20, viết bằng Rust) sang Zig 0.17: nó nhận cùng định dạng
node, cùng tùy chọn render và API của takumi, và đã được đối chiếu với takumi trên từng fixture. Nó chạy
trên Node.js, trình duyệt, bundler, Bun, Deno và các edge runtime như Cloudflare Workers, và được phát
hành theo ba profile build (và một profile `pdf` cho đầu ra PDF) để bạn chỉ nạp những tính năng mình dùng.

Tài liệu: [docs/vi](docs/vi/README.md) (trên GitHub: `https://github.com/OWNER/bm-engine/tree/main/docs/vi`).

## Điểm nổi bật

Đo so với `@takumi-rs/wasm` 2.20.0 trên 250 fixture dùng chung (Node 26, i3-10100; chi tiết ở
[docs/vi/benchmark.md](docs/vi/benchmark.md)):

- **Nhỏ**: wasm `core` 487.6 KiB, `standard` 934.4 KiB, `full` 1 141.5 KiB (brotli 194 / 398 / 470 KiB),
  so với 4 234.9 KiB của takumi — nhỏ hơn 8.7× / 4.5× / 3.7×. Module **không có import nào** (không
  WASI, không glue wasm-bindgen) và wrapper JS không có dependency.
- **Đầu ra giống nhau**: 81 fixture trùng từng byte, 169 fixture tương đương (SSIM ≥ 0.99, chỉ khác ở
  mép khử răng cưa), 0 fixture gần giống, 0 fixture khác, 0 lỗi. Layout của `measure()` khớp takumi tới 0.001 px
  (246/247 ca không-transform).
- **Nhanh**: render PNG mất 0.45× thời gian của takumi (trung bình nhân; nhanh hơn ở 248/250 ca), RGBA
  thô 0.63× (nhanh hơn ở 229/250 ca); cold start (init + font + PNG đầu tiên) 78 ms so với 194 ms; file
  PNG nhỏ hơn 20 %.
- **Đồng bộ hoặc bất đồng bộ**: mọi method đều có bản `*Sync`; `init` / `initSync` nhận bytes, URL,
  `Response` hoặc một `WebAssembly.Module` đã biên dịch sẵn.

Chỗ còn thua: bộ nhớ tuyến tính wasm **lớn hơn 9 %** so với takumi sau 50 lần render (11.6 so với
10.6 MiB); render thô chậm hơn ở nhóm `border-radius` (1.20×), `text-stroke` (1.58×), `svg-image`
(1.48×) và `text-decoration` (1.12×). Xem [Tình trạng](#tình-trạng-và-hạn-chế).

## Cài đặt

```sh
npm install bm-engine
```

### Native trên Node.js, wasm ở mọi nơi khác

Trên Node.js, cùng package này còn chạy dưới dạng **addon Node-API native**: `npm install bm-engine` kéo theo
đúng một optional platform package khớp với máy (`bm-engine-linux-x64-gnu`, `bm-engine-darwin-arm64`, ...;
không cần trình biên dịch, không có install script), và `import ... from "bm-engine"` dùng nó, với cùng API
và output giống hệt từng byte, nhanh hơn, và `render()` cùng các method async chạy trên thread pool của
libuv. Nếu addon không có hoặc không nạp được, `bm-engine` lặng lẽ chuyển sang WebAssembly. Trình duyệt,
worker và edge runtime luôn dùng WebAssembly. Kiểm tra bằng `import { backend } from "bm-engine"`; ép bằng
`BM_ENGINE_BACKEND=wasm|native`.

| Platform package | Trạng thái |
|:--|:--|
| `win32-x64-msvc` | đã chạy: giống hệt từng byte với wasm trên 250 fixture, test luồng, bộ nhớ, fuzz và cài đặt |
| `win32-arm64-msvc`, `linux-x64-gnu`, `linux-x64-musl`, `linux-arm64-gnu`, `linux-arm64-musl`, `darwin-x64`, `darwin-arm64` | đã cross-compile và kiểm tra cấu trúc, **chưa từng chạy** (fallback sang wasm nếu không nạp được) |

Chi tiết: [Bắt đầu → Cài đặt](docs/vi/getting-started.md#cài-đặt) (package manager, Docker, serverless,
lockfile), [docs/NATIVE.md](docs/NATIVE.md) (thiết kế), [Phát hành](docs/vi/publishing.md) (maintainer).

## Bắt đầu nhanh (Node.js)

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // Node: addon native hoặc profile wasm full, sẵn sàng khi import

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") }); // không kèm sẵn font nào

const png = renderer.renderSync(
  {
    type: "container",
    style: {
      display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
      backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)",
    },
    children: [{ type: "text", text: "Hello from bm-engine", style: { fontFamily: "Inter", fontSize: 64, color: "white" } }],
  },
  { width: 1200, height: 630 }, // format: "png" (mặc định) | "jpeg" | "webp" | "raw" | "ico"
);
writeFileSync("og.png", png);
```

HTML và stylesheet cũng dùng được (profile `standard` và `full`):
`renderer.renderSync("<div style='display:flex;...'>Hi</div>", { width: 1200, height: 630, css: [".x { ... }"] })`.

## Bắt đầu nhanh (trình duyệt)

```js
import { init, Renderer } from "bm-engine/full"; // hoặc bm-engine/standard, bm-engine/core

await init(); // tải bm_engine.wasm nằm cạnh module (bundler sẽ xuất nó thành asset)
const renderer = new Renderer();
renderer.registerFont(await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer());
const png = await renderer.render(node, { width: 1200, height: 630 });
document.querySelector("img").src = URL.createObjectURL(new Blob([png], { type: "image/png" }));
```

Trên Cloudflare Workers, import binary như một module rồi truyền vào: `import wasm from "bm-engine/full.wasm";
initSync(wasm)`. Xem [Bắt đầu](docs/vi/getting-started.md) cho bundler, Workers, Deno và Bun.

## Bắt đầu nhanh (PDF)

```js
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf"; // profile pdf: full + đầu ra PDF

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const bytes = await pdf.render(
  `<h1 style="font-family: Inter">Quarterly report</h1><p style="font-family: Inter">Selectable text.</p>`,
  { size: "a4", margin: 36, footer: `<span style="font: 10px Inter">Page <span class="pageNumber"></span></span>` },
);
writeFileSync("report.pdf", bytes);
```

Nội dung chảy qua nhiều trang; hỗ trợ header, footer, bộ đếm trang, liên kết, bookmark, metadata, tệp đính
kèm, PDF có thẻ (PDF/UA) và PDF/A. Xem [Đầu ra PDF](docs/vi/pdf/index.md). Trên Node.js, `bm-engine/pdf` dùng addon native
khi đã cài (cùng byte, nhanh hơn, async chạy ngoài main thread), nếu không thì dùng profile wasm `pdf`.

## Các profile

| Profile | Import | wasm (thô / brotli) | Thêm |
|:--|:--|--:|:--|
| `core` | `bm-engine/core` | 487.6 / 194.3 KiB | cây node + style inline, `var()` / `calc()`, layout block / inline / flex / grid / absolute, font TTF tĩnh với shaping OpenType, mọi kiểu viền, gradient, đổ bóng, filter, transform 2D, ảnh vào PNG / JPEG, xuất PNG / JPEG / WebP / raw |
| `standard` | `bm-engine/standard` | 934.4 / 398.0 KiB | + stylesheet và selector, Tailwind, đầu vào HTML, ảnh SVG, WOFF / WOFF2, font biến thiên và CFF, clip-path / mask / blend mode / backdrop-filter, oklch / lab / color-mix, bảng, float, ảnh vào WebP / GIF, `text-wrap: balance` |
| `full` | `bm-engine` (Node), `bm-engine/full` | 1 141.5 / 469.8 KiB | + bidi và chữ phức tạp, emoji màu, CSS animation và `renderAnimation`, `renderSvg`, WebP lossy và ảnh động, xuất ICO |
| `pdf` | `bm-engine/pdf` | khoảng 1.5 MB thô | `full` + đầu ra PDF: phân trang, header / footer, liên kết, bookmark, metadata, tệp đính kèm, PDF có thẻ, PDF/A. Xem [Đầu ra PDF](docs/vi/pdf/index.md) |

Một add-on 84 KiB (`bm-engine/woff`) giúp `core` đọc được WOFF / WOFF2. `features` cho biết binary đang
nạp có những gì. Chi tiết: [Profile và kích thước](docs/vi/profiles-and-size.md).

## Tài liệu

- [Bắt đầu](docs/vi/getting-started.md): cài đặt, addon native / WebAssembly, điểm vào, bundler / Workers, profile
- Ảnh: [bắt đầu nhanh](docs/vi/image/index.md) (Node / trình duyệt, font, ảnh, định dạng) · [Tham chiếu API](docs/vi/image/api.md): `init`, `Renderer`, định dạng node, tùy chọn, lỗi, giới hạn, bộ nhớ
- [Hỗ trợ CSS và tính năng](docs/vi/image/css-support.md): ma trận tính năng và mọi thuộc tính được hỗ trợ
- PDF: [bắt đầu nhanh](docs/vi/pdf/index.md), [tham chiếu API](docs/vi/pdf/api.md), [công thức](docs/vi/pdf/recipes.md), [phân trang](docs/vi/pdf/pagination.md), [header và footer](docs/vi/pdf/headers-footers.md), [liên kết và metadata](docs/vi/pdf/links-metadata.md), [font](docs/vi/pdf/fonts.md), [PDF/UA và PDF/A](docs/vi/pdf/accessibility.md)
- [Profile và kích thước](docs/vi/profiles-and-size.md) · [Khác biệt với takumi / chuyển đổi](docs/vi/image/differences-from-takumi.md)
- [Benchmark](docs/vi/benchmark.md) · [Build từ mã nguồn](docs/vi/building-from-source.md) · [Playground](docs/vi/image/playground.md) · [Xử lý sự cố](docs/vi/troubleshooting.md)
- Tài liệu cho nhà phát triển: [ARCHITECTURE](docs/ARCHITECTURE.md), [TAKUMI_NOTES](docs/TAKUMI_NOTES.md), [CONVENTIONS](docs/CONVENTIONS.md), [BENCHMARK (báo cáo đầy đủ)](docs/BENCHMARK.md)

Tài liệu cũng là một trang VitePress có sẵn **playground** chạy trên trình duyệt (các mẫu có sẵn, cả ba
profile, mọi định dạng đầu ra): chạy `npm run docs` trong bản checkout của repository rồi mở
`http://localhost:5173/vi/` (playground: `/vi/image/playground`). Chỉ chạy playground: `npm run playground`, rồi mở
`http://127.0.0.1:8080/docs/playground-app/`; xem [docs/vi/image/playground.md](docs/vi/image/playground.md).

## Tình trạng và hạn chế

Phiên bản 0.1.0. Những điều cần biết trước khi dùng:

- **Không kèm font.** takumi có sẵn Geist; bm-engine không vẽ chữ nào cho tới khi bạn đăng ký font.
- **Không truy cập mạng.** Ảnh từ xa và URL trong `@font-face` không bao giờ được tải (`prepare()` cũng
  không tải); hãy truyền bytes qua `images` và `registerFont`.
- **Không có JSX, không có `ImageResponse`.** Chuyển JSX bằng
  `@takumi-rs/helpers`.
- **PDF là một entry riêng** (`bm-engine/pdf`: profile wasm `pdf`, khoảng 1.5 MB thô, hoặc addon native trên Node.js) và là bản port của `takumi-pdf` với một số
  khác biệt đã biết: nội dung chỉ được dàn một lần ở một chiều rộng (trang có tên với chiều rộng khác không được dàn lại), `list-style-image` không được hỗ trợ, PDF/A được kiểm tra nhưng chưa được chứng nhận, và không có
  bước `needs` (xem [Đầu ra PDF → Hạn chế đã biết](docs/vi/pdf/differences-from-takumi.md#hạn-chế-đã-biết)).
- **Layout inline đã đủ cho nội dung thông thường** (chữ chảy quanh float; block-in-inline, hộp inline
  RTL, inline nguyên tử và padding của span inline tham gia ngắt dòng). Còn lại: khoảng trắng treo của RTL +
  `pre-wrap`, line-clamp quanh float, block nằm trong hộp inline `position: relative` (xem
  [Hỗ trợ CSS → Các hạn chế đã biết](docs/vi/image/css-support.md#các-hạn-chế-đã-biết)).
- Chưa hỗ trợ: list marker / counter, `writing-mode`, transform 3D, `clip-path: url()`, cú pháp màu tương
  đối, các variant tương tác và `space-*` của Tailwind (giống takumi), `<text>` bên trong ảnh SVG và một số
  filter SVG.
- Khác biệt đã biết: `display: contents`, `margin` / `padding` theo % trên hộp inline và `text-indent`
  sau một con dạng block theo Chrome thay vì takumi; các text run của `measure()` không có trường `text`.
- WebAssembly: đơn luồng và đồng bộ trong một instance; bộ nhớ chỉ tăng chứ không bao giờ co lại. Native
  (Node.js): một renderer chạy một lệnh tại một thời điểm, nhiều renderer chạy song song; tới nay mới chỉ
  addon Windows x64 được chạy thật.

Danh sách đầy đủ: [Hỗ trợ CSS → Các hạn chế đã biết](docs/vi/image/css-support.md#các-hạn-chế-đã-biết) và
[Khác biệt với takumi](docs/vi/image/differences-from-takumi.md).

## Giấy phép và ghi công

bm-engine được cấp phép theo [MIT License](LICENSE-MIT) hoặc [Apache License 2.0](LICENSE-APACHE), tùy
bạn chọn — cùng điều khoản với takumi.

bm-engine là sản phẩm phái sinh của **takumi** do Kane Wang phát triển (MIT OR Apache-2.0): phần lớn mã
được chuyển ngữ từ mã Rust của takumi (layout, vẽ, chữ, CSS, Tailwind, HTML, SVG, animation, codec), và
hành vi của nó được kiểm chứng bằng chính đầu ra của takumi. Mọi công lao thiết kế bộ render thuộc về dự
án takumi. Bản thân takumi đi theo Blink của Chromium và Skia; bm-engine còn port thuật toán và dữ liệu
từ tiny-skia, HarfBuzz, libwebp, libjpeg, Unicode / ICU, Brotli và các dự án khác. Xem [NOTICE](NOTICE)
và [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) để biết phần ghi công.
