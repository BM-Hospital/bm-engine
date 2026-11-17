// Playground end-to-end test (headless Edge via puppeteer-core).
//   node bench/browser/playground-test.mjs [--browser=<exe>] [--skip-docs-build]
// 1. Serves the repo root (dev layout, docs/playground-app/), exercises every profile (core / standard / full).
// 2. Builds and smoke-tests the self-contained build (docs/playground-app/dist).
// 3. Builds the VitePress docs site (npm run docs:build equivalent; --skip-docs-build reuses docs/.vitepress/dist) and
//    checks the /image/playground and /vi/image/playground pages: the embedded app starts on every profile and renders the OG card.
// PDF mode (?mode=pdf): on the dev server (full pass: lazy loading, every PDF template, viewer and pdf.js previews,
// download, open in a tab, "Copy code" run in Node.js, engine errors, share link, Image <-> PDF, dark, phone), on the
// self-contained build (reduced pass) and embedded at /pdf/playground and /vi/pdf/playground of the built docs site.
// Screenshot: bench/out/docs-site/playground-pdf-standalone.png. Servers listen on ephemeral ports.
import { existsSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync, mkdtempSync, symlinkSync, unlinkSync } from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";
import { startServer } from "../../docs/playground-app/serve.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const PG = path.join(ROOT, "docs", "playground-app");
const SITE = path.join(ROOT, "docs", ".vitepress", "dist");
const SHOTS = path.join(PG, "screenshots");
const OUT = path.join(ROOT, "bench", "out");
const DOCS_SHOTS = path.join(OUT, "docs-site");
mkdirSync(SHOTS, { recursive: true }); mkdirSync(OUT, { recursive: true }); mkdirSync(DOCS_SHOTS, { recursive: true });
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const candidates = [args.browser, process.env.BROWSER_PATH,
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe"].filter((x) => x && x !== true);
const exe = candidates.find((p) => existsSync(p));
if (!exe) { console.error("No Chromium-based browser found:\n  " + candidates.join("\n  ")); process.exit(2); }

const failures = [];
const log = [];
const say = (s) => { console.log(s); log.push(s); };
const fail = (m) => { failures.push(m); say("FAIL: " + m); };
const check = (cond, m) => { if (!cond) fail(m); return !!cond; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = {}; // profile -> { templates: {id: status}, ... }

// ---------------------------------------------------------------------------------------------- helpers
function watch(page, tag, sink) {
  page.on("console", (m) => { if (m.type() === "error") sink.push(`[${tag}] console.error: ${m.text()}`); });
  page.on("pageerror", (e) => sink.push(`[${tag}] pageerror: ${e.message}`));
  page.on("requestfailed", (r) => sink.push(`[${tag}] requestfailed: ${r.url()} ${r.failure()?.errorText}`));
  page.on("response", (r) => { if (r.status() >= 400) sink.push(`[${tag}] HTTP ${r.status()}: ${r.url()}`); });
}
const renders = (page) => page.evaluate(() => +document.body.dataset.renders || 0);
async function settle(page, before) {
  await page.waitForFunction((b) => (+document.body.dataset.renders || 0) > b, { timeout: 30000 }, before);
  let prev = -1;
  for (let i = 0; i < 20; i++) { const n = await renders(page); if (n === prev) break; prev = n; await sleep(120); }
}
/** Clicks Render and waits until a render finished. */
async function doRender(page) {
  const b = await renders(page);
  await page.click("#renderBtn");
  await settle(page, b);
}
async function snapshot(page) {
  return page.evaluate(() => {
    const d = document.body.dataset, img = document.getElementById("outImg"), cv = document.getElementById("outCanvas");
    const frameVisible = !document.getElementById("frame").hidden;
    return {
      status: d.status, format: d.outFormat, w: +d.outW, h: +d.outH, bytes: +d.outBytes,
      error: document.getElementById("errorPanel").hidden ? "" : document.getElementById("errorText").textContent,
      hintButtons: [...document.querySelectorAll("#errorHint button")].map((b) => b.textContent),
      imgOk: !img.hidden && img.complete && img.naturalWidth > 0, imgW: img.naturalWidth, imgH: img.naturalHeight, canvasW: cv.hidden ? 0 : cv.width, canvasH: cv.hidden ? 0 : cv.height, frameVisible,
      time: document.getElementById("stTime").textContent, mem: document.getElementById("stMem").textContent,
    };
  });
}
async function openPage(ctx, base, query, sink, tag, hash = "") {
  const page = await ctx.newPage();
  await page.setViewport({ width: 1440, height: 900 });
  watch(page, tag, sink);
  await page.goto(`${base}${query}${hash}`, { waitUntil: "load" });
  await page.waitForFunction("document.body.dataset.ready === '1' || document.body.dataset.ready === 'error'", { timeout: 60000 });
  const ready = await page.evaluate(() => document.body.dataset.ready);
  if (ready !== "1") throw new Error("playground failed to start: " + await page.evaluate(() => document.getElementById("errorText").textContent));
  await settle(page, 0);
  return page;
}
const setSource = (page, kind, text, extra = {}) => page.evaluate((kind, text, extra) => {
  const t = document.querySelector(`#tabs button[data-kind=${kind}]`); t.click();
  const s = document.getElementById("src"); s.value = text; s.dispatchEvent(new Event("input", { bubbles: true }));
  for (const [id, v] of Object.entries(extra)) { const el = document.getElementById(id); el.value = v; el.dispatchEvent(new Event("input", { bubbles: true })); el.dispatchEvent(new Event("change", { bubbles: true })); }
}, kind, text, extra);
const setFormat = async (page, f) => { await page.select("#format", f); };

// ---------------------------------------------------------------------------------------------- per-profile suite
async function suite(ctxFactory, base, profile, { dist = false } = {}) {
  const tag = `${dist ? "dist-" : ""}${profile}`;
  const sink = [];
  const ctx = await ctxFactory();
  const R = { templates: {}, extra: {} };
  results[tag] = R;
  const dl = mkdtempSync(path.join(os.tmpdir(), "bm-pg-dl-"));
  let page;
  try {
    const imgReqs = []; // Image mode must not request anything of PDF mode
    page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, tag, sink);
    page.on("request", (r) => imgReqs.push(r.url()));
    await page.goto(`${base}?profile=${profile}`, { waitUntil: "load" });
    await page.waitForFunction("document.body.dataset.ready === '1' || document.body.dataset.ready === 'error'", { timeout: 60000 });
    if (await page.evaluate(() => document.body.dataset.ready) !== "1") throw new Error("playground failed to start: " + await page.evaluate(() => document.getElementById("errorText").textContent));
    await settle(page, 0);
    { const hits = imgReqs.filter((u) => PDF_LAZY.test(u)); R.extra["no PDF engine / pdf.js requested"] = hits.length ? "FAIL" : "pass"; check(!hits.length, `${tag}: Image mode requested ${hits.join(", ")}`); }
    const cdp = await page.createCDPSession();
    await cdp.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: dl, eventsEnabled: true }).catch(() => cdp.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: dl }));
    const info = await page.evaluate(() => ({ profile: document.body.dataset.profile, bin: document.getElementById("binInfo").textContent, chips: document.querySelectorAll("#featChips .chip").length, on: document.querySelectorAll("#featChips .chip:not(.off)").length, features: window.pg.engine.features, tplOptions: document.querySelectorAll("#template option").length }));
    R.info = info;
    say(`\n== ${tag}: ${info.bin}; features on: ${info.on}/${info.chips}`);
    check(info.profile === profile, `${tag}: profile ${info.profile}`);
    check(info.chips >= 17 && /\.wasm - /.test(info.bin), `${tag}: binary size / feature chips not shown (${info.bin}, ${info.chips})`);
    check(info.tplOptions === 12, `${tag}: template options ${info.tplOptions}`);
    const F = info.features;
    const templates = await page.evaluate(() => window.pg.templates.map((t) => ({ id: t.id, needs: t.needs, w: t.width, h: t.height, kind: t.kind })));

    // ---- every template through the UI select + Render button
    const only = dist ? templates.filter((t) => t.id === "og-card" || (t.id === "html-article" && F.html)) : templates;
    for (const t of only) {
      const missing = t.needs.filter((n) => !F[n]);
      const b = await renders(page);
      await page.select("#template", t.id);
      await sleep(60);
      await doRender(page);
      let s = await snapshot(page);
      if (!missing.length) {
        const ok = s.status === "ok" && s.imgOk && s.imgW === t.w && s.imgH === t.h && !s.error;
        R.templates[t.id] = ok ? "pass" : "FAIL";
        if (!ok) fail(`${tag}: template ${t.id}: ${JSON.stringify(s)}`);
        else say(`  ok   ${t.id} ${s.imgW}x${s.imgH} ${s.bytes} B  ${s.time}`);
      } else {
        const expectError = missing.some((m) => ["html", "css"].includes(m));
        if (expectError) {
          const ok = s.status === "error" && s.error.length > 0 && !s.error.includes("undefined");
          R.templates[t.id] = ok ? `pass (friendly error: ${missing.join(",")} missing)` : "FAIL";
          if (!ok) fail(`${tag}: template ${t.id} should show an engine error: ${JSON.stringify(s)}`); else say(`  ok   ${t.id} -> error panel: ${s.error.split("\n")[0]}`);
        } else {
          R.templates[t.id] = `rendered=${s.status === "ok"} (lacks ${missing.join(",")}; ${s.status === "ok" ? "degraded" : "error: " + s.error.split("\n")[0]})`;
          say(`  info ${t.id} lacks ${missing.join(",")} -> ${s.status}`);
        }
      }
      void b;
    }
    if (dist) { check(sink.length === 0, `${tag}: browser errors:\n  ` + sink.join("\n  ")); await ctx.close(); return; }

    // ---- formats on the OG card
    await page.select("#template", "og-card"); await sleep(60); await doRender(page);
    for (const f of ["jpeg", "webp", "png"]) {
      await setFormat(page, f); await sleep(60); await doRender(page);
      const s = await snapshot(page);
      const ok = s.status === "ok" && s.format === f && s.imgOk && s.imgW === 1200 && s.imgH === 630;
      R.extra["format " + f] = ok ? "pass" : "FAIL"; if (!ok) fail(`${tag}: format ${f}: ${JSON.stringify(s)}`);
    }
    await setFormat(page, "raw"); await sleep(60); await doRender(page);
    { const s = await snapshot(page); const ok = s.status === "ok" && s.canvasW === 1200 && s.canvasH === 630; R.extra["format raw"] = ok ? "pass" : "FAIL"; if (!ok) fail(`${tag}: raw: ${JSON.stringify(s)}`); }
    await setFormat(page, "svg"); await sleep(60); await doRender(page);
    { const s = await snapshot(page);
      if (F.renderSvg) { const ok = s.status === "ok" && s.format === "svg" && s.imgOk && s.bytes > 100; R.extra["format svg"] = ok ? "pass" : "FAIL"; if (!ok) fail(`${tag}: svg: ${JSON.stringify(s)}`); }
      else { const ok = s.status === "error" && /renderSvg|svg/i.test(s.error); R.extra["format svg"] = ok ? "pass (friendly error)" : "FAIL"; if (!ok) fail(`${tag}: svg should error on this profile: ${JSON.stringify(s)}`); } }
    // animated export
    await page.select("#template", "animation"); await sleep(60);
    for (const f of ["anim-webp", "anim-gif", "anim-apng"]) {
      await setFormat(page, f); await sleep(60); await doRender(page);
      const s = await snapshot(page);
      if (F.animation && F.css) { const ok = s.status === "ok" && s.imgOk && s.imgW === 600 && s.imgH === 300; R.extra["format " + f] = ok ? "pass" : "FAIL"; if (!ok) fail(`${tag}: ${f}: ${JSON.stringify(s)}`); }
      else { const ok = s.status === "error" && s.error.length > 0; R.extra["format " + f] = ok ? "pass (friendly error)" : "FAIL"; if (!ok) fail(`${tag}: ${f} should error: ${JSON.stringify(s)}`); }
    }
    await setFormat(page, "png");

    // ---- measure overlay
    await page.select("#template", "og-card"); await sleep(60); await doRender(page);
    await page.click("#measureToggle"); await sleep(100);
    await settle(page, (await renders(page)) - 1).catch(() => {}); await sleep(200);
    { const n = await page.evaluate(() => +document.body.dataset.measureBoxes || 0); R.extra["measure overlay"] = n > 3 ? `pass (${n} boxes)` : "FAIL"; check(n > 3, `${tag}: measure overlay boxes ${n}`); }
    await page.click("#measureToggle");

    // ---- font upload through the hidden input + render with it
    const robotoPath = path.join(ROOT, "assets", "fonts", "Roboto-Regular.ttf");
    const fi = await page.$("#fontInput");
    await fi.uploadFile(robotoPath);
    await page.waitForFunction(() => document.querySelector('#fontList li[data-family="Roboto"]'), { timeout: 15000 }).catch(() => {});
    const hasRoboto = await page.evaluate(() => !!document.querySelector('#fontList li[data-family="Roboto"]'));
    check(hasRoboto, `${tag}: uploaded font not listed (${await page.evaluate(() => document.getElementById("fontMsg").textContent)})`);
    await setSource(page, "json", JSON.stringify({ type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#fff", alignItems: "center", justifyContent: "center" }, children: [{ type: "text", text: "Roboto upload", style: { fontFamily: "Roboto", fontSize: 72, color: "#111" } }] }), { width: 600, height: 200 });
    await sleep(60); await doRender(page);
    { const s = await snapshot(page); const ok = s.status === "ok" && s.imgW === 600 && s.imgH === 200; R.extra["font upload + render"] = ok && hasRoboto ? "pass" : "FAIL"; if (!ok) fail(`${tag}: render with uploaded font: ${JSON.stringify(s)}`); }
    // remove it again
    await page.click('#fontList li[data-family="Roboto"] button');
    check(!(await page.evaluate(() => !!document.querySelector('#fontList li[data-family="Roboto"]'))), `${tag}: font not removed`);
    R.extra["font remove"] = "pass";

    // ---- image upload (png -> images entry)
    const tmpPng = path.join(dl, "pic.png");
    writeFileSync(tmpPng, Buffer.from(await page.evaluate(() => window.pg.state.images[0]?.b64 || ""), "base64"));
    if (readFileSync(tmpPng).length) {
      await (await page.$("#imageInput")).uploadFile(tmpPng);
      await page.waitForFunction(() => window.pg.state.images.some((i) => i.src === "img://pic"), { timeout: 10000 }).catch(() => {});
      const ok = await page.evaluate(() => window.pg.state.images.some((i) => i.src === "img://pic"));
      R.extra["image upload"] = ok ? "pass" : "FAIL"; check(ok, `${tag}: image upload entry`);
    }

    // ---- download + copy data URL
    await page.select("#template", "og-card"); await sleep(60); await setFormat(page, "png"); await sleep(60); await doRender(page);
    for (const fmt of F.renderSvg ? ["png", "svg"] : ["png"]) {
      await setFormat(page, fmt); await sleep(60); await doRender(page);
      await page.evaluate(() => {
        window.__dl = null;
        HTMLAnchorElement.prototype.click = function () {
          if (!this.download) return;
          const name = this.download;
          fetch(this.href).then((r) => r.arrayBuffer()).then((buf) => { const u = new Uint8Array(buf); window.__dl = { name, size: u.length, head: Array.from(u.subarray(0, 8)), text: new TextDecoder().decode(u.subarray(0, 300)) }; });
        };
      });
      await page.click("#downloadBtn");
      await page.waitForFunction(() => window.__dl, { timeout: 5000 }).catch(() => {});
      const d = await page.evaluate(() => window.__dl);
      const ok = !!d && d.name === (fmt === "png" ? "bm-render.png" : "bm-render.svg") && (fmt === "png" ? d.head[1] === 80 && d.head[2] === 78 && d.head[3] === 71 : /<svg/.test(d.text));
      R.extra["download " + fmt] = ok ? "pass" : "FAIL"; check(ok, `${tag}: download ${fmt} (${JSON.stringify(d)})`);
    }
    await setFormat(page, "png"); await sleep(60); await doRender(page);
    await page.click("#copyBtn"); await sleep(200);
    { const u = await page.evaluate(() => window.__lastDataUrl || ""); const ok = u.startsWith("data:image/png;base64,") && u.length > 1000; R.extra["copy data URL"] = ok ? "pass" : "FAIL"; check(ok, `${tag}: copy data URL`); }

    // ---- friendly message for HTML input where unsupported
    await setSource(page, "html", "<div style=\"font-family:Inter;font-size:40px\">Hello HTML</div>", { width: 400, height: 120 });
    await sleep(60); await doRender(page);
    { const s = await snapshot(page);
      if (!F.html) {
        const ok = s.status === "error" && /html/i.test(s.error) && s.hintButtons.length > 0;
        R.extra["html input friendly error"] = ok ? "pass" : "FAIL"; check(ok, `${tag}: expected friendly HTML error: ${JSON.stringify(s)}`);
        const tabMark = await page.evaluate(() => !document.querySelector("#tab-html .miss").hidden);
        check(tabMark, `${tag}: HTML tab not annotated`);
      } else { const ok = s.status === "ok" && s.imgW === 400 && s.imgH === 120; R.extra["html input"] = ok ? "pass" : "FAIL"; check(ok, `${tag}: html render ${JSON.stringify(s)}`); } }
    // invalid JSON message
    await setSource(page, "json", "{ nope"); await sleep(60); await doRender(page);
    { const s = await snapshot(page); const ok = s.status === "error" && /Invalid JSON/.test(s.error); R.extra["invalid JSON message"] = ok ? "pass" : "FAIL"; check(ok, `${tag}: invalid json: ${JSON.stringify(s)}`); }

    // ---- hash share round trip (fresh context = empty localStorage)
    await page.select("#template", "vietnamese"); await sleep(60);
    await setSource(page, "json", JSON.stringify({ type: "text", text: "Hash round trip Xin chào", style: { fontFamily: "Inter", fontSize: 40 } }), { width: 640, height: 120 });
    await sleep(60); await doRender(page);
    await page.click("#shareBtn"); await sleep(400);
    const hash = await page.evaluate(() => location.hash);
    check(/^#s=[zp]\./.test(hash), `${tag}: share hash ${hash.slice(0, 20)}`);
    const before = await page.evaluate(() => ({ json: window.pg.state.json, w: window.pg.state.width, h: window.pg.state.height }));
    const ctx2 = await browser.createBrowserContext();
    const p2 = await openPage(ctx2, base, `?profile=${profile}`, sink, tag + "-hash", hash);
    const after = await p2.evaluate(() => ({ json: window.pg.state.json, w: window.pg.state.width, h: window.pg.state.height, shown: document.getElementById("src").value }));
    const hok = after.json === before.json && after.w === 640 && after.h === 120 && after.shown === before.json;
    const s2 = await snapshot(p2);
    R.extra["hash round trip"] = hok && s2.status === "ok" && s2.imgW === 640 ? `pass (${hash.length} chars, ${hash.startsWith("#s=z.") ? "compressed" : "plain"})` : "FAIL";
    check(hok && s2.status === "ok" && s2.imgW === 640, `${tag}: hash round trip ${JSON.stringify({ hok, s2 })}`);
    await ctx2.close();

    // ---- switching profile through the selector reloads with ?profile=
    if (profile === "full") {
      await page.select("#profile", "core");
      await page.waitForFunction(() => document.body.dataset.profile === "core" && document.body.dataset.ready === "1", { timeout: 30000 });
      const p = await page.evaluate(() => ({ p: document.body.dataset.profile, url: location.search, bin: document.getElementById("binInfo").textContent }));
      R.extra["profile switch (reload)"] = p.p === "core" && /core\.wasm/.test(p.bin) ? "pass" : "FAIL"; check(p.p === "core" && /core\.wasm/.test(p.bin), `${tag}: switch ${JSON.stringify(p)}`);
    }
  } catch (e) {
    fail(`${tag}: exception ${e.stack || e}`);
  }
  check(sink.length === 0, `${tag}: browser errors:\n  ` + sink.join("\n  "));
  if (sink.length) R.extra["console/page/network errors"] = sink.length + " (see FAIL)"; else R.extra["console/page/network errors"] = "none";
  rmSync(dl, { recursive: true, force: true });
  await ctx.close();
}

// ---------------------------------------------------------------------------------------------- PDF mode
const PDF_LAZY = /\/(pdf\.mjs|pdf-api\.mjs|pdf-templates\.js|bm_render\.pdf\.wasm)(\?|$)|pdfjs-/;
const PDFJS = /pdfjs-[\d.]+\/pdf(\.worker)?\.min\.mjs/;
const IPHONE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1";
const countPages = (buf) => (Buffer.from(buf).toString("latin1").match(/\/Type\s*\/Page(?![s\w])/g) || []).length;
function trackRequests(page) { const urls = []; page.on("request", (r) => urls.push(r.url())); return urls; }
/** A screenshot of an element, decoded in the page: how many distinct colours and dark pixels it shows. */
async function shotStats(page, handle) {
  const b64 = await handle.screenshot({ encoding: "base64" });
  return page.evaluate(async (b64) => {
    const bmp = await createImageBitmap(await (await fetch("data:image/png;base64," + b64)).blob());
    const c = new OffscreenCanvas(bmp.width, bmp.height); const x = c.getContext("2d"); x.drawImage(bmp, 0, 0);
    const d = x.getImageData(0, 0, bmp.width, bmp.height).data; const colors = new Set(); let dark = 0;
    for (let i = 0; i < d.length; i += 4 * 3) { colors.add(((d[i] >> 4) << 8) | ((d[i + 1] >> 4) << 4) | (d[i + 2] >> 4)); if (d[i] + d[i + 1] + d[i + 2] < 240) dark++; }
    return { w: bmp.width, h: bmp.height, colors: colors.size, dark };
  }, b64);
}
/** pdf.js canvases: how many, and the share of non-white pixels of the first (the page drawn, not an empty sheet). */
const canvasInk = (frame) => frame.evaluate(() => {
  const cv = document.querySelector("#pdfPages canvas"); if (!cv) return { n: 0, ink: 0 };
  const d = cv.getContext("2d").getImageData(0, 0, cv.width, cv.height).data; let ink = 0, n = 0;
  for (let i = 0; i < d.length; i += 4 * 7) { n++; if (d[i] < 200 || d[i + 1] < 200 || d[i + 2] < 200) ink++; }
  return { n: document.querySelectorAll("#pdfPages canvas").length, ink: ink / n };
});
async function pdfSnap(frame) {
  return frame.evaluate(() => {
    const d = document.body.dataset;
    return { status: d.status, mode: d.mode, head: d.outHead || "", pages: +d.outPages || 0, bytes: +d.outBytes || 0, preview: d.pdfPreview, previewReady: d.previewReady,
      error: document.getElementById("errorPanel").hidden ? "" : document.getElementById("errorText").textContent,
      frameSrc: document.getElementById("pdfFrame").getAttribute("src") || "", time: document.getElementById("stTime").textContent,
      bin: document.getElementById("binInfo").textContent, mem: document.getElementById("stMem").textContent };
  });
}
/** Waits for the PDF viewer frame (blob: URL) and checks from a screenshot that it shows the page. */
async function viewerShows(page, frame) {
  const fh = await frame.$("#pdfFrame");
  let cf = null;
  for (let i = 0; i < 40 && !(cf && cf.url().startsWith("blob:")); i++) { cf = await fh.contentFrame(); await sleep(150); }
  await sleep(1500); // the viewer paints asynchronously
  const st = await shotStats(page, fh);
  return { url: cf?.url() || "", child: cf ? cf.childFrames().length : -1, ...st };
}
/** Runs the "Copy code" module in Node.js against this checkout (node_modules/bm-render and assets/ are junctions). */
function runSnippet(code) {
  const dir = mkdtempSync(path.join(os.tmpdir(), "bm-pg-snippet-"));
  const links = [path.join(dir, "node_modules", "bm-render"), path.join(dir, "assets")];
  mkdirSync(path.join(dir, "node_modules"));
  symlinkSync(ROOT, links[0], "junction"); symlinkSync(path.join(ROOT, "assets"), links[1], "junction");
  writeFileSync(path.join(dir, "render-pdf.mjs"), code);
  const r = spawnSync(process.execPath, ["render-pdf.mjs"], { cwd: dir, encoding: "utf8", env: { ...process.env, BM_RENDER_BACKEND: "wasm" } });
  const out = existsSync(path.join(dir, "bm-render.pdf")) ? readFileSync(path.join(dir, "bm-render.pdf")) : null;
  for (const l of links) unlinkSync(l); // the junctions first: never recurse into the checkout
  rmSync(dir, { recursive: true, force: true });
  return { status: r.status, stdout: r.stdout.trim(), stderr: r.stderr.trim(), head: out ? out.subarray(0, 5).toString("latin1") : "", pages: out ? countPages(out) : 0, bytes: out?.length || 0 };
}
async function selectPdfTemplate(frame, id) {
  const b = await renders(frame);
  await frame.select("#template", id);
  await settle(frame, b);
  await frame.waitForFunction(() => document.body.dataset.previewReady, { timeout: 30000 });
}
async function interceptDownload(frame) {
  await frame.evaluate(() => {
    window.__dl = null;
    HTMLAnchorElement.prototype.click = function () {
      if (!this.download) return;
      const name = this.download;
      fetch(this.href).then((r) => r.arrayBuffer()).then((buf) => { const u = new Uint8Array(buf); window.__dl = { name, size: u.length, head: new TextDecoder("latin1").decode(u.subarray(0, 5)) }; });
    };
  });
}
const setPdf = (page, kv) => page.evaluate((kv) => {
  for (const [k, v] of Object.entries(kv)) {
    const el = document.querySelector(`[data-pdf="${k}"]`); if (el.type === "checkbox") el.checked = v; else el.value = v;
    el.dispatchEvent(new Event(el.tagName === "SELECT" || el.type === "checkbox" ? "change" : "input", { bubbles: true }));
  }
}, kv);

/** PDF mode of the standalone app (dev layout, or a reduced pass on the self-contained build). */
async function pdfSuite(base, tag, { full = true } = {}) {
  const sink = [];
  const R = { templates: {}, extra: {} };
  results[tag] = R;
  const ctx = await browser.createBrowserContext();
  try {
    // ---- Image mode first: nothing of the PDF engine or pdf.js is requested
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, tag, sink);
    const reqs = trackRequests(page);
    await page.goto(`${base}?profile=full&mode=image`, { waitUntil: "load" });
    await page.waitForFunction("document.body.dataset.ready === '1'", { timeout: 60000 });
    await settle(page, 0);
    const lazyHits = reqs.filter((u) => PDF_LAZY.test(u));
    R.extra["Image mode requests no PDF engine / pdf.js"] = lazyHits.length ? "FAIL" : `pass (wasm: ${reqs.filter((u) => /\.wasm/.test(u)).map((u) => u.split("/").pop()).join(", ")})`;
    check(!lazyHits.length, `${tag}: Image mode requested PDF files: ${lazyHits.join(", ")}`);
    const switchVisible = await page.$eval("#modeSwitch", (e) => getComputedStyle(e).display !== "none");
    check(switchVisible, `${tag}: Image | PDF switch not visible standalone`);

    // ---- switch to PDF in place: the editor content stays, the PDF engine loads now, the URL says mode=pdf
    const before = await page.evaluate(() => ({ kind: window.pg.state.kind, src: document.getElementById("src").value, css: document.getElementById("css").value }));
    let b = await renders(page);
    await page.click('#modeSwitch button[data-mode="pdf"]');
    await settle(page, b);
    await page.waitForFunction(() => document.body.dataset.previewReady, { timeout: 30000 });
    let s = await pdfSnap(page);
    const after = await page.evaluate(() => ({ kind: window.pg.state.kind, src: document.getElementById("src").value, css: document.getElementById("css").value, url: location.search, accent: getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() }));
    const kept = after.kind === before.kind && after.src === before.src && after.css === before.css;
    const okSwitch = kept && s.mode === "pdf" && s.status === "ok" && s.head.startsWith("%PDF-") && /mode=pdf/.test(after.url) && /bm_render\.pdf\.wasm - 1\.\d+ MiB/.test(s.bin) && after.accent.toLowerCase() === "#4f46e5";
    R.extra["Image -> PDF keeps the editor, loads the pdf wasm, ?mode=pdf"] = okSwitch ? `pass (${s.bin}; OG card JSON -> ${s.pages}-page PDF)` : "FAIL";
    check(okSwitch, `${tag}: switch to PDF: ${JSON.stringify({ kept, s, after })}`);
    check(reqs.some((u) => /bm_render\.pdf\.wasm/.test(u)) && !reqs.some((u) => PDFJS.test(u)), `${tag}: after the switch: pdf wasm requested and pdf.js not (viewer preview)`);

    // ---- every PDF template: %PDF- bytes, page count, the viewer shows it
    const tpls = await page.evaluate(() => window.pg.pdfTemplates.map((t) => ({ id: t.id, pages: t.pages })));
    check(tpls.length >= 5 && tpls.length <= 7, `${tag}: ${tpls.length} PDF templates`);
    const tplOptions = await page.evaluate(() => document.querySelectorAll("#template option").length);
    check(tplOptions === tpls.length + 1, `${tag}: PDF template options ${tplOptions}`);
    for (const t of full ? tpls : tpls.slice(0, 2)) {
      await selectPdfTemplate(page, t.id);
      s = await pdfSnap(page);
      const ok = s.status === "ok" && s.head.startsWith("%PDF-") && s.pages === t.pages && s.previewReady === "viewer" && s.frameSrc.startsWith("blob:") && !s.error;
      R.templates[t.id] = ok ? `pass (${s.pages} page(s), ${s.bytes} B, ${s.time})` : "FAIL";
      if (!ok) fail(`${tag}: PDF template ${t.id}: ${JSON.stringify(s)} expected ${t.pages} pages`); else say(`  ok   pdf ${t.id} ${s.pages}p ${s.bytes} B  ${s.time}`);
    }
    await selectPdfTemplate(page, "invoice");
    // the page screenshot first: an element screenshot can resize the viewport for a moment and the viewer re-zooms
    if (full) { await sleep(2000); await page.screenshot({ path: path.join(DOCS_SHOTS, "playground-pdf-standalone.png") }); }
    const v = await viewerShows(page, page.mainFrame());
    const vok = v.url.startsWith("blob:") && v.colors > 8 && v.dark > 200;
    R.extra["inline preview: browser PDF viewer (iframe, blob URL) shows the page"] = vok ? `pass (viewer child frames: ${v.child}, ${v.colors} colours, ${v.dark} dark px in ${v.w}x${v.h})` : "FAIL";
    check(vok, `${tag}: viewer preview: ${JSON.stringify(v)}`);

    // ---- pdf.js preview (chosen), loaded only now; canvases with ink
    await page.select("#pdfPreview", "pdfjs");
    await page.waitForFunction(() => ["pdfjs", "pdfjs-error"].includes(document.body.dataset.previewReady), { timeout: 30000 });
    const ink = await canvasInk(page.mainFrame());
    const pjOk = ink.n === 1 && ink.ink > 0.01 && reqs.some((u) => PDFJS.test(u));
    R.extra["pdf.js preview: loaded on demand, non-blank canvas"] = pjOk ? `pass (${ink.n} canvas, ${(ink.ink * 100).toFixed(1)}% ink)` : "FAIL";
    check(pjOk, `${tag}: pdf.js preview ${JSON.stringify({ ink, note: await page.$eval("#previewNote", (e) => e.textContent) })}`);
    await selectPdfTemplate(page, "report");
    await page.waitForFunction(() => document.body.dataset.previewReady === "pdfjs", { timeout: 30000 });
    { const k = await canvasInk(page.mainFrame()); check(k.n === 4 && k.ink > 0.01, `${tag}: pdf.js report pages ${JSON.stringify(k)}`); }
    await page.select("#pdfPreview", "auto");
    if (!full) { check(sink.length === 0, `${tag}: browser errors:\n  ` + sink.join("\n  ")); R.extra["console/page/network errors"] = sink.length ? "see FAIL" : "none"; await ctx.close(); return; }

    // ---- measure(), stats
    await page.click("#measureToggle"); await sleep(100); await selectPdfTemplate(page, "article");
    { const m = await page.evaluate(() => ({ v: document.getElementById("stMeasure").textContent, shown: !document.getElementById("stMeasureBox").hidden, mem: document.getElementById("stMem").textContent, t: document.getElementById("stTime").textContent }));
      const ok = m.shown && /^\d+ x \d+ px$/.test(m.v) && /MiB/.test(m.mem) && /median of \d+/.test(m.t);
      R.extra["stats: pages, size, median time, wasm memory, measure()"] = ok ? `pass (measure ${m.v}, memory ${m.mem})` : "FAIL"; check(ok, `${tag}: stats ${JSON.stringify(m)}`); }
    await page.click("#measureToggle");

    // ---- download (intercepted) and open in a new tab
    await interceptDownload(page.mainFrame());
    await page.click("#downloadBtn");
    await page.waitForFunction(() => window.__dl, { timeout: 5000 }).catch(() => {});
    { const d = await page.evaluate(() => window.__dl); const ok = d && d.name === "bm-render.pdf" && d.head === "%PDF-" && d.size > 1000;
      R.extra["download .pdf"] = ok ? `pass (${d.size} B)` : "FAIL"; check(ok, `${tag}: download ${JSON.stringify(d)}`); }
    const newTarget = browser.waitForTarget((t) => t.url().startsWith("blob:"), { timeout: 10000 }).catch(() => null);
    await page.click("#openBtn");
    { const t = await newTarget; R.extra["open in new tab (blob URL)"] = t ? "pass" : "FAIL"; check(!!t, `${tag}: open in new tab: no blob: target`); if (t) { const p2 = await t.page().catch(() => null); await p2?.close().catch(() => {}); } }

    // ---- Copy code -> run the module in Node.js
    await selectPdfTemplate(page, "accessible");
    await page.click("#codeBtn"); await sleep(200);
    { const code = await page.evaluate(() => window.__lastCode || "");
      const want = await page.evaluate(() => +document.body.dataset.outPages);
      const r = code.includes('from "bm-render/pdf"') && code.includes("new PdfRenderer()") ? runSnippet(code) : { status: -1, stderr: "no snippet" };
      const ok = r.status === 0 && r.head === "%PDF-" && r.pages === want;
      R.extra["Copy code -> runs in Node.js"] = ok ? `pass (accessible template, PDF/UA-1 + image: ${r.pages} page, ${r.bytes} B; ${code.split("\n").length} lines)` : "FAIL";
      check(ok, `${tag}: copy code run: ${JSON.stringify(r)}`); }

    // ---- engine errors verbatim: a PDF/UA violation (with the hint), a colour the engine rejects, a character no font draws
    await setPdf(page, { title: "" }); await doRender(page);
    s = await pdfSnap(page);
    { const hint = await page.$eval("#errorHint", (e) => (e.hidden ? "" : e.textContent));
      const ok = s.status === "error" && s.error === "bm-render: Writing the PDF failed: validation failed with 1 error" && /metadata.title/.test(hint);
      R.extra["PDF/UA validation error (no title) + hint"] = ok ? `pass (${s.error})` : "FAIL"; check(ok, `${tag}: ua1 without title ${JSON.stringify({ s, hint })}`); }
    await selectPdfTemplate(page, "invoice");
    await setPdf(page, { bg: "paper" });
    await doRender(page);
    s = await pdfSnap(page);
    { const ok = s.status === "error" && s.error === "bm-render: backgroundColor is not a color: paper";
      R.extra["engine error shown verbatim (backgroundColor)"] = ok ? `pass (${s.error})` : "FAIL"; check(ok, `${tag}: bg error ${JSON.stringify(s)}`); }
    await setPdf(page, { bg: "" });
    await setSource(page, "html", "<p style=\"font-family: Inter\">Tokyo 東京</p>");
    await doRender(page);
    s = await pdfSnap(page);
    { const ok = s.status === "error" && /^bm-render: No font the text can use draws 東/.test(s.error);
      R.extra["missing font error (uncoveredText: error)"] = ok ? `pass (${s.error.slice(0, 60)}...)` : "FAIL"; check(ok, `${tag}: missing font ${JSON.stringify(s)}`); }
    await setPdf(page, { uncovered: "blank" }); await doRender(page);
    s = await pdfSnap(page); check(s.status === "ok" && s.head.startsWith("%PDF-"), `${tag}: uncoveredText blank ${JSON.stringify(s)}`);
    // conformance selects follow the typings: pdfa 2a forbids tagged false / ua2
    await setPdf(page, { pdfa: "2a" }); await sleep(100);
    { const dis = await page.$$eval("#pdfTagged option", (o) => o.filter((x) => x.disabled).map((x) => x.value).join(","));
      R.extra["tagged choices limited by pdfa (2a)"] = dis === "false,ua2" ? "pass (false, ua2 disabled)" : "FAIL"; check(dis === "false,ua2", `${tag}: tagged disabled for 2a: ${dis}`); }
    await setPdf(page, { pdfa: "" });

    // ---- share link: mode + PDF options survive a fresh browser profile
    await selectPdfTemplate(page, "invoice");
    await setPdf(page, { size: "letter", landscape: true, title: "Shared invoice", outline: true, pageRanges: "1" });
    await doRender(page);
    await page.click("#shareBtn"); await sleep(400);
    const shareUrl = await page.evaluate(() => window.__shareUrl || "");
    check(/[?&]mode=pdf/.test(shareUrl) && /#s=[zp]\./.test(shareUrl), `${tag}: share URL ${shareUrl.slice(0, 120)}`);
    const ctx2 = await browser.createBrowserContext();
    const p2 = await ctx2.newPage(); await p2.setViewport({ width: 1440, height: 900 }); watch(p2, tag + "-share", sink);
    const u = new URL(shareUrl); u.searchParams.delete("mode"); // the hash alone must restore the mode
    await p2.goto(u.href, { waitUntil: "load" });
    await p2.waitForFunction("document.body.dataset.ready === '1' && +document.body.dataset.renders > 0 && document.body.dataset.previewReady", { timeout: 60000 });
    { const st = await p2.evaluate(() => ({ mode: window.pg.state.mode, p: window.pg.state.pdf, size: document.getElementById("pdfSize").value, land: document.querySelector('[data-pdf="landscape"]').checked, title: document.querySelector('[data-pdf="title"]').value }));
      const s2 = await pdfSnap(p2);
      const ok = st.mode === "pdf" && st.size === "letter" && st.land && st.title === "Shared invoice" && st.p.outline === true && st.p.pageRanges === "1" && s2.status === "ok" && s2.pages === 1;
      R.extra["share link round trip (mode + PDF options)"] = ok ? `pass (${shareUrl.length} chars)` : "FAIL"; check(ok, `${tag}: share round trip ${JSON.stringify({ st, s2 })}`); }
    await ctx2.close();

    // ---- back to Image: the editor content stays and renders as an image
    const srcPdf = await page.$eval("#src", (e) => e.value);
    b = await renders(page);
    await page.click('#modeSwitch button[data-mode="image"]');
    await settle(page, b);
    { const st = await page.evaluate(() => ({ mode: document.body.dataset.mode, src: document.getElementById("src").value, fmt: document.body.dataset.outFormat, status: document.body.dataset.status, url: location.search }));
      const ok = st.mode === "image" && st.src === srcPdf && st.fmt === "png" && st.status === "ok" && /mode=image/.test(st.url);
      R.extra["PDF -> Image keeps the editor"] = ok ? "pass" : "FAIL"; check(ok, `${tag}: back to image ${JSON.stringify(st)}`); }

    // ---- dark theme accent and the phone layout (pdf.js preview: a phone browser has no inline viewer)
    const pd = await ctx.newPage(); watch(pd, tag + "-dark", sink);
    await pd.emulateMediaFeatures([{ name: "prefers-color-scheme", value: "dark" }]);
    await pd.setViewport({ width: 1440, height: 900 });
    await pd.goto(`${base}?mode=pdf`, { waitUntil: "load" });
    await pd.waitForFunction("document.body.dataset.ready === '1' && document.body.dataset.previewReady", { timeout: 60000 });
    { const a = await pd.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--accent").trim().toLowerCase());
      R.extra["dark theme (PDF accent #a5b4fc)"] = a === "#a5b4fc" ? "pass" : "FAIL"; check(a === "#a5b4fc", `${tag}: dark accent ${a}`); }
    await pd.close();
    const pm = await ctx.newPage(); watch(pm, tag + "-mobile", sink);
    await pm.setUserAgent(IPHONE_UA);
    await pm.setViewport({ width: 390, height: 844, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
    await pm.goto(`${base}?mode=pdf`, { waitUntil: "load" });
    await pm.waitForFunction("document.body.dataset.ready === '1' && ['pdfjs','pdfjs-error'].includes(document.body.dataset.previewReady)", { timeout: 60000 });
    { const k = await canvasInk(pm.mainFrame()); const o = await pm.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      const ok = k.n >= 1 && k.ink > 0.01 && o <= 1;
      R.extra["phone (iPhone UA, 390px): pdf.js preview, no overflow"] = ok ? `pass (${k.n} page canvas, overflow ${o}px)` : "FAIL"; check(ok, `${tag}: mobile ${JSON.stringify({ k, o })}`); }
    await pm.close();
  } catch (e) { fail(`${tag}: exception ${e.stack || e}`); }
  check(sink.length === 0, `${tag}: browser errors:\n  ` + sink.join("\n  "));
  R.extra["console/page/network errors"] = sink.length ? sink.length + " (see FAIL)" : "none";
  await ctx.close();
}

/** /pdf/playground and /vi/pdf/playground of the built docs site: the embedded app in PDF mode. */
async function sitePdfSuite(siteBase, lang) {
  const route = lang === "vi" ? "/vi/pdf/playground" : "/pdf/playground";
  const tag = `site${route}`;
  const sink = [];
  const R = { templates: {}, extra: {} };
  results[tag] = R;
  const ctx = await browser.createBrowserContext();
  try {
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, tag, sink);
    const reqs = trackRequests(page);
    const resp = await page.goto(siteBase + route, { waitUntil: "load" });
    check(resp.status() === 200, `${tag}: HTTP ${resp.status()}`);
    await page.waitForSelector("iframe.pg-embed-frame", { timeout: 30000 });
    const src = await page.$eval("iframe.pg-embed-frame", (f) => f.getAttribute("src"));
    check(src.includes("mode=pdf") && src.includes("embed=1") && src.includes(`lang=${lang}`), `${tag}: iframe src ${src}`);
    const frame = await (await page.$("iframe.pg-embed-frame")).contentFrame();
    await frame.waitForFunction(() => document.body?.dataset.ready === "1" && +document.body.dataset.renders > 0 && document.body.dataset.previewReady, { timeout: 60000 });
    const ui = await frame.evaluate(() => ({ lang: document.documentElement.lang, switchShown: getComputedStyle(document.getElementById("modeSwitch")).display !== "none", tpl: document.getElementById("template").value }));
    check(ui.lang === lang && !ui.switchShown && ui.tpl === "invoice", `${tag}: embedded app ${JSON.stringify(ui)}`);
    let s = await pdfSnap(frame);
    check(s.status === "ok" && s.head.startsWith("%PDF-") && s.pages === 1, `${tag}: first render ${JSON.stringify(s)}`);
    R.templates["invoice (first render)"] = `pass (${s.pages} page, ${s.bytes} B, ${s.time})`;
    // the nested iframe (docs page > app > blob: PDF) shows the page in the browser's viewer
    const v = await viewerShows(page, frame);
    const vok = v.url.startsWith("blob:") && v.colors > 8 && v.dark > 200;
    R.extra["nested iframe: browser PDF viewer shows the page"] = vok ? `pass (${v.colors} colours, ${v.dark} dark px in ${v.w}x${v.h})` : "FAIL";
    check(vok, `${tag}: nested viewer ${JSON.stringify(v)}`);
    for (const id of ["article", "links"]) {
      await selectPdfTemplate(frame, id);
      s = await pdfSnap(frame);
      const ok = s.status === "ok" && s.head.startsWith("%PDF-") && s.pages === 4;
      R.templates[id] = ok ? `pass (${s.pages} pages, ${s.bytes} B)` : "FAIL"; check(ok, `${tag}: ${id} ${JSON.stringify(s)}`);
    }
    await frame.select("#pdfPreview", "pdfjs");
    await frame.waitForFunction(() => ["pdfjs", "pdfjs-error"].includes(document.body.dataset.previewReady), { timeout: 30000 });
    const ink = await canvasInk(frame);
    const pjOk = ink.n === 4 && ink.ink > 0.01 && reqs.some((u) => PDFJS.test(u)) && reqs.every((u) => u.startsWith(siteBase) || /^(blob|data):/.test(u));
    R.extra["pdf.js preview inside the docs iframe (served by the site, no CDN)"] = pjOk ? `pass (${ink.n} canvases)` : "FAIL";
    check(pjOk, `${tag}: embedded pdf.js ${JSON.stringify(ink)} ${reqs.filter((u) => !u.startsWith(siteBase)).join(" ")}`);
    await frame.select("#pdfPreview", "auto");
    // the docs page's own switcher: PDF current, Image links to the image playground of this locale
    const sw = await page.evaluate(() => [...document.querySelectorAll(".bm-pg-switcher a")].map((a) => [a.getAttribute("href"), a.getAttribute("aria-current") || ""]));
    const pre = lang === "vi" ? "/vi" : "";
    const swOk = JSON.stringify(sw) === JSON.stringify([[`${pre}/image/playground`, ""], [`${pre}/pdf/playground`, "page"]]);
    R.extra["page switcher (Image | PDF) above the app"] = swOk ? "pass" : "FAIL";
    check(swOk, `${tag}: page switcher ${JSON.stringify(sw)}`);
  } catch (e) { fail(`${tag}: exception ${e.stack || e}`); }
  check(sink.length === 0, `${tag}: browser errors:\n  ` + sink.join("\n  "));
  R.extra["console/page/network errors"] = sink.length ? sink.length + " (see FAIL)" : "none";
  await ctx.close();
}

// ---------------------------------------------------------------------------------------------- screenshots
async function shots(base) {
  const sink = [];
  const ctx = await browser.createBrowserContext();
  const page = await openPage(ctx, base, "?profile=full", sink, "shots");
  await page.setViewport({ width: 1440, height: 900 });
  await page.select("#template", "og-card"); await sleep(60); await doRender(page);
  await sleep(200);
  await page.screenshot({ path: path.join(SHOTS, "og-card-full.png") });
  await page.select("#template", "vietnamese"); await sleep(60); await doRender(page); await sleep(200);
  await page.screenshot({ path: path.join(SHOTS, "vietnamese-full.png") });
  await page.emulateMediaFeatures([{ name: "prefers-color-scheme", value: "dark" }]);
  await page.select("#template", "og-card"); await sleep(60); await doRender(page); await sleep(300);
  await page.screenshot({ path: path.join(SHOTS, "dark-mode-full.png") });
  await page.setViewport({ width: 390, height: 844, isMobile: true });
  await sleep(300);
  await page.screenshot({ path: path.join(SHOTS, "mobile-full.png") });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check(overflow <= 1, `mobile layout horizontal overflow ${overflow}px`);
  check(sink.length === 0, "screenshot page errors: " + sink.join("; "));
  await ctx.close();
}

// ---------------------------------------------------------------------------------------------- docs site
/** The playground page of the built docs site: the iframe app starts on every profile and renders the OG card. */
async function siteSuite(siteBase, lang) {
  const route = lang === "vi" ? "/vi/image/playground" : "/image/playground";
  const tag = `site${route}`;
  const sink = [];
  const R = { templates: {}, extra: {} };
  results[tag] = R;
  const ctx = await browser.createBrowserContext();
  try {
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, tag, sink);
    const reqs = trackRequests(page);
    const resp = await page.goto(siteBase + route, { waitUntil: "load" });
    check(resp.status() === 200, `${tag}: HTTP ${resp.status()}`);
    await page.waitForSelector("iframe.pg-embed-frame", { timeout: 30000 });
    const box = await page.$eval("iframe.pg-embed-frame", (f) => { const r = f.getBoundingClientRect(); return { w: r.width, h: r.height, src: f.getAttribute("src") }; });
    R.extra["iframe size"] = `${Math.round(box.w)}x${Math.round(box.h)} (${box.src})`;
    check(box.w >= 1000 && box.h >= 700, `${tag}: iframe too small ${JSON.stringify(box)}`);
    check(box.src.includes(`lang=${lang}`), `${tag}: iframe src without lang: ${box.src}`);
    const frame = await (await page.$("iframe.pg-embed-frame")).contentFrame();
    for (const profile of ["full", "standard", "core"]) {
      const cur = await frame.evaluate(() => document.body?.dataset.profile || "");
      if (cur && cur !== profile) await frame.select("#profile", profile);
      await frame.waitForFunction((p) => document.body && document.body.dataset.ready === "1" && document.body.dataset.profile === p, { timeout: 60000 }, profile);
      await settle(frame, 0);
      await frame.select("#template", "og-card"); await sleep(60);
      await doRender(frame);
      const s = await snapshot(frame);
      const uiLang = await frame.evaluate(() => document.documentElement.lang);
      const ok = s.status === "ok" && s.imgOk && s.imgW === 1200 && s.imgH === 630 && !s.error && uiLang === lang;
      R.templates[`og-card (${profile})`] = ok ? `pass (${s.bytes} B, ${s.time}, ui=${uiLang})` : "FAIL";
      if (!ok) fail(`${tag}: ${profile}: ${JSON.stringify({ ...s, uiLang })}`); else say(`  ok   ${tag} ${profile} og-card ${s.imgW}x${s.imgH}`);
    }
    { const hits = reqs.filter((u) => PDF_LAZY.test(u)); R.extra["no PDF engine / pdf.js requested"] = hits.length ? "FAIL" : "pass"; check(!hits.length, `${tag}: requested ${hits.join(", ")}`); }
  } catch (e) { fail(`${tag}: exception ${e.stack || e}`); }
  check(sink.length === 0, `${tag}: browser errors:\n  ` + sink.join("\n  "));
  R.extra["console/page/network errors"] = sink.length ? sink.length + " (see FAIL)" : "none";
  await ctx.close();
}

// ---------------------------------------------------------------------------------------------- main
let browser, server, distServer, siteServer;
try {
  browser = await puppeteer.launch({ executablePath: exe, headless: true, args: ["--no-first-run", "--no-default-browser-check", "--disable-extensions"] });
  say(`browser: ${await browser.version()}`);
  server = await startServer();
  const base = `${server.url}/docs/playground-app/`;
  say(`dev server: ${server.url}`);
  // static server sanity: wasm MIME + traversal
  { const r = await fetch(server.url + "/js/bm_render.wasm"); check(r.headers.get("content-type") === "application/wasm", "wasm content-type " + r.headers.get("content-type"));
    const t = await fetch(server.url + "/docs/playground-app/..%2f..%2f..%2fpackage.json").catch(() => null); check(!t || t.status >= 400, "directory traversal not blocked"); }

  for (const profile of ["core", "standard", "full"]) await suite(() => browser.createBrowserContext(), base, profile);
  await pdfSuite(base, "pdf (dev)");
  await shots(base);

  // ---- dist build
  const b = spawnSync(process.execPath, [path.join(PG, "build.mjs")], { encoding: "utf8" });
  say("\n" + (b.stdout || "").trim());
  if (!check(b.status === 0, "build.mjs failed: " + b.stderr)) throw new Error("build failed");
  distServer = await startServer({ root: path.join(PG, "dist") });
  say(`dist server: ${distServer.url}`);
  { const r = await fetch(distServer.url + "/vendor/bm_render.core.wasm"); check(r.headers.get("content-type") === "application/wasm", "dist wasm type"); }
  for (const profile of ["core", "standard", "full"]) await suite(() => browser.createBrowserContext(), distServer.url + "/", profile, { dist: true });
  { const r = await fetch(distServer.url + "/vendor/bm_render.pdf.wasm"); check(r.ok && r.headers.get("content-type") === "application/wasm", "dist pdf wasm " + r.status);
    const cfg = await (await fetch(distServer.url + "/config.js")).text(); check(/versions: \{"bm_render\.core\.wasm":"[0-9a-f]{12}"/.test(cfg) && /pdfjsBase: "\.\/vendor\/pdfjs-[\d.]+\/"/.test(cfg), "dist config.js: versions / pdfjsBase"); }
  await pdfSuite(distServer.url + "/", "pdf (dist)", { full: false });

  // ---- docs site (VitePress build) embedding the playground
  if (!args["skip-docs-build"] || !existsSync(path.join(SITE, "index.html"))) {
    const vp = path.join(ROOT, "node_modules", "vitepress", "bin", "vitepress.js");
    if (!check(existsSync(vp), "vitepress not installed: run npm install in the repository root")) throw new Error("no vitepress");
    for (const cmd of [[path.join(ROOT, "docs", ".vitepress", "prepare.mjs")], [vp, "build", "docs"]]) {
      const r = spawnSync(process.execPath, cmd, { cwd: ROOT, encoding: "utf8" });
      if (!check(r.status === 0, `docs build step failed (${cmd.join(" ")}):\n${r.stdout}\n${r.stderr}`)) throw new Error("docs build failed");
    }
    say("\ndocs site built: docs/.vitepress/dist");
  }
  siteServer = await startServer({ root: SITE, cleanUrls: true });
  say(`docs site server: ${siteServer.url}`);
  { const r = await fetch(siteServer.url + "/playground-app/vendor/bm_render.wasm"); check(r.ok && r.headers.get("content-type") === "application/wasm", "site wasm " + r.status); }
  for (const lang of ["en", "vi"]) await siteSuite(siteServer.url, lang);
  for (const lang of ["en", "vi"]) await sitePdfSuite(siteServer.url, lang);
} catch (e) {
  fail("fatal: " + (e.stack || e));
} finally {
  await browser?.close().catch(() => {});
  await server?.close(); await distServer?.close(); await siteServer?.close();
}

// ---------------------------------------------------------------------------------------------- report
const md = ["# Playground test results", "", `Run: ${new Date().toISOString()}  -  ${failures.length ? "FAILED" : "PASSED"} (${failures.length} failure(s))`, ""];
for (const [tag, R] of Object.entries(results)) {
  md.push(`## ${tag}`, "");
  if (R.info) md.push(`Binary: ${R.info.bin}; features: ${Object.entries(R.info.features).filter(([, v]) => v).map(([k]) => k).join(", ") || "none"}`, "");
  const rows = Object.entries(R.templates);
  if (rows.length) { md.push("| template | result |", "|---|---|", ...rows.map(([k, v]) => `| ${k} | ${v} |`), ""); }
  const ex = Object.entries(R.extra);
  if (ex.length) { md.push("| check | result |", "|---|---|", ...ex.map(([k, v]) => `| ${k} | ${v} |`), ""); }
}
md.push("## Screenshots", "", "- bench/out/docs-site/playground-pdf-standalone.png (1440x900, PDF mode, invoice, browser viewer)", "- docs/playground-app/screenshots/og-card-full.png (1440x900, OG card, full profile)", "- docs/playground-app/screenshots/vietnamese-full.png", "- docs/playground-app/screenshots/dark-mode-full.png", "- docs/playground-app/screenshots/mobile-full.png", "");
if (failures.length) md.push("## Failures", "", ...failures.map((f) => "- " + f.replace(/\n/g, "\n  ")), "");
writeFileSync(path.join(OUT, "PLAYGROUND.md"), md.join("\n"));
say(failures.length ? `\n${failures.length} FAILURE(S)` : "\nALL PLAYGROUND CHECKS PASSED");
process.exit(failures.length ? 1 : 0);
