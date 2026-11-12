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
| bm-engine | 0.1.0, git `ef21c5674b` (integ, 4 file đang sửa) |
| bm-native | `native/dist/win32-x64-msvc/bm-engine.win32-x64-msvc.node`, 2 083 KiB, Zig 0.17.1, ReleaseFast, sha256 `ec92d1feb24f` |
| bm-wasm | `js/bm_engine.wasm` (profile full), 1 140 KiB, sha256 `7a7e363d2c98` |
| takumi-native | `@takumi-rs/core` 2.20.0 + `@takumi-rs/core-win32-x64-msvc` 2.20.0, 9 796 KiB |
| takumi-wasm | `@takumi-rs/wasm` 2.20.0, 4 235 KiB |
| Lần chạy | 2026-11-12 11:03 UTC, chế độ full, 250 fixtures, 16.6 min; CPU bận trước khi chạy: 53.5 % |
<!-- /native-bench:env -->

### Tóm tắt

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

Theo nhóm fixture:

<!-- native-bench:categories -->
| Nhóm | n | raw bm-n sync | raw bm-n async | raw bm-w | raw tk-n | raw tk-w | raw bm-n/tk-n | png bm-n sync | png bm-n async | png bm-w | png tk-n | png tk-w | png bm-n/tk-n |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| aa-exact | 2 | 0.41 | 0.43 | 0.59 | 0.77 | 1.01 | 0.56× | 0.75 | 0.82 | 1.16 | 1.47 | 2.37 | 0.56× |
| absolute | 3 | 0.88 | 0.91 | 1.29 | 1.12 | 1.69 | 0.81× | 1.69 | 1.86 | 2.52 | 3.20 | 6.29 | 0.58× |
| animation | 44 | 0.15 | 0.17 | 0.25 | 0.35 | 0.44 | 0.49× | 0.25 | 0.25 | 0.36 | 0.65 | 0.92 | 0.38× |
| backdrop-filter | 1 | 1.46 | 1.54 | 2.74 | 2.67 | 4.54 | 0.58× | 2.23 | 2.30 | 4.00 | 3.25 | 8.05 | 0.71× |
| bg-blend | 1 | 0.75 | 0.89 | 1.67 | 5.07 | 6.10 | 0.18× | 3.04 | 3.04 | 4.76 | 5.54 | 12.4 | 0.55× |
| bg-clip-text | 1 | 0.43 | 0.48 | 0.61 | 2.28 | 3.05 | 0.21× | 1.58 | 1.61 | 2.24 | 2.87 | 5.94 | 0.56× |
| block-in-inline | 4 | 0.34 | 0.36 | 0.55 | 0.82 | 1.02 | 0.44× | 0.64 | 0.64 | 0.92 | 1.37 | 1.89 | 0.47× |
| blog-card | 2 | 4.59 | 4.59 | 8.21 | 5.89 | 12.0 | 0.78× | 10.7 | 10.8 | 16.6 | 9.52 | 32.3 | 1.13× |
| border-radius | 4 | 0.98 | 1.03 | 1.57 | 1.15 | 1.52 | 0.89× | 2.04 | 1.97 | 2.84 | 2.91 | 6.33 | 0.68× |
| borders | 3 | 0.96 | 1.08 | 1.67 | 1.41 | 2.11 | 0.77× | 1.60 | 1.61 | 2.43 | 2.90 | 5.30 | 0.55× |
| box-shadow | 4 | 1.97 | 2.18 | 3.70 | 4.33 | 6.58 | 0.50× | 4.90 | 4.89 | 8.12 | 6.10 | 17.4 | 0.80× |
| clip-path | 1 | 0.44 | 0.47 | 0.76 | 0.76 | 1.09 | 0.61× | 1.33 | 1.40 | 2.08 | 1.77 | 6.28 | 0.79× |
| colors | 5 | 0.74 | 0.83 | 1.32 | 1.31 | 2.02 | 0.64× | 1.10 | 1.13 | 1.73 | 2.71 | 4.55 | 0.42× |
| css-stylesheet | 8 | 0.58 | 0.64 | 0.92 | 0.99 | 1.22 | 0.65× | 0.91 | 0.92 | 1.34 | 2.03 | 3.27 | 0.45× |
| dashed-border | 1 | 1.00 | 1.32 | 2.02 | 1.81 | 3.23 | 0.73× | 1.13 | 1.21 | 1.76 | 2.20 | 3.55 | 0.55× |
| dotted-border | 1 | 0.95 | 0.99 | 1.68 | 1.97 | 3.01 | 0.50× | 1.78 | 1.39 | 3.13 | 3.26 | 4.92 | 0.43× |
| double-3d-border | 1 | 0.35 | 0.39 | 0.62 | 0.59 | 0.80 | 0.66× | 0.55 | 0.58 | 0.85 | 1.20 | 1.70 | 0.49× |
| drop-shadow | 1 | 0.81 | 0.80 | 1.35 | 1.18 | 1.71 | 0.68× | 2.28 | 2.29 | 3.61 | 1.98 | 7.22 | 1.16× |
| emoji | 5 | 0.14 | 0.15 | 0.22 | 0.51 | 0.65 | 0.28× | 0.53 | 0.53 | 0.74 | 0.81 | 1.05 | 0.66× |
| filter | 1 | 0.65 | 0.69 | 1.31 | 1.29 | 1.93 | 0.53× | 1.79 | 1.84 | 2.98 | 2.02 | 5.18 | 0.91× |
| flex | 5 | 0.89 | 0.96 | 1.43 | 1.19 | 1.74 | 0.81× | 1.46 | 1.47 | 2.13 | 2.82 | 5.21 | 0.52× |
| float | 4 | 0.31 | 0.33 | 0.55 | 0.61 | 0.78 | 0.55× | 0.74 | 0.74 | 1.09 | 1.37 | 2.64 | 0.54× |
| float-paint-order | 3 | 0.42 | 0.45 | 0.71 | 0.90 | 1.09 | 0.50× | 0.67 | 0.68 | 1.00 | 1.29 | 1.74 | 0.52× |
| float-text | 7 | 0.49 | 0.54 | 0.80 | 0.91 | 1.15 | 0.59× | 1.19 | 1.18 | 1.67 | 1.76 | 2.98 | 0.67× |
| font-variant | 3 | 0.40 | 0.44 | 0.62 | 0.96 | 1.19 | 0.45× | 1.18 | 1.19 | 1.63 | 1.87 | 3.23 | 0.63× |
| fonts | 2 | 1.35 | 1.51 | 2.16 | 2.34 | 3.19 | 0.64× | 3.93 | 4.12 | 5.42 | 4.41 | 10.1 | 0.94× |
| grid | 4 | 0.99 | 1.07 | 1.57 | 1.63 | 2.11 | 0.65× | 1.74 | 1.67 | 2.75 | 3.41 | 6.49 | 0.49× |
| grid-areas | 3 | 0.35 | 0.42 | 0.71 | 0.78 | 0.94 | 0.54× | 0.71 | 0.78 | 1.12 | 1.61 | 2.34 | 0.48× |
| html | 4 | 0.77 | 0.80 | 1.11 | 1.34 | 1.73 | 0.59× | 1.68 | 1.70 | 2.41 | 2.84 | 5.06 | 0.60× |
| images | 7 | 1.02 | 1.10 | 2.00 | 3.01 | 4.24 | 0.37× | 8.59 | 8.94 | 13.5 | 6.50 | 23.7 | 1.37× |
| inline-bidi | 3 | 0.51 | 0.52 | 0.82 | 1.09 | 1.40 | 0.48× | 0.93 | 0.93 | 1.35 | 1.65 | 2.50 | 0.56× |
| inline-block | 4 | 0.33 | 0.38 | 0.58 | 0.71 | 0.86 | 0.53× | 0.79 | 0.80 | 1.16 | 1.45 | 2.13 | 0.56× |
| inline-box | 1 | 1.32 | 1.30 | 2.24 | 2.12 | 2.92 | 0.61× | 2.61 | 2.65 | 3.99 | 3.03 | 6.43 | 0.88× |
| inline-box-model | 4 | 0.70 | 0.74 | 1.14 | 1.26 | 1.67 | 0.59× | 1.54 | 1.57 | 2.24 | 2.12 | 3.72 | 0.74× |
| inline-flow | 5 | 0.47 | 0.49 | 0.82 | 0.92 | 1.17 | 0.53× | 1.11 | 1.12 | 1.68 | 1.70 | 2.97 | 0.66× |
| inline-relative | 1 | 0.52 | 0.53 | 0.78 | 1.09 | 1.33 | 0.48× | 0.86 | 0.88 | 1.23 | 1.55 | 2.11 | 0.57× |
| known-gaps | 9 | 0.30 | 0.32 | 0.48 | 0.63 | 0.85 | 0.51× | 0.62 | 0.63 | 0.91 | 1.31 | 2.36 | 0.48× |
| linear-gradient | 4 | 1.83 | 1.99 | 3.14 | 3.75 | 5.13 | 0.53× | 5.03 | 4.98 | 7.65 | 5.80 | 20.8 | 0.86× |
| mask | 1 | 0.82 | 0.84 | 1.30 | 1.36 | 1.82 | 0.62× | 2.46 | 2.27 | 2.97 | 2.41 | 9.13 | 0.94× |
| mix-blend | 1 | 1.13 | 1.20 | 1.86 | 1.61 | 3.02 | 0.74× | 2.91 | 3.06 | 4.63 | 2.31 | 8.53 | 1.33× |
| mixed-border | 1 | 0.56 | 0.59 | 1.08 | 0.92 | 1.35 | 0.65× | 0.73 | 0.71 | 1.11 | 1.57 | 2.18 | 0.45× |
| og-card | 2 | 1.97 | 1.93 | 3.21 | 3.64 | 5.21 | 0.53× | 6.72 | 6.44 | 9.81 | 5.71 | 14.1 | 1.13× |
| opacity | 4 | 1.36 | 1.45 | 2.59 | 2.86 | 5.51 | 0.51× | 2.33 | 2.43 | 3.83 | 4.34 | 9.70 | 0.56× |
| outline | 1 | 0.62 | 0.79 | 1.19 | 1.24 | 1.92 | 0.64× | 0.86 | 0.86 | 1.34 | 1.96 | 2.91 | 0.44× |
| overflow | 3 | 0.82 | 0.96 | 1.44 | 1.64 | 2.09 | 0.58× | 1.69 | 1.66 | 2.57 | 3.38 | 6.15 | 0.49× |
| pseudo-elements | 4 | 0.42 | 0.46 | 0.69 | 0.79 | 1.03 | 0.58× | 0.77 | 0.71 | 1.08 | 1.53 | 2.59 | 0.46× |
| radial-gradient | 3 | 1.34 | 1.62 | 2.34 | 4.41 | 5.62 | 0.37× | 9.05 | 9.45 | 13.1 | 8.06 | 27.3 | 1.17× |
| rtl | 5 | 0.31 | 0.34 | 0.57 | 0.67 | 0.83 | 0.51× | 0.47 | 0.48 | 0.75 | 1.06 | 1.49 | 0.45× |
| sizing | 5 | 0.69 | 0.76 | 1.03 | 0.93 | 1.26 | 0.82× | 1.23 | 1.18 | 1.70 | 2.94 | 5.15 | 0.40× |
| stress | 3 | 7.84 | 8.93 | 13.1 | 12.8 | 17.4 | 0.70× | 17.5 | 17.2 | 26.4 | 18.4 | 39.9 | 0.94× |
| svg-image | 1 | 0.69 | 0.75 | 1.48 | 0.71 | 1.01 | 1.05× | 1.39 | 1.74 | 3.13 | 1.82 | 2.92 | 0.96× |
| table | 8 | 0.53 | 0.54 | 0.88 | 1.09 | 1.41 | 0.50× | 0.92 | 0.92 | 1.43 | 1.73 | 2.76 | 0.53× |
| tailwind | 8 | 0.72 | 0.74 | 1.14 | 1.12 | 1.53 | 0.66× | 1.01 | 1.01 | 1.52 | 1.96 | 3.22 | 0.52× |
| text-decoration | 1 | 1.12 | 1.21 | 1.90 | 1.37 | 1.90 | 0.89× | 1.98 | 1.95 | 3.00 | 2.12 | 3.95 | 0.92× |
| text-i18n | 2 | 1.28 | 1.31 | 1.70 | 2.30 | 2.69 | 0.57× | 3.11 | 3.19 | 4.21 | 4.07 | 8.48 | 0.78× |
| text-indent | 4 | 0.50 | 0.51 | 0.78 | 1.03 | 1.27 | 0.50× | 1.08 | 1.09 | 1.49 | 1.66 | 2.67 | 0.66× |
| text-overflow | 4 | 0.33 | 0.36 | 0.50 | 0.86 | 1.07 | 0.42× | 0.66 | 0.67 | 0.94 | 1.49 | 2.14 | 0.45× |
| text-paragraph | 5 | 1.33 | 1.43 | 2.00 | 2.22 | 3.10 | 0.65× | 2.86 | 2.86 | 3.85 | 4.04 | 7.83 | 0.71× |
| text-shadow | 1 | 0.64 | 0.65 | 1.15 | 0.93 | 1.19 | 0.70× | 2.67 | 2.76 | 4.04 | 2.07 | 4.57 | 1.33× |
| text-single-line | 3 | 0.81 | 0.86 | 1.21 | 1.47 | 1.92 | 0.59× | 1.74 | 1.79 | 2.33 | 2.91 | 5.10 | 0.61× |
| text-stroke | 2 | 0.79 | 0.85 | 1.45 | 0.72 | 0.97 | 1.18× | 1.40 | 1.39 | 2.07 | 1.39 | 2.40 | 1.00× |
| text-truncation | 3 | 0.81 | 0.95 | 1.26 | 1.49 | 1.96 | 0.64× | 1.50 | 1.51 | 2.02 | 2.85 | 4.97 | 0.53× |
| text-wrap-balance | 3 | 0.64 | 0.64 | 1.00 | 1.22 | 1.63 | 0.52× | 1.17 | 1.20 | 1.70 | 1.89 | 3.16 | 0.63× |
| transform | 5 | 0.69 | 0.73 | 1.09 | 1.49 | 2.30 | 0.49× | 1.16 | 1.23 | 1.77 | 2.47 | 4.48 | 0.50× |
| visibility | 1 | 0.21 | 0.23 | 0.33 | 0.44 | 0.54 | 0.51× | 0.30 | 0.32 | 0.41 | 1.12 | 1.39 | 0.29× |

Geomean ms theo nhóm fixture. bm-n = bm-native, bm-w = bm-wasm (sync), tk-n = takumi-native (async), tk-w = takumi-wasm; tỉ lệ = bm-native async / takumi-native async (dưới 1× = bm nhanh hơn).
<!-- /native-bench:categories -->

bm-native so với takumi-native (cùng async):

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

### Tương đương và trùng byte

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

### Cold start

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

### Bộ nhớ

<!-- native-bench:memory -->
| Engine | RSS sau khởi tạo | RSS sau lượt 1 → 10 | bộ nhớ engine 1 → N | JS heap 1 → N | RSS đỉnh, cả bộ | RSS đỉnh PNG 4000×4000 (tăng thêm) |
|:--|--:|--:|--:|--:|--:|--:|
| bm-native | 67.2 | 94.7 → 96.0 | 31.6 → 31.6 | 7.50 → 6.40 | 186 | 143 (85.8) |
| bm-wasm | 75.0 | 132 → 156 | 65.1 → 88.1 | 6.60 → 6.70 | 253 | 149 (89.3) |
| takumi-native | 70.4 | 102 → 139 | — → — | 7.70 → 6.70 | 201 | 135 (74.8) |
| takumi-wasm | 86.0 | 140 → 176 | 71.5 → 71.5 | 7.40 → 7.50 | 237 | 151 (83.6) |

MiB, sau khi ép GC. Một tiến trình cho mỗi engine; mỗi lượt render mọi fixture ra raw và PNG (API async), một renderer cho mỗi bộ font. Bộ nhớ engine: bm-native = số byte addon đang cấp phát (`memoryBytes()`), bm-wasm / takumi-wasm = bộ nhớ tuyến tính wasm, takumi-native = không công bố. Node rỗng: 45.0 MiB RSS. "Tăng thêm" = RSS đỉnh trừ RSS ngay trước lần render 4000×4000.
<!-- /native-bench:memory -->

### Event loop

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

### Nhiễu

<!-- native-bench:noise -->
| Giai đoạn | bắt đầu (UTC) | thời lượng | CPU bận ngay trước | CPU bận trong lúc đo | tiến trình khác, lõi |
|:--|--:|--:|--:|--:|--:|
| speed lượt 1 | 11:03 | 160 s | 46.9 % | 58.1 % (max 83.3 %) | 3.50 |
| speed lượt 2 | 11:07 | 190 s | 45.8 % | 79.6 % (max 99.6 %) | 5.32 |
| speed lượt 3 | 11:12 | 152 s | 32.0 % | 48.4 % (max 75.1 %) | 2.70 |
| cold |  | 23.6 s |  | 76.7 % (max 97.0 %) | 4.78 |
| memory |  | 60.3 s |  | 50.1 % (max 70.8 %) | 2.82 |
| eventloop |  | 12.9 s |  | 48.7 % (max 56.9 %) | 2.95 |
| throughput |  | 286.1 s |  | 56.8 % (max 100 %) | 2.14 |

"Tiến trình khác" = số lõi-giây bận của cả máy trừ thời gian CPU của chính benchmark, chia cho thời gian thực (8 CPU logic). Số fixture có median lệch quá 10 % giữa các lượt: bm-native:sync raw: 225, bm-native:sync png: 209, bm-native:async raw: 235, bm-native:async png: 228, bm-wasm:sync raw: 228, bm-wasm:sync png: 192, takumi-native:async raw: 241, takumi-native:async png: 236, takumi-wasm:async raw: 222, takumi-wasm:async png: 198. 20 geomean tuyệt đối (biến thể × định dạng) lệch quá 10 % giữa các lượt (khoảng lệch lớn nhất: 53.7 %), vì vậy các bảng ưu tiên tỉ lệ đo trong từng lượt. Tỉ lệ giữa engine lệch quá 10 %: ratio takumi-native:async/takumi-wasm:async jpeg: range between passes 15.5 %.
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
| `colors-solid-bg` | colors | 0.23 / 0.48 | 0.25 / 0.89 | 0.40 / 0.61 | 0.41 / 1.46 | 0.63 / 0.97 | 0.62× | 0.57× | 0.25 / 0.42 | 0.28 / 0.54 | 0.50 / 0.64 | 1.22 / 1.74 | 1.60 / 2.46 | 0.23× | 0.49× |
| `colors-hex` | colors | 1.96 / 3.37 | 2.12 / 3.07 | 3.84 / 4.69 | 3.18 / 4.19 | 6.15 / 10.2 | 0.67× | 0.51× | 2.24 / 3.17 | 2.40 / 2.96 | 3.64 / 4.33 | 4.97 / 5.94 | 9.37 / 12.0 | 0.48× | 0.61× |
| `colors-functional` | colors | 1.22 / 2.24 | 1.41 / 2.21 | 2.45 / 3.48 | 2.27 / 2.94 | 3.20 / 4.23 | 0.62× | 0.50× | 2.10 / 2.90 | 2.01 / 2.54 | 3.23 / 5.10 | 4.71 / 5.73 | 9.10 / 11.0 | 0.43× | 0.65× |
| `colors-named` | colors | 1.29 / 1.86 | 1.44 / 2.23 | 2.12 / 3.06 | 2.20 / 2.82 | 3.43 / 4.12 | 0.65× | 0.61× | 2.87 / 3.66 | 2.94 / 4.00 | 3.81 / 5.56 | 5.29 / 6.36 | 9.34 / 11.3 | 0.56× | 0.75× |
| `colors-transparent-canvas` | colors | 0.31 / 0.52 | 0.37 / 0.61 | 0.51 / 0.90 | 0.59 / 1.12 | 0.79 / 1.41 | 0.62× | 0.62× | 0.48 / 0.72 | 0.46 / 0.68 | 0.69 / 1.12 | 0.97 / 1.44 | 1.53 / 2.09 | 0.48× | 0.70× |
| `flex-row-column` | flex | 1.11 / 4.45 | 1.16 / 2.23 | 1.63 / 2.73 | 1.23 / 1.92 | 1.54 / 2.41 | 0.94× | 0.68× | 2.15 / 3.13 | 2.24 / 2.62 | 3.19 / 4.51 | 3.91 / 4.58 | 7.98 / 10.0 | 0.57× | 0.68× |
| `flex-justify-align` | flex | 1.36 / 2.56 | 1.50 / 2.63 | 2.14 / 3.09 | 1.65 / 2.83 | 3.05 / 4.98 | 0.91× | 0.64× | 2.06 / 2.98 | 1.90 / 2.62 | 2.94 / 4.24 | 3.47 / 3.86 | 7.44 / 8.60 | 0.55× | 0.70× |
| `flex-wrap-gap` | flex | 1.42 / 2.44 | 1.54 / 2.13 | 2.53 / 3.06 | 1.72 / 2.29 | 2.84 / 3.58 | 0.89× | 0.56× | 2.73 / 3.67 | 2.79 / 3.76 | 4.00 / 5.03 | 4.02 / 4.83 | 7.99 / 11.1 | 0.69× | 0.68× |
| `flex-grow-shrink-basis` | flex | 1.20 / 1.91 | 1.23 / 2.00 | 1.84 / 2.32 | 1.53 / 2.04 | 2.25 / 2.67 | 0.81× | 0.65× | 1.54 / 2.41 | 1.58 / 2.13 | 2.17 / 3.36 | 3.38 / 4.11 | 6.18 / 7.52 | 0.47× | 0.71× |
| `flex-nested-small` | flex | 0.22 / 0.35 | 0.25 / 0.72 | 0.36 / 0.65 | 0.44 / 1.16 | 0.53 / 0.80 | 0.56× | 0.61× | 0.35 / 0.55 | 0.37 / 0.53 | 0.53 / 0.84 | 0.97 / 1.27 | 1.30 / 2.01 | 0.38× | 0.66× |
| `sizing-percent` | sizing | 0.92 / 1.65 | 0.98 / 2.16 | 1.39 / 1.96 | 1.31 / 1.74 | 2.00 / 2.64 | 0.75× | 0.66× | 2.27 / 2.67 | 2.12 / 2.71 | 2.91 / 3.93 | 4.77 / 5.57 | 8.53 / 11.4 | 0.44× | 0.78× |
| `sizing-minmax` | sizing | 0.98 / 3.72 | 0.96 / 2.33 | 1.42 / 2.58 | 1.18 / 1.88 | 1.67 / 2.09 | 0.81× | 0.69× | 1.73 / 2.21 | 1.62 / 2.02 | 2.19 / 3.14 | 3.95 / 5.21 | 7.39 / 8.68 | 0.41× | 0.79× |
| `sizing-aspect-ratio` | sizing | 0.95 / 1.49 | 1.08 / 1.78 | 1.37 / 2.32 | 1.09 / 1.72 | 1.48 / 2.16 | 1.00× | 0.69× | 1.63 / 2.32 | 1.51 / 2.05 | 2.36 / 3.30 | 3.98 / 4.48 | 7.14 / 7.95 | 0.38× | 0.69× |
| `sizing-padding-margin` | sizing | 1.01 / 1.37 | 1.22 / 1.85 | 1.40 / 2.20 | 1.21 / 1.66 | 1.57 / 2.80 | 1.01× | 0.73× | 1.52 / 2.18 | 1.47 / 2.54 | 2.25 / 3.50 | 3.88 / 4.92 | 7.38 / 9.15 | 0.38× | 0.67× |
| `sizing-auto-margin-center` | sizing | 0.18 / 0.27 | 0.20 / 0.41 | 0.31 / 0.47 | 0.34 / 0.58 | 0.42 / 0.67 | 0.61× | 0.59× | 0.29 / 0.43 | 0.30 / 0.41 | 0.43 / 0.66 | 0.75 / 1.04 | 1.09 / 1.73 | 0.40× | 0.68× |
| `abs-inset` | absolute | 1.08 / 4.10 | 1.28 / 2.27 | 1.64 / 2.55 | 1.44 / 2.02 | 2.32 / 3.16 | 0.89× | 0.66× | 2.21 / 3.18 | 2.28 / 3.24 | 3.09 / 4.81 | 4.71 / 5.34 | 8.90 / 13.5 | 0.48× | 0.72× |
| `abs-zorder` | absolute | 2.09 / 4.97 | 1.78 / 2.58 | 2.75 / 3.76 | 1.51 / 2.26 | 2.75 / 3.32 | 1.18× | 0.76× | 4.87 / 6.74 | 5.14 / 7.48 | 7.71 / 10.3 | 4.81 / 6.20 | 16.2 / 18.8 | 1.07× | 0.63× |
| `abs-in-flow` | absolute | 0.30 / 0.43 | 0.33 / 0.52 | 0.47 / 0.79 | 0.64 / 0.83 | 0.75 / 1.12 | 0.51× | 0.63× | 0.44 / 0.68 | 0.55 / 0.77 | 0.67 / 1.02 | 1.45 / 1.57 | 1.73 / 2.50 | 0.38× | 0.66× |
| `borders-uniform` | borders | 1.04 / 2.02 | 1.16 / 2.60 | 1.64 / 2.80 | 1.79 / 2.57 | 2.40 / 3.00 | 0.65× | 0.64× | 2.10 / 3.57 | 2.03 / 3.88 | 3.32 / 5.74 | 4.61 / 5.17 | 7.61 / 10.3 | 0.44× | 0.63× |
| `borders-per-side` | borders | 1.11 / 1.48 | 1.26 / 1.84 | 1.96 / 2.89 | 1.73 / 2.59 | 2.47 / 3.47 | 0.73× | 0.56× | 2.38 / 3.61 | 2.29 / 3.84 | 3.51 / 4.91 | 4.07 / 4.76 | 8.12 / 11.8 | 0.56× | 0.68× |
| `borders-with-radius` | borders | 0.77 / 0.92 | 0.87 / 1.15 | 1.44 / 1.78 | 0.92 / 1.14 | 1.59 / 2.09 | 0.95× | 0.53× | 0.82 / 1.28 | 0.89 / 1.40 | 1.24 / 2.04 | 1.30 / 1.62 | 2.40 / 3.21 | 0.68× | 0.66× |
| `radius-uniform-percorner` | border-radius | 1.54 / 3.08 | 1.40 / 1.97 | 2.27 / 3.64 | 1.66 / 3.09 | 2.15 / 2.82 | 0.85× | 0.68× | 2.70 / 3.78 | 2.69 / 3.41 | 3.68 / 4.36 | 3.94 / 4.53 | 8.27 / 11.6 | 0.68× | 0.73× |
| `radius-elliptical` | border-radius | 1.49 / 2.78 | 1.53 / 2.16 | 2.54 / 3.26 | 1.37 / 2.18 | 1.98 / 2.72 | 1.12× | 0.59× | 3.87 / 4.52 | 3.72 / 4.42 | 4.98 / 5.41 | 4.19 / 4.41 | 10.8 / 12.6 | 0.89× | 0.78× |
| `radius-pill-circle` | border-radius | 1.57 / 2.68 | 1.77 / 3.92 | 2.55 / 3.32 | 1.84 / 3.15 | 2.55 / 3.49 | 0.96× | 0.61× | 3.09 / 3.98 | 2.91 / 4.53 | 4.28 / 5.15 | 4.19 / 4.74 | 10.2 / 11.4 | 0.69× | 0.72× |
| `radius-small` | border-radius | 0.26 / 0.41 | 0.29 / 1.04 | 0.41 / 0.68 | 0.42 / 0.77 | 0.49 / 0.75 | 0.69× | 0.63× | 0.54 / 0.59 | 0.52 / 0.65 | 0.83 / 0.92 | 1.03 / 1.13 | 1.75 / 1.89 | 0.51× | 0.65× |
| `lingrad-angles` | linear-gradient | 2.64 / 3.31 | 3.02 / 4.07 | 4.85 / 6.57 | 4.97 / 5.98 | 7.18 / 9.56 | 0.61× | 0.55× | 7.68 / 9.83 | 7.28 / 8.91 | 11.6 / 13.9 | 9.17 / 11.0 | 39.1 / 44.9 | 0.79× | 0.67× |
| `lingrad-multistop` | linear-gradient | 2.44 / 3.80 | 2.53 / 3.87 | 4.69 / 6.45 | 6.18 / 7.52 | 9.06 / 11.2 | 0.41× | 0.52× | 7.58 / 8.43 | 6.97 / 10.1 | 12.6 / 16.0 | 8.14 / 9.98 | 30.9 / 39.9 | 0.86× | 0.60× |
| `lingrad-alpha` | linear-gradient | 4.13 / 4.92 | 4.75 / 5.80 | 7.13 / 8.66 | 6.99 / 7.50 | 10.2 / 12.8 | 0.68× | 0.58× | 7.05 / 10.3 | 7.16 / 10.7 | 11.0 / 16.2 | 8.55 / 16.0 | 40.2 / 60.4 | 0.84× | 0.64× |
| `lingrad-hero-small` | linear-gradient | 0.42 / 0.60 | 0.43 / 0.82 | 0.60 / 1.01 | 0.92 / 1.23 | 1.04 / 1.50 | 0.47× | 0.71× | 1.56 / 2.15 | 1.70 / 2.20 | 2.14 / 3.15 | 1.78 / 2.07 | 3.85 / 5.91 | 0.96× | 0.73× |
| `radial-shapes` | radial-gradient | 2.17 / 2.86 | 2.66 / 3.47 | 3.93 / 5.25 | 6.58 / 8.50 | 8.37 / 11.5 | 0.40× | 0.55× | 13.8 / 18.1 | 14.0 / 18.4 | 20.3 / 25.3 | 11.7 / 14.6 | 44.5 / 56.2 | 1.19× | 0.68× |
| `radial-at-position` | radial-gradient | 2.48 / 3.38 | 3.29 / 4.12 | 5.83 / 6.74 | 8.72 / 10.3 | 13.4 / 15.2 | 0.38× | 0.42× | 12.3 / 15.1 | 13.4 / 16.2 | 19.4 / 25.7 | 14.1 / 16.0 | 42.7 / 55.6 | 0.95× | 0.63× |
| `radial-spotlight-small` | radial-gradient | 0.45 / 0.59 | 0.49 / 0.69 | 0.56 / 0.91 | 1.50 / 1.85 | 1.59 / 2.32 | 0.33× | 0.80× | 4.37 / 5.14 | 4.51 / 5.82 | 5.68 / 8.26 | 3.17 / 3.74 | 10.7 / 12.3 | 1.42× | 0.77× |
| `shadow-offset-blur` | box-shadow | 3.09 / 4.00 | 2.74 / 5.26 | 5.31 / 7.81 | 6.14 / 8.13 | 9.33 / 11.4 | 0.45× | 0.58× | 8.99 / 11.8 | 8.78 / 11.1 | 15.2 / 17.5 | 8.79 / 9.93 | 33.1 / 43.1 | 1.00× | 0.59× |
| `shadow-spread-multi` | box-shadow | 3.07 / 4.81 | 4.52 / 5.21 | 6.34 / 9.88 | 5.70 / 8.29 | 9.21 / 13.8 | 0.79× | 0.48× | 9.26 / 12.3 | 9.33 / 12.5 | 15.9 / 19.5 | 8.63 / 11.0 | 33.6 / 40.6 | 1.08× | 0.58× |
| `shadow-inset` | box-shadow | 3.34 / 4.20 | 3.33 / 5.55 | 6.23 / 8.70 | 8.75 / 10.8 | 14.0 / 16.5 | 0.38× | 0.54× | 9.33 / 13.0 | 9.23 / 13.3 | 14.4 / 17.7 | 10.9 / 13.6 | 33.8 / 43.0 | 0.85× | 0.65× |
| `shadow-small` | box-shadow | 0.48 / 0.74 | 0.54 / 0.99 | 0.89 / 1.49 | 1.15 / 1.71 | 1.56 / 2.46 | 0.47× | 0.53× | 0.74 / 0.89 | 0.76 / 1.01 | 1.25 / 1.35 | 1.68 / 2.46 | 2.44 / 3.67 | 0.45× | 0.60× |
| `opacity-basic` | opacity | 2.53 / 3.35 | 2.73 / 3.92 | 4.09 / 5.35 | 3.38 / 4.34 | 7.33 / 10.1 | 0.81× | 0.62× | 4.31 / 5.68 | 4.68 / 5.83 | 6.45 / 8.16 | 6.42 / 7.71 | 15.6 / 18.6 | 0.73× | 0.67× |
| `opacity-nested` | opacity | 1.58 / 2.31 | 1.69 / 2.78 | 2.75 / 4.06 | 4.51 / 5.86 | 10.1 / 11.3 | 0.38× | 0.58× | 2.67 / 3.14 | 2.77 / 3.04 | 3.98 / 4.51 | 6.87 / 7.69 | 15.5 / 17.2 | 0.40× | 0.67× |
| `opacity-with-radius-shadow` | opacity | 0.75 / 0.97 | 0.84 / 1.10 | 1.59 / 2.26 | 2.23 / 2.80 | 3.87 / 5.27 | 0.38× | 0.47× | 1.08 / 1.26 | 1.11 / 1.71 | 1.97 / 2.51 | 2.67 / 3.41 | 4.97 / 5.73 | 0.41× | 0.55× |
| `overflow-hidden-clip` | overflow | 1.02 / 3.95 | 1.09 / 2.31 | 1.79 / 2.06 | 2.17 / 2.90 | 2.70 / 3.42 | 0.51× | 0.57× | 1.98 / 2.59 | 2.05 / 2.59 | 2.87 / 3.41 | 4.32 / 5.18 | 7.70 / 8.79 | 0.47× | 0.69× |
| `overflow-radius-clip` | overflow | 1.66 / 2.32 | 1.99 / 2.89 | 2.46 / 4.56 | 3.08 / 3.73 | 4.40 / 7.00 | 0.65× | 0.68× | 5.10 / 6.55 | 4.59 / 6.94 | 8.03 / 10.4 | 6.16 / 7.39 | 18.1 / 27.0 | 0.75× | 0.64× |
| `overflow-nested` | overflow | 0.33 / 0.49 | 0.40 / 1.33 | 0.67 / 0.88 | 0.66 / 1.06 | 0.76 / 1.27 | 0.61× | 0.49× | 0.48 / 0.80 | 0.49 / 0.76 | 0.74 / 1.13 | 1.45 / 2.06 | 1.66 / 2.92 | 0.34× | 0.65× |
| `transform-basic` | transform | 1.87 / 3.06 | 1.83 / 2.43 | 2.72 / 3.63 | 3.18 / 4.40 | 5.11 / 6.79 | 0.58× | 0.69× | 2.75 / 4.18 | 3.25 / 4.34 | 4.77 / 5.97 | 5.19 / 6.93 | 11.5 / 14.8 | 0.63× | 0.58× |
| `transform-combined-origin` | transform | 1.42 / 2.11 | 1.44 / 2.26 | 2.14 / 3.56 | 2.77 / 3.49 | 4.14 / 5.32 | 0.52× | 0.66× | 2.67 / 3.89 | 2.65 / 2.93 | 3.61 / 4.60 | 4.65 / 5.43 | 9.45 / 10.6 | 0.57× | 0.74× |
| `transform-text-small` | transform | 0.57 / 0.85 | 0.60 / 0.93 | 1.05 / 1.61 | 1.20 / 1.72 | 1.81 / 2.63 | 0.50× | 0.54× | 0.96 / 1.32 | 1.02 / 1.51 | 1.57 / 2.36 | 1.90 / 2.47 | 2.85 / 4.53 | 0.54× | 0.61× |
| `text-single-sizes` | text-single-line | 1.27 / 1.93 | 1.36 / 1.75 | 2.10 / 2.94 | 2.00 / 2.49 | 3.07 / 3.84 | 0.68× | 0.61× | 2.80 / 3.76 | 2.87 / 3.28 | 3.61 / 4.25 | 4.00 / 4.45 | 7.81 / 9.76 | 0.72× | 0.78× |
| `text-single-colors-small` | text-single-line | 0.30 / 0.45 | 0.32 / 0.72 | 0.43 / 0.71 | 0.78 / 1.02 | 0.90 / 1.45 | 0.41× | 0.70× | 0.61 / 0.86 | 0.59 / 0.79 | 0.84 / 1.32 | 1.42 / 1.58 | 1.86 / 2.92 | 0.42× | 0.72× |
| `text-single-fonts` | text-single-line | 1.37 / 2.74 | 1.48 / 2.39 | 1.94 / 2.62 | 2.02 / 2.62 | 2.57 / 3.28 | 0.73× | 0.71× | 3.11 / 4.62 | 3.36 / 4.50 | 4.18 / 4.90 | 4.36 / 5.30 | 9.14 / 12.8 | 0.77× | 0.74× |
| `text-paragraph-wrap` | text-paragraph | 2.02 / 2.53 | 2.27 / 3.29 | 3.18 / 4.20 | 3.12 / 3.79 | 4.67 / 6.97 | 0.73× | 0.63× | 3.63 / 4.50 | 3.63 / 4.63 | 4.86 / 6.37 | 4.80 / 5.49 | 9.60 / 11.2 | 0.76× | 0.75× |
| `text-paragraph-lineheight` | text-paragraph | 1.82 / 2.76 | 1.78 / 3.36 | 2.86 / 3.75 | 3.07 / 4.13 | 4.55 / 6.27 | 0.58× | 0.64× | 4.14 / 5.01 | 3.91 / 5.79 | 5.77 / 8.09 | 5.27 / 7.03 | 10.2 / 11.7 | 0.74× | 0.72× |
| `text-paragraph-letterspacing` | text-paragraph | 2.48 / 2.96 | 2.41 / 3.67 | 3.90 / 5.58 | 3.82 / 4.34 | 6.23 / 7.54 | 0.63× | 0.64× | 4.67 / 6.13 | 4.69 / 6.26 | 6.03 / 8.68 | 5.61 / 6.71 | 11.2 / 14.5 | 0.83× | 0.77× |
| `text-paragraph-small` | text-paragraph | 0.34 / 0.52 | 0.36 / 0.61 | 0.50 / 0.75 | 0.71 / 0.97 | 0.82 / 1.29 | 0.51× | 0.68× | 0.81 / 1.15 | 0.78 / 1.20 | 1.10 / 1.73 | 1.35 / 1.66 | 2.00 / 3.03 | 0.58× | 0.74× |
| `text-long-wrap` | text-paragraph | 1.32 / 3.23 | 1.71 / 2.05 | 1.82 / 3.11 | 2.08 / 2.65 | 2.64 / 3.62 | 0.82× | 0.73× | 3.37 / 5.33 | 3.67 / 5.41 | 4.55 / 6.58 | 5.61 / 6.57 | 13.4 / 18.2 | 0.65× | 0.74× |
| `fonts-weights-italic` | fonts | 1.62 / 2.31 | 1.98 / 2.19 | 2.55 / 3.51 | 2.93 / 3.72 | 3.87 / 4.96 | 0.68× | 0.64× | 4.59 / 5.81 | 4.28 / 5.03 | 5.91 / 8.69 | 4.76 / 6.21 | 10.8 / 14.1 | 0.90× | 0.78× |
| `fonts-mixed-inline` | fonts | 1.12 / 1.43 | 1.15 / 2.38 | 1.82 / 2.90 | 1.88 / 2.79 | 2.62 / 5.88 | 0.61× | 0.61× | 3.37 / 4.65 | 3.97 / 4.63 | 4.97 / 6.37 | 4.08 / 5.40 | 9.36 / 11.7 | 0.97× | 0.68× |
| `text-vietnamese` | text-i18n | 1.33 / 1.97 | 1.46 / 2.02 | 1.68 / 2.66 | 2.30 / 3.40 | 3.01 / 4.10 | 0.64× | 0.79× | 3.12 / 4.72 | 3.11 / 4.56 | 4.10 / 6.47 | 4.21 / 4.95 | 8.58 / 11.3 | 0.74× | 0.76× |
| `text-accented-latin` | text-i18n | 1.22 / 1.73 | 1.17 / 2.39 | 1.72 / 3.35 | 2.30 / 2.67 | 2.40 / 5.38 | 0.51× | 0.71× | 3.10 / 3.92 | 3.28 / 4.21 | 4.31 / 6.05 | 3.94 / 5.05 | 8.38 / 10.6 | 0.83× | 0.72× |
| `text-ellipsis-nowrap` | text-truncation | 1.08 / 1.69 | 1.21 / 2.13 | 1.50 / 2.59 | 1.87 / 2.49 | 2.22 / 3.38 | 0.65× | 0.72× | 2.06 / 3.12 | 2.07 / 3.12 | 2.82 / 4.07 | 4.03 / 4.52 | 7.14 / 10.5 | 0.51× | 0.73× |
| `text-lineclamp` | text-truncation | 1.63 / 2.54 | 2.10 / 3.08 | 2.47 / 3.87 | 2.33 / 3.49 | 3.48 / 5.15 | 0.90× | 0.66× | 3.12 / 4.52 | 3.15 / 4.87 | 4.18 / 6.54 | 4.86 / 6.37 | 9.82 / 14.0 | 0.65× | 0.75× |
| `text-lineclamp-small` | text-truncation | 0.30 / 0.51 | 0.33 / 0.49 | 0.54 / 0.67 | 0.76 / 1.10 | 0.97 / 1.24 | 0.44× | 0.56× | 0.52 / 0.76 | 0.53 / 0.81 | 0.70 / 1.11 | 1.18 / 1.54 | 1.75 / 2.47 | 0.45× | 0.75× |
| `img-png-fit` | images | 1.60 / 2.14 | 1.85 / 2.68 | 3.08 / 4.28 | 4.29 / 5.22 | 6.29 / 7.87 | 0.43× | 0.52× | 11.8 / 14.3 | 12.1 / 13.1 | 18.7 / 24.8 | 9.63 / 11.3 | 36.8 / 40.9 | 1.25× | 0.63× |
| `img-jpeg-fit` | images | 1.68 / 1.93 | 1.67 / 1.95 | 3.21 / 4.17 | 13.4 / 16.2 | 20.5 / 24.4 | 0.12× | 0.52× | 19.8 / 28.9 | 20.0 / 24.1 | 29.1 / 41.2 | 18.8 / 25.8 | 55.7 / 68.8 | 1.06× | 0.68× |
| `img-intrinsic-size` | images | 0.23 / 0.35 | 0.28 / 0.84 | 0.62 / 0.77 | 0.57 / 1.21 | 0.80 / 1.08 | 0.49× | 0.36× | 2.06 / 2.74 | 2.54 / 3.18 | 3.32 / 4.65 | 1.69 / 2.00 | 5.68 / 7.25 | 1.50× | 0.62× |
| `img-radius-clip` | images | 3.18 / 4.18 | 2.94 / 4.99 | 5.53 / 7.17 | 6.10 / 7.85 | 9.92 / 12.2 | 0.48× | 0.57× | 17.4 / 22.2 | 17.6 / 23.4 | 29.3 / 34.2 | 12.0 / 13.5 | 47.9 / 52.8 | 1.46× | 0.59× |
| `img-photo-bg` | images | 1.34 / 2.86 | 1.39 / 2.97 | 2.06 / 3.48 | 4.01 / 6.85 | 6.67 / 10.5 | 0.35× | 0.65× | 30.8 / 36.1 | 30.5 / 34.3 | 46.3 / 50.9 | 13.4 / 15.2 | 58.8 / 75.2 | 2.28× | 0.66× |
| `grid-fixed-fr` | grid | 1.17 / 4.96 | 1.36 / 2.53 | 1.88 / 3.14 | 1.81 / 2.20 | 2.18 / 2.99 | 0.75× | 0.62× | 2.07 / 3.30 | 2.10 / 2.85 | 3.36 / 4.03 | 4.05 / 4.45 | 7.42 / 9.77 | 0.52× | 0.62× |
| `grid-repeat-gap` | grid | 1.30 / 3.75 | 1.41 / 2.49 | 2.13 / 3.22 | 1.91 / 3.32 | 2.57 / 3.22 | 0.74× | 0.61× | 2.50 / 3.57 | 2.36 / 3.26 | 3.71 / 4.44 | 4.65 / 4.92 | 11.6 / 14.0 | 0.51× | 0.67× |
| `grid-spans` | grid | 1.26 / 1.83 | 1.27 / 1.89 | 1.84 / 2.67 | 1.98 / 2.64 | 2.44 / 3.87 | 0.64× | 0.68× | 2.20 / 3.27 | 2.10 / 3.60 | 3.02 / 4.11 | 3.99 / 4.89 | 8.34 / 9.45 | 0.53× | 0.73× |
| `grid-small-mixed` | grid | 0.51 / 0.62 | 0.54 / 1.00 | 0.82 / 1.18 | 1.04 / 1.33 | 1.46 / 1.75 | 0.52× | 0.62× | 0.80 / 1.08 | 0.75 / 1.09 | 1.51 / 1.76 | 1.80 / 2.14 | 2.47 / 3.28 | 0.42× | 0.53× |
| `card-og` | og-card | 3.52 / 4.01 | 3.27 / 4.13 | 5.83 / 6.31 | 6.07 / 6.77 | 7.95 / 9.62 | 0.54× | 0.60× | 11.1 / 15.3 | 10.2 / 14.2 | 16.1 / 23.4 | 8.82 / 11.4 | 23.3 / 28.6 | 1.16× | 0.69× |
| `card-og-small` | og-card | 1.10 / 1.46 | 1.13 / 1.31 | 1.77 / 2.04 | 2.19 / 3.44 | 3.42 / 3.75 | 0.52× | 0.62× | 4.06 / 5.42 | 4.07 / 5.51 | 5.99 / 7.24 | 3.69 / 5.20 | 8.60 / 9.86 | 1.10× | 0.68× |
| `card-blog` | blog-card | 7.20 / 8.84 | 6.70 / 9.06 | 12.0 / 14.9 | 8.78 / 10.6 | 19.5 / 25.7 | 0.76× | 0.60× | 20.0 / 23.5 | 20.1 / 24.1 | 30.8 / 36.4 | 12.5 / 15.8 | 50.0 / 58.5 | 1.61× | 0.65× |
| `card-flat-ui` | blog-card | 2.92 / 4.58 | 3.14 / 4.62 | 5.63 / 7.02 | 3.95 / 5.33 | 7.41 / 10.4 | 0.79× | 0.52× | 5.69 / 8.10 | 5.78 / 6.38 | 8.90 / 11.4 | 7.25 / 9.21 | 20.8 / 23.4 | 0.80× | 0.64× |
| `stress-600-boxes` | stress | 5.59 / 9.47 | 7.00 / 9.58 | 9.81 / 13.1 | 7.62 / 9.62 | 9.79 / 11.9 | 0.92× | 0.57× | 9.01 / 12.9 | 8.39 / 10.7 | 13.6 / 19.6 | 9.44 / 11.1 | 17.7 / 21.8 | 0.89× | 0.66× |
| `stress-200-labels` | stress | 5.68 / 8.52 | 6.14 / 8.25 | 10.4 / 15.0 | 11.6 / 17.1 | 16.2 / 23.9 | 0.53× | 0.55× | 10.2 / 12.5 | 10.8 / 15.1 | 16.2 / 21.5 | 14.7 / 19.1 | 24.6 / 31.4 | 0.74× | 0.63× |
| `stress-3000x2000-card` | stress | 15.2 / 17.5 | 16.6 / 21.2 | 22.2 / 29.0 | 23.5 / 31.9 | 33.3 / 38.0 | 0.71× | 0.68× | 57.9 / 68.6 | 56.5 / 59.8 | 83.2 / 97.4 | 45.1 / 55.5 | 146 / 166 | 1.25× | 0.70× |
| `fx-text-shadow` | text-shadow | 0.64 / 1.01 | 0.65 / 1.16 | 1.15 / 1.89 | 0.93 / 1.49 | 1.19 / 2.02 | 0.70× | 0.56× | 2.67 / 3.93 | 2.76 / 3.93 | 4.04 / 5.90 | 2.07 / 2.50 | 4.57 / 6.36 | 1.33× | 0.66× |
| `gap-dashed-dotted-border` | known-gaps | 0.62 / 0.99 | 0.67 / 1.00 | 1.14 / 1.76 | 1.27 / 1.93 | 1.98 / 3.00 | 0.53× | 0.55× | 0.84 / 1.27 | 0.82 / 1.33 | 1.31 / 2.07 | 2.24 / 2.61 | 2.79 / 3.43 | 0.36× | 0.64× |
| `fx-filter-blur-grayscale` | filter | 0.65 / 1.03 | 0.69 / 1.02 | 1.31 / 1.74 | 1.29 / 1.81 | 1.93 / 2.61 | 0.53× | 0.50× | 1.79 / 2.13 | 1.84 / 2.17 | 2.98 / 3.83 | 2.02 / 2.71 | 5.18 / 6.71 | 0.91× | 0.60× |
| `gap-tailwind-tw` | known-gaps | 0.28 / 0.41 | 0.30 / 0.55 | 0.43 / 0.65 | 0.50 / 0.78 | 0.59 / 0.93 | 0.59× | 0.66× | 0.45 / 0.69 | 0.46 / 0.80 | 0.66 / 1.04 | 1.00 / 1.64 | 1.46 / 2.38 | 0.47× | 0.69× |
| `gap-oklch-color` | known-gaps | 0.15 / 0.27 | 0.19 / 0.37 | 0.25 / 0.37 | 0.30 / 0.82 | 0.33 / 0.59 | 0.64× | 0.60× | 0.22 / 0.33 | 0.22 / 0.36 | 0.30 / 0.48 | 0.88 / 1.24 | 1.22 / 1.82 | 0.25× | 0.74× |
| `gap-svg-image` | known-gaps | 0.21 / 0.34 | 0.21 / 0.45 | 0.38 / 0.63 | 0.38 / 0.62 | 0.50 / 0.83 | 0.57× | 0.56× | 0.41 / 0.69 | 0.41 / 0.66 | 0.61 / 0.97 | 0.83 / 1.24 | 1.25 / 2.05 | 0.49× | 0.68× |
| `gap-inline-box-decoration` | known-gaps | 0.27 / 0.42 | 0.29 / 0.51 | 0.41 / 0.64 | 0.58 / 0.87 | 0.73 / 1.15 | 0.50× | 0.65× | 0.69 / 1.05 | 0.66 / 1.02 | 0.94 / 1.46 | 1.25 / 1.56 | 1.94 / 2.83 | 0.53× | 0.74× |
| `gap-mix-blend-mode` | known-gaps | 0.28 / 0.45 | 0.30 / 0.54 | 0.48 / 0.78 | 0.56 / 0.82 | 0.90 / 1.30 | 0.55× | 0.59× | 0.59 / 0.88 | 0.67 / 0.88 | 0.92 / 1.40 | 1.21 / 1.76 | 1.86 / 2.85 | 0.55× | 0.64× |
| `gap-clip-path` | known-gaps | 0.51 / 0.68 | 0.53 / 0.80 | 0.90 / 1.12 | 0.72 / 0.96 | 1.21 / 1.35 | 0.74× | 0.56× | 1.04 / 1.43 | 1.03 / 1.62 | 1.56 / 2.46 | 1.43 / 2.13 | 7.31 / 11.0 | 0.72× | 0.67× |
| `gap-background-clip-text` | known-gaps | 0.34 / 0.65 | 0.38 / 0.52 | 0.49 / 0.75 | 1.62 / 2.18 | 2.17 / 3.58 | 0.23× | 0.70× | 1.55 / 1.67 | 1.54 / 1.66 | 2.28 / 2.61 | 2.50 / 2.97 | 7.90 / 9.55 | 0.62× | 0.68× |
| `gap-text-wrap-balance` | known-gaps | 0.25 / 0.46 | 0.26 / 0.47 | 0.37 / 0.64 | 0.57 / 0.92 | 0.68 / 1.06 | 0.45× | 0.67× | 0.61 / 0.84 | 0.61 / 0.89 | 0.85 / 1.28 | 1.31 / 1.44 | 1.73 / 2.71 | 0.46× | 0.72× |
| `pfx-aa-shapes` | aa-exact | 0.39 / 0.47 | 0.44 / 0.64 | 0.59 / 0.83 | 0.60 / 1.10 | 0.94 / 1.30 | 0.73× | 0.66× | 0.65 / 1.26 | 0.77 / 1.01 | 1.17 / 1.40 | 1.36 / 1.70 | 2.16 / 2.57 | 0.56× | 0.56× |
| `pfx-aa-text` | aa-exact | 0.43 / 0.63 | 0.43 / 0.62 | 0.60 / 0.84 | 0.98 / 1.31 | 1.09 / 1.75 | 0.44× | 0.72× | 0.87 / 1.30 | 0.88 / 1.27 | 1.16 / 1.73 | 1.58 / 2.06 | 2.60 / 3.38 | 0.56× | 0.75× |
| `pfx-border-dashed` | dashed-border | 1.00 / 1.36 | 1.32 / 1.46 | 2.02 / 2.49 | 1.81 / 2.42 | 3.23 / 4.35 | 0.73× | 0.50× | 1.13 / 1.74 | 1.21 / 1.72 | 1.76 / 2.73 | 2.20 / 3.09 | 3.55 / 5.59 | 0.55× | 0.64× |
| `pfx-border-dotted` | dotted-border | 0.95 / 1.55 | 0.99 / 1.56 | 1.68 / 2.77 | 1.97 / 2.76 | 3.01 / 3.74 | 0.50× | 0.57× | 1.78 / 1.99 | 1.39 / 1.77 | 3.13 / 3.45 | 3.26 / 3.64 | 4.92 / 6.51 | 0.43× | 0.57× |
| `pfx-border-double-3d` | double-3d-border | 0.35 / 0.56 | 0.39 / 0.59 | 0.62 / 1.05 | 0.59 / 0.90 | 0.80 / 1.27 | 0.66× | 0.56× | 0.55 / 0.91 | 0.58 / 0.88 | 0.85 / 1.37 | 1.20 / 1.75 | 1.70 / 2.57 | 0.49× | 0.64× |
| `pfx-border-mixed` | mixed-border | 0.56 / 0.89 | 0.59 / 0.89 | 1.08 / 1.49 | 0.92 / 1.54 | 1.35 / 2.10 | 0.65× | 0.52× | 0.73 / 1.10 | 0.71 / 1.25 | 1.11 / 1.78 | 1.57 / 1.81 | 2.18 / 3.34 | 0.45× | 0.66× |
| `pfx-outline` | outline | 0.62 / 0.94 | 0.79 / 0.93 | 1.19 / 1.59 | 1.24 / 1.94 | 1.92 / 3.06 | 0.64× | 0.52× | 0.86 / 1.23 | 0.86 / 1.36 | 1.34 / 1.92 | 1.96 / 2.29 | 2.91 / 3.94 | 0.44× | 0.64× |
| `pfx-clip-path-shapes` | clip-path | 0.44 / 0.71 | 0.47 / 0.73 | 0.76 / 1.28 | 0.76 / 1.15 | 1.09 / 1.71 | 0.61× | 0.58× | 1.33 / 2.16 | 1.40 / 2.09 | 2.08 / 3.24 | 1.77 / 2.00 | 6.28 / 7.75 | 0.79× | 0.64× |
| `pfx-mask-gradient` | mask | 0.82 / 1.08 | 0.84 / 1.22 | 1.30 / 2.12 | 1.36 / 1.76 | 1.82 / 2.90 | 0.62× | 0.63× | 2.46 / 2.78 | 2.27 / 3.10 | 2.97 / 5.06 | 2.41 / 3.23 | 9.13 / 11.9 | 0.94× | 0.83× |
| `pfx-bg-clip-text` | bg-clip-text | 0.43 / 0.64 | 0.48 / 0.63 | 0.61 / 0.93 | 2.28 / 3.05 | 3.05 / 4.00 | 0.21× | 0.70× | 1.58 / 2.27 | 1.61 / 2.32 | 2.24 / 2.70 | 2.87 / 3.84 | 5.94 / 7.67 | 0.56× | 0.70× |
| `pfx-mix-blend` | mix-blend | 1.13 / 1.33 | 1.20 / 1.33 | 1.86 / 2.30 | 1.61 / 1.76 | 3.02 / 3.31 | 0.74× | 0.61× | 2.91 / 4.08 | 3.06 / 4.30 | 4.63 / 5.35 | 2.31 / 2.85 | 8.53 / 10.3 | 1.33× | 0.63× |
| `pfx-bg-blend` | bg-blend | 0.75 / 1.18 | 0.89 / 1.41 | 1.67 / 1.91 | 5.07 / 6.86 | 6.10 / 9.29 | 0.18× | 0.45× | 3.04 / 3.72 | 3.04 / 4.61 | 4.76 / 5.87 | 5.54 / 7.82 | 12.4 / 14.0 | 0.55× | 0.64× |
| `pfx-drop-shadow` | drop-shadow | 0.81 / 1.27 | 0.80 / 1.27 | 1.35 / 1.99 | 1.18 / 1.68 | 1.71 / 2.63 | 0.68× | 0.60× | 2.28 / 3.48 | 2.29 / 3.40 | 3.61 / 4.23 | 1.98 / 2.79 | 7.22 / 12.6 | 1.16× | 0.63× |
| `pfx-backdrop-filter` | backdrop-filter | 1.46 / 2.15 | 1.54 / 1.85 | 2.74 / 3.43 | 2.67 / 3.59 | 4.54 / 5.42 | 0.58× | 0.53× | 2.23 / 3.31 | 2.30 / 2.80 | 4.00 / 4.76 | 3.25 / 4.04 | 8.05 / 8.89 | 0.71× | 0.56× |
| `pfx-text-stroke` | text-stroke | 0.77 / 1.01 | 0.83 / 1.06 | 1.29 / 1.51 | 0.73 / 0.91 | 0.92 / 1.22 | 1.14× | 0.59× | 1.35 / 1.85 | 1.33 / 1.69 | 1.98 / 3.01 | 1.38 / 1.71 | 2.32 / 3.61 | 0.96× | 0.68× |
| `pfx-text-decoration` | text-decoration | 1.12 / 1.74 | 1.21 / 1.78 | 1.90 / 3.06 | 1.37 / 1.95 | 1.90 / 2.84 | 0.89× | 0.59× | 1.98 / 2.88 | 1.95 / 2.43 | 3.00 / 4.52 | 2.12 / 2.86 | 3.95 / 5.86 | 0.92× | 0.66× |
| `pfx-visibility` | visibility | 0.21 / 0.32 | 0.23 / 0.37 | 0.33 / 0.47 | 0.44 / 0.71 | 0.54 / 0.81 | 0.51× | 0.63× | 0.30 / 0.50 | 0.32 / 0.54 | 0.41 / 0.63 | 1.12 / 1.43 | 1.39 / 2.20 | 0.29× | 0.72× |
| `pfx-opacity-layers` | opacity | 1.13 / 1.78 | 1.15 / 1.29 | 2.50 / 4.06 | 1.96 / 2.98 | 3.23 / 5.13 | 0.58× | 0.45× | 2.39 / 3.76 | 2.41 / 3.17 | 4.26 / 7.42 | 3.01 / 3.78 | 7.38 / 10.7 | 0.80× | 0.56× |
| `pfx-svg-background` | svg-image | 0.69 / 1.21 | 0.75 / 1.15 | 1.48 / 2.27 | 0.71 / 1.06 | 1.01 / 1.66 | 1.05× | 0.46× | 1.39 / 1.90 | 1.74 / 2.03 | 3.13 / 3.62 | 1.82 / 2.93 | 2.92 / 4.27 | 0.96× | 0.44× |
| `pfx-inline-boxes-many` | inline-box | 1.32 / 1.59 | 1.30 / 1.92 | 2.24 / 3.08 | 2.12 / 2.86 | 2.92 / 4.41 | 0.61× | 0.59× | 2.61 / 3.37 | 2.65 / 3.75 | 3.99 / 5.25 | 3.03 / 4.12 | 6.43 / 7.64 | 0.88× | 0.65× |
| `css-class-id` | css-stylesheet | 1.46 / 2.07 | 1.97 / 2.66 | 2.79 / 4.31 | 2.46 / 3.29 | 3.27 / 4.48 | 0.80× | 0.52× | 2.40 / 2.85 | 2.42 / 2.58 | 3.61 / 4.68 | 3.84 / 4.31 | 7.73 / 10.0 | 0.63× | 0.67× |
| `css-nth-child` | css-stylesheet | 0.76 / 1.37 | 0.81 / 1.87 | 1.21 / 1.92 | 1.50 / 2.24 | 1.85 / 3.24 | 0.54× | 0.63× | 1.28 / 1.76 | 1.27 / 1.71 | 1.91 / 2.14 | 2.46 / 3.09 | 4.58 / 5.85 | 0.52× | 0.67× |
| `css-media-layer` | css-stylesheet | 0.68 / 3.62 | 0.77 / 1.47 | 1.05 / 1.74 | 0.86 / 2.34 | 0.97 / 1.84 | 0.89× | 0.65× | 1.11 / 1.42 | 1.07 / 1.40 | 1.62 / 2.15 | 2.67 / 3.26 | 4.83 / 5.32 | 0.40× | 0.68× |
| `css-important-var` | css-stylesheet | 0.53 / 0.82 | 0.57 / 1.06 | 0.81 / 1.14 | 0.89 / 1.92 | 1.12 / 1.78 | 0.64× | 0.65× | 0.83 / 1.15 | 0.79 / 1.13 | 1.22 / 1.73 | 2.40 / 2.77 | 3.60 / 4.09 | 0.33× | 0.68× |
| `tw-card` | tailwind | 1.33 / 2.34 | 1.36 / 2.64 | 1.85 / 2.29 | 1.96 / 2.63 | 2.64 / 3.48 | 0.69× | 0.72× | 2.87 / 3.42 | 2.72 / 4.20 | 3.84 / 4.93 | 4.00 / 4.68 | 7.35 / 10.5 | 0.68× | 0.75× |
| `tw-responsive` | tailwind | 0.88 / 3.23 | 0.89 / 1.42 | 1.29 / 1.51 | 0.96 / 1.72 | 1.27 / 1.79 | 0.93× | 0.68× | 1.04 / 1.60 | 1.05 / 1.28 | 1.59 / 2.21 | 2.87 / 3.69 | 4.27 / 5.57 | 0.37× | 0.66× |
| `tw-structural` | tailwind | 0.87 / 1.29 | 0.91 / 1.45 | 1.40 / 2.88 | 1.00 / 1.72 | 1.27 / 1.73 | 0.90× | 0.62× | 0.98 / 1.22 | 0.97 / 1.26 | 1.48 / 2.26 | 2.08 / 2.69 | 3.30 / 4.22 | 0.47× | 0.66× |
| `tw-arbitrary` | tailwind | 1.81 / 2.42 | 1.68 / 2.76 | 2.85 / 4.00 | 3.92 / 5.24 | 5.56 / 7.13 | 0.43× | 0.64× | 2.44 / 3.43 | 2.60 / 3.69 | 4.42 / 5.96 | 4.92 / 6.36 | 9.64 / 11.7 | 0.53× | 0.55× |
| `html-article` | html | 1.03 / 1.83 | 1.06 / 2.45 | 1.34 / 2.47 | 1.73 / 2.46 | 2.02 / 2.83 | 0.61× | 0.77× | 1.90 / 2.68 | 1.99 / 2.46 | 2.62 / 3.70 | 3.40 / 3.70 | 5.89 / 6.83 | 0.58× | 0.72× |
| `html-document` | html | 0.46 / 1.06 | 0.48 / 1.01 | 0.68 / 1.01 | 0.79 / 1.43 | 0.97 / 1.67 | 0.61× | 0.68× | 0.87 / 1.34 | 0.83 / 1.33 | 1.25 / 1.83 | 1.96 / 2.80 | 2.95 / 4.54 | 0.42× | 0.69× |
| `html-flex-card` | html | 1.34 / 1.62 | 1.39 / 2.25 | 2.20 / 2.57 | 2.50 / 3.91 | 3.73 / 4.62 | 0.56× | 0.61× | 4.75 / 5.71 | 4.96 / 5.98 | 7.13 / 8.49 | 4.66 / 5.97 | 12.8 / 14.2 | 1.06× | 0.67× |
| `html-inline` | html | 0.55 / 0.81 | 0.57 / 0.87 | 0.76 / 1.06 | 0.96 / 1.34 | 1.22 / 1.92 | 0.60× | 0.73× | 1.02 / 1.19 | 1.03 / 1.22 | 1.46 / 1.95 | 2.09 / 2.37 | 2.96 / 3.91 | 0.49× | 0.70× |
| `pseudo-inline` | pseudo-elements | 0.40 / 0.69 | 0.43 / 0.79 | 0.62 / 0.98 | 0.82 / 2.51 | 1.06 / 1.46 | 0.52× | 0.64× | 0.78 / 1.10 | 0.74 / 1.03 | 1.12 / 1.35 | 1.50 / 1.90 | 2.65 / 4.15 | 0.50× | 0.70× |
| `pseudo-block` | pseudo-elements | 0.62 / 0.92 | 0.66 / 1.24 | 0.90 / 1.36 | 0.98 / 1.55 | 1.23 / 1.86 | 0.67× | 0.69× | 0.91 / 1.29 | 0.85 / 1.18 | 1.31 / 1.74 | 1.95 / 2.15 | 2.99 / 4.24 | 0.43× | 0.69× |
| `pseudo-attr` | pseudo-elements | 0.31 / 0.55 | 0.34 / 1.22 | 0.56 / 0.82 | 0.72 / 1.25 | 0.97 / 1.56 | 0.47× | 0.55× | 0.66 / 0.86 | 0.56 / 0.78 | 0.86 / 1.30 | 1.29 / 1.88 | 2.34 / 3.54 | 0.44× | 0.77× |
| `pseudo-tw` | pseudo-elements | 0.43 / 0.66 | 0.46 / 1.26 | 0.71 / 1.07 | 0.68 / 1.28 | 0.88 / 1.27 | 0.68× | 0.61× | 0.75 / 1.20 | 0.70 / 1.11 | 1.07 / 1.30 | 1.46 / 1.99 | 2.42 / 3.16 | 0.48× | 0.71× |
| `anim-opacity-t0` | animation | 0.10 / 0.17 | 0.12 / 0.25 | 0.18 / 0.30 | 0.23 / 0.38 | 0.26 / 0.44 | 0.53× | 0.54× | 0.18 / 0.29 | 0.18 / 0.28 | 0.26 / 0.39 | 0.50 / 0.71 | 0.71 / 1.13 | 0.36× | 0.72× |
| `anim-opacity-t250` | animation | 0.13 / 0.18 | 0.13 / 0.20 | 0.22 / 0.32 | 0.33 / 0.45 | 0.46 / 0.66 | 0.41× | 0.57× | 0.23 / 0.31 | 0.22 / 0.33 | 0.31 / 0.48 | 0.78 / 1.05 | 1.02 / 1.57 | 0.28× | 0.73× |
| `anim-opacity-t500` | animation | 0.14 / 0.24 | 0.16 / 0.70 | 0.23 / 0.40 | 0.39 / 0.70 | 0.51 / 0.98 | 0.41× | 0.58× | 0.20 / 0.37 | 0.21 / 0.35 | 0.29 / 0.45 | 0.62 / 0.98 | 0.94 / 1.48 | 0.33× | 0.69× |
| `anim-opacity-t900` | animation | 0.12 / 0.19 | 0.14 / 0.23 | 0.22 / 0.37 | 0.32 / 0.55 | 0.46 / 0.70 | 0.46× | 0.57× | 0.22 / 0.34 | 0.21 / 0.36 | 0.30 / 0.49 | 0.66 / 1.00 | 0.99 / 1.53 | 0.32× | 0.73× |
| `anim-opacity-t1500` | animation | 0.14 / 0.21 | 0.15 / 0.31 | 0.24 / 0.34 | 0.32 / 0.49 | 0.39 / 0.58 | 0.46× | 0.59× | 0.19 / 0.28 | 0.17 / 0.31 | 0.25 / 0.40 | 0.57 / 0.85 | 0.80 / 1.32 | 0.30× | 0.74× |
| `anim-transform-t0` | animation | 0.13 / 0.23 | 0.16 / 0.31 | 0.24 / 0.41 | 0.28 / 0.43 | 0.31 / 0.51 | 0.57× | 0.54× | 0.25 / 0.38 | 0.24 / 0.39 | 0.37 / 0.59 | 0.56 / 0.92 | 0.81 / 1.31 | 0.42× | 0.66× |
| `anim-transform-t200` | animation | 0.16 / 0.26 | 0.17 / 0.30 | 0.25 / 0.41 | 0.28 / 0.49 | 0.33 / 0.53 | 0.61× | 0.62× | 0.27 / 0.42 | 0.26 / 0.37 | 0.41 / 0.51 | 0.57 / 0.78 | 0.82 / 1.27 | 0.45× | 0.65× |
| `anim-transform-t400` | animation | 0.16 / 0.25 | 0.17 / 0.27 | 0.25 / 0.44 | 0.27 / 0.42 | 0.34 / 0.51 | 0.63× | 0.61× | 0.28 / 0.43 | 0.28 / 0.42 | 0.42 / 0.66 | 0.58 / 0.84 | 0.82 / 1.31 | 0.49× | 0.67× |
| `anim-transform-t600` | animation | 0.15 / 0.25 | 0.17 / 0.28 | 0.26 / 0.42 | 0.29 / 0.46 | 0.34 / 0.51 | 0.61× | 0.56× | 0.31 / 0.48 | 0.30 / 0.47 | 0.45 / 0.66 | 0.63 / 0.94 | 0.85 / 1.32 | 0.48× | 0.69× |
| `anim-transform-t800` | animation | 0.12 / 0.22 | 0.15 / 0.25 | 0.22 / 0.35 | 0.26 / 0.47 | 0.30 / 0.50 | 0.60× | 0.54× | 0.23 / 0.34 | 0.22 / 0.31 | 0.35 / 0.57 | 0.55 / 0.81 | 0.80 / 1.19 | 0.40× | 0.65× |
| `anim-color-t0` | animation | 0.20 / 0.30 | 0.19 / 0.34 | 0.30 / 0.45 | 0.45 / 0.72 | 0.54 / 0.85 | 0.42× | 0.65× | 0.30 / 0.42 | 0.28 / 0.39 | 0.44 / 0.59 | 0.73 / 1.04 | 1.02 / 1.20 | 0.38× | 0.69× |
| `anim-color-t300` | animation | 0.18 / 0.28 | 0.18 / 0.29 | 0.29 / 0.42 | 0.42 / 0.66 | 0.51 / 0.78 | 0.44× | 0.62× | 0.30 / 0.45 | 0.30 / 0.38 | 0.43 / 0.66 | 0.74 / 1.07 | 0.99 / 1.57 | 0.40× | 0.68× |
| `anim-color-t700` | animation | 0.16 / 0.23 | 0.18 / 0.29 | 0.26 / 0.41 | 0.41 / 0.65 | 0.50 / 0.69 | 0.43× | 0.60× | 0.29 / 0.44 | 0.27 / 0.40 | 0.43 / 0.66 | 0.73 / 1.10 | 1.00 / 1.61 | 0.37× | 0.68× |
| `anim-color-t2000` | animation | 0.16 / 0.24 | 0.18 / 0.30 | 0.27 / 0.42 | 0.41 / 0.64 | 0.52 / 0.76 | 0.44× | 0.60× | 0.29 / 0.41 | 0.27 / 0.46 | 0.43 / 0.70 | 0.71 / 1.17 | 1.00 / 1.38 | 0.37× | 0.68× |
| `anim-width-t0` | animation | 0.13 / 0.17 | 0.14 / 0.26 | 0.22 / 0.33 | 0.26 / 0.46 | 0.31 / 0.49 | 0.56× | 0.60× | 0.19 / 0.27 | 0.19 / 0.27 | 0.28 / 0.43 | 0.50 / 0.74 | 0.71 / 1.13 | 0.39× | 0.67× |
| `anim-width-t100` | animation | 0.16 / 0.23 | 0.17 / 0.30 | 0.27 / 0.40 | 0.28 / 0.42 | 0.33 / 0.53 | 0.61× | 0.60× | 0.28 / 0.39 | 0.28 / 0.43 | 0.41 / 0.64 | 0.62 / 0.93 | 0.85 / 1.32 | 0.45× | 0.68× |
| `anim-width-t500` | animation | 0.26 / 0.31 | 0.25 / 0.35 | 0.37 / 0.54 | 0.41 / 0.63 | 0.52 / 0.69 | 0.61× | 0.70× | 0.37 / 0.55 | 0.36 / 0.55 | 0.56 / 0.88 | 0.71 / 1.04 | 1.00 / 1.46 | 0.51× | 0.66× |
| `anim-width-t999` | animation | 0.18 / 0.32 | 0.21 / 0.40 | 0.32 / 0.52 | 0.32 / 0.57 | 0.37 / 0.60 | 0.65× | 0.56× | 0.52 / 0.70 | 0.54 / 1.27 | 0.78 / 1.03 | 0.92 / 1.44 | 1.36 / 1.78 | 0.58× | 0.67× |
| `anim-delay-fill-t0` | animation | 0.15 / 0.23 | 0.18 / 0.28 | 0.27 / 0.43 | 0.35 / 0.56 | 0.50 / 0.74 | 0.50× | 0.56× | 0.26 / 0.41 | 0.27 / 0.40 | 0.40 / 0.62 | 0.67 / 1.02 | 0.97 / 1.34 | 0.40× | 0.65× |
| `anim-delay-fill-t750` | animation | 0.20 / 0.32 | 0.21 / 0.48 | 0.34 / 0.52 | 0.42 / 0.88 | 0.64 / 0.98 | 0.50× | 0.59× | 0.26 / 0.43 | 0.27 / 0.46 | 0.42 / 0.71 | 0.66 / 1.07 | 1.03 / 1.51 | 0.41× | 0.63× |
| `anim-delay-fill-t2000` | animation | 0.14 / 0.22 | 0.17 / 0.28 | 0.25 / 0.40 | 0.29 / 0.44 | 0.35 / 0.55 | 0.59× | 0.56× | 0.27 / 0.41 | 0.27 / 0.38 | 0.39 / 0.63 | 0.67 / 0.95 | 0.86 / 1.40 | 0.41× | 0.69× |
| `anim-alternate-t100` | animation | 0.12 / 0.25 | 0.16 / 0.25 | 0.22 / 0.35 | 0.36 / 0.53 | 0.47 / 0.75 | 0.46× | 0.56× | 0.19 / 0.31 | 0.20 / 0.29 | 0.27 / 0.42 | 0.62 / 0.94 | 0.92 / 1.50 | 0.33× | 0.70× |
| `anim-alternate-t500` | animation | 0.14 / 0.18 | 0.16 / 0.23 | 0.23 / 0.30 | 0.34 / 0.52 | 0.47 / 0.74 | 0.46× | 0.61× | 0.19 / 0.30 | 0.20 / 0.34 | 0.28 / 0.45 | 0.60 / 0.95 | 0.93 / 1.48 | 0.33× | 0.68× |
| `anim-alternate-t700` | animation | 0.11 / 0.21 | 0.13 / 0.75 | 0.20 / 0.34 | 0.32 / 0.54 | 0.46 / 0.72 | 0.41× | 0.57× | 0.19 / 0.31 | 0.19 / 0.28 | 0.27 / 0.44 | 0.64 / 0.94 | 0.94 / 1.48 | 0.30× | 0.71× |
| `anim-alternate-t1100` | animation | 0.13 / 0.22 | 0.15 / 0.31 | 0.22 / 0.36 | 0.34 / 0.62 | 0.47 / 0.72 | 0.44× | 0.60× | 0.19 / 0.29 | 0.20 / 0.30 | 0.28 / 0.44 | 0.62 / 0.98 | 0.93 / 1.48 | 0.32× | 0.70× |
| `anim-alternate-t1300` | animation | 0.12 / 0.21 | 0.14 / 0.27 | 0.21 / 0.35 | 0.27 / 0.45 | 0.31 / 0.52 | 0.52× | 0.60× | 0.17 / 0.25 | 0.19 / 0.25 | 0.25 / 0.41 | 0.50 / 0.78 | 0.73 / 1.10 | 0.37× | 0.68× |
| `anim-steps-t0` | animation | 0.12 / 0.20 | 0.13 / 0.24 | 0.21 / 0.34 | 0.26 / 0.44 | 0.32 / 0.51 | 0.51× | 0.57× | 0.22 / 0.36 | 0.22 / 0.42 | 0.31 / 0.48 | 0.59 / 0.83 | 0.80 / 1.27 | 0.38× | 0.71× |
| `anim-steps-t260` | animation | 0.15 / 0.22 | 0.16 / 0.27 | 0.24 / 0.37 | 0.29 / 0.45 | 0.32 / 0.51 | 0.56× | 0.62× | 0.21 / 0.31 | 0.23 / 0.31 | 0.30 / 0.47 | 0.58 / 0.83 | 0.78 / 1.19 | 0.40× | 0.68× |
| `anim-steps-t500` | animation | 0.12 / 0.22 | 0.13 / 0.26 | 0.21 / 0.36 | 0.25 / 0.48 | 0.30 / 0.52 | 0.53× | 0.56× | 0.20 / 0.29 | 0.20 / 0.31 | 0.30 / 0.46 | 0.53 / 0.76 | 0.77 / 1.22 | 0.38× | 0.67× |
| `anim-steps-t990` | animation | 0.12 / 0.21 | 0.14 / 0.25 | 0.21 / 0.36 | 0.26 / 0.47 | 0.31 / 0.48 | 0.53× | 0.56× | 0.20 / 0.32 | 0.20 / 0.31 | 0.30 / 0.50 | 0.53 / 0.81 | 0.75 / 1.19 | 0.38× | 0.67× |
| `anim-two-anims-t0` | animation | 0.16 / 0.27 | 0.18 / 0.32 | 0.28 / 0.43 | 0.39 / 0.59 | 0.49 / 0.78 | 0.46× | 0.56× | 0.22 / 0.31 | 0.21 / 0.36 | 0.32 / 0.48 | 0.63 / 0.87 | 0.95 / 1.44 | 0.34× | 0.70× |
| `anim-two-anims-t400` | animation | 0.18 / 0.30 | 0.21 / 0.36 | 0.29 / 0.46 | 0.54 / 0.84 | 0.77 / 1.14 | 0.38× | 0.62× | 0.25 / 0.44 | 0.24 / 0.37 | 0.37 / 0.54 | 0.76 / 1.10 | 1.24 / 1.90 | 0.32× | 0.68× |
| `anim-two-anims-t600` | animation | 0.19 / 0.26 | 0.23 / 0.30 | 0.31 / 0.48 | 0.49 / 0.74 | 0.80 / 1.21 | 0.46× | 0.62× | 0.29 / 0.40 | 0.28 / 0.46 | 0.40 / 0.61 | 0.83 / 1.22 | 1.33 / 2.04 | 0.34× | 0.73× |
| `anim-two-anims-t1200` | animation | 0.14 / 0.24 | 0.16 / 0.30 | 0.24 / 0.39 | 0.36 / 0.62 | 0.53 / 0.84 | 0.45× | 0.59× | 0.24 / 0.35 | 0.25 / 0.35 | 0.34 / 0.52 | 0.67 / 1.00 | 1.01 / 1.62 | 0.37× | 0.70× |
| `anim-inherit-t0` | animation | 0.22 / 0.32 | 0.22 / 0.30 | 0.34 / 0.49 | 0.46 / 0.69 | 0.58 / 0.86 | 0.48× | 0.64× | 0.35 / 0.50 | 0.34 / 0.49 | 0.50 / 0.76 | 0.79 / 1.12 | 1.04 / 1.62 | 0.44× | 0.70× |
| `anim-inherit-t500` | animation | 0.21 / 0.32 | 0.23 / 0.34 | 0.32 / 0.50 | 0.52 / 0.73 | 0.62 / 0.89 | 0.43× | 0.65× | 0.45 / 0.65 | 0.43 / 0.69 | 0.63 / 0.93 | 1.00 / 1.28 | 1.24 / 1.79 | 0.43× | 0.72× |
| `anim-inherit-t1000` | animation | 0.22 / 0.37 | 0.23 / 0.39 | 0.36 / 0.59 | 0.54 / 0.84 | 0.65 / 1.01 | 0.42× | 0.63× | 0.51 / 0.62 | 0.50 / 0.58 | 0.70 / 0.81 | 1.00 / 1.27 | 1.39 / 1.88 | 0.50× | 0.72× |
| `anim-tw-spin-t125` | animation | 0.16 / 0.25 | 0.18 / 0.31 | 0.28 / 0.37 | 0.44 / 0.61 | 0.57 / 0.91 | 0.42× | 0.58× | 0.21 / 0.33 | 0.21 / 0.36 | 0.30 / 0.49 | 0.64 / 1.00 | 0.96 / 1.56 | 0.32× | 0.70× |
| `anim-tw-spin-t375` | animation | 0.15 / 0.19 | 0.17 / 0.27 | 0.24 / 0.37 | 0.35 / 0.56 | 0.46 / 0.70 | 0.50× | 0.62× | 0.21 / 0.35 | 0.22 / 0.33 | 0.31 / 0.49 | 0.64 / 0.98 | 0.94 / 1.47 | 0.34× | 0.69× |
| `anim-tw-spin-t1600` | animation | 0.14 / 0.25 | 0.17 / 0.36 | 0.24 / 0.44 | 0.44 / 0.63 | 0.51 / 0.82 | 0.40× | 0.61× | 0.23 / 0.34 | 0.23 / 0.32 | 0.32 / 0.50 | 0.67 / 0.97 | 0.97 / 1.47 | 0.34× | 0.71× |
| `anim-kf-option-t0` | animation | 0.13 / 0.20 | 0.14 / 0.24 | 0.20 / 0.29 | 0.31 / 0.55 | 0.41 / 0.63 | 0.47× | 0.63× | 0.18 / 0.30 | 0.20 / 0.27 | 0.26 / 0.42 | 0.55 / 0.84 | 0.79 / 1.34 | 0.35× | 0.71× |
| `anim-kf-option-t500` | animation | 0.18 / 0.28 | 0.19 / 0.33 | 0.28 / 0.41 | 0.46 / 0.69 | 0.68 / 1.05 | 0.41× | 0.67× | 0.20 / 0.29 | 0.20 / 0.29 | 0.29 / 0.46 | 0.69 / 1.01 | 1.07 / 1.71 | 0.30× | 0.70× |
| `layout2-table-auto` | table | 0.66 / 0.85 | 0.62 / 1.07 | 1.01 / 1.56 | 1.17 / 1.58 | 1.52 / 2.23 | 0.53× | 0.65× | 1.15 / 1.50 | 1.11 / 1.52 | 1.68 / 2.33 | 2.08 / 2.68 | 3.20 / 4.03 | 0.53× | 0.69× |
| `layout2-table-spans` | table | 0.49 / 0.75 | 0.54 / 1.02 | 0.81 / 1.20 | 0.88 / 1.23 | 1.13 / 1.43 | 0.62× | 0.61× | 0.86 / 1.24 | 0.84 / 1.19 | 1.28 / 1.80 | 1.53 / 1.85 | 2.39 / 3.71 | 0.55× | 0.67× |
| `layout2-table-fixed` | table | 0.51 / 0.72 | 0.52 / 0.88 | 0.87 / 1.37 | 1.10 / 1.78 | 1.41 / 2.15 | 0.47× | 0.59× | 0.95 / 1.38 | 0.97 / 1.35 | 1.42 / 2.19 | 1.75 / 2.17 | 2.97 / 4.20 | 0.55× | 0.67× |
| `layout2-table-percent` | table | 0.37 / 0.43 | 0.35 / 0.64 | 0.58 / 0.78 | 0.71 / 0.99 | 0.89 / 1.14 | 0.49× | 0.64× | 0.53 / 0.68 | 0.52 / 0.78 | 0.80 / 1.26 | 1.13 / 1.55 | 1.67 / 1.91 | 0.46× | 0.67× |
| `layout2-table-collapse-conflicts` | table | 0.53 / 0.81 | 0.59 / 1.27 | 0.94 / 1.41 | 1.11 / 1.92 | 1.41 / 2.18 | 0.53× | 0.56× | 0.91 / 1.60 | 0.96 / 1.43 | 1.42 / 2.43 | 1.81 / 2.80 | 2.70 / 4.23 | 0.53× | 0.64× |
| `layout2-table-col-backgrounds` | table | 0.68 / 1.03 | 0.69 / 1.06 | 1.15 / 1.79 | 1.60 / 2.37 | 2.20 / 3.53 | 0.43× | 0.59× | 1.85 / 2.25 | 1.88 / 2.51 | 3.07 / 3.65 | 2.51 / 2.90 | 5.12 / 5.86 | 0.75× | 0.60× |
| `layout2-table-empty-cells` | table | 0.46 / 0.70 | 0.48 / 0.70 | 0.77 / 1.13 | 1.09 / 1.60 | 1.40 / 2.13 | 0.44× | 0.60× | 0.65 / 0.89 | 0.63 / 0.90 | 1.01 / 1.71 | 1.50 / 2.19 | 2.18 / 3.67 | 0.42× | 0.64× |
| `layout2-table-caption-bottom` | table | 0.63 / 1.04 | 0.64 / 1.01 | 1.07 / 1.85 | 1.27 / 2.15 | 1.68 / 2.32 | 0.50× | 0.59× | 0.96 / 1.42 | 0.95 / 1.26 | 1.60 / 2.38 | 1.88 / 2.49 | 2.92 / 3.65 | 0.51× | 0.60× |
| `layout2-float-image` | float | 0.37 / 0.65 | 0.43 / 0.78 | 0.76 / 1.20 | 0.76 / 1.09 | 0.93 / 1.49 | 0.57× | 0.48× | 1.73 / 2.51 | 1.69 / 3.25 | 2.53 / 4.29 | 1.63 / 1.98 | 6.05 / 8.54 | 1.04× | 0.69× |
| `layout2-float-clear` | float | 0.27 / 0.43 | 0.27 / 0.66 | 0.46 / 0.76 | 0.53 / 0.85 | 0.62 / 1.01 | 0.52× | 0.59× | 0.49 / 0.72 | 0.50 / 0.70 | 0.71 / 1.10 | 1.37 / 1.75 | 2.08 / 3.13 | 0.36× | 0.69× |
| `layout2-float-bfc` | float | 0.26 / 0.37 | 0.28 / 0.43 | 0.47 / 0.71 | 0.56 / 0.92 | 0.75 / 1.23 | 0.49× | 0.55× | 0.41 / 0.63 | 0.41 / 0.56 | 0.65 / 1.04 | 1.09 / 1.60 | 1.64 / 2.67 | 0.38× | 0.63× |
| `layout2-float-wrap` | float | 0.35 / 0.54 | 0.38 / 1.16 | 0.56 / 0.91 | 0.63 / 1.06 | 0.85 / 1.21 | 0.61× | 0.62× | 0.85 / 1.28 | 0.86 / 1.43 | 1.20 / 1.86 | 1.44 / 1.76 | 2.35 / 3.59 | 0.60× | 0.71× |
| `layout2-ib-badges` | inline-block | 0.29 / 0.41 | 0.31 / 0.49 | 0.52 / 0.71 | 0.66 / 0.91 | 0.79 / 1.13 | 0.48× | 0.56× | 0.70 / 0.85 | 0.72 / 0.83 | 0.95 / 1.23 | 1.46 / 1.83 | 1.93 / 2.51 | 0.50× | 0.73× |
| `layout2-ib-wrap` | inline-block | 0.46 / 0.67 | 0.55 / 1.03 | 0.93 / 1.16 | 0.89 / 1.88 | 1.23 / 1.59 | 0.62× | 0.50× | 0.81 / 1.30 | 0.77 / 1.26 | 1.18 / 1.70 | 1.73 / 2.11 | 2.32 / 3.64 | 0.45× | 0.68× |
| `layout2-ib-valign` | inline-block | 0.34 / 0.48 | 0.39 / 0.58 | 0.55 / 0.85 | 0.66 / 1.07 | 0.80 / 1.16 | 0.59× | 0.61× | 1.55 / 2.36 | 1.59 / 2.40 | 2.41 / 3.61 | 1.61 / 1.85 | 3.58 / 5.29 | 0.99× | 0.64× |
| `layout2-ib-json` | inline-block | 0.27 / 0.42 | 0.29 / 0.45 | 0.43 / 0.65 | 0.67 / 0.95 | 0.72 / 1.12 | 0.44× | 0.63× | 0.44 / 0.86 | 0.48 / 0.78 | 0.66 / 1.12 | 1.08 / 1.70 | 1.29 / 2.28 | 0.44× | 0.67× |
| `layout2-grid-areas` | grid-areas | 0.47 / 0.75 | 0.54 / 0.86 | 0.94 / 1.26 | 0.84 / 1.19 | 1.03 / 1.60 | 0.64× | 0.50× | 0.83 / 1.35 | 0.96 / 1.31 | 1.37 / 2.05 | 1.72 / 2.27 | 2.62 / 3.82 | 0.55× | 0.60× |
| `layout2-grid-named-lines` | grid-areas | 0.35 / 0.50 | 0.42 / 0.74 | 0.67 / 1.00 | 0.76 / 1.28 | 0.91 / 1.32 | 0.55× | 0.52× | 0.74 / 1.02 | 0.76 / 1.06 | 1.14 / 1.66 | 1.71 / 2.16 | 2.48 / 2.94 | 0.45× | 0.65× |
| `layout2-grid-areas-auto` | grid-areas | 0.27 / 0.50 | 0.33 / 0.58 | 0.57 / 0.90 | 0.76 / 1.14 | 0.89 / 1.48 | 0.44× | 0.49× | 0.59 / 0.85 | 0.64 / 0.86 | 0.91 / 1.36 | 1.43 / 1.88 | 1.97 / 3.01 | 0.45× | 0.66× |
| `layout3-float-left` | float-text | 0.38 / 0.55 | 0.46 / 0.73 | 0.68 / 1.04 | 0.81 / 1.07 | 0.93 / 1.33 | 0.57× | 0.57× | 0.92 / 1.34 | 0.90 / 1.23 | 1.25 / 1.88 | 1.66 / 1.81 | 2.47 / 3.54 | 0.55× | 0.73× |
| `layout3-float-right` | float-text | 0.38 / 0.60 | 0.43 / 0.94 | 0.66 / 1.06 | 0.79 / 1.07 | 0.94 / 1.34 | 0.54× | 0.58× | 0.87 / 1.31 | 0.91 / 1.23 | 1.24 / 1.85 | 1.62 / 1.92 | 2.40 / 3.83 | 0.56× | 0.70× |
| `layout3-float-stacked` | float-text | 0.57 / 0.77 | 0.62 / 1.17 | 0.88 / 1.34 | 0.98 / 1.22 | 1.22 / 1.75 | 0.63× | 0.64× | 1.60 / 1.90 | 1.36 / 1.98 | 2.10 / 2.68 | 1.86 / 2.39 | 3.57 / 5.02 | 0.73× | 0.76× |
| `layout3-float-tall` | float-text | 0.66 / 0.99 | 0.73 / 1.09 | 1.03 / 1.64 | 1.20 / 1.58 | 1.54 / 2.11 | 0.61× | 0.64× | 1.54 / 2.41 | 1.55 / 2.36 | 2.23 / 3.28 | 2.12 / 2.57 | 3.95 / 6.06 | 0.73× | 0.69× |
| `layout3-float-in-text` | float-text | 0.48 / 0.76 | 0.50 / 0.86 | 0.80 / 1.37 | 0.93 / 1.28 | 1.15 / 1.77 | 0.54× | 0.60× | 1.19 / 1.60 | 1.17 / 1.35 | 1.67 / 2.20 | 1.63 / 2.05 | 2.88 / 3.72 | 0.72× | 0.71× |
| `layout3-float-rtl` | float-text | 0.67 / 1.10 | 0.72 / 1.20 | 1.03 / 1.86 | 1.08 / 1.84 | 1.47 / 2.51 | 0.66× | 0.65× | 1.62 / 2.35 | 1.64 / 1.80 | 2.31 / 2.75 | 1.94 / 2.60 | 3.68 / 5.03 | 0.85× | 0.70× |
| `layout3-float-inline-box` | float-text | 0.38 / 0.59 | 0.40 / 0.83 | 0.62 / 1.00 | 0.68 / 0.99 | 0.91 / 1.33 | 0.59× | 0.61× | 0.90 / 1.13 | 0.93 / 1.08 | 1.30 / 1.71 | 1.56 / 2.00 | 2.38 / 3.17 | 0.59× | 0.69× |
| `layout3-inline-badges` | inline-flow | 0.49 / 0.63 | 0.51 / 0.87 | 0.83 / 1.24 | 0.94 / 1.40 | 1.24 / 1.42 | 0.54× | 0.60× | 1.02 / 1.45 | 1.01 / 1.29 | 1.49 / 2.27 | 1.71 / 2.01 | 2.82 / 4.15 | 0.59× | 0.68× |
| `layout3-inline-image` | inline-flow | 0.49 / 0.71 | 0.54 / 0.81 | 0.96 / 1.59 | 1.01 / 1.47 | 1.23 / 2.06 | 0.53× | 0.51× | 1.79 / 2.91 | 1.86 / 2.80 | 2.91 / 4.42 | 2.00 / 2.93 | 4.34 / 6.85 | 0.93× | 0.61× |
| `layout3-inline-flex-chip` | inline-flow | 0.61 / 0.92 | 0.66 / 1.22 | 1.29 / 2.07 | 1.16 / 2.00 | 1.60 / 2.33 | 0.57× | 0.47× | 1.68 / 2.00 | 1.77 / 2.58 | 2.83 / 3.76 | 2.18 / 2.77 | 4.67 / 5.77 | 0.81× | 0.59× |
| `layout3-inline-br` | inline-flow | 0.42 / 0.60 | 0.43 / 0.74 | 0.63 / 0.98 | 0.90 / 1.11 | 1.04 / 1.55 | 0.48× | 0.66× | 0.75 / 1.26 | 0.73 / 1.05 | 1.03 / 1.58 | 1.48 / 1.75 | 2.05 / 3.47 | 0.50× | 0.72× |
| `layout3-inline-abs` | inline-flow | 0.35 / 0.54 | 0.36 / 0.56 | 0.57 / 0.87 | 0.67 / 0.99 | 0.87 / 1.27 | 0.53× | 0.62× | 0.73 / 1.12 | 0.73 / 1.09 | 1.05 / 1.55 | 1.30 / 1.58 | 1.98 / 3.01 | 0.56× | 0.69× |
| `layout3-span-edges` | inline-box-model | 0.57 / 0.75 | 0.58 / 1.09 | 0.94 / 1.41 | 0.80 / 1.19 | 1.14 / 1.75 | 0.73× | 0.60× | 1.05 / 1.56 | 1.09 / 1.55 | 1.57 / 1.90 | 1.51 / 1.81 | 2.49 / 3.71 | 0.72× | 0.67× |
| `layout3-span-nowrap` | inline-box-model | 0.48 / 0.83 | 0.54 / 0.82 | 0.76 / 1.23 | 0.91 / 1.32 | 1.22 / 1.72 | 0.59× | 0.63× | 1.03 / 1.47 | 1.07 / 1.55 | 1.49 / 2.32 | 1.58 / 2.08 | 2.59 / 3.81 | 0.68× | 0.69× |
| `layout3-span-valign` | inline-box-model | 0.64 / 0.95 | 0.67 / 1.02 | 1.00 / 1.58 | 1.47 / 1.74 | 1.72 / 2.47 | 0.45× | 0.64× | 1.25 / 1.73 | 1.31 / 1.71 | 1.76 / 2.51 | 1.99 / 2.56 | 3.19 / 4.31 | 0.66× | 0.71× |
| `layout3-card-all` | inline-box-model | 1.39 / 1.68 | 1.43 / 1.69 | 2.37 / 3.00 | 2.33 / 2.64 | 3.22 / 3.48 | 0.62× | 0.59× | 4.13 / 4.68 | 4.00 / 4.79 | 6.14 / 7.46 | 4.25 / 4.91 | 9.31 / 10.3 | 0.94× | 0.67× |
| `fix-css-struct-text-nodes` | css-stylesheet | 0.59 / 1.00 | 0.63 / 1.16 | 0.89 / 1.37 | 1.23 / 2.35 | 1.46 / 2.40 | 0.51× | 0.67× | 0.89 / 1.30 | 0.89 / 1.31 | 1.33 / 1.93 | 2.16 / 2.91 | 3.28 / 4.53 | 0.41× | 0.67× |
| `fix-css-blank-text-dropped` | css-stylesheet | 0.31 / 0.40 | 0.29 / 0.43 | 0.48 / 0.72 | 0.62 / 0.89 | 0.78 / 1.16 | 0.47× | 0.64× | 0.45 / 0.65 | 0.47 / 0.68 | 0.65 / 1.00 | 1.07 / 1.47 | 1.45 / 2.29 | 0.44× | 0.69× |
| `fix-css-tw-structural-text` | tailwind | 0.58 / 1.00 | 0.61 / 1.06 | 0.93 / 1.49 | 1.08 / 1.78 | 1.38 / 2.20 | 0.56× | 0.62× | 0.80 / 1.22 | 0.84 / 1.31 | 1.19 / 1.97 | 1.54 / 2.38 | 2.33 / 2.99 | 0.55× | 0.67× |
| `fix-css-playground-css-demo` | css-stylesheet | 1.01 / 1.29 | 1.06 / 1.67 | 1.36 / 2.03 | 1.47 / 2.30 | 1.97 / 3.16 | 0.72× | 0.74× | 1.57 / 2.15 | 1.44 / 1.76 | 2.19 / 2.51 | 2.65 / 3.47 | 5.01 / 6.33 | 0.54× | 0.71× |
| `fix-css-transform-nested` | transform | 0.31 / 0.47 | 0.35 / 0.62 | 0.48 / 0.73 | 0.80 / 1.25 | 1.27 / 1.90 | 0.43× | 0.65× | 0.52 / 0.74 | 0.52 / 0.73 | 0.76 / 1.24 | 1.34 / 2.12 | 2.32 / 2.72 | 0.38× | 0.69× |
| `fix-css-transform-abs-text` | transform | 0.34 / 0.44 | 0.36 / 0.54 | 0.53 / 0.70 | 0.86 / 1.29 | 1.32 / 1.89 | 0.42× | 0.64× | 0.58 / 0.89 | 0.61 / 0.93 | 0.86 / 1.36 | 1.50 / 1.94 | 2.49 / 3.63 | 0.41× | 0.68× |
| `fix-css-image-rendering-pixelated` | images | 0.44 / 0.65 | 0.50 / 0.84 | 0.90 / 1.13 | 1.18 / 1.74 | 1.27 / 1.84 | 0.43× | 0.49× | 2.56 / 3.60 | 2.54 / 3.82 | 3.89 / 4.95 | 2.26 / 2.79 | 7.80 / 9.36 | 1.13× | 0.66× |
| `fix-css-image-rendering-modes` | images | 0.97 / 1.33 | 1.11 / 1.64 | 2.01 / 3.44 | 2.32 / 3.55 | 2.83 / 4.52 | 0.48× | 0.48× | 5.25 / 6.87 | 5.46 / 5.93 | 8.58 / 9.96 | 4.41 / 4.72 | 16.2 / 21.6 | 1.24× | 0.61× |
| `fix-css-tw-theme` | tailwind | 0.62 / 0.82 | 0.60 / 1.25 | 1.02 / 1.51 | 0.98 / 1.52 | 1.46 / 1.97 | 0.62× | 0.61× | 0.94 / 1.51 | 0.90 / 1.45 | 1.36 / 2.05 | 1.66 / 2.31 | 3.02 / 4.15 | 0.54× | 0.69× |
| `fix-css-tw-theme-node-vars` | tailwind | 0.24 / 0.35 | 0.29 / 0.43 | 0.45 / 0.59 | 0.48 / 0.86 | 0.59 / 0.78 | 0.61× | 0.54× | 0.34 / 0.51 | 0.35 / 0.58 | 0.51 / 0.81 | 0.71 / 1.05 | 1.03 / 1.59 | 0.49× | 0.66× |
| `fix-css-tw-animate` | tailwind | 0.44 / 0.66 | 0.46 / 0.67 | 0.72 / 1.23 | 0.69 / 1.06 | 1.10 / 1.49 | 0.67× | 0.61× | 0.58 / 0.81 | 0.58 / 0.81 | 0.89 / 1.37 | 1.03 / 1.53 | 1.62 / 2.67 | 0.57× | 0.65× |
| `fix-css-cascade-layers-tw` | css-stylesheet | 0.17 / 0.30 | 0.21 / 0.36 | 0.30 / 0.54 | 0.30 / 0.51 | 0.33 / 0.57 | 0.70× | 0.58× | 0.27 / 0.44 | 0.32 / 0.45 | 0.40 / 0.66 | 0.78 / 0.93 | 0.89 / 1.44 | 0.41× | 0.68× |
| `fix-css-anim-font-size-em-t0` | animation | 0.15 / 0.22 | 0.15 / 0.27 | 0.24 / 0.36 | 0.36 / 0.55 | 0.39 / 0.59 | 0.43× | 0.62× | 0.21 / 0.33 | 0.21 / 0.38 | 0.33 / 0.50 | 0.51 / 0.76 | 0.64 / 0.92 | 0.42× | 0.64× |
| `fix-css-anim-font-size-em-t500` | animation | 0.14 / 0.25 | 0.15 / 0.26 | 0.24 / 0.38 | 0.32 / 0.57 | 0.38 / 0.64 | 0.47× | 0.60× | 0.23 / 0.34 | 0.23 / 0.37 | 0.34 / 0.56 | 0.56 / 0.82 | 0.66 / 1.03 | 0.41× | 0.67× |
| `fix-text-overflow-string` | text-overflow | 0.38 / 0.65 | 0.41 / 0.65 | 0.58 / 0.91 | 0.95 / 1.37 | 1.19 / 1.86 | 0.43× | 0.66× | 0.69 / 1.01 | 0.70 / 1.00 | 0.96 / 1.50 | 1.45 / 1.99 | 2.15 / 3.41 | 0.48× | 0.71× |
| `fix-text-overflow-string-fallback` | text-overflow | 0.30 / 0.46 | 0.34 / 0.51 | 0.43 / 0.74 | 0.82 / 1.31 | 0.99 / 1.48 | 0.41× | 0.69× | 0.68 / 0.99 | 0.70 / 0.94 | 0.93 / 1.54 | 1.60 / 1.82 | 1.89 / 2.95 | 0.44× | 0.73× |
| `fix-text-overflow-string-rtl` | text-overflow | 0.31 / 0.46 | 0.31 / 0.45 | 0.45 / 0.71 | 0.78 / 1.15 | 0.95 / 1.26 | 0.39× | 0.69× | 0.53 / 0.76 | 0.55 / 0.78 | 0.81 / 1.08 | 1.41 / 1.58 | 2.15 / 2.66 | 0.39× | 0.66× |
| `fix-text-line-clamp-marker` | text-overflow | 0.36 / 0.62 | 0.39 / 0.58 | 0.57 / 0.87 | 0.90 / 1.34 | 1.16 / 1.92 | 0.43× | 0.64× | 0.75 / 1.09 | 0.76 / 1.15 | 1.06 / 1.82 | 1.51 / 2.00 | 2.38 / 3.73 | 0.51× | 0.70× |
| `fix-text-paint-order` | text-stroke | 0.82 / 1.32 | 0.87 / 1.39 | 1.62 / 2.27 | 0.71 / 1.11 | 1.02 / 1.56 | 1.21× | 0.51× | 1.44 / 1.80 | 1.47 / 2.11 | 2.15 / 2.93 | 1.41 / 1.78 | 2.49 / 3.51 | 1.04× | 0.67× |
| `fix-text-small-caps` | font-variant | 0.26 / 0.36 | 0.28 / 0.41 | 0.42 / 0.72 | 0.69 / 1.02 | 0.85 / 1.32 | 0.40× | 0.62× | 0.83 / 1.15 | 0.85 / 1.31 | 1.15 / 1.49 | 1.36 / 1.80 | 2.23 / 3.27 | 0.62× | 0.72× |
| `fix-text-all-small-caps` | font-variant | 0.36 / 0.55 | 0.41 / 0.62 | 0.59 / 0.83 | 0.91 / 1.34 | 1.15 / 1.72 | 0.45× | 0.61× | 1.05 / 1.49 | 1.00 / 1.19 | 1.44 / 1.73 | 1.61 / 2.22 | 3.05 / 4.60 | 0.62× | 0.73× |
| `fix-text-petite-unicase-caps` | font-variant | 0.70 / 1.04 | 0.73 / 1.30 | 0.98 / 1.64 | 1.42 / 2.23 | 1.76 / 2.62 | 0.51× | 0.72× | 1.87 / 2.61 | 1.97 / 2.90 | 2.63 / 3.82 | 3.00 / 3.53 | 4.97 / 7.08 | 0.66× | 0.71× |
| `fix-text-emoji-zwj` | emoji | 0.16 / 0.22 | 0.17 / 0.27 | 0.25 / 0.39 | 0.66 / 0.93 | 0.80 / 1.20 | 0.26× | 0.64× | 1.01 / 1.57 | 1.04 / 1.68 | 1.47 / 2.24 | 0.87 / 1.20 | 1.12 / 1.72 | 1.20× | 0.69× |
| `fix-text-emoji-flags-skin` | emoji | 0.12 / 0.19 | 0.14 / 0.19 | 0.19 / 0.28 | 0.42 / 0.64 | 0.54 / 0.75 | 0.33× | 0.63× | 0.27 / 0.40 | 0.26 / 0.40 | 0.36 / 0.54 | 0.76 / 1.12 | 0.97 / 1.48 | 0.34× | 0.75× |
| `fix-text-emoji-keycap-vs` | emoji | 0.13 / 0.21 | 0.13 / 0.20 | 0.21 / 0.30 | 0.42 / 0.64 | 0.54 / 0.87 | 0.32× | 0.63× | 0.31 / 0.48 | 0.31 / 0.45 | 0.42 / 0.63 | 0.75 / 1.10 | 0.96 / 1.43 | 0.42× | 0.74× |
| `fix-text-emoji-spacing` | emoji | 0.14 / 0.22 | 0.15 / 0.23 | 0.22 / 0.34 | 0.54 / 0.85 | 0.72 / 1.13 | 0.27× | 0.65× | 1.07 / 1.71 | 1.07 / 1.64 | 1.61 / 1.92 | 0.87 / 1.16 | 1.16 / 1.86 | 1.24× | 0.66× |
| `fix-text-emoji-wrap` | emoji | 0.13 / 0.21 | 0.14 / 0.23 | 0.21 / 0.32 | 0.55 / 0.80 | 0.67 / 1.06 | 0.25× | 0.63× | 0.46 / 0.68 | 0.47 / 0.69 | 0.64 / 0.95 | 0.82 / 1.13 | 1.05 / 1.57 | 0.57× | 0.71× |
| `fix-layout-rtl-flex` | rtl | 0.37 / 0.56 | 0.42 / 0.64 | 0.70 / 1.13 | 0.70 / 1.02 | 0.83 / 1.32 | 0.60× | 0.52× | 0.53 / 0.83 | 0.55 / 0.84 | 0.89 / 1.48 | 1.18 / 1.87 | 1.61 / 2.51 | 0.47× | 0.60× |
| `fix-layout-rtl-flex-wrap-abs` | rtl | 0.47 / 0.58 | 0.50 / 1.13 | 0.94 / 1.05 | 0.87 / 1.03 | 1.13 / 1.42 | 0.58× | 0.50× | 0.51 / 0.62 | 0.49 / 0.62 | 0.83 / 0.94 | 1.09 / 1.22 | 1.55 / 1.77 | 0.45× | 0.62× |
| `fix-layout-rtl-grid-block` | rtl | 0.36 / 0.55 | 0.42 / 0.66 | 0.68 / 1.03 | 0.76 / 1.10 | 0.93 / 1.35 | 0.55× | 0.53× | 0.60 / 0.87 | 0.61 / 0.93 | 0.95 / 1.49 | 1.34 / 1.74 | 1.79 / 2.73 | 0.46× | 0.64× |
| `fix-layout-rtl-table` | rtl | 0.73 / 1.11 | 0.74 / 1.10 | 1.26 / 1.97 | 1.74 / 2.65 | 2.34 / 3.58 | 0.43× | 0.58× | 1.19 / 1.90 | 1.25 / 1.88 | 1.94 / 3.02 | 2.37 / 3.54 | 4.22 / 6.07 | 0.53× | 0.62× |
| `fix-layout-rtl-node-dir` | rtl | 0.06 / 0.11 | 0.07 / 0.15 | 0.10 / 0.19 | 0.17 / 0.37 | 0.19 / 0.37 | 0.43× | 0.60× | 0.12 / 0.20 | 0.12 / 0.23 | 0.17 / 0.28 | 0.32 / 0.52 | 0.40 / 0.64 | 0.38× | 0.69× |
| `fix-layout-text-indent` | text-indent | 0.62 / 0.98 | 0.63 / 0.97 | 0.97 / 1.46 | 1.38 / 1.59 | 1.43 / 1.95 | 0.46× | 0.65× | 1.47 / 2.25 | 1.66 / 2.09 | 2.09 / 3.01 | 1.99 / 2.58 | 3.54 / 5.21 | 0.83× | 0.70× |
| `fix-layout-text-indent-keywords` | text-indent | 0.70 / 1.09 | 0.71 / 1.16 | 1.10 / 1.58 | 1.23 / 1.85 | 1.64 / 2.58 | 0.58× | 0.64× | 1.51 / 2.38 | 1.48 / 1.97 | 2.12 / 3.06 | 1.96 / 2.54 | 3.70 / 5.09 | 0.76× | 0.71× |
| `fix-layout-text-indent-sizing` | text-indent | 0.49 / 0.59 | 0.52 / 0.70 | 0.79 / 1.28 | 1.02 / 1.43 | 1.35 / 2.01 | 0.51× | 0.62× | 0.95 / 1.38 | 0.97 / 1.38 | 1.39 / 1.45 | 1.69 / 2.25 | 2.62 / 3.45 | 0.57× | 0.69× |
| `fix-layout-text-indent-node` | text-indent | 0.28 / 0.46 | 0.29 / 0.62 | 0.44 / 0.71 | 0.65 / 1.02 | 0.83 / 1.32 | 0.44× | 0.64× | 0.64 / 0.89 | 0.60 / 0.87 | 0.81 / 1.24 | 1.15 / 1.63 | 1.48 / 2.25 | 0.53× | 0.78× |
| `fix-layout-inline-rtl-box` | inline-bidi | 0.51 / 0.77 | 0.53 / 0.77 | 0.85 / 1.34 | 1.03 / 1.46 | 1.35 / 1.99 | 0.51× | 0.60× | 0.94 / 1.46 | 0.98 / 1.40 | 1.39 / 2.28 | 1.59 / 2.22 | 2.39 / 3.52 | 0.62× | 0.67× |
| `fix-layout-inline-bidi-fragments` | inline-bidi | 0.48 / 0.71 | 0.48 / 0.68 | 0.76 / 1.17 | 1.03 / 1.43 | 1.36 / 1.88 | 0.47× | 0.63× | 0.84 / 1.24 | 0.83 / 1.19 | 1.20 / 1.90 | 1.56 / 2.13 | 2.32 / 3.39 | 0.53× | 0.70× |
| `fix-layout-inline-bidi-wrap` | inline-bidi | 0.53 / 0.84 | 0.55 / 0.84 | 0.84 / 1.33 | 1.20 / 1.62 | 1.50 / 2.15 | 0.46× | 0.63× | 1.02 / 1.45 | 1.00 / 1.31 | 1.48 / 1.80 | 1.83 / 2.27 | 2.84 / 4.28 | 0.55× | 0.69× |
| `fix-layout-balance-inline-boxes` | text-wrap-balance | 0.69 / 0.94 | 0.70 / 1.16 | 1.10 / 1.68 | 1.46 / 1.98 | 1.86 / 2.80 | 0.48× | 0.63× | 1.18 / 1.84 | 1.21 / 1.79 | 1.77 / 2.24 | 2.00 / 2.56 | 3.41 / 4.88 | 0.60× | 0.67× |
| `fix-layout-balance-atomic` | text-wrap-balance | 0.76 / 1.30 | 0.75 / 1.27 | 1.17 / 2.12 | 1.39 / 2.38 | 1.91 / 3.02 | 0.54× | 0.65× | 1.45 / 2.17 | 1.51 / 1.99 | 2.07 / 2.72 | 2.28 / 2.75 | 4.10 / 5.37 | 0.66× | 0.70× |
| `fix-layout-balance-floats` | text-wrap-balance | 0.49 / 0.78 | 0.49 / 0.82 | 0.79 / 1.26 | 0.89 / 1.33 | 1.21 / 1.81 | 0.55× | 0.62× | 0.92 / 1.43 | 0.94 / 1.42 | 1.34 / 1.81 | 1.49 / 1.94 | 2.25 / 3.35 | 0.63× | 0.69× |
| `fix-layout-block-in-inline` | block-in-inline | 0.35 / 0.52 | 0.35 / 0.57 | 0.55 / 0.82 | 0.83 / 1.13 | 0.99 / 1.46 | 0.42× | 0.63× | 0.64 / 0.97 | 0.63 / 0.96 | 0.91 / 1.26 | 1.30 / 1.80 | 1.80 / 2.87 | 0.49× | 0.70× |
| `fix-layout-block-in-inline-nested` | block-in-inline | 0.53 / 0.89 | 0.56 / 0.94 | 0.87 / 1.36 | 1.14 / 1.83 | 1.53 / 2.27 | 0.49× | 0.62× | 1.04 / 1.47 | 1.04 / 1.50 | 1.52 / 2.23 | 2.07 / 2.63 | 2.99 / 4.22 | 0.51× | 0.68× |
| `fix-layout-block-in-inline-align` | block-in-inline | 0.41 / 0.54 | 0.43 / 0.63 | 0.67 / 1.04 | 0.98 / 1.43 | 1.26 / 1.78 | 0.44× | 0.61× | 0.74 / 1.04 | 0.74 / 1.20 | 1.10 / 1.54 | 1.62 / 2.06 | 2.40 / 3.33 | 0.46× | 0.67× |
| `fix-layout-block-in-inline-node` | block-in-inline | 0.18 / 0.26 | 0.20 / 0.31 | 0.28 / 0.42 | 0.50 / 0.79 | 0.58 / 0.82 | 0.41× | 0.64× | 0.35 / 0.53 | 0.35 / 0.47 | 0.48 / 0.74 | 0.80 / 1.21 | 0.99 / 1.51 | 0.43× | 0.73× |
| `fix-layout-float-paint-text` | float-paint-order | 0.31 / 0.46 | 0.32 / 0.48 | 0.49 / 0.76 | 0.63 / 0.91 | 0.81 / 1.15 | 0.51× | 0.63× | 0.62 / 0.94 | 0.63 / 0.94 | 0.92 / 1.37 | 1.11 / 1.65 | 1.41 / 1.78 | 0.56× | 0.68× |
| `fix-layout-float-paint-layers` | float-paint-order | 0.47 / 0.65 | 0.53 / 0.74 | 0.77 / 1.13 | 1.03 / 1.43 | 1.41 / 1.94 | 0.52× | 0.62× | 0.74 / 1.05 | 0.75 / 1.07 | 1.11 / 1.63 | 1.55 / 1.91 | 2.09 / 3.02 | 0.48× | 0.66× |
| `fix-layout-float-paint-nested` | float-paint-order | 0.52 / 0.70 | 0.53 / 0.78 | 0.96 / 1.10 | 1.12 / 1.39 | 1.15 / 1.81 | 0.48× | 0.54× | 0.67 / 1.03 | 0.66 / 1.04 | 0.99 / 1.26 | 1.26 / 1.71 | 1.78 / 2.33 | 0.52× | 0.68× |
| `fix-layout-inline-relative` | inline-relative | 0.52 / 0.77 | 0.53 / 0.81 | 0.78 / 1.27 | 1.09 / 1.76 | 1.33 / 2.11 | 0.48× | 0.67× | 0.86 / 1.30 | 0.88 / 1.31 | 1.23 / 1.78 | 1.55 / 2.00 | 2.11 / 2.95 | 0.57× | 0.70× |

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
