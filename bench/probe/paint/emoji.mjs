// BM_WASM=<wasm> node probe/paint/emoji.mjs [dump dir]
// Colour glyphs (CBDT bitmaps from takumi's bundled NotoColorEmoji) in text: bm vs takumi.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import tk from "../../engines/takumi-wasm.mjs";
import { PNG } from "pngjs";
const fonts = [{ name: "Inter", path: "../assets/fonts/Inter-Regular.ttf", weight: 400, style: "normal" }, { name: "Noto Color Emoji", path: "../ref/takumi/assets/fonts/noto-sans/NotoColorEmoji.ttf", weight: 400, style: "normal" }];
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer();
for (const f of fonts) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
const t = await tk.create({ fonts });
const cases = {
  "emoji-line": { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#fff", alignItems: "center", justifyContent: "center" }, children: [{ type: "text", text: "Hi \u{1F600}\u{1F389} ok \u{2764}\u{FE0F}", style: { fontFamily: "Inter, Noto Color Emoji", fontSize: 48, color: "#111" } }] },
  "emoji-alpha": { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#0f172a", alignItems: "center", justifyContent: "center" }, children: [{ type: "text", text: "\u{1F680} launch \u{1F525}", style: { fontFamily: "Inter, Noto Color Emoji", fontSize: 30, fontWeight: 700, fontStyle: "italic", color: "rgba(255,255,255,0.5)" } }] },
};
const png = (rgba, w, h) => { const p = new PNG({ width: w, height: h }); p.data = Buffer.from(rgba); return PNG.sync.write(p); };
for (const [id, node] of Object.entries(cases)) {
  const o = { width: 500, height: 120, format: "raw", devicePixelRatio: 1 };
  const A = new Uint8Array(await t.render(node, o)); let B;
  try { B = new Uint8Array(r.renderSync(node, o)); } catch (e) { console.log(id, "bm-error", e.message); continue; }
  const m = compare(A, B, 500, 120, {});
  console.log(id.padEnd(14), verdict(m), `ssim ${Math.min(m.ssim, m.ssimRgb).toFixed(4)} pct ${m.pctStrict.toFixed(3)} max ${m.maxAbs}`);
  if (process.argv[2]) { mkdirSync(process.argv[2], { recursive: true }); writeFileSync(`${process.argv[2]}/${id}-takumi.png`, png(A, 500, 120)); writeFileSync(`${process.argv[2]}/${id}-bm.png`, png(B, 500, 120)); }
}
