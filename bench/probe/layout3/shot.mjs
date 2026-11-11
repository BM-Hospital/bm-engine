// Snapshot of one q.mjs snippet in both engines: node probe/layout3/shot.mjs <snippets.mjs> <name> <outdir> [w] [h] -> takumi.png, bm.png
import { pathToFileURL } from "node:url";
import path from "node:path";
import { writeFileSync, mkdirSync } from "node:fs";
import { T, B } from "../layout2/lib.mjs";
import { asset } from "../../fixtures/_h.mjs";
const mod = (await import(pathToFileURL(path.resolve(process.argv[2])).href)).default;
const v = mod[process.argv[3]];
const node = typeof v === "string" ? v : v.node;
const body = `<style>.page{font-family:Inter;width:100%;height:100%;background:#fff;color:#0f172a;font-size:16px}</style><div class="page">${node}</div>`;
const images = [{ src: "img://avatar", data: asset("avatar.png") }, { src: "img://icon", data: asset("icon.png") }];
const o = { width: +(process.argv[5] || 240), height: +(process.argv[6] || 110), images, devicePixelRatio: +(process.env.DPR || 1) };
mkdirSync(process.argv[4], { recursive: true });
writeFileSync(process.argv[4] + "/takumi.png", Buffer.from(await T.render(body, { ...o, format: "png" })));
writeFileSync(process.argv[4] + "/bm.png", Buffer.from(await B.render(body, { ...o, format: "png" })));
