// Sanity check for fixtures/anim.mjs: each time sample must change the image (in both engines), so the
// oracle comparison is not vacuous. Prints a short hash per engine per case.
// Usage (from bench/): node probe/anim/vary.mjs
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
import anim from "../../fixtures/anim.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_render.wasm"));
const r = new bm.Renderer();
const t = new TR();
for (const f of fontsFor()) {
  const data = readFileSync(f.path);
  r.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
  await t.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
}
const h = (b) => createHash("sha1").update(b).digest("hex").slice(0, 8);
for (const k of anim) {
  const o = { width: k.width, height: k.height, format: "raw", ...(k.opts || {}) };
  console.log(k.id.padEnd(24), "takumi", h(await t.render(k.node, o)), "bm", h(r.renderSync(k.node, o)));
}
