// Scaling probe, one fresh process per (engine, page count) (spawned by bench/pdf/bench.mjs).
//
//   node --expose-gc bench/pdf/bench/scale-child.mjs <engine> <pages> [--reps=N] [--sync]
//
// Warms the engine with the 1-page stress document, then renders the <pages>-page stress document `reps` times
// (bench/pdf/corpus/docs.mjs stressHtml: per page a heading, paragraphs, a 14-row table and an image). Reports
// per-render times, pages/s, output bytes, peak RSS of the process and the engine's memory (wasm linear memory or
// native live allocation) after the renders. Prints one JSON line (an error line when the engine fails).
import { stressCorpus, EnginePool, inputs } from "../corpus/index.mjs";

const [engine, pagesArg] = process.argv.slice(2);
const args = Object.fromEntries(process.argv.slice(4).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const pages = +pagesArg;
const reps = +(args.reps ?? 1);
const [warmDoc] = stressCorpus([1]);
const [doc] = stressCorpus([pages]);
const pool = new EnginePool();
const { e, families } = await pool.get(engine, doc.fonts);
const MiB = 2 ** 20;
const rss = () => +(process.memoryUsage().rss / MiB).toFixed(1);
const peak = () => +(process.resourceUsage().maxRSS / 1024).toFixed(1);
const eng = () => (e.memoryBytes() == null ? null : +(e.memoryBytes() / MiB).toFixed(1));
const w = inputs(warmDoc, families);
await e.render(w.source, w.options);
global.gc?.();
const before = { rssMiB: rss(), peakRssMiB: peak(), engineMiB: eng() };
const { source, options } = inputs(doc, families);
const times = [];
let bytes = 0;
try {
  for (let i = 0; i < reps; i++) {
    const t0 = performance.now();
    const out = args.sync ? e.renderSync(source, options) : await e.render(source, options);
    times.push(performance.now() - t0);
    bytes = out.length;
  }
  const s = [...times].sort((a, b) => a - b);
  const med = s[s.length >> 1];
  console.log(JSON.stringify({ engine, pages, reps, ok: true, ms: +med.toFixed(1), minMs: +s[0].toFixed(1), times: times.map((t) => +t.toFixed(1)), pagesPerSec: +((pages * 1000) / med).toFixed(1), bytes, bytesPerPage: Math.round(bytes / pages), before, after: { rssMiB: rss(), peakRssMiB: peak(), engineMiB: eng() } }));
} catch (err) {
  console.log(JSON.stringify({ engine, pages, reps, ok: false, error: String(err?.message ?? err).split("\n")[0].slice(0, 300), before, after: { rssMiB: rss(), peakRssMiB: peak(), engineMiB: eng() } }));
}
process.exit(0);
