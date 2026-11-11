// Probe: does takumi apply structural pseudo-classes to `text` nodes with metadata? (containers vs text)
import { readFileSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";
const t = new Renderer();
await t.registerFont({ name: "Inter", data: readFileSync(new URL("../../../assets/fonts/Inter-Regular.ttf", import.meta.url)) });
const css = [`.l{display:flex;width:40px;height:30px} .i{width:10px;height:10px;background:blue} .i:nth-child(2){background:red} .i:first-child{background:green}`];
for (const type of ["container", "text"]) {
  const kid = (i) => (type === "text" ? { type, className: "i", text: "x", style: { display: "block", color: "transparent", fontSize: 4 } } : { type, className: "i", children: [] });
  const node = { type: "container", className: "l", children: [kid(0), kid(1), kid(2)] };
  const raw = new Uint8Array(await t.render(node, { width: 40, height: 30, format: "raw", css }));
  const px = (x) => Array.from(raw.slice((5 * 40 + x) * 4, (5 * 40 + x) * 4 + 3)).join(",");
  console.log(type, px(5), px(15), px(25));
}
