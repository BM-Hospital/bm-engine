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
| Node.js, Bun, Deno và bạn muốn đầu ra PDF | **native**, tự động quay về profile wasm `pdf` | `import { PdfRenderer, backend } from "bm-engine/pdf"`; xem [Đầu ra PDF](./pdf.md#backend-native-trên-nodejs) |
| Node.js và muốn báo lỗi thay vì lặng lẽ quay về wasm | native | `import ... from "bm-engine/native"` hoặc `BM_ENGINE_BACKEND=native` |

Việc quay về wasm diễn ra im lặng: nếu không có addon cho nền tảng, nếu CPU cũ hơn x86-64-v2 (SSE4.2), hoặc nếu
addon không qua bước kiểm tra dấu phẩy động lúc nạp, `bm-engine` nạp bản wasm và mọi thứ vẫn chạy, chỉ chậm hơn
và các lời gọi async chạy trên main thread. Hãy ghi log `backend` một lần lúc khởi động nếu bạn cần biết.

`bm-engine/pdf` theo cùng quy tắc: trên Node.js nó dùng addon khi đã cài, nếu không thì dùng profile wasm `pdf`, tạo
ra byte PDF giống hệt trên cả hai, và khi chạy native thì các phương thức async chạy trên thread pool của libuv.
Bản thân `bm-engine` không cung cấp PDF trên backend nào, dù binary addon có chứa bộ ghi PDF.

## Kết quả tóm tắt

<!-- native-bench:highlights -->
- **bm-native so với bm-wasm (sync):** raw bằng 0.60× thời gian của wasm [0.60× / 0.59× / 0.60×] (nhanh hơn ở 250/250 fixture), PNG 0.68× [0.68× / 0.68× / 0.68×] (nhanh hơn ở 250/250).
- **bm-native so với takumi-native, cùng async:** raw 0.55× [0.55× / 0.55× / 0.55×] (bm nhanh hơn ở 244/250, từng fixture 0.13×–1.21×), PNG 0.56× [0.56× / 0.58× / 0.56×] (bm nhanh hơn ở 227/250, từng fixture 0.23×–2.28×). Với API sync của bm: raw 0.50×, PNG 0.56×. Dưới 1× = bm-native tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ đó ở từng lượt.
- **Thời gian CPU mỗi ảnh (cùng async):** PNG 2.32 ms bm-native so với 3.81 ms takumi-native (1.47 so với 1.78 lõi bận trong một lần render); raw 1.42 so với 1.71 ms. takumi-native chạy một phần của một lần render (các đoạn deflate PNG, blur, WebP, khung animation) trên thread pool rayon riêng; bm render một ảnh trên một thread (bm-native sync: 0.91 lõi với PNG).
- **Hai bản build của chính takumi:** takumi-native tốn 0.75× thời gian của takumi-wasm với raw và 0.56× với PNG.
- **Trùng byte:** bm-native và bm-wasm cho cùng byte ở 1810/1810 phép so trên 250 fixture (637 MB; 0 khác biệt).
- **Nhiễu:** geomean tuyệt đối raw / PNG lệch tới 33.4 % giữa các lượt (tải của tiến trình khác thay đổi trong lúc chạy), còn tỉ lệ giữa các engine, đo xen kẽ trong từng lượt, lệch nhiều nhất 3.70 %. Hãy đọc tỉ lệ; coi số ms tuyệt đối là ±16.7 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Chỉ số | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — API sync | 0.51 ±15.5 % ⚠ | 0.85 ±16.1 % ⚠ | không có API sync | — |
| raw RGBA, geomean ms — API async | 0.56 ±15.7 % ⚠ | — | 1.02 ±15.3 % ⚠ | 1.36 ±15.8 % ⚠ |
| PNG, geomean ms — API sync | 1.05 ±14.6 % ⚠ | 1.56 ±15.0 % ⚠ | không có API sync | — |
| PNG, geomean ms — API async | 1.06 ±16.7 % ⚠ | — | 1.89 ±14.5 % ⚠ | 3.36 ±15.8 % ⚠ |
| Thời gian CPU mỗi lần render PNG, ms trung bình (số lõi dùng) | 1.42 (0.91 lõi) | 1.78 (0.77 lõi) | 3.81 (1.78 lõi) | 4.08 (0.86 lõi) |
| Dung lượng PNG, geomean so với takumi | 0.80× | 0.80× | 1.00× | 1.00× |
| Cold start so với Node rỗng, median / p95 ms | 31.3 / 69.2 | 99.9 / 138 | 50.9 / 97.5 | 238 / 304 |
| RSS sau 1 → 10 lượt cả bộ fixture, MiB | 94.7 → 96.0 | 132 → 156 | 102 → 139 | 140 → 176 |
| RSS đỉnh, một PNG 4000×4000, MiB | 143 | 149 | 135 | 151 |
| Event loop: độ trễ lớn nhất của timer 1 ms, render nặng 2400×2400, ms | 227 (sync) · 1.50 (async) | 455 (sync) · 473 (async) | 7.30 (async) | 819 (async) |
| Event loop: như trên, animation 60 khung, ms | 476 (sync) · 1.20 (async) | 969 (sync) · 954 (async) | 21.6 (async) | 2 072 (async) |
| Thông lượng, og card PNG, 4 đồng thời, ảnh/s (cấu hình tốt nhất) | 312 (many K=4, UV 4) ⚠ | 233 (pool K=4) ⚠ | 270 (one, UV 8) ⚠ | 137 (pool K=8) ⚠ |
| Thông lượng, 8 đồng thời, ảnh/s (cấu hình tốt nhất) | 402 (many K=8, UV 8) ⚠ | 270 (pool K=8) ⚠ | 316 (one, UV 8) ⚠ | 180 (pool K=8) ⚠ |

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
  một instance engine ([công thức](./recipes.md#pool-worker-threads)). Benchmark cũng đo bm-wasm và takumi-wasm theo cách này.

### Thông lượng khi chạy đồng thời

<!-- native-bench:throughput -->
| Engine | Cách chạy | UV_THREADPOOL_SIZE | N=1 | N=2 | N=4 | N=8 | N=16 |
|:--|--:|--:|--:|--:|--:|--:|--:|
| bm-native | 1 client, tuần tự | 4 | 92.1 |  |  |  |  |
| bm-wasm | 1 client, tuần tự | — | 62.2 |  |  |  |  |
| takumi-native | 1 client, tuần tự | 4 | 115 |  |  |  |  |
| takumi-wasm | 1 client, tuần tự | — | 38.5 |  |  |  |  |
| bm-native | 1 renderer, async | 4 | 89.1 (0.97×, 97 %) | 97.9 (1.06×, 106 %) | 98.9 (1.07×, 107 %) | 98.9 (1.07×, 107 %) | 98.8 (1.07×, 107 %) |
| bm-native | 2 renderer, async | 4 | 96.6 (1.05×, 105 %) | 188 (2.04×, 102 %) | 191 (2.08×, 104 %) | 185 (2.01×, 101 %) | 182 (1.98×, 99 %) |
| bm-native | 4 renderer, async | 4 | 97.5 (1.06×, 106 %) | 189 (2.05×, 102 %) | 312 (3.39×, 85 %) | 312 (3.38×, 85 %) | 314 (3.41×, 85 %) |
| bm-native | 8 renderer, async | 4 | 96.9 (1.05×, 105 %) | 183 (1.99×, 99 %) | 309 (3.36×, 84 %) | 309 (3.35×, 84 %) | 305 (3.31×, 83 %) |
| bm-native | 1 renderer, async | 8 | 97.3 (1.06×, 106 %) | 101 (1.09×, 109 %) | 98.0 (1.06×, 106 %) | 100 (1.09×, 109 %) | 98.9 (1.07×, 107 %) |
| bm-native | 2 renderer, async | 8 | 97.9 (1.06×, 106 %) | 189 (2.05×, 102 %) | 187 (2.03×, 102 %) | 184 (1.99×, 100 %) | 190 (2.06×, 103 %) |
| bm-native | 4 renderer, async | 8 | 97.2 (1.06×, 106 %) | 184 (1.99×, 100 %) | 299 (3.25×, 81 %) | 274 (2.97×, 74 %) | 301 (3.26×, 82 %) |
| bm-native | 8 renderer, async | 8 | 96.9 (1.05×, 105 %) | 184 (2.00×, 100 %) | 312 (3.39×, 85 %) | 402 (4.36×, 55 %) | 416 (4.51×, 56 %) |
| takumi-native | 1 renderer, async | 4 | 124 (1.08×, 108 %) | 198 (1.71×, 86 %) | 264 (2.29×, 57 %) | 272 (2.36×, 59 %) | 267 (2.32×, 58 %) |
| takumi-native | 1 renderer, async | 8 | 123 (1.07×, 107 %) | 198 (1.72×, 86 %) | 270 (2.34×, 59 %) | 316 (2.74×, 34 %) | 303 (2.63×, 33 %) |
| takumi-native | 2 renderer, async | 4 | 124 (1.07×, 107 %) | 197 (1.71×, 85 %) | 264 (2.29×, 114 %) | 265 (2.30×, 115 %) | 267 (2.32×, 116 %) |
| takumi-native | 4 renderer, async | 4 | 123 (1.07×, 107 %) | 197 (1.71×, 85 %) | 231 (2.01×, 50 %) | 236 (2.04×, 51 %) | 220 (1.91×, 48 %) |
| takumi-native | 2 renderer, async | 8 | 108 (0.93×, 93 %) | 177 (1.53×, 77 %) | 238 (2.06×, 103 %) | 298 (2.59×, 129 %) | 311 (2.70×, 135 %) |
| takumi-native | 4 renderer, async | 8 | 124 (1.08×, 108 %) | 190 (1.64×, 82 %) | 259 (2.25×, 56 %) | 314 (2.73×, 68 %) | 287 (2.49×, 62 %) |
| bm-wasm | worker pool, 1 worker | — | 62.2 (1.00×, 100 %) | 68.1 (1.09×, 109 %) | 68.3 (1.10×, 110 %) | 68.1 (1.09×, 109 %) | 68.6 (1.10×, 110 %) |
| bm-wasm | worker pool, 2 worker | — | 67.9 (1.09×, 109 %) | 130 (2.09×, 105 %) | 129 (2.08×, 104 %) | 130 (2.10×, 105 %) | 131 (2.10×, 105 %) |
| bm-wasm | worker pool, 4 worker | — | 67.9 (1.09×, 109 %) | 123 (1.97×, 99 %) | 233 (3.74×, 94 %) | 217 (3.49×, 87 %) | 228 (3.67×, 92 %) |
| bm-wasm | worker pool, 8 worker | — | 64.5 (1.04×, 104 %) | 113 (1.81×, 91 %) | 193 (3.10×, 78 %) | 270 (4.34×, 54 %) | 260 (4.18×, 52 %) |
| takumi-wasm | worker pool, 1 worker | — | 39.4 (1.02×, 102 %) | 41.1 (1.07×, 107 %) | 41.1 (1.07×, 107 %) | 41.0 (1.06×, 106 %) | 42.2 (1.10×, 110 %) |
| takumi-wasm | worker pool, 2 worker | — | 40.6 (1.05×, 105 %) | 81.5 (2.12×, 106 %) | 80.8 (2.10×, 105 %) | 81.9 (2.13×, 106 %) | 81.3 (2.11×, 106 %) |
| takumi-wasm | worker pool, 4 worker | — | 42.4 (1.10×, 110 %) | 82.3 (2.14×, 107 %) | 134 (3.48×, 87 %) | 134 (3.49×, 87 %) | 132 (3.43×, 86 %) |
| takumi-wasm | worker pool, 8 worker | — | 41.9 (1.09×, 109 %) | 83.0 (2.16×, 108 %) | 137 (3.55×, 89 %) | 180 (4.68×, 58 %) | 188 (4.88×, 61 %) |

Ảnh mỗi giây; trong ngoặc là mức tăng so với tốc độ tuần tự một client của cùng engine (các dòng đầu) và hiệu suất mở rộng = mức tăng / min(N, số thread có thể render các ảnh khác nhau cùng lúc, 8 CPU logic); một renderer bm tính là 1, K renderer là min(K, UV_THREADPOOL_SIZE), renderer của takumi-native là UV_THREADPOOL_SIZE, pool worker là K. og card 1200×630 PNG, vòng kín: N client, mỗi client luôn có một yêu cầu đang chạy; 2000 ms mỗi điểm sau khi khởi động. CPU bận trong lúc đo: trung bình 56.8 % (tiến trình khác ≈ 2.14 lõi). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 2.14 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
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

`bench/native-identity.mjs`: 250 fixture, 1810 phép so (raw, PNG, JPEG, WebP, measure, SVG, animation, ICO, HTML, ảnh, WOFF2, thông báo lỗi, native async so với sync), 1810 trùng (8 trong số đó là cùng thông báo lỗi ở cả hai), 0 khác, 637 MB đã so.
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
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 2 083 | 1 120 | 914 | đã chạy (benchmark này) |
| bm wasm `core` | wasm32 | 487 | 228 | 194 |  |
| bm wasm `standard` | wasm32 | 934 | 463 | 398 |  |
| bm wasm `full` | wasm32 | 1 140 | 558 | 470 |  |
| bm wasm `add-on WOFF` | wasm32 | 84.2 | 67.7 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Addon native lấy từ `native/dist/manifest.json` (build ngày 2026-11-12 với Zig 0.17.1, ReleaseFast). Mỗi người dùng chỉ tải một addon (gói optional cho nền tảng của họ) cộng với bản wasm dự phòng nằm trong gói chính.
<!-- /native-bench:sizes -->

## Event loop

<!-- native-bench:eventloop -->
| Việc | Engine | API | ms của việc | CPU ms | trễ timer lớn nhất ms | trễ p99 ms | số lần timer chạy |
|:--|--:|--:|--:|--:|--:|--:|--:|
| heavy | bm-native | sync | 227 | 218 | 227 | 227 | 1 |
| heavy | bm-native | async | 235 | 469 | 1.50 | 1.00 | 236 |
| heavy | bm-wasm | sync | 455 | 688 | 455 | 455 | 1 |
| heavy | bm-wasm | async (chạy trên main thread) | 473 | 750 | 473 | 473 | 1 |
| heavy | takumi-native | async | 262 | 796 | 7.30 | 2.50 | 253 |
| heavy | takumi-wasm | async (chạy trên main thread) | 819 | 968 | 819 | 819 | 1 |
| anim | bm-native | sync | 476 | 484 | 476 | 476 | 1 |
| anim | bm-native | async | 544 | 1 064 | 1.20 | 1.10 | 545 |
| anim | bm-wasm | sync | 969 | 1 219 | 969 | 969 | 1 |
| anim | bm-wasm | async (chạy trên main thread) | 954 | 1 094 | 954 | 954 | 1 |
| anim | takumi-native | async | 409 | 2 156 | 21.6 | 13.2 | 286 |
| anim | takumi-wasm | async (chạy trên main thread) | 2 072 | 2 360 | 2 072 | 2 072 | 1 |

heavy = một PNG 2400×2400: gradient, 24 thẻ với box-shadow mờ lớn, cứ ba thẻ có một thẻ `filter: blur(6px)`, chữ; anim = renderAnimation: 60 khung (2 s ở 30 fps) WebP lossless 800×420, 12 hình tròn có bóng, mờ, xoay (cảnh tĩnh). Một `setInterval` 1 ms ghi khoảng cách giữa các lần chạy trong lúc lời gọi chạy. Một chuỗi setImmediate giữ cho vòng lặp không ngủ, vì vòng lặp Node rảnh trên Windows thức theo đồng hồ hệ thống 15,6 ms và timer sẽ không bao giờ cho thấy dưới ~16 ms. Lời gọi chặn vòng lặp cho thấy một lần chạy có độ trễ bằng cả lời gọi. CPU ms là của cả tiến trình trong lúc gọi, kể cả chuỗi setImmediate trên main thread (khoảng một lõi mỗi khi vòng lặp rảnh). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 2.95 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:eventloop -->

## Cold start

<!-- native-bench:cold -->
| Engine | thực median | wall p95 | hơn Node, median | hơn Node, p95 | import | registerFont | PNG đầu tiên |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Node rỗng (mốc) | 68.6 | 101 | 0 | 0 | — | — | — |
| bm-native | 99.9 | 138 | 31.3 | 69.2 | 6.20 | 0.36 | 21.7 |
| bm-wasm | 168 | 207 | 99.9 | 138 | 10.1 | 3.18 | 85.0 |
| takumi-native | 120 | 166 | 50.9 | 97.5 | 28.9 | 0.98 | 22.5 |
| takumi-wasm | 306 | 373 | 238 | 304 | 42.3 | 3.97 | 188 |

ms. 30 lần mỗi engine, xen kẽ các engine; spawn node → import engine như người dùng → registerFont(Inter Regular) → PNG og card 1200×630 → thoát; thời gian thực = đồng hồ của tiến trình cha từ spawn tới khi thoát. Các cột import / registerFont / PNG đầu tiên là median đo bên trong tiến trình con. CPU bận trong lúc đo: trung bình 76.7 % (tiến trình khác ≈ 4.78 lõi). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 4.78 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:cold -->

## Bộ nhớ

<!-- native-bench:memory -->
| Engine | RSS sau khởi tạo | RSS sau lượt 1 → 10 | bộ nhớ engine 1 → N | JS heap 1 → N | RSS đỉnh, cả bộ | RSS đỉnh PNG 4000×4000 (tăng thêm) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 67.2 | 94.7 → 96.0 | 31.6 → 31.6 | 7.50 → 6.40 | 186 | 143 (85.8) |
| bm-wasm | 75.0 | 132 → 156 | 65.1 → 88.1 | 6.60 → 6.70 | 253 | 149 (89.3) |
| takumi-native | 70.4 | 102 → 139 | — → — | 7.70 → 6.70 | 201 | 135 (74.8) |
| takumi-wasm | 86.0 | 140 → 176 | 71.5 → 71.5 | 7.40 → 7.50 | 237 | 151 (83.6) |

MiB, sau khi ép GC. Một tiến trình cho mỗi engine; mỗi lượt render mọi fixture ra raw và PNG (API async), một renderer cho mỗi bộ font. Bộ nhớ engine: bm-native = số byte addon đang cấp phát (`memoryBytes()`), bm-wasm / takumi-wasm = bộ nhớ tuyến tính wasm, takumi-native = không công bố. Node rỗng: 45.0 MiB RSS. "Tăng thêm" = RSS đỉnh trừ RSS ngay trước lần render 4000×4000.
<!-- /native-bench:memory -->

## Thời gian render

<!-- native-bench:speed -->
| Định dạng (số fixture) | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| raw (250) | 0.51 ±15.5 % ⚠ | 0.56 ±15.7 % ⚠ | 0.85 ±16.1 % ⚠ | 1.02 ±15.3 % ⚠ | 1.36 ±15.8 % ⚠ |
| png (250) | 1.05 ±14.6 % ⚠ | 1.06 ±16.7 % ⚠ | 1.56 ±15.0 % ⚠ | 1.89 ±14.5 % ⚠ | 3.36 ±15.8 % ⚠ |
| jpeg (3) | 13.5 ±19.9 % ⚠ | 13.2 ±17.9 % ⚠ | 21.7 ±24.1 % ⚠ | 19.5 ±15.1 % ⚠ | 28.4 ±25.3 % ⚠ |
| webp (3) | 10.1 ±21.2 % ⚠ | 9.95 ±22.0 % ⚠ | 13.9 ±26.9 % ⚠ | 73.9 ±23.4 % ⚠ | 17.8 ±24.3 % ⚠ |
| raw, bỏ known-gaps | 0.52 | 0.57 | 0.87 | 1.04 | 1.38 |
| png, bỏ known-gaps | 1.07 | 1.08 | 1.59 | 1.92 | 3.41 |
| raw, từng lượt | 0.52 / 0.64 / 0.48 | 0.56 / 0.69 / 0.51 | 0.87 / 1.07 / 0.79 | 1.03 / 1.26 / 0.94 | 1.37 / 1.71 / 1.28 |
| png, từng lượt | 1.07 / 1.32 / 1.01 | 1.07 / 1.36 / 1.00 | 1.57 / 1.96 / 1.49 | 1.89 / 2.33 / 1.78 | 3.37 / 4.29 / 3.23 |

Trung bình nhân của thời gian render median từng fixture, ms. jpeg (quality 85) và webp (lossless; takumi-wasm dùng bộ mã hoá WebP khác takumi-native, xem bảng định dạng) chỉ đo trên ba fixture.
<!-- /native-bench:speed -->

<!-- native-bench:cpu -->
| Biến thể | raw: thực / CPU ms / lõi | PNG: thực / CPU ms / lõi |
|:--|--:|--:|
| bm-native sync | 0.53 / 0.55 / 1.05 | 1.56 / 1.42 / 0.91 |
| bm-native async | 0.60 / 1.42 / 2.35 | 1.58 / 2.32 / 1.47 |
| bm-wasm sync | 0.87 / 0.69 / 0.79 | 2.31 / 1.78 / 0.77 |
| takumi-native async | 1.02 / 1.71 / 1.67 | 2.14 / 3.81 / 1.78 |
| takumi-wasm | 1.40 / 1.10 / 0.79 | 4.77 / 4.08 / 0.86 |

Trung bình trên mọi lần render được đo (không phải geomean): thời gian thực mỗi lần render, thời gian CPU của tiến trình (mọi thread) trong lúc đó, và tỉ số. Tỉ số trên 1 nghĩa là một lần render dùng hơn một lõi.
<!-- /native-bench:cpu -->

Các fixture mà bm-native vượt xa nhất và thua xa nhất takumi-native (cùng async):

<!-- native-bench:best-worst -->
**raw — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-jpeg-fit` | 1.68 | 1.67 | 13.4 | 1.43 | 0.12× |
| `pfx-bg-blend` | 0.75 | 0.89 | 5.07 | 1.04 | 0.18× |
| `pfx-bg-clip-text` | 0.43 | 0.48 | 2.28 | 0.93 | 0.21× |
| `gap-background-clip-text` | 0.34 | 0.38 | 1.62 | 1.05 | 0.23× |
| `fix-text-emoji-wrap` | 0.13 | 0.14 | 0.55 | 1.10 | 0.25× |
| `fix-text-emoji-zwj` | 0.16 | 0.17 | 0.66 | 2.21 | 0.26× |
| `fix-text-emoji-spacing` | 0.14 | 0.15 | 0.54 | 1.14 | 0.27× |
| `fix-text-emoji-keycap-vs` | 0.13 | 0.13 | 0.42 | 1.90 | 0.32× |
| `radial-spotlight-small` | 0.45 | 0.49 | 1.50 | 2.02 | 0.33× |
| `fix-text-emoji-flags-skin` | 0.12 | 0.14 | 0.42 | 1.52 | 0.33× |

**raw — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `fix-text-paint-order` | 0.82 | 0.87 | 0.71 | 1.17 | 1.21× |
| `abs-zorder` | 2.09 | 1.78 | 1.51 | 1.08 | 1.18× |
| `pfx-text-stroke` | 0.77 | 0.83 | 0.73 | 1.43 | 1.14× |
| `radius-elliptical` | 1.49 | 1.53 | 1.37 | 0.82 | 1.12× |
| `pfx-svg-background` | 0.69 | 0.75 | 0.71 | 3.19 | 1.05× |
| `sizing-padding-margin` | 1.01 | 1.22 | 1.21 | 1.72 | 1.01× |
| `sizing-aspect-ratio` | 0.95 | 1.08 | 1.09 | 2.73 | 1.00× |
| `radius-pill-circle` | 1.57 | 1.77 | 1.84 | 1.07 | 0.96× |
| `borders-with-radius` | 0.77 | 0.87 | 0.92 | 0.87 | 0.95× |
| `flex-row-column` | 1.11 | 1.16 | 1.23 | 1.77 | 0.94× |

**png — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `colors-solid-bg` | 0.25 | 0.28 | 1.22 | 2.54 | 0.23× |
| `gap-oklch-color` | 0.22 | 0.22 | 0.88 | 1.27 | 0.25× |
| `anim-opacity-t250` | 0.23 | 0.22 | 0.78 | 2.33 | 0.28× |
| `pfx-visibility` | 0.30 | 0.32 | 1.12 | 1.36 | 0.29× |
| `anim-kf-option-t500` | 0.20 | 0.20 | 0.69 | 1.75 | 0.30× |
| `anim-alternate-t700` | 0.19 | 0.19 | 0.64 | 1.11 | 0.30× |
| `anim-opacity-t1500` | 0.19 | 0.17 | 0.57 | 0.88 | 0.30× |
| `anim-alternate-t1100` | 0.19 | 0.20 | 0.62 | 2.39 | 0.32× |
| `anim-two-anims-t400` | 0.25 | 0.24 | 0.76 | 1.13 | 0.32× |
| `anim-opacity-t900` | 0.22 | 0.21 | 0.66 | 1.52 | 0.32× |

**png — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-photo-bg` | 30.8 | 30.5 | 13.4 | 3.52 | 2.28× |
| `card-blog` | 20.0 | 20.1 | 12.5 | 2.50 | 1.61× |
| `img-intrinsic-size` | 2.06 | 2.54 | 1.69 | 2.96 | 1.50× |
| `img-radius-clip` | 17.4 | 17.6 | 12.0 | 2.02 | 1.46× |
| `radial-spotlight-small` | 4.37 | 4.51 | 3.17 | 2.57 | 1.42× |
| `fx-text-shadow` | 2.67 | 2.76 | 2.07 | 4.04 | 1.33× |
| `pfx-mix-blend` | 2.91 | 3.06 | 2.31 | 1.30 | 1.33× |
| `stress-3000x2000-card` | 57.9 | 56.5 | 45.1 | 1.80 | 1.25× |
| `img-png-fit` | 11.8 | 12.1 | 9.63 | 1.79 | 1.25× |
| `fix-css-image-rendering-modes` | 5.25 | 5.46 | 4.41 | 3.18 | 1.24× |
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
| 300×200 raw | 0.13 | 0.14 | 0.22 | 0.28 | 0.41 |
| 300×200 png | 0.22 | 0.15 | 0.19 | 0.47 | 0.56 |
| 1200×630 raw | 0.73 | 0.77 | 1.14 | 0.92 | 1.18 |
| 1200×630 png | 1.08 | 0.72 | 1.30 | 3.14 | 5.17 |
| 2400×1260 raw | 2.60 | 2.98 | 5.16 | 2.96 | 5.88 |
| 2400×1260 png | 4.84 | 4.96 | 6.11 | 11.0 | 20.4 |

| Cảnh animation, một khung raw 800×420 | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| shadow + blur (as animated) | 7.16 | 7.19 | 14.3 | 17.9 | 32.3 |
| shadow only | 2.17 | 2.24 | 4.37 | 5.08 | 8.11 |
| blur only | 2.22 | 2.30 | 4.01 | 3.78 | 6.60 |
| neither | 0.97 | 1.00 | 1.59 | 1.38 | 2.16 |

Median ms, các biến thể chạy xen kẽ (40 lần cho khung rỗng, ít hơn cho cảnh). Khung rỗng không vẽ gì, nên thời gian của nó là chi phí theo điểm ảnh mà khung nào cũng trả (xoá canvas, đổi alpha, chép kết quả ra) cộng, với PNG, việc mã hoá một ảnh phẳng. Cảnh là cảnh của animation trong phép đo event loop: 12 hình tròn 60×60 xoay, có `box-shadow: 0 8px 30px` và `filter: blur(2px)`.
<!-- /native-bench:diagnose -->

### Định dạng và bộ mã hoá

<!-- native-bench:formats -->
| Fixture | Định dạng | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|--:|
| `lingrad-angles` | raw | 2.64 ms · 2 953 KiB | 3.02 ms · 2 953 KiB | 4.85 ms · 2 953 KiB | 4.97 ms · 2 953 KiB | 7.18 ms · 2 953 KiB |
| `lingrad-angles` | png | 7.68 ms · 32.6 KiB | 7.28 ms · 32.6 KiB | 11.6 ms · 32.6 KiB | 9.17 ms · 102 KiB | 39.1 ms · 102 KiB |
| `lingrad-angles` | jpeg | 12.4 ms · 52.2 KiB | 13.3 ms · 52.2 KiB | 23.8 ms · 52.2 KiB | 20.4 ms · 52.3 KiB | 27.4 ms · 52.3 KiB |
| `lingrad-angles` | webp | 9.23 ms · 28.9 KiB | 8.91 ms · 28.9 KiB | 12.1 ms · 28.9 KiB | 126 ms · 22.8 KiB | 17.2 ms · 169 KiB |
| `img-photo-bg` | raw | 1.34 ms · 2 953 KiB | 1.39 ms · 2 953 KiB | 2.06 ms · 2 953 KiB | 4.01 ms · 2 953 KiB | 6.67 ms · 2 953 KiB |
| `img-photo-bg` | png | 30.8 ms · 511 KiB | 30.5 ms · 511 KiB | 46.3 ms · 511 KiB | 13.4 ms · 513 KiB | 58.8 ms · 513 KiB |
| `img-photo-bg` | jpeg | 16.4 ms · 55.1 KiB | 14.0 ms · 55.1 KiB | 21.3 ms · 55.1 KiB | 20.3 ms · 55.2 KiB | 31.7 ms · 55.2 KiB |
| `img-photo-bg` | webp | 15.9 ms · 367 KiB | 14.7 ms · 367 KiB | 20.7 ms · 367 KiB | 183 ms · 414 KiB | 25.0 ms · 470 KiB |
| `card-flat-ui` | raw | 2.92 ms · 2 953 KiB | 3.14 ms · 2 953 KiB | 5.63 ms · 2 953 KiB | 3.95 ms · 2 953 KiB | 7.41 ms · 2 953 KiB |
| `card-flat-ui` | png | 5.69 ms · 23.1 KiB | 5.78 ms · 23.1 KiB | 8.90 ms · 23.1 KiB | 7.25 ms · 25.3 KiB | 20.8 ms · 25.3 KiB |
| `card-flat-ui` | jpeg | 12.2 ms · 48.9 KiB | 12.4 ms · 48.9 KiB | 20.2 ms · 48.9 KiB | 17.9 ms · 49.0 KiB | 26.4 ms · 49.0 KiB |
| `card-flat-ui` | webp | 6.96 ms · 18.5 KiB | 7.51 ms · 18.5 KiB | 10.7 ms · 18.5 KiB | 17.5 ms · 13.4 KiB | 13.2 ms · 27.6 KiB |

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
| bm-engine | 0.1.0, git `ef21c5674b` (integ, 4 file đang sửa) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 2 083 KiB, Zig 0.17.1, ReleaseFast, sha256 `ec92d1feb24f` |
| bm-wasm | `js/bm_engine.wasm` (profile full), 1 140 KiB, sha256 `7a7e363d2c98` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Lần chạy | 2026-11-12 11:03 UTC, chế độ full, 250 fixtures, 16.6 min; CPU bận trước khi chạy: 53.5 % |
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
