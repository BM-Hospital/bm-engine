// Oracle: renders `background-image: <arg2>` on a W x 1 box (W = argv[2]) and prints each pixel "r g b a".
import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const w = +process.argv[2];
for (const g of process.argv.slice(3)) {
  const raw = await r.render({ type: "container", style: { display: "block", width: w, height: 1, backgroundImage: g } }, { width: w, height: 1, format: "raw" });
  const out = [];
  for (let i = 0; i < w; i++) out.push(`${raw[i * 4]} ${raw[i * 4 + 1]} ${raw[i * 4 + 2]} ${raw[i * 4 + 3]}`);
  console.log(g + "\n" + out.join("\n"));
}
