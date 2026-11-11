// Probe: <br> forced breaks and list items (HTML) — heights, bm vs takumi.
import { readFileSync } from "node:fs";
import * as bm from "file:///D:/project/bm-engine/js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer(); const t = new TR();
const font = readFileSync("D:/project/bm-engine/assets/fonts/Inter-Regular.ttf");
r.registerFont(font); await t.registerFont(font);
for (const src of ["<p style='margin:0;font-family:Inter'>one<br>two</p>", "<ul style='margin:0'><li>a</li><li>b</li></ul>"]) {
  const a = await t.measure(src, { width: 300, height: 100 });
  const b = r.measureSync(src, { width: 300, height: 100 });
  console.log(src, "takumi h", a.height, JSON.stringify(a.children?.[0]?.height ?? null), "| bm h", b.height, JSON.stringify(b.children?.[0]?.height ?? null));
}
