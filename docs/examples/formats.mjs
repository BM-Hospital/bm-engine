// Examples for docs/{en,vi}/image/formats.md. Regions are copied into the pages by sync-docs.mjs.
import { saver } from "./_lib.mjs";
const save = saver("formats");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine"; // Node: the full profile

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

// A card with rounded corners on a transparent canvas: good for showing what each format does with alpha.
const card = {
  type: "container",
  style: {
    display: "flex", flexDirection: "column", justifyContent: "center", gap: 6,
    width: "100%", height: "100%", padding: 28, borderRadius: 28, fontFamily: "Inter",
    backgroundImage: "linear-gradient(135deg, #f97316, #db2777 55%, #7c3aed)",
  },
  children: [
    { type: "text", text: "bm-engine", style: { fontSize: 40, fontWeight: 700, color: "white" } },
    { type: "text", text: "PNG · JPEG · WebP · SVG", style: { fontSize: 20, color: "rgba(255,255,255,0.85)" } },
  ],
};
// #endregion

// #region png
const png = renderer.renderSync(card, { width: 400, height: 200 }); // format defaults to "png"
// #endregion
save("png", png);

// #region compare
for (const format of ["png", "jpeg", "webp"]) {
  const bytes = renderer.renderSync(card, { width: 400, height: 200, format });
  console.log(format, bytes.length, "bytes");
}
// #endregion

// #region jpeg-quality
const low = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 15 });
const high = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 90 });
console.log("quality 15:", low.length, "bytes; quality 90:", high.length, "bytes");
// #endregion
save("jpeg-q15", low, "jpg");
save("jpeg-q90", high, "jpg");
console.log("jpeg default quality (75):", renderer.renderSync(card, { width: 400, height: 200, format: "jpeg" }).length);

// #region jpeg-opaque
// JPEG has no alpha channel: transparent pixels (the rounded corners) come out black.
const cornersBlack = renderer.renderSync(card, { width: 400, height: 200, format: "jpeg", quality: 90 });

// Paint an opaque background behind the card instead:
const onWhite = renderer.renderSync(
  { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "white" }, children: [card] },
  { width: 400, height: 200, format: "jpeg", quality: 90 },
);
// #endregion
save("jpeg-black-corners", cornersBlack, "jpg");
save("jpeg-on-white", onWhite, "jpg");

// #region webp
const webp = renderer.renderSync(card, { width: 400, height: 200, format: "webp", quality: 10 });
const webpDefault = renderer.renderSync(card, { width: 400, height: 200, format: "webp" });
console.log(webp.length === webpDefault.length); // true: WebP output is always lossless, quality is ignored
// #endregion
console.log("webp", webp.length);
save("webp", webp, "webp");

// #region raw
const width = 400, height = 200;
const raw = renderer.renderSync(card, { width, height, format: "raw" });
console.log(raw.length === width * height * 4); // true: straight (non-premultiplied) RGBA8, row by row

const pixel = (x, y) => Array.from(raw.subarray((y * width + x) * 4, (y * width + x) * 4 + 4));
console.log(pixel(0, 0));     // [0, 0, 0, 0]: the corner outside the border radius is transparent
console.log(pixel(200, 100)); // an opaque pixel of the gradient
// #endregion
console.log("pixel(200,100) =", pixel(200, 100));

// #region raw-roundtrip
// Raw pixels can be fed back as an image source: { width, height, data }.
const thumbnails = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", gap: 12, padding: 12, width: "100%", height: "100%", backgroundColor: "#f1f5f9" },
    children: [1, 2, 3].map(() => ({ type: "image", src: { width, height, data: raw }, style: { width: 120, height: 60 } })),
  },
  { width: 420, height: 84 },
);
// #endregion
save("raw-roundtrip", thumbnails);

// #region dataurl
const url = renderer.renderAsDataUrlSync(card, { width: 400, height: 200, format: "webp" });
console.log(url.slice(0, 23)); // "data:image/webp;base64,"
// in a browser: img.src = url
// #endregion
console.log(url.slice(0, 23));

// #region ico
const favicon = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
             borderRadius: 12, backgroundColor: "#7c3aed" },
    children: [{ type: "text", text: "b", style: { fontFamily: "Inter", fontWeight: 700, fontSize: 44, color: "white" } }],
  },
  { width: 64, height: 64, format: "ico" }, // full profile only; 1-256 px per side
);
// #endregion
console.log("ico", favicon.length, Array.from(favicon.subarray(0, 4)));
save("favicon", renderer.renderSync(
  { type: "container", style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", borderRadius: 12, backgroundColor: "#7c3aed" },
    children: [{ type: "text", text: "b", style: { fontFamily: "Inter", fontWeight: 700, fontSize: 44, color: "white" } }] },
  { width: 64, height: 64 }));

// #region svg
const svg = renderer.renderSvgSync(card, { width: 400, height: 200 }); // full profile only
console.log(svg.slice(0, 90));
// '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200" viewBox="0 0 400 200">...'
// #endregion
console.log("svg length", svg.length);
save("card", svg, "svg");

// #region dpr
// The same 400 x 200 CSS layout, rendered with twice as many pixels:
const retina = renderer.renderSync(card, { width: 800, height: 400, devicePixelRatio: 2 });

// Without the larger canvas, devicePixelRatio: 2 leaves only 200 x 100 CSS px of room:
const cramped = renderer.renderSync(card, { width: 400, height: 200, devicePixelRatio: 2 });
// #endregion
save("dpr2", retina);
save("dpr2-cramped", cramped);

// #region auto-size
// Without width / height the canvas takes the size of the laid-out root.
const badge = renderer.renderSync({
  type: "container",
  style: { display: "flex", padding: "6px 14px", borderRadius: 999, backgroundColor: "#0f172a" },
  children: [{ type: "text", text: "v0.1.0", style: { fontFamily: "Inter", fontSize: 18, color: "#e2e8f0" } }],
});
// #endregion
save("auto-size", badge);
console.log("auto-size", (badge[16] << 24 | badge[17] << 16 | badge[18] << 8 | badge[19]), (badge[20] << 24 | badge[21] << 16 | badge[22] << 8 | badge[23]));

// #region abort
const controller = new AbortController();
controller.abort(new Error("request closed"));
try {
  await renderer.render(card, { width: 400, height: 200, signal: controller.signal });
} catch (err) {
  console.log(err.message); // "request closed": the signal is checked before rendering starts
}
// #endregion

// #region core
import * as core from "bm-engine/core";

const small = new core.Renderer();
small.renderSync({ type: "container", style: { width: 16, height: 16, backgroundColor: "red" } },
                 { width: 16, height: 16, format: "webp" }); // png / jpeg / webp / raw work on every profile
try {
  small.renderSync({ type: "container" }, { width: 16, height: 16, format: "ico" });
} catch (err) {
  console.log(err.message); // "bm-engine: this build has no ICO output support (use the full build)"
}
// #endregion
