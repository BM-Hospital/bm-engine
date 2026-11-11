import { readFileSync } from "node:fs";
const r = JSON.parse(readFileSync(new URL("../out/results.json", import.meta.url), "utf8"));
const g = (xs) => xs.length ? Math.exp(xs.reduce((a, b) => a + Math.log(b), 0) / xs.length) : NaN;
const by = new Map();
for (const c of r.cases) { if (!by.has(c.feature)) by.set(c.feature, []); by.get(c.feature).push(c); }
const f2 = (v) => Number.isFinite(v) ? v.toFixed(2) : "–";
console.log("| Tính năng | số ca | raw: takumi-wasm ms | raw: bm ms | bm/takumi | png: takumi-wasm ms | png: bm ms | bm/takumi | PNG bytes bm/takumi | takumi-native raw ms | tương đương (identical/equivalent/close/different/error) | SSIM thấp nhất | % px lệch (TB) |");
console.log("|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--|--:|--:|");
const all = { tr: [], br: [], tp: [], bp: [], sz: [], nr: [] };
for (const [feat, cs] of by) {
  const ok = cs.filter((c) => c.perf?.bm?.raw && c.perf?.["takumi-wasm"]?.raw);
  const tr = ok.map((c) => c.perf["takumi-wasm"].raw.median), br = ok.map((c) => c.perf.bm.raw.median);
  const tp = ok.map((c) => c.perf["takumi-wasm"].png.median), bp = ok.map((c) => c.perf.bm.png.median);
  const sz = ok.map((c) => c.perf.bm.png.bytes / c.perf["takumi-wasm"].png.bytes);
  const nr = ok.filter((c) => c.perf["takumi-native"]?.raw).map((c) => c.perf["takumi-native"].raw.median);
  if (feat !== "known-gaps") { all.tr.push(...tr); all.br.push(...br); all.tp.push(...tp); all.bp.push(...bp); all.sz.push(...sz); all.nr.push(...nr); }
  const v = { identical: 0, equivalent: 0, close: 0, different: 0, error: 0 };
  let minS = 1, pct = 0, n = 0;
  for (const c of cs) { const m = c.cmp?.bm; const k = (m?.verdict || "error").startsWith("error") ? "error" : m.verdict; v[k]++; if (m?.ssim != null) { minS = Math.min(minS, m.ssim, m.ssimRgb); pct += m.pctStrict; n++; } }
  console.log(`| ${feat} | ${cs.length} | ${f2(g(tr))} | ${f2(g(br))} | ${f2(g(br) / g(tr))} | ${f2(g(tp))} | ${f2(g(bp))} | ${f2(g(bp) / g(tp))} | ${f2(g(sz))} | ${f2(g(nr))} | ${v.identical}/${v.equivalent}/${v.close}/${v.different}/${v.error} | ${n ? minS.toFixed(4) : "–"} | ${n ? (pct / n).toFixed(3) : "–"} |`);
}
console.log(`| **Tất cả (trừ known-gaps), geomean** | ${all.tr.length} | ${f2(g(all.tr))} | ${f2(g(all.br))} | **${f2(g(all.br) / g(all.tr))}** | ${f2(g(all.tp))} | ${f2(g(all.bp))} | **${f2(g(all.bp) / g(all.tp))}** | **${f2(g(all.sz))}** | ${f2(g(all.nr))} | | | |`);
let w = 0, l = 0, wp = 0, lp = 0;
for (const c of r.cases) { const t = c.perf?.["takumi-wasm"], b = c.perf?.bm; if (!t?.raw || !b?.raw || c.feature === "known-gaps") continue; if (b.raw.median < t.raw.median) w++; else l++; if (b.png.median < t.png.median) wp++; else lp++; }
console.log("\nraw: bm nhanh hơn ở", w, "ca, chậm hơn ở", l, "| png: nhanh hơn", wp, "chậm hơn", lp);
console.log("\nformats:", JSON.stringify(r.cases.filter((c) => c.perf?.bm?.jpeg).map((c) => ({ id: c.id, bm_jpeg: [c.perf.bm.jpeg.median.toFixed(2), c.perf.bm.jpeg.bytes], tk_jpeg: [c.perf["takumi-wasm"].jpeg.median.toFixed(2), c.perf["takumi-wasm"].jpeg.bytes], bm_webp: [c.perf.bm.webp.median.toFixed(2), c.perf.bm.webp.bytes], tk_webp: [c.perf["takumi-wasm"].webp.median.toFixed(2), c.perf["takumi-wasm"].webp.bytes], bm_png: [c.perf.bm.png.median.toFixed(2), c.perf.bm.png.bytes], tk_png: [c.perf["takumi-wasm"].png.median.toFixed(2), c.perf["takumi-wasm"].png.bytes] })), null, 0));
