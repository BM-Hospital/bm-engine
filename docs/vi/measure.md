# measure()

[English](../en/measure.md) · [Tiếng Việt](measure.md)

`measure()` chạy cùng các bước style và layout như `render()` nhưng dừng trước khi vẽ và encode. Nó trả về
kích thước và vị trí của mọi hộp và mọi text run, đúng thứ bạn cần để co một tiêu đề cho vừa hộp, đặt kích
thước canvas theo nội dung, hoặc đặt một thứ gì đó cạnh phần chữ đã được dàn trang. Trang này giải thích
kết quả trả về, hệ toạ độ của nó, các giới hạn trong 0.1.0, và đi qua một ví dụ tiêu đề tự co nhỏ. Mọi ví
dụ đều được chạy bởi `docs/examples/measure.mjs`.

[[toc]]

## Cách gọi

```ts
renderer.measureSync(source, options?): MeasuredNode
renderer.measure(source, options?): Promise<MeasuredNode>
```

`source` và `options` giống hệt [`render`](./api.md#render--rendersync): một cây node, một chuỗi HTML
(`standard` / `full`), `{ json }` hoặc handle của `prepare()`, kèm `width`, `height`, `css`, `images`,
`fontFamilies`, `devicePixelRatio` và, với bản async, `fonts`. Các tuỳ chọn đầu ra (`format`, `quality`)
bị bỏ qua. Font phải được đăng ký y như khi render: chữ được đo khi không có font sẽ có chiều rộng bằng 0.

<!-- @example measure#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
```

## Kết quả

<!-- @example measure#basic -->
```js
const card = {
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 8, width: 320, padding: 16, fontFamily: "Inter", fontSize: 16 },
  children: [
    { type: "text", text: "Release notes", style: { fontSize: 24, fontWeight: 700 } },
    { type: "text", text: "Faster PNG encoding and a smaller core build." },
  ],
};
const measured = renderer.measureSync(card, { width: 400, height: 200 });
```

Cây kết quả cho tấm thẻ này (chép từ output của script):

```json
{
  "width": 320, "height": 109, "transform": [1, 0, 0, 1, 0, 0], "runs": [],
  "children": [
    { "width": 288, "height": 29, "transform": [1, 0, 0, 1, 16, 16], "children": [],
      "runs": [{ "x": 0, "y": 0, "width": 164.109375, "height": 29 }] },
    { "width": 288, "height": 40, "transform": [1, 0, 0, 1, 16, 53], "children": [],
      "runs": [{ "x": 0, "y": 0, "width": 265.84375, "height": 20 },
               { "x": 0, "y": 20, "width": 79.734375, "height": 20 }] }
  ]
}
```

| Trường | Ý nghĩa |
|:--|:--|
| `width`, `height` | **border box** của node, tính bằng pixel thiết bị (độ chính xác 1/64 px) |
| `transform` | `[a, b, c, d, e, f]`: ma trận 2D đặt hộp vào canvas; `e`, `f` là toạ độ x / y tuyệt đối của góc trên trái border box |
| `children` | các hộp con đã đo, theo thứ tự trong cây |
| `runs` | các text run mà hộp này dàn trang: `{ x, y, width, height }` |

Ở đây hai text node là flex item, nên mỗi node là một hộp riêng (rộng 288 px, bằng content width của flex
container) và sở hữu các run của mình. Text thứ hai xuống thành hai dòng: hai run cách nhau 20 px (chiều
cao dòng của Inter cỡ 16 px).

## Hệ toạ độ

- `transform[4]` và `transform[5]` là toạ độ trên **canvas**, không tương đối với node cha: tiêu đề ở trên
  nằm tại (16, 16) do padding của thẻ, phần thân nằm tại (16, 53) = 16 + 29 + gap 8.
- `x` và `y` của một run tương đối với **content box** của hộp sở hữu nó, nên hãy cộng thêm border và
  padding của hộp đó (và vị trí `transform` của nó) để ra toạ độ trên canvas.
- `height` của run là chiều cao dòng, không phải phạm vi glyph; takumi báo chiều cao hộp glyph ở đây, nên
  giá trị khác nhau (vị trí và chiều rộng thì khớp).
- Trong 0.1.0 run không có trường `text` (run của takumi thì có). Nếu cần nội dung của từng dòng, hãy tự
  giữ ở phía bạn hoặc đo từng từ riêng.

### Hộp nào xuất hiện

Chỉ các hộp mới xuất hiện trong `children`: block container, flex item và grid item, inline-block, ảnh,
v.v. Chữ bên trong một block container (cùng các inline container, tức các "span", bao quanh nó) thuộc về
container đó: nó xuất hiện dưới dạng **run của container**, mỗi dòng **và mỗi đoạn inline** là một run:

<!-- @example measure#runs -->
```js
// Text inside a block container belongs to that container: there is no child for the
// text node, and every inline fragment on a line is a separate run.
const paragraph = {
  type: "container",
  style: { display: "block", width: 260, padding: 20, border: "4px solid #e2e8f0", fontFamily: "Inter", fontSize: 16 },
  children: [
    { type: "text", text: "Runs are reported per line and per inline " },
    { type: "container", style: { fontWeight: 700, color: "#dc2626" }, children: [{ type: "text", text: "fragment" }] },
    { type: "text", text: ", relative to the content box." },
  ],
};
const p = renderer.measureSync(paragraph, { width: 300, height: 140 });
// p.children: []   p.runs: [{ x: 0, y: 0, width: 196.359375, height: 20 }, ...] (5 runs)
```

Đoạn văn này sinh ra năm run trên ba dòng: dòng thứ hai bị tách thành "and per inline", chữ đậm
"fragment" và dấu phẩy. Inline-block và ảnh nằm trên dòng thì xuất hiện như các con, với transform riêng.

### Vẽ lớp phủ từ số đo

Vì transform là toạ độ tuyệt đối, bạn có thể biến số đo thành các hộp định vị tuyệt đối và vẽ chúng đè lên
cây gốc. Khung xanh là các hộp, hình chữ nhật đỏ là các run; run được dịch thêm bằng border và padding của
đoạn văn (4 + 20 px):

<!-- @example measure#overlay -->
```js
// Draw the measured geometry on top of the rendered tree: boxes in blue, text runs in red.
// Runs are relative to the owner's content box, so add its border + padding (here 4 + 20).
function overlay(node, m, contentOffset) {
  const boxes = [];
  const walk = (n, inset) => {
    const [, , , , x, y] = n.transform;
    boxes.push({ type: "container", style: { position: "absolute", left: x, top: y, width: n.width, height: n.height, border: "1px solid #2563eb" } });
    for (const r of n.runs) {
      boxes.push({ type: "container", style: { position: "absolute", left: x + inset + r.x, top: y + inset + r.y, width: r.width, height: r.height, backgroundColor: "rgba(239,68,68,0.25)" } });
    }
    n.children.forEach((c) => walk(c, 0));
  };
  walk(m, contentOffset);
  return { type: "container", style: { display: "block", position: "relative", width: "100%", height: "100%", backgroundColor: "#fff" }, children: [node, ...boxes] };
}
const overlayPng = renderer.renderSync(overlay(paragraph, p, 24), { width: 300, height: 140 });
```

![Một đoạn văn có hộp được viền xanh và mỗi text run được tô đỏ](/img/guide/measure-overlay.png)

Cùng kỹ thuật này dùng để đặt badge ngay sau dòng cuối của tiêu đề, vẽ dấu tô sáng phía sau những run cụ
thể, hoặc tạo chế độ xem debug cho layout.

## Kích thước nội dung và canvas vừa khít

Khi không có `width` / `height`, root được dàn trang theo kích thước max-content, và `render()` sẽ tạo ra
ảnh đúng kích thước đó (làm tròn lên số pixel nguyên). `measure()` cho bạn biết trước kích thước ấy:

<!-- @example measure#intrinsic -->
```js
// Without width / height the root is laid out at its max-content size: the result is
// the size the image would have if you rendered it without a canvas size.
const label = { type: "text", text: "Hello bm-engine", style: { fontFamily: "Inter", fontSize: 32, fontWeight: 700 } };
const { width, height } = renderer.measureSync(label); // { width: 258.71875, height: 39 }
const tight = renderer.renderSync(label); // a 259 × 39 PNG
```

![Nhãn đậm "Hello bm-engine" trên canvas trong suốt 259 x 39](/img/guide/measure-intrinsic.png)

Khi có `width` / `height`, kích thước phần trăm, `vw` / `vh` và các truy vấn `@media` được tính theo chúng,
giống như khi render.

## Ví dụ: tiêu đề tự co nhỏ

Hàm dưới đây dùng tìm kiếm nhị phân để tìm cỡ chữ lớn nhất mà tiêu đề vẫn nằm vừa trong hai dòng của một
hộp rộng 200 px. Mỗi bước là một lần gọi `measureSync`; số dòng là số vị trí `y` khác nhau của các run. Sau
đó ba tấm thẻ được render với các cỡ chữ tìm được:

<!-- @example measure#fit -->
```js
// Auto-shrink: the largest font size (between min and max) at which the title fits
// in `maxLines` lines of a box `boxWidth` px wide. Each probe is a layout-only measure.
function fitFontSize(text, { boxWidth, maxLines, min = 12, max = 64, fontWeight = 700 }) {
  const lines = (fontSize) => {
    const m = renderer.measureSync(
      { type: "container", style: { display: "block", width: boxWidth, fontFamily: "Inter", fontWeight, fontSize, lineHeight: 1.15 },
        children: [{ type: "text", text }] },
      { width: boxWidth, height: 1000 },
    );
    return new Set(m.runs.map((r) => r.y)).size; // distinct line positions
  };
  let lo = min, hi = max;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (lines(mid) <= maxLines) lo = mid; else hi = mid - 1;
  }
  return lo;
}

const titles = ["Ship it", "Rendering OG images in WebAssembly", "A much longer headline that has to shrink before it fits in two lines"];
const cards = titles.map((title) => {
  const fontSize = fitFontSize(title, { boxWidth: 200, maxLines: 2 });
  return {
    type: "container",
    style: { display: "flex", flexDirection: "column", justifyContent: "space-between", width: 232, height: 150, padding: 16, borderRadius: 12, backgroundColor: "#1e1b4b", color: "#fff", fontFamily: "Inter" },
    children: [
      { type: "text", text: title, style: { fontSize, fontWeight: 700, lineHeight: 1.15 } },
      { type: "text", text: `fontSize ${fontSize}px`, style: { fontSize: 13, color: "#a5b4fc" } },
    ],
  };
});
const fitted = renderer.renderSync(
  { type: "container", style: { display: "flex", gap: 12, padding: 12, width: "100%", height: "100%", backgroundColor: "#f1f5f9" }, children: cards },
  { width: 744, height: 174 },
);
```

![Ba tấm thẻ: "Ship it" cỡ 64px, "Rendering OG images in WebAssembly" cỡ 18px và một tiêu đề dài cỡ 12px, mỗi tiêu đề chiếm tối đa hai dòng](/img/guide/measure-fit.png)

Mẹo khi co chữ:

- Đo đúng các style bạn sẽ render (cùng font family, độ đậm, `lineHeight`, letter spacing, chiều rộng).
  `lineHeight` khác đi sẽ làm thay đổi cả số dòng lẫn chiều cao.
- Đếm dòng bằng các `y` khác nhau đúng với chữ thuần. Với nội dung inline trộn lẫn, một dòng có thể có
  nhiều run, vì vậy ví dụ dùng `Set`.
- Muốn co theo chiều cao thay vì số dòng, hãy so `height` của root với khoảng trống bạn có.
- Tìm trong khoảng 12–64 px cần khoảng sáu lần đo. Các lần gọi chỉ-layout bỏ qua bước vẽ và encode PNG,
  thường là phần lớn thời gian của một lần render (xem [Hiệu năng](./performance.md)).
- Với tiêu đề một dòng, hãy đo một lần ở cỡ tham chiếu rồi nhân tỉ lệ: chiều rộng của chữ không xuống
  dòng tỉ lệ với cỡ chữ, sai khác chỉ do làm tròn.

## Device pixel ratio

Mọi giá trị đều tính bằng **pixel thiết bị**: `devicePixelRatio` nhân các độ dài CSS và cỡ chữ, nên một hộp
100 px đo được 200 khi tỉ lệ là 2:

<!-- @example measure#dpr -->
```js
// Results are in device pixels: devicePixelRatio scales CSS lengths and font sizes.
const box = { type: "container", style: { display: "block", width: 100, height: 20 } };
renderer.measureSync(box, { width: 300, height: 100 }).width; // 100
renderer.measureSync(box, { width: 300, height: 100, devicePixelRatio: 2 }).width; // 200
```

Chữ không phải lúc nào cũng nhân đúng tỉ lệ: chiều cao dòng lấy từ metric của font ở cỡ đã nhân và được
làm tròn theo từng cỡ (phần thân của [mục kết quả](#kết-quả) có dòng cao 20 px ở tỉ lệ 1 và 39 px ở tỉ lệ
2, không phải 40). Chia cho tỉ lệ để ra pixel CSS.

## Transform không được tính vào

::: warning Giới hạn của 0.1.0
`transform` chỉ chứa vị trí của hộp. CSS transform (`transform`, `translate`, `rotate`, `scale`) **không**
được áp vào ma trận; còn độ dời của `position: relative` thì có, vì nó là một phần của layout. takumi có
tính CSS transform vào ma trận này.
:::

<!-- @example measure#transforms -->
```js
// transform holds the box position only: CSS transforms (rotate, scale, translate) are not
// included in the matrix in 0.1.0; position: relative offsets are.
const moved = renderer.measureSync(
  { type: "container", style: { display: "flex", width: 300, height: 100 }, children: [
    { type: "container", style: { width: 50, height: 50, transform: "translate(10px, 20px) rotate(45deg)" } },
    { type: "container", style: { width: 50, height: 50, position: "relative", left: 7, top: 3 } },
  ] },
);
// moved.children[0].transform: [1, 0, 0, 1, 0, 0]
// moved.children[1].transform: [1, 0, 0, 1, 57, 3]
```

Nếu cần vị trí thực sự được vẽ của một hộp có transform, hãy tự áp transform đó quanh `transform-origin`
của nó (mặc định là tâm border box).

## HTML và stylesheet

Chuỗi HTML và tuỳ chọn `css` hoạt động giống như khi render (cần `standard` hoặc `full`). Root của kết quả
là phần tử gốc của HTML:

<!-- @example measure#html -->
```js
// HTML strings and stylesheets measure exactly like they render (standard / full).
const fromHtml = renderer.measureSync(
  `<div class="card"><h1>Title</h1><p>Body text</p></div>`,
  { width: 400, height: 300, css: [".card { display: flex; flex-direction: column; padding: 12px; font-family: Inter } h1, p { margin: 0 }"] },
);
// fromHtml is the .card box; fromHtml.children are the h1 and p boxes (canvas coordinates)
```

## Lỗi và các trường hợp biên

- Đo sẽ ném lỗi vì cùng những lý do như render: giá trị style inline không hợp lệ, profile thiếu tính
  năng (HTML trên `core`), node sai định dạng. Xem [API: lỗi](./api.md#lỗi).
- Nội dung có kích thước bằng 0 và không có `width` / `height` sẽ ném
  `invalid viewport: content has zero size and no width/height was given`.
- Phần tử có `display: "none"` vẫn xuất hiện trong `children` dưới dạng mục 0 × 0 tại (0, 0), để chỉ số
  của các con vẫn khớp với cây node.

Xem thêm: [Tham chiếu API](./api.md#measure--measuresync), [Typography](./typography.md), [Font](./fonts.md).
