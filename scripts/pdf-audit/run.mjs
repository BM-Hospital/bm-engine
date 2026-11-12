// Runs the PDF audit probes: every scripts/pdf-audit/*.probe.mjs registers probes with lib.mjs's `probe()`.
//
//   node scripts/pdf-audit/run.mjs [--json] [--quiet] [filter ...]
//
//   TAKUMI_PDF_REF=<dir with node_modules/takumi-pdf>   compare with the published takumi-pdf (see lib.mjs)
//   BM_ENGINE_BACKEND=wasm | native                     the bm-engine backend (both must give the same result)
//
// Needs js/bm_engine.pdf.wasm (`node scripts/build.mjs --profile=pdf`). Writes bench/out/pdf-audit/results.json
// (the evidence column of docs/PDF_AUDIT.md). Exit code 1 when a probe fails.
import { readdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { bmMod, outDir, refMod, refVersion, runProbes } from "./lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const filter = argv.filter((a) => !a.startsWith("--"));
const quiet = argv.includes("--quiet");

for (const f of readdirSync(here).filter((n) => n.endsWith(".probe.mjs")).sort()) await import(pathToFileURL(path.join(here, f)).href);

console.log(`bm-engine/pdf backend: ${bmMod.backend}; reference: ${refMod ? "takumi-pdf " + refVersion : "not installed (set TAKUMI_PDF_REF): comparisons are unverified"}`);
const rows = await runProbes(filter);
let fail = 0; let pass = 0; let unverified = 0;
for (const r of rows) {
  if (r.status === "FAIL") fail++; else if (r.status === "UNVERIFIED") unverified++; else pass++;
  if (!quiet || r.status === "FAIL") console.log(`${r.status.padEnd(10)} ${r.id.padEnd(44)} ${r.pass} ok${r.fail ? ", " + r.fail + " failed" : ""}${r.unverified ? ", " + r.unverified + " unverified" : ""}`);
  for (const f of r.failures) console.log(`           - ${f}`);
  if (!quiet) for (const n of r.notes) console.log(`           . ${n}`);
}
writeFileSync(path.join(outDir, "results.json"), JSON.stringify({ backend: bmMod.backend, reference: refVersion, rows }, null, 1));
if (argv.includes("--json")) console.log(JSON.stringify(rows));
console.log(`\n${rows.length} probes: ${pass} pass, ${fail} fail, ${unverified} unverified (no reference)`);
process.exit(fail ? 1 : 0);
