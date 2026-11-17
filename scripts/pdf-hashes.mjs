#!/usr/bin/env node
// Output fingerprint of the bench/pdf corpus (takumi-pdf golden inputs, guide documents, stress documents up to
// 100 pages): the SHA-256 of every rendered file, to check that a refactor changes no byte.
//
//   node scripts/pdf-hashes.mjs --write=<file.json>       render and save the hashes
//   node scripts/pdf-hashes.mjs --check=<file.json>       render and compare (exit 1 on any difference)
//   --engine=bm-native | bm-wasm (default bm-native)       --filter=<regex on the document id>
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const arg = (k) => process.argv.slice(2).find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? null;
const engine = arg("engine") ?? "bm-native";
const { loadCorpus, EnginePool, inputs } = await import(pathToFileURL(path.join(ROOT, "bench", "pdf", "corpus", "index.mjs")).href);
const { docs } = await loadCorpus({ filter: arg("filter"), maxStress: 100 });
const pool = new EnginePool({ keep: 1 });
const out = {};
for (const doc of docs) {
  const { e, families } = await pool.get(engine, doc.fonts);
  const { source, options } = inputs(doc, families);
  try {
    const bytes = await e.render(source, options);
    out[doc.id] = createHash("sha256").update(bytes).digest("hex");
  } catch (err) {
    out[doc.id] = "error: " + String(err?.message ?? err).slice(0, 200);
  }
}
pool.dispose();
const write = arg("write");
const check = arg("check");
if (write) writeFileSync(write, JSON.stringify(out, null, 1));
if (check) {
  const want = JSON.parse(readFileSync(check, "utf8"));
  const ids = [...new Set([...Object.keys(want), ...Object.keys(out)])].sort();
  const diff = ids.filter((id) => want[id] !== out[id]);
  for (const id of diff) console.log(`DIFF ${id}: ${want[id] ?? "(missing)"} -> ${out[id] ?? "(missing)"}`);
  console.log(`${ids.length - diff.length}/${ids.length} identical (${engine})`);
  process.exitCode = diff.length ? 1 : 0;
} else console.log(`${Object.keys(out).length} documents hashed (${engine})`);
