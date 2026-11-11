import { Renderer } from "@takumi-rs/wasm/node";
import { readFileSync } from "node:fs";
export const FONTS = "D:/project/bm-engine/ref/takumi/assets/fonts/";
export const font = (p) => readFileSync(FONTS + p);
export const r = new Renderer();
export async function raw(node, opts) {
  const buf = await r.render(node, { format: "raw", ...opts });
  return buf;
}
export function px(buf, w, x, y) { const i = (y * w + x) * 4; return [buf[i], buf[i+1], buf[i+2], buf[i+3]]; }
export function row(buf, w, y, x0=0, x1=w) { const out=[]; for (let x=x0;x<x1;x++) out.push(px(buf,w,x,y).join(',')); return out; }
