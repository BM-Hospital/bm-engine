// Compares the SVG module (wasm harness, see harness.zig) with the takumi oracle.
// usage (from bench/): node probe/svg/oracle.mjs <svg_harness.wasm> [filter] [--dump dir] [--l16] [--gen N]
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";
import { compare, verdict } from "../../lib/metrics.mjs";
import { CASES } from "./cases.mjs";

const args = process.argv.slice(2);
const wasmPath = args[0];
const filter = args[1] && !args[1].startsWith("--") ? args[1] : "";
const opt = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const dump = opt("--dump");
const nGen = Number(opt("--gen") ?? 0);
const l16 = args.includes("--l16") ? 1 : 0;
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {});
const ex = instance.exports;
const tk = new Renderer();
const enc = new TextEncoder();

function mine(svg, w, h) {
  const bytes = enc.encode(svg);
  const p = ex.buf_alloc(bytes.length);
  new Uint8Array(ex.memory.buffer, p, bytes.length).set(bytes);
  const t0 = performance.now();
  const out = ex.render(p, bytes.length, w, h, l16, 0, 0, w, h);
  const ms = performance.now() - t0;
  ex.buf_free(p, bytes.length);
  if (!out) return null;
  return { px: new Uint8Array(ex.memory.buffer, out, w * h * 4).slice(), ms };
}
async function oracle(svg, w, h) {
  const t0 = performance.now();
  const px = new Uint8Array(await tk.render({ type: "image", src: svg, style: { width: w, height: h } }, { width: w, height: h, format: "raw" }));
  return { px, ms: performance.now() - t0 };
}

const td = "../src/svg/testdata/";
const list = [];
for (const f of readdirSync(td).filter((f) => f.endsWith(".svg"))) list.push({ name: f, svg: readFileSync(td + f, "utf8") });
for (const c of CASES) list.push(c);
if (nGen > 0) {
  const gen = "../ref/takumi/takumi/tests/fixtures-generated/";
  const files = readdirSync(gen).filter((f) => f.endsWith(".svg")).sort();
  const step = Math.max(1, Math.floor(files.length / nGen));
  for (let i = 0; i < files.length && list.length < CASES.length + 16 + nGen; i += step) {
    list.push({ name: "gen/" + files[i].replace(".svg", ""), svg: readFileSync(gen + files[i], "utf8"), w: 600, h: 315 });
  }
}

if (dump) mkdirSync(dump, { recursive: true });
console.log("name".padEnd(40), "size".padEnd(8), "SSIM    ssimRGB  %diff   meanAbs  max  verdict      ms(tk/ours)");
const rows = [];
for (const c of list) {
  if (filter && !c.name.includes(filter)) continue;
  const w = c.w ?? 256, h = c.h ?? 256;
  const a = await oracle(c.svg, w, h);
  const b = mine(c.svg, w, h);
  if (!b) { console.log(c.name.padEnd(40), "OURS FAILED"); continue; }
  const m = compare(a.px, b.px, w, h);
  rows.push({ name: c.name, m });
  console.log(c.name.padEnd(40), `${w}x${h}`.padEnd(8), m.ssim.toFixed(4), "", m.ssimRgb.toFixed(4), "", m.pctStrict.toFixed(2).padStart(6), "  ", m.meanAbs.toFixed(3).padStart(6), "", String(m.maxAbs).padStart(4), "", verdict(m).padEnd(12), `${a.ms.toFixed(1)}/${b.ms.toFixed(1)}`);
  if (dump) {
    const base = `${dump}/${c.name.replace(/[\/]/g, "_")}`;
    writeFileSync(`${base}.tk.rgba`, a.px);
    writeFileSync(`${base}.me.rgba`, b.px);
  }
}
const avg = (k) => rows.reduce((s, r) => s + r.m[k], 0) / Math.max(1, rows.length);
console.log(`\n${rows.length} files: mean SSIM ${avg("ssim").toFixed(4)}, mean ssimRGB ${avg("ssimRgb").toFixed(4)}, mean %diff ${avg("pctStrict").toFixed(2)}, mean abs ${avg("meanAbs").toFixed(3)}`);
