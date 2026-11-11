// Regenerates src/raster/testdata/skia_*.a8 (takumi / tiny-skia coverage goldens used by the unit tests).
// usage (from bench/):  node probe/raster/gen_golden.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";
const tk = new Renderer();
const dir = "../src/raster/testdata";
mkdirSync(dir, { recursive: true });
async function gen(name, w, h, style) {
  const px = new Uint8Array(await tk.render({ type: "container", style: { width: w, height: h, display: "flex" }, children: [{ type: "container", style: { position: "absolute", backgroundColor: "white", ...style } }] }, { width: w, height: h, format: "raw" }));
  const a = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) a[i] = px[i * 4 + 3];
  writeFileSync(`${dir}/skia_${name}.a8`, a);
  console.log(name, w, h);
}
await gen("ellipse", 40, 24, { left: 5, top: 9, width: 23, height: 9, borderRadius: "50%" });
await gen("rrect", 48, 64, { left: 7, top: 11, width: 33, height: 47, borderRadius: "9.5px" });
await gen("quads", 40, 40, { left: 0, top: 0, width: 40, height: 40, clipPath: 'path("M 5.25 30.5 Q 5.25 5.75 20.5 5.75 Q 34.75 5.75 34.75 30.5 L 29.5 30.5 Q 29.5 11.25 20.5 11.25 Q 10.75 11.25 10.75 30.5 Z")' });
await gen("cubics", 64, 64, { left: 0, top: 0, width: 64, height: 64, clipPath: 'path(evenodd, "M 10 32 C 20 -20 44 84 54 32 L 54 60 L 10 60 Z M 20 40 C 24 30 40 62 44 50 L 30 58 Z")' });
