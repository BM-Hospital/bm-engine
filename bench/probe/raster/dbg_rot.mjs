import { readFileSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";
const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]), {});
const ex = instance.exports; const tk = new Renderer();
const w = 400, h = 400, x = 120, y = 140, bw = 160, bh = 100, deg = +process.argv[3];
const px = new Uint8Array(await tk.render({ type: "container", style: { width: w, height: h, display: "flex" }, children: [{ type: "container", style: { position: "absolute", left: x, top: y, width: bw, height: bh, backgroundColor: "white", transform: `rotate(${deg}deg)` } }] }, { width: w, height: h, format: "raw" }));
const a = (deg * Math.PI) / 180, m = [Math.cos(a), Math.sin(a), -Math.sin(a), Math.cos(a)];
ex.path_reset(); ex.path_rrect(0, 0, bw, bh, 0, 0, 0, 0, 0, 0, 0, 0);
const cx = x + bw / 2, cy = y + bh / 2;
const ptr = ex.raster(w, h, 2, 0, m[0], m[1], m[2], m[3], cx - (m[0] * bw / 2 + m[2] * bh / 2), cy - (m[1] * bw / 2 + m[3] * bh / 2));
const mine = new Uint8Array(ex.memory.buffer, ptr, w * h);
for (const row of [+process.argv[4], +process.argv[4] + 1, 190]) {
  let s1 = "", s2 = "";
  for (let i = 0; i < w; i++) { const t = px[(row * w + i) * 4 + 3], q = mine[row * w + i]; if ((t || q) && (t !== 255 || q !== 255)) { s1 += `${i}:${t} `; s2 += `${i}:${q} `; } }
  console.log("row", row, "\n takumi", s1, "\n mine  ", s2);
}
const set = new Set(); for (let i = 0; i < w * h; i++) set.add(px[i * 4 + 3]); console.log("takumi distinct alpha values:", [...set].sort((p, q) => p - q).join(","));
