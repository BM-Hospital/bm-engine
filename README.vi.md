# bm-engine

[English](README.md) · [Tiếng Việt](README.vi.md)

Render cây node, HTML và Tailwind/CSS thành PNG, JPEG, WebP, ICO, RGBA thô, SVG và WebP / APNG / GIF động
bằng một engine WebAssembly không phụ thuộc thư viện nào. bm-engine là bản port bộ render
[takumi](https://github.com/kane50613/takumi) (2.20, viết bằng Rust) sang Zig 0.17: nó nhận cùng định dạng
node, cùng tùy chọn render và API của takumi, và đã được đối chiếu với takumi trên từng fixture. Nó chạy
trên Node.js, trình duyệt, bundler, Bun, Deno và các edge runtime như Cloudflare Workers, và được phát
hành theo ba profile build để bạn chỉ nạp những tính năng mình dùng.

Tài liệu: [docs/vi](docs/vi/README.md) (trên GitHub: `https://github.com/OWNER/bm-engine/tree/main/docs/vi`).

## Điểm nổi bật

Đo so với `@takumi-rs/wasm` 2.20.0 trên 184 fixture dùng chung (Node 26, i3-10100; chi tiết ở
[docs/vi/benchmark.md](docs/vi/benchmark.md)):

- **Nhỏ**: wasm `core` 428.5 KiB, `standard` 849.6 KiB, `full` 1 070.0 KiB (brotli 171 / 365 / 443 KiB),
  so với 4 234.9 KiB của takumi — nhỏ hơn 9.9× / 5.0× / 4.0×. Module **không có import nào** (không
  WASI, không glue wasm-bindgen) và wrapper JS không có dependency.
- **Đầu ra giống nhau**: 74 fixture trùng từng byte, 109 fixture tương đương (SSIM ≥ 0.99, chỉ khác ở
  mép khử răng cưa), 1 fixture gần giống, 0 fixture khác. Layout của `measure()` khớp takumi tới 0.001 px.
- **Nhanh**: render PNG mất 0.48× thời gian của takumi (trung bình nhân; nhanh hơn ở 175/175 ca), RGBA
  thô 0.65× (nhanh hơn ở 155/175 ca); cold start (init + font + PNG đầu tiên) 72 ms so với 187 ms; file
  PNG nhỏ hơn 24 %.
- **Đồng bộ hoặc bất đồng bộ**: mọi method đều có bản `*Sync`; `init` / `initSync` nhận bytes, URL,
  `Response` hoặc một `WebAssembly.Module` đã biên dịch sẵn.

Chỗ còn thua: bộ nhớ tuyến tính wasm **lớn hơn 9 %** so với takumi sau 50 lần render (11.6 so với
10.6 MiB); render thô chậm hơn ở nhóm `border-radius` (1.18×), `text-stroke` (1.58×), `svg-image`
(1.55×) và `text-decoration` (1.07×). Xem [Tình trạng](#tình-trạng-và-hạn-chế).

## Cài đặt

```sh
npm install bm-engine
```

## Bắt đầu nhanh (Node.js)

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // Node: profile full, tự khởi tạo khi import

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

## Các profile

| Profile | Import | wasm (thô / brotli) | Thêm |
|:--|:--|--:|:--|
| `core` | `bm-engine/core` | 428.5 / 171.0 KiB | cây node + style inline, `var()` / `calc()`, layout block / inline / flex / grid / absolute, font TTF tĩnh với shaping OpenType, mọi kiểu viền, gradient, đổ bóng, filter, transform 2D, ảnh vào PNG / JPEG, xuất PNG / JPEG / WebP / raw |
| `standard` | `bm-engine/standard` | 849.6 / 364.5 KiB | + stylesheet và selector, Tailwind, đầu vào HTML, ảnh SVG, WOFF / WOFF2, font biến thiên và CFF, clip-path / mask / blend mode / backdrop-filter, oklch / lab / color-mix, bảng, float, ảnh vào WebP / GIF, `text-wrap: balance` |
| `full` | `bm-engine` (Node), `bm-engine/full` | 1 070.0 / 442.8 KiB | + bidi và chữ phức tạp, emoji màu, CSS animation và `renderAnimation`, `renderSvg`, WebP lossy và ảnh động, xuất ICO |

Một add-on 84 KiB (`bm-engine/woff`) giúp `core` đọc được WOFF / WOFF2. `features` cho biết binary đang
nạp có những gì. Chi tiết: [Profile và kích thước](docs/vi/profiles-and-size.md).

## Tài liệu

- [Bắt đầu](docs/vi/getting-started.md): cài đặt, Node / trình duyệt / bundler / Workers, profile, font, ảnh, định dạng
- [Tham chiếu API](docs/vi/api.md): `init`, `Renderer`, định dạng node, tùy chọn, lỗi, giới hạn, bộ nhớ
- [Hỗ trợ CSS và tính năng](docs/vi/css-support.md): ma trận tính năng và mọi thuộc tính được hỗ trợ
- [Profile và kích thước](docs/vi/profiles-and-size.md) · [Khác biệt với takumi / chuyển đổi](docs/vi/differences-from-takumi.md)
- [Benchmark](docs/vi/benchmark.md) · [Build từ mã nguồn](docs/vi/building-from-source.md) · [Playground](docs/vi/playground.md) · [Xử lý sự cố](docs/vi/troubleshooting.md)
- Tài liệu cho nhà phát triển: [ARCHITECTURE](docs/ARCHITECTURE.md), [TAKUMI_NOTES](docs/TAKUMI_NOTES.md), [CONVENTIONS](docs/CONVENTIONS.md), [BENCHMARK (báo cáo đầy đủ)](docs/BENCHMARK.md)

Repository có kèm một **playground** chạy trên trình duyệt (`npm run playground`, rồi mở
`http://127.0.0.1:8080/playground/`) với các mẫu có sẵn, cả ba profile và mọi định dạng đầu ra; xem
[docs/vi/playground.md](docs/vi/playground.md).

## Tình trạng và hạn chế

Phiên bản 0.1.0. Những điều cần biết trước khi dùng:

- **Không kèm font.** takumi có sẵn Geist; bm-engine không vẽ chữ nào cho tới khi bạn đăng ký font.
- **Không truy cập mạng.** Ảnh từ xa và URL trong `@font-face` không bao giờ được tải (`prepare()` cũng
  không tải); hãy truyền bytes qua `images` và `registerFont`.
- **Không có JSX, không có `ImageResponse`, không có PDF, không có binding native.** Chuyển JSX bằng
  `@takumi-rs/helpers`.
- **Các thiếu sót layout đang được hoàn thiện trong 0.1.0** (xem [docs/BENCHMARK.md](docs/BENCHMARK.md)
  để biết tình trạng cuối cùng): chữ chảy quanh float; phần tử inline nguyên khối ở giữa dòng và padding
  của span inline.
- Chưa hỗ trợ: `display: contents`, list marker / counter, `writing-mode`, transform 3D,
  `clip-path: url()`, cú pháp màu tương đối, `animate-*` và các variant tương tác của Tailwind (giống
  takumi), `<text>` bên trong ảnh SVG và một số filter SVG.
- Khác biệt đã biết: `direction: rtl` không đảo chiều hàng flex; `image-rendering: pixelated` bị bỏ qua
  với ảnh raster; các text run của `measure()` không có trường `text`.
- Đơn luồng và đồng bộ trong một instance; bộ nhớ WebAssembly chỉ tăng chứ không bao giờ co lại.

Danh sách đầy đủ: [Hỗ trợ CSS → Các hạn chế đã biết](docs/vi/css-support.md#các-hạn-chế-đã-biết) và
[Khác biệt với takumi](docs/vi/differences-from-takumi.md).

## Giấy phép và ghi công

bm-engine được cấp phép theo [MIT License](LICENSE-MIT) hoặc [Apache License 2.0](LICENSE-APACHE), tùy
bạn chọn — cùng điều khoản với takumi.

bm-engine là sản phẩm phái sinh của **takumi** do Kane Wang phát triển (MIT OR Apache-2.0): phần lớn mã
được chuyển ngữ từ mã Rust của takumi (layout, vẽ, chữ, CSS, Tailwind, HTML, SVG, animation, codec), và
hành vi của nó được kiểm chứng bằng chính đầu ra của takumi. Mọi công lao thiết kế bộ render thuộc về dự
án takumi. Bản thân takumi đi theo Blink của Chromium và Skia; bm-engine còn port thuật toán và dữ liệu
từ tiny-skia, HarfBuzz, libwebp, libjpeg, Unicode / ICU, Brotli và các dự án khác. Xem [NOTICE](NOTICE)
và [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) để biết phần ghi công.
