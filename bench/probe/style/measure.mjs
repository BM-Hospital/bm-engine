// Layout-visible semantics of a few style values (sizes via measure()).
import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const box = (style) => ({ type: "container", style: { display: "flex", width: 400, height: 100 }, children: [{ type: "container", style: { display: "block", ...style } }] });
async function m(label, style, opts = {}) {
  try {
    const res = await r.measure(box(style), { width: 400, height: 100, ...opts });
    const c = res.children?.[0] ?? res;
    console.log(label, JSON.stringify({ w: c.width, h: c.height, x: c.transform?.[4] ?? c.x, y: c.y }));
  } catch (e) { console.log(label, "ERR", String(e.message).split("\n")[0].slice(0, 80)); }
}
const res0 = await r.measure(box({ width: 10, height: 10 }), { width: 400, height: 100 });
console.log("shape", JSON.stringify(res0).slice(0, 300));
await m("flex 1 2 3 (basis 3px?)", { flex: "1 2 3", height: 10 });
await m("flex 0 0 30", { flex: "0 0 30", height: 10 });
await m("width 2em fontSize 10", { width: "2em", fontSize: 10, height: 10 });
await m("width 2em before fontSize", { width: "2em", fontSize: 10, height: 10 });
await m("fontSize 2em -> width 1em", { fontSize: "2em", width: "1em", height: 10 });
await m("width calc(50% - 10px)", { width: "calc(50% - 10px)", flexShrink: 0, height: 10 });
await m("width min(10px, 20px)", { width: "min(10px, 20px)", height: 10 });
await m("width 50vw dpr2", { width: "50vw", height: 10 }, { devicePixelRatio: 2 });
await m("width 10 dpr2", { width: 10, height: 10 }, { devicePixelRatio: 2 });
await m("width 1rem dpr2", { width: "1rem", height: 10 }, { devicePixelRatio: 2 });
await m("width 1ch", { width: "1ch", height: 10 });
await m("width 1ex", { width: "1ex", height: 10 });
await m("padding auto", { padding: "auto", width: 10, height: 10 });
await m("aspectRatio -1", { aspectRatio: "-1", width: 10 });
await m("aspectRatio 2", { aspectRatio: 2, width: 10 });
await m("maxWidth auto", { maxWidth: "auto", width: 50, height: 10 });
await m("fontSize -1 width 1em", { fontSize: "-1px", width: "10em", height: 10 });
await m("fontSize smaller width 1em", { fontSize: "smaller", width: "1em", height: 10 });
await m("fontSize larger width 1em", { fontSize: "larger", width: "1em", height: 10 });
await m("fontSize xxx-large width 1em", { fontSize: "xxx-large", width: "1em", height: 10 });
await m("lineHeight 24 text", { lineHeight: 24, fontSize: 10 });
