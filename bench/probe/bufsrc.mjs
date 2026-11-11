import { Renderer } from "../../js/node.mjs";
import { readFileSync } from "node:fs";
const r = new Renderer();
const buf = readFileSync("assets/icon.png"); // Node Buffer
const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#fff" }, children: [{ type: "image", src: buf, width: 64, height: 64 }] };
const raw = r.renderSync(node, { width: 64, height: 64, format: "raw" });
let nonWhite = 0; for (let i = 0; i < raw.length; i += 4) if (raw[i] !== 255 || raw[i + 1] !== 255 || raw[i + 2] !== 255) nonWhite++;
console.log("Buffer src non-white pixels:", nonWhite);
console.log((await r.renderAsDataUrl(node, { width: 64, height: 64, format: "jpg" })).slice(0, 22));
