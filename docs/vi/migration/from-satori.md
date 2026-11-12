# Chuyển từ satori và next/og sang

[English](../../en/migration/from-satori.md) · [Tiếng Việt](from-satori.md)

[satori](https://github.com/vercel/satori) biến JSX thành một chuỗi SVG; một công cụ thứ hai như
`@resvg/resvg-js` (hoặc sharp) biến SVG thành PNG, còn `next/og` / `@vercel/og` gói cả hai bước sau
`ImageResponse`. bm-engine thay toàn bộ pipeline đó bằng một lời gọi trả thẳng về byte PNG, JPEG hoặc
WebP (hoặc SVG với `renderSvg`). Trang này chỉ ra từng phần tương ứng với gì, cách mang JSX của bạn theo,
và mỗi bên làm được gì mà bên kia không làm được.

::: info Trạng thái kiểm chứng
Mọi điều nói về bm-engine đều đã được chạy trên Node 26.13 (`docs/examples/frameworks/check-helpers.mjs`:
JSX factory `h()` qua esbuild, `flexByDefault()`, `renderSvg` + đầu ra PNG). satori, resvg và `next/og`
**không được cài hay chạy**: các nhận định về chúng là những đặc điểm phổ biến, được biết rộng rãi của
các dự án đó tại thời điểm viết, kèm dè dặt ở chỗ khác nhau giữa các phiên bản — hãy kiểm tra README
hiện tại của chúng.
:::

## Hai pipeline đặt cạnh nhau

```js
// before: satori + resvg
import satori from "satori";
import { Resvg } from "@resvg/resvg-js";

const svg = await satori(<Card title="Hello" />, {
  width: 1200,
  height: 630,
  fonts: [{ name: "Inter", data: interBytes, weight: 400, style: "normal" }],
});
const png = new Resvg(svg).render().asPng();
```

```js
// after: bm-engine
import { Renderer } from "bm-engine/standard";
import { h } from "./h.js"; // JSX factory, see below

const renderer = new Renderer(); // once per process
renderer.registerFont({ name: "Inter", data: interBytes, weight: 400, style: "normal" });

const png = renderer.renderSync(Card({ title: "Hello" }), { width: 1200, height: 630 });
// need the SVG too?  renderer.renderSvgSync(node, { width: 1200, height: 630 })  (full profile)
```

| satori / resvg / next/og | bm-engine |
|:--|:--|
| `satori(element, { width, height, fonts })` → SVG | `renderer.renderSvgSync(node, { width, height })` → SVG (profile `full`); chữ thành đường viền glyph, giống đầu ra mặc định của satori |
| `new Resvg(svg).render().asPng()` | không cần: `renderer.renderSync(node, options)` trả về PNG (`format: "jpeg" \| "webp"` cho định dạng khác) |
| `fonts: [...]` ở mỗi lần gọi | `registerFont(...)` một lần cho mỗi renderer (cũng có render option `fonts`) |
| `new ImageResponse(element, options)` | `new Response(bytes, { headers })` hoặc [helper `imageResponse()`](../frameworks/index.md#helper-imageresponse) |
| `loadAdditionalAsset` (font / emoji động) | không có callback: đăng ký sẵn các font fallback ([chuỗi fallback](../recipes.md#i18n-chuỗi-font-fallback)); emoji màu lấy từ một font emoji đã đăng ký trên `full` |
| `graphemeImages` | không có tương đương; dùng node `image` |
| `debug: true` | `drawDebugBorder` được chấp nhận và bị bỏ qua |
| prop `tw` (hỗ trợ Tailwind của satori) | `tw` trên node, profile `standard` / `full`; độ phủ class theo bảng của takumi, không theo satori |

## Chuyển đổi JSX

satori nhận React element. bm-engine nhận object node thuần. Chọn một trong các cách:

1. **Biên dịch các file card với [factory `h()`](../frameworks/index.md#node-tree-không-cần-jsx).**
   Với esbuild `--jsx-factory=h --jsx-fragment=Fragment`, TypeScript `"jsxFactory": "h"`, hoặc pragma
   `/** @jsx h */`, `<div style={...}>` thành node container, chuỗi thành node text và `<img src>` thành
   node image. Đã kiểm chứng với esbuild 0.28.2. Function component hoạt động (được gọi với props của
   chúng); hook và context thì không.
2. **Chuyển đổi React element** bằng `fromJsx()` của takumi trong `@takumi-rs/helpers`, hàm này còn ánh
   xạ các phần tử HTML sang preset mặc định của takumi (xem [Chuyển từ takumi → JSX](./from-takumi.md#jsx)).
3. **Render ra HTML** bằng `react-dom/server` rồi truyền chuỗi vào (`standard` / `full`); đầu vào HTML
   có user-agent style cho `h1`, `p`, ... như trình duyệt. Xem [HTML và Tailwind](../html-and-tailwind.md).

### `display: flex` ở mọi nơi

satori (và do đó `next/og`) coi mọi phần tử là flex container. bm-engine theo CSS và takumi: mọi node là
`display: inline` cho tới khi bạn đặt khác, và container inline bỏ qua `width` / `height`. Template viết
cho satori thường dựa vào mặc định flex này, nên hoặc thêm `display: "flex"` ở chỗ cần, hoặc áp mặc định
của satori cho cả cây:

```js
export function flexByDefault(node) {
  if (!node || node.type !== "container") return node;
  return { ...node, style: { display: "flex", ...node.style }, children: node.children?.map(flexByDefault) };
}

renderer.renderSync(flexByDefault(Card({ title: "Hello" })), { width: 1200, height: 630 });
```

Đã kiểm chứng: một container 400 × 200 với hai con 100 × 50 và không có `display` được measure thành
một dòng inline không có box con nào; sau `flexByDefault()` các con nằm thành hàng ở x = 0 và x = 100.

## Font

- satori bắt buộc có `fonts` và đọc TTF, OTF và WOFF (không có WOFF2, theo những gì README của nó nêu).
  bm-engine đọc TTF trên mọi profile, OTF (CFF) và WOFF / WOFF2 trên `standard` / `full`, WOFF / WOFF2 trên
  `core` qua [add-on WOFF](../api.md#add-on-woff).
- Giống satori, bm-engine không có font hệ thống và không có font mặc định: chữ không có font đã đăng ký
  sẽ không được vẽ (không báo lỗi).
- Variable font theo `font-weight` / `font-variation-settings` trên `standard` / `full`.
- Đăng ký font **một lần** cho mỗi renderer thay vì truyền byte ở mỗi lần gọi; phân tích font mới là
  phần tốn kém.

## bm-engine có thêm gì

Đã kiểm chứng ở phía bm-engine (chi tiết trong bảng [Hỗ trợ CSS](../css-support.md)):

- Xuất raster trực tiếp: PNG, JPEG, WebP, RGBA thô (và ICO trên `full`) — không cần bước resvg.
- Layout ngoài flexbox: block, inline, grid, float và bảng (`tables` / `floats` trên `standard`).
- Stylesheet (option `css`, `<style>` trong HTML), selector, `@media` theo canvas, Tailwind qua `tw`.
- Chuỗi HTML làm đầu vào (`standard` / `full`).
- CSS animation render thành WebP / APNG / GIF động (`full`), hoặc một khung hình đơn với `timeMs`.
- Bidi và các hệ chữ phức tạp (Ả Rập, Do Thái, Ấn, Thái) và font emoji màu trên `full`.
- `measure()` cho các box layout và run của từng dòng chữ (xem [Measure](../measure.md)).
- API đồng bộ, không dependency, mỗi profile một file `.wasm` (454.9 KiB – 1.08 MiB raw).

## satori có gì mà bm-engine không có

Có dè dặt — dựa trên các tính năng satori đã công bố, không phải do chạy thử:

- Nhận trực tiếp React element (bm-engine cần một bước chuyển đổi, như trên).
- Callback `loadAdditionalAsset` để tải font hoặc ảnh emoji theo nhu cầu ngay trong lúc render.
- `graphemeImages` để ánh xạ ký tự sang ảnh.
- Bước layout được phân phối thuần JavaScript (satori dùng Yoga biên dịch sang WebAssembly; resvg là một
  binary hoặc module wasm riêng) — bm-engine là một binary WebAssembly mà bạn nạp bằng `init` trên các
  runtime không phải Node.
- Hệ sinh thái lớn hơn: `next/og` có sẵn trong Next.js, và nhiều template nhắm vào hành vi mặc định flex
  của satori.

## Checklist

- Thay `satori` + `resvg` bằng một `Renderer`, tạo một lần, đăng ký font một lần.
- Chuyển JSX bằng `h()`, `fromJsx()` hoặc HTML; thêm `display: "flex"` (hoặc `flexByDefault()`).
- Thay `ImageResponse` bằng một `Response` (hoặc `imageResponse()`), và đặt `content-type`.
- Thay `loadAdditionalAsset` / các option emoji bằng font fallback và font emoji đã đăng ký.
- Chọn profile: `core` cho cây node dùng inline style với font TTF, `standard` cho Tailwind / HTML /
  WOFF2, `full` cho đầu ra SVG, emoji và các hệ chữ phức tạp.
- So sánh bằng mắt vài đầu ra: hai engine dàn chữ khác nhau, nên chỗ ngắt dòng có thể dịch chuyển.
