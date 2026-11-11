import { readFileSync } from "node:fs";
const r = JSON.parse(readFileSync(new URL("../out/results.json", import.meta.url), "utf8"));
const tally = {};
for (const c of r.cases) {
  const m = c.cmp?.bm; const v = m?.verdict || ("err:" + (c.renders?.bm?.error || "?"));
  tally[v.slice(0, 30)] = (tally[v.slice(0, 30)] || 0) + 1;
  if (v !== "identical") console.log(c.id.padEnd(28), String(v).padEnd(12), m && m.ssim != null ? `ssim ${Math.min(m.ssim, m.ssimRgb).toFixed(4)} pct ${m.pctStrict.toFixed(3)} max ${m.maxAbs} mean ${m.meanAbs.toFixed(3)}` : (c.renders?.bm?.error || ""));
}
console.log(tally);
