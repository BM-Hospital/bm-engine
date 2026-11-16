# Cloudflare Workers

[English](../../../en/image/frameworks/cloudflare-workers.md) · [Tiếng Việt](cloudflare-workers.md)

Workers không có hệ thống file và không cho phép biên dịch WebAssembly từ byte lúc runtime; thay vào đó,
wrangler biên dịch trước mọi file `.wasm` được import và đưa cho mã của bạn một `WebAssembly.Module`.
`init()` / `initSync()` của bm-render nhận đúng thứ đó, nên một Worker import binary, khởi tạo một lần cho
mỗi isolate, bundle font dưới dạng data và trả về một `Response`.

::: info Trạng thái kiểm chứng
Đã kiểm chứng với **wrangler 4.160.1**: `wrangler deploy --dry-run --outdir dist` đã bundle Worker bên
dưới (các file `.wasm` và `.ttf` được xuất thành các module riêng). Sau đó **bản bundle đầu ra** và mã
nguồn được chạy trên Node 26.13 với ngữ nghĩa module của Workers được giả lập (import `.wasm` →
`WebAssembly.Module`, rule `Data` → `ArrayBuffer`, một `caches.default` trong bộ nhớ, export condition
`workerd`): cả hai đều trả về PNG 1200 × 630, và request thứ hai được phục vụ từ cache
(`docs/examples/frameworks/check-cloudflare.mjs`). **Chưa chạy trong chính workerd** — `wrangler dev`
không khởi động được trên máy thử (binary `workerd.exe` không nạp được), và chưa triển khai gì cả.
:::

## Worker

```js
// src/worker.js
import { initSync, Renderer } from "bm-render/core";
import wasm from "bm-render/core.wasm";             // a WebAssembly.Module (wrangler compiles .wasm imports)
import interRegular from "./Inter-Regular.ttf";     // an ArrayBuffer (the "Data" rule in wrangler.toml)
import interBold from "./Inter-Bold.ttf";

initSync(wasm);
let renderer; // one per isolate, reused across requests

function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: interRegular, weight: 400 });
    renderer.registerFont({ name: "Inter", data: interBold, weight: 700 });
  }
  return renderer;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== "/og.png") return new Response("Not found", { status: 404 });

    const cache = caches.default;
    const cached = await cache.match(request);
    if (cached) return cached;

    const title = url.searchParams.get("title") ?? "Hello from Workers";
    const png = getRenderer().renderSync(
      {
        type: "container",
        style: { display: "flex", flexDirection: "column", justifyContent: "center", width: "100%", height: "100%",
          padding: 64, fontFamily: "Inter", backgroundImage: "linear-gradient(to bottom right, #fff7ed, #fecaca)" },
        children: [{ type: "text", text: title, style: { fontSize: 72, fontWeight: 700, color: "#111827" } }],
      },
      { width: 1200, height: 630 },
    );
    const response = new Response(png, {
      headers: { "content-type": "image/png", "cache-control": "public, max-age=86400" },
    });
    ctx.waitUntil(cache.put(request, response.clone()));
    return response;
  },
};
```

```toml
# wrangler.toml
name = "@hunghg255/bm-render-og"
main = "src/worker.js"
compatibility_date = "2025-06-01"

[[rules]]
type = "Data"
globs = ["**/*.ttf"]
fallthrough = true
```

- wrangler phân giải `bm-render/core` với condition `workerd` tới entry kiểu trình duyệt (không có
  `node:fs`), và `bm-render/core.wasm` tới binary thô. Không cần cờ `nodejs_compat`.
- Import `.wasm` được xử lý bằng các module rule mặc định của wrangler; chỉ cần thêm rule cho font.
- Dùng cùng một profile cho JS entry và binary (`bm-render/core` + `bm-render/core.wasm`,
  `bm-render/standard` + `/standard.wasm`, `bm-render/full` + `/full.wasm`). Với entry chung `bm-render`,
  truyền `bm-render/wasm` (= full).
- WOFF trên `core`: `import woff from "bm-render/woff.wasm"; import { loadWoff } from "bm-render/woff"; await loadWoff(woff);`
  (đã kiểm chứng với một `WebAssembly.Module` dưới `--conditions=workerd`).
- `caches.default` lưu response vào cache của data centre; response phải cache được
  (`cache-control`). Để cache toàn cầu, đặt Worker sau một route có Cache Rules.

## Giới hạn kích thước

Workers giới hạn kích thước nén của script được upload (tính gộp mọi module). Giới hạn tùy theo gói dịch
vụ và thay đổi theo thời gian — hãy xem tài liệu hiện hành của Cloudflare. Phần bm-render đóng góp:

| Module | raw | gzip -9 |
|:--|--:|--:|
| `bm_render.core.wasm` | 489.6 KiB | 229.5 KiB |
| `bm_render.standard.wasm` | 936.5 KiB | 465.1 KiB |
| `bm_render.wasm` (full) | 1 143.6 KiB | 560.0 KiB |
| JS wrapper (đã bundle) | ~23 KiB | — |

Bản dry-run của Worker ở trên báo **Total Upload: 1290.11 KiB / gzip: 618.63 KiB**, phần lớn là hai file
Inter TTF (mỗi file khoảng 400 KiB). Font thường tốn hơn cả engine: hãy subset font theo các ký tự bạn
cần, hoặc nạp chúng từ R2 / KV / một URL ở request đầu tiên thay vì bundle (lời gọi `registerFont` vẫn y
hệt với một `ArrayBuffer` lấy từ `fetch`).

## Thời gian CPU

Render là công việc CPU đồng bộ nằm trong request: một thẻ 1200 × 630 có gradient mất khoảng 14 ms trên
máy thử (Node; chưa đo trên workerd). Request đầu tiên trong một isolate còn phải trả thêm chi phí khởi
tạo module và parse font. Hãy cache kết quả (như trên) để phần lớn request không bao giờ phải render, và
kiểm tra giới hạn thời gian CPU của gói bạn dùng.

## Những gì không chạy trên Workers

- `await init()` không có đối số trên một profile entry: nó cố fetch file `.wasm` nằm cạnh module, mà
  trong Worker file đó không tồn tại dưới dạng URL. Hãy truyền module đã import.
- Khởi tạo từ byte (`initSync(bytes)` / `init(arrayBuffer)`): Workers cấm biên dịch lúc runtime; hãy import
  `.wasm` thay vào đó.
- Đọc file bằng `node:fs`; và bất cứ thứ gì ngầm fetch ảnh từ xa — bm-render không bao giờ fetch; hãy tự
  `fetch()` rồi truyền qua `images` (xem [recipe ảnh từ xa](../recipes.md#nhúng-ảnh-từ-xa)).
