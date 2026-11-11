import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const show = (m) => JSON.stringify(m, (k, v) => (k === "transform" || k === "runs") ? undefined : v);
const trees = [
 { type: "container", tagName: "div", style: { width: 50, height: 10 }, children: [ { type: "container", tagName: "p", style: { width: 3, height: 3 } } ] },
 { type: "container", tagName: "div", style: { width: 50, height: 10 }, children: [ { type: "container", tagName: "p", preset: { width: 3, height: 3 } } ] },
 { type: "container", tagName: "div", style: { width: 50, height: 10, display: "flex" }, children: [ { type: "container", tagName: "p", style: { height: 3 } , preset: {width: 1} } ] },
];
for (const t of trees) console.log(show(await r.measure(t, { width: 800, height: 100, css: ["p{width:7px}"] })));
