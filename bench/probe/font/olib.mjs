import { Renderer } from "@takumi-rs/wasm/node";
import { readFileSync } from "node:fs";
export const F = "D:/project/bm-engine/assets/fonts/";
export const r = new Renderer();
export function reg(files = ["Inter-Regular.ttf","Inter-Bold.ttf","NotoSans-Regular.ttf","Roboto-Regular.ttf"]) {
  return files.map(f => r.registerFont(readFileSync(F + f)));
}
// measure text in a block container of given width (or auto via flex)
export async function mt(text, style = {}, width = null, vp = { width: 2000, height: 2000 }) {
  const node = width == null
    ? { type: "container", style: { display: "flex", alignItems: "flex-start" }, children: [{ type: "text", text, style }] }
    : { type: "container", style: { width }, children: [{ type: "text", text, style }] };
  const m = await r.measure(node, vp);
  const t = (width == null ? m.children[0] : (m.children[0] ?? m)) ?? {width:0,height:0,runs:[]};
  const runs = (t.runs?.length ? t.runs : (m.runs ?? []));
  return { w: t.width, h: t.height, runs };
}
