// Prints "<id> <hash>" of the raw render of every fixture (to diff two wasm builds for regressions).
// Usage: BM_WASM=... node probe/frontend/hashes.mjs > a.txt
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import * as bm from "../../../js/index.mjs";
import { ALL_CASES } from "../../fixtures/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer();
for (const f of fontsFor()) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
for (const k of ALL_CASES) {
  if (k.feature && /css-stylesheet|tailwind|html|pseudo/.test(k.feature)) continue;
  let h;
  try { h = createHash("sha1").update(r.renderSync(k.node, { width: k.width, height: k.height, format: "raw", images: k.images })).digest("hex").slice(0, 12); }
  catch (e) { h = "ERR " + String(e.message).slice(0, 60); }
  console.log(k.id, h);
}
