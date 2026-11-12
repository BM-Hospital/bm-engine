// Docs site smoke test (headless Edge via puppeteer-core) for the VitePress build in docs/.vitepress/dist.
//   npm run docs:build && node bench/browser/docs-site-test.mjs [--url=http://localhost:4173] [--browser=<exe>]
// Without --url it serves docs/.vitepress/dist itself (clean URLs + 404.html, like Vercel).
// Checks key pages (HTTP 200, no console / page / network errors, language switcher, search, tables, no horizontal
// overflow), clicks every sidebar link of both locales, the cross-locale language-switch fallbacks, the embedded
// playground (renders the default template, follows the site's dark mode) and saves 1440x900 screenshots to
// bench/out/docs-site/.
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";
import { startServer } from "../../docs/playground-app/serve.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SITE = path.join(ROOT, "docs", ".vitepress", "dist");
const OUT = path.join(ROOT, "bench", "out", "docs-site");
mkdirSync(OUT, { recursive: true });
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const exe = [args.browser, process.env.BROWSER_PATH,
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"].filter((x) => x && x !== true).find((p) => existsSync(p));
if (!exe) { console.error("No Chromium-based browser found"); process.exit(2); }

const failures = [];
const log = [];
const say = (s) => { console.log(s); log.push(s); };
const fail = (m) => { failures.push(m); say("FAIL: " + m); };
const check = (c, m) => { if (!c) fail(m); return !!c; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function watch(page, sink) {
  page.on("console", (m) => { if (m.type() === "error") sink.push(`console.error: ${m.text()} @ ${page.url()}`); });
  page.on("pageerror", (e) => sink.push(`pageerror: ${e.message} @ ${page.url()}`));
  page.on("requestfailed", (r) => { if (!/net::ERR_ABORTED/.test(r.failure()?.errorText || "")) sink.push(`requestfailed: ${r.url()} ${r.failure()?.errorText}`); });
  page.on("response", (r) => { if (r.status() >= 400) sink.push(`HTTP ${r.status()}: ${r.url()}`); });
}
async function pageInfo(page) {
  return page.evaluate(() => ({
    title: document.title,
    h1: document.querySelector(".vp-doc h1, .VPHero .name")?.textContent?.trim() || "",
    translations: !!document.querySelector(".VPNavBarTranslations, .VPNavBarExtra"),
    search: !!document.querySelector(".VPNavBarSearch button, #local-search button, .DocSearch-Button"),
    tables: document.querySelectorAll(".vp-doc table").length,
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    is404: !!document.querySelector(".NotFound"),
  }));
}
async function waitPlayground(page) {
  await page.waitForSelector("iframe.pg-embed-frame", { timeout: 30000 });
  const frame = await (await page.$("iframe.pg-embed-frame")).contentFrame();
  await frame.waitForFunction(() => document.body && document.body.dataset.ready === "1" && (+document.body.dataset.renders || 0) > 0, { timeout: 60000 });
  await sleep(300);
  return frame;
}

const KEY_PAGES = [
  ["/", "home-en.png", { home: true }], ["/vi/", "home-vi.png", { home: true }],
  ["/getting-started"], ["/api", "api-en.png"], ["/benchmark", null, { tables: true }],
  ["/vi/benchmark", "benchmark-vi.png", { tables: true }], ["/vi/benchmark-report", "benchmark-report-vi.png", { tables: true }],
  ["/results-full", "results-full.png", { tables: true }], ["/dev/architecture"],
  ["/playground", "playground-en.png", { playground: "en" }], ["/vi/playground", "playground-vi.png", { playground: "vi" }],
];

let browser, server;
const report = [];
try {
  let base = typeof args.url === "string" ? args.url.replace(/\/$/, "") : null;
  if (!base) {
    if (!existsSync(path.join(SITE, "index.html"))) throw new Error("docs/.vitepress/dist missing: run `npm run docs:build` first");
    server = await startServer({ root: SITE, cleanUrls: true });
    base = server.url;
  }
  say(`site: ${base}`);
  browser = await puppeteer.launch({ executablePath: exe, headless: true, args: ["--no-first-run", "--no-default-browser-check", "--disable-extensions"] });
  say(`browser: ${await browser.version()}`);

  // ---- key pages
  for (const [route, shot, opt = {}] of KEY_PAGES) {
    const sink = [];
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, sink);
    const resp = await page.goto(base + route, { waitUntil: "networkidle0" });
    const info = await pageInfo(page);
    let extra = "";
    check(resp.status() === 200 && !info.is404, `${route}: HTTP ${resp.status()} 404page=${info.is404}`);
    check(info.translations, `${route}: language switcher missing`);
    check(info.search, `${route}: search button missing`);
    check(info.overflow <= 1, `${route}: horizontal page overflow ${info.overflow}px`);
    if (opt.tables) check(info.tables > 0, `${route}: no tables rendered`);
    if (opt.home) { const n = await page.$$eval(".VPFeature", (e) => e.length); check(n >= 6, `${route}: feature cards ${n}`); extra = `${n} feature cards`; }
    if (opt.playground) {
      const frame = await waitPlayground(page);
      const s = await frame.evaluate(() => ({ status: document.body.dataset.status, w: +document.body.dataset.outW, h: +document.body.dataset.outH, lang: document.documentElement.lang, img: document.getElementById("outImg").naturalWidth, tpl: document.getElementById("template").value }));
      check(s.status === "ok" && s.img > 0 && s.lang === opt.playground, `${route}: embedded playground ${JSON.stringify(s)}`);
      const box = await page.$eval("iframe.pg-embed-frame", (f) => { const r = f.getBoundingClientRect(); return [Math.round(r.width), Math.round(r.height)]; });
      check(box[0] >= 1000 && box[1] >= 700, `${route}: iframe ${box}`);
      extra = `iframe ${box.join("x")}, template ${s.tpl} rendered ${s.w}x${s.h}, ui ${s.lang}`;
    }
    if (shot) await page.screenshot({ path: path.join(OUT, shot) });
    if (shot && opt.home) await page.screenshot({ path: path.join(OUT, shot.replace(".png", "-full.png")), fullPage: true });
    check(sink.length === 0, `${route}: browser errors:\n  ${sink.join("\n  ")}`);
    say(`  ${route}: ${resp.status()} "${info.title}" tables=${info.tables} overflow=${info.overflow} ${extra}`);
    report.push(`| ${route} | ${resp.status()} | ${info.tables} | ${info.translations ? "yes" : "NO"} | ${info.search ? "yes" : "NO"} | ${sink.length} | ${extra} |`);
    await ctx.close();
  }

  // ---- dark mode: the site toggle reaches the embedded playground (initial ?theme= and live postMessage)
  {
    const sink = [];
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, sink);
    await page.goto(base + "/playground", { waitUntil: "networkidle0" });
    const frame = await waitPlayground(page);
    const before = await frame.evaluate(() => document.documentElement.dataset.theme || "");
    await page.click(".VPNavBarAppearance button, .VPSwitchAppearance");
    await sleep(500);
    const after = await frame.evaluate(() => document.documentElement.dataset.theme || "");
    const siteDark = await page.evaluate(() => document.documentElement.classList.contains("dark"));
    check(before === "light" && after === "dark" && siteDark, `dark-mode sync: before=${before} after=${after} siteDark=${siteDark}`);
    await page.screenshot({ path: path.join(OUT, "playground-en-dark.png") });
    await page.goto(base + "/vi/benchmark-report", { waitUntil: "networkidle0" });
    await page.screenshot({ path: path.join(OUT, "benchmark-report-vi-dark.png") });
    check(sink.length === 0, `dark mode: browser errors:\n  ${sink.join("\n  ")}`);
    say(`  dark mode: playground theme ${before} -> ${after}`);
    await ctx.close();
  }

  // ---- every sidebar link of both locales, by clicking (SPA navigation) + a direct HTTP load
  for (const start of ["/getting-started", "/vi/getting-started"]) {
    const sink = [];
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, sink);
    await page.goto(base + start, { waitUntil: "networkidle0" });
    const links = await page.$$eval(".VPSidebar a.VPLink, .VPSidebar a.link", (as) => as.map((a) => a.getAttribute("href")));
    check(links.length >= 12, `${start}: only ${links.length} sidebar links`);
    let ok = 0;
    for (const href of links) {
      await page.goto(base + start, { waitUntil: "networkidle0" });
      // expand collapsed groups so every link is clickable
      await page.$$eval(".VPSidebarItem.collapsible.collapsed > .item", (els) => els.forEach((e) => e.click()));
      await sleep(100);
      const el = await page.$(`.VPSidebar a[href="${href}"]`);
      await el.click();
      await page.waitForFunction((h) => location.pathname === h || location.pathname === h + ".html", { timeout: 15000 }, href).catch(() => {});
      await sleep(250);
      const info = await pageInfo(page);
      const st = (await fetch(base + href)).status;
      if (check(st === 200 && !info.is404 && !!info.h1, `${start}: sidebar ${href}: HTTP ${st} 404page=${info.is404} h1="${info.h1}"`)) ok++;
      check(info.overflow <= 1, `${href}: horizontal overflow ${info.overflow}px`);
    }
    check(sink.length === 0, `${start} sidebar walk: browser errors:\n  ${sink.join("\n  ")}`);
    say(`  sidebar from ${start}: ${ok}/${links.length} links OK`);
    report.push(`| sidebar ${start} | ${ok}/${links.length} OK | | | | ${sink.length} | |`);
    await ctx.close();
  }

  // ---- language switcher, incl. the single-language pages (router fallback instead of a 404)
  {
    const sink = [];
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    watch(page, sink);
    for (const [from, expect] of [["/api", "/vi/api"], ["/vi/troubleshooting", "/troubleshooting"], ["/vi/benchmark-report", "/benchmark"], ["/results-full", "/results-full"], ["/dev/conventions", "/dev/conventions"]]) {
      await page.goto(base + from, { waitUntil: "networkidle0" });
      await page.hover(".VPNavBarTranslations button");
      await sleep(200);
      await page.click(".VPNavBarTranslations .VPMenu a");
      await sleep(800);
      const at = await page.evaluate(() => location.pathname.replace(/\.html$/, ""));
      const info = await pageInfo(page);
      check(at === expect && !info.is404, `language switch from ${from}: at ${at} (expected ${expect}) 404=${info.is404}`);
    }
    check(sink.length === 0, `language switcher: browser errors:\n  ${sink.join("\n  ")}`);
    say("  language switcher: checked 5 pages");
    await ctx.close();
  }

  // ---- phone width: no horizontal page overflow (wide tables scroll inside themselves)
  {
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.setViewport({ width: 390, height: 844, isMobile: true });
    for (const route of ["/", "/results-full", "/vi/benchmark-report", "/css-support", "/playground"]) {
      await page.goto(base + route, { waitUntil: "networkidle0" });
      const o = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      check(o <= 1, `${route} at 390px: horizontal overflow ${o}px`);
      if (route === "/results-full") await page.screenshot({ path: path.join(OUT, "results-full-mobile.png") });
    }
    say("  phone width (390px): overflow checked on 5 pages");
    await ctx.close();
  }

  // ---- local search finds a page
  {
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    await page.goto(base + "/", { waitUntil: "networkidle0" });
    await page.click(".VPNavBarSearch button");
    await page.waitForSelector(".VPLocalSearchBox input", { timeout: 10000 });
    await page.type(".VPLocalSearchBox input", "renderAnimation");
    await sleep(800);
    const hits = await page.$$eval(".VPLocalSearchBox .result", (r) => r.length);
    check(hits > 0, `local search: ${hits} results for renderAnimation`);
    say(`  local search: ${hits} results for "renderAnimation"`);
    await ctx.close();
  }
} catch (e) {
  fail("fatal: " + (e.stack || e));
} finally {
  await browser?.close().catch(() => {});
  await server?.close();
}

const md = ["# Docs site test", "", `Run: ${new Date().toISOString()}  -  ${failures.length ? "FAILED" : "PASSED"} (${failures.length} failure(s))`, "",
  "| page | HTTP | tables | lang switch | search | browser errors | notes |", "|---|---|--:|---|---|--:|---|", ...report, "",
  "Screenshots (1440x900): bench/out/docs-site/*.png", ""];
if (failures.length) md.push("## Failures", "", ...failures.map((f) => "- " + f.replace(/\n/g, "\n  ")), "");
writeFileSync(path.join(OUT, "DOCS_SITE.md"), md.join("\n"));
say(failures.length ? `\n${failures.length} FAILURE(S)` : "\nALL DOCS SITE CHECKS PASSED");
process.exit(failures.length ? 1 : 0);
