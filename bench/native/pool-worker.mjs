// Worker of throughput.mjs's worker_threads pool: its own engine instance with the card's fonts, renders the og
// card to PNG on each message and transfers the bytes back (no copy).
import { parentPort, workerData } from "node:worker_threads";
import { ALL_CASES } from "../fixtures/index.mjs";
import { renderOpts } from "../lib/pipeline.mjs";
import { createEngine } from "./engines.mjs";

const k = ALL_CASES.find((c) => c.id === "card-og");
const opts = renderOpts(k, "png");
const e = await createEngine(workerData.engine, k.fonts);
parentPort.on("message", async ({ id }) => {
  try {
    const out = e.sync ? e.sync(k.node, opts) : await e.async(k.node, opts);
    const png = out.byteOffset === 0 && out.byteLength === out.buffer.byteLength ? out : out.slice();
    parentPort.postMessage({ id, png }, [png.buffer]);
  } catch (err) {
    parentPort.postMessage({ id, error: String(err?.message ?? err) });
  }
});
parentPort.postMessage({ ready: true });
