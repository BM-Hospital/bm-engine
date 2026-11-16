// Page previews of the PDFs the docs link to: docs/public/pdf/examples/<name>.pdf -> docs/public/img/guide/<name>.png.
// The PDF is opened in headless Edge's built-in PDF viewer (the real file, rendered by the browser's PDF engine, not
// by bm-render), screenshotted without the toolbar and cropped to the pages; several pages appear stacked vertically.
//   node bench/browser/pdf-previews.mjs [name ...] [--pages=N] [--width=640] [--browser=<exe>]
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import puppeteer from "puppeteer-core";
import { PNG } from "pngjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SRC = path.join(ROOT, "docs", "public", "pdf", "examples");
const OUT = path.join(ROOT, "docs", "public", "img", "guide");
const argv = process.argv.slice(2);
const opt = Object.fromEntries(argv.filter((a) => a.startsWith("--")).map((a) => { const [k, v] = a.slice(2).split("="); return [k, v ?? true]; }));
const names = argv.filter((a) => !a.startsWith("--"));
const list = names.length ? names : readdirSync(SRC).filter((f) => f.endsWith(".pdf")).map((f) => f.slice(0, -4));
const WIDTH = Number(opt.width || 560); // viewport width; the page is drawn a bit narrower (viewer margins)
const exe = [opt.browser, process.env.BROWSER_PATH,
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"].filter((x) => typeof x === "string").find((p) => existsSync(p));
if (!exe) { console.error("No Chromium-based browser found"); process.exit(2); }

const latin1 = (b) => new TextDecoder("latin1").decode(b);
/** Page sizes in points, in document order. */
function pageSizes(bytes) {
  const s = latin1(bytes);
  return [...s.matchAll(/\/Type\/Page[^s][\s\S]*?\/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]/g)].map((m) => [+m[1], +m[2]]);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Bounding box of the pixels that are not the viewer's grey background. */
function crop(png) {
  const { width: w, height: h, data } = png;
  const bg = [data[0], data[1], data[2]]; // top-left pixel is viewer background
  const isBg = (i) => Math.abs(data[i] - bg[0]) < 6 && Math.abs(data[i + 1] - bg[1]) < 6 && Math.abs(data[i + 2] - bg[2]) < 6;
  let x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!isBg((y * w + x) * 4)) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  }
  if (x1 < 0) throw new Error("blank screenshot");
  const pad = 6;
  x0 = Math.max(0, x0 - pad); y0 = Math.max(0, y0 - pad); x1 = Math.min(w - 1, x1 + pad); y1 = Math.min(h - 1, y1 + pad);
  const out = new PNG({ width: x1 - x0 + 1, height: y1 - y0 + 1 });
  PNG.bitblt(png, out, x0, y0, out.width, out.height, 0, 0);
  return out;
}

/** [firstRow, lastRow] of each page shown in the screenshot (non-background runs of the centre column). */
function pageRuns(png) {
  const { width: w, height: h, data } = png;
  const x = w >> 1, bg = [data[0], data[1], data[2]];
  const runs = [];
  let start = -1;
  for (let y = 0; y <= h; y++) {
    const i = (y * w + x) * 4;
    const isBg = y === h || (Math.abs(data[i] - bg[0]) < 6 && Math.abs(data[i + 1] - bg[1]) < 6 && Math.abs(data[i + 2] - bg[2]) < 6);
    if (!isBg && start < 0) start = y;
    if (isBg && start >= 0) { runs.push([start, y - 1]); start = -1; }
  }
  return runs;
}

const browser = await puppeteer.launch({ executablePath: exe, headless: true, args: ["--no-first-run", "--no-default-browser-check", "--disable-extensions"] });
let failed = 0;
try {
  for (const name of list) {
    const file = path.join(SRC, name + ".pdf");
    const bytes = readFileSync(file);
    const sizes = pageSizes(bytes);
    const n = Math.min(sizes.length, Number(opt.pages || sizes.length));
    // The viewer fits the page width (minus its own margins); give it a viewport tall enough for n pages.
    const scale = (WIDTH - 40) / Math.max(...sizes.map((s) => s[0]));
    const height = Math.ceil(sizes.slice(0, n).reduce((a, s) => a + s[1] * scale + 14, 0) + (n < sizes.length ? 300 : 40));
    const page = await browser.newPage();
    await page.setViewport({ width: WIDTH, height: Math.min(height, 8000), deviceScaleFactor: 1 });
    const url = pathToFileURL(file).href + "#toolbar=0&view=FitH";
    await page.goto(url, { waitUntil: "load", timeout: 15000 }).catch(() => {});
    await sleep(2500);
    let shot = PNG.sync.read(Buffer.from(await page.screenshot({ type: "png" })));
    await page.close();
    // keep only the first n pages: pages are runs of non-background rows in the centre column
    const runs = pageRuns(shot);
    if (runs.length > n) {
      const cut = new PNG({ width: shot.width, height: runs[n - 1][1] + 8 });
      PNG.bitblt(shot, cut, 0, 0, shot.width, cut.height, 0, 0);
      shot = cut;
    }
    const png = crop(shot);
    const out = PNG.sync.write(png, { colorType: 2, deflateLevel: 9 });
    writeFileSync(path.join(OUT, name + ".png"), out);
    console.log(`wrote ${name}.png ${png.width}x${png.height} (${(out.length / 1024).toFixed(1)} KiB) from ${sizes.length} page(s)`);
  }
} catch (e) {
  failed++; console.error(e);
} finally {
  await browser.close();
}
process.exit(failed ? 1 : 0);
