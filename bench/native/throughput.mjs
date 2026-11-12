// Throughput under concurrency, one fresh process per configuration (spawned by bench/run-native.mjs, which sets
// UV_THREADPOOL_SIZE in the environment).
//
//   node native/throughput.mjs <engine> <mode> [--k=K] [--n=1,2,4,8,16] [--ms=2000]
//
// Workload: the og card fixture (card-og, 1200x630) to PNG, over and over. N clients each keep one request in
// flight (closed loop) for `ms` milliseconds after a warm-up; result = completed images / second.
//   seq    one client calling the synchronous API in a loop (bm) or awaiting render() one at a time (takumi)
//   one    N clients on ONE renderer, async render()
//   many   N clients on K renderers (client j uses renderer j mod K), async render()
//   pool   N clients on a worker_threads pool of K workers, each with its own engine instance (the recipe of
//          docs/examples/frameworks/lib/pool.mjs: a queue, idle workers, the PNG transferred back)
import os from "node:os";
import { Worker } from "node:worker_threads";
import { ALL_CASES } from "../fixtures/index.mjs";
import { renderOpts } from "../lib/pipeline.mjs";
import { createEngine } from "./engines.mjs";

const [engine, mode] = process.argv.slice(2);
const args = Object.fromEntries(process.argv.slice(4).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const K = +(args.k ?? 1);
const NS = String(args.n ?? "1,2,4,8,16").split(",").map(Number);
const MS = +(args.ms ?? 2000);
const k = ALL_CASES.find((c) => c.id === "card-og");
const opts = renderOpts(k, "png");

function makePool(size) {
  const idle = [], queue = [], pending = new Map();
  let next = 0;
  const workers = Array.from({ length: size }, () => {
    const w = new Worker(new URL("./pool-worker.mjs", import.meta.url), { workerData: { engine } });
    w.on("message", (m) => {
      if (m.ready) { idle.push(w); pump(); return; }
      const p = pending.get(m.id); pending.delete(m.id);
      m.error ? p.reject(new Error(m.error)) : p.resolve(m.png);
      idle.push(w); pump();
    });
    return w;
  });
  function pump() { while (idle.length && queue.length) idle.pop().postMessage(queue.shift()); }
  const ready = Promise.all(workers.map((w) => new Promise((r) => { const f = (m) => { if (m.ready) { w.off("message", f); r(); } }; w.on("message", f); })));
  return {
    ready,
    render: () => new Promise((resolve, reject) => { const id = next++; pending.set(id, { resolve, reject }); queue.push({ id }); pump(); }),
    close: () => Promise.all(workers.map((w) => w.terminate())),
  };
}

let render, close = async () => {};
let renderers = [];
if (mode === "pool") {
  const pool = makePool(K);
  await pool.ready;
  render = () => pool.render();
  close = pool.close;
} else {
  const count = mode === "many" ? K : 1;
  for (let i = 0; i < count; i++) renderers.push(await createEngine(engine, k.fonts));
  close = async () => renderers.forEach((e) => e.dispose());
}
const clientRender = (j) => {
  if (mode === "pool") return render();
  const e = renderers[j % renderers.length];
  if (mode === "seq") return e.sync ? e.sync(k.node, opts) : e.async(k.node, opts);
  return e.async(k.node, opts);
};

async function run(n, ms) {
  let done = 0, stop = false, bytes = 0;
  const t0 = performance.now(), c0 = process.cpuUsage();
  const client = async (j) => { while (!stop) { const out = await clientRender(j); bytes = out.length ?? out.byteLength; done++; if (performance.now() - t0 >= ms) stop = true; } };
  await Promise.all(Array.from({ length: n }, (_, j) => client(j)));
  const s = (performance.now() - t0) / 1000;
  const c = process.cpuUsage(c0);
  return { n, images: done, seconds: +s.toFixed(3), ips: +(done / s).toFixed(1), cpuMs: +((c.user + c.system) / 1000).toFixed(0), bytes };
}

const results = [];
for (const n of mode === "seq" ? [1] : NS) {
  await run(n, Math.min(400, MS / 4)); // warm-up (code, caches, thread pools)
  results.push(await run(n, MS));
}
await close();
console.log(JSON.stringify({ engine, mode, k: mode === "many" || mode === "pool" ? K : 1, uv: +(process.env.UV_THREADPOOL_SIZE || 4), cpus: os.availableParallelism(), results }));
process.exit(0);
