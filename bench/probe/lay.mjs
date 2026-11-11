// usage: node probe/lay.mjs <case-id> [tol]  -> compares measure() trees of takumi vs bm
import { ALL_CASES } from "../fixtures/index.mjs";
import tw from "../engines/takumi-wasm.mjs";
import bm from "../engines/bm.mjs";
import { fontsFor } from "../lib/fonts.mjs";
const re = new RegExp(process.argv[2] || ".");
const tol = +(process.argv[3] || 0.02);
const A = await tw.create({ fonts: fontsFor() });
const B = await bm.create({ fonts: fontsFor() });
for (const c of ALL_CASES.filter((k) => re.test(k.id))) {
  const opts = { width: c.width, height: c.height, images: c.images };
  let a, b;
  try { a = await A.measure(c.node, opts); b = await B.measure(c.node, opts); } catch (e) { console.log(c.id, "ERR", e.message); continue; }
  let n = 0;
  const walk = (x, y, path) => {
    const d = [x.width - y.width, x.height - y.height, x.transform[4] - y.transform[4], x.transform[5] - y.transform[5]];
    if (d.some((v) => Math.abs(v) > tol)) { if (n++ < 8) console.log(c.id, path, "takumi", x.width, x.height, x.transform[4], x.transform[5], "bm", y.width, y.height, y.transform[4], y.transform[5]); }
    if (x.children.length !== y.children.length) { if (n++ < 8) console.log(c.id, path, "child count", x.children.length, y.children.length); return; }
    x.children.forEach((k, i) => walk(k, y.children[i], path + "/" + i));
  };
  walk(a, b, "");
  console.log(c.id, n ? `${n} diffs` : "layout OK");
}
