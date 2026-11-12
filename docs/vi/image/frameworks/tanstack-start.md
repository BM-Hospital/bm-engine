# TanStack Start

[English](../../../en/image/frameworks/tanstack-start.md) · [Tiếng Việt](tanstack-start.md)

Server route của TanStack Start định nghĩa các HTTP handler nhận một `Request` chuẩn Web và trả về một
`Response`. Vì vậy một endpoint Open Graph chính là [mẫu chung](./index.md#mẫu-chung) đặt
bên dưới `server.handlers`.

::: info Trạng thái kiểm chứng
Đã kiểm chứng: object handler `GET({ request })` bên dưới được gọi trên Node 26.13 và trả về một PNG
1200 × 630 (`docs/examples/frameworks/check-frameworks.mjs`). **Chưa kiểm chứng trong một ứng dụng
TanStack Start thật**: API định nghĩa route (`createFileRoute(...)({ server: { handlers } })`) lấy theo
hướng dẫn TanStack Start của takumi và thay đổi giữa các bản phát hành TanStack Start — hãy kiểm tra phiên
bản bạn dùng.
:::

## Một server route

```tsx
// src/routes/og-image.ts
import { createFileRoute } from "@tanstack/react-router";
import { getRenderer, card } from "../server/og";          // the overview's og.js
import { imageResponse } from "../server/image-response";  // the overview's helper

export const Route = createFileRoute("/og-image")({
  server: {
    handlers: {
      GET: ({ request }) => {
        const url = new URL(request.url);
        return imageResponse(getRenderer(), card({
          title: url.searchParams.get("title") ?? "bm-engine + TanStack Start",
          description: url.searchParams.get("description") ?? "A server route",
        }), {
          width: 1200,
          height: 630,
          headers: { "cache-control": "public, max-age=3600" },
        });
      },
    },
  },
});
```

Truy cập `/og-image?title=Hello`. Sau đó tham chiếu nó từ phần head của trang:

```tsx
export const Route = createFileRoute("/posts/$slug")({
  head: ({ params }) => ({
    meta: [
      { property: "og:image", content: `https://example.com/og-image?title=${encodeURIComponent(params.slug)}` },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
});
```

## Dùng JSX

Dự án TanStack Start vốn đã biên dịch JSX bằng automatic runtime của React, vốn tạo ra React element chứ
không phải node của bm-engine. Các lựa chọn:

- dựng trực tiếp object node (như trên), hoặc gọi [`h()`](./index.md#node-tree-không-cần-jsx) như một hàm
  thông thường;
- đặt thẻ vào một file riêng có pragma `/** @jsxRuntime classic */ /** @jsx h */` để JSX của file đó gọi
  `h` (esbuild và TypeScript hỗ trợ; plugin React của Vite có thể ghi đè runtime — chưa thử ở đây);
- chuyển React element bằng `fromJsx()` của takumi trong `@takumi-rs/helpers` (xem
  [hướng dẫn chuyển đổi](../migration/from-takumi.md#jsx)).

## Đích triển khai (cấu hình dự kiến)

TanStack Start build qua Vite và triển khai lên Node (mặc định), Vercel, Netlify, Cloudflare và các đích
khác. Trên các đích dựa trên Node, đoạn mã trên chạy nguyên vẹn; giữ `bm-engine` là dependency lúc runtime
để các file `.wasm` của nó có mặt cạnh `js/node-*.mjs`. Trên Cloudflare hãy dùng
[mẫu Workers](./cloudflare-workers.md). Chưa build thử đích nào trong số này ở đây.
