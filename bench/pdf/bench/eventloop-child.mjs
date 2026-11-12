// Event-loop blocking probe, one fresh process per (engine, api) (spawned by bench/pdf/bench.mjs).
//
//   node bench/pdf/bench/eventloop-child.mjs <engine> <sync|async> [--pages=100]
//
// A 1 ms setInterval records the gap between consecutive ticks while one render of the <pages>-page stress document
// runs (a setImmediate chain keeps the loop polling so the timer has ~1 ms resolution on Windows, as in
// bench/native/eventloop.mjs). Reports render time, the longest timer gap (max delay), p99 gap, tick count.
import { stressCorpus, EnginePool, inputs } from "../corpus/index.mjs";

const [engine, api] = process.argv.slice(2);
const args = Object.fromEntries(process.argv.slice(4).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const pages = +(args.pages ?? 100);
const [doc] = stressCorpus([pages]);
const [warm] = stressCorpus([1]);
const pool = new EnginePool();
const { e, families } = await pool.get(engine, doc.fonts);
const fn = api === "sync" ? e.renderSync : e.render;
if (!fn) { console.log(JSON.stringify({ engine, api, pages, unsupported: true })); process.exit(0); }
const w = inputs(warm, families); await e.render(w.source, w.options);
const { source, options } = inputs(doc, families);

let stopSpin = false, done = false;
const spin = () => { if (!stopSpin) setImmediate(spin); };
setImmediate(spin);
const gaps = [];
let last = performance.now(), after = 0;
const timer = setInterval(() => { const now = performance.now(); if (!done || after++ === 0) gaps.push(now - last); last = now; }, 1);
await new Promise((r) => setTimeout(r, 300));
const idle = gaps.splice(0).sort((a, b) => a - b);
last = performance.now();
const t0 = performance.now();
let out, error = null;
try { out = api === "sync" ? fn(source, options) : await fn(source, options); } catch (err) { error = String(err?.message ?? err).slice(0, 200); }
const ms = performance.now() - t0;
done = true;
await new Promise((r) => setTimeout(r, 20));
clearInterval(timer); stopSpin = true;
const s = (gaps.length ? gaps : [ms]).sort((a, b) => a - b);
const q = (arr, p) => arr[Math.min(arr.length - 1, Math.floor(p * (arr.length - 1) + 0.5))];
console.log(JSON.stringify({ engine, api, pages, ms: +ms.toFixed(1), maxDelayMs: +s.at(-1).toFixed(1), p99DelayMs: +q(s, 0.99).toFixed(1), ticks: gaps.length, idleMaxMs: +idle.at(-1).toFixed(1), idleP99Ms: +q(idle, 0.99).toFixed(1), bytes: out?.length ?? null, error }));
process.exit(0);
