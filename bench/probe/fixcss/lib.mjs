// Shared helpers for the fix-css probes: takumi (@takumi-rs/wasm/node) and bm (js/node.mjs) side by side.
import { Renderer as TR } from "@takumi-rs/wasm/node";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
const HERE = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(HERE, "../../..");
const FONT_DIR = path.join(ROOT, "ref/takumi/assets/fonts/");
export const inter = readFileSync(path.join(ROOT, "assets/fonts/Inter-Regular.ttf"));
export const tk = new TR();
await tk.registerFont({ name: "Inter", data: inter, weight: 400, style: "normal" });
const bmMod = await import(pathToFileURL(path.join(ROOT, "js/node.mjs")).href);
export const bm = new bmMod.Renderer();
bm.registerFont({ name: "Inter", data: inter, weight: 400, style: "normal" });
export const both = async (fn) => { const out = {}; for (const [n, r] of [["tk", tk], ["bm", bm]]) { try { out[n] = await fn(r, n); } catch (e) { out[n] = "ERR " + (e?.message ?? e); } } return out; };
/** Strip measure trees to {w,h,t,c} with numbers rounded to 1/64. */
export const slim = (m) => m && typeof m === "object" ? { w: m.width, h: m.height, t: m.transform, ...(m.children?.length ? { c: m.children.map(slim) } : {}) } : m;
export const px = (buf, w, x, y) => { const i = (y * w + x) * 4; return [buf[i], buf[i + 1], buf[i + 2], buf[i + 3]]; };
