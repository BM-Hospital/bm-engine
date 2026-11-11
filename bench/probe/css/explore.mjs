import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const node = { type: "container", tagName: "div", preset: { width: 1, height: 1 }, children: [
  { type: "container", tagName: "p", className: "a", preset: { width: 1, height: 1 } },
  { type: "container", preset: { width: 1, height: 1 } } ] };
const show = (m) => JSON.stringify(m, (k, v) => (k === "transform" || k === "runs") ? undefined : v);
for (const css of [[".a{width:7px}"], ["div{width:9px}"], ["p{width:5px} @media (min-width: 500px){p{width:6px}}"], [".a{ span:first-child{width:3px} width:4px }"]]) {
  for (const dpr of [1, 2]) {
    try { const m = await r.measure(node, { width: 800, height: 100, css, devicePixelRatio: dpr }); console.log(dpr, css[0], show(m)); }
    catch (e) { console.log("ERR", e.message); }
  }
}
