#!/usr/bin/env node
// PDF scaling regression check: the stress document of bench/pdf/corpus (per A4 page a heading, paragraphs, a
// 14-row collapsed table and an image, a page-counter footer) rendered at 100 and at 500 pages. Per page, time and
// file size must not grow with the page count:
//   * time per page at 500 pages / time per page at 100 pages < 1.5
//   * bytes per page at 500 pages within 10 % of bytes per page at 100 pages
// and the engine memory (Renderer.memoryBytes(): wasm linear memory / native live allocation) is reported.
//
//   node scripts/pdf-scaling.mjs                  wasm, and native when the addon is built (native/dist)
//   node scripts/pdf-scaling.mjs --takumi         also takumi-pdf 0.20.0 (bench/pdf/node_modules) for file size and memory
//   node scripts/pdf-scaling.mjs --backend=wasm   one backend only (wasm | native)
//
// Each backend runs in a child process of its own (a fresh wasm memory / addon heap), timed after one 10-page
// warm-up render. Exit status 1 when a check fails.
import { spawnSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const opt = (name) => { const a = args.find((x) => x.startsWith(`--${name}=`)); return a ? a.slice(name.length + 3) : null; };
const SIZES = [100, 500];

if (opt("child")) {
  // ---- child: one engine, prints one JSON line
  const engine = opt("child");
  const { stressHtml, stressCorpus, INTER } = await import(pathToFileURL(path.join(ROOT, "bench", "pdf", "corpus", "docs.mjs")).href);
  const fonts = INTER.map((f) => ({ name: f.name, data: new Uint8Array(readFileSync(f.path)), weight: f.weight, style: f.style }));
  let r, memory, backend;
  if (engine === "takumi-pdf") {
    const { createEngine } = await import(pathToFileURL(path.join(ROOT, "bench", "pdf", "engines.mjs")).href);
    const e = await createEngine("takumi-pdf");
    for (const f of fonts) await e.registerFont(f);
    r = { render: (s, o) => e.render(s, o) };
    memory = () => e.memoryBytes();
    backend = "wasm";
  } else {
    const mod = await import(pathToFileURL(path.join(ROOT, "js", "node-pdf.mjs")).href);
    const pr = new mod.PdfRenderer();
    for (const f of fonts) pr.registerFont(f);
    r = pr;
    memory = () => mod.Renderer.memoryBytes();
    backend = mod.backend;
  }
  const options = stressCorpus([1])[0].options;
  const out = { engine, backend, runs: [] };
  await r.render(stressHtml(10), options()); // warm-up
  for (const n of SIZES) {
    const src = stressHtml(n);
    const t0 = performance.now();
    const bytes = await r.render(src, options());
    const ms = performance.now() - t0;
    const pages = (Buffer.from(bytes).toString("latin1").match(/\/Type\s*\/Page\b(?!s)/g) || []).length;
    out.runs.push({ pages: n, pagesOut: pages, ms, bytes: bytes.length, memory: memory(), rss: process.memoryUsage().rss });
  }
  console.log(JSON.stringify(out));
  process.exit(0);
}

// ---- parent
const want = opt("backend");
const engines = [];
if (!want || want === "wasm") engines.push(["bm wasm", "wasm"]);
if (!want || want === "native") {
  const hasAddon = existsSync(path.join(ROOT, "native", "dist")) && spawnSync(process.execPath, ["-e", "import('./js/native.mjs').then(m=>process.exit(m.nativePdfBinding()?0:1)).catch(()=>process.exit(1))"], { cwd: ROOT }).status === 0;
  if (hasAddon) engines.push(["bm native", "native"]);
  else console.log("native addon not built for this checkout (node scripts/build-native.mjs): native skipped");
}
if (args.includes("--takumi")) engines.push(["takumi-pdf 0.20.0", "takumi-pdf"]);

const MiB = (b) => (b == null ? "-" : (b / 2 ** 20).toFixed(1) + " MiB");
let failed = 0;
const results = [];
for (const [label, engine] of engines) {
  const env = { ...process.env };
  if (engine === "wasm" || engine === "native") env.BM_RENDER_BACKEND = engine;
  const p = spawnSync(process.execPath, ["--max-old-space-size=8192", fileURLToPath(import.meta.url), `--child=${engine}`], { cwd: ROOT, env, encoding: "utf8", maxBuffer: 1 << 26 });
  const line = (p.stdout || "").trim().split("\n").pop();
  let res;
  try { res = JSON.parse(line); } catch { console.log(`FAIL  ${label}: ${(p.stderr || p.stdout || "").trim().slice(-600)}`); failed++; continue; }
  results.push([label, res]);
  const [a, b] = res.runs;
  for (const x of res.runs) {
    console.log(`${label.padEnd(18)} ${String(x.pages).padStart(4)} pages: ${(x.ms / 1000).toFixed(2)} s (${(x.ms / x.pages).toFixed(1)} ms/page), ${(x.bytes / 2 ** 20).toFixed(2)} MiB (${Math.round(x.bytes / x.pages)} B/page), engine memory ${MiB(x.memory)}, rss ${MiB(x.rss)}`);
    if (x.pagesOut !== x.pages) { console.log(`FAIL  ${label}: ${x.pagesOut} pages written for ${x.pages}`); failed++; }
  }
  if (engine === "takumi-pdf") continue;
  const timeRatio = (b.ms / b.pages) / (a.ms / a.pages);
  const byteRatio = (b.bytes / b.pages) / (a.bytes / a.pages);
  const ok1 = timeRatio < 1.5;
  const ok2 = Math.abs(byteRatio - 1) <= 0.1;
  console.log(`${ok1 ? "PASS" : "FAIL"}  ${label}: time per page 500 / 100 = ${timeRatio.toFixed(2)} (< 1.5)`);
  console.log(`${ok2 ? "PASS" : "FAIL"}  ${label}: bytes per page 500 / 100 = ${byteRatio.toFixed(3)} (within 10 %)`);
  if (!ok1) failed++;
  if (!ok2) failed++;
}
const tk = results.find(([, r]) => r.engine === "takumi-pdf");
if (tk) for (const [label, r] of results) {
  if (r.engine === "takumi-pdf") continue;
  for (let k = 0; k < SIZES.length; k++) {
    const x = r.runs[k], y = tk[1].runs[k];
    console.log(`${label} vs takumi-pdf at ${x.pages} pages: file ${(x.bytes / y.bytes).toFixed(2)}x (${x.bytes} / ${y.bytes} B), engine memory ${MiB(x.memory)} / ${MiB(y.memory)}, time ${(x.ms / y.ms).toFixed(2)}x`);
  }
}
process.exit(failed ? 1 : 0);
