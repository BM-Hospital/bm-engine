// Runs the PDF audit probes: every scripts/pdf-audit/*.probe.mjs registers probes with lib.mjs's `probe()`.
//
//   node scripts/pdf-audit/run.mjs [--json] [--quiet] [filter ...]
//
//   TAKUMI_PDF_REF=<dir with node_modules/takumi-pdf>   compare with the published takumi-pdf (see lib.mjs)
//   BM_RENDER_BACKEND=wasm | native                     the bm-render backend (both must give the same result)
//
// Needs js/bm_render.pdf.wasm (`node scripts/build.mjs --profile=pdf`). Writes bench/out/pdf-audit/results.json
// (the evidence column of docs/PDF_AUDIT.md). Exit code 1 when a probe fails.
import { readdirSync, writeFileSync, writeSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { bmMod, outDir, refMod, refVersion, runProbes } from "./lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
for (const arg of argv) if (arg.startsWith('--') && !['--json', '--quiet', '--strict'].includes(arg)) throw new Error(`Unknown PDF audit option: ${arg}`);
const filter = argv.filter((a) => !a.startsWith("--"));
const quiet = argv.includes("--quiet");
// The report is written synchronously: on Windows stdout to a pipe is asynchronous, and a process
// that loaded native addons (bm-render, @napi-rs/canvas for pdf.js) can end before it is flushed.
const say = (line) => writeSync(1, line + "\n");

for (const f of readdirSync(here).filter((n) => n.endsWith(".probe.mjs")).sort()) await import(pathToFileURL(path.join(here, f)).href);

say(`bm-render/pdf backend: ${bmMod.backend}; reference: ${refMod ? "takumi-pdf " + refVersion : "not installed (set TAKUMI_PDF_REF): comparisons are unverified"}`);
const rows = await runProbes(filter);
if (rows.length === 0) throw new Error(`No PDF audit probes matched: ${filter.join(", ") || "(all)"}`);
let fail = 0; let pass = 0; let unverified = 0;
for (const r of rows) {
  if (r.status === "FAIL") fail++; else if (r.status === "UNVERIFIED") unverified++; else pass++;
  if (!quiet || r.status === "FAIL") say(`${r.status.padEnd(10)} ${r.id.padEnd(44)} ${r.pass} ok${r.fail ? ", " + r.fail + " failed" : ""}${r.unverified ? ", " + r.unverified + " unverified" : ""}`);
  for (const f of r.failures) say(`           - ${f}`);
  if (!quiet) for (const n of r.notes) say(`           . ${n}`);
}
writeFileSync(path.join(outDir, "results.json"), JSON.stringify({ backend: bmMod.backend, reference: refVersion, rows }, null, 1));
if (argv.includes("--json")) say(JSON.stringify(rows));
say(`\n${rows.length} probes: ${pass} pass, ${fail} fail, ${unverified} unverified (no reference)`);
process.exitCode = fail || (argv.includes('--strict') && (!process.env.TAKUMI_PDF_REF_ENTRY || !refMod || unverified)) ? 1 : 0;
