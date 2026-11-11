// Where takumi / two bm builds paint a root box (bounding box of opaque pixels). Usage: node probe/layout2/root_px.mjs <a.wasm> <b.wasm>
import { readFileSync } from "node:fs";
import { T } from "./lib.mjs";
const mk = async (p, i) => { const bm = await import("../../../js/index.mjs?rp=" + i); bm.initSync(readFileSync(p)); const r = new bm.Renderer(); r.registerFont({ data: readFileSync("../assets/fonts/Inter-Regular.ttf") }); return r; };
const A = await mk(process.argv[2], 1), B = await mk(process.argv[3], 2);
const bbox = (px, w, h) => { let x0 = w, y0 = h, x1 = -1, y1 = -1; for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (px[(y * w + x) * 4 + 3] > 128) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); } return `${x0},${y0}-${x1},${y1}`; };
const cases = [
  ["abs root", { type: "container", style: { position: "absolute", left: 10, top: 5, width: 30, height: 30, backgroundColor: "red" } }],
  ["margin auto", { type: "container", style: { display: "block", width: 50, margin: "auto", height: 20, backgroundColor: "red" } }],
  ["rel root", { type: "container", style: { position: "relative", left: 10, top: 5, width: 30, height: 30, backgroundColor: "red" } }],
  ["abs right", { type: "container", style: { position: "absolute", right: 10, bottom: 5, width: 30, height: 30, backgroundColor: "red" } }],
];
for (const [n, node] of cases) {
  const o = { width: 100, height: 50, format: "raw" };
  const t = bbox(new Uint8Array(await T.render(node, o)), 100, 50);
  console.log(n.padEnd(12), "takumi", t, "A(icb)", bbox(A.renderSync(node, o), 100, 50), "B(no icb)", bbox(B.renderSync(node, o), 100, 50));
}
