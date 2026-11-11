// Renders + measures one HTML snippet (file path or literal) with bm and prints the wasm stack of a trap:
//   BM_WASM=<unstripped build> node probe/layout3/one.mjs '<div>..</div>' [width] [height]
import { readFileSync, existsSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import { asset } from "../../fixtures/_h.mjs";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
const r = new bm.Renderer();
for (const f of fontsFor()) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
const arg = process.argv[2];
const html = existsSync(arg) ? readFileSync(arg, "utf8") : arg;
const o = { width: +(process.argv[3] || 400), height: +(process.argv[4] || 300), images: [{ src: "img://icon", data: asset("icon.png") }, { src: "img://avatar", data: asset("avatar.png") }] };
try {
  const raw = r.renderSync(html, { ...o, format: "raw" });
  console.log("render ok", raw.length);
  console.log(JSON.stringify(r.measureSync(html, o)).slice(0, 2000));
} catch (e) { console.log(String(e.stack).split("\n").slice(0, 24).join("\n")); }
