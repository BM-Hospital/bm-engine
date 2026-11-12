// Worker of the pool example in docs/{en,vi}/image/performance.md (run by performance.mjs, not on its own).
// #region worker
// render-worker.mjs: one wasm instance + one renderer per worker, fonts registered once.
import { parentPort } from "node:worker_threads";
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });

parentPort.on("message", ({ id, node, options }) => {
  try {
    const bytes = renderer.renderSync(node, options);
    parentPort.postMessage({ id, bytes }, [bytes.buffer]); // transfer, do not copy
  } catch (err) {
    parentPort.postMessage({ id, error: err.message });
  }
});
// #endregion
