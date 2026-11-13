# Addon native so với WebAssembly

[English](../en/native-vs-wasm.md) · [Tiếng Việt](native-vs-wasm.md)

Trên Node.js, bm-engine chạy dưới dạng addon Node-API native hoặc dưới dạng WebAssembly. Cả hai được biên dịch
từ cùng một mã nguồn Zig, có cùng API và cho ra cùng từng byte. Trang này giải thích bạn nhận được backend nào,
khi nào nên chọn backend kia, backend native dùng thread ra sao, và cả hai so với bản native và bản wasm của
takumi thế nào trên bộ benchmark 250 fixture. Cài đặt: [Bắt đầu](./getting-started.md). Cách build và phát hành
các gói theo nền tảng: [Phát hành](./publishing.md).

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

## Kết quả tóm tắt

<!-- native-bench:highlights -->
- **bm-native so với bm-wasm (sync):** raw bằng 0.61× thời gian của wasm [0.62× / 0.61× / 0.61×] (nhanh hơn ở 250/250 fixture), PNG 0.67× [0.68× / 0.68× / 0.67×] (nhanh hơn ở 250/250).
- **bm-native so với takumi-native, cùng async:** raw 0.55× [0.55× / 0.55× / 0.55×] (bm nhanh hơn ở 244/250, từng fixture 0.12×–1.20×), PNG 0.54× [0.55× / 0.55× / 0.54×] (bm nhanh hơn ở 227/250, từng fixture 0.23×–2.54×). Với API sync của bm: raw 0.53×, PNG 0.57×. Dưới 1× = bm-native tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ đó ở từng lượt.
- **Thời gian CPU mỗi ảnh (cùng async):** PNG 1.98 ms bm-native so với 3.20 ms takumi-native (1.73 so với 1.98 lõi bận trong một lần render); raw 1.30 so với 1.41 ms. takumi-native chạy một phần của một lần render (các đoạn deflate PNG, blur, WebP, khung animation) trên thread pool rayon riêng; bm render một ảnh trên một thread (bm-native sync: 0.87 lõi với PNG).
- **Hai bản build của chính takumi:** takumi-native tốn 0.72× thời gian của takumi-wasm với raw và 0.55× với PNG.
- **Trùng byte:** bm-native và bm-wasm cho cùng byte ở 2626/2626 phép so trên 250 fixture (802 MB; 0 khác biệt).
- **Nhiễu:** geomean tuyệt đối raw / PNG lệch tới 4.70 % giữa các lượt (tải của tiến trình khác thay đổi trong lúc chạy), còn tỉ lệ giữa các engine, đo xen kẽ trong từng lượt, lệch nhiều nhất 1.50 %. Hãy đọc tỉ lệ; coi số ms tuyệt đối là ±2.35 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Chỉ số | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — API sync | 0.45 ±2.15 % | 0.74 ±2.15 % | không có API sync | — |
| raw RGBA, geomean ms — API async | 0.47 ±2.25 % | — | 0.86 ±2.10 % | 1.19 ±2.35 % |
| PNG, geomean ms — API sync | 0.95 ±1.95 % | 1.41 ±1.55 % | không có API sync | — |
| PNG, geomean ms — API async | 0.90 ±2.30 % | — | 1.66 ±1.55 % | 3.03 ±1.65 % |
| Thời gian CPU mỗi lần render PNG, ms trung bình (số lõi dùng) | 1.00 (0.87 lõi) | 1.30 (0.76 lõi) | 3.20 (1.98 lõi) | 2.84 (0.81 lõi) |
| Dung lượng PNG, geomean so với takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start so với Node rỗng, median / p95 ms | 21.8 / 45.5 | 75.5 / 93.0 | 46.2 / 69.2 | 185 / 249 |
| RSS sau 1 → 10 lượt cả bộ fixture, MiB | 90.7 → 91.4 | 127 → 150 | 118 → 124 | 138 → 172 |
| RSS đỉnh, một PNG 4000×4000, MiB | 140 | 146 | 133 | 148 |
| Event loop: độ trễ lớn nhất của timer 1 ms, render nặng 2400×2400, ms | 211 (sync) · 1.20 (async) | 401 (sync) · 392 (async) | 13.4 (async) | 746 (async) |
| Event loop: như trên, animation 60 khung, ms | 438 (sync) · 1.10 (async) | 848 (sync) · 873 (async) | 11.5 (async) | 1 848 (async) |
| Thông lượng, og card PNG, 4 đồng thời, ảnh/s (cấu hình tốt nhất) | 372 (many K=8, UV 4) | 263 (pool K=4) | 298 (many K=2, UV 8) | 173 (pool K=8) |
| Thông lượng, 8 đồng thời, ảnh/s (cấu hình tốt nhất) | 408 (many K=8, UV 8) | 291 (pool K=8) | 336 (one, UV 8) | 202 (pool K=8) |

Geomean trên 250 fixture mà cả bốn engine đều render được; ± = nửa khoảng chênh giữa geomean của 3 lượt so với median của chúng; ⚠ = chênh quá 10 %. Cold start: median / p95 của 30 tiến trình mới trừ median của Node rỗng. Event loop, bộ nhớ và thông lượng là một lần đo; ở các dòng thông lượng ⚠ = tiến trình khác dùng trung bình hơn một lõi trong lúc đo.
<!-- /native-bench:summary -->

Cách đọc bảng:

- **sync / async.** bm-engine có cả `renderSync` (chạy trên thread gọi) và `render` (bản native: chạy trên thread
  pool của libuv). takumi-native chỉ có `render` async, nên phép so công bằng với nó là dòng *async*; dòng sync cho
  thấy bm-native tốn bao nhiêu khi không phải chuyển sang thread khác. Trên wasm, `render` làm đúng việc của
  `renderSync` trên main thread, nên bm-wasm được đo qua `renderSync` còn takumi-wasm qua `render` công khai của nó.
- **Thời gian thực so với thời gian CPU.** takumi-native chạy một phần của *một* lần render (các đoạn deflate của PNG,
  blur, WebP, các khung animation) trên thread pool rayon riêng, nên một lần render của nó có thể làm bận nhiều lõi.
  bm-native render một ảnh trên một thread. Dòng CPU cho thấy khác biệt này: khi máy đang phục vụ nhiều yêu cầu,
  CPU cho mỗi ảnh quan trọng hơn độ trễ của một lần render.
- Thời gian **PNG** phụ thuộc vào mức nén của bộ mã hoá mà không engine nào cho chỉnh; hãy so kèm dung lượng file
  ([bảng định dạng](#định-dạng-và-bộ-mã-hoá)).

## Mô hình thread

Với backend native, cái gì chạy ở đâu:

- `renderSync`, `measureSync`, `renderSvgSync`, `renderAnimationSync`, `registerFont`: trên thread gọi. Chúng chặn
  event loop trong suốt lời gọi, giống hệt bản wasm.
- `render`, `renderAsDataUrl`, `renderSvg`, `measure`, `renderAnimation`: đầu vào được sao chép, rồi engine chạy trên
  **một thread của thread pool libuv** và promise được hoàn tất trên thread JavaScript. Event loop vẫn tiếp tục phục
  vụ yêu cầu khác trong lúc render ([bảng event loop](#event-loop)).
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
  một instance engine ([công thức](./image/recipes.md#pool-worker-threads)). Benchmark cũng đo bm-wasm và takumi-wasm theo cách này.

### Thông lượng khi chạy đồng thời

<!-- native-bench:throughput -->
| Engine | Cách chạy | UV_THREADPOOL_SIZE | N=1 | N=2 | N=4 | N=8 | N=16 |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 1 client, tuần tự | 4 | 109 |  |  |  |  |
| bm-wasm | 1 client, tuần tự | — | 72.3 |  |  |  |  |
| takumi-native | 1 client, tuần tự | 4 | 123 |  |  |  |  |
| takumi-wasm | 1 client, tuần tự | — | 45.6 |  |  |  |  |
| bm-native | 1 renderer, async | 4 | 104 (0.96×, 96 %) | 106 (0.98×, 98 %) | 104 (0.96×, 96 %) | 105 (0.96×, 96 %) | 105 (0.97×, 97 %) |
| bm-native | 2 renderer, async | 4 | 104 (0.95×, 95 %) | 194 (1.79×, 89 %) | 197 (1.82×, 91 %) | 205 (1.89×, 94 %) | 200 (1.84×, 92 %) |
| bm-native | 4 renderer, async | 4 | 101 (0.93×, 93 %) | 197 (1.81×, 91 %) | 371 (3.42×, 85 %) | 367 (3.39×, 85 %) | 359 (3.31×, 83 %) |
| bm-native | 8 renderer, async | 4 | 99.6 (0.92×, 92 %) | 198 (1.82×, 91 %) | 372 (3.43×, 86 %) | 369 (3.40×, 85 %) | 366 (3.38×, 84 %) |
| bm-native | 1 renderer, async | 8 | 103 (0.95×, 95 %) | 106 (0.97×, 97 %) | 105 (0.96×, 96 %) | 104 (0.95×, 95 %) | 106 (0.97×, 97 %) |
| bm-native | 2 renderer, async | 8 | 104 (0.95×, 95 %) | 195 (1.79×, 90 %) | 197 (1.82×, 91 %) | 199 (1.84×, 92 %) | 202 (1.86×, 93 %) |
| bm-native | 4 renderer, async | 8 | 103 (0.95×, 95 %) | 197 (1.81×, 91 %) | 360 (3.32×, 83 %) | 371 (3.42×, 85 %) | 356 (3.28×, 82 %) |
| bm-native | 8 renderer, async | 8 | 104 (0.96×, 96 %) | 198 (1.82×, 91 %) | 365 (3.36×, 84 %) | 408 (3.76×, 47 %) | 406 (3.74×, 47 %) |
| takumi-native | 1 renderer, async | 4 | 130 (1.06×, 106 %) | 210 (1.71×, 85 %) | 296 (2.40×, 60 %) | 296 (2.40×, 60 %) | 298 (2.42×, 60 %) |
| takumi-native | 1 renderer, async | 8 | 129 (1.04×, 104 %) | 209 (1.69×, 85 %) | 273 (2.21×, 55 %) | 336 (2.72×, 34 %) | 338 (2.74×, 34 %) |
| takumi-native | 2 renderer, async | 4 | 132 (1.07×, 107 %) | 212 (1.72×, 86 %) | 298 (2.41×, 121 %) | 293 (2.38×, 119 %) | 300 (2.43×, 122 %) |
| takumi-native | 4 renderer, async | 4 | 132 (1.07×, 107 %) | 212 (1.72×, 86 %) | 295 (2.39×, 60 %) | 298 (2.42×, 60 %) | 264 (2.14×, 54 %) |
| takumi-native | 2 renderer, async | 8 | 131 (1.06×, 106 %) | 211 (1.71×, 85 %) | 298 (2.42×, 121 %) | 327 (2.65×, 133 %) | 305 (2.47×, 124 %) |
| takumi-native | 4 renderer, async | 8 | 130 (1.06×, 106 %) | 210 (1.70×, 85 %) | 294 (2.38×, 60 %) | 333 (2.70×, 68 %) | 324 (2.63×, 66 %) |
| bm-wasm | worker pool, 1 worker | — | 70.5 (0.98×, 98 %) | 67.8 (0.94×, 94 %) | 69.9 (0.97×, 97 %) | 71.1 (0.98×, 98 %) | 71.0 (0.98×, 98 %) |
| bm-wasm | worker pool, 2 worker | — | 69.0 (0.95×, 95 %) | 137 (1.89×, 95 %) | 137 (1.90×, 95 %) | 139 (1.92×, 96 %) | 137 (1.89×, 95 %) |
| bm-wasm | worker pool, 4 worker | — | 70.7 (0.98×, 98 %) | 138 (1.91×, 95 %) | 263 (3.64×, 91 %) | 249 (3.45×, 86 %) | 263 (3.63×, 91 %) |
| bm-wasm | worker pool, 8 worker | — | 70.7 (0.98×, 98 %) | 138 (1.91×, 95 %) | 236 (3.27×, 82 %) | 291 (4.03×, 50 %) | 309 (4.27×, 53 %) |
| takumi-wasm | worker pool, 1 worker | — | 46.0 (1.01×, 101 %) | 46.4 (1.02×, 102 %) | 47.0 (1.03×, 103 %) | 47.4 (1.04×, 104 %) | 47.1 (1.03×, 103 %) |
| takumi-wasm | worker pool, 2 worker | — | 44.5 (0.98×, 98 %) | 90.3 (1.98×, 99 %) | 88.9 (1.95×, 97 %) | 92.4 (2.03×, 101 %) | 91.8 (2.01×, 101 %) |
| takumi-wasm | worker pool, 4 worker | — | 46.1 (1.01×, 101 %) | 91.3 (2.00×, 100 %) | 170 (3.72×, 93 %) | 174 (3.82×, 96 %) | 179 (3.92×, 98 %) |
| takumi-wasm | worker pool, 8 worker | — | 46.4 (1.02×, 102 %) | 90.1 (1.98×, 99 %) | 173 (3.80×, 95 %) | 202 (4.43×, 55 %) | 213 (4.67×, 58 %) |

Ảnh mỗi giây; trong ngoặc là mức tăng so với tốc độ tuần tự một client của cùng engine (các dòng đầu) và hiệu suất mở rộng = mức tăng / min(N, số thread có thể render các ảnh khác nhau cùng lúc, 8 CPU logic); một renderer bm tính là 1, K renderer là min(K, UV_THREADPOOL_SIZE), renderer của takumi-native là UV_THREADPOOL_SIZE, pool worker là K. og card 1200×630 PNG, vòng kín: N client, mỗi client luôn có một yêu cầu đang chạy; 2000 ms mỗi điểm sau khi khởi động. CPU bận trong lúc đo: trung bình 42.8 % (tiến trình khác ≈ 0.90 lõi).
<!-- /native-bench:throughput -->

## Đầu ra trùng từng byte

Hai backend cho ra **cùng từng byte**: trên mọi fixture của bộ benchmark, đầu ra raw RGBA, PNG, JPEG, WebP, SVG và
`measure`, animation (WebP / APNG / GIF), ICO, nguồn HTML, ảnh đính kèm, font WOFF2 và thông báo lỗi đều được so từng
byte (`node bench/native-identity.mjs`), và kết quả async của native được so với kết quả sync của native. Một server có
thể đổi backend (hoặc bị quay về wasm) mà ảnh và cache không thay đổi gì. Cam kết này mới được kiểm chứng trên
Windows x64; xem bảng nền tảng.

<!-- native-bench:equiv -->
| Engine so với takumi-wasm (250 fixture, raw RGBA) | identical | equivalent | close | different | error/unsupported |
|:--|--:|--:|--:|--:|--:|
| bm-native | 81 | 169 | 0 | 0 | 0 |
| bm-wasm | 81 | 169 | 0 | 0 | 0 |
| takumi-native | 250 | 0 | 0 | 0 | 0 |

| Cùng engine, hai bản build | raw RGBA trùng byte | file PNG trùng byte |
|:--|--:|--:|
| bm-native = bm-wasm | 250/250 | 250/250 |
| takumi-native = takumi-wasm | 250/250 | 250/250 |

`bench/native-identity.mjs`: 250 fixture, 2626 phép so (raw, PNG, JPEG, WebP, measure, SVG, animation, ICO, HTML, ảnh, WOFF2, thông báo lỗi, native async so với sync), 2626 trùng (121 trong số đó là cùng thông báo lỗi ở cả hai), 0 khác, 802 MB đã so.
<!-- /native-bench:equiv -->

So với takumi, phép so vẫn là phép so dùng từ giai đoạn 1 (takumi-wasm là chuẩn; "identical" = mọi byte bằng nhau,
"equivalent" = SSIM ≥ 0.99 và tối đa 0.5 % điểm ảnh khác). Bản native không thay đổi gì ở đây: hai backend của bm
nhận cùng kết luận.

## Hỗ trợ nền tảng

| Gói theo nền tảng | Target | Trạng thái |
|:--|:--|:--|
| `bm-engine-win32-x64-msvc` | Windows x64 | **Đã chạy**: bộ kiểm tra trùng byte, bộ test native và benchmark này chạy trên nó |
| `bm-engine-win32-arm64-msvc` | Windows on Arm | cross-compile và kiểm tra cấu trúc; **chưa từng chạy** |
| `bm-engine-linux-x64-gnu` | Linux x64, glibc ≥ 2.17 | cross-compile và kiểm tra cấu trúc; **chưa từng chạy** |
| `bm-engine-linux-x64-musl` | Linux x64, musl (Alpine) | cross-compile và kiểm tra cấu trúc; **chưa từng chạy** |
| `bm-engine-linux-arm64-gnu` | Linux arm64, glibc ≥ 2.17 | cross-compile và kiểm tra cấu trúc; **chưa từng chạy** |
| `bm-engine-linux-arm64-musl` | Linux arm64, musl | cross-compile và kiểm tra cấu trúc; **chưa từng chạy** |
| `bm-engine-darwin-x64` | macOS Intel, 10.15+ | cross-compile và kiểm tra cấu trúc; **chưa từng chạy** |
| `bm-engine-darwin-arm64` | macOS Apple silicon, 11+ | cross-compile và kiểm tra cấu trúc; **chưa từng chạy** |

"Kiểm tra cấu trúc" nghĩa là script build kiểm tra từng file mà không chạy nó: định dạng file và CPU, hàm đăng ký được
export, đúng tập import Node-API mong đợi, không phụ thuộc thư viện nào ngoài thư viện C (hoặc `kernel32.dll`), không
import hàm toán học, và (arm64) số lệnh fused multiply-add. Chừng nào bộ kiểm tra trùng byte và bộ test chưa chạy trên
một nền tảng thì hãy coi addon của nền tảng đó là chưa được kiểm thử; trên mọi nền tảng bản wasm vẫn luôn có
(`bm-engine/full`) và là thứ `bm-engine` quay về.

### Kích thước

<!-- native-bench:sizes -->
| File | Target | KiB | gzip -9 KiB | brotli KiB | Trạng thái |
|:--|--:|--:|--:|--:|--:|
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 3 327 | 1 765 | 1 389 | đã chạy (benchmark này) |
| `bm-engine.win32-arm64-msvc.node` | `aarch64-windows-gnu` | 2 627 | 1 577 | 1 179 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-x64-gnu.node` | `x86_64-linux-gnu.2.17` | 3 185 | 1 720 | 1 361 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-x64-musl.node` | `x86_64-linux-musl` | 3 185 | 1 720 | 1 362 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-arm64-gnu.node` | `aarch64-linux-gnu.2.17` | 2 634 | 1 579 | 1 180 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-arm64-musl.node` | `aarch64-linux-musl` | 2 633 | 1 579 | 1 180 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.darwin-x64.node` | `x86_64-macos.10.15` | 3 175 | 1 719 | 1 360 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.darwin-arm64.node` | `aarch64-macos.11.0` | 2 652 | 1 536 | 1 128 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| bm wasm `core` | wasm32 | 490 | 229 | 195 |  |
| bm wasm `standard` | wasm32 | 937 | 465 | 399 |  |
| bm wasm `full` | wasm32 | 1 144 | 560 | 471 |  |
| bm wasm `add-on WOFF` | wasm32 | 84.4 | 67.8 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Addon native lấy từ `native/dist/manifest.json` (build ngày 2026-11-13 với Zig 0.17.1, ReleaseFast). Mỗi người dùng chỉ tải một addon (gói optional cho nền tảng của họ) cộng với bản wasm dự phòng nằm trong gói chính.
<!-- /native-bench:sizes -->

## Event loop

<!-- native-bench:eventloop -->
| Việc | Engine | API | ms của việc | CPU ms | trễ timer lớn nhất ms | trễ p99 ms | số lần timer chạy |
|:--|--:|--:|--:|--:|--:|--:|--:|
| heavy | bm-native | sync | 211 | 219 | 211 | 211 | 1 |
| heavy | bm-native | async | 247 | 500 | 1.20 | 1.10 | 248 |
| heavy | bm-wasm | sync | 401 | 579 | 401 | 401 | 1 |
| heavy | bm-wasm | async (chạy trên main thread) | 391 | 563 | 392 | 392 | 1 |
| heavy | takumi-native | async | 242 | 671 | 13.4 | 2.00 | 231 |
| heavy | takumi-wasm | async (chạy trên main thread) | 745 | 814 | 746 | 746 | 1 |
| anim | bm-native | sync | 437 | 437 | 438 | 438 | 1 |
| anim | bm-native | async | 448 | 875 | 1.10 | 1.00 | 450 |
| anim | bm-wasm | sync | 848 | 1 015 | 848 | 848 | 1 |
| anim | bm-wasm | async (chạy trên main thread) | 872 | 1 031 | 873 | 873 | 1 |
| anim | takumi-native | async | 367 | 2 141 | 11.5 | 8.90 | 312 |
| anim | takumi-wasm | async (chạy trên main thread) | 1 848 | 2 218 | 1 848 | 1 848 | 1 |

heavy = một PNG 2400×2400: gradient, 24 thẻ với box-shadow mờ lớn, cứ ba thẻ có một thẻ `filter: blur(6px)`, chữ; anim = renderAnimation: 60 khung (2 s ở 30 fps) WebP lossless 800×420, 12 hình tròn có bóng, mờ, xoay (cảnh tĩnh). Một `setInterval` 1 ms ghi khoảng cách giữa các lần chạy trong lúc lời gọi chạy. Một chuỗi setImmediate giữ cho vòng lặp không ngủ, vì vòng lặp Node rảnh trên Windows thức theo đồng hồ hệ thống 15,6 ms và timer sẽ không bao giờ cho thấy dưới ~16 ms. Lời gọi chặn vòng lặp cho thấy một lần chạy có độ trễ bằng cả lời gọi. CPU ms là của cả tiến trình trong lúc gọi, kể cả chuỗi setImmediate trên main thread (khoảng một lõi mỗi khi vòng lặp rảnh).
<!-- /native-bench:eventloop -->

## Cold start

<!-- native-bench:cold -->
| Engine | thực median | wall p95 | hơn Node, median | hơn Node, p95 | import | registerFont | PNG đầu tiên |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Node rỗng (mốc) | 49.1 | 68.5 | 0 | 0 | — | — | — |
| bm-native | 71.0 | 94.7 | 21.8 | 45.5 | 4.70 | 0.34 | 17.9 |
| bm-wasm | 125 | 142 | 75.5 | 93.0 | 7.10 | 2.43 | 65.4 |
| takumi-native | 95.4 | 118 | 46.2 | 69.2 | 23.1 | 0.92 | 20.2 |
| takumi-wasm | 234 | 298 | 185 | 249 | 33.7 | 3.29 | 146 |

ms. 30 lần mỗi engine, xen kẽ các engine; spawn node → import engine như người dùng → registerFont(Inter Regular) → PNG og card 1200×630 → thoát; thời gian thực = đồng hồ của tiến trình cha từ spawn tới khi thoát. Các cột import / registerFont / PNG đầu tiên là median đo bên trong tiến trình con. CPU bận trong lúc đo: trung bình 33.3 % (tiến trình khác ≈ 1.20 lõi). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 1.20 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:cold -->

## Bộ nhớ

<!-- native-bench:memory -->
| Engine | RSS sau khởi tạo | RSS sau lượt 1 → 10 | bộ nhớ engine 1 → N | JS heap 1 → N | RSS đỉnh, cả bộ | RSS đỉnh PNG 4000×4000 (tăng thêm) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 63.2 | 90.7 → 91.4 | 31.6 → 31.6 | 6.40 → 6.50 | 183 | 140 (85.6) |
| bm-wasm | 75.4 | 127 → 150 | 63.8 → 86.8 | 6.60 → 6.70 | 247 | 146 (88.9) |
| takumi-native | 67.0 | 118 → 124 | — → — | 6.60 → 6.70 | 199 | 133 (74.5) |
| takumi-wasm | 83.5 | 138 → 172 | 71.5 → 71.5 | 7.40 → 7.50 | 237 | 148 (83.3) |

MiB, sau khi ép GC. Một tiến trình cho mỗi engine; mỗi lượt render mọi fixture ra raw và PNG (API async), một renderer cho mỗi bộ font. Bộ nhớ engine: bm-native = số byte addon đang cấp phát (`memoryBytes()`), bm-wasm / takumi-wasm = bộ nhớ tuyến tính wasm, takumi-native = không công bố. Node rỗng: 41.5 MiB RSS. "Tăng thêm" = RSS đỉnh trừ RSS ngay trước lần render 4000×4000.
<!-- /native-bench:memory -->

## Thời gian render

<!-- native-bench:speed -->
| Định dạng (số fixture) | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| raw (250) | 0.45 ±2.15 % | 0.47 ±2.25 % | 0.74 ±2.15 % | 0.86 ±2.10 % | 1.19 ±2.35 % |
| png (250) | 0.95 ±1.95 % | 0.90 ±2.30 % | 1.41 ±1.55 % | 1.66 ±1.55 % | 3.03 ±1.65 % |
| jpeg (3) | 11.1 ±2.90 % | 11.3 ±2.40 % | 18.3 ±1.95 % | 17.5 ±2.45 % | 24.2 ±2.50 % |
| webp (3) | 8.71 ±3.15 % | 8.87 ±2.65 % | 12.4 ±2.55 % | 66.6 ±2.20 % | 15.8 ±2.35 % |
| raw, bỏ known-gaps | 0.47 | 0.48 | 0.76 | 0.87 | 1.21 |
| png, bỏ known-gaps | 0.97 | 0.92 | 1.44 | 1.69 | 3.07 |
| raw, từng lượt | 0.46 / 0.47 / 0.45 | 0.47 / 0.48 / 0.46 | 0.74 / 0.76 / 0.73 | 0.86 / 0.89 / 0.85 | 1.19 / 1.23 / 1.17 |
| png, từng lượt | 0.96 / 0.98 / 0.94 | 0.91 / 0.94 / 0.90 | 1.42 / 1.45 / 1.41 | 1.67 / 1.70 / 1.65 | 3.04 / 3.11 / 3.01 |

Trung bình nhân của thời gian render median từng fixture, ms. jpeg (quality 85) và webp (lossless; takumi-wasm dùng bộ mã hoá WebP khác takumi-native, xem bảng định dạng) chỉ đo trên ba fixture.
<!-- /native-bench:speed -->

<!-- native-bench:cpu -->
| Biến thể | raw: thực / CPU ms / lõi | PNG: thực / CPU ms / lõi |
|:--|--:|--:|
| bm-native sync | 0.41 / 0.38 / 0.91 | 1.16 / 1.00 / 0.87 |
| bm-native async | 0.46 / 1.30 / 2.81 | 1.15 / 1.98 / 1.73 |
| bm-wasm sync | 0.66 / 0.51 / 0.77 | 1.71 / 1.30 / 0.76 |
| takumi-native async | 0.78 / 1.41 / 1.80 | 1.61 / 3.20 / 1.98 |
| takumi-wasm | 1.06 / 0.78 / 0.73 | 3.50 / 2.84 / 0.81 |

Trung bình trên mọi lần render được đo (không phải geomean): thời gian thực mỗi lần render, thời gian CPU của tiến trình (mọi thread) trong lúc đó, và tỉ số. Tỉ số trên 1 nghĩa là một lần render dùng hơn một lõi.
<!-- /native-bench:cpu -->

Các fixture mà bm-native vượt xa nhất và thua xa nhất takumi-native (cùng async):

<!-- native-bench:best-worst -->
**raw — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-jpeg-fit` | 1.37 | 1.45 | 11.9 | 1.30 | 0.12× |
| `pfx-bg-blend` | 0.69 | 0.71 | 3.70 | 0.92 | 0.19× |
| `pfx-bg-clip-text` | 0.42 | 0.41 | 1.81 | 1.07 | 0.23× |
| `gap-background-clip-text` | 0.27 | 0.30 | 1.30 | 1.28 | 0.23× |
| `fix-text-emoji-spacing` | 0.13 | 0.14 | 0.52 | 1.72 | 0.26× |
| `fix-text-emoji-wrap` | 0.12 | 0.13 | 0.48 | 1.66 | 0.26× |
| `fix-text-emoji-zwj` | 0.13 | 0.13 | 0.48 | 2.46 | 0.27× |
| `fix-text-emoji-flags-skin` | 0.12 | 0.12 | 0.41 | 2.05 | 0.29× |
| `fix-text-emoji-keycap-vs` | 0.12 | 0.12 | 0.39 | 2.31 | 0.31× |
| `radial-shapes` | 1.97 | 1.99 | 6.30 | 1.26 | 0.32× |

**raw — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `fix-text-paint-order` | 0.77 | 0.80 | 0.67 | 2.24 | 1.20× |
| `abs-zorder` | 1.38 | 1.42 | 1.20 | 1.76 | 1.19× |
| `pfx-text-stroke` | 0.83 | 0.83 | 0.75 | 1.31 | 1.12× |
| `pfx-svg-background` | 0.66 | 0.65 | 0.61 | 2.75 | 1.08× |
| `radius-uniform-percorner` | 1.07 | 1.10 | 1.07 | 1.46 | 1.03× |
| `radius-pill-circle` | 1.09 | 1.07 | 1.06 | 3.75 | 1.01× |
| `flex-wrap-gap` | 1.34 | 1.37 | 1.42 | 1.78 | 0.97× |
| `flex-row-column` | 1.09 | 1.07 | 1.12 | 1.55 | 0.96× |
| `tw-structural` | 0.64 | 0.66 | 0.69 | 2.94 | 0.95× |
| `radius-elliptical` | 1.07 | 1.10 | 1.15 | 1.60 | 0.95× |

**png — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `colors-solid-bg` | 0.20 | 0.19 | 0.82 | 1.30 | 0.23× |
| `gap-oklch-color` | 0.18 | 0.17 | 0.72 | 0.83 | 0.24× |
| `anim-kf-option-t500` | 0.19 | 0.17 | 0.64 | 1.12 | 0.27× |
| `pfx-visibility` | 0.26 | 0.23 | 0.84 | 0.72 | 0.28× |
| `anim-alternate-t100` | 0.18 | 0.17 | 0.59 | 1.23 | 0.29× |
| `anim-opacity-t900` | 0.17 | 0.16 | 0.55 | 1.31 | 0.29× |
| `anim-opacity-t500` | 0.17 | 0.16 | 0.55 | 1.76 | 0.29× |
| `anim-alternate-t1100` | 0.18 | 0.17 | 0.58 | 1.53 | 0.29× |
| `anim-opacity-t250` | 0.17 | 0.16 | 0.54 | 1.79 | 0.30× |
| `anim-alternate-t700` | 0.17 | 0.17 | 0.56 | 1.91 | 0.30× |

**png — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-photo-bg` | 28.5 | 28.7 | 11.3 | 4.33 | 2.54× |
| `card-blog` | 18.9 | 19.1 | 11.8 | 2.51 | 1.62× |
| `radial-spotlight-small` | 4.14 | 4.14 | 2.62 | 2.80 | 1.58× |
| `img-radius-clip` | 14.6 | 14.7 | 9.53 | 2.69 | 1.54× |
| `stress-3000x2000-card` | 52.6 | 53.6 | 39.6 | 2.88 | 1.35× |
| `fx-text-shadow` | 2.67 | 2.67 | 2.03 | 3.35 | 1.32× |
| `img-intrinsic-size` | 1.76 | 1.83 | 1.40 | 2.38 | 1.31× |
| `img-png-fit` | 11.2 | 11.3 | 8.65 | 1.75 | 1.31× |
| `card-og` | 9.61 | 9.70 | 7.50 | 2.49 | 1.29× |
| `pfx-mix-blend` | 2.70 | 2.72 | 2.15 | 4.14 | 1.27× |
<!-- /native-bench:best-worst -->

### bm-native thua ở đâu, và vì sao

Những gì phép đo cho thấy (bảng chẩn đoán bên dưới là một phần của mỗi lần chạy; điều gì không được nó chứng minh
thì được ghi là giả thuyết):

- **`filter: blur()` chậm hơn nhiều ở bm-engine, trên cả hai backend.** Trong cảnh animation, bỏ filter blur thì
  thời gian một khung của bm xuống dưới takumi, và riêng blur chiếm gần hết thời gian của bm; blur của takumi rẻ.
  Chính hiệu ứng này làm animation 60 khung trong bảng event loop của bm lâu hơn nhiều (takumi-native còn render
  các khung song song). *Giả thuyết, chưa profile:* bước filter của bm xử lý một vùng lớn hơn nhiều so với phần
  tử bị làm mờ. Đây là vấn đề của engine, không phải của native so với wasm.
- **Khung raw lớn, ít nội dung.** Các fixture raw thua takumi-native nhiều nhất là khung 1200×630 với các hộp
  đơn giản. Khung rỗng cho thấy cùng khoảng cách: chi phí cố định theo điểm ảnh để tạo đầu ra raw của bm (xoá,
  đổi alpha, chép ra) cao hơn takumi-native, và với API **async** của bm nó còn tăng theo kích thước khung, trong
  khi đầu ra PNG (kết quả nhỏ) không bị thiệt gì khi async. *Giả thuyết:* đường async chép hoặc cấp phát mới thêm
  một lần kết quả nhiều megabyte. Dù sao điều này chỉ ảnh hưởng `raw`.
- **PNG của ảnh lớn kiểu ảnh chụp.** takumi-native nén deflate một PNG thành nhiều đoạn trên nhiều lõi (cột "lõi
  takumi" trong bảng PNG kém nhất lớn hơn 1 khá nhiều ở phần lớn các fixture đó); bm mã hoá trên một thread. Tính chung bm
  vẫn tốn ít CPU hơn cho mỗi PNG (dòng CPU trong bảng tóm tắt), và file trung bình nhỏ hơn.
- **WebP** thì ngược lại: WebP lossless của takumi-native (libwebp, theo mã nguồn takumi) chậm hơn bm vài lần,
  file nhỏ hơn với ảnh phẳng và lớn hơn với ảnh chụp (bảng định dạng).

<!-- native-bench:diagnose -->
| Khung trắng rỗng | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| 300×200 raw | 0.10 | 0.11 | 0.18 | 0.22 | 0.29 |
| 300×200 png | 0.15 | 0.12 | 0.18 | 0.45 | 0.53 |
| 1200×630 raw | 0.70 | 0.70 | 0.97 | 0.78 | 1.09 |
| 1200×630 png | 1.11 | 0.69 | 1.24 | 2.94 | 4.88 |
| 2400×1260 raw | 2.50 | 2.66 | 4.50 | 2.77 | 4.91 |
| 2400×1260 png | 4.60 | 4.32 | 5.78 | 10.3 | 19.3 |

| Cảnh animation, một khung raw 800×420 | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| shadow + blur (as animated) | 6.85 | 6.87 | 12.9 | 16.9 | 30.1 |
| shadow only | 2.18 | 2.13 | 4.10 | 4.86 | 7.78 |
| blur only | 2.15 | 2.14 | 3.80 | 3.53 | 6.12 |
| neither | 0.93 | 0.96 | 1.50 | 1.30 | 2.04 |

Median ms, các biến thể chạy xen kẽ (40 lần cho khung rỗng, ít hơn cho cảnh). Khung rỗng không vẽ gì, nên thời gian của nó là chi phí theo điểm ảnh mà khung nào cũng trả (xoá canvas, đổi alpha, chép kết quả ra) cộng, với PNG, việc mã hoá một ảnh phẳng. Cảnh là cảnh của animation trong phép đo event loop: 12 hình tròn 60×60 xoay, có `box-shadow: 0 8px 30px` và `filter: blur(2px)`.
<!-- /native-bench:diagnose -->

### Định dạng và bộ mã hoá

<!-- native-bench:formats -->
| Fixture | Định dạng | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|--:|
| `lingrad-angles` | raw | 2.13 ms · 2 953 KiB | 2.22 ms · 2 953 KiB | 3.81 ms · 2 953 KiB | 4.47 ms · 2 953 KiB | 6.53 ms · 2 953 KiB |
| `lingrad-angles` | png | 6.49 ms · 32.6 KiB | 6.40 ms · 32.6 KiB | 9.84 ms · 32.6 KiB | 7.78 ms · 102 KiB | 34.6 ms · 102 KiB |
| `lingrad-angles` | jpeg | 11.0 ms · 52.2 KiB | 11.3 ms · 52.2 KiB | 18.7 ms · 52.2 KiB | 17.8 ms · 52.3 KiB | 24.0 ms · 52.3 KiB |
| `lingrad-angles` | webp | 7.02 ms · 28.9 KiB | 7.27 ms · 28.9 KiB | 10.4 ms · 28.9 KiB | 109 ms · 22.8 KiB | 15.3 ms · 169 KiB |
| `img-photo-bg` | raw | 1.17 ms · 2 953 KiB | 1.24 ms · 2 953 KiB | 1.66 ms · 2 953 KiB | 3.76 ms · 2 953 KiB | 5.89 ms · 2 953 KiB |
| `img-photo-bg` | png | 28.5 ms · 511 KiB | 28.7 ms · 511 KiB | 39.9 ms · 511 KiB | 11.3 ms · 513 KiB | 53.4 ms · 513 KiB |
| `img-photo-bg` | jpeg | 10.6 ms · 55.1 KiB | 10.8 ms · 55.1 KiB | 17.2 ms · 55.1 KiB | 17.6 ms · 55.2 KiB | 24.2 ms · 55.2 KiB |
| `img-photo-bg` | webp | 13.6 ms · 367 KiB | 13.8 ms · 367 KiB | 19.2 ms · 367 KiB | 160 ms · 414 KiB | 20.7 ms · 470 KiB |
| `card-flat-ui` | raw | 2.68 ms · 2 953 KiB | 2.68 ms · 2 953 KiB | 4.45 ms · 2 953 KiB | 3.65 ms · 2 953 KiB | 6.72 ms · 2 953 KiB |
| `card-flat-ui` | png | 5.39 ms · 23.1 KiB | 5.31 ms · 23.1 KiB | 8.40 ms · 23.1 KiB | 6.48 ms · 25.3 KiB | 19.2 ms · 25.3 KiB |
| `card-flat-ui` | jpeg | 11.6 ms · 48.9 KiB | 11.8 ms · 48.9 KiB | 19.1 ms · 48.9 KiB | 17.1 ms · 49.0 KiB | 24.5 ms · 49.0 KiB |
| `card-flat-ui` | webp | 6.91 ms · 18.5 KiB | 6.96 ms · 18.5 KiB | 9.66 ms · 18.5 KiB | 16.8 ms · 13.4 KiB | 12.6 ms · 27.6 KiB |

Thời gian median và dung lượng đầu ra. JPEG: quality 85 cho mọi engine. WebP: lossless cho mọi engine (không có `quality`); takumi-native mã hoá bằng libwebp, takumi-wasm bằng crate `image-webp` (nên file lớn hơn). PNG: không engine nào cho chỉnh mức nén; mỗi engine dùng mức mặc định của nó (bm: deflate riêng; takumi: `png` + `zlib-rs`, chọn giữa level 7 / không lọc và level 3 / lọc thích ứng trên một mẫu, nén thành tối đa 8 đoạn song song ở bản native), nên thời gian PNG được so kèm dung lượng file.
<!-- /native-bench:formats -->

Theo nhóm, theo từng fixture, phương pháp đo và ghi nhận nhiễu: [báo cáo đầy đủ](../BENCHMARK.md) và
`docs/results-native.json`.

## Điều kiện đo và cách chạy lại

<!-- native-bench:env -->
| Mục | Giá trị |
|:--|:--|
| Máy | Intel(R) Core(TM) i3-10100 CPU @ 3.60GHz, 8 CPU logic, 7.80 GiB, win32 10.0.26200 x64 |
| Node.js | v26.13.0 (V8 14.6.202.34-node.40, N-API 10, libuv 1.52.1) |
| bm-engine | 0.1.0, git `e5c535cbbf` (main, 3 file đang sửa) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 3 327 KiB, Zig 0.17.1, ReleaseFast, sha256 `1d5ff5ea0a4f` |
| bm-wasm | `js/bm_engine.wasm` (profile full), 1 144 KiB, sha256 `a7e1528586ac` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Lần chạy | 2026-11-13 04:23 UTC, chế độ full, 250 fixtures, 16.0 min; CPU bận trước khi chạy: 5.00 % |
<!-- /native-bench:env -->

```sh
node bench/run-native.mjs           # toàn bộ: JSON, Markdown và các bảng trên trang này
node bench/run-native.mjs --quick   # chạy thử ngắn
node bench/native-identity.mjs      # chỉ so native == wasm từng byte
```

Lần chạy ghi `bench/out/native/results-native.json` và `NATIVE.md`, chép JSON sang `docs/results-native.json` và viết
lại các bảng của trang này (và của các trang benchmark) giữa các comment đánh dấu `native-bench`, nên không có con số
nào trên trang này được gõ tay. Máy được dùng chung với các job build và test khác trong lúc đo; ghi nhận nhiễu nằm
trong báo cáo đầy đủ.
