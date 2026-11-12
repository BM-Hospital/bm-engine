# Deno và Bun

[English](../../../en/image/frameworks/deno-bun.md) · [Tiếng Việt](deno-bun.md)

Deno và Bun đều chạy được package npm và đều phân giải export condition `node`, nên `bm-engine` cùng các
profile entry của nó nạp binary bằng `node:fs` và tự khởi tạo khi import, y hệt trên Node.js. HTTP server
tích hợp sẵn của chúng nhận một hàm `Request → Response`, tức là [mẫu chung](./index.md#mẫu-chung)
mà không cần framework nào.

::: warning Trạng thái kiểm chứng
**Chưa chạy trên Deno hay Bun** — máy thử không cài runtime nào trong hai cái này. Những gì đã kiểm chứng:
hàm `handler` bên dưới, chạy trên Node 26.13 với các object `Request` thật, trả về PNG 1200 × 630 và 404
cho các path khác (`docs/examples/frameworks/check-frameworks.mjs`); các biến thể nạp thủ công được kiểm
chứng dưới `node --conditions=browser`. Mọi thứ riêng của Deno hoặc Bun trên trang này (quyền truy cập,
specifier `npm:`, cách xử lý condition) là hành vi dự kiến, chưa được thử.
:::

## Handler dùng chung

```js
// handler.js
import { getRenderer, card } from "./og.js";          // the overview's og.js
import { imageResponse } from "./image-response.js";  // the overview's helper

export async function handler(request) {
  const url = new URL(request.url);
  if (url.pathname !== "/og.png") return new Response("Not found", { status: 404 });
  return imageResponse(getRenderer(), card({
    title: url.searchParams.get("title") ?? "Hello",
    description: "Deno.serve / Bun.serve",
  }), { width: 1200, height: 630, headers: { "cache-control": "public, max-age=3600" } });
}
```

## Bun

```js
// server.js — bun run server.js
import { handler } from "./handler.js";

Bun.serve({ port: 3000, fetch: handler });
```

`bun add bm-engine` để cài; `import { Renderer } from "bm-engine/standard"` trong `og.js` phân giải tới
Node entry. Đọc font bằng `readFileSync(new URL("./fonts/Inter-Regular.ttf", import.meta.url))` chạy trên
Bun như trên Node. File thực thi đơn (`bun build --compile`) chưa được thử: Node entry đọc `.wasm` của nó
từ ổ đĩa, cạnh `node_modules/bm-engine/js/`, nên file đó phải tồn tại lúc runtime (hoặc trỏ `BM_WASM` tới
một bản sao, với entry `bm-engine`).

## Deno

```js
// server.js — deno run --allow-read --allow-net server.js
import { handler } from "./handler.js";

Deno.serve({ port: 3000 }, handler);
```

Import bằng specifier `npm:` (`import { Renderer } from "npm:bm-engine/standard"`) hoặc ánh xạ
`bm-engine` trong `deno.json` (`"imports": { "bm-engine": "npm:bm-engine" }` — khi đó các subpath cần ánh
xạ riêng hoặc tiền tố `npm:`). Cần `--allow-read` vì Node entry đọc `.wasm` của nó (và font của bạn) từ ổ
đĩa.

### Deno Deploy và các môi trường không truy cập được file

Vì Deno và Bun phân giải condition `node`, mọi specifier `bm-engine` import từ npm đều trỏ tới một Node
entry đọc binary bằng `node:fs` **ngay khi import**. Package không có export nào trả về entry kiểu trình
duyệt, chưa khởi tạo, dưới condition `node`, nên ở nơi không đọc được file, bạn phải bỏ qua cơ chế phân
giải npm và import các file dành cho trình duyệt qua URL, rồi tự nạp binary:

```js
// the same files the package ships in js/, served from your own origin or a CDN
import { init, Renderer } from "https://cdn.example.com/bm-engine/js/standard.mjs";

await init(); // fetches bm_engine.standard.wasm next to standard.mjs
// or: await init(fetch("https://cdn.example.com/bm-engine/js/bm_engine.standard.wasm"));
// or: initSync(bytes);
```

`init(fetch(url))`, `init()` trên một profile entry và `initSync(bytes)` đã được kiểm chứng dưới
`node --conditions=browser` (cùng các file đó); import chúng qua URL trong Deno thì chưa thử. Các file cho
trình duyệt không có dependency nào (`standard.mjs` chỉ import `./engine.mjs`), nên vendor nguyên thư mục
`js/` cũng được.

## Chọn entry

| Mục tiêu | Import |
|:--|:--|
| Tự khởi tạo, đọc từ `node_modules` | `bm-engine/core`, `/standard`, `/full` (hoặc `bm-engine` = full) |
| Kiểm soát tường minh binary | các file trình duyệt qua URL + `init(...)` / `initSync(...)`, hoặc `BM_WASM=/path/file.wasm` với Node entry `bm-engine` |
| Nhiều profile song song | mỗi profile entry có wasm instance riêng |
