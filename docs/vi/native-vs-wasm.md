# Addon native so với WebAssembly

[English](../en/native-vs-wasm.md) · [Tiếng Việt](native-vs-wasm.md)

Trên Node.js, bm-engine chạy dưới dạng addon Node-API native hoặc dưới dạng WebAssembly. Cả hai được biên dịch
từ cùng một mã nguồn Zig, có cùng API và cho ra cùng từng byte. Trang này giải thích bạn nhận được backend nào,
khi nào nên chọn backend kia, backend native dùng thread ra sao, và cả hai so với bản native và bản wasm của
takumi thế nào trên bộ benchmark 200 fixture. Cài đặt: [Bắt đầu](./getting-started.md). Cách build và phát hành
các gói theo nền tảng: [Phát hành](./publishing.md).

## Nên dùng backend nào

| Mã của bạn chạy ở đâu | Backend | Cách dùng |
|:--|:--|:--|
| Node.js, Bun, Deno (server, CLI, script build) | **native**, tự động quay về wasm | `import { Renderer, backend } from "bm-engine"`; `backend` là `"native"` hoặc `"wasm"` |
| Trình duyệt, Web Worker | wasm (lựa chọn duy nhất) | `bm-engine` trỏ tới bản wasm ở đó |
| Cloudflare Workers, Vercel / Netlify Edge, Deno Deploy và các runtime edge khác | wasm (lựa chọn duy nhất) | cùng câu import |
| Node.js nhưng vẫn muốn wasm (ví dụ để tái tạo đúng từng bit ảnh render trong trình duyệt, hoặc trên nền tảng mà addon chưa được kiểm thử) | wasm | `import ... from "bm-engine/full"` hoặc `BM_ENGINE_BACKEND=wasm` |
| Node.js và muốn báo lỗi thay vì lặng lẽ quay về wasm | native | `import ... from "bm-engine/native"` hoặc `BM_ENGINE_BACKEND=native` |

Việc quay về wasm diễn ra im lặng: nếu không có addon cho nền tảng, nếu CPU cũ hơn x86-64-v2 (SSE4.2), hoặc nếu
addon không qua bước kiểm tra dấu phẩy động lúc nạp, `bm-engine` nạp bản wasm và mọi thứ vẫn chạy, chỉ chậm hơn
và các lời gọi async chạy trên main thread. Hãy ghi log `backend` một lần lúc khởi động nếu bạn cần biết.

## Kết quả tóm tắt

<!-- native-bench:highlights -->
- **bm-native so với bm-wasm (sync):** raw bằng 0.76× thời gian của wasm [0.77× / 0.75× / 0.80×] (nhanh hơn ở 192/200 fixture), PNG 0.67× [0.68× / 0.67× / 0.68×] (nhanh hơn ở 200/200).
- **bm-native so với takumi-native, cùng async:** raw 0.89× [0.90× / 0.88× / 0.95×] (bm nhanh hơn ở 136/200, từng fixture 0.22×–2.78×), PNG 0.68× [0.67× / 0.65× / 0.66×] (bm nhanh hơn ở 170/200, từng fixture 0.28×–2.21×). Với API sync của bm: raw 0.69×, PNG 0.66×. Dưới 1× = bm-native tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ đó ở từng lượt.
- **Thời gian CPU mỗi ảnh (cùng async):** PNG 3.29 ms bm-native so với 5.28 ms takumi-native (1.11 so với 1.45 lõi bận trong một lần render); raw 2.25 so với 2.30 ms. takumi-native chạy một phần của một lần render (các đoạn deflate PNG, blur, WebP, khung animation) trên thread pool rayon riêng; bm render một ảnh trên một thread (bm-native sync: 0.88 lõi với PNG).
- **Hai bản build của chính takumi:** takumi-native tốn 0.69× thời gian của takumi-wasm với raw và 0.48× với PNG.
- **Trùng byte:** bm-native và bm-wasm cho cùng byte ở 1457/1457 phép so trên 200 fixture (586 MB; 0 khác biệt).
- **Nhiễu:** geomean tuyệt đối raw / PNG lệch tới 40.1 % giữa các lượt (tải của tiến trình khác thay đổi trong lúc chạy), còn tỉ lệ giữa các engine, đo xen kẽ trong từng lượt, lệch nhiều nhất 17.9 %. Hãy đọc tỉ lệ; coi số ms tuyệt đối là ±20.1 %.
<!-- /native-bench:highlights -->

<!-- native-bench:summary -->
| Chỉ số | bm-native | bm-wasm | takumi-native | takumi-wasm |
|:--|--:|--:|--:|--:|
| raw RGBA, geomean ms — API sync | 0.96 ±7.00 % ⚠ | 1.26 ±5.20 % ⚠ | không có API sync | — |
| raw RGBA, geomean ms — API async | 1.25 ±20.1 % ⚠ | — | 1.40 ±15.3 % ⚠ | 2.02 ±6.45 % ⚠ |
| PNG, geomean ms — API sync | 1.80 ±5.85 % ⚠ | 2.67 ±5.50 % ⚠ | không có API sync | — |
| PNG, geomean ms — API async | 1.83 ±11.8 % ⚠ | — | 2.71 ±11.1 % ⚠ | 5.63 ±5.45 % ⚠ |
| Thời gian CPU mỗi lần render PNG, ms trung bình (số lõi dùng) | 2.46 (0.88 lõi) | 3.19 (0.78 lõi) | 5.28 (1.45 lõi) | 7.29 (0.85 lõi) |
| Dung lượng PNG, geomean so với takumi | 0.78× | 0.78× | 1.00× | 1.00× |
| Cold start so với Node rỗng, median / p95 ms | 28.6 / 75.5 | 96.5 / 139 | 60.2 / 83.8 | 238 / 282 |
| RSS sau 1 → 10 lượt cả bộ fixture, MiB | 91.9 → 93.4 | 126 → 126 | 147 → 160 | 132 → 161 |
| RSS đỉnh, một PNG 4000×4000, MiB | 146 | 149 | 137 | 151 |
| Event loop: độ trễ lớn nhất của timer 1 ms, render nặng 2400×2400, ms | 299 (sync) · 3.90 (async) | 700 (sync) · 604 (async) | 15.3 (async) | 1 095 (async) |
| Event loop: như trên, animation 60 khung, ms | 5 376 (sync) · 6.50 (async) | 10 866 (sync) · 9 086 (async) | 30.1 (async) | 2 563 (async) |
| Thông lượng, og card PNG, 4 đồng thời, ảnh/s (cấu hình tốt nhất) | 177 (many K=4, UV 4) ⚠ | 119 (pool K=8) ⚠ | 170 (many K=2, UV 4) ⚠ | 78.5 (pool K=4) ⚠ |
| Thông lượng, 8 đồng thời, ảnh/s (cấu hình tốt nhất) | 247 (many K=8, UV 8) ⚠ | 157 (pool K=8) ⚠ | 200 (one, UV 8) ⚠ | 88.9 (pool K=8) ⚠ |

Geomean trên 200 fixture mà cả bốn engine đều render được; ± = nửa khoảng chênh giữa geomean của 3 lượt so với median của chúng; ⚠ = chênh quá 10 %. Cold start: median / p95 của 30 tiến trình mới trừ median của Node rỗng. Event loop, bộ nhớ và thông lượng là một lần đo; ở các dòng thông lượng ⚠ = tiến trình khác dùng trung bình hơn một lõi trong lúc đo.
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
| bm-native | 1 client, tuần tự | 4 | 58.9 |  |  |  |  |
| bm-wasm | 1 client, tuần tự | — | 37.1 |  |  |  |  |
| takumi-native | 1 client, tuần tự | 4 | 75.2 |  |  |  |  |
| takumi-wasm | 1 client, tuần tự | — | 26.6 |  |  |  |  |
| bm-native | 1 renderer, async | 4 | 63.8 (1.08×, 108 %) | 64.2 (1.09×, 109 %) | 66.3 (1.13×, 113 %) | 68.6 (1.16×, 116 %) | 70.7 (1.20×, 120 %) |
| bm-native | 2 renderer, async | 4 | 68.9 (1.17×, 117 %) | 116 (1.97×, 99 %) | 98.0 (1.66×, 83 %) | 99.9 (1.70×, 85 %) | 106 (1.79×, 90 %) |
| bm-native | 4 renderer, async | 4 | 66.1 (1.12×, 112 %) | 108 (1.83×, 91 %) | 177 (3.00×, 75 %) | 188 (3.20×, 80 %) | 168 (2.86×, 71 %) |
| bm-native | 8 renderer, async | 4 | 59.0 (1.00×, 100 %) | 92.0 (1.56×, 78 %) | 159 (2.70×, 68 %) | 160 (2.71×, 68 %) | 150 (2.55×, 64 %) |
| bm-native | 1 renderer, async | 8 | 62.0 (1.05×, 105 %) | 63.8 (1.08×, 108 %) | 64.2 (1.09×, 109 %) | 63.4 (1.08×, 108 %) | 53.6 (0.91×, 91 %) |
| bm-native | 2 renderer, async | 8 | 68.4 (1.16×, 116 %) | 105 (1.79×, 89 %) | 116 (1.97×, 99 %) | 71.8 (1.22×, 61 %) | 109 (1.85×, 93 %) |
| bm-native | 4 renderer, async | 8 | 70.5 (1.20×, 120 %) | 106 (1.81×, 90 %) | 173 (2.93×, 73 %) | 189 (3.20×, 80 %) | 201 (3.41×, 85 %) |
| bm-native | 8 renderer, async | 8 | 69.7 (1.18×, 118 %) | 101 (1.72×, 86 %) | 154 (2.62×, 65 %) | 247 (4.19×, 52 %) | 220 (3.74×, 47 %) |
| takumi-native | 1 renderer, async | 4 | 94.0 (1.25×, 125 %) | 121 (1.60×, 80 %) | 158 (2.10×, 52 %) | 164 (2.18×, 55 %) | 166 (2.21×, 55 %) |
| takumi-native | 1 renderer, async | 8 | 87.9 (1.17×, 117 %) | 123 (1.64×, 82 %) | 158 (2.10×, 52 %) | 200 (2.66×, 33 %) | 205 (2.73×, 34 %) |
| takumi-native | 2 renderer, async | 4 | 87.0 (1.16×, 116 %) | 102 (1.36×, 68 %) | 170 (2.26×, 113 %) | 178 (2.37×, 119 %) | 177 (2.35×, 118 %) |
| takumi-native | 4 renderer, async | 4 | 77.4 (1.03×, 103 %) | 126 (1.68×, 84 %) | 167 (2.22×, 56 %) | 176 (2.34×, 58 %) | 173 (2.30×, 57 %) |
| takumi-native | 2 renderer, async | 8 | 87.9 (1.17×, 117 %) | 133 (1.76×, 88 %) | 163 (2.17×, 109 %) | 183 (2.44×, 122 %) | 184 (2.45×, 123 %) |
| takumi-native | 4 renderer, async | 8 | 81.3 (1.08×, 108 %) | 97.5 (1.30×, 65 %) | 161 (2.13×, 53 %) | 182 (2.42×, 60 %) | 180 (2.39×, 60 %) |
| bm-wasm | worker pool, 1 worker | — | 41.6 (1.12×, 112 %) | 42.3 (1.14×, 114 %) | 42.3 (1.14×, 114 %) | 42.8 (1.15×, 115 %) | 40.5 (1.09×, 109 %) |
| bm-wasm | worker pool, 2 worker | — | 48.7 (1.31×, 131 %) | 80.6 (2.17×, 109 %) | 77.0 (2.08×, 104 %) | 69.6 (1.88×, 94 %) | 70.7 (1.91×, 95 %) |
| bm-wasm | worker pool, 4 worker | — | 40.9 (1.10×, 110 %) | 80.8 (2.18×, 109 %) | 116 (3.12×, 78 %) | 123 (3.31×, 83 %) | 114 (3.08×, 77 %) |
| bm-wasm | worker pool, 8 worker | — | 43.3 (1.17×, 117 %) | 68.1 (1.84×, 92 %) | 119 (3.22×, 80 %) | 157 (4.22×, 53 %) | 166 (4.49×, 56 %) |
| takumi-wasm | worker pool, 1 worker | — | 21.4 (0.80×, 80 %) | 23.9 (0.90×, 90 %) | 27.8 (1.05×, 105 %) | 27.1 (1.02×, 102 %) | 29.7 (1.12×, 112 %) |
| takumi-wasm | worker pool, 2 worker | — | 28.4 (1.07×, 107 %) | 53.0 (1.99×, 100 %) | 50.5 (1.90×, 95 %) | 49.6 (1.86×, 93 %) | 54.3 (2.04×, 102 %) |
| takumi-wasm | worker pool, 4 worker | — | 27.5 (1.03×, 103 %) | 44.2 (1.66×, 83 %) | 78.5 (2.95×, 74 %) | 84.3 (3.17×, 79 %) | 87.3 (3.28×, 82 %) |
| takumi-wasm | worker pool, 8 worker | — | 27.7 (1.04×, 104 %) | 50.7 (1.91×, 95 %) | 72.6 (2.73×, 68 %) | 88.9 (3.34×, 42 %) | 95.8 (3.60×, 45 %) |

Ảnh mỗi giây; trong ngoặc là mức tăng so với tốc độ tuần tự một client của cùng engine (các dòng đầu) và hiệu suất mở rộng = mức tăng / min(N, số thread có thể render các ảnh khác nhau cùng lúc, 8 CPU logic); một renderer bm tính là 1, K renderer là min(K, UV_THREADPOOL_SIZE), renderer của takumi-native là UV_THREADPOOL_SIZE, pool worker là K. og card 1200×630 PNG, vòng kín: N client, mỗi client luôn có một yêu cầu đang chạy; 2000 ms mỗi điểm sau khi khởi động. CPU bận trong lúc đo: trung bình 98.4 % (tiến trình khác ≈ 6.17 lõi). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 6.17 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:throughput -->

## Đầu ra trùng từng byte

Hai backend cho ra **cùng từng byte**: trên mọi fixture của bộ benchmark, đầu ra raw RGBA, PNG, JPEG, WebP, SVG và
`measure`, animation (WebP / APNG / GIF), ICO, nguồn HTML, ảnh đính kèm, font WOFF2 và thông báo lỗi đều được so từng
byte (`node bench/native-identity.mjs`), và kết quả async của native được so với kết quả sync của native. Một server có
thể đổi backend (hoặc bị quay về wasm) mà ảnh và cache không thay đổi gì. Cam kết này mới được kiểm chứng trên
Windows x64; xem bảng nền tảng.

<!-- native-bench:equiv -->
| Engine so với takumi-wasm (200 fixture, raw RGBA) | identical | equivalent | close | different | error/unsupported |
|:--|--:|--:|--:|--:|--:|
| bm-native | 74 | 126 | 0 | 0 | 0 |
| bm-wasm | 74 | 126 | 0 | 0 | 0 |
| takumi-native | 200 | 0 | 0 | 0 | 0 |

| Cùng engine, hai bản build | raw RGBA trùng byte | file PNG trùng byte |
|:--|--:|--:|
| bm-native = bm-wasm | 200/200 | 200/200 |
| takumi-native = takumi-wasm | 200/200 | 200/200 |

`bench/native-identity.mjs`: 200 fixture, 1457 phép so (raw, PNG, JPEG, WebP, measure, SVG, animation, ICO, HTML, ảnh, WOFF2, thông báo lỗi, native async so với sync), 1457 trùng (8 trong số đó là cùng thông báo lỗi ở cả hai), 0 khác, 586 MB đã so.
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
| `bm-engine.win32-x64-msvc.node` | `x86_64-windows-gnu` | 2 010 | 1 077 | 880 | đã chạy (benchmark này) |
| `bm-engine.win32-arm64-msvc.node` | `aarch64-windows-gnu` | 1 570 | 954 | 743 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-x64-gnu.node` | `x86_64-linux-gnu.2.17` | 1 901 | 1 041 | 856 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-x64-musl.node` | `x86_64-linux-musl` | 1 900 | 1 041 | 856 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-arm64-gnu.node` | `aarch64-linux-gnu.2.17` | 1 571 | 955 | 743 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.linux-arm64-musl.node` | `aarch64-linux-musl` | 1 571 | 955 | 742 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.darwin-x64.node` | `x86_64-macos.10.15` | 1 901 | 1 040 | 855 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| `bm-engine.darwin-arm64.node` | `aarch64-macos.11.0` | 1 594 | 929 | 712 | cross-compile, kiểm tra cấu trúc, chưa từng chạy |
| bm wasm `core` | wasm32 | 454 | 212 | 180 |  |
| bm wasm `standard` | wasm32 | 878 | 435 | 374 |  |
| bm wasm `full` | wasm32 | 1 100 | 538 | 453 |  |
| bm wasm `add-on WOFF` | wasm32 | 84.2 | 67.7 | 65.5 |  |
| takumi 2.20 native win32-x64-msvc (.node) |  | 9 796 | 4 258 | 3 201 |  |
| takumi 2.20 wasm (takumi_wasm_bg.wasm) |  | 4 235 | 1 861 | 1 409 |  |

Addon native lấy từ `native/dist/manifest.json` (build ngày 2026-11-12 với Zig 0.17.1, ReleaseFast). Mỗi người dùng chỉ tải một addon (gói optional cho nền tảng của họ) cộng với bản wasm dự phòng nằm trong gói chính.
<!-- /native-bench:sizes -->

## Event loop

<!-- native-bench:eventloop -->
| Việc | Engine | API | ms của việc | CPU ms | trễ timer lớn nhất ms | trễ p99 ms | số lần timer chạy |
|:--|--:|--:|--:|--:|--:|--:|--:|
| heavy | bm-native | sync | 298 | 297 | 299 | 299 | 1 |
| heavy | bm-native | async | 333 | 687 | 3.90 | 1.50 | 331 |
| heavy | bm-wasm | sync | 700 | 890 | 700 | 700 | 1 |
| heavy | bm-wasm | async (chạy trên main thread) | 603 | 797 | 604 | 604 | 1 |
| heavy | takumi-native | async | 301 | 735 | 15.3 | 2.00 | 286 |
| heavy | takumi-wasm | async (chạy trên main thread) | 1 095 | 1 297 | 1 095 | 1 095 | 1 |
| anim | bm-native | sync | 5 374 | 5 031 | 5 376 | 5 376 | 1 |
| anim | bm-native | async | 5 820 | 11 172 | 6.50 | 1.80 | 5749 |
| anim | bm-wasm | sync | 10 866 | 10 453 | 10 866 | 10 866 | 1 |
| anim | bm-wasm | async (chạy trên main thread) | 9 086 | 9 234 | 9 086 | 9 086 | 1 |
| anim | takumi-native | async | 414 | 2 204 | 30.1 | 22.6 | 257 |
| anim | takumi-wasm | async (chạy trên main thread) | 2 562 | 2 938 | 2 563 | 2 563 | 1 |

heavy = một PNG 2400×2400: gradient, 24 thẻ với box-shadow mờ lớn, cứ ba thẻ có một thẻ `filter: blur(6px)`, chữ; anim = renderAnimation: 60 khung (2 s ở 30 fps) WebP lossless 800×420, 12 hình tròn có bóng, mờ, xoay (cảnh tĩnh). Một `setInterval` 1 ms ghi khoảng cách giữa các lần chạy trong lúc lời gọi chạy. Một chuỗi setImmediate giữ cho vòng lặp không ngủ, vì vòng lặp Node rảnh trên Windows thức theo đồng hồ hệ thống 15,6 ms và timer sẽ không bao giờ cho thấy dưới ~16 ms. Lời gọi chặn vòng lặp cho thấy một lần chạy có độ trễ bằng cả lời gọi. CPU ms là của cả tiến trình trong lúc gọi, kể cả chuỗi setImmediate trên main thread (khoảng một lõi mỗi khi vòng lặp rảnh). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 5.40 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:eventloop -->

## Cold start

<!-- native-bench:cold -->
| Engine | thực median | wall p95 | hơn Node, median | hơn Node, p95 | import | registerFont | PNG đầu tiên |
|:--|--:|--:|--:|--:|--:|--:|--:|
| Node rỗng (mốc) | 66.5 | 86.7 | 0 | 0 | — | — | — |
| bm-native | 95.1 | 142 | 28.6 | 75.5 | 6.50 | 0.44 | 22.9 |
| bm-wasm | 163 | 205 | 96.5 | 139 | 8.90 | 3.20 | 85.1 |
| takumi-native | 127 | 150 | 60.2 | 83.8 | 29.5 | 0.97 | 27.2 |
| takumi-wasm | 305 | 348 | 238 | 282 | 46.7 | 4.18 | 187 |

ms. 30 lần mỗi engine, xen kẽ các engine; spawn node → import engine như người dùng → registerFont(Inter Regular) → PNG og card 1200×630 → thoát; thời gian thực = đồng hồ của tiến trình cha từ spawn tới khi thoát. Các cột import / registerFont / PNG đầu tiên là median đo bên trong tiến trình con. CPU bận trong lúc đo: trung bình 82.7 % (tiến trình khác ≈ 5.24 lõi). ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng 5.24 lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.
<!-- /native-bench:cold -->

## Bộ nhớ

<!-- native-bench:memory -->
| Engine | RSS sau khởi tạo | RSS sau lượt 1 → 10 | bộ nhớ engine 1 → N | JS heap 1 → N | RSS đỉnh, cả bộ | RSS đỉnh PNG 4000×4000 (tăng thêm) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 65.6 | 91.9 → 93.4 | 28.2 → 28.2 | 7.20 → 6.20 | 218 | 146 (85.8) |
| bm-wasm | 67.0 | 126 → 126 | 60.4 → 60.4 | 7.40 → 6.40 | 223 | 149 (87.6) |
| takumi-native | 67.5 | 147 → 160 | — → — | 7.40 → 6.40 | 190 | 137 (74.9) |
| takumi-wasm | 73.1 | 132 → 161 | 67.2 → 67.2 | 7.10 → 7.20 | 224 | 151 (82.9) |

MiB, sau khi ép GC. Một tiến trình cho mỗi engine; mỗi lượt render mọi fixture ra raw và PNG (API async), một renderer cho mỗi bộ font. Bộ nhớ engine: bm-native = số byte addon đang cấp phát (`memoryBytes()`), bm-wasm / takumi-wasm = bộ nhớ tuyến tính wasm, takumi-native = không công bố. Node rỗng: 48.2 MiB RSS. "Tăng thêm" = RSS đỉnh trừ RSS ngay trước lần render 4000×4000.
<!-- /native-bench:memory -->

## Thời gian render

<!-- native-bench:speed -->
| Định dạng (số fixture) | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| raw (200) | 0.96 ±7.00 % ⚠ | 1.25 ±20.1 % ⚠ | 1.26 ±5.20 % ⚠ | 1.40 ±15.3 % ⚠ | 2.02 ±6.45 % ⚠ |
| png (200) | 1.80 ±5.85 % ⚠ | 1.83 ±11.8 % ⚠ | 2.67 ±5.50 % ⚠ | 2.71 ±11.1 % ⚠ | 5.63 ±5.45 % ⚠ |
| jpeg (3) | 17.3 ±13.1 % ⚠ | 17.5 ±12.7 % ⚠ | 30.2 ±13.7 % ⚠ | 26.8 ±16.9 % ⚠ | 40.7 ±14.2 % ⚠ |
| webp (3) | 11.3 ±15.1 % ⚠ | 11.8 ±19.1 % ⚠ | 18.2 ±16.3 % ⚠ | 93.5 ±14.3 % ⚠ | 23.3 ±17.2 % ⚠ |
| raw, bỏ known-gaps | 0.99 | 1.30 | 1.31 | 1.44 | 2.08 |
| png, bỏ known-gaps | 1.86 | 1.90 | 2.76 | 2.78 | 5.76 |
| raw, từng lượt | 1.00 / 0.88 / 1.02 | 1.35 / 1.12 / 1.67 | 1.31 / 1.18 / 1.29 | 1.51 / 1.29 / 1.75 | 2.09 / 1.88 / 2.15 |
| png, từng lượt | 1.87 / 1.66 / 1.83 | 1.97 / 1.68 / 2.15 | 2.77 / 2.47 / 2.69 | 2.96 / 2.59 / 3.24 | 5.89 / 5.25 / 5.88 |

Trung bình nhân của thời gian render median từng fixture, ms. jpeg (quality 85) và webp (lossless; takumi-wasm dùng bộ mã hoá WebP khác takumi-native, xem bảng định dạng) chỉ đo trên ba fixture.
<!-- /native-bench:speed -->

<!-- native-bench:cpu -->
| Biến thể | raw: thực / CPU ms / lõi | PNG: thực / CPU ms / lõi |
|:--|--:|--:|
| bm-native sync | 1.10 / 0.98 / 0.89 | 2.80 / 2.46 / 0.88 |
| bm-native async | 1.59 / 2.25 / 1.42 | 2.96 / 3.29 / 1.11 |
| bm-wasm sync | 1.42 / 1.21 / 0.86 | 4.07 / 3.19 / 0.78 |
| takumi-native async | 1.71 / 2.30 / 1.34 | 3.63 / 5.28 / 1.45 |
| takumi-wasm | 2.31 / 1.85 / 0.80 | 8.56 / 7.29 / 0.85 |

Trung bình trên mọi lần render được đo (không phải geomean): thời gian thực mỗi lần render, thời gian CPU của tiến trình (mọi thread) trong lúc đó, và tỉ số. Tỉ số trên 1 nghĩa là một lần render dùng hơn một lõi.
<!-- /native-bench:cpu -->

Các fixture mà bm-native vượt xa nhất và thua xa nhất takumi-native (cùng async):

<!-- native-bench:best-worst -->
**raw — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `pfx-bg-blend` | 1.03 | 1.15 | 5.25 | 0.78 | 0.22× |
| `img-jpeg-fit` | 2.49 | 3.54 | 15.3 | 0.92 | 0.23× |
| `pfx-bg-clip-text` | 0.68 | 0.82 | 2.84 | 1.14 | 0.29× |
| `gap-background-clip-text` | 0.47 | 0.57 | 1.96 | 1.35 | 0.29× |
| `anim-delay-fill-t0` | 0.29 | 0.40 | 0.95 | 0.64 | 0.42× |
| `opacity-with-radius-shadow` | 1.22 | 1.33 | 2.85 | 1.32 | 0.47× |
| `radial-spotlight-small` | 0.75 | 0.95 | 2.02 | 1.13 | 0.47× |
| `radial-shapes` | 3.48 | 4.56 | 8.75 | 1.21 | 0.52× |
| `radial-at-position` | 4.18 | 5.41 | 10.3 | 1.18 | 0.53× |
| `anim-color-t2000` | 0.27 | 0.31 | 0.58 | 2.33 | 0.54× |

**raw — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `radius-uniform-percorner` | 3.13 | 4.88 | 1.75 | 0.92 | 2.78× |
| `sizing-aspect-ratio` | 2.32 | 3.98 | 1.71 | 0.93 | 2.34× |
| `radius-pill-circle` | 2.76 | 4.99 | 2.16 | 1.75 | 2.31× |
| `radius-elliptical` | 2.79 | 4.14 | 1.85 | 1.42 | 2.24× |
| `sizing-minmax` | 2.01 | 2.65 | 1.26 | 0.95 | 2.10× |
| `flex-row-column` | 2.19 | 2.89 | 1.38 | 1.24 | 2.09× |
| `abs-zorder` | 3.09 | 4.04 | 2.02 | 0.70 | 2.00× |
| `flex-grow-shrink-basis` | 1.74 | 2.79 | 1.42 | 2.08 | 1.96× |
| `css-media-layer` | 1.26 | 1.99 | 1.02 | 3.43 | 1.95× |
| `tw-responsive` | 1.27 | 1.84 | 0.96 | 2.01 | 1.92× |

**png — 10 ca bm-native tốt nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `pseudo-attr` | 1.00 | 1.04 | 3.71 | 0.93 | 0.28× |
| `layout2-float-clear` | 0.82 | 0.78 | 2.13 | 1.36 | 0.37× |
| `abs-in-flow` | 0.63 | 0.59 | 1.54 | 0.78 | 0.39× |
| `css-important-var` | 1.28 | 1.31 | 3.33 | 0.85 | 0.39× |
| `anim-color-t300` | 0.44 | 0.41 | 1.04 | 1.29 | 0.40× |
| `anim-color-t700` | 0.45 | 0.42 | 1.05 | 0.96 | 0.40× |
| `anim-color-t2000` | 0.44 | 0.42 | 1.04 | 1.75 | 0.41× |
| `colors-solid-bg` | 0.59 | 0.57 | 1.39 | 2.10 | 0.41× |
| `overflow-nested` | 0.69 | 0.68 | 1.65 | 1.13 | 0.41× |
| `flex-nested-small` | 0.49 | 0.50 | 1.19 | 0.96 | 0.42× |

**png — 10 ca bm-native kém nhất**

| Fixture | bm-native sync ms | bm-native async ms | takumi-native ms | lõi takumi | bm/takumi (async) |
|:--|--:|--:|--:|--:|--:|
| `img-photo-bg` | 39.0 | 38.8 | 17.6 | 2.97 | 2.21× |
| `img-intrinsic-size` | 2.73 | 2.72 | 1.62 | 3.53 | 1.68× |
| `card-blog` | 22.2 | 24.2 | 15.6 | 2.70 | 1.55× |
| `fx-text-shadow` | 3.75 | 3.86 | 2.53 | 2.87 | 1.52× |
| `img-png-fit` | 17.8 | 17.7 | 12.0 | 1.51 | 1.47× |
| `pfx-mix-blend` | 4.13 | 4.15 | 2.85 | 0.78 | 1.46× |
| `img-radius-clip` | 20.8 | 19.3 | 13.3 | 1.90 | 1.46× |
| `card-og` | 13.7 | 14.7 | 10.4 | 2.73 | 1.42× |
| `radial-spotlight-small` | 6.48 | 6.53 | 5.05 | 1.99 | 1.29× |
| `pfx-drop-shadow` | 3.48 | 3.46 | 2.69 | 1.32 | 1.28× |
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
| 300×200 raw | 0.16 | 0.24 | 0.18 | 0.27 | 0.38 |
| 300×200 png | 0.34 | 0.31 | 0.45 | 0.63 | 0.84 |
| 1200×630 raw | 1.61 | 2.53 | 1.55 | 1.05 | 1.64 |
| 1200×630 png | 3.03 | 2.80 | 4.36 | 4.31 | 8.20 |
| 2400×1260 raw | 6.42 | 11.0 | 6.20 | 3.31 | 7.71 |
| 2400×1260 png | 10.9 | 10.2 | 15.1 | 13.0 | 27.5 |

| Cảnh animation, một khung raw 800×420 | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|
| shadow + blur (as animated) | 73.2 | 74.5 | 145 | 18.8 | 35.9 |
| shadow only | 2.60 | 2.77 | 4.73 | 5.55 | 8.72 |
| blur only | 66.1 | 66.8 | 124 | 3.96 | 7.60 |
| neither | 1.46 | 1.92 | 1.76 | 1.52 | 2.22 |

Median ms, các biến thể chạy xen kẽ (40 lần cho khung rỗng, ít hơn cho cảnh). Khung rỗng không vẽ gì, nên thời gian của nó là chi phí theo điểm ảnh mà khung nào cũng trả (xoá canvas, đổi alpha, chép kết quả ra) cộng, với PNG, việc mã hoá một ảnh phẳng. Cảnh là cảnh của animation trong phép đo event loop: 12 hình tròn 60×60 xoay, có `box-shadow: 0 8px 30px` và `filter: blur(2px)`.
<!-- /native-bench:diagnose -->

### Định dạng và bộ mã hoá

<!-- native-bench:formats -->
| Fixture | Định dạng | bm-native sync | bm-native async | bm-wasm sync | takumi-native async | takumi-wasm |
|:--|--:|--:|--:|--:|--:|--:|
| `lingrad-angles` | raw | 4.43 ms · 2 953 KiB | 7.89 ms · 2 953 KiB | 6.75 ms · 2 953 KiB | 9.07 ms · 2 953 KiB | 11.4 ms · 2 953 KiB |
| `lingrad-angles` | png | 10.7 ms · 32.6 KiB | 11.1 ms · 32.6 KiB | 16.5 ms · 32.6 KiB | 12.3 ms · 102 KiB | 58.1 ms · 102 KiB |
| `lingrad-angles` | jpeg | 18.9 ms · 52.2 KiB | 17.7 ms · 52.2 KiB | 33.7 ms · 52.2 KiB | 27.9 ms · 52.3 KiB | 42.0 ms · 52.3 KiB |
| `lingrad-angles` | webp | 11.6 ms · 28.9 KiB | 10.9 ms · 28.9 KiB | 16.9 ms · 28.9 KiB | 168 ms · 22.8 KiB | 25.9 ms · 169 KiB |
| `img-photo-bg` | raw | 2.53 ms · 2 953 KiB | 3.59 ms · 2 953 KiB | 3.01 ms · 2 953 KiB | 5.69 ms · 2 953 KiB | 10.4 ms · 2 953 KiB |
| `img-photo-bg` | png | 39.0 ms · 511 KiB | 38.8 ms · 511 KiB | 52.2 ms · 511 KiB | 17.6 ms · 513 KiB | 76.6 ms · 513 KiB |
| `img-photo-bg` | jpeg | 14.5 ms · 55.1 KiB | 15.5 ms · 55.1 KiB | 24.4 ms · 55.1 KiB | 23.7 ms · 55.2 KiB | 38.1 ms · 55.2 KiB |
| `img-photo-bg` | webp | 16.6 ms · 367 KiB | 16.2 ms · 367 KiB | 27.1 ms · 367 KiB | 219 ms · 414 KiB | 26.6 ms · 470 KiB |
| `card-flat-ui` | raw | 4.47 ms · 2 953 KiB | 4.51 ms · 2 953 KiB | 6.29 ms · 2 953 KiB | 5.31 ms · 2 953 KiB | 8.98 ms · 2 953 KiB |
| `card-flat-ui` | png | 8.26 ms · 23.1 KiB | 8.80 ms · 23.1 KiB | 12.3 ms · 23.1 KiB | 9.57 ms · 25.3 KiB | 28.1 ms · 25.3 KiB |
| `card-flat-ui` | jpeg | 19.0 ms · 48.9 KiB | 19.5 ms · 48.9 KiB | 33.5 ms · 48.9 KiB | 29.1 ms · 49.0 KiB | 42.1 ms · 49.0 KiB |
| `card-flat-ui` | webp | 7.48 ms · 18.5 KiB | 9.30 ms · 18.5 KiB | 13.1 ms · 18.5 KiB | 22.2 ms · 13.4 KiB | 18.3 ms · 27.6 KiB |

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
| bm-engine | 0.1.0, git `987ef16d8d` (native, 5 file đang sửa) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 2 010 KiB, Zig 0.17.1, ReleaseFast, sha256 `0da5c5eda3b0` |
| bm-wasm | `js/bm_engine.wasm` (profile full), 1 100 KiB, sha256 `1bf382cb6985` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Lần chạy | 2026-11-12 08:36 UTC, chế độ full, 200 fixtures, 17.5 min; CPU bận trước khi chạy: 97.2 % |
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
