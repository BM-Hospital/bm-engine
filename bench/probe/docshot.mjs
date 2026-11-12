import puppeteer from "puppeteer-core";
import { existsSync, mkdirSync } from "node:fs";
const exe = ["C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "C:/Program Files/Microsoft/Edge/Application/msedge.exe"].find(existsSync);
const b = await puppeteer.launch({ executablePath: exe, headless: true });
const p = await b.newPage(); await p.setViewport({ width: 1440, height: 900 });
const errs = []; p.on("pageerror", (e) => errs.push(String(e))); p.on("console", (m) => m.type() === "error" && errs.push(m.text()));
mkdirSync("out/docs", { recursive: true });
for (const [u, f] of [["/", "home-vi"], ["/docs/BENCHMARK.md", "benchmark"]]) {
  const r = await p.goto("http://127.0.0.1:4173" + u, { waitUntil: "load" });
  await p.screenshot({ path: `out/docs/${f}.png` });
  console.log(u, r.status(), await p.evaluate(() => document.querySelectorAll("table").length + " tables, " + document.querySelectorAll("nav a").length + " nav links"));
}
// every nav link must resolve
const links = await p.evaluate(() => [...document.querySelectorAll("nav a")].map((a) => a.getAttribute("href")));
for (const l of links) { const r = await fetch("http://127.0.0.1:4173" + l); if (r.status !== 200) errs.push(l + " -> " + r.status); }
console.log("nav links checked:", links.length, "errors:", errs.length, errs.slice(0, 5));
await b.close();
