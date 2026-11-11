import takumi from "../engines/takumi-wasm.mjs";
import { FONTS } from "../lib/fonts.mjs";
import { ALL_CASES } from "../fixtures/index.mjs";
const r = await takumi.create({ fonts: FONTS });
for (const k of ALL_CASES) {
  try { const t=performance.now(); const o = await r.render(k.node, { width: k.width, height: k.height, format: "raw", images: k.images }); console.log("ok ", k.id, o.length === k.width*k.height*4, (performance.now()-t).toFixed(1)); }
  catch (e) { console.log("ERR", k.id, String(e.message ?? e).slice(0, 300)); }
}
