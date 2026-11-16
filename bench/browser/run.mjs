// Real-browser test driver.  node bench/browser/run.mjs [--quick] [--filter=<regex>] [--iters=N] [--no-takumi] [--browser=<path>]
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import puppeteer from "puppeteer-core";
import { startServer, REPO_ROOT } from "./server.mjs";
import { ALL_CASES } from "../fixtures/index.mjs";
import { FONTS } from "../lib/fonts.mjs";

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const QUICK_IDS = ["colors-solid-bg", "flex-wrap-gap", "borders-with-radius", "lingrad-angles", "radial-shapes", "shadow-spread-multi",
  "transform-combined-origin", "text-vietnamese", "text-paragraph-wrap", "img-photo-bg", "grid-repeat-gap", "card-flat-ui"];
const TIMING_IDS = ["card-flat-ui", "card-og", "lingrad-angles", "shadow-spread-multi", "text-paragraph-wrap", "text-vietnamese", "img-photo-bg", "grid-repeat-gap"];
const ITERS = +(args.iters || (args.quick ? 10 : 25));
const OUT = path.join(REPO_ROOT, "bench", "out");
mkdirSync(OUT, { recursive: true });
const log = (...a) => console.log(...a);

let cases;
if (args.quick) cases = QUICK_IDS.map((id) => ALL_CASES.find((k) => k.id === id)).filter(Boolean);
else cases = ALL_CASES.filter((k) => k.feature !== "known-gaps");
if (args.filter && args.filter !== true) { const re = new RegExp(args.filter, "i"); cases = cases.filter((k) => re.test(k.id) || re.test(k.feature)); }
const timingCases = TIMING_IDS.map((id) => ALL_CASES.find((k) => k.id === id)).filter(Boolean);

// ---- locate browser ----
const candidates = [args.browser, process.env.BROWSER_PATH,
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe"].filter((x) => x && x !== true);
const exe = candidates.find((p) => existsSync(p));
if (!exe) { console.error("No Chromium-based browser found. Tried:\n  " + candidates.join("\n  ")); process.exit(2); }

// ---- Node reference (same wasm file the browser downloads) ----
const wasmPath = path.join(REPO_ROOT, "js", "bm_render.wasm");
const wasmBytes = readFileSync(wasmPath);
const wasmSha = createHash("sha256").update(wasmBytes).digest("hex").slice(0, 16);
const bm = await import(pathToFileURL(path.join(REPO_ROOT, "js", "index.mjs")).href);
bm.initSync(wasmBytes);
const nodeR = new bm.Renderer();
for (const f of FONTS) nodeR.registerFont({ name: f.name, data: new Uint8Array(readFileSync(f.path)), weight: f.weight, style: f.style });
const nopts = (k, format) => { const o = { width: k.width, height: k.height, format, devicePixelRatio: 1 }; if (k.images) o.images = k.images; if (format === "jpeg") o.quality = 85; return o; };
const median = (a) => { const s = [...a].sort((x, y) => x - y); return s[s.length >> 1]; };
const fontArgs = FONTS.map(({ name, file, weight, style }) => ({ name, file, weight, style }));
const payloadOf = (k) => ({ id: k.id, width: k.width, height: k.height, node: k.node,
  images: (k.images || []).map((i) => ({ src: i.src, b64: Buffer.from(i.data).toString("base64") })) });

const failures = [];
const fail = (m) => { failures.push(m); console.error("FAIL: " + m); };

const server = await startServer();
let browser;
const consoleErrors = [];
try {
  browser = await puppeteer.launch({ executablePath: exe, headless: true, args: ["--no-first-run", "--no-default-browser-check", "--disable-extensions"] });
  const version = await browser.version();
  log(`browser: ${version} (${exe})\nserver: ${server.url}  wasm sha256[:16]=${wasmSha}  cases=${cases.length}`);

  const watch = (page, tag) => {
    page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(`[${tag}] console.error: ${m.text()}`); });
    page.on("pageerror", (e) => consoleErrors.push(`[${tag}] pageerror: ${e.message}`));
    page.on("requestfailed", (r) => consoleErrors.push(`[${tag}] requestfailed: ${r.url()} ${r.failure()?.errorText}`));
    page.on("response", (r) => { if (r.status() >= 400) consoleErrors.push(`[${tag}] HTTP ${r.status()}: ${r.url()}`); });
  };

  const page = await browser.newPage();
  watch(page, "page");
  await page.goto(server.url + "/bench/browser/page.html", { waitUntil: "load" });
  await page.waitForFunction("window.bmReady === true", { timeout: 30000 });
  const initInfo = await page.evaluate((fonts) => window.bmInit(fonts), fontArgs);
  log("init:", JSON.stringify(initInfo));
  if (initInfo.wasmContentType !== "application/wasm") fail("wasm content-type " + initInfo.wasmContentType);

  const loaded = new Set();
  const load = async (k) => {
    if (loaded.has(k.id)) return;
    loaded.add(k.id);
    await page.evaluate((p) => window.bmLoadCase(p), payloadOf(k));
  };

  const rows = [];
  for (const k of cases) {
    const row = { id: k.id, feature: k.feature, width: k.width, height: k.height };
    try {
      await load(k);
      const nodeRaw = nodeR.renderSync(k.node, nopts(k, "raw"));
      const meta = await page.evaluate((id) => window.bmRender(id, "raw"), k.id);
      const parts = [];
      const CH = 6 * 1024 * 1024; // multiple of 3 so base64 chunks concatenate
      for (let off = 0; off < meta.bytes; off += CH) parts.push(Buffer.from(await page.evaluate((o, l) => window.bmRawChunk(o, l), off, Math.min(CH, meta.bytes - off)), "base64"));
      const brRaw = Buffer.concat(parts);
      row.rawBytes = brRaw.length;
      if (brRaw.length !== nodeRaw.length) { row.identical = false; row.diffPixels = -1; }
      else {
        let diffPx = 0, maxD = 0;
        for (let i = 0; i < brRaw.length; i += 4) {
          if (brRaw[i] !== nodeRaw[i] || brRaw[i + 1] !== nodeRaw[i + 1] || brRaw[i + 2] !== nodeRaw[i + 2] || brRaw[i + 3] !== nodeRaw[i + 3]) {
            diffPx++;
            for (let c = 0; c < 4; c++) maxD = Math.max(maxD, Math.abs(brRaw[i + c] - nodeRaw[i + c]));
          }
        }
        row.identical = diffPx === 0; row.diffPixels = diffPx; row.maxChannelDiff = maxD;
      }
      if (!row.identical) fail(`${k.id}: browser raw differs from node (${row.diffPixels} px, bytes ${brRaw.length} vs ${nodeRaw.length})`);
      for (const fmt of ["png", "webp", "jpeg"]) {
        const r = await page.evaluate((id, f) => window.bmFormatCheck(id, f), k.id, fmt);
        let ok = r.dimsOk;
        if (ok && fmt !== "jpeg") ok = r.maxDiff <= 1 && r.alphaMaxDiff <= 1;
        if (ok && fmt === "jpeg") ok = r.meanAbsDiff < 3;
        r.ok = ok;
        row[fmt] = r;
        if (!ok) fail(`${k.id}: ${fmt} check failed ${JSON.stringify(r)}`);
      }
    } catch (e) { row.error = String(e?.message ?? e).split("\n")[0]; fail(`${k.id}: ${row.error}`); }
    rows.push(row);
    const good = !row.error && row.identical && row.png?.ok && row.webp?.ok && row.jpeg?.ok;
    log(`${good ? "ok  " : "BAD "} ${k.id}` + (row.png ? `  png ${row.png.ok ? "ok" : "BAD"} webp ${row.webp.ok ? "ok" : "BAD"} jpeg ${row.jpeg.ok ? "ok" : "BAD"}(mad ${row.jpeg.meanAbsDiff?.toFixed(2)})` : ""));
  }

  // ---- timing ----
  const timing = [];
  for (const k of timingCases) {
    try {
      await load(k);
      const br = await page.evaluate((id, n) => window.bmBench(id, n), k.id, ITERS);
      const nres = {};
      for (const f of ["raw", "png"]) {
        for (let i = 0; i < 2; i++) nodeR.renderSync(k.node, nopts(k, f));
        const t = [];
        for (let i = 0; i < ITERS; i++) { const s = performance.now(); nodeR.renderSync(k.node, nopts(k, f)); t.push(performance.now() - s); }
        nres[f] = { medianMs: median(t), iters: ITERS };
      }
      timing.push({ id: k.id, browser: br, node: nres });
      log(`time ${k.id}: raw br ${br.raw.medianMs.toFixed(1)} / node ${nres.raw.medianMs.toFixed(1)} ms; png br ${br.png.medianMs.toFixed(1)} / node ${nres.png.medianMs.toFixed(1)} ms`);
    } catch (e) { fail(`timing ${k.id}: ${e.message}`); }
  }
  const memory = await page.evaluate(() => window.bmMemory());
  log("memory:", JSON.stringify(memory));

  // ---- takumi in the browser (optional) ----
  let takumi = { status: "skipped" };
  if (!args["no-takumi"]) {
    const tpage = await browser.newPage();
    const tErrors = [];
    tpage.on("console", (m) => { if (m.type() === "error") tErrors.push(m.text()); });
    tpage.on("pageerror", (e) => tErrors.push(e.message));
    try {
      await tpage.goto(server.url + "/bench/browser/page.html", { waitUntil: "load" });
      await tpage.waitForFunction("window.bmReady === true", { timeout: 30000 });
      await tpage.evaluate((fonts) => window.bmInit(fonts), fontArgs);
      const ti = await tpage.evaluate((fonts) => window.bmTakumiInit(fonts), fontArgs);
      takumi = { status: "ok", init: ti, timing: [] };
      const tIters = Math.max(5, Math.min(ITERS, 15));
      for (const k of timingCases) {
        await tpage.evaluate((p) => window.bmLoadCase(p), payloadOf(k));
        const r = await tpage.evaluate((id, n) => window.bmTakumiBench(id, n), k.id, tIters);
        takumi.timing.push({ id: k.id, ...r });
        log(`takumi(browser) ${k.id}: raw ${r.raw.medianMs.toFixed(1)} ms, png ${r.png.medianMs.toFixed(1)} ms`);
      }
      takumi.iters = tIters;
      takumi.memory = await tpage.evaluate(() => window.bmMemory());
    } catch (e) {
      takumi = { status: "failed", reason: String(e?.message ?? e).split("\n")[0], pageErrors: tErrors.slice(0, 5) };
      log("takumi in browser failed (informational): " + takumi.reason, tErrors.slice(0, 3));
    }
    await tpage.close();
  }

  // ---- examples/browser.html ----
  const ex = await browser.newPage();
  watch(ex, "example");
  let example = {};
  try {
    await ex.goto(server.url + "/examples/browser.html", { waitUntil: "load" });
    await ex.waitForFunction(() => { const i = document.getElementById("info"); const im = document.getElementById("out"); return i && !/rendering/.test(i.textContent) && im && im.complete && im.naturalWidth > 0; }, { timeout: 30000 });
    example = await ex.evaluate(() => ({ info: document.getElementById("info").textContent, w: document.getElementById("out").naturalWidth, h: document.getElementById("out").naturalHeight }));
    if (example.w !== 1200 || example.h !== 630) fail("examples/browser.html image is " + example.w + "x" + example.h);
    log("example:", JSON.stringify(example));
  } catch (e) { example.error = e.message.split("\n")[0]; fail("examples/browser.html: " + example.error); }

  for (const e of consoleErrors) fail(e);

  // ---- report ----
  const sum = {
    cases: rows.length, identical: rows.filter((r) => r.identical).length,
    pngOk: rows.filter((r) => r.png?.ok).length, webpOk: rows.filter((r) => r.webp?.ok).length, jpegOk: rows.filter((r) => r.jpeg?.ok).length,
    consoleErrors: consoleErrors.length, failures: failures.length,
  };
  const results = { browser: { version, executable: exe }, date: new Date().toISOString(), wasmSha256_16: wasmSha, args: process.argv.slice(2), init: initInfo, memory, summary: sum, rows, timing, takumi, example, consoleErrors, failures };
  writeFileSync(path.join(OUT, "browser-results.json"), JSON.stringify(results, null, 1));
  const f1 = (x) => (x == null ? "-" : x.toFixed(x < 10 ? 2 : 1));
  const yn = (b) => (b ? "yes" : "NO");
  const md = [];
  md.push(`# Browser test`, ``, `- Browser: **${version}** (headless, puppeteer-core)`,
    `- wasm: js/bm_render.wasm (${initInfo.wasmBytes} bytes, sha256 ${wasmSha}), served as \`${initInfo.wasmContentType}\`; compile+instantiate (streaming) **${f1(initInfo.compileInstantiateMs)} ms**; registering ${initInfo.fonts} fonts ${f1(initInfo.fontRegisterMs)} ms`,
    `- Memory after run: wasm linear memory ${(memory.wasmMemoryBytes / 1048576).toFixed(1)} MiB; JS heap used ${memory.jsHeapUsed ? (memory.jsHeapUsed / 1048576).toFixed(1) + " MiB" : "n/a"}`,
    `- Result: **${failures.length ? "FAIL" : "PASS"}** - ${sum.identical}/${sum.cases} raw renders byte-identical to Node; png ${sum.pngOk}/${sum.cases}, webp ${sum.webpOk}/${sum.cases}, jpeg ${sum.jpegOk}/${sum.cases} decode OK; console errors ${sum.consoleErrors}`,
    `- examples/browser.html: ${example.error ? "ERROR " + example.error : `shows ${example.w}x${example.h} image (${example.info})`}`, ``,
    `Method: PNG/WebP are decoded in the browser with \`createImageBitmap\`, drawn to an OffscreenCanvas (no colour conversion) and compared with the raw render: RGB must be within +-1 for fully opaque pixels; translucent pixels are excluded from the RGB comparison (canvas premultiplies, which loses precision) but their alpha must still be within +-1. JPEG: dimensions match and mean abs RGB diff < 3 over opaque pixels.`, ``,
    `## Cases`, ``, `| case | identical to Node | diff px | png | webp | jpeg (mean abs diff) |`, `|---|---|---|---|---|---|`);
  for (const r of rows) md.push(`| ${r.id} | ${r.error ? "ERR " + r.error : yn(r.identical)} | ${r.diffPixels ?? "-"} | ${r.png ? yn(r.png.ok) : "-"} | ${r.webp ? yn(r.webp.ok) : "-"} | ${r.jpeg ? yn(r.jpeg.ok) + " (" + r.jpeg.meanAbsDiff.toFixed(2) + ")" : "-"} |`);
  md.push(``, `## Timing (median of ${ITERS}, renderSync, ms; lower is better)`, ``);
  const tk = takumi.status === "ok" ? new Map(takumi.timing.map((t) => [t.id, t])) : null;
  md.push(`| case | bm raw browser | bm raw node | bm png browser | bm png node |${tk ? " takumi raw browser | takumi png browser |" : ""}`, `|---|---|---|---|---|${tk ? "---|---|" : ""}`);
  for (const t of timing) md.push(`| ${t.id} | ${f1(t.browser.raw.medianMs)} | ${f1(t.node.raw.medianMs)} | ${f1(t.browser.png.medianMs)} | ${f1(t.node.png.medianMs)} |${tk ? ` ${f1(tk.get(t.id)?.raw.medianMs)} | ${f1(tk.get(t.id)?.png.medianMs)} |` : ""}`);
  md.push(``, `## takumi (@takumi-rs/wasm) in the browser`, ``);
  if (takumi.status === "ok") md.push(`Works through an import map (\`@takumi-rs/helpers\` -> /bench/node_modules/...). Import + compile + instantiate ${f1(takumi.init.compileInstantiateMs)} ms; takumi wasm memory ${takumi.init.wasmMemoryBytes ? (takumi.init.wasmMemoryBytes / 1048576).toFixed(1) + " MiB" : "n/a"}. Timings use \`await renderer.render\`, ${takumi.iters} iterations.`);
  else md.push(`${takumi.status}${takumi.reason ? ": " + takumi.reason : ""}`);
  if (failures.length) md.push(``, `## Failures`, ``, ...failures.map((f) => "- " + f));
  writeFileSync(path.join(OUT, "BROWSER.md"), md.join("\n") + "\n");
  log(`\n${failures.length ? "FAIL" : "PASS"}: identical ${sum.identical}/${sum.cases}, png ${sum.pngOk}, webp ${sum.webpOk}, jpeg ${sum.jpegOk}, console errors ${sum.consoleErrors}`);
} catch (e) {
  console.error("driver error:", e);
  failures.push("driver error: " + e.message);
} finally {
  try { await browser?.close(); } catch {}
  await server.close();
}
process.exit(failures.length ? 1 : 0);
