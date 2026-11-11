import { r } from "./olib.mjs";
import { cmp, summary } from "./cmp1.mjs";
import { mine } from "./mine.mjs";
// multi-run
const parts = ["Hello small ", "BIG World", " and small again to wrap lines ", "Tiny Vast", " end."];
let bad = 0, tot = 0;
for (const [famA, sA, famB, sB] of [["Inter", 16, "Noto Sans", 28], ["Roboto", 20, "Inter", 12], ["Noto Sans", 14, "Roboto", 40]])
for (const lh of [undefined, 1.5, "30px"]) for (const w of [1000, 400, 150, 90]) {
  const A = { fontFamily: famA, fontSize: sA }, B = { fontFamily: famB, fontSize: sB };
  const node = { type: "container", style: { display: "block", width: w, ...A, lineHeight: lh }, children: parts.map((t, i) => ({ type: "text", text: t, style: i & 1 ? B : {} })) };
  const o = await r.measure(node, { width: 2000, height: 2000 });
  const m = mine(parts.join("\x01"), { ...A, lineHeight: lh, famB, sizeB: sB }, w);
  // oracle lines: group by (y of small-run) is unreliable; compare height + per-line right edge
  const ends = []; let last = -1;
  for (const q of o.runs) { if (q.x < last - 0.001 || last < 0) ends.push(0); ends[ends.length - 1] = q.x + q.width; last = q.x + q.width; }
  const ok = Math.abs(o.height - m.h) < 1e-3 && ends.length === m.lines.length && ends.every((e, i) => Math.abs(e - m.lines[i].width) < 0.02);
  tot++; if (!ok) { bad++; console.log("DIFF", famA, sA, famB, sB, lh, w, "oracle h", o.height, ends, "| mine h", m.h, m.lines.map(l => l.width)); }
}
console.log(`multi-run ${tot - bad}/${tot}`);
for (const fam of ["Inter", "Roboto", "Nope"]) for (const lh of [undefined, 1.3]) for (const w of [null, 300]) await cmp("aΩऄ\u2c60\u1e9e\ua722b\u4e2d fallback Ⱡ test Ꜣ", { fontFamily: fam, fontSize: 30, lineHeight: lh }, w);
summary();
