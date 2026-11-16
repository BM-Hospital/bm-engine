# Định dạng đầu ra

[English](../../en/image/formats.md) · [Tiếng Việt](formats.md)

`render()` dựng layout một lần rồi chuyển điểm ảnh cho bộ mã hoá; tuỳ chọn `format` quyết định dùng bộ
nào. Trang này đi qua mọi đầu ra mà bm-render 0.1.0 tạo được — PNG, JPEG, WebP, RGBA thô, ICO, data URL,
tài liệu SVG và (ở trang riêng) ảnh động — mỗi định dạng xử lý độ trong suốt và `quality` ra sao,
`devicePixelRatio` và kích thước canvas tác động lẫn nhau thế nào, profile nào có bộ mã hoá nào, và
benchmark nói gì về tốc độ và dung lượng file. Tài liệu PDF có các trang riêng, bắt đầu từ [Đầu ra PDF](../pdf/index.md). Mọi đoạn mã dưới đây đều nằm trong
`docs/examples/formats.mjs`, và ảnh bên dưới mỗi đoạn là đầu ra thật của nó.

## Tổng quan

| `format` | Alpha | `quality` | Profile | Ghi chú |
|:--|:-:|:-:|:--|:--|
| `"png"` (mặc định) | có | bỏ qua | tất cả | lossless; tự chọn palette / RGB / RGBA |
| `"jpeg"` (bí danh `"jpg"`) | không — bị bỏ, vùng trong suốt thành **đen** | 1–100, mặc định 75 | tất cả | JPEG baseline; hãy cho node gốc một nền đặc |
| `"webp"` | có | bỏ qua | tất cả | luôn **lossless**; `lossless` cũng bị bỏ qua |
| `"raw"` | có | bỏ qua | tất cả | `width × height × 4` byte RGBA8 dạng straight (không premultiply) |
| `"ico"` | có | bỏ qua | `full` | một ảnh PNG trong container ICO, mỗi cạnh 1–256 px |
| `renderSvg()` | có | — | `full` | một chuỗi tài liệu SVG |
| `renderAnimation()` | có | — | `full` | WebP động (mặc định), APNG hoặc GIF; xem [Animation](./animation.md) |

Mọi giá trị `format` khác đều ném lỗi `bm-render: unsupported format: <x>` (ví dụ `"gif"` cho ảnh tĩnh).

Mọi ví dụ trên trang này dùng chung phần khởi tạo và tấm card dưới đây. Để ý các góc bo tròn trên canvas
trong suốt: chúng cho thấy mỗi định dạng làm gì với kênh alpha.

<!-- @example formats#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render"; // Node: the full profile

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

// A card with rounded corners on a transparent canvas: good for showing what each format does with alpha.
const card = {
  type: "container",
  style: {
    display: "flex", flexDirection: "column", justifyContent: "center", gap: 6,
    width: "100%", height: "100%", padding: 28, borderRadius: 28, fontFamily: "Inter",
    backgroundImage: "linear-gradient(135deg, #f97316, #db2777 55%, #7c3aed)",
  },
  children: [
    { type: "text", text: "bm-render", style: { fontSize: 40, fontWeight: 700, color: "white" } },
    { type: "text", text: "PNG · JPEG · WebP · SVG", style: { fontSize: 20, color: "rgba(255,255,255,0.85)" } },
  ],
};
```

## PNG

PNG là mặc định và là lựa chọn an toàn: lossless, giữ trong suốt và trình xem nào cũng đọc được.

<!-- @example formats#png -->
```js
const png = renderer.renderSync(card, { width: 400, height: 200 }); // format defaults to "png"
```

![Card xuất ra PNG](/img/guide/formats-png.png)

PNG nén không mất dữ liệu. Dung lượng file phụ thuộc nội dung ảnh.

## So sánh dung lượng

Cùng một card, mã hoá theo ba cách:

<!-- @example formats#compare -->
```js
for (const format of ["png", "jpeg", "webp"]) {
  const bytes = renderer.renderSync(card, { width: 400, height: 200, format });
  console.log(format, bytes.length, "bytes");
}
```

Kết quả ví dụ này in ra (400 × 200, gradient + chữ; dung lượng chỉ đúng cho ảnh này):

| Định dạng | Byte |
|:--|--:|
| PNG | 12 145 |
| JPEG (quality 75) | 9 681 |
| WebP (lossless) | 13 882 |

Với gradient và ảnh chụp, JPEG thắng; với giao diện phẳng (màu đặc, chữ), PNG và WebP lossless thường nhỏ
hơn JPEG và không bị nhiễu nén. Benchmark giai đoạn 1 đã đo ba ca đại diện 1200 × 630 (thời gian = render
+ mã hoá, median; số liệu lấy từ [docs/BENCHMARK.md](../../BENCHMARK.md)):

| Ca | PNG | JPEG q75 | WebP lossless |
|:--|--:|--:|--:|
| card UI phẳng | 7.13 ms / 13 381 B | 17.63 ms / 47 298 B | 8.99 ms / 11 134 B |
| gradient | 14.50 ms / 32 991 B | 19.28 ms / 53 465 B | 11.57 ms / 29 580 B |
| nền ảnh chụp | 47.60 ms / 523 396 B | 17.88 ms / 56 442 B | 45.94 ms / 414 512 B |

Ca WebP ảnh chụp đã được tối ưu sau đó (45.9 → 19.9 ms, 414 → 376 KB, xem
[Benchmark](../benchmark.md)); các số còn lại chưa được đo lại theo từng định dạng. Nhìn chung, lượt chạy
cuối của 0.1.0 render một PNG trong 1.33 ms và một buffer raw trong 0.64 ms (trung bình nhân trên 250
fixture, máy Intel i3-10100).

## JPEG và `quality`

`quality` chỉ có tác dụng với JPEG. Giá trị bị kẹp trong khoảng 1–100, mặc định 75.

<!-- @example formats#jpeg-quality -->
```js
const low = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 15 });
const high = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 90 });
console.log("quality 15:", low.length, "bytes; quality 90:", high.length, "bytes");
```

Ví dụ này in ra `quality 15: 3525 bytes; quality 90: 15693 bytes` (mặc định 75 cho 9 681 byte).

| quality 15 | quality 90 |
|:-:|:-:|
| ![JPEG quality 15](/img/guide/formats-jpeg-q15.jpg) | ![JPEG quality 90](/img/guide/formats-jpeg-q90.jpg) |

### Độ trong suốt trong JPEG

Canvas khởi đầu trong suốt, còn JPEG không có kênh alpha, nên mọi điểm ảnh trong suốt được ghi thành
**màu đen** — ở đây là phần nằm ngoài các góc bo tròn. Hãy vẽ một nền đục phía sau nội dung khi xuất JPEG:

<!-- @example formats#jpeg-opaque -->
```js
// JPEG has no alpha channel: transparent pixels (the rounded corners) come out black.
const cornersBlack = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 90 });

// Paint an opaque background behind the card instead:
const onWhite = renderer.renderSync(
  { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "white" }, children: [card] },
  { width: 400, height: 200, format: "jpeg", quality: 90 },
);
```

| góc trong suốt → đen | nền đục |
|:-:|:-:|
| ![JPEG có góc đen](/img/guide/formats-jpeg-black-corners.jpg) | ![JPEG trên nền trắng](/img/guide/formats-jpeg-on-white.jpg) |

::: tip
Bộ mã hoá JPEG chỉ đơn giản bỏ kênh alpha, không trộn với màu nào, và không có tuỳ chọn màu nền. Điểm ảnh trong suốt hoàn toàn thành
màu đen, còn điểm ảnh bán trong suốt giữ nguyên màu với cường độ đầy đủ: canvas tô `rgba(255, 0, 0, 0.5)`
ra màu đỏ đặc, và một bóng đổ mềm trên canvas trong suốt biến thành một khối cứng màu của bóng. Luôn đặt
một màu đặc cho node gốc khi xuất JPEG.
:::

## WebP

Đầu ra WebP **luôn lossless**: `quality` và `lossless: false` được
chấp nhận nhưng bị bỏ qua. Kênh alpha được giữ.

<!-- @example formats#webp -->
```js
const webp = renderer.renderSync(card, { width: 400, height: 200, format: "webp", quality: 10 });
const webpDefault = renderer.renderSync(card, { width: 400, height: 200, format: "webp" });
console.log(webp.length === webpDefault.length); // true: WebP output is always lossless, quality is ignored
```

![WebP lossless](/img/guide/formats-webp.webp)

Chọn WebP lossless khi cần trong suốt và file nhỏ hơn PNG với nội dung phẳng; chọn JPEG khi cần nén có
mất dữ liệu cho nội dung kiểu ảnh chụp. Việc *giải mã* WebP lossy có trên `full` (xem [Ảnh](./images.md)),
còn *xuất* WebP lossy thì không profile nào có.

## Điểm ảnh thô (raw)

`format: "raw"` bỏ qua bước mã hoá và trả về canvas dưới dạng RGBA8 straight, từng hàng từ trên xuống. Dùng
nó để hậu xử lý điểm ảnh, so sánh ảnh, đưa vào bộ mã hoá video hoặc vẽ lên `<canvas>` (trong trình duyệt:
`new ImageData(new Uint8ClampedArray(raw.buffer), width, height)`).

<!-- @example formats#raw -->
```js
const width = 400, height = 200;
const raw = renderer.renderSync(card, { width, height, format: "raw" });
console.log(raw.length === width * height * 4); // true: straight (non-premultiplied) RGBA8, row by row

const pixel = (x, y) => Array.from(raw.subarray((y * width + x) * 4, (y * width + x) * 4 + 4));
console.log(pixel(0, 0));     // [0, 0, 0, 0]: the corner outside the border radius is transparent
console.log(pixel(200, 100)); // an opaque pixel of the gradient
```

Điểm ảnh đục được in ra là `[222, 46, 110, 255]`. Raw cũng là đường nhanh nhất vì bỏ qua bộ mã hoá
(0.64 ms so với 1.33 ms trung bình nhân trong benchmark).

Buffer raw có thể đưa ngược vào bm-render làm nguồn ảnh, rất tiện để ghép thumbnail hay dải khung hình mà
không cần thêm thư viện xử lý ảnh:

<!-- @example formats#raw-roundtrip -->
```js
// Raw pixels can be fed back as an image source: { width, height, data }.
const thumbnails = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 12, padding: 12, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: [1, 2, 3].map(() => ({ type: "image", src: { width, height, data: raw }, style: { width: 120, height: 60 } })),
  },
  { width: 420, height: 84 },
);
```

![Ba thumbnail ghép từ một buffer raw](/img/guide/formats-raw-roundtrip.png)

## Data URL

`renderAsDataUrl()` / `renderAsDataUrlSync()` nhận cùng tham số với `render()` và trả về
`data:<mime>;base64,...` cho `png`, `jpeg` (cả dạng `"jpg"`), `webp` và `ico`.

<!-- @example formats#dataurl -->
```js
const url = renderer.renderAsDataUrlSync(card, { width: 400, height: 200, format: "webp" });
console.log(url.slice(0, 23)); // "data:image/webp;base64,"
// in a browser: img.src = url
```

`format: "raw"` ném lỗi `bm-render: renderAsDataUrl needs an encoded format`. Data URL lớn hơn khoảng một
phần ba so với số byte nó mã hoá; với phản hồi HTTP, hãy gửi thẳng byte kèm `content-type` đúng.

## ICO (favicon)

`format: "ico"` ghi một file ICO chứa một ảnh PNG. Cần profile `full` và canvas mỗi cạnh từ 1 đến 256 điểm
ảnh; lớn hơn sẽ ném lỗi `bm-render: ICO images are 1 to 256 pixels on a side, not 300`.

<!-- @example formats#ico -->
```js
const favicon = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
             borderRadius: 12, backgroundColor: "#7c3aed" },
    children: [{ type: "text", text: "b", style: { fontFamily: "Inter", fontWeight: 700, fontSize: 44, color: "white" } }],
  },
  { width: 64, height: 64, format: "ico" }, // full profile only; 1-256 px per side
);
```

File ICO của ví dụ này nặng 553 byte và bắt đầu bằng chữ ký ICO `[0, 0, 1, 0]`. Cùng node đó render ra PNG:

![Favicon dạng PNG](/img/guide/formats-favicon.png)

## Tài liệu SVG

`renderSvg()` / `renderSvgSync()` (profile full) chạy cùng một layout nhưng xuất tài liệu SVG thay vì
bitmap: hộp thành `<rect>` / `<path>`, gradient thành `<linearGradient>` / `<radialGradient>` (gradient
conic thành các hình quạt), bóng đổ thành `<filter>`, ảnh được nhúng dạng `data:` URL và chữ thành đường
viền glyph (`<use>` các path trong `<defs>`).

<!-- @example formats#svg -->
```js
const svg = renderer.renderSvgSync(card, { width: 400, height: 200 }); // full profile only
console.log(svg.slice(0, 90));
// '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200" viewBox="0 0 400 200">...'
```

![Card dạng tài liệu SVG](/img/guide/formats-card.svg)

SVG của ví dụ này nặng 7 118 byte. Cần biết:

Chữ trong SVG được xuất thành đường nét. Hãy kiểm tra file bằng đúng trình xem mà ứng dụng sử dụng.

## Device pixel ratio

`width` và `height` luôn là kích thước ảnh đầu ra tính bằng điểm ảnh. `devicePixelRatio` nhân mọi độ dài
CSS (px, cỡ chữ, kích thước gốc của ảnh) nhưng **không** đổi canvas. Để render thiết kế 400 × 200 ở mức 2×,
hãy nhân đôi canvas *và* đặt tỉ lệ:

<!-- @example formats#dpr -->
```js
// The same 400 x 200 CSS layout, rendered with twice as many pixels:
const retina = renderer.renderSync(card, { width: 800, height: 400, devicePixelRatio: 2 });

// Without the larger canvas, devicePixelRatio: 2 leaves only 200 x 100 CSS px of room:
const cramped = renderer.renderSync(card, { width: 400, height: 200, devicePixelRatio: 2 });
```

`retina` (800 × 400, cùng layout với độ phân giải gấp đôi):

![Card render với devicePixelRatio 2](/img/guide/formats-dpr2.png)

`cramped` (canvas 400 × 200 với tỉ lệ 2, nên layout chỉ còn 200 × 100 px CSS và chữ không còn vừa):

![Render chật: tỉ lệ 2 mà không tăng canvas](/img/guide/formats-dpr2-cramped.png)

`%`, `vw` và `vh` tính theo canvas, nên `width: "100%"` không cần sửa gì. Giá trị ngoài khoảng (0, 64) bị
bỏ qua. Hiển thị ảnh 2× ở một nửa kích thước điểm ảnh (`<img width="400">`).

## Để nội dung quyết định kích thước

Khi không có `width` và/hoặc `height`, node gốc được layout theo kích thước max-content trên trục đó và
canvas lấy đúng kích thước ấy:

<!-- @example formats#auto-size -->
```js
// Without width / height the canvas takes the size of the laid-out root.
const badge = renderer.renderSync({
  type: "container",
  style: { display: "flex", padding: "6px 14px", borderRadius: 999, backgroundColor: "#0f172a" },
  children: [{ type: "text", text: "v0.1.0", style: { fontFamily: "Inter", fontSize: 18, color: "#e2e8f0" } }],
});
```

![Badge có kích thước theo nội dung](/img/guide/formats-auto-size.png)

Badge này ra 76 × 33 px. Node gốc không có gì để đo và không có kích thước sẽ ném lỗi
`invalid viewport: content has zero size and no width/height was given`. Canvas bị giới hạn 16 384 px mỗi
cạnh và 40 megapixel (`canvas too large`).

## Đầu ra động

`renderAnimation()` mã hoá các scene thành WebP động (lossless, mặc định), APNG hoặc GIF, còn
`render(..., { timeMs })` render một khung hình của CSS animation. Cả hai cần profile `full` và được trình
bày ở trang [Animation](./animation.md).

## Huỷ render

`signal` nhận một `AbortSignal`. Nó được kiểm tra trước khi bắt đầu render (và trước khi giải quyết các
tuỳ chọn async); signal đã bị abort sẽ ném ra `reason` của nó. Một lần render đã bắt đầu thì không ngắt
được — nó chạy đồng bộ và thường chỉ mất vài mili giây.

<!-- @example formats#abort -->
```js
const controller = new AbortController();
controller.abort(new Error("request closed"));
try {
  await renderer.render(card, { width: 400, height: 200, signal: controller.signal });
} catch (err) {
  console.log(err.message); // "request closed": the signal is checked before rendering starts
}
```

## Bộ mã hoá theo profile

| Đầu ra | core | standard | full |
|:--|:-:|:-:|:-:|
| PNG, JPEG, WebP lossless, raw, data URL | ✓ | ✓ | ✓ |
| ICO | | | ✓ |
| `renderSvg()` | | | ✓ |
| `renderAnimation()` (WebP / APNG / GIF) | | | ✓ |
| PDF (`renderPdf()`, `bm-render/pdf`) | | | không có trong `full`: xem [Đầu ra PDF](../pdf/index.md) |

Trên profile nhỏ hơn, các đầu ra chỉ có ở `full` ném lỗi rõ ràng:

<!-- @example formats#core -->
```js
import * as core from "bm-render/core";

const small = new core.Renderer();
small.renderSync({ type: "container", style: { width: 16, height: 16, backgroundColor: "red" } },
                 { width: 16, height: 16, format: "webp" }); // png / jpeg / webp / raw work on every profile
try {
  small.renderSync({ type: "container" }, { width: 16, height: 16, format: "ico" });
} catch (err) {
  console.log(err.message); // "bm-render: this build has no ICO output support (use the full build)"
}
```

Để kiểm tra kết quả ảnh, so sánh điểm ảnh sau khi giải mã. Hash của file nén không thể hiện đầy đủ mức giống nhau về hình ảnh.
