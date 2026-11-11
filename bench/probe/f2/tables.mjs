// Table paint cases vs takumi (collapsed-border conflict resolution, column / row / group backgrounds,
// captions, empty-cells, visibility: collapse, anonymous tables).
// Usage (from bench/): BM_WASM=<wasm> node probe/f2/tables.mjs [regex] [--dump]
// --dump writes PNGs to bench/out/f2/tables/<name>-{takumi,bm}.png
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
import { compare, verdict } from "../../lib/metrics.mjs";
import { encodePng } from "../../lib/pipeline.mjs";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
const r = new bm.Renderer(), t = new TR();
const data = readFileSync("../assets/fonts/Inter-Regular.ttf");
r.registerFont({ name: "Inter", data }); await t.registerFont({ name: "Inter", data });
const W = 360, H = 220;
const doc = (css, body) => `<style>.p{font-family:Inter;font-size:14px;width:100%;height:100%;background:#fff;padding:10px} td,th{padding:4px 8px} ${css}</style><div class="p">${body}</div>`;
const rows = `<table><colgroup><col class="c1"><col class="c2"></colgroup><thead><tr class="h"><td>a</td><td>b</td></tr></thead><tbody class="g"><tr class="r1"><td class="x">c</td><td>d</td></tr><tr class="r2"><td>e</td><td class="y"></td></tr></tbody></table>`;
const grid3 = `<table><colgroup class="cg"><col class="c1"><col class="c2"></colgroup><col class="c3"><tr class="r0"><td>a</td><td class="b">b</td><td>c</td></tr><tr class="r1"><td class="d">d</td><td class="e">e</td><td class="f">f</td></tr><tr class="r2"><td>g</td><td class="h">h</td><td>i</td></tr></table>`;
const spans = `<table><tr><td colspan="2" class="a">a</td><td>b</td></tr><tr><td rowspan="2" class="c">c</td><td>d</td><td class="e">e</td></tr><tr><td colspan="2" class="f">f</td></tr></table>`;
export const cases = {
  "row-bg": doc(".r1{background:#fca5a5} .h{background:#93c5fd}", rows),
  "group-bg": doc(".g{background:#86efac}", rows),
  "col-bg": doc(".c1{background:#fde047}", rows),
  "table-bg-spacing": doc("table{background:#c7d2fe;border-spacing:6px;border:3px solid #312e81} td{background:#fff}", rows),
  "collapse": doc("table{border-collapse:collapse;border:4px solid #000} td{border:1px solid #f00}", rows),
  "empty-cells": doc("table{empty-cells:hide;border-spacing:4px} td{background:#f9a8d4;border:1px solid #000}", rows),
  // conflict resolution
  "cf-width": doc("table{border-collapse:collapse} td{border:1px solid #f00} .e{border:5px solid #00f} .b{border:3px solid #0a0}", grid3),
  "cf-style": doc("table{border-collapse:collapse} td{border:4px solid #f00} .e{border:4px double #00f} .b{border:4px dashed #0a0} .h{border:4px dotted #808} .d{border:4px ridge #0aa} .f{border:4px groove #a50}", grid3),
  "cf-hidden": doc("table{border-collapse:collapse;border:3px solid #000} td{border:2px solid #f00} .e{border-style:hidden} .b{border-bottom:6px solid #00f}", grid3),
  "cf-order": doc("table{border-collapse:collapse;border:2px solid #000} td{border:2px solid #f00} .r1{border:2px solid #00f} .c2{border:2px solid #0a0} .cg{border:2px solid #f0f}", grid3),
  "cf-row-group": doc("table{border-collapse:collapse} .r1{border:3px solid #00f} .c3{border:5px solid #0a0} .cg{border:2px dashed #f0f} td{border:1px solid #999}", grid3),
  "cf-table-wide": doc("table{border-collapse:collapse;border:8px double #334155} td{border:1px solid #94a3b8} .e{border:3px dotted #f00}", grid3),
  "cf-inset-outset": doc("table{border-collapse:collapse;border:6px outset #88f} td{border:4px inset #f88} .e{border:6px ridge #8c8}", grid3),
  "cf-colors": doc("table{border-collapse:collapse} td{border:2px solid} .b{border-color:#f00} .d{border-color:#0a0} .e{border-color:#00f} .f{border-color:#f0f} .h{border-color:#0aa}", grid3),
  "cf-odd": doc("table{border-collapse:collapse;border:3px solid #000} td{border:1px solid #f00} .e{border:5px solid #00f} .r2{border-top:7px solid #0a0}", grid3),
  "cf-spans": doc("table{border-collapse:collapse;border:2px solid #000} td{border:1px solid #f00} .a{border:3px solid #00f} .c{border:4px dashed #0a0} .f{border:2px double #808;border-width:6px}", spans),
  "cf-spans-bg": doc("table{border-collapse:collapse} td{border:2px solid #555;background:#fee} .c{background:#cfc} .f{background:#ccf} tr{background:#ff0}", spans),
  "cf-dashed-all": doc("table{border-collapse:collapse;border:3px dashed #000} td{border:3px dotted #f00}", grid3),
  "cf-translucent": doc("table{border-collapse:collapse;border:4px solid rgba(0,0,0,.5)} td{border:4px solid rgba(255,0,0,.5);background:#def}", grid3),
  "cf-partial": doc("table{border-collapse:collapse} td{border-bottom:2px solid #f00} .e{border-left:4px solid #00f;border-right:1px solid #0a0} .b{border-top:3px solid #000}", grid3),
  // columns
  "col-group-bg": doc(".cg{background:#fde047} .c2{background:#fca5a5} .c3{background:linear-gradient(#bbf,#fbb)} table{border-spacing:5px}", grid3),
  "col-bg-spans": doc("table{border-spacing:4px} col{background:#fde047} td{border:1px solid #999}", `<table><col><col style="background:#9cf"><col><tr><td colspan="2">a</td><td>b</td></tr><tr><td rowspan="2">c</td><td>d</td><td>e</td></tr><tr><td colspan="2">f</td></tr></table>`),
  "col-span-attr": doc("table{border-spacing:3px}", `<table><col span="2" style="background:#fde047"><col style="background:#9cf"><tr><td>a</td><td>b</td><td>c</td><td>d</td></tr><tr><td>e</td><td>f</td><td>g</td><td>h</td></tr></table>`),
  "col-border-collapse": doc("table{border-collapse:collapse} .c2{border:3px solid #00f;background:#eef} td{border:1px solid #999}", grid3),
  // rows / groups
  "row-gradient": doc(".r1{background:linear-gradient(90deg,#f00,#00f)} table{border-spacing:8px} td{border:1px solid #000}", grid3),
  "group-gradient": doc("tbody{background:linear-gradient(180deg,#ff0,#0ff)} table{border-spacing:6px}", rows),
  "row-over-col": doc(".c1{background:#fde047} .r1{background:rgba(255,0,0,.4)} .g{background:rgba(0,0,255,.2)} .x{background:rgba(0,255,0,.5)}", rows),
  "row-shadow": doc(".r1{box-shadow:0 0 6px #f00;background:#fee} table{border-spacing:6px}", grid3),
  // captions and table decorations
  "caption-top-bg": doc("table{background:#c7d2fe;border:3px solid #312e81;box-shadow:4px 4px 0 #f00;border-radius:8px} caption{padding:6px}", `<table><caption>Top caption</caption><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>`),
  "caption-bottom-bg": doc("table{background:#c7d2fe;border:3px solid #312e81;box-shadow:0 0 8px #000;border-radius:8px} caption{caption-side:bottom;padding:6px;background:#fee}", `<table><caption>Bottom caption</caption><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>`),
  "caption-both-collapse": doc("table{border-collapse:collapse;background:#efe;border:4px solid #060} td{border:1px solid #999} .b{caption-side:bottom}", `<table><caption>Top</caption><caption class="b">Bottom</caption><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>`),
  "table-outline": doc("table{outline:2px solid #f00;background:#eee;margin:6px} caption{padding:4px}", `<table><caption>Cap</caption><tr><td>a</td><td>b</td></tr></table>`),
  // hidden parts
  "empty-cells-show": doc("table{border-spacing:4px} td{background:#f9a8d4;border:1px solid #000}", rows),
  "empty-cells-collapse": doc("table{empty-cells:hide;border-collapse:collapse} td{background:#f9a8d4;border:1px solid #000}", rows),
  "empty-cells-row-bg": doc("table{empty-cells:hide;border-spacing:4px} td{border:1px solid #000} .r2{background:#9cf}", rows),
  "vis-collapse-row": doc(".r1{visibility:collapse} td{background:#def;border:1px solid #000} tr{background:#fc0}", grid3),
  "vis-collapse-col": doc(".c2{visibility:collapse} td{background:#def;border:1px solid #000}", grid3),
  "vis-collapse-bc": doc("table{border-collapse:collapse} .r1{visibility:collapse} td{background:#def;border:2px solid #000}", grid3),
  "vis-hidden-cell": doc(".e{visibility:hidden} td{background:#def;border:1px solid #000} .r1{background:#f00} table{border-spacing:4px}", grid3),
  "vis-hidden-cell-bc": doc("table{border-collapse:collapse} .e{visibility:hidden} td{background:#def;border:2px solid #000} .r1{background:#f00}", grid3),
  // anonymous boxes
  "anon-row": doc(".t{display:table-row;background:#fde047} .c{display:table-cell;padding:6px;border:2px solid #000}", `<div class="t"><div class="c">a</div><div class="c">b</div></div>`),
  "anon-cells": doc("table{border-spacing:4px} tr{background:#9cf} td{background:#fee}", `<table><tr><td>a</td><div>anon</div><td>c</td></tr></table>`),
  "anon-collapse": doc(".t{display:table-row;border-collapse:collapse} .c{display:table-cell;padding:6px;border:3px solid #00f} .d{border-color:#f00;border-width:5px}", `<div class="t"><div class="c">a</div><div class="c d">b</div><div class="c">c</div></div>`),
  "nested": doc("table{border-collapse:collapse} td{border:2px solid #000} table table td{border:1px dashed #f00;background:#ffe}", `<table><tr><td>a</td><td><table><tr><td>x</td><td>y</td></tr></table></td></tr></table>`),
  "inline-table": doc(".t{display:inline-table;border-collapse:collapse;border:2px solid #00f} td{border:1px solid #999}", `<div>text <table class="t"><tr><td>a</td><td>b</td></tr></table> more</div>`),
  "frac": doc("table{border-collapse:collapse;width:77.7%;margin-left:0.4px} td{border:1.5px solid #f00} .e{border:2.5px solid #00f}", grid3),
  "radius-cells": doc("table{border-spacing:6px} td{border:2px solid #000;border-radius:8px;background:#def} tr{background:#fc0;border-radius:10px}", grid3),
};
if (process.argv[1] && process.argv[1].endsWith("tables.mjs")) {
  const re = new RegExp(process.argv.slice(2).find((a) => !a.startsWith("--")) || ".");
  const dump = process.argv.includes("--dump");
  if (dump) mkdirSync("out/f2/tables", { recursive: true });
  const tally = {};
  for (const [n, node] of Object.entries(cases)) {
    if (!re.test(n)) continue;
    const o = { width: W, height: H, format: "raw" };
    let a, b;
    try { a = new Uint8Array(await t.render(node, o)); } catch (e) { console.log(n.padEnd(22), "takumi error", String(e.message || e).slice(0, 120)); continue; }
    try { b = r.renderSync(node, o); } catch (e) { console.log(n.padEnd(22), "bm error", String(e.message || e).slice(0, 120)); continue; }
    const m = compare(a, b, W, H, {});
    const v = verdict(m);
    tally[v] = (tally[v] || 0) + 1;
    console.log(n.padEnd(22), v.padEnd(10), "diff%", m.pctStrict.toFixed(3), "ssim", Math.min(m.ssim, m.ssimRgb).toFixed(4), "max", m.maxAbs);
    if (dump) {
      writeFileSync(`out/f2/tables/${n}-takumi.png`, encodePng(a, W, H));
      writeFileSync(`out/f2/tables/${n}-bm.png`, encodePng(b, W, H));
    }
  }
  console.log(JSON.stringify(tally));
}
