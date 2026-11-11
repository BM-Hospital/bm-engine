// Checks the luminance-mask formula of src/raster/blend.zig (`lumaCov`, MaskSource.luminance)
// against takumi: an SVG <mask> (mask-type luminance) of solid colours over a white rect.
// usage (from bench/):  node probe/raster/blend_luma_oracle.mjs
import { Renderer } from "@takumi-rs/wasm/node";

const f = Math.fround;
// same f32 operations as blend.zig lumaCov, on a premultiplied pixel
function lumaCov(p) {
  if (p[3] === 0) return 0;
  const a = f(p[3] / 255);
  const r = f(f(p[0] / 255) / a), g = f(f(p[1] / 255) / a), b = f(f(p[2] / 255) / a);
  const luma = f(f(f(r * f(0.2126)) + f(g * f(0.7152))) + f(b * f(0.0722)));
  return Math.ceil(Math.min(255, Math.max(0, f(f(luma * a) * 255))));
}

let seed = 99;
const rnd = (n) => { seed = (Math.imul(seed, 1103515245) + 12345) >>> 0; return (seed >>> 8) % n; };
const N = 16, CELL = 4, W = N * CELL;
const cols = [];
for (let i = 0; i < N * N; i++) {
  if (i < 64) { const v = i * 4 + 3; cols.push([v, v, v]); } // greys
  else cols.push([rnd(256), rnd(256), rnd(256)]);
}
const rects = cols.map((c, i) => `<rect x="${(i % N) * CELL}" y="${((i / N) | 0) * CELL}" width="${CELL}" height="${CELL}" fill="rgb(${c})"/>`).join("");
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${W} ${W}"><defs><mask id="m">${rects}</mask></defs><rect width="${W}" height="${W}" fill="#fff" mask="url(#m)"/></svg>`;
const r = new Renderer();
const node = { type: "image", src: "data:image/svg+xml;base64," + Buffer.from(svg).toString("base64"), width: W, height: W, style: { width: W, height: W } };
const raw = new Uint8Array(await r.render(node, { width: W, height: W, format: "raw" }));
let bad = 0, max = 0;
for (let i = 0; i < N * N; i++) {
  const x = (i % N) * CELL + 1, y = ((i / N) | 0) * CELL + 1, o = (y * W + x) * 4;
  const want = raw[o + 3], got = lumaCov([...cols[i], 255]);
  if (want !== got) { bad++; max = Math.max(max, Math.abs(want - got)); if (bad <= 5) console.log(`rgb(${cols[i]}) takumi ${want} mine ${got}`); }
}
console.log(bad === 0 ? `luminance mask: EXACT (${N * N} colours)` : `luminance mask: ${bad}/${N * N} differ, max ${max}`);
