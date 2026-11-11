import { readFileSync, writeFileSync } from "node:fs";
let s = readFileSync("cmp1.mjs", "utf8");
s = s.replace("return { w: t.width, h: t.height, lines: t.runs };", `const lines = [];
  for (const q of t.runs) { const l = lines[lines.length - 1];
    if (l && Math.abs(l.y - q.y) < 0.01) { l.text += q.text; l.width = q.x + q.width - l.x; } else lines.push({ ...q }); }
  return { w: t.width, h: t.height, lines };`);
writeFileSync("cmp1.mjs", s);
