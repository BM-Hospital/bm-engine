// One pass of the per-fixture render-time measurement (a child of bench/run-native.mjs).
//
//   node native/speed.mjs --out=<file.json> [--quick] [--filter=<regex>]
//
// Variants (one renderer per engine and font set, fonts registered before any timing):
//   bm-native:sync   renderSync on the main thread       bm-native:async  render() on the libuv pool
//   bm-wasm:sync     renderSync (full-profile wasm)
//   takumi-native:async  render() (takumi-native has no synchronous render)
//   takumi-wasm:async    render() (the public API; the work runs on the calling thread)
// For every fixture and format: `warmup` renders per variant, then rounds in which every variant renders once,
// in an order that rotates each round (interleaving: a burst of load from other processes hits all variants
// alike). Per variant: median, p95, min, n of the per-render wall times, output bytes, and the process CPU time
// spent inside its calls (cpuMs / wallMs > 1 means the engine used more than one core for one render).
import { writeFileSync } from "node:fs";
import { selectCases, FORMAT_CASES } from "../fixtures/index.mjs";
import { renderOpts } from "../lib/pipeline.mjs";
import { createEngine, ENGINES } from "./engines.mjs";

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const quick = !!args.quick;
const cfg = quick ? { warmup: 1, minRounds: 5, minMs: 25, maxMs: 400 } : { warmup: 3, minRounds: 15, minMs: 150, maxMs: 2500 };
export const VARIANTS = [
  ["bm-native", "sync"], ["bm-native", "async"], ["bm-wasm", "sync"], ["takumi-native", "async"], ["takumi-wasm", "async"],
];

const engines = new Map();
async function enginesFor(families) {
  const key = families ? families.join(",") : "*";
  if (!engines.has(key)) {
    const m = {};
    for (const n of ENGINES) m[n] = await createEngine(n, families);
    engines.set(key, m);
  }
  return engines.get(key);
}

function stats(times) {
  const s = [...times].sort((a, b) => a - b);
  const q = (p) => s[Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5))];
  return { median: +q(0.5).toFixed(4), p95: +q(0.95).toFixed(4), min: +s[0].toFixed(4), n: s.length };
}
const cpuNow = () => { const c = process.cpuUsage(); return (c.user + c.system) / 1000; };

const cases = selectCases(args.filter);
const out = { date: new Date().toISOString(), quick, cfg, cases: [] };
const t0 = performance.now(), cpu0 = cpuNow();
let idx = 0;
for (const k of cases) {
  idx++;
  const eng = await enginesFor(k.fonts);
  const row = { id: k.id, feature: k.feature, width: k.width, height: k.height, perf: {} };
  const formats = ["raw", "png", ...(FORMAT_CASES.includes(k.id) ? ["jpeg", "webp"] : [])];
  for (const f of formats) {
    const opts = renderOpts(k, f);
    const live = [];
    for (const [n, api] of VARIANTS) {
      const fn = eng[n][api];
      const v = `${n}:${api}`;
      const call = () => fn(k.node, opts);
      try {
        let bytes = 0;
        for (let i = 0; i < cfg.warmup; i++) bytes = (api === "sync" ? call() : await call()).length;
        live.push({ v, api, call, times: [], cpu: 0, wall: 0, bytes });
      } catch (e) {
        (row.perf[v] ??= {})[f] = { error: String(e?.message ?? e).split("\n")[0].slice(0, 300) };
      }
    }
    const start = performance.now();
    for (let round = 0; ; round++) {
      for (let j = 0; j < live.length; j++) {
        const t = live[(j + round) % live.length];
        const c0 = cpuNow(), a = performance.now();
        if (t.api === "sync") t.call(); else await t.call();
        const b = performance.now();
        t.times.push(b - a); t.wall += b - a; t.cpu += cpuNow() - c0;
      }
      const el = performance.now() - start;
      if ((round + 1 >= cfg.minRounds && el >= cfg.minMs) || el >= cfg.maxMs) break;
    }
    for (const t of live) (row.perf[t.v] ??= {})[f] = { ...stats(t.times), bytes: t.bytes, cpuMs: +t.cpu.toFixed(2), wallMs: +t.wall.toFixed(2) };
  }
  out.cases.push(row);
  if (!args.silent && (idx % 20 === 0 || idx === cases.length)) process.stderr.write(`  speed ${idx}/${cases.length} ${((performance.now() - t0) / 1000).toFixed(0)}s\n`);
}
for (const m of engines.values()) for (const e of Object.values(m)) e.dispose();
out.durationMs = +(performance.now() - t0).toFixed(0);
out.cpuMs = +(cpuNow() - cpu0).toFixed(0);
writeFileSync(args.out, JSON.stringify(out));
process.exit(0);
