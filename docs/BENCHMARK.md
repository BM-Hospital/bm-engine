# bm-engine (Zig) so với takumi 2.20.0 — benchmark và kiểm tra tương đương

> **Giai đoạn 4 (2026-11-12)** — addon native cho Node.js: bm-native, bm-wasm, takumi-native và takumi-wasm đo cùng lúc; ở ngay dưới, mọi bảng sinh từ [results-native.json](results-native.json).
> **Giai đoạn 3 (2026-11-12)** — số liệu cuối cùng của 0.1.0 (bản wasm) ở sau đó; giai đoạn 2 được giữ làm lịch sử (số của giai đoạn 2 được ghi rõ). Báo cáo giai đoạn 1 được giữ nguyên ở cuối file để đối chiếu.
> Số liệu từng fixture: [RESULTS_FULL.md](RESULTS_FULL.md), [results.json](results.json). Ảnh: `bench/out/<id>/`.

## Giai đoạn 4 — native Node.js

Bốn engine trên cùng một máy, cùng Node, cùng 200 fixture, cùng font, cùng ảnh, cùng kích thước đầu ra:
**bm-native** (addon Node-API của bm-engine, `native/dist/win32-x64-msvc`), **bm-wasm** (bản wasm profile `full`),
**takumi-native** (`@takumi-rs/core`) và **takumi-wasm** (`@takumi-rs/wasm`). Mọi bảng trong phần này được sinh từ
`docs/results-native.json` bởi `node bench/run-native.mjs` (giữa các comment `native-bench`); không con số nào được gõ tay.
Trang tóm tắt bằng tiếng Anh và tiếng Việt: [en/native-vs-wasm.md](en/native-vs-wasm.md), [vi/native-vs-wasm.md](vi/native-vs-wasm.md).

### Điều kiện đo

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

### Tóm tắt

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

### Phương pháp

- **API và tính công bằng.** bm có `renderSync` (thread gọi) và `render` (bản native: thread pool libuv; bản wasm:
  cùng công việc trên main thread). takumi-native chỉ có `render` async (một `AsyncTask` của napi-rs trên pool libuv,
  bên trong dùng thread pool rayon riêng cho một phần công việc). takumi-wasm được gọi qua `render` công khai (wrapper
  async, mỗi lần gọi chạy thêm bước `needs` rồi render trên main thread). Vì vậy có năm biến thể: bm-native sync,
  bm-native async, bm-wasm sync, takumi-native async, takumi-wasm; phép so "cùng kiểu API" với takumi-native là
  bm-native **async**.
- **Tuỳ chọn giống hệt nhau:** `devicePixelRatio: 1`, cùng `width`/`height`, cùng `images` và `css` từng fixture
  (`bench/lib/pipeline.mjs` `renderOpts`), JPEG quality 85, WebP không có `quality` (lossless ở mọi engine). Font
  (9 file TTF) được đăng ký trước mọi phép đo, một renderer cho mỗi bộ font, cho mỗi engine.
- **PNG:** không engine nào cho chỉnh mức nén. bm dùng bộ deflate riêng (mức mặc định duy nhất); takumi dùng `png` +
  `zlib-rs`, thử trên mẫu 1/32 số hàng giữa level 7 / không lọc và level 3 / lọc thích ứng rồi chọn cái nhỏ hơn, nén
  thành nhiều đoạn — song song trên bản native. Không thể đặt hai bên về cùng một mức, nên thời gian PNG luôn được
  ghi kèm dung lượng file.
- **Đo thời gian:** mỗi fixture, mỗi định dạng (raw, png; thêm jpeg và webp cho 3 fixture): 3 lần khởi động mỗi biến
  thể, sau đó các vòng mà trong mỗi vòng mọi biến thể render một lần theo thứ tự xoay vòng (A,B,C,D,E rồi B,C,D,E,A…),
  tối thiểu 15 vòng và 150 ms, tối đa 2.5 s. Ghi median, p95, min, số byte đầu ra, và thời gian CPU của tiến trình
  trong các lời gọi (để thấy một lần render dùng bao nhiêu lõi).
- **Ba lượt** toàn bộ bộ fixture, mỗi lượt là một tiến trình mới, ở ba thời điểm khác nhau (xen giữa các giai đoạn
  đo khác). Số của từng fixture = median của ba median; geomean tính trên các fixture mà cả năm biến thể đều đo được;
  "±" = nửa khoảng chênh giữa geomean của ba lượt so với median; ⚠ khi khoảng chênh vượt 10 %.
- **Tải hệ thống:** trước và trong mỗi giai đoạn, `os.cpus()` được lấy mẫu mỗi giây; "tiến trình khác" = lõi-giây
  bận của cả máy trừ thời gian CPU của chính benchmark. Các agent khác build/test trên cùng máy trong lúc đo, nên số
  tuyệt đối có nhiễu; tỉ lệ giữa các engine (đo xen kẽ trong cùng fixture) ổn định hơn số tuyệt đối.
- **Cold start:** spawn `node` → import engine như người dùng (`bm-engine` = `js/node.mjs`, wasm qua
  `BM_ENGINE_BACKEND=wasm`; `@takumi-rs/core`; `@takumi-rs/wasm` + `initSync`) → đăng ký Inter Regular → PNG og card
  1200×630 → thoát; ≥ 30 lần mỗi engine, xen kẽ; trừ median của một tiến trình Node rỗng đọc cùng file.
- **Bộ nhớ:** một tiến trình mỗi engine, render cả bộ (raw + PNG) 10 lượt, đo sau GC cưỡng bức; RSS đỉnh của một PNG
  4000×4000 trong tiến trình riêng.
- **Event loop:** một `setInterval` 1 ms ghi khoảng cách giữa các lần chạy trong lúc một việc nặng chạy, với một chuỗi
  `setImmediate` để vòng lặp không ngủ (trên Windows, vòng lặp rảnh thức theo đồng hồ 15.6 ms).
- **Thông lượng:** og card PNG, N client vòng kín (N = 1, 2, 4, 8, 16), mỗi điểm 2 s sau khi khởi động; bm-native một
  renderer, K renderer (K = 1, 2, 4, 8) với `UV_THREADPOOL_SIZE` 4 (mặc định) và 8; takumi-native một renderer và
  K renderer; bm-wasm và takumi-wasm trong pool `worker_threads` K worker (công thức của
  `docs/examples/frameworks/lib/pool.mjs`).
- **Tương đương:** bộ so sánh có sẵn (`bench/lib/metrics.mjs`) cho raw RGBA của từng engine so với takumi-wasm; thêm so
  từng byte raw và PNG giữa hai bản build của mỗi engine; và `bench/native-identity.mjs` (bm-native == bm-wasm trên
  raw, PNG, JPEG, WebP, measure, SVG, animation, ICO, HTML, ảnh, WOFF2, lỗi).

### So với số đo takumi-native ở giai đoạn 1

<!-- native-bench:phase1 -->
<!-- /native-bench:phase1 -->

Giai đoạn 1 đo takumi-native một lần trên 78 fixture, bằng `await render()` từng engine một (không xen kẽ từng vòng),
với bản bm wasm của giai đoạn 1; cold start khi đó là thời gian trong tiến trình (init + font + PNG đầu tiên), không
gồm khởi động Node. Bộ fixture nay là 200 ca (thêm stylesheet, Tailwind, HTML, bảng, float, 42 ca animation, layout
inline…), nên geomean không so trực tiếp được với số cũ; cột "bỏ known-gaps" bỏ 9 ca vốn là khoảng trống của giai
đoạn 1.

### Thời gian render

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

Theo nhóm fixture:

<!-- native-bench:categories -->
| Nhóm | n | raw bm-n sync | raw bm-n async | raw bm-w | raw tk-n | raw tk-w | raw bm-n/tk-n | png bm-n sync | png bm-n async | png bm-w | png tk-n | png tk-w | png bm-n/tk-n |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| aa-exact | 2 | 0.53 | 0.62 | 0.72 | 0.81 | 1.19 | 0.77× | 0.99 | 0.98 | 1.44 | 1.62 | 2.73 | 0.61× |
| absolute | 3 | 1.29 | 1.86 | 1.52 | 1.20 | 1.90 | 1.54× | 2.62 | 2.51 | 3.64 | 3.59 | 9.30 | 0.70× |
| animation | 42 | 0.28 | 0.39 | 0.37 | 0.53 | 0.67 | 0.73× | 0.50 | 0.52 | 0.74 | 0.98 | 1.47 | 0.54× |
| backdrop-filter | 1 | 2.21 | 2.35 | 4.15 | 3.59 | 5.83 | 0.65× | 3.66 | 3.71 | 6.34 | 4.64 | 11.6 | 0.80× |
| bg-blend | 1 | 1.03 | 1.15 | 1.39 | 5.25 | 7.25 | 0.22× | 4.20 | 4.25 | 6.58 | 7.53 | 17.9 | 0.56× |
| bg-clip-text | 1 | 0.68 | 0.82 | 0.84 | 2.84 | 4.59 | 0.29× | 2.02 | 1.74 | 2.75 | 3.73 | 6.18 | 0.47× |
| blog-card | 2 | 6.05 | 6.48 | 8.91 | 7.05 | 14.3 | 0.92× | 13.5 | 14.6 | 21.3 | 12.2 | 40.1 | 1.19× |
| border-radius | 4 | 1.87 | 2.94 | 1.95 | 1.41 | 1.97 | 2.09× | 2.54 | 3.06 | 3.75 | 4.37 | 8.29 | 0.70× |
| borders | 3 | 1.54 | 2.18 | 1.81 | 1.44 | 2.25 | 1.52× | 2.72 | 2.62 | 3.76 | 3.75 | 7.45 | 0.70× |
| box-shadow | 4 | 3.33 | 3.94 | 5.47 | 5.90 | 9.60 | 0.67× | 7.20 | 7.18 | 11.6 | 7.99 | 26.3 | 0.90× |
| clip-path | 1 | 0.75 | 0.92 | 1.13 | 1.04 | 1.66 | 0.88× | 2.01 | 2.14 | 3.00 | 1.86 | 8.61 | 1.15× |
| colors | 5 | 1.40 | 1.99 | 1.67 | 1.65 | 2.68 | 1.20× | 1.71 | 1.65 | 2.57 | 3.34 | 6.58 | 0.49× |
| css-stylesheet | 4 | 1.49 | 2.19 | 1.80 | 1.56 | 2.24 | 1.40× | 2.15 | 2.22 | 3.09 | 3.91 | 7.99 | 0.57× |
| dashed-border | 1 | 1.36 | 1.50 | 2.40 | 2.33 | 4.23 | 0.64× | 1.70 | 1.75 | 2.79 | 3.06 | 5.63 | 0.57× |
| dotted-border | 1 | 1.60 | 1.69 | 2.59 | 2.58 | 4.73 | 0.66× | 1.61 | 1.59 | 2.95 | 3.17 | 4.38 | 0.50× |
| double-3d-border | 1 | 0.59 | 0.69 | 0.93 | 0.80 | 1.20 | 0.86× | 0.77 | 0.73 | 1.23 | 1.35 | 2.11 | 0.54× |
| drop-shadow | 1 | 1.26 | 1.33 | 1.98 | 1.70 | 2.55 | 0.78× | 3.48 | 3.46 | 5.38 | 2.69 | 12.3 | 1.28× |
| filter | 1 | 1.10 | 1.20 | 2.12 | 1.78 | 3.00 | 0.68× | 2.73 | 2.90 | 4.75 | 2.71 | 7.95 | 1.07× |
| flex | 5 | 1.46 | 2.09 | 1.76 | 1.26 | 1.92 | 1.66× | 2.15 | 2.01 | 3.08 | 3.29 | 7.39 | 0.61× |
| float | 4 | 0.60 | 1.05 | 0.76 | 1.09 | 1.22 | 0.96× | 1.30 | 1.55 | 1.97 | 2.51 | 4.92 | 0.62× |
| float-text | 7 | 0.87 | 1.01 | 1.15 | 1.16 | 1.74 | 0.87× | 1.72 | 1.74 | 2.48 | 2.15 | 4.43 | 0.81× |
| fonts | 2 | 2.47 | 3.36 | 2.52 | 2.72 | 4.29 | 1.23× | 5.34 | 5.42 | 7.55 | 6.10 | 14.5 | 0.89× |
| grid | 4 | 1.62 | 2.19 | 2.04 | 1.84 | 2.67 | 1.19× | 2.60 | 2.52 | 3.63 | 3.98 | 8.52 | 0.63× |
| grid-areas | 3 | 0.67 | 0.81 | 0.90 | 0.92 | 1.34 | 0.88× | 1.04 | 1.04 | 1.63 | 2.10 | 3.50 | 0.50× |
| html | 4 | 1.45 | 2.02 | 1.66 | 1.95 | 2.52 | 1.03× | 2.67 | 2.79 | 3.67 | 3.93 | 8.05 | 0.71× |
| images | 5 | 1.92 | 2.67 | 2.97 | 4.68 | 7.44 | 0.57× | 16.0 | 15.7 | 22.9 | 10.3 | 42.9 | 1.53× |
| inline-block | 4 | 0.57 | 0.77 | 0.70 | 0.99 | 1.18 | 0.78× | 1.05 | 1.07 | 1.57 | 1.66 | 3.02 | 0.65× |
| inline-box | 1 | 2.22 | 2.34 | 3.41 | 3.00 | 4.68 | 0.78× | 3.88 | 3.82 | 5.93 | 4.18 | 8.73 | 0.91× |
| inline-box-model | 4 | 1.17 | 1.27 | 1.72 | 1.67 | 2.40 | 0.76× | 2.23 | 2.24 | 3.40 | 2.74 | 5.71 | 0.82× |
| inline-flow | 5 | 0.73 | 0.83 | 1.14 | 1.17 | 1.66 | 0.71× | 1.59 | 1.60 | 2.40 | 2.07 | 4.39 | 0.77× |
| known-gaps | 9 | 0.46 | 0.55 | 0.59 | 0.75 | 1.12 | 0.74× | 0.89 | 0.90 | 1.35 | 1.59 | 3.37 | 0.57× |
| linear-gradient | 4 | 2.64 | 3.73 | 4.06 | 4.69 | 6.80 | 0.80× | 6.88 | 7.03 | 10.5 | 6.95 | 28.0 | 1.01× |
| mask | 1 | 1.31 | 1.36 | 2.04 | 1.70 | 2.69 | 0.80× | 2.33 | 2.34 | 3.53 | 2.53 | 10.2 | 0.93× |
| mix-blend | 1 | 1.35 | 1.48 | 2.18 | 1.80 | 3.05 | 0.83× | 4.13 | 4.15 | 6.53 | 2.85 | 12.0 | 1.46× |
| mixed-border | 1 | 0.85 | 0.91 | 1.35 | 1.08 | 1.98 | 0.84× | 1.15 | 1.20 | 1.82 | 1.82 | 3.38 | 0.66× |
| og-card | 2 | 2.78 | 3.22 | 4.00 | 4.31 | 6.39 | 0.75× | 9.18 | 9.43 | 13.3 | 7.17 | 19.4 | 1.31× |
| opacity | 4 | 2.28 | 2.78 | 3.98 | 3.90 | 8.41 | 0.71× | 3.41 | 3.45 | 5.47 | 5.49 | 14.6 | 0.63× |
| outline | 1 | 0.95 | 1.03 | 1.47 | 1.58 | 2.88 | 0.65× | 1.28 | 1.21 | 1.98 | 2.33 | 4.39 | 0.52× |
| overflow | 3 | 1.42 | 1.86 | 1.69 | 1.78 | 2.75 | 1.04× | 2.24 | 2.18 | 3.18 | 3.84 | 9.03 | 0.57× |
| pseudo-elements | 4 | 0.84 | 1.13 | 0.95 | 1.07 | 1.52 | 1.05× | 1.20 | 1.23 | 1.73 | 2.45 | 4.25 | 0.50× |
| radial-gradient | 3 | 2.22 | 2.87 | 3.10 | 5.66 | 7.84 | 0.51× | 13.0 | 13.0 | 18.3 | 10.6 | 40.4 | 1.23× |
| sizing | 5 | 1.41 | 2.06 | 1.38 | 1.13 | 1.65 | 1.83× | 2.41 | 2.47 | 3.65 | 3.70 | 7.88 | 0.67× |
| stress | 3 | 13.2 | 15.5 | 18.1 | 17.2 | 24.9 | 0.90× | 23.9 | 24.0 | 34.9 | 25.5 | 57.5 | 0.94× |
| svg-image | 1 | 1.34 | 1.43 | 2.67 | 0.98 | 1.67 | 1.47× | 1.81 | 1.80 | 3.30 | 2.01 | 4.07 | 0.89× |
| table | 8 | 0.92 | 1.13 | 1.30 | 1.57 | 2.26 | 0.72× | 1.45 | 1.50 | 2.23 | 2.54 | 4.44 | 0.59× |
| tailwind | 4 | 1.78 | 2.49 | 2.21 | 1.83 | 2.65 | 1.36× | 2.35 | 2.31 | 3.50 | 4.19 | 8.27 | 0.55× |
| text-decoration | 1 | 1.90 | 1.94 | 2.70 | 1.78 | 2.74 | 1.09× | 2.81 | 2.91 | 4.43 | 2.72 | 5.55 | 1.07× |
| text-i18n | 2 | 2.19 | 3.09 | 2.39 | 2.35 | 3.56 | 1.31× | 4.22 | 4.47 | 6.10 | 4.97 | 12.3 | 0.90× |
| text-paragraph | 5 | 2.09 | 2.68 | 2.44 | 2.41 | 3.80 | 1.11× | 3.98 | 4.04 | 5.71 | 5.08 | 11.5 | 0.80× |
| text-shadow | 1 | 1.03 | 1.26 | 1.76 | 1.21 | 1.82 | 1.04× | 3.75 | 3.86 | 6.03 | 2.53 | 6.98 | 1.52× |
| text-single-line | 3 | 1.31 | 1.87 | 1.41 | 1.62 | 2.34 | 1.15× | 2.47 | 2.56 | 3.48 | 3.54 | 7.79 | 0.72× |
| text-stroke | 1 | 1.26 | 1.37 | 1.96 | 1.01 | 1.45 | 1.35× | 1.90 | 1.82 | 2.87 | 1.71 | 3.32 | 1.06× |
| text-truncation | 3 | 1.30 | 1.85 | 1.51 | 1.65 | 2.44 | 1.12× | 1.93 | 1.86 | 2.56 | 3.07 | 6.66 | 0.61× |
| transform | 3 | 1.74 | 2.21 | 2.40 | 2.72 | 4.57 | 0.81× | 2.67 | 2.62 | 4.00 | 4.56 | 9.73 | 0.58× |
| visibility | 1 | 0.29 | 0.41 | 0.37 | 0.50 | 0.66 | 0.83× | 0.61 | 0.57 | 1.00 | 1.23 | 2.01 | 0.46× |

Geomean ms theo nhóm fixture. bm-n = bm-native, bm-w = bm-wasm (sync), tk-n = takumi-native (async), tk-w = takumi-wasm; tỉ lệ = bm-native async / takumi-native async (dưới 1× = bm nhanh hơn).
<!-- /native-bench:categories -->

bm-native so với takumi-native (cùng async):

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

#### bm-native thua ở đâu, và vì sao

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

### Tương đương và trùng byte

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

### Cold start

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

### Bộ nhớ

<!-- native-bench:memory -->
| Engine | RSS sau khởi tạo | RSS sau lượt 1 → 10 | bộ nhớ engine 1 → N | JS heap 1 → N | RSS đỉnh, cả bộ | RSS đỉnh PNG 4000×4000 (tăng thêm) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 65.6 | 91.9 → 93.4 | 28.2 → 28.2 | 7.20 → 6.20 | 218 | 146 (85.8) |
| bm-wasm | 67.0 | 126 → 126 | 60.4 → 60.4 | 7.40 → 6.40 | 223 | 149 (87.6) |
| takumi-native | 67.5 | 147 → 160 | — → — | 7.40 → 6.40 | 190 | 137 (74.9) |
| takumi-wasm | 73.1 | 132 → 161 | 67.2 → 67.2 | 7.10 → 7.20 | 224 | 151 (82.9) |

MiB, sau khi ép GC. Một tiến trình cho mỗi engine; mỗi lượt render mọi fixture ra raw và PNG (API async), một renderer cho mỗi bộ font. Bộ nhớ engine: bm-native = số byte addon đang cấp phát (`memoryBytes()`), bm-wasm / takumi-wasm = bộ nhớ tuyến tính wasm, takumi-native = không công bố. Node rỗng: 48.2 MiB RSS. "Tăng thêm" = RSS đỉnh trừ RSS ngay trước lần render 4000×4000.
<!-- /native-bench:memory -->

### Event loop

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

### Nhiễu

<!-- native-bench:noise -->
| Giai đoạn | bắt đầu (UTC) | thời lượng | CPU bận ngay trước | CPU bận trong lúc đo | tiến trình khác, lõi |
|:--|--:|--:|--:|--:|--:|
| speed lượt 1 | 08:36 | 191 s | 97.1 % | 93.7 % (max 100 %) | 6.53 |
| speed lượt 2 | 08:41 | 173 s | 73.7 % | 87.2 % (max 100 %) | 5.92 |
| speed lượt 3 | 08:46 | 177 s | 60.7 % | 83.0 % (max 100 %) | 5.67 |
| cold |  | 23.1 s |  | 82.7 % (max 98.9 %) | 5.24 |
| memory |  | 76.7 s |  | 85.8 % (max 100 %) | 5.78 |
| eventloop |  | 42.9 s |  | 80.8 % (max 97.2 %) | 5.40 |
| throughput |  | 293.3 s |  | 98.4 % (max 100 %) | 6.17 |

"Tiến trình khác" = số lõi-giây bận của cả máy trừ thời gian CPU của chính benchmark, chia cho thời gian thực (8 CPU logic). Số fixture có median lệch quá 10 % giữa các lượt: bm-native:sync raw: 180, bm-native:sync png: 173, bm-native:async raw: 188, bm-native:async png: 176, bm-wasm:sync raw: 160, bm-wasm:sync png: 163, takumi-native:async raw: 175, takumi-native:async png: 169, takumi-wasm:async raw: 170, takumi-wasm:async png: 170. 20 geomean tuyệt đối (biến thể × định dạng) lệch quá 10 % giữa các lượt (khoảng lệch lớn nhất: 40.1 %), vì vậy các bảng ưu tiên tỉ lệ đo trong từng lượt. Tỉ lệ giữa engine lệch quá 10 %: ratio bm-native:async/takumi-native:async webp: range between passes 15.6 %; ratio bm-native:sync/takumi-native:async raw: range between passes 15.1 %; ratio bm-native:sync/takumi-native:async png: range between passes 12.2 %; ratio bm-native:sync/takumi-native:async webp: range between passes 13.9 %; ratio bm-native:sync/bm-wasm:sync webp: range between passes 16.1 %; ratio takumi-native:async/takumi-wasm:async raw: range between passes 17.9 %; ratio takumi-native:async/takumi-wasm:async png: range between passes 11.6 %.
<!-- /native-bench:noise -->

### Chạy lại

```sh
node bench/run-native.mjs                 # đầy đủ: 3 lượt speed, 30 cold start, 10 lượt bộ nhớ, ...
node bench/run-native.mjs --quick         # chạy thử ngắn (1 lượt, ngân sách nhỏ)
node bench/run-native.mjs --stages=cold,eventloop   # chỉ đo lại vài giai đoạn; phần còn lại giữ từ JSON
node bench/native/report.mjs              # chỉ sinh lại Markdown và bảng trong docs từ JSON
```

### Từng fixture

<!-- native-bench:per-fixture -->
| Fixture | Nhóm | raw bm-n sync | raw bm-n async | raw bm-w | raw tk-n | raw tk-w | raw bm-n/tk-n | raw bm-n/bm-w | png bm-n sync | png bm-n async | png bm-w | png tk-n | png tk-w | png bm-n/tk-n | png bm-n/bm-w |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| `colors-solid-bg` | colors | 0.36 / 0.47 | 0.57 / 2.58 | 0.40 / 0.53 | 0.49 / 1.37 | 0.72 / 1.46 | 1.16× | 0.90× | 0.59 / 0.91 | 0.57 / 0.82 | 0.86 / 1.16 | 1.39 / 2.49 | 2.25 / 2.91 | 0.41× | 0.68× |
| `colors-hex` | colors | 3.38 / 5.26 | 5.31 / 8.33 | 4.26 / 6.03 | 3.92 / 5.81 | 6.94 / 11.4 | 1.35× | 0.79× | 3.47 / 4.32 | 3.22 / 4.20 | 5.17 / 6.04 | 6.49 / 7.96 | 13.7 / 17.1 | 0.50× | 0.67× |
| `colors-functional` | colors | 2.66 / 3.25 | 3.77 / 5.50 | 3.15 / 3.60 | 2.65 / 4.06 | 4.76 / 6.47 | 1.42× | 0.84× | 3.24 / 3.50 | 3.06 / 3.93 | 4.93 / 5.46 | 5.68 / 6.05 | 12.4 / 13.7 | 0.54× | 0.66× |
| `colors-named` | colors | 2.58 / 3.14 | 3.58 / 4.62 | 3.24 / 3.74 | 2.70 / 3.70 | 4.71 / 5.47 | 1.33× | 0.80× | 3.09 / 3.58 | 3.15 / 3.50 | 4.50 / 5.45 | 5.84 / 6.54 | 13.0 / 14.1 | 0.54× | 0.69× |
| `colors-transparent-canvas` | colors | 0.63 / 1.41 | 0.76 / 2.85 | 0.75 / 0.88 | 0.89 / 4.49 | 1.24 / 3.51 | 0.86× | 0.85× | 0.71 / 0.76 | 0.68 / 0.80 | 1.13 / 1.26 | 1.39 / 1.57 | 2.49 / 2.75 | 0.49× | 0.63× |
| `flex-row-column` | flex | 2.19 / 3.19 | 2.89 / 3.61 | 2.41 / 2.98 | 1.38 / 2.63 | 2.22 / 3.45 | 2.09× | 0.91× | 2.66 / 3.39 | 2.25 / 3.25 | 3.35 / 4.53 | 4.39 / 4.91 | 10.6 / 12.7 | 0.51× | 0.79× |
| `flex-justify-align` | flex | 2.29 / 2.88 | 3.51 / 4.84 | 2.71 / 3.31 | 1.84 / 2.66 | 3.06 / 5.85 | 1.91× | 0.84× | 2.81 / 3.12 | 2.72 / 2.95 | 3.55 / 5.00 | 3.95 / 4.32 | 10.6 / 11.6 | 0.69× | 0.79× |
| `flex-wrap-gap` | flex | 2.51 / 3.18 | 3.38 / 4.40 | 3.48 / 3.82 | 1.87 / 2.20 | 2.87 / 3.26 | 1.81× | 0.72× | 3.62 / 4.30 | 3.41 / 4.32 | 5.78 / 6.38 | 4.72 / 5.78 | 11.6 / 13.8 | 0.72× | 0.63× |
| `flex-grow-shrink-basis` | flex | 1.74 / 2.34 | 2.79 / 4.99 | 2.02 / 3.76 | 1.42 / 2.23 | 2.02 / 2.60 | 1.96× | 0.86× | 3.51 / 4.27 | 3.17 / 4.85 | 5.25 / 6.15 | 3.96 / 4.49 | 8.93 / 11.8 | 0.80× | 0.67× |
| `flex-nested-small` | flex | 0.30 / 0.47 | 0.42 / 1.91 | 0.36 / 0.58 | 0.46 / 0.72 | 0.67 / 0.86 | 0.90× | 0.83× | 0.49 / 0.59 | 0.50 / 0.58 | 0.77 / 0.93 | 1.19 / 1.25 | 1.89 / 2.13 | 0.42× | 0.63× |
| `sizing-percent` | sizing | 1.85 / 2.48 | 2.60 / 3.93 | 1.88 / 2.59 | 1.48 / 2.34 | 2.20 / 3.34 | 1.75× | 0.98× | 4.22 / 5.54 | 4.53 / 6.34 | 6.11 / 8.51 | 5.45 / 7.63 | 12.8 / 18.5 | 0.83× | 0.69× |
| `sizing-minmax` | sizing | 2.01 / 2.99 | 2.65 / 3.74 | 1.73 / 2.37 | 1.26 / 4.66 | 2.04 / 4.91 | 2.10× | 1.16× | 4.10 / 4.91 | 3.84 / 4.29 | 5.67 / 7.88 | 5.86 / 8.44 | 11.5 / 14.1 | 0.65× | 0.72× |
| `sizing-aspect-ratio` | sizing | 2.32 / 4.00 | 3.98 / 10.5 | 2.26 / 3.69 | 1.71 / 3.74 | 2.43 / 3.79 | 2.34× | 1.03× | 2.46 / 4.51 | 2.80 / 6.99 | 3.74 / 4.80 | 5.11 / 7.43 | 12.0 / 18.8 | 0.55× | 0.66× |
| `sizing-padding-margin` | sizing | 1.89 / 2.47 | 2.78 / 4.50 | 2.02 / 2.46 | 1.46 / 2.64 | 2.04 / 2.42 | 1.91× | 0.93× | 3.29 / 4.27 | 3.46 / 4.18 | 5.56 / 6.73 | 4.56 / 4.95 | 10.6 / 11.9 | 0.76× | 0.59× |
| `sizing-auto-margin-center` | sizing | 0.34 / 0.45 | 0.49 / 0.88 | 0.33 / 0.44 | 0.39 / 0.50 | 0.56 / 0.66 | 1.25× | 1.04× | 0.58 / 0.67 | 0.54 / 0.65 | 0.90 / 1.04 | 0.93 / 1.07 | 1.63 / 1.77 | 0.59× | 0.64× |
| `abs-inset` | absolute | 1.66 / 2.18 | 2.76 / 4.29 | 1.98 / 2.71 | 1.48 / 2.92 | 2.85 / 3.84 | 1.87× | 0.84× | 4.34 / 5.36 | 3.83 / 7.29 | 5.32 / 8.06 | 4.96 / 6.08 | 14.0 / 17.2 | 0.77× | 0.82× |
| `abs-zorder` | absolute | 3.09 / 6.92 | 4.04 / 5.29 | 3.77 / 4.82 | 2.02 / 3.03 | 2.84 / 3.35 | 2.00× | 0.82× | 6.61 / 7.50 | 6.93 / 7.41 | 9.83 / 10.8 | 6.02 / 7.03 | 23.1 / 28.4 | 1.15× | 0.67× |
| `abs-in-flow` | absolute | 0.42 / 0.54 | 0.58 / 0.81 | 0.47 / 0.62 | 0.59 / 0.72 | 0.85 / 1.02 | 0.98× | 0.90× | 0.63 / 0.69 | 0.59 / 0.76 | 0.92 / 0.98 | 1.54 / 1.69 | 2.48 / 2.75 | 0.39× | 0.68× |
| `borders-uniform` | borders | 2.01 / 3.17 | 3.24 / 5.05 | 2.05 / 2.40 | 1.85 / 2.52 | 2.83 / 3.10 | 1.75× | 0.98× | 3.71 / 4.12 | 3.77 / 4.00 | 5.63 / 6.07 | 4.54 / 4.93 | 9.93 / 10.9 | 0.83× | 0.66× |
| `borders-per-side` | borders | 1.85 / 2.85 | 2.62 / 6.40 | 2.02 / 2.49 | 1.69 / 3.20 | 2.44 / 3.40 | 1.55× | 0.91× | 3.89 / 5.30 | 3.62 / 5.55 | 4.37 / 6.09 | 4.93 / 8.32 | 11.6 / 17.2 | 0.73× | 0.89× |
| `borders-with-radius` | borders | 0.99 / 4.75 | 1.23 / 3.47 | 1.42 / 3.03 | 0.95 / 3.80 | 1.65 / 2.35 | 1.29× | 0.70× | 1.39 / 2.77 | 1.32 / 2.43 | 2.16 / 3.02 | 2.36 / 5.33 | 3.58 / 5.84 | 0.56× | 0.64× |
| `radius-uniform-percorner` | border-radius | 3.13 / 5.56 | 4.88 / 9.10 | 3.04 / 3.76 | 1.75 / 3.30 | 2.84 / 4.47 | 2.78× | 1.03× | 4.38 / 6.32 | 5.46 / 8.31 | 7.22 / 9.74 | 6.37 / 12.1 | 15.6 / 23.1 | 0.86× | 0.61× |
| `radius-elliptical` | border-radius | 2.79 / 3.83 | 4.14 / 6.38 | 3.07 / 4.43 | 1.85 / 2.56 | 2.63 / 5.13 | 2.24× | 0.91× | 3.97 / 7.74 | 3.92 / 8.14 | 5.28 / 12.7 | 5.38 / 13.0 | 13.0 / 24.4 | 0.73× | 0.75× |
| `radius-pill-circle` | border-radius | 2.76 / 5.05 | 4.99 / 7.75 | 2.80 / 4.14 | 2.16 / 7.07 | 2.85 / 4.51 | 2.31× | 0.99× | 3.49 / 15.2 | 5.60 / 10.9 | 5.63 / 19.3 | 8.41 / 13.9 | 12.2 / 22.6 | 0.67× | 0.62× |
| `radius-small` | border-radius | 0.50 / 1.38 | 0.74 / 3.35 | 0.55 / 0.74 | 0.56 / 2.74 | 0.71 / 1.30 | 1.33× | 0.92× | 0.69 / 2.28 | 0.74 / 6.42 | 0.92 / 1.48 | 1.26 / 3.06 | 1.92 / 3.69 | 0.58× | 0.75× |
| `lingrad-angles` | linear-gradient | 4.43 / 5.13 | 7.89 / 10.8 | 6.75 / 10.3 | 9.07 / 13.7 | 11.4 / 15.8 | 0.87× | 0.66× | 10.7 / 11.7 | 11.1 / 15.8 | 16.5 / 18.6 | 12.3 / 15.0 | 58.1 / 65.5 | 0.91× | 0.65× |
| `lingrad-multistop` | linear-gradient | 3.65 / 5.60 | 5.64 / 8.04 | 6.14 / 10.7 | 8.80 / 14.5 | 11.6 / 21.0 | 0.64× | 0.59× | 10.4 / 11.6 | 10.7 / 12.9 | 16.1 / 17.7 | 9.71 / 12.8 | 39.5 / 45.8 | 1.10× | 0.65× |
| `lingrad-alpha` | linear-gradient | 5.50 / 5.89 | 6.40 / 7.05 | 8.46 / 9.68 | 7.00 / 9.04 | 12.9 / 16.8 | 0.91× | 0.65× | 9.53 / 9.85 | 9.75 / 10.2 | 15.2 / 16.1 | 9.89 / 13.6 | 50.0 / 62.4 | 0.99× | 0.63× |
| `lingrad-hero-small` | linear-gradient | 0.55 / 0.70 | 0.68 / 0.90 | 0.77 / 0.89 | 0.86 / 1.39 | 1.26 / 1.44 | 0.79× | 0.71× | 2.10 / 2.19 | 2.11 / 2.18 | 2.97 / 3.13 | 1.97 / 2.65 | 5.38 / 5.75 | 1.07× | 0.71× |
| `radial-shapes` | radial-gradient | 3.48 / 4.12 | 4.56 / 5.56 | 5.33 / 6.56 | 8.75 / 12.1 | 12.4 / 13.7 | 0.52× | 0.65× | 18.9 / 20.6 | 18.9 / 20.6 | 27.1 / 31.4 | 14.8 / 16.9 | 60.7 / 70.2 | 1.28× | 0.70× |
| `radial-at-position` | radial-gradient | 4.18 / 5.12 | 5.41 / 10.5 | 6.57 / 7.75 | 10.3 / 14.2 | 15.5 / 19.5 | 0.53× | 0.64× | 18.0 / 19.1 | 17.8 / 20.2 | 25.4 / 27.2 | 16.0 / 18.0 | 59.9 / 71.6 | 1.11× | 0.71× |
| `radial-spotlight-small` | radial-gradient | 0.75 / 0.84 | 0.95 / 3.02 | 0.85 / 0.95 | 2.02 / 3.97 | 2.51 / 2.74 | 0.47× | 0.88× | 6.48 / 8.76 | 6.53 / 10.5 | 8.90 / 11.2 | 5.05 / 10.6 | 18.2 / 24.1 | 1.29× | 0.73× |
| `shadow-offset-blur` | box-shadow | 4.97 / 5.39 | 6.22 / 7.87 | 8.01 / 8.80 | 8.77 / 10.3 | 14.0 / 15.1 | 0.71× | 0.62× | 13.3 / 14.5 | 13.4 / 15.8 | 20.3 / 24.6 | 11.7 / 13.9 | 51.2 / 57.4 | 1.15× | 0.66× |
| `shadow-spread-multi` | box-shadow | 5.65 / 6.25 | 6.38 / 9.55 | 9.37 / 11.6 | 8.14 / 9.18 | 13.6 / 16.6 | 0.78× | 0.60× | 14.3 / 15.7 | 13.9 / 15.2 | 22.3 / 24.5 | 11.5 / 13.7 | 53.2 / 58.4 | 1.21× | 0.64× |
| `shadow-inset` | box-shadow | 5.41 / 6.08 | 6.48 / 8.91 | 9.19 / 11.4 | 11.1 / 13.2 | 18.6 / 23.9 | 0.58× | 0.59× | 13.4 / 17.4 | 13.1 / 16.8 | 21.8 / 28.3 | 14.4 / 18.6 | 51.0 / 90.0 | 0.91× | 0.61× |
| `shadow-small` | box-shadow | 0.81 / 1.02 | 0.94 / 1.71 | 1.30 / 1.43 | 1.52 / 2.06 | 2.41 / 4.33 | 0.61× | 0.63× | 1.05 / 1.21 | 1.09 / 1.38 | 1.83 / 2.28 | 2.11 / 2.34 | 3.44 / 4.18 | 0.52× | 0.57× |
| `opacity-basic` | opacity | 4.20 / 5.86 | 5.06 / 8.25 | 6.28 / 7.39 | 4.64 / 5.37 | 10.5 / 11.1 | 1.09× | 0.67× | 5.76 / 7.77 | 5.73 / 8.39 | 8.93 / 11.6 | 7.58 / 10.0 | 22.7 / 26.7 | 0.76× | 0.65× |
| `opacity-nested` | opacity | 2.96 / 3.77 | 4.86 / 6.04 | 4.36 / 5.93 | 6.21 / 8.28 | 15.8 / 18.7 | 0.78× | 0.68× | 4.21 / 4.82 | 4.33 / 5.41 | 6.13 / 7.90 | 9.19 / 12.4 | 23.7 / 35.5 | 0.47× | 0.69× |
| `opacity-with-radius-shadow` | opacity | 1.22 / 1.32 | 1.33 / 1.60 | 2.32 / 2.78 | 2.85 / 3.17 | 5.88 / 6.44 | 0.47× | 0.53× | 1.65 / 2.22 | 1.59 / 2.14 | 3.10 / 3.38 | 3.57 / 4.02 | 7.57 / 8.43 | 0.45× | 0.53× |
| `overflow-hidden-clip` | overflow | 1.91 / 2.11 | 2.76 / 5.13 | 2.12 / 3.43 | 2.42 / 3.00 | 3.84 / 4.86 | 1.14× | 0.90× | 2.67 / 3.39 | 2.63 / 3.84 | 3.74 / 4.75 | 5.28 / 6.49 | 11.7 / 13.9 | 0.50× | 0.71× |
| `overflow-radius-clip` | overflow | 3.05 / 4.04 | 3.77 / 5.82 | 3.62 / 4.88 | 3.69 / 6.53 | 5.66 / 8.05 | 1.02× | 0.84× | 6.08 / 6.66 | 5.75 / 6.59 | 7.67 / 9.60 | 6.51 / 7.16 | 22.7 / 26.4 | 0.88× | 0.79× |
| `overflow-nested` | overflow | 0.49 / 0.79 | 0.62 / 0.78 | 0.62 / 0.85 | 0.64 / 0.88 | 0.96 / 1.14 | 0.97× | 0.79× | 0.69 / 0.79 | 0.68 / 0.96 | 1.12 / 1.31 | 1.65 / 2.20 | 2.75 / 3.03 | 0.41× | 0.62× |
| `transform-basic` | transform | 2.50 / 2.93 | 3.29 / 4.30 | 2.95 / 3.23 | 3.62 / 3.94 | 6.26 / 6.87 | 0.91× | 0.84× | 3.98 / 5.87 | 3.98 / 4.35 | 5.75 / 7.52 | 6.75 / 8.68 | 15.8 / 20.2 | 0.59× | 0.69× |
| `transform-combined-origin` | transform | 2.41 / 3.04 | 3.38 / 3.85 | 2.99 / 3.59 | 3.47 / 3.83 | 5.68 / 6.17 | 0.97× | 0.81× | 3.56 / 4.12 | 3.53 / 5.18 | 5.19 / 6.63 | 6.20 / 7.53 | 14.3 / 17.5 | 0.57× | 0.69× |
| `transform-text-small` | transform | 0.88 / 1.01 | 0.97 / 1.28 | 1.58 / 1.71 | 1.60 / 1.81 | 2.68 / 3.09 | 0.61× | 0.56× | 1.34 / 1.57 | 1.28 / 1.59 | 2.15 / 2.81 | 2.26 / 2.92 | 4.06 / 4.65 | 0.57× | 0.63× |
| `text-single-sizes` | text-single-line | 2.10 / 2.56 | 3.11 / 3.80 | 2.19 / 2.88 | 2.16 / 3.05 | 3.28 / 4.45 | 1.44× | 0.96× | 3.65 / 4.34 | 3.71 / 4.76 | 5.22 / 5.70 | 4.80 / 5.34 | 12.0 / 13.0 | 0.77× | 0.70× |
| `text-single-colors-small` | text-single-line | 0.53 / 0.64 | 0.70 / 1.18 | 0.55 / 0.73 | 0.94 / 1.42 | 1.30 / 1.60 | 0.74× | 0.95× | 0.88 / 1.13 | 0.97 / 4.39 | 1.26 / 1.79 | 1.68 / 6.29 | 2.89 / 3.63 | 0.58× | 0.70× |
| `text-single-fonts` | text-single-line | 2.03 / 2.58 | 3.04 / 4.20 | 2.28 / 2.70 | 2.09 / 2.55 | 3.03 / 4.43 | 1.45× | 0.89× | 4.70 / 6.35 | 4.67 / 9.32 | 6.41 / 8.36 | 5.49 / 7.81 | 13.7 / 18.1 | 0.85× | 0.73× |
| `text-paragraph-wrap` | text-paragraph | 3.54 / 4.15 | 4.02 / 6.86 | 3.44 / 4.57 | 3.63 / 5.28 | 5.61 / 8.28 | 1.11× | 1.03× | 4.99 / 7.48 | 5.32 / 6.47 | 7.20 / 8.94 | 5.96 / 8.72 | 14.2 / 16.7 | 0.89× | 0.69× |
| `text-paragraph-lineheight` | text-paragraph | 2.82 / 3.94 | 4.00 / 5.67 | 3.64 / 4.09 | 3.43 / 3.60 | 5.63 / 7.01 | 1.17× | 0.77× | 5.83 / 7.31 | 5.71 / 7.31 | 7.75 / 11.1 | 6.65 / 13.3 | 15.0 / 20.7 | 0.86× | 0.75× |
| `text-paragraph-letterspacing` | text-paragraph | 3.32 / 3.96 | 4.11 / 4.99 | 3.89 / 4.51 | 3.78 / 5.57 | 6.24 / 6.82 | 1.09× | 0.85× | 6.40 / 6.98 | 6.43 / 9.29 | 9.10 / 10.9 | 6.84 / 9.21 | 16.4 / 17.3 | 0.94× | 0.70× |
| `text-paragraph-small` | text-paragraph | 0.59 / 0.67 | 0.70 / 0.85 | 0.69 / 0.84 | 0.88 / 1.05 | 1.26 / 1.50 | 0.80× | 0.86× | 1.27 / 1.56 | 1.26 / 3.23 | 1.81 / 2.86 | 2.22 / 4.99 | 3.22 / 5.91 | 0.57× | 0.70× |
| `text-long-wrap` | text-paragraph | 2.05 / 2.49 | 2.99 / 5.90 | 2.58 / 3.47 | 1.96 / 2.85 | 3.16 / 3.61 | 1.52× | 0.80× | 4.21 / 5.43 | 4.38 / 8.18 | 6.59 / 8.81 | 5.59 / 11.7 | 17.8 / 23.3 | 0.78× | 0.64× |
| `fonts-weights-italic` | fonts | 2.63 / 3.49 | 3.73 / 4.96 | 2.83 / 4.00 | 3.10 / 4.42 | 4.68 / 6.20 | 1.20× | 0.93× | 5.98 / 6.58 | 5.93 / 6.38 | 8.42 / 9.17 | 5.91 / 9.24 | 15.1 / 16.3 | 1.00× | 0.71× |
| `fonts-mixed-inline` | fonts | 2.32 / 4.33 | 3.02 / 5.03 | 2.25 / 2.67 | 2.40 / 2.94 | 3.93 / 6.67 | 1.26× | 1.03× | 4.77 / 6.48 | 4.96 / 8.89 | 6.78 / 8.30 | 6.30 / 8.22 | 13.8 / 17.3 | 0.79× | 0.70× |
| `text-vietnamese` | text-i18n | 2.22 / 2.99 | 3.31 / 4.41 | 2.49 / 3.59 | 2.47 / 3.20 | 3.76 / 5.35 | 1.34× | 0.89× | 4.03 / 4.96 | 4.49 / 4.90 | 6.24 / 7.23 | 4.95 / 5.26 | 12.5 / 13.6 | 0.91× | 0.65× |
| `text-accented-latin` | text-i18n | 2.15 / 3.92 | 2.87 / 4.81 | 2.30 / 3.07 | 2.24 / 2.86 | 3.37 / 3.79 | 1.28× | 0.93× | 4.43 / 4.71 | 4.45 / 5.20 | 5.97 / 7.53 | 4.98 / 6.57 | 12.2 / 15.2 | 0.89× | 0.74× |
| `text-ellipsis-nowrap` | text-truncation | 1.85 / 2.61 | 2.67 / 3.77 | 2.01 / 2.75 | 2.00 / 2.75 | 2.88 / 3.46 | 1.33× | 0.92× | 2.59 / 3.24 | 2.33 / 3.16 | 3.07 / 4.35 | 3.94 / 4.68 | 10.2 / 11.7 | 0.59× | 0.84× |
| `text-lineclamp` | text-truncation | 2.65 / 3.62 | 4.02 / 5.46 | 3.24 / 4.00 | 3.01 / 4.08 | 4.78 / 5.92 | 1.33× | 0.82× | 3.92 / 4.60 | 3.99 / 4.48 | 5.42 / 6.12 | 5.33 / 6.68 | 12.6 / 14.6 | 0.75× | 0.72× |
| `text-lineclamp-small` | text-truncation | 0.45 / 0.60 | 0.59 / 1.11 | 0.53 / 0.65 | 0.75 / 0.92 | 1.06 / 1.32 | 0.79× | 0.86× | 0.71 / 0.83 | 0.69 / 0.86 | 1.01 / 1.09 | 1.38 / 1.99 | 2.29 / 2.46 | 0.50× | 0.70× |
| `img-png-fit` | images | 2.85 / 3.20 | 3.96 / 4.99 | 4.28 / 4.57 | 6.01 / 6.52 | 9.73 / 13.8 | 0.66× | 0.67× | 17.8 / 23.3 | 17.7 / 23.1 | 25.2 / 36.5 | 12.0 / 20.7 | 55.9 / 70.9 | 1.47× | 0.71× |
| `img-jpeg-fit` | images | 2.49 / 3.30 | 3.54 / 5.03 | 3.90 / 5.03 | 15.3 / 19.6 | 26.2 / 32.9 | 0.23× | 0.64× | 26.9 / 30.3 | 26.1 / 29.6 | 38.0 / 42.8 | 24.9 / 29.2 | 77.1 / 91.3 | 1.05× | 0.71× |
| `img-intrinsic-size` | images | 0.33 / 0.53 | 0.45 / 1.45 | 0.65 / 0.78 | 0.60 / 1.52 | 0.87 / 1.20 | 0.76× | 0.52× | 2.73 / 2.92 | 2.72 / 3.00 | 4.25 / 4.64 | 1.62 / 1.95 | 8.75 / 9.69 | 1.68× | 0.64× |
| `img-radius-clip` | images | 4.31 / 5.24 | 5.96 / 6.58 | 7.18 / 7.97 | 7.17 / 7.87 | 9.98 / 12.8 | 0.83× | 0.60× | 20.8 / 25.4 | 19.3 / 23.3 | 29.8 / 33.8 | 13.3 / 15.2 | 50.3 / 58.3 | 1.46× | 0.70× |
| `img-photo-bg` | images | 2.53 / 3.03 | 3.59 / 5.37 | 3.01 / 3.63 | 5.69 / 7.62 | 10.4 / 12.6 | 0.63× | 0.84× | 39.0 / 43.3 | 38.8 / 42.9 | 52.2 / 59.0 | 17.6 / 18.2 | 76.6 / 85.1 | 2.21× | 0.75× |
| `grid-fixed-fr` | grid | 2.19 / 3.24 | 3.10 / 4.43 | 2.38 / 3.18 | 2.08 / 3.08 | 2.94 / 4.21 | 1.49× | 0.92× | 3.94 / 4.75 | 3.42 / 5.83 | 4.60 / 5.84 | 4.89 / 7.39 | 10.5 / 11.4 | 0.70× | 0.86× |
| `grid-repeat-gap` | grid | 2.42 / 3.01 | 3.21 / 3.94 | 3.17 / 3.46 | 2.54 / 3.29 | 3.59 / 4.76 | 1.26× | 0.76× | 3.39 / 4.36 | 3.73 / 4.52 | 5.25 / 6.24 | 5.44 / 6.29 | 13.5 / 19.0 | 0.69× | 0.65× |
| `grid-spans` | grid | 2.16 / 4.25 | 3.38 / 5.84 | 2.53 / 3.87 | 2.26 / 3.78 | 3.37 / 5.53 | 1.49× | 0.85× | 3.38 / 4.09 | 3.25 / 4.18 | 4.61 / 5.02 | 4.97 / 5.23 | 12.4 / 14.1 | 0.65× | 0.73× |
| `grid-small-mixed` | grid | 0.61 / 0.74 | 0.68 / 0.93 | 0.90 / 1.01 | 0.95 / 1.21 | 1.42 / 1.65 | 0.71× | 0.67× | 1.01 / 1.33 | 0.96 / 1.22 | 1.56 / 1.94 | 1.90 / 2.30 | 3.01 / 3.23 | 0.51× | 0.65× |
| `card-og` | og-card | 4.38 / 5.00 | 5.43 / 6.64 | 6.03 / 6.97 | 5.97 / 7.17 | 8.78 / 9.12 | 0.91× | 0.73× | 13.7 / 17.3 | 14.7 / 17.3 | 19.5 / 24.0 | 10.4 / 12.4 | 28.3 / 36.6 | 1.42× | 0.70× |
| `card-og-small` | og-card | 1.77 / 1.95 | 1.91 / 2.66 | 2.66 / 3.01 | 3.10 / 3.49 | 4.65 / 5.21 | 0.61× | 0.67× | 6.13 / 6.60 | 6.03 / 6.61 | 9.08 / 9.67 | 4.95 / 6.35 | 13.3 / 14.2 | 1.22× | 0.68× |
| `card-blog` | blog-card | 8.20 / 9.74 | 9.31 / 12.5 | 12.6 / 15.5 | 9.37 / 10.8 | 22.8 / 27.0 | 0.99× | 0.65× | 22.2 / 33.6 | 24.2 / 31.8 | 37.0 / 47.6 | 15.6 / 21.4 | 57.2 / 83.5 | 1.55× | 0.60× |
| `card-flat-ui` | blog-card | 4.47 / 5.52 | 4.51 / 6.67 | 6.29 / 7.70 | 5.31 / 6.67 | 8.98 / 11.0 | 0.85× | 0.71× | 8.26 / 9.86 | 8.80 / 11.3 | 12.3 / 15.9 | 9.57 / 12.8 | 28.1 / 37.8 | 0.92× | 0.67× |
| `stress-600-boxes` | stress | 9.55 / 10.9 | 10.8 / 12.1 | 14.6 / 15.6 | 10.4 / 13.4 | 14.0 / 16.7 | 1.04× | 0.66× | 13.4 / 15.1 | 13.4 / 17.7 | 21.6 / 26.2 | 14.9 / 17.0 | 27.0 / 30.6 | 0.90× | 0.62× |
| `stress-200-labels` | stress | 9.59 / 11.8 | 10.9 / 15.7 | 13.6 / 16.7 | 17.4 / 23.8 | 25.9 / 31.2 | 0.63× | 0.70× | 11.9 / 15.6 | 13.2 / 16.4 | 18.0 / 23.9 | 18.0 / 22.0 | 31.8 / 39.8 | 0.73× | 0.66× |
| `stress-3000x2000-card` | stress | 25.0 / 32.0 | 31.6 / 38.5 | 29.8 / 34.2 | 28.1 / 33.8 | 42.4 / 45.6 | 1.12× | 0.84× | 85.6 / 121 | 78.4 / 98.5 | 109 / 120 | 61.9 / 64.1 | 222 / 231 | 1.27× | 0.79× |
| `fx-text-shadow` | text-shadow | 1.03 / 1.30 | 1.26 / 1.55 | 1.76 / 2.10 | 1.21 / 1.82 | 1.82 / 2.02 | 1.04× | 0.58× | 3.75 / 4.61 | 3.86 / 4.68 | 6.03 / 6.13 | 2.53 / 2.97 | 6.98 / 7.70 | 1.52× | 0.62× |
| `gap-dashed-dotted-border` | known-gaps | 1.03 / 1.12 | 1.05 / 1.28 | 1.71 / 1.91 | 1.68 / 1.91 | 2.91 / 3.28 | 0.62× | 0.60× | 1.20 / 1.32 | 1.28 / 1.39 | 1.98 / 2.21 | 2.46 / 2.55 | 4.00 / 4.42 | 0.52× | 0.61× |
| `fx-filter-blur-grayscale` | filter | 1.10 / 1.27 | 1.20 / 1.67 | 2.12 / 2.73 | 1.78 / 2.13 | 3.00 / 3.42 | 0.68× | 0.52× | 2.73 / 3.14 | 2.90 / 3.20 | 4.75 / 5.21 | 2.71 / 3.79 | 7.95 / 9.37 | 1.07× | 0.58× |
| `gap-tailwind-tw` | known-gaps | 0.42 / 0.51 | 0.50 / 0.82 | 0.51 / 0.61 | 0.59 / 0.77 | 0.78 / 0.95 | 0.86× | 0.82× | 0.67 / 0.71 | 0.65 / 0.73 | 0.96 / 1.05 | 1.42 / 1.52 | 2.21 / 2.45 | 0.46× | 0.69× |
| `gap-oklch-color` | known-gaps | 0.23 / 0.37 | 0.34 / 0.65 | 0.23 / 0.40 | 0.31 / 0.58 | 0.39 / 0.58 | 1.09× | 1.01× | 0.46 / 0.64 | 0.52 / 0.72 | 0.79 / 0.94 | 1.19 / 1.39 | 1.87 / 2.14 | 0.44× | 0.58× |
| `gap-svg-image` | known-gaps | 0.33 / 0.45 | 0.43 / 1.09 | 0.43 / 0.57 | 0.44 / 0.89 | 0.64 / 0.81 | 0.97× | 0.77× | 0.61 / 0.66 | 0.60 / 0.78 | 0.92 / 1.00 | 1.10 / 1.24 | 1.97 / 2.14 | 0.54× | 0.66× |
| `gap-inline-box-decoration` | known-gaps | 0.42 / 0.56 | 0.51 / 0.74 | 0.55 / 0.62 | 0.74 / 1.17 | 1.04 / 1.23 | 0.69× | 0.77× | 0.95 / 1.08 | 0.92 / 1.06 | 1.33 / 1.69 | 1.43 / 1.58 | 2.73 / 2.94 | 0.64× | 0.72× |
| `gap-mix-blend-mode` | known-gaps | 0.50 / 0.64 | 0.55 / 0.83 | 0.74 / 0.83 | 0.71 / 1.32 | 1.29 / 1.47 | 0.78× | 0.67× | 0.84 / 0.89 | 0.80 / 0.95 | 1.29 / 1.36 | 1.54 / 1.69 | 2.71 / 2.85 | 0.52× | 0.65× |
| `gap-clip-path` | known-gaps | 0.64 / 1.06 | 0.72 / 1.00 | 0.86 / 1.10 | 0.71 / 0.93 | 1.28 / 1.60 | 1.01× | 0.74× | 1.52 / 1.66 | 1.57 / 1.72 | 2.26 / 2.47 | 1.57 / 1.75 | 10.5 / 11.9 | 1.00× | 0.67× |
| `gap-background-clip-text` | known-gaps | 0.47 / 0.58 | 0.57 / 0.80 | 0.59 / 0.71 | 1.96 / 2.44 | 2.95 / 3.27 | 0.29× | 0.80× | 1.40 / 1.78 | 1.45 / 1.72 | 2.19 / 2.39 | 2.83 / 3.20 | 8.48 / 9.49 | 0.51× | 0.64× |
| `gap-text-wrap-balance` | known-gaps | 0.43 / 0.81 | 0.55 / 1.21 | 0.49 / 0.62 | 0.72 / 1.20 | 1.01 / 1.42 | 0.76× | 0.89× | 0.90 / 1.08 | 0.93 / 1.30 | 1.22 / 1.40 | 1.44 / 2.07 | 2.64 / 3.06 | 0.64× | 0.74× |
| `pfx-aa-shapes` | aa-exact | 0.53 / 0.73 | 0.64 / 0.99 | 0.77 / 0.93 | 0.64 / 0.88 | 1.01 / 1.17 | 1.00× | 0.69× | 0.85 / 0.97 | 0.83 / 0.98 | 1.28 / 1.36 | 1.45 / 1.91 | 2.46 / 2.63 | 0.57× | 0.66× |
| `pfx-aa-text` | aa-exact | 0.53 / 0.70 | 0.60 / 1.23 | 0.67 / 0.85 | 1.01 / 2.33 | 1.41 / 1.86 | 0.60× | 0.79× | 1.16 / 1.29 | 1.16 / 1.31 | 1.62 / 1.76 | 1.81 / 2.47 | 3.04 / 3.58 | 0.64× | 0.72× |
| `pfx-border-dashed` | dashed-border | 1.36 / 1.71 | 1.50 / 1.98 | 2.40 / 2.94 | 2.33 / 3.32 | 4.23 / 5.25 | 0.64× | 0.57× | 1.70 / 1.83 | 1.75 / 2.12 | 2.79 / 3.15 | 3.06 / 4.31 | 5.63 / 6.16 | 0.57× | 0.61× |
| `pfx-border-dotted` | dotted-border | 1.60 / 1.76 | 1.69 / 1.87 | 2.59 / 2.73 | 2.58 / 2.92 | 4.73 / 5.18 | 0.66× | 0.62× | 1.61 / 1.92 | 1.59 / 2.02 | 2.95 / 3.25 | 3.17 / 3.56 | 4.38 / 6.33 | 0.50× | 0.55× |
| `pfx-border-double-3d` | double-3d-border | 0.59 / 0.76 | 0.69 / 0.89 | 0.93 / 1.04 | 0.80 / 1.44 | 1.20 / 1.37 | 0.86× | 0.64× | 0.77 / 0.86 | 0.73 / 0.89 | 1.23 / 1.37 | 1.35 / 1.70 | 2.11 / 2.68 | 0.54× | 0.62× |
| `pfx-border-mixed` | mixed-border | 0.85 / 1.08 | 0.91 / 1.75 | 1.35 / 1.57 | 1.08 / 2.07 | 1.98 / 2.39 | 0.84× | 0.63× | 1.15 / 1.30 | 1.20 / 1.24 | 1.82 / 2.07 | 1.82 / 1.96 | 3.38 / 3.85 | 0.66× | 0.63× |
| `pfx-outline` | outline | 0.95 / 1.78 | 1.03 / 3.08 | 1.47 / 1.69 | 1.58 / 2.44 | 2.88 / 4.79 | 0.65× | 0.65× | 1.28 / 1.63 | 1.21 / 1.50 | 1.98 / 2.18 | 2.33 / 3.14 | 4.39 / 5.31 | 0.52× | 0.65× |
| `pfx-clip-path-shapes` | clip-path | 0.75 / 1.22 | 0.92 / 1.30 | 1.13 / 1.32 | 1.04 / 1.41 | 1.66 / 2.14 | 0.88× | 0.67× | 2.01 / 2.26 | 2.14 / 2.34 | 3.00 / 3.35 | 1.86 / 2.12 | 8.61 / 9.97 | 1.15× | 0.67× |
| `pfx-mask-gradient` | mask | 1.31 / 2.27 | 1.36 / 2.05 | 2.04 / 2.50 | 1.70 / 2.03 | 2.69 / 3.22 | 0.80× | 0.64× | 2.33 / 2.58 | 2.34 / 2.61 | 3.53 / 4.05 | 2.53 / 2.84 | 10.2 / 11.7 | 0.93× | 0.66× |
| `pfx-bg-clip-text` | bg-clip-text | 0.68 / 0.93 | 0.82 / 0.93 | 0.84 / 0.96 | 2.84 / 3.30 | 4.59 / 4.81 | 0.29× | 0.81× | 2.02 / 2.68 | 1.74 / 2.54 | 2.75 / 3.48 | 3.73 / 3.89 | 6.18 / 9.14 | 0.47× | 0.74× |
| `pfx-mix-blend` | mix-blend | 1.35 / 1.45 | 1.48 / 1.99 | 2.18 / 3.63 | 1.80 / 2.87 | 3.05 / 3.69 | 0.83× | 0.62× | 4.13 / 4.54 | 4.15 / 4.67 | 6.53 / 6.92 | 2.85 / 4.87 | 12.0 / 14.0 | 1.46× | 0.63× |
| `pfx-bg-blend` | bg-blend | 1.03 / 1.24 | 1.15 / 1.36 | 1.39 / 1.84 | 5.25 / 6.65 | 7.25 / 8.83 | 0.22× | 0.74× | 4.20 / 4.87 | 4.25 / 4.86 | 6.58 / 6.95 | 7.53 / 8.25 | 17.9 / 20.9 | 0.56× | 0.64× |
| `pfx-drop-shadow` | drop-shadow | 1.26 / 1.41 | 1.33 / 1.47 | 1.98 / 2.27 | 1.70 / 1.94 | 2.55 / 2.96 | 0.78× | 0.64× | 3.48 / 3.80 | 3.46 / 3.76 | 5.38 / 5.83 | 2.69 / 3.09 | 12.3 / 13.8 | 1.28× | 0.65× |
| `pfx-backdrop-filter` | backdrop-filter | 2.21 / 2.53 | 2.35 / 2.70 | 4.15 / 4.90 | 3.59 / 4.09 | 5.83 / 7.42 | 0.65× | 0.53× | 3.66 / 4.26 | 3.71 / 3.93 | 6.34 / 6.95 | 4.64 / 4.90 | 11.6 / 12.9 | 0.80× | 0.58× |
| `pfx-text-stroke` | text-stroke | 1.26 / 1.34 | 1.37 / 1.61 | 1.96 / 2.29 | 1.01 / 1.14 | 1.45 / 1.77 | 1.35× | 0.64× | 1.90 / 2.05 | 1.82 / 2.25 | 2.87 / 3.14 | 1.71 / 2.36 | 3.32 / 3.74 | 1.06× | 0.66× |
| `pfx-text-decoration` | text-decoration | 1.90 / 1.96 | 1.94 / 2.54 | 2.70 / 3.02 | 1.78 / 1.98 | 2.74 / 3.12 | 1.09× | 0.70× | 2.81 / 3.08 | 2.91 / 3.08 | 4.43 / 4.74 | 2.72 / 2.91 | 5.55 / 6.07 | 1.07× | 0.63× |
| `pfx-visibility` | visibility | 0.29 / 0.42 | 0.41 / 0.75 | 0.37 / 0.46 | 0.50 / 0.79 | 0.66 / 0.86 | 0.83× | 0.79× | 0.61 / 0.71 | 0.57 / 0.71 | 1.00 / 1.13 | 1.23 / 1.41 | 2.01 / 2.38 | 0.46× | 0.61× |
| `pfx-opacity-layers` | opacity | 1.79 / 1.94 | 1.82 / 1.96 | 3.95 / 4.27 | 2.83 / 3.09 | 5.13 / 5.74 | 0.64× | 0.45× | 3.40 / 3.84 | 3.58 / 3.83 | 5.27 / 6.36 | 3.65 / 4.14 | 11.1 / 13.0 | 0.98× | 0.65× |
| `pfx-svg-background` | svg-image | 1.34 / 2.05 | 1.43 / 3.18 | 2.67 / 3.66 | 0.98 / 2.12 | 1.67 / 2.09 | 1.47× | 0.50× | 1.81 / 2.36 | 1.80 / 2.72 | 3.30 / 4.28 | 2.01 / 4.57 | 4.07 / 5.14 | 0.89× | 0.55× |
| `pfx-inline-boxes-many` | inline-box | 2.22 / 2.66 | 2.34 / 2.66 | 3.41 / 4.18 | 3.00 / 3.55 | 4.68 / 5.35 | 0.78× | 0.65× | 3.88 / 4.56 | 3.82 / 4.94 | 5.93 / 7.58 | 4.18 / 6.92 | 8.73 / 12.0 | 0.91× | 0.65× |
| `css-class-id` | css-stylesheet | 2.49 / 2.99 | 3.87 / 6.02 | 3.08 / 3.70 | 2.65 / 3.02 | 3.85 / 4.59 | 1.46× | 0.81× | 4.39 / 6.60 | 5.00 / 7.14 | 6.01 / 12.8 | 5.64 / 9.10 | 12.5 / 16.4 | 0.89× | 0.73× |
| `css-nth-child` | css-stylesheet | 1.48 / 2.09 | 1.90 / 3.54 | 1.93 / 2.25 | 1.78 / 2.22 | 2.81 / 5.52 | 1.06× | 0.77× | 2.14 / 2.84 | 2.06 / 2.67 | 3.16 / 4.38 | 3.22 / 4.33 | 7.34 / 8.27 | 0.64× | 0.68× |
| `css-media-layer` | css-stylesheet | 1.26 / 2.40 | 1.99 / 3.24 | 1.52 / 2.03 | 1.02 / 1.96 | 1.43 / 2.46 | 1.95× | 0.83× | 1.78 / 1.92 | 1.79 / 2.08 | 2.64 / 2.77 | 3.88 / 4.95 | 8.00 / 8.44 | 0.46× | 0.67× |
| `css-important-var` | css-stylesheet | 1.06 / 1.38 | 1.57 / 2.78 | 1.17 / 1.35 | 1.22 / 3.18 | 1.63 / 2.29 | 1.29× | 0.91× | 1.28 / 1.76 | 1.31 / 1.52 | 1.82 / 2.32 | 3.33 / 5.38 | 5.54 / 6.70 | 0.39× | 0.71× |
| `tw-card` | tailwind | 2.49 / 4.68 | 3.65 / 6.07 | 2.77 / 4.06 | 2.40 / 5.33 | 3.68 / 5.30 | 1.52× | 0.90× | 3.84 / 4.32 | 3.52 / 4.53 | 5.40 / 5.70 | 4.78 / 5.24 | 11.6 / 12.7 | 0.74× | 0.71× |
| `tw-responsive` | tailwind | 1.27 / 1.82 | 1.84 / 4.87 | 1.33 / 1.68 | 0.96 / 1.65 | 1.32 / 2.38 | 1.92× | 0.95× | 1.53 / 1.79 | 1.54 / 2.07 | 2.17 / 2.36 | 3.58 / 3.77 | 5.84 / 6.72 | 0.43× | 0.71× |
| `tw-structural` | tailwind | 1.18 / 1.62 | 1.68 / 4.77 | 1.53 / 2.24 | 0.95 / 1.85 | 1.24 / 1.96 | 1.78× | 0.77× | 1.45 / 1.60 | 1.44 / 1.68 | 2.24 / 2.41 | 2.86 / 3.18 | 5.34 / 5.92 | 0.50× | 0.65× |
| `tw-arbitrary` | tailwind | 2.71 / 3.28 | 3.38 / 5.01 | 4.24 / 5.27 | 5.14 / 6.09 | 8.16 / 9.72 | 0.66× | 0.64× | 3.59 / 3.91 | 3.66 / 4.10 | 5.75 / 6.38 | 6.26 / 6.88 | 13.0 / 14.2 | 0.59× | 0.62× |
| `html-article` | html | 1.91 / 3.86 | 2.80 / 4.12 | 2.12 / 3.43 | 2.11 / 3.58 | 2.86 / 3.83 | 1.32× | 0.90× | 3.11 / 5.02 | 3.08 / 5.25 | 3.99 / 5.20 | 4.37 / 5.63 | 9.44 / 12.0 | 0.71× | 0.78× |
| `html-document` | html | 0.90 / 2.52 | 1.28 / 3.16 | 0.93 / 1.39 | 1.01 / 1.53 | 1.36 / 1.90 | 1.26× | 0.97× | 1.26 / 2.01 | 1.59 / 2.58 | 1.87 / 2.82 | 2.99 / 4.43 | 4.63 / 5.34 | 0.53× | 0.67× |
| `html-flex-card` | html | 2.57 / 4.08 | 3.23 / 4.19 | 3.33 / 4.45 | 3.69 / 3.98 | 5.50 / 6.31 | 0.88× | 0.77× | 7.65 / 8.11 | 7.65 / 8.01 | 11.0 / 11.6 | 6.17 / 7.10 | 19.4 / 20.9 | 1.24× | 0.70× |
| `html-inline` | html | 1.01 / 1.94 | 1.43 / 3.73 | 1.16 / 2.52 | 1.84 / 5.13 | 1.88 / 3.38 | 0.78× | 0.87× | 1.70 / 2.26 | 1.61 / 2.11 | 2.21 / 2.47 | 2.95 / 3.58 | 4.96 / 5.79 | 0.55× | 0.77× |
| `pseudo-inline` | pseudo-elements | 0.86 / 1.87 | 1.20 / 4.66 | 0.84 / 1.34 | 1.16 / 2.81 | 1.65 / 2.20 | 1.04× | 1.02× | 1.20 / 1.41 | 1.24 / 1.39 | 1.77 / 2.09 | 2.03 / 2.36 | 4.27 / 4.80 | 0.61× | 0.68× |
| `pseudo-block` | pseudo-elements | 1.04 / 1.30 | 1.44 / 3.47 | 1.31 / 1.49 | 1.22 / 2.29 | 1.72 / 2.19 | 1.18× | 0.79× | 1.43 / 1.68 | 1.44 / 1.90 | 2.07 / 2.26 | 2.54 / 2.81 | 4.95 / 5.35 | 0.57× | 0.69× |
| `pseudo-attr` | pseudo-elements | 0.60 / 0.94 | 0.73 / 2.46 | 0.73 / 0.88 | 0.89 / 1.31 | 1.29 / 3.36 | 0.82× | 0.82× | 1.00 / 1.25 | 1.04 / 1.71 | 1.42 / 2.29 | 3.71 / 7.34 | 4.00 / 5.30 | 0.28× | 0.70× |
| `pseudo-tw` | pseudo-elements | 0.92 / 1.07 | 1.28 / 2.41 | 1.02 / 2.17 | 1.04 / 4.08 | 1.45 / 1.56 | 1.22× | 0.90× | 1.20 / 1.39 | 1.23 / 1.80 | 1.71 / 1.88 | 1.87 / 2.04 | 3.84 / 4.27 | 0.66× | 0.70× |
| `anim-opacity-t0` | animation | 0.22 / 0.30 | 0.26 / 0.42 | 0.27 / 0.32 | 0.33 / 0.45 | 0.43 / 0.50 | 0.78× | 0.81× | 0.42 / 0.48 | 0.41 / 0.56 | 0.61 / 0.77 | 0.67 / 0.83 | 1.07 / 1.74 | 0.60× | 0.68× |
| `anim-opacity-t250` | animation | 0.25 / 0.31 | 0.33 / 0.68 | 0.31 / 0.37 | 0.45 / 0.71 | 0.70 / 0.82 | 0.74× | 0.81× | 0.46 / 0.53 | 0.47 / 0.62 | 0.68 / 0.76 | 0.94 / 1.71 | 1.48 / 1.66 | 0.51× | 0.67× |
| `anim-opacity-t500` | animation | 0.23 / 0.32 | 0.29 / 0.95 | 0.31 / 0.39 | 0.43 / 1.46 | 0.67 / 0.82 | 0.67× | 0.75× | 0.46 / 0.71 | 0.49 / 1.27 | 0.69 / 0.85 | 0.96 / 1.77 | 1.52 / 2.09 | 0.52× | 0.67× |
| `anim-opacity-t900` | animation | 0.24 / 0.30 | 0.28 / 0.46 | 0.31 / 0.37 | 0.45 / 0.96 | 0.69 / 0.76 | 0.63× | 0.77× | 0.47 / 0.67 | 0.46 / 0.79 | 0.68 / 0.80 | 0.93 / 1.19 | 1.52 / 1.91 | 0.49× | 0.69× |
| `anim-opacity-t1500` | animation | 0.22 / 0.31 | 0.34 / 0.90 | 0.26 / 0.32 | 0.39 / 1.32 | 0.47 / 0.61 | 0.87× | 0.83× | 0.43 / 0.56 | 0.48 / 1.96 | 0.63 / 0.72 | 0.85 / 3.56 | 1.24 / 1.36 | 0.56× | 0.68× |
| `anim-transform-t0` | animation | 0.29 / 0.39 | 0.62 / 5.27 | 0.40 / 0.93 | 1.13 / 4.24 | 0.54 / 1.24 | 0.55× | 0.72× | 0.55 / 1.61 | 0.78 / 3.93 | 0.81 / 0.93 | 1.01 / 3.49 | 1.31 / 2.75 | 0.78× | 0.69× |
| `anim-transform-t200` | animation | 0.29 / 0.40 | 0.39 / 2.45 | 0.37 / 0.74 | 0.45 / 3.69 | 0.53 / 0.87 | 0.86× | 0.80× | 0.47 / 0.52 | 0.48 / 1.23 | 0.68 / 0.81 | 0.90 / 1.80 | 1.35 / 1.61 | 0.53× | 0.68× |
| `anim-transform-t400` | animation | 0.33 / 0.42 | 0.45 / 1.44 | 0.38 / 0.56 | 0.48 / 1.40 | 0.56 / 0.74 | 0.93× | 0.87× | 0.44 / 0.46 | 0.44 / 1.81 | 0.65 / 0.69 | 0.85 / 1.04 | 1.25 / 1.45 | 0.52× | 0.67× |
| `anim-transform-t600` | animation | 0.31 / 0.36 | 0.41 / 0.71 | 0.37 / 0.45 | 0.44 / 0.52 | 0.54 / 0.73 | 0.92× | 0.84× | 0.45 / 0.50 | 0.42 / 0.73 | 0.65 / 0.71 | 0.84 / 0.92 | 1.29 / 1.44 | 0.51× | 0.69× |
| `anim-transform-t800` | animation | 0.24 / 0.34 | 0.30 / 0.51 | 0.33 / 0.37 | 0.36 / 0.46 | 0.45 / 0.61 | 0.85× | 0.74× | 0.53 / 0.66 | 0.52 / 0.76 | 0.77 / 0.89 | 0.88 / 1.18 | 1.29 / 1.57 | 0.59× | 0.69× |
| `anim-color-t0` | animation | 0.29 / 0.36 | 0.34 / 0.53 | 0.39 / 0.48 | 0.57 / 0.74 | 0.77 / 0.93 | 0.59× | 0.75× | 0.46 / 0.50 | 0.43 / 0.52 | 0.67 / 0.71 | 1.03 / 1.10 | 1.61 / 1.72 | 0.42× | 0.69× |
| `anim-color-t300` | animation | 0.29 / 0.37 | 0.37 / 0.99 | 0.38 / 0.47 | 0.61 / 0.73 | 0.79 / 0.99 | 0.62× | 0.76× | 0.44 / 0.51 | 0.41 / 0.61 | 0.64 / 0.71 | 1.04 / 1.36 | 1.49 / 1.67 | 0.40× | 0.68× |
| `anim-color-t700` | animation | 0.29 / 0.36 | 0.32 / 0.49 | 0.39 / 0.47 | 0.56 / 0.70 | 0.74 / 0.87 | 0.58× | 0.74× | 0.45 / 0.52 | 0.42 / 0.84 | 0.67 / 0.86 | 1.05 / 1.21 | 1.59 / 1.91 | 0.40× | 0.67× |
| `anim-color-t2000` | animation | 0.27 / 0.41 | 0.31 / 0.72 | 0.37 / 0.54 | 0.58 / 0.79 | 0.73 / 0.95 | 0.54× | 0.73× | 0.44 / 0.49 | 0.42 / 0.57 | 0.64 / 0.69 | 1.04 / 1.20 | 1.53 / 1.65 | 0.41× | 0.68× |
| `anim-width-t0` | animation | 0.22 / 0.32 | 0.31 / 0.52 | 0.30 / 0.35 | 0.35 / 0.72 | 0.43 / 0.58 | 0.87× | 0.75× | 0.48 / 0.67 | 0.52 / 1.02 | 0.70 / 0.92 | 0.82 / 1.43 | 1.23 / 1.92 | 0.63× | 0.68× |
| `anim-width-t100` | animation | 0.35 / 0.67 | 0.49 / 1.41 | 0.41 / 0.49 | 0.48 / 2.09 | 0.57 / 0.90 | 1.00× | 0.85× | 0.45 / 0.61 | 0.48 / 1.98 | 0.65 / 0.77 | 0.93 / 1.81 | 1.38 / 1.58 | 0.52× | 0.69× |
| `anim-width-t500` | animation | 0.33 / 0.43 | 0.40 / 0.71 | 0.47 / 0.57 | 0.43 / 0.61 | 0.55 / 0.65 | 0.93× | 0.71× | 0.55 / 1.21 | 0.56 / 1.49 | 0.81 / 2.30 | 0.97 / 1.37 | 1.48 / 1.75 | 0.58× | 0.68× |
| `anim-width-t999` | animation | 0.33 / 0.60 | 0.39 / 1.04 | 0.46 / 0.62 | 0.42 / 1.06 | 0.54 / 0.73 | 0.92× | 0.72× | 0.51 / 0.59 | 0.48 / 0.66 | 0.77 / 0.95 | 0.89 / 1.12 | 1.32 / 1.52 | 0.54× | 0.66× |
| `anim-delay-fill-t0` | animation | 0.29 / 0.39 | 0.40 / 3.07 | 0.40 / 1.75 | 0.95 / 8.43 | 0.75 / 2.06 | 0.42× | 0.72× | 0.56 / 1.42 | 0.55 / 2.00 | 0.84 / 1.36 | 0.94 / 3.86 | 1.54 / 2.37 | 0.58× | 0.66× |
| `anim-delay-fill-t750` | animation | 0.33 / 0.40 | 0.38 / 1.35 | 0.47 / 0.51 | 0.60 / 1.86 | 0.95 / 1.24 | 0.64× | 0.71× | 0.57 / 0.61 | 0.58 / 0.95 | 0.88 / 1.06 | 0.99 / 1.40 | 1.67 / 2.49 | 0.58× | 0.65× |
| `anim-delay-fill-t2000` | animation | 0.28 / 0.41 | 0.38 / 2.29 | 0.37 / 0.45 | 0.44 / 2.21 | 0.55 / 0.81 | 0.86× | 0.75× | 0.50 / 0.58 | 0.51 / 0.76 | 0.77 / 0.89 | 0.87 / 1.08 | 1.29 / 1.64 | 0.58× | 0.65× |
| `anim-alternate-t100` | animation | 0.26 / 0.33 | 0.44 / 1.33 | 0.32 / 0.47 | 0.57 / 1.56 | 0.77 / 1.08 | 0.77× | 0.79× | 0.49 / 0.77 | 0.77 / 1.68 | 0.75 / 1.50 | 1.49 / 3.40 | 1.59 / 2.71 | 0.52× | 0.64× |
| `anim-alternate-t500` | animation | 0.27 / 0.48 | 0.72 / 1.63 | 0.34 / 0.42 | 0.74 / 2.28 | 0.78 / 1.45 | 0.98× | 0.80× | 0.50 / 0.91 | 1.28 / 2.58 | 0.72 / 1.32 | 1.51 / 3.77 | 1.56 / 2.93 | 0.85× | 0.70× |
| `anim-alternate-t700` | animation | 0.25 / 0.38 | 0.35 / 1.65 | 0.32 / 0.38 | 0.53 / 1.17 | 0.75 / 0.86 | 0.66× | 0.79× | 0.47 / 0.51 | 0.46 / 1.26 | 0.67 / 0.79 | 0.95 / 2.47 | 1.54 / 1.83 | 0.48× | 0.70× |
| `anim-alternate-t1100` | animation | 0.26 / 0.34 | 0.34 / 2.26 | 0.32 / 0.38 | 0.51 / 1.28 | 0.73 / 1.01 | 0.66× | 0.81× | 0.48 / 0.68 | 0.47 / 1.47 | 0.70 / 0.77 | 0.93 / 1.44 | 1.54 / 2.03 | 0.51× | 0.68× |
| `anim-alternate-t1300` | animation | 0.24 / 0.33 | 0.33 / 1.92 | 0.30 / 0.40 | 0.41 / 1.84 | 0.47 / 0.62 | 0.80× | 0.79× | 0.47 / 0.76 | 0.49 / 1.40 | 0.65 / 0.79 | 0.83 / 1.11 | 1.22 / 1.45 | 0.59× | 0.73× |
| `anim-steps-t0` | animation | 0.25 / 0.33 | 0.32 / 1.06 | 0.33 / 0.39 | 0.42 / 1.57 | 0.50 / 0.70 | 0.77× | 0.77× | 0.50 / 0.65 | 0.48 / 0.69 | 0.74 / 0.84 | 0.82 / 1.30 | 1.26 / 1.64 | 0.58× | 0.67× |
| `anim-steps-t260` | animation | 0.24 / 0.33 | 0.29 / 0.74 | 0.31 / 0.46 | 0.37 / 0.70 | 0.47 / 0.61 | 0.79× | 0.76× | 0.45 / 0.51 | 0.45 / 0.55 | 0.67 / 0.81 | 0.77 / 0.91 | 1.16 / 1.36 | 0.58× | 0.67× |
| `anim-steps-t500` | animation | 0.25 / 0.40 | 0.33 / 0.60 | 0.32 / 0.38 | 0.38 / 0.54 | 0.48 / 0.63 | 0.87× | 0.77× | 0.47 / 0.54 | 0.45 / 0.61 | 0.69 / 0.81 | 0.78 / 0.93 | 1.22 / 1.32 | 0.58× | 0.68× |
| `anim-steps-t990` | animation | 0.25 / 0.35 | 0.30 / 1.71 | 0.32 / 0.43 | 0.39 / 1.01 | 0.47 / 0.63 | 0.78× | 0.78× | 0.48 / 0.57 | 0.47 / 1.08 | 0.70 / 0.97 | 0.82 / 1.16 | 1.22 / 1.50 | 0.58× | 0.69× |
| `anim-two-anims-t0` | animation | 0.28 / 0.41 | 0.33 / 1.06 | 0.36 / 0.47 | 0.46 / 1.40 | 0.73 / 0.93 | 0.70× | 0.77× | 0.50 / 0.53 | 0.49 / 0.76 | 0.73 / 0.90 | 0.92 / 1.06 | 1.54 / 1.79 | 0.53× | 0.68× |
| `anim-two-anims-t400` | animation | 0.38 / 0.47 | 0.53 / 8.03 | 0.52 / 1.13 | 0.71 / 6.52 | 1.19 / 1.96 | 0.74× | 0.73× | 0.64 / 0.85 | 0.74 / 2.83 | 0.97 / 1.35 | 1.41 / 4.14 | 2.08 / 4.06 | 0.53× | 0.66× |
| `anim-two-anims-t600` | animation | 0.42 / 0.54 | 0.62 / 3.84 | 0.55 / 1.15 | 0.84 / 3.27 | 1.30 / 2.41 | 0.74× | 0.77× | 0.64 / 0.73 | 0.67 / 1.74 | 0.97 / 1.05 | 1.33 / 3.59 | 2.11 / 2.64 | 0.51× | 0.66× |
| `anim-two-anims-t1200` | animation | 0.31 / 0.57 | 0.86 / 4.85 | 0.39 / 0.55 | 0.85 / 5.47 | 0.89 / 1.34 | 1.01× | 0.80× | 0.54 / 0.95 | 0.57 / 3.23 | 0.80 / 1.04 | 1.08 / 2.11 | 1.65 / 2.05 | 0.53× | 0.68× |
| `anim-inherit-t0` | animation | 0.33 / 0.39 | 0.38 / 2.81 | 0.45 / 0.52 | 0.65 / 1.20 | 0.84 / 0.96 | 0.58× | 0.75× | 0.53 / 0.56 | 0.48 / 0.60 | 0.75 / 0.77 | 1.08 / 1.48 | 1.65 / 1.82 | 0.44× | 0.70× |
| `anim-inherit-t500` | animation | 0.36 / 0.43 | 0.45 / 2.28 | 0.48 / 0.58 | 0.71 / 1.60 | 0.94 / 1.12 | 0.63× | 0.75× | 0.65 / 0.69 | 0.58 / 0.73 | 0.88 / 0.95 | 1.20 / 1.37 | 1.81 / 2.01 | 0.48× | 0.74× |
| `anim-inherit-t1000` | animation | 0.36 / 0.51 | 0.40 / 0.60 | 0.48 / 0.55 | 0.73 / 1.13 | 0.94 / 1.17 | 0.54× | 0.75× | 0.75 / 0.87 | 0.72 / 0.96 | 1.07 / 1.35 | 1.41 / 2.78 | 2.19 / 3.11 | 0.51× | 0.70× |
| `anim-tw-spin-t125` | animation | 0.29 / 0.38 | 0.42 / 2.39 | 0.33 / 1.13 | 0.54 / 2.46 | 0.76 / 1.76 | 0.78× | 0.89× | 0.49 / 0.56 | 0.51 / 0.57 | 0.72 / 0.80 | 0.98 / 1.05 | 1.48 / 1.62 | 0.52× | 0.68× |
| `anim-tw-spin-t375` | animation | 0.27 / 0.37 | 0.34 / 0.95 | 0.33 / 0.40 | 0.53 / 1.77 | 0.75 / 0.84 | 0.64× | 0.82× | 0.51 / 0.56 | 0.49 / 0.60 | 0.72 / 0.83 | 0.97 / 1.15 | 1.50 / 1.65 | 0.51× | 0.71× |
| `anim-tw-spin-t1600` | animation | 0.28 / 0.43 | 0.56 / 3.89 | 0.34 / 0.59 | 0.98 / 3.15 | 0.77 / 1.30 | 0.57× | 0.83× | 0.52 / 0.74 | 0.56 / 1.25 | 0.77 / 0.84 | 1.02 / 1.93 | 1.55 / 1.69 | 0.55× | 0.67× |
| `anim-kf-option-t0` | animation | 0.31 / 0.50 | 0.39 / 2.57 | 0.41 / 0.55 | 0.50 / 2.40 | 0.61 / 1.01 | 0.79× | 0.75× | 0.53 / 0.88 | 0.55 / 2.31 | 0.78 / 1.80 | 0.91 / 3.57 | 1.31 / 2.21 | 0.60× | 0.68× |
| `anim-kf-option-t500` | animation | 0.33 / 0.49 | 0.39 / 2.67 | 0.43 / 0.51 | 0.61 / 1.95 | 0.96 / 1.10 | 0.64× | 0.76× | 0.57 / 0.83 | 0.54 / 1.51 | 0.86 / 0.97 | 1.07 / 2.05 | 1.79 / 2.10 | 0.51× | 0.66× |
| `layout2-table-auto` | table | 1.17 / 1.24 | 1.69 / 3.31 | 1.60 / 3.60 | 1.80 / 3.30 | 2.51 / 4.00 | 0.94× | 0.73× | 1.71 / 2.12 | 1.76 / 2.06 | 2.65 / 2.97 | 2.69 / 3.09 | 5.00 / 5.61 | 0.66× | 0.65× |
| `layout2-table-spans` | table | 0.85 / 1.10 | 1.04 / 1.67 | 1.10 / 1.34 | 1.17 / 1.41 | 1.63 / 1.96 | 0.89× | 0.77× | 1.32 / 1.47 | 1.35 / 1.56 | 2.00 / 2.31 | 2.13 / 2.20 | 3.75 / 4.40 | 0.63× | 0.66× |
| `layout2-table-fixed` | table | 0.94 / 1.10 | 1.11 / 2.34 | 1.29 / 1.57 | 1.60 / 2.54 | 2.26 / 3.07 | 0.70× | 0.73× | 1.52 / 1.88 | 1.54 / 2.21 | 2.17 / 2.31 | 2.40 / 2.68 | 4.43 / 4.85 | 0.64× | 0.70× |
| `layout2-table-percent` | table | 0.60 / 1.10 | 0.74 / 2.24 | 0.77 / 1.22 | 1.01 / 2.36 | 1.38 / 2.07 | 0.74× | 0.77× | 0.85 / 1.15 | 0.88 / 2.19 | 1.28 / 1.59 | 1.75 / 2.51 | 2.78 / 3.15 | 0.50× | 0.66× |
| `layout2-table-collapse-conflicts` | table | 1.02 / 1.72 | 1.19 / 2.75 | 1.46 / 1.57 | 1.66 / 2.88 | 2.40 / 2.95 | 0.72× | 0.70× | 1.38 / 1.45 | 1.38 / 1.63 | 2.12 / 2.27 | 2.71 / 2.94 | 4.05 / 4.37 | 0.51× | 0.65× |
| `layout2-table-col-backgrounds` | table | 1.15 / 1.27 | 1.32 / 1.42 | 1.78 / 2.05 | 2.34 / 2.70 | 3.59 / 3.81 | 0.56× | 0.64× | 3.05 / 3.37 | 3.14 / 3.91 | 4.80 / 4.92 | 3.78 / 5.90 | 8.51 / 8.82 | 0.83× | 0.64× |
| `layout2-table-empty-cells` | table | 0.75 / 0.97 | 0.91 / 1.30 | 1.14 / 1.23 | 1.51 / 2.15 | 2.26 / 2.78 | 0.60× | 0.65× | 1.02 / 1.18 | 1.13 / 1.92 | 1.64 / 1.84 | 2.27 / 2.56 | 3.89 / 4.55 | 0.50× | 0.62× |
| `layout2-table-caption-bottom` | table | 1.07 / 1.14 | 1.28 / 1.72 | 1.61 / 1.91 | 1.82 / 3.49 | 2.68 / 2.92 | 0.70× | 0.67× | 1.58 / 3.03 | 1.59 / 2.23 | 2.49 / 2.81 | 3.12 / 5.06 | 4.88 / 6.95 | 0.51× | 0.64× |
| `layout2-float-image` | float | 0.66 / 1.04 | 0.90 / 4.20 | 1.08 / 1.18 | 1.04 / 3.09 | 1.45 / 2.17 | 0.86× | 0.62× | 2.84 / 3.82 | 3.01 / 4.69 | 4.34 / 6.50 | 2.56 / 7.02 | 12.3 / 16.8 | 1.18× | 0.65× |
| `layout2-float-clear` | float | 0.53 / 0.58 | 0.70 / 1.38 | 0.57 / 0.67 | 0.71 / 1.99 | 0.93 / 1.23 | 0.98× | 0.92× | 0.82 / 0.92 | 0.78 / 1.79 | 1.12 / 1.31 | 2.13 / 3.83 | 3.94 / 5.27 | 0.37× | 0.73× |
| `layout2-float-bfc` | float | 0.52 / 0.59 | 1.86 / 5.24 | 0.63 / 1.74 | 1.69 / 3.91 | 1.21 / 3.86 | 1.10× | 0.82× | 0.93 / 1.77 | 1.63 / 2.47 | 1.59 / 2.39 | 2.31 / 3.41 | 3.13 / 5.09 | 0.71× | 0.59× |
| `layout2-float-wrap` | float | 0.73 / 1.80 | 1.04 / 3.02 | 0.86 / 1.15 | 1.15 / 3.68 | 1.34 / 1.59 | 0.91× | 0.85× | 1.34 / 1.52 | 1.52 / 2.44 | 1.94 / 3.63 | 3.12 / 5.82 | 3.85 / 5.55 | 0.49× | 0.69× |
| `layout2-ib-badges` | inline-block | 0.54 / 2.00 | 0.77 / 4.17 | 0.71 / 1.11 | 0.98 / 2.17 | 1.17 / 2.12 | 0.79× | 0.76× | 0.79 / 1.09 | 0.90 / 1.41 | 1.15 / 1.49 | 1.71 / 2.18 | 2.45 / 3.18 | 0.53× | 0.68× |
| `layout2-ib-wrap` | inline-block | 0.78 / 1.82 | 1.21 / 2.93 | 0.98 / 1.70 | 1.34 / 2.80 | 1.43 / 2.17 | 0.90× | 0.80× | 1.07 / 1.20 | 1.07 / 1.26 | 1.67 / 1.86 | 1.76 / 2.65 | 3.35 / 3.81 | 0.61× | 0.64× |
| `layout2-ib-valign` | inline-block | 0.51 / 0.73 | 0.61 / 0.87 | 0.67 / 0.76 | 0.83 / 1.12 | 1.12 / 1.44 | 0.73× | 0.77× | 2.29 / 2.87 | 2.30 / 2.65 | 3.56 / 3.82 | 1.84 / 2.13 | 5.13 / 5.63 | 1.25× | 0.64× |
| `layout2-ib-json` | inline-block | 0.47 / 0.92 | 0.62 / 1.98 | 0.53 / 0.69 | 0.87 / 2.87 | 1.04 / 1.62 | 0.71× | 0.90× | 0.63 / 0.86 | 0.60 / 2.12 | 0.89 / 1.86 | 1.37 / 2.58 | 1.98 / 3.22 | 0.44× | 0.71× |
| `layout2-grid-areas` | grid-areas | 0.83 / 1.06 | 1.03 / 2.73 | 1.11 / 1.37 | 1.04 / 2.02 | 1.47 / 3.63 | 0.99× | 0.75× | 1.29 / 1.99 | 1.25 / 3.91 | 1.97 / 5.09 | 2.40 / 4.69 | 4.05 / 7.29 | 0.52× | 0.65× |
| `layout2-grid-named-lines` | grid-areas | 0.61 / 0.97 | 0.73 / 1.20 | 0.88 / 1.21 | 0.87 / 1.25 | 1.32 / 1.51 | 0.84× | 0.70× | 1.05 / 1.14 | 1.03 / 1.44 | 1.64 / 1.87 | 2.14 / 3.12 | 3.69 / 4.77 | 0.48× | 0.64× |
| `layout2-grid-areas-auto` | grid-areas | 0.58 / 0.91 | 0.72 / 3.30 | 0.74 / 1.35 | 0.87 / 3.40 | 1.24 / 4.04 | 0.83× | 0.78× | 0.82 / 1.04 | 0.87 / 1.03 | 1.33 / 1.47 | 1.81 / 2.15 | 2.88 / 3.32 | 0.48× | 0.62× |
| `layout3-float-left` | float-text | 0.68 / 0.84 | 0.84 / 2.80 | 0.93 / 1.63 | 0.93 / 1.77 | 1.33 / 1.80 | 0.90× | 0.74× | 1.28 / 1.52 | 1.37 / 1.64 | 1.84 / 2.37 | 1.89 / 2.42 | 3.64 / 4.50 | 0.72× | 0.70× |
| `layout3-float-right` | float-text | 0.74 / 0.82 | 0.89 / 1.29 | 0.92 / 4.88 | 1.01 / 4.92 | 1.44 / 2.15 | 0.88× | 0.80× | 1.30 / 1.40 | 1.37 / 1.66 | 1.92 / 2.16 | 1.79 / 1.98 | 3.57 / 3.87 | 0.77× | 0.67× |
| `layout3-float-stacked` | float-text | 0.95 / 1.21 | 1.09 / 1.77 | 1.21 / 1.42 | 1.17 / 1.34 | 1.75 / 2.22 | 0.93× | 0.78× | 1.82 / 2.05 | 1.85 / 2.05 | 2.74 / 3.03 | 2.22 / 2.29 | 4.64 / 5.40 | 0.83× | 0.67× |
| `layout3-float-tall` | float-text | 1.05 / 1.17 | 1.24 / 1.49 | 1.41 / 1.53 | 1.38 / 1.52 | 2.15 / 2.28 | 0.90× | 0.75× | 2.32 / 2.48 | 2.35 / 2.61 | 3.36 / 3.57 | 2.59 / 2.92 | 5.77 / 6.12 | 0.91× | 0.69× |
| `layout3-float-in-text` | float-text | 0.88 / 1.02 | 1.02 / 1.93 | 1.17 / 1.34 | 1.15 / 2.43 | 1.73 / 1.94 | 0.88× | 0.75× | 1.81 / 2.15 | 1.74 / 1.99 | 2.52 / 2.73 | 2.12 / 2.66 | 4.25 / 4.66 | 0.82× | 0.72× |
| `layout3-float-rtl` | float-text | 1.18 / 1.50 | 1.35 / 3.23 | 1.64 / 3.10 | 1.68 / 3.51 | 2.58 / 3.34 | 0.80× | 0.72× | 2.35 / 4.08 | 2.38 / 5.48 | 3.34 / 8.15 | 2.50 / 10.2 | 5.73 / 9.37 | 0.95× | 0.70× |
| `layout3-float-inline-box` | float-text | 0.74 / 0.98 | 0.80 / 3.59 | 0.97 / 1.27 | 0.97 / 2.10 | 1.48 / 1.63 | 0.83× | 0.76× | 1.50 / 1.87 | 1.43 / 1.63 | 2.09 / 2.38 | 2.04 / 4.01 | 3.95 / 4.64 | 0.70× | 0.72× |
| `layout3-inline-badges` | inline-flow | 0.88 / 0.98 | 1.02 / 2.45 | 1.20 / 1.39 | 1.37 / 2.53 | 1.96 / 2.36 | 0.74× | 0.74× | 1.48 / 1.67 | 1.47 / 1.63 | 2.19 / 2.32 | 2.17 / 2.35 | 4.13 / 4.35 | 0.68× | 0.68× |
| `layout3-inline-image` | inline-flow | 0.75 / 0.97 | 0.89 / 1.44 | 1.34 / 1.58 | 1.21 / 1.44 | 1.70 / 2.01 | 0.74× | 0.56× | 2.62 / 2.84 | 2.71 / 3.00 | 4.13 / 4.64 | 2.32 / 2.50 | 6.55 / 7.09 | 1.17× | 0.63× |
| `layout3-inline-flex-chip` | inline-flow | 0.92 / 1.04 | 1.08 / 1.41 | 1.79 / 2.02 | 1.59 / 1.79 | 2.27 / 2.49 | 0.68× | 0.52× | 2.47 / 2.70 | 2.49 / 2.84 | 3.81 / 4.58 | 2.74 / 3.13 | 6.80 / 8.14 | 0.91× | 0.65× |
| `layout3-inline-br` | inline-flow | 0.64 / 0.81 | 0.71 / 1.31 | 0.89 / 1.09 | 1.04 / 1.85 | 1.41 / 2.13 | 0.68× | 0.72× | 1.05 / 1.16 | 1.09 / 1.47 | 1.56 / 2.76 | 1.77 / 3.00 | 3.15 / 4.03 | 0.61× | 0.67× |
| `layout3-inline-abs` | inline-flow | 0.54 / 0.67 | 0.58 / 0.74 | 0.76 / 0.86 | 0.81 / 1.04 | 1.18 / 1.32 | 0.72× | 0.71× | 1.00 / 1.15 | 0.97 / 1.12 | 1.48 / 1.65 | 1.55 / 1.68 | 2.81 / 3.04 | 0.63× | 0.67× |
| `layout3-span-edges` | inline-box-model | 1.01 / 1.15 | 1.09 / 1.42 | 1.43 / 1.81 | 1.13 / 1.56 | 1.71 / 1.98 | 0.97× | 0.70× | 1.50 / 1.80 | 1.54 / 1.66 | 2.45 / 2.67 | 1.87 / 2.09 | 3.68 / 4.30 | 0.82× | 0.61× |
| `layout3-span-nowrap` | inline-box-model | 0.87 / 1.08 | 0.96 / 1.24 | 1.20 / 1.33 | 1.28 / 1.49 | 1.84 / 2.24 | 0.75× | 0.73× | 1.55 / 1.67 | 1.54 / 1.68 | 2.17 / 2.39 | 2.09 / 2.46 | 3.89 / 4.77 | 0.74× | 0.71× |
| `layout3-span-valign` | inline-box-model | 0.99 / 1.21 | 1.15 / 1.36 | 1.41 / 2.17 | 1.68 / 2.83 | 2.32 / 3.48 | 0.68× | 0.70× | 1.71 / 1.85 | 1.78 / 1.91 | 2.67 / 2.95 | 2.53 / 2.82 | 4.91 / 5.29 | 0.70× | 0.64× |
| `layout3-card-all` | inline-box-model | 2.11 / 2.37 | 2.16 / 2.75 | 3.61 / 3.98 | 3.21 / 3.48 | 4.59 / 4.97 | 0.67× | 0.58× | 6.21 / 8.30 | 5.96 / 7.02 | 9.40 / 11.7 | 5.71 / 6.12 | 15.1 / 18.8 | 1.04× | 0.66× |

median / p95 ms từng fixture (median qua các lượt của median và p95 mỗi lượt). Tỉ lệ: bm-native async / takumi-native async, bm-native sync / bm-wasm sync.
<!-- /native-bench:per-fixture -->

## Giai đoạn 3 — trạng thái cuối cùng của 0.1.0

Đo trên bản build cuối (sau `wasm-opt`), so với `@takumi-rs/wasm` 2.20.0.

- **Kích thước (KiB, raw / gzip -9 / brotli):** core 454.5 / 211.5 / 180.3; standard 877.5 / 435.2 / 374.5; full 1 099.8 / 538.2 / 453.4;
  add-on WOFF 84.2 / 67.7 / 65.5; takumi-wasm 2.20: 4 234.9 / 1 860.9 / 1 409.3. So với takumi (raw): core nhỏ hơn 9.3×, standard 4.8×, full 3.9×.
  (Số giai đoạn 2: 428.5 / 849.6 / 1 070.0 và 9.9× / 5.0× / 4.0×.) Công việc dòng inline thêm khoảng 26–30 KB cho mỗi profile.
- **Tương đương:** **200 fixture: 74 identical, 126 equivalent, 0 close, 0 different, 0 lỗi** (giai đoạn 2: 184 = 74 / 109 / 1 close).
  Ca `layout2-float-wrap` trước đây "close" nay là equivalent. Cổng layout measure-tree: 197/197 ca không-transform khớp takumi trong 0.001 px.
- **Hiệu năng (geomean trên 191 ca không-gap):** raw 0.69 ms so với takumi 1.02 ms = 0.68× (nhanh hơn ở 171/191 ca, chậm hơn ở 20);
  png 1.59 ms so với 3.26 ms = 0.49× (nhanh hơn ở 191/191); tỉ lệ dung lượng PNG 0.78. Cold start tổng (init + font + og-card PNG đầu tiên):
  bm 70.8 ms so với takumi-wasm 178.4 ms (takumi-native 43.8 ms). Bộ nhớ wasm sau 50 lần render og-card PNG: bm 11.6 MiB so với 10.6 MiB (+9 %);
  peak RSS bm 89.1 MiB so với takumi-wasm 107.9 MiB. Unit test: 402/402.
- **Hai khoảng trống layout đã xong:** (a) chữ chảy quanh float (hộp dòng ngắn lại cạnh float và nở lại bên dưới; float trong nội dung inline; RTL);
  (b) định dạng inline thật cho nội dung hỗn hợp: inline nguyên tử (inline-block / inline-flex / inline-grid / ảnh inline) tham gia ngắt dòng giữa dòng
  với mọi giá trị `vertical-align`; padding / viền / margin ngang của span đẩy chữ (mép fragment đầu/cuối, `box-decoration-break: clone`),
  `white-space` theo từng span, `<br>` trong nội dung hỗn hợp, strut theo từng hộp (span cỡ chữ lớn hơn làm dòng cao lên khi `line-height` tường minh, như Blink).
  Fixture mới: `float-text` (7 ca), `inline-flow` (5), `inline-box-model` (4) — cả 16 ca equivalent với takumi (SSIM ≥ 0.9999).
- **Gói npm cuối (`npm pack`):** 28 file, 1 293.8 KiB nén, 2 655.8 KiB giải nén (có `README.vi.md`); `npm run test:pack` 15/15 đạt
  (Node ESM/CJS, TypeScript ×4 cấu hình, build Vite 8.3.8 + Edge 157 headless, esbuild, mô phỏng workerd). Test playground đạt trên cả ba profile (dev + dist).

Khoảng trống còn lại ở layout inline:

- Hộp inline hướng RTL bao quanh chữ LTR đặt mép start/end sai phía thị giác; fragment của hộp chưa được tách qua các đoạn bidi bị sắp xếp lại.
- RTL + `white-space: pre-wrap`: khoảng trắng treo.
- line-clamp / `-webkit-box` quanh float.
- Block-in-inline (span chứa block) vẫn biến span thành block.
- Thứ tự vẽ float chỉ xấp xỉ (float vẽ sau nội dung in-flow của stacking context).
- `text-wrap: balance/pretty` quay về ngắt dòng tham lam trong đoạn có hộp inline / inline nguyên tử hoặc cạnh float.
- padding/margin theo % trên hộp inline được tính bằng 0.
- Chuỗi inline-block lồng nhau giới hạn khoảng 255 cấp (lỗi "nested too deeply" rõ ràng), trong khi lồng thường hỗ trợ 512.

## Giai đoạn 2 — tóm tắt

Điều kiện đo như giai đoạn 1 (i3-10100, Node 26.13, `@takumi-rs/wasm` 2.20.0), bản bm **full** (mọi tính năng), 184 fixture
(87 cũ + 97 mới cho các tính năng vừa port). Sàn nhiễu vẫn bằng 0 (takumi-native ≡ takumi-wasm từng byte).

| Chỉ số | takumi-wasm | bm giai đoạn 1 | bm giai đoạn 2 (full) |
|:--|--:|--:|--:|
| Tương đương trên toàn bộ fixture | — | 78 ca: 9 identical / 69 equivalent (+9 ca "gap": 5 different, 1 lỗi) | **184 ca: 74 identical / 109 equivalent / 1 close / 0 different / 0 lỗi** |
| Render `raw`, geomean | 1.09 ms (175 ca) | 0.61× takumi (78 ca) | **0.65×** (nhanh hơn ở 155/175 ca) |
| Render `png`, geomean | 3.41 ms | 0.72× | **0.48×** (nhanh hơn ở **175/175** ca) |
| Dung lượng PNG, geomean | 1.00 | 0.75 | 0.76 |
| Cold start tổng (init + font + render og-card PNG đầu tiên) | 186.9 ms | 79.5 ms | **72.1 ms** |
| Bộ nhớ wasm sau 50 lần render og-card PNG | 10.6 MiB | 11.9 MiB (+12 %) | 11.6 MiB (**+9 %**) |
| Peak RSS tiến trình | 99.4 MiB | 77.2 MiB | 88.6 MiB |
| Độ sâu cây tối đa | 512 | 128 | **512** |

### Kích thước theo cấu hình build (sau `wasm-opt -Oz`; số cuối cùng của giai đoạn 3 — giai đoạn 2 là 428.5 / 849.6 / 1 070.0)

| Cấu hình | raw KiB | gzip -9 | brotli | so với takumi (4 234.9 KiB) | Gồm |
|:--|--:|--:|--:|:--|:--|
| `core` | **454.5** | 211.5 | 180.3 | nhỏ hơn 9.3× | node JSON + style inline, var()/calc, flex/grid/block/absolute, hàng inline, TTF/TTC tĩnh + OpenType shaper mặc định, viền mọi kiểu/outline/trang trí chữ, PNG/JPEG vào, PNG/JPEG/WebP/raw ra |
| `standard` | **877.5** | 435.2 | 374.5 | nhỏ hơn 4.8× | core + stylesheet/selector, Tailwind, HTML, ảnh SVG, WOFF/WOFF2, font biến thiên, CFF, clip-path/mask/blend/backdrop, màu oklch/lab/color-mix, bảng, float, WebP/GIF vào, text-wrap balance |
| `full` (mặc định) | **1 099.8** | 538.2 | 453.4 | nhỏ hơn 3.9× | standard + chữ phức (bidi, Ả Rập, Hebrew, Indic, Thái), emoji màu, animation + renderAnimation, VP8 lossy, ảnh động, ICO, renderSvg |
| add-on `bm_woff.wasm` | 84.2 | 67.7 | 65.5 | — | giải mã WOFF/WOFF2 tải theo yêu cầu cho bản core |
| giai đoạn 1 (một bản duy nhất) | 320.9 | 147.1 | 126.5 | nhỏ hơn 13.2× | tập tính năng giai đoạn 1 |

Chi phí biên từng tính năng (đo ở giai đoạn 2, trước công việc dòng inline vốn thêm khoảng 26–30 KB cho mỗi profile; KB sau wasm-opt, thêm vào core / bỏ khỏi full): css 62.5 / 60.7 · tw 37.5 / 32.2 · html 27.8 / 27.2 ·
ảnh SVG 100.6 / 102.7 · woff 80.1 / 79.5 (52 KB là từ điển brotli bắt buộc) · font biến thiên 15.8 / 14.4 · cff 9.7 / 8.3 ·
effects 17.4 / 17.6 · màu hiện đại 12.1 / 10.1 · bảng 48.1 / 46.1 · float 6.5 / 4.8 · emoji màu 30.9 / 35.9 ·
chữ phức 52.2 / 53.0 · animation 42.0 / 52.9 · codec phụ 0.8 / 33.5 · renderSvg 57.0 / 59.1.

**Vì sao core không về được 321 KiB:** phần lõi đã lớn lên thật (+113 KB mã): viền/outline/trang trí chữ +31 KB, engine GSUB/GPOS
đầy đủ +26 KB, style (var(), calc, grid đặt tên, thuộc tính logic) +24 KB, raster (AA trùng tiny-skia, stroker) +17 KB, layout +9 KB,
DOM/measure +20 KB; bù lại core bỏ WebP/GIF vào (−36 KB). Cắt tiếp nghĩa là đổi thuật toán hoặc đổi kết quả render của core.

**Tải lười (lazy add-on):** chỉ làm được cho phần là hàm thuần byte-vào/byte-ra — đã làm cho WOFF/WOFF2 (`js/addons.mjs`,
đầu ra trùng từng byte với bản tích hợp). Tailwind không tách được vì nó là một tầng cascade riêng, sinh pseudo-element và cần thông tin
cấu trúc phần tử bên trong engine. SVG/CSS/shaping không tách được vì đọc-ghi trực tiếp cấu trúc nội bộ (ComputedStyle, cây layout,
cache glyph) trong cùng bộ nhớ tuyến tính — cần một dynamic linker thật cho wasm.

## Các điểm thua ở giai đoạn 1: nguyên nhân và kết quả sửa

| # | Điểm thua | Nguyên nhân gốc (đã profile) | Sửa được? | Trước → sau |
|:--|:--|:--|:--|:--|
| 1 | `border-radius` raw chậm hơn (hình elip lớn) | `fillPath` dựng mặt nạ A8 trên cả bbox rồi `blendSolid` đọc lại từng byte coverage (pass mask-rồi-blend 0.78 ms so với 0.2 ms quét cạnh) | **Một phần.** Bỏ mặt nạ trung gian: phát span thẳng từ hàng tích luỹ | elip 1200×630: 0.97 → 0.43 ms. Nhưng nhóm fixture vẫn 1.18× takumi (1.00 vs 0.85 ms): phần còn lại là chi phí cố định mỗi khung (xoá canvas, un-premultiply, copy 3 MB sang JS) chứ không phải rasterizer |
| 2 | PNG chậm hơn ở ảnh nhiều chữ | Chuỗi băm deflate bị giới hạn bởi độ trễ bộ nhớ (hash 4 byte trên dữ liệu chỉ mục → chuỗi dài, yếu); thử 3 chiến lược lọc × 51 hàng; đếm palette có nhánh sai dự đoán ở mép AA; Adler-32 chậm | **Có** | bước PNG −34…−62 %: text-vietnamese 8.41 → 4.33 ms (takumi 8.32); fonts-weights-italic 11.27 → 6.10 (10.55); card-og 21.5 → 15.2 (22.7). Giờ PNG nhanh hơn takumi ở 175/175 ca |
| 3 | WebP lossless ảnh chụp chậm 2.1× | LZ77 chuỗi băm trên phần dư của ảnh chụp chiếm ~65 % thời gian và còn làm file **lớn hơn** 9 % | **Có** — tự nhận biết nội dung kiểu ảnh chụp, chỉ dùng copy trái/trên | img-photo-bg: 45.9 → 19.9 ms (takumi 21.3), 414 → 376 KB (takumi 482 KB) |
| 4 | Bộ nhớ wasm +12 % | Scratch của bộ nén PNG (bản sao ảnh đã lọc), layer nhóm cỡ canvas, mặt nạ hi-res của glyph không được giải phóng, upload cả ảnh không dùng | **Một phần** — PNG nén theo luồng, canvas ngoài arena, scratch glyph riêng, chỉ upload ảnh được tham chiếu | 11.9 → 11.6 MiB (takumi 10.6): còn **+9 %**. Phần còn lại: bộ đệm scratch của rasterizer + layer cỡ canvas + cấp phát theo trang 64 KiB; chưa giảm tiếp |
| 5 | Viền dashed/dotted vẽ thành nét liền | Chưa cài | **Có** — port `BoxBorderPainter` của Blink/takumi | card-flat-ui SSIM 0.9949 → 0.9998; nét đứt cạnh thẳng trùng takumi; cạnh **bo tròn** còn lệch pha ~0.1 px mỗi góc (0.08–0.25 % px) |
| + | Mép khử răng cưa không trùng byte | AA theo diện tích chính xác ≠ siêu lấy mẫu 4×4 của tiny-skia; và `div_255` của takumi lệch 1 ở 126/65536 tích | **Có** — port bộ quét siêu lấy mẫu (232/232 hình thử trùng từng byte) và công thức `div_255` | fixture identical: 9 → 74; sai khác trung bình ở ca chữ ~0.1 → ~0.005 |

Điểm thua **còn lại** sau giai đoạn 2: bộ nhớ wasm +9 %; nhóm `border-radius` raw 1.18×; `text-stroke` raw 1.58× và `svg-image` raw 1.55×
(đường stroker và SVG chưa tối ưu); `text-decoration` 1.07×; peak RSS tăng so với giai đoạn 1 (77 → 89 MiB, vẫn dưới takumi 99 MiB).

## Tính năng đã port ở giai đoạn 2 và mức tương đương

| Tính năng | Kết quả kiểm chứng với takumi |
|:--|:--|
| Stylesheet / selector / cascade, `@media`, `@layer`, `@supports`, nesting, `var()` | 252/252 node khớp luật thắng; 4 fixture: 1 identical, 3 equivalent |
| Tailwind `tw` | 656/657 chuỗi class khớp takumi; 4 fixture: 2 identical, 2 equivalent |
| HTML đầu vào + preset UA, `::before` / `::after` | 55/58 mẫu khớp cấu trúc cây; 8 fixture equivalent |
| Màu oklch / lab / lch / color() / color-mix, không gian nội suy gradient | 495/495 màu trùng 8-bit; gradient lệch tối đa 1–2 mức |
| WOFF / WOFF2 (brotli viết lại từ đầu) | 17/19 font WOFF2 của takumi trùng từng byte với bộ tham chiếu; 2 font khác 1 bit cờ theo đặc tả mới |
| Font biến thiên (fvar/avar/gvar/HVAR/MVAR), CFF/CFF2, TTC mọi face | 1 400 phép so bề rộng lệch ≤ 1/64 px; 196/196 chiều cao dòng |
| Shaping đầy đủ: GSUB 1–8, GPOS 1–9, bidi UAX#9, Ả Rập, Hebrew, Devanagari, Bengali, Thái, tiếng Việt tổ hợp, `text-wrap: balance/pretty` | bề rộng khớp 0.000 px ở mọi nhóm; bidi 91 679/91 679 ca chuẩn; balance/pretty 216/216; 825/825 ca Latin cũ giữ nguyên |
| Emoji màu: COLR v0/v1, CBDT, sbix | SSIM ≥ 0.991 (takumi **không** vẽ được COLR v1 — phần này vượt takumi, so với Chrome) |
| Ảnh SVG (parser + renderer riêng) | 397/422 SVG của takumi identical/equivalent, SSIM trung bình 0.9956; nhanh hơn 3–10× |
| `renderSvg` (cây node → SVG) | rasterize SVG của hai bên bằng cùng bộ rasterizer: 175/179 fixture identical/equivalent |
| Bảng (auto/fixed, span, collapse, caption), float, inline-block, grid đặt tên/areas, độ sâu 512 | layout: 339/352 bảng, 138/138 float, 168/179 inline; 19 fixture: 18 equivalent/identical, 1 close (giai đoạn 2; `layout2-float-wrap` nay là equivalent) |
| Viền dashed/dotted/double/groove/ridge/inset/outset, outline | 5 fixture: 1 identical, 4 equivalent |
| clip-path, mask-image, mix-blend-mode, background-blend-mode, background-clip:text, drop-shadow, backdrop-filter, text-stroke, trang trí chữ, hộp inline | 12 fixture: 6 identical, 6 equivalent |
| CSS animation theo `timeMs`, `renderAnimation` (WebP/APNG/GIF) | 42 fixture: 32 identical, 10 equivalent; số khung và độ trễ khớp chính xác |
| WebP lossy (VP8), GIF/APNG/WebP động (giải mã + mã hoá), ICO | VP8 trùng libwebp từng bit; khung động trùng `anim_dump` |
| Trình duyệt thật (Edge 157 headless) | 78/78 ca raw trùng từng byte với Node; PNG/WebP/JPEG giải mã đúng trong trình duyệt; takumi cũng chạy được trong Edge để so thời gian |

## Bảng theo nhóm tính năng (giai đoạn 2, bản full)

| Tính năng | số ca | raw: takumi-wasm ms | raw: bm ms | bm/takumi | png: takumi-wasm ms | png: bm ms | bm/takumi | PNG bytes bm/takumi | takumi-native raw ms | tương đương (identical/equivalent/close/different/error) | SSIM thấp nhất | % px lệch (TB) |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--|--:|--:|
| colors | 5 | 1.41 | 0.90 | 0.63 | 3.91 | 1.51 | 0.39 | 0.65 | 1.15 | 2/3/0/0/0 | 1.0000 | 0.000 |
| flex | 5 | 1.19 | 1.11 | 0.93 | 4.58 | 2.06 | 0.45 | 0.67 | 1.24 | 5/0/0/0/0 | 1.0000 | 0.000 |
| sizing | 5 | 0.90 | 0.86 | 0.95 | 4.49 | 2.09 | 0.47 | 0.40 | 1.06 | 5/0/0/0/0 | 1.0000 | 0.000 |
| absolute | 3 | 1.05 | 0.89 | 0.85 | 5.32 | 2.25 | 0.42 | 0.55 | 0.99 | 2/1/0/0/0 | 1.0000 | 0.000 |
| borders | 3 | 1.37 | 1.09 | 0.80 | 4.17 | 2.03 | 0.49 | 0.61 | 1.11 | 3/0/0/0/0 | 1.0000 | 0.000 |
| border-radius | 4 | 0.85 | 1.00 | 1.18 | 4.10 | 1.84 | 0.45 | 0.83 | 0.94 | 4/0/0/0/0 | 1.0000 | 0.000 |
| linear-gradient | 4 | 3.90 | 2.26 | 0.58 | 17.08 | 6.55 | 0.38 | 0.65 | 3.02 | 1/3/0/0/0 | 1.0000 | 0.000 |
| radial-gradient | 3 | 4.79 | 1.78 | 0.37 | 24.77 | 12.00 | 0.48 | 0.58 | 4.07 | 0/3/0/0/0 | 1.0000 | 0.000 |
| box-shadow | 4 | 5.84 | 3.30 | 0.56 | 15.74 | 7.59 | 0.48 | 0.98 | 4.15 | 2/2/0/0/0 | 1.0000 | 0.000 |
| opacity | 4 | 5.23 | 2.26 | 0.43 | 9.06 | 3.48 | 0.38 | 0.81 | 2.83 | 0/4/0/0/0 | 1.0000 | 0.000 |
| overflow | 3 | 1.61 | 1.00 | 0.62 | 5.46 | 2.07 | 0.38 | 0.77 | 1.43 | 1/2/0/0/0 | 1.0000 | 0.000 |
| transform | 3 | 3.02 | 1.67 | 0.55 | 6.37 | 2.71 | 0.43 | 0.90 | 2.69 | 0/3/0/0/0 | 0.9995 | 0.026 |
| text-single-line | 3 | 1.49 | 0.92 | 0.62 | 4.74 | 2.27 | 0.48 | 0.99 | 1.50 | 0/3/0/0/0 | 1.0000 | 0.001 |
| text-paragraph | 5 | 2.20 | 1.43 | 0.65 | 6.88 | 3.56 | 0.52 | 0.91 | 2.03 | 0/5/0/0/0 | 1.0000 | 0.000 |
| fonts | 2 | 2.71 | 1.69 | 0.63 | 8.82 | 4.65 | 0.53 | 0.99 | 2.55 | 0/2/0/0/0 | 1.0000 | 0.008 |
| text-i18n | 2 | 2.34 | 1.56 | 0.67 | 7.93 | 4.05 | 0.51 | 1.01 | 2.33 | 0/2/0/0/0 | 1.0000 | 0.001 |
| text-truncation | 3 | 1.50 | 0.90 | 0.60 | 4.16 | 1.78 | 0.43 | 0.92 | 1.35 | 0/3/0/0/0 | 1.0000 | 0.000 |
| images | 5 | 4.66 | 1.77 | 0.38 | 28.56 | 17.08 | 0.60 | 1.00 | 3.60 | 0/5/0/0/0 | 0.9994 | 0.000 |
| grid | 4 | 1.61 | 1.26 | 0.78 | 5.54 | 2.27 | 0.41 | 0.70 | 1.59 | 0/4/0/0/0 | 1.0000 | 0.000 |
| og-card | 2 | 4.24 | 2.41 | 0.57 | 13.41 | 9.23 | 0.69 | 1.00 | 3.32 | 0/2/0/0/0 | 1.0000 | 0.000 |
| blog-card | 2 | 10.51 | 6.82 | 0.65 | 31.14 | 16.47 | 0.53 | 0.95 | 6.26 | 0/2/0/0/0 | 0.9998 | 0.003 |
| stress | 3 | 16.11 | 11.84 | 0.73 | 36.71 | 24.00 | 0.65 | 0.98 | 14.07 | 1/2/0/0/0 | 1.0000 | 0.000 |
| text-shadow | 1 | 1.00 | 1.00 | 1.01 | 4.35 | 3.95 | 0.91 | 1.03 | 0.72 | 0/1/0/0/0 | 1.0000 | 0.001 |
| known-gaps | 9 | 0.57 | 0.32 | 0.56 | 2.03 | 0.82 | 0.40 | 0.71 | 0.43 | 3/6/0/0/0 | 0.9994 | 0.014 |
| filter | 1 | 1.77 | 1.30 | 0.74 | 4.89 | 3.09 | 0.63 | 0.98 | 1.19 | 1/0/0/0/0 | 1.0000 | 0.000 |
| aa-exact | 2 | 0.61 | 0.37 | 0.61 | 1.57 | 0.84 | 0.54 | 0.98 | 0.46 | 1/1/0/0/0 | 1.0000 | 0.000 |
| dashed-border | 1 | 2.40 | 1.34 | 0.56 | 3.35 | 1.67 | 0.50 | 0.91 | 1.39 | 0/1/0/0/0 | 0.9997 | 0.077 |
| dotted-border | 1 | 2.82 | 1.50 | 0.53 | 3.65 | 1.83 | 0.50 | 0.91 | 1.57 | 0/1/0/0/0 | 0.9987 | 0.248 |
| double-3d-border | 1 | 0.60 | 0.49 | 0.81 | 1.40 | 0.70 | 0.50 | 0.83 | 0.46 | 1/0/0/0/0 | 1.0000 | 0.000 |
| mixed-border | 1 | 1.07 | 0.71 | 0.66 | 1.94 | 1.05 | 0.54 | 0.92 | 0.62 | 0/1/0/0/0 | 1.0000 | 0.000 |
| outline | 1 | 1.53 | 0.82 | 0.54 | 2.64 | 1.18 | 0.45 | 0.94 | 0.93 | 0/1/0/0/0 | 0.9996 | 0.068 |
| clip-path | 1 | 0.87 | 0.63 | 0.72 | 5.44 | 1.95 | 0.36 | 0.73 | 0.58 | 1/0/0/0/0 | 1.0000 | 0.000 |
| mask | 1 | 1.57 | 1.12 | 0.71 | 6.32 | 2.29 | 0.36 | 0.70 | 1.04 | 1/0/0/0/0 | 1.0000 | 0.000 |
| bg-clip-text | 1 | 2.63 | 0.44 | 0.17 | 5.36 | 2.16 | 0.40 | 1.00 | 1.83 | 0/1/0/0/0 | 1.0000 | 0.000 |
| mix-blend | 1 | 1.80 | 1.23 | 0.69 | 7.64 | 4.15 | 0.54 | 0.95 | 1.03 | 1/0/0/0/0 | 1.0000 | 0.000 |
| bg-blend | 1 | 4.92 | 0.99 | 0.20 | 10.58 | 4.37 | 0.41 | 0.99 | 3.91 | 1/0/0/0/0 | 1.0000 | 0.000 |
| drop-shadow | 1 | 1.53 | 1.20 | 0.79 | 7.06 | 3.45 | 0.49 | 0.97 | 1.09 | 0/1/0/0/0 | 1.0000 | 0.000 |
| backdrop-filter | 1 | 4.42 | 2.79 | 0.63 | 7.36 | 4.11 | 0.56 | 0.87 | 2.43 | 1/0/0/0/0 | 1.0000 | 0.000 |
| text-stroke | 1 | 0.74 | 1.18 | 1.58 | 2.11 | 1.90 | 0.90 | 1.00 | 0.59 | 0/1/0/0/0 | 0.9986 | 0.195 |
| text-decoration | 1 | 1.68 | 1.80 | 1.07 | 3.71 | 2.85 | 0.77 | 0.96 | 1.29 | 0/1/0/0/0 | 0.9992 | 0.019 |
| visibility | 1 | 0.30 | 0.18 | 0.62 | 1.20 | 0.52 | 0.43 | 0.36 | 0.27 | 1/0/0/0/0 | 1.0000 | 0.000 |
| svg-image | 1 | 0.77 | 1.19 | 1.55 | 2.21 | 1.81 | 0.82 | 0.87 | 0.48 | 0/1/0/0/0 | 0.9989 | 0.095 |
| inline-box | 1 | 2.67 | 1.85 | 0.69 | 5.34 | 3.68 | 0.69 | 1.01 | 1.91 | 0/1/0/0/0 | 1.0000 | 0.008 |
| css-stylesheet | 4 | 1.35 | 1.05 | 0.78 | 4.78 | 1.78 | 0.37 | 0.70 | 1.48 | 1/3/0/0/0 | 1.0000 | 0.000 |
| tailwind | 4 | 1.59 | 1.35 | 0.85 | 5.17 | 2.14 | 0.41 | 0.86 | 1.81 | 2/2/0/0/0 | 1.0000 | 0.000 |
| html | 4 | 1.55 | 0.97 | 0.63 | 4.68 | 2.24 | 0.48 | 0.98 | 1.52 | 0/4/0/0/0 | 1.0000 | 0.001 |
| pseudo-elements | 4 | 0.78 | 0.50 | 0.64 | 2.41 | 0.97 | 0.40 | 0.93 | 0.76 | 0/4/0/0/0 | 1.0000 | 0.000 |
| animation | 42 | 0.25 | 0.16 | 0.64 | 0.75 | 0.37 | 0.49 | 0.62 | 0.22 | 32/10/0/0/0 | 0.9997 | 0.000 |
| table | 8 | 1.17 | 0.70 | 0.60 | 2.54 | 1.27 | 0.50 | 0.99 | 0.93 | 0/8/0/0/0 | 1.0000 | 0.000 |
| float | 4 | 0.55 | 0.40 | 0.73 | 2.44 | 1.07 | 0.44 | 0.76 | 0.45 | 1/2/1/0/0 | 0.9511 | 0.419 |
| inline-block | 4 | 0.55 | 0.34 | 0.62 | 1.80 | 0.90 | 0.50 | 0.98 | 0.45 | 0/4/0/0/0 | 1.0000 | 0.000 |
| grid-areas | 3 | 0.71 | 0.54 | 0.75 | 2.13 | 0.94 | 0.44 | 0.88 | 0.63 | 0/3/0/0/0 | 1.0000 | 0.000 |
| **Tất cả (trừ known-gaps), geomean** | 175 | 1.09 | 0.71 | **0.65** | 3.41 | 1.62 | **0.48** | **0.76** | 0.93 | | | |

## Chưa port / còn khác takumi sau giai đoạn 2

- **PDF: không port.** `takumi-pdf` là gói npm riêng (không thuộc `@takumi-rs/wasm`), ~43 500 dòng Rust: phân trang, nhúng/cắt font, form tương tác — một sản phẩm khác.
- **Dòng inline:** float + chữ và chữ trong dòng hỗn hợp đã xong ở giai đoạn 3; các khoảng trống còn lại nằm trong mục "Giai đoạn 3" ở đầu file.
- **Shaping:** Indic chỉ kiểm chứng Devanagari + Bengali (các hệ khác dùng shaper mặc định); chuỗi emoji ZWJ có ca chưa gộp thành một glyph; ưu tiên font emoji khác takumi ở vài ca (©️, VS15).
- **SVG:** `<text>` chỉ qua hook; thiếu feTurbulence/feImage/feMorphology/feConvolveMatrix/feDisplacementMap/lighting/feTile; bảng SVG trong font chưa vẽ.
- **CSS:** `@apply`, `display: contents`, counter trong `content`, list marker, `animate-*` của Tailwind, animation trên pseudo-element, `clip-path: url()`, cú pháp màu tương đối, `outline-offset` theo %.
- **Sai khác 1 mức còn lại:** phần trong của gradient (takumi cộng dồn f32 theo từng span), viền nét đứt trên cạnh bo tròn, chữ bị xoay, `text-stroke`.
- **API:** `prepare()` không tự tải URL (takumi có); `setGlyphCacheMaxBytes` là no-op.
- **An toàn:** bản phát hành tắt kiểm tra; đã fuzz từng module và toàn pipeline trên ReleaseSafe cho cả ba profile (không trap).

---

# Báo cáo giai đoạn 1 (2026-11-11) — giữ để đối chiếu

Số liệu đầy đủ từng fixture: [RESULTS_FULL.md](RESULTS_FULL.md) (sinh tự động) và [results.json](results.json).
Ảnh từng ca: `bench/out/<id>/{takumi,bm,native,diff}.png` (chạy `node bench/run.mjs` để tạo lại).

## Điều kiện đo

- Máy: Intel Core i3-10100 @ 3.6 GHz (8 luồng), 7.8 GB RAM, Windows 11, Node v26.13.0. Ngày đo: 2026-11-11.
- Đối chứng: `@takumi-rs/wasm` 2.20.0 (bản wasm chính thức trên npm) và `@takumi-rs/core` 2.20.0 (native N-API, chỉ để tham khảo).
- bm-engine: `zig build` (optimize = small, wasm32-freestanding, simd128) + `wasm-opt -Oz`.
- 87 fixture trong `bench/fixtures/` (25 nhóm tính năng), cùng một cây node, cùng 9 font TTF tĩnh (Inter, Noto Sans,
  Roboto) đăng ký giống hệt nhau vào mọi engine.
- Thời gian: median của ≥ 20 lần lặp và ≥ 300 ms sau 3 lần warm-up, các engine chạy xen kẽ theo từng ca.
  `raw` = `render(..., {format:"raw"})` (RGBA thẳng), `png` = định dạng mặc định.
- Tương đương: so buffer `raw` của bm với takumi-wasm. **identical** = 0 byte khác; **equivalent** = SSIM ≥ 0.99 và
  ≤ 0.5 % điểm ảnh vượt ngưỡng pixelmatch 0.1; **close** = SSIM ≥ 0.95 và ≤ 5 %; còn lại **different**.
  SSIM lấy giá trị thấp hơn giữa SSIM độ sáng và SSIM RGB.
- Sàn nhiễu: takumi-native so với takumi-wasm **giống hệt từng byte ở cả 87 ca**, nên mọi sai khác của bm là sai khác thật.

## Tóm tắt

| Chỉ số | takumi-wasm 2.20 | bm-engine | Tỉ lệ |
|:--|--:|--:|:--|
| Kích thước `.wasm` | 4 234.9 KiB | **320.9 KiB** | nhỏ hơn **13.2×** |
| `.wasm` gzip -9 / brotli | 1 860.9 / 1 409.3 KiB | **147.1 / 126.5 KiB** | nhỏ hơn 12.7× / 11.1× |
| JS glue | 37.5 KiB (+ phụ thuộc `@takumi-rs/helpers`) | **9.5 KiB**, không phụ thuộc | nhỏ hơn 3.9× |
| Import của module wasm | shim wasm-bindgen | **0** | |
| Compile + instantiate wasm | 34.1 ms | **2.7 ms** | nhanh hơn 12.6× |
| Render đầu tiên (og-card PNG, tiến trình mới) | 151.7 ms | **74.7 ms** | nhanh hơn 2.0× |
| Cold start tổng (init + font + render đầu) | 188.1 ms | **79.5 ms** | nhanh hơn 2.4× (takumi-native: 44.8 ms) |
| Thời gian render `raw`, geomean 78 ca | 2.38 ms | **1.45 ms** | bm = 0.61× (nhanh hơn ở 70/78 ca; takumi-native: 1.99 ms) |
| Thời gian render `png`, geomean 78 ca | 8.09 ms | **5.84 ms** | bm = 0.72× (nhanh hơn ở 70/78 ca) |
| Dung lượng PNG xuất ra, geomean | 1.00 | **0.75** | nhỏ hơn 25 % |
| Bộ nhớ tuyến tính wasm sau init + 9 font | 6.3 MiB | 6.3 MiB | bằng nhau |
| Bộ nhớ tuyến tính wasm sau 50 lần render og-card PNG | **10.6 MiB** | 11.9 MiB | bm **nhiều hơn 12 %** |
| Peak RSS của tiến trình (50 lần render) | 99.6 MiB | **77.2 MiB** | ít hơn 22 % |
| Bộ nhớ wasm cuối toàn bộ lượt chạy (có canvas 3000×2000) | 66.4 MiB | 65.8 MiB | tương đương |
| Tương đương điểm ảnh trên 78 ca thuộc phạm vi đã port | — | 9 identical, 69 equivalent | 0 close / different / lỗi |
| 9 ca “known-gaps” (tính năng chưa port) | — | 1 equivalent, 2 close, 5 different, 1 lỗi | xem mục “Chưa port” |

## Theo từng tính năng

Thời gian là geomean của median (ms) các ca trong nhóm; tỉ lệ < 1 nghĩa là bm nhanh hơn / nhỏ hơn.
Cột tương đương: identical / equivalent / close / different / error.

| Tính năng | số ca | raw takumi-wasm | raw bm | bm/takumi | png takumi-wasm | png bm | bm/takumi | PNG bytes bm/takumi | raw takumi-native | tương đương | SSIM thấp nhất | % px lệch (TB) |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--|--:|--:|
| colors | 5 | 1.52 | 0.86 | 0.57 | 3.97 | 2.57 | 0.65 | 0.63 | 1.21 | 1/4/0/0/0 | 0.9999 | 0.010 |
| flex | 5 | 1.23 | 1.05 | 0.85 | 4.56 | 3.61 | 0.79 | 0.68 | 1.23 | 1/4/0/0/0 | 1.0000 | 0.000 |
| sizing (%, min/max, aspect-ratio, margin auto) | 5 | 0.87 | 0.80 | 0.92 | 4.52 | 3.08 | 0.68 | 0.39 | 1.01 | 3/2/0/0/0 | 1.0000 | 0.000 |
| absolute | 3 | 1.06 | 0.86 | 0.81 | 5.35 | 2.95 | 0.55 | 0.48 | 0.94 | 1/2/0/0/0 | 1.0000 | 0.000 |
| borders | 3 | 1.35 | 1.15 | 0.86 | 4.13 | 3.28 | 0.79 | 0.61 | 1.17 | 1/2/0/0/0 | 0.9980 | 0.030 |
| border-radius | 4 | 0.86 | 0.98 | **1.14** | 4.08 | 3.56 | 0.87 | 0.78 | 0.96 | 0/4/0/0/0 | 0.9999 | 0.001 |
| linear-gradient | 4 | 3.95 | 2.19 | 0.55 | 17.03 | 9.49 | 0.56 | 0.66 | 3.01 | 0/4/0/0/0 | 0.9998 | 0.014 |
| radial-gradient | 3 | 4.94 | 1.76 | 0.36 | 24.75 | 15.93 | 0.64 | 0.66 | 4.31 | 0/3/0/0/0 | 1.0000 | 0.000 |
| box-shadow | 4 | 5.86 | 3.16 | 0.54 | 15.85 | 8.34 | 0.53 | 0.97 | 4.07 | 0/4/0/0/0 | 0.9999 | 0.001 |
| opacity | 3 | 6.34 | 2.10 | 0.33 | 9.76 | 4.60 | 0.47 | 0.76 | 3.28 | 0/3/0/0/0 | 0.9998 | 0.004 |
| overflow (clip) | 3 | 1.59 | 0.96 | 0.60 | 5.43 | 3.66 | 0.67 | 0.76 | 1.41 | 0/3/0/0/0 | 0.9999 | 0.015 |
| transform | 3 | 2.93 | 1.74 | 0.59 | 6.03 | 4.61 | 0.77 | 0.96 | 2.19 | 0/3/0/0/0 | 0.9988 | 0.155 |
| text một dòng | 3 | 1.36 | 0.77 | 0.56 | 4.58 | 4.30 | 0.94 | 0.93 | 1.23 | 0/3/0/0/0 | 0.9993 | 0.200 |
| text đoạn văn (wrap, align, line-height, letter-spacing) | 5 | 2.31 | 1.34 | 0.58 | 6.89 | 6.13 | 0.89 | 0.88 | 1.90 | 0/5/0/0/0 | 0.9990 | 0.142 |
| fonts (weight, italic, nhiều family, fake bold) | 2 | 2.72 | 1.58 | 0.58 | 8.85 | 9.02 | **1.02** | 0.88 | 2.53 | 0/2/0/0/0 | 0.9991 | 0.362 |
| text-i18n (tiếng Việt, Latin có dấu) | 2 | 2.46 | 1.53 | 0.62 | 7.94 | 8.44 | **1.06** | 0.95 | 2.38 | 0/2/0/0/0 | 0.9994 | 0.233 |
| text-truncation (ellipsis, line-clamp) | 3 | 1.71 | 0.96 | 0.56 | 4.50 | 3.51 | 0.78 | 0.89 | 1.46 | 0/3/0/0/0 | 0.9998 | 0.047 |
| text-shadow | 1 | 1.00 | 1.00 | 1.00 | 4.36 | 5.44 | **1.25** | 1.01 | 0.70 | 0/1/0/0/0 | 0.9996 | 0.142 |
| filter (blur, grayscale) | 1 | 1.76 | 1.12 | 0.64 | 4.95 | 3.49 | 0.70 | 0.98 | 1.14 | 1/0/0/0/0 | 1.0000 | 0.000 |
| images (PNG/JPEG, object-fit, clip bo góc, background url) | 5 | 4.91 | 1.82 | 0.37 | 28.47 | 20.06 | 0.70 | 1.00 | 3.65 | 1/4/0/0/0 | 0.9994 | 0.011 |
| grid | 4 | 1.67 | 1.02 | 0.61 | 5.53 | 3.61 | 0.65 | 0.70 | 1.54 | 0/4/0/0/0 | 0.9999 | 0.001 |
| og-card (tổng hợp) | 2 | 4.21 | 2.25 | 0.54 | 13.52 | 13.75 | **1.02** | 0.97 | 3.16 | 0/2/0/0/0 | 0.9991 | 0.261 |
| blog-card (tổng hợp, có ảnh) | 2 | 10.68 | 4.78 | 0.45 | 31.33 | 15.33 | 0.49 | 0.71 | 6.04 | 0/2/0/0/0 | 0.9949 | 0.180 |
| stress (600 hộp, 200 nhãn, canvas 3000×2000) | 3 | 16.39 | 11.05 | 0.67 | 36.80 | 33.15 | 0.90 | 0.83 | 13.43 | 0/3/0/0/0 | 0.9991 | 0.062 |
| **Tất cả, geomean (78 ca)** | 78 | 2.38 | 1.45 | **0.61** | 8.09 | 5.84 | **0.72** | **0.75** | 1.99 | 9/69/0/0/0 | | |
| known-gaps (chưa port) | 9 | — | — | — | — | — | — | — | — | 0/1/2/5/1 | 0.2611 | 20.2 |

Chỗ bm **thua**: nhóm border-radius ở `raw` (1.14×: hình elip lớn đi qua rasterizer đường cong tổng quát, takumi/tiny-skia
nhanh hơn ở hình to); PNG của các ca nhiều chữ (fonts, text-i18n, og-card: 1.02–1.06×) và text-shadow (1.25×) — bộ nén
PNG của bm chậm hơn trên dữ liệu chữ khử răng cưa dù file nhỏ hơn.

### Bộ mã hoá (3 ca đại diện, 1200×630; ms median / byte)

| Ca | Định dạng | takumi-wasm | bm-engine |
|:--|:--|--:|--:|
| card-flat-ui (UI phẳng) | PNG | 19.93 ms / 25 948 B | **7.13 ms / 13 381 B** |
| | JPEG q75 4:4:4 | 25.14 ms / 50 167 B | **17.63 ms / 47 298 B** |
| | WebP lossless | 12.33 ms / 28 238 B | **8.99 ms / 11 134 B** |
| lingrad-angles (gradient) | PNG | 35.33 ms / 104 338 B | **14.50 ms / 32 991 B** |
| | JPEG | 24.68 ms / 53 557 B | **19.28 ms / 53 465 B** |
| | WebP lossless | 15.58 ms / 173 498 B | **11.57 ms / 29 580 B** |
| img-photo-bg (ảnh chụp) | PNG | 55.27 ms / 524 989 B | **47.60 ms / 523 396 B** |
| | JPEG | 24.86 ms / 56 484 B | **17.88 ms / 56 442 B** |
| | WebP lossless | **21.50 ms** / 481 634 B | 45.94 ms / **414 512 B** (chậm hơn 2.1×, nhỏ hơn 14 %) |

## Kết quả đầu ra tương đương tới đâu

- **Layout**: `measure()` của bm khớp takumi trong 0.001 px ở toàn bộ 73 fixture không có transform
  (`node bench/probe/lay.mjs "^(?!transform)" 0.001`). Bộ test layout riêng: 839/850 cây ngẫu nhiên + viết tay khớp
  takumi; 11 ca lệch đều liên quan `aspect-ratio` trên flex container tự co giãn (liệt kê trong
  `src/layout/testdata/oracle_xfail.txt`).
- **Text**: bề rộng dòng, vị trí ngắt dòng, chiều cao dòng khớp takumi ở 825/825 phép so của module font
  (Latin, tiếng Việt, kerning, ligature, letter-spacing, 5 chế độ white-space, ellipsis, line-clamp).
- **Gradient / shadow**: 25/27 ca kiểm tra riêng của module raster trùng từng byte với takumi; 2 ca còn lại lệch tối đa 1 mức.
- **9 ca identical**: nền đặc, box có biên nguyên, filter blur/grayscale…
- **69 ca equivalent**: khác biệt còn lại nằm ở **khử răng cưa** của mép cong và glyph. takumi dùng tiny-skia
  (siêu lấy mẫu 4×4 theo cạnh fixed-point); bm rasterize theo diện tích chính xác rồi lượng tử về 17 mức, riêng glyph
  thì quét ở 4× rồi gộp 4×4 để bắt chước. Vì vậy điểm ảnh ở mép có thể lệch tới ~60/255 (một mẫu con), nhưng tỉ lệ
  điểm ảnh lệch quá ngưỡng trung bình chỉ 0.00–0.36 % mỗi nhóm, SSIM ≥ 0.9949 ở mọi ca (thấp nhất: `card-flat-ui`, do
  viền `dashed` bị vẽ thành nét liền).
- JPEG giải mã: lệch tối đa 4/255 so với takumi (khác biệt làm tròn IDCT của zune-jpeg; bm trùng mozjpeg).

## Chưa port / khác takumi (trung thực)

Có fixture chứng minh (`bench/fixtures/gaps.mjs`):

| Ca | Kết quả | Lý do |
|:--|:--|:--|
| gap-tailwind-tw | different (SSIM 0.26) | prop `tw` (Tailwind) không được hỗ trợ — bị bỏ qua |
| gap-oklch-color | **lỗi** | `oklch()`, `lab()`, `color-mix()`, `color()` bị từ chối (takumi hỗ trợ) |
| gap-svg-image | different | không có trình render SVG (takumi tự có SVG engine) |
| gap-dashed-dotted-border | different | viền dashed/dotted/double được vẽ thành nét liền |
| gap-clip-path | different | `clip-path`, `mask-*` không hỗ trợ |
| gap-background-clip-text | different | `background-clip: text` không hỗ trợ |
| gap-mix-blend-mode | close | chỉ có source-over |
| gap-text-wrap-balance | close | `text-wrap: balance/pretty` bị coi như wrap thường |
| gap-inline-box-decoration | equivalent (ngẫu nhiên) | span inline có nền/padding riêng: bm bỏ qua trang trí hộp inline |

Không có fixture nhưng đã biết:

- **Font**: chỉ TrueType tĩnh `.ttf`/`.ttc` (face đầu tiên). Không WOFF/WOFF2, không font biến thiên (variable), không
  outline CFF (`.otf`), không emoji màu (COLR/CBDT). takumi hỗ trợ tất cả và kèm sẵn font Geist; bm không kèm font nào.
- **Shaping**: chỉ LTR đơn giản — kerning GPOS cặp, GSUB loại 1/4 và ngữ cảnh dạng 3. Không bidi/RTL, không chữ phức
  (Ả Rập, Devanagari…), không định vị dấu (mark positioning; tiếng Việt dựng sẵn NFC thì ổn), ngắt dòng là tập con
  UAX #14 (CJK chỉ được test ở mức đơn vị).
- **CSS**: không stylesheet/selector/cascade (`css`, `className`, `@media`), không `var()`, không animation/keyframes
  (`timeMs`, `renderAnimation`), không HTML đầu vào, không `renderSvg`, không PDF, không bảng (table), float, list marker.
  Thuộc tính logic (`margin-inline`…), `grid-template-areas`, tên đường lưới, `outline` (parse nhưng chưa vẽ),
  `drop-shadow()`, `filter: url()`, `backdrop-filter` chưa có.
- **Ảnh**: không giải mã WebP lossy (VP8), GIF/APNG chỉ khung đầu; ảnh lớn được cache cả bản gốc lẫn bản thu nhỏ
  (takumi chỉ giữ bản thu nhỏ); không tự tải URL (`prepare()` của takumi làm việc này).
- **Xuất**: không ICO, không ảnh động; WebP chỉ lossless (giống bản wasm của takumi).
- **Giới hạn**: cây node sâu tối đa 128 cấp (takumi 512), canvas tối đa 16384 px mỗi cạnh và 40 Mpx.
- **API**: `registerFont` đồng bộ và trả về `{name, weight, style}` (takumi trả `Promise<RegisteredFamily[]>`); chưa có
  `fontFamilies`, `unicodeRange`, `unregisterFont`, `dithering`, `drawDebugBorder`, `lang`.
- **Chất lượng mã**: đã fuzz toàn pipeline trên bản ReleaseSafe (~8 000 cây ngẫu nhiên, không trap) và fuzz riêng từng
  bộ giải mã/parser, nhưng bản phát hành tắt kiểm tra an toàn (`optimize = small`), nên lỗi còn sót sẽ là hỏng bộ nhớ
  trong sandbox wasm chứ không phải panic. Chưa chạy thử trong trình duyệt thật — chỉ kiểm tra đường `init(Response)`
  + `index.mjs` bằng Node (`bench/probe/browserlike.mjs`); module không có import nên rủi ro thấp nhưng chưa được xác minh.

## Vì sao nhỏ và nhanh hơn

1. takumi 2.x là bản port LayoutNG + paint của Blink sang Rust (table, float, cascade, selector, HTML parser, SVG engine,
   ICU4X, HarfBuzz port…) ⇒ 4.2 MB. bm chỉ giữ phần phục vụ ảnh OG từ cây node với style inline (~26 000 dòng Zig).
2. Không tokenizer CSS tổng quát, không serde/wasm-bindgen: một lần `JSON.stringify`, một parser JSON ~300 dòng.
3. Bump allocator tái sử dụng chunk giữa các lần render; canvas, cache glyph, cache ảnh nằm ngoài arena; PNG nén theo
   luồng từng hàng (không tạo bản sao ảnh đã lọc).
4. Hộp bo góc lớn chỉ rasterize 4 ô góc; nhóm opacity chỉ cấp vùng bao của cây con; mask glyph được cache theo pha ¼ px.
5. PNG: tự chọn indexed/RGB/RGBA + bộ dò khớp “1 pixel trước / 1 hàng trên”.

## Kết luận

Trong phạm vi đã port (flex/grid/block, box model, gradient, shadow, opacity, clip, transform, text Latin/tiếng Việt với
font TTF tĩnh, ảnh PNG/JPEG, xuất PNG/JPEG/WebP), bản Zig **tốt hơn rõ rệt** về kích thước (13×), cold start (2.4×),
tốc độ render (raw nhanh hơn ~1.6×, PNG ~1.4×) và dung lượng PNG (−25 %), với đầu ra tương đương về thị giác (SSIM ≥ 0.994,
layout khớp tới 1/64 px) nhưng **không trùng từng byte** ở các mép khử răng cưa. Nó **thua** ở bộ nhớ tuyến tính wasm
(+12 %), WebP lossless với ảnh chụp (chậm hơn 2×), và hình bo tròn lớn.

Nó **chưa thay thế được takumi**: takumi là một engine CSS gần như đầy đủ (Tailwind, stylesheet, SVG, font biến thiên,
WOFF2, emoji màu, chữ phức, animation). Lợi thế kích thước của bm đến chủ yếu từ việc *không làm* những thứ đó, nên con
số 13× không phải là so sánh ngang tính năng; thêm font biến thiên + WOFF2 + shaping đầy đủ sẽ làm bản Zig lớn lên
đáng kể. Lựa chọn hợp lý: dùng bm-engine khi đầu vào nằm trong tập con ở trên và cần wasm nhỏ / khởi động nhanh
(edge, trình duyệt); dùng takumi khi cần độ phủ CSS.
