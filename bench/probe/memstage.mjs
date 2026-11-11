import { readFileSync } from "node:fs";
import { ALL_CASES } from "../fixtures/index.mjs";
import { fontsFor } from "../lib/fonts.mjs";
const { Renderer } = await import("../../js/node.mjs");
const k = ALL_CASES.find((c) => c.id === (process.argv[3] || "card-og"));
const r = new Renderer();
const mb = () => (r.memoryBytes() / 1048576).toFixed(2);
console.log("empty", mb());
for (const f of fontsFor()) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
console.log("fonts", mb());
const o = { width: k.width, height: k.height, images: k.images };
const mode = process.argv[2];
if (mode === "measure") { for (let i = 0; i < 5; i++) r.measureSync(k.node, o); console.log("measure", mb()); }
if (mode === "raw") { for (let i = 0; i < 5; i++) r.renderSync(k.node, { ...o, format: "raw" }); console.log("raw", mb()); }
if (mode === "png") { for (let i = 0; i < 5; i++) r.renderSync(k.node, { ...o, format: "png" }); console.log("png", mb()); }
