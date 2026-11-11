// Side-by-side PNG (takumi | ours | diff x4) from oracle.mjs --dump output.
// usage: node probe/svg/viz.mjs <dumpdir> <name> <w> <h> <out.png> [scale]
import { readFileSync, writeFileSync } from "node:fs";
import { PNG } from "pngjs";
const [dir, name, ws, hs, out, sc] = process.argv.slice(2);
const w = +ws, h = +hs, s = +(sc ?? 1);
const a = readFileSync(`${dir}/${name}.tk.rgba`), b = readFileSync(`${dir}/${name}.me.rgba`);
const W = w * 3 * s, H = h * s;
const png = new PNG({ width: W, height: H });
const over = (p, i) => { const al = p[i + 3] / 255; return [0, 1, 2].map((k) => Math.round(p[i + k] * al + 255 * (1 - al))); };
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const panel = Math.floor(x / (w * s)), sx = Math.floor((x % (w * s)) / s), sy = Math.floor(y / s), i = (sy * w + sx) * 4;
  let c;
  if (panel === 0) c = over(a, i); else if (panel === 1) c = over(b, i);
  else { const ca = over(a, i), cb = over(b, i); c = [0, 1, 2].map((k) => Math.min(255, Math.abs(ca[k] - cb[k]) * 4)); c = c.map((v) => 255 - v); }
  const o = (y * W + x) * 4; png.data[o] = c[0]; png.data[o + 1] = c[1]; png.data[o + 2] = c[2]; png.data[o + 3] = 255;
}
writeFileSync(out, PNG.sync.write(png));
