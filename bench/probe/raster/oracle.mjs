// Compares the raster module (gradients, blur) against the takumi wasm oracle.
// usage (from bench/):  node probe/raster/oracle.mjs <path-to-oracle.wasm>
// Build the wasm from oracle_root.zig (repo root; ZIG = zig 0.17.1):
//   ZIG build-exe -target wasm32-freestanding -mcpu=generic+simd128+bulk_memory+sign_ext+nontrapping_fptoint+mutable_globals -O ReleaseSmall -fno-entry -rdynamic -fstrip -femit-bin=oracle.wasm --dep raster -Mroot=bench/probe/raster/oracle_root.zig -Mraster=src/raster/raster.zig
import { readFileSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";

const wasmPath = process.argv[2];
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {});
const ex = instance.exports;
const r = new Renderer();

function mine(ptr, w, h) {
  return new Uint8Array(ex.memory.buffer, ptr, w * h * 4).slice();
}
function setStops(stops) {
  stops.forEach((s, i) => ex.set_stop(i, s[0], s[1], s[2], s[3], s[4] ?? 255));
  return stops.length;
}
async function oracle(style, w, h, children) {
  const node = { type: "container", style: { width: w, height: h, ...style }, children };
  return new Uint8Array(await r.render(node, { width: w, height: h, format: "raw" }));
}
function diff(name, a, b, w, h) {
  let max = 0, cnt = 0, first = null;
  for (let i = 0; i < w * h * 4; i++) {
    const d = Math.abs(a[i] - b[i]);
    if (d) { cnt++; if (d > max) max = d; if (!first) first = i; }
  }
  let extra = "";
  if (first !== null) {
    const p = first >> 2, x = p % w, y = (p / w) | 0;
    extra = ` first@(${x},${y}) takumi=${Array.from(a.slice(p * 4, p * 4 + 4))} mine=${Array.from(b.slice(p * 4, p * 4 + 4))}`;
  }
  console.log(`${name.padEnd(46)} ${cnt === 0 ? "EXACT" : `diff bytes ${cnt}/${w * h * 4} max ${max}`}${extra}`);
}

const RED = [255, 0, 0], BLUE = [0, 0, 255], LIME = [0, 255, 0];
const D2R = Math.PI / 180;

// CSS gradient line for an angle (Blink EndPointsFromAngle)
function line(w, h, deg) {
  const a = deg * D2R;
  const dx = Math.sin(a), dy = -Math.cos(a);
  const L = Math.abs(w * Math.sin(a)) + Math.abs(h * Math.cos(a));
  const cx = w / 2, cy = h / 2;
  return [cx - dx * L / 2, cy - dy * L / 2, cx + dx * L / 2, cy + dy * L / 2];
}

const cases = [];
const lin = (name, css, w, h, deg, stops, rep = 0) => cases.push(async () => {
  const n = setStops(stops);
  const [x0, y0, x1, y1] = line(w, h, deg);
  diff(name, await oracle({ backgroundImage: css }, w, h), mine(ex.linear(w, h, x0, y0, x1, y1, n, rep), w, h), w, h);
});

lin("linear to right red->blue 10x2", "linear-gradient(to right, red, blue)", 10, 2, 90, [[0, ...RED], [1, ...BLUE]]);
lin("linear to right 200x40", "linear-gradient(to right, red, blue)", 200, 40, 90, [[0, ...RED], [1, ...BLUE]]);
lin("linear to bottom 64x300", "linear-gradient(to bottom, #f97316, #7c3aed)", 64, 300, 180, [[0, 0xf9, 0x73, 0x16], [1, 0x7c, 0x3a, 0xed]]);
lin("linear 135deg 200x100", "linear-gradient(135deg, #f97316, #7c3aed)", 200, 100, 135, [[0, 0xf9, 0x73, 0x16], [1, 0x7c, 0x3a, 0xed]]);
lin("linear 30deg 3 stops 320x200", "linear-gradient(30deg, red, lime 30%, blue)", 320, 200, 30, [[0, ...RED], [0.3, ...LIME], [1, ...BLUE]]);
lin("linear 90deg hard stops 100x10", "linear-gradient(90deg, red 0%, red 50%, blue 50%, blue 100%)", 100, 10, 90, [[0, ...RED], [0.5, ...RED], [0.5, ...BLUE], [1, ...BLUE]]);
lin("linear alpha 90deg 256x8", "linear-gradient(90deg, rgba(255,0,0,1), rgba(0,0,255,0))", 256, 8, 90, [[0, ...RED, 255], [1, ...BLUE, 0]]);
lin("linear to right 1200x8", "linear-gradient(to right, #000, #fff)", 1200, 8, 90, [[0, 0, 0, 0], [1, 255, 255, 255]]);
lin("repeating 90deg 20px 200x10", "repeating-linear-gradient(90deg, red 0px, blue 20px)", 200, 10, 90, [[0, ...RED], [0.1, ...BLUE]], 1);
lin("repeating 45deg stripes 120x120", "repeating-linear-gradient(45deg, red 0px, red 10px, blue 10px, blue 20px)", 120, 120, 45,
  (() => { const L = 120 * Math.SQRT2; return [[0, ...RED], [10 / L, ...RED], [10 / L, ...BLUE], [20 / L, ...BLUE]]; })(), 1);

cases.push(async () => {
  const w = 200, h = 100, n = setStops([[0, ...RED], [1, ...BLUE]]);
  // default: ellipse farthest-corner at center
  diff("radial default ellipse 200x100", await oracle({ backgroundImage: "radial-gradient(red, blue)" }, w, h),
    mine(ex.radial(w, h, w / 2, h / 2, (w / 2) * Math.SQRT2, (h / 2) * Math.SQRT2, n, 0), w, h), w, h);
});
cases.push(async () => {
  const w = 160, h = 160, n = setStops([[0, 255, 255, 255], [0.5, ...LIME], [1, 0, 0, 0]]);
  diff("radial circle 60px at 40px 50px", await oracle({ backgroundImage: "radial-gradient(circle 60px at 40px 50px, white, lime 50%, black)" }, w, h),
    mine(ex.radial(w, h, 40, 50, 60, 60, n, 0), w, h), w, h);
});
cases.push(async () => {
  const w = 160, h = 120, n = setStops([[0, ...RED], [1, ...BLUE]]);
  diff("repeating radial circle 20px", await oracle({ backgroundImage: "repeating-radial-gradient(circle 100px at center, red 0px, blue 20px)" }, w, h),
    mine(ex.radial(w, h, 80, 60, 100, 100, setStops([[0, ...RED], [0.2, ...BLUE]]), 1), w, h), w, h);
  void n;
});
cases.push(async () => {
  const w = 120, h = 80, n = setStops([[0, ...RED], [1, ...BLUE]]);
  const maxr = Math.hypot(Math.max(60, w - 60), Math.max(40, h - 40));
  diff("conic red->blue 120x80", await oracle({ backgroundImage: "conic-gradient(red, blue)" }, w, h),
    mine(ex.conic(w, h, 60, 40, 0, n, 0, maxr), w, h), w, h);
});
cases.push(async () => {
  const w = 150, h = 150, n = setStops([[0, ...RED], [0.25, ...LIME], [1, ...BLUE]]);
  const maxr = Math.hypot(Math.max(50, w - 50), Math.max(60, h - 60));
  diff("conic from 45deg at 50px 60px", await oracle({ backgroundImage: "conic-gradient(from 45deg at 50px 60px, red, lime 25%, blue)" }, w, h),
    mine(ex.conic(w, h, 50, 60, 45 * D2R, n, 0, maxr), w, h), w, h);
});

const sh = (blur, bw = 10, bh = 10) => cases.push(async () => {
  const w = 20 + bw + 40, h = 20 + bh + 40;
  const child = { type: "container", style: { width: bw, height: bh, marginLeft: 20, marginTop: 20, backgroundColor: "white", boxShadow: `0 0 ${blur}px black` } };
  const a = await oracle({ backgroundColor: "white", display: "flex" }, w, h, [child]);
  diff(`box-shadow blur ${blur}px (sigma ${blur / 2}) ${bw}x${bh}`, a, mine(ex.shadow(w, h, 20, 20, bw, bh, blur / 2), w, h), w, h);
});
[1, 2, 3, 3.5, 4, 6, 7, 8, 10, 13, 24].forEach((b) => sh(b));
sh(10, 40, 25);

for (const c of cases) await c();
