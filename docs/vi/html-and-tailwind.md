# HTML và Tailwind

[English](../en/html-and-tailwind.md) · [Tiếng Việt](html-and-tailwind.md)

Ngoài node tree, profile `standard` và `full` còn nhận hai cách mô tả ảnh nữa: một **chuỗi HTML** làm
source render, và **class Tailwind** trong trường `tw` của node (hoặc thuộc tính `tw=""` trong HTML).
Cả hai đều là bản port trình parse HTML và trình biên dịch Tailwind của chính takumi, nên nhận cùng tập
con. Trang này nói về những gì trình parse HTML hiểu, style user-agent nào được áp dụng, cái gì bị bỏ
qua, và trình biên dịch Tailwind đi được tới đâu — variant, giá trị tùy ý, Preflight, biến theme và các
lỗ hổng. Toàn bộ mã là `docs/examples/html-and-tailwind.mjs`, chạy với `bm-engine/standard`.

[[toc]]

<!-- @example html-and-tailwind#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine/standard"; // HTML and Tailwind need standard or full

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Italic.ttf"));
```

Trên `core` cả hai loại đầu vào đều ném lỗi:

<!-- @example html-and-tailwind#core-errors -->
```js
import { Renderer as CoreRenderer } from "bm-engine/core";
const core = new CoreRenderer();
expectThrow(() => core.renderSync("<div></div>", { width: 10, height: 10 }));
// "bm-engine: this build has no HTML input support (use the standard / full build)"
expectThrow(() => core.renderSync({ type: "container", tw: "flex" }, { width: 10, height: 10 }));
// "bm-engine: Tailwind (`tw`) is not supported by this build"
```

## Source HTML {#html-sources}

**Mọi chuỗi JavaScript truyền vào làm source đều được parse như HTML** (giống takumi). Trình parse là
một tập con dễ dãi của thuật toán WHATWG: nhận cả fragment lẫn tài liệu đầy đủ, thẻ đóng ngầm định
(`p`, `li`, `dt` / `dd`, các phần của bảng), `tbody` ngầm định, phần tử void và tham chiếu ký tự. Khối
`<style>` ở bất kỳ đâu trong chuỗi đều được áp dụng như một stylesheet, cùng với option `css` nếu có.

<!-- @example html-and-tailwind#article -->
```js
const html = `
<style>
  .post { font-family: Inter; padding: 20px 28px; background: #fff; color: #1f2937; height: 100%; }
  .post h1 { margin: 0 0 6px; font-size: 30px; }
  .meta { color: #6b7280; font-size: 14px; }
  .post p { font-size: 16px; line-height: 1.5; margin: 10px 0; }
  mark { background: #fef08a; }
</style>
<article class="post">
  <h1>Rendering HTML</h1>
  <div class="meta">5&nbsp;min read &middot; 2026</div>
  <p>The source is a <strong>plain string</strong> with <em>inline</em> elements,
     <mark>highlighted text</mark> and <code>code</code>.</p>
  <p>Line one<br>line two &mdash; entities such as &amp;, &lt; and &copy; are decoded.</p>
</article>`;
const articlePng = renderer.renderSync(html, { width: 560, height: 230 });
```

![Bài viết với tiêu đề, dòng meta màu xám, đoạn văn có chữ đậm, nghiêng, tô sáng và một lần ngắt dòng](/img/guide/html-and-tailwind-article.png)

Những điều cần để ý trong kết quả:

- `<strong>`, `<em>` và `<mark>` nhận style user-agent của chúng; `<br>` ngắt dòng.
- `&nbsp;`, `&middot;`, `&mdash;`, `&amp;`, `&lt;`, `&copy;` được giải mã (hỗ trợ tham chiếu dạng số và
  338 tham chiếu có tên).
- `<code>` được vẽ bằng Inter: stylesheet user-agent yêu cầu `monospace`, nhưng tên họ font generic
  không được ánh xạ tới font nào, nên chữ rơi về các font đã đăng ký (xem [Font](./fonts.md)). Hãy đăng
  ký một font monospace và đặt `font-family` cho `code` nếu muốn khác.
- Khoảng trắng được gộp lại như trên trình duyệt.

### Style user-agent {#user-agent-styles}

Style user-agent của Chromium được áp dụng làm lớp thấp nhất (`preset` của node), nên HTML chưa style
trông giống trên trình duyệt: `div`, `p`, `h1`–`h6`, `ul`, `blockquote`, `table`, ... là block với
margin quen thuộc, `b` / `strong` in đậm, `i` / `em` in nghiêng, `u` gạch chân, `s` gạch ngang,
`small` nhỏ hơn, v.v.

<!-- @example html-and-tailwind#ua-styles -->
```js
// No stylesheet at all: the Chromium user-agent defaults give headings, paragraphs and lists their look
const uaPng = renderer.renderSync(`
  <div style="font-family: Inter; padding: 0 16px; background: white; height: 100%">
    <h2>Heading 2</h2>
    <p>A paragraph with <b>bold</b>, <i>italic</i>, <u>underline</u>, <s>strike</s> and <small>small</small> text.</p>
    <ul><li>first item</li><li>second item</li></ul>
    <blockquote>blockquote</blockquote>
  </div>`, { width: 560, height: 280 });
```

![HTML chưa style: tiêu đề đậm, đoạn văn có style inline, danh sách thụt lề không có dấu đầu dòng và một blockquote thụt lề](/img/guide/html-and-tailwind-ua-styles.png)

::: warning Không có ký hiệu đầu dòng
Các mục danh sách vẫn được dàn trang (với phần thụt lề của `ul` / `ol`) nhưng **không có dấu chấm hay
số nào được vẽ**: marker, `::marker` và counter CSS chưa được hiện thực ở 0.1.0. Nếu cần, hãy tự vẽ
bằng `::before` hoặc một phần tử inline.
:::

Style user-agent chỉ áp dụng cho source HTML. Đặt `tagName: "h1"` trên node tree giúp node khớp với
selector `h1` nhưng không làm nó đậm hay to lên (giống takumi).

### Fragment và tài liệu {#fragments-and-documents}

Một fragment (`<div>...</div>`) được render nguyên trạng. Một tài liệu đầy đủ (`<html><body>...`) nhận
mặc định `body { margin: 8px }`, đúng như một trang web trên trình duyệt:

<!-- @example html-and-tailwind#document-mode -->
```js
const firstBox = (source) => renderer.measureSync(source, { width: 400, height: 300 }).children[0];
firstBox("<div><div style='height:10px'></div></div>").transform; // [1,0,0,1,0,0] – a fragment: no body margin
firstBox("<html><body><div style='height:10px'></div></body></html>").transform; // [1,0,0,1,8,8] – body has an 8px margin
```

Fragment có nhiều phần tử cấp cao nhất được bọc trong một root ẩn danh phủ kín canvas. Giống node
tree, root không tự giãn theo canvas: hãy đặt `width: 100%; height: 100%` cho phần tử ngoài cùng (hoặc
một rule `<style>`) để nó phủ kín.

### Thuộc tính {#attributes}

| Thuộc tính | Tác dụng |
|:--|:--|
| `style="..."` | khai báo inline theo cú pháp CSS thường (kebab-case); khai báo không hợp lệ bị bỏ, không ném lỗi |
| `class`, `id`, mọi thuộc tính khác | dùng được cho selector của stylesheet (`.x`, `#x`, `[data-x=y]`); `attr()` trong `content` |
| `tw="..."` | class Tailwind ([bên dưới](#tailwind)) |
| `dir`, `lang` | hướng chữ và ngôn ngữ (`:dir()`, `:lang()`, bidi trên `full`) |
| `width`, `height` trên `img` / `svg` | gợi ý kích thước trình bày |
| `src` trên `img` | URL `data:` hoặc một key của option `images` |

### Ảnh và SVG inline {#images-and-inline-svg}

`<img src>` không bao giờ tải gì về: giá trị là key tra cứu trong option render `images`, hoặc một URL
`data:`. Phần tử `<svg>` inline được render như một ảnh SVG. Key không tồn tại thì không vẽ gì (không
báo lỗi); phần tử vẫn giữ `width` / `height` của nó.

<!-- @example html-and-tailwind#images-svg -->
```js
const logo = readFileSync("docs/public/favicon.svg"); // any PNG / JPEG / WebP / GIF / SVG bytes
const imgPng = renderer.renderSync(`
  <div style="display:flex; align-items:center; gap:20px; padding:20px; background:#0f172a; height:100%">
    <img src="logo.svg" width="64" height="64">
    <svg width="64" height="64" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" fill="#f472b6"/></svg>
    <img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'%3E%3Crect width='10' height='10' rx='2' fill='%2338bdf8'/%3E%3C/svg%3E" width="64" height="64">
    <img src="https://example.com/never-fetched.png" width="64" height="64" style="background:#334155">
  </div>`, {
  width: 400,
  height: 104,
  images: [{ src: "logo.svg", data: logo }], // <img src> is a lookup key into `images`
});
```

![Bốn ô vuông: favicon lấy từ images, hình tròn SVG inline màu hồng, SVG dạng data URL màu xanh và một ô xám trống cho URL không được tải](/img/guide/html-and-tailwind-images.png)

Thêm về nguồn ảnh và bộ giải mã: [Ảnh](./images.md).

### Những gì bị bỏ qua {#what-is-ignored}

`<script>` (không bao giờ chạy), nội dung `<template>`, comment, và mọi thứ trong `<head>` trừ
`<style>` đều không tạo ra box nào. Không có gì được tải về: `<link rel="stylesheet">`,
`@import url(...)` và URL trong `@font-face` đều không được nạp.

<!-- @example html-and-tailwind#ignored -->
```js
// <script>, <head> content, comments and the hidden attribute
const ignoredPng = renderer.renderSync(`
  <html><head><title>not drawn</title><style>p { color: #059669 }</style></head>
  <body style="margin:0; font-family:Inter; padding: 12px; background:white">
    <script>document.body.innerHTML = "never runs"</script>
    <!-- a comment -->
    <p style="margin:0">Body content is drawn.</p>
    <p hidden style="margin:0">hidden attribute: still drawn in 0.1.0</p>
  </body></html>`, { width: 400, height: 70 });
```

![Hai dòng chữ xanh lá: đoạn văn trong body và đoạn có thuộc tính hidden](/img/guide/html-and-tailwind-ignored.png)

::: warning Thuộc tính `hidden` không được tôn trọng
Phần tử có `hidden` vẫn được vẽ (style user-agent không có rule `[hidden] { display: none }`), giống
takumi. Hãy dùng `style="display:none"` thay thế.
:::

Cũng chưa được hiện thực (cùng các lỗ hổng như trình parse của takumi): thuật toán adoption agency cho
thẻ định dạng lồng sai, foster parenting cho nội dung lạc trong bảng, MathML, và điều khiển form như
widget (`<input>`, `<button>`, `<select>` chỉ là box thường).

## Tailwind {#tailwind}

Đặt class vào trường `tw` của node, hoặc thuộc tính `tw="..."` trong HTML. Chúng được biên dịch thành
khai báo CSS lúc render và cần profile `standard` hoặc `full`. Trình biên dịch là bản port tập con
Tailwind v4 của takumi: 656 trên 657 chuỗi class trong bài kiểm tra tương đương biên dịch ra cùng khai
báo như takumi.

<!-- @example html-and-tailwind#tw-node -->
```js
const twPng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col justify-between w-full h-full p-6 bg-linear-to-br from-indigo-600 to-fuchsia-600",
  style: { fontFamily: "Inter" },
  children: [
    { type: "text", tw: "text-sm font-bold uppercase tracking-widest text-white/70", text: "Tailwind on nodes" },
    { type: "text", tw: "text-3xl font-bold text-white leading-tight", text: "Utility classes compiled at render time" },
    {
      type: "container",
      tw: "flex gap-2",
      children: ["flex", "p-6", "bg-linear-to-br", "text-white/70"].map((c) => ({
        type: "text", tw: "px-3 py-1 rounded-full bg-white/20 text-white text-xs", text: c,
      })),
    },
  ],
}, { width: 560, height: 200 });
```

![Thẻ gradient tím sang đỏ tươi với nhãn chữ hoa, tiêu đề trắng lớn và bốn viên thuốc trong mờ](/img/guide/html-and-tailwind-tw-node.png)

### `tw`, không phải `class` {#tw-not-class}

Trong HTML chỉ thuộc tính `tw` mới đi vào trình biên dịch Tailwind. `class` dành cho selector của
stylesheet, nên tên class Tailwind đặt trong `class` không có tác dụng gì trừ khi một stylesheet định
nghĩa nó (đã kiểm tra ở 0.1.0):

<!-- @example html-and-tailwind#tw-html -->
```js
// In HTML the attribute is tw="..."; class="..." only feeds stylesheet selectors
const twHtmlPng = renderer.renderSync(`
  <div tw="flex items-center gap-4 w-full h-full px-6 bg-emerald-50" style="font-family: Inter">
    <div tw="w-12 h-12 rounded-xl bg-emerald-500"></div>
    <div tw="flex flex-col">
      <span tw="text-xl font-bold text-emerald-900">tw attribute</span>
      <span class="text-xl text-red-600">class attribute: not Tailwind</span>
    </div>
  </div>`, { width: 460, height: 100 });
```

![Ô vuông xanh lá, tiêu đề đậm từ tw và một dòng chữ đen thường vì class không có tác dụng](/img/guide/html-and-tailwind-tw-html.png)

Node tree cũng vậy: `className: "flex p-4"` là tên class cho selector, không phải Tailwind.

### Các nhóm utility được hỗ trợ {#supported-utility-families}

| Nhóm | Ví dụ |
|:--|:--|
| Layout và display | `flex`, `grid`, `block`, `inline-block`, `hidden`, `contents`, `overflow-hidden`, `object-cover` |
| Định vị | `relative`, `absolute`, `inset-0`, `top-4`, `-left-2` |
| Kích thước | `w-64`, `h-full`, `size-12`, `min-w-0`, `max-w-md`, `aspect-video` |
| Khoảng cách | `p-6`, `px-3`, `mt-2`, `-mb-1`, `gap-4`, `gap-x-2` |
| Flex và grid | `flex-col`, `flex-wrap`, `grow`, `shrink-0`, `basis-1/2`, `items-center`, `justify-between`, `self-end`, `grid-cols-3`, `col-span-2` |
| Typography | `text-3xl`, `text-slate-700`, `font-bold`, `leading-tight`, `tracking-wide`, `uppercase`, `truncate`, `line-clamp-2`, `whitespace-nowrap`, `underline`, `decoration-wavy` |
| Nền | `bg-sky-500`, `bg-white/20`, `bg-linear-to-br from-indigo-600 via-... to-fuchsia-600`, `bg-radial`, `bg-conic`, `bg-cover` |
| Viền | `border`, `border-2`, `border-dashed`, `border-slate-300`, `rounded-xl`, `rounded-t-lg`, `outline-2 outline-solid` (riêng `outline-2` không vẽ gì) |
| Hiệu ứng | `shadow-lg`, `inset-shadow-sm`, `text-shadow-md`, `opacity-50`, `mix-blend-multiply`, `bg-blend-overlay`, `mask-[linear-gradient(black,transparent)]` (các utility mask có tên của v4 như `mask-b-from-50%` không có tác dụng) |
| Filter | `blur-sm`, `grayscale`, `drop-shadow-md`, `backdrop-blur-md` (`backdrop-blur` trần kiểu v3 không có tác dụng) |
| Transform | `rotate-6`, `scale-95`, `translate-x-4`, `origin-top-left` |

Giá trị lấy từ theme mặc định của Tailwind: thang khoảng cách (`p-4` = 16px), toàn bộ bảng màu với
modifier `/opacity` (`bg-red-500/50`), cỡ chữ kèm line height (`text-sm` = 14px / 20px), bo góc, bóng
đổ và breakpoint.

### Giá trị tùy ý {#arbitrary-values}

Ngoặc vuông nhận mọi giá trị CSS; dấu gạch dưới thay cho dấu cách:

<!-- @example html-and-tailwind#arbitrary -->
```js
const arbitraryPng = renderer.renderSync({
  type: "container",
  tw: "flex items-center justify-center w-full h-full bg-[#0b1020]",
  children: [{
    type: "text",
    tw: "px-[18px] py-[6px] rounded-[10px] border-2 border-[rgb(250_204_21)] text-[26px] text-[#facc15] tracking-[0.2em]",
    style: { fontFamily: "Inter" },
    text: "ARBITRARY",
  }],
}, { width: 400, height: 90 });
```

![Nhãn ARBITRARY viền vàng trên nền gần đen](/img/guide/html-and-tailwind-arbitrary.png)

Thuộc tính tùy ý (`[width:30px]`), cú pháp rút gọn `(--var)` và `var()` trong ngoặc vuông
(`bg-[var(--brand)]`) chưa được hỗ trợ — xem [Những gì Tailwind không làm](#what-tailwind-does-not-do).

### Variant {#variants}

| Variant | Áp dụng khi |
|:--|:--|
| `sm:` `md:` `lg:` `xl:` `2xl:` | canvas rộng ít nhất 640 / 768 / 1024 / 1280 / 1536 CSS px |
| `first:` `last:` `only:` `odd:` `even:` | vị trí giữa các anh em |
| `first-of-type:` `last-of-type:` `only-of-type:` `empty:` `nth-*:` `not-*:` `[&:...]:` | cấu trúc, như Tailwind |
| `before:` `after:` | style pseudo-element `::before` / `::after` (`content-['...']` cho nó nội dung chữ) |

<!-- @example html-and-tailwind#variants -->
```js
const rows = ["Plan", "Seats", "Total", "Due"];
const variantsPng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col w-full h-full p-4 bg-white",
  style: { fontFamily: "Inter" },
  children: [
    {
      type: "text",
      tw: "text-lg font-bold mb-2 after:content-['NEW'] after:ml-2 after:px-2 after:rounded after:bg-amber-300 after:text-xs",
      text: "Structural variants",
    },
    {
      type: "container",
      tw: "flex flex-col",
      // structural variants: use container rows (or a tagName): a bare text node is not an element for them
      children: rows.map((r) => ({
        type: "container",
        tw: "flex px-3 py-1 text-sm bg-slate-100 odd:bg-sky-100 first:rounded-t-lg last:rounded-b-lg last:font-bold",
        children: [{ type: "text", text: r }],
      })),
    },
  ],
}, { width: 400, height: 190 });
```

![Tiêu đề kèm huy hiệu NEW màu hổ phách từ after:, và bốn hàng xen kẽ màu xanh, hàng đầu và cuối bo góc, hàng cuối in đậm](/img/guide/html-and-tailwind-variants.png)

::: warning Variant cấu trúc trên node text trần
Node `text` không có `tagName` không phải là phần tử đối với `first:`, `last:`, `odd:` và các variant
tương tự (cũng như `:first-child` trong stylesheet), giống takumi: nó không được tính vào các anh em, nên
khi nhiều node text trần đứng cạnh nhau thì **node nào** cũng khớp `first:`, `last:` và `odd:`. Đó là lý
do các hàng ở trên là container có một node text con; đặt `tagName` (ví dụ `"div"`) cho node text cũng
được. Phần tử HTML không bị ảnh hưởng.
:::

Breakpoint so sánh với chiều rộng canvas tính bằng CSS px:

<!-- @example html-and-tailwind#breakpoints -->
```js
const responsive = { type: "container", tw: "block h-2 w-10 sm:w-20 md:w-40" };
renderer.measureSync(responsive, { width: 600, height: 10 }).width; // 40  – sm (≥ 640px) does not match a 600px canvas…
renderer.measureSync(responsive, { width: 700, height: 10 }).width; // 80  – …sm matches at 700px
renderer.measureSync(responsive, { width: 800, height: 10 }).width; // 160 – md (≥ 768px)
```

### Xung đột và độ ưu tiên {#conflicts-and-precedence}

Giống Tailwind, thứ tự class trong chuỗi không quan trọng: thứ tự sắp xếp riêng của trình biên dịch
quyết định. Utility cho một cạnh thắng utility chung, và giữa hai utility cho cùng thuộc tính (như hai
màu nền) thì utility đứng sau theo thứ tự bảng chữ cái thắng (`bg-red-500 bg-blue-500` ra màu đỏ).

<!-- @example html-and-tailwind#conflicts -->
```js
const w = (tw, style) => renderer.measureSync({ type: "container", tw, style }, { width: 400, height: 50 });
w("block pt-2 p-4").height; // 24 – pt-2 (8) + bottom p-4 (16): the side-specific utility wins…
w("block p-4 pt-2").height; // 24 – …whatever the class order
w("block w-20 h-1", { width: 40 }).width;  // 40 – inline style beats tw
w("block !w-20 h-1", { width: 40 }).width; // 80 – unless the utility is !important
```

So với các nguồn style khác: `style` inline thắng `tw`, rule stylesheet không thuộc layer thắng `tw`, `tw`
thắng rule nằm trong `@layer` có tên, và utility có tiền tố `!` thắng mọi khai báo thường lẫn rule
`!important` không thuộc layer (chỉ rule `!important` trong layer có tên mới thắng nó). Xem
[Style](./styles.md#how-the-layers-combine).

### Preflight {#preflight}

Mặc định không áp dụng Tailwind Preflight, nên phần tử HTML giữ margin user-agent và cỡ tiêu đề. Thêm
`@import "tailwindcss";` vào `css` để bật Preflight — nó xóa margin và đặt lại cỡ chữ, độ đậm của tiêu
đề:

<!-- @example html-and-tailwind#preflight -->
```js
const page = `<div style="font-family: Inter; background: white; height: 100%; padding: 0 12px"><h1>Heading</h1><p>Paragraph</p></div>`;
const withoutPreflight = renderer.renderSync(page, { width: 280, height: 160 });
const withPreflight = renderer.renderSync(page, { width: 280, height: 160, css: ['@import "tailwindcss";'] });
```

| mặc định | với `@import "tailwindcss";` |
|:-:|:-:|
| ![Tiêu đề lớn đậm có margin phía trên đoạn văn](/img/guide/html-and-tailwind-preflight-off.png) | ![Tiêu đề và đoạn văn cùng kiểu chữ thường, không margin](/img/guide/html-and-tailwind-preflight-on.png) |

### Biến theme {#theme-variables}

`@theme { ... }` trong stylesheet định nghĩa biến theme. Utility đọc các biến này, như Tailwind v4: màu
(`--color-*`, cả khi có modifier `/opacity`), `--spacing` và `--spacing-*`, `--container-*`, `--radius-*`,
`--text-*` (kèm biến `--text-*--line-height` đi cùng), `--font-*`, `--font-weight-*`, `--tracking-*`,
`--leading-*`, `--aspect-*`, `--animate-*` và `--breakpoint-*`; định nghĩa lại một giá trị mặc định
(`--color-red-500`) sẽ đổi `bg-red-500`. Các biến cũng được khai báo trên `:root`, nên `var()` đọc được
chúng trong CSS và style inline:

<!-- @example html-and-tailwind#theme -->
```js
// @theme variables feed the utilities (bg-brand-500, bg-brand-500/15, rounded-card, text-hero,
// font-display, ...) and are also custom properties on :root, so var() can read them.
const theme = `@theme {
  --color-brand-500: #7c3aed;
  --radius-card: 14px;
  --text-hero: 28px;
  --text-hero--line-height: 34px;
  --font-display: Inter;
}`;
const themePng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col items-center justify-center gap-2 w-full h-full bg-brand-500/15 font-display",
  children: [
    { type: "text", text: "@theme → utilities", tw: "text-hero font-bold text-brand-500" },
    { type: "container", tw: "flex px-4 py-1 rounded-card bg-brand-500",
      children: [{ type: "text", text: "rounded-card bg-brand-500", tw: "text-sm text-white" }] },
    { type: "text", text: "var(--color-brand-500) in a style", tw: "text-sm", style: { color: "var(--color-brand-500)" } },
  ],
}, { width: 340, height: 140, css: [theme] });
```

![Một thẻ tím nhạt có tiêu đề lớn màu tím, một viên thuốc bo tròn màu tím và một dòng chữ tím, tất cả lấy màu từ một biến @theme](/img/guide/html-and-tailwind-theme.png)

Utility `animate-*`, kể cả tên lấy từ `--animate-*`, cần profile `full`; xem
[Animation](./animation.md#tên-dựng-sẵn-và-tailwind).

### Những gì Tailwind không làm {#what-tailwind-does-not-do}

Đã kiểm tra với package. takumi cũng không hỗ trợ bất kỳ mục nào sau đây:

<!-- @example html-and-tailwind#tw-gaps -->
```js
const px = (tw, css) => {
  const raw = renderer.renderSync({ type: "container", tw: `block w-4 h-4 ${tw}` }, { width: 16, height: 16, format: "raw", css });
  return raw[3] === 0 ? "transparent" : "painted";
};
px("bg-red-500");                                          // painted
px("bg-linear-to-r from-red-500 to-blue-500");             // painted
px("bg-gradient-to-r from-red-500 to-blue-500");           // transparent – Tailwind v3 name, not supported
px("bg-brand-500", ["@theme { --color-brand-500: red }"]);  // painted – utilities read @theme variables
px("bg-[var(--brand)]", [":root { --brand: red }"]);        // transparent – var() inside [...] is not supported
px("bg-(--brand)", [":root { --brand: red }"]);             // transparent – nor the (--var) shorthand
px("hover:bg-red-500");                                    // transparent – hover / focus / dark never apply
```

- **Tên của Tailwind v3**: `bg-gradient-to-*` không biên dịch ra gì; hãy dùng `bg-linear-to-*` của v4
  (cùng `from-*` / `via-*` / `to-*`), `bg-radial`, `bg-conic`.
- **Variant tương tác và môi trường**: `hover:`, `focus:`, `dark:`, `group-*:`, `peer-*:`, breakpoint
  `max-*:`.
- **Utility**: `z-*`, `order-*`, `skew-*`, `ring-*`, `space-x-*` / `space-y-*` (dùng `gap-*`),
  `divide-*`, `place-*`, `cursor-*`; `outline-2` không kèm kiểu outline, `backdrop-blur` không kèm cỡ,
  `mask-b-from-50%`.
- **Cú pháp**: thuộc tính tùy ý (`[width:30px]`), rút gọn `(--var)`, `var()` trong ngoặc vuông
  (`bg-[var(--x)]`, `w-[var(--w)]`), `@apply` trong stylesheet, `@utility`, `@plugin`, `@config`.
- **Thuộc tính `class`**: trong HTML chỉ `tw="..."` được biên dịch thành Tailwind (xem [ở trên](#tailwind)).
- Class không biết bị bỏ qua lặng lẽ; không có gì ném lỗi.

Nếu cần nhiều Tailwind hơn, hãy biên dịch class bằng Tailwind thật trong bước build rồi truyền CSS sinh
ra qua `css`; khi đó engine stylesheet áp dụng phần CSS mà nó hỗ trợ, khớp phần tử qua `class` (HTML)
hoặc `className` (node tree).

## Xem thêm {#see-also}

- [Style](./styles.md) — style inline, stylesheet, cascade và các chế độ layout
- [Hỗ trợ CSS](./css-support.md#đầu-vào-html) — bảng trạng thái HTML và Tailwind
- [Ảnh](./images.md) — nguồn ảnh cho `<img>`
- [bm-engine hoạt động thế nào](./concepts.md) — pipeline và ba loại đầu vào
