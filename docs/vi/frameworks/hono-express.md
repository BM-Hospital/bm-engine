# Hono, Express và node:http

[English](../../en/frameworks/hono-express.md) · [Tiếng Việt](hono-express.md)

Server Node.js thuần là cách trực tiếp nhất để phục vụ ảnh với bm-engine: import một Node entry (nó tự
khởi tạo), tạo renderer một lần, rồi ghi các byte vào response. Trang này trình bày cùng một endpoint
`/og.png` trong Hono, Express và module `node:http` trần.

::: info Trạng thái kiểm chứng
Đã kiểm chứng trên Node 26.13 với bm-engine cài từ tarball đã đóng gói: mỗi server bên dưới được khởi động
trên một cổng localhost ngẫu nhiên rồi được fetch; mọi response đều là PNG 1200 × 630 với các header như
mong đợi. Phiên bản: **Hono 4.13.18 với @hono/node-server 2.1.7**, **Express 5.3.0**, `node:http`
(`docs/examples/frameworks/check-servers.mjs`). Express 4.22.3 chỉ được kiểm tra về cách `res.send` xử lý một `Uint8Array` trần (xem bên dưới).
:::

Cả ba đều import `og.js` từ trang tổng quan (`getRenderer()` và `card()`) và, với Hono, cả
[helper `imageResponse()`](./index.md#helper-imageresponse).

## Hono

Handler của Hono trả về `Response` chuẩn Web, nên helper dùng được ngay:

```js
import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { getRenderer, card } from "./og.js";
import { imageResponse } from "./image-response.js";

const app = new Hono();

app.get("/og.png", (c) =>
  imageResponse(getRenderer(), card({ title: c.req.query("title") ?? "Hello", description: "From Hono" }), {
    width: 1200,
    height: 630,
    headers: { "cache-control": "public, max-age=3600" },
  }));

serve({ fetch: app.fetch, port: 3000 });
```

`app.fetch` là một hàm `Request → Response` thuần, nên cùng ứng dụng này được kỳ vọng chạy được trên Bun
(`export default app`) và Deno (`Deno.serve(app.fetch)`) với Node entry, và trên Cloudflare Workers khi
renderer được khởi tạo từ một module đã import (xem [Cloudflare Workers](./cloudflare-workers.md)); các
runtime đó chưa được thử. Trong bài kiểm tra, `app.fetch(new Request(...))` cũng được gọi trực tiếp, không
qua server, và trả về PNG.

## Express

```js
import express from "express";
import { getRenderer, card } from "./og.js";

const app = express();

app.get("/og.png", async (req, res, next) => {
  try {
    const png = await getRenderer().render(
      card({ title: String(req.query.title ?? "Hello"), description: "From Express" }),
      { width: 1200, height: 630 },
    );
    res.type("png").set("cache-control", "public, max-age=3600");
    res.send(Buffer.from(png.buffer, png.byteOffset, png.byteLength));
  } catch (error) {
    next(error);
  }
});

app.listen(3000);
```

- `Buffer.from(png.buffer, ...)` bọc các byte mà không sao chép. Điều này quan trọng trên Express 4: thử
  với Express 4.22.3, `res.send(png)` với `Uint8Array` trần gửi đi **JSON** (`{"0":137,"1":80,...}`) kèm
  content type `image/png`. Express 5.3.0 gửi `Uint8Array` trần đúng cách. View `Buffer` chạy được trên cả
  hai.
- Express 5 tự chuyển các promise bị reject tới error handler; `try` / `next` tường minh giúp đoạn mã vẫn
  đúng trên Express 4.
- Đặt `res.type("png")` (hoặc `content-type`) một cách tường minh.

## node:http

Không dùng framework, kèm ETag tính từ đầu vào để các request lặp lại hoàn toàn không phải render:

```js
import { createServer } from "node:http";
import { getRenderer, card } from "./og.js";

const TEMPLATE_VERSION = "card-v1"; // bump when the template or fonts change

async function etagFor(params) {
  const data = new TextEncoder().encode(TEMPLATE_VERSION + "\0" + JSON.stringify(params));
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return `"${[...hash.subarray(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("")}"`;
}

createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname !== "/og.png") return res.writeHead(404).end();

  const params = {
    title: url.searchParams.get("title") ?? "Hello",
    description: url.searchParams.get("description") ?? "Rendered with bm-engine",
  };
  const etag = await etagFor(params);
  const headers = { etag, "cache-control": "public, max-age=3600, stale-while-revalidate=86400" };
  if (req.headers["if-none-match"] === etag) return res.writeHead(304, headers).end();

  try {
    const png = await getRenderer().render(card(params), { width: 1200, height: 630 });
    res.writeHead(200, { ...headers, "content-type": "image/png", "content-length": png.byteLength });
    res.end(png);
  } catch (error) {
    console.error(error);
    res.writeHead(500, { "content-type": "text/plain" }).end("Failed to generate image");
  }
}).listen(3000);
```

Bài kiểm tra request cùng một URL hai lần với `If-None-Match`: lần thứ hai nhận `304` và renderer chỉ bị
gọi một lần. `res.end()` nhận trực tiếp `Uint8Array`.

## Ghi chú cho production

- **Kiểm tra đầu vào.** Giới hạn độ dài chữ (`title.slice(0, 200)`), và đừng bao giờ lấy `width` /
  `height` từ query string mà không kiểm tra: canvas bị giới hạn ở 16384 px mỗi cạnh và 40 megapixel, và
  canvas lớn làm bộ nhớ wasm tăng vĩnh viễn (xem [Bộ nhớ](../api.md#bộ-nhớ-instance-và-luồng)).
- **CPU.** Việc render chặn event loop trong suốt thời gian render. Nếu server còn làm việc khác nhạy cảm
  với độ trễ, hãy render trong một [pool worker_threads](../recipes.md#pool-worker-threads) (đã kiểm
  chứng: 4 worker render 48 thẻ nhanh hơn 2,5–3,9× so với một luồng trên máy thử).
- **Cache.** Đặt một CDN phía trước, hoặc giữ một LRU trong bộ nhớ chứa các PNG gần đây, khóa theo ETag.
