// Which blend rounding does takumi use on the AA edge of an UNCLIPPED solid rounded box (tiny-skia
// `Pixmap::fill_path`)? The coverage of every pixel is read from a white-on-black render of the same shape
// (in both engines), then candidate formulas are scored against takumi's coloured render.
// Usage (from bench/): BM_WASM=<wasm> node probe/f2/fit2.mjs [alpha=255] [--list]
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import tk from "../../engines/takumi-wasm.mjs";
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer(); const t = await tk.create({ fonts: [] });
const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const A8 = +(args[0] || 255);
const S = [236, 72, 153, A8], D = [15, 23, 42];
const mk = (bg, fg) => ({ type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: bg, alignItems: "center", justifyContent: "center" }, children: [{ type: "container", style: { width: 150, height: 150, borderRadius: 75, backgroundColor: fg } }] });
const o = { width: 200, height: 200, format: "raw" };
const covT = new Uint8Array(await t.render(mk("#000", "#fff"), o)), covB = new Uint8Array(r.renderSync(mk("#000", "#fff"), o));
const fg = `rgba(${S[0]},${S[1]},${S[2]},${S[3] / 255})`;
const colT = new Uint8Array(await t.render(mk(`rgb(${D})`, fg), o)), colB = new Uint8Array(r.renderSync(mk(`rgb(${D})`, fg), o));
const d255 = (v) => (v + 128 + (v >> 8)) >> 8, lp = (v) => (v + 255) >> 8;
const pre = S.slice(0, 3).map((c) => d255(c * S[3]));
const preF = S.slice(0, 3).map((c) => Math.fround(Math.fround(c / 255) * Math.fround(S[3] / 255)));
const forms = {
  "exact: d255(s*c) + d255(d*(255-d255(a*c)))": (ch, d, c) => d255(pre[ch] * c) + d255(d * (255 - d255(S[3] * c))),
  "lowp scale+srcover (v+255)>>8": (ch, d, c) => lp(pre[ch] * c) + lp(d * (255 - lp(S[3] * c))),
  "lowp srcover then lerp (v+255)>>8": (ch, d, c) => { const so = pre[ch] + lp(d * (255 - S[3])); return lp(d * (255 - c) + so * c); },
  "lerp exact: d255(d*(255-c) + so*c)": (ch, d, c) => { const so = pre[ch] + d255(d * (255 - S[3])); return d255(d * (255 - c) + so * c); },
  "highp f32 scale+srcover": (ch, d, c) => { const cf = Math.fround(c * Math.fround(1 / 255)); const sc = Math.fround(preF[ch] * cf), sa = Math.fround(Math.fround(S[3] / 255) * cf); return Math.floor(Math.fround(Math.fround(sc + Math.fround(Math.fround(d / 255) * Math.fround(1 - sa))) * 255) + 0.5); },
  "highp f32 lerp": (ch, d, c) => { const cf = Math.fround(c * Math.fround(1 / 255)); const df = Math.fround(d / 255); const so = Math.fround(preF[ch] + Math.fround(df * Math.fround(1 - Math.fround(S[3] / 255)))); return Math.floor(Math.fround(Math.fround(df + Math.fround(Math.fround(so - df) * cf)) * 255) + 0.5); },
};
const score = Object.fromEntries(Object.keys(forms).map((k) => [k, 0]));
let n = 0, covDiff = 0, colDiff = 0;
const hist = {};
for (let i = 0; i < covT.length; i += 4) {
  const c = covT[i];
  if (covT[i] !== covB[i]) covDiff++;
  if (c === 0 || c === 255) continue;
  n++; hist[c] = (hist[c] || 0) + 1;
  if (colT[i] !== colB[i] || colT[i + 1] !== colB[i + 1] || colT[i + 2] !== colB[i + 2]) { colDiff++; if (process.argv.includes("--list")) console.log("px", (i / 4) % 200, Math.floor(i / 4 / 200), "cov tk", c, "bm", covB[i], "tk", [...colT.subarray(i, i + 3)].join(","), "bm", [...colB.subarray(i, i + 3)].join(",")); }
  for (const [k, f] of Object.entries(forms)) if ([0, 1, 2].every((ch) => f(ch, D[ch], c) === colT[i + ch])) score[k]++;
}
console.log("alpha", A8, "edge pixels", n, "coverage differs (white on black)", covDiff, "colour differs", colDiff);
console.log(score);
if (process.argv.includes("--hist")) console.log("coverage values", JSON.stringify(hist));
