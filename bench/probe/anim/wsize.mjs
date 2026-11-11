// Code-size attribution of an UNSTRIPPED wasm (`zig build -Dstrip=false -p <dir>`): sums function body bytes
// per name prefix (first `depth` dotted components, default 2) using the name section; data segments listed
// separately. Usage (from bench/):
//   node probe/anim/wsize.mjs <wasm> [depth] [filter-regex] [top-n functions]
//   node probe/anim/wsize.mjs <wasm> [depth] [filter-regex] --vs=<other.wasm>   per-group delta (wasm - other)
import { readFileSync } from "node:fs";

const argv = process.argv.slice(2);
const vsArg = argv.find((a) => a.startsWith("--vs="));
const pos = argv.filter((a) => !a.startsWith("--"));
const depth = Number(pos[1] || 2);
const filter = pos[2] ? new RegExp(pos[2]) : null;
const topN = Number(pos[3] || 0);

function parse(file) {
  const b = readFileSync(file);
  let p = 8;
  const leb = () => { let r = 0, s = 0, c; do { c = b[p++]; r |= (c & 0x7f) << s; s += 7; } while (c & 0x80); return r >>> 0; };
  let nImports = 0, dataBytes = 0;
  const bodies = [], names = new Map();
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
  return { groups, fns, total, dataBytes };
}

const a = parse(pos[0]);
if (vsArg) {
  const o = parse(vsArg.slice(5));
  console.log(`code ${a.total} vs ${o.total} (${a.total - o.total >= 0 ? "+" : ""}${a.total - o.total}); data ${a.dataBytes} vs ${o.dataBytes}`);
  const keys = new Set([...a.groups.keys(), ...o.groups.keys()]);
  const rows = [...keys].map((k) => [k, a.groups.get(k) || 0, o.groups.get(k) || 0]).sort((x, y) => Math.abs(y[1] - y[2]) - Math.abs(x[1] - x[2]));
  for (const [k, x, y] of rows.slice(0, 60)) console.log(String(x).padStart(8), String(y).padStart(8), String((x - y >= 0 ? "+" : "") + (x - y)).padStart(8), " ", k);
} else {
  console.log(`code ${a.total} bytes in ${a.fns.length} functions; data section ${a.dataBytes} bytes`);
  for (const [k, v] of [...a.groups].sort((x, y) => y[1] - x[1]).slice(0, 60)) console.log(String(v).padStart(8), k);
  if (topN) { a.fns.sort((x, y) => y[0] - x[0]); for (const [s, n] of a.fns.slice(0, topN)) console.log(String(s).padStart(8), "  ", n.slice(0, 140)); }
}
