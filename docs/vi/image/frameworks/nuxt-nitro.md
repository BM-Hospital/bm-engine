# Nuxt và Nitro

[English](../../../en/image/frameworks/nuxt-nitro.md) · [Tiếng Việt](nuxt-nitro.md)

Phía server của Nuxt là Nitro, và route của Nitro là các event handler của [h3](https://h3.dev). Một
handler h3 được phép trả về một `Response` chuẩn Web, nên một route dùng bm-render chính là
[mẫu chung](./index.md#mẫu-chung) đặt bên trong `defineEventHandler`. Trang này nói về `server/routes`
của Nuxt, Nitro độc lập, và những gì thay đổi trên các preset edge. Không có Nuxt module nào cho
bm-render.

::: info Trạng thái kiểm chứng
Đã kiểm chứng: handler dưới đây chạy dưới **h3 2.0.8** (`new H3().get(...)`, gửi request qua `app.fetch`)
trên Node 26.13 và trả về một PNG 1200 × 630 với `content-type: image/png`
(`docs/examples/frameworks/check-servers.mjs`). **Chưa kiểm chứng bên trong một bản build Nuxt hay Nitro
thật**: Nuxt 3/4 đi kèm h3 1.x, và cách h3 1.x xử lý một `Response` được trả về chưa được thử ở đây; các
ghi chú về bundle bên dưới là cấu hình dự kiến, chưa được thử.
:::

## Nuxt: một server route

```ts
// server/utils/og.ts — auto-imported in server code
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render/standard";

let renderer: Renderer | undefined;

export function getOgRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf"), weight: 400 });
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf"), weight: 700 });
  }
  return renderer;
}
```

```ts
// server/routes/og.png.ts  ->  GET /og.png?title=...
import { card } from "~/server/utils/card";            // the card() template from the overview
import { imageResponse } from "~/server/utils/image-response"; // the helper from the overview

export default defineEventHandler((event) => {
  const { title = "bm-render + Nuxt", description = "A Nitro server route" } = getQuery(event);
  return imageResponse(getOgRenderer(), card({ title: String(title), description: String(description) }), {
    width: 1200,
    height: 630,
    headers: { "cache-control": "public, max-age=3600" },
  });
});
```

- `defineEventHandler` và `getQuery` được Nuxt / Nitro tự import; bên ngoài chúng thì import từ `h3`.
- Đọc font bằng đường dẫn tương đối với thư mục làm việc chạy được khi server khởi động từ thư mục gốc
  của dự án. Trong bản build production (`.output/`), thư mục làm việc và cấu trúc file khác đi: hãy chép
  font cùng bản build (ví dụ vào `public/` hoặc một thư mục server asset) rồi đọc từ đó, hoặc dùng server
  asset của Nitro (`useStorage("assets:server")`) — kiểm tra tài liệu Nitro cho phiên bản bạn dùng.
- Nếu bạn muốn trả về byte thay vì một `Response`, hãy tự đặt header:
  `setResponseHeader(event, "content-type", "image/png"); return png;` (h3 gửi một `Uint8Array` làm
  body).

## Nitro độc lập / h3 thuần

Handler vẫn như vậy. Dùng h3 trực tiếp (đây là phần đã được chạy):

```js
import { H3, defineEventHandler, getQuery } from "h3";
import { getRenderer, card } from "./og.js";
import { imageResponse } from "./image-response.js";

const app = new H3().get("/og.png", defineEventHandler((event) => {
  const { title = "Hello" } = getQuery(event);
  return imageResponse(getRenderer(), card({ title: String(title), description: "From h3" }), { width: 1200, height: 630 });
}));

// app.fetch(request) is a Web-standard handler; serve it with h3's `serve(app)` or any adapter
const res = await app.fetch(new Request("http://localhost/og.png?title=Nitro"));
```

Trong một dự án Nitro, đặt cùng `defineEventHandler` đó vào `routes/og.png.ts` (Nitro v2: `server/routes/`
trong Nuxt, `routes/` khi dùng độc lập).

## Preset và bundle (cấu hình dự kiến)

| Preset | Cần làm gì |
|:--|:--|
| `node-server` (mặc định), `vercel` (Node function), `netlify` | `import ... from "bm-render/standard"` như trên. Nitro trace các dependency vào `.output/server/node_modules`; Node entry của bm-render sau đó đọc `.wasm` từ đó. Nếu lúc chạy thiếu file `.wasm`, hãy bảo đảm bm-render vẫn ở dạng external (đừng liệt kê nó trong `nitro.externals.inline`) và các file `js/*.wasm` của nó đã được chép sang. |
| `cloudflare-module`, `cloudflare-pages`, `vercel-edge` | không có `node:fs`: import binary dưới dạng module rồi gọi `initSync(module)`, và bundle font dưới dạng data. Hỗ trợ WebAssembly của Nitro (unwasm) quyết định cách xử lý các import `.wasm`; mẫu trên [trang Cloudflare Workers](./cloudflare-workers.md) là hình dạng cần đạt. Chưa thử với Nitro. |

bm-render tự instantiate binary của nó và cần hoặc các byte, hoặc một `WebAssembly.Module` chưa được
instantiate; một tích hợp bundler tự instantiate các import `.wasm` cho bạn (kiểu ESM-integration) là
không tương thích. Nếu `initSync` ném `Argument 0 must be a buffer source` dù bạn đã truyền một module,
xem ghi chú về realm trên [trang Next.js](./nextjs.md#edge-runtime).

## Dùng từ một trang Vue

Trỏ các thẻ meta tới route; phía client không cần gì thêm:

```ts
// pages/blog/[slug].vue  (script setup)
const route = useRoute();
useSeoMeta({
  ogImage: `https://example.com/og.png?title=${encodeURIComponent(String(route.params.slug))}`,
  twitterCard: "summary_large_image",
});
```

bm-render không render Vue component. Hãy
dựng node tree trong server route (hoặc render một Vue component thành chuỗi HTML bằng server renderer
của Vue rồi truyền chuỗi đó — đầu vào HTML cần profile `standard` hoặc `full`; xem
[HTML và Tailwind](../html-and-tailwind.md); chưa thử với Vue).
