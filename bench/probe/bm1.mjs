import { Renderer } from "../../js/node.mjs";
import { readFileSync, writeFileSync } from "node:fs";
import { PNG } from "pngjs";
const r = new Renderer();
console.log(r.registerFont(readFileSync("../assets/fonts/Inter-Regular.ttf")));
const node = { type: "container", style: { width: "100%", height: "100%", backgroundColor: "#fff", display: "flex", alignItems: "center", justifyContent: "center", padding: 40 },
  children: [{ type: "container", style: { display:"flex", backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)", borderRadius: 32, padding: "32px 48px", boxShadow: "0 12px 40px rgba(0,0,0,0.35)", border: "4px solid #111" },
    children: [{ type: "text", text: "Hello Takumi — Xin chào Việt Nam", style: { fontSize: 44, color: "white", fontFamily: "Inter" } }] }] };
let t = performance.now();
const png = r.renderSync(node, { width: 1200, height: 630 });
console.log("ms", performance.now() - t, png.length);
for (let i=0;i<5;i++){ t = performance.now(); r.renderSync(node, { width: 1200, height: 630, format: "raw" }); console.log("raw ms", performance.now() - t);}
t = performance.now(); r.renderSync(node, { width: 1200, height: 630 }); console.log("png ms", performance.now() - t);
writeFileSync("probe/bm1.png", png);
console.log(JSON.stringify(r.measureSync(node, { width: 1200, height: 630 })));
console.log("mem", r.memoryBytes());
