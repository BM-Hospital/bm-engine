// takumi: viewBox-only / default-size SVG sources in block and flex contexts, with an explicit width.
// Usage (from bench/): node probe/anim/svgsize2.mjs
import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const vb = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20"></svg>`;
const none = `<svg xmlns="http://www.w3.org/2000/svg"></svg>`;
const rem = `<svg xmlns="http://www.w3.org/2000/svg" width="2rem" height="2ex"></svg>`;
for (const [name, src] of [["vb", vb], ["none", none], ["rem", rem]]) {
  for (const [ctx, st] of [["block", {}], ["flexrow", { display: "flex" }], ["flexcol", { display: "flex", flexDirection: "column" }]]) {
    for (const img of [{}, { width: 100 }, { height: 50 }]) {
      const m = await r.measure({ type: "container", style: st, children: [{ type: "image", src, style: img }] }, { width: 400, height: 300 });
      console.log(name.padEnd(5), ctx.padEnd(8), JSON.stringify(img).padEnd(14), m.children[0].width + "x" + m.children[0].height);
    }
  }
}
