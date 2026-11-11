// Interleaved A/B comparison of several wbench wasm builds (robust against machine noise):
//   node probe/raster/wcmp.mjs a.wasm b.wasm ...   (env CASES="0:0,0:2,2:2" = what:mode list)
import { readFileSync } from "node:fs";
const files = process.argv.slice(2);
const insts = [];
for (const f of files) { const { instance } = await WebAssembly.instantiate(readFileSync(f), {}); instance.exports.init(); insts.push(instance.exports); }
const NAMES = { 0: "ellipse 1200x630 fill", 1: "rrect 1200x630 fill", 2: "glyph 40px mask", 3: "glyph 16px mask", 4: "glyph 40px fill", 5: "ellipse 1200x630 mask", 6: "resample 2x down", 7: "ellipse gradient fill", 8: "ellipse 220x160 fill", 9: "rrect rotated fill", 10: "fillRect full" };
const ITERS = { 0: 4, 1: 4, 2: 400, 3: 800, 4: 400, 5: 4, 6: 1, 7: 2, 8: 40, 9: 4, 10: 4 };
const MODES = ["exact", "levels16", "skia_ss"];
const cases = (process.env.CASES || "10:0,0:1,0:2,1:1,1:2,8:1,8:2,9:1,9:2,5:1,5:2,2:0,2:1,2:2,3:1,3:2,4:1,4:2").split(",").map((s) => s.split(":").map(Number));
const rounds = +(process.env.ROUNDS || 60);
console.log("case".padEnd(34), files.map((f) => f.split(/[\/]/).pop().padStart(14)).join(""));
for (const [what, mode] of cases) {
  const it = ITERS[what];
  const best = insts.map(() => 1e9);
  for (const ex of insts) { try { ex.run(what, mode, it); } catch {} }
  for (let r = 0; r < rounds; r++) insts.forEach((ex, i) => { const t = performance.now(); ex.run(what, mode, it); best[i] = Math.min(best[i], (performance.now() - t) / it); });
  console.log(`${NAMES[what]} ${MODES[mode]}`.padEnd(34), best.map((b) => ((b * 1000).toFixed(1) + " us").padStart(14)).join(""));
}
