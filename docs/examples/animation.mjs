// Examples for docs/{en,vi}/image/animation.md. Regions are copied into the pages by sync-docs.mjs.
import { saver } from "./_lib.mjs";
const save = saver("animation");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer, features } from "bm-render"; // Node: the full profile

console.log(features.animation); // true: CSS animations need the full profile
const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
// #endregion

// #region scene
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
// #endregion

// #region frame
const frame = renderer.renderSync(scene, { width: 240, height: 80, css, timeMs: 500 }); // one PNG, 500 ms in
// #endregion
save("frame-500", frame);

// #region strip
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
// #endregion
save("strip", strip);

// #region render-animation
const webp = renderer.renderAnimationSync({
  scenes: [{ node: scene, durationMs: 2000 }],
  width: 240, height: 80, fps: 25, // 2000 ms * 25 fps = 50 frames
  format: "webp",                   // "webp" (default, lossless) | "apng" | "gif"
  css,
});
// #endregion
save("ball", webp, "webp");

// #region formats
for (const format of ["webp", "apng", "gif"]) {
  const bytes = renderer.renderAnimationSync({ scenes: [{ node: scene, durationMs: 2000 }], width: 240, height: 80, fps: 25, format, css });
  console.log(format, bytes.length, "bytes");
}
// #endregion
save("ball", renderer.renderAnimationSync({ scenes: [{ node: scene, durationMs: 2000 }], width: 240, height: 80, fps: 25, format: "gif", css }), "gif");

// #region easing
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
// #endregion
save("easing", easingGif, "gif");
save("easing-still", renderer.renderSync(easingScene, { width: 560, height: 210, css: easingCss, timeMs: 700 }));

// #region iteration
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
// #endregion
for (const [a, t] of [["move 1s linear", 250], ["move 1s linear", 1500], ["move 1s linear forwards", 1500], ["move 1s linear infinite alternate", 1400], ["move 1s linear 500ms backwards", 200], ["move 1s steps(4)", 300]]) console.log("probe", a, t, probe(a, t));

// #region layout-props
// Layout properties animate too: the box is re-laid out at every sampled time.
const grow = renderer.measureSync(
  { type: "container", style: { display: "flex", width: 300, height: 20 },
    children: [{ type: "container", style: { height: 20, animation: "grow 1s linear" } }] },
  { css: ["@keyframes grow { from { width: 20px } to { width: 220px } }"], timeMs: 500 },
);
console.log(grow.children[0].width); // 120
// #endregion
console.log("grow", grow.children[0].width);

// #region rule-object
// Keyframes as data instead of CSS text (takumi rule object):
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
// #endregion
save("rule-object", pulse);

// #region tailwind
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
// #endregion
save("tailwind", twGif, "gif");

// #region html
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
// #endregion
save("spinner", spinnerGif, "gif");

// #region scenes
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
// #endregion
save("scenes", slides, "gif");

// #region frame-count
const fps = 30, durationMs = 1000;
const frameCount = Math.ceil((durationMs * fps) / 1000);       // 30
const frameStart = (i) => Math.floor((i * 1000) / fps);        // 0, 33, 66, 100, ...
console.log(frameCount, frameStart(1), frameStart(2), frameStart(3));
// #endregion

// #region video
// Frames for a video encoder: render raw RGBA at each frame time and hand the bytes over,
// e.g. to `ffmpeg -f rawvideo -pix_fmt rgba -s 240x80 -r 30 -i - out.mp4` through its stdin.
const videoFrames = [];
for (let i = 0; i < frameCount; i++) {
  videoFrames.push(renderer.renderSync(scene, { width: 240, height: 80, css, timeMs: frameStart(i), format: "raw" }));
}
console.log(videoFrames.length, videoFrames[0].length); // 30 frames of 240 * 80 * 4 bytes
// #endregion

// #region errors
for (const options of [
  { scenes: [{ node: scene, durationMs: 1000 }], width: 240, height: 80, fps: 60, format: "gif" },
  { scenes: [], width: 240, height: 80, fps: 10 },
]) {
  try { renderer.renderAnimationSync(options); } catch (err) { console.log(err.message); }
}
// bm-render: Frame rate 60 fps exceeds the maximum 50 fps for this animation format
// bm-render: Expected at least one animation scene
// #endregion

// #region custom-props
// Not animated in 0.1.0: custom properties (and anything on ::before / ::after).
const notAnimated = renderer.measureSync(
  { type: "container", style: { display: "flex", width: 200, height: 20 },
    children: [{ type: "container", className: "dot", style: { width: 10, height: 10 } }] },
  { css: ["@keyframes x { from { --x: 0px } to { --x: 100px } } .dot { margin-left: var(--x, 0px); animation: x 1s linear }"], timeMs: 500 },
);
console.log(notAnimated.children[0].transform[4]); // 0
// #endregion
console.log("custom prop x", notAnimated.children[0].transform[4]);

// #region standard
import * as standard from "bm-render/standard";

const std = new standard.Renderer();
const still = std.measureSync(
  { type: "container", style: { display: "flex", width: 200, height: 20 },
    children: [{ type: "container", style: { width: 10, height: 10, animation: "move 1s linear" } }] },
  { css: ["@keyframes move { to { margin-left: 100px } }"], timeMs: 500 },
);
console.log(standard.features.animation, still.children[0].transform[4]); // false 0: parsed, not applied
// #endregion
console.log("standard", standard.features.animation, still.children[0].transform[4]);
