# Animation

[English](animation.md) · [Tiếng Việt](../../vi/image/animation.md)

bm-render renders CSS animations by **sampling** the
`@keyframes` timeline at a point in time you choose. One call gives you one frame at `timeMs`; another
samples a list of scenes at a fixed frame rate and encodes them as an animated WebP, APNG or GIF. This
page shows both, how to define keyframes (stylesheet text, rule objects, HTML `<style>`), the timing
functions, what can and cannot be animated, the frame schedule, and what animations cost. Everything
here needs the **`full`** profile; the snippets are `docs/examples/animation.mjs` and the images below
them are its real output.

## Which call to use

| You want | Call |
|:--|:--|
| One still frame at a given time | `render(source, { css, timeMs })` |
| An animated WebP, APNG or GIF | `renderAnimation({ scenes, width, height, fps, format, css })` |
| Frames for a video encoder | `render(..., { timeMs, format: "raw" })` in a loop |

## Defining an animation

Keyframes live in a stylesheet, passed with the `css` option (or a `<style>` element in an HTML
source). Elements refer to them with the usual `animation*` properties, in an inline `style`, a
stylesheet rule or HTML.

<!-- @example animation#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer, features } from "bm-render"; // Node: the full profile

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

Two animations run on the same element here: `slide` moves it, `tint` changes its colour. Both are
`infinite alternate`, so the ball goes right during the first second and back during the next.

### Keyframes as data

When values come from your application, pass the keyframes as a rule object instead of building
CSS text: `{ keyframes: name, steps: [{ offset, style }] }`, where `offset` is `"from"`, `"to"` or a
percentage such as `"50%"`, and `style` uses the same camelCase keys as inline styles.

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

![Frame at 500 ms of the rule-object animation](/img/guide/animation-rule-object.png)

The deprecated top-level `keyframes` option (`{ name: { from: {...}, to: {...} } }`) also still works.

### Built-in names and Tailwind

`spin`, `ping`, `pulse` and `bounce` (Tailwind's keyframes) work without a `@keyframes` rule. For example,
`animation: "spin 1s linear infinite"` rotates the element. The Tailwind utilities work too:
`animate-spin`, `animate-ping`, `animate-pulse`, `animate-bounce`, `animate-none`, arbitrary values such
as `animate-[spin_1s_linear_infinite]`, and your own names from `--animate-*` variables in `@theme` (with
their `@keyframes` inside the `@theme` block or anywhere in `css`):

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

![Five shapes animated by Tailwind classes: spinning, bouncing, pinging, spinning backwards and wiggling](/img/guide/animation-tailwind.gif)

## One frame: `timeMs`

`timeMs` is the position on the animation timeline in milliseconds. It is floored to a whole number of
milliseconds; when you leave it out, animations are still applied, at time 0.

<!-- @example animation#frame -->
```js
const frame = renderer.renderSync(scene, { width: 240, height: 80, css, timeMs: 500 }); // one PNG, 500 ms in
```

![The scene at 500 ms](/img/guide/animation-frame-500.png)

Rendering several times gives you a strip of frames. Raw RGBA output can be used directly as an image
source, so bm-render can assemble the strip itself:

<!-- @example animation#strip -->
```js
// Five raw frames, laid side by side by bm-render itself (raw RGBA works as an image source).
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

![Frames at 0, 250, 500, 750 and 1000 ms](/img/guide/animation-strip.png)

## Animated images: `renderAnimation`

`renderAnimation()` / `renderAnimationSync()` take a list of scenes, each a source (node, HTML or
`{ json }`) shown for `durationMs`, sample them at `fps`, and encode the frames.

<!-- @example animation#render-animation -->
```js
const webp = renderer.renderAnimationSync({
  scenes: [{ node: scene, durationMs: 2000 }],
  width: 240, height: 80, fps: 25, // 2000 ms * 25 fps = 50 frames
  format: "webp",                   // "webp" (default, lossless) | "apng" | "gif"
  css,
});
```

![Animated WebP of the ball](/img/guide/animation-ball.webp)

| Option | Notes |
|:--|:--|
| `scenes` | required, at least one: `{ node, durationMs }[]` |
| `width`, `height` | required (a still render can size itself from content; an animation cannot) |
| `fps` | required, greater than 0; at most 50 for GIF, 90 for WebP / APNG |
| `format` | `"webp"` (default, lossless), `"apng"` or `"gif"` |
| `css`, `images`, `fontFamilies`, `lang`, `devicePixelRatio`, `keyframes` | as for `render()` |
| `quality`, `lossless` | accepted, ignored (WebP is lossless, GIF is palette-quantised per frame) |

### Choosing the animated format

<!-- @example animation#formats -->
```js
for (const format of ["webp", "apng", "gif"]) {
  const bytes = renderer.renderAnimationSync({ scenes: [{ node: scene, durationMs: 2000 }], width: 240, height: 80, fps: 25, format, css });
  console.log(format, bytes.length, "bytes");
}
```

This printed 17 288 bytes for WebP, 32 330 for APNG and 18 360 for GIF (50 frames of 240 × 80; sizes
are for this example only). The GIF version:

![Animated GIF of the ball](/img/guide/animation-ball.gif)

- **WebP** (lossless, full alpha) is usually the smallest and is supported by every current browser.
- **APNG** keeps full colour and alpha too, and is often the largest.
- **GIF** plays everywhere (chat apps, email) but has 256 colours per frame and 1-bit transparency, and
  is limited to 50 fps.

### Scenes

Scenes play one after the other with no tweening between them, and **each scene starts its own
timeline at 0 ms**, so an entry animation replays in every scene:

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

![Three scenes, each with its own entry animation](/img/guide/animation-scenes.gif)

### Frame schedule

With `total` = the sum of `durationMs`, there are
`ceil(total × fps / 1000)` frames; frame *i* starts at `floor(i × 1000 / fps)` ms and lasts until the
next one starts (zero-length frames are dropped). A frame shows the scene active at its start time,
sampled at that scene's local time.

<!-- @example animation#frame-count -->
```js
const fps = 30, durationMs = 1000;
const frameCount = Math.ceil((durationMs * fps) / 1000);       // 30
const frameStart = (i) => Math.floor((i * 1000) / fps);        // 0, 33, 66, 100, ...
console.log(frameCount, frameStart(1), frameStart(2), frameStart(3));
```

This prints `30 33 66 100`.

## Timing functions

`animation-timing-function` accepts the keywords (`linear`, `ease`, `ease-in`, `ease-out`,
`ease-in-out`, `step-start`, `step-end`), `cubic-bezier()`, `steps()` with every jump term, and the
`linear()` easing function with optional percentages. As in CSS, the timing function applies to each
keyframe segment separately.

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

![Seven timing functions side by side](/img/guide/animation-easing.gif)

The same scene as a still frame at 700 ms — note the `cubic-bezier()` with a negative control point
overshooting to the left of its track:

![Timing functions at 700 ms](/img/guide/animation-easing-still.png)

## Iterations, direction, fill mode, delay

All the longhands are supported: `animation-delay` (also negative), `-direction`
(`normal`, `reverse`, `alternate`, `alternate-reverse`), `-fill-mode` (`none`, `forwards`, `backwards`,
`both`), `-iteration-count` (numbers and `infinite`) and several comma-separated animations per
element. `measure()` applies animations too, which makes the effect easy to check:

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

The printed values match the comments: 25, 0, 100, 60, 0 and 25.

::: warning `animation-play-state` is ignored
`paused` animations are sampled anyway: a sampled render has no notion of "paused".
:::

## What can be animated

Animated values are interpolated and the whole page is laid out again at the sampled time, so layout
properties animate as well as paint properties:

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

| Property kind | Behaviour (checked in `animation.mjs` and with probes) |
|:--|:--|
| `transform`, `translate`, `rotate`, `scale`, `opacity`, `filter` | interpolated |
| Colours (`background-color`, `border-color`, ...) | interpolated |
| Lengths: `width`, `height`, `margin*`, `padding*`, `inset`, `font-size`, `letter-spacing`, `border-radius`, ... | interpolated, layout runs again |
| `background-image` (gradients), `display` and other non-interpolable values | discrete: the value switches halfway through the segment |
| Custom properties (`--x`) | **not** animated |
| `::before` / `::after` | **not** animated |
| `transition*` | parsed; a sampled render has no transitions |

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

When `font-size` is animated, `em` lengths on the same element follow the animated size, as in a
browser: `width: "2em"` with `font-size` animated from 10 px to 30 px is 40 px wide halfway through.

## Animations in HTML sources

An HTML source can carry its own keyframes in a `<style>` element; the same string works with
`render()` and `renderAnimation()`:

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

![Spinner from an HTML source](/img/guide/animation-spinner.gif)

## Frames for video

For MP4 / WebM, render raw frames at the schedule's timestamps and pass them to a video encoder such as
ffmpeg (`ffmpeg -f rawvideo -pix_fmt rgba -s 240x80 -r 30 -i - out.mp4`, writing the frames to its
stdin). bm-render itself has no video encoder.

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

## Errors and limits

<!-- @example animation#errors -->
```js
for (const options of [
  { scenes: [{ node: scene, durationMs: 1000 }], width: 240, height: 80, fps: 60, format: "gif" },
  { scenes: [], width: 240, height: 80, fps: 10 },
]) {
  try { renderer.renderAnimationSync(options); } catch (err) { console.log(err.message); }
}
// bm-render: Frame rate 60 fps exceeds the maximum 50 fps for this animation format
// bm-render: Expected at least one animation scene
```

Other messages: `renderAnimation needs \`width\` and \`height\``, `missing field \`fps\``,
`Expected fps to be greater than 0`, `unsupported animation format: mp4`. The raw frames of one call
are capped at 512 MiB in total.

## Cost

Animation cost grows with frame count, canvas size and effects. To keep animations cheap:

- keep the canvas small — work and memory grow with `width × height × frames`;
- use the lowest `fps` that looks smooth (12–25 is plenty for most UI motion);
- prefer WebP; GIF quantises every frame to a palette;
- reuse one `Renderer` (fonts and glyph caches stay warm across frames, see
  [Performance](./performance.md)).

## Profiles

Only `full` animates (`features.animation`). On `standard` the `@keyframes` rules parse and nothing
moves; on `core` the `animation` property is ignored; `renderAnimation()` throws
`this build has no animation support (use the full build)` on both.

<!-- @example animation#standard -->
```js
import * as standard from "bm-render/standard";

const std = new standard.Renderer();
const still = std.measureSync(
  { type: "container", style: { display: "flex", width: 200, height: 20 },
    children: [{ type: "container", style: { width: 10, height: 10, animation: "move 1s linear" } }] },
  { css: ["@keyframes move { to { margin-left: 100px } }"], timeMs: 500 },
);
console.log(standard.features.animation, still.children[0].transform[4]); // false 0: parsed, not applied
```

See also: [Output formats](./formats.md), [CSS support → Animations](./css-support.md#animations),
[API → renderAnimation](./api.md#renderanimation--renderanimationsync).
