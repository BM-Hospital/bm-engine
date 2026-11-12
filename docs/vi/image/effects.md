# Hiệu ứng

[English](../../en/image/effects.md) · [Tiếng Việt](effects.md)

Các hiệu ứng hình ảnh mà bm-engine vẽ được: gradient, viền và bo góc, outline, bóng đổ của box và của chữ,
chữ gradient và viền chữ, filter, opacity, transform 2D, clip path, mask, blend mode và backdrop filter.
Mỗi phần có một ví dụ nhỏ và ghi rõ profile cần dùng; đa số hiệu ứng có trên mọi profile, còn clip-path,
mask, blend mode, backdrop-filter và các không gian màu hiện đại cần **standard** hoặc **full**
(`features.effects`, `features.modernColor`). Mọi ví dụ là các đoạn của `docs/examples/effects.mjs` trong
repository và hình là kết quả của nó.

- [Chuẩn bị](#chuẩn-bị)
- [Gradient](#gradient) · [Không gian màu](#không-gian-màu)
- [Viền và border-radius](#viền-và-border-radius) · [Outline](#outline)
- [Bóng đổ của box](#bóng-đổ-của-box)
- [Hiệu ứng chữ](#hiệu-ứng-chữ)
- [Filter](#filter)
- [Opacity](#opacity)
- [Transform](#transform)
- [clip-path](#clip-path)
- [Mask](#mask)
- [Blend mode](#blend-mode)
- [backdrop-filter](#backdrop-filter)
- [Tóm tắt theo profile](#tóm-tắt-theo-profile)

## Chuẩn bị

Các ví dụ render trên điểm vào `full` và dùng hai hàm phụ nhỏ: `tile(label, style, children)` vẽ một ô
130 × 90 có nhãn và `grid(tiles)` xếp các ô thành hàng.

<!-- @example effects#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

// A labelled demo tile and a wrapping grid of tiles, used by every example below.
const tile = (label, style, children = []) => ({
  type: "container",
  style: { display: "flex", flexDirection: "column", alignItems: "center", gap: 6 },
  children: [
    { type: "container", style: { display: "flex", width: 130, height: 90, alignItems: "center", justifyContent: "center", ...style }, children },
    { type: "text", text: label, style: { fontSize: 12, color: "#334155" } },
  ],
});
const grid = (tiles, background = "#f8fafc") => ({
  type: "container",
  style: { display: "flex", flexWrap: "wrap", gap: 18, padding: 18, width: "100%", height: "100%", backgroundColor: background, fontFamily: "Inter" },
  children: tiles,
});
```

## Gradient

`linear-gradient()`, `radial-gradient()`, `conic-gradient()` và các biến thể `repeating-*` dùng được
trong `backgroundImage` trên mọi profile, và trong `maskImage` trên standard / full (`border-image` hoàn
toàn không được hỗ trợ). Các điểm dừng màu nhận vị trí, vị trí kép (`#facc15 33% 66%`) để tạo điểm dừng
cứng, và hint. Có thể chồng nhiều lớp bằng dấu phẩy; lớp đầu tiên nằm trên cùng.

<!-- @example effects#gradients -->
```js
const gradients = renderer.renderSync(grid([
  tile("linear-gradient", { backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)" }),
  tile("hard stops", { backgroundImage: "linear-gradient(90deg, #ef4444 33%, #facc15 33% 66%, #22c55e 66%)" }),
  tile("radial-gradient", { backgroundImage: "radial-gradient(circle at 30% 30%, #fde68a, #f59e0b 40%, #7c2d12)" }),
  tile("conic-gradient", { backgroundImage: "conic-gradient(from 90deg, #22d3ee, #a855f7, #f43f5e, #22d3ee)" }),
  tile("repeating-linear", { backgroundImage: "repeating-linear-gradient(45deg, #0f172a 0 10px, #fbbf24 10px 20px)" }),
  tile("repeating-radial", { backgroundImage: "repeating-radial-gradient(circle, #e0e7ff 0 8px, #6366f1 8px 16px)" }),
  tile("repeating-conic", { backgroundImage: "repeating-conic-gradient(#0f172a 0 25%, #f1f5f9 0 50%)", backgroundSize: "30px 30px" }),
  tile("layers", { backgroundColor: "#0b1020", backgroundImage: "radial-gradient(ellipse 80% 60% at 70% 20%, rgba(139,92,246,.8), transparent 70%), radial-gradient(ellipse 70% 60% at 20% 80%, rgba(236,72,153,.7), transparent 70%)" }),
]), { width: 640, height: 260 });
```

![Gradient tuyến tính, điểm dừng cứng, radial, conic, repeating linear, repeating radial, repeating conic và hai gradient radial chồng lớp](/img/guide/effects-gradients.png)

Ghi chú:

- Hướng: góc (`135deg`, `0.25turn`) và từ khóa (`to right`, `to bottom left`). Gradient radial nhận
  `circle` / `ellipse`, kích thước (`closest-side`, `farthest-corner`, độ dài, phần trăm) và
  `at <position>`; gradient conic nhận `from <angle>` và `at <position>`.
- `backgroundSize` và `backgroundRepeat` lát gradient giống như ảnh (ô bàn cờ là một
  `repeating-conic-gradient` cỡ `30px 30px`).
- Phần bên trong gradient có thể lệch takumi một mức màu (benchmark: 7 / 7 fixture gradient tương
  đương).

### Không gian màu

Trên `standard` và `full`, gradient có thể nội suy trong không gian màu khác (`in oklab`, `in oklch`,
`in srgb-linear`, ... với `shorter` / `longer hue`), và màu có thể viết bằng `oklch()`, `oklab()`,
`lab()`, `lch()`, `color()`, `color-mix()` và `light-dark()`:

<!-- @example effects#interpolation -->
```js
const interpolation = renderer.renderSync(grid([
  tile("sRGB (default)", { width: 280, backgroundImage: "linear-gradient(90deg, #2563eb, #facc15)" }),
  tile("in oklab", { width: 280, backgroundImage: "linear-gradient(in oklab 90deg, #2563eb, #facc15)" }),
  tile("in oklch longer hue", { width: 280, backgroundImage: "linear-gradient(in oklch longer hue 90deg, #ff5f6d, #ffc371)" }),
  tile("color-mix() / oklch()", { width: 280, backgroundImage: "linear-gradient(90deg, oklch(70% 0.2 145), color-mix(in oklab, #2563eb 40%, white))" }),
]), { width: 640, height: 260 });
```

![Cùng một gradient xanh sang vàng trong sRGB và trong oklab, dải cầu vồng oklch longer hue và các hàm màu hiện đại](/img/guide/effects-interpolation.png)

Trên `core`, không gian nội suy bị bỏ qua (gradient nội suy trong sRGB), còn các hàm màu hiện đại là giá
trị không hợp lệ: trong style inline chúng làm lần render throw `invalid value for style property ...`.

## Viền và border-radius

Mọi kiểu viền của CSS đều được vẽ trên mọi profile, theo bộ vẽ viền của Chromium:

<!-- @example effects#borders -->
```js
const borderStyles = ["solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset"];
const borders = renderer.renderSync(grid([
  ...borderStyles.map((s) => tile(s, { border: `8px ${s} #6366f1`, backgroundColor: "white" })),
]), { width: 640, height: 260 });
```

![Tám box với viền solid, dashed, dotted, double, groove, ridge, inset và outset](/img/guide/effects-borders.png)

`borderRadius` nhận một đến bốn giá trị, phần trăm và cú pháp elip với `/`; từng góc và các góc logic
(`borderStartStartRadius`, ...) đặt riêng được. Bo góc cắt nền, và với `overflow: "hidden"` thì cắt cả
các phần tử con:

<!-- @example effects#radius -->
```js
const radius = renderer.renderSync(grid([
  tile("borderRadius: 16", { borderRadius: 16, backgroundColor: "#0ea5e9" }),
  tile("50% (ellipse)", { borderRadius: "50%", backgroundColor: "#0ea5e9" }),
  tile("per corner", { borderRadius: "40px 0 40px 0", backgroundColor: "#0ea5e9" }),
  tile("elliptical 60px / 20px", { borderRadius: "60px / 20px", backgroundColor: "#0ea5e9" }),
  tile("radius + border", { borderRadius: 24, border: "6px solid #0369a1", backgroundColor: "#bae6fd" }),
  tile("mixed border colours", { borderRadius: 45, borderWidth: 10, borderStyle: "solid", borderColor: "#ef4444 #f59e0b #22c55e #3b82f6" }),
  tile("outline + offset", { borderRadius: 12, backgroundColor: "#fde68a", outline: "3px dashed #b45309", outlineOffset: 6 }),
  tile("overflow clip", { borderRadius: 30, overflow: "hidden", backgroundColor: "#e2e8f0", alignItems: "flex-start" },
    [{ type: "container", style: { width: 130, height: 40, backgroundColor: "#0f172a" } }]),
]), { width: 640, height: 260 });
```

![Các box bo góc: bán kính cố định, elip 50 %, bán kính từng góc, bán kính elip, bo góc có viền, bốn màu viền, outline có offset và cắt bằng overflow](/img/guide/effects-radius.png)

### Outline

`outline` (độ dày, kiểu, màu) được vẽ bên ngoài border box và đi theo bo góc; `outlineOffset` đẩy nó ra
xa (hoặc vào trong, với giá trị âm). `outlineOffset` dạng phần trăm chưa được hỗ trợ. Outline không chiếm
chỗ trong layout. Mọi profile.

## Bóng đổ của box

`boxShadow` nhận bao nhiêu bóng cũng được, với độ lệch, độ nhòe, spread, màu và `inset`; bóng đi theo bo
góc. Mọi profile.

<!-- @example effects#shadows -->
```js
const card = { backgroundColor: "white", borderRadius: 14 };
const shadows = renderer.renderSync(grid([
  tile("soft", { ...card, boxShadow: "0 10px 25px rgba(15,23,42,.25)" }),
  tile("hard offset", { ...card, border: "2px solid #0f172a", boxShadow: "6px 6px 0 #0f172a" }),
  tile("spread ring", { ...card, boxShadow: "0 0 0 6px #a5b4fc" }),
  tile("inset", { ...card, backgroundColor: "#e2e8f0", boxShadow: "inset 0 6px 14px rgba(0,0,0,.35)" }),
  tile("multiple", { ...card, boxShadow: "0 0 0 3px #f472b6, 0 0 0 7px #fbcfe8, 0 12px 20px rgba(0,0,0,.3)" }),
  tile("coloured glow", { ...card, backgroundColor: "#7c3aed", boxShadow: "0 0 30px 6px rgba(124,58,237,.7)" }),
], "#f1f5f9"), { width: 640, height: 260 });
```

![Bóng mềm, bóng lệch cứng, vòng spread, bóng inset, nhiều vòng chồng nhau và quầng sáng màu](/img/guide/effects-shadows.png)

Bóng spread không nhòe (`0 0 0 6px`) là cách thường dùng để vẽ một "vòng" quanh box mà không đổi kích
thước của nó (các utility `ring-*` của Tailwind không được hỗ trợ, xem
[HTML và Tailwind](./html-and-tailwind.md)).

## Hiệu ứng chữ

`textShadow` (nhiều bóng, có nhòe), `WebkitTextStroke` (chữ viền, kèm `paintOrder`), và chữ gradient
bằng `backgroundClip: "text"` cùng `color` trong suốt:

<!-- @example effects#text-effects -->
```js
const big = { fontSize: 40, fontWeight: 700 };
const text = (t, style) => ({ type: "text", text: t, style: { ...big, ...style } });
const textEffects = renderer.renderSync({
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 14, padding: 20, width: "100%", height: "100%", backgroundColor: "#0f172a", fontFamily: "Inter" },
  children: [
    text("Neon glow", { color: "#fff", textShadow: "0 0 6px #fff, 0 0 18px #ff2d95, 0 0 42px #ff2d95" }),
    text("Hard shadow", { color: "#fbbf24", textShadow: "3px 3px 0 #b91c1c" }),
    text("Outlined", { color: "transparent", WebkitTextStroke: "1.5px #38bdf8" }),
    { type: "container", style: { display: "flex" }, children: [
      text("Gradient text", { backgroundImage: "linear-gradient(90deg, #f97316, #ec4899, #8b5cf6)", backgroundClip: "text", color: "transparent" }),
    ] },
  ],
}, { width: 640, height: 280 });
```

![Chữ neon phát sáng, bóng chữ cứng, chữ viền và chữ gradient](/img/guide/effects-text-effects.png)

Cả bốn đều chạy trên mọi profile (chữ gradient cũng đã được kiểm tra trên `core`). Với chữ gradient, hãy
đặt text node trong một container không kéo giãn nó (hàng flex ở trên), nếu không gradient sẽ trải theo
cả chiều rộng bị kéo giãn. Gạch chân, `text-transform` và các phần typography khác có trong
[Typography](./typography.md).

## Filter

`filter` áp dụng cho phần tử và các con của nó: `blur()`, `brightness()`, `contrast()`, `grayscale()`,
`hue-rotate()`, `invert()`, `opacity()`, `saturate()`, `sepia()` và `drop-shadow()`, kết hợp tùy ý (áp
dụng theo thứ tự). Mọi profile. `filter: url(...)` (tham chiếu filter SVG) không được hỗ trợ.

<!-- @example effects#filters -->
```js
const sample = {
  backgroundImage: "linear-gradient(135deg, #ef4444, #facc15 50%, #22c55e)",
  borderRadius: 12,
};
const filters = renderer.renderSync(grid([
  tile("none", sample),
  tile("blur(4px)", { ...sample, filter: "blur(4px)" }),
  tile("grayscale(1)", { ...sample, filter: "grayscale(1)" }),
  tile("sepia(1)", { ...sample, filter: "sepia(1)" }),
  tile("hue-rotate(180deg)", { ...sample, filter: "hue-rotate(180deg)" }),
  tile("invert(1)", { ...sample, filter: "invert(1)" }),
  tile("brightness(.6) contrast(1.5)", { ...sample, filter: "brightness(.6) contrast(1.5)" }),
  tile("drop-shadow", { filter: "drop-shadow(4px 6px 3px rgba(0,0,0,.5))" },
    [{ type: "text", text: "★", style: { fontSize: 64, color: "#f59e0b" } }]),
]), { width: 640, height: 260 });
```

![Một box gradient không filter, blur, grayscale, sepia, hue-rotate, invert, brightness kèm contrast, và ngôi sao có drop-shadow](/img/guide/effects-filters.png)

`drop-shadow()` đi theo hình dạng alpha của nội dung (glyph ngôi sao), khác với `boxShadow` đi theo box.
Filter cũng dùng được cho image node (xem [Ảnh](./images.md#trang-trí-ảnh)).

## Opacity

`opacity` làm phần tử và mọi thứ bên trong nó trong suốt như một nhóm. Muốn chỉ nền trong suốt, hãy dùng
màu `rgba()` / `#rrggbbaa`. Mọi profile.

<!-- @example effects#opacity -->
```js
const opacity = renderer.renderSync(grid([
  tile("opacity: 1", { backgroundColor: "#2563eb" }),
  tile("opacity: .6", { backgroundColor: "#2563eb", opacity: 0.6 }),
  tile("opacity: .25", { backgroundColor: "#2563eb", opacity: 0.25 }),
  tile("rgba() background", { backgroundColor: "rgba(37,99,235,.25)" },
    [{ type: "text", text: "text stays opaque", style: { fontSize: 13 } }]),
]), { width: 640, height: 140 });
```

![Cùng một box xanh với opacity 1, 0.6 và 0.25, và nền rgba trong suốt với chữ vẫn đậm màu](/img/guide/effects-opacity.png)

## Transform

Transform 2D chạy trên mọi profile: `translate*()`, `rotate()`, `scale*()`, `skew*()`, `matrix()`, các
thuộc tính riêng `translate`, `rotate` và `scale`, và `transformOrigin` (mặc định `50% 50%`). Transform
không ảnh hưởng tới layout; nó chỉ dịch chuyển kết quả được vẽ.

<!-- @example effects#transforms -->
```js
const square = (transform, extra = {}) => [{
  type: "container",
  style: { width: 50, height: 50, backgroundColor: "#f43f5e", border: "2px solid #881337", transform, ...extra },
}];
const transforms = renderer.renderSync(grid([
  tile("rotate(30deg)", { backgroundColor: "#ffe4e6" }, square("rotate(30deg)")),
  tile("scale(1.4, .7)", { backgroundColor: "#ffe4e6" }, square("scale(1.4, .7)")),
  tile("skewX(-20deg)", { backgroundColor: "#ffe4e6" }, square("skewX(-20deg)")),
  tile("translate(30px, 15px)", { backgroundColor: "#ffe4e6" }, square("translate(30px, 15px)")),
  tile("origin: top left", { backgroundColor: "#ffe4e6" }, square("rotate(25deg)", { transformOrigin: "top left" })),
  tile("rotate: 45deg + scale: .8", { backgroundColor: "#ffe4e6" }, square(undefined, { rotate: "45deg", scale: 0.8 })),
  tile("matrix(...)", { backgroundColor: "#ffe4e6" }, square("matrix(1, .3, -.3, 1, 0, 0)")),
  tile("rotated text", { backgroundColor: "#ffe4e6" },
    [{ type: "text", text: "SALE", style: { fontSize: 28, fontWeight: 700, color: "#be123c", transform: "rotate(-12deg)" } }]),
]), { width: 640, height: 260 });
```

![Các hình vuông được xoay, co giãn, nghiêng, dịch, xoay quanh góc trên trái, dùng thuộc tính rotate và scale riêng, matrix, và chữ xoay](/img/guide/effects-transforms.png)

::: warning Không có transform 3D
Các hàm 3D (`rotateX()`, `rotateY()`, `perspective()`, `matrix3d()`, `translateZ()`, ...) là giá trị
không hợp lệ, như trong takumi. Trong style inline chúng làm cả lần render throw:
:::

<!-- @example effects#transform-3d -->
```js
const message = expectThrow(() =>
  renderer.renderSync({ type: "container", style: { width: 10, height: 10, transform: "rotateX(45deg)" } }, { width: 10, height: 10 }),
);
console.log(message); // bm-engine: invalid value for style property transform
```

Trong stylesheet hay class `tw`, khai báo không hợp lệ bị bỏ đi thay vì throw (cơ chế phục hồi lỗi của
CSS).

## clip-path

`clipPath` cắt phần tử và các con của nó theo một hình: `inset()` (với `round`), `circle()`, `ellipse()`,
`polygon()` và `path()`, có thể kèm geometry box (`border-box`, `padding-box`, `content-box`, ...). Cần
**standard** hoặc **full**; `path()` dùng mã SVG, vốn có trong cả hai.

<!-- @example effects#clip-path -->
```js
const photoLike = { backgroundImage: "linear-gradient(135deg, #06b6d4, #3b82f6 50%, #a855f7)" };
const clipPaths = renderer.renderSync(grid([
  tile("circle(40%)", { ...photoLike, clipPath: "circle(40%)" }),
  tile("ellipse(50% 35%)", { ...photoLike, clipPath: "ellipse(50% 35%)" }),
  tile("polygon (triangle)", { ...photoLike, clipPath: "polygon(50% 0, 100% 100%, 0 100%)" }),
  tile("polygon (arrow)", { ...photoLike, clipPath: "polygon(0 30%, 60% 30%, 60% 0, 100% 50%, 60% 100%, 60% 70%, 0 70%)" }),
  tile("inset(10px round 20px)", { ...photoLike, clipPath: "inset(10px 20px round 20px)" }),
  tile("path()", { ...photoLike, clipPath: "path('M65 80 C10 45 20 5 65 30 C110 5 120 45 65 80Z')" }),
]), { width: 640, height: 260 });
```

![Một gradient bị cắt thành hình tròn, elip, tam giác, mũi tên, inset bo góc và path hình trái tim](/img/guide/effects-clip-path.png)

`clip-path: url(#id)` (tham chiếu tới clip path của SVG) không được hỗ trợ. Lưu ý tọa độ của `path()` là
pixel trong border box của phần tử và không co giãn theo nó.

## Mask

`maskImage` (cùng các thuộc tính `mask*` / `WebkitMask*` khác: `maskSize`, `maskPosition`, `maskRepeat`,
`maskMode`, `maskOrigin`, `maskClip`, `maskType`) dùng kênh alpha của một gradient hay một ảnh (kể cả
SVG) để làm mờ dần hoặc cắt phần tử. Cần **standard** hoặc **full**.

<!-- @example effects#masks -->
```js
const masks = renderer.renderSync(grid([
  tile("linear fade", { ...photoLike, maskImage: "linear-gradient(to right, black, transparent)" }),
  tile("radial spotlight", { ...photoLike, maskImage: "radial-gradient(circle, black 40%, transparent 70%)" }),
  tile("repeating stripes", { ...photoLike, maskImage: "repeating-linear-gradient(90deg, black 0 8px, transparent 8px 14px)" }),
  tile("SVG mask image", {
    ...photoLike,
    maskImage: `url("data:image/svg+xml;utf8,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 2l3 7h7l-5.5 4.5 2 7.5-6.5-4.5-6.5 4.5 2-7.5L2 9h7z"/></svg>')}")`,
    maskSize: "contain", maskRepeat: "no-repeat", maskPosition: "center",
  }),
]), { width: 640, height: 140 });
```

![Một gradient mờ dần bằng mask tuyến tính, mask spotlight radial, mask sọc và mask SVG hình ngôi sao](/img/guide/effects-masks.png)

`maskComposite` được chấp nhận và bị bỏ qua: nhiều lớp mask luôn được kết hợp bằng `add`.

## Blend mode

`mixBlendMode` hòa trộn một phần tử với những gì đã vẽ bên dưới, dùng 16 blend mode của CSS cùng
`plus-lighter` và `plus-darker`; `backgroundBlendMode` hòa trộn các lớp nền với nhau;
`isolation: "isolate"` giới hạn việc hòa trộn trong một nhóm. Cần **standard** hoặc **full**.

<!-- @example effects#blend -->
```js
const blendModes = ["normal", "multiply", "screen", "overlay", "darken", "lighten", "difference", "exclusion"];
const circles = (mode) => [
  { type: "container", style: { position: "absolute", left: 25, top: 10, width: 55, height: 55, borderRadius: 30, backgroundColor: "#f43f5e" } },
  { type: "container", style: { position: "absolute", left: 50, top: 25, width: 55, height: 55, borderRadius: 30, backgroundColor: "#22d3ee", mixBlendMode: mode } },
];
const blend = renderer.renderSync(grid(
  blendModes.map((mode) => tile(mode, { position: "relative", backgroundColor: "#facc15", isolation: "isolate" }, circles(mode))),
), { width: 640, height: 260 });
```

![Hình tròn cyan đè lên hình tròn đỏ trên nền vàng với các blend mode normal, multiply, screen, overlay, darken, lighten, difference và exclusion](/img/guide/effects-blend.png)

Các hình tròn được định vị tuyệt đối, nên mỗi ô có `position: "relative"`: thiếu nó, mọi hình tròn sẽ
được đặt theo canvas.

## backdrop-filter

`backdropFilter` (cả `WebkitBackdropFilter`) áp filter lên những gì nằm phía sau phần tử, trong phạm vi
border box và bo góc của nó: hiệu ứng "kính mờ". Hãy cho phần tử một nền bán trong suốt để thấy được phần
phía sau đã lọc. Cần **standard** hoặc **full**.

<!-- @example effects#backdrop -->
```js
const backdrop = renderer.renderSync({
  type: "container",
  style: {
    display: "flex", gap: 24, padding: 30, width: "100%", height: "100%", alignItems: "center", fontFamily: "Inter",
    backgroundImage: "radial-gradient(circle at 20% 30%, #f97316 0 60px, transparent 61px), radial-gradient(circle at 75% 70%, #8b5cf6 0 80px, transparent 81px), linear-gradient(#0ea5e9, #1e3a8a)",
  },
  children: ["blur(8px)", "blur(8px) saturate(1.8)", "grayscale(1)"].map((f) => ({
    type: "container",
    style: {
      display: "flex", width: 170, height: 120, alignItems: "center", justifyContent: "center", borderRadius: 18,
      backgroundColor: "rgba(255,255,255,.18)", border: "1px solid rgba(255,255,255,.5)", backdropFilter: f,
    },
    children: [{ type: "text", text: f, style: { color: "white", fontSize: 14, fontWeight: 700 } }],
  })),
}, { width: 640, height: 180 });
```

![Ba thẻ bán trong suốt đặt trên các hình tròn màu với backdrop filter blur, blur kèm saturate, và grayscale](/img/guide/effects-backdrop.png)

## Tóm tắt theo profile

| Hiệu ứng | core | standard | full |
|:--|:-:|:-:|:-:|
| Gradient (mọi loại, repeating, chồng lớp) | ✓ | ✓ | ✓ |
| Không gian nội suy gradient, `oklch()` / `lab()` / `color-mix()` / `light-dark()` | sRGB / throw | ✓ | ✓ |
| Kiểu viền, `borderRadius`, `outline`, cắt bằng `overflow` | ✓ | ✓ | ✓ |
| `boxShadow`, `textShadow`, `WebkitTextStroke`, `backgroundClip: "text"` | ✓ | ✓ | ✓ |
| `filter`, `opacity`, transform 2D | ✓ | ✓ | ✓ |
| `clipPath`, `maskImage`, `mixBlendMode`, `backgroundBlendMode`, `isolation`, `backdropFilter` | bỏ qua | ✓ | ✓ |
| Transform 3D, `filter: url()`, `clip-path: url()` | — | — | — |

"bỏ qua" nghĩa là thuộc tính được chấp nhận, không báo lỗi và không có tác dụng. Script ví dụ kiểm tra
điều này với `clipPath`: cùng một ô bị cắt trên `core` và trên `full`:

<!-- @example effects#core-ignores -->
```js
// The same clipped tile on core and on full: core accepts clipPath but ignores it.
const clipped = { type: "container", style: { width: 40, height: 40, backgroundColor: "red", clipPath: "circle(10px)" } };
const corner = (r) => r.renderSync(clipped, { width: 40, height: 40, format: "raw" }).slice(0, 4);
const coreRenderer = new core.Renderer();
console.log("core:", corner(coreRenderer), "full:", corner(renderer)); // core: 255,0,0,255  full: 0,0,0,0
```

Xem thêm: [Hỗ trợ CSS → Bóng đổ và hiệu ứng](./css-support.md#bóng-đổ-và-hiệu-ứng),
[Profile và kích thước](../profiles-and-size.md), [Animation](./animation.md).
