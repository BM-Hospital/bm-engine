# TanStack Start

[English](../../../en/image/frameworks/tanstack-start.md) · [Tiếng Việt](tanstack-start.md)

Server route của TanStack Start định nghĩa các HTTP handler nhận một `Request` chuẩn Web và trả về một
`Response`. Vì vậy một endpoint Open Graph chính là [mẫu chung](./index.md#mẫu-chung) đặt
bên dưới `server.handlers`.

Route dưới đây là mẫu tích hợp. Kiểm tra API định nghĩa route theo phiên bản TanStack Start của ứng dụng; ví dụ chưa được chạy trong một bản build framework hoàn chỉnh tại đây.

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
          title: url.searchParams.get("title") ?? "bm-render + TanStack Start",
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
không phải node của bm-render. Các lựa chọn:

- Render React component thành HTML trên server rồi truyền chuỗi đó vào bm-render.

## Đích triển khai (cấu hình dự kiến)

TanStack Start build qua Vite và triển khai lên Node (mặc định), Vercel, Netlify, Cloudflare và các đích
khác. Trên các đích dựa trên Node, đoạn mã trên chạy nguyên vẹn; giữ `bm-render` là dependency lúc runtime
để các file `.wasm` của nó có mặt cạnh `js/node-*.mjs`. Trên Cloudflare hãy dùng
[mẫu Workers](./cloudflare-workers.md). Chưa build thử đích nào trong số này ở đây.
