# Vite và trình duyệt

[English](../../en/frameworks/vite-browser.md) · [Tiếng Việt](vite-browser.md)

bm-engine chạy hoàn toàn trong trình duyệt: binary không có import nào, nên mọi engine có WebAssembly
SIMD đều render ra đúng các byte như Node. Trang này nói về bundler (Vite trước tiên), cách nạp khi không
có bundler hoặc từ CDN, cách render trong Web Worker để trang không bao giờ bị giật, và cách hiển thị kết
quả.

::: info Trạng thái kiểm chứng
- **Vite**: bài kiểm tra package của repository (`npm run test:pack`, `scripts/pack-test.mjs`) build hai
  trang bằng **Vite 8.3.8** — `bm-engine/core` + `await init()`, và `bm-engine` + `init(wasmUrl)` từ một
  import `?url`, kèm add-on WOFF — rồi nạp chúng trong **Edge 157 headless**: PNG được render, không có lỗi
  console.
- **Web Worker, không bundler**: `docs/examples/frameworks/check-browser.mjs` phục vụ
  `docs/examples/frameworks/browser/` và chạy nó trong Edge 157 headless: một module worker chạy
  `await init()` từ `bm-engine/standard`, render với `devicePixelRatio` 2, chuyển (transfer) PNG về, và
  trang hiển thị nó qua một blob URL và `createImageBitmap` (1200 × 630, không có lỗi console).
- `init(fetch(url))` với `application/wasm` đã dùng `WebAssembly.instantiateStreaming` (kiểm tra dưới
  `node --conditions=browser`).
- **Chưa thử**: cơ chế bundle worker của Vite (`new Worker(new URL(...))` trong một bản build Vite),
  webpack, Rollup, Parcel, và nạp từ CDN (package chưa được phát hành).
:::

## Vite

Import một profile entry và gọi `init()` không đối số:

```js
import { init, Renderer } from "bm-engine/standard";

await init(); // Vite emits bm_engine.standard.wasm as an asset and rewrites the URL
const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: await (await fetch("/Inter-Regular.ttf")).arrayBuffer() });
```

Các profile entry tìm binary của mình bằng `new URL("./bm_engine.standard.wasm", import.meta.url)`, một
mẫu mà Vite (cùng webpack 5, Parcel) biến thành một asset được xuất ra. Nếu muốn tự kiểm soát URL, hãy
import nó với `?url` rồi truyền vào:

```js
import { init, Renderer } from "bm-engine";
import wasmUrl from "bm-engine/standard.wasm?url";

await init(wasmUrl); // any profile's binary works with the generic entry
```

- **Đừng** thêm `vite-plugin-wasm` hay bật tích hợp WebAssembly ESM cho các file này: bm-engine tự khởi
  tạo module và cần một URL, byte hoặc một `WebAssembly.Module` chưa được khởi tạo.
- Ở production, phục vụ `.wasm` với `application/wasm` để biên dịch dạng streaming (dev server của Vite và
  hầu hết các host đều làm vậy). Với content type khác, `init` quay về `arrayBuffer()`, cách này cũng chạy.
- Trong mã SSR (Vite SSR, các framework dựng trên Vite), import cùng profile entry đó: trên server,
  condition `node` chọn file Node tự khởi tạo, và `await init()` là một lời gọi vô hại không làm gì.

Các bundler khác, theo [Bắt đầu](../getting-started.md#bundler): webpack 5 mặc định xuất asset cho
`new URL(..., import.meta.url)` (chưa thử); Rollup cần một asset plugin, hoặc bạn tự truyền URL; esbuild
bundle phần JS nhưng không chép file `.wasm` (hãy chép nó cạnh bundle và truyền URL của nó).

## Render trong Web Worker

Việc render là đồng bộ: một thẻ lớn có thể mất hàng chục mili giây, đủ gây giật thấy rõ trên luồng chính.
Hãy chuyển engine vào một module worker và transfer các byte trở về:

```js
// render-worker.js
import { init, Renderer } from "bm-engine/standard";

const ready = (async () => {
  await init();
  const renderer = new Renderer();
  const font = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
  renderer.registerFont({ name: "Inter", data: font });
  return renderer;
})();

self.onmessage = async ({ data: { id, node, options } }) => {
  try {
    const renderer = await ready;
    const png = renderer.renderSync(node, options);
    self.postMessage({ id, png }, [png.buffer]); // transfer, no copy
  } catch (error) {
    self.postMessage({ id, error: String(error?.message ?? error) });
  }
};
```

```js
// main.js
const worker = new Worker(new URL("./render-worker.js", import.meta.url), { type: "module" });
let nextId = 0;
const pending = new Map();
worker.onmessage = ({ data: { id, png, error } }) => {
  const p = pending.get(id);
  pending.delete(id);
  error ? p.reject(new Error(error)) : p.resolve(png);
};
export const render = (node, options) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject });
  worker.postMessage({ id, node, options });
});
```

Bản đã kiểm chứng import `/node_modules/bm-engine/js/standard.mjs` theo đường dẫn (không bundler); với
Vite, import `bm-engine/standard` như trên. Cây node là object thuần nên đi qua `postMessage` nguyên vẹn;
byte ảnh trong `images` cũng transfer được. Mỗi worker có wasm instance riêng và font riêng.

## Hiển thị kết quả

```js
const dpr = Math.min(window.devicePixelRatio || 1, 3);
const png = await render(node, { width: Math.round(600 * dpr), height: Math.round(315 * dpr), devicePixelRatio: dpr });
const blob = new Blob([png], { type: "image/png" });

// as an image element
img.src = URL.createObjectURL(blob);   // URL.revokeObjectURL(img.src) when replaced
img.style.width = "600px";

// or onto a canvas
const bitmap = await createImageBitmap(blob);
canvas.getContext("2d").drawImage(bitmap, 0, 0, 600, 315);
```

Render `width × dpr` nhân `height × dpr` pixel **và** truyền `devicePixelRatio: dpr`: kích thước canvas
luôn là `width × height`, còn `devicePixelRatio` scale các độ dài CSS bên trong (đã kiểm chứng: dpr 2 cho
bitmap 1200 × 630 với layout 600 × 315). Với canvas, bạn cũng có thể bỏ qua bước mã hóa PNG:
`format: "raw"` trả về RGBA thẳng (straight), `new ImageData(new Uint8ClampedArray(raw.buffer), w, h)` rồi
`putImageData` (`raw` không nằm trong bài kiểm tra trình duyệt). `renderAsDataUrl()` trả về một URL
`data:` nếu bạn cần chuỗi.

## Không dùng bundler, hoặc từ CDN

Phục vụ thư mục `js/` của package và import một profile entry; `init()` sẽ fetch binary nằm cạnh nó:

```html
<script type="module">
  import { init, Renderer } from "/node_modules/bm-engine/js/standard.mjs";
  await init();
  const renderer = new Renderer();
</script>
```

Từ một CDN phục vụ package npm (jsDelivr, unpkg), cách tương tự chạy được với URL có phiên bản — hãy ghim
đúng phiên bản bạn đã thử:

```js
import { init, Renderer } from "https://cdn.jsdelivr.net/npm/bm-engine@<version>/js/standard.mjs";
await init(); // fetches .../js/bm_engine.standard.wasm from the same CDN
```

Cách dùng CDN chưa được thử cho tới khi package được phát hành. Hãy kiểm tra CDN có gửi `application/wasm`
và header CORS cho file `.wasm` không; nếu không, `init` vẫn chạy qua `arrayBuffer()` miễn là bản thân
request được phép.

## Kích thước trong trình duyệt

| Profile | wasm brotli | Khi nào |
|:--|--:|:--|
| `core` | 180.3 KiB | cây node, inline style, TTF, ảnh PNG / JPEG |
| `standard` | 374.5 KiB | + HTML, CSS, Tailwind, SVG, WOFF2, hiệu ứng, bảng |
| `full` | 453.4 KiB | + chữ phức tạp, emoji màu, animation, `renderSvg` |

Font thường là phần tải về lớn nhất; hãy subset chúng. Xem [Profile và kích thước](../profiles-and-size.md).
