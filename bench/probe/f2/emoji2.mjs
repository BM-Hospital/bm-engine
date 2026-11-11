// Emoji presentation selection vs takumi: text-default emoji with / without VS16 / VS15, different font stacks.
// Prints verdict and the count of "colourful" pixels (a colour glyph was used) in each engine.
// Usage (from bench/): BM_WASM=<wasm> node probe/f2/emoji2.mjs [dump dir]
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import tk from "../../engines/takumi-wasm.mjs";
import { PNG } from "pngjs";
const fonts = [
  { name: "Inter", path: "../assets/fonts/Inter-Regular.ttf", weight: 400, style: "normal" },
  { name: "Noto Color Emoji", path: "../ref/takumi/assets/fonts/noto-sans/NotoColorEmoji.ttf", weight: 400, style: "normal" },
];
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer();
for (const f of fonts) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
const t = await tk.create({ fonts });
const W = 260, H = 70;
const strs = {
  "heart-vs16": "a❤️b", "heart-bare": "a❤b", "heart-vs15": "a❤︎b", "smile-vs16": "a☺️b", "smile-bare": "a☺b",
  "copy-vs16": "a©️b", "copy-bare": "a©b", "keycap": "a1️⃣b", "digit-vs16": "a1️b", "grin": "a\u{1F600}b", "grin-vs15": "a\u{1F600}︎b",
  "sun-bare": "a☀b", "sun-vs16": "a☀️b", "watch-bare": "a⌚b", "star-bare": "a⭐b", "check-vs16": "a✔️b", "arrow-vs16": "a↗️b", "arrow-bare": "a↗b",
  "zwj-family": "a\u{1F468}‍\u{1F469}‍\u{1F467}b", "flag": "a\u{1F1EF}\u{1F1F5}b", "skin": "a\u{1F44D}\u{1F3FD}b", "heart-fire": "a❤️‍\u{1F525}b", "two-hearts": "❤️❤️", "heart-first": "❤️ x",
};
const stacks = { "inter,emoji": "Inter, Noto Color Emoji", "inter": "Inter", "emoji,inter": "Noto Color Emoji, Inter", "none": undefined };
const png = (rgba, w, h) => { const p = new PNG({ width: w, height: h }); p.data = Buffer.from(rgba); return PNG.sync.write(p); };
const colourful = (P) => { let n = 0; for (let i = 0; i < P.length; i += 4) { const mx = Math.max(P[i], P[i + 1], P[i + 2]), mn = Math.min(P[i], P[i + 1], P[i + 2]); if (mx - mn > 60) n++; } return n; };
const dump = process.argv[2];
if (dump) mkdirSync(dump, { recursive: true });
for (const [sn, ff] of Object.entries(stacks)) for (const [id, text] of Object.entries(strs)) {
  const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#fff", alignItems: "center", justifyContent: "center" }, children: [{ type: "text", text, style: { ...(ff ? { fontFamily: ff } : {}), fontSize: 40, color: "#111" } }] };
  const o = { width: W, height: H, format: "raw", devicePixelRatio: 1 };
  const A = new Uint8Array(await t.render(node, o)); let B;
  try { B = new Uint8Array(r.renderSync(node, o)); } catch (e) { console.log(id, "bm-error", e.message); continue; }
  const m = compare(A, B, W, H, {});
  const ca = colourful(A), cb = colourful(B);
  const flag = (ca > 30) !== (cb > 30) ? "PRESENTATION-DIFF" : verdict(m) === "different" || verdict(m) === "close" ? "diff" : "ok";
  console.log(flag.padEnd(18), sn.padEnd(12), id.padEnd(12), verdict(m).padEnd(10), `ssim ${Math.min(m.ssim, m.ssimRgb).toFixed(4)} pct ${m.pctStrict.toFixed(3)} colour px takumi ${ca} bm ${cb}`);
  if (dump) { writeFileSync(`${dump}/${sn.replace(",", "_")}-${id}-takumi.png`, png(A, W, H)); writeFileSync(`${dump}/${sn.replace(",", "_")}-${id}-bm.png`, png(B, W, H)); }
}
