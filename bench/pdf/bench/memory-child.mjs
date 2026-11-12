// Memory probe, one fresh process per engine (spawned by bench/pdf/bench.mjs with --expose-gc).
//
//   node --expose-gc bench/pdf/bench/memory-child.mjs <engine> [--passes=10]
//
// Renders the guide documents (bench/pdf/corpus/docs.mjs: invoice, report, ticket, ..., PDF/A, tagged) `passes`
// times with one engine instance per font set; after pass 1 and after the last pass: GC, then RSS, V8 heap,
// external, and the engine's own memory (bm: Renderer.memoryBytes = wasm linear memory size or the native addon's
// live allocation; takumi-pdf: wasm linear memory size).
import { loadCorpus, EnginePool, inputs } from "../corpus/index.mjs";

const [engine] = process.argv.slice(2);
const args = Object.fromEntries(process.argv.slice(3).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const passes = +(args.passes ?? 10);
const { docs } = await loadCorpus({ filter: "^docs/" });
const MiB = 2 ** 20;
const pool = new EnginePool();
let any;
const snap = () => {
  global.gc?.(); global.gc?.();
  const m = process.memoryUsage();
  return { rssMiB: +(m.rss / MiB).toFixed(1), heapUsedMiB: +(m.heapUsed / MiB).toFixed(1), externalMiB: +(m.external / MiB).toFixed(1), engineMiB: any?.memoryBytes() == null ? null : +(any.memoryBytes() / MiB).toFixed(1), peakRssMiB: +(process.resourceUsage().maxRSS / 1024).toFixed(1) };
};
const out = { engine, passes, docs: docs.length, before: snap(), after: [] };
let errors = 0;
for (let p = 1; p <= passes; p++) {
  const t0 = performance.now();
  for (const d of docs) {
    const { e, families } = await pool.get(engine, d.fonts);
    any = e;
    const { source, options } = inputs(d, families);
    try { await e.render(source, options); } catch { errors++; }
  }
  if (p === 1 || p === passes) out.after.push({ pass: p, seconds: +((performance.now() - t0) / 1000).toFixed(2), ...snap() });
}
out.renderers = pool.map.size;
out.errors = errors;
const c = process.cpuUsage();
out.cpuMs = (c.user + c.system) / 1000;
console.log(JSON.stringify(out));
process.exit(0);
