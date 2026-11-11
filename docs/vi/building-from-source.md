# Build từ mã nguồn

[English](../en/building-from-source.md) · [Tiếng Việt](building-from-source.md)

Cách build ba profile wasm và add-on WOFF, chạy unit test, benchmark tương đương với takumi, test trình
duyệt và fuzzer, cùng cấu trúc của repository. Bạn chỉ cần trang này khi muốn sửa engine hoặc tự build
bản riêng; package npm đã kèm sẵn binary build sẵn.

## Yêu cầu

- **Zig 0.17.x** (phát triển với 0.17.1). Không cần khi chỉ dùng package.
- **Node.js ≥ 20** cho script build (nó chạy `wasm-opt`), benchmark và playground.
- `wasm-opt` từ binaryen: được cài bằng `npm install` ở thư mục gốc repository (dev dependency
  `binaryen`) hoặc trong `bench/`. Nếu thiếu, script build sẽ cảnh báo và xuất binary chưa tối ưu.

Script build tìm Zig qua biến môi trường `ZIG`, nếu không có thì dùng `zig` trên `PATH`.

## Các lệnh

```sh
npm install                        # root dev dependency: binaryen (wasm-opt)

node scripts/build.mjs             # core + standard + full + WOFF add-on: zig build (optimize=small) + wasm-opt -Oz
node scripts/build.mjs --profile=core          # one profile (core | standard | full)
node scripts/build.mjs -- -Dtables=false       # extra zig options for every profile (marked "custom" in the manifest)
node scripts/build.mjs --manifest  # rewrite js/build-manifest.json from the wasm files in js/
node scripts/build.mjs --verify    # check js/*.wasm against the manifest (run by prepublishOnly)
node scripts/build.mjs --test      # zig build test (also: npm test)
```

Đầu ra: `js/bm_engine.core.wasm`, `js/bm_engine.standard.wasm`, `js/bm_engine.wasm` (full),
`js/bm_woff.wasm`, `zig-out/bin/bm_engine.wasm` (full, đã tối ưu), `js/build-manifest.json` (profile,
kích thước, sha256 và bit tính năng của từng file) và một bảng kích thước ghi vào `bench/out/sizes.json`.

Lệnh Zig trực tiếp:

```sh
zig build                                   # full profile, optimize=small -> zig-out/bin/bm_engine.wasm (+ bm_woff.wasm)
zig build -Dprofile=standard -Dcss=false    # any profile + single-feature flags
zig build -Dwasm-optimize=safe -Dstrip=false  # safety-checked build (for fuzzing / debugging)
zig build addons                            # only the add-on modules
zig build test --summary all                # native unit tests of every module
```

Tùy chọn: `-Dprofile=core|standard|full`, mỗi tính năng một cờ `-D<feature>=true|false` (danh sách ở
[Profile và kích thước](profiles-and-size.md#build-tùy-biến)), `-Dwasm-optimize=small|fast|safe|debug`,
`-Dstrip=false`, `-Dstack-kib=<n>` (shadow stack, mặc định 1024).

Trong một bản checkout mã nguồn, `import "bm-engine"` trỏ về repository (hoặc import thẳng `js/node.mjs`)
sẽ ưu tiên file `zig-out/bin/bm_engine.wasm` vừa build hơn file `js/bm_engine.wasm` đóng gói sẵn.
`BM_WASM=<path>` nạp một binary bất kỳ.

## Kiểm thử

| Nội dung | Lệnh | Ghi chú |
|:--|:--|:--|
| Unit test (native, mọi module) | `zig build test --summary all` | dữ liệu test nằm cạnh từng module trong `testdata/` |
| Một module | `zig test src/<module>/<module>.zig` | module import module anh em được test qua một file gốc `src/test_*.zig` |
| Smoke test package | `npm run test:pack` | `scripts/pack-test.mjs`: đóng gói tarball npm rồi import nó |
| Thăm dò tính năng theo profile | `node bench/probe/profiles.mjs` | mỗi binary xử lý đầu vào của tính năng bị thiếu ra sao; thất bại nếu có trap |
| Tương đương + benchmark với takumi | `cd bench && npm install --ignore-scripts && node run.mjs` | xem [Benchmark](benchmark.md#tái-lập-kết-quả) |
| Trình duyệt thật | `cd bench && npm run browser:quick` | Edge / Chrome headless qua puppeteer-core; đầu ra raw phải trùng với Node |
| Fuzz (toàn pipeline) | xem bên dưới | chạy trên bản build có kiểm tra an toàn |

Fuzz toàn pipeline bằng cây node ngẫu nhiên trên bản ReleaseSafe (vi phạm an toàn sẽ thành trap của
wasm thay vì âm thầm làm hỏng bộ nhớ):

```sh
zig build -Dwasm-optimize=safe -Dstrip=false -p /tmp/bmsafe
cd bench
BM_WASM=/tmp/bmsafe/bin/bm_engine.wasm node probe/fuzz.mjs 1 3000   # seed, iterations
```

## Cách harness kiểm tra tương đương hoạt động

`bench/` render mọi fixture trong `bench/fixtures/*.mjs` bằng takumi-wasm 2.20 (oracle), takumi-native
(sàn nhiễu) và bm-engine, từ cùng cây node, font và ảnh. Với mỗi ca, đầu ra `raw` được so sánh
(`bench/lib/metrics.mjs`): trùng byte, pixelmatch có và không có dung sai khử răng cưa, sai khác kênh
trung bình / lớn nhất, PSNR và SSIM (độ sáng và RGB). Kết luận là identical / equivalent / close /
different như định nghĩa ở [Benchmark](benchmark.md#điều-kiện-đo). Phần đo thời gian chạy xen kẽ các
engine theo từng ca; cold start và bộ nhớ chạy trong tiến trình con mới. Adapter của các engine nằm trong
`bench/engines/`, đầu ra trong `bench/out/` (`results.json`, `RESULTS.md`, PNG và ảnh diff của từng ca).
Các oracle cấp module (cây layout, bề rộng chữ, màu, luật thắng trong cascade, đầu ra Tailwind, SVG,
khung animation) nằm trong `bench/probe/`.

## Cấu trúc thư mục

```
src/wasm.zig          wasm exports (C ABI), the only entry of the binary
src/config.zig        compile-time feature flags (set from build.zig profiles / -D flags)
src/render.zig        pipeline: source -> DOM -> style -> layout -> paint -> encode; options, caches
src/dom.zig           node tree from JSON, preset / css / tw / style cascade per element
src/json.zig          JSON parser
src/style/            CSS value parsing -> ComputedStyle (props.zig = property table), colours, gradients, calc
src/css/              stylesheet tokenizer / parser, selectors, cascade, @media / @supports
src/tw/               Tailwind compiler + palette
src/html/             HTML tokenizer / tree builder, UA presets, entities
src/layout/           block, inline, flex, grid, table, float layout
src/font/             sfnt / CFF / variations, shaping (GSUB / GPOS, Arabic, Indic), bidi, colour glyphs
src/woff/             WOFF / WOFF2 + brotli;  src/addon_woff.zig = the add-on module
src/raster/           paths, scan conversion (tiny-skia-exact AA), stroking, blur, blending, images
src/paint*.zig        painter (Blink paint order), borders, effects, text, tables, SVG images
src/svg/              SVG parser + renderer (for SVG images)
src/svg_out*.zig      renderSvg (node tree -> SVG document)
src/animate.zig       CSS animation sampling
src/codec/            PNG, JPEG, WebP (lossless + VP8), GIF, ICO, animation encoders, deflate / inflate
src/bump.zig, pages.zig  allocators (per-render bump arena, page allocator)
js/                   ESM wrapper (engine.mjs + entries), typings, prebuilt wasm, build manifest
scripts/              build.mjs (release build, manifest), pack-test.mjs
bench/                fixtures shared with takumi, benchmark / equivalence harness, probes, browser test
playground/           browser playground (see playground.md)
docs/                 user docs (en/, vi/) and developer docs (ARCHITECTURE, TAKUMI_NOTES, CONVENTIONS, BENCHMARK)
ref/takumi/           local clone of takumi used as a read-only reference (not in git)
```

## Tài liệu cho nhà phát triển

- [ARCHITECTURE.md](../ARCHITECTURE.md): thiết kế, sơ đồ module, pipeline render, ABI của wasm.
- [TAKUMI_NOTES.md](../TAKUMI_NOTES.md): ngữ nghĩa của takumi mà bản port tái hiện (giá trị mặc định, đơn
  vị, DPR, font dự phòng, bộ mã hoá), kèm tham chiếu mã nguồn.
- [CONVENTIONS.md](../CONVENTIONS.md): quy tắc kỹ thuật (không `std.Io` / libc trong mã thư viện, kỷ luật
  với đầu vào không tin cậy, kỷ luật kích thước, quyền sở hữu file).
- [BENCHMARK.md](../BENCHMARK.md), [RESULTS_FULL.md](../RESULTS_FULL.md), [results.json](../results.json):
  số liệu đo.

## Đóng góp

- Đọc [CONVENTIONS.md](../CONVENTIONS.md) trước: mã thư viện nhận allocator tường minh, không bao giờ
  trap với đầu vào không tin cậy (kiểm tra biên, không `unreachable`, đệ quy có giới hạn: shadow stack của
  wasm chỉ 1 MiB), và báo cáo chi phí kích thước wasm của mình.
- Mọi tính năng tùy chọn phải được bảo vệ bằng một cờ trong `src/config.zig` để có thể loại khỏi các
  profile nhỏ; chạy `node bench/probe/profiles.mjs` sau khi động vào ranh giới tính năng.
- Một thay đổi về render phải giữ benchmark ở mức 0 fixture "different"; thêm fixture vào
  `bench/fixtures/` cho hành vi mới, so với takumi và ghi kết quả vào `docs/BENCHMARK.md`.
- `ref/takumi` là bản clone của bên thứ ba chỉ để đọc; không chạy bất cứ thứ gì trong đó.
