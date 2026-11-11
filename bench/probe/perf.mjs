import { readFileSync } from "node:fs";
const r = JSON.parse(readFileSync(new URL("../out/results.json", import.meta.url), "utf8"));
const g = (xs) => Math.exp(xs.reduce((a, b) => a + Math.log(b), 0) / xs.length);
const rr = [], rp = [], sz = [];
const slow = [];
for (const c of r.cases) {
  const t = c.perf?.["takumi-wasm"], b = c.perf?.bm; if (!t?.raw || !b?.raw) continue;
  const a = b.raw.median / t.raw.median, p = b.png.median / t.png.median;
  rr.push(a); rp.push(p); sz.push(b.png.bytes / t.png.bytes);
  if (a > 1.1 || p > 1.1) slow.push(`${c.id.padEnd(28)} raw ${b.raw.median.toFixed(2)} vs ${t.raw.median.toFixed(2)} (${a.toFixed(2)})  png ${b.png.median.toFixed(2)} vs ${t.png.median.toFixed(2)} (${p.toFixed(2)})`);
}
console.log("geomean raw ratio", g(rr).toFixed(3), "png ratio", g(rp).toFixed(3), "png bytes ratio", g(sz).toFixed(3), "n", rr.length);
console.log(slow.join("\n"));
