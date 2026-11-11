# bm-engine

Bản port bằng **Zig 0.17** của phần lõi [takumi](https://github.com/kane50613/takumi) (cây node/JSX → ảnh),
biên dịch ra wasm theo ba cấu hình — **core 429 KiB, standard 850 KiB, full 1 070 KiB** (takumi: 4 235 KiB) — chạy được ở cả trình duyệt lẫn Node.js / Bun /
Deno / edge runtime. Module wasm **không có import nào** (không WASI, không glue wasm-bindgen).

- Nhận cùng định dạng node của takumi (`{ type: "container" | "text" | "image", style, children }`),
  cùng tuỳ chọn `render(node, { width, height, format, quality, devicePixelRatio, images })`.
- Layout: flexbox, block, CSS grid, absolute — khớp takumi tới 1/64 px trên toàn bộ fixture.
- Vẽ: màu nền, gradient (linear / radial / conic, repeating), border, border-radius, box-shadow (outer + inset),
  opacity, overflow clip, transform 2D, text-shadow, filter (blur, grayscale, …), ảnh PNG/JPEG/WebP-lossless/GIF
  với object-fit, background-image `url()`.
- Text: font TrueType tĩnh (`.ttf` / `.ttc`), kerning GPOS, ligature GSUB cơ bản, xuống dòng UAX#14 rút gọn,
  line-height, letter-spacing, text-align, ellipsis, line-clamp, fake bold / fake italic.
- Xuất: PNG (indexed / RGB / RGBA tự chọn), JPEG, WebP lossless, raw RGBA.

Kết quả benchmark và so sánh điểm ảnh với takumi: [docs/BENCHMARK.md](docs/BENCHMARK.md).
Kiến trúc: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Ghi chú ngữ nghĩa takumi: [docs/TAKUMI_NOTES.md](docs/TAKUMI_NOTES.md).

## Cấu hình build

| Profile | Kích thước (wasm-opt) | File | Nội dung |
|:--|--:|:--|:--|
| core | 428.5 KiB | `js/bm_engine.core.wasm` (`js/node-core.mjs`) | node JSON + style inline, flex/grid/block, TTF tĩnh, PNG/JPEG |
| standard | 849.6 KiB | `js/bm_engine.standard.wasm` (`js/node-standard.mjs`) | + CSS, Tailwind, HTML, SVG, WOFF2, font biến thiên, CFF, bảng, float, hiệu ứng |
| full | 1 070.0 KiB | `js/bm_engine.wasm` (`js/node.mjs`) | + chữ phức/bidi, emoji màu, animation, renderSvg, codec phụ |

`node scripts/build.mjs` build cả ba (`--profile=core|standard|full` để build một); `zig build -Dprofile=core -D<cờ>=true|false` để tuỳ biến.
Add-on `js/bm_woff.wasm` (84 KiB) + `js/addons.mjs` cho phép bản core nạp WOFF/WOFF2 theo yêu cầu. `features` (export của `js/index.mjs`) cho biết bản đang nạp có gì.
Giai đoạn 2 đã port thêm: stylesheet/selector, Tailwind, HTML, SVG vào/ra (`renderSvg`), WOFF2, font biến thiên, CFF, emoji màu, shaping đầy đủ + bidi,
bảng, float, animation + `renderAnimation`, clip-path/mask/blend, viền nét đứt, WebP lossy, ảnh động, ICO. Test trình duyệt thật: `cd bench && npm run browser`.

## Dùng thử

Node.js (file wasm đã build sẵn nằm ở `js/bm_engine.wasm`):

```js
import { readFileSync } from "node:fs";
import { Renderer } from "./js/node.mjs";

const r = new Renderer();
r.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });

const png = r.renderSync(
  {
    type: "container",
    style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
             backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)" },
    children: [{ type: "text", text: "Xin chào Việt Nam", style: { fontFamily: "Inter", fontSize: 64, color: "white" } }],
  },
  { width: 1200, height: 630 }, // format: "png" (mặc định) | "jpeg" | "webp" | "raw"
);
```

Trình duyệt / edge (ESM, không cần bundler):

```js
import init, { Renderer } from "./js/index.mjs";
await init(fetch(new URL("./js/bm_engine.wasm", import.meta.url))); // hoặc bytes / WebAssembly.Module
const r = new Renderer();
r.registerFont(await (await fetch("/Inter-Regular.ttf")).arrayBuffer());
const png = await r.render(node, { width: 1200, height: 630 });
```

Ví dụ đầy đủ: `examples/browser.html` (serve thư mục gốc qua HTTP rồi mở `/examples/browser.html`).

API: `init()` / `initSync()`, `new Renderer()`, `registerFont(bytes | { name, data, weight, style })`,
`render()` / `renderSync()`, `measure()` / `measureSync()`, `renderAsDataUrl()`, `clearFonts()`, `memoryBytes()`, `free()`.

## Build

Yêu cầu: Zig **0.17.x**, Node.js ≥ 20 (chỉ để chạy `wasm-opt` và benchmark).

```powershell
# 1. cài công cụ benchmark + wasm-opt (binaryen), không chạy install script
cd D:\project\bm-engine\bench ; npm install --ignore-scripts ; cd ..

# 2. build bản phát hành: zig build (optimize = small) + wasm-opt -Oz → zig-out/bin/bm_engine.wasm và js/bm_engine.wasm
$env:ZIG = "C:\Users\admini\Downloads\zig-x86_64-windows-0.17.1\zig-x86_64-windows-0.17.1\zig.exe"
node scripts/build.mjs

# (hoặc chỉ biên dịch, không wasm-opt)
& $env:ZIG build
# tuỳ chọn: -Dwasm-optimize=fast|safe|debug  -Dstrip=false  -Dstack-kib=1024

# 3. unit test native của mọi module (137 test)
& $env:ZIG build test --summary all
```

## Benchmark & kiểm tra tương đương với takumi

```powershell
cd D:\project\bm-engine\bench
node run.mjs                 # đầy đủ: tương đương điểm ảnh + hiệu năng + cold start + bộ nhớ + kích thước
node run.mjs --quick         # nhanh
node run.mjs --filter="text|card" --engines=takumi-wasm,bm
node report.mjs              # sinh lại out/RESULTS.md từ out/results.json
node selftest.mjs            # tự kiểm tra bộ đo (SSIM, pixelmatch, …)
node probe/lay.mjs "^(?!transform)" 0.001   # so cây layout (measure) với takumi, sai số 0.001 px
```

Ảnh kết quả từng fixture: `bench/out/<id>/{takumi,bm,native,diff}.png`.

Fuzz toàn pipeline trên bản ReleaseSafe:

```powershell
& $env:ZIG build "-Dwasm-optimize=safe" "-Dstrip=false" -p $env:TEMP\bmsafe
$env:BM_WASM = "$env:TEMP\bmsafe\bin\bm_engine.wasm" ; node bench/probe/fuzz.mjs 1 3000
```

## Cấu trúc thư mục

```
src/json.zig       parser JSON tối giản        src/style/    parse giá trị CSS → ComputedStyle
src/layout/        flex / block / grid         src/font/     sfnt, GPOS/GSUB, shaping, dàn dòng
src/raster/        path, rasterizer AA, blur   src/codec/    PNG, JPEG, WebP, GIF, deflate
src/render.zig     pipeline + cache            src/paint.zig painter (thứ tự vẽ kiểu Blink)
src/bump.zig, src/pages.zig   cấp phát bộ nhớ  src/wasm.zig  export C-ABI
js/                wrapper ESM + bm_engine.wasm
bench/             fixture dùng chung với takumi, harness benchmark, probe
ref/takumi/        bản clone takumi để tham chiếu (không nằm trong git)
```

## Giấy phép

Chưa chọn giấy phép cho mã nguồn bm-engine (tuỳ chủ dự án quyết định). Font trong `assets/fonts` theo giấy phép riêng
của từng font (Inter, Noto Sans: OFL; Roboto: Apache-2.0). takumi (tham chiếu) là MIT / Apache-2.0.
