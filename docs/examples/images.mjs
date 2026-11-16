// Examples for docs/{en,vi}/image/images.md. Run: node docs/examples/run-all.mjs images
import { saver } from "./_lib.mjs";
import assert from "node:assert/strict";
import * as core from "bm-render/core";
import * as standard from "bm-render/standard";
const save = saver("images");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
// #endregion

// #region photo
// A 320 × 200 test picture, rendered by bm-render itself. Any PNG / JPEG bytes work the same way.
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
// #endregion
save("photo", photo);

// #region sources
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
// #endregion
save("sources", sources);

// #region pixelated
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
// #endregion
save("pixelated", pixelated);

// #region fetch
async function loadImages(urls) {
  return Promise.all(urls.map(async (src) => ({ src, data: new Uint8Array(await (await fetch(src)).arrayBuffer()) })));
}
// const images = await loadImages(["https://example.com/logo.png"]);
// renderer.renderSync(node, { width: 1200, height: 630, images });
// #endregion
void loadImages;

// #region lazy
const lazy = await renderer.render(
  { type: "image", src: "avatar", style: { width: 64, height: 64, borderRadius: 32 } },
  { width: 64, height: 64, images: [{ src: "avatar", data: async () => photo }] }, // resolved by the async API
);
// renderer.renderSync(...) with the same options throws "lazy images[].data() needs the async API"
// #endregion
assert.equal(lazy[0], 0x89);

// #region missing
const missing = renderer.measureSync(
  { type: "container", style: { display: "flex" }, children: [{ type: "image", src: "not-in-images" }] },
  { width: 100, height: 100 },
);
console.log(missing.children[0].width, missing.children[0].height); // 0 0, and no exception
// #endregion
assert.equal(missing.children[0].width, 0);

// #region object-fit
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
// #endregion
save("object-fit", objectFit);

// #region object-position
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
// #endregion
save("object-position", objectPosition);

// #region background
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
// #endregion
save("background", backgrounds);

// #region sizing
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
// #endregion
console.log(sized.children.map((c) => `${c.width}×${c.height}`).join(" "));

// #region dpr
const atDpr2 = renderer.measureSync(
  { type: "container", style: { display: "flex" }, children: [{ type: "image", src: photo }] },
  { width: 800, height: 600, devicePixelRatio: 2 },
);
console.log(atDpr2.children[0].width, atDpr2.children[0].height); // 640 400 (output pixels)
// #endregion

// #region styling
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
// #endregion
save("styling", styling);

// #region svg
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
// #endregion
save("svg", svgOut);

// #region svg-text
const badge = `<svg xmlns="http://www.w3.org/2000/svg" width="260" height="60">
  <rect width="260" height="60" rx="30" fill="#0f172a"/>
  <text x="130" y="39" font-family="Inter" font-size="22" font-weight="700" fill="#f8fafc" text-anchor="middle">SVG &lt;text&gt; works</text></svg>`;
const svgText = renderer.renderSync(
  { type: "container", style: { display: "flex", padding: 20, backgroundColor: "#fff7ed" }, children: [{ type: "image", src: badge }] },
  { width: 300, height: 100, images: { sources: [], cache: "none" } }, // the object form of `images` is accepted too
);
// #endregion
save("svg-text", svgText);

// #region html-img
const html = renderer.renderSync(
  `<div style="display:flex;gap:16px;align-items:center;padding:16px;font-family:Inter;font-size:20px;background:#ecfeff;height:100%">
     <img src="photo" width="120" style="border-radius:12px" />
     <img src="${dataUrl}" style="width:60px;height:60px;object-fit:cover;border-radius:50%" />
     <span>&lt;img&gt; in HTML input</span>
   </div>`,
  { width: 520, height: 110, images: [{ src: "photo", data: photo }] },
);
// #endregion
save("html-img", html);

// #region animated
// An animated GIF / APNG / WebP source shows the frame that is current at `timeMs` (full profile).
const fill = (color) => ({ type: "container", style: { width: "100%", height: "100%", backgroundColor: color } });
const gif = renderer.renderAnimationSync({
  scenes: [{ node: fill("#ef4444"), durationMs: 500 }, { node: fill("#3b82f6"), durationMs: 500 }],
  width: 40, height: 40, fps: 2, format: "gif",
});
const at = (timeMs) => renderer.renderSync({ type: "image", src: gif }, { width: 40, height: 40, format: "raw", timeMs });
console.log(at(0).slice(0, 3), at(700).slice(0, 3)); // red at 0 ms, blue at 700 ms
// #endregion
const a0 = at(0), a7 = at(700);
console.log(a0.slice(0, 3), a7.slice(0, 3));

// --- profile checks behind the "Supported formats" table (not shown in the page) ---
const webp = renderer.renderSync(fill("#ef4444"), { width: 8, height: 8, format: "webp" });
const jpeg = renderer.renderSync(fill("#ef4444"), { width: 8, height: 8, format: "jpeg" });
const svgSmall = '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="red"/></svg>';
const width = (m, src) => new m.Renderer().measureSync({ type: "container", style: { display: "flex" }, children: [{ type: "image", src }] }, { width: 20, height: 20 }).children[0].width;
const table = {};
for (const [name, src] of Object.entries({ png: photo, jpeg, webpLossless: webp, gif, svg: svgSmall })) {
  table[name] = [core, standard].map((m) => width(m, src) > 0);
}
console.log(table);
assert.deepEqual(table, { png: [true, true], jpeg: [true, true], webpLossless: [false, true], gif: [false, true], svg: [false, true] });
