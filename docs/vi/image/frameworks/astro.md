# Astro

[English](../../../en/image/frameworks/astro.md) · [Tiếng Việt](astro.md)

Endpoint của Astro là các file trong `src/pages/` export hàm `GET`. Khi build tĩnh, Astro gọi chúng một
lần cho mỗi path và ghi các byte trả về vào `dist/`, nên đây là cách đơn giản nhất để phát hành mỗi trang
một ảnh Open Graph mà không tốn chi phí runtime nào. Ở chế độ server, cùng endpoint đó render theo từng
request.

Dùng server endpoint của Astro để trả byte ảnh. Ví dụ dưới đây minh họa cách tích hợp; hãy kiểm tra trong bản build ứng dụng của bạn.

## Mỗi trang một ảnh lúc build

```js
// src/pages/og/[slug].png.js  ->  dist/og/<slug>.png
import { getCollection } from "astro:content";
import { getRenderer, card } from "../../lib/og.js"; // the overview's og.js

export async function getStaticPaths() {
  const posts = await getCollection("blog");
  return posts.map((post) => ({
    params: { slug: post.id },
    props: { title: post.data.title, description: post.data.description },
  }));
}

export async function GET({ props }) {
  const png = await getRenderer().render(card(props), { width: 1200, height: 630 });
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

- Phần `.png` trong tên file trở thành phần mở rộng của file được sinh ra.
- Renderer được tạo một lần cho cả bản build (ở phạm vi module), nên font chỉ được parse một lần dù có
  hàng nghìn trang: recipe batch render 48 thẻ trong khoảng 0,7 s trên một luồng.
- Có thể đọc font bằng `readFileSync` tương đối với thư mục gốc dự án (`process.cwd()` trong lúc build).

Tham chiếu ảnh từ layout:

```astro
---
// src/layouts/Post.astro
const { title, slug } = Astro.props;
const ogImage = new URL(`/og/${slug}.png`, Astro.site);
---
<meta property="og:title" content={title} />
<meta property="og:image" content={ogImage} />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
```

Đặt `site` trong `astro.config.mjs` để `Astro.site` có giá trị.

## Render theo yêu cầu

Với một adapter và `output: "server"` (hoặc `export const prerender = false` trên endpoint), cùng hàm
`GET` đó chạy theo từng request. Khi đó đọc tham số từ URL thay vì từ props:

```js
// src/pages/og.png.js
import { getRenderer, card } from "../lib/og.js";
import { imageResponse } from "../lib/image-response.js";

export const prerender = false;

export async function GET({ url }) {
  return imageResponse(getRenderer(), card({
    title: url.searchParams.get("title") ?? "bm-render + Astro",
    description: url.searchParams.get("description") ?? "On-demand endpoint",
  }), { width: 1200, height: 630, headers: { "cache-control": "public, max-age=86400" } });
}
```

Với `@astrojs/node`, đây vẫn là Node entry như thường lệ. Với `@astrojs/cloudflare`, hãy làm theo mẫu
[Cloudflare Workers](./cloudflare-workers.md) (import `.wasm` như một module, font dưới dạng data); chưa
thử với pipeline Vite của Astro.

## Không dùng endpoint: một script build

Nếu không muốn đụng tới routing của Astro, hãy chạy một script Node trước `astro build` để ghi các PNG vào
`public/og/` (Astro chép nguyên `public/`). [Recipe build-time](../recipes.md#sinh-ảnh-lúc-build)
làm đúng việc đó và bỏ qua các bài viết có đầu vào không đổi:

```json
{ "scripts": { "build": "node scripts/build-og.mjs public/og && astro build" } }
```
