// Tests of the native addon that need the real thing running (so: only on a host whose addon is built, see
// scripts/build-native.mjs). Every case runs in its own child process: a native crash is an exit code, not a
// lost test run.
//
//   node native-tests.mjs                 every case, summary + out/native-tests.json
//   node native-tests.mjs --only=a,b      some cases        (--list prints the names)
//   node native-tests.mjs --case=<name>   one case in this process (what the children run)
//
// Cases: concurrency, eventloop, free, gc, errors, fallback, workers, stack, fuzz-tree, fuzz-inline, fuzz-table,
// fuzz-diff, perf, cold. Byte identity on the fixtures is bench/native-identity.mjs.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const SELF = fileURLToPath(import.meta.url);
const BENCH = path.dirname(SELF);
const ROOT = path.resolve(BENCH, "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const href = (...p) => pathToFileURL(path.join(ROOT, ...p)).href;
const sha = (b) => createHash("sha256").update(typeof b === "string" ? Buffer.from(b) : b).digest("hex").slice(0, 16);
const median = (a) => { const s = [...a].sort((x, y) => x - y); return s[Math.floor((s.length - 1) / 2)]; };
const fontFile = (f) => new Uint8Array(readFileSync(path.join(ROOT, "assets", "fonts", f)));
const WASM_FILE = path.join(ROOT, "js", "bm_engine.wasm");

let failures = 0;
const notes = {};
function check(ok, what) {
  if (!ok) { failures++; console.log("  FAIL " + what); } else if (args.verbose) console.log("  ok   " + what);
  return ok;
}

async function load() {
  const { createBinding } = await import(href("js", "engine.mjs"));
  const newWasm = () => { const b = createBinding(); b.initSync(readFileSync(WASM_FILE)); return b; };
  const native = await import(href("js", "node-native.mjs"));
  const { ALL_CASES } = await import(href("bench", "fixtures", "index.mjs"));
  const { fontsFor } = await import(href("bench", "lib", "fonts.mjs"));
  const { renderOpts } = await import(href("bench", "lib", "pipeline.mjs"));
  const withFonts = (B, families) => {
    const r = new B.Renderer();
    for (const f of fontsFor(families)) r.registerFont({ name: f.name, data: new Uint8Array(readFileSync(f.path)), weight: f.weight, style: f.style });
    return r;
  };
  return { wasm: newWasm(), newWasm, native, addon: await native.init(), ALL_CASES, renderOpts, withFonts };
}

/** { ok: hash } | { error: message } | { trap: message } of a sync call. */
function outcome(fn) {
  try {
    const v = fn();
    return { ok: sha(typeof v === "string" ? v : Buffer.from(v.buffer, v.byteOffset, v.byteLength)) };
  } catch (e) {
    if (typeof WebAssembly !== "undefined" && e instanceof WebAssembly.RuntimeError) return { trap: String(e.message) };
    if (e instanceof RangeError) return { trap: "RangeError: " + e.message };
    return { error: String(e && e.message) };
  }
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ============================================================================================================
const CASES = {};

// ---- c. async correctness ---------------------------------------------------------------------------------
CASES.concurrency = async () => {
  const { wasm, native, ALL_CASES, renderOpts, withFonts } = await load();
  const ids = ["card-og", "card-flat-ui", "lingrad-angles", "img-photo-bg", "text-wrap-long", "grid-basic", "shadow-multi", "stress-nested-500"];
  const picks = ids.map((id) => ALL_CASES.find((k) => k.id === id)).filter(Boolean);
  while (picks.length < 8) picks.push(ALL_CASES[picks.length * 7]);
  const wr = withFonts(wasm);
  const expected = picks.map((k) => sha(wr.renderSync(k.node, renderOpts(k, "png"))));
  // 200 concurrent render() calls on ONE renderer
  const r = withFonts(native);
  let t0 = performance.now();
  const outs = await Promise.all(Array.from({ length: 200 }, (_, i) => r.render(picks[i % picks.length].node, renderOpts(picks[i % picks.length], "png"))));
  const oneMs = performance.now() - t0;
  check(outs.every((o, i) => sha(o) === expected[i % picks.length]), "200 concurrent render() on one renderer give the wasm bytes");
  // the same work on the calling thread, for scale
  t0 = performance.now();
  for (let i = 0; i < 200; i++) r.renderSync(picks[i % picks.length].node, renderOpts(picks[i % picks.length], "png"));
  const syncMs = performance.now() - t0;
  // 200 calls spread over 8 renderers: these run in parallel on the pool
  const rs = Array.from({ length: 8 }, () => withFonts(native));
  for (const x of rs) for (const k of picks) x.renderSync(k.node, renderOpts(k, "png")); // warm caches like `r`
  t0 = performance.now();
  const outs8 = await Promise.all(Array.from({ length: 200 }, (_, i) => rs[i % 8].render(picks[(i >> 3) % picks.length].node, renderOpts(picks[(i >> 3) % picks.length], "png"))));
  const eightMs = performance.now() - t0;
  check(outs8.every((o, i) => sha(o) === expected[(i >> 3) % picks.length]), "200 concurrent render() across 8 renderers give the wasm bytes");
  // mixed operations queued on one renderer, with sync calls (font registration, sync render) in between
  const k0 = picks[0];
  const mixed = [];
  for (let i = 0; i < 40; i++) {
    mixed.push(r.render(k0.node, renderOpts(k0, "raw")).then(sha), r.measure(k0.node, renderOpts(k0, "raw")).then((m) => sha(JSON.stringify(m))), r.renderSvg(k0.node, renderOpts(k0, "raw")).then(sha));
    if (i % 10 === 5) { r.registerFont({ name: "Extra" + i, data: fontFile("Roboto-Regular.ttf") }); mixed.push(Promise.resolve(sha(r.renderSync(k0.node, renderOpts(k0, "raw"))))); }
  }
  const got = await Promise.all(mixed);
  const want = { raw: sha(wr.renderSync(k0.node, renderOpts(k0, "raw"))), measure: sha(JSON.stringify(wr.measureSync(k0.node, renderOpts(k0, "raw")))), svg: sha(wr.renderSvgSync(k0.node, renderOpts(k0, "raw"))) };
  check(got.every((h) => h === want.raw || h === want.measure || h === want.svg), "mixed async render / measure / renderSvg + sync calls on one renderer are all correct");
  check(new Set(got).size === 3, "mixed calls produced the three distinct expected results");
  notes.concurrency = { threadPool: +(process.env.UV_THREADPOOL_SIZE || 4), cpus: os.cpus().length, sync200Ms: +syncMs.toFixed(0), oneRenderer200Ms: +oneMs.toFixed(0), eightRenderers200Ms: +eightMs.toFixed(0), parallelSpeedup: +(syncMs / eightMs).toFixed(2) };
  check(eightMs < syncMs * 0.75, `8 renderers run in parallel (sync ${syncMs.toFixed(0)} ms, 8 renderers ${eightMs.toFixed(0)} ms)`);
};

CASES.eventloop = async () => {
  const { wasm, native, withFonts } = await load();
  // a deliberately heavy call: 60 animation frames of a blurred, shadowed tree
  const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundImage: "linear-gradient(135deg,#1e3a8a,#db2777)", alignItems: "center", justifyContent: "center" },
    children: Array.from({ length: 12 }, (_, i) => ({ type: "container", style: { width: 60, height: 60, margin: 6, borderRadius: 30, backgroundColor: "#fff", boxShadow: "0 8px 30px rgba(0,0,0,.5)", filter: "blur(2px)", transform: `rotate(${i * 10}deg)` } })) };
  const job = { scenes: [{ node, durationMs: 2000 }], width: 800, height: 420, fps: 30, format: "webp" };
  const measure = async (B) => {
    const r = withFonts(B, ["Inter"]);
    let maxGap = 0, ticks = 0, last = performance.now();
    const timer = setInterval(() => { const now = performance.now(); maxGap = Math.max(maxGap, now - last); last = now; ticks++; }, 1);
    await new Promise((res) => setTimeout(res, 30));
    maxGap = 0; ticks = 0; last = performance.now();
    const t0 = performance.now();
    const out = await r.renderAnimation(job);
    const ms = performance.now() - t0;
    maxGap = Math.max(maxGap, performance.now() - last);
    clearInterval(timer);
    r.free();
    return { ms: +ms.toFixed(0), maxTimerDelayMs: +maxGap.toFixed(1), timerTicks: ticks, hash: sha(out) };
  };
  const w = await measure(wasm);
  const n = await measure(native);
  notes.eventloop = { job: "renderAnimation 60 frames 800x420 webp", wasm: w, native: n };
  check(w.hash === n.hash, "the heavy animation is byte-identical");
  check(n.maxTimerDelayMs < 50 && n.maxTimerDelayMs < w.maxTimerDelayMs / 4, `event loop stays responsive natively (max 1 ms-timer delay: native ${n.maxTimerDelayMs} ms, wasm ${w.maxTimerDelayMs} ms)`);
  check(n.timerTicks > 20, `timers kept firing during the native render (${n.timerTicks} ticks)`);
};

CASES.free = async () => {
  const { wasm, native, addon, ALL_CASES, renderOpts, withFonts } = await load();
  const k = ALL_CASES.find((c) => c.id === "card-og");
  const want = sha(withFonts(wasm).renderSync(k.node, renderOpts(k, "png")));
  const base = addon.memoryBytes();
  // free() right after queueing 30 renders: the one already on a pool thread finishes, the rest fail cleanly
  for (let round = 0; round < 20; round++) {
    const r = withFonts(native);
    const ps = Array.from({ length: 30 }, () => r.render(k.node, renderOpts(k, "png")));
    if (round % 2) await new Promise((res) => setTimeout(res, round));
    r.free();
    const res = await Promise.allSettled(ps);
    const good = res.filter((x) => x.status === "fulfilled");
    const bad = res.filter((x) => x.status === "rejected");
    if (!check(good.every((x) => sha(x.value) === want), "renders that completed before free() are correct")) break;
    if (!check(bad.every((x) => x.reason.message === "bm-engine: renderer has been freed"), `renders after free() reject with "renderer has been freed" (${bad[0] && bad[0].reason.message})`)) break;
    if (round === 0) notes.free = { fulfilled: good.length, rejected: bad.length };
    let threw = "";
    try { await r.render(k.node, {}); } catch (e) { threw = e.message; }
    check(threw === "bm-engine: renderer has been freed", "render() on a freed renderer rejects");
    r.free(); // idempotent
  }
  // dropping the last reference while work is pending: the work completes, then the memory goes away
  // (created in a plain function so that no frame of this async function keeps a renderer reachable)
  const startDropped = () => Array.from({ length: 20 }, () => withFonts(native, ["Inter"]).render(k.node, renderOpts(k, "png")));
  let pending = startDropped();
  if (global.gc) global.gc();
  const outs = await Promise.all(pending);
  check(outs.every((o) => sha(o) === want), "renderers dropped (not freed) with pending work still deliver");
  pending = null;
  for (let i = 0; i < 10 && global.gc; i++) { global.gc(); await new Promise((res) => setTimeout(res, 20)); }
  const after = addon.memoryBytes();
  notes.free = { ...notes.free, nativeBytesBefore: base, nativeBytesAfterAllDropped: after };
  if (global.gc) check(after - base < 1 << 20, `native memory returns to the baseline after free / GC (${base} -> ${after} bytes)`);
};

CASES.gc = async () => {
  const { native, addon } = await load();
  const inter = fontFile("Inter-Regular.ttf"), noto = fontFile("NotoSans-Regular.ttf");
  const node = { type: "container", style: { display: "flex", width: 300, height: 100, backgroundColor: "#fff" }, children: [{ type: "text", text: "GC stress 0123456789", style: { fontFamily: "Inter", fontSize: 24 } }] };
  const mb = (n) => +(n / 1048576).toFixed(1);
  const series = [];
  const loop = async (count, freeEach) => {
    for (let i = 1; i <= count; i++) {
      const r = new native.Renderer();
      r.registerFont({ name: "Inter", data: inter });
      r.registerFont({ name: "Noto Sans", data: noto });
      r.renderSync(node, { format: "raw" });
      if (freeEach) r.free();
      if (i % 50 === 0) await new Promise((res) => setImmediate(res)); // let finalizers run, as a server's event loop would
      if (i % 500 === 0) series.push({ mode: freeEach ? "free()" : "dropped", i, rssMB: mb(process.memoryUsage().rss), nativeMB: mb(addon.memoryBytes()), externalMB: mb(process.memoryUsage().external) });
    }
  };
  // 1. renderers are only dropped (no free(), no forced gc): V8 must collect them from the reported external memory
  await loop(4000, false);
  const dropped = series.filter((s) => s.mode === "dropped");
  // 2. explicit free()
  await loop(4000, true);
  for (let i = 0; i < 10; i++) { global.gc(); await new Promise((res) => setTimeout(res, 20)); }
  const end = { rssMB: mb(process.memoryUsage().rss), nativeMB: mb(addon.memoryBytes()) };
  notes.gc = { perRendererMB: mb(inter.length + noto.length), series, afterFinalGc: end };
  const early = Math.max(...dropped.slice(0, 2).map((s) => s.rssMB)), late = Math.max(...dropped.slice(-3).map((s) => s.rssMB));
  check(late < early * 1.5 + 64, `RSS plateaus while dropping 4000 renderers (max of first 1000: ${early} MB, max of last 1500: ${late} MB)`);
  const freed = series.filter((s) => s.mode === "free()").slice(1); // (the first sample still sees renderers dropped by part 1)
  check(Math.max(...freed.map((s) => s.nativeMB)) < 8, `with free() native memory stays flat (max ${Math.max(...freed.map((s) => s.nativeMB))} MB)`);
  check(end.nativeMB < 1, `native memory after the final GC: ${end.nativeMB} MB`);
};

CASES.errors = async () => {
  const { wasm, native, ALL_CASES, renderOpts, withFonts } = await load();
  const k = ALL_CASES.find((c) => c.id === "card-og");
  const deep = (n) => { let x = { type: "text", text: "x" }; for (let i = 0; i < n; i++) x = { type: "container", children: [x] }; return x; };
  const aborted = AbortSignal.abort();
  const inputs = {
    "invalid JSON": [{ json: "{\"type\":" }, {}],
    "not a node": [{ json: "[1,2]" }, {}],
    "unknown format": [k.node, { format: "tiff" }],
    "bad width": [k.node, { width: "wide" }],
    "513 levels": [deep(513), { width: 50, height: 50 }],
    "ico too large": [k.node, { ...renderOpts(k, "ico") }],
    "canvas too large": [k.node, { width: 100000, height: 100000 }],
    "bad rgba": [{ type: "image", src: { width: 4, height: 4, data: new Uint8Array(5) } }, {}],
    "aborted": [k.node, { signal: aborted }],
    "lazy image in images": [k.node, { images: [{ src: "a", data: () => new Uint8Array(4) }] }],
    "malformed html": ["<div><<<p></div></span>", { width: 100, height: 40 }],
  };
  const wr = withFonts(wasm), nr = withFonts(native);
  const table = {};
  for (const [name, [node, opts]] of Object.entries(inputs)) {
    const w = outcome(() => wr.renderSync(node, opts));
    const s = outcome(() => nr.renderSync(node, opts));
    let a;
    try { const v = await nr.render(node, opts); a = { ok: sha(Buffer.from(v.buffer, v.byteOffset, v.byteLength)) }; } catch (e) { a = { error: String(e && e.message) }; }
    // (the async API resolves lazy images, so that one input legitimately differs from the sync call)
    const wa = name === "lazy image in images" ? await wr.render(node, opts).then((v) => ({ ok: sha(Buffer.from(v.buffer, v.byteOffset, v.byteLength)) }), (e) => ({ error: e.message })) : w;
    table[name] = w.error ?? w.ok;
    check(same(w, s), `sync: ${name}: wasm ${JSON.stringify(w)} native ${JSON.stringify(s)}`);
    check(same(wa, a), `async: ${name}: wasm ${JSON.stringify(wa)} native ${JSON.stringify(a)}`);
  }
  // other entry points
  for (const [name, fn] of Object.entries({
    "measure invalid": (r) => JSON.stringify(r.measureSync({ json: "nope" }, {})),
    "svg invalid": (r) => r.renderSvgSync({ json: "nope" }, {}),
    "animation fps": (r) => r.renderAnimationSync({ scenes: [{ node: k.node, durationMs: 100 }], width: 10, height: 10, fps: 1000 }),
    "animation gif fps 60": (r) => r.renderAnimationSync({ scenes: [{ node: k.node, durationMs: 100 }], width: 10, height: 10, fps: 60, format: "gif" }),
    "font garbage": (r) => JSON.stringify(r.registerFont(new Uint8Array(100))),
    "woff garbage": (r) => JSON.stringify(r.registerFont(new Uint8Array([0x77, 0x4f, 0x46, 0x32, 1, 2, 3, 4, 5, 6, 7, 8]))),
  })) {
    const w = outcome(() => fn(wr)), s = outcome(() => fn(nr));
    table[name] = w.error ?? w.ok;
    check(same(w, s), `${name}: wasm ${JSON.stringify(w)} native ${JSON.stringify(s)}`);
  }
  let asyncAnim;
  try { await nr.renderAnimation({ scenes: [], width: 10, height: 10, fps: 10 }); } catch (e) { asyncAnim = e.message; }
  check(asyncAnim === outcome(() => wr.renderAnimationSync({ scenes: [], width: 10, height: 10, fps: 10 })).error, "async renderAnimation rejects with the wasm message");
  notes.errors = table;
};

// ---- d. fallback ------------------------------------------------------------------------------------------
CASES.fallback = async () => {
  const probe = `const m = await import(${JSON.stringify(href("js", "node.mjs"))}); const r = new m.Renderer();` +
    `const o = await r.render({type:"container",style:{width:40,height:20,backgroundColor:"teal"}},{format:"png"});` +
    `const { loadWoff } = await import(${JSON.stringify(href("js", "addons.mjs"))}); const w = await loadWoff();` +
    `console.log(JSON.stringify({backend:m.backend, bytes:o.length, woff:m.features.woff, builtIn:w.builtIn, mem:r.memoryBytes()}));`;
  const run = (env, code = probe) => {
    const r = spawnSync(process.execPath, ["--input-type=module", "-e", code], { encoding: "utf8", env: { ...process.env, BM_ENGINE_BACKEND: "", BM_ENGINE_NATIVE_PATH: "", ...env } });
    let json = null;
    try { json = JSON.parse(r.stdout.trim().split("\n").pop()); } catch {}
    return { status: r.status, json, stderr: r.stderr.split("\n").filter((l) => /Error|bm-engine/.test(l)).slice(0, 2).join(" | ").slice(0, 400), noise: r.stderr.trim().length };
  };
  const garbage = path.join(BENCH, "out", "not-an-addon.node");
  mkdirSync(path.dirname(garbage), { recursive: true });
  writeFileSync(garbage, "this is not a shared library");
  const table = {
    default: run({}),
    "BM_ENGINE_BACKEND=wasm": run({ BM_ENGINE_BACKEND: "wasm" }),
    "BM_ENGINE_BACKEND=native": run({ BM_ENGINE_BACKEND: "native" }),
    "NATIVE_PATH=missing": run({ BM_ENGINE_NATIVE_PATH: path.join(BENCH, "out", "does-not-exist.node") }),
    "NATIVE_PATH=garbage file": run({ BM_ENGINE_NATIVE_PATH: garbage }),
    "NATIVE_PATH=missing + BACKEND=native": run({ BM_ENGINE_NATIVE_PATH: path.join(BENCH, "out", "does-not-exist.node"), BM_ENGINE_BACKEND: "native" }),
    "BM_ENGINE_BACKEND=bogus": run({ BM_ENGINE_BACKEND: "gpu" }),
    "BM_PROFILE=core (a wasm choice)": run({ BM_PROFILE: "core" }),
    "bm-engine/native, addon missing": run({ BM_ENGINE_NATIVE_PATH: garbage }, `await import(${JSON.stringify(href("js", "node-native.mjs"))})`),
    "bm-engine/full (always wasm)": run({}, `const m = await import(${JSON.stringify(href("js", "node-full.mjs"))}); console.log(JSON.stringify({backend:m.backend}))`),
  };
  notes.fallback = Object.fromEntries(Object.entries(table).map(([k, v]) => [k, v.json ? v.json : `exit ${v.status}: ${v.stderr}`]));
  const ok = (name, backend) => check(table[name].status === 0 && table[name].json && table[name].json.backend === backend && (name.includes("native,") || table[name].json.bytes === table.default.json.bytes || !table[name].json.bytes), `${name} -> ${backend} (${JSON.stringify(table[name].json)} ${table[name].stderr})`);
  ok("default", "native");
  ok("BM_ENGINE_BACKEND=wasm", "wasm");
  ok("BM_ENGINE_BACKEND=native", "native");
  ok("NATIVE_PATH=missing", "wasm");
  ok("NATIVE_PATH=garbage file", "wasm");
  ok("BM_PROFILE=core (a wasm choice)", "wasm");
  ok("bm-engine/full (always wasm)", "wasm");
  check(table["NATIVE_PATH=missing"].noise === 0 && table["NATIVE_PATH=garbage file"].noise === 0, "the fallback to wasm prints nothing");
  check(table.default.json.builtIn === true && table["NATIVE_PATH=missing"].json.builtIn === true, "loadWoff() reports built-in WOFF on both backends of the full build");
  check(table["NATIVE_PATH=missing + BACKEND=native"].status !== 0 && /BM_ENGINE_BACKEND=native, but the native addon is not available/.test(table["NATIVE_PATH=missing + BACKEND=native"].stderr), "BM_ENGINE_BACKEND=native without an addon fails with a clear error");
  check(table["BM_ENGINE_BACKEND=bogus"].status !== 0 && /must be "wasm" or "native"/.test(table["BM_ENGINE_BACKEND=bogus"].stderr), "a bogus BM_ENGINE_BACKEND is rejected");
  check(table["bm-engine/native, addon missing"].status !== 0 && /bm-engine\/native: the native addon is not available/.test(table["bm-engine/native, addon missing"].stderr), "bm-engine/native without an addon fails with a clear error");
};

// ---- e. worker threads ------------------------------------------------------------------------------------
const WORKER_NODE = { type: "container", style: { display: "flex", width: 400, height: 200, backgroundImage: "linear-gradient(90deg,#fde68a,#f0abfc)", alignItems: "center", justifyContent: "center" }, children: [{ type: "text", text: "worker threads", style: { fontFamily: "Inter", fontSize: 40 } }] };
async function workerMain() {
  const m = await import(href("js", "node.mjs"));
  const r = new m.Renderer();
  r.registerFont({ name: "Inter", data: fontFile("Inter-Regular.ttf") });
  if (workerData.mode === "render") {
    const hashes = new Set();
    for (let i = 0; i < 10; i++) hashes.add(sha(r.renderSync(WORKER_NODE, { format: "png" })));
    for (const o of await Promise.all(Array.from({ length: 10 }, () => r.render(WORKER_NODE, { format: "png" })))) hashes.add(sha(o));
    parentPort.postMessage({ backend: m.backend, hashes: [...hashes] });
  } else {
    // render forever; the parent terminates this thread in the middle
    parentPort.postMessage({ ready: true });
    for (;;) await Promise.all(Array.from({ length: 4 }, () => r.render(WORKER_NODE, { format: "png", width: 1200, height: 630 })));
  }
}
CASES.workers = async () => {
  const { native } = await load();
  const r = new native.Renderer();
  r.registerFont({ name: "Inter", data: fontFile("Inter-Regular.ttf") });
  const want = sha(r.renderSync(WORKER_NODE, { format: "png" }));
  const spawn = (mode) => new Worker(SELF, { workerData: { mode } });
  // 1. eight workers load the addon at the same time and render
  const results = await Promise.all(Array.from({ length: 8 }, () => new Promise((res, rej) => { const w = spawn("render"); w.once("message", (m) => w.terminate().then(() => res(m))); w.once("error", rej); })));
  check(results.every((m) => m.backend === "native"), "every worker runs the native backend");
  check(results.every((m) => m.hashes.length === 1 && m.hashes[0] === want), "every worker renders the main thread's bytes (sync and async)");
  // 2. workers killed while their renders are on the pool, 25 rounds of 4
  let killed = 0;
  for (let round = 0; round < 25; round++) {
    await Promise.all(Array.from({ length: 4 }, (_, i) => new Promise((res, rej) => {
      const w = spawn("loop");
      w.once("error", rej);
      w.once("message", () => setTimeout(() => w.terminate().then(() => { killed++; res(); }), 3 + ((round * 7 + i * 13) % 40)));
    })));
    if (sha(r.renderSync(WORKER_NODE, { format: "png" })) !== want) { check(false, "main thread output changed after worker termination"); break; }
  }
  check(killed === 100, `100 workers terminated mid-render without a crash (${killed})`);
  check(sha(await r.render(WORKER_NODE, { format: "png" })) === want, "the main thread still renders correctly afterwards");
  notes.workers = { simultaneous: 8, terminatedMidRender: killed };
};

// ---- libm: the addon's own floor / ceil / trunc / round / fmod against JavaScript's exact results -----------
CASES.libm = async () => {
  const { addon } = await load();
  let seed = 0x9e3779b9;
  const next = () => { seed ^= seed << 13; seed >>>= 0; seed ^= seed >>> 17; seed ^= seed << 5; seed >>>= 0; return seed; };
  const roundAway = (x) => { const a = Math.abs(x), f = Math.floor(a), r = a - f >= 0.5 ? f + 1 : f; return x < 0 || Object.is(x, -0) ? -r : r; };
  const refs = [Math.floor, Math.ceil, Math.trunc, roundAway];
  const names = ["floor", "ceil", "trunc", "round", "fmod"];
  const edge = [0, 0.25, 0.49999997, 0.5, 0.50000006, 0.75, 1, 1.5, 2.5, 3.5, 8388607.5, 8388608, 16777216, 4503599627370495.5, 4503599627370496, 9007199254740992, 1e-45, 1e-310, 1.17549435e-38, 2.2250738585072014e-308, 3.4028234663852886e38, 1.7976931348623157e308, Infinity, NaN, 0.1, 1 / 3, 123456.789, 2147483647.5, 4294967295.5, 1e15 + 0.5];
  const stats = {};
  for (const [ti, F, I] of [[0, Float32Array, Uint32Array], [1, Float64Array, BigUint64Array]]) {
    const N = 1 << 20;
    const vals = new F(N);
    const bits = new I(vals.buffer);
    let k = 0;
    for (const e of edge) { vals[k++] = e; vals[k++] = -e; }
    for (; k < N; k++) {
      const how = k & 3;
      if (how === 0) { if (ti === 0) bits[k] = next(); else bits[k] = (BigInt(next()) << 32n) | BigInt(next()); } // any bit pattern
      else if (how === 1) vals[k] = (next() / 4294967296 - 0.5) * 4096; // small magnitudes, the engine's usual range
      else if (how === 2) vals[k] = ((next() % 2000001) - 1000000) / 2; // integers and exact halves
      else vals[k] = (next() / 4294967296 - 0.5) * 2 ** ((next() % 120) - 30); // every binade around the integer boundary
    }
    const input = new Uint8Array(vals.buffer);
    for (let fn = 0; fn < 4; fn++) {
      const out = new F(addon.run(null, addon.ops.mathProbe, fn, ti, null, null, ["", input, 0, 0, 0]).buffer);
      let bad = 0, first = null;
      for (let i = 0; i < N; i++) {
        const want = refs[fn](vals[i]);
        if (!(Object.is(out[i], want) || (Number.isNaN(want) && Number.isNaN(out[i])))) { bad++; first ??= `${names[fn]}(${vals[i]}) = ${out[i]}, expected ${want}`; }
      }
      stats[`${names[fn]} f${ti ? 64 : 32}`] = bad;
      check(bad === 0, `${names[fn]} f${ti ? 64 : 32}: ${N} values bit-exact (${bad} wrong; ${first})`);
    }
    // fmod over consecutive pairs (x = vals[i], y = vals[i + 1])
    const out = new F(addon.run(null, addon.ops.mathProbe, 4, ti, null, null, ["", input, 0, 0, 0]).buffer);
    let bad = 0, first = null, tested = 0;
    for (let i = 0; i + 1 < N; i++) {
      const x = vals[i], y = vals[i + 1];
      if (!(y !== 0 && y === y && x === x && Number.isFinite(x))) continue;
      tested++;
      const want = x % y;
      if (!Object.is(out[i], want)) { bad++; first ??= `fmod(${x}, ${y}) = ${out[i]}, expected ${want}`; }
    }
    stats[`fmod f${ti ? 64 : 32}`] = bad;
    check(bad === 0, `fmod f${ti ? 64 : 32}: ${tested} pairs bit-exact (${bad} wrong; ${first})`);
  }
  notes.libm = { valuesPerFunction: 1 << 20, wrong: stats };
};

// ---- stack ------------------------------------------------------------------------------------------------
function deepInputs() {
  const heavy = (i) => ({ display: i % 3 === 0 ? "grid" : i % 3 === 1 ? "flex" : "block", padding: 0.5, opacity: i % 16 === 0 ? 0.9 : 1, overflow: i % 5 === 0 ? "hidden" : "visible", borderRadius: 3, border: "1px solid red", transform: i % 7 === 0 ? "rotate(1deg)" : undefined, filter: i % 31 === 0 ? "blur(1px)" : undefined, boxShadow: "0 0 2px #000" });
  const tree = (depth, style) => { let n = { type: "text", text: "Deep text with shadow", style: { fontFamily: "Inter", fontWeight: 700, textDecoration: "underline", textShadow: "0 1px 2px red" } }; for (let i = 0; i < depth; i++) n = { type: "container", style: style(i), children: [n] }; return n; };
  const o = { width: 400, height: 300 };
  const svg = (inner) => `<svg xmlns="http://www.w3.org/2000/svg" width="50" height="50" viewBox="0 0 50 50">${inner}</svg>`;
  const list = [];
  const add = (name, fn) => list.push({ name, fn });
  for (const [label, style] of [["heavy", heavy], ["flex", () => ({ display: "flex" })], ["block", () => ({ display: "block", padding: 0.1 })], ["grid", () => ({ display: "grid" })], ["table", (i) => ({ display: ["table", "table-row", "table-cell"][i % 3] })], ["inline", () => ({ display: "inline" })], ["float", () => ({ float: "left" })]]) {
    add(`511 containers + text ${label}: png`, (r) => r.renderSync(tree(511, style), { ...o, format: "png" }));
    add(`511 containers + text ${label}: measure`, (r) => JSON.stringify(r.measureSync(tree(511, style), o)));
    add(`511 containers + text ${label}: svg`, (r) => r.renderSvgSync(tree(511, style), o));
  }
  add("512 containers + text (rejected)", (r) => r.renderSync(tree(512, heavy), o));
  add("511 levels heavy at dpr 2", (r) => r.renderSync(tree(511, heavy), { ...o, devicePixelRatio: 2, format: "raw" }));
  add("JSON nested 100000 arrays", (r) => r.renderSync({ json: "[".repeat(100000) }, o));
  add("JSON nested 100000 objects", (r) => r.renderSync({ json: "{\"children\":[".repeat(100000) }, o));
  add("options JSON nested deep", (r) => r.renderSync({ json: "{\"type\":\"container\"}" }, { ...o, css: JSON.parse("[".repeat(3000) + "]".repeat(3000)) }));
  for (const tag of ["div", "span", "b", "table", "ul", "blockquote", "svg", "p"]) add(`HTML 600 nested <${tag}>`, (r) => r.renderSync(`<${tag}>`.repeat(600) + "x", { ...o, format: "raw" }));
  add("HTML 100000 nested <div>", (r) => r.renderSync("<div>".repeat(100000) + "x", { ...o, format: "raw" }));
  add("HTML 100000 nested <span> measure", (r) => JSON.stringify(r.measureSync("<span>".repeat(100000) + "x", o)));
  add("HTML 20000 nested <i> closed", (r) => r.renderSync("<i>".repeat(20000) + "x" + "</i>".repeat(20000), { ...o, format: "raw" }));
  const cssCase = (name, css) => add(name, (r) => r.renderSync("<div class=a><p>text</p></div>", { ...o, format: "raw", css: [css] }));
  cssCase("CSS calc nested 5000", `.a{width:${"calc(".repeat(5000)}1px${")".repeat(5000)}}`);
  cssCase("CSS min/max nested 3000", `.a{width:${"min(max(".repeat(1500)}1px${",2px),3px)".repeat(1500)}}`);
  cssCase("CSS :not nested 5000", `${":not(".repeat(5000)}p${")".repeat(5000)}{color:red}`);
  cssCase("CSS :is nested 5000", `${":is(".repeat(5000)}.a${")".repeat(5000)} p{color:red}`);
  cssCase("CSS @media nested 5000", `${"@media all{".repeat(5000)}.a{color:red}${"}".repeat(5000)}`);
  cssCase("CSS blocks nested 20000", `${".a{".repeat(20000)}color:red${"}".repeat(20000)}`);
  cssCase("CSS var chain 2000", Array.from({ length: 2000 }, (_, i) => `--v${i}:var(--v${i + 1})`).join(";").replace(/^/, ".a{") + ";--v2000:5px;width:var(--v0)}");
  cssCase("CSS var cycle", ".a{--a:var(--b);--b:var(--a);width:var(--a)}");
  cssCase("CSS color-mix nested 2000", `.a{color:${"color-mix(in srgb,".repeat(2000)}red${",blue)".repeat(2000)}}`);
  cssCase("CSS gradient in gradient garbage", `.a{background:${"linear-gradient(".repeat(3000)}red,blue${")".repeat(3000)}}`);
  cssCase("CSS unbalanced 100000 parens", `.a{width:${"(".repeat(100000)}}`);
  add("style calc nested 5000", (r) => r.renderSync({ type: "container", style: { width: "calc(".repeat(5000) + "1px" + ")".repeat(5000), transform: "rotate(".repeat(2000) + "1deg" + ")".repeat(2000) } }, { ...o, format: "raw" }));
  add("tw arbitrary nested", (r) => r.renderSync({ type: "container", tw: "w-[" + "calc(".repeat(3000) + "1px" + ")".repeat(3000) + "] " + "hover:".repeat(3000) + "p-1 " + "[&>*]:".repeat(2000) + "m-1" }, { ...o, format: "raw" }));
  add("SVG 5000 nested <g>", (r) => r.renderSync({ type: "image", src: svg("<g>".repeat(5000) + "<rect width='10' height='10'/>" + "</g>".repeat(5000)) }, { ...o, format: "raw" }));
  add("SVG 100000 unclosed <g>", (r) => r.renderSync({ type: "image", src: svg("<g>".repeat(100000)) }, { ...o, format: "raw" }));
  add("SVG <use> cycle", (r) => r.renderSync({ type: "image", src: svg("<defs><g id='a'><use href='#b'/></g><g id='b'><use href='#a'/></g></defs><use href='#a'/>") }, { ...o, format: "raw" }));
  add("SVG <use> fan-out", (r) => r.renderSync({ type: "image", src: svg("<defs>" + Array.from({ length: 30 }, (_, i) => `<g id='g${i}'><use href='#g${i + 1}'/><use href='#g${i + 1}'/></g>`).join("") + "<rect id='g30' width='1' height='1'/></defs><use href='#g0'/>") }, { ...o, format: "raw" }));
  add("SVG nested <svg> 3000 + transforms", (r) => r.renderSync({ type: "image", src: svg("<svg>".repeat(3000) + "<g transform='rotate(1)'>".repeat(3000)) }, { ...o, format: "raw" }));
  add("SVG path with 200000 commands", (r) => r.renderSync({ type: "image", src: svg(`<path d="M0 0${" l1 1 -1 0".repeat(100000)}"/>`) }, { ...o, format: "raw" }));
  add("clip-path path() huge", (r) => r.renderSync({ type: "container", style: { width: 100, height: 100, backgroundColor: "red", clipPath: `path("M0 0${" c1 1 2 2 3 0".repeat(50000)}")` } }, { ...o, format: "raw" }));
  add("bidi 5000 embeddings", (r) => r.renderSync({ type: "text", text: "‪‫".repeat(2500) + "abc אבג 123" + "‬".repeat(5000), style: { fontFamily: "Inter" } }, { ...o, format: "raw" }));
  add("1 MB single word", (r) => r.renderSync({ type: "text", text: "a".repeat(1 << 20), style: { fontFamily: "Inter", fontSize: 3 } }, { ...o, format: "raw" }));
  add("3000 combining marks", (r) => JSON.stringify(r.measureSync({ type: "text", text: "e" + "́".repeat(3000), style: { fontFamily: "Inter" } }, o)));
  add("animation with deep scene", (r) => r.renderAnimationSync({ scenes: [{ node: tree(511, heavy), durationMs: 100 }], width: 100, height: 80, fps: 20, format: "gif" }));
  return list;
}

CASES["stack-probe"] = async () => {
  // child of `stack`: runs deep input #idx natively on a helper thread with exactly --stack bytes
  const { native, addon, withFonts } = await load();
  addon.tune(+args.mode || 2, +args.stack, 0);
  const r = withFonts(native, ["Inter"]);
  const inputs = deepInputs();
  const ids = String(args.idx).split(",").map(Number);
  const out = {};
  const ms = {};
  for (const i of ids) { const t0 = performance.now(); out[i] = outcome(() => inputs[i].fn(r)); ms[i] = Math.round(performance.now() - t0); }
  if (args.times) for (const i of ids) console.log(`TIME ${ms[i]} ms  ${inputs[i].name}`);
  console.log("RESULT " + JSON.stringify(out));
};

CASES.stack = async () => {
  const { wasm, newWasm, withFonts } = await load();
  const inputs = deepInputs();
  // reference outcomes from the wasm build (a wasm trap poisons the instance: start a new one)
  let B = wasm, wr = withFonts(B, ["Inter"]);
  const ref = inputs.map((x) => { const o = outcome(() => x.fn(wr)); if (o.trap) { B = newWasm(); wr = withFonts(B, ["Inter"]); } return o; });
  const probe = (stack, idx, mode = 2) => {
    const r = spawnSync(process.execPath, [SELF, "--case=stack-probe", `--stack=${stack}`, `--idx=${idx.join(",")}`, `--mode=${mode}`], { encoding: "utf8", timeout: 300000 });
    const line = r.stdout.split("\n").find((l) => l.startsWith("RESULT "));
    return { status: r.status, signal: r.signal, out: line ? JSON.parse(line.slice(7)) : null };
  };
  const all = inputs.map((_, i) => i);
  // 1. the shipped configuration: automatic mode (inline on this thread's stack), and forced helper thread of the default size
  const table = [];
  const dflt = probe(0, all, 1), thr = probe(0, all, 2);
  check(dflt.status === 0 && dflt.out, `default configuration survives every deep input (exit ${dflt.status})`);
  check(thr.status === 0 && thr.out, `helper thread with the default stack survives every deep input (exit ${thr.status})`);
  let wasmTraps = 0;
  inputs.forEach((x, i) => {
    const w = ref[i], n = dflt.out && dflt.out[i], t = thr.out && thr.out[i];
    if (w.trap) { wasmTraps++; check(n && !n.trap, `${x.name}: wasm TRAPS (${w.trap}); native must at least not crash: ${JSON.stringify(n)}`); }
    else { check(same(w, n), `${x.name}: wasm ${JSON.stringify(w)} native ${JSON.stringify(n)}`); check(same(w, t), `${x.name} (helper thread): wasm ${JSON.stringify(w)} native ${JSON.stringify(t)}`); }
    table.push({ input: x.name, wasm: w.trap ? "TRAP " + w.trap : w.error ? "error: " + w.error : "ok", native: n ? (n.error ? "error: " + n.error : "ok") : "CRASH" });
  });
  // 2. how much stack does the worst input really need? smallest helper-thread stack on which ALL inputs behave
  let lo = 16 << 10, hi = 3 << 20; // lo fails (or is the floor), hi passes
  const passes = (s) => { const p = probe(s, all); return p.status === 0 && p.out && inputs.every((_, i) => ref[i].trap || same(ref[i], p.out[i])); };
  if (passes(lo)) hi = lo;
  while (hi - lo > 8 << 10) { const mid = (lo + hi) >> 1; if (passes(mid)) hi = mid; else lo = mid; }
  // which inputs are the hungriest: the ones that fail at 3/4 of the requirement
  const tight = probe(Math.max(16 << 10, (hi * 3) >> 2), all);
  const hungry = tight.out ? inputs.filter((_, i) => !ref[i].trap && !same(ref[i], tight.out[i])).map((x) => x.name) : [`(process died with exit ${tight.status}: inputs unknown)`];
  // one by one at 3/4 when the whole batch dies
  const worst = [];
  if (!tight.out) for (const i of all) { const p = probe(Math.max(16 << 10, (hi * 3) >> 2), [i]); if (p.status !== 0) worst.push(inputs[i].name); }
  notes.stack = { inputs: inputs.length, wasmTraps, minimalStackKiB: hi >> 10, defaultStackKiB: 3072, marginX: +((3 << 20) / hi).toFixed(1), crashAtThreeQuarters: worst.length ? worst : hungry, table };
  check(hi <= 1 << 20, `every deep input fits a ${hi >> 10} KiB stack: the 3072 KiB guarantee has >= 3x margin`);
};

// ---- f. fuzz ----------------------------------------------------------------------------------------------
function runProbe(name, script, argv, cwd = BENCH) {
  const r = spawnSync(process.execPath, ["--import", href("bench", "lib", "native-hooks.mjs"), script, ...argv], { cwd, encoding: "utf8", timeout: 900000, env: { ...process.env, BM_WASM: WASM_FILE, BM_ENGINE_BACKEND: "" }, maxBuffer: 64 << 20 });
  const tail = r.stdout.trim().split("\n").slice(-1)[0] || "";
  const traps = (r.stdout.match(/^TRAP/gm) || []).length;
  check(r.status === 0 && traps === 0, `${name} ${argv.join(" ")}: exit ${r.status}${r.signal ? " signal " + r.signal : ""}, ${traps} traps; ${tail.slice(0, 200)} ${r.status ? r.stderr.slice(-300) : ""}`);
  return { exit: r.status, signal: r.signal, summary: tail.slice(0, 300) };
}
CASES["fuzz-tree"] = async () => {
  // bench/probe/fuzz.mjs: random node trees with every style family, 4 seeds x 2500 trees
  notes["fuzz-tree"] = [1, 2, 3, 4].map((seed) => ({ seed, ...runProbe("probe/fuzz.mjs", "probe/fuzz.mjs", [String(seed), "2500"]) }));
};
CASES["fuzz-inline"] = async () => {
  // bench/probe/layout3/fuzz.mjs: random inline / float HTML, 3 seeds x 1500
  notes["fuzz-inline"] = [1, 2, 3].map((seed) => ({ seed, ...runProbe("probe/layout3/fuzz.mjs", "probe/layout3/fuzz.mjs", [String(seed), "1500"]) }));
};
CASES["fuzz-table"] = async () => {
  // bench/probe/f2/tablefuzz.mjs: random tables, 3 seeds x 800
  notes["fuzz-table"] = [1, 2, 3].map((seed) => ({ seed, ...runProbe("probe/f2/tablefuzz.mjs", "probe/f2/tablefuzz.mjs", [String(seed), "800"]) }));
};

CASES["fuzz-diff-run"] = async () => {
  // child of fuzz-diff: one class of mutated inputs, every input through wasm AND native, outcomes compared
  const { newWasm, native, ALL_CASES } = await load();
  const cls = String(args.class);
  let seed = (+args.seed || 1) >>> 0;
  const rnd = (n) => { seed = (seed + 0x6d2b79f5) >>> 0; let t = seed; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return (((t ^ (t >>> 14)) >>> 0) % n); };
  const inter = fontFile("Inter-Regular.ttf");
  let W = newWasm(), wr = new W.Renderer(), nr = new native.Renderer();
  wr.registerFont({ name: "Inter", data: inter }); nr.registerFont({ name: "Inter", data: inter });
  const resetWasm = () => { W = newWasm(); wr = new W.Renderer(); wr.registerFont({ name: "Inter", data: inter }); };
  const mutateBytes = (src, headBias) => {
    let b = Uint8Array.from(src);
    const how = rnd(10);
    if (how === 0) b = b.slice(0, rnd(b.length));
    else if (how === 1) { const at = rnd(b.length), n = rnd(64); b = Uint8Array.from([...b.subarray(0, at), ...b.subarray(Math.min(b.length, at + n))]); }
    for (let k = rnd(8); k >= 0; k--) {
      const at = headBias && rnd(3) ? rnd(Math.min(b.length, headBias)) : rnd(b.length || 1);
      const m = rnd(4);
      if (b.length === 0) break;
      b[at] = m === 0 ? rnd(256) : m === 1 ? b[at] ^ (1 << rnd(8)) : m === 2 ? 0xff : 0;
    }
    return b;
  };
  const toks = ["<", ">", "</", "/>", "<!--", "-->", "<![CDATA[", "]]>", "&#", "&amp", ";", "\"", "'", "=", "<svg", "</svg>", "<p>", "<table>", "<tr>", "<td>", "<li>", "<textarea>", "<script>", "<style>", "<template>", "\r", "\0", "�", "<pre>", "<body>", "<html>", "<!doctype html>",
    "{", "}", "(", ")", "calc(", "var(--x)", "!important", "@media", "@keyframes k{", ":not(", "::before", "url(", "#", "%", "1e99", "-", "\\", "/*", "*/", "[", "]", ",", "rgb(", "linear-gradient(", "\"type\":", "\"children\":[", "null", "1e999", "\\ud800", "‮"];
  const mutateText = (s) => {
    if (rnd(4) === 0) s = s.slice(0, rnd(s.length + 1));
    for (let k = rnd(10); k >= 0; k--) {
      const at = rnd(s.length + 1), m = rnd(3);
      if (m === 0) s = s.slice(0, at) + toks[rnd(toks.length)] + s.slice(at);
      else if (m === 1) s = s.slice(0, at) + s.slice(at + rnd(40));
      else s = s.slice(0, at) + s.slice(rnd(s.length + 1));
    }
    return s.slice(0, 200000);
  };
  const o = { width: 240, height: 160, format: "raw" };
  const htmlDir = path.join(ROOT, "ref", "takumi", "takumi", "tests", "fixtures-html");
  const htmlSeeds = existsSync(htmlDir) ? readdirSync(htmlDir).filter((f) => f.endsWith(".html")).map((f) => readFileSync(path.join(htmlDir, f), "utf8")) : [];
  htmlSeeds.push("<style>.a{display:flex;gap:4px;color:red}.a>b{font-weight:700}</style><div class=a><b>x</b><i>y</i><table><tr><td>1<td colspan=2>2</table><ul><li>a<li>b</ul><img src='data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\"/>'></div>");
  const jsonSeeds = ALL_CASES.filter((k) => typeof k.node === "object" && !k.images && JSON.stringify(k.node).length < 20000).filter((_, i) => i % 5 === 0).map((k) => JSON.stringify(k.node));
  const cssSeeds = ALL_CASES.filter((k) => k.opts && k.opts.css).map((k) => k.opts.css.join("\n")).concat([".a{color:red;width:calc(100% - 2px);background:linear-gradient(in oklch,red,blue)}@media (min-width:1px){.a:not(.b)>p::before{content:counter(x) \"a\"}}@keyframes k{from{opacity:0}to{opacity:1}}"]);
  const svgSeed = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><defs><linearGradient id='g'><stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue'/></linearGradient><clipPath id='c'><circle cx='50' cy='50' r='40'/></clipPath></defs><g clip-path='url(#c)' transform='rotate(10 50 50)'><rect width='100' height='100' fill='url(#g)'/><path d='M10 10 C 20 20, 40 20, 50 10 S 80 0 90 90 Z' stroke='black' fill='none' stroke-width='3' stroke-dasharray='4 2'/><text x='10' y='50' font-size='12'>svg</text><use href='#g'/></g></svg>";
  const asset = (f) => new Uint8Array(readFileSync(path.join(BENCH, "assets", f)));
  const imgSeeds = [];
  if (cls === "image") {
    const base = { type: "container", style: { display: "flex", width: 64, height: 48, backgroundImage: "linear-gradient(45deg,red,blue)" }, children: [{ type: "text", text: "im", style: { fontFamily: "Inter" } }] };
    imgSeeds.push(asset("icon.png"), asset("photo.jpg").subarray(0, 60000), wr.renderSync(base, { format: "png" }), wr.renderSync(base, { format: "jpeg" }), wr.renderSync(base, { format: "webp" }), wr.renderSync(base, { format: "ico" }));
    for (const format of ["gif", "apng", "webp"]) imgSeeds.push(wr.renderAnimationSync({ scenes: [{ node: base, durationMs: 200 }], width: 32, height: 24, fps: 10, format }));
  }
  let fontSeeds = [];
  if (cls === "font") {
    const { default: wawoff2 } = await import("wawoff2");
    const small = fontFile("Inter-Regular.ttf");
    fontSeeds = [small, fontFile("NotoSans-Regular.ttf"), new Uint8Array(await wawoff2.compress(Buffer.from(small)))];
    for (const extra of ["ref/takumi/assets/fonts/geist/geist-latin-wght-300-800.woff2", "ref/takumi/assets/fonts/twemoji/TwemojiMozilla-colr.woff2", "ref/takumi/assets/fonts/noto-sans/NotoColorEmoji.ttf", "src/font/testdata/Roboto-Regular.ttf"]) {
      const p = path.join(ROOT, extra);
      if (existsSync(p) && readFileSync(p).length < 3 << 20) fontSeeds.push(new Uint8Array(readFileSync(p)));
    }
  }
  const N = +args.n || 1000;
  const stats = { class: cls, seed: +args.seed || 1, cases: 0, identicalOk: 0, identicalError: 0, mismatches: 0, wasmTraps: 0, worstMs: 0 };
  const shown = [];
  const lastFile = path.join(BENCH, "out", `fuzz-diff-${cls}-last.txt`);
  for (let i = 0; i < N; i++) {
    let call, desc;
    if (cls === "html") { const s = mutateText((rnd(50) === 0 ? "<div>".repeat(rnd(700)) : "") + htmlSeeds[rnd(htmlSeeds.length)]); desc = s; call = (r) => r.renderSync(s, o); }
    else if (cls === "json") { const s = mutateText(jsonSeeds[rnd(jsonSeeds.length)]); desc = s; call = (r) => r.renderSync({ json: s }, o); }
    else if (cls === "css") { const s = mutateText(cssSeeds[rnd(cssSeeds.length)]); desc = s; call = (r) => r.renderSync("<div class='a b box'><p class=t>one <b>two</b></p><span class=a>x</span></div>", { ...o, css: [s], timeMs: 300 }); }
    else if (cls === "svg") { const s = mutateText(svgSeed); desc = s; call = (r) => r.renderSync({ type: "image", src: s, style: { width: 100, height: 100 } }, o); }
    else if (cls === "image") { const b = mutateBytes(imgSeeds[rnd(imgSeeds.length)], 256); desc = Buffer.from(b).toString("base64"); call = (r) => r.renderSync({ type: "image", src: b, style: { width: 100, height: 80 } }, { ...o, timeMs: 150 }); }
    else if (cls === "font") {
      const b = mutateBytes(fontSeeds[rnd(fontSeeds.length)], 4096); desc = Buffer.from(b.subarray(0, 64)).toString("hex");
      call = (r, B) => { const f = new B.Renderer(); try { const fams = JSON.stringify(f.registerFont({ name: "F", data: b })); return fams + sha(f.renderSync({ type: "text", text: "Hello fuzz 0123 Àé fi 😀 الع", style: { fontFamily: "F", fontSize: 28, fontWeight: 600 } }, o)) + sha(f.renderSvgSync({ type: "text", text: "Hg", style: { fontFamily: "F" } }, o)); } finally { f.free(); } };
    } else throw new Error("unknown class " + cls);
    writeFileSync(lastFile, `${cls} seed ${args.seed} iteration ${i}\n${desc}`);
    const t0 = performance.now();
    const w = outcome(() => call(wr, W));
    const n = outcome(() => call(nr, native));
    stats.worstMs = Math.max(stats.worstMs, +(performance.now() - t0).toFixed(0));
    stats.cases++;
    if (w.trap) { stats.wasmTraps++; resetWasm(); if (shown.length < 5) shown.push({ i, wasm: w, native: n, input: String(desc).slice(0, 300) }); continue; }
    if (same(w, n)) { if (w.ok) stats.identicalOk++; else stats.identicalError++; }
    else { stats.mismatches++; if (shown.length < 5) shown.push({ i, wasm: w, native: n, input: String(desc).slice(0, 600) }); }
  }
  console.log("RESULT " + JSON.stringify({ ...stats, shown }));
};
CASES["fuzz-diff"] = async () => {
  // differential mutation fuzzing: html, json node trees, css, svg images, encoded images, fonts
  const plan = [["html", 1500], ["json", 1500], ["css", 1500], ["svg", 1500], ["image", 2500], ["font", 400]];
  const rows = [];
  for (const [cls, n] of plan) for (const seed of [1, 2]) {
    const r = spawnSync(process.execPath, [SELF, "--case=fuzz-diff-run", `--class=${cls}`, `--seed=${seed}`, `--n=${n}`], { encoding: "utf8", timeout: 1800000, maxBuffer: 64 << 20 });
    const line = r.stdout.split("\n").find((l) => l.startsWith("RESULT "));
    const res = line ? JSON.parse(line.slice(7)) : null;
    const last = res ? "" : (() => { try { return readFileSync(path.join(BENCH, "out", `fuzz-diff-${cls}-last.txt`), "utf8").slice(0, 400); } catch { return ""; } })();
    check(r.status === 0 && res, `fuzz-diff ${cls} seed ${seed}: exit ${r.status}${r.signal ? " " + r.signal : ""} ${last} ${r.stderr.slice(-300)}`);
    if (res) {
      check(res.mismatches === 0, `fuzz-diff ${cls} seed ${seed}: ${res.mismatches} native/wasm mismatches, e.g. ${JSON.stringify(res.shown[0] ?? null).slice(0, 700)}`);
      rows.push({ class: cls, seed, cases: res.cases, identicalOk: res.identicalOk, identicalError: res.identicalError, mismatches: res.mismatches, wasmTraps: res.wasmTraps, worstMs: res.worstMs, exit: r.status, examples: res.shown.slice(0, 2) });
    } else rows.push({ class: cls, seed, exit: r.status, signal: r.signal, crashedOn: last });
  }
  notes["fuzz-diff"] = rows;
};

// ---- g. quick performance ---------------------------------------------------------------------------------
CASES.perf = async () => {
  const { wasm, native, ALL_CASES, renderOpts, withFonts } = await load();
  const pools = { wasm: new Map(), native: new Map() };
  const get = (which, B, fam) => { const key = fam ? fam.join(",") : "*"; if (!pools[which].has(key)) pools[which].set(key, withFonts(B, fam)); return pools[which].get(key); };
  const time = (r, k, format) => {
    const opts = renderOpts(k, format);
    for (let i = 0; i < 2; i++) r.renderSync(k.node, opts);
    const samples = [];
    const start = performance.now();
    while (samples.length < 5 || (performance.now() - start < 25 && samples.length < 200)) { const t = performance.now(); r.renderSync(k.node, opts); samples.push(performance.now() - t); }
    return median(samples);
  };
  const res = { raw: [], png: [] };
  for (const k of ALL_CASES) {
    for (const format of ["raw", "png"]) {
      // interleaved: wasm, native, wasm, native
      const w1 = time(get("wasm", wasm, k.fonts), k, format), n1 = time(get("native", native, k.fonts), k, format);
      const w2 = time(get("wasm", wasm, k.fonts), k, format), n2 = time(get("native", native, k.fonts), k, format);
      res[format].push({ id: k.id, wasm: Math.min(w1, w2), native: Math.min(n1, n2) });
    }
  }
  const geo = (a) => Math.exp(a.reduce((s, x) => s + Math.log(x), 0) / a.length);
  const summary = {};
  for (const format of ["raw", "png"]) {
    const rows = res[format];
    const ratios = rows.map((x) => x.wasm / x.native).sort((a, b) => a - b);
    summary[format] = { fixtures: rows.length, geomeanWasmMs: +geo(rows.map((x) => x.wasm)).toFixed(3), geomeanNativeMs: +geo(rows.map((x) => x.native)).toFixed(3), speedupGeomean: +geo(ratios).toFixed(2), speedupMin: +ratios[0].toFixed(2), speedupMedian: +median(ratios).toFixed(2), speedupMax: +ratios[ratios.length - 1].toFixed(2), slowerThanWasm: rows.filter((x) => x.native > x.wasm).map((x) => x.id).slice(0, 10) };
  }
  notes.perf = { optimize: args.label || "fast", ...summary };
  check(summary.raw.speedupGeomean > 1, `native is faster than wasm on the fixtures (raw geomean x${summary.raw.speedupGeomean})`);
};

CASES.cold = async () => {
  // process start -> first PNG on stdout, wall clock of the whole child (spawn + node boot + import + font + render + exit)
  const code = `import { readFileSync } from "node:fs"; const m = await import(${JSON.stringify(href("js", "node.mjs"))}); const r = new m.Renderer();` +
    `r.registerFont({ name: "Inter", data: readFileSync(${JSON.stringify(path.join(ROOT, "assets", "fonts", "Inter-Regular.ttf"))}) });` +
    `const png = r.renderSync({ type: "container", style: { display: "flex", width: 1200, height: 630, backgroundImage: "linear-gradient(135deg,#0f172a,#1d4ed8)", alignItems: "center", justifyContent: "center" }, children: [{ type: "text", text: "Cold start", style: { fontFamily: "Inter", fontSize: 96, color: "#fff" } }] }, { format: "png" });` +
    `process.stdout.write(m.backend + " " + png.length + " " + performance.now().toFixed(1));`;
  const once = (env, script) => {
    const t0 = performance.now();
    const r = spawnSync(process.execPath, ["--input-type=module", "-e", script], { encoding: "utf8", env: { ...process.env, BM_ENGINE_BACKEND: "", BM_ENGINE_NATIVE_PATH: "", ...env } });
    return { wall: performance.now() - t0, out: r.stdout, status: r.status };
  };
  const runs = 15;
  const sample = (env, script = code) => { once(env, script); const a = Array.from({ length: runs }, () => once(env, script)); return { wallMs: +median(a.map((x) => x.wall)).toFixed(1), inProcessMs: +median(a.map((x) => +(x.out.split(" ")[2] || 0))).toFixed(1), backend: a[0].out.split(" ")[0], ok: a.every((x) => x.status === 0) }; };
  const empty = sample({}, "process.stdout.write('none 0 ' + performance.now().toFixed(1))");
  const n = sample({ BM_ENGINE_BACKEND: "native" }), w = sample({ BM_ENGINE_BACKEND: "wasm" });
  notes.cold = { runs, what: "spawn -> import bm-engine -> registerFont(Inter) -> 1200x630 PNG -> exit; wall = parent's clock, inProcess = performance.now() at the end", emptyNode: empty, native: n, wasm: w, nativeOverNodeMs: +(n.wallMs - empty.wallMs).toFixed(1), wasmOverNodeMs: +(w.wallMs - empty.wallMs).toFixed(1) };
  check(n.ok && w.ok && n.backend === "native" && w.backend === "wasm", "cold-start children ran on the intended backends");
};

// ============================================================================================================
const NODE_FLAGS = { gc: ["--expose-gc"], free: ["--expose-gc"] };
const HIDDEN = new Set(["stack-probe", "fuzz-diff-run"]);
// (a worker-pool thread count other than libuv's default of 4 is up to the caller: UV_THREADPOOL_SIZE)

if (!isMainThread) {
  await workerMain();
} else if (args.list) {
  console.log(Object.keys(CASES).filter((c) => !HIDDEN.has(c)).join("\n"));
} else if (args.case) {
  const name = String(args.case);
  if (!CASES[name]) { console.error("unknown case " + name); process.exit(2); }
  await CASES[name]();
  if (!HIDDEN.has(name)) console.log("NOTES " + JSON.stringify(notes[name] ?? null));
  process.exit(failures ? 1 : 0);
} else {
  const names = args.only ? String(args.only).split(",") : Object.keys(CASES).filter((c) => !HIDDEN.has(c));
  const summary = {};
  let bad = 0;
  for (const name of names) {
    const t0 = performance.now();
    const r = spawnSync(process.execPath, [...(NODE_FLAGS[name] || []), SELF, `--case=${name}`, ...(args.verbose ? ["--verbose"] : []), ...(args.label ? [`--label=${args.label}`] : [])], { encoding: "utf8", timeout: 3600000, maxBuffer: 256 << 20 });
    const lines = r.stdout.split("\n");
    const notesLine = lines.find((l) => l.startsWith("NOTES "));
    const fails = lines.filter((l) => l.startsWith("  FAIL"));
    const ok = r.status === 0;
    if (!ok) bad++;
    summary[name] = { pass: ok, exit: r.status, signal: r.signal, seconds: +((performance.now() - t0) / 1000).toFixed(1), failures: fails.map((l) => l.slice(7)), notes: notesLine ? JSON.parse(notesLine.slice(6)) : null, stderr: ok ? undefined : r.stderr.slice(-600) };
    console.log(`${ok ? "PASS" : "FAIL"} ${name.padEnd(12)} ${summary[name].seconds} s${ok ? "" : `  (exit ${r.status}${r.signal ? " " + r.signal : ""})`}`);
    for (const f of fails) console.log("     " + f.trim());
    if (!ok && r.stderr.trim()) console.log("     " + r.stderr.trim().split("\n").slice(-3).join("\n     "));
    if (summary[name].notes && !args.quiet) console.log("     " + JSON.stringify(summary[name].notes).slice(0, 1500));
  }
  mkdirSync(path.join(BENCH, "out"), { recursive: true });
  const file = path.join(BENCH, "out", args.only ? `native-tests-${names.join("+").slice(0, 60)}.json` : "native-tests.json");
  writeFileSync(file, JSON.stringify({ date: new Date().toISOString(), node: process.version, platform: `${process.platform}-${process.arch}`, cpu: os.cpus()[0]?.model, cpus: os.cpus().length, cases: summary }, null, 1));
  console.log(`${names.length - bad}/${names.length} cases passed; details: ${path.relative(ROOT, file)}`);
  process.exit(bad ? 1 : 0);
}
