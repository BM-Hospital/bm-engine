// Worker side of lib/pool.mjs: imports bm-render (its own wasm instance), registers fonts once, renders jobs.
import { parentPort } from "node:worker_threads";
import { getRenderer, card } from "./og.mjs";

parentPort.on("message", ({ id, props, options }) => {
  try {
    const png = getRenderer().renderSync(card(props), options);
    parentPort.postMessage({ id, png }, [png.buffer]); // transfer, no copy
  } catch (error) {
    parentPort.postMessage({ id, error: String(error?.message ?? error) });
  }
});
