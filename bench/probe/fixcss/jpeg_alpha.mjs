// JPEG output of translucent content: takumi encodes the straight RGBA buffer as RGB (jpeg-encoder ColorType::Rgba
// drops alpha: no compositing, no background option). Both engines' JPEGs are decoded with takumi's own decoder
// (image node -> raw) and compared per pixel; also checks the dropped-alpha model: decoded ~ straight RGB of the raw render.
import { tk, bm } from "./lib.mjs";
const decode = (bytes, w, h) => tk.render({ type: "image", src: bytes, style: { width: w, height: h } }, { width: w, height: h, format: "raw" });
const W = 160, H = 80;
const cases = {
  "translucent fills": { type: "container", style: { display: "flex", width: W, height: H }, children: ["rgba(255,0,0,0.5)", "rgba(0,0,255,0.25)", "transparent", "#22c55e"].map((c) => ({ type: "container", style: { width: 40, height: H, backgroundColor: c } })) },
  "soft shadow on transparent canvas": { type: "container", style: { display: "flex", width: W, height: H, padding: 20 }, children: [{ type: "container", style: { width: 120, height: 40, borderRadius: 12, backgroundColor: "#fff", boxShadow: "0 8px 16px rgba(0,0,0,0.35)" } }] },
  "opaque card": { type: "container", style: { display: "flex", width: W, height: H, backgroundColor: "#0f172a", padding: 16 }, children: [{ type: "text", text: "JPEG", style: { fontFamily: "Inter", fontSize: 32, color: "#fde047" } }] },
};
for (const [name, node] of Object.entries(cases)) {
  const out = {};
  for (const [n, r] of [["tk", tk], ["bm", bm]]) {
    const jpg = new Uint8Array(await r.render(node, { width: W, height: H, format: "jpeg", quality: 90 }));
    const raw = new Uint8Array(await r.render(node, { width: W, height: H, format: "raw" }));
    out[n] = { dec: await decode(jpg, W, H), raw };
  }
  let d = 0, model = 0, maxd = 0, tmodel = 0;
  for (let i = 0; i < W * H * 4; i += 4) for (let c = 0; c < 3; c++) {
    const e = Math.abs(out.tk.dec[i + c] - out.bm.dec[i + c]); d += e; maxd = Math.max(maxd, e);
    model += Math.abs(out.bm.dec[i + c] - out.bm.raw[i + c]); // straight RGB, alpha ignored
    tmodel += Math.abs(out.tk.dec[i + c] - out.tk.raw[i + c]);
  }
  const n = W * H * 3;
  console.log(`${name.padEnd(36)} tk vs bm decoded: mean ${(d / n).toFixed(3)} max ${maxd} | bm decoded vs straight RGB of raw: bm ${(model / n).toFixed(3)} tk ${(tmodel / n).toFixed(3)}`);
}
