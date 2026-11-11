// Table paint features vs takumi (row / row-group / column backgrounds, collapsed borders, empty-cells,
// caption + table border). Writes PNGs to bench/out/layout2/paintprobe/<name>-{takumi,bm}.png.
import { readFileSync, writeFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
import { compare, verdict } from "../../lib/metrics.mjs";
import { encodePng } from "../../lib/pipeline.mjs";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
const r = new bm.Renderer(), t = new TR();
const data = readFileSync("../assets/fonts/Inter-Regular.ttf");
r.registerFont({ name: "Inter", data }); await t.registerFont({ name: "Inter", data });
const W = 300, H = 160;
const doc = (css, body) => `<style>.p{font-family:Inter;font-size:14px;width:100%;height:100%;background:#fff;padding:10px} td{padding:4px 8px} ${css}</style><div class="p">${body}</div>`;
const rows = `<table><colgroup><col class="c1"><col></colgroup><thead><tr class="h"><td>a</td><td>b</td></tr></thead><tbody class="g"><tr class="r1"><td>c</td><td>d</td></tr><tr><td>e</td><td></td></tr></tbody></table>`;
const cases = {
  "row-bg": doc(".r1{background:#fca5a5} .h{background:#93c5fd}", rows),
  "group-bg": doc(".g{background:#86efac}", rows),
  "col-bg": doc(".c1{background:#fde047}", rows),
  "table-bg-spacing": doc("table{background:#c7d2fe;border-spacing:6px;border:3px solid #312e81} td{background:#fff}", rows),
  "collapse": doc("table{border-collapse:collapse;border:4px solid #000} td{border:1px solid #f00}", rows),
  "empty-cells": doc("table{empty-cells:hide;border-spacing:4px} td{background:#f9a8d4;border:1px solid #000}", rows),
};
for (const [n, node] of Object.entries(cases)) {
  const o = { width: W, height: H, format: "raw" };
  const a = new Uint8Array(await t.render(node, o)), b = r.renderSync(node, o);
  const m = compare(a, b, W, H, {});
  console.log(n.padEnd(18), verdict(m).padEnd(10), "diff%", m.pctStrict.toFixed(2), "ssim", m.ssim.toFixed(4));
  writeFileSync(`out/layout2/paintprobe/${n}-takumi.png`, encodePng(a, W, H));
  writeFileSync(`out/layout2/paintprobe/${n}-bm.png`, encodePng(b, W, H));
}
