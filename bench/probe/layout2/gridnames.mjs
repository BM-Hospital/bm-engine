// takumi probes: named grid line resolution (negative n, lone names, -start/-end, unknown names, span name).
import { T, B } from "./lib.mjs";
const cols = "[a] 10px [b] 20px [a] 30px [c-start] 40px [c-end] 50px [a]";
const tests = [
  "a", "2 a", "3 a", "4 a", "-1 a", "-2 a", "-3 a", "a -4", "b", "c", "c / c", "zzz", "2 zzz", "-1 zzz", "b / span a", "span a / 6", "span 2 a / 6", "a / span 2 a", "c-start / c-end", "span a", "b / span zzz", "a / span c-end", "span c-start / 6", "b / span 3", "a / a", "zzz / zzz", "b / zzz", "zzz / b", "span zzz / 3", "c-end / c-start",
];
for (const gc of tests) {
  const node = { type: "container", style: { display: "grid", gridTemplateColumns: cols, gridTemplateRows: "10px", width: 400 }, children: [{ type: "container", style: { gridColumn: gc, gridRow: "1", height: 10 } }] };
  let a, b;
  try { a = await T.measure(node, { width: 400, height: 50 }); } catch (e) { console.log(gc.padEnd(16), "takumi ERR", String(e.message).slice(0, 70)); continue; }
  b = await B.measure(node, { width: 400, height: 50 });
  const f = (m) => { const k = m.children[0]; return `x=${k.transform[4]} w=${k.width}`; };
  console.log(gc.padEnd(16), "takumi", f(a).padEnd(16), "bm", f(b));
}
