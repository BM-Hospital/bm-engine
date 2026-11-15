# Native và WebAssembly

Chọn backend theo môi trường chạy. Trên Node.js, package ưu tiên addon native và tự chuyển sang WebAssembly khi addon không dùng được. Xem [Benchmark](benchmark.md) để đọc số đo tốc độ và bộ nhớ.

## Nên dùng backend nào

| Mã của bạn chạy ở đâu | Backend | Cách dùng |
|:--|:--|:--|
| Node.js, Bun, Deno (server, CLI, script build) | **native**, tự động quay về wasm | `import { Renderer, backend } from "bm-engine"`; `backend` là `"native"` hoặc `"wasm"` |
| Trình duyệt, Web Worker | wasm (lựa chọn duy nhất) | `bm-engine` trỏ tới bản wasm ở đó |
| Cloudflare Workers, Vercel / Netlify Edge, Deno Deploy và các runtime edge khác | wasm (lựa chọn duy nhất) | cùng câu import |
| Node.js nhưng vẫn muốn wasm (ví dụ để tái tạo đúng từng bit ảnh render trong trình duyệt, hoặc trên nền tảng mà addon chưa được kiểm thử) | wasm | `import ... from "bm-engine/full"` hoặc `BM_ENGINE_BACKEND=wasm` |
| Node.js, Bun, Deno và bạn muốn đầu ra PDF | **native**, tự động quay về profile wasm `pdf` | `import { PdfRenderer, backend } from "bm-engine/pdf"`; xem [Đầu ra PDF](./pdf/native-and-wasm.md#backend-native-trên-nodejs) |
| Node.js và muốn báo lỗi thay vì lặng lẽ quay về wasm | native | `import ... from "bm-engine/native"` hoặc `BM_ENGINE_BACKEND=native` |

Việc quay về wasm diễn ra im lặng: nếu không có addon cho nền tảng, nếu CPU cũ hơn x86-64-v2 (SSE4.2), hoặc nếu
addon không qua bước kiểm tra dấu phẩy động lúc nạp, `bm-engine` nạp bản wasm và mọi thứ vẫn chạy, chỉ chậm hơn
và các lời gọi async chạy trên main thread. Hãy ghi log `backend` một lần lúc khởi động nếu bạn cần biết.

`bm-engine/pdf` theo cùng quy tắc: trên Node.js nó dùng addon khi đã cài, nếu không thì dùng profile wasm `pdf`, tạo
ra byte PDF giống hệt trên cả hai, và khi chạy native thì các phương thức async chạy trên thread pool của libuv.
Bản thân `bm-engine` không cung cấp PDF trên backend nào, dù binary addon có chứa bộ ghi PDF.


## Mô hình thread

Với backend native, cái gì chạy ở đâu:

- `renderSync`, `measureSync`, `renderSvgSync`, `renderAnimationSync`, `registerFont`: trên thread gọi. Chúng chặn
  event loop trong suốt lời gọi, giống hệt bản wasm.
- `render`, `renderAsDataUrl`, `renderSvg`, `measure`, `renderAnimation`: đầu vào được sao chép, rồi engine chạy trên
  **một thread của thread pool libuv** và promise được hoàn tất trên thread JavaScript. Event loop vẫn tiếp tục phục
  vụ yêu cầu khác trong lúc render.
- **Một renderer chỉ xử lý một lời gọi tại một thời điểm.** Các lời gọi trên cùng một `Renderer` được xếp hàng theo
  thứ tự (vào trước ra trước). Muốn render song song, hãy tạo nhiều renderer (mỗi cái đăng ký font của nó) và chia
  việc cho chúng:

```js
import { Renderer } from "bm-engine";

const fonts = [/* { name, data, weight, style } ... */];
const renderers = Array.from({ length: 4 }, () => {
  const r = new Renderer();
  for (const f of fonts) r.registerFont(f);
  return r;
});
let next = 0;
export function renderPng(node, options) {
  const r = renderers[next++ % renderers.length]; // xoay vòng
  return r.render(node, options); // chạy trên pool của libuv, không chặn event loop
}
```

- **Mức song song bị giới hạn bởi pool của libuv**, `UV_THREADPOOL_SIZE`, **mặc định là 4**. Pool này cũng phục vụ
  `fs`, `dns.lookup`, `crypto` và `zlib`. Muốn render trên nhiều thread hơn, đặt biến môi trường trước khi Node khởi
  động, ví dụ `UV_THREADPOOL_SIZE=8 node server.js` (gán `process.env.UV_THREADPOOL_SIZE` bên trong chương trình chỉ
  có tác dụng nếu chưa có gì dùng tới pool). Nhiều renderer hơn số thread của pool thì không giúp gì thêm.
- Các renderer khác nhau không dùng chung trạng thái nào (mỗi cái có font, cache và bộ nhớ riêng), nên chúng không
  bao giờ phải chờ nhau. Addon cũng nạp được trong `worker_threads`, nhưng với backend native thì một nhóm renderer
  trong một thread đã làm được việc đó mà không cần worker.
- Với backend **wasm**, các hàm async chạy trên main thread; muốn song song cần một pool `worker_threads`, mỗi worker
  một instance engine ([công thức](./image/recipes.md#pool-worker-threads)).
