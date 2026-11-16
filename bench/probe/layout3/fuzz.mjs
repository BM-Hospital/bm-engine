// Random inline / float HTML snippets: text, nested spans with inline edges, nowrap, vertical-align, own
// font sizes and line-heights, <br>, inline-blocks / inline-flex / images, floats inside and around the text,
// absolutely positioned boxes, RTL, alignment. Every snippet is rendered (raw) and measured by bm; a trap
// (RuntimeError) or a non-finite measure tree fails the run.
//   BM_WASM=<ReleaseSafe build> node probe/layout3/fuzz.mjs [seed=1] [count=1500]
//   ... --oracle   also runs takumi and reports the measure-tree / pixel agreement rate (first mismatches
//                  are printed; FUZZ_SHOW=n sets how many)
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import { asset } from "../../fixtures/_h.mjs";

const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const oracle = process.argv.includes("--oracle");
let seed = +(args[0] || 1) >>> 0;
const count = +(args[1] || 1500);
const rnd = () => { seed = (seed + 0x6d2b79f5) >>> 0; let t = seed; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const chance = (p) => rnd() < p;
const int = (a, b) => a + Math.floor(rnd() * (b - a + 1));

const WORDS = "the quick brown fox jumps over a lazy dog and keeps running through forests until night falls supercalifragilistic x yz I".split(" ");
const words = (n) => Array.from({ length: n }, () => pick(WORDS)).join(" ");
const color = () => pick(["#fde68a", "#bfdbfe", "#fecaca", "#bbf7d0", "#e9d5ff", "#f1f5f9"]);
const valign = () => pick(["baseline", "baseline", "top", "bottom", "middle", "text-top", "text-bottom", "sub", "super", "6px", "-5px", "40%"]);

function spanStyle() {
  const s = [];
  if (chance(0.5)) s.push(`background:${color()}`);
  if (chance(0.4)) s.push(`padding:${int(0, 3)}px ${int(0, 12)}px`);
  if (chance(0.25)) s.push(`border:${int(1, 3)}px solid #334155`);
  if (chance(0.25)) s.push(`margin:0 ${int(-2, 10)}px`);
  if (chance(0.15)) s.push("white-space:nowrap");
  if (chance(0.15)) s.push(`vertical-align:${valign()}`);
  if (chance(0.15)) s.push(`font-size:${pick([10, 12, 20, 28])}px`);
  if (chance(0.1)) s.push(`line-height:${pick(["1", "1.8", "30px", "normal"])}`);
  if (chance(0.1)) s.push("font-weight:700");
  if (chance(0.05)) s.push("box-decoration-break:clone");
  if (chance(0.05)) s.push("text-decoration:underline");
  return s.join(";");
}
function atomic(depth) {
  const k = rnd();
  const va = chance(0.4) ? `vertical-align:${valign()};` : "";
  const mg = chance(0.2) ? `margin:${int(0, 6)}px ${int(-2, 8)}px;` : "";
  if (k < 0.3) return `<span style="display:inline-block;width:${int(4, 60)}px;height:${int(4, 44)}px;background:${color()};${va}${mg}"></span>`;
  if (k < 0.55) return `<span style="display:inline-block;padding:${int(0, 4)}px ${int(0, 8)}px;background:${color()};${chance(0.2) ? "overflow:hidden;" : ""}${chance(0.3) ? `width:${int(30, 120)}px;` : ""}${va}${mg}">${inline(depth + 1, int(1, 4))}</span>`;
  if (k < 0.7) return `<span style="display:inline-flex;align-items:center;gap:4px;padding:2px 6px;background:${color()};${va}"><span style="width:10px;height:10px;background:#0ea5e9"></span>${words(int(1, 2))}</span>`;
  if (k < 0.9) return `<img src="img://icon" style="width:${int(8, 40)}px;height:${int(8, 40)}px;${va}${mg}">`;
  return `<span style="display:inline-block;${va}"></span>`;
}
const float = () => `<span style="float:${pick(["left", "right"])};width:${int(10, 160)}px;height:${int(8, 70)}px;background:${color()};${chance(0.2) ? "clear:" + pick(["left", "right", "both"]) + ";" : ""}${chance(0.2) ? `margin:${int(0, 8)}px;` : ""}"></span>`;
const abs = () => `<${pick(["span", "div"])} style="position:absolute;width:8px;height:8px;background:#ef4444${chance(0.2) ? ";left:3px" : ""}"></${"span"}>`.replace(/<div([^>]*)><\/span>/, "<div$1></div>");
function inline(depth, n) {
  let s = "";
  for (let i = 0; i < n; i++) {
    const k = rnd();
    if (k < 0.5 || depth > 3) s += words(int(1, 6)) + (chance(0.8) ? " " : "");
    else if (k < 0.7) s += `<span style="${spanStyle()}">${inline(depth + 1, int(0, 3))}</span>` + (chance(0.7) ? " " : "");
    else if (k < 0.84) s += atomic(depth) + (chance(0.6) ? " " : "");
    else if (k < 0.9) s += float();
    else if (k < 0.94) s += "<br>";
    else if (k < 0.97) s += abs();
    else s += `<b>${words(int(1, 3))}</b> `;
  }
  return s;
}
function block() {
  const s = [`width:${pick([90, 140, 200, 260, 330])}px`];
  if (chance(0.15)) s.push("direction:rtl");
  if (chance(0.3)) s.push(`text-align:${pick(["center", "right", "justify", "end"])}`);
  if (chance(0.2)) s.push(`line-height:${pick(["1.2", "1.6", "26px"])}`);
  if (chance(0.15)) s.push(`padding:${int(0, 8)}px`);
  if (chance(0.1)) s.push("white-space:" + pick(["nowrap", "pre-wrap", "pre-line"]));
  if (chance(0.1)) s.push("overflow-wrap:anywhere");
  if (chance(0.05)) s.push("overflow:hidden;text-overflow:ellipsis;white-space:nowrap");
  if (chance(0.05)) s.push("display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;overflow:hidden");
  return `<div style="${s.join(";")}">${inline(0, simple ? int(1, 3) : int(1, 7))}</div>`;
}
const simple = !!process.env.FUZZ_SIMPLE; // one short block per snippet (for triage)
function snippet() {
  let s = "";
  const n = simple ? 1 : int(1, 3);
  for (let i = 0; i < n; i++) {
    if (chance(0.25)) s += `<div style="float:${pick(["left", "right"])};width:${int(20, 120)}px;height:${int(10, 90)}px;background:${color()}"></div>`;
    s += chance(0.15) ? `<p style="margin:${int(0, 10)}px 0;${chance(0.3) ? "clear:both;" : ""}">${inline(0, int(1, 4))}</p>` : block();
  }
  return `<style>.page{font-family:Inter;width:100%;height:100%;background:#fff;color:#0f172a;font-size:16px;position:relative}</style><div class="page">${s}</div>`;
}

bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_render.wasm"));
let r = new bm.Renderer();
const fonts = fontsFor();
const reg = (x) => { for (const f of fonts) x.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style }); };
reg(r);
const images = [{ src: "img://icon", data: asset("icon.png") }];
const opts = { width: 400, height: 300, images };
let T = null, cmp = null;
if (oracle) {
  const { Renderer } = await import("@takumi-rs/wasm/node");
  T = new Renderer();
  for (const f of fonts) await T.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
  cmp = await import("../../lib/metrics.mjs");
}
const finite = (t) => [t.width, t.height, t.transform[4], t.transform[5]].every(Number.isFinite) && t.children.every(finite);
function treeDiff(x, y, out, path = "") {
  const d = [x.width - y.width, x.height - y.height, x.transform[4] - y.transform[4], x.transform[5] - y.transform[5]];
  if (d.some((v) => Math.abs(v) > 0.05)) out.push(path || "/");
  if (x.children.length !== y.children.length) { out.push((path || "/") + " children " + x.children.length + "/" + y.children.length); return; }
  x.children.forEach((k, i) => treeDiff(k, y.children[i], out, path + "/" + i));
}
let traps = 0, errors = 0, bad = 0, treeOk = 0, pixOk = 0, compared = 0, shown = 0;
const show = +(process.env.FUZZ_SHOW || 5);
const t0 = performance.now();
for (let i = 0; i < count; i++) {
  const html = snippet();
  let tree, raw;
  try {
    raw = r.renderSync(html, { ...opts, format: "raw" });
    tree = r.measureSync(html, opts);
    if (!finite(tree)) { bad++; if (shown++ < show) console.log("NON-FINITE", i, html); }
  } catch (e) {
    const msg = String(e && e.message || e);
    if (e instanceof WebAssembly.RuntimeError || /unreachable|out of bounds|memory access/.test(msg)) {
      traps++;
      console.log("TRAP", i, msg, "\n", html);
      // the instance is poisoned after a trap
      bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_render.wasm"));
      r = new bm.Renderer();
      reg(r);
    } else { errors++; if (shown++ < show) console.log("ERROR", i, msg.slice(0, 200), "\n", html); }
    continue;
  }
  if (!oracle) continue;
  try {
    const ta = await T.measure(html, opts);
    const a = new Uint8Array(await T.render(html, { ...opts, format: "raw" }));
    compared++;
    const d = [];
    treeDiff(ta, tree, d);
    const m = cmp.compare(a, raw, opts.width, opts.height, {});
    const v = cmp.verdict(m);
    if (!d.length) treeOk++;
    if (v === "identical" || v === "equivalent") pixOk++;
    if ((d.length || (v !== "identical" && v !== "equivalent")) && shown++ < show) console.log(`MISMATCH #${i} tree:${d.slice(0, 4).join(",") || "ok"} pixels:${v} ${m.pctStrict.toFixed(2)}%\n`, html.replace(/^<style>.*?<\/style>/, ""));
  } catch (e) { /* takumi rejected the input */ }
}
console.log(`seed ${args[0] || 1}: ${count} snippets in ${((performance.now() - t0) / 1000).toFixed(1)} s, traps ${traps}, errors ${errors}, non-finite ${bad}` + (oracle ? `; vs takumi (${compared}): measure tree ${treeOk} (${(100 * treeOk / Math.max(compared, 1)).toFixed(1)}%), pixels equivalent ${pixOk} (${(100 * pixOk / Math.max(compared, 1)).toFixed(1)}%)` : ""));
if (traps || bad) process.exit(1);
