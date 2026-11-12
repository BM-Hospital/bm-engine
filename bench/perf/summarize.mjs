// Reads a native benchmark result (bench/out/native/results-native.json, written by bench/run-native.mjs) and
// prints what the performance work is judged by: the raw / PNG geomean ratios against takumi-native, and every
// fixture on which bm-native is still slower than takumi-native by more than a factor.
//
//   node bench/perf/summarize.mjs [results-native.json] [--factor=1.3] [--baseline=<other results json>]
//
// With --baseline the same ratios of another run (e.g. docs/results-native.json of the previous phase) are shown
// next to each fixture.
import { readFileSync } from "node:fs";
import path from "node:path";
import { ROOT_DIR } from "../lib/assets.mjs";

const args = Object.fromEntries(process.argv.slice(2).filter((a) => a.startsWith("--")).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return [m[1], m[2] ?? true]; }));
const file = process.argv.slice(2).find((a) => !a.startsWith("--")) ?? path.join(ROOT_DIR, "bench", "out", "native", "results-native.json");
const factor = +(args.factor ?? 1.3);
const load = (f) => JSON.parse(readFileSync(f, "utf8")).speed;
const s = load(file);
const base = args.baseline ? load(String(args.baseline)) : null;
const geo = (a) => Math.exp(a.reduce((x, y) => x + Math.log(y), 0) / a.length);
const med = (r, v, f) => r.perf?.[v]?.[f]?.median;
const ratioRows = (sp, num, den, f) => sp.fixtures.filter((r) => med(r, num, f) > 0 && med(r, den, f) > 0).map((r) => ({ id: r.id, ratio: med(r, num, f) / med(r, den, f), a: med(r, num, f), b: med(r, den, f) }));

const pairs = [["bm-native:async", "takumi-native:async"], ["bm-native:sync", "takumi-native:async"], ["bm-wasm:sync", "takumi-wasm:async"], ["bm-native:sync", "bm-wasm:sync"]];
console.log(`${file}\n`);
console.log("geomean of per-fixture time ratios (below 1 = the first engine is faster)");
for (const [num, den] of pairs) for (const f of ["raw", "png"]) {
  const rows = ratioRows(s, num, den, f);
  if (!rows.length) continue;
  const faster = rows.filter((r) => r.ratio < 1).length;
  const b = base ? ratioRows(base, num, den, f) : null;
  console.log(`  ${(num + " / " + den).padEnd(42)} ${f.padEnd(4)} ${geo(rows.map((r) => r.ratio)).toFixed(3)}x  (faster on ${faster}/${rows.length}, range ${Math.min(...rows.map((r) => r.ratio)).toFixed(2)}x-${Math.max(...rows.map((r) => r.ratio)).toFixed(2)}x)` +
    (b && b.length ? `   baseline ${geo(b.map((r) => r.ratio)).toFixed(3)}x` : ""));
}
console.log("\ngeomean ms");
for (const v of ["bm-native:sync", "bm-native:async", "bm-wasm:sync", "takumi-native:async", "takumi-wasm:async"]) {
  const line = ["raw", "png"].map((f) => { const m = s.fixtures.map((r) => med(r, v, f)).filter((x) => x > 0); return m.length ? `${f} ${geo(m).toFixed(3)}` : ""; }).join("   ");
  console.log(`  ${v.padEnd(22)} ${line}`);
}
for (const f of ["raw", "png"]) {
  const rows = ratioRows(s, "bm-native:async", "takumi-native:async", f).filter((r) => r.ratio > factor).sort((x, y) => y.ratio - x.ratio);
  const bmap = base ? new Map(ratioRows(base, "bm-native:async", "takumi-native:async", f).map((r) => [r.id, r.ratio])) : null;
  console.log(`\n${f}: bm-native async slower than takumi-native by more than ${factor}x on ${rows.length} fixtures`);
  for (const r of rows) console.log(`  ${r.id.padEnd(34)} ${r.ratio.toFixed(2)}x  (${r.a.toFixed(2)} vs ${r.b.toFixed(2)} ms)` + (bmap && bmap.has(r.id) ? `   baseline ${bmap.get(r.id).toFixed(2)}x` : ""));
}
