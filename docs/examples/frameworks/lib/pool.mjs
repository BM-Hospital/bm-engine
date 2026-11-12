// A minimal worker_threads pool for bm-engine (recipes.md "worker_threads pool"). Each worker owns its own
// wasm instance and fonts (lib/render-worker.mjs); the PNG bytes are transferred back without copying.
import { Worker } from "node:worker_threads";
import { availableParallelism } from "node:os";

export function createPool(size = Math.max(1, availableParallelism() - 1), workerUrl = new URL("./render-worker.mjs", import.meta.url)) {
  const idle = [];
  const queue = [];
  const pending = new Map();
  let nextId = 0;
  const workers = Array.from({ length: size }, () => {
    const w = new Worker(workerUrl);
    w.on("message", ({ id, png, error }) => {
      const p = pending.get(id);
      pending.delete(id);
      error ? p.reject(new Error(error)) : p.resolve(png);
      idle.push(w);
      pump();
    });
    idle.push(w);
    return w;
  });
  function pump() {
    while (idle.length && queue.length) {
      const job = queue.shift();
      idle.pop().postMessage(job.msg);
    }
  }
  return {
    /** Renders `props` with the worker's template; resolves to the PNG bytes. */
    render(props, options) {
      return new Promise((resolve, reject) => {
        const id = nextId++;
        pending.set(id, { resolve, reject });
        queue.push({ msg: { id, props, options } });
        pump();
      });
    },
    close: () => Promise.all(workers.map((w) => w.terminate())),
  };
}
