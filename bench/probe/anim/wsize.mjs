// Code-size attribution of an UNSTRIPPED wasm (`zig build -Dstrip=false -p <dir>`): sums function body bytes
// per name prefix (first `depth` dotted components, default 2) using the name section; data segments listed
// separately. Usage (from bench/): node probe/anim/wsize.mjs <wasm> [depth] [filter-regex] [top-n functions]
import { readFileSync } from "node:fs";

const b = readFileSync(process.argv[2]);
const depth = Number(process.argv[3] || 2);
const filter = process.argv[4] ? new RegExp(process.argv[4]) : null;
const topN = Number(process.argv[5] || 0);
let p = 8;
const leb = () => { let r = 0, s = 0, c; do { c = b[p++]; r |= (c & 0x7f) << s; s += 7; } while (c & 0x80); return r >>> 0; };
let nImports = 0, bodies = [], names = new Map(), dataBytes = 0;
while (p < b.length) {
  const id = b[p++];
  const len = leb();
  const end = p + len;
  if (id === 2) { // imports
    const n = leb();
    for (let i = 0; i < n; i++) { let l = leb(); p += l; l = leb(); p += l; const k = b[p++]; if (k === 0) { leb(); nImports++; } else if (k === 1) { p++; const f = b[p++]; leb(); if (f & 1) leb(); } else if (k === 2) { const f = b[p++]; leb(); if (f & 1) leb(); } else { p += 2; } }
  } else if (id === 10) {
    const n = leb();
    for (let i = 0; i < n; i++) { const sz = leb(); bodies.push(sz); p += sz; }
  } else if (id === 11) {
    dataBytes = len;
  } else if (id === 0) {
    const nl = leb();
    const nm = b.subarray(p, p + nl).toString();
    p += nl;
    if (nm === "name") {
      while (p < end) {
        const sid = b[p++];
        const sl = leb();
        const se = p + sl;
        if (sid === 1) {
          const n = leb();
          for (let i = 0; i < n; i++) { const idx = leb(); const l = leb(); names.set(idx, b.subarray(p, p + l).toString()); p += l; }
        }
        p = se;
      }
    }
  }
  p = end;
}
const groups = new Map();
const fns = [];
let total = 0;
bodies.forEach((sz, i) => {
  const name = names.get(i + nImports) || `f${i}`;
  if (filter && !filter.test(name)) return;
  const key = name.split(/[.(]/).slice(0, depth).join(".");
  groups.set(key, (groups.get(key) || 0) + sz);
  fns.push([sz, name]);
  total += sz;
});
console.log(`code ${total} bytes in ${fns.length} functions; data section ${dataBytes} bytes`);
for (const [k, v] of [...groups].sort((x, y) => y[1] - x[1]).slice(0, 60)) console.log(String(v).padStart(8), k);
if (topN) { fns.sort((x, y) => y[0] - x[0]); for (const [s, n] of fns.slice(0, topN)) console.log(String(s).padStart(8), "  ", n.slice(0, 140)); }
