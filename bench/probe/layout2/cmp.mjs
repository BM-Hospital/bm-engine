// Oracle comparison for bench/fixtures/layout2.mjs (or any case matching argv[2]): pixel verdict / % differing
// pixels / SSIM (like probe/frontend/cmp.mjs) plus the measure() tree diff (positions / sizes > tol, child counts).
// Usage (from bench/): BM_WASM=../zig-out/bin/bm_engine.wasm node probe/layout2/cmp.mjs [filter] [tol]
// LAY_OUT=1 writes takumi.png / bm.png / diff.png to bench/out/layout2/<id>/; LAY_TREE=1 prints both trees.
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
import { ALL_CASES } from "../../fixtures/index.mjs";
import layout2 from "../../fixtures/layout2.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import { encodePng } from "../../lib/pipeline.mjs";
import { fmt } from "./fmt.mjs";

bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
const r = new bm.Renderer();
const t = new TR();
for (const f of fontsFor()) {
  const data = readFileSync(f.path);
  r.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
  await t.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
}
const filter = process.argv[2];
const tol = +(process.argv[3] || 0.02);
const cases = filter ? ALL_CASES.filter((k) => new RegExp(filter, "i").test(k.id) || new RegExp(filter, "i").test(k.feature)) : layout2;

function treeDiff(x, y, path, out) {
  const d = [x.width - y.width, x.height - y.height, x.transform[4] - y.transform[4], x.transform[5] - y.transform[5]];
  const r2 = (v) => Math.round(v * 100) / 100;
  if (d.some((v) => Math.abs(v) > tol)) out.push(`${path || "/"} takumi ${r2(x.width)}x${r2(x.height)}@${r2(x.transform[4])},${r2(x.transform[5])} bm ${r2(y.width)}x${r2(y.height)}@${r2(y.transform[4])},${r2(y.transform[5])}`);
  if (x.children.length !== y.children.length) { out.push(`${path || "/"} child count takumi ${x.children.length} bm ${y.children.length}`); return; }
  x.children.forEach((k, i) => treeDiff(k, y.children[i], path + "/" + i, out));
}

for (const k of cases) {
  const o = { width: k.width, height: k.height, format: "raw", devicePixelRatio: 1, ...(k.images ? { images: k.images } : {}), ...(k.opts || {}) };
  let a, b;
  try { a = await t.render(k.node, o); } catch (e) { console.log(k.id.padEnd(26), "takumi error:", String(e.message || e).slice(0, 200)); continue; }
  try { b = r.renderSync(k.node, o); } catch (e) { console.log(k.id.padEnd(26), "bm error:", String(e.message || e).slice(0, 200)); continue; }
  const m = compare(new Uint8Array(a), b, k.width, k.height, { diff: !!process.env.LAY_OUT });
  console.log(k.id.padEnd(26), verdict(m).padEnd(10), "diff%", m.pctStrict.toFixed(2).padStart(6), "AA%", m.pctAA.toFixed(2).padStart(6), "ssim", m.ssim.toFixed(4), "ssimRgb", m.ssimRgb.toFixed(4));
  const mo = { ...o };
  delete mo.format;
  try {
    const ta = await t.measure(k.node, mo);
    const tb = r.measureSync(k.node, mo);
    const diffs = [];
    treeDiff(ta, tb, "", diffs);
    console.log("   measure:", diffs.length ? `${diffs.length} diffs` : "layout OK");
    for (const s of diffs.slice(0, 10)) console.log("     ", s);
    if (process.env.LAY_TREE) console.log("takumi:\n" + fmt(ta) + "bm:\n" + fmt(tb));
  } catch (e) { console.log("   measure error:", String(e.message || e).slice(0, 200)); }
  if (process.env.LAY_OUT) {
    const dir = `out/layout2/${k.id}`;
    mkdirSync(dir, { recursive: true });
    writeFileSync(`${dir}/takumi.png`, encodePng(new Uint8Array(a), k.width, k.height));
    writeFileSync(`${dir}/bm.png`, encodePng(b, k.width, k.height));
    writeFileSync(`${dir}/diff.png`, encodePng(m.diff, k.width, k.height));
  }
}
