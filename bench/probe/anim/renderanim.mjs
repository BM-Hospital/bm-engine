// renderAnimation oracle comparison: the same 2-scene animation rendered by @takumi-rs/wasm and bm-render in
// every format. Compares the container frame lists (count + per-frame delays, parsed here without any codec)
// and the pixels of every frame: both outputs are decoded by takumi itself (an `image` node whose src is the
// animation, sampled with `timeMs` = frame start, takumi's animated-source frame selection).
// Usage (from bench/): BM_WASM=../zig-out/bin/bm_render.wasm node probe/anim/renderanim.mjs [fps]
import { readFileSync } from "node:fs";
import * as bm from "../../../js/index.mjs";
import { Renderer as TR } from "@takumi-rs/wasm/node";
import { fontsFor } from "../../lib/fonts.mjs";
import { compare } from "../../lib/metrics.mjs";

bm.initSync(readFileSync(process.env.BM_WASM || "../zig-out/bin/bm_render.wasm"));
const r = new bm.Renderer();
const t = new TR();
for (const f of fontsFor()) {
  const data = readFileSync(f.path);
  r.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
  await t.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
}

const u16 = (b, o) => b[o] | (b[o + 1] << 8);
const be32 = (b, o) => ((b[o] << 24) >>> 0) + (b[o + 1] << 16) + (b[o + 2] << 8) + b[o + 3];
/** Frame delays (ms) of an APNG / animated WebP / GIF. */
function frames(b) {
  const out = [];
  if (b[0] === 0x89 && b[1] === 0x50) {
    for (let o = 8; o + 8 <= b.length;) {
      const len = be32(b, o);
      const type = String.fromCharCode(...b.subarray(o + 4, o + 8));
      if (type === "fcTL") {
        const d = o + 8;
        const num = (b[d + 20] << 8) | b[d + 21];
        const den = ((b[d + 22] << 8) | b[d + 23]) || 100;
        out.push(Math.round((num * 1000) / den));
      }
      o += 12 + len;
    }
  } else if (String.fromCharCode(...b.subarray(0, 4)) === "RIFF") {
    for (let o = 12; o + 8 <= b.length;) {
      const type = String.fromCharCode(...b.subarray(o, o + 4));
      const len = b[o + 4] | (b[o + 5] << 8) | (b[o + 6] << 16) | (b[o + 7] << 24);
      if (type === "ANMF") out.push(b[o + 8 + 12] | (b[o + 8 + 13] << 8) | (b[o + 8 + 14] << 16));
      o += 8 + len + (len & 1);
    }
  } else if (String.fromCharCode(...b.subarray(0, 3)) === "GIF") {
    let o = 13;
    if (b[10] & 0x80) o += 3 * (1 << ((b[10] & 7) + 1));
    let delay = 0;
    const skip = () => { while (b[o] !== 0) o += b[o] + 1; o += 1; };
    while (o < b.length) {
      const k = b[o];
      if (k === 0x3b) break;
      if (k === 0x21) {
        if (b[o + 1] === 0xf9) delay = u16(b, o + 4) * 10;
        o += 2;
        skip();
      } else if (k === 0x2c) {
        const flags = b[o + 9];
        o += 10;
        if (flags & 0x80) o += 3 * (1 << ((flags & 7) + 1));
        o += 1; // LZW min code size
        skip();
        out.push(delay);
      } else break;
    }
  }
  return out;
}

const W = 240, H = 120;
const card = (bg, label) => ({ type: "container", className: "card", style: { width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", backgroundColor: bg }, children: [
  { type: "container", className: "dot", style: { width: 50, height: 50, borderRadius: 25, backgroundColor: "#f97316" } },
  { type: "text", text: label, style: { fontFamily: "Inter", fontSize: 28, color: "#0f172a", marginLeft: 12 } },
] });
const css = ["@keyframes slide { from { transform: translateX(-60px); opacity: 0.25 } to { transform: translateX(60px); opacity: 1 } } .dot { animation: slide 600ms ease-in-out both }"];
const fps = Number(process.argv[2] || 10);
const opts = { scenes: [{ node: card("#e0f2fe", "One"), durationMs: 600 }, { node: card("#fef3c7", "Two"), durationMs: 450 }], width: W, height: H, fps, css };

const decodeAt = async (bytes, ms) => new Uint8Array(await t.render({ type: "image", src: bytes, style: { width: W, height: H } }, { width: W, height: H, format: "raw", timeMs: ms, images: [] }));

for (const format of ["webp", "apng", "gif"]) {
  let a, b;
  try { a = new Uint8Array(await t.renderAnimation({ ...opts, format })); } catch (e) { console.log(format, "takumi error", e.message); continue; }
  try { b = r.renderAnimationSync({ ...opts, format }); } catch (e) { console.log(format, "bm error", e.message); continue; }
  const fa = frames(a), fb = frames(b);
  console.log(`${format.padEnd(5)} bytes takumi ${a.length} bm ${b.length}; frames takumi ${fa.length} [${fa.join(",")}] bm ${fb.length} [${fb.join(",")}]`);
  // per-frame pixels at every frame start of the takumi schedule
  let start = 0, worst = { ssim: 1, pct: 0 };
  const rows = [];
  for (const d of fa) {
    const pa = await decodeAt(a, start), pb = await decodeAt(b, start);
    const m = compare(pa, pb, W, H, {});
    rows.push(`${start}:${m.pctStrict.toFixed(2)}%/${m.ssim.toFixed(4)}`);
    if (m.ssim < worst.ssim) worst = { ssim: m.ssim, pct: m.pctStrict };
    start += d;
  }
  console.log("      per frame (start ms: diff% / ssim)", rows.join("  "));
  console.log(`      worst frame ssim ${worst.ssim.toFixed(4)} diff% ${worst.pct.toFixed(2)}`);
}
