# Bắt đầu

[English](../en/getting-started.md) · [Tiếng Việt](getting-started.md)

Trang này đưa bạn từ `npm install` tới một ảnh đã render trên Node.js, trong trình duyệt (có hoặc không
có bundler) và trên edge runtime, rồi đi qua ba quyết định mà dự án nào cũng phải đưa ra: nạp profile
build nào, đăng ký font nào (bm-engine **không** kèm sẵn font) và ảnh đi vào renderer bằng cách nào. Mọi
đoạn mã Node.js trên trang này đều đã được chạy thật với bm-engine 0.1.0 thông qua cơ chế phân giải
package; những đoạn dành cho runtime không chạy thử được ở đây đều được ghi chú rõ.

- [Cài đặt](#cài-đặt)
- [Các điểm vào của package](#các-điểm-vào-của-package)
- [Node.js](#nodejs)
- [Trình duyệt không dùng bundler](#trình-duyệt-không-dùng-bundler)
- [Bundler (Vite, webpack, Rollup, esbuild, Next.js)](#bundler)
- [Cloudflare Workers và các edge runtime khác, Deno, Bun](#edge-runtime-deno-bun)
- [Chọn profile](#chọn-profile)
- [Font](#font)
- [Ảnh](#ảnh)
- [Định dạng đầu ra](#định-dạng-đầu-ra)

## Cài đặt

```sh
npm install bm-engine
```

Package không có dependency và không có install script. Bên trong gồm ba binary WebAssembly build sẵn
(`core`, `standard`, `full`), add-on WOFF tùy chọn, một wrapper ESM không phụ thuộc gì và các khai báo
TypeScript. Package chỉ phát hành dạng ES module (xem [CommonJS](#commonjs)).

Package cũng khai báo tám **optional dependency**, mỗi nền tảng một cái: `bm-engine-win32-x64-msvc`,
`bm-engine-linux-x64-gnu`, ... (bảng bên dưới). Mỗi package chỉ chứa bản build Node-API native của cùng
engine (khoảng 1 MB sau nén) và khai báo `os`, `cpu` và, trên Linux, `libc`, nên package manager chỉ cài
đúng cái khớp với máy và bỏ qua những cái còn lại. Không có gì được biên dịch hay tải về lúc cài hoặc lúc
chạy; không có postinstall script.

### Native trên Node.js, WebAssembly ở mọi nơi khác

Trên Node.js, `import ... from "bm-engine"` dùng addon native khi platform package của nó được cài và nạp
được; nếu không, nó **tự động và lặng lẽ** chuyển sang binary WebAssembly `full`. API giống hệt và output
giống hệt, đến từng byte; ở dạng native engine chạy nhanh hơn và các method async (`render`, `renderSvg`,
`measure`, `renderAnimation`, ...) chạy trên thread pool của libuv thay vì chặn event loop. Trình duyệt,
bundler cho trình duyệt, worker và edge runtime không bao giờ thấy code native.

```js
import { backend } from "bm-engine";
console.log(backend); // "native" or "wasm"
```

| Muốn ép | Dùng |
|:--|:--|
| WebAssembly trên Node | `BM_ENGINE_BACKEND=wasm`, hoặc import `bm-engine/full` (luôn là wasm) |
| native, hoặc báo lỗi rõ ràng | `BM_ENGINE_BACKEND=native` (lệnh import ném lỗi và nói lý do), hoặc import `bm-engine/native` |

Lý do addon không được dùng nằm trong thông báo lỗi của `BM_ENGINE_BACKEND=native node app.mjs`, ví dụ
`bm-engine: BM_ENGINE_BACKEND=native, but the native addon is not available (bm-engine-linux-x64-gnu: not
installed)`.

| Platform package | `os` / `cpu` / `libc` | Trạng thái |
|:--|:--|:--|
| `bm-engine-win32-x64-msvc` | win32 / x64 | **đã chạy**: giống hệt từng byte với wasm trên 250 fixture, test luồng / bộ nhớ / fuzz, test cài đặt |
| `bm-engine-win32-arm64-msvc` | win32 / arm64 | đã build và kiểm tra cấu trúc, **chưa từng chạy** |
| `bm-engine-linux-x64-gnu` | linux / x64 / glibc 2.17+ | đã build và kiểm tra cấu trúc, **chưa từng chạy** |
| `bm-engine-linux-x64-musl` | linux / x64 / musl (Alpine) | đã build và kiểm tra cấu trúc, **chưa từng chạy** |
| `bm-engine-linux-arm64-gnu` | linux / arm64 / glibc 2.17+ | đã build và kiểm tra cấu trúc, **chưa từng chạy** |
| `bm-engine-linux-arm64-musl` | linux / arm64 / musl | đã build và kiểm tra cấu trúc, **chưa từng chạy** |
| `bm-engine-darwin-x64` | darwin / x64 (macOS 10.15+) | đã build và kiểm tra cấu trúc, **chưa từng chạy** |
| `bm-engine-darwin-arm64` | darwin / arm64 (macOS 11+) | đã build và kiểm tra cấu trúc, **chưa từng chạy** |

"Kiểm tra cấu trúc" nghĩa là script build đã kiểm tra từng binary mà không chạy nó (định dạng, CPU, các
symbol export và import, phiên bản symbol của glibc, không import thư viện toán). Cho tới khi một nền tảng
được chạy thật, hãy dựa vào cơ chế fallback: nếu addon của nó không nạp được, `bm-engine` dùng WebAssembly.
Các bản build x64 cần CPU x86-64-v2 (SSE4.2, từ 2009 trở đi); CPU cũ hơn dùng WebAssembly. Cần Node.js 18
trở lên.

### Package manager, Docker, serverless

- **npm, pnpm, Yarn, Bun** tôn trọng `os` và `cpu` (ở đây chỉ npm được kiểm thử). `libc` (glibc hay musl) được npm hiện tại (đã kiểm
  thử: npm 11) và, theo tài liệu của chúng, pnpm và Yarn 3.2+ tôn trọng; một package manager bỏ qua nó có thể cài cả hai biến thể
  Linux cho kiến trúc của bạn, điều này vô hại: `bm-engine` phát hiện musl và nạp đúng cái.
- **`npm install --omit=optional`** (`--no-optional`, Yarn `--ignore-optional`, ...) không cài platform
  package nào: bạn nhận WebAssembly (đã kiểm thử với npm).
- **Lockfile tạo trên hệ điều hành khác.** Với npm 11, lockfile ghi trên Windows liệt kê đủ tám package
  cùng `os` / `cpu` / `libc` của chúng, và `npm ci` cho Linux x64 cài `bm-engine-linux-x64-gnu` (đã kiểm
  thử). Một số phiên bản npm cũ hơn làm rơi optional package của các nền tảng khác khỏi lockfile khi
  `node_modules` đã tồn tại (npm/cli#4828), cái bẫy kinh điển của package native. Ở đây nó không gây lỗi:
  thiếu addon nghĩa là WebAssembly, không phải lỗi. Để sửa, xóa `node_modules` và lockfile rồi cài lại, và
  kiểm tra `backend` trong CI.
- **Docker.** Chạy `npm ci` bên trong image, trên nền tảng của image; đừng chép `node_modules` được build
  trên máy Windows hay macOS vào một image Linux (bạn sẽ nhận WebAssembly). Build đa kiến trúc
  (`docker buildx --platform linux/amd64,linux/arm64`) cài đúng package cho từng kiến trúc. Image Alpine
  nhận package `-musl`.
- **Cài cho một máy khác** (ví dụ build bản deploy Linux trên máy Mac): có thể báo cho npm biết nền tảng
  đích, và khi đó cần đủ cả ba cờ (không có `--libc`, trên Windows npm không cài package Linux nào):

  ```sh
  npm ci --os=linux --cpu=x64 --libc=glibc     # AWS Lambda x86_64, most Linux servers
  npm ci --os=linux --cpu=arm64 --libc=glibc   # Lambda arm64 (Graviton)
  npm ci --os=linux --cpu=x64 --libc=musl      # Alpine
  ```

  pnpm và Yarn dùng `supportedArchitectures` trong cấu hình của chúng.
- **Serverless (AWS Lambda, Vercel Functions, Netlify Functions, ...).** Binary được chọn lúc cài
  dependency, trên máy build: nền tảng build trên Linux x64 (Vercel, Netlify, đa số CI) nhận
  `bm-engine-linux-x64-gnu`; một file zip `node_modules` tạo trên Mac hoặc Windows mang theo binary sai
  (lúc chạy là WebAssembly). Các công cụ deploy có bundle cũng phải mang theo platform package; xem
  [Next.js](./frameworks/nextjs.md#addon-native-khi-triển-khai) về `outputFileTracingIncludes`. Hãy log
  `backend` một lần khi khởi động để biết thứ gì đang chạy. Chưa kiểm thử kiểu deploy nào trong số này.
- **Bun, Deno, Electron** nạp điểm vào `node` và có thể nạp được addon; chưa kiểm thử. Nếu không nạp
  được, chúng dùng WebAssembly.

## Các điểm vào của package

| Import | Node.js (điều kiện `node`) | Mọi nơi khác (trình duyệt, bundler, worker, Deno) |
|:--|:--|:--|
| `bm-engine` | addon native nếu đã cài, nếu không thì binary `full`, sẵn sàng ngay khi import (`BM_ENGINE_BACKEND`, `BM_PROFILE`, `BM_WASM` ghi đè) | chỉ có wrapper: bạn tự gọi `init(wasm)` với binary |
| `bm-engine/native` | addon native, nếu không có thì lệnh import ném lỗi | không có |
| `bm-engine/full` | `full`, tự khởi tạo khi import | `await init()` tự tìm `bm_engine.wasm` nằm cạnh module (hoặc truyền vào) |
| `bm-engine/standard` | `standard`, tự khởi tạo khi import | `await init()` tự tìm `bm_engine.standard.wasm` |
| `bm-engine/core` | `core`, tự khởi tạo khi import | `await init()` tự tìm `bm_engine.core.wasm` |
| `bm-engine/woff` | `loadWoff()` / `decodeWoff()` — add-on WOFF | như bên trái |
| `bm-engine/full.wasm`, `/standard.wasm`, `/core.wasm`, `/woff.wasm` (`bm-engine/wasm` = full) | các binary thô, dùng cho import asset của bundler và import module trên Workers; mỗi file còn có dạng `...wasm?module` cho Next.js Edge | như bên trái |

Mọi điểm vào đều có cùng API (`init`, `initSync`, `Renderer`, `features`, `backend`, ...; các điểm vào theo
profile còn export thêm `profile` và `wasmUrl()`). Mỗi điểm vào có **instance module riêng**, nên có thể
nạp nhiều profile song song trong một tiến trình; trong cùng một điểm vào, lần `init` thành công đầu
tiên được giữ và các lần gọi sau trả về đúng instance đó. `bm-engine` và `bm-engine/full` cũng là hai
instance riêng: import cả hai trên Node sẽ nạp binary full hai lần, nên chỉ chọn một.

## Node.js

Trên Node.js, mọi điểm vào đều sẵn sàng ngay khi import (`bm-engine` với addon native hoặc, nếu không có, giống
các điểm vào theo profile: đọc binary wasm từ đĩa và khởi tạo đồng bộ), nên bạn có thể tạo `Renderer` luôn:

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const png = renderer.renderSync(
  {
    type: "container",
    style: {
      display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
      backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)",
    },
    children: [{ type: "text", text: "Hello from bm-engine", style: { fontFamily: "Inter", fontSize: 64, color: "white" } }],
  },
  { width: 1200, height: 630 },
);
writeFileSync("og.png", png);
```

Cần lưu ý:

- **Đăng ký font trước khi render chữ.** Nếu chưa có font, chữ sẽ không được vẽ và cũng không báo lỗi
  (takumi kèm sẵn font Geist; bm-engine thì không). Xem [Font](#font).
- `renderSync` trả về `Uint8Array` (PNG nếu bạn không truyền `format`). Method nào cũng có bản async
  tương ứng (`render`, `measure`, ...). Với backend native, các bản async render trên thread pool
  của libuv (một renderer chỉ chạy một lệnh tại một thời điểm: tạo vài renderer để render song song); với
  wasm, việc render luôn đồng bộ và các bản async tồn tại để tương thích với takumi và để xử lý những tùy
  chọn cần chờ (`fonts`, `images` nạp lười).
- `display` mặc định là **`inline`**, giống takumi và CSS. Container nào có kích thước, hoặc cần xếp con
  theo hàng/cột, phải đặt rõ `display: "flex"` / `"block"` / `"grid"`.
  Xem [Xử lý sự cố](troubleshooting.md#khối-chứa-bị-co-về-chiều-cao-0).

Điểm vào Node của `bm-engine` đọc ba biến môi trường: `BM_ENGINE_BACKEND=wasm|native` (xem
[Cài đặt](#native-trên-nodejs-webassembly-ở-mọi-nơi-khác)), `BM_PROFILE=core|standard|full` chọn một trong các
binary wasm đóng gói sẵn và `BM_WASM=/path/to/file.wasm` nạp một bản build tùy biến (cả hai đều kéo theo wasm). Trong mã ứng dụng, nên
dùng các subpath tường minh (`bm-engine/core`, ...).

### CommonJS

bm-engine được phát hành dưới dạng ES module. Vì các điểm vào Node không dùng top-level `await`, những
phiên bản Node hỗ trợ `require(esm)` (22.12+, 20.19+) có thể nạp chúng từ CommonJS:

```js
const { Renderer } = require("bm-engine");
```

Điều này đã được kiểm chứng trên Node 26.13. Với Node cũ hơn, dùng `const { Renderer } = await import("bm-engine")`.

## Trình duyệt không dùng bundler

Phục vụ thư mục package qua HTTP và import điểm vào theo profile bằng URL. `init()` không đối số sẽ tải
binary nằm cạnh module điểm vào:

```html
<img id="out" />
<script type="module">
  import { init, Renderer } from "/node_modules/bm-engine/js/full.mjs"; // hoặc core.mjs / standard.mjs

  await init(); // tải ./bm_engine.wasm tương đối với full.mjs
  const renderer = new Renderer();
  const font = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
  renderer.registerFont({ name: "Inter", data: font });

  const png = await renderer.render(
    { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#7c3aed" },
      children: [{ type: "text", text: "Hi", style: { fontFamily: "Inter", fontSize: 48, color: "white" } }] },
    { width: 300, height: 100 },
  );
  document.getElementById("out").src = URL.createObjectURL(new Blob([png], { type: "image/png" }));
</script>
```

Với điểm vào chung (`js/index.mjs`), bạn truyền binary một cách tường minh:
`await init(fetch("/node_modules/bm-engine/js/bm_engine.wasm"))`. `init` nhận chuỗi URL, `URL`,
`Request`, `Response`, `Promise<Response>`, bytes hoặc một `WebAssembly.Module` đã biên dịch.

- Phục vụ file `.wasm` với content type `application/wasm` để được biên dịch theo luồng (streaming); với
  content type khác, `init` chuyển sang `arrayBuffer()` + `WebAssembly.instantiate`, cách này vẫn chạy.
- Binary **không có import nào** (không WASI, không glue wasm-bindgen). Runtime cần WebAssembly có
  SIMD128 và bulk memory (mọi engine trình duyệt hiện nay đều có).
- Những gì đã kiểm thử: đường `init(fetch(url))` đã được chạy trong Node với một HTTP server cục bộ phục
  vụ package; bài test trình duyệt của repository (`bench/browser`, Edge 157 headless) nạp cùng wrapper
  và binary, kiểm tra đầu ra raw trùng từng byte với Node (12/12 ca ở lần chạy gần nhất, xem
  [Benchmark](benchmark.md#trình-duyệt)).
  Bài test package còn nạp các trang build bằng Vite trong Edge 157 headless (render ra PNG, không có lỗi
  console). Nạp thẳng từ CDN (`https://cdn.jsdelivr.net/npm/bm-engine@0.1.0/js/core.mjs`, rồi
  `await init()`) hẳn sẽ chạy theo cùng cách khi package được phát hành; trước đó thì chưa kiểm thử.

## Bundler

Import một điểm vào theo profile và gọi `init()` không đối số. Các điểm vào này định vị binary bằng
`new URL("./bm_engine.wasm", import.meta.url)`, một mẫu mà Vite, webpack 5, Rollup và Parcel nhận ra và
xuất thành asset:

```js
import { init, Renderer } from "bm-engine/full"; // hoặc bm-engine/standard, bm-engine/core

await init();
const renderer = new Renderer();
```

Nếu bundler của bạn không xử lý mẫu đó, hãy tự import URL của binary rồi truyền vào:

```js
import { init, Renderer } from "bm-engine/full";
import wasmUrl from "bm-engine/full.wasm?url"; // Vite

await init(wasmUrl);
```

| Bundler | Ghi chú | Đã kiểm thử |
|:--|:--|:--|
| Vite | `await init()` xuất file `.wasm` thành asset; import `?url` cũng được; không cần cấu hình thêm | có: Vite 8.3.8, cả build lẫn dev server, các trang chạy trong Edge 157 headless |
| webpack 5 | `new URL(..., import.meta.url)` mặc định được xuất thành asset module | không |
| Rollup | cần một plugin asset xử lý `new URL(..., import.meta.url)` (ví dụ `@web/rollup-plugin-import-meta-assets`), hoặc tự truyền URL | không |
| esbuild | bundle được (điều kiện browser và `workerd`) nhưng không chép asset của `new URL()`: hãy chép file `.wasm` cạnh bundle, hoặc dùng `--loader:.wasm=file` rồi truyền URL đã import cho `init` | chỉ bước bundle (esbuild 0.28) |

**Bundle một chương trình Node.js** (esbuild `--platform=node`, Rollup, webpack với `target: "node"`). Cách
đơn giản nhất là để package nằm ngoài bundle: `esbuild app.mjs --bundle --platform=node
--external:bm-engine`, rồi mang theo `node_modules`. Nếu vẫn bundle, điểm vào Node của `bm-engine` vẫn chạy
miễn là `node_modules/bm-engine` (và platform package) tồn tại lúc chạy: nó tìm file wasm ngay cạnh nó, sau
đó qua package resolution, sau đó trong `<cwd>/node_modules/bm-engine/js/`, và require platform package lúc
chạy (không cần `--loader:.node`: file `.node` không bao giờ nằm trong bundle). Đã kiểm thử với esbuild
0.28: bundle ESM và CommonJS chạy native; bundle CommonJS chép sang một thư mục không có `node_modules` lỗi
ngay khi import với `bm-engine: cannot find bm_engine.wasm (...). This happens when a bundler moved
bm-engine's Node.js entry away from its package: keep the package external ...`, và chạy được với
`BM_WASM=/path/to/bm_engine.wasm`.

**Đừng** bật cơ chế tích hợp WebAssembly-ESM của bundler cho các file này (`experiments.asyncWebAssembly`,
`vite-plugin-wasm`): bm-engine tự instantiate module và chờ nhận một URL, bytes hoặc một
`WebAssembly.Module`.

**Next.js.** Trong Route Handler chạy trên runtime Node.js, import `bm-engine` và đọc font bằng `fs` như ví
dụ Node. Với Next.js 16.4.6 (builder Turbopack và webpack), cách này chạy mà không cần cấu hình gì khi dùng
`next start`, ở dạng native nếu platform package đã được cài. Với output tự chứa (`output: "standalone"`,
Vercel), thêm `serverExternalPackages: ["bm-engine"]` và
`outputFileTracingIncludes: { "/*": ["./node_modules/bm-engine-*/**"] }` để các file wasm và platform package
được chép theo; thiếu chúng, bản build webpack lỗi lúc chạy và bản build Turbopack lùi về wasm. Trên Edge
runtime, dùng `import wasm from "bm-engine/core.wasm?module"` và `initSync(wasm)` (từ `bm-engine/core`).
bm-engine không có helper `ImageResponse`; hãy trả về
`new Response(png, { headers: { "content-type": "image/png" } })`. Xem trang [Next.js](./frameworks/nextjs.md)
để biết cấu hình đầy đủ và chính xác những gì đã được kiểm chứng.

Tình trạng kiểm chứng của mục này: các dòng Vite và esbuild đã được chạy trong bài test package
(`npm run test:pack`: `npm pack`, cài tarball, build, chạy trong Edge headless); webpack và Rollup
chưa được kiểm thử; Next.js có [trang riêng](./frameworks/nextjs.md).

## Edge runtime, Deno, Bun

**Cloudflare Workers / workerd** biên dịch các import `.wasm` từ trước và đưa cho bạn một
`WebAssembly.Module` (ở đó không được phép biên dịch từ bytes lúc chạy). Import binary rồi truyền cho
`init` hoặc `initSync`:

```js
import { initSync, Renderer } from "bm-engine/full";
import wasm from "bm-engine/full.wasm"; // a WebAssembly.Module under wrangler

initSync(wasm);
let renderer; // reuse one renderer per isolate

export default {
  async fetch() {
    renderer ??= new Renderer(); // + registerFont(...) with font bytes from an asset / KV / fetch
    const png = renderer.renderSync({ type: "container", style: { width: "100%", height: "100%", backgroundColor: "#7c3aed" } },
                                    { width: 1200, height: 630 });
    return new Response(png, { headers: { "content-type": "image/png" } });
  },
};
```

Những gì đã kiểm thử: `initSync(new WebAssembly.Module(bytes))` đã chạy trong Node, và bài test package
resolve các điểm vào với `node --conditions=workerd` rồi khởi tạo chúng từ một `WebAssembly.Module`;
đoạn mã trên **chưa** được chạy dưới wrangler / workerd. Kích thước nén của từng profile (gzip -9: core
200 KiB, standard 463.5 KiB, full 558.2 KiB) là con số tính vào giới hạn kích thước script Workers theo gói
của bạn. Add-on WOFF dùng tương tự: `import woff from "bm-engine/woff.wasm"; await loadWoff(woff)`.

- **Bun**: điều kiện `node` được áp dụng, nên `import { Renderer } from "bm-engine"` thử addon native và
  nếu không có thì nạp binary wasm bằng `node:fs`. Chưa kiểm thử.
- **Deno**: `import { Renderer } from "npm:bm-engine"` dùng cùng điểm vào Node. Chưa kiểm thử.

## Chọn profile

| Profile | wasm thô / brotli | Chọn khi |
|:--|:--|:--|
| `core` | 487.0 / 194.3 KiB | Đầu vào là cây node với `style` inline, font TTF tĩnh và ảnh PNG/JPEG (ảnh OG điển hình). |
| `standard` | 933.9 / 397.7 KiB | Bạn cần stylesheet (`css`), Tailwind (`tw`), đầu vào HTML, ảnh SVG, WOFF2, font biến thiên hoặc CFF, hiệu ứng (clip-path, mask, blend mode, backdrop-filter), màu hiện đại, bảng hoặc float. |
| `full` | 1 140.5 / 469.6 KiB | Bạn cần thêm bidi / chữ phức tạp (Ả Rập, Hebrew, Ấn Độ, Thái), emoji màu, CSS animation / `renderAnimation`, `renderSvg`, ảnh vào WebP lossy hoặc ảnh động, hoặc xuất ICO. |

Chi tiết, kể cả việc profile nhỏ xử lý ra sao với đầu vào nó không hỗ trợ, nằm ở
[Profile và kích thước](profiles-and-size.md). Lúc chạy, `features` cho biết binary đang nạp có gì:

```js
import { features } from "bm-engine/standard";
features.css;         // true
features.complexText; // false (full only)
```

## Font

bm-engine không bao giờ đọc font hệ thống và **không kèm font nào**. Hãy đăng ký mọi font bạn dùng, theo
từng `Renderer`:

```js
renderer.registerFont(readFileSync("Inter-Regular.ttf"));                                     // name / weight / style read from the font
renderer.registerFont({ name: "Brand", data: readFileSync("Inter-Bold.ttf"), weight: 700 });  // explicit
renderer.registerFont({ name: "Geist", data: readFileSync("Geist-VF.ttf") });                 // variable font
await renderer.registerFont("https://example.com/font.woff2");                                // URL: fetched, returns a Promise
```

`registerFont` trả về `RegisteredFamily[]` giống takumi:
`[{ name, faces: [{ weight, style, width, index }], weight, style }]`. Đăng ký thêm một file dưới tên
family đã có sẽ bổ sung face vào family đó. Xem [Tham chiếu API](api.md#registerfont).

| Định dạng | core | standard | full |
|:--|:-:|:-:|:-:|
| TrueType `.ttf`, bộ sưu tập `.ttc` (mọi face) | có | có | có |
| OpenType với outline CFF / CFF2 (`.otf`) | không (`unsupported font format`) | có | có |
| WOFF / WOFF2 | với [add-on WOFF](#woff-trên-core) | có | có |
| Font biến thiên | đăng ký được, chỉ vẽ ở instance mặc định | có | có |
| Glyph màu, font emoji: COLR v0/v1 / bitmap CBDT, sbix | không màu / không vẽ | không màu / có | có |

Trên `standard` và `full`, font biến thiên đi theo `font-weight` (`wght`), `font-stretch` (`wdth`),
`font-optical-sizing` (`opsz`) và `font-variation-settings`.

**Chọn face và font dự phòng.** Trong một family, face gần nhất được chọn theo thuật toán so khớp font
của CSS (độ rộng, rồi kiểu, rồi độ đậm); face đậm / nghiêng bị thiếu sẽ được giả lập. Phần tử không đặt
`font-family` sẽ dùng tùy chọn render `fontFamilies` (chồng font gốc) nếu có. Ký tự không tìm thấy trong
các family của phần tử sẽ được tìm tiếp trong **mọi family đã đăng ký, theo thứ tự đăng ký**. Ký tự mà
không font nào chứa sẽ được vẽ bằng glyph `.notdef` của font (thường là một ô rỗng). Tên chung chung
(`sans-serif`, ...) không được ánh xạ tới font nào; chữ dùng chúng sẽ rơi thẳng xuống chuỗi font dự
phòng.

**Emoji.** Emoji màu cần profile `full` *và* một font emoji màu đã đăng ký (ví dụ Noto Color Emoji). Vì
cơ chế dự phòng duyệt qua mọi family đã đăng ký, chỉ cần đăng ký font emoji là đủ.

**Tiếng Việt và các chữ Latin có dấu khác.** Văn bản dựng sẵn (NFC) hiển thị đúng trên mọi profile. Văn
bản tổ hợp (NFD) phụ thuộc vào khả năng định vị dấu của font; chỉ `full` chuẩn hoá văn bản. Để an toàn,
hãy gọi `text.normalize("NFC")` với dữ liệu người dùng nhập. Xem [Xử lý sự cố](troubleshooting.md#tiếng-việt).

### WOFF trên core

Binary `core` không có bộ giải mã WOFF/WOFF2. Một add-on riêng 84 KiB (`bm-engine/woff`) chuyển
WOFF/WOFF2 sang TTF/OTF trước khi đăng ký; kết quả trùng từng byte với bộ giải mã tích hợp:

```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine/core";
import { loadWoff } from "bm-engine/woff";

await loadWoff(); // Node: reads bm_woff.wasm from the package; bundlers: emitted as an asset
const renderer = new Renderer();
renderer.registerFont({ name: "Geist", data: readFileSync("Geist.woff2") }); // accepted now
```

Trên Workers hãy truyền module: `import woff from "bm-engine/woff.wasm"; await loadWoff(woff)`. Việc chuyển
đổi không thêm khả năng đọc CFF: một WOFF2 chứa outline CFF vẫn cần `standard` hoặc `full`.

## Ảnh

`src` của node `image`, và `url(...)` trong CSS `backgroundImage` / `maskImage`, có thể là:

| `src` | Ví dụ |
|:--|:--|
| một khoá của tùy chọn render `images` | `src: "https://example.com/logo.png"` + `images: [{ src: "https://example.com/logo.png", data: bytes }]` |
| URL `data:` (base64 hoặc mã hoá phần trăm) | `"data:image/png;base64,iVBOR..."` |
| bytes | `src: new Uint8Array(bytes)` hoặc một `ArrayBuffer` |
| điểm ảnh thô | `src: { width, height, data, premultiplied? }`: RGBA8, `data.length === width * height * 4` |
| mã SVG inline | `src: '<svg xmlns="http://www.w3.org/2000/svg" ...>...</svg>'` (standard / full) |

```js
const logo = readFileSync("logo.png");
const png = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 16, padding: 16, width: "100%", height: "100%" },
    children: [
      { type: "image", src: "https://example.com/logo.png", width: 64, height: 64 },
      { type: "image", src: new Uint8Array(logo), width: 64, height: 64 },
      { type: "container", style: { width: 64, height: 64, backgroundImage: "url(logo)", backgroundSize: "cover", borderRadius: 32 } },
    ],
  },
  {
    width: 280, height: 96,
    images: [
      { src: "https://example.com/logo.png", data: logo },
      { src: "logo", data: logo },
    ],
  },
);
```

- **Không có gì được tải về.** URL chỉ là khoá để tra trong `images`; khoá không tồn tại thì không vẽ gì
  và không ném lỗi, giống `render` của takumi khi không qua `prepare`. Bạn tự tải bytes.
- **`Buffer` của Node đặt trực tiếp vào `src`:** dùng được luôn; không còn cần bọc bằng
  `new Uint8Array(buffer)`. Buffer trong `images[].data` và `registerFont` cũng dùng bình thường.
- `images[].data` có thể là hàm hoặc promise (nạp lười) khi dùng các method async (`render`,
  `prepare`, ...); các method sync sẽ ném `lazy images[].data() needs the async API`.
- Chỉ những ảnh mà nguồn thực sự tham chiếu tới mới được chép vào bộ nhớ wasm.
- `width` / `height` trên node ảnh là gợi ý trình bày (ưu tiên thấp nhất, giống thuộc tính HTML);
  `width` / `height` của CSS sẽ thắng. Nếu chỉ có một trong hai, chiều còn lại theo tỉ lệ khung hình.
  Nếu không có cả hai, kích thước gốc của ảnh (× `devicePixelRatio`) được dùng.

| Ảnh đầu vào | core | standard | full |
|:--|:-:|:-:|:-:|
| PNG, JPEG | có | có | có |
| SVG (mã `<svg>`, `data:image/svg+xml`, `url()`) | không (không vẽ gì) | có | có |
| WebP lossless, GIF (khung đầu tiên) | không (không vẽ gì) | có | có |
| WebP lossy (VP8), GIF / APNG / WebP động | không | không có WebP lossy | có |

## Định dạng đầu ra

| `format` | Đầu ra | Profile |
|:--|:--|:--|
| `"png"` (mặc định) | PNG; tự chọn indexed / RGB / RGBA | tất cả |
| `"jpeg"` (bí danh `"jpg"`) | JPEG baseline, `quality` 1–100 (mặc định 75); điểm ảnh trong suốt thành màu đen | tất cả |
| `"webp"` | WebP **lossless** (bỏ qua `quality` / `lossless`, giống bản wasm của takumi) | tất cả |
| `"raw"` | `width × height × 4` byte, RGBA8 thẳng (không premultiplied), theo từng hàng | tất cả |
| `"ico"` | ICO với một mục PNG; mỗi cạnh 1–256 px | full |
| `renderSvg()` | chuỗi tài liệu SVG | full |
| `renderAnimation()` | WebP động (lossless, mặc định), APNG hoặc GIF | full |

`renderAsDataUrl` trả về `data:image/...;base64,...` cho `png`, `jpeg`, `webp` và `ico` (không cho `raw`).
Đọc tiếp [Tham chiếu API](api.md).


## Xem thêm

Các trang hướng dẫn đi sâu vào từng chủ đề, kèm ví dụ chạy được và ảnh kết quả:
[Khái niệm](concepts.md) · [Style và layout](styles.md) · [HTML và Tailwind](html-and-tailwind.md) ·
[Font](fonts.md) · [Typography](typography.md) · [Ảnh](images.md) · [Bảng và float](tables.md) ·
[Hiệu ứng](effects.md) · [Định dạng đầu ra](formats.md) · [Animation](animation.md) · [measure()](measure.md) ·
[Biểu đồ](charts.md) · [Mẫu](templates.md) · [Hiệu năng](performance.md)
