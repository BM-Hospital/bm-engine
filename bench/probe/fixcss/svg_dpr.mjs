// renderSvg ignores devicePixelRatio (takumi `RenderOptions::svg` draws at DPR 1): for every fixture the SVG text
// at DPR 2 / 0.5 must equal the DPR 1 text, in both engines.  usage: node svg_dpr.mjs [--filter=re]
import { ALL_CASES } from "../../fixtures/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import tkEngine from "../../engines/takumi-wasm.mjs";
import { Renderer } from "../../../js/node.mjs";
import { readFileSync } from "node:fs";
const filter = process.argv.find((a) => a.startsWith("--filter="))?.slice(9);
const { Renderer: TR } = await import("@takumi-rs/wasm/node");
const tk = new TR(), bm = new Renderer();
for (const f of fontsFor()) { const d = readFileSync(f.path); await tk.registerFont({ name: f.name, data: d, weight: f.weight, style: f.style }); bm.registerFont({ name: f.name, data: d, weight: f.weight, style: f.style }); }
const res = { tk: [0, 0], bm: [0, 0] };
for (const k of ALL_CASES) {
  if (filter && !new RegExp(filter, "i").test(k.id)) continue;
  for (const [n, r] of [["tk", tk], ["bm", bm]]) {
    const svg = async (dpr) => { try { return String(await r.renderSvg(k.node, { width: k.width, height: k.height, images: k.images, ...(k.opts || {}), devicePixelRatio: dpr })); } catch (e) { return "ERR " + e.message; } };
    const base = await svg(1);
    const ok = (await svg(2)) === base && (await svg(0.5)) === base;
    res[n][ok ? 0 : 1]++;
    if (!ok) console.log(n, "differs at dpr != 1:", k.id);
  }
}
console.log(`renderSvg DPR-invariant: takumi ${res.tk[0]}/${res.tk[0] + res.tk[1]}, bm ${res.bm[0]}/${res.bm[0] + res.bm[1]}`);
