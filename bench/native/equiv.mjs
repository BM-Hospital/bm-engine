// Output equivalence of the four engines (a child of bench/run-native.mjs).
//
//   node native/equiv.mjs --out=<file.json> [--filter=<regex>]
//
// Every fixture is rendered to raw RGBA by each engine (async API) and compared with the existing comparer
// (lib/pipeline.mjs compareRenders -> lib/metrics.mjs verdicts) against takumi-wasm, the reference of every
// earlier phase. In addition, byte identity of raw RGBA and of the PNG file between the two builds of each
// engine (bm-native vs bm-wasm, takumi-native vs takumi-wasm).
import { writeFileSync } from "node:fs";
import { selectCases } from "../fixtures/index.mjs";
import { renderOpts, compareRenders } from "../lib/pipeline.mjs";
import { createEngine, ENGINES } from "./engines.mjs";

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const engines = new Map();
async function enginesFor(families) {
  const key = families ? families.join(",") : "*";
  if (!engines.has(key)) { const m = {}; for (const n of ENGINES) m[n] = await createEngine(n, families); engines.set(key, m); }
  return engines.get(key);
}
const attempt = async (fn) => { try { return { bytes: await fn() }; } catch (e) { return { error: String(e?.message ?? e).split("\n")[0] }; } };
const same = (a, b) => (a.error !== undefined || b.error !== undefined ? a.error === b.error : Buffer.compare(Buffer.from(a.bytes), Buffer.from(b.bytes)) === 0);

const cases = selectCases(args.filter);
const CANDS = ["bm-native", "bm-wasm", "takumi-native"];
const verdicts = Object.fromEntries(CANDS.map((n) => [n, {}]));
const pairs = { "bm-native=bm-wasm": { raw: 0, png: 0 }, "takumi-native=takumi-wasm": { raw: 0, png: 0 } };
const rows = [];
for (const k of cases) {
  const eng = await enginesFor(k.fonts);
  const raw = {}, png = {};
  for (const n of ENGINES) {
    raw[n] = await attempt(() => eng[n].async(k.node, renderOpts(k, "raw")));
    png[n] = await attempt(() => eng[n].async(k.node, renderOpts(k, "png")));
  }
  const row = { id: k.id, feature: k.feature, cmp: {}, identical: {} };
  const ref = raw["takumi-wasm"].error ? { error: raw["takumi-wasm"].error } : { rgba: raw["takumi-wasm"].bytes };
  for (const n of CANDS) {
    const c = compareRenders(k, ref, raw[n].error ? { error: raw[n].error } : { rgba: raw[n].bytes });
    delete c._diff;
    row.cmp[n] = { verdict: c.verdict, ssim: c.ssim, ssimRgb: c.ssimRgb, pctStrict: c.pctStrict, maxAbs: c.maxAbs };
    verdicts[n][c.verdict] = (verdicts[n][c.verdict] ?? 0) + 1;
  }
  for (const [p, [a, b]] of Object.entries({ "bm-native=bm-wasm": ["bm-native", "bm-wasm"], "takumi-native=takumi-wasm": ["takumi-native", "takumi-wasm"] })) {
    const r = same(raw[a], raw[b]), q = same(png[a], png[b]);
    pairs[p].raw += r; pairs[p].png += q;
    row.identical[p] = { raw: r, png: q };
  }
  rows.push(row);
}
for (const m of engines.values()) for (const e of Object.values(m)) e.dispose();
const out = { date: new Date().toISOString(), fixtures: cases.length, reference: "takumi-wasm", verdicts, identicalBytes: pairs, rows };
writeFileSync(args.out, JSON.stringify(out));
process.exit(0);
