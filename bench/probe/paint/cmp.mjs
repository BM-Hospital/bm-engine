// Paint-agent equivalence probe (does not touch bench/out):
//   BM_WASM=<wasm> node probe/paint/cmp.mjs "<regex>" [--dump=<dir>] [--all] [--extra=<fixture file>]
// Renders every matching fixture with takumi-wasm and bm (raw) and prints verdict / SSIM / % / max diff.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import * as bm from "../../../js/index.mjs";
import { ALL_CASES } from "../../fixtures/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import tk from "../../engines/takumi-wasm.mjs";
import { PNG } from "pngjs";
const args = process.argv.slice(2);
const re = new RegExp(args.find((a) => !a.startsWith("--")) || ".", "i");
const dump = args.find((a) => a.startsWith("--dump="))?.slice(7);
const showAll = args.includes("--all");
const extra = args.find((a) => a.startsWith("--extra="))?.slice(8);
let cases = ALL_CASES;
if (extra) cases = cases.concat((await import(pathToFileURL(path.resolve(extra)).href)).default);
bm.initSync(readFileSync(process.env.BM_WASM || new URL("../../../zig-out/bin/bm_render.wasm", import.meta.url)));
const pools = new Map();
async function engines(fonts) {
  const key = fonts ? fonts.join(",") : "*";
  if (!pools.has(key)) {
    const r = new bm.Renderer();
    for (const f of fontsFor(fonts)) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
    pools.set(key, { b: r, t: await tk.create({ fonts: fontsFor(fonts) }) });
  }
  return pools.get(key);
}
const png = (rgba, w, h) => { const p = new PNG({ width: w, height: h }); p.data = Buffer.from(rgba); return PNG.sync.write(p); };
const tally = {};
for (const k of cases) {
  if (!re.test(k.id) && !re.test(k.feature)) continue;
  const o = { width: k.width, height: k.height, format: "raw", devicePixelRatio: 1 }; if (k.images) o.images = k.images;
  const e = await engines(k.fonts);
  let A, B, v, line = "";
  try { A = new Uint8Array(await e.t.render(k.node, o)); } catch (x) { v = "ref-error"; line = String(x?.message ?? x).split("\n")[0].slice(0, 200); }
  if (!v) try { B = new Uint8Array(e.b.renderSync(k.node, o)); } catch (x) { v = "bm-error"; line = String(x?.message ?? x).split("\n")[0].slice(0, 200); }
  if (!v) {
    if (A.length !== B.length) { v = "size-mismatch"; }
    else {
      const m = compare(A, B, k.width, k.height, { diff: !!dump });
      v = verdict(m);
      line = `ssim ${Math.min(m.ssim, m.ssimRgb).toFixed(4)} pct ${m.pctStrict.toFixed(3)} max ${m.maxAbs} mean ${m.meanAbs.toFixed(4)}`;
      if (dump) { const d = path.join(dump, k.id); mkdirSync(d, { recursive: true }); writeFileSync(path.join(d, "takumi.png"), png(A, k.width, k.height)); writeFileSync(path.join(d, "bm.png"), png(B, k.width, k.height)); if (m.diff) writeFileSync(path.join(d, "diff.png"), png(m.diff, k.width, k.height)); }
    }
  }
  const grp = k.feature === "known-gaps" ? "gap:" + v : v;
  tally[grp] = (tally[grp] || 0) + 1;
  if (v !== "identical" || showAll) console.log(k.id.padEnd(30), v.padEnd(12), line);
}
console.log(JSON.stringify(tally));
