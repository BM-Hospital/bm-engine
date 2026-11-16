// Native benchmark: bm-native vs bm-wasm vs takumi-native vs takumi-wasm on Node.js. ONE command regenerates the
// JSON results, the Markdown report and the generated tables in the docs:
//
//   node bench/run-native.mjs                  full run (3 speed passes, 30 cold starts, ...; ~25-35 min)
//   node bench/run-native.mjs --quick          short budgets, 1 speed pass, 10 cold starts (~5 min); for a smoke test
//   options: --stages=identity,equiv,speed,cold,memory,eventloop,diagnose,throughput,sizes   (default: all; the stages not
//              run keep their previous results from the JSON, so one stage can be re-measured cheaply)
//            --passes=N  --cold-runs=N  --mem-passes=N  --tp-ms=N  --filter=<regex> (fixtures)  --no-docs
//            --out=<dir> (default bench/out/native)
//
// Outputs: <out>/results-native.json (everything, incl. per-fixture numbers), <out>/NATIVE.md (all tables),
// docs/results-native.json (a copy), and the tables between `<!-- native-bench:<name> -->` markers in the docs
// (bench/native/report.mjs; `node bench/native/report.mjs` re-renders them from the JSON without measuring).
//
// Noise: other processes may be using the CPU. Every stage records the overall CPU load while it runs (os.cpus()
// sampled each second) next to its own CPU time; engines are interleaved inside each fixture; the speed suite is
// run in several passes at different moments (interleaved with the other stages) and the pass-to-pass spread is
// reported; anything whose spread exceeds 10 % is flagged in the report.
import { spawn, execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, existsSync, copyFileSync } from "node:fs";
import os from "node:os";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ALL_CASES } from "./fixtures/index.mjs";
import { renderOpts } from "./lib/pipeline.mjs";
import { FONTS } from "./lib/fonts.mjs";
import { sizeOf } from "./lib/sizes.mjs";
import { ENGINES, PATHS, engineVersions } from "./native/engines.mjs";
import { aggregateSpeed, renderAll } from "./native/report.mjs";

const BENCH = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(BENCH, "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const quick = !!args.quick;
const ALL_STAGES = ["identity", "equiv", "speed", "cold", "memory", "eventloop", "diagnose", "throughput", "sizes"];
const stages = new Set(args.stages ? String(args.stages).split(",") : ALL_STAGES);
for (const s of stages) if (!ALL_STAGES.includes(s)) throw new Error(`unknown stage ${s} (${ALL_STAGES.join(", ")})`);
const outDir = path.resolve(args.out ? String(args.out) : path.join(BENCH, "out", "native"));
const passes = +(args.passes ?? (quick ? 1 : 3));
const coldRuns = +(args["cold-runs"] ?? (quick ? 10 : 30));
const memPasses = +(args["mem-passes"] ?? (quick ? 3 : 10));
const tpMs = +(args["tp-ms"] ?? (quick ? 600 : 2000));
const filter = args.filter ? String(args.filter) : null;
const log = (...a) => console.error(...a);
mkdirSync(outDir, { recursive: true });
const jsonPath = path.join(outDir, "results-native.json");
const prev = existsSync(jsonPath) ? JSON.parse(readFileSync(jsonPath, "utf8")) : {};
const res = { ...prev };

// ---- environment ----
const git = (...a) => { try { return execFileSync("git", a, { cwd: ROOT, encoding: "utf8" }).trim(); } catch { return null; } };
res.meta = {
  date: new Date().toISOString(),
  args: process.argv.slice(2), quick, stagesRun: [...stages],
  node: process.version, v8: process.versions.v8, napi: process.versions.napi, uv: process.versions.uv,
  platform: `${process.platform} ${os.release()} ${process.arch}`, cpu: os.cpus()[0]?.model, cpus: os.availableParallelism(),
  totalMemGiB: +(os.totalmem() / 2 ** 30).toFixed(1),
  git: { commit: git("rev-parse", "HEAD"), branch: git("rev-parse", "--abbrev-ref", "HEAD"), dirtyFiles: (git("status", "--porcelain", "--untracked-files=no") || "").split("\n").filter(Boolean).length },
  engines: engineVersions(),
  fixtures: filter ? ALL_CASES.filter((k) => new RegExp(filter, "i").test(k.id) || new RegExp(filter, "i").test(k.feature)).length : ALL_CASES.length,
  filter,
};

// ---- CPU load sampling ----
function cpuTimes() { return os.cpus().map((c) => ({ busy: c.times.user + c.times.nice + c.times.sys + c.times.irq, total: c.times.user + c.times.nice + c.times.sys + c.times.irq + c.times.idle })); }
function loadSampler() {
  const samples = [];
  let prevT = cpuTimes();
  const start = cpuTimes();
  const t0 = performance.now();
  const timer = setInterval(() => {
    const now = cpuTimes();
    let b = 0, t = 0;
    now.forEach((c, i) => { b += c.busy - prevT[i].busy; t += c.total - prevT[i].total; });
    if (t > 0) samples.push((100 * b) / t);
    prevT = now;
  }, 1000);
  return {
    stop(childCpuMs = null) {
      clearInterval(timer);
      const end = cpuTimes();
      let b = 0, t = 0;
      end.forEach((c, i) => { b += c.busy - start[i].busy; t += c.total - start[i].total; });
      const wallS = (performance.now() - t0) / 1000;
      const ncpu = end.length;
      const busyCoreS = (b / Math.max(1, t)) * ncpu * wallS;
      const r = { seconds: +wallS.toFixed(1), meanBusyPct: +((100 * b) / Math.max(1, t)).toFixed(1), maxBusyPct: samples.length ? +Math.max(...samples).toFixed(1) : null };
      if (childCpuMs != null) {
        r.benchCpuCoreS = +(childCpuMs / 1000).toFixed(1);
        // what other processes used meanwhile, in cores (busy core-seconds minus the benchmark's own CPU time)
        r.otherCores = +Math.max(0, (busyCoreS - childCpuMs / 1000) / Math.max(wallS, 1e-3)).toFixed(2);
      }
      return r;
    },
  };
}
async function idleLoad(ms = 2000) { const s = loadSampler(); await new Promise((r) => setTimeout(r, ms)); return s.stop(0); }

// ---- child processes ----
function child(argv, { env = {}, live = false, nodeArgs = [] } = {}) {
  return new Promise((resolve) => {
    const t0 = performance.now();
    const p = spawn(process.execPath, [...nodeArgs, ...argv], { cwd: BENCH, env: { ...process.env, ...env } });
    let out = "", err = "";
    p.stdout.on("data", (d) => { out += d; });
    p.stderr.on("data", (d) => { err += d; if (live) process.stderr.write(d); });
    p.on("close", (code) => resolve({ code, out, err, wallMs: performance.now() - t0 }));
  });
}
const lastJson = (r) => { try { return JSON.parse(r.out.trim().split("\n").pop()); } catch { return { error: (r.err || r.out || `exit ${r.code}`).trim().split("\n").slice(-3).join(" | ").slice(0, 400) }; } };
const median = (a) => { const s = [...a].sort((x, y) => x - y); return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : null; };
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5))]; };
const r2 = (v, d = 2) => (v == null ? null : +v.toFixed(d));
const T0 = performance.now();

// ---- stages ----
const S = {};
S.identity = async () => {
  log("identity: native-identity.mjs (bm-native vs bm-wasm, byte for byte)");
  const r = await child(["native-identity.mjs", ...(filter ? [`--filter=${filter}`] : [])]);
  const j = JSON.parse(readFileSync(path.join(BENCH, "out", "native-identity.json"), "utf8"));
  res.identity = { exitCode: r.code, fixtures: j.fixtures, compared: j.compared, identical: j.identical, sameErrorOnBoth: j.bothError, mbCompared: r2(j.bytes / 1e6, 1), asyncChecked: j.asyncChecked, mismatches: j.mismatches.length, seconds: r2(r.wallMs / 1000, 1) };
  log(`  ${j.identical}/${j.compared} identical, ${j.mismatches.length} mismatches`);
};
S.equiv = async () => {
  log("equiv: 4 engines vs takumi-wasm (raw RGBA) + byte identity of each engine's two builds");
  const file = path.join(outDir, "equiv.tmp.json");
  const r = await child(["native/equiv.mjs", `--out=${file}`, ...(filter ? [`--filter=${filter}`] : [])]);
  if (r.code !== 0) throw new Error("equiv failed: " + r.err.slice(-500));
  const j = JSON.parse(readFileSync(file, "utf8"));
  res.equiv = { fixtures: j.fixtures, reference: j.reference, verdicts: j.verdicts, identicalBytes: j.identicalBytes, rows: j.rows.map((x) => ({ id: x.id, v: Object.fromEntries(Object.entries(x.cmp).map(([n, c]) => [n, c.verdict])), ssim: Object.fromEntries(Object.entries(x.cmp).map(([n, c]) => [n, c.ssim])), same: x.identical })) };
  log("  " + JSON.stringify(j.verdicts) + " " + JSON.stringify(j.identicalBytes));
};
let speedPass = 0;
const speedPasses = [];
S.speedPass = async () => {
  speedPass++;
  log(`speed: pass ${speedPass}/${passes}`);
  const file = path.join(outDir, `speed-pass${speedPass}.tmp.json`);
  const before = await idleLoad(2000);
  const ls = loadSampler();
  const r = await child(["native/speed.mjs", `--out=${file}`, ...(quick ? ["--quick"] : []), ...(filter ? [`--filter=${filter}`] : [])], { live: true });
  if (r.code !== 0) throw new Error("speed failed: " + r.err.slice(-500));
  const j = JSON.parse(readFileSync(file, "utf8"));
  speedPasses.push({ pass: speedPass, date: j.date, cfg: j.cfg, durationMs: j.durationMs, loadBefore: before, load: ls.stop(j.cpuMs), cases: j.cases });
};
S.cold = async () => {
  log(`cold start: ${coldRuns} runs x (4 engines + empty Node), interleaved`);
  const card = ALL_CASES.find((c) => c.id === "card-og");
  const cardFile = path.join(outDir, "cold-card.json");
  const { images, ...options } = renderOpts(card, "png"); // image bytes as base64 (decoded by the child before its clock starts)
  writeFileSync(cardFile, JSON.stringify({ node: card.node, options, images: (images ?? []).map((i) => ({ ...i, data: Buffer.from(i.data).toString("base64") })) }));
  const font = FONTS[0].path;
  const names = ["none", ...ENGINES];
  const samples = Object.fromEntries(names.map((n) => [n, []]));
  const ls = loadSampler();
  let cpu = 0;
  for (let i = 0; i < coldRuns; i++) {
    for (let j = 0; j < names.length; j++) {
      const n = names[(i + j) % names.length];
      const env = n === "bm-wasm" ? { BM_RENDER_BACKEND: "wasm" } : { BM_RENDER_BACKEND: "" };
      const r = await child(["native/cold-child.mjs", n, cardFile, font], { env });
      const o = lastJson(r);
      if (o.error) { samples[n].push({ error: o.error }); continue; }
      cpu += o.cpuMs;
      samples[n].push({ wallMs: r.wallMs, ...o });
    }
  }
  const load = ls.stop(cpu);
  const out = { runs: coldRuns, what: "spawn node -> import the engine as a user does -> registerFont(Inter Regular) -> 1200x630 og card PNG -> exit; wall = parent clock spawn to exit", load, engines: {} };
  const base = samples.none.filter((s) => !s.error);
  const baseMed = median(base.map((s) => s.wallMs));
  for (const n of names) {
    const ok = samples[n].filter((s) => !s.error);
    if (!ok.length) { out.engines[n] = { error: samples[n][0]?.error }; continue; }
    const w = ok.map((s) => s.wallMs);
    out.engines[n] = {
      runs: ok.length, backend: ok[0].backend, wallMedianMs: r2(median(w), 1), wallP95Ms: r2(pct(w, 0.95), 1), wallMinMs: r2(Math.min(...w), 1),
      overNodeMedianMs: n === "none" ? 0 : r2(median(w) - baseMed, 1), overNodeP95Ms: n === "none" ? 0 : r2(pct(w, 0.95) - baseMed, 1),
      importMs: r2(median(ok.map((s) => s.importMs)), 1), fontMs: r2(median(ok.map((s) => s.fontMs)), 2), firstRenderMs: r2(median(ok.map((s) => s.renderMs)), 1),
      inProcessMs: r2(median(ok.map((s) => s.totalMs)), 1), bytes: ok[0].bytes, errors: samples[n].length - ok.length,
    };
  }
  res.cold = out;
  log("  " + names.map((n) => `${n} ${out.engines[n].wallMedianMs}`).join(", "));
};
S.memory = async () => {
  log(`memory: whole suite x${memPasses} per engine; 4000x4000 PNG peak RSS`);
  const out = { suitePasses: memPasses, engines: {} };
  const base = await child(["-e", "global.gc();global.gc();const m=process.memoryUsage();console.log(JSON.stringify({rssMiB:+(m.rss/2**20).toFixed(1),maxRssMiB:+(process.resourceUsage().maxRSS/1024).toFixed(1)}))"], { nodeArgs: ["--expose-gc"] });
  out.emptyNode = lastJson(base);
  const ls = loadSampler();
  let cpu = 0;
  for (const n of ENGINES) {
    const env = n === "bm-wasm" ? { BM_RENDER_BACKEND: "wasm" } : {};
    const s = lastJson(await child(["native/memory.mjs", n, "suite", `--passes=${memPasses}`, ...(filter ? [`--filter=${filter}`] : [])], { env, nodeArgs: ["--expose-gc"] }));
    const l = lastJson(await child(["native/memory.mjs", n, "large", "--size=4000"], { env, nodeArgs: ["--expose-gc"] }));
    cpu += (s.cpuMs ?? 0) + (l.cpuMs ?? 0);
    out.engines[n] = { suite: s, large: l };
    log(`  ${n}: after pass 1 RSS ${s.passes?.[0]?.rssMiB} MiB, after ${memPasses} ${s.passes?.at(-1)?.rssMiB} MiB; 4000x4000 peak ${l.after?.maxRssMiB} MiB`);
  }
  out.load = ls.stop(cpu);
  res.memory = out;
};
S.eventloop = async () => {
  const jobs = quick ? ["heavy"] : ["heavy", "anim"];
  log(`event loop: ${jobs.join(", ")} x engines x sync/async`);
  const out = { jobs: { heavy: "one 2400x2400 PNG: gradient, 24 cards with large blurred box-shadows, every third with filter: blur(6px), text", anim: "renderAnimation: 60 frames (2 s at 30 fps) of 800x420 lossless WebP, 12 shadowed, blurred, rotated discs (a static scene)" }, runs: [] };
  const ls = loadSampler();
  for (const job of jobs) for (const n of ENGINES) for (const api of ["sync", "async"]) {
    if (api === "sync" && n.startsWith("takumi")) continue; // takumi has no synchronous render API
    const o = lastJson(await child(["native/eventloop.mjs", n, api, job]));
    out.runs.push(o);
    log(`  ${job} ${n} ${api}: ${o.ms} ms, max delay ${o.maxDelayMs} ms, p99 ${o.p99DelayMs} ms`);
  }
  out.load = ls.stop(out.runs.reduce((a, r) => a + (r.cpuMs ?? 0), 0));
  res.eventloop = out;
};
S.throughput = async () => {
  const Ks = quick ? [1, 4, 8] : [1, 2, 4, 8];
  const Ns = quick ? "1,4,8,16" : "1,2,4,8,16";
  const configs = [];
  for (const e of ENGINES) configs.push({ engine: e, mode: "seq", uv: 4 });
  for (const uv of [4, 8]) for (const k of Ks) configs.push({ engine: "bm-native", mode: "many", k, uv });
  for (const uv of [4, 8]) configs.push({ engine: "takumi-native", mode: "one", uv });
  if (!quick) for (const uv of [4, 8]) for (const k of [2, 4]) configs.push({ engine: "takumi-native", mode: "many", k, uv });
  for (const e of ["bm-wasm", "takumi-wasm"]) for (const k of Ks) configs.push({ engine: e, mode: "pool", k, uv: 4 });
  log(`throughput: ${configs.length} configurations, ${tpMs} ms per point`);
  const out = { workload: "card-og 1200x630 PNG, closed loop: N clients each with one request in flight", msPerPoint: tpMs, cpus: os.availableParallelism(), physicalCores: null, runs: [] };
  const ls = loadSampler();
  let cpu = 0;
  for (const c of configs) {
    const o = lastJson(await child(["native/throughput.mjs", c.engine, c.mode, `--k=${c.k ?? 1}`, `--n=${Ns}`, `--ms=${tpMs}`], { env: { UV_THREADPOOL_SIZE: String(c.uv), ...(c.engine === "bm-wasm" ? { BM_RENDER_BACKEND: "wasm" } : {}) } }));
    for (const x of o.results ?? []) cpu += x.cpuMs;
    out.runs.push({ ...c, ...o });
    log(`  ${c.engine} ${c.mode}${c.k ? " k=" + c.k : ""} uv=${c.uv}: ${(o.results ?? []).map((x) => `${x.n}:${x.ips}`).join(" ") || o.error}`);
  }
  out.load = ls.stop(cpu);
  res.throughput = out;
};
S.diagnose = async () => {
  log("diagnose: fixed per-frame cost (empty frames) and the animation scene's effects, interleaved");
  const ls = loadSampler();
  const o = lastJson(await child(["native/diagnose.mjs", `--iters=${quick ? 15 : 40}`]));
  o.load = ls.stop(null);
  res.diagnose = o;
};
S.sizes = async () => {
  log("sizes");
  const man = JSON.parse(readFileSync(path.join(ROOT, "native", "dist", "manifest.json"), "utf8"));
  // gzip -9 / brotli q11 of 10+ MB is slow: cached by content hash in <out>/sizes-cache.json
  const cacheFile = path.join(outDir, "sizes-cache.json");
  const cache = existsSync(cacheFile) ? JSON.parse(readFileSync(cacheFile, "utf8")) : {};
  const sized = (bytes) => { const h = createHash("sha256").update(bytes).digest("hex"); return (cache[h] ??= sizeOf(bytes)); };
  const f = (p) => (existsSync(p) ? sized(readFileSync(p)) : null);
  const native = {};
  for (const [name, m] of Object.entries(man.files ?? {})) {
    const p = path.join(ROOT, "native", "dist", m.file);
    native[name] = { zigTarget: m.zigTarget, optimize: m.optimize, verified: m.verified, ...(f(p) ?? { raw: m.bytes, gzip9: null, brotli: null }), manifestGzip: m.gzip ?? null, executedHere: name === `win32-${process.arch}-msvc` && process.platform === "win32" };
  }
  const js = path.join(ROOT, "js");
  res.sizes = {
    manifestDate: man.date, zig: man.zig, native,
    wasm: { core: f(path.join(js, "bm_render.core.wasm")), standard: f(path.join(js, "bm_render.standard.wasm")), full: f(path.join(js, "bm_render.wasm")), woffAddon: f(path.join(js, "bm_woff.wasm")) },
    takumi: { "native win32-x64-msvc (.node)": f(PATHS.takumiNative), "wasm (takumi_wasm_bg.wasm)": f(PATHS.takumiWasm) },
  };
  writeFileSync(cacheFile, JSON.stringify(cache));
};

// schedule: the speed passes are spread between the other stages ("different moments")
const others = ["identity", "equiv", "cold", "memory", "eventloop", "diagnose", "throughput", "sizes"].filter((s) => stages.has(s));
const plan = [];
if (stages.has("speed")) {
  const slots = Array.from({ length: passes }, () => []);
  others.forEach((s, i) => slots[Math.min(passes - 1, Math.floor((i * passes) / Math.max(1, others.length)))].push(s));
  for (let p = 0; p < passes; p++) { plan.push("speedPass"); plan.push(...slots[p]); }
} else plan.push(...others);
res.meta.loadAtStart = await idleLoad(3000);
log(`run-native: ${quick ? "quick" : "full"}; plan: ${plan.join(" -> ")}; CPU busy at start ${res.meta.loadAtStart.meanBusyPct} %`);
for (const s of plan) {
  const t = performance.now();
  await S[s]();
  log(`  [${s}] ${((performance.now() - t) / 1000).toFixed(0)} s (total ${((performance.now() - T0) / 60000).toFixed(1)} min)`);
}
if (stages.has("speed")) res.speed = aggregateSpeed(speedPasses);
res.meta.durationMin = +((performance.now() - T0) / 60000).toFixed(1);
if (ALL_STAGES.some((s) => !stages.has(s)) && prev.meta) {
  // a partial run: the environment record stays the one of the last full run, this run is appended to it
  const { stagesRun, durationMin, date, git, engines, quick: q } = res.meta;
  res.meta = { ...prev.meta, partialRuns: [...(prev.meta.partialRuns ?? []), { date, stages: stagesRun, quick: q, durationMin, git, engines }] };
}

writeFileSync(jsonPath, JSON.stringify(res, null, 1));
const docsJson = path.join(ROOT, "docs", "results-native.json");
const md = renderAll(res, { docs: !args["no-docs"], root: ROOT });
writeFileSync(path.join(outDir, "NATIVE.md"), md);
if (!args["no-docs"]) copyFileSync(jsonPath, docsJson);
log(`wrote ${jsonPath}, ${path.join(outDir, "NATIVE.md")}${args["no-docs"] ? "" : ", docs/results-native.json and the doc tables"} in ${((performance.now() - T0) / 60000).toFixed(1)} min`);
process.exit(0);
