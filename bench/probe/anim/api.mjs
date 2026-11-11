// JS API parity smoke test for js/index.mjs (takumi Renderer surface). Usage (from bench/): node probe/anim/api.mjs
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_engine.wasm"));
bm.setGlyphCacheMaxBytes(1 << 20);
const font = readFileSync("../src/font/testdata/Inter-Regular.ttf");
const node = { type: "container", style: { width: 16, height: 16, backgroundColor: "red" }, children: [{ type: "text", text: "a" }] };
{
  using r = new bm.Renderer({ cacheMaxBytes: 1 });
  console.log("registerFont(async data)", (await r.registerFont({ name: "X", data: async () => font }))[0].name);
  console.log("unregisterFont({name})", r.unregisterFont({ name: "X" }));
  const fams = await (async () => { const out = await r.render(node, { width: 16, height: 16, fonts: [{ name: "Y", data: font }] }); return out.length > 0; })();
  console.log("render with fonts option", fams);
  const p = await r.prepare(node, { width: 16, height: 16, css: [], images: [{ src: "x", data: () => new Uint8Array(1) }] });
  console.log("prepare -> render png", (await r.render(p, { format: "png" })).slice(1, 4).toString());
  console.log("prepare -> measure", (await r.measure(p)).width);
  console.log("renderAsDataUrl ico", (await r.renderAsDataUrl(node, { width: 16, height: 16, format: "ico" })).slice(0, 24));
  try { await r.renderSvg(node); } catch (e) { console.log("renderSvg:", e.message); }
  const pa = await r.prepareAnimation({ scenes: [{ node, durationMs: 100 }], width: 16, height: 16, fps: 20, format: "gif" });
  console.log("prepareAnimation -> renderAnimation", String.fromCharCode(...(await r.renderAnimation(pa)).slice(0, 6)));
  const ac = new AbortController(); ac.abort();
  try { await r.render(node, { width: 16, height: 16, signal: ac.signal }); } catch (e) { console.log("aborted:", e.name); }
}
