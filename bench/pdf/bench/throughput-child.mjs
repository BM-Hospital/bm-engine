// Throughput under concurrency, one fresh process per configuration (spawned by bench/pdf/bench.mjs, which sets
// UV_THREADPOOL_SIZE).
//
//   node bench/pdf/bench/throughput-child.mjs <engine> <mode> [--k=K] [--n=1,2,4,8] [--ms=2000]
//
// Workload: the guide's one-page A4 invoice (docs/invoice), over and over. N clients each keep one request in
// flight (closed loop) for `ms` after a warm-up; result = PDFs / second.
//   seq    one client, synchronous API (bm) or awaiting render() one at a time (takumi-pdf)
//   many   N clients on K renderers (client j uses renderer j mod K), async render() (bm-native: libuv pool)
//   pool   N clients on a worker_threads pool of K workers, each with its own engine instance
import os from "node:os";
import { Worker } from "node:worker_threads";
import { loadCorpus, EnginePool, inputs } from "../corpus/index.mjs";

const [engine, mode] = process.argv.slice(2);
const args = Object.fromEntries(process.argv.slice(4).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const K = +(args.k ?? 1);
const NS = String(args.n ?? "1,2,4,8").split(",").map(Number);
const MS = +(args.ms ?? 2000);
const DOC = "docs/invoice";

function makePool(size) {
  const idle = [], queue = [], pending = new Map();
  let next = 0;
  const workers = Array.from({ length: size }, () => {
    const w = new Worker(new URL("./pool-worker.mjs", import.meta.url), { workerData: { engine, doc: DOC } });
    w.on("message", (m) => {
      if (m.ready) { idle.push(w); pump(); return; }
      const p = pending.get(m.id); pending.delete(m.id);
      m.error ? p.reject(new Error(m.error)) : p.resolve(m.bytes);
      idle.push(w); pump();
    });
    w.on("error", (e) => { for (const p of pending.values()) p.reject(e); });
    return w;
  });
  function pump() { while (idle.length && queue.length) idle.pop().postMessage(queue.shift()); }
  const ready = Promise.all(workers.map((w) => new Promise((r) => { const f = (m) => { if (m.ready) { w.off("message", f); r(); } }; w.on("message", f); })));
  return { ready, render: () => new Promise((resolve, reject) => { const id = next++; pending.set(id, { resolve, reject }); queue.push({ id }); pump(); }), close: () => Promise.all(workers.map((w) => w.terminate())) };
}

let clientRender, close = async () => {};
if (mode === "pool") {
  const pool = makePool(K);
  await pool.ready;
  clientRender = () => pool.render();
  close = pool.close;
} else {
  const { docs } = await loadCorpus({ filter: "^" + DOC + "$" });
  const doc = docs[0];
  const engines = [];
  for (let i = 0; i < (mode === "many" ? K : 1); i++) {
    const p = new EnginePool();
    const { e, families } = await p.get(engine, doc.fonts);
    engines.push({ e, ...inputs(doc, families) });
  }
  clientRender = (j) => {
    const x = engines[j % engines.length];
    if (mode === "seq" && x.e.renderSync) return x.e.renderSync(x.source, x.options);
    return x.e.render(x.source, x.options);
  };
  close = async () => engines.forEach((x) => x.e.dispose());
}

async function run(n, ms) {
  let done = 0, stop = false, bytes = 0;
  const t0 = performance.now(), c0 = process.cpuUsage();
  const client = async (j) => { while (!stop) { const out = await clientRender(j); bytes = out.length ?? out.byteLength; done++; if (performance.now() - t0 >= ms) stop = true; } };
  await Promise.all(Array.from({ length: n }, (_, j) => client(j)));
  const s = (performance.now() - t0) / 1000;
  const c = process.cpuUsage(c0);
  return { n, pdfs: done, seconds: +s.toFixed(3), pps: +(done / s).toFixed(1), cpuMs: +((c.user + c.system) / 1000).toFixed(0), bytes };
}
const results = [];
try {
  for (const n of mode === "seq" ? [1] : NS) {
    await run(n, Math.min(400, MS / 4));
    results.push(await run(n, MS));
  }
} catch (err) { results.push({ error: String(err?.message ?? err).slice(0, 200) }); }
await close();
console.log(JSON.stringify({ engine, mode, k: mode === "many" || mode === "pool" ? K : 1, uv: +(process.env.UV_THREADPOOL_SIZE || 4), cpus: os.availableParallelism(), results }));
process.exit(0);
