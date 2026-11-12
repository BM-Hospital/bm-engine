# Ảnh

[English](../../en/image/images.md) · [Tiếng Việt](images.md)

Cách đưa hình ảnh vào một lần render của bm-engine: image node và `<img>` trong HTML, `background-image`
và mask trong CSS, năm cách trao byte ảnh cho engine (bm-engine không bao giờ tự tải gì từ mạng), mỗi
profile giải mã được định dạng nào, ảnh được tính kích thước và đặt vào khung ra sao, và cache ảnh đã giải
mã làm gì cho bạn. Mọi ví dụ trên trang này là một đoạn của `docs/examples/images.mjs` trong repository,
đã chạy thật với package; hình ngay dưới mỗi đoạn mã là kết quả của chính nó.

- [Chuẩn bị và ảnh thử](#chuẩn-bị-và-ảnh-thử)
- [Byte ảnh đến từ đâu](#byte-ảnh-đến-từ-đâu)
- [Định dạng được hỗ trợ theo profile](#định-dạng-được-hỗ-trợ-theo-profile)
- [Quy tắc kích thước](#quy-tắc-kích-thước)
- [object-fit và object-position](#object-fit-và-object-position)
- [Ảnh nền](#ảnh-nền)
- [Trang trí ảnh](#trang-trí-ảnh)
- [Ảnh SVG](#ảnh-svg)
- [Ảnh trong đầu vào HTML](#ảnh-trong-đầu-vào-html)
- [Ảnh động làm nguồn](#ảnh-động-làm-nguồn)
- [Cache, bộ nhớ và giới hạn](#cache-bộ-nhớ-và-giới-hạn)

## Chuẩn bị và ảnh thử

Các ví dụ dùng chung một renderer (trên Node.js, điểm vào `bm-engine` nạp profile `full`) đã đăng ký
Inter thường và đậm:

<!-- @example images#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

Thay vì kèm file mẫu, các ví dụ tự render một ảnh thử bằng bm-engine rồi đưa byte PNG đó vào lại. Điều
này cũng cho thấy đầu ra của một lần render hoàn toàn dùng được làm đầu vào cho lần sau (hữu ích khi muốn
cache một ảnh con tốn công tạo):

<!-- @example images#photo -->
```js
// A 320 × 200 test picture, rendered by bm-engine itself. Any PNG / JPEG bytes work the same way.
const photo = renderer.renderSync(
  {
    type: "container",
    style: {
      display: "flex", width: "100%", height: "100%", alignItems: "flex-end", justifyContent: "center",
      backgroundImage: "linear-gradient(#38bdf8, #e0f2fe)",
    },
    children: [
      { type: "container", style: { position: "absolute", top: 30, left: 40, width: 60, height: 60, borderRadius: 30, backgroundColor: "#facc15" } },
      { type: "container", style: { width: "100%", height: 70, backgroundColor: "#16a34a" } },
      { type: "text", text: "320 × 200", style: { position: "absolute", top: 80, fontFamily: "Inter", fontWeight: 700, fontSize: 32, color: "#0f172a" } },
    ],
  },
  { width: 320, height: 200 },
);
```

![Ảnh thử 320 × 200](/img/guide/images-photo.png)

## Byte ảnh đến từ đâu

Một image node có dạng `{ type: "image", src, width?, height?, style? }`. `src` có thể là:

| `src` | Ví dụ | Ghi chú |
|:--|:--|:--|
| một khóa của option `images` | `"https://example.com/photo.png"` + `images: [{ src: "https://example.com/photo.png", data: bytes }]` | chuỗi chỉ là khóa tra cứu; viết gì cũng được |
| byte đã mã hóa | `Buffer` của Node, `Uint8Array`, `ArrayBuffer` hoặc `ArrayBufferView` khác | `Buffer` không cần bọc lại |
| URL `data:` | `"data:image/png;base64,iVBOR..."`, `"data:image/svg+xml;utf8,..."` | base64 hoặc percent-encoding |
| pixel thô | `{ width, height, data, premultiplied? }` | RGBA8, `data.length` phải bằng `width × height × 4` |
| mã SVG | `'<svg xmlns="http://www.w3.org/2000/svg" ...>'` | standard / full |

Cả năm cách đặt cạnh nhau:

<!-- @example images#sources -->
```js
const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="96" height="96">
  <circle cx="12" cy="12" r="11" fill="#6366f1"/><path d="M7 12.5l3 3 7-7" fill="none" stroke="white" stroke-width="2.5"/></svg>`;
const dataUrl = "data:image/png;base64," + Buffer.from(photo).toString("base64");
const pixels = new Uint8Array(4 * 4 * 4); // a 4 × 4 checkerboard of raw RGBA pixels
for (let i = 0; i < 16; i++) pixels.set((i + (i >> 2)) % 2 ? [244, 63, 94, 255] : [255, 255, 255, 255], i * 4);

const tile = (label, image) => ({
  type: "container",
  style: { display: "flex", flexDirection: "column", alignItems: "center", gap: 8, fontFamily: "Inter", fontSize: 14 },
  children: [image, { type: "text", text: label }],
});
const box = { width: 96, height: 96, objectFit: "cover", borderRadius: 12 };

const sources = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 20, padding: 20, width: "100%", height: "100%", backgroundColor: "#f8fafc" },
    children: [
      tile("images key", { type: "image", src: "https://example.com/photo.png", style: box }),
      tile("Buffer", { type: "image", src: photo, style: box }),
      tile("data: URL", { type: "image", src: dataUrl, style: box }),
      tile("raw RGBA", { type: "image", src: { width: 4, height: 4, data: pixels }, style: box }),
      tile("SVG markup", { type: "image", src: svg, style: box }),
    ],
  },
  {
    width: 600, height: 150,
    // The URL is only a lookup key: nothing is downloaded.
    images: [{ src: "https://example.com/photo.png", data: photo }],
  },
);
```

![Cùng một ảnh lấy từ khóa images, từ Buffer và từ data URL, một bàn cờ RGBA thô 4 × 4 và một SVG inline](/img/guide/images-sources.png)

Hãy để ý bàn cờ thô 4 × 4: nó được phóng lên 96 × 96 bằng nội suy mượt (bilinear). Muốn phóng to kiểu
pixel-art sắc nét, hãy đặt `imageRendering: "pixelated"` (hoặc `"crisp-edges"`): ảnh khi đó được phóng
theo điểm gần nhất (nearest-neighbour), giống hệt takumi. Cách này dùng được cho image node và ảnh nền,
trên mọi profile:

<!-- @example images#pixelated -->
```js
// image-rendering: pixelated (or crisp-edges) scales with nearest-neighbour sampling instead of
// smooth (bilinear) resampling: on image nodes and on background images, on every profile.
const checker = { width: 4, height: 4, data: pixels };
const pixelated = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 20, padding: 20, width: "100%", height: "100%", backgroundColor: "#f8fafc" },
    children: [
      tile("auto (smooth)", { type: "image", src: checker, style: { width: 96, height: 96 } }),
      tile("pixelated", { type: "image", src: checker, style: { width: 96, height: 96, imageRendering: "pixelated" } }),
      tile("pixelated background", {
        type: "container",
        style: { width: 96, height: 96, backgroundImage: "url(checker)", backgroundSize: "48px 48px", imageRendering: "pixelated" },
      }),
    ],
  },
  { width: 420, height: 170, images: [{ src: "checker", data: renderer.renderSync({ type: "image", src: checker }, { width: 4, height: 4 }) }] },
);
```

![Bàn cờ 4 × 4 được phóng mượt thành hoa văn nhoè, cũng bàn cờ đó với mép pixel sắc nét, và một nền lát bằng các bàn cờ sắc nét](/img/guide/images-pixelated.png)

::: warning bm-engine không truy cập mạng
Một URL trong `src` (hoặc trong `url(...)`) **không bao giờ được tải**, kể cả qua `prepare()` (`prepare`
của takumi có tải; của bm-engine thì không). Hãy tự tải byte và truyền vào `images`. Điều này cũng áp
dụng cho URL trong `@font-face` của stylesheet.
:::

Một hàm nhỏ biến danh sách URL thành mảng `images`:

<!-- @example images#fetch -->
```js
async function loadImages(urls) {
  return Promise.all(urls.map(async (src) => ({ src, data: new Uint8Array(await (await fetch(src)).arrayBuffer()) })));
}
// const images = await loadImages(["https://example.com/logo.png"]);
// renderer.renderSync(node, { width: 1200, height: 630, images });
```

`images[].data` cũng có thể là một hàm hoặc một promise. Các mục *lazy* như vậy được các method async
(`render`, `renderAsDataUrl`, `measure`, `prepare`, ...) resolve; các method sync sẽ throw
`bm-engine: lazy images[].data() needs the async API`:

<!-- @example images#lazy -->
```js
const lazy = await renderer.render(
  { type: "image", src: "avatar", style: { width: 64, height: 64, borderRadius: 32 } },
  { width: 64, height: 64, images: [{ src: "avatar", data: async () => photo }] }, // resolved by the async API
);
// renderer.renderSync(...) with the same options throws "lazy images[].data() needs the async API"
```

`images` có thể là một mảng hoặc một object `{ sources, cache }` (dạng của takumi). `cache` của từng ảnh
và `images.cache` được chấp nhận nhưng bị bỏ qua: ảnh đã giải mã luôn được cache (xem
[Cache](#cache-bộ-nhớ-và-giới-hạn)). Chỉ những mục có `src` thật sự xuất hiện trong source mới được chép
vào bộ nhớ wasm, nên truyền cùng một danh sách chung mọi asset cho mọi lần render là hoàn toàn ổn.

**Ảnh thiếu hoặc không giải mã được không bao giờ throw.** Nó không vẽ gì và có kích thước nội tại 0 × 0,
có thể làm layout của bạn bị co lại. Hãy đặt kích thước tường minh cho image node khi ảnh có thể thiếu:

<!-- @example images#missing -->
```js
const missing = renderer.measureSync(
  { type: "container", style: { display: "flex" }, children: [{ type: "image", src: "not-in-images" }] },
  { width: 100, height: 100 },
);
console.log(missing.children[0].width, missing.children[0].height); // 0 0, and no exception
```

## Định dạng được hỗ trợ theo profile

| Đầu vào | core | standard | full |
|:--|:-:|:-:|:-:|
| PNG, JPEG (baseline và progressive) | ✓ | ✓ | ✓ |
| APNG | khung đầu | khung đầu | chuyển động |
| WebP lossless (VP8L) | — | ✓ | ✓ |
| WebP lossy (VP8) | — | — | ✓ |
| GIF | — | khung đầu | chuyển động |
| WebP động | — | — | chuyển động |
| SVG (mã, `data:image/svg+xml`, nền và mask `url()`) | — | ✓ | ✓ |

"—" nghĩa là ảnh không vẽ gì và đo được 0 × 0, giống hệt ảnh thiếu; không có gì throw. "chuyển động"
nghĩa là khung hình tương ứng với `timeMs` được hiển thị (xem [Ảnh động làm nguồn](#ảnh-động-làm-nguồn)).
Các cột core / standard / full đã được script ví dụ kiểm tra (nó assert kích thước đo được của nguồn PNG,
JPEG, WebP lossless, GIF và SVG trên `bm-engine/core` và `bm-engine/standard`); WebP lossy được kiểm tra
bằng một file VP8 thật (0 × 0 trên standard, 1200 × 630 trên full). Không có bộ giải mã ICO, BMP, TIFF
hay AVIF. `features.svg`, `features.webpGifDecode` và `features.extraCodecs` cho bạn biết lúc chạy binary
đang nạp giải mã được gì.

## Quy tắc kích thước

Ảnh là một *replaced element*: nó có kích thước nội tại (kích thước pixel, hoặc `width` / `height` /
`viewBox` của SVG) và một tỉ lệ khung, và CSS tính kích thước cho nó giống như trình duyệt làm với
`<img>`:

- Không có kích thước nào: dùng kích thước nội tại (nhân với `devicePixelRatio`).
- Chỉ có chiều rộng hoặc chỉ có chiều cao: chiều còn lại theo tỉ lệ khung.
- Các trường `width` / `height` của node là **gợi ý trình bày**, giống thuộc tính HTML: mọi `width` /
  `height` của CSS (`style` inline, stylesheet, `tw`) đều thắng chúng.

<!-- @example images#sizing -->
```js
const sized = renderer.measureSync(
  {
    type: "container",
    style: { display: "flex", alignItems: "flex-start" },
    children: [
      { type: "image", src: photo },                                   // intrinsic: 320 × 200
      { type: "image", src: photo, width: 160 },                       // height follows: 160 × 100
      { type: "image", src: photo, style: { height: 50 } },            // width follows: 80 × 50
      { type: "image", src: photo, width: 999, style: { width: 64 } }, // CSS beats the attribute: 64 × 40
    ],
  },
  { width: 800, height: 300 },
);
console.log(sized.children.map((c) => `${c.width}×${c.height}`).join(" ")); // 320×200 160×100 80×50 64×40
```

`devicePixelRatio` nhân kích thước nội tại giống mọi độ dài CSS khác, nên ảnh 320 × 200 chiếm 640 × 400
pixel đầu ra khi `devicePixelRatio: 2`. Hãy dùng ảnh 2× khi render ở DPR 2 để ảnh vẫn nét:

<!-- @example images#dpr -->
```js
const atDpr2 = renderer.measureSync(
  { type: "container", style: { display: "flex" }, children: [{ type: "image", src: photo }] },
  { width: 800, height: 600, devicePixelRatio: 2 },
);
console.log(atDpr2.children[0].width, atDpr2.children[0].height); // 640 400 (output pixels)
```

::: tip Ảnh trong hàng flex
Kích thước tối thiểu của một flex item là kích thước nội dung: một ảnh 320 px trong một hàng flex rộng
200 px vẫn giữ 320 px và ép các phần tử anh em về chiều rộng 0. Hãy cho ảnh `width` / `height` cố định
(như trên) hoặc `minWidth: 0` để nó co được, và `flexShrink: 0` cho những item không được co.
:::

## object-fit và object-position

Khi cả hai chiều của khung đều cố định, `objectFit` quyết định ảnh lấp khung thế nào. Mặc định là `fill`
(kéo giãn), như trong CSS:

<!-- @example images#object-fit -->
```js
const fits = ["fill", "contain", "cover", "none", "scale-down"];
const objectFit = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 16, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: fits.map((fit) =>
      tile(fit, {
        type: "image", src: photo,
        style: { width: 100, height: 130, objectFit: fit, backgroundColor: "#cbd5e1", border: "2px solid #334155" },
      }),
    ),
  },
  { width: 600, height: 190 },
);
```

![object-fit: fill, contain, cover, none và scale-down trong khung 100 × 130](/img/guide/images-object-fit.png)

`objectPosition` đặt ảnh bên trong khung (mặc định `50% 50%`); nó có tác dụng với `contain`, `cover` và
`none`. Dùng được từ khóa, độ dài và phần trăm:

<!-- @example images#object-position -->
```js
const positions = ["left top", "center", "right bottom", "20% 80%"];
const objectPosition = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 16, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: positions.map((pos) =>
      tile(pos, {
        type: "image", src: photo,
        style: { width: 120, height: 120, objectFit: "none", objectPosition: pos, border: "2px solid #334155" },
      }),
    ),
  },
  { width: 600, height: 180 },
);
```

![object-position: left top, center, right bottom và 20% 80% với object-fit: none](/img/guide/images-object-position.png)

## Ảnh nền

Mọi container đều vẽ được ảnh bằng `backgroundImage: "url(key)"`, trong đó `key` được tra cứu y như `src`
của ảnh (một khóa của `images` hoặc một URL `data:`). Các lớp cách nhau bằng dấu phẩy, lớp đầu tiên nằm
trên cùng, và có thể trộn gradient với ảnh. Các thuộc tính đi kèm quen thuộc đều hoạt động:
`backgroundSize` (`cover`, `contain`, độ dài, phần trăm, `auto`), `backgroundPosition` (cả
`backgroundPositionX` / `Y`), `backgroundRepeat` (`repeat`, `no-repeat`, `repeat-x`, `repeat-y`,
`space`, `round`), `backgroundOrigin` và `backgroundClip`:

<!-- @example images#background -->
```js
const bg = (label, style) => tile(label, {
  type: "container",
  style: { width: 130, height: 100, border: "2px solid #334155", backgroundImage: "url(photo)", backgroundColor: "#cbd5e1", ...style },
});
const backgrounds = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexWrap: "wrap", gap: 16, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: [
      bg("cover", { backgroundSize: "cover", backgroundPosition: "center" }),
      bg("contain", { backgroundSize: "contain", backgroundRepeat: "no-repeat", backgroundPosition: "center" }),
      bg("64px repeat", { backgroundSize: "64px 40px" }),
      bg("64px space", { backgroundSize: "64px 40px", backgroundRepeat: "space" }),
      bg("round", { backgroundSize: "64px 40px", backgroundRepeat: "round" }),
      bg("repeat-x bottom", { backgroundSize: "50px", backgroundRepeat: "repeat-x", backgroundPosition: "left bottom" }),
      bg("gradient over image", { backgroundImage: "linear-gradient(transparent, rgba(15,23,42,.85)), url(photo)", backgroundSize: "cover" }),
      bg("radius + cover", { backgroundSize: "cover", borderRadius: 50, border: "none" }),
    ],
  },
  { width: 640, height: 300, images: [{ src: "photo", data: photo }] },
);
```

![Ảnh nền với cover, contain, ô lặp lại, space, round, repeat-x, lớp gradient phủ lên và border-radius](/img/guide/images-background.png)

Ô "gradient over image" là mẹo kinh điển để chữ dễ đọc trên ảnh: một lớp gradient nằm trên ảnh, trong
cùng danh sách `backgroundImage`. `backgroundAttachment` được chấp nhận và bị bỏ qua (không có cuộn
trang). `maskImage: "url(...)"` nhận ảnh theo cùng cách; xem [Hiệu ứng](./effects.md#mask).

## Trang trí ảnh

Image node là một box bình thường: viền, `borderRadius` (cắt ảnh theo góc bo), bóng đổ, filter, opacity
và transform đều áp dụng được:

<!-- @example images#styling -->
```js
const styling = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 24, padding: 24, alignItems: "center", width: "100%", height: "100%", backgroundColor: "#0f172a" },
    children: [
      { type: "image", src: photo, style: { width: 100, height: 100, objectFit: "cover", borderRadius: "50%", border: "4px solid #f8fafc" } },
      { type: "image", src: photo, style: { width: 120, height: 90, objectFit: "cover", borderRadius: 16, boxShadow: "0 8px 24px rgba(0,0,0,.6)" } },
      { type: "image", src: photo, style: { width: 120, height: 90, objectFit: "cover", filter: "grayscale(1) contrast(1.2)" } },
      { type: "image", src: photo, style: { width: 120, height: 90, objectFit: "cover", opacity: 0.5, transform: "rotate(-8deg)" } },
    ],
  },
  { width: 600, height: 160 },
);
```

![Avatar tròn có viền, một thẻ có bóng đổ, ảnh đen trắng và ảnh xoay bán trong suốt](/img/guide/images-styling.png)

Tất cả đều chạy trên mọi profile. Muốn cắt ảnh theo hình không phải chữ nhật, dùng `clipPath` hoặc
`maskImage` (standard / full), xem [Hiệu ứng](./effects.md#clip-path).

## Ảnh SVG

Trên `standard` và `full`, SVG được giải mã bằng bộ render SVG riêng của bm-engine và vẽ dạng vector ở
kích thước cuối cùng, nên luôn sắc nét ở mọi tỉ lệ. SVG dùng được làm `src` của ảnh (mã hoặc URL
`data:`), làm một mục của `images`, và trong nền và mask `url()`:

<!-- @example images#svg -->
```js
const logo = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs><linearGradient id="g" x2="1" y2="1"><stop offset="0" stop-color="#f97316"/><stop offset="1" stop-color="#db2777"/></linearGradient></defs>
  <rect width="100" height="100" rx="24" fill="url(#g)"/>
  <path d="M30 70V30h22a12 12 0 0 1 0 24H30" fill="none" stroke="white" stroke-width="10" stroke-linejoin="round"/></svg>`;
const svgOut = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 24, padding: 24, alignItems: "center", width: "100%", height: "100%", backgroundColor: "#fff7ed" },
    children: [
      { type: "image", src: logo, style: { width: 48, height: 48 } }, // vector: sharp at any size
      { type: "image", src: logo, style: { width: 120, height: 120 } },
      { type: "image", src: "data:image/svg+xml;utf8," + encodeURIComponent(logo), style: { width: 80, height: 80 } },
      { type: "container", style: { width: 160, height: 120, borderRadius: 16, backgroundImage: "url(logo.svg)", backgroundSize: "40px 40px" } },
    ],
  },
  { width: 520, height: 170, images: [{ src: "logo.svg", data: new TextEncoder().encode(logo) }] },
);
```

![Logo SVG ở 48 px, 120 px, từ data URL, và cùng SVG đó lát làm nền](/img/guide/images-svg.png)

Được hỗ trợ: các hình cơ bản, path, `use` / `symbol`, gradient, pattern, `clipPath`, `mask`, marker,
`svg` / `image` lồng nhau, phần tử `style` với selector đơn giản, và các filter `feGaussianBlur`,
`feOffset`, `feFlood`, `feColorMatrix`, `feComposite`, `feMerge`, `feBlend`, `feDropShadow`,
`feComponentTransfer`. Không hỗ trợ: `feTurbulence`, `feImage`, `feMorphology`, `feConvolveMatrix`,
`feDisplacementMap`, các filter chiếu sáng, `feTile`, và tham chiếu ra ngoài (SVG không nạp được file
khác).

Phần tử `text` của SVG được vẽ bằng các font đã đăng ký trên renderer, theo một mô hình đơn giản: mỗi
phần tử `text` là một run tại `x` / `y` của nó, tôn trọng `font-family`, `font-size`, `font-weight`,
`text-anchor` và `fill` màu đơn. Chữ tô bằng gradient sẽ không được vẽ, và nội dung chữ của các con
`tspan` / `textPath` được nối vào run của cha (vị trí và màu riêng của chúng bị bỏ qua). Không có font
nào được đăng ký thì chữ không được vẽ.

<!-- @example images#svg-text -->
```js
const badge = `<svg xmlns="http://www.w3.org/2000/svg" width="260" height="60">
  <rect width="260" height="60" rx="30" fill="#0f172a"/>
  <text x="130" y="39" font-family="Inter" font-size="22" font-weight="700" fill="#f8fafc" text-anchor="middle">SVG &lt;text&gt; works</text></svg>`;
const svgText = renderer.renderSync(
  { type: "container", style: { display: "flex", padding: 20, backgroundColor: "#fff7ed" }, children: [{ type: "image", src: badge }] },
  { width: 300, height: 100, images: { sources: [], cache: "none" } }, // the object form of `images` is accepted too
);
```

![Một huy hiệu SVG có nhãn là phần tử text của SVG](/img/guide/images-svg-text.png)

::: tip Biểu đồ và icon
SVG inline là cách dễ nhất để vẽ đường, đường cong và icon mà các box CSS không diễn tả được
(sparkline, biểu đồ đường, logo). Xem [Biểu đồ](./charts.md).
:::

Trên `core`, nguồn SVG không vẽ gì (0 × 0). Nếu chỉ cần vài icon trên `core`, hãy rasterize chúng một lần
(ví dụ dùng `standard` trong bước build) rồi dùng byte PNG.

## Ảnh trong đầu vào HTML

Với source là HTML (standard / full), phần tử `img` hoạt động như image node: `src` được tra trong
`images` hoặc giải mã như URL `data:`, thuộc tính `width` / `height` là gợi ý trình bày, và các phần tử
`svg` inline trong markup được render thành ảnh SVG. Lưu ý trong chữ HTML phải viết `&lt;` để có ký tự
`<`:

<!-- @example images#html-img -->
```js
const html = renderer.renderSync(
  `<div style="display:flex;gap:16px;align-items:center;padding:16px;font-family:Inter;font-size:20px;background:#ecfeff;height:100%">
     <img src="photo" width="120" style="border-radius:12px" />
     <img src="${dataUrl}" style="width:60px;height:60px;object-fit:cover;border-radius:50%" />
     <span>&lt;img&gt; in HTML input</span>
   </div>`,
  { width: 520, height: 110, images: [{ src: "photo", data: photo }] },
);
```

![Hai phần tử img trong đầu vào HTML: một ảnh bo góc và một avatar tròn](/img/guide/images-html-img.png)

## Ảnh động làm nguồn

Trên `full`, GIF động, APNG hoặc WebP động hiển thị khung hình ứng với `timeMs` của lần render (lặp
theo tổng thời lượng của file). Trong `renderAnimation` mỗi khung hình đều tăng thời gian, nên một
sticker động sẽ chuyển động bên trong ảnh động đầu ra. Trên `core`, APNG hiện khung đầu còn GIF không
hiện gì; trên `standard` cả hai hiện khung đầu. Dưới đây một GIF hai khung (tạo bằng
`renderAnimationSync`) được lấy mẫu ở 0 ms và 700 ms:

<!-- @example images#animated -->
```js
// An animated GIF / APNG / WebP source shows the frame that is current at `timeMs` (full profile).
const fill = (color) => ({ type: "container", style: { width: "100%", height: "100%", backgroundColor: color } });
const gif = renderer.renderAnimationSync({
  scenes: [{ node: fill("#ef4444"), durationMs: 500 }, { node: fill("#3b82f6"), durationMs: 500 }],
  width: 40, height: 40, fps: 2, format: "gif",
});
const at = (timeMs) => renderer.renderSync({ type: "image", src: gif }, { width: 40, height: 40, format: "raw", timeMs });
console.log(at(0).slice(0, 3), at(700).slice(0, 3)); // red at 0 ms, blue at 700 ms
```

Xem [Animation](./animation.md) về `timeMs` và `renderAnimation`.

## Cache, bộ nhớ và giới hạn

- **Cache giải mã.** Mỗi renderer cache ảnh đã giải mã theo nội dung byte, nên cùng một logo dùng trong
  mọi lần render (hoặc nhiều lần trong một cây) chỉ được giải mã một lần. Khi cache vượt 96 MiB, nó được
  xóa ở đầu lần render kế tiếp. Ngân sách này cố định: `new Renderer({ cacheMaxBytes })` và `cache` của
  từng ảnh được chấp nhận nhưng bị bỏ qua.
- **Sao chép.** Ở mỗi lần render, byte của từng ảnh được tham chiếu sẽ được chép vào bộ nhớ wasm (chỉ
  những ảnh source có nhắc tới). Ảnh lớn dùng thường xuyên vì vậy tốn một lần chép mỗi lần render, nhưng
  không phải giải mã lại.
- **Giới hạn kích thước.** Một ảnh sau giải mã tối đa 24 megapixel (`96 MiB / 4`); ảnh lớn hơn không
  được vẽ. Hãy thu nhỏ ảnh lớn trước khi render: giải mã một JPEG 12 megapixel chỉ để vẽ ở 400 × 300 là
  chi phí dễ tránh nhất trong các template nhiều ảnh.
- **Số pixel quan trọng hơn dung lượng file.** Chi phí giải mã tăng theo số pixel. Nên gửi ảnh ở cỡ gần
  với cỡ được vẽ (× `devicePixelRatio`).
- **Ảnh chụp ở đầu ra lossless thì nặng.** Ảnh chụp trong đầu ra PNG hay WebP nén kém; với thẻ nhiều ảnh
  chụp hãy dùng `format: "jpeg"` (xem [Định dạng](./formats.md)).
- **Dùng lại một renderer.** Cache nằm trong renderer; tạo renderer mới cho mỗi request là giải mã lại
  tất cả. Xem [Hiệu năng](./performance.md).

Xem thêm: [Hỗ trợ CSS → Ảnh và SVG](./css-support.md#ảnh-và-svg),
[Xử lý sự cố → Ảnh không hiện](../troubleshooting.md#ảnh-không-hiện).
