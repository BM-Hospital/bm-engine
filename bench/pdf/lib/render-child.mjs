// Renders one corpus document with one engine in a fresh process (used for the large stress documents, so an
// engine that runs out of memory cannot take the whole run down). Prints one JSON line.
//
//   node bench/pdf/lib/render-child.mjs <engine> <doc id> <out.pdf> [--sync]
import { writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { loadCorpus, EnginePool, inputs } from "../corpus/index.mjs";

const [engine, id, out] = process.argv.slice(2);
const sync = process.argv.includes("--sync");
const { docs } = await loadCorpus({ filter: "^" + id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$" });
const doc = docs[0];
if (!doc) { console.log(JSON.stringify({ ok: false, error: "no such document " + id })); process.exit(0); }
const pool = new EnginePool();
const { e, families } = await pool.get(engine, doc.fonts);
const { source, options } = inputs(doc, families);
const t0 = performance.now();
try {
  const bytes = sync ? e.renderSync(source, options) : await e.render(source, options);
  const ms = performance.now() - t0;
  if (out) writeFileSync(out, bytes);
  const r = { ok: true, bytes: bytes.length, sha256: createHash("sha256").update(bytes).digest("hex"), ms: +ms.toFixed(1), engineMiB: e.memoryBytes() == null ? null : +(e.memoryBytes() / 2 ** 20).toFixed(1), peakRssMiB: +(process.resourceUsage().maxRSS / 1024).toFixed(1) };
  if (engine === "bm-native" && !sync) { const s = e.renderSync(source, doc.options()); r.syncSameBytes = createHash("sha256").update(s).digest("hex") === r.sha256; }
  console.log(JSON.stringify(r));
} catch (err) {
  console.log(JSON.stringify({ ok: false, error: String(err?.message ?? err).split("\n")[0].slice(0, 400), ms: +(performance.now() - t0).toFixed(1), engineMiB: e.memoryBytes() == null ? null : +(e.memoryBytes() / 2 ** 20).toFixed(1), peakRssMiB: +(process.resourceUsage().maxRSS / 1024).toFixed(1) }));
}
process.exit(0);
