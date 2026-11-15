# Trả PDF từ framework

[English](../../en/pdf/frameworks.md) · [Tiếng Việt](frameworks.md)

Trả về một PDF cũng giống như trả về một ảnh: tạo renderer một lần, render cho mỗi request, bọc các byte
vào một `Response`. Các trang framework của phần Ảnh hướng dẫn thiết lập cho từng framework
([Framework và runtime](../image/frameworks/index.md): Next.js, Nuxt và Nitro, SvelteKit, Astro, TanStack
Start, Hono, Express, node:http, Cloudflare Workers, Deno, Bun, Vite). Mọi thứ ở đó đều áp dụng cho đầu ra
PDF; trang này chỉ liệt kê những gì khác đi và đưa ra một handler bạn có thể đặt vào bất kỳ framework nào
trong số đó.

::: info Tình trạng kiểm chứng
Mọi đoạn mã trên trang này là một đoạn của `docs/examples/pdf-frameworks.mjs` trong repository và đã được
chính file đó chạy trên Node 26.13, một lần trên addon native (`backend` báo `"native"`) và một lần với
`BM_ENGINE_BACKEND=wasm` (`backend` báo `"wasm"`): handler được gọi trực tiếp trong tiến trình với một
`Request` thật, và qua server `node:http` bên dưới trên một cổng cục bộ bằng `fetch`. Cả hai lần đều kiểm
tra status, `content-type: application/pdf`, `content-disposition`, `content-length` và phần đầu tệp
`%PDF-`, và việc một request đã bị huỷ sẽ reject với `AbortError`. Bản thân các adapter của framework chưa
được chạy với đầu ra PDF.
:::

- [Khác gì so với ảnh](#khác-gì-so-với-ảnh)
- [Một renderer cho mỗi tiến trình](#một-renderer-cho-mỗi-tiến-trình)
- [Helper `pdfResponse()`](#helper-pdfresponse)
- [Một handler cho mọi framework](#một-handler-cho-mọi-framework)
- [node:http](#nodehttp)
- [Edge runtime và trình duyệt](#edge-runtime-và-trình-duyệt)

## Khác gì so với ảnh

| | Ảnh | PDF |
|:--|:--|:--|
| Import | `bm-engine` hoặc một profile entry (`bm-engine/core`, `/standard`, `/full`) | chỉ `bm-engine/pdf`; các entry khác throw khi gọi `renderPdf` ([Bắt đầu nhanh với PDF](index.md)) |
| Renderer | `Renderer` | `PdfRenderer` (cùng API font: `registerFont`, `loadFont`, ...) |
| Kích thước kết quả | do `width` / `height` quyết định | do tài liệu quyết định: một hoặc nhiều trang (`size`, `margin`, `viewport`) |
| `content-type` | `image/png`, `image/webp`, ... | `application/pdf` |
| `content-disposition` | thường không đặt | `inline` (hiện trong trình xem của trình duyệt) hoặc `attachment` (lưu thành tệp), kèm `filename` |
| Cache | ảnh OG là hàm thuần của URL: cache mạnh tay | tài liệu thường riêng cho từng người dùng: `private, no-store` trừ khi là tài liệu công khai |
| Tệp wasm cho Workers / trình duyệt | `bm_engine.wasm` và các profile nhỏ hơn | `bm_engine.pdf.wasm`: 3 187.8 KiB thô, 1 311.8 KiB gzip, 1 015.7 KiB brotli |

`render()` trả về cả tệp dưới dạng một `Uint8Array` khi tài liệu đã xong; không có API streaming. Các ví dụ
trên trang này nặng 15 KiB; các [công thức](recipes.md) từ 19 tới 40 KiB, phần lớn là font đã subset. Hãy
đặt `content-length` từ `byteLength`.

Trên Node.js, `bm-engine/pdf` dùng addon native khi nó được cài: khi đó `render()` chạy trên thread pool của
libuv và không chặn event loop. Trên backend wasm (và ở mọi nơi ngoài Node.js), việc render là công việc
đồng bộ trên thread gọi nó, giống như với ảnh; xem [Native và WebAssembly](native-and-wasm.md) và, nếu cần
worker pool, [Công thức cho ảnh](../image/recipes.md#pool-worker-threads).

## Một renderer cho mỗi tiến trình

Giống như với ảnh, hãy tạo `PdfRenderer` một cách lười (lazy), một lần cho mỗi tiến trình hoặc isolate, và
đăng ký font vào nó ([Font trong PDF](fonts.md)):

<!-- @example pdf-frameworks#renderer -->
```js
// pdf.js — create the renderer once per process (or per isolate), not per request
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

let renderer;
export function getPdfRenderer() {
  if (!renderer) {
    renderer = new PdfRenderer();
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
  }
  return renderer;
}
```

## Helper `pdfResponse()`

Phiên bản PDF của [`imageResponse()`](../image/frameworks/index.md#helper-imageresponse) trong phần Ảnh:

<!-- @example pdf-frameworks#helper -->
```js
/** PDF bytes -> a web-standard Response. `download: true` makes browsers save the file instead of showing it. */
export function pdfResponse(bytes, { filename = "document.pdf", download = false, headers = {} } = {}) {
  return new Response(bytes, {
    headers: {
      "content-type": "application/pdf",
      "content-length": String(bytes.byteLength),
      "content-disposition": `${download ? "attachment" : "inline"}; filename="${filename}"`,
      ...headers,
    },
  });
}
```

`inline` cho phép trình duyệt mở trình xem PDF của nó; `attachment` khiến trình duyệt tải tệp về với tên
`filename`. Một `filename` có ký tự ngoài ASCII cần thêm dạng RFC 6266 `filename*=UTF-8''...`.

## Một handler cho mọi framework

Route Handler của Next.js, `+server.js` của SvelteKit, endpoint của Astro, server route của TanStack Start,
Hono, Nitro (h3 2), Cloudflare Workers, Deno và Bun đều đưa cho bạn một `Request` chuẩn web và nhận lại một
`Response`, nên hàm này dùng được ngay: export nó thành `GET`, trả về từ `app.get(...)`, hoặc gọi trong
`fetch`.

<!-- @example pdf-frameworks#handler -->
```js
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** GET /report.pdf?name=Ada[&download=1] — works wherever a framework hands you a Request. */
export async function handleReport(request) {
  const url = new URL(request.url);
  const name = escapeHtml((url.searchParams.get("name") ?? "World").slice(0, 100));
  const bytes = await getPdfRenderer().render(
    `<div style="font-family: Inter; font-size: 14px">
       <h1>Report for ${name}</h1>
       <p>Generated on ${new Date().toISOString().slice(0, 10)}.</p>
     </div>`,
    {
      size: "a4",
      footer: `<div style="font: 10px Inter; text-align: center">Page <span class="pageNumber"></span></div>`,
      signal: request.signal, // a request the client abandoned is not rendered
    },
  );
  return pdfResponse(bytes, {
    filename: "report.pdf",
    download: url.searchParams.has("download"),
    headers: { "cache-control": "private, no-store" },
  });
}
```

- **Escape dữ liệu đầu vào** khi đưa vào HTML (`escapeHtml` ở trên) và giới hạn độ dài, như với ảnh.
- **`signal: request.signal`** kiểm tra `AbortSignal` của request trước khi render đọc và vẽ tài liệu: một
  request đã bị huỷ sẽ reject với `AbortError` thay vì render. Nó không ngắt một lần render đã bắt đầu.
- Trên Next.js và các công cụ deploy có bundle, phần thiết lập của mục Ảnh áp dụng y nguyên (ví dụ
  `serverExternalPackages: ["bm-engine"]` và chép package nền tảng:
  [Next.js](../image/frameworks/nextjs.md)); entry PDF nằm trong cùng package.

## node:http

`node:http` không có `Request` / `Response`; hãy chuyển đổi ở rìa (các framework làm việc này thay bạn).
Bài kiểm tra đã chạy server này trên một cổng ngẫu nhiên và gọi `/report.pdf`:

<!-- @example pdf-frameworks#node-http -->
```js
import { createServer } from "node:http";
import { Readable } from "node:stream";

// node:http has no Request / Response: convert at the edge (Hono, Nitro, SvelteKit, ... do this for you)
const server = createServer(async (req, res) => {
  const controller = new AbortController();
  res.on("close", () => { if (!res.writableFinished) controller.abort(); });
  try {
    const request = new Request(new URL(req.url, `http://${req.headers.host}`), { signal: controller.signal });
    const response = await handleReport(request);
    res.writeHead(response.status, Object.fromEntries(response.headers));
    Readable.fromWeb(response.body).pipe(res);
  } catch (error) {
    if (!controller.signal.aborted) console.error(error);
    if (!res.headersSent) res.writeHead(500, { "content-type": "text/plain" }).end("Failed to render the PDF");
  }
});
server.listen(Number(process.env.PORT ?? 3000));
```

Express có thể dùng cùng handler này qua một adapter như vậy, hoặc render trực tiếp rồi `res.end(bytes)` với
các header của `pdfResponse()`; chi tiết riêng của Express nằm ở [Hono, Express và
node:http](../image/frameworks/hono-express.md).

## Edge runtime và trình duyệt

Ngoài Node.js, `bm-engine/pdf` là profile wasm `pdf` và phải được khởi tạo một lần trước lần render đầu
tiên: `await init()` tải `bm_engine.pdf.wasm` nằm cạnh module (trình duyệt, bundler), còn trên Cloudflare
Workers bạn import tệp nhị phân như một module rồi truyền vào:

```js
import wasm from "bm-engine/pdf.wasm";
import { init, PdfRenderer } from "bm-engine/pdf";

await init(wasm);
```

Đoạn này chưa được chạy dưới wrangler. Kích thước nén của `bm_engine.pdf.wasm` (1 311.8 KiB gzip) được tính
vào giới hạn kích thước script của gói Workers bạn dùng; xem [Cloudflare
Workers](../image/frameworks/cloudflare-workers.md) cho phần còn lại của thiết lập và [Bắt đầu nhanh với
PDF](index.md) cho ví dụ trên trình duyệt mở kết quả bằng một URL `Blob`.
