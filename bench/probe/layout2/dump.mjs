// usage: node probe/layout2/dump.mjs <case-id-regex> -> prints takumi and bm measure trees (compact)
import { ALL_CASES } from "../../fixtures/index.mjs";
import tw from "../../engines/takumi-wasm.mjs";
import bm from "../../engines/bm.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
const re = new RegExp(process.argv[2] || ".");
const A = await tw.create({ fonts: fontsFor() });
const B = await bm.create({ fonts: fontsFor() });
const fmt = (x, ind = "") => {
  const r = (v) => Math.round(v * 100) / 100;
  let s = `${ind}${r(x.width)}x${r(x.height)} @${r(x.transform[4])},${r(x.transform[5])}` + (x.runs?.length ? ` runs=${x.runs.length}[` + x.runs.map((q) => `${JSON.stringify(q.text ?? "")}:${r(q.x)},${r(q.y)} ${r(q.width)}x${r(q.height)}`).join(" | ") + "]" : "") + "\n";
  for (const c of x.children) s += fmt(c, ind + "  ");
  return s;
};
for (const c of ALL_CASES.filter((k) => re.test(k.id))) {
  const opts = { width: c.width, height: c.height, images: c.images, ...(c.opts || {}) };
  console.log("=== " + c.id);
  try { console.log("takumi:\n" + fmt(await A.measure(c.node, opts))); } catch (e) { console.log("takumi ERR", e.message); }
  try { console.log("bm:\n" + fmt(await B.measure(c.node, opts))); } catch (e) { console.log("bm ERR", e.message); }
}
