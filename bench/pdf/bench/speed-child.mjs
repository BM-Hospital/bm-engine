// One pass of the per-document render-time measurement (a child of bench/pdf/bench.mjs).
//
//   node bench/pdf/bench/speed-child.mjs --out=<file.json> [--quick] [--filter=<regex>]
//
// Variants (one engine instance per engine and font set, fonts registered before any timing):
//   bm-native:sync   PdfRenderer.renderSync on the main thread     bm-native:async  render() on the libuv pool
//   bm-wasm:sync     renderSync (pdf-profile wasm)                  bm-wasm:async    render() (same thread)
//   takumi-pdf:async render() (its only API; the wasm runs on the calling thread)
// Per document: `warmup` renders per variant, then rounds in which every variant renders once, in an order that
// rotates each round (a burst of load from other processes hits all variants alike). Per variant: median, p95,
// min, n, output bytes, CPU time spent inside the calls.
import { writeFileSync } from "node:fs";
import { loadCorpus, EnginePool, inputs } from "../corpus/index.mjs";
import { available } from "../engines.mjs";

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const quick = !!args.quick;
const cfg = quick ? { warmup: 1, minRounds: 5, minMs: 40, maxMs: 600 } : { warmup: 2, minRounds: 12, minMs: 200, maxMs: 3000 };
export const VARIANTS = [["bm-native", "sync"], ["bm-native", "async"], ["bm-wasm", "sync"], ["bm-wasm", "async"], ["takumi-pdf", "async"]];

const { docs } = await loadCorpus({ filter: args.filter ? String(args.filter) : null, maxStress: 10 });
const selected = docs.filter((d) => !quick || d.group !== "golden" || /gradients|box-shadows|collapsed-table|text-|report-links|invoice-pdfa-2b|table-tagged/.test(d.id));
const variants = [];
for (const v of VARIANTS) if (await available(v[0])) variants.push(v);
const pool = new EnginePool({ keep: 1 });
const stats = (t) => { const s = [...t].sort((a, b) => a - b); const q = (p) => s[Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5))]; return { median: +q(0.5).toFixed(4), p95: +q(0.95).toFixed(4), min: +s[0].toFixed(4), n: s.length }; };
const cpuNow = () => { const c = process.cpuUsage(); return (c.user + c.system) / 1000; };
const out = { date: new Date().toISOString(), quick, cfg, variants: variants.map((v) => v.join(":")), cases: [] };
const t0 = performance.now(), cpu0 = cpuNow();
let idx = 0;
for (const d of selected) {
  idx++;
  const row = { id: d.id, group: d.group, perf: {} };
  const live = [];
  for (const [n, api] of variants) {
    const v = `${n}:${api}`;
    try {
      const { e, families } = await pool.get(n, d.fonts);
      const { source, options } = inputs(d, families);
      const fn = api === "sync" ? e.renderSync : e.render;
      if (!fn) continue;
      const call = () => fn(source, options);
      let bytes = 0;
      for (let i = 0; i < cfg.warmup; i++) bytes = (api === "sync" ? call() : await call()).length;
      live.push({ v, api, call, times: [], cpu: 0, bytes });
    } catch (err) { row.perf[v] = { error: String(err?.message ?? err).split("\n")[0].slice(0, 300) }; }
  }
  const start = performance.now();
  for (let round = 0; live.length; round++) {
    for (let j = 0; j < live.length; j++) {
      const t = live[(j + round) % live.length];
      const c0 = cpuNow(), a = performance.now();
      if (t.api === "sync") t.call(); else await t.call();
      t.times.push(performance.now() - a); t.cpu += cpuNow() - c0;
    }
    const el = performance.now() - start;
    if ((round + 1 >= cfg.minRounds && el >= cfg.minMs) || el >= cfg.maxMs) break;
  }
  for (const t of live) row.perf[t.v] = { ...stats(t.times), bytes: t.bytes, cpuMs: +(t.cpu / t.times.length).toFixed(3) };
  out.cases.push(row);
  if (idx % 20 === 0 || idx === selected.length) process.stderr.write(`  speed ${idx}/${selected.length} ${((performance.now() - t0) / 1000).toFixed(0)}s\n`);
}
pool.dispose();
out.durationMs = +(performance.now() - t0).toFixed(0);
out.cpuMs = +(cpuNow() - cpu0).toFixed(0);
writeFileSync(args.out, JSON.stringify(out));
process.exit(0);
