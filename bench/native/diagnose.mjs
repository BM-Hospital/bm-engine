// Diagnostic probes behind the biggest gaps between the engines (a child of bench/run-native.mjs, stage "diagnose").
//
//   node native/diagnose.mjs [--iters=40]
//
// 1. Fixed per-frame cost: an empty white container rendered to raw RGBA and PNG at three sizes. Nothing is drawn,
//    so the time is the per-pixel work every frame pays (canvas clear, alpha conversion, copying the result out),
//    plus, for PNG, encoding a flat image.
// 2. The event-loop animation scene (12 rotated discs with box-shadow 30px and filter: blur(2px)) as ONE 800x420 raw
//    frame, as is, without the filter, without the shadow: which effect the 60-frame animation time comes from.
// Variants are interleaved iteration by iteration; medians are reported.
import { createEngine } from "./engines.mjs";

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const N = +(args.iters ?? 40);
const med = (a) => { const s = [...a].sort((x, y) => x - y); return +s[s.length >> 1].toFixed(3); };
const E = {};
for (const n of ["bm-native", "bm-wasm", "takumi-native", "takumi-wasm"]) E[n] = await createEngine(n, ["Inter"]);
const V = {
  "bm-native:sync": (n, o) => E["bm-native"].sync(n, o), "bm-native:async": (n, o) => E["bm-native"].async(n, o),
  "bm-wasm:sync": (n, o) => E["bm-wasm"].sync(n, o), "takumi-native:async": (n, o) => E["takumi-native"].async(n, o),
  "takumi-wasm:async": (n, o) => E["takumi-wasm"].async(n, o),
};
async function measure(node, opts, iters) {
  const t = Object.fromEntries(Object.keys(V).map((k) => [k, []]));
  for (let i = 0; i < iters + 3; i++) for (const [k, f] of Object.entries(V)) { const a = performance.now(); await f(node, opts); if (i >= 3) t[k].push(performance.now() - a); }
  return Object.fromEntries(Object.entries(t).map(([k, v]) => [k, med(v)]));
}
const empty = { type: "container", style: { width: "100%", height: "100%", backgroundColor: "#ffffff" } };
const disc = (shadow, blur) => ({ type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundImage: "linear-gradient(135deg,#1e3a8a,#db2777)", alignItems: "center", justifyContent: "center" },
  children: Array.from({ length: 12 }, (_, i) => ({ type: "container", style: { width: 60, height: 60, margin: 6, borderRadius: 30, backgroundColor: "#fff", ...(shadow ? { boxShadow: "0 8px 30px rgba(0,0,0,.5)" } : {}), ...(blur ? { filter: "blur(2px)" } : {}), transform: `rotate(${i * 10}deg)` } })) });
const out = { iters: N, emptyFrame: [], animScene: [] };
for (const [w, h] of [[300, 200], [1200, 630], [2400, 1260]]) for (const format of ["raw", "png"]) out.emptyFrame.push({ width: w, height: h, format, ms: await measure(empty, { width: w, height: h, format }, N) });
for (const [label, s, b] of [["shadow + blur (as animated)", true, true], ["shadow only", true, false], ["blur only", false, true], ["neither", false, false]])
  out.animScene.push({ label, ms: await measure(disc(s, b), { width: 800, height: 420, format: "raw" }, Math.max(5, N >> 2)) });
for (const e of Object.values(E)) e.dispose();
console.log(JSON.stringify(out));
process.exit(0);
