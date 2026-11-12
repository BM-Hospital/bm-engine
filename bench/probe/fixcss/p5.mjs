import { tk, bm } from "./lib.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import { readFileSync } from "node:fs";
const checker = new Uint8Array(await tk.render({ type: "container", style: { display: "flex", flexWrap: "wrap", width: 6, height: 5 }, children: Array.from({ length: 30 }, (_, i) => ({ type: "container", style: { width: 1, height: 1, backgroundColor: ["#e11d48", "#2563eb", "#facc15", "#16a34a", "rgba(0,0,0,0.4)"][i % 5] } })) }, { width: 6, height: 5, format: "png" }));
const photo = readFileSync("../../assets/photo.jpg");
const W = 400, H = 200;
const imgs = [{ src: "img://checker", data: checker }, { src: "img://photo", data: photo }];
const node = (ir) => ({ type: "container", style: { display: "flex", width: W, height: H, gap: 6, padding: 6, backgroundColor: "#fff", flexWrap: "wrap" }, children: [
  { type: "image", src: "img://checker", style: { width: 97, height: 71, imageRendering: ir } },
  { type: "image", src: "img://photo", style: { width: 90, height: 60, imageRendering: ir, objectFit: "cover" } },
  { type: "container", style: { width: 120, height: 80, backgroundImage: "url(img://checker)", backgroundSize: "30px 25px", imageRendering: ir } },
  { type: "image", src: "img://checker", style: { width: 40, height: 40, imageRendering: ir, transform: "rotate(20deg)" } },
] });
for (const ir of ["auto", "smooth", "pixelated", "crisp-edges", "optimizeSpeed"]) {
  const a = new Uint8Array(await tk.render(node(ir), { width: W, height: H, format: "raw", images: imgs }));
  const b = new Uint8Array(await bm.render(node(ir), { width: W, height: H, format: "raw", images: imgs }));
  const m = compare(a, b, W, H);
  console.log(ir.padEnd(14), verdict(m), "ssim", m.ssim.toFixed(5), "pct", m.pctStrict.toFixed(3), "maxAbs", m.maxAbs);
}
{
  const a = new Uint8Array(await tk.render(node("pixelated"), { width: W, height: H, format: "raw", images: imgs }));
  const b = new Uint8Array(await bm.render(node("pixelated"), { width: W, height: H, format: "raw", images: imgs }));
  const pts = [];
  for (let i = 0; i < a.length; i += 4) { const d = Math.max(...[0, 1, 2, 3].map((c) => Math.abs(a[i + c] - b[i + c]))); if (d > 20) pts.push([(i / 4) % W, Math.floor(i / 4 / W), [...a.slice(i, i + 4)].join(","), [...b.slice(i, i + 4)].join(",")]); }
  console.log(pts.length, pts.slice(0, 12));
}
