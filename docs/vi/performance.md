# Hiệu năng

[English](../en/performance.md) · [Tiếng Việt](performance.md)

Mặc định bm-engine đã nhanh — một card điển hình render trong vài mili giây — nhưng vài thói quen quyết
định server của bạn dành thời gian để render, hay để parse lại font, giải mã lại cùng một tấm ảnh và nở
bộ nhớ mà không bao giờ trả lại được. Trang này gom chúng lại: dùng lại một renderer, đăng ký font một
lần, hiểu cold start, chọn profile nhỏ nhất, dùng đầu ra raw khi cần hậu xử lý, để cache ảnh làm việc,
giữ bộ nhớ ổn định và chia việc cho các worker thread. Số liệu lấy từ benchmark của dự án
([tóm tắt](./benchmark.md), [báo cáo đầy đủ](../BENCHMARK.md)); mã nguồn là
`docs/examples/performance.mjs` và chạy đúng như trình bày.

## Các con số

Đo trên Intel Core i3-10100, Windows 11, Node 26.13, profile `full`, so với `@takumi-rs/wasm` 2.20.0
(lượt chạy cuối của 0.1.0 trừ khi có ghi chú):

| Chỉ số | bm-engine | takumi-wasm |
|:--|--:|--:|
| Cold start: init + đăng ký một font + PNG og-card đầu tiên | **78.1 ms** | 193.8 ms |
| Compile + instantiate wasm (lượt chạy cold start, Node) | 8.0 ms | 33.9 ms |
| Compile + instantiate dạng streaming trong Edge 157 headless | 20.4 ms | — |
| Render `raw`, trung bình nhân trên 250 fixture | **0.64 ms** | 1.01 ms |
| Render `png` (render + mã hoá), trung bình nhân | **1.33 ms** | 2.95 ms |
| PNG og-card / blog-card / stress (3000 × 2000) | 14.51 / 30.48 / 83.20 ms | 22.26 / 49.99 / 143.20 ms |
| Bộ nhớ wasm sau 50 lần render PNG og-card | 11.6 MiB | 10.6 MiB |
| Peak RSS của tiến trình | 92.3 MiB | 105.0 MiB |
| Dung lượng tải wasm, brotli: core / standard / full | 194.3 / 397.7 / 469.6 KiB | 1 409.3 KiB |

Mọi số liệu ở trang này là của bản **wasm**. Thời gian tuyệt đối phụ thuộc máy; các tỉ lệ ổn định hơn. Trên
250 fixture, render PNG nhanh hơn takumi-wasm ở 248/250 ca (0.45× thời gian của nó) và render raw ở 229/250
ca (0.63×). Addon native còn nhanh hơn nữa: xem [Native và WebAssembly](./native-vs-wasm.md).

## Tạo renderer một lần

Một `Renderer` sở hữu các font đã đăng ký, một cache glyph và một cache ảnh đã giải mã. Tạo renderer rất
rẻ; **đăng ký font thì không** (byte được chép vào bộ nhớ wasm rồi parse), và chính các cache làm lần render
thứ hai nhanh hơn lần đầu. Hãy tạo renderer khi nạp module, đăng ký font một lần, rồi dùng lại cho mọi
request:

<!-- @example performance#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

// Create the renderer and register fonts ONCE, at module load, and reuse them for every request.
const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

export function renderCard(title, subtitle) {
  return renderer.renderSync(
    {
      type: "container",
      style: { display: "flex", flexDirection: "column", justifyContent: "flex-end", gap: 8, width: "100%", height: "100%",
               padding: 40, fontFamily: "Inter", backgroundImage: "linear-gradient(160deg, #0f172a, #1e3a8a)" },
      children: [
        { type: "text", text: title, style: { fontSize: 44, fontWeight: 700, color: "white", lineClamp: 2 } },
        { type: "text", text: subtitle, style: { fontSize: 22, color: "#93c5fd" } },
      ],
    },
    { width: 600, height: 315 },
  );
}
```

![Card render bằng renderer dùng chung](/img/guide/performance-card.png)

::: warning Đừng tạo renderer cho mỗi request
Mỗi renderer giữ bản sao font và cache riêng, và bộ nhớ wasm không bao giờ co lại. Một renderer cho mỗi
request nhân bội việc parse font và bộ nhớ; nếu thật sự cần renderer tạm, hãy giải phóng nó (xem
[Bộ nhớ](#bộ-nhớ)).
:::

## Cold start

Trên Node.js, các điểm vào `bm-engine` đọc và instantiate binary một cách đồng bộ **ngay khi import**, nên
`new Renderer()` đầu tiên có thể theo ngay sau. Cold start là tổng của việc instantiate module, đăng ký font
và lần render đầu (lần này còn lấp đầy cache glyph) — tổng cộng 78.1 ms với fixture og-card trong benchmark,
so với 193.8 ms của takumi-wasm.

- Trong hàm serverless, hãy import, `new Renderer()` và `registerFont` ở **phạm vi module**, không đặt
  trong handler, để các lần gọi khi đã "ấm" bỏ qua được chúng.
- Chỉ đăng ký những file font bạn dùng. Mỗi face tốn đúng dung lượng file của nó trong bộ nhớ wasm cộng
  thời gian parse; một variable font thay được nhiều độ đậm tĩnh.
- Edge runtime (Cloudflare Workers) nhận sẵn một `WebAssembly.Module` đã biên dịch; gọi `initSync(module)`
  ở phạm vi module và tạo renderer khi cần (xem [Bắt đầu](./getting-started.md#edge-runtime-deno-bun)).

## Các lần render khi đã "ấm"

Lần render đầu tiên với một font và cỡ chữ nhất định phải rasterize glyph; các lần sau lấy lại từ cache
glyph (8 MiB mỗi renderer). Để thấy khác biệt trên máy của bạn:

<!-- @example performance#timing -->
```js
const t0 = performance.now();
renderCard("First render", "pays for glyph rasterisation");
const t1 = performance.now();
for (let i = 0; i < 20; i++) renderCard("First render", "pays for glyph rasterisation");
const t2 = performance.now();
console.log(`first: ${(t1 - t0).toFixed(1)} ms, then: ${((t2 - t1) / 20).toFixed(1)} ms per render`);
```

Kết quả phụ thuộc máy nên không được trích ở đây; lần render đầu sẽ chậm nhất và các lần sau ổn định dần.

## Chọn profile nhỏ nhất

Ba binary khác nhau về dung lượng tải và về khả năng, chứ không khác về tốc độ ở những tính năng chung:

| Profile | wasm raw / brotli | Dùng cho |
|:--|--:|:--|
| `bm-engine/core` | 487.0 / 194.3 KiB | cây node với style inline, TTF tĩnh, ảnh PNG / JPEG |
| `bm-engine/standard` | 933.9 / 397.7 KiB | + stylesheet, Tailwind, HTML, SVG, WOFF2, font variable / CFF, hiệu ứng, bảng, float |
| `bm-engine/full` (và `bm-engine` trên Node) | 1 140.5 / 469.6 KiB | + bidi / chữ phức, emoji màu, animation, `renderSvg`, ICO, đầu vào WebP lossy |

Dung lượng quan trọng trong trình duyệt và trên edge runtime có giới hạn kích thước script; trên server
Node, khác biệt chỉ là vài trăm KiB đọc một lần khi khởi động. Hãy kiểm tra profile đã nạp ngay khi khởi
động thay vì phát hiện thiếu tính năng ở request đầu tiên:

<!-- @example performance#features -->
```js
import { features } from "bm-engine";

// Fail fast at startup if the loaded profile cannot render your templates.
for (const need of ["css", "tw", "html"]) {
  if (!features[need]) throw new Error(`bm-engine profile lacks "${need}": import bm-engine/standard or /full`);
}
```

Chi tiết ở [Profile và kích thước](./profiles-and-size.md).

## Đầu ra raw hay đã mã hoá

Mã hoá chiếm phần lớn một lần render: trong benchmark, trung bình nhân là 0.64 ms với `raw` và 1.33 ms với
PNG. Nếu đằng nào bạn cũng xử lý điểm ảnh (so sánh ảnh, ghép ảnh, đưa vào `<canvas>` hoặc bộ mã hoá video),
hãy lấy `raw` và bỏ qua bộ mã hoá:

<!-- @example performance#raw-vs-png -->
```js
const node = { type: "container", style: { width: "100%", height: "100%", backgroundImage: "radial-gradient(circle, #fde68a, #f97316)" } };
const rawPixels = renderer.renderSync(node, { width: 600, height: 315, format: "raw" }); // no encoding step
const pngFile = renderer.renderSync(node, { width: 600, height: 315 });                  // + PNG compression
console.log(rawPixels.length, pngFile.length); // 756000 (600 * 315 * 4) vs 21334 bytes for this gradient
```

Buffer raw rất lớn (`width × height × 4` byte), nên đừng gửi qua mạng hay giữ nhiều trong bộ nhớ. Về đánh
đổi giữa PNG, JPEG và WebP, xem [Định dạng đầu ra](./formats.md).

## Ảnh

- **Việc giải mã được cache.** Mỗi renderer cache ảnh đã giải mã (và đã đổi kích thước) theo nội dung, tối
  đa 96 MiB; vượt quá thì cache bị xoá. Cùng một logo hay ảnh nền trong mọi card chỉ giải mã một lần.
- **Byte được chép mỗi lần render.** Byte đã mã hoá của mọi mục `images` mà nguồn tham chiếu được chép vào
  bộ nhớ wasm ở mỗi lời gọi (mục không được nhắc tới thì bỏ qua), nên file nguồn khổng lồ tốn một lần chép
  mỗi lần dù việc giải mã đã được cache.
- **Đưa ảnh về đúng cỡ.** Một ảnh đã giải mã tối đa 24 megapixel (lớn hơn sẽ không được vẽ), và giải mã
  một ảnh máy ảnh 12 megapixel chỉ để hiển thị ở 600 × 315 là phí thời gian và tới 48 MB cache. Hãy thu nhỏ
  ảnh lớn một lần trước khi đưa vào renderer.

<!-- @example performance#images -->
```js
// Decoded images are cached per renderer by content, so the same logo / photo is decoded once.
// The bytes themselves are copied into wasm memory on every render that references them.
const photo = renderer.renderSync(
  { type: "container", style: { width: "100%", height: "100%", backgroundImage: "conic-gradient(from 45deg, #22d3ee, #a855f7, #f43f5e, #22d3ee)" } },
  { width: 1600, height: 1000 },
); // stands in for a large photo
const withPhoto = (title) => ({
  type: "container",
  style: { display: "flex", alignItems: "flex-end", width: "100%", height: "100%", padding: 32,
           backgroundImage: "url(hero)", backgroundSize: "cover" },
  children: [{ type: "text", text: title, style: { fontFamily: "Inter", fontWeight: 700, fontSize: 40, color: "white" } }],
});
const images = [{ src: "hero", data: photo }];

let start = performance.now();
renderer.renderSync(withPhoto("first"), { width: 600, height: 315, images });   // decodes and resizes the PNG
const firstMs = performance.now() - start;
start = performance.now();
const second = renderer.renderSync(withPhoto("second"), { width: 600, height: 315, images }); // cache hit
console.log(`first ${firstMs.toFixed(1)} ms, second ${(performance.now() - start).toFixed(1)} ms`);
```

![Card có ảnh nền đã được cache](/img/guide/performance-images.png)

Lần render thứ hai không giải mã lại PNG 1600 × 1000; trên máy thử nó nhanh hơn lần đầu nhiều lần (số liệu
trên máy bạn sẽ khác).

### Giải quyết đầu vào async một lần với `prepare`

Khi byte ảnh hay font đến bất đồng bộ, `prepare()` giải quyết chúng một lần và trả về một handle mà bao nhiêu
lần render cũng dùng lại được, mỗi lần với tuỳ chọn riêng:

<!-- @example performance#prepare -->
```js
// Resolve async inputs (lazy images, font loaders) once, render many variants from the handle.
const prepared = await renderer.prepare(withPhoto("Prepared"), {
  width: 600, height: 315,
  images: [{ src: "hero", data: async () => photo }], // e.g. () => fetch(url).then((r) => r.arrayBuffer())
});
const asPng = renderer.renderSync(prepared);
const asJpeg = renderer.renderSync(prepared, { format: "jpeg", quality: 80 });
console.log(asPng.length, asJpeg.length);
```

Khác takumi, `prepare` không bao giờ tải gì về; hãy tự fetch byte (xem [Ảnh](./images.md)).

## Bộ nhớ

Mọi renderer của cùng một điểm vào dùng chung một vùng nhớ tuyến tính WebAssembly, và **bộ nhớ
WebAssembly chỉ tăng chứ không bao giờ co lại**. bm-engine dùng lại bộ nhớ giữa các lần render (arena cho
mỗi lần render, cache có ngân sách cố định), nên một tải ổn định sẽ chững lại: 11.6 MiB bộ nhớ wasm sau 50
lần render og-card trong benchmark (takumi: 10.6 MiB). Thứ làm nó tăng là thứ lớn nhất bạn từng render:

<!-- @example performance#memory -->
```js
console.log(renderer.memoryBytes());     // wasm linear memory of this entry, in bytes
renderer.renderSync(node, { width: 3000, height: 2000, format: "raw" });
console.log(renderer.memoryBytes());     // grew for the big canvas ...
renderCard("Back to normal", "small canvas");
console.log(renderer.memoryBytes());     // ... and stays that size: wasm memory never shrinks
```

Trong benchmark giai đoạn 1, instance kết thúc toàn bộ lượt chạy (có một canvas 3000 × 2000) ở 65.8 MiB
(takumi: 66.4 MiB). Quy tắc kinh nghiệm:

- Một canvas tốn `width × height × 4` byte, cộng các layer cho hiệu ứng như nhóm opacity, filter và mask.
  Canvas 3000 × 2000 đã là 24 MB trước khi có layer nào.
- Tách các lần render khổng lồ thỉnh thoảng mới có ra khỏi instance phục vụ lưu lượng thường ngày — chạy
  chúng trong một worker riêng, có thể terminate để lấy lại bộ nhớ.
- Ngân sách cố định cho mỗi renderer: ảnh đã giải mã tối đa 96 MiB, mặt nạ glyph tối đa 8 MiB. Các tuỳ chọn
  constructor `cacheMaxBytes` / `fontCacheMaxBytes` được nhận để tương thích takumi nhưng bị bỏ qua.
- `renderer.memoryBytes()` (hoặc `Renderer.memoryBytes()`) báo kích thước hiện tại; hãy ghi log nó nếu nghi
  bộ nhớ tăng.

Giải phóng một renderer trả font và cache của nó về bộ cấp phát của wasm, nơi công việc sau sẽ dùng lại —
còn kích thước vùng nhớ tuyến tính thì giữ nguyên:

<!-- @example performance#free -->
```js
{
  using temp = new Renderer();           // explicit resource management: temp.free() at the end of the block
  temp.registerFont(readFileSync("assets/fonts/Roboto-Regular.ttf"));
  temp.renderSync({ type: "text", text: "one-off", style: { fontFamily: "Roboto" } }, { width: 100, height: 30 });
}
const other = new Renderer();
other.free();                            // same thing by hand; methods throw "renderer has been freed" afterwards
```

## Canvas lớn và DPI cao

Chi phí tăng theo số điểm ảnh đầu ra: rasterize, ghép lớp và mã hoá đều chạm vào từng điểm ảnh. Một lần
render 2× (`devicePixelRatio: 2` với canvas gấp đôi) có số điểm ảnh gấp bốn lần render 1×. Giới hạn:
16 384 px mỗi cạnh và 40 megapixel mỗi canvas (`canvas too large`).

- Render đúng kích thước sẽ hiển thị; chỉ để trình duyệt thu nhỏ khi bạn cần ảnh 2× sắc nét.
- Blur lớn (`filter: blur()`, `box-shadow` có bán kính blur lớn, `backdrop-filter`) và nhiều lớp opacity /
  blend chồng nhau là các hiệu ứng tốn kém; màu phẳng, viền và chữ thì rẻ.
- Với thumbnail, render trực tiếp ở kích thước nhỏ thay vì render lớn rồi thu nhỏ.

## Song song: worker pool

::: tip Backend native trên Node.js
Với backend native (được `import "bm-engine"` dùng trên Node.js khi đã cài addon cho nền tảng), các phương
thức async (`render()`, `measure()`, ...) chạy trên thread pool của libuv và không chặn event loop. Khi đó
xử lý song song đến từ nhiều instance `Renderer` (mỗi cái chạy một lần gọi một lúc) và kích thước của pool
đó, `UV_THREADPOOL_SIZE`, thay vì từ worker thread. Xem
[Native và WebAssembly → Mô hình thread](./native-vs-wasm.md#mô-hình-thread) để biết chi tiết và thông lượng
đo được. Phần còn lại của mục này áp dụng cho backend wasm.
:::

Engine chạy đơn luồng và `render` là đồng bộ: một lần render chặn luồng gọi nó. Các phương thức async
(`render()`, `measure()`, ...) chỉ tồn tại để tương thích API và để giải quyết tuỳ chọn async — chúng không
đẩy việc sang luồng khác. Để dùng nhiều nhân CPU, hãy chạy một instance bm-engine cho mỗi worker thread. Mỗi
worker import bm-engine (có instance wasm và bộ nhớ riêng) và đăng ký font riêng:

<!-- @example _performance-worker#worker -->
```js
// render-worker.mjs: one wasm instance + one renderer per worker, fonts registered once.
import { parentPort } from "node:worker_threads";
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

parentPort.on("message", ({ id, node, options }) => {
  try {
    const bytes = renderer.renderSync(node, options);
    parentPort.postMessage({ id, bytes }, [bytes.buffer]); // transfer, do not copy
  } catch (err) {
    parentPort.postMessage({ id, error: err.message });
  }
});
```

Luồng chính phân phát việc và nhận lại byte đã mã hoá (được chuyển giao, không chép):

<!-- @example performance#pool -->
```js
import { Worker } from "node:worker_threads";
import { availableParallelism } from "node:os";

class RenderPool {
  #idle = [];
  #queue = [];
  #jobs = new Map();
  #nextId = 0;
  constructor(size) {
    for (let i = 0; i < size; i++) {
      const worker = new Worker(new URL("./_performance-worker.mjs", import.meta.url));
      worker.on("message", ({ id, bytes, error }) => {
        const job = this.#jobs.get(id);
        this.#jobs.delete(id);
        error ? job.reject(new Error(error)) : job.resolve(bytes);
        this.#idle.push(worker);
        this.#pump();
      });
      this.#idle.push(worker);
    }
  }
  render(node, options) {
    return new Promise((resolve, reject) => {
      const id = this.#nextId++;
      this.#jobs.set(id, { resolve, reject });
      this.#queue.push({ id, node, options });
      this.#pump();
    });
  }
  #pump() {
    while (this.#idle.length && this.#queue.length) this.#idle.pop().postMessage(this.#queue.shift());
  }
  close() {
    return Promise.all(this.#idle.map((w) => w.terminate()));
  }
}

const pool = new RenderPool(Math.min(4, availableParallelism()));
const cards = await Promise.all(
  ["one", "two", "three", "four", "five", "six", "seven", "eight"].map((n) =>
    pool.render(
      { type: "container",
        style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#0f766e" },
        children: [{ type: "text", text: `Card ${n}`, style: { fontFamily: "Inter", fontSize: 32, color: "white" } }] },
      { width: 300, height: 120 },
    ),
  ),
);
console.log(cards.length, "PNGs rendered on", Math.min(4, availableParallelism()), "threads");
await pool.close();
```

![Một trong tám card do pool render](/img/guide/performance-pool-card.png)

- Đặt kích thước pool theo số nhân (`availableParallelism()`), không theo số request; mỗi worker tốn bộ nhớ
  wasm và font riêng.
- Renderer, handle `Prepared` và font đã đăng ký không chia sẻ được giữa các worker; gửi vào cây node (dữ
  liệu thuần) và nhận ra byte.
- Trong trình duyệt, mô hình tương tự dùng được với Web Worker: render ngoài luồng chính để trang vẫn mượt.
  Phần này chưa được chạy ở đây; bản Node phía trên thì đã chạy.

## Mẹo cho trình duyệt

- **Phục vụ `.wasm` với `application/wasm`** để `init()` dùng được biên dịch streaming
  (`WebAssembly.instantiateStreaming`); với content type khác nó quay về tải hết file trước, vẫn chạy được.
  Trong lượt chạy Edge headless của benchmark, compile + instantiate dạng streaming mất 20.4 ms.
- **Cache binary.** Tên file không đổi giữa các bản phát hành cùng phiên bản, nên hãy phục vụ chúng với cache
  dài hạn gắn với phiên bản package (hoặc để bundler gắn dấu vân tay vào tên file).
- **Nạp profile nhỏ nhất** đủ cho template của bạn — dung lượng tải từ 180 KiB (core) tới 453 KiB (full)
  với brotli.
- **Khởi tạo sớm** (`await init()` khi ứng dụng khởi động, không đợi cú nhấp đầu tiên) và giữ một renderer
  suốt vòng đời trang.
- **Render trong Web Worker** nếu việc render diễn ra khi người dùng đang thao tác trên trang.

Xem [Bắt đầu](./getting-started.md#trình-duyệt-không-dùng-bundler) để biết cách nạp binary trong trình duyệt
và bundler.

## Danh sách kiểm tra

- [ ] Một `Renderer` sống lâu cho mỗi bộ font; font đăng ký một lần, lúc khởi động.
- [ ] Profile nhỏ nhất đủ cho đầu vào; kiểm tra `features` khi khởi động.
- [ ] Dùng `raw` khi hậu xử lý điểm ảnh; chọn JPEG / WebP / PNG theo nội dung.
- [ ] Ảnh được thu nhỏ trước khi render; dùng lại cùng byte để cache giải mã phát huy.
- [ ] Không tạo renderer theo request; canvas khổng lồ được cách ly trong worker riêng.
- [ ] Worker pool theo số nhân CPU khi cần thông lượng.
