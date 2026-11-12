import { both, tk, px } from "./lib.mjs";
// decode a JPEG with takumi itself (image node, raw output)
const decode = async (bytes, w, h) => tk.render({ type: "image", src: bytes, style: { width: w, height: h } }, { width: w, height: h, format: "raw" });
const node = { type: "container", style: { display: "flex", width: 64, height: 32 }, children: [
  { type: "container", style: { width: 16, height: 32, backgroundColor: "rgba(255,0,0,0.5)" } },
  { type: "container", style: { width: 16, height: 32, backgroundColor: "rgba(0,0,255,0.25)" } },
  { type: "container", style: { width: 16, height: 32, backgroundColor: "rgba(0,0,0,0)" } },
  { type: "container", style: { width: 16, height: 32, backgroundColor: "#00ff00" } },
] };
for (const q of [75, 100]) {
  const r = await both(async (e) => { const j = new Uint8Array(await e.render(node, { width: 64, height: 32, format: "jpeg", quality: q })); const d = await decode(j, 64, 32); return [8, 24, 40, 56].map((x) => px(d, 64, x, 16).join(",")); });
  console.log("q", q, r);
}
