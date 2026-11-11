// Fits blend formulas for AA edge pixels of an unclipped solid circle: which rounding does takumi use?
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import tk from "../../engines/takumi-wasm.mjs";
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer(); const t = await tk.create({ fonts: [] });
const S = [236, 72, 153, +(process.argv[2] || 255)], D = [15, 23, 42];
const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: `rgb(${D})`, alignItems: "center", justifyContent: "center" }, children: [{ type: "container", style: { width: 150, height: 150, borderRadius: 75, backgroundColor: `rgba(${S[0]},${S[1]},${S[2]},${S[3] / 255})` } }] };
const o = { width: 200, height: 200, format: "raw" };
const A = new Uint8Array(await t.render(node, o)), B = new Uint8Array(r.renderSync(node, o));
const d255 = (v) => (v + 128 + (v >> 8)) >> 8, lp = (v) => (v + 255) >> 8;
const pre = S.slice(0, 3).map((c) => d255(c * S[3]));
const forms = {
  exact: (s, d, c, a) => { const sc = d255(s * c), sa = d255(a * c); return sc + d255(d * (255 - sa)); },
  lowp: (s, d, c, a) => { const sc = lp(s * c), sa = lp(a * c); return sc + lp(d * (255 - sa)); },
  lowp_lerp: (s, d, c, a) => { const o = s + lp(d * (255 - a)); return lp(d * (255 - c) + o * c); },
  highp: (s, d, c, a) => { const cf = Math.fround(c / 255); const sc = Math.fround(s / 255 * cf), sa = Math.fround(a / 255 * cf); return Math.round(Math.fround(sc + d / 255 * (1 - sa)) * 255); },
};
const score = Object.fromEntries(Object.keys(forms).map((k) => [k, 0])); let n = 0, diff = 0;
for (let i = 0; i < A.length; i += 4) {
  const isEdge = !(A[i] === D[0] && A[i + 1] === D[1] && A[i + 2] === D[2]) && !(B[i] === forms.exact(pre[0], D[0], 255, S[3]) && B[i + 1] === forms.exact(pre[1], D[1], 255, S[3]));
  if (!isEdge && S[3] === 255) continue;
  if (A[i] === D[0] && A[i + 1] === D[1] && A[i + 2] === D[2]) continue;
  n++; if (A[i] !== B[i] || A[i + 1] !== B[i + 1] || A[i + 2] !== B[i + 2]) diff++;
  for (const [k, f] of Object.entries(forms)) { let ok = false; for (let c = 1; c <= 255 && !ok; c++) ok = [0, 1, 2].every((ch) => f(pre[ch], D[ch], c, S[3]) === A[i + ch]); if (ok) score[k]++; }
}
console.log("alpha", S[3], "pixels", n, "bm!=tk", diff, score);
if (S[3] === 255) for (let i = 0; i < A.length; i += 4) {
  if (A[i] === B[i] && A[i + 1] === B[i + 1] && A[i + 2] === B[i + 2]) continue;
  const cs = (P) => { const o = []; for (let c = 1; c <= 255; c++) if ([0, 1, 2].every((ch) => forms.exact(pre[ch], D[ch], c, 255) === P[i + ch])) o.push(c); return o.join("/"); };
  console.log("px", (i / 4) % 200, Math.floor(i / 4 / 200), "tk", [...A.subarray(i, i + 3)].join(","), "c=" + cs(A), "bm", [...B.subarray(i, i + 3)].join(","), "c=" + cs(B));
}
