// Benchmark + equivalence runner.  node run.mjs [--quick] [--filter=<regex>] [--iters=N] [--engines=a,b] [--no-perf] [--no-equiv] [--no-cold] [--cold-runs=7]
import { writeFileSync, mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ALL } from "./engines/index.mjs";
import { selectCases, FORMAT_CASES } from "./fixtures/index.mjs";
import { selfCheck } from "./lib/metrics.mjs";
import { EnginePool, equivalenceForCase, measureInterleaved, errMsg } from "./lib/pipeline.mjs";
import { collectSizes } from "./lib/sizes.mjs";
import { renderMarkdown } from "./lib/report.mjs";

const BENCH = path.dirname(fileURLToPath(import.meta.url));
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const quick = !!args.quick;
const outDir = path.resolve(BENCH, args.out || "out");
const cfg = {
  warmup: quick ? 2 : 3, rounds: 2,
  minIters: args.iters ? 0 : quick ? 6 : 20, minMs: quick ? 40 : 300, maxMs: quick ? 400 : 2000,
  iters: args.iters ? +args.iters : 0,
};
const wantNames = (args.engines ? String(args.engines).split(",") : Object.keys(ALL));
const log = (...a) => console.error(...a);

log("metrics self-check:", selfCheck().length, "checks passed");
mkdirSync(outDir, { recursive: true });

const adapters = {};
const engineInfo = {};
for (const n of Object.keys(ALL)) {
  const on = wantNames.includes(n);
  adapters[n] = on ? ALL[n] : { ...ALL[n], available: false };
  engineInfo[n] = { available: !!adapters[n].available, status: !on ? "not selected" : ALL[n].available ? "available" : "unavailable", wasmPath: ALL[n].wasmPath ?? ALL[n].nativePath ?? null };
  if (on && !ALL[n].available) log(`engine ${n}: unavailable (${ALL[n].wasmPath ?? ALL[n].nativePath ?? "missing files"})`);
}
const live = Object.keys(adapters).filter((n) => adapters[n].available);
if (!adapters["takumi-wasm"].available) { log("takumi-wasm (the reference) is not available; aborting"); process.exit(1); }

const cases = selectCases(args.filter);
log(`engines: ${live.join(", ")}; cases: ${cases.length}${args.filter ? ` (filter ${args.filter})` : ""}; mode: ${quick ? "quick" : cfg.iters ? "iters=" + cfg.iters : "full"}`);

const pool = new EnginePool(adapters);
const results = {
  meta: {
    date: new Date().toISOString(), node: process.version, platform: `${process.platform} ${os.release()} ${process.arch}`,
    cpu: os.cpus()[0]?.model, cpus: os.cpus().length, totalMemGB: +(os.totalmem() / 2 ** 30).toFixed(1),
    args: process.argv.slice(2), config: cfg, engines: engineInfo,
  },
  sizes: collectSizes(ALL), cold: {}, memory: {}, cases: [],
};

// ---- per-case equivalence + performance ----
const t0 = performance.now();
let idx = 0;
for (const k of cases) {
  idx++;
  const row = { id: k.id, feature: k.feature, title: k.title, width: k.width, height: k.height, notes: k.notes };
  if (!args["no-equiv"]) {
    try { Object.assign(row, await equivalenceForCase(k, pool, adapters, { outDir })); }
    catch (e) { row.equivError = errMsg(e); }
  }
  if (!args["no-perf"]) {
    row.perf = {};
    const formats = ["raw", "png", ...(FORMAT_CASES.includes(k.id) ? ["jpeg", "webp"] : [])];
    const targets = [];
    for (const n of live) { const e = await pool.get(adapters[n], k.fonts); if (e.inst) targets.push({ name: n, inst: e.inst }); else row.perf[n] = { error: e.error }; }
    for (const f of formats) {
      const m = await measureInterleaved(targets, k, f, cfg);
      for (const n of Object.keys(m)) (row.perf[n] ??= {})[f] = m[n];
    }
  }
  results.cases.push(row);
  const v = Object.entries(row.cmp ?? {}).map(([n, c]) => `${n.replace("takumi-", "")}:${c.verdict}`).join(" ");
  const p = row.perf?.["takumi-wasm"]?.png?.median;
  log(`[${idx}/${cases.length}] ${k.id.padEnd(30)} ${v}${p ? `  wasm png ${p.toFixed(1)}ms` : ""}`);
}
results.memory.poolWasmLinearMemory = pool.memory();
pool.dispose();
log(`cases done in ${((performance.now() - t0) / 1000).toFixed(1)}s`);

// ---- cold start + memory (fresh child processes) ----
const median = (a) => { const s = [...a].sort((x, y) => x - y); return s[Math.floor((s.length - 1) / 2)]; };
function child(args2) {
  const r = spawnSync(process.execPath, [path.join(BENCH, "lib", "cold.mjs"), ...args2], { encoding: "utf8", cwd: BENCH, timeout: 120000 });
  if (r.status !== 0) return { error: (r.stderr || `exit ${r.status}`).split("\n").filter(Boolean).slice(-2).join(" | ").slice(0, 300) };
  try { return JSON.parse(r.stdout.trim().split("\n").pop()); } catch { return { error: "bad child output: " + r.stdout.slice(0, 200) }; }
}
if (!args["no-cold"]) {
  const runs = +(args["cold-runs"] || (quick ? 3 : 7));
  const base = spawnSync(process.execPath, ["-e", "console.log(process.resourceUsage().maxRSS)"], { encoding: "utf8" });
  results.memory.nodeBaselineMaxRssKB = +base.stdout.trim() || null;
  for (const n of live) {
    log(`cold start: ${n} x${runs}`);
    const samples = Array.from({ length: runs }, () => child([n]));
    const ok = samples.filter((s) => !s.error);
    if (!ok.length) { results.cold[n] = { error: samples[0]?.error ?? "failed" }; continue; }
    const med = (key) => +median(ok.map((s) => s[key])).toFixed(2);
    results.cold[n] = { runs: ok.length, initMs: med("initMs"), fontMs: med("fontMs"), firstRenderMs: med("firstRenderMs"), totalMs: med("totalMs"), samplesTotalMs: ok.map((s) => +s.totalMs.toFixed(1)) };
    log(`mem: ${n}`);
    results.memory[n] = child([n, "--mem"]);
  }
}

writeFileSync(path.join(outDir, "results.json"), JSON.stringify(results, null, 1));
writeFileSync(path.join(outDir, "RESULTS.md"), renderMarkdown(results));
log(`wrote ${path.join(outDir, "results.json")} and RESULTS.md`);
