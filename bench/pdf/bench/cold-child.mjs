// Cold-start probe, one fresh process per run (spawned by bench/pdf/bench.mjs).
//
//   node bench/pdf/bench/cold-child.mjs <bm|takumi-pdf|none> <font.ttf> <doc.html>
//
// The font and the document are read before the clock starts (for "none" too). Then: import the engine the way a
// user does (`bm-engine/pdf` = js/node-pdf.mjs, whose backend follows BM_ENGINE_BACKEND; `takumi-pdf`) -> register
// one font -> render a one-page A4 invoice -> print one JSON line -> exit. The parent times spawn-to-exit.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const [engine, fontPath, docPath] = process.argv.slice(2);
const font = new Uint8Array(readFileSync(fontPath));
const html = readFileSync(docPath, "utf8");
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const t0 = performance.now();
let backend = engine, out = { length: 0 }, t1 = t0, t2 = t0;
if (engine !== "none") {
  let r;
  if (engine === "bm") {
    const m = await import(pathToFileURL(path.join(ROOT, "js", "node-pdf.mjs")).href);
    backend = "bm-" + m.backend;
    r = new m.PdfRenderer();
  } else if (engine === "takumi-pdf") {
    const m = await import(pathToFileURL(path.join(ROOT, "bench", "pdf", "node_modules", "takumi-pdf", "bundlers", "node.mjs")).href);
    r = new m.PdfRenderer();
  } else throw new Error("unknown engine " + engine);
  t1 = performance.now();
  await r.registerFont({ name: "Inter", data: font, weight: 400, style: "normal" });
  t2 = performance.now();
  out = await r.render(html, { size: "a4", margin: 48 });
}
const t3 = performance.now();
const c = process.cpuUsage();
console.log(JSON.stringify({ backend, importMs: t1 - t0, fontMs: t2 - t1, renderMs: t3 - t2, totalMs: t3 - t0, bytes: out.length, cpuMs: (c.user + c.system) / 1000, maxRssMiB: +(process.resourceUsage().maxRSS / 1024).toFixed(1) }));
process.exit(0);
