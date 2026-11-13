# Next.js

[English](../../../en/image/frameworks/nextjs.md) · [Tiếng Việt](nextjs.md)

Phục vụ ảnh Open Graph từ một route handler của Next.js App Router, hoặc để Next.js tự phát hiện chúng
qua quy ước file `opengraph-image`. bm-engine thay `ImageResponse` của `next/og` bằng một renderer do
bạn quản lý và một `Response` thông thường; ảnh là một node tree (hoặc HTML), không phải JSX — xem
[Node tree không cần JSX](./index.md#node-tree-không-cần-jsx) để có một helper `h()` nhỏ.

::: info Trạng thái kiểm chứng
Đã kiểm chứng với **Next.js 16.4.6 trên Windows x64, Node 26.13**, bm-engine và platform package
`bm-engine-win32-x64-msvc` được cài từ các tarball đã đóng gói: `next build` với Turbopack (mặc định) và
với `--webpack`, rồi `next start`; với `output: "standalone"`, thư mục `.next/standalone` được chép ra một
thư mục nằm ngoài project và chạy bằng `node server.js`, để không thứ gì có thể được resolve từ
`node_modules` của máy build. Các route: một route handler Node.js dùng `bm-engine`, một dùng
`bm-engine/full`, và một route Edge; mỗi route trả về một PNG. Kết quả nằm trong các bảng bên dưới. Chưa
kiểm thử: deploy lên Vercel, máy chủ Linux / macOS, cấu trúc thư mục của pnpm / Yarn, các phiên bản
Next.js khác. Không thể kiểm thử Edge runtime với builder webpack: trên Next.js 16.4.6, `next build
--webpack` thất bại với *mọi* route Edge trên máy này, kể cả một route không dùng bm-engine (`ENOENT ...
route_client-reference-manifest.js`). Ứng dụng mẫu nằm ở
[`docs/examples/frameworks/nextjs/`](../../../examples/frameworks/nextjs/).
:::

## 1. Cài đặt và cấu hình

```sh
npm install bm-engine
```

```js
// next.config.mjs
/** @type {import("next").NextConfig} */
export default {
  // Giữ bm-engine ngoài server bundle: Node nạp nó từ node_modules, và Next.js chép các file của nó
  // vào output standalone / Vercel.
  serverExternalPackages: ["bm-engine"],
  // Chép cả platform package native (file tracing của Turbopack không lần theo nó, xem bên dưới).
  outputFileTracingIncludes: { "/*": ["./node_modules/bm-engine-*/**"] },
};
```

Với `next dev` / `next start` trên chính máy đã build ứng dụng thì không cần tùy chọn nào: cả hai builder
đều chạy được mà không cần cấu hình, và chạy native. Chúng chỉ quan trọng với output tự chứa
(`output: "standalone"`, Vercel và các host chỉ chép những file đã được trace):

| Builder | `next.config` | `next start` | output standalone, chạy ở nơi khác |
|:--|:--|:--|:--|
| Turbopack | không có gì | native | **wasm** (platform package không được chép) |
| Turbopack | `serverExternalPackages` | native | **wasm** (platform package không được chép) |
| Turbopack | `serverExternalPackages` + `outputFileTracingIncludes` | native | **native** |
| Turbopack | chỉ `outputFileTracingIncludes` | native | native |
| webpack (`--webpack`) | không có gì | native | **lỗi**: `bm-engine: cannot find bm_engine.wasm (...)` (HTTP 500) |
| webpack (`--webpack`) | `serverExternalPackages` | native | **native** (platform package được trace) |

"wasm" là cơ chế fallback tự động: output đúng, chậm hơn, và các method async chặn event loop. Hãy log
hoặc trả về `backend` (được `bm-engine` export) một lần để biết thứ gì đang chạy trên production.

Package hoạt động thế nào khi Next.js bundle nó: điểm vào Node tìm file `.wasm` ngay cạnh nó (hoặc asset
mà Turbopack phát ra), sau đó qua package resolution, sau đó trong `<cwd>/node_modules/bm-engine/js/`;
nếu tất cả đều thất bại, thông báo lỗi nêu tên `serverExternalPackages`. Platform package được require
lúc chạy với một tên viết cứng cho mỗi nền tảng, có đánh dấu `turbopackIgnore` / `webpackIgnore`, nên
build không bao giờ lỗi vì những platform package không được cài; cái giá phải trả là file tracing của
Turbopack bỏ qua nó, vì vậy cần `outputFileTracingIncludes`. Với pnpm, các package nằm trong
`node_modules/.pnpm/`: hãy sửa glob (ví dụ `"./node_modules/.pnpm/bm-engine-*/**"`); chưa kiểm thử.

### Addon native khi triển khai

Platform package được chọn lúc cài dependency, trên máy chạy lệnh cài: Vercel build trên Linux x64 và
nhận `bm-engine-linux-x64-gnu`, bản đã được build và kiểm tra cấu trúc nhưng **chưa từng được chạy** (chỉ
`win32-x64-msvc` đã chạy, xem [Cài đặt](../../getting-started.md#native-trên-nodejs-webassembly-ở-mọi-nơi-khác)).
Nếu nó không nạp được ở đó, route vẫn chạy bằng wasm. Một thư mục `node_modules` được build trên máy Mac
hoặc Windows của bạn rồi tải lên máy chủ Linux sẽ mang theo binary sai (lúc chạy là wasm).

## 2. Renderer và template dùng chung

Đặt renderer trong một module để nó chỉ được tạo một lần cho mỗi tiến trình server. Next.js chạy route
handler với thư mục gốc của project làm thư mục làm việc, nên `process.cwd()` là gốc đáng tin cậy cho các
file font nằm trong repository:

```js
// lib/og.js
import { readFileSync } from "node:fs";
import path from "node:path";
import { Renderer, backend } from "bm-engine";

let renderer;

export function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    const dir = path.join(process.cwd(), "fonts");
    renderer.registerFont({ name: "Inter", data: readFileSync(path.join(dir, "Inter-Regular.ttf")), weight: 400 });
    renderer.registerFont({ name: "Inter", data: readFileSync(path.join(dir, "Inter-Bold.ttf")), weight: 700 });
  }
  return renderer;
}

export { backend }; // "native" | "wasm"

export function card({ title, description }) {
  return {
    type: "container",
    style: {
      display: "flex", flexDirection: "column", justifyContent: "center", gap: 24,
      width: "100%", height: "100%", padding: 64, fontFamily: "Inter",
      backgroundImage: "linear-gradient(to bottom right, #fff7ed, #fecaca)",
    },
    children: [
      { type: "text", text: title, style: { fontSize: 72, fontWeight: 700, color: "#111827" } },
      { type: "text", text: description, style: { fontSize: 42, color: "#4b5563" } },
    ],
  };
}
```

Trên Node, `bm-engine` là addon native hoặc binary wasm `full`. Nếu muốn cố định một profile wasm nhỏ
hơn, hãy import `bm-engine/standard` hoặc `bm-engine/core` (luôn là wasm). Một renderer chỉ render một ảnh
tại một thời điểm; với backend native, vài renderer (cùng bộ font) render song song trên thread pool.

## 3. Một route handler

```js
// app/og/route.js
import { getRenderer, card, backend } from "../../lib/og.js";

export const runtime = "nodejs"; // mặc định; ghi ra cho rõ

export async function GET(request) {
  const { searchParams } = new URL(request.url);
  const png = await getRenderer().render(
    card({
      title: searchParams.get("title") ?? "bm-engine + Next.js",
      description: searchParams.get("description") ?? "Rendered in a route handler",
    }),
    { width: 1200, height: 630 },
  );
  return new Response(png, {
    headers: { "content-type": "image/png", "cache-control": "public, max-age=3600", "x-bm-backend": backend },
  });
}
```

Truy cập `/og?title=Hello`. Để kiểm soát response khi lỗi (một `500` dạng text ngắn cộng với hook
`onError`), dùng [helper `imageResponse()`](./index.md#helper-imageresponse) thay cho `new Response`.

## 4. Quy ước file `opengraph-image`

Next.js đọc một file `opengraph-image.js` (hoặc `twitter-image.js`) nằm cạnh `page.js`, phục vụ nó và thêm
các thẻ `og:image`, `og:image:type`, `og:image:width` và `og:image:height`. Default export của nó có thể
trả về một `Response`, nên không cần `ImageResponse`:

```js
// app/opengraph-image.js
import { getRenderer, card } from "../lib/og.js";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "bm-engine + Next.js";

export default async function Image() {
  const png = await getRenderer().render(card({ title: "bm-engine + Next.js", description: "opengraph-image file convention" }), size);
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

Không có đầu vào động thì Next.js prerender file này lúc build. Với ảnh riêng cho từng trang trong một
segment động, default export nhận `{ params }` (một promise trong các phiên bản Next.js gần đây). Đặt
`metadataBase` trong root layout để các URL sinh ra là tuyệt đối; nếu không, bản build sẽ cảnh báo.
(Quy ước file này đã được kiểm chứng ở một lượt trước với Next.js 16.4.6; lượt này chạy lại các route
handler.)

## Edge runtime

Edge runtime không có `node:fs` và không có code native. Hãy import một binary wasm dưới dạng
`WebAssembly.Module` bằng hậu tố `?module` của Next.js rồi truyền nó cho `initSync` của điểm vào profile
tương ứng:

```js
// app/og-edge/route.js
import { initSync, Renderer } from "bm-engine/core";
import wasm from "bm-engine/core.wasm?module";

export const runtime = "edge";

let renderer;
async function getRenderer() {
  if (!renderer) {
    initSync(wasm);
    const font = await fetch(new URL("../../fonts/Inter-Regular.ttf", import.meta.url)).then((r) => r.arrayBuffer());
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: font });
  }
  return renderer;
}

export async function GET(request) {
  const title = new URL(request.url).searchParams.get("title") ?? "Edge";
  const r = await getRenderer();
  const png = r.renderSync(
    { type: "container", style: { display: "flex", width: "100%", height: "100%", padding: 64, backgroundColor: "#7c3aed" },
      children: [{ type: "text", text: title, style: { fontFamily: "Inter", fontSize: 72, color: "white" } }] },
    { width: 1200, height: 630 },
  );
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

Với Turbopack, route này build được và trả về PNG 1200 × 630 khi chạy `next start` lẫn từ output standalone
đã tách riêng. Lý do nó chạy được: Turbopack tra specifier trong `exports` của package **kể cả phần query**,
nên bm-engine khai báo `"./core.wasm?module"` (và tương tự cho `standard`, `full`, `wasm`, `woff`) trỏ tới
file và giữ nguyên query. Trước khi có mục này, lệnh import lỗi với
`Module not found: Can't resolve 'bm-engine/core.wasm'`, còn một key mà target không giữ query thì cho
`Export default doesn't exist in target module`. webpack bỏ query trước khi resolve, nên cùng lệnh import
này được kỳ vọng chạy với `--webpack`, nhưng không thể kiểm thử (xem khung ở đầu trang). Cách vòng
`Object.setPrototypeOf` mà các phiên bản cũ của trang này cần đã không còn: `initSync` nhận module mà
Next.js truyền vào.

Kích thước rất quan trọng trên Edge: binary `core` nặng 489.6 KiB khi chưa nén (khoảng 210 KiB gzip) và
font cộng thêm kích thước của chính nó; xem [Profile và kích thước](../../profiles-and-size.md). Edge runtime
đã bị deprecate trong Next.js 16 (bản build in ra cảnh báo) và không có addon native: nên dùng Node.js
runtime.

## Chuyển từ `next/og`

| `next/og` | bm-engine |
|:--|:--|
| `new ImageResponse(jsx, { width, height })` | `new Response(await renderer.render(node, { width, height }), { headers })` hoặc [`imageResponse()`](./index.md#helper-imageresponse) |
| JSX element | node object, chuỗi HTML, hoặc JSX thông qua [`h()`](./index.md#node-tree-không-cần-jsx) |
| mọi `div` đều là `display: flex` | mọi node đều là `display: inline` cho tới khi bạn đặt `display` |
| có font mặc định đi kèm | không có font nào cho tới khi bạn đăng ký |
| tùy chọn `emoji` (tải Twemoji) | đăng ký một font emoji màu (profile `full`) |
| `fonts: [{ name, data, weight, style }]` cho mỗi response | `renderer.registerFont(...)` một lần, hoặc render option `fonts` |

Xem [Chuyển từ satori và next/og](../migration/from-satori.md) để có danh sách đầy đủ.
