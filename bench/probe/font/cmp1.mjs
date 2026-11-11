import { r, reg } from "./olib.mjs";
import { mine, regMine } from "./mine.mjs";
reg(); regMine();
export async function oracle(text, st, width) {
  const tn = { type: "text", text, style: { display: "block", ...st } };
  const node = width == null ? { type: "container", style: { display: "flex", alignItems: "flex-start" }, children: [tn] }
                             : { type: "container", style: { display: "block", width }, children: [tn] };
  const m = await r.measure(node, { width: 3000, height: 3000 });
  const t = m.children[0] ?? { width: 0, height: 0, runs: [] };
  const lines = [];
  for (const q of t.runs) { const l = lines[lines.length - 1];
    if (l && Math.abs(l.y - q.y) < 0.01) { l.text += q.text; l.width = q.x + q.width - l.x; } else lines.push({ ...q }); }
  return { w: t.width, h: t.height, lines };
}
let bad = 0, total = 0;
export async function cmp(text, st = {}, width = null, verbose = false) {
  const o = await oracle(text, st, width), m = mine(text, st, width); m.lines = m.lines.filter(l => l.n > 0);
  total++;
  const ow = width == null ? o.w : Math.max(0, ...o.lines.map(l => l.width));
  const mw = width == null ? m.w : Math.max(0, ...m.lines.map(l => l.width));
  let ok = Math.abs(o.h - m.h) < 1e-3 && o.lines.length === m.lines.length && Math.abs(ow - mw) < 0.02;
  if (ok) for (let i = 0; i < o.lines.length; i++) if (Math.abs(o.lines[i].width - m.lines[i].width) > 0.02 || Math.abs(o.lines[i].x - m.lines[i].x) > 0.02) ok = false;
  if (!ok) bad++;
  if (!ok || verbose) {
    console.log(ok ? "OK  " : "DIFF", JSON.stringify(text.slice(0, 50)), JSON.stringify(st), width, `| oracle w=${o.w} h=${o.h} lines=${o.lines.length} | mine w=${m.w} h=${m.h} lines=${m.lines.length}`);
    const n = Math.max(o.lines.length, m.lines.length);
    for (let i = 0; i < n; i++) { const a = o.lines[i], b = m.lines[i];
      console.log("    ", a ? `${JSON.stringify(a.text)} x=${a.x} y=${a.y} w=${a.width}` : "-", " || ", b ? `${JSON.stringify(b.text)} x=${b.x} top=${b.top} bl=${b.baseline} w=${b.width} h=${b.height}` : "-"); }
  }
  return ok;
}
export const summary = () => console.log(`${total - bad}/${total} match`);
