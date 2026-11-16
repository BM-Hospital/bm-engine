# Bắt đầu nhanh với ảnh

[English](../../en/image/index.md) · [Tiếng Việt](index.md)

Trang này đưa bạn từ một package đã cài tới một ảnh đã render trên Node.js và trong trình duyệt, rồi đi
qua hai thứ mà dự án ảnh nào cũng phải tự cung cấp: font (bm-render **không** kèm sẵn font) và ảnh. Hãy
cài package và chọn điểm vào trước: [Bắt đầu](../getting-started.md) nói về addon native và WebAssembly,
bundler, edge runtime và các profile build. Mọi đoạn mã Node.js trên trang này đều đã được chạy thật với
bm-render 0.1.0 thông qua cơ chế phân giải package.

- [Node.js](#nodejs)
- [Trình duyệt không dùng bundler](#trình-duyệt-không-dùng-bundler)
- [Font](#font)
- [Ảnh](#ảnh)
- [Định dạng đầu ra](#định-dạng-đầu-ra)
- [Xem thêm](#xem-thêm)

## Node.js

Trên Node.js, mọi điểm vào đều sẵn sàng ngay khi import (`bm-render` với addon native hoặc, nếu không có, giống
các điểm vào theo profile: đọc binary wasm từ đĩa và khởi tạo đồng bộ), nên bạn có thể tạo `Renderer` luôn:

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const png = renderer.renderSync(
  {
    type: "container",
    style: {
      display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
      backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)",
    },
    children: [{ type: "text", text: "Hello from bm-render", style: { fontFamily: "Inter", fontSize: 64, color: "white" } }],
  },
  { width: 1200, height: 630 },
);
writeFileSync("og.png", png);
```

Cần lưu ý:

- **Đăng ký font trước khi render chữ.** Nếu chưa có font, chữ sẽ không được vẽ và cũng không báo lỗi.
  Xem [Font](#font).
- `renderSync` trả về `Uint8Array` (PNG nếu bạn không truyền `format`). Method nào cũng có bản async
  tương ứng (`render`, `measure`, ...). Với backend native, các bản async render trên thread pool
  của libuv (một renderer chỉ chạy một lệnh tại một thời điểm: tạo vài renderer để render song song); với
  wasm, việc render luôn đồng bộ và các bản async tồn tại để xử lý những tùy
  chọn cần chờ (`fonts`, `images` nạp lười).
- `display` mặc định là **`inline`**. Container nào có kích thước, hoặc cần xếp con
  theo hàng/cột, phải đặt rõ `display: "flex"` / `"block"` / `"grid"`.
  Xem [Xử lý sự cố](../troubleshooting.md#khối-chứa-bị-co-về-chiều-cao-0).

Điểm vào Node của `bm-render` đọc ba biến môi trường: `BM_RENDER_BACKEND=wasm|native` (xem
[Cài đặt](../getting-started.md#native-trên-nodejs-webassembly-ở-mọi-nơi-khác)), `BM_PROFILE=core|standard|full` chọn một trong các
binary wasm đóng gói sẵn và `BM_WASM=/path/to/file.wasm` nạp một bản build tùy biến (cả hai đều kéo theo wasm). Trong mã ứng dụng, nên
dùng các subpath tường minh (`bm-render/core`, ...).

## Trình duyệt không dùng bundler

Phục vụ thư mục package qua HTTP và import điểm vào theo profile bằng URL. `init()` không đối số sẽ tải
binary nằm cạnh module điểm vào:

```html
<img id="out" />
<script type="module">
  import { init, Renderer } from "/node_modules/bm-render/js/full.mjs"; // hoặc core.mjs / standard.mjs

  await init(); // tải ./bm_render.wasm tương đối với full.mjs
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
`await init(fetch("/node_modules/bm-render/js/bm_render.wasm"))`. `init` nhận chuỗi URL, `URL`,
`Request`, `Response`, `Promise<Response>`, bytes hoặc một `WebAssembly.Module` đã biên dịch.

- Phục vụ file `.wasm` với content type `application/wasm` để được biên dịch theo luồng (streaming); với
  content type khác, `init` chuyển sang `arrayBuffer()` + `WebAssembly.instantiate`, cách này vẫn chạy.
- Binary **không có import nào** (không WASI, không glue wasm-bindgen). Runtime cần WebAssembly có
  SIMD128 và bulk memory (mọi engine trình duyệt hiện nay đều có).
- Những gì đã kiểm thử: đường `init(fetch(url))` đã được chạy trong Node với một HTTP server cục bộ phục
  vụ package; bài test trình duyệt của repository (`bench/browser`, Edge 157 headless) nạp cùng wrapper
  và binary, kiểm tra đầu ra raw trùng từng byte với Node (12/12 ca ở lần chạy gần nhất, xem
  [Benchmark](../benchmark.md)).
  Bài test package còn nạp các trang build bằng Vite trong Edge 157 headless (render ra PNG, không có lỗi
  console). Nạp thẳng từ CDN (`https://cdn.jsdelivr.net/npm/bm-render@0.1.0/js/core.mjs`, rồi
  `await init()`) hẳn sẽ chạy theo cùng cách khi package được phát hành; trước đó thì chưa kiểm thử.

## Font

bm-render không bao giờ đọc font hệ thống và **không kèm font nào**. Hãy đăng ký mọi font bạn dùng, theo
từng `Renderer`:

```js
renderer.registerFont(readFileSync("Inter-Regular.ttf"));                                     // name / weight / style read from the font
renderer.registerFont({ name: "Brand", data: readFileSync("Inter-Bold.ttf"), weight: 700 });  // explicit
renderer.registerFont({ name: "Geist", data: readFileSync("Geist-VF.ttf") });                 // variable font
await renderer.registerFont("https://example.com/font.woff2");                                // URL: fetched, returns a Promise
```

`registerFont` trả về `RegisteredFamily[]`:
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
hãy gọi `text.normalize("NFC")` với dữ liệu người dùng nhập. Xem [Xử lý sự cố](../troubleshooting.md#tiếng-việt).

### WOFF trên core

Binary `core` không có bộ giải mã WOFF/WOFF2. Một add-on riêng 84 KiB (`bm-render/woff`) chuyển
WOFF/WOFF2 sang TTF/OTF trước khi đăng ký; kết quả trùng từng byte với bộ giải mã tích hợp:

```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render/core";
import { loadWoff } from "bm-render/woff";

await loadWoff(); // Node: reads bm_woff.wasm from the package; bundlers: emitted as an asset
const renderer = new Renderer();
renderer.registerFont({ name: "Geist", data: readFileSync("Geist.woff2") }); // accepted now
```

Trên Workers hãy truyền module: `import woff from "bm-render/woff.wasm"; await loadWoff(woff)`. Việc chuyển
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
  và không ném lỗi,  Bạn tự tải bytes.
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
| `"webp"` | WebP **lossless** (bỏ qua `quality` / `lossless`) | tất cả |
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
