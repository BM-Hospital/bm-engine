// Hypothesis check: takumi fills a transformed NON-rounded solid box without AA (pixel-centre test).
import { Renderer } from "@takumi-rs/wasm/node";
const tk = new Renderer();
const w = 400, h = 400, x = 120, y = 140, bw = 160, bh = 100;
for (const deg of [5, 10, 30, 45, 60, 137]) {
  const px = new Uint8Array(await tk.render({ type: "container", style: { width: w, height: h, display: "flex" }, children: [{ type: "container", style: { position: "absolute", left: x, top: y, width: bw, height: bh, backgroundColor: "white", transform: `rotate(${deg}deg)` } }] }, { width: w, height: h, format: "raw" }));
  const a = (deg * Math.PI) / 180, c = Math.cos(a), s = Math.sin(a), cx = x + bw / 2, cy = y + bh / 2;
  let bad = 0, n = 0;
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    const dx = i + 0.5 - cx, dy = j + 0.5 - cy;
    const u = c * dx + s * dy + bw / 2, v = -s * dx + c * dy + bh / 2;
    const inside = u >= 0 && u < bw && v >= 0 && v < bh;
    const t = px[(j * w + i) * 4 + 3];
    if (t) n++;
    if ((t === 255) !== inside) bad++;
  }
  console.log(`rotate(${deg}deg): covered px ${n}, pixel-centre test mismatches ${bad}`);
}
