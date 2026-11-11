import { readFileSync } from "node:fs";
const wmod = new WebAssembly.Module(readFileSync(process.env.BM_WASM)); let seq = 0;
async function run(label, n, opts, fonts = ["Inter-Regular.ttf", "NotoSans-Bold.ttf"]) {
  const bm = await import("../../js/index.mjs?i=" + seq++); bm.initSync(wmod);
  const r = new bm.Renderer();
  for (const f of fonts) r.registerFont({ data: readFileSync("../assets/fonts/" + f) });
  try { if (process.env.MEAS) { console.log(label, JSON.stringify(r.measureSync(n, opts))); return; } const o = r.renderSync(n, opts); console.log(label, "ok", o.length, JSON.stringify(r.measureSync(n, opts)).slice(0, 200)); } catch (e) { console.log(label, "ERR", String(e.stack).split("\n").slice(0, 3).join(" | ")); }
}
const T = (text) => ({ type: "container", style: {}, children: [{ type: "container", style: { borderTop: "6px solid green" }, children: [{ type: "text", text, style: {} }] }] });
await run("h1 viet", T("Xin chào Việt Nam — tiếng Việt có dấu"), { height: 1 });
await run("h1 ascii", T("Hello"), { height: 1 });
await run("h50 viet", T("Xin chào Việt Nam — tiếng Việt có dấu"), { height: 50 });
await run("h1 inter-only", T("Xin chào"), { height: 1 }, ["Inter-Regular.ttf"]);
await run("w200 h1", T("Xin chào"), { height: 1, width: 200 });
await run("h3", T("Xin"), { height: 3 });
await run("h7", T("Xin"), { height: 7 });
await run("h30", T("Xin"), { height: 30 });
const N = {"type":"container","style":{},"children":[{"type":"container","style":{"borderTop":"6px solid green"},"children":[{"type":"container","style":{"bottom":20},"children":[{"type":"container","style":{},"children":[{"type":"container","style":{},"children":[{"type":"text","text":"Xin chào Việt Nam — tiếng Việt có dấu","style":{}}]},{"type":"container","style":{},"children":[]}]}]}]}]};
await run("exact h1", N, { height: 1 });
await run("exact h40", N, { height: 40 });
await run("exact h1 raw", N, { height: 1, format: "raw" });
await run("exact w300 h1", N, { width: 300, height: 1 });
const M = (text, bottom, extra = {}) => ({ type: "container", style: {}, children: [{ type: "container", style: { bottom, ...extra }, children: [{ type: "container", style: {}, children: [{ type: "text", text, style: {} }] }, { type: "container", style: {}, children: [] }] }] });
for (const [txt, b] of [["X", 20], ["X", 5], ["X", 0], ["Xin", 14], ["i", 20], ["Xin chào Việt Nam — tiếng Việt có dấu", 20], ["Xin chào Việt Nam — tiếng Việt có dấu", 3], ["Xin chào Việt Nam", 20], ["ệ", 20], ["ấ", 20], ["à", 20],["Vi", 20],["—", 20]]) await run(`"${txt}" bottom ${b}`, M(txt, b), { height: 30, format: "raw" });
console.log("----");
const V = "Xin chào Việt Nam — tiếng Việt có dấu";
for (const b of [14, 13, 15, 10, 17]) await run(`viet bottom ${b}`, M(V, b), { height: 30, format: "raw" });
for (const t of ["Xin chào", "Việt Nam", "— tiếng", "có dấu", "X", "ệ", "ấ", "g", "à", "ó", "ế"]) await run(`"${t}" bottom 14`, M(t, 14), { height: 30, format: "raw" });
console.log("====");
const Q = (astyle, text, canvas) => run(JSON.stringify(astyle) + " " + text + " " + JSON.stringify(canvas), { type: "container", style: {}, children: [{ type: "container", style: astyle, children: [{ type: "container", style: { bottom: 20 }, children: [{ type: "container", style: {}, children: [{ type: "container", style: {}, children: [{ type: "text", text, style: {} }] }, { type: "container", style: {}, children: [] }] }] }] }] }, { ...canvas, format: "raw" });
await Q({ borderTop: "6px solid green" }, "X", { height: 30 });
await Q({ borderTop: "6px solid green" }, "X", { height: 30, width: 100 });
await Q({ paddingTop: 6 }, "X", { height: 30 });
await Q({ borderTop: "6px solid green" }, "", { height: 30, width: 100 });
await Q({ border: "6px solid green" }, "X", { height: 30, width: 100 });
await Q({ marginTop: 6 }, "X", { height: 30, width: 100 });
await Q({ paddingTop: 5 }, "X", { height: 30, width: 100 });
await Q({ paddingTop: 7 }, "X", { height: 30, width: 100 });
await Q({ paddingTop: 20 }, "X", { height: 30, width: 100 });
