// Compact measure-tree printer shared by the layout2 probes.
const r = (v) => Math.round(v * 100) / 100;
export const fmt = (x, ind = "", runs = true) => {
  let s = `${ind}${r(x.width)}x${r(x.height)} @${r(x.transform[4])},${r(x.transform[5])}` + (runs && x.runs?.length ? ` runs=${x.runs.length}[` + x.runs.map((q) => `${JSON.stringify(q.text ?? "")}:${r(q.x)},${r(q.y)} ${r(q.width)}x${r(q.height)}`).join(" | ") + "]" : "") + "\n";
  for (const c of x.children) s += fmt(c, ind + "  ", runs);
  return s;
};
