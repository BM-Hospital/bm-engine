import { Renderer } from "../../js/node.mjs";
import { Renderer as T } from "@takumi-rs/wasm/node";
import { readFileSync } from "node:fs";
const r = new Renderer(), t = new T();
const font = readFileSync("../assets/fonts/Inter-Regular.ttf");
r.registerFont({ name: "Inter", data: font }); await t.registerFont({ name: "Inter", data: font });
const W = 1200, H = 630;
const root = (style, children = []) => ({ type: "container", style: { display: "flex", width: "100%", height: "100%", ...style }, children });
const box = (style, children = []) => ({ type: "container", style: { display: "flex", ...style }, children });
const cases = {
  empty: root({}),
  solid: root({ backgroundColor: "#fff" }),
  solidA: root({ backgroundColor: "rgba(255,0,0,0.5)" }),
  rounded: root({ backgroundColor: "#fff", padding: 40 }, [box({ flex: 1, backgroundColor: "#369", borderRadius: 40 })]),
  boxes40: root({ backgroundColor: "#fff", flexWrap: "wrap", gap: 8 }, Array.from({ length: 40 }, (_, i) => box({ width: 100, height: 100, backgroundColor: "#369", borderRadius: 12 }))),
  rects40: root({ backgroundColor: "#fff", flexWrap: "wrap", gap: 8 }, Array.from({ length: 40 }, (_, i) => box({ width: 100, height: 100, backgroundColor: "#369" }))),
  grad: root({ backgroundImage: "linear-gradient(135deg,#f00,#00f)" }),
  text: root({ backgroundColor: "#fff" }, [{ type: "text", text: "Hello world ".repeat(40), style: { fontSize: 24, fontFamily: "Inter" } }]),
};
function bench(fn) { for (let i = 0; i < 20; i++) fn(); const ts = []; for (let i = 0; i < 60; i++) { const a = performance.now(); fn(); ts.push(performance.now() - a); } ts.sort((a, b) => a - b); return ts[30].toFixed(2); }
async function benchA(fn) { for (let i = 0; i < 20; i++) await fn(); const ts = []; for (let i = 0; i < 60; i++) { const a = performance.now(); await fn(); ts.push(performance.now() - a); } ts.sort((a, b) => a - b); return ts[30].toFixed(2); }
for (const [k, n] of Object.entries(cases)) {
  const o = { width: W, height: H, format: "raw" };
  console.log(k.padEnd(8), "bm raw", bench(() => r.renderSync(n, o)), " takumi raw", await benchA(() => t.render(n, o)), "| bm png", bench(() => r.renderSync(n, { ...o, format: "png" })), " takumi png", await benchA(() => t.render(n, { ...o, format: "png" })), "| bm measure", bench(() => r.measureSync(n, o)));
}
console.log("mem", r.memoryBytes());
