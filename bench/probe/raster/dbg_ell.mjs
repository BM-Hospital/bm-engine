import { readFileSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";
const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]), {});
const ex = instance.exports; const tk = new Renderer();
const [x, y, bw, bh] = process.argv.slice(3, 7).map(Number);
const w = 1200, h = 630;
const px = new Uint8Array(await tk.render({ type: "container", style: { width: w, height: h, display: "flex" }, children: [{ type: "container", style: { position: "absolute", left: x, top: y, width: bw, height: bh, backgroundColor: "white", borderRadius: "50%" } }] }, { width: w, height: h, format: "raw" }));
ex.path_reset(); ex.path_rrect(x, y, bw, bh, bw / 2, bh / 2, bw / 2, bh / 2, bw / 2, bh / 2, bw / 2, bh / 2);
const ptr = ex.raster(w, h, 2, 0, 1, 0, 0, 1, 0, 0);
const mine = new Uint8Array(ex.memory.buffer, ptr, w * h);
for (let i = 0; i < w * h; i++) { const t = px[i * 4 + 3]; if (t !== mine[i]) { const X = i % w, Y = (i / w) | 0; let s = ""; for (let k = -3; k <= 3; k++) s += `${px[(i + k) * 4 + 3]}/${mine[i + k]} `; console.log(`(${X},${Y}) takumi/mine: ${s}`); } }
