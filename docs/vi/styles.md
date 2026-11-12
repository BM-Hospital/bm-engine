# Style và layout

[English](../en/styles.md) · [Tiếng Việt](styles.md)

bm-engine style phần tử bằng CSS thật: cùng thuộc tính, giá trị, cascade và thuật toán layout như trình
duyệt (port từ takumi, vốn port từ Blink). Trang này trình bày ba cách gắn style — object `style`
inline, stylesheet qua option `css`, và class Tailwind trong `tw` — cách chúng kết hợp với nhau, một ví
dụ hoàn chỉnh cho từng chế độ layout (flex, grid, luồng block / inline, định vị absolute, float), rồi
đến đơn vị và màu sắc. Danh sách đầy đủ các thuộc tính và trạng thái của chúng nằm ở
[Hỗ trợ CSS](./css-support.md). Toàn bộ mã dưới đây là `docs/examples/styles.mjs`, chạy trên profile
`full`; mỗi ảnh là kết quả của đoạn mã ngay phía trên nó.

[[toc]]

## Nên dùng cơ chế nào {#which-mechanism-to-use}

| Bạn có | Dùng | Profile |
|:--|:--|:--|
| Style tính bằng code, từng node một | [`style` inline](#inline-styles) | tất cả |
| Văn bản CSS, class dùng chung, `@media`, design token trong `:root` | [option `css`](#stylesheets-the-css-option) | standard / full |
| Class Tailwind, không có bước build | [`tw`](#tailwind-tw) | standard / full |
| Tailwind được bundler biên dịch | CSS sinh ra, truyền vào `css` (chỉ phần engine stylesheet hỗ trợ mới có tác dụng) | standard / full |
| HTML có `<style>` và `style=""` | một [source HTML](./html-and-tailwind.md) | standard / full |

Các ví dụ dùng chung phần khởi tạo này:

<!-- @example styles#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // stylesheets and Tailwind need the standard or full profile

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
```

## Style inline {#inline-styles}

`style` là một object chứa khai báo CSS với key **camelCase**. Giá trị là chuỗi CSS hoặc số: số nghĩa
là px với thuộc tính nhận độ dài và là số thuần ở chỗ khác. Custom property giữ nguyên dấu gạch ngang
và dùng được với `var()`, còn các thuộc tính kế thừa (`fontFamily`, `color`, `fontSize`, ...) truyền
từ container xuống chữ bên trong.

<!-- @example styles#inline -->
```js
const inlinePng = renderer.renderSync({
  type: "container",
  style: {
    display: "flex",
    alignItems: "center",
    gap: 16,                              // number = px
    padding: "0 24px",                    // string = any CSS value
    width: "100%",
    height: "100%",
    "--accent": "#db2777",                // custom properties keep their dashes
    backgroundColor: "#fdf2f8",
    borderLeft: "8px solid var(--accent)",
    fontFamily: "Inter",                  // inherited by the text below
  },
  children: [
    { type: "text", text: "Inline style", style: { fontSize: 32, fontWeight: 700, color: "var(--accent)" } },
    { type: "text", text: "opacity: 0.6", style: { fontSize: 20, opacity: 0.6 } }, // plain number
  ],
}, { width: 500, height: 100 });
```

![Banner hồng có viền trái màu hồng và dòng chữ Inline style](/img/guide/styles-inline.png)

Style inline chặt chẽ với giá trị nhưng dễ dãi với tên:

<!-- @example styles#inline-errors -->
```js
// kebab-case keys and unknown properties are ignored silently
renderer.renderSync({ type: "container", style: { "background-color": "red", colour: "blue" } }, { width: 10, height: 10 });

// an invalid value for a known property throws
expectThrow(() => renderer.renderSync({ type: "container", style: { width: "10 px" } }, { width: 10, height: 10 }));
// "bm-engine: invalid value for style property width"
```

::: warning Key kebab-case bị bỏ qua
`{ "background-color": "red" }` bị bỏ qua lặng lẽ, giống takumi. Hãy dùng `backgroundColor`. Tiền tố
vendor viết hoa chữ đầu: `WebkitLineClamp`, `WebkitTextStroke`.
:::

Cả shorthand (`border`, `background`, `flex`, `font`, `inset`, `gridArea`, ...) lẫn longhand đều dùng
được; thuộc tính logic (`marginInline`, `paddingBlockStart`, `insetInlineEnd`) cũng vậy. `"!important"`
bên trong chuỗi giá trị được tôn trọng.

## Stylesheet: option `css` {#stylesheets-the-css-option}

Truyền một hay nhiều stylesheet dạng chuỗi (hoặc [rule object](#rule-objects)) vào `css`. Node được
khớp qua `className`, `id`, `attributes` và `tagName`. Mọi thứ bạn chờ đợi ở CSS đều có: selector và
combinator, custom property trong `:root`, `var()`, nesting, `@media`, `@supports`, `@layer`.

<!-- @example styles#stylesheet -->
```js
const css = `
  :root { --brand: #2563eb; --radius: 14px; }
  .card { display: flex; flex-direction: column; gap: 8px; width: 100%; height: 100%; padding: 24px;
          font-family: Inter; background: #eff6ff; border-radius: var(--radius); }
  .card > .title { font-size: 30px; font-weight: 700; color: var(--brand); }
  .tags { display: flex; gap: 8px; }
  .tag { padding: 4px 12px; border-radius: 999px; background: white; color: #1e3a8a; font-size: 16px; }
  .tag:first-child { background: var(--brand); color: white; }
  @media (max-width: 400px) {
    .card { padding: 14px; }
    .card > .title { font-size: 22px; }
  }
`;

const tagged = {
  type: "container",
  className: "card",
  children: [
    { type: "text", className: "title", text: "Stylesheets" },
    { type: "container", className: "tags", children: ["css", "selectors", "@media"].map((t) => ({ type: "text", className: "tag", text: t })) },
  ],
};

const wide = renderer.renderSync(tagged, { width: 560, height: 120, css: [css] });
const narrow = renderer.renderSync(tagged, { width: 360, height: 100, css: [css] }); // @media matches
```

| 560 × 120 | 360 × 100 (`@media (max-width: 400px)` khớp) |
|:-:|:-:|
| ![Thẻ rộng](/img/guide/styles-stylesheet-wide.png) | ![Thẻ hẹp với tiêu đề nhỏ hơn](/img/guide/styles-stylesheet-narrow.png) |

Tóm tắt những gì engine stylesheet hỗ trợ (danh sách đầy đủ ở
[Hỗ trợ CSS](./css-support.md#stylesheet-và-selector)):

- **Selector**: type, universal, class, id, attribute (mọi toán tử), bốn combinator, danh sách
  selector, pseudo-class cấu trúc (`:first-child`, `:nth-child(2n+1 of .x)`, `:only-of-type`, ...),
  `:not()`, `:is()`, `:where()`, `:has()`, `:root`, `:empty`, `:lang()`, `:dir()`, và pseudo-element
  `::before` / `::after` với `content`.
- **At-rule**: `@media` (`width`, `height`, `aspect-ratio`, `orientation`, `resolution`, cú pháp
  khoảng, `and` / `or` / `not`), `@supports`, `@layer`, CSS nesting với `&`, `@keyframes`
  ([Animation](./animation.md)), `@theme`, `@import "tailwindcss"`.
- **Không được áp dụng**: `@font-face` (hãy đăng ký font bằng `registerFont`), `@property`,
  `@container`, `@apply`, `@page`; pseudo-class động như `:hover` parse được nhưng không bao giờ khớp.
- `@media` được tính theo kích thước canvas tính bằng **CSS px** (px canvas ÷ `devicePixelRatio`);
  media feature mà engine không biết (ví dụ `prefers-color-scheme`) làm cả truy vấn thành false.
- Khai báo hay rule hỏng sẽ bị bỏ; stylesheet không bao giờ làm lần render bị ném lỗi.

::: warning Pseudo-class cấu trúc trên node text
Ở 0.1.0, `:first-child`, `:last-child`, `:nth-child()` và các variant Tailwind `first:` / `odd:` / ...
khớp với **mọi** node `text` trần giữa các anh em của nó. Hãy đặt chữ vào trong một `container` khi
vị trí là quan trọng. Phần tử HTML và node container không bị ảnh hưởng.
:::

### Rule object {#rule-objects}

Thay vì văn bản, bạn có thể truyền rule object kiểu takumi, `{ selector, style }` với `style` dạng
camelCase. Chúng tiện khi giá trị đến từ dữ liệu, vì không có gì bị nối vào chuỗi CSS. Thứ tự trong
mảng chính là thứ tự cascade:

<!-- @example styles#rule-objects -->
```js
// takumi rule objects: data stays data, no string concatenation
const theme = { brand: "#16a34a" };
const ruleObjects = renderer.renderSync(tagged, {
  width: 560,
  height: 120,
  css: [
    css,
    { selector: ":root", style: { "--brand": theme.brand } },
    { selector: ".card", style: { backgroundColor: "#f0fdf4" } },
  ],
});
```

![Cùng thẻ đó với màu thương hiệu xanh lá và nền xanh lá](/img/guide/styles-rule-objects.png)

Các dạng rule object khác của takumi (`{ media, rules }`, `{ keyframes, steps }`, ...) cũng được chấp
nhận; `{ selector, style }` và `{ media, rules }` đã được kiểm tra ở đây.

### Selector và tagName {#selectors-and-tagname}

Node tree không có tên thẻ trừ khi bạn đặt: một container *không* phải là `div` đối với selector.
Selector type chỉ khớp node có `tagName`; selector class, id, attribute và `*` khớp mọi node.

<!-- @example styles#selectors-tagname -->
```js
// A type selector only matches nodes that have a tagName; `*`, classes, ids and attributes match any node
const heightWith = (node, css) => renderer.measureSync(node, { width: 100, height: 100, css: [css] }).height;
heightWith({ type: "container" }, "div { display: block; height: 7px }");                   // 0 – no tagName
heightWith({ type: "container", tagName: "div" }, "div { display: block; height: 7px }");   // 7
heightWith({ type: "container", id: "hero" }, "#hero { display: block; height: 7px }");     // 7
heightWith({ type: "container", attributes: { "data-kind": "pro" } }, "[data-kind=pro] { display: block; height: 7px }"); // 7
```

Đặt `tagName` trên node tree không áp dụng style user-agent của HTML (node `h1` không tự in đậm); muốn
vậy hãy dùng trường `preset`, hoặc một [source HTML](./html-and-tailwind.md#user-agent-styles).

## Tailwind: `tw` {#tailwind-tw}

Trường `tw` nhận class utility Tailwind v4 và biên dịch chúng ngay trong engine — không cần bước build.
Đây là cùng trình biên dịch của takumi, với cùng tập con; xem
[HTML và Tailwind](./html-and-tailwind.md#tailwind) về variant, giá trị tùy ý và những gì chưa hỗ trợ.

<!-- @example styles#tailwind -->
```js
const twPng = renderer.renderSync({
  type: "container",
  tw: "flex items-center justify-between w-full h-full px-8 bg-slate-900",
  style: { fontFamily: "Inter" },
  children: [
    { type: "text", text: "Tailwind via tw", tw: "text-3xl font-bold text-white" },
    { type: "text", text: "PRO", tw: "px-3 py-1 rounded-md bg-amber-400/90 text-slate-900 text-sm font-bold" },
  ],
}, { width: 500, height: 100 });
```

![Banner tối với tiêu đề Tailwind via tw và huy hiệu PRO màu hổ phách](/img/guide/styles-tailwind.png)

## Các lớp kết hợp ra sao {#how-the-layers-combine}

Từ ưu tiên thấp đến cao:

1. `preset` (lớp user-agent; thẻ HTML nhận mặc định của Chromium ở đây)
2. utility Tailwind từ `tw`
3. rule stylesheet từ `css` và `<style>` (theo độ đặc hiệu và thứ tự, có tôn trọng `@layer`)
4. `style` inline
5. khai báo `!important`, đảo ngược thứ tự như trong CSS (utility có tiền tố `!` như `!w-20` thắng
   khai báo inline)

<!-- @example styles#precedence -->
```js
const widthWith = (node, css = []) => renderer.measureSync(node, { width: 400, height: 100, css }).width;
const base = { type: "container", className: "box", tw: "block w-20 h-5" };   // tw: width 80px

widthWith(base);                                                      // 80  – tw
widthWith(base, [".box { width: 60px }"]);                            // 60  – a stylesheet rule beats tw
widthWith({ ...base, style: { width: 40 } }, [".box { width: 60px }"]); // 40  – inline style beats both
widthWith({ ...base, style: { width: 40 } }, [".box { width: 60px !important }"]); // 60 – !important wins
widthWith({ ...base, tw: "block !w-20 h-5", style: { width: 40 } });  // 80  – a !utility beats inline style
widthWith({ type: "container", preset: { display: "block", width: 30 }, style: { height: 5 } }); // 30 – preset is the lowest layer
```

::: info Khác với Tailwind trên trình duyệt
Ở đây rule của stylesheet thắng utility `tw` ngay cả khi rule nằm trong một `@layer` có tên (đã kiểm
tra: `@layer base { .x { width: 33px } }` thắng `w-20`). Trên trình duyệt với Tailwind v4, utility sẽ
thắng rule nằm trong layer. Hãy dùng `style` inline hoặc utility `!` khi cần utility thắng.
:::

## Các chế độ layout {#layout-modes}

Mọi chế độ layout CSS mà takumi hỗ trợ đều có trên mọi profile, trừ float và bảng cần `standard`. Bảng
có trang riêng: [Bảng và float](./tables.md).

### Flexbox {#flexbox}

`display: "flex"` với `flexDirection`, `flexWrap`, `gap`, `flex` / `flexGrow` / `flexShrink` /
`flexBasis`, `justifyContent`, `alignItems`, `alignContent`, `alignSelf` và `order`. Đây là công cụ
chủ lực cho thẻ và banner:

<!-- @example styles#flex -->
```js
const box = (text, style) => ({
  type: "container",
  style: { display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 8, ...style },
  children: [label(text)],
});
const flexPng = renderer.renderSync({
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 10, padding: 16, width: "100%", height: "100%", backgroundColor: "#f1f5f9", fontFamily: "Inter" },
  children: [
    { // a row: fixed, growing and shrinking items
      type: "container",
      style: { display: "flex", gap: 10, height: 60 },
      children: [
        box("120px", { width: 120, backgroundColor: "#0ea5e9" }),
        box("flex: 1", { flex: 1, backgroundColor: "#6366f1" }),
        box("flex: 2", { flex: 2, backgroundColor: "#a855f7" }),
      ],
    },
    { // wrapping, centred
      type: "container",
      style: { display: "flex", flexWrap: "wrap", justifyContent: "center", gap: 8, flex: 1, alignContent: "center" },
      children: ["one", "two", "three", "four", "five", "six", "seven"].map((t) => box(t, { width: 110, height: 34, backgroundColor: "#f97316" })),
    },
  ],
}, { width: 560, height: 200 });
```

![Một hàng ba box 120px, flex 1, flex 2 phía trên hai hàng viên thuốc màu cam được căn giữa và xuống dòng](/img/guide/styles-flex.png)

`direction: "rtl"` không đảo hàng flex ở 0.1.0 (takumi thì có); hãy dùng `flexDirection: "row-reverse"`.

### Grid {#grid}

`display: "grid"` với danh sách track (`px`, `%`, `fr`, `auto`, `minmax()`, `repeat()` kể cả
`auto-fill` / `auto-fit`), tự động đặt vị trí, span, đường lưới có tên và `gridTemplateAreas`:

<!-- @example styles#grid -->
```js
const area = (name, color) => ({
  type: "container",
  style: { gridArea: name, display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 8, backgroundColor: color },
  children: [label(name)],
});
const gridPng = renderer.renderSync({
  type: "container",
  style: {
    display: "grid",
    gridTemplateColumns: "120px 1fr 1fr",
    gridTemplateRows: "40px 1fr 30px",
    gridTemplateAreas: '"head head head" "side main main" "side foot foot"',
    gap: 8, padding: 12, width: "100%", height: "100%", backgroundColor: "#f1f5f9", fontFamily: "Inter",
  },
  children: [area("head", "#0f172a"), area("side", "#0d9488"), area("main", "#2563eb"), area("foot", "#64748b")],
}, { width: 560, height: 200 });
```

![Lưới với hàng head màu tối, cột side màu xanh mòng két và các vùng main, foot](/img/guide/styles-grid.png)

### Luồng block và inline {#block-and-inline-flow}

Box `display: "block"` xếp chồng theo chiều dọc với margin collapsing; chữ và box inline bên trong tạo
thành các dòng (line box) tự xuống dòng ở mép container. Trộn đoạn chữ, span có style và box
`inline-block` trên cùng một dòng:

<!-- @example styles#flow -->
```js
// Block and inline flow: block boxes stack, inline content wraps into lines
const flowPng = renderer.renderSync({
  type: "container",
  style: { display: "block", padding: 16, width: "100%", height: "100%", backgroundColor: "white", fontFamily: "Inter", fontSize: 18, color: "#1e293b" },
  children: [
    { type: "text", text: "Block flow", style: { display: "block", fontSize: 24, fontWeight: 700, marginBottom: 8 } },
    {
      type: "container",
      style: { display: "block", lineHeight: 1.6 },
      children: [
        { type: "text", text: "Text runs, " },
        { type: "text", text: "styled spans", style: { color: "#be185d", fontWeight: 700 } },
        { type: "text", text: " and an " },
        { type: "container", style: { display: "inline-block", width: 60, height: 18, borderRadius: 9, backgroundColor: "#22c55e", verticalAlign: "middle" } },
        { type: "text", text: " inline-block share the same lines and wrap at the container edge." },
      ],
    },
  ],
}, { width: 560, height: 150 });
```

![Tiêu đề và đoạn văn có span hồng in đậm và một viên thuốc xanh inline-block, xuống hai dòng](/img/guide/styles-flow.png)

Layout chữ (xuống dòng, `whiteSpace`, `lineHeight`, dấu ba chấm, ...) có ở [Typography](./typography.md).

### Định vị absolute {#absolute-positioning}

`position: "absolute"` đưa box ra khỏi luồng và đặt nó bằng `top` / `right` / `bottom` / `left` (hoặc
`inset`) so với tổ tiên được định vị gần nhất; `zIndex` đổi thứ tự vẽ. `position: "fixed"` định vị
theo canvas; `sticky` hoạt động như `relative`.

<!-- @example styles#absolute -->
```js
const absPng = renderer.renderSync({
  type: "container",
  style: { display: "flex", position: "relative", width: "100%", height: "100%", backgroundColor: "#1e293b", fontFamily: "Inter" },
  children: [
    { type: "container", style: { position: "absolute", top: 16, left: 16, width: 120, height: 80, borderRadius: 10, backgroundColor: "#38bdf8" } },
    { type: "container", style: { position: "absolute", top: 50, left: 90, width: 120, height: 80, borderRadius: 10, backgroundColor: "#f472b6", opacity: 0.9 } },
    { type: "container", style: { position: "absolute", top: 30, left: 50, width: 120, height: 80, borderRadius: 10, backgroundColor: "#facc15", zIndex: 2 } },
    {
      type: "container",
      style: { position: "absolute", right: 16, bottom: 16, padding: "6px 14px", borderRadius: 999, backgroundColor: "#ef4444" },
      children: [label("NEW")],
    },
  ],
}, { width: 400, height: 160 });
```

![Ba hình chữ nhật bo góc chồng nhau, hình vàng nằm trên nhờ z-index, và huy hiệu NEW màu đỏ ở góc](/img/guide/styles-absolute.png)

### Float {#floats}

`float: "left" | "right"` và `clear` (standard / full; bị bỏ qua trên `core`). Các dòng bên cạnh float
bị thu ngắn và rộng trở lại bên dưới nó:

<!-- @example styles#floats -->
```js
// floats need the standard or full profile (ignored on core)
const floatPng = renderer.renderSync({
  type: "container",
  style: { display: "block", padding: 16, width: "100%", height: "100%", backgroundColor: "white", fontFamily: "Inter", fontSize: 16, lineHeight: 1.5, color: "#334155" },
  children: [
    { type: "container", style: { float: "left", width: 90, height: 90, marginRight: 14, borderRadius: 12, backgroundImage: "linear-gradient(135deg, #f97316, #db2777)" } },
    { type: "text", text: "This paragraph flows around the floated box: lines beside the float are shorter, and once the float ends the text returns to the full width of the container, as in a browser. Use clear to start below a float." },
  ],
}, { width: 460, height: 170 });
```

![Ô vuông gradient float trái, đoạn văn chảy quanh nó rồi tiếp tục bên dưới](/img/guide/styles-floats.png)

Thêm về float và giới hạn của nó: [Bảng và float](./tables.md).

## Đơn vị {#units}

| Đơn vị | Ý nghĩa trong bm-engine |
|:--|:--|
| số, `px` | CSS px (× `devicePixelRatio` trên canvas) |
| `%` | của khối chứa; trên root là của canvas |
| `em`, `rem` | của cỡ chữ phần tử / root (root: 16 px) |
| `vw`, `vh`, `vmin`, `vmax` | của canvas (px đầu ra) |
| `pt`, `pc`, `in`, `cm`, `mm`, `Q` | đơn vị tuyệt đối (1in = 96px) |
| `ch`, `ex`, `lh`, `rlh`, `cq*` | hỗ trợ như CSS |
| `calc()`, `min()`, `max()`, `clamp()` và các hàm toán khác | dùng được ở mọi chỗ nhận độ dài hoặc số |

Xem [bm-engine hoạt động thế nào](./concepts.md#numbers-units-and-the-viewport) để có ví dụ đã đo.

## Màu sắc {#colours}

Tên màu, hex (`#rgb`, `#rrggbbaa`), `rgb()` / `hsl()` / `hwb()` ở cả hai cú pháp, `currentColor` và
`transparent` dùng được ở mọi nơi. `standard` và `full` có thêm `oklch()`, `oklab()`, `lab()`, `lch()`,
`color()`, `color-mix()` và `light-dark()` (luôn chọn giá trị light):

<!-- @example styles#colors -->
```js
const swatch = (color) => ({
  type: "container",
  style: { display: "flex", alignItems: "flex-end", height: 70, padding: 6, borderRadius: 8, backgroundColor: color },
  children: [{ type: "text", text: color, style: { fontSize: 11, color: "white", backgroundColor: "rgb(0 0 0 / 0.45)", padding: "1px 4px", borderRadius: 4 } }],
});
const colorsPng = renderer.renderSync({
  type: "container",
  style: { display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 8, padding: 12, width: "100%", height: "100%", backgroundColor: "#f8fafc", fontFamily: "Inter" },
  children: [
    "tomato", "#0ea5e9", "rgb(34 197 94)", "hsl(270 70% 55%)",
    "oklch(62% 0.2 30)", "color-mix(in oklab, #2563eb 60%, white)", "lab(55% 40 -60)", "rgb(15 23 42 / 0.5)",
  ].map(swatch),
}, { width: 560, height: 190 });
```

![Tám ô màu, mỗi ô ghi màu CSS đã tạo ra nó](/img/guide/styles-colors.png)

Trên `core` các hàm màu hiện đại không được parse, nên style inline dùng chúng sẽ ném lỗi:

<!-- @example styles#core-colors -->
```js
import { Renderer as CoreRenderer } from "bm-engine/core";
const core = new CoreRenderer();
expectThrow(() => core.renderSync({ type: "container", style: { width: 10, height: 10, backgroundColor: "oklch(62% 0.2 30)" } }, { width: 10, height: 10 }));
// "bm-engine: invalid value for style property backgroundColor"
```

Trong stylesheet, cùng khai báo đó chỉ đơn giản bị bỏ. Cú pháp màu tương đối
(`rgb(from red r g b / 50%)`) không được hỗ trợ trên profile nào.

## Xem thêm {#see-also}

- [Hỗ trợ CSS](./css-support.md) — mọi thuộc tính, giá trị và trạng thái
- [HTML và Tailwind](./html-and-tailwind.md) — source HTML và trình biên dịch Tailwind
- [Typography](./typography.md), [Hiệu ứng](./effects.md), [Ảnh](./images.md)
- [bm-engine hoạt động thế nào](./concepts.md) — các mặc định như `display: inline` và `border-box`
