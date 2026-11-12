# bm-engine hoạt động thế nào

[English](../../en/image/concepts.md) · [Tiếng Việt](concepts.md)

Trang này giải thích mô hình đứng sau mọi lần render: đầu vào là gì (node tree, chuỗi HTML hay class
Tailwind), engine chạy qua những bước nào (style, layout, paint, encode), những giá trị mặc định hay làm
người quen trình duyệt bất ngờ, và renderer cùng bộ nhớ hoạt động ra sao trong suốt vòng đời một tiến
trình. Hãy đọc trang này một lần trước khi sang các trang chủ đề ([Style](./styles.md),
[Font](./fonts.md), [Typography](./typography.md), [Ảnh](./images.md), ...). Mọi đoạn mã dưới đây đều
nằm trong `docs/examples/concepts.mjs` và đã được chạy thật với package; các ảnh là kết quả của nó.

[[toc]]

## Pipeline {#the-pipeline}

Một lời gọi như `renderer.renderSync(source, options)` chạy qua năm bước, tất cả bên trong một module
WebAssembly và đều đồng bộ:

| Bước | Điều gì xảy ra | Đầu vào liên quan |
|:--|:--|:--|
| 1. Input | Source được chuyển thành cây phần tử. Object node được đọc trực tiếp, `{ json }` được parse, chuỗi được parse như HTML (standard / full). | `source` |
| 2. Style | Mỗi phần tử nhận computed style: mặc định user-agent (`preset`, thẻ HTML), rule của stylesheet (`css`, `<style>`), utility Tailwind (`tw`), `style` inline, rồi kế thừa, `var()` và `calc()`. | `css`, `tw`, `style`, `devicePixelRatio`, `timeMs` |
| 3. Layout | Các box nhận vị trí và kích thước: luồng block và inline với ngắt dòng và shaping chữ, flexbox, grid, bảng, float, định vị absolute. Đơn vị là pixel thiết bị với độ chính xác 1/64 px. | `width`, `height`, font đã đăng ký |
| 4. Paint | Nền, viền, bóng, ảnh, glyph, filter và hiệu ứng được rasterize vào canvas RGBA (khử răng cưa bằng supersampling 4×4, giống takumi). | `images` |
| 5. Encode | Canvas thành PNG, JPEG, WebP, ICO hoặc giữ nguyên RGBA thô. `renderSvg` thay paint + encode bằng đầu ra SVG; `measure` dừng sau layout. | `format`, `quality` |

Không bước nào chạm tới mạng, hệ thống file hay font hệ thống: mọi font và mọi byte ảnh đều đến từ mã
JavaScript của bạn (xem [Ảnh](./images.md) và [Font](./fonts.md)).

Đây là chương trình đầy đủ nhỏ nhất. Tạo renderer một lần, đăng ký font một lần, rồi render bao nhiêu
lần tùy ý:

<!-- @example concepts#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer, features } from "bm-engine";

const renderer = new Renderer(); // create once, reuse for every render
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

<!-- @example concepts#first -->
```js
const png = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#4f46e5" },
    children: [{ type: "text", text: "Hello, bm-engine", style: { fontFamily: "Inter", fontSize: 40, fontWeight: 700, color: "white" } }],
  },
  { width: 600, height: 200 },
);
```

![Banner tím với dòng chữ Hello, bm-engine](/img/guide/concepts-first.png)

`renderSync` trả về một `Uint8Array` chứa file PNG. Mỗi phương thức đều có bản async (`render`,
`measure`, ...) chỉ khác ở chỗ nhận được các option bất đồng bộ như dữ liệu ảnh lazy; bản thân việc
render vẫn đồng bộ trong cả hai trường hợp. Chọn định dạng bằng `format`, xem
[Định dạng](./formats.md).

## Định dạng node {#the-node-format}

Node tree là dữ liệu thuần, tương thích JSON. Có ba loại node:

| `type` | Trường bắt buộc | Hoạt động như |
|:--|:--|:--|
| `"container"` | — (`children` tùy chọn) | một phần tử (`div`) |
| `"text"` | `text` | một đoạn chữ inline (`span`) |
| `"image"` | `src` | một phần tử thay thế (`img`) |

Node nào cũng có thể mang thêm:

| Trường | Mục đích |
|:--|:--|
| `style` | khai báo CSS inline với key **camelCase** (`backgroundColor`) |
| `tw` | class Tailwind (standard / full) |
| `preset` | một lớp style có độ ưu tiên thấp nhất, cho các mặc định kiểu user-agent |
| `className`, `id`, `attributes`, `tagName` | móc cho selector của stylesheet (xem [Style](./styles.md#selectors-and-tagname)) |
| `dir`, `lang` | hướng chữ và ngôn ngữ (bidi, `:lang()`, ngôn ngữ OpenType) |

Các trường `width` / `height` của node ảnh chỉ là gợi ý trình bày, giống thuộc tính HTML; `width` và
`height` trong CSS thắng chúng. `src` có thể là pixel RGBA thô, byte đã mã hóa, URL `data:`, markup SVG
inline hoặc một key của option `images` — xem [Ảnh](./images.md).

<!-- @example concepts#node-format -->
```js
// a 2 × 2 RGBA image, built in code (raw pixels work on every profile)
const pixels = { width: 2, height: 2, data: new Uint8Array([
  239, 68, 68, 255,   34, 197, 94, 255,
  59, 130, 246, 255,  234, 179, 8, 255,
]) };

const card = {
  type: "container",                                  // a box; may have children
  style: { display: "flex", gap: 24, padding: 32, width: "100%", height: "100%", alignItems: "center", backgroundColor: "#f8fafc" },
  children: [
    { type: "image", src: pixels, width: 96, height: 96, style: { borderRadius: 16 } },        // an image
    {
      type: "container",
      style: { display: "flex", flexDirection: "column", gap: 6 },
      children: [
        { type: "text", text: "Three node types", style: { fontFamily: "Inter", fontSize: 32, fontWeight: 700, color: "#0f172a" } }, // text
        { type: "text", text: "container · text · image", style: { fontFamily: "Inter", fontSize: 22, color: "#475569" } },
        null, // null / undefined children are skipped
      ],
    },
  ],
};
const nodePng = renderer.renderSync(card, { width: 600, height: 160 });
```

![Một ảnh bốn màu nhòe cạnh tiêu đề và phụ đề](/img/guide/concepts-node-format.png)

Ảnh 2 × 2 được kéo giãn thành 96 × 96 với nội suy mượt; `objectFit` mặc định là `fill`. Key lạ trên
node bị bỏ qua; node thiếu `type` sẽ ném ``bm-engine: node is missing `type` `` và node text thiếu
`text` sẽ ném ``bm-engine: text node is missing `text` ``.

## Ba cách mô tả cùng một ảnh {#three-ways-to-describe-the-same-image}

Node tree là đầu vào gốc. Trên profile `standard` và `full` bạn còn có thể truyền một chuỗi HTML hoặc
dùng class Tailwind; chúng tạo ra cùng một cây phần tử và đi qua cùng pipeline.

<!-- @example concepts#inputs -->
```js
// 1. a node tree (every profile)
const fromTree = renderer.renderSync({
  type: "container",
  style: { display: "flex", width: "100%", height: "100%", padding: 24, backgroundColor: "#0f172a" },
  children: [{ type: "text", text: "Node tree", style: { fontFamily: "Inter", fontSize: 36, color: "#38bdf8" } }],
}, { width: 300, height: 100 });

// 2. an HTML string (standard / full): every JS string source is parsed as HTML
const fromHtml = renderer.renderSync(
  `<div style="display:flex; width:100%; height:100%; padding:24px; background:#0f172a">
     <span style="font-family:Inter; font-size:36px; color:#a3e635">HTML string</span>
   </div>`,
  { width: 300, height: 100 },
);

// 3. Tailwind classes in `tw` (standard / full), on a node tree or as a tw="" attribute in HTML
const fromTw = renderer.renderSync({
  type: "container",
  tw: "flex w-full h-full p-6 bg-slate-900",
  children: [{ type: "text", text: "Tailwind", tw: "text-4xl text-pink-400", style: { fontFamily: "Inter" } }],
}, { width: 300, height: 100 });

// 4. JSON text: wrap it, because a plain string would be parsed as HTML
const fromJson = renderer.renderSync({ json: '{"type":"container","style":{"width":300,"height":100,"backgroundColor":"#0f172a"}}' });
```

| Node tree | Chuỗi HTML | Tailwind |
|:-:|:-:|:-:|
| ![Node tree](/img/guide/concepts-input-tree.png) | ![Chuỗi HTML](/img/guide/concepts-input-html.png) | ![Tailwind](/img/guide/concepts-input-tw.png) |

- **Mọi chuỗi JavaScript đều là HTML**, giống takumi. Muốn truyền node tree dưới dạng văn bản JSON,
  hãy bọc nó lại: `{ json: "..." }`.
- Các dạng có thể trộn tự do: HTML có thể mang `style=""`, `tw=""` và khối `<style>`; node tree có thể
  mang `tw` và được style bằng option `css`.
- Trên `core`, source HTML ném `this build has no HTML input support` và node có `tw` ném
  ``Tailwind (`tw`) is not supported by this build``. Xem [HTML và Tailwind](./html-and-tailwind.md).

Nếu bạn viết JSX, hãy chuyển nó thành node tree trước (ví dụ bằng `fromJsx` của `@takumi-rs/helpers`;
xem [Khác biệt so với takumi](./differences-from-takumi.md#chuyển-đổi-trong-năm-bước)).

## Những mặc định gây bất ngờ {#defaults-that-surprise-people}

bm-engine theo takumi, mà takumi theo CSS và Chromium. Vài mặc định của CSS trông lạ nếu bạn đến từ
satori hoặc từ trình duyệt có CSS reset.

### `display` là `inline` {#display-is-inline}

Mọi node — kể cả container — khởi đầu với `display: inline`, đúng như một phần tử chưa style trong CSS.
Box inline bỏ qua `width` và `height`. Chỉ có root và con của container flex / grid là được
*blockify* tự động:

<!-- @example concepts#display-default -->
```js
const twoSquares = (display) => ({
  type: "container",
  style: { display, gap: 10, padding: 10, backgroundColor: "#e2e8f0" },
  children: [
    { type: "container", style: { width: 50, height: 50, backgroundColor: "#f97316" } },
    { type: "container", style: { width: 50, height: 50, backgroundColor: "#8b5cf6" } },
  ],
});
// wrap the box in a block parent and measure how tall the parent becomes
const heightOf = (display) =>
  renderer.measureSync({ type: "container", style: { display: "block" }, children: [twoSquares(display)] }, { width: 200, height: 100 }).height;

heightOf(undefined); // 20 – default display is inline: width / height of the box and of its inline children are
                     //      ignored; only one line remains (the padded inline box makes it a non-empty line)
heightOf("block");   // 20 – only the padding: the children are still inline
heightOf("flex");    // 70 – flex items are blockified: 50 + 2 × 10 padding
```

Cũng ba box đó khi render (mỗi box nằm trong một wrapper block):

<!-- @example concepts#display-image -->
```js
const row = (display, label) => ({
  type: "container",
  style: { display: "flex", alignItems: "center", gap: 16 },
  children: [
    { type: "text", text: label, style: { fontFamily: "Inter", fontSize: 18, width: 170, color: "#334155" } },
    // a block wrapper, so that twoSquares is not itself a (blockified) flex item
    { type: "container", style: { display: "block", width: 140 }, children: [twoSquares(display)] },
  ],
});
const displayPng = renderer.renderSync({
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 12, padding: 16, width: "100%", height: "100%", backgroundColor: "white" },
  children: [row(undefined, "display: (default)"), row("block", "display: block"), row("flex", "display: flex")],
}, { width: 420, height: 180 });
```

![Ba hàng: hàng mặc định chỉ có một ô xám nhỏ (padding của hộp inline rỗng), hàng block có dải padding xám, hàng flex hiện hai ô vuông cam và tím](/img/guide/concepts-display.png)

::: tip Quy tắc dễ nhớ
Hãy đặt `display: "flex"`, `"block"` hoặc `"grid"` tường minh cho mọi container có kích thước, hoặc có
các con cần xếp thành hàng hay cột. Node text bên trong container flex thì không cần gì.
:::

Đầu vào HTML thì khác: ở đó stylesheet user-agent của Chromium biến `div`, `p`, `h1`, ... thành box
block, giống trình duyệt (xem [HTML và Tailwind](./html-and-tailwind.md#user-agent-styles)).

::: info measure() và box inline
`measure()` chỉ báo cáo các box cấp block (và các dòng chữ). Một container inline không có mặt trong
`children` của cha nó, vì vậy ví dụ trên đo chiều cao của cha.
:::

### `box-sizing` là `border-box` {#box-sizing-is-border-box}

Khác với CSS, `width` và `height` mặc định đã bao gồm padding và viền (lựa chọn của takumi). Đặt
`boxSizing: "content-box"` để có hành vi như CSS:

<!-- @example concepts#box-sizing -->
```js
const boxes = renderer.measureSync({
  type: "container",
  style: { display: "flex", gap: 10 },
  children: [
    { type: "container", style: { width: 100, height: 40, padding: 10, border: "5px solid black" } },
    { type: "container", style: { width: 100, height: 40, padding: 10, border: "5px solid black", boxSizing: "content-box" } },
  ],
}, { width: 400, height: 100 });
boxes.children.map((c) => `${c.width}×${c.height}`); // [ '100×40', '130×70' ]
```

### Số, đơn vị và viewport {#numbers-units-and-the-viewport}

- Số là **px** với các thuộc tính nhận độ dài (`width: 120`) và giữ nguyên là số ở chỗ khác
  (`opacity: 0.6`, `lineHeight: 1.4`, `flexGrow: 1`, `fontWeight: 700`).
- Chuỗi nhận mọi giá trị CSS: `"50%"`, `"2rem"`, `"25vw"`, `"calc(100% - 48px)"`, `clamp()`, ...
- **Canvas chính là viewport**: `%` trên root, `vw`, `vh` và các truy vấn `@media` tính theo option
  render `width` và `height`. Cỡ chữ của root là 16 px, nên `1rem = 16px`.

<!-- @example concepts#units -->
```js
const unitBox = (width) => ({ type: "container", style: { display: "block", width, height: 10 } });
const widthOf = (width, options = {}) => renderer.measureSync(unitBox(width), { width: 400, height: 100, ...options }).width;

widthOf(120);                       // 120 – a number is px
widthOf("50%");                     // 200 – of the canvas width
widthOf("25vw");                    // 100 – vw / vh refer to the canvas
widthOf("2rem");                    // 32  – root font size is 16px
widthOf("calc(100% - 2 * 24px)");   // 352
widthOf(120, { devicePixelRatio: 2 }); // 240 – CSS px are scaled, the canvas is not
```

Các giá trị `measure` trả về là pixel thiết bị (CSS px × `devicePixelRatio`).

### Canvas {#the-canvas}

- `width` / `height` là kích thước đầu ra tính bằng pixel (tối đa 16384 mỗi cạnh và 40 megapixel).
- Canvas khởi đầu **trong suốt**. Hãy tô nền cho root nếu cần; đầu ra JPEG biến pixel trong suốt
  thành đen.
- Root *không* tự giãn theo canvas: đặt `width: "100%"` và `height: "100%"` để nó phủ kín.
- Bỏ `width` và/hoặc `height` thì canvas lấy kích thước của root sau khi layout:

<!-- @example concepts#canvas -->
```js
// No width / height: the canvas takes the size of the root box
const auto = renderer.renderSync({ type: "container", style: { width: 240, height: 60, backgroundColor: "#22c55e" } });
// auto is a 240 × 60 PNG

// Empty content and no size is an error
expectThrow(() => renderer.renderSync({ type: "container" }));
// "bm-engine: invalid viewport: content has zero size and no width/height was given"
```

### Device pixel ratio {#device-pixel-ratio}

`devicePixelRatio` nhân mọi độ dài CSS và cỡ chữ nhưng **không** đổi kích thước canvas. Muốn ảnh nét
hơn cho cùng một thiết kế, hãy nhân canvas lên cùng hệ số:

<!-- @example concepts#dpr -->
```js
const badge = {
  type: "container",
  style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#fef3c7", borderRadius: 12 },
  children: [{ type: "text", text: "Retina", style: { fontFamily: "Inter", fontSize: 24, fontWeight: 700, color: "#92400e" } }],
};
const x1 = renderer.renderSync(badge, { width: 160, height: 60 });
// same design, twice the pixels: double the canvas AND set devicePixelRatio
const x2 = renderer.renderSync(badge, { width: 320, height: 120, devicePixelRatio: 2 });
```

| `width: 160, height: 60` | `width: 320, height: 120, devicePixelRatio: 2` |
|:-:|:-:|
| ![Huy hiệu 1x](/img/guide/concepts-dpr-1x.png) | ![Huy hiệu 2x](/img/guide/concepts-dpr-2x.png) |

`%`, `vw` và `vh` vốn đã theo canvas nên không cần đổi. Truy vấn `@media` thấy kích thước canvas tính
bằng CSS px (px đầu ra ÷ `devicePixelRatio`).

### Không có font dựng sẵn {#fonts-none-built-in}

bm-engine không kèm font nào và không bao giờ đọc font hệ thống. Chữ không có font đăng ký dùng được sẽ
**không được vẽ**, và không báo lỗi. Hãy đăng ký mọi font bạn dùng trên từng renderer — xem
[Font](./fonts.md).

### Style inline chặt chẽ, stylesheet dễ dãi {#strict-inline-styles-forgiving-stylesheets}

Giá trị không hợp lệ trong `style` inline (`width: "10 px"`) sẽ ném
`bm-engine: invalid value for style property width`. Cùng lỗi đó trong stylesheet hay class Tailwind
chỉ bị bỏ qua lặng lẽ, giống trình duyệt. Thuộc tính lạ và key kebab-case trong `style` cũng bị bỏ qua
lặng lẽ. Xem [Style](./styles.md#inline-styles).

## Renderer, instance và bộ nhớ {#renderers-instances-and-memory}

Ba đối tượng có vòng đời khác nhau:

| Đối tượng | Số lượng | Giữ gì |
|:--|:--|:--|
| **Instance wasm** | một cho mỗi điểm vào (`bm-engine`, `bm-engine/core`, `/standard`, `/full`), tạo bởi `init` (tự động trên Node) | linear memory dùng chung cho mọi renderer của điểm vào đó |
| Một **`Renderer`** | bao nhiêu tùy cần; thường một cho mỗi bộ font | font đã đăng ký, cache ảnh đã giải mã (xóa khi vượt 96 MiB), cache glyph (xóa khi vượt 8 MiB), canvas |
| Một **lần render** | một cho mỗi lời gọi | một arena tạm, được lần render sau dùng lại |

<!-- @example concepts#lifecycle -->
```js
// Renderers are cheap; fonts are not. Keep one renderer per font set and reuse it.
const r = new Renderer();
r.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf")); // family name read from the font: "Inter"

for (let i = 0; i < 3; i++) {
  r.renderSync({ type: "text", text: `card ${i}`, style: { fontFamily: "Inter" } }, { width: 200, height: 40 });
}
r.memoryBytes(); // size of the wasm memory shared by every renderer of this entry, in bytes

r.free();        // releases its fonts and caches; r can no longer be used
expectThrow(() => r.renderSync({ type: "container" }, { width: 10, height: 10 }));
// "bm-engine: renderer has been freed"

{
  using scoped = new Renderer(); // free() is called at the end of the block
  scoped.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
}
```

- **Tạo một lần, dùng lại.** Tạo renderer thì rẻ; đăng ký font thì phải sao chép và parse byte font.
  Hãy giữ một renderer sống lâu cho mỗi bộ font (ví dụ một cho mỗi tiến trình server hoặc mỗi worker)
  thay vì tạo mới cho từng request.
- **Bộ nhớ chỉ tăng.** Bộ nhớ WebAssembly không thể co lại. Vùng nhớ đã giải phóng được các lần render
  sau dùng lại, nên một tải ổn định sẽ chững lại (khoảng 6 MiB cho thẻ 1200 × 630 với một font). Một
  canvas rất lớn sẽ nâng mức đó lên suốt phần đời còn lại của instance; xem
  [Hiệu năng](./performance.md).
- **Đơn luồng.** Một lần render chặn luồng gọi nó. Muốn song song, hãy chạy một instance cho mỗi worker
  thread; renderer không thể chia sẻ giữa các luồng.
- `free()` (hoặc `using`) giải phóng font và cache của renderer; sau đó mọi lời gọi trên nó đều ném
  `bm-engine: renderer has been freed`.

## Profile trong một đoạn {#profiles-in-one-paragraph}

Engine được biên dịch thành ba binary cho ảnh (và binary thứ tư, `pdf`, thêm đầu ra PDF; xem [Đầu ra PDF](../pdf/index.md)): `core` (node tree, style inline, font TrueType tĩnh, ảnh PNG /
JPEG; 487.6 KiB), `standard` (thêm stylesheet, Tailwind, HTML, ảnh SVG, WOFF2, font variable và CFF,
hiệu ứng như clip-path và blend mode, màu hiện đại, bảng, float; 934.4 KiB) và `full` (thêm bidi và chữ
phức, emoji màu, animation CSS và `renderAnimation`, `renderSvg`, codec bổ sung; 1 141.5 KiB). Trên
Node.js, `bm-engine` nạp `full`; `bm-engine/core` và `bm-engine/standard` nạp các bản nhỏ hơn.
`features` cho biết binary đang nạp làm được gì:

<!-- @example concepts#features -->
```js
features.html;        // true on standard / full
features.complexText; // true on full only
```

So sánh đầy đủ, và cách một profile nhỏ hơn xử lý đầu vào nó không hỗ trợ, nằm ở
[Profile và kích thước](../profiles-and-size.md).

## Xem thêm {#see-also}

- [Style](./styles.md) — style inline, stylesheet, Tailwind và các chế độ layout
- [HTML và Tailwind](./html-and-tailwind.md) — trình parse HTML và trình biên dịch Tailwind chi tiết
- [Tham chiếu API](./api.md) — mọi phương thức và option
- [Xử lý sự cố](../troubleshooting.md) — những triệu chứng mà các mặc định này gây ra
