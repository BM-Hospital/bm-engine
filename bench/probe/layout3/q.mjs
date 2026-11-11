// Ad-hoc oracle queries: node probe/layout3/q.mjs <snippets.mjs> [name-regex]  (from bench/)
// The snippet module default-exports { name: html | {node, w, h} }; prints takumi + bm measure trees and the pixel verdict.
import { pathToFileURL } from "node:url";
import path from "node:path";
import { T, B, fmt } from "../layout2/lib.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import { asset } from "../../fixtures/_h.mjs";
const mod = (await import(pathToFileURL(path.resolve(process.argv[2])).href)).default;
const re = new RegExp(process.argv[3] || ".");
const images = [{ src: "img://avatar", data: asset("avatar.png") }, { src: "img://icon", data: asset("icon.png") }];
const only = process.env.ONLY; // "t" | "b"
for (const [name, v] of Object.entries(mod)) {
  if (!re.test(name)) continue;
  const node = typeof v === "string" ? v : v.node;
  const w = v.w || 400, h = v.h || 200;
  const body = `<style>.page{font-family:Inter;width:100%;height:100%;background:#fff;color:#0f172a;font-size:16px}</style><div class="page">${node}</div>`;
  const o = { width: w, height: h, images };
  console.log("=== " + name);
  let ta, tb;
  if (only !== "b") try { ta = await T.measure(body, o); console.log("takumi:\n" + fmt(ta)); } catch (e) { console.log("takumi ERR", e.message); }
  if (only !== "t") try { tb = await B.measure(body, o); console.log("bm:\n" + fmt(tb)); } catch (e) { console.log("bm ERR", e.message); }
  if (ta && tb) {
    const diffs = [];
    const td = (x, y, path) => {
      const d = [x.width - y.width, x.height - y.height, x.transform[4] - y.transform[4], x.transform[5] - y.transform[5]];
      if (d.some((v) => Math.abs(v) > 0.02)) diffs.push(path || "/");
      if (x.children.length !== y.children.length) { diffs.push((path || "/") + " child count " + x.children.length + " vs " + y.children.length); return; }
      x.children.forEach((k, i) => td(k, y.children[i], path + "/" + i));
    };
    td(ta, tb, "");
    console.log("measure:", diffs.length ? diffs.join(" ; ") : "OK");
  }
  if (!only) try {
    const a = await T.render(body, { ...o, format: "raw" }), b = await B.render(body, { ...o, format: "raw" });
    const m = compare(new Uint8Array(a), new Uint8Array(b), w, h, {});
    console.log("pixels:", verdict(m), "diff%", m.pctStrict.toFixed(3), "ssim", Math.min(m.ssim, m.ssimRgb).toFixed(4));
  } catch (e) { console.log("render ERR", e.message); }
}
