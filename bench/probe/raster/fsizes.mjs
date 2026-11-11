// Lists the largest functions of an unstripped wasm (code-section body sizes + name section).
//   node probe/raster/fsizes.mjs file.wasm [top=30]
import { readFileSync } from "node:fs";
const b = readFileSync(process.argv[2]); let p = 8;
const leb = () => { let r = 0, s = 0, c; do { c = b[p++]; r |= (c & 127) << s; s += 7; } while (c & 128); return r >>> 0; };
let nimp = 0; const sizes = []; const names = new Map();
while (p < b.length) {
  const id = b[p++], len = leb(), end = p + len;
  if (id === 2) { const n = leb(); for (let i = 0; i < n; i++) { let l = leb(); p += l; l = leb(); p += l; const k = b[p++]; if (k === 0) { leb(); nimp++; } else if (k === 1) { p++; const f = b[p++]; leb(); if (f & 1) leb(); } else if (k === 2) { const f = b[p++]; leb(); if (f & 1) leb(); } else if (k === 3) p += 2; } }
  else if (id === 10) { const n = leb(); for (let i = 0; i < n; i++) { const l = leb(); sizes.push(l); p += l; } }
  else if (id === 0) { const l = leb(); const nm = b.subarray(p, p + l).toString(); p += l; if (nm === "name") { while (p < end) { const sid = b[p++], sl = leb(), se = p + sl; if (sid === 1) { const n = leb(); for (let i = 0; i < n; i++) { const idx = leb(), l2 = leb(); names.set(idx, b.subarray(p, p + l2).toString()); p += l2; } } p = se; } } }
  p = end;
}
const rows = sizes.map((s, i) => [s, names.get(i + nimp) || "f" + (i + nimp)]).sort((x, y) => y[0] - x[0]);
console.log("functions", sizes.length, "code bytes", sizes.reduce((x, y) => x + y, 0));
for (const [s, n] of rows.slice(0, +(process.argv[3] || 30))) console.log(String(s).padStart(7), n.slice(0, 100));
