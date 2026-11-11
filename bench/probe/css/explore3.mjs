import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const show = (m) => JSON.stringify(m, (k, v) => (k === "transform" || k === "runs") ? undefined : v);
const P = { display: "flex", width: 1, height: 1, flexShrink: 0 };
const t = { type: "container", tagName: "div", preset: P, children: [ { type: "container", tagName: "p", className: "a", preset: P }, { type: "container", preset: P } ] };
for (const [css, dpr] of [[["p{width:5px} @media (min-width: 500px){p{width:6px}}"],1],[["p{width:5px} @media (min-width: 500px){p{width:6px}}"],2],[["p{width:5px} @media (min-width: 40em){p{width:6px}}"],2],
  [[".a{ span:first-child{width:3px} width:4px }"],1], [["div{ p:first-child{width:3px} }"],1], [["p::before{content:'';width:9px;height:1px;display:block}"],1], [["div{color:red"," p{width:8px}"],1]]) {
  console.log(dpr, JSON.stringify(css), show(await r.measure(t, { width: 800, height: 100, css, devicePixelRatio: dpr })));
}
