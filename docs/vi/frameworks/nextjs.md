# Next.js

[English](../../en/frameworks/nextjs.md) · [Tiếng Việt](nextjs.md)

Phục vụ ảnh Open Graph từ một route handler của Next.js App Router, hoặc để Next.js tự phát hiện chúng
qua quy ước file `opengraph-image`. bm-engine thay `ImageResponse` của `next/og` bằng một renderer do
bạn quản lý và một `Response` thông thường; ảnh là một node tree (hoặc HTML), không phải JSX — xem
[Node tree không cần JSX](./index.md#node-tree-không-cần-jsx) để có một helper `h()` nhỏ.

::: info Trạng thái kiểm chứng
Đã kiểm chứng với **Next.js 16.4.6 (Turbopack), `next build` + `next start` trên Node 26.13**, bm-engine
được cài từ tarball đã đóng gói: route handler và `opengraph-image.js` dưới đây trả về PNG 1200 × 630, và
các thẻ meta `og:image` của trang được sinh ra. Route chạy trên Edge runtime chỉ trả về PNG **khi có
cách vòng tránh được trình bày** (bm-engine 0.1.0 từ chối `WebAssembly.Module` mà Next.js truyền vào; xem
[Edge runtime](#edge-runtime)). Builder webpack (`next build --webpack`), việc deploy lên Vercel và các
phiên bản Next.js khác chưa được thử. Ứng dụng thử nằm trong
[`docs/examples/frameworks/nextjs/`](../../../docs/examples/frameworks/nextjs/).
:::

## 1. Cài đặt và giữ bm-engine ở dạng external

```sh
npm install bm-engine
```

```js
// next.config.mjs
/** @type {import("next").NextConfig} */
export default {
  serverExternalPackages: ["bm-engine"],
};
```

`serverExternalPackages` là **bắt buộc** với Node.js runtime: Node entry của bm-engine đọc file `.wasm`
nằm cạnh nó bằng `readFileSync(new URL("./bm_engine....wasm", import.meta.url))`. Khi Turbopack bundle
module đó, nó viết lại `new URL(...)` và build thất bại ở bước prerender:

```
TypeError: The "path" argument must be of type string or an instance of Buffer or URL. Received an instance of URL
```

Khi package ở dạng external, Node nạp nó từ `node_modules` và mọi thứ hoạt động (đã kiểm chứng cả hai
trường hợp).

## 2. Renderer và template dùng chung

Đặt renderer trong một module để nó chỉ được tạo một lần cho mỗi process server. Next.js chạy route
handler với thư mục gốc của dự án làm thư mục làm việc, nên `process.cwd()` là gốc đáng tin cậy cho các
file font nằm trong repository:

```js
// lib/og.js
import { readFileSync } from "node:fs";
import path from "node:path";
import { Renderer } from "bm-engine/standard";

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

## 3. Một route handler

```js
// app/og/route.js
import { getRenderer, card } from "../../lib/og.js";

export const runtime = "nodejs"; // the default; stated for clarity

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
    headers: { "content-type": "image/png", "cache-control": "public, max-age=3600" },
  });
}
```

Mở `/og?title=Hello`. Trong lần thử, response giữ nguyên header `cache-control`. Để kiểm soát response
khi lỗi (một `500` dạng text ngắn kèm hook `onError`), hãy dùng
[helper `imageResponse()`](./index.md#helper-imageresponse) thay cho `new Response`.

## 4. Quy ước file `opengraph-image`

Next.js đọc một file `opengraph-image.js` (hoặc `twitter-image.js`) nằm cạnh `page.js`, phục vụ nó và
thêm các thẻ `og:image`, `og:image:type`, `og:image:width` và `og:image:height`. Default export của nó
được phép trả về một `Response`, nên không cần `ImageResponse`:

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

Khi không có đầu vào động, Next.js prerender file này lúc build (bản build liệt kê `/opengraph-image` là
tĩnh và phục vụ nó với `cache-control: s-maxage=31536000`). Với ảnh riêng cho từng trang trong một
segment động, default export nhận `{ params }` (là một promise ở các phiên bản Next.js gần đây) — hãy
dựng card từ đó (không nằm trong phần thử).
Đặt `metadataBase` trong root layout để các URL được sinh ra là tuyệt đối; nếu không, build sẽ cảnh báo.

## Edge runtime

Trên Edge runtime không có `node:fs`, nên không dùng được Node entry. Bạn phải import binary dưới dạng
module WebAssembly và truyền nó cho `initSync`. Những gì đã xảy ra khi thử với Next.js 16.4.6
(Turbopack):

| Cách thử | Kết quả |
|:--|:--|
| `import wasm from "bm-engine/core.wasm?module"` | lỗi build: `Module not found: Can't resolve 'bm-engine/core.wasm'` |
| `import wasm from "bm-engine/core.wasm"` | lỗi build: Turbopack tự instantiate file (`Export default doesn't exist in target module`) |
| `import { init } from "bm-engine/core"; await init()` | build được; lỗi khi có request (`fetch failed`, `invalid method`): URL asset được xuất ra không fetch được bên trong sandbox của edge |
| đường dẫn tương đối + `?module`, như dưới đây | build được; `initSync` ném `WebAssembly.Module(): Argument 0 must be a buffer source` **trừ khi** thêm dòng vòng tránh; có dòng đó: 200, PNG 1200 × 630 |

```js
// app/og-edge/route.js
import { initSync, Renderer } from "bm-engine/core";
import wasm from "../../node_modules/bm-engine/js/bm_engine.core.wasm?module";

export const runtime = "edge";

let renderer;
async function getRenderer() {
  if (!renderer) {
    // Next.js hands the edge sandbox a WebAssembly.Module from another realm; bm-engine 0.1.0 checks
    // `instanceof WebAssembly.Module`, so re-brand it with this realm's prototype first.
    if (!(wasm instanceof WebAssembly.Module)) Object.setPrototypeOf(wasm, WebAssembly.Module.prototype);
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

::: warning Đường Edge dựa vào một cách vòng tránh
Dòng `Object.setPrototypeOf` vòng tránh một hạn chế của bm-engine 0.1.0 (phép kiểm tra module của nó phụ
thuộc vào realm), còn đường dẫn `node_modules` tương đối phụ thuộc vào cấu trúc cài đặt của bạn (nó hỏng
khi cách hoisting thay đổi, với pnpm hoặc monorepo). Hãy ưu tiên Node.js runtime trừ khi bạn thật sự cần
Edge. Nếu deploy lên Edge, hãy thử route đã deploy, không chỉ `next start`.
:::

Kích thước quan trọng trên Edge: binary `core` nặng 454.9 KiB thô (khoảng 210 KiB gzip) và font còn cộng
thêm kích thước của chúng; xem [Profile và kích thước](../profiles-and-size.md).

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
