// Animation oracle comparison: renders bench/fixtures/anim.mjs cases (or any case matching argv[2]) with
// bm-engine and @takumi-rs/wasm, forwarding the case `opts` (timeMs, css, keyframes), and prints % differing
// pixels + SSIM. Writes PNGs to bench/out/anim/<id>/ when FE_OUT=1.
// Usage (from bench/): BM_WASM=../zig-out/bin/bm_engine.wasm node probe/anim/cmp.mjs [filter]
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
import { ALL_CASES } from "../../fixtures/index.mjs";
import anim from "../../fixtures/anim.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import { encodePng } from "../../lib/pipeline.mjs";

bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
const r = new bm.Renderer();
const t = new TR();
for (const f of fontsFor()) {
  const data = readFileSync(f.path);
  r.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
  await t.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
}
const filter = process.argv[2];
const cases = filter ? ALL_CASES.filter((k) => new RegExp(filter, "i").test(k.id) || new RegExp(filter, "i").test(k.feature)) : anim;
for (const k of cases) {
  const o = { width: k.width, height: k.height, format: "raw", devicePixelRatio: 1, ...(k.images ? { images: k.images } : {}), ...(k.opts || {}) };
  let a, b;
  try { a = await t.render(k.node, o); } catch (e) { console.log(k.id.padEnd(22), "takumi error:", String(e.message || e).slice(0, 200)); continue; }
  try { b = r.renderSync(k.node, o); } catch (e) { console.log(k.id.padEnd(22), "bm error:", String(e.message || e).slice(0, 200)); continue; }
  const m = compare(new Uint8Array(a), b, k.width, k.height, { diff: !!process.env.FE_OUT });
  console.log(k.id.padEnd(22), verdict(m).padEnd(10), "diff%", m.pctStrict.toFixed(2).padStart(6), "AA%", m.pctAA.toFixed(2).padStart(6), "ssim", m.ssim.toFixed(4), "ssimRgb", m.ssimRgb.toFixed(4));
  if (process.env.FE_OUT) {
    const dir = `out/anim/${k.id}`;
    mkdirSync(dir, { recursive: true });
    writeFileSync(`${dir}/takumi.png`, encodePng(new Uint8Array(a), k.width, k.height));
    writeFileSync(`${dir}/bm.png`, encodePng(b, k.width, k.height));
    writeFileSync(`${dir}/diff.png`, encodePng(m.diff, k.width, k.height));
  }
}
