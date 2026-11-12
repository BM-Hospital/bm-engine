// Renders the corpus with every available engine into bench/out/pdf/pdfs/<engine>/<id>.pdf and records
// bench/out/pdf/pdfs/manifest.json (per document and engine: ok / error, bytes, sha256, pages hint, ms).
// bm-native's async (libuv pool) and sync outputs are compared byte for byte, and bm-native against bm-wasm:
// the identity check of validate.mjs reads the result.
//
//   node bench/pdf/lib/build.mjs [--filter=<regex>] [--max-stress=500]
import { mkdirSync, writeFileSync, existsSync, readFileSync, rmSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { OUT_DIR } from "./tools.mjs";
import { loadCorpus, EnginePool, inputs } from "../corpus/index.mjs";
import { ENGINES, available, engineVersions } from "../engines.mjs";

const LIB = path.dirname(fileURLToPath(import.meta.url));
export const PDF_OUT = path.join(OUT_DIR, "pdfs");
export const fileOf = (engine, id) => path.join(PDF_OUT, engine, id.replace(/[\/\\]/g, "__") + ".pdf");
export const manifestPath = path.join(PDF_OUT, "manifest.json");
const sha = (b) => createHash("sha256").update(b).digest("hex");
const lines = (s) => String(s || "").split(String.fromCharCode(10)).map((l) => l.trim()).filter(Boolean);
/** The JSON line a child printed last, or an error record built from its stderr. */
function childResult(r) {
  try { return JSON.parse(lines(r.stdout).pop()); }
  catch { return { ok: false, crashed: true, error: `child exited ${r.status ?? r.signal}: ${lines(r.stderr).filter((l) => /error|memory/i.test(l)).slice(0, 2).join(" | ").slice(0, 300)}` }; }
}

export async function buildCorpus({ filter = null, maxStress = 500, log = console.error, write = true } = {}) {
  const { docs, goldenNote } = await loadCorpus({ filter, maxStress });
  const engines = [];
  for (const n of ENGINES) if (await available(n)) engines.push(n);
  const pool = new EnginePool({ keep: 1 });
  const rows = [];
  const t0 = performance.now();
  for (const doc of docs) {
    const row = { id: doc.id, group: doc.group, pdfa: doc.pdfa, tagged: doc.tagged, viewport: doc.viewport, golden: doc.golden ?? null, engines: {} };
    for (const n of engines) {
      if (doc.group === "stress" && doc.pages >= 100) { // a fresh process each: an out-of-memory engine cannot end the run
        const f = fileOf(n, doc.id); mkdirSync(path.dirname(f), { recursive: true }); if (existsSync(f)) rmSync(f);
        const r = spawnSync(process.execPath, [path.join(LIB, "render-child.mjs"), n, doc.id, f], { encoding: "utf8", timeout: 900000, maxBuffer: 1 << 24, env: { ...process.env, BM_ENGINE_BACKEND: "" } });
        const o = childResult(r);
        row.engines[n] = o;
        continue;
      }
      const { e, families } = await pool.get(n, doc.fonts);
      const { source, options } = inputs(doc, families);
      const f = fileOf(n, doc.id);
      mkdirSync(path.dirname(f), { recursive: true });
      try {
        const a = performance.now();
        const out = await e.render(source, options);
        const ms = performance.now() - a;
        writeFileSync(f, out);
        const r = { ok: true, bytes: out.length, sha256: sha(out), ms: +ms.toFixed(1), engineMiB: e.memoryBytes() == null ? null : +(e.memoryBytes() / 2 ** 20).toFixed(1) };
        if (n === "bm-native") {
          const s = e.renderSync(source, doc.options());
          r.syncSameBytes = sha(s) === r.sha256;
        }
        row.engines[n] = r;
      } catch (err) {
        if (existsSync(f)) rmSync(f);
        row.engines[n] = { ok: false, error: String(err?.message ?? err).split("\n")[0].slice(0, 400) };
      }
    }
    const nat = row.engines["bm-native"], wasm = row.engines["bm-wasm"];
    if (nat && wasm) row.nativeEqualsWasm = nat.ok && wasm.ok ? nat.sha256 === wasm.sha256 : (!nat.ok && !wasm.ok ? (nat.error === wasm.error ? "same-error" : false) : false);
    rows.push(row);
    log(`  build ${doc.id.padEnd(44)} ${engines.map((n) => `${n} ${row.engines[n].ok ? row.engines[n].bytes + " B" : "ERROR"}`).join(", ")}`);
  }
  pool.dispose();
  const manifest = { date: new Date().toISOString(), engines, versions: engineVersions(), goldenNote, filter, maxStress, seconds: +((performance.now() - t0) / 1000).toFixed(1), docs: rows };
  mkdirSync(PDF_OUT, { recursive: true });
  if (write) writeFileSync(manifestPath, JSON.stringify(manifest, null, 1));
  return manifest;
}

/** The manifest of the last build (building first when there is none or `rebuild`). */
export async function corpusBuild({ rebuild = false, filter = null, maxStress = 500, log } = {}) {
  const prev = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, "utf8")) : null;
  if (!rebuild && prev) {
    // the documents asked for, from the last build, when it has them all
    const { docs } = await loadCorpus({ filter, maxStress });
    const have = new Map(prev.docs.map((d) => [d.id, d]));
    if (docs.every((d) => have.has(d.id))) return { ...prev, docs: docs.map((d) => have.get(d.id)), filter };
  }
  const m = await buildCorpus({ filter, maxStress, log, write: false });
  // merge into the previous manifest (a filtered build replaces only its documents)
  const merged = prev && filter ? { ...m, filter: null, docs: [...prev.docs.filter((d) => !m.docs.some((x) => x.id === d.id)), ...m.docs] } : m;
  writeFileSync(manifestPath, JSON.stringify(merged, null, 1));
  return m;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
  const m = await buildCorpus({ filter: args.filter ? String(args.filter) : null, maxStress: +(args["max-stress"] ?? 500) });
  const errs = m.docs.flatMap((d) => Object.entries(d.engines).filter(([, r]) => !r.ok).map(([n, r]) => `${d.id} ${n}: ${r.error}`));
  console.log(`${m.docs.length} docs x ${m.engines.join(", ")} in ${m.seconds} s; ${errs.length} render errors`);
  for (const e of errs) console.log("  " + e);
  process.exit(0);
}
