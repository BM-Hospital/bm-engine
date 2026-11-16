// PDF benchmark: bm-native (sync + async), bm-wasm (sync + async) and takumi-pdf (wasm; no native build exists)
// on Node.js. ONE command regenerates the JSON results, the Markdown report and the generated doc tables:
//
//   node bench/pdf/bench.mjs                full run (3 speed passes, 30 cold starts, scaling to 500 pages, ...)
//   node bench/pdf/bench.mjs --quick        short budgets, 1 speed pass, 10 cold starts, scaling to 100 pages
//   options: --stages=speed,sizes,scale,cold,memory,eventloop,throughput,equiv   (default: all; stages not run keep
//              their previous results from the JSON, so one stage can be re-measured cheaply)
//            --passes=N --cold-runs=N --mem-passes=N --tp-ms=N --max-pages=N --filter=<regex> --no-docs
//
// Outputs: bench/out/pdf/results-pdf.json (everything), bench/out/pdf/PDF.md (all tables), docs/results-pdf.json (a
// copy) and the tables between `<!-- pdf-bench:<name> -->` markers in the docs (bench/pdf/report.mjs, which can also
// re-render them from the JSON without measuring). Exit 1 when a stage fails to run.
//
// Noise: every stage records the machine's CPU busy % before and while it runs (os.cpus(), sampled each second) next
// to its own CPU time; engines are interleaved inside each document; the speed suite runs in several passes at
// different moments (between the other stages) and the pass-to-pass spread is reported; > 10 % is flagged.
import { spawn, execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, existsSync, copyFileSync, statSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ENGINES, available, engineVersions } from "./engines.mjs";
import { OUT_DIR, ROOT, findBin } from "./lib/tools.mjs";
import { aggregateSpeed, renderAll } from "./report.mjs";
import { loadCorpus } from "./corpus/index.mjs";
import { fileOf, manifestPath } from "./lib/build.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const quick = !!args.quick;
const ALL_STAGES = ["speed", "sizes", "scale", "cold", "memory", "eventloop", "throughput", "equiv"];
const stages = new Set(args.stages ? String(args.stages).split(",") : ALL_STAGES);
for (const s of stages) if (!ALL_STAGES.includes(s)) throw new Error(`unknown stage ${s} (${ALL_STAGES.join(", ")})`);
const passes = +(args.passes ?? (quick ? 1 : 3));
const coldRuns = +(args["cold-runs"] ?? (quick ? 10 : 30));
const memPasses = +(args["mem-passes"] ?? 10);
const tpMs = +(args["tp-ms"] ?? (quick ? 800 : 2000));
const maxPages = +(args["max-pages"] ?? (quick ? 100 : 500));
const filter = args.filter ? String(args.filter) : null;
const log = (...a) => console.error(...a);
mkdirSync(OUT_DIR, { recursive: true });
const jsonPath = path.join(OUT_DIR, "results-pdf.json");
const prev = existsSync(jsonPath) ? JSON.parse(readFileSync(jsonPath, "utf8")) : {};
const res = { ...prev };
let failures = 0;

// ---- environment ----
const git = (...a) => { try { return execFileSync("git", a, { cwd: ROOT, encoding: "utf8" }).trim(); } catch { return null; } };
const avail = {};
for (const e of ENGINES) avail[e] = await available(e);
res.meta = {
  date: new Date().toISOString(), args: process.argv.slice(2), quick, stagesRun: [...stages],
  node: process.version, v8: process.versions.v8, uv: process.versions.uv,
  platform: `${process.platform} ${os.release()} ${process.arch}`, cpu: os.cpus()[0]?.model, cpus: os.availableParallelism(), totalMemGiB: +(os.totalmem() / 2 ** 30).toFixed(1),
  git: { commit: git("rev-parse", "HEAD"), branch: git("rev-parse", "--abbrev-ref", "HEAD"), dirtyFiles: (git("status", "--porcelain", "--untracked-files=no") || "").split("\n").filter(Boolean).length },
  engines: engineVersions(), available: avail,
};

// ---- CPU load sampling (as bench/run-native.mjs) ----
function cpuTimes() { return os.cpus().map((c) => ({ busy: c.times.user + c.times.nice + c.times.sys + c.times.irq, total: c.times.user + c.times.nice + c.times.sys + c.times.irq + c.times.idle })); }
function loadSampler() {
  const samples = []; let prevT = cpuTimes(); const start = cpuTimes(); const t0 = performance.now();
  const timer = setInterval(() => { const now = cpuTimes(); let b = 0, t = 0; now.forEach((c, i) => { b += c.busy - prevT[i].busy; t += c.total - prevT[i].total; }); if (t > 0) samples.push((100 * b) / t); prevT = now; }, 1000);
  return {
    stop(childCpuMs = null) {
      clearInterval(timer);
      const end = cpuTimes(); let b = 0, t = 0; end.forEach((c, i) => { b += c.busy - start[i].busy; t += c.total - start[i].total; });
      const wallS = (performance.now() - t0) / 1000;
      const r = { seconds: +wallS.toFixed(1), meanBusyPct: +((100 * b) / Math.max(1, t)).toFixed(1), maxBusyPct: samples.length ? +Math.max(...samples).toFixed(1) : null };
      if (childCpuMs != null) { r.benchCpuCoreS = +(childCpuMs / 1000).toFixed(1); r.otherCores = +Math.max(0, ((b / Math.max(1, t)) * end.length * wallS - childCpuMs / 1000) / Math.max(wallS, 1e-3)).toFixed(2); }
      return r;
    },
  };
}
async function idleLoad(ms = 2000) { const s = loadSampler(); await new Promise((r) => setTimeout(r, ms)); return s.stop(0); }

// ---- child processes ----
function child(argv, { env = {}, live = false, nodeArgs = [], timeout = 1800000 } = {}) {
  return new Promise((resolve) => {
    const t0 = performance.now();
    const p = spawn(process.execPath, [...nodeArgs, ...argv], { cwd: HERE, env: { ...process.env, ...env } });
    let out = "", err = "";
    const timer = setTimeout(() => { try { p.kill(); } catch {} }, timeout);
    p.stdout.on("data", (d) => { out += d; });
    p.stderr.on("data", (d) => { err += d; if (live) process.stderr.write(d); });
    p.on("close", (code) => { clearTimeout(timer); resolve({ code, out, err, wallMs: performance.now() - t0 }); });
  });
}
const lastJson = (r) => { try { return JSON.parse(r.out.trim().split(/\r?\n/).pop()); } catch { return { error: (r.err || r.out || `exit ${r.code}`).trim().split(/\r?\n/).filter((l) => /error|memory|fatal/i.test(l)).slice(0, 3).join(" | ").slice(0, 400) || `exit ${r.code}` }; } };
const median = (a) => { const s = a.filter((x) => x != null).sort((x, y) => x - y); return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : null; };
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5))]; };
const r2 = (v, d = 2) => (v == null ? null : +(+v).toFixed(d));
const envFor = (e) => (e === "bm-wasm" ? { BM_RENDER_BACKEND: "wasm" } : { BM_RENDER_BACKEND: "" });
const T0 = performance.now();

// ---- stages ----
const S = {};
let speedPass = 0;
const speedPasses = [];
S.speedPass = async () => {
  speedPass++;
  log(`speed: pass ${speedPass}/${passes}`);
  const file = path.join(OUT_DIR, `speed-pass${speedPass}.tmp.json`);
  const before = await idleLoad(2000);
  const ls = loadSampler();
  const r = await child(["bench/speed-child.mjs", `--out=${file}`, ...(quick ? ["--quick"] : []), ...(filter ? [`--filter=${filter}`] : [])], { live: true });
  if (r.code !== 0) throw new Error("speed failed: " + r.err.slice(-500));
  const j = JSON.parse(readFileSync(file, "utf8"));
  speedPasses.push({ pass: speedPass, date: j.date, cfg: j.cfg, durationMs: j.durationMs, loadBefore: before, load: ls.stop(j.cpuMs), cases: j.cases });
};

S.sizes = async () => {
  // output size of every corpus document as rendered by lib/build.mjs (raw), and after qpdf recompresses both
  // engines' files the same way (zlib level 9 streams, object streams): aligns the compression of the two writers
  log("sizes: raw bytes + after the same qpdf recompression");
  if (!existsSync(manifestPath)) { log("  no build manifest: run node bench/pdf/validate.mjs (or lib/build.mjs) first"); res.sizes = { error: "no build" }; return; }
  const man = JSON.parse(readFileSync(manifestPath, "utf8"));
  const qpdf = findBin("qpdf", "qpdf");
  const tmp = path.join(OUT_DIR, "sizes.tmp.pdf");
  const rows = [];
  for (const d of man.docs) {
    const row = { id: d.id, group: d.group };
    for (const e of ["bm-native", "bm-wasm", "takumi-pdf"]) {
      const r = d.engines[e];
      if (!r?.ok) continue;
      const x = { raw: r.bytes };
      if (qpdf && r.bytes < 50e6) {
        const q = spawnSync(qpdf, ["--recompress-flate", "--compression-level=9", "--object-streams=generate", "--deterministic-id", fileOf(e, d.id), tmp], { encoding: "utf8" });
        if (q.status === 0 || q.status === 3) x.qpdf9 = statSync(tmp).size;
      }
      row[e] = x;
    }
    rows.push(row);
  }
  res.sizes = { note: "Neither engine exposes a compression setting: both write FlateDecode streams and object streams by default. 'qpdf9' = the same file after qpdf --recompress-flate --compression-level=9 --object-streams=generate (the same compressor for both).", qpdf: qpdf ? "qpdf " + (spawnSync(qpdf, ["--version"], { encoding: "utf8" }).stdout.split("\n")[0]) : null, buildDate: man.date, rows };
};

S.scale = async () => {
  const pagesList = [1, 10, 100, 500].filter((p) => p <= maxPages);
  log(`scale: ${pagesList.join("/")} pages x engines (fresh process each)`);
  const ls = loadSampler();
  const out = { pages: pagesList, runs: [] };
  for (const p of pagesList) for (const e of ENGINES) {
    if (!avail[e]) continue;
    const reps = p <= 10 ? (quick ? 3 : 7) : p <= 100 ? (quick ? 1 : 3) : 1;
    const o = lastJson(await child(["bench/scale-child.mjs", e, String(p), `--reps=${reps}`], { env: envFor(e), nodeArgs: ["--expose-gc"] }));
    out.runs.push({ engine: e, pages: p, ...o });
    log(`  ${e} ${p}p: ${o.ok ? `${o.ms} ms, ${o.pagesPerSec} pages/s, ${o.bytes} B, peak RSS ${o.after?.peakRssMiB} MiB, engine ${o.after?.engineMiB} MiB` : "ERROR " + o.error}`);
  }
  out.load = ls.stop(null);
  res.scale = out;
};

S.cold = async () => {
  log(`cold start: ${coldRuns} runs x (bm-native, bm-wasm, takumi-pdf, empty Node), interleaved`);
  const font = path.join(ROOT, "assets", "fonts", "Inter-Regular.ttf");
  const docFile = path.join(OUT_DIR, "cold-invoice.html");
  const { docs } = await loadCorpus({ filter: "^docs/invoice$" });
  writeFileSync(docFile, docs[0].source([]));
  const names = ["none", ...ENGINES.filter((e) => avail[e])];
  const samples = Object.fromEntries(names.map((n) => [n, []]));
  const ls = loadSampler(); let cpu = 0;
  for (let i = 0; i < coldRuns; i++) for (let j = 0; j < names.length; j++) {
    const n = names[(i + j) % names.length];
    const r = await child(["bench/cold-child.mjs", n.startsWith("bm-") ? "bm" : n, font, docFile], { env: envFor(n) });
    const o = lastJson(r);
    if (o.error) { samples[n].push({ error: o.error }); continue; }
    cpu += o.cpuMs; samples[n].push({ wallMs: r.wallMs, ...o });
  }
  const out = { runs: coldRuns, what: "spawn node -> import bm-render/pdf (js/node-pdf.mjs; BM_RENDER_BACKEND picks the backend) or takumi-pdf -> registerFont(Inter Regular) -> one-page A4 invoice -> exit; wall = parent clock spawn to exit", load: ls.stop(cpu), engines: {} };
  const baseMed = median(samples.none.filter((s) => !s.error).map((s) => s.wallMs));
  for (const n of names) {
    const ok = samples[n].filter((s) => !s.error);
    if (!ok.length) { out.engines[n] = { error: samples[n][0]?.error }; continue; }
    const w = ok.map((s) => s.wallMs);
    out.engines[n] = { runs: ok.length, backend: ok[0].backend, wallMedianMs: r2(median(w), 1), wallP95Ms: r2(pct(w, 0.95), 1), wallMinMs: r2(Math.min(...w), 1), overNodeMedianMs: n === "none" ? 0 : r2(median(w) - baseMed, 1), importMs: r2(median(ok.map((s) => s.importMs)), 1), fontMs: r2(median(ok.map((s) => s.fontMs)), 2), firstRenderMs: r2(median(ok.map((s) => s.renderMs)), 1), bytes: ok[0].bytes, maxRssMiB: r2(median(ok.map((s) => s.maxRssMiB)), 1), errors: samples[n].length - ok.length };
  }
  res.cold = out;
  log("  " + names.map((n) => `${n} ${out.engines[n].wallMedianMs} ms`).join(", "));
};

S.memory = async () => {
  log(`memory: the guide documents x${memPasses} per engine (fresh process each)`);
  const out = { passes: memPasses, engines: {} };
  out.emptyNode = lastJson(await child(["-e", "global.gc();const m=process.memoryUsage();console.log(JSON.stringify({rssMiB:+(m.rss/2**20).toFixed(1),peakRssMiB:+(process.resourceUsage().maxRSS/1024).toFixed(1)}))"], { nodeArgs: ["--expose-gc"] }));
  const ls = loadSampler(); let cpu = 0;
  for (const e of ENGINES) {
    if (!avail[e]) continue;
    const o = lastJson(await child(["bench/memory-child.mjs", e, `--passes=${memPasses}`], { env: envFor(e), nodeArgs: ["--expose-gc"] }));
    cpu += o.cpuMs ?? 0;
    out.engines[e] = o;
    log(`  ${e}: RSS after pass 1 ${o.after?.[0]?.rssMiB} MiB, after ${memPasses} ${o.after?.at(-1)?.rssMiB} MiB, engine ${o.after?.[0]?.engineMiB} -> ${o.after?.at(-1)?.engineMiB} MiB`);
  }
  out.load = ls.stop(cpu);
  res.memory = out;
};

S.eventloop = async () => {
  const pages = quick ? 30 : 100;
  log(`event loop: one ${pages}-page render x engines x sync/async`);
  const out = { pages, runs: [] };
  const ls = loadSampler();
  for (const e of ENGINES) for (const api of ["sync", "async"]) {
    if (!avail[e] || (api === "sync" && e === "takumi-pdf")) continue;
    const o = lastJson(await child(["bench/eventloop-child.mjs", e, api, `--pages=${pages}`], { env: envFor(e) }));
    out.runs.push({ engine: e, api, ...o });
    log(`  ${e} ${api}: ${o.ms} ms, max delay ${o.maxDelayMs} ms, p99 ${o.p99DelayMs} ms${o.error ? " ERROR " + o.error : ""}`);
  }
  out.load = ls.stop(null);
  res.eventloop = out;
};

S.throughput = async () => {
  const Ks = quick ? [1, 4] : [1, 2, 4, 8];
  const Ns = "1,2,4,8";
  const configs = [];
  for (const e of ENGINES) if (avail[e]) configs.push({ engine: e, mode: "seq", uv: 4 });
  if (avail["bm-native"]) for (const uv of [4, 8]) for (const k of Ks) configs.push({ engine: "bm-native", mode: "many", k, uv });
  for (const e of ["bm-wasm", "takumi-pdf"]) if (avail[e]) for (const k of Ks) configs.push({ engine: e, mode: "pool", k, uv: 4 });
  log(`throughput: ${configs.length} configurations, ${tpMs} ms per point`);
  const out = { workload: "docs/invoice (one-page A4 invoice, HTML + footer), closed loop: N clients each with one request in flight", msPerPoint: tpMs, cpus: os.availableParallelism(), runs: [] };
  const ls = loadSampler(); let cpu = 0;
  for (const c of configs) {
    const o = lastJson(await child(["bench/throughput-child.mjs", c.engine, c.mode, `--k=${c.k ?? 1}`, `--n=${Ns}`, `--ms=${tpMs}`], { env: { UV_THREADPOOL_SIZE: String(c.uv), ...envFor(c.engine) } }));
    for (const x of o.results ?? []) cpu += x.cpuMs ?? 0;
    out.runs.push({ ...c, ...o });
    log(`  ${c.engine} ${c.mode}${c.k ? " k=" + c.k : ""} uv=${c.uv}: ${(o.results ?? []).map((x) => `${x.n}:${x.pps}`).join(" ") || o.error}`);
  }
  out.load = ls.stop(cpu);
  res.throughput = out;
};

S.equiv = async () => {
  log("equiv: the summaries of validate.mjs / visual.mjs and the build's identity record");
  const rd = (f) => { const p = path.join(OUT_DIR, f); return existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) : null; };
  const v = rd("validation.json"), vi = rd("visual.json");
  const man = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, "utf8")) : null;
  res.equiv = {
    validation: v ? { date: v.date, docs: v.summary.docs, byEngine: v.summary.byEngine, identity: v.summary.identity, semantic: v.summary.semantic, verapdf: Object.fromEntries(Object.entries(v.summary.verapdf).map(([e, x]) => [e, { runs: x.runs, compliant: x.compliant }])), toolVersions: v.summary.toolVersions } : null,
    visual: vi ? { date: vi.date, rasterisers: vi.summary.rasterisers, dpis: vi.summary.dpis, docs: vi.summary.docs, perRasteriser: vi.summary.perRasteriser, consensus: vi.summary.consensus, pdfVsImage: vi.summary.pdfVsImage, pdfVsImageSsim: vi.summary.pdfVsImageSsim, rasteriserDependent: vi.summary.rasteriserDependent.length } : null,
    identity: man ? { date: man.date, docs: man.docs.length, nativeEqualsWasm: man.docs.filter((d) => d.nativeEqualsWasm === true).length, sameError: man.docs.filter((d) => d.nativeEqualsWasm === "same-error").length, compared: man.docs.filter((d) => d.nativeEqualsWasm != null).length, mismatches: man.docs.filter((d) => d.nativeEqualsWasm === false).map((d) => d.id), renderErrors: man.docs.flatMap((d) => Object.entries(d.engines).filter(([, r]) => !r.ok).map(([e, r]) => ({ id: d.id, engine: e, error: r.error }))) } : null,
  };
};

// schedule: the speed passes spread between the other stages ("different moments")
const others = ALL_STAGES.filter((s) => s !== "speed" && stages.has(s));
const plan = [];
if (stages.has("speed")) {
  const slots = Array.from({ length: passes }, () => []);
  others.forEach((s, i) => slots[Math.min(passes - 1, Math.floor((i * passes) / Math.max(1, others.length)))].push(s));
  for (let p = 0; p < passes; p++) { plan.push("speedPass"); plan.push(...slots[p]); }
} else plan.push(...others);
res.meta.loadAtStart = await idleLoad(3000);
log(`bench/pdf: ${quick ? "quick" : "full"}; engines ${ENGINES.filter((e) => avail[e]).join(", ")}; plan: ${plan.join(" -> ")}; CPU busy at start ${res.meta.loadAtStart.meanBusyPct} %`);
for (const s of plan) {
  const t = performance.now();
  try { await S[s](); } catch (e) { failures++; log(`  [${s}] FAILED: ${e.message}`); }
  log(`  [${s}] ${((performance.now() - t) / 1000).toFixed(0)} s (total ${((performance.now() - T0) / 60000).toFixed(1)} min)`);
}
if (stages.has("speed") && speedPasses.length) res.speed = aggregateSpeed(speedPasses);
res.meta.durationMin = +((performance.now() - T0) / 60000).toFixed(1);
if (ALL_STAGES.some((s) => !stages.has(s)) && prev.meta) {
  const { stagesRun, durationMin, date, git: g, engines, quick: q } = res.meta;
  res.meta = { ...prev.meta, partialRuns: [...(prev.meta.partialRuns ?? []), { date, stages: stagesRun, quick: q, durationMin, git: g, engines }] };
}
writeFileSync(jsonPath, JSON.stringify(res, null, 1));
const md = renderAll(res, { docs: !args["no-docs"], root: ROOT });
writeFileSync(path.join(OUT_DIR, "PDF.md"), md);
if (!args["no-docs"]) copyFileSync(jsonPath, path.join(ROOT, "docs", "results-pdf.json"));
log(`wrote ${jsonPath}, ${path.join(OUT_DIR, "PDF.md")}${args["no-docs"] ? "" : ", docs/results-pdf.json and the doc tables"} in ${((performance.now() - T0) / 60000).toFixed(1)} min${failures ? `; ${failures} stage(s) FAILED` : ""}`);
process.exit(failures ? 1 : 0);
