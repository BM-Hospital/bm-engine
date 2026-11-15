# Animation

[English](../../en/image/animation.md) · [Tiếng Việt](animation.md)

bm-engine render CSS animation bằng cách **lấy mẫu** dòng thời gian
`@keyframes` tại thời điểm bạn chọn. Một lời gọi cho bạn một khung hình tại `timeMs`; lời gọi khác lấy
mẫu một danh sách scene theo tốc độ khung hình cố định rồi mã hoá thành WebP động, APNG hoặc GIF. Trang này
trình bày cả hai, cách khai báo keyframes (văn bản stylesheet, rule object, `<style>` trong HTML), các
hàm timing, những gì animate được và không, lịch khung hình, và chi phí của animation. Mọi thứ ở đây cần
profile **`full`**; các đoạn mã nằm trong `docs/examples/animation.mjs` và ảnh bên dưới là đầu ra thật.

## Dùng lời gọi nào

| Bạn cần | Lời gọi |
|:--|:--|
| Một khung hình tĩnh tại một thời điểm | `render(source, { css, timeMs })` |
| Một ảnh WebP, APNG hoặc GIF động | `renderAnimation({ scenes, width, height, fps, format, css })` |
| Khung hình cho bộ mã hoá video | `render(..., { timeMs, format: "raw" })` trong vòng lặp |

## Khai báo animation

Keyframes nằm trong stylesheet, truyền qua tuỳ chọn `css` (hoặc thẻ `<style>` trong nguồn HTML). Phần tử
tham chiếu đến chúng bằng các thuộc tính `animation*` quen thuộc, trong `style` inline, trong rule của
stylesheet hoặc trong HTML.

<!-- @example animation#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer, features } from "bm-engine"; // Node: the full profile

console.log(features.animation); // true: CSS animations need the full profile
const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
```

<!-- @example animation#scene -->
```js
const css = [`
  @keyframes slide { from { transform: translateX(0) } to { transform: translateX(150px) } }
  @keyframes tint  { from { background-color: #f97316 } to { background-color: #7c3aed } }
  .ball { width: 40px; height: 40px; border-radius: 20px;
          animation: slide 1s ease-in-out infinite alternate, tint 1s linear infinite alternate; }
`];
const scene = {
  type: "container",
  style: { display: "flex", alignItems: "center", width: "100%", height: "100%", padding: "0 25px", backgroundColor: "#f8fafc" },
  children: [{ type: "container", className: "ball" }],
};
```

Ở đây có hai animation chạy trên cùng một phần tử: `slide` di chuyển nó, `tint` đổi màu. Cả hai đều là
`infinite alternate`, nên quả bóng đi sang phải trong giây đầu và quay về trong giây tiếp theo.

### Keyframes dạng dữ liệu

Khi giá trị đến từ ứng dụng của bạn, hãy truyền keyframes dưới dạng rule object thay vì ghép
chuỗi CSS: `{ keyframes: name, steps: [{ offset, style }] }`, trong đó `offset` là `"from"`, `"to"` hoặc
phần trăm như `"50%"`, còn `style` dùng cùng các khoá camelCase như style inline.

<!-- @example animation#rule-object -->
```js
const pulse = renderer.renderSync(
  { type: "container", style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center" },
    children: [{ type: "container", style: { width: 40, height: 40, borderRadius: 8, backgroundColor: "#16a34a", animation: "pop 1s ease-out" } }] },
  {
    width: 80, height: 80, timeMs: 500,
    css: [{ keyframes: "pop", steps: [
      { offset: "from", style: { transform: "scale(0.5)", opacity: 0.2 } },
      { offset: "to", style: { transform: "scale(1.5)", opacity: 1 } },
    ] }],
  },
);
```

![Khung hình tại 500 ms của animation dạng rule object](/img/guide/animation-rule-object.png)

Tuỳ chọn cấp cao nhất `keyframes` (đã deprecated; `{ name: { from: {...}, to: {...} } }`) vẫn hoạt
động.

### Tên dựng sẵn và Tailwind

`spin`, `ping`, `pulse` và `bounce` (keyframes của Tailwind) dùng được mà không cần rule `@keyframes`. Ví dụ,
`animation: "spin 1s linear infinite"` làm phần tử xoay. Các utility Tailwind cũng dùng
được: `animate-spin`, `animate-ping`, `animate-pulse`, `animate-bounce`, `animate-none`, giá trị tùy ý như
`animate-[spin_1s_linear_infinite]`, và tên riêng của bạn từ biến `--animate-*` trong `@theme` (kèm
`@keyframes` của chúng, đặt trong khối `@theme` hoặc ở đâu đó trong `css`):

<!-- @example animation#tailwind -->
```js
// Tailwind's animate-* utilities (full profile): the built-in spin / ping / pulse / bounce, arbitrary
// values, and your own --animate-* theme variables with their @keyframes.
const twScene = {
  type: "container",
  tw: "flex items-center justify-around w-full h-full bg-slate-100",
  children: [
    { type: "container", tw: "w-10 h-10 rounded-md bg-indigo-500 animate-spin" },
    { type: "container", tw: "w-10 h-10 rounded-full bg-sky-500 animate-bounce" },
    { type: "container", tw: "w-10 h-10 rounded-full bg-rose-500 animate-ping" },
    { type: "container", tw: "w-10 h-10 rounded-md bg-amber-500 animate-[spin_2s_linear_infinite_reverse]" },
    { type: "container", tw: "w-10 h-10 rounded-md bg-emerald-500 animate-wiggle" },
  ],
};
const twTheme = `@theme {
  --animate-wiggle: wiggle 1s ease-in-out infinite;
  @keyframes wiggle { 0%, 100% { transform: rotate(-15deg) } 50% { transform: rotate(15deg) } }
}`;
const twGif = renderer.renderAnimationSync({
  scenes: [{ node: twScene, durationMs: 1000 }], width: 360, height: 100, fps: 20, format: "gif", css: [twTheme],
});
```

![Năm hình được animate bằng class Tailwind: xoay, nảy, ping, xoay ngược và lắc](/img/guide/animation-tailwind.gif)

## Một khung hình: `timeMs`

`timeMs` là vị trí trên dòng thời gian animation, tính bằng mili giây. Giá trị được làm tròn xuống thành
số nguyên mili giây; khi bỏ trống, animation vẫn được áp dụng, tại thời điểm 0.

<!-- @example animation#frame -->
```js
const frame = renderer.renderSync(scene, { width: 240, height: 80, css, timeMs: 500 }); // one PNG, 500 ms in
```

![Scene tại 500 ms](/img/guide/animation-frame-500.png)

Render nhiều lần cho bạn một dải khung hình. Đầu ra RGBA raw dùng thẳng làm nguồn ảnh được, nên chính
bm-engine có thể ghép dải đó:

<!-- @example animation#strip -->
```js
// Five raw frames, laid side by side by bm-engine itself (raw RGBA works as an image source).
const times = [0, 250, 500, 750, 1000];
const frames = times.map((timeMs) => renderer.renderSync(scene, { width: 240, height: 80, css, timeMs, format: "raw" }));
const strip = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", gap: 4, padding: 4, backgroundColor: "#cbd5e1", fontFamily: "Inter" },
    children: frames.map((data, i) => ({
      type: "container",
      style: { display: "flex", alignItems: "center", gap: 8 },
      children: [
        { type: "image", src: { width: 240, height: 80, data } },
        { type: "text", text: `${times[i]} ms`, style: { fontSize: 16, color: "#0f172a", width: 70 } },
      ],
    })),
  },
  {}, // no width / height: the canvas takes the size of the content
);
```

![Khung hình tại 0, 250, 500, 750 và 1000 ms](/img/guide/animation-strip.png)

## Ảnh động: `renderAnimation`

`renderAnimation()` / `renderAnimationSync()` nhận danh sách scene, mỗi scene là một nguồn (node, HTML
hoặc `{ json }`) hiển thị trong `durationMs`, lấy mẫu theo `fps` rồi mã hoá các khung hình.

<!-- @example animation#render-animation -->
```js
const webp = renderer.renderAnimationSync({
  scenes: [{ node: scene, durationMs: 2000 }],
  width: 240, height: 80, fps: 25, // 2000 ms * 25 fps = 50 frames
  format: "webp",                   // "webp" (default, lossless) | "apng" | "gif"
  css,
});
```

![WebP động của quả bóng](/img/guide/animation-ball.webp)

| Tuỳ chọn | Ghi chú |
|:--|:--|
| `scenes` | bắt buộc, ít nhất một: `{ node, durationMs }[]` |
| `width`, `height` | bắt buộc (render tĩnh tự lấy kích thước theo nội dung được; animation thì không) |
| `fps` | bắt buộc, lớn hơn 0; tối đa 50 với GIF, 90 với WebP / APNG |
| `format` | `"webp"` (mặc định, lossless), `"apng"` hoặc `"gif"` |
| `css`, `images`, `fontFamilies`, `lang`, `devicePixelRatio`, `keyframes` | như với `render()` |
| `quality`, `lossless` | được chấp nhận nhưng bỏ qua (WebP lossless, GIF lượng tử hoá palette theo từng khung) |

### Chọn định dạng ảnh động

<!-- @example animation#formats -->
```js
for (const format of ["webp", "apng", "gif"]) {
  const bytes = renderer.renderAnimationSync({ scenes: [{ node: scene, durationMs: 2000 }], width: 240, height: 80, fps: 25, format, css });
  console.log(format, bytes.length, "bytes");
}
```

Ví dụ in ra 17 288 byte cho WebP, 32 330 cho APNG và 18 360 cho GIF (50 khung hình 240 × 80; dung lượng
chỉ đúng cho ví dụ này). Bản GIF:

![GIF động của quả bóng](/img/guide/animation-ball.gif)

- **WebP** (lossless, alpha đầy đủ) thường nhỏ nhất và mọi trình duyệt hiện nay đều hỗ trợ.
- **APNG** cũng giữ đủ màu và alpha, và thường lớn nhất.
- **GIF** chạy ở mọi nơi (ứng dụng chat, email) nhưng chỉ có 256 màu mỗi khung, trong suốt 1 bit, và giới
  hạn 50 fps.

### Scene

Các scene phát lần lượt, không có chuyển tiếp nội suy giữa chúng, và **mỗi scene bắt đầu dòng thời gian
riêng từ 0 ms**, nên animation xuất hiện sẽ chạy lại ở mỗi scene:

<!-- @example animation#scenes -->
```js
const card = (text, color) => ({
  type: "container",
  style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
           backgroundColor: color, fontFamily: "Inter", fontSize: 28, color: "white" },
  children: [{ type: "text", text, style: { animation: "enter 400ms ease-out both" } }],
});
const slides = renderer.renderAnimationSync({
  scenes: [
    { node: card("Build", "#0f172a"), durationMs: 900 },
    { node: card("Render", "#7c3aed"), durationMs: 900 },
    { node: card("Ship", "#db2777"), durationMs: 900 },
  ],
  width: 240, height: 80, fps: 20, format: "gif",
  css: ["@keyframes enter { from { opacity: 0; transform: translateY(16px) } }"],
}); // each scene starts its own timeline at 0 ms
```

![Ba scene, mỗi scene có animation xuất hiện riêng](/img/guide/animation-scenes.gif)

### Lịch khung hình

Lịch: với `total` = tổng các `durationMs`, có `ceil(total × fps / 1000)` khung hình;
khung *i* bắt đầu tại `floor(i × 1000 / fps)` ms và kéo dài tới khi khung kế tiếp bắt đầu (khung có độ dài
0 bị bỏ). Mỗi khung hiển thị scene đang hoạt động tại thời điểm bắt đầu của nó, lấy mẫu theo thời gian cục
bộ của scene đó.

<!-- @example animation#frame-count -->
```js
const fps = 30, durationMs = 1000;
const frameCount = Math.ceil((durationMs * fps) / 1000);       // 30
const frameStart = (i) => Math.floor((i * 1000) / fps);        // 0, 33, 66, 100, ...
console.log(frameCount, frameStart(1), frameStart(2), frameStart(3));
```

Đoạn này in ra `30 33 66 100`.

## Hàm timing

`animation-timing-function` nhận các từ khoá (`linear`, `ease`, `ease-in`, `ease-out`, `ease-in-out`,
`step-start`, `step-end`), `cubic-bezier()`, `steps()` với mọi kiểu jump, và hàm easing `linear()` có
phần trăm tuỳ chọn. Như trong CSS, hàm timing áp dụng riêng cho từng đoạn giữa hai keyframe.

<!-- @example animation#easing -->
```js
const easings = ["linear", "ease", "ease-in", "ease-out", "cubic-bezier(0.68, -0.6, 0.32, 1.6)", "steps(5)",
                 "linear(0, 1 40%, 0.75 55%, 1 70%, 0.93 85%, 1)"];
const lane = (timing) => ({
  type: "container",
  style: { display: "flex", alignItems: "center", height: 26, gap: 8 },
  children: [
    { type: "text", text: timing.replace(/, /g, ","), style: { width: 190, fontSize: 11, color: "#334155" } },
    { type: "container", style: { display: "flex", width: 330, height: 18, borderRadius: 9, backgroundColor: "#e2e8f0" },
      children: [{ type: "container", style: {
        width: 18, height: 18, borderRadius: 9, backgroundColor: "#2563eb",
        animation: `go 2s ${timing} infinite`,
      } }] },
  ],
});
const easingScene = {
  type: "container",
  style: { display: "flex", flexDirection: "column", justifyContent: "center", width: "100%", height: "100%",
           padding: "0 12px", backgroundColor: "white", fontFamily: "Inter" },
  children: easings.map(lane),
};
const easingCss = ["@keyframes go { 0%, 10% { transform: translateX(0) } 90%, 100% { transform: translateX(312px) } }"];
const easingGif = renderer.renderAnimationSync({
  scenes: [{ node: easingScene, durationMs: 2000 }], width: 560, height: 210, fps: 20, format: "gif", css: easingCss,
});
```

![Bảy hàm timing đặt cạnh nhau](/img/guide/animation-easing.gif)

Cùng scene đó dưới dạng khung tĩnh tại 700 ms — để ý `cubic-bezier()` có điểm điều khiển âm vượt ra
ngoài bên trái đường chạy:

![Các hàm timing tại 700 ms](/img/guide/animation-easing-still.png)

## Số lần lặp, hướng, fill mode, độ trễ

Mọi thuộc tính con đều được hỗ trợ: `animation-delay` (kể cả giá trị âm), `-direction` (`normal`,
`reverse`, `alternate`, `alternate-reverse`), `-fill-mode` (`none`, `forwards`, `backwards`, `both`),
`-iteration-count` (số và `infinite`) và nhiều animation phân tách bằng dấu phẩy trên một phần tử.
`measure()` cũng áp dụng animation, nên kiểm tra hiệu ứng rất dễ:

<!-- @example animation#iteration -->
```js
const probe = (animation, timeMs) => {
  const m = renderer.measureSync(
    { type: "container", style: { display: "flex", width: 200, height: 20 },
      children: [{ type: "container", style: { width: 10, height: 10, animation } }] },
    { css: ["@keyframes move { from { margin-left: 0 } to { margin-left: 100px } }"], timeMs },
  );
  return m.children[0].transform[4]; // x position of the box in canvas coordinates
};
console.log(probe("move 1s linear", 250));                     // 25
console.log(probe("move 1s linear", 1500));                    // 0   (finished, no fill mode)
console.log(probe("move 1s linear forwards", 1500));           // 100 (fill-mode forwards keeps the end)
console.log(probe("move 1s linear infinite alternate", 1400)); // 60  (second iteration runs backwards)
console.log(probe("move 1s linear 500ms backwards", 200));     // 0   (in the delay, holds the first keyframe)
console.log(probe("move 1s steps(4)", 300));                   // 25
```

Các giá trị in ra khớp với chú thích: 25, 0, 100, 60, 0 và 25.

::: warning `animation-play-state` bị bỏ qua
Animation `paused` vẫn được lấy mẫu: một lần render lấy mẫu không có khái niệm "tạm dừng".
:::

## Những gì animate được

Giá trị được nội suy và toàn bộ trang được layout lại tại thời điểm lấy mẫu, nên thuộc tính layout cũng
animate được, không chỉ thuộc tính vẽ:

<!-- @example animation#layout-props -->
```js
// Layout properties animate too: the box is re-laid out at every sampled time.
const grow = renderer.measureSync(
  { type: "container", style: { display: "flex", width: 300, height: 20 },
    children: [{ type: "container", style: { height: 20, animation: "grow 1s linear" } }] },
  { css: ["@keyframes grow { from { width: 20px } to { width: 220px } }"], timeMs: 500 },
);
console.log(grow.children[0].width); // 120
```

| Loại thuộc tính | Hành vi (kiểm tra trong `animation.mjs` và bằng probe) |
|:--|:--|
| `transform`, `translate`, `rotate`, `scale`, `opacity`, `filter` | nội suy |
| Màu (`background-color`, `border-color`, ...) | nội suy |
| Độ dài: `width`, `height`, `margin*`, `padding*`, `inset`, `font-size`, `letter-spacing`, `border-radius`, ... | nội suy, layout chạy lại |
| `background-image` (gradient), `display` và các giá trị không nội suy được | rời rạc: giá trị đổi ở giữa đoạn |
| Custom property (`--x`) | **không** animate |
| `::before` / `::after` | **không** animate |
| `transition*` | được parse; render lấy mẫu không có transition |

<!-- @example animation#custom-props -->
```js
// Not animated in 0.1.0: custom properties (and anything on ::before / ::after).
const notAnimated = renderer.measureSync(
  { type: "container", style: { display: "flex", width: 200, height: 20 },
    children: [{ type: "container", className: "dot", style: { width: 10, height: 10 } }] },
  { css: ["@keyframes x { from { --x: 0px } to { --x: 100px } } .dot { margin-left: var(--x, 0px); animation: x 1s linear }"], timeMs: 500 },
);
console.log(notAnimated.children[0].transform[4]); // 0
```

Khi animate `font-size`, các độ dài `em` trên cùng phần tử đó đi theo cỡ chữ đang animate, như trong
trình duyệt: `width: "2em"` với `font-size` animate từ 10 px đến 30 px sẽ rộng 40 px ở giữa chừng.

## Animation trong nguồn HTML

Nguồn HTML có thể mang keyframes riêng trong thẻ `<style>`; cùng một chuỗi dùng được cho cả `render()` và
`renderAnimation()`:

<!-- @example animation#html -->
```js
const spinner = `
  <style>
    @keyframes spin { to { transform: rotate(360deg) } }
    .ring { width: 48px; height: 48px; border: 6px solid #e2e8f0; border-top-color: #0ea5e9;
            border-radius: 50%; animation: spin 0.8s linear infinite; }
  </style>
  <div style="display:flex; width:100%; height:100%; align-items:center; justify-content:center; background:white">
    <div class="ring"></div>
  </div>`;
const spinnerGif = renderer.renderAnimationSync({ scenes: [{ node: spinner, durationMs: 800 }], width: 80, height: 80, fps: 20, format: "gif" });
```

![Spinner từ nguồn HTML](/img/guide/animation-spinner.gif)

## Khung hình cho video

Với MP4 / WebM, hãy render khung raw tại các mốc thời gian của lịch rồi đưa cho bộ mã hoá video như ffmpeg
(`ffmpeg -f rawvideo -pix_fmt rgba -s 240x80 -r 30 -i - out.mp4`, ghi các khung vào stdin của nó). Bản
thân bm-engine không có bộ mã hoá video.

<!-- @example animation#video -->
```js
// Frames for a video encoder: render raw RGBA at each frame time and hand the bytes over,
// e.g. to `ffmpeg -f rawvideo -pix_fmt rgba -s 240x80 -r 30 -i - out.mp4` through its stdin.
const videoFrames = [];
for (let i = 0; i < frameCount; i++) {
  videoFrames.push(renderer.renderSync(scene, { width: 240, height: 80, css, timeMs: frameStart(i), format: "raw" }));
}
console.log(videoFrames.length, videoFrames[0].length); // 30 frames of 240 * 80 * 4 bytes
```

## Lỗi và giới hạn

<!-- @example animation#errors -->
```js
for (const options of [
  { scenes: [{ node: scene, durationMs: 1000 }], width: 240, height: 80, fps: 60, format: "gif" },
  { scenes: [], width: 240, height: 80, fps: 10 },
]) {
  try { renderer.renderAnimationSync(options); } catch (err) { console.log(err.message); }
}
// bm-engine: Frame rate 60 fps exceeds the maximum 50 fps for this animation format
// bm-engine: Expected at least one animation scene
```

Các thông báo khác: `renderAnimation needs \`width\` and \`height\``, `missing field \`fps\``,
`Expected fps to be greater than 0`, `unsupported animation format: mp4`. Tổng dữ liệu khung raw của một
lời gọi bị giới hạn 512 MiB.

## Chi phí

Chi phí render animation tăng theo số khung hình, kích thước canvas và hiệu ứng. Để giảm chi phí:

- giữ canvas nhỏ — công việc và bộ nhớ tăng theo `width × height × số khung`;
- dùng `fps` thấp nhất mà vẫn mượt (12–25 là đủ cho hầu hết chuyển động UI);
- ưu tiên WebP; GIF lượng tử hoá từng khung về palette;
- dùng lại một `Renderer` (font và cache glyph được giữ nóng giữa các khung, xem
  [Hiệu năng](./performance.md)).

## Profile

Chỉ `full` có animation (`features.animation`). Trên `standard`, rule `@keyframes` được parse nhưng không
gì chuyển động; trên `core`, thuộc tính `animation` bị bỏ qua; `renderAnimation()` ném lỗi
`this build has no animation support (use the full build)` trên cả hai.

<!-- @example animation#standard -->
```js
import * as standard from "bm-engine/standard";

const std = new standard.Renderer();
const still = std.measureSync(
  { type: "container", style: { display: "flex", width: 200, height: 20 },
    children: [{ type: "container", style: { width: 10, height: 10, animation: "move 1s linear" } }] },
  { css: ["@keyframes move { to { margin-left: 100px } }"], timeMs: 500 },
);
console.log(standard.features.animation, still.children[0].transform[4]); // false 0: parsed, not applied
```

Xem thêm: [Định dạng đầu ra](./formats.md), [Hỗ trợ CSS → Animation](./css-support.md#animation),
[API → renderAnimation](./api.md#renderanimation--renderanimationsync).
