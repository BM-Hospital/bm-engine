# Framework và runtime

[English](../../../en/image/frameworks/index.md) · [Tiếng Việt](index.md)

bm-render là một thư viện thuần: đưa vào một node tree (hoặc HTML), nhận lại các byte của ảnh. Nó không
có plugin cho framework nào, không có class `ImageResponse` và không có JSX runtime, nên mọi tích hợp đều
chỉ là ba dòng "keo" giống nhau — tạo renderer, đăng ký font, bọc các byte vào một `Response`. Trang này
giải thích những phần mà mọi tích hợp dùng chung: import entry nào của package, mẫu "tạo một lần", một
helper `imageResponse()` khoảng 30 dòng để bạn dán vào dự án, header cache, cách nạp font, và cách dựng
node tree mà không cần JSX. Các trang riêng cho từng framework sau đó chỉ trình bày những điểm khác biệt.

::: info Trạng thái kiểm chứng
Mọi đoạn mã trên trang này đều đã được chạy trên Node 26.13 với tarball npm đã đóng gói của bm-render 0.1.0
(`npm pack`, cài vào một dự án nháp): `imageResponse()` được gọi với một `Request` thật, body của
`Response` trả về được giải mã thành một PNG 1200 × 630; `h()` được kiểm tra cho ra kết quả giống từng
byte với node viết tay, kể cả khi dùng làm JSX factory của esbuild; các cách tự nạp wasm được chạy dưới
`node --conditions=browser`. Các script nằm trong
[`docs/examples/frameworks/`](../../../examples/frameworks/) (`node docs/examples/frameworks/run-all.mjs`).
:::

| Hướng dẫn | Runtime | Đã kiểm chứng những gì |
|:--|:--|:--|
| [Next.js](./nextjs.md) | Node.js runtime, Edge runtime | các hàm handler; xem trang riêng |
| [Nuxt và Nitro](./nuxt-nitro.md) | server route của Nitro (h3) | handler chạy dưới h3 2.0.8 |
| [SvelteKit](./sveltekit.md) | endpoint `+server.js` | hàm handler |
| [Astro](./astro.md) | endpoint, sinh tĩnh | handler + `getStaticPaths` |
| [TanStack Start](./tanstack-start.md) | server route | hàm handler |
| [Hono, Express, node:http](./hono-express.md) | server Node.js | server thật trên localhost |
| [Cloudflare Workers](./cloudflare-workers.md) | workerd | bundle của wrangler, chạy với ngữ nghĩa module của Workers được giả lập |
| [Deno và Bun](./deno-bun.md) | Deno, Bun | chưa chạy (chưa cài); handler chạy trên Node |
| [Vite và trình duyệt](./vite-browser.md) | trình duyệt, Web Worker | Edge 157 headless |

## Nên import entry nào

Package có một entry chung và ba entry cố định theo profile. Một specifier được phân giải tới file nào
phụ thuộc vào các export condition của runtime:

| Import | Node.js, Bun, Deno (điều kiện `node`) | Trình duyệt, bundler cho trình duyệt, workerd, Vercel Edge |
|:--|:--|:--|
| `bm-render` | binary full, đọc từ đĩa và khởi tạo khi import | chỉ có wrapper: bạn tự gọi `init(wasm)` |
| `bm-render/core` · `/standard` · `/full` | profile tương ứng, khởi tạo khi import | `await init()` tải binary nằm cạnh module (hoặc truyền vào) |
| `bm-render/wasm` (= `full.wasm`), `bm-render/core.wasm`, `/standard.wasm`, `/full.wasm`, `/woff.wasm` | file binary thô | file binary thô (URL asset với `?url` trong Vite, `WebAssembly.Module` dưới wrangler) |

Quy tắc kinh nghiệm:

- **Server trên Node.js (Express, Hono trên Node, Next.js Node runtime, Nuxt / SvelteKit / Astro với
  adapter Node):** `import { Renderer } from "bm-render/standard"` (hoặc `/core`, `/full`). Không cần
  khởi tạo gì; binary được đọc bằng `node:fs` khi module được nạp.
- **Bundle cho trình duyệt:** `import { init, Renderer } from "bm-render/standard"` rồi `await init()`.
  Vite, webpack 5 và Parcel xuất file `.wasm` thành asset (xem [Vite và trình duyệt](./vite-browser.md)).
- **Workers / edge runtime:** import binary dưới dạng module rồi truyền vào:
  `import wasm from "bm-render/core.wasm"; initSync(wasm)` (xem [Cloudflare Workers](./cloudflare-workers.md)).
- **Mọi trường hợp khác:** tự nạp các byte rồi gọi `init()` / `initSync()` (bên dưới).

Chọn profile nhỏ nhất có đủ những gì template của bạn dùng; `core` là đủ cho node tree với style inline
và font TTF. Xem [Profile và kích thước](../../profiles-and-size.md). Mỗi entry là **một wasm instance
riêng**: import cả `bm-render` lẫn `bm-render/full` trên Node sẽ nạp binary full hai lần, nên mỗi ứng
dụng hãy chọn một entry.

### Tự nạp wasm

`init()` nhận byte, chuỗi URL, `URL`, `Request`, `Response`, promise của bất kỳ thứ nào kể trên, một
`WebAssembly.Module` đã compile, hoặc object `{ module_or_path }`. `initSync()` nhận byte
hoặc một `WebAssembly.Module`. Một `Response` được phục vụ với `application/wasm` sẽ được compile bằng
`WebAssembly.instantiateStreaming`; mọi content type khác đi qua `arrayBuffer()`.

```js
import { init, initSync, Renderer } from "bm-render";

// 1. fetch it (browsers, Deno, workers that allow runtime compilation)
await init(fetch("/assets/bm_render.wasm"));

// 2. bytes you already have (any runtime that allows WebAssembly compilation from bytes)
initSync(bytes);

// 3. a precompiled module (Cloudflare Workers, Vercel Edge `?module` imports)
initSync(wasmModule);

await init({ module_or_path: "/assets/bm_render.wasm" });
```

Tất cả các cách này đều đã chạy dưới `node --conditions=browser`, điều kiện phân giải ra đúng những
file mà bundler dùng. `init()` là idempotent theo từng entry: lần gọi thành công đầu tiên thắng, các lần
gọi sau trả về cùng instance và bỏ qua tham số. Trước khi khởi tạo, `new Renderer()` ném lỗi
`bm-render: call init()/initSync() before creating a Renderer`, còn `init()` không tham số trên entry
chung sẽ reject với `bm-render: init() needs the wasm binary: ...`.

## Mẫu chung

Mọi tích hợp trong các trang này đều có cùng một dạng:

1. **Tạo một `Renderer` cho mỗi process (Node) hoặc mỗi isolate (Workers), theo kiểu lazy.** Đăng ký
   font sẽ parse font và chép vào bộ nhớ wasm; làm việc đó cho từng request vừa tốn thời gian vừa làm
   bộ nhớ phình ra.
2. **Đăng ký font một lần.** bm-render không kèm font nào: không có font đã đăng ký thì chữ không được vẽ.
3. **Với mỗi request:** đọc tham số, dựng node tree, render, trả về một `Response` chứa các byte và
   `content-type`.

```js
// og.js — shared by every route
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render/standard";

let renderer; // one per process / isolate

export function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: readFileSync(new URL("./fonts/Inter-Regular.ttf", import.meta.url)), weight: 400 });
    renderer.registerFont({ name: "Inter", data: readFileSync(new URL("./fonts/Inter-Bold.ttf", import.meta.url)), weight: 700 });
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

`display: "flex"` ở node gốc không phải tùy chọn:, mọi node mặc định là `display: inline`
(xem [Xử lý sự cố](../../troubleshooting.md#khối-chứa-bị-co-về-chiều-cao-0)). Các trang theo framework
import `getRenderer` và `card` từ file này.

::: tip Render chặn luồng
Một lần render là công việc WebAssembly đồng bộ (một card 1200 × 630 có gradient mất khoảng 14 ms trong
recipe render hàng loạt trên máy thử). `render()` trả về promise để trả kết quả bất đồng bộ, nhưng công việc
vẫn diễn ra trên luồng gọi nó. Với server nặng CPU, hãy render trong một worker pool
(xem [Recipes](../recipes.md#pool-worker-threads)).
:::

## Helper `imageResponse()`

bm-render không có class `ImageResponse` (đã kiểm tra: không có gì tên `ImageResponse` trong `js/`).
Helper dưới đây cho bạn phần hữu ích của nó. Nó chạy ở mọi nơi có `Response` và `Headers`: Node 18+,
Deno, Bun, Workers, trình duyệt và mọi framework trong các trang này.

```js
// image-response.js
const CONTENT_TYPES = { png: "image/png", jpeg: "image/jpeg", jpg: "image/jpeg", webp: "image/webp", ico: "image/x-icon" };

/**
 * Renders `source` (node tree, { json } or HTML string) and answers with the encoded image.
 * options: every render option, plus `headers`, `status`, `onError`.
 */
export async function imageResponse(renderer, source, options = {}) {
  const { headers, status = 200, onError = console.error, ...renderOptions } = options;
  const format = renderOptions.format ?? "png";
  if (format === "raw") throw new TypeError("imageResponse: use an encoded format, not raw");
  let bytes;
  try {
    bytes = await renderer.render(source, renderOptions);
  } catch (error) {
    onError(error);
    return new Response("Failed to generate image", { status: 500, headers: { "content-type": "text/plain; charset=utf-8" } });
  }
  const h = new Headers(headers);
  if (!h.has("content-type")) h.set("content-type", CONTENT_TYPES[format] ?? "application/octet-stream");
  h.set("content-length", String(bytes.byteLength));
  return new Response(bytes, { status, headers: h });
}
```

Cách dùng trong bất kỳ handler chuẩn Web nào:

```js
import { getRenderer, card } from "./og.js";
import { imageResponse } from "./image-response.js";

export async function GET(request) {
  const url = new URL(request.url);
  return imageResponse(getRenderer(), card({
    title: url.searchParams.get("title") ?? "Hello",
    description: url.searchParams.get("description") ?? "Rendered with bm-render",
  }), {
    width: 1200,
    height: 630,
    headers: { "cache-control": "public, max-age=3600" },
  });
}
```

Khi tự tạo HTTP response, lưu ý:

- Đây là một hàm trả về `Promise<Response>`, không phải class con của `Response`; hãy await hoặc trả
  thẳng promise đó (mọi framework ở đây đều chấp nhận handler trả về promise).
- Ảnh được render **trước** khi tạo response, nên render thất bại sẽ thành một `500` thật sự (không có
  body streaming hỏng giữa chừng, cũng không có promise `ready` nào phải await).
- Không có tùy chọn `emoji` và không có gì được tải về: font và ảnh phải được đăng ký sẵn hoặc truyền
  qua `images` (xem [Nạp font](#các-cách-nạp-font)).
- Renderer là tường minh. Tái sử dụng renderer trả về từ `getRenderer()` ở trên.

## Header cache

Một card đã render là hàm thuần của đầu vào, nên hãy cache mạnh nhất mà URL của bạn cho phép:

| Tình huống | `cache-control` |
|:--|:--|
| URL chứa phiên bản hoặc hash nội dung (`/og/post-42.png?v=3`) | `public, max-age=31536000, immutable` |
| Nội dung có thể đổi mà URL giữ nguyên | `public, max-age=3600, stale-while-revalidate=86400` (chỉnh theo tần suất bạn sửa nội dung) |
| Sau một CDN cần giữ lâu hơn trình duyệt | `public, max-age=600, s-maxage=86400` |
| Nội dung riêng của từng người dùng hoặc bí mật | `private, no-store` |

Một `ETag` tính **từ đầu vào** (phiên bản template + tham số) cho phép trả lời `If-None-Match` bằng `304`
mà không cần render gì cả; [recipe HTTP](../recipes.md#phục-vụ-qua-http-với-etag-và-cache-control)
minh họa điều này (đã kiểm chứng: request thứ hai trả về 304 và renderer không bị gọi). Crawler của mạng
xã hội chỉ tải ảnh OG vài lần, nên lợi ích lớn nằm ở cache của CDN và việc build ảnh lúc deploy
(xem [Astro](./astro.md) và [Recipes](../recipes.md#sinh-ảnh-lúc-build)).

## Các cách nạp font

bm-render không bao giờ đọc font hệ thống và không có font tích hợp sẵn. Chọn cách phù hợp với runtime:

| Cách | Ở đâu | Làm thế nào |
|:--|:--|:--|
| Đọc từ đĩa lúc khởi động | Node.js, Bun, Deno | `readFileSync(new URL("./fonts/Inter-Regular.ttf", import.meta.url))` |
| Bundle thành module | Cloudflare Workers | một rule `Data` của wrangler: `import inter from "./Inter-Regular.ttf"` cho ra một `ArrayBuffer` |
| Fetch một lần, giữ trong renderer | trình duyệt, Deno Deploy, mọi edge runtime | `renderer.registerFont(await (await fetch(url)).arrayBuffer())`, hoặc `await renderer.registerFont(url)` |
| Theo từng lần render, bất đồng bộ | hiếm khi cần | render option `fonts` (chỉ API async; đăng ký vào renderer) |

- Đăng ký mọi độ đậm bạn dùng (`fontWeight: 700` khi chỉ có face regular sẽ được tổng hợp, trông kém
  hơn một face bold thật). Đăng ký thêm một file dưới cùng `name` sẽ thêm một face vào family đó.
- TTF chạy trên mọi profile; `.otf` (CFF) và WOFF2 cần `standard` / `full`, hoặc
  [add-on WOFF](../api.md#add-on-woff) trên `core`. Hãy subset font về đúng các ký tự bạn cần để tiết
  kiệm bộ nhớ và thời gian khởi động.
- Ký tự không có trong một font sẽ fallback sang mọi family đã đăng ký khác, theo thứ tự đăng ký. Đăng
  ký font thương hiệu trước, các font phủ rộng sau (xem
  [recipe fallback](../recipes.md#i18n-chuỗi-font-fallback)).
- Trang [Font](../fonts.md) đi sâu vào việc khớp font, variable font và emoji.

## Node tree không cần JSX

bm-render nhận ba loại nguồn: một node object, `{ json: string }`, hoặc một chuỗi HTML (HTML cần
`standard` / `full`; xem [HTML và Tailwind](../html-and-tailwind.md)). Một node chỉ là dữ liệu thuần:

```js
{ type: "container", style: { display: "flex" }, children: [ /* nodes */ ] }
{ type: "text", text: "Hello", style: { fontSize: 48 } }
{ type: "image", src: "logo", width: 64, height: 64 }   // src: images key, data: URL, bytes or SVG markup
```

Viết tay các object này là ổn cho một card. Nhiều hơn thế, một hàm hyperscript mười dòng giúp template
dễ đọc:

```js
// h.js
export function h(tag, props, ...children) {
  const kids = children.flat(Infinity).filter((c) => c != null && typeof c !== "boolean")
    .map((c) => (typeof c === "object" ? c : { type: "text", text: String(c) }));
  if (typeof tag === "function") return tag({ ...props, children: kids }); // components
  const { children: _, ...meta } = props ?? {};
  if (tag === "img") return { type: "image", tagName: "img", ...meta }; // src, width, height, style
  return { type: "container", tagName: tag, ...meta, children: kids };  // style, tw, className, id, ...
}

export const Fragment = ({ children }) => children;
```

```js
import { h } from "./h.js";

const Title = ({ children }) => h("div", { style: { fontSize: 64, fontWeight: 700 } }, children);

const node = h("div", { style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", padding: 48, fontFamily: "Inter" } },
  h(Title, null, "Hello ", 42),
  user.isPro && h("span", { style: { fontSize: 32 } }, "Pro"),   // false / null are skipped
  h("img", { src: "logo", width: 64, height: 64 }),
);
```

Vì `h` có chữ ký kiểu `createElement` cổ điển, nó cũng dùng được làm **JSX factory** mà không cần React.
Với esbuild (`--jsx-factory=h --jsx-fragment=Fragment`), TypeScript (`"jsx": "react"`,
`"jsxFactory": "h"`, `"jsxFragmentFactory": "Fragment"`) hoặc pragma `/** @jsx h */`, bạn có thể viết:

```jsx
import { h, Fragment } from "./h.js";

export const Card = ({ title }) => (
  <div style={{ display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#7c3aed" }}>
    <span style={{ fontFamily: "Inter", fontSize: 48, color: "white" }}>{title}</span>
  </div>
);
```

Đường đi qua esbuild đã được kiểm chứng (esbuild 0.28.2: component sau khi compile render ra một PNG
400 × 200). Giới hạn của cách này, theo thiết kế:

- Đây là bộ dựng cây tĩnh: không có hook, không có context, không dùng được React component từ thư viện.
- `tagName` được ghi lại cho selector của stylesheet (tùy chọn `css`), nhưng **không có user-agent style
  nào được áp cho node tree**: một node `h1` không đậm, không có margin và là `inline` như mọi node khác
  (đã kiểm chứng bằng `measure()`). Hãy style tường minh, hoặc dùng chuỗi HTML, nơi HTML parser áp UA
  style.
- Một `Fragment` ở gốc trả về một mảng, đó không phải nguồn hợp lệ; hãy bọc nó trong một container.

Với React component, render thành chuỗi HTML trên server rồi truyền vào profile `standard` hoặc `full`. Với mẫu tĩnh, bạn cũng có thể dùng hàm dựng node ở trên.
