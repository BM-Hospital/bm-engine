// Wasm micro-benchmark of the raster module.
// usage (from bench/):  node probe/raster/wbench.mjs <path-to-wbench.wasm> [filter]
// Build (repo root; ZIG = zig 0.17.1):
//   ZIG build-exe -target wasm32-freestanding -mcpu=generic+simd128+bulk_memory+sign_ext+nontrapping_fptoint+mutable_globals -O ReleaseSmall -fno-entry -rdynamic -fstrip -femit-bin=wbench.wasm --dep raster -Mroot=bench/probe/raster/wbench_root.zig -Mraster=src/raster/raster.zig
import { readFileSync } from "node:fs";
const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]), {});
const ex = instance.exports;
ex.init();
const MODES = ["exact", "levels16", "skia_ss"];
const cases = [
  [10, "fillRect 1200x630 solid (memset reference)", 20, [0]],
  [0, "ellipse 1200x630 solid fillPath", 20, [0, 1, 2]],
  [1, "rrect r48 1200x630 solid fillPath", 20, [0, 1, 2]],
  [8, "ellipse 220x160 solid fillPath", 200, [0, 1, 2]],
  [7, "ellipse 1200x630 linear-gradient fillPath", 10, [1, 2]],
  [9, "rrect rotated+scaled solid fillPath", 20, [1, 2]],
  [5, "ellipse 1200x630 rasterize -> mask", 20, [1, 2]],
  [2, "glyph 40px rasterize -> mask", 4000, [0, 1, 2]],
  [3, "glyph 16px rasterize -> mask", 8000, [0, 1, 2]],
  [4, "glyph 40px fillPath solid", 4000, [0, 1, 2]],
  [6, "resample 2400x1260 -> 1200x630", 2, [0]],
];
const filt = process.argv[3];
const maxMode = +(process.env.MAXMODE ?? 2);
for (const [what, name, iters, modes] of cases) {
  if (filt && !name.includes(filt)) continue;
  for (const mode of modes) {
    if (mode > maxMode) continue;
    ex.run(what, mode, Math.max(1, iters >> 2));
    let best = 1e9;
    for (let k = 0; k < 25; k++) {
      const t = performance.now();
      ex.run(what, mode, iters);
      best = Math.min(best, (performance.now() - t) / iters);
    }
    const s = best >= 0.1 ? best.toFixed(3) + " ms" : (best * 1000).toFixed(2) + " us";
    console.log(`${name.padEnd(44)} ${MODES[mode].padEnd(9)} ${s.padStart(12)}`);
  }
}
