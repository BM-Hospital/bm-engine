// Docs site smoke test (headless Edge via puppeteer-core) for the VitePress build in docs/.vitepress/dist.
//   npm run docs:build && node bench/browser/docs-site-test.mjs [--url=http://localhost:4199] [--browser=<exe>]
// Without --url it serves docs/.vitepress/dist itself (clean URLs + 404.html, like Vercel without its redirects).
// Checks key pages (HTTP 200, no console / page / network errors, language switcher, search, tables, no horizontal
// overflow), the Image / PDF product switcher (present on product and shared pages in both locales, switching
// navigates and swaps the sidebar, the choice persists on shared pages and across a reload, keyboard operation,
// 390px drawer, dark mode, per-product accent), every sidebar link of both product sidebars in both locales, the
// redirects of old URLs (client-side layer, and vercel.json against the same table), the cross-locale
// language-switch fallbacks, the embedded playground, and saves screenshots to bench/out/docs-site/.
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";
import { startServer } from "../../docs/playground-app/serve.mjs";
import { REDIRECTS, redirectFor } from "../../docs/.vitepress/redirects.mjs";

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
  page.on("console", (m) => { if (m.type() === "error" || /hydration/i.test(m.text())) sink.push(`console.${m.type()}: ${m.text()} @ ${page.url()}`); });
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
/** State of the product switcher and the sidebar on the current page. */
async function switcherState(page) {
  return page.evaluate(() => {
    const sw = document.querySelector(".VPSidebar .bm-switcher");
    const links = [...document.querySelectorAll(".VPSidebar a.VPLink, .VPSidebar a.link")].map((a) => a.getAttribute("href"));
    return {
      present: !!sw,
      title: sw?.querySelector(".bm-switcher-button .bm-switcher-title")?.textContent?.trim() || "",
      desc: sw?.querySelector(".bm-switcher-button .bm-switcher-desc")?.textContent?.trim() || "",
      expanded: sw?.querySelector(".bm-switcher-button")?.getAttribute("aria-expanded") || "",
      listVisible: !!sw && getComputedStyle(sw.querySelector(".bm-switcher-list")).display !== "none",
      sidebarProduct: links.some((h) => /^(\/vi)?\/pdf\/pagination$/.test(h)) ? "pdf" : links.some((h) => /^(\/vi)?\/image\/styles$/.test(h)) ? "image" : "none",
      shared: links.some((h) => /^(\/vi)?\/benchmark$/.test(h)),
      layoutClass: document.querySelector(".Layout")?.className || "",
      brand: getComputedStyle(document.querySelector(".Layout") || document.body).getPropertyValue("--vp-c-brand-1").trim(),
      path: location.pathname,
    };
  });
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
  ["/getting-started"], ["/vi/getting-started"], ["/image/"], ["/pdf/"], ["/vi/pdf/"],
  ["/image/api", "api-en.png"], ["/pdf/api", "api-pdf-en.png"], ["/pdf/recipes", "pdf-recipes-en.png"], ["/vi/pdf/css-support"],
  ["/benchmark", null, { tables: true }], ["/vi/benchmark", "benchmark-vi.png", { tables: true }],
  ["/vi/benchmark-report", "benchmark-report-vi.png", { tables: true }],
  ["/results-full", "results-full.png", { tables: true }], ["/dev/architecture"],
  ["/image/playground", "playground-en.png", { playground: "en" }], ["/vi/image/playground", "playground-vi.png", { playground: "vi" }],
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
  const newPage = async (sink, viewport = { width: 1440, height: 900 }) => {
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.setViewport(viewport);
    if (sink) watch(page, sink);
    return { ctx, page };
  };

  // ---- key pages
  for (const [route, shot, opt = {}] of KEY_PAGES) {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    const resp = await page.goto(base + route, { waitUntil: "networkidle0" });
    const info = await pageInfo(page);
    let extra = "";
    check(resp.status() === 200 && !info.is404, `${route}: HTTP ${resp.status()} 404page=${info.is404}`);
    check(info.translations, `${route}: language switcher missing`);
    check(info.search, `${route}: search button missing`);
    check(info.overflow <= 1, `${route}: horizontal page overflow ${info.overflow}px`);
    if (opt.tables) check(info.tables > 0, `${route}: no tables rendered`);
    if (opt.home) {
      const n = await page.$$eval(".VPFeature", (e) => e.length);
      const cards = await page.$$eval(".bm-product-card a.bm-product-head", (a) => a.map((x) => x.getAttribute("href")));
      const vi = route.startsWith("/vi");
      check(n >= 6, `${route}: feature cards ${n}`);
      check(cards.join() === (vi ? "/vi/image/,/vi/pdf/" : "/image/,/pdf/"), `${route}: product cards ${cards}`);
      extra = `${n} feature cards, product cards ${cards.join(" ")}`;
    }
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

  // ---- product switcher: present on product and shared pages, both locales; the right product and sidebar
  {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    const cases = [
      ["/image/fonts", "Image", "image", "switcher-image-en.png"], ["/pdf/pagination", "PDF", "pdf", "switcher-pdf-en.png"],
      ["/benchmark", "Image", "image"], ["/dev/architecture", "Image", "image"],
      ["/vi/image/fonts", "Ảnh", "image", "switcher-image-vi.png"], ["/vi/pdf/pagination", "PDF", "pdf", "switcher-pdf-vi.png"],
      ["/vi/troubleshooting", "Ảnh", "image"],
    ];
    for (const [route, title, product, shot] of cases) {
      // a fresh profile per case: nothing remembered, so shared pages show the default (Image)
      await page.evaluate(() => { try { localStorage.clear(); } catch {} }).catch(() => {});
      await page.goto(base + route, { waitUntil: "networkidle0" });
      await page.evaluate(() => { try { localStorage.clear(); } catch {} });
      await page.reload({ waitUntil: "networkidle0" });
      const s = await switcherState(page);
      check(s.present && s.title === title && s.sidebarProduct === product && s.shared && s.expanded === "false" && !s.listVisible,
        `switcher on ${route}: ${JSON.stringify(s)}`);
      check(/pdf/.test(product) ? /product-pdf/.test(s.layoutClass) && s.brand.toLowerCase() === "#be123c" : !/product-pdf/.test(s.layoutClass) && s.brand.toLowerCase() === "#008046",
        `accent on ${route}: class "${s.layoutClass}" brand ${s.brand}`);
      if (shot) await page.screenshot({ path: path.join(OUT, shot) });
    }
    check(sink.length === 0, `switcher presence: browser errors:\n  ${sink.join("\n  ")}`);
    say(`  switcher: present with the right product, sidebar and accent on ${cases.length} pages (EN + VI, product + shared)`);
    await ctx.close();
  }

  // ---- switching by mouse: navigates to the counterpart page and swaps the sidebar; persists on shared pages
  {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    await page.goto(base + "/image/fonts", { waitUntil: "networkidle0" });
    await page.click(".VPSidebar .bm-switcher-button");
    await sleep(200);
    let s = await switcherState(page);
    const opts = await page.$$eval(".VPSidebar .bm-switcher-list [role=option]", (o) => o.map((x) => [x.querySelector(".bm-switcher-title").textContent.trim(), x.getAttribute("aria-selected")]));
    check(s.expanded === "true" && s.listVisible && JSON.stringify(opts) === JSON.stringify([["Image", "true"], ["PDF", "false"]]), `open menu: ${JSON.stringify({ s, opts })}`);
    // the open list must not be covered by the nav bar or clipped by the sidebar
    const cover = await page.evaluate(() => {
      const el = document.querySelector(".VPSidebar .bm-switcher-list [role=option]:last-child");
      const r = el.getBoundingClientRect();
      const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return el.contains(top);
    });
    check(cover, "open menu: the PDF option is covered by another element");
    await page.screenshot({ path: path.join(OUT, "switcher-open-en.png") });
    await Promise.all([page.waitForFunction(() => location.pathname === "/pdf/fonts", { timeout: 10000 }).catch(() => {}),
      page.click(".VPSidebar .bm-switcher-list [role=option]:last-child")]);
    await sleep(600);
    s = await switcherState(page);
    check(s.path === "/pdf/fonts" && s.title === "PDF" && s.sidebarProduct === "pdf" && !s.listVisible && /product-pdf/.test(s.layoutClass), `after choosing PDF on /image/fonts: ${JSON.stringify(s)}`);
    // counterparts and fallbacks
    for (const [from, to] of [["/pdf/api", "/image/api"], ["/image/frameworks/nextjs", "/pdf/frameworks"], ["/pdf/frameworks", "/image/frameworks/"], ["/pdf/pagination", "/image/"], ["/vi/image/recipes", "/vi/pdf/recipes"]]) {
      await page.goto(base + from, { waitUntil: "networkidle0" });
      await page.click(".VPSidebar .bm-switcher-button");
      await sleep(150);
      const other = from.includes("/pdf/") ? 0 : 1;
      await page.click(`.VPSidebar .bm-switcher-list [role=option]:nth-child(${other + 1})`);
      await page.waitForFunction((t) => location.pathname === t, { timeout: 10000 }, to).catch(() => {});
      await sleep(300);
      const at = await page.evaluate(() => location.pathname);
      const info = await pageInfo(page);
      check(at === to && !info.is404, `switch from ${from}: at ${at}, expected ${to} (404=${info.is404})`);
    }
    // choose PDF, then follow the sidebar to a shared page: it keeps the PDF sidebar; also after a reload
    await page.goto(base + "/pdf/pagination", { waitUntil: "networkidle0" });
    await page.click('.VPSidebar a[href="/benchmark"]');
    await page.waitForFunction(() => location.pathname === "/benchmark", { timeout: 10000 }).catch(() => {});
    await sleep(500);
    s = await switcherState(page);
    check(s.path === "/benchmark" && s.title === "PDF" && s.sidebarProduct === "pdf" && s.shared, `shared page after PDF (SPA): ${JSON.stringify(s)}`);
    await page.reload({ waitUntil: "networkidle0" });
    await sleep(300);
    s = await switcherState(page);
    check(s.title === "PDF" && s.sidebarProduct === "pdf", `shared page after a reload: ${JSON.stringify(s)}`);
    const stored = await page.evaluate(() => localStorage.getItem("bm-docs-product"));
    check(stored === "pdf", `localStorage bm-docs-product = ${stored}`);
    // choosing Image on a shared page goes to the Image index and is remembered too
    await page.click(".VPSidebar .bm-switcher-button");
    await sleep(150);
    await page.click(".VPSidebar .bm-switcher-list [role=option]:first-child");
    await page.waitForFunction(() => location.pathname === "/image/", { timeout: 10000 }).catch(() => {});
    await page.goto(base + "/troubleshooting", { waitUntil: "networkidle0" });
    s = await switcherState(page);
    check(s.title === "Image" && s.sidebarProduct === "image", `shared page after choosing Image: ${JSON.stringify(s)}`);
    // Vietnamese shared page after choosing PDF
    await page.goto(base + "/vi/image/fonts", { waitUntil: "networkidle0" });
    await page.click(".VPSidebar .bm-switcher-button");
    await sleep(150);
    await page.click(".VPSidebar .bm-switcher-list [role=option]:last-child");
    await page.waitForFunction(() => location.pathname === "/vi/pdf/fonts", { timeout: 10000 }).catch(() => {});
    await page.goto(base + "/vi/benchmark", { waitUntil: "networkidle0" });
    await sleep(300);
    s = await switcherState(page);
    check(s.path === "/vi/benchmark" && s.title === "PDF" && s.desc === "Tài liệu phân trang" && s.sidebarProduct === "pdf", `/vi/benchmark after choosing PDF: ${JSON.stringify(s)}`);
    await page.screenshot({ path: path.join(OUT, "switcher-shared-vi.png") });
    check(sink.length === 0, `switching: browser errors:\n  ${sink.join("\n  ")}`);
    say("  switcher: mouse selection, 5 counterpart routes, persistence on shared pages (SPA, reload, VI)");
    await ctx.close();
  }

  // ---- keyboard
  {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    await page.goto(base + "/image/api", { waitUntil: "networkidle0" });
    await page.focus(".VPSidebar .bm-switcher-button");
    await page.keyboard.press("Enter");
    await sleep(150);
    let st = await page.evaluate(() => ({ focus: document.activeElement?.getAttribute("role"), active: document.activeElement?.getAttribute("aria-activedescendant"), expanded: document.querySelector(".bm-switcher-button").getAttribute("aria-expanded") }));
    check(st.focus === "listbox" && st.active === "bm-product-switcher-image" && st.expanded === "true", `keyboard Enter opens: ${JSON.stringify(st)}`);
    await page.keyboard.press("Escape");
    await sleep(100);
    st = await page.evaluate(() => ({ focusButton: document.activeElement?.classList.contains("bm-switcher-button"), expanded: document.querySelector(".bm-switcher-button").getAttribute("aria-expanded") }));
    check(st.focusButton && st.expanded === "false", `keyboard Escape closes and refocuses the button: ${JSON.stringify(st)}`);
    const ring = await page.evaluate(() => { const b = document.querySelector(".bm-switcher-button"); const cs = getComputedStyle(b); return cs.outlineStyle !== "none" && parseFloat(cs.outlineWidth) >= 1; });
    check(ring, "keyboard focus: no visible focus ring on the switcher button");
    await page.keyboard.press(" ");
    await sleep(100);
    await page.keyboard.press("ArrowDown");
    st = await page.evaluate(() => document.activeElement?.getAttribute("aria-activedescendant"));
    check(st === "bm-product-switcher-pdf", `ArrowDown moves to PDF: ${st}`);
    await page.keyboard.press("Enter");
    await page.waitForFunction(() => location.pathname === "/pdf/api", { timeout: 10000 }).catch(() => {});
    const at = await page.evaluate(() => location.pathname);
    check(at === "/pdf/api", `keyboard selection navigates: at ${at}`);
    check(sink.length === 0, `keyboard: browser errors:\n  ${sink.join("\n  ")}`);
    say("  switcher: keyboard (Enter / Space open, arrows, Escape, focus ring, Enter selects)");
    await ctx.close();
  }

  // ---- dark mode: PDF accent
  {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    await page.evaluateOnNewDocument(() => { try { localStorage.setItem("vitepress-theme-appearance", "dark"); } catch {} });
    await page.goto(base + "/pdf/pagination", { waitUntil: "networkidle0" });
    const s = await switcherState(page);
    const dark = await page.evaluate(() => document.documentElement.classList.contains("dark"));
    check(dark && s.brand.toLowerCase() === "#fb7185" && s.title === "PDF", `dark PDF page: dark=${dark} ${JSON.stringify(s)}`);
    await page.click(".VPSidebar .bm-switcher-button");
    await sleep(200);
    await page.screenshot({ path: path.join(OUT, "switcher-pdf-dark.png") });
    check(sink.length === 0, `dark: browser errors:\n  ${sink.join("\n  ")}`);
    say(`  switcher: dark mode accent ${s.brand}`);
    await ctx.close();
  }

  // ---- phone width: the switcher sits at the top of the sidebar drawer; choosing closes the drawer
  {
    const sink = [];
    const { ctx, page } = await newPage(sink, { width: 390, height: 844, isMobile: true, hasTouch: true });
    await page.goto(base + "/pdf/pagination", { waitUntil: "networkidle0" });
    await page.click(".VPLocalNav .menu");
    await sleep(600);
    const st = await page.evaluate(() => {
      const sb = document.querySelector(".VPSidebar");
      const sw = sb.querySelector(".bm-switcher");
      const r = sw.getBoundingClientRect();
      const group = sb.querySelector(".VPSidebarItem").getBoundingClientRect();
      return { open: sb.classList.contains("open"), first: r.bottom <= group.top, left: r.left, right: r.right, width: innerWidth };
    });
    check(st.open && st.first && st.left >= 0 && st.right <= st.width, `mobile drawer: ${JSON.stringify(st)}`);
    await page.screenshot({ path: path.join(OUT, "switcher-mobile.png") });
    await page.click(".VPSidebar .bm-switcher-button");
    await sleep(200);
    await page.click(".VPSidebar .bm-switcher-list [role=option]:first-child");
    await page.waitForFunction(() => location.pathname === "/image/", { timeout: 10000 }).catch(() => {});
    await sleep(700);
    const after = await page.evaluate(() => ({ path: location.pathname, open: document.querySelector(".VPSidebar").classList.contains("open") }));
    check(after.path === "/image/" && !after.open, `mobile: choosing Image: ${JSON.stringify(after)}`);
    for (const route of ["/", "/results-full", "/vi/benchmark-report", "/image/css-support", "/pdf/css-support", "/image/playground", "/vi/pdf/recipes"]) {
      await page.goto(base + route, { waitUntil: "networkidle0" });
      const o = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      check(o <= 1, `${route} at 390px: horizontal overflow ${o}px`);
      if (route === "/results-full") await page.screenshot({ path: path.join(OUT, "results-full-mobile.png") });
    }
    check(sink.length === 0, `mobile: browser errors:\n  ${sink.join("\n  ")}`);
    say("  phone width (390px): drawer switcher, selection closes the drawer, overflow checked on 7 pages");
    await ctx.close();
  }

  // ---- dark mode: the site toggle reaches the embedded playground (initial ?theme= and live postMessage)
  {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    await page.goto(base + "/image/playground", { waitUntil: "networkidle0" });
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

  // ---- every sidebar link of both product sidebars, both locales: click (SPA navigation) + a direct HTTP load
  for (const start of ["/image/", "/pdf/", "/vi/image/", "/vi/pdf/"]) {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    await page.goto(base + start, { waitUntil: "networkidle0" });
    const links = await page.$$eval(".VPSidebar a.VPLink, .VPSidebar a.link", (as) => as.map((a) => a.getAttribute("href")));
    check(links.length >= 20, `${start}: only ${links.length} sidebar links`);
    let ok = 0;
    for (const href of links) {
      await page.goto(base + start, { waitUntil: "networkidle0" });
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
      // a shared page reached from this product's sidebar keeps this product's sidebar
      const s = await switcherState(page);
      const want = start.includes("/pdf/") ? "pdf" : "image";
      // (the playground page has no sidebar at all: full width)
      check(s.sidebarProduct === want || (!s.present && /playground$/.test(href)), `${start}: on ${href} the sidebar is ${s.sidebarProduct}, expected ${want}`);
    }
    check(sink.length === 0, `${start} sidebar walk: browser errors:\n  ${sink.join("\n  ")}`);
    say(`  sidebar from ${start}: ${ok}/${links.length} links OK`);
    report.push(`| sidebar ${start} | ${ok}/${links.length} OK | | | | ${sink.length} | |`);
    await ctx.close();
  }

  // ---- old URLs: client-side redirects (direct load and SPA navigation), #anchors kept
  {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    const OLD = [
      ["/fonts", "/image/fonts", ""], ["/api#renderer", "/image/api", "#renderer"], ["/vi/css-support", "/vi/image/css-support", ""],
      ["/frameworks/", "/image/frameworks/", ""], ["/frameworks/nextjs", "/image/frameworks/nextjs", ""],
      ["/vi/migration/from-takumi", "/vi/image/migration/from-takumi", ""], ["/pdf-pagination#tables", "/pdf/pagination", "#tables"],
      ["/vi/pdf-fonts", "/vi/pdf/fonts", ""], ["/pdf", "/pdf/", ""], ["/playground", "/image/playground", ""],
      ["/getting-started#fonts", "/image/", "#fonts"], ["/vi/getting-started#font", "/vi/image/", "#font"],
    ];
    let ok = 0;
    for (const [from, to, hash] of OLD) {
      await page.goto(base + from, { waitUntil: "networkidle0" }).catch(() => {});
      await page.waitForFunction((t) => location.pathname === t, { timeout: 10000 }, to).catch(() => {});
      await sleep(300);
      const at = await page.evaluate(() => ({ path: location.pathname, hash: decodeURIComponent(location.hash), is404: !!document.querySelector(".NotFound"), target: location.hash ? !!document.getElementById(decodeURIComponent(location.hash.slice(1))) : true }));
      if (check(at.path === to && at.hash === hash && !at.is404 && at.target, `old URL ${from}: ${JSON.stringify(at)} expected ${to}${hash}`)) ok++;
    }
    // SPA navigation to an old URL (a link in a page written before the move)
    await page.goto(base + "/benchmark", { waitUntil: "networkidle0" });
    await page.evaluate(() => { const a = document.createElement("a"); a.href = "/pdf-headers-footers#a-header"; a.id = "old-link"; a.textContent = "old"; document.querySelector(".vp-doc").prepend(a); });
    await page.click("#old-link");
    await page.waitForFunction(() => location.pathname === "/pdf/headers-footers", { timeout: 10000 }).catch(() => {});
    await sleep(400);
    const spa = await page.evaluate(() => location.pathname + location.hash);
    if (check(spa === "/pdf/headers-footers#a-header", `SPA link to an old URL: at ${spa}`)) ok++;
    // the 404 answers of the static server are expected here (that is how old URLs reach the client)
    const unexpected = sink.filter((e) => !/HTTP 404|status of 404/.test(e));
    check(unexpected.length === 0, `old URLs: browser errors:\n  ${unexpected.join("\n  ")}`);
    say(`  old URLs (client-side layer): ${ok}/${OLD.length + 1} land on the right page and anchor`);
    report.push(`| old URLs (client) | ${ok}/${OLD.length + 1} OK | | | | ${unexpected.length} | |`);
    await ctx.close();
  }

  // ---- vercel.json: the server-side redirects agree with redirects.mjs, and no current page is redirected
  {
    const vercel = JSON.parse(readFileSync(path.join(ROOT, "vercel.json"), "utf8"));
    const rules = vercel.redirects.map((r) => {
      const names = [];
      const re = "^" + r.source.replace(/:(\w+)(\([^)]*\))?(\*)?/g, (_m, n, alt, star) => { names.push(n); return star ? "(.*)" : alt ?? "([^/]+)"; }).replace(/\/\(\.\*\)$/, "(?:/(.*))?") + "/?$";
      return { r, re: new RegExp(re), names };
    });
    const apply = (p) => {
      for (const { r, re, names } of rules) {
        const m = re.exec(p);
        if (!m) continue;
        let d = r.destination;
        names.forEach((n, i) => { d = d.replace(new RegExp(":" + n + "\\*?"), m[i + 1] ?? ""); });
        return d;
      }
      return null;
    };
    const norm = (p) => (p.length > 1 ? p.replace(/\/$/, "") : p);
    let agree = 0, total = 0;
    const olds = Object.keys(REDIRECTS).filter((p) => !/\/(pdf|image)$/.test(p)).concat(["/frameworks/", "/frameworks/nextjs", "/vi/migration/from-satori", "/vi/frameworks/sveltekit"]);
    for (const p of olds) { total++; const v = apply(p); if (check(v && norm(v) === norm(redirectFor(p)), `vercel.json: ${p} -> ${v}, redirects.mjs says ${redirectFor(p)}`)) agree++; }
    const routes = [];
    const walk = (rel) => {
      for (const f of readdirSync(path.join(SITE, rel), { withFileTypes: true })) {
        const r = rel ? rel + "/" + f.name : f.name;
        if (f.isDirectory()) { if (!["assets", "playground-app", "img", "data", "pdf/examples"].includes(r)) walk(r); }
        else if (f.name.endsWith(".html") && r !== "404.html") routes.push("/" + r.replace(/(^|\/)index\.html$/, "$1").replace(/\.html$/, ""));
      }
    };
    walk("");
    let loops = 0;
    for (const r of routes) if (apply(r)) { loops++; fail(`vercel.json redirects a current page: ${r} -> ${apply(r)}`); }
    say(`  vercel.json: ${agree}/${total} old URLs redirect to the same place as redirects.mjs; ${routes.length} current routes, ${loops} redirected`);
    report.push(`| vercel.json redirects | ${agree}/${total} agree, ${loops} current routes redirected | | | | | |`);
  }

  // ---- language switcher, incl. the single-language pages (router fallback instead of a 404)
  {
    const sink = [];
    const { ctx, page } = await newPage(sink);
    for (const [from, expect] of [["/image/api", "/vi/image/api"], ["/pdf/pagination", "/vi/pdf/pagination"], ["/vi/troubleshooting", "/troubleshooting"], ["/vi/benchmark-report", "/benchmark"], ["/results-full", "/results-full"], ["/dev/conventions", "/dev/conventions"]]) {
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
    say("  language switcher: checked 6 pages");
    await ctx.close();
  }

  // ---- local search finds pages and names their product
  {
    const { ctx, page } = await newPage(null);
    await page.goto(base + "/", { waitUntil: "networkidle0" });
    for (const [q, want] of [["renderAnimation", "Image ›"], ["PdfRenderer", "PDF ›"]]) {
      await page.click(".VPNavBarSearch button");
      await page.waitForSelector(".VPLocalSearchBox input", { timeout: 10000 });
      await page.$eval(".VPLocalSearchBox input", (i) => { i.value = ""; });
      await page.type(".VPLocalSearchBox input", q);
      await sleep(900);
      const hits = await page.$$eval(".VPLocalSearchBox .result", (r) => r.map((x) => x.textContent.replace(/\s+/g, " ")));
      check(hits.length > 0 && hits.some((h) => h.includes(want)), `local search "${q}": ${hits.length} results, none with "${want}"`);
      say(`  local search: ${hits.length} results for "${q}" (product shown: ${hits.some((h) => h.includes(want))})`);
      await page.keyboard.press("Escape");
      await sleep(200);
    }
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
  "Screenshots: bench/out/docs-site/*.png (1440x900; switcher-mobile.png 390x844)", ""];
if (failures.length) md.push("## Failures", "", ...failures.map((f) => "- " + f.replace(/\n/g, "\n  ")), "");
writeFileSync(path.join(OUT, "DOCS_SITE.md"), md.join("\n"));
say(failures.length ? `\n${failures.length} FAILURE(S)` : "\nALL DOCS SITE CHECKS PASSED");
process.exit(failures.length ? 1 : 0);
