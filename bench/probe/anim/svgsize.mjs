// takumi intrinsic size of SVG image sources (measure()). Usage (from bench/): node probe/anim/svgsize.mjs
import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const heads = [
  `<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"></svg>`,
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20"></svg>`,
  `<svg xmlns="http://www.w3.org/2000/svg" width="40" viewBox="0 0 40 20"></svg>`,
  `<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 0 40 20"></svg>`,
  `<svg xmlns="http://www.w3.org/2000/svg"></svg>`,
  `<svg xmlns="http://www.w3.org/2000/svg" width="50%" height="30"></svg>`,
  `<svg xmlns="http://www.w3.org/2000/svg" width="2em" height="3em"></svg>`,
  `<svg xmlns="http://www.w3.org/2000/svg" width="10mm" height="1in"></svg>`,
  `<svg xmlns="http://www.w3.org/2000/svg" width="40"></svg>`,
];
for (const dpr of [1, 2]) for (const h of heads) {
  const variants = { inline: h, b64: "data:image/svg+xml;base64," + Buffer.from(h).toString("base64"), pct: "data:image/svg+xml," + encodeURIComponent(h) };
  const out = [];
  for (const [k, src] of Object.entries(variants)) {
    try {
      const m = await r.measure({ type: "container", style: { display: "flex", alignItems: "flex-start" }, children: [{ type: "image", src }] }, { width: 400, height: 300, devicePixelRatio: dpr });
      out.push(k + "=" + m.children[0].width + "x" + m.children[0].height);
    } catch (e) { out.push(k + "=ERR " + e.message); }
  }
  console.log("dpr", dpr, h.replace('xmlns="http://www.w3.org/2000/svg" ', "").padEnd(52), out.join("  "));
}
// images option entry with svg bytes
const m = await r.measure({ type: "container", style: { display: "flex", alignItems: "flex-start" }, children: [{ type: "image", src: "logo" }] }, { width: 400, height: 300, images: [{ src: "logo", data: Buffer.from(heads[0]) }] });
console.log("images option:", m.children[0].width, m.children[0].height);
