// Layout behaviours where bm-engine follows Chrome because takumi 2.20 deviates from it (or does not
// support the feature), so they cannot be fixtures of the takumi equivalence suite:
//   * display: contents                      (takumi: declaration dropped / inline style rejected)
//   * percentage margin / padding of inline boxes and percentage margins of inline-blocks
//                                            (takumi: the percentage part is 0)
//   * text-indent of an anonymous block that is not the first child of its container
//                                            (takumi: indented; Chrome: no first formatted line)
// Each case is rendered by bm-engine (zig-out/bin/bm_engine.wasm, or $BM_WASM) and by a headless
// Chromium (Edge / Chrome, found like bench/browser/run.mjs does) with the fixture fonts, and compared
// with the suite's metrics (lib/metrics.mjs). Cases without text must be `equivalent` (SSIM >= 0.99,
// <= 0.5 % pixels) or `identical`; cases with text (`text: true`: glyph rasterisation differs between
// the engines) must be at least `close` (SSIM >= 0.95).
//
//   node probe/fix-layout/chrome-check.mjs [--filter=<regex>] [--browser=<path>] [--out=<dir>]
// Exit code 1 when a case fails, 2 when no browser was found.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";
import bm from "../../engines/bm.mjs";
import { FONTS, fontsFor } from "../../lib/fonts.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import { encodePng } from "../../lib/pipeline.mjs";

const BENCH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const outDir = path.resolve(BENCH, args.out || "out/fix-layout-chrome");

const B = (c, w = 40, h = 20, extra = "") => `<div style="width:${w}px;height:${h}px;background:${c};${extra}"></div>`;
const IB = (c, w = 30, h = 14, extra = "") => `<span style="display:inline-block;width:${w}px;height:${h}px;background:${c};${extra}"></span>`;
const base = `.page { font-family: Inter; font-size: 14px; color: #0f172a; width: 100%; height: 100%; background: #fff; padding: 10px; box-sizing: border-box }
  .row { display: flex; gap: 6px; background: #e2e8f0; margin-bottom: 6px }
  .c { display: contents }`;

/** { id, width, height, css?, body, text? } */
const CASES = [
  // ---- display: contents
  { id: "contents-flex-items", width: 360, height: 130, body: `
      <div class="row">${B("#38bdf8")}<div class="c" style="background:blue;padding:20px;border:5px solid #000;margin:30px">${B("#f97316")}${B("#22c55e", 60)}</div>${B("#a855f7")}</div>
      <div class="row" style="justify-content:space-between">${B("#38bdf8")}<div class="c"><div class="c">${B("#f97316")}</div>${B("#22c55e")}</div></div>
      <div class="row" style="flex-direction:column;align-items:flex-end;gap:2px"><div class="c">${B("#f97316", 40, 10)}${B("#22c55e", 60, 10)}</div></div>` },
  { id: "contents-grid-items", width: 360, height: 110, css: `.g { display: grid; grid-template-columns: 60px 1fr 80px; gap: 5px; background: #e2e8f0 } .g div { width: auto }`, body: `
      <div class="g">${B("#38bdf8")}<div class="c">${B("#f97316")}${B("#22c55e")}${B("#a855f7")}</div><div class="c"></div>${B("#ec4899", 40, 20, "grid-column:2 / span 2")}</div>` },
  { id: "contents-block-children", width: 360, height: 130, body: `
      <div style="background:#e2e8f0;padding:4px">${B("#38bdf8", 80, 14, "margin-bottom:8px")}<div class="c" style="margin:40px;width:10px;height:200px;overflow:hidden;position:relative">${B("#f97316", 120, 14, "margin:8px 0")}${B("#22c55e", 60, 14, "margin-top:12px")}</div>${B("#a855f7", 90, 14)}</div>` },
  { id: "contents-inline-content", width: 360, height: 110, body: `
      <div style="width:200px;background:#e2e8f0;line-height:20px">${IB("#38bdf8")} <span class="c" style="padding:0 30px;background:red;border:3px solid">${IB("#f97316")} ${IB("#22c55e", 50)}</span> ${IB("#a855f7", 60)} <div class="c">${IB("#ec4899", 70)} ${IB("#eab308")}</div></div>` },
  { id: "contents-table-parts", width: 360, height: 120, css: `.tb { display: table; border-spacing: 4px; background: #e2e8f0 } .tr { display: table-row } .td { display: table-cell; border: 2px solid #334155 }`, body: `
      <div class="tb"><div class="tr"><div class="td">${B("#38bdf8")}</div><div class="c"><div class="td">${B("#f97316", 60)}</div><div class="td">${B("#22c55e")}</div></div></div><div class="c"><div class="tr"><div class="td">${B("#a855f7")}</div><div class="c"><div class="td">${B("#ec4899")}</div></div><div class="td">${B("#eab308", 20)}</div></div></div></div>` },
  { id: "contents-inherit-pseudo", width: 360, height: 110, css: `.c::before { content: ""; display: block; width: 50px; height: 10px; background: #0f172a } .k { width: 2em; height: 1em; background: currentColor }`, body: `
      <div class="row" style="align-items:flex-start"><div class="c" style="color:#dc2626;font-size:30px"><div class="k"></div><div class="c" style="font-size:10px"><div class="k"></div></div></div>${B("#38bdf8")}</div>` },
  { id: "contents-root-image-abs", width: 360, height: 110, body: `
      <div class="row" style="position:relative;height:60px"><div class="c"><div style="position:absolute;right:4px;bottom:4px;width:30px;height:12px;background:#dc2626"></div>${B("#38bdf8")}</div><div class="c" style="order:-1">${B("#22c55e", 20)}</div>${B("#f97316", 30, 20, "order:-2")}</div>` },
  { id: "contents-text", width: 360, height: 90, text: true, body: `
      <div class="row"><div class="c" style="color:#dc2626;background:blue;padding:20px">red inherited text</div><span>second item</span></div>
      <p style="margin:0">para <span class="c" style="background:#fde047;border:2px solid;font-weight:700">bold no box</span> end</p>` },
  // ---- percentage margin / padding of inline boxes and inline-blocks
  { id: "pct-inline-box", width: 360, height: 130, css: `p { margin: 0 0 6px; width: 300px; background: #e2e8f0; line-height: 20px }`, body: `
      <p>${IB("#0f172a")}<span style="padding:0 10%;background:#fde047">${IB("#f97316")}</span>${IB("#0f172a")}<span style="margin:0 5%;background:#bae6fd">${IB("#22c55e")}</span>${IB("#0f172a")}</p>
      <p style="width:200px">${IB("#0f172a")}<span style="padding-left:20%;margin-right:10%;border:2px solid #dc2626;background:#fde047">${IB("#f97316", 60)} ${IB("#f97316", 60)} ${IB("#f97316", 60)}</span>${IB("#0f172a")}</p>
      <p dir="rtl">${IB("#0f172a")}<span style="padding-left:10%;margin-right:5%;background:#fde047;border-left:3px solid red">${IB("#22c55e", 40)}</span>${IB("#0f172a")}</p>` },
  { id: "pct-inline-block-margin", width: 360, height: 170, css: `p { margin: 0 0 6px; width: 300px; background: #e2e8f0; line-height: 20px }`, body: `
      <p>${IB("#0f172a")}${IB("#f97316", 30, 14, "margin:0 10%;padding:5%;box-sizing:content-box")}${IB("#0f172a")}</p>
      <p>${IB("#0f172a")}${IB("#22c55e", 30, 14, "margin-left:calc(5% + 4px);margin-top:10%")}${IB("#0f172a")}</p>
      <div style="display:inline-block;background:#e2e8f0">${IB("#0f172a")}<span style="padding:0 10%;background:#fde047">${IB("#f97316")}</span>${IB("#0f172a")}</div>` },
  { id: "pct-inline-text", width: 360, height: 90, text: true, css: `p { margin: 0 0 6px; width: 300px; background: #e2e8f0 }`, body: `
      <p>aa <span style="padding:0 10%;background:#fde047">pct pad</span> bb <span style="margin:0 5%;background:#bae6fd">pct margin</span> cc</p>
      <p style="width:200px">wrap <span style="padding-left:20%;margin-right:10%;border:2px solid #dc2626;background:#fde047">pct pad box that wraps over the lines</span> end</p>` },
  // ---- text-indent and anonymous blocks
  { id: "text-indent-anonymous", width: 360, height: 110, css: `.t { text-indent: 40px; width: 300px; background: #e2e8f0; line-height: 20px }`, body: `
      <div class="t">${IB("#0f172a")} ${IB("#f97316")}<div style="background:#bae6fd">${IB("#22c55e")}</div>${IB("#0f172a")} ${IB("#a855f7")}<div style="height:6px"></div>${IB("#dc2626")}</div>` },
];

// ------------------------------------------------------------------------------------------------ run
const candidates = [args.browser, process.env.BROWSER_PATH,
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
  "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"].filter((x) => x && x !== true);
const exe = candidates.find((p) => existsSync(p));
if (!exe) { console.error("no Chromium-based browser found (pass --browser=<path>)"); process.exit(2); }
if (!bm.available) { console.error("bm-engine wasm not built (zig build / node scripts/build.mjs)"); process.exit(2); }

const fontCss = FONTS.map((f) => `@font-face{font-family:"${f.name}";src:url(data:font/ttf;base64,${readFileSync(f.path).toString("base64")});font-weight:${f.weight};font-style:${f.style}}`).join("\n");
const re = new RegExp(args.filter || ".", "i");
const engine = await bm.create({ fonts: fontsFor() });
const browser = await puppeteer.launch({ executablePath: exe, headless: true, args: ["--no-first-run", "--no-default-browser-check", "--disable-extensions", "--disable-lcd-text", "--font-render-hinting=none", "--force-color-profile=srgb"] });
const page = await browser.newPage();
let failed = 0;
const rows = [];
try {
  for (const k of CASES.filter((c) => re.test(c.id))) {
    const css = `${base}\n${k.css || ""}`;
    const body = `<div class="page">${k.body}</div>`;
    const opts = { width: k.width, height: k.height, format: "raw", devicePixelRatio: 1 };
    const a = new Uint8Array(await engine.render(`<style>${css}</style>${body}`, opts));
    await page.setViewport({ width: k.width, height: k.height, deviceScaleFactor: 1 });
    await page.setContent(`<!doctype html><html><head><style>${fontCss}\nhtml,body{margin:0;padding:0;width:${k.width}px;height:${k.height}px;overflow:hidden;background:#fff}\n${css}</style></head><body>${body}</body></html>`, { waitUntil: "load" });
    await page.evaluate(() => document.fonts.ready);
    const shot = await page.screenshot({ type: "png", omitBackground: false });
    const { PNG } = await import("pngjs");
    const png = PNG.sync.read(Buffer.from(shot));
    const b = new Uint8Array(png.data.buffer, png.data.byteOffset, png.data.byteLength);
    const m = compare(b, a, k.width, k.height, { diff: true });
    const v = verdict(m);
    const ok = k.text ? v !== "different" : v === "identical" || v === "equivalent";
    if (!ok) failed++;
    const dir = path.join(outDir, k.id);
    mkdirSync(dir, { recursive: true });
    writeFileSync(path.join(dir, "bm.png"), encodePng(a, k.width, k.height));
    writeFileSync(path.join(dir, "chrome.png"), shot);
    if (m.diff) writeFileSync(path.join(dir, "diff.png"), encodePng(m.diff, k.width, k.height));
    rows.push({ id: k.id, verdict: v, ok, ssim: Math.min(m.ssim, m.ssimRgb), pct: m.pctStrict, text: !!k.text });
    console.log(`${ok ? "ok  " : "FAIL"} ${k.id.padEnd(28)} ${v.padEnd(10)} ssim ${Math.min(m.ssim, m.ssimRgb).toFixed(5)}  differing ${m.pctStrict.toFixed(3)} %${k.text ? "  (text)" : ""}`);
  }
} finally {
  await browser.close();
  engine.dispose();
}
mkdirSync(outDir, { recursive: true });
writeFileSync(path.join(outDir, "results.json"), JSON.stringify({ date: new Date().toISOString(), browser: exe, rows }, null, 1));
console.log(`${rows.length - failed}/${rows.length} cases match Chrome; images in ${outDir}`);
process.exit(failed ? 1 : 0);
