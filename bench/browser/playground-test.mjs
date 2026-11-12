// Playground end-to-end test (headless Edge via puppeteer-core).
//   node bench/browser/playground-test.mjs [--browser=<exe>] [--skip-docs-build]
// 1. Serves the repo root (dev layout, docs/playground-app/), exercises every profile (core / standard / full).
// 2. Builds and smoke-tests the self-contained build (docs/playground-app/dist).
// 3. Builds the VitePress docs site (npm run docs:build equivalent; --skip-docs-build reuses docs/.vitepress/dist) and
//    checks the /playground and /vi/playground pages: the embedded app starts on every profile and renders the OG card.
import { existsSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync, mkdtempSync } from "node:fs";
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
mkdirSync(SHOTS, { recursive: true }); mkdirSync(OUT, { recursive: true });
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
    page = await openPage(ctx, base, `?profile=${profile}`, sink, tag);
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
      const ok = !!d && d.name === (fmt === "png" ? "bm-engine.png" : "bm-engine.svg") && (fmt === "png" ? d.head[1] === 80 && d.head[2] === 78 && d.head[3] === 71 : /<svg/.test(d.text));
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
  const route = lang === "vi" ? "/vi/playground" : "/playground";
  const tag = `site${route}`;
  const sink = [];
  const R = { templates: {}, extra: {} };
  results[tag] = R;
  const ctx = await browser.createBrowserContext();
  try {
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, tag, sink);
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
  { const r = await fetch(server.url + "/js/bm_engine.wasm"); check(r.headers.get("content-type") === "application/wasm", "wasm content-type " + r.headers.get("content-type"));
    const t = await fetch(server.url + "/docs/playground-app/..%2f..%2f..%2fpackage.json").catch(() => null); check(!t || t.status >= 400, "directory traversal not blocked"); }

  for (const profile of ["core", "standard", "full"]) await suite(() => browser.createBrowserContext(), base, profile);
  await shots(base);

  // ---- dist build
  const b = spawnSync(process.execPath, [path.join(PG, "build.mjs")], { encoding: "utf8" });
  say("\n" + (b.stdout || "").trim());
  if (!check(b.status === 0, "build.mjs failed: " + b.stderr)) throw new Error("build failed");
  distServer = await startServer({ root: path.join(PG, "dist") });
  say(`dist server: ${distServer.url}`);
  { const r = await fetch(distServer.url + "/vendor/bm_engine.core.wasm"); check(r.headers.get("content-type") === "application/wasm", "dist wasm type"); }
  for (const profile of ["core", "standard", "full"]) await suite(() => browser.createBrowserContext(), distServer.url + "/", profile, { dist: true });

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
  { const r = await fetch(siteServer.url + "/playground-app/vendor/bm_engine.wasm"); check(r.ok && r.headers.get("content-type") === "application/wasm", "site wasm " + r.status); }
  for (const lang of ["en", "vi"]) await siteSuite(siteServer.url, lang);
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
md.push("## Screenshots", "", "- docs/playground-app/screenshots/og-card-full.png (1440x900, OG card, full profile)", "- docs/playground-app/screenshots/vietnamese-full.png", "- docs/playground-app/screenshots/dark-mode-full.png", "- docs/playground-app/screenshots/mobile-full.png", "");
if (failures.length) md.push("## Failures", "", ...failures.map((f) => "- " + f.replace(/\n/g, "\n  ")), "");
writeFileSync(path.join(OUT, "PLAYGROUND.md"), md.join("\n"));
say(failures.length ? `\n${failures.length} FAILURE(S)` : "\nALL PLAYGROUND CHECKS PASSED");
process.exit(failures.length ? 1 : 0);
