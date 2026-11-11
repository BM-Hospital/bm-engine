// Times one HTML file render in bm (and measure only). Usage: BM_WASM=<wasm> node probe/f2/timehtml.mjs <file.html> [w] [h]
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer();
r.registerFont({ name: "Inter", data: readFileSync("../assets/fonts/Inter-Regular.ttf") });
const html = readFileSync(process.argv[2], "utf8");
const o = { width: +(process.argv[3] || 300), height: +(process.argv[4] || 240) };
let t0 = performance.now();
try { r.measureSync(html, o); } catch (e) { console.log("measure error", e.message); }
console.log("measure", Math.round(performance.now() - t0), "ms");
t0 = performance.now();
try { r.renderSync(html, { ...o, format: "raw" }); } catch (e) { console.log("render error", e.message); }
console.log("render", Math.round(performance.now() - t0), "ms");
