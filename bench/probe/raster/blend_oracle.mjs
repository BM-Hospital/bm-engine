// Compares src/raster/blend.zig (drawPixmapBlend) with the takumi wasm oracle, and times it.
// usage (from bench/):  node probe/raster/blend_oracle.mjs <path-to-blend.wasm> [--bench]
// Build the wasm (repo root; ZIG = zig 0.17.1):
//   ZIG build-exe -target wasm32-freestanding -mcpu=generic+simd128+bulk_memory+sign_ext+nontrapping_fptoint+mutable_globals -O ReleaseSmall -fno-entry -rdynamic -fstrip -femit-bin=blend.wasm --dep raster -Mroot=bench/probe/raster/blend_root.zig -Mraster=src/raster/blend.zig
import { readFileSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";

const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]), {});
const ex = instance.exports;
const MODES = ["normal", "multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light",
  "soft-light", "difference", "exclusion", "hue", "saturation", "color", "luminosity", "plus-lighter"];

let seed = 12345;
const rnd = (n) => { seed = (Math.imul(seed, 1103515245) + 12345) >>> 0; return (seed >>> 8) % n; };

// Straight colours whose premultiplied form is exact (alpha = 255*j/q, channels multiples of q),
// so the canvas content is known without guessing how takumi rounds when premultiplying.
function color() {
  const q = [1, 1, 3, 5, 15][rnd(5)];
  const j = q === 1 ? (rnd(8) ? 1 : 0) : rnd(q + 1);
  const a = (255 * j) / q;
  const top = Math.floor(255 / q);
  const c = () => [0, top * q, rnd(top + 1) * q, rnd(top + 1) * q][rnd(4)];
  const s = [c(), c(), c(), a];
  return { s, p: [s[0] * a / 255, s[1] * a / 255, s[2] * a / 255, a] };
}
const hex = (s) => "#" + s.map((v) => v.toString(16).padStart(2, "0")).join("");

const COLS = 16, ROWS = 16, CELL = 2, N = COLS * ROWS, W = COLS * CELL, H = ROWS * CELL;
const cells = [];
for (let i = 0; i < N; i++) cells.push({ bg: color(), fg: color() });
cells[0] = { bg: { s: [255, 255, 255, 255], p: [255, 255, 255, 255] }, fg: { s: [0, 0, 255, 255], p: [0, 0, 255, 255] } };

if (process.argv.includes("--bench")) {
  const w = 1200, h = 630, px = w * h;
  const fill = (ptr, opaque) => {
    const u = new Uint8Array(ex.memory.buffer, ptr, px * 4);
    for (let i = 0; i < px; i++) {
      const a = opaque ? 255 : (i * 7) & 255;
      for (let k = 0; k < 3; k++) u[i * 4 + k] = ((Math.imul(i + 1, (k + 3) * 2654435761) >>> 24) * a / 255) | 0;
      u[i * 4 + 3] = a;
    }
  };
  for (const opaque of [true, false]) {
    console.log(opaque ? "opaque src + dst, opacity 1" : "translucent src + dst, opacity 0.5", "(ns/pixel, 1200x630)");
    for (let m = 0; m < MODES.length; m++) {
      let best = Infinity;
      for (let rep = 0; rep < 5; rep++) {
        fill(ex.dstPtr(), opaque); fill(ex.srcPtr(), opaque);
        const t = performance.now();
        ex.blend(w, h, m, opaque ? 1 : 0.5, 1);
        best = Math.min(best, performance.now() - t);
      }
      console.log(`  ${MODES[m].padEnd(13)} ${(best * 1e6 / px).toFixed(2)}`);
    }
  }
  for (const src of [0, 1]) {
    let best = Infinity;
    for (let rep = 0; rep < 5; rep++) {
      fill(ex.dstPtr(), false); fill(ex.srcPtr(), false);
      const t = performance.now();
      ex.mask(w, h, src, 1);
      best = Math.min(best, performance.now() - t);
    }
    console.log(`  maskMultiplyPixmap ${src ? "luminance" : "alpha"} ${(best * 1e6 / px).toFixed(2)}`);
  }
  process.exit(0);
}

const r = new Renderer();
async function oracle(mode, opacity) {
  const children = cells.map(({ bg, fg }) => {
    const style = { width: CELL, height: CELL, backgroundColor: hex(fg.s), mixBlendMode: mode };
    if (opacity !== 1) style.opacity = opacity;
    return { type: "container", style: { width: CELL, height: CELL, backgroundColor: hex(bg.s), display: "flex" }, children: [{ type: "container", style }] };
  });
  const node = { type: "container", style: { width: W, height: H, display: "flex", flexWrap: "wrap" }, children };
  return new Uint8Array(await r.render(node, { width: W, height: H, format: "raw" }));
}
function mine(mode, opacity) {
  const d = new Uint8Array(ex.memory.buffer, ex.dstPtr(), N * 4);
  const s = new Uint8Array(ex.memory.buffer, ex.srcPtr(), N * 4);
  cells.forEach(({ bg, fg }, i) => { d.set(bg.p, i * 4); s.set(fg.p, i * 4); });
  ex.blend(N, 1, mode, opacity, 1);
  ex.straight(N, 1);
  return new Uint8Array(ex.memory.buffer, ex.dstPtr(), N * 4).slice();
}

let exactModes = 0;
for (const opacity of [1, 0.5, 0.3]) {
  console.log(`--- opacity ${opacity} (${N} colour pairs per mode; diffs on the straight-alpha output of takumi)`);
  for (let m = 0; m < MODES.length; m++) {
    const t = await oracle(MODES[m], opacity);
    const g = mine(m, opacity);
    let bad = 0, max = 0, maxOpaque = 0, worst = "";
    for (let i = 0; i < N; i++) {
      const x = (i % COLS) * CELL, y = ((i / COLS) | 0) * CELL, o = (y * W + x) * 4;
      let dmax = 0;
      for (let k = 0; k < 4; k++) dmax = Math.max(dmax, Math.abs(t[o + k] - g[i * 4 + k]));
      if (dmax) {
        bad++;
        if (t[o + 3] >= 128) maxOpaque = Math.max(maxOpaque, dmax);
        if (dmax > max) { max = dmax; worst = ` worst: bg ${cells[i].bg.p} fg ${cells[i].fg.p} takumi ${Array.from(t.slice(o, o + 4))} mine ${Array.from(g.slice(i * 4, i * 4 + 4))}`; }
      }
    }
    if (!bad && opacity === 1) exactModes++;
    console.log(`${MODES[m].padEnd(13)} ${bad === 0 ? "EXACT" : `${bad}/${N} pixels differ, max ${max} (max ${maxOpaque} where alpha >= 128)${worst}`}`);
  }
}
console.log(`modes exact at opacity 1: ${exactModes}/${MODES.length}`);
