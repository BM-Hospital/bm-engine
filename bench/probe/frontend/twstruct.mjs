// Probe: Tailwind structural variants in takumi — do untagged text nodes count as siblings, and what is
// the "type" of untagged nodes for *-of-type?
import { readFileSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";
const t = new Renderer();
await t.registerFont({ name: "Inter", data: readFileSync(new URL("../../../assets/fonts/Inter-Regular.ttf", import.meta.url)) });
const box = (type, tw) => type === "text" ? { type, tw: "block w-[10px] h-[10px] text-[4px] text-transparent " + tw, text: "x" }
  : type === "image" ? { type, src: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", tw: "w-[10px] h-[10px] " + tw }
  : { type, tw: "w-[10px] h-[10px] " + tw, children: [] };
async function run(label, kids) {
  const node = { type: "container", tw: "flex w-[40px] h-[30px]", children: kids };
  const raw = new Uint8Array(await t.render(node, { width: 40, height: 30, format: "raw" }));
  const px = (x) => Array.from(raw.slice((5 * 40 + x) * 4, (5 * 40 + x) * 4 + 3)).join(",");
  console.log(label.padEnd(28), px(5), "|", px(15), "|", px(25));
}
const v = "bg-blue-500 first:bg-green-500 last:bg-red-500";
await run("text first/last", [box("text", v), box("text", v), box("text", v)]);
await run("container,text,container", [box("container", v), box("text", v), box("container", v)]);
const ot = "bg-blue-500 first-of-type:bg-green-500";
await run("cont,text,cont first-of-type", [box("container", ot), box("text", ot), box("container", ot)]);
await run("text,cont first-of-type", [box("text", ot), box("container", ot), box("container", ot)]);
