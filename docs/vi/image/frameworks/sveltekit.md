# SvelteKit

[English](../../../en/image/frameworks/sveltekit.md) · [Tiếng Việt](sveltekit.md)

Một endpoint của SvelteKit (`+server.js`) là một hàm nhận request event và trả về `Response`, đúng thứ
bm-render cần. Trang này trình bày một endpoint động, một endpoint được prerender, và cách đưa HTML của
một Svelte component vào bm-render.

::: info Trạng thái kiểm chứng
Đã kiểm chứng: handler `GET` dưới đây được gọi trên Node 26.13 với dạng event mà SvelteKit truyền vào
(`{ url, request }`) và trả về một PNG 1200 × 630 (`docs/examples/frameworks/check-frameworks.mjs`).
**Chưa kiểm chứng bên trong một dự án SvelteKit thật** (không `vite build`, không adapter); các ghi chú
về adapter là cấu hình dự kiến.
:::

## Một endpoint động

Đặt `og.js` (`getRenderer()` và `card()`) cùng `image-response.js` từ
[trang tổng quan](./index.md#mẫu-chung) vào `src/lib/server/`.

```js
// src/routes/og.png/+server.js   ->  GET /og.png?title=...
import { getRenderer, card } from "$lib/server/og.js";
import { imageResponse } from "$lib/server/image-response.js";

export async function GET({ url }) {
  return imageResponse(
    getRenderer(),
    card({ title: url.searchParams.get("title") ?? "bm-render + SvelteKit", description: "A +server.js endpoint" }),
    { width: 1200, height: 630, headers: { "cache-control": "public, max-age=3600" } },
  );
}
```

Trong TypeScript, khai báo kiểu là `export const GET: RequestHandler = async ({ url }) => ...` với
`import type { RequestHandler } from "./$types"`. Giữ renderer trong `$lib/server/` để nó không bao giờ
bị import vào code phía client.

Font: với `adapter-node`, đọc chúng từ đĩa theo đường dẫn tương đối với thư mục làm việc (hoặc bundle
chúng bằng `?url` / file tĩnh). Nhớ rằng kết quả build nằm trong `build/`; các file trong `static/` được
chép sang đó.

## Prerender lúc build

Với ảnh chỉ phụ thuộc dữ liệu có sẵn lúc build, hãy prerender endpoint và các file sẽ được ghi vào kết
quả build như mọi asset tĩnh khác:

```js
// src/routes/og/[slug].png/+server.js
import { getRenderer, card } from "$lib/server/og.js";
import { posts } from "$lib/posts.js";

export const prerender = true;

export function entries() {
  return posts.map((post) => ({ slug: post.slug }));
}

export async function GET({ params }) {
  const post = posts.find((p) => p.slug === params.slug);
  const png = await getRenderer().render(card(post), { width: 1200, height: 630 });
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

Việc prerender chạy trên Node trong lúc `vite build`, nên Node entry vẫn dùng được kể cả khi sau đó bạn
deploy lên một adapter edge (chỉ các PNG tĩnh được đưa lên).

## Render một Svelte component

Bạn có thể render một component bằng `svelte/server` rồi truyền `head + body` dưới
dạng HTML. Cách này cũng chạy với đầu vào HTML của bm-render, vốn cần profile `standard` hoặc `full`
(phân tích HTML, cộng với tính năng `css` cho khối `<style>` được chèn vào). Font vẫn đến từ renderer:
đăng ký chúng một lần thay vì truyền URL font theo mỗi response:

```js
// src/routes/og-svelte.png/+server.js
import { render } from "svelte/server";
import OgImage from "$lib/components/OgImage.svelte"; // use <svelte:options css="injected" />
import { getRenderer } from "$lib/server/og.js";

export async function GET({ url }) {
  const { head, body } = render(OgImage, { props: { name: url.searchParams.get("name") ?? "you" } });
  const png = await getRenderer().render(head + body, { width: 1200, height: 630 });
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

Biến thể này chưa được chạy (chưa cài Svelte). Kiểm tra các tính năng HTML và CSS bạn dựa vào trong
[HTML và Tailwind](../html-and-tailwind.md); nhớ rằng bm-render chỉ render, nó không chạy script của
component.

## Adapter (cấu hình dự kiến)

| Adapter | Ghi chú |
|:--|:--|
| `adapter-node` | chạy như mọi server Node; giữ `bm-render` là dependency lúc chạy (SvelteKit mặc định để `dependencies` ở dạng external). |
| `adapter-vercel` (Node runtime), `adapter-netlify` | như Node; bảo đảm các file `.wasm` trong `node_modules/bm-render/js/` có mặt trong bundle của function. |
| `adapter-cloudflare` | không có `node:fs`: làm theo mẫu [Cloudflare Workers](./cloudflare-workers.md) (`initSync` với một module được import, font dưới dạng data) — hoặc prerender các ảnh. |
| `adapter-static` | prerender mọi thứ (ở trên). |
