// Worker of throughput-child.mjs's worker_threads pool: its own engine instance with the document's fonts; renders
// the document on each message and transfers the PDF bytes back.
import { parentPort, workerData } from "node:worker_threads";
import { loadCorpus, EnginePool, inputs } from "../corpus/index.mjs";

const { docs } = await loadCorpus({ filter: "^" + workerData.doc + "$" });
const doc = docs[0];
const { e, families } = await new EnginePool().get(workerData.engine, doc.fonts);
const { source, options } = inputs(doc, families);
parentPort.on("message", async ({ id }) => {
  try {
    const out = e.renderSync ? e.renderSync(source, options) : await e.render(source, options);
    const bytes = out.byteOffset === 0 && out.byteLength === out.buffer.byteLength ? out : out.slice();
    parentPort.postMessage({ id, bytes }, [bytes.buffer]);
  } catch (err) { parentPort.postMessage({ id, error: String(err?.message ?? err) }); }
});
parentPort.postMessage({ ready: true });
