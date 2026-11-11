import { Renderer } from "@takumi-rs/wasm/node";
import { readFileSync, writeFileSync } from "node:fs";
const r = new Renderer();
console.log(Object.getOwnPropertyNames(Object.getPrototypeOf(r)));
const fam = r.registerFont ? r.registerFont(readFileSync("../assets/fonts/Inter-Regular.ttf")) : r.loadFont(readFileSync("../assets/fonts/Inter-Regular.ttf"));
console.log(fam);
const node = { type: "container", style: { width: "100%", height: "100%", backgroundColor: "#fff", display: "flex", alignItems: "center", justifyContent: "center", padding: 40 },
  children: [{ type: "container", style: { backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)", borderRadius: 32, padding: "32px 48px", boxShadow: "0 12px 40px rgba(0,0,0,0.35)", border: "4px solid #111" },
    children: [{ type: "text", text: "Hello Takumi — Xin chào Việt Nam", style: { fontSize: 44, color: "white", fontFamily: "Inter" } }] }] };
let t = performance.now();
const png = await r.render(node, { width: 1200, height: 630 });
console.log("ms", performance.now() - t, png.length);
t = performance.now();
const raw = await r.render(node, { width: 1200, height: 630, format: "raw" });
console.log("raw ms", performance.now() - t, raw.length);
writeFileSync("probe/first.png", png);
