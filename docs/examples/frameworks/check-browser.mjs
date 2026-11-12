// Verifies the Web Worker recipe (recipes.md, vite-browser.md) in a real headless Chromium-based browser:
// browser/index.html starts a module Worker that runs `await init()` from bm-engine/standard (no bundler),
// renders at devicePixelRatio, transfers the PNG, and the page shows it via a blob URL and createImageBitmap.
// Needs puppeteer-core (repo: bench/node_modules) and Edge / Chrome (BROWSER_PATH); otherwise SKIPPED.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { check, done, FONTS } from "./lib/util.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const pkgJs = path.dirname(fileURLToPath(import.meta.resolve("bm-engine/standard")));
const repo = process.env.BM_REPO || path.resolve(here, "..", "..", "..");
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".wasm": "application/wasm", ".ttf": "font/ttf" };

async function loadPuppeteer() {
  try { return (await import("puppeteer-core")).default; } catch {}
  const p = path.join(repo, "bench", "package.json");
  if (!existsSync(p)) return null;
  try { return (await import(pathToFileURL(createRequire(p).resolve("puppeteer-core")).href)).default; } catch { return null; }
}

await check("module Web Worker renders, page shows it via blob URL + createImageBitmap", async () => {
  const puppeteer = await loadPuppeteer();
  const exe = [process.env.BROWSER_PATH, "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "/usr/bin/google-chrome", "/usr/bin/chromium"].find((p) => p && existsSync(p));
  if (!puppeteer || !exe) return `SKIPPED: ${!puppeteer ? "puppeteer-core" : "browser"} not found`;
  const server = createServer((req, res) => {
    const u = decodeURIComponent(new URL(req.url, "http://x").pathname);
    let file;
    if (u.startsWith("/node_modules/bm-engine/js/")) file = path.join(pkgJs, u.slice("/node_modules/bm-engine/js/".length));
    else if (u.startsWith("/fonts/")) file = fileURLToPath(new URL(u.slice(7), FONTS));
    else file = path.join(here, "browser", u === "/" ? "index.html" : u);
    if (!existsSync(file)) return res.writeHead(404).end();
    res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream" }).end(readFileSync(file));
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const browser = await puppeteer.launch({ executablePath: exe, headless: true, args: ["--no-sandbox"] });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 800, height: 600, deviceScaleFactor: 2 });
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.waitForFunction(() => document.body.dataset.result, { timeout: 30000 });
    const result = JSON.parse(await page.evaluate(() => document.body.dataset.result));
    assert.ok(result.ok, result.error);
    assert.equal(result.dpr, 2);
    assert.deepEqual(result.natural, [1200, 630]);
    assert.deepEqual(result.bitmap, [1200, 630]);
    assert.ok(result.px[3] === 255 && result.px[0] > 200, `orange-ish corner pixel ${result.px}`);
    assert.deepEqual(errors, []);
    return `${await browser.version()}, dpr 2 -> 1200x630 PNG`;
  } finally { await browser.close(); server.close(); }
});
done();
