// Compares the raster module's coverage (mode skia_ss by default) with takumi / tiny-skia, pixel by pixel.
// usage (from bench/):  node probe/raster/skia_oracle.mjs <skia.wasm> [mode=2] [verbose]
// Build (repo root; ZIG = zig 0.17.1):
//   ZIG build-exe -target wasm32-freestanding -mcpu=generic+simd128+bulk_memory+sign_ext+nontrapping_fptoint+mutable_globals -O ReleaseSmall -fno-entry -rdynamic -fstrip -femit-bin=skia.wasm --dep raster -Mroot=bench/probe/raster/skia_root.zig -Mraster=src/raster/raster.zig
import { readFileSync } from "node:fs";
import { Renderer } from "@takumi-rs/wasm/node";

const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]), {});
const ex = instance.exports;
const MODE = +(process.argv[3] ?? 2);
const VERBOSE = process.argv[4];
const tk = new Renderer();

// takumi: alpha channel of a white shape on a transparent canvas = coverage
async function oracle(w, h, child) {
  const node = { type: "container", style: { width: w, height: h, display: "flex" }, children: [child] };
  const px = new Uint8Array(await tk.render(node, { width: w, height: h, format: "raw" }));
  const a = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) a[i] = px[i * 4 + 3];
  return a;
}
function mine(w, h, evenodd = 0, t = [1, 0, 0, 1, 0, 0]) {
  const ptr = ex.raster(w, h, MODE, evenodd, ...t);
  return new Uint8Array(ex.memory.buffer, ptr, w * h).slice();
}

const totals = {};
function compare(group, name, a, b, w, h) {
  let edge = 0, same = 0, max = 0, all = 0, first = null;
  const hist = {};
  for (let i = 0; i < w * h; i++) {
    const isEdge = (a[i] !== 0 && a[i] !== 255) || (b[i] !== 0 && b[i] !== 255) || a[i] !== b[i];
    if (!isEdge) continue;
    edge++;
    const d = Math.abs(a[i] - b[i]);
    if (d === 0) same++;
    else { all++; if (d > max) max = d; first ??= i; hist[b[i] - a[i]] = (hist[b[i] - a[i]] || 0) + 1; }
  }
  const t = (totals[group] ??= { edge: 0, same: 0, max: 0, cases: 0, exact: 0 });
  t.edge += edge; t.same += same; t.max = Math.max(t.max, max); t.cases++; if (all === 0) t.exact++;
  if (VERBOSE || all) {
    let extra = "";
    if (first !== null) extra = ` first@(${first % w},${(first / w) | 0}) takumi=${a[first]} mine=${b[first]}` + (VERBOSE ? " hist " + JSON.stringify(hist) : "");
    console.log(`  ${name.padEnd(52)} edge px ${String(edge).padStart(5)}  identical ${(edge ? (same / edge) * 100 : 100).toFixed(2).padStart(6)}%  max diff ${max}${extra}`);
  }
}

const cases = [];
// ---- rounded rects / ellipses (CSS border-radius)
function rrect(group, w, h, x, y, bw, bh, radii, css) {
  cases.push(async () => {
    const a = await oracle(w, h, { type: "container", style: { position: "absolute", left: x, top: y, width: bw, height: bh, backgroundColor: "white", borderRadius: css } });
    ex.path_reset();
    ex.path_rrect(x, y, bw, bh, ...radii.flat());
    compare(group, `${bw}x${bh}@(${x},${y}) radius ${css}`, a, mine(w, h), w, h);
  });
}
const uni = (r) => [[r, r], [r, r], [r, r], [r, r]];
for (const [bw, bh, r] of [[40, 40, 8], [100, 60, 12], [100, 60, 30], [220, 160, 32], [220, 160, 80], [300, 80, 40], [64, 64, 20], [17, 13, 5], [200, 200, 3], [120, 40, 20], [33, 47, 9.5], [90, 90, 0.75]])
  for (const [x, y] of [[0, 0], [7, 11], [100, 50]]) rrect("rounded rect", 420, 300, x, y, bw, bh, uni(r), `${r}px`);
rrect("rounded rect", 420, 300, 10, 10, 220, 160, [[10, 10], [40, 40], [70, 70], [100, 100]], "10px 40px 70px 100px");
rrect("rounded rect", 420, 300, 10, 10, 220, 160, [[100, 30], [100, 30], [100, 30], [100, 30]], "100px / 30px");
rrect("rounded rect", 420, 300, 10, 10, 220, 160, [[40, 10], [10, 40], [40, 10], [10, 40]], "40px 10px / 10px 40px");
rrect("rounded rect", 420, 300, 3, 5, 220, 160, [[66, 48], [154, 48], [154, 112], [66, 112]], "30% 70% 70% 30% / 30% 30% 70% 70%");
rrect("rounded rect", 1200, 630, 0, 0, 1200, 630, uni(48), "48px");
for (const [bw, bh] of [[40, 40], [180, 180], [220, 160], [41, 41], [7, 7], [300, 80], [80, 300], [101, 67], [16, 16], [23, 9]])
  for (const [x, y] of [[0, 0], [5, 9], [60, 30]]) rrect("ellipse", 420, 420, x, y, bw, bh, uni(0).map(() => [bw / 2, bh / 2]), "50%");
rrect("ellipse", 1200, 630, 0, 0, 1200, 630, uni(0).map(() => [600, 315]), "50%");
rrect("ellipse", 1200, 630, 100, 15, 1000, 600, uni(0).map(() => [500, 300]), "50%");

// ---- transformed boxes (CSS transform about the box centre)
function xform(group, w, h, x, y, bw, bh, r, css, m) {
  cases.push(async () => {
    const a = await oracle(w, h, { type: "container", style: { position: "absolute", left: x, top: y, width: bw, height: bh, backgroundColor: "white", borderRadius: r, transform: css } });
    ex.path_reset();
    const mode = process.env.XF || "local";
    const cx = x + bw / 2, cy = y + bh / 2;
    let t;
    if (mode === "local") {
      // path at the origin, transform = T(pos + c) * M * T(-c)
      ex.path_rrect(0, 0, bw, bh, ...uni(r).flat());
      const lx = bw / 2, ly = bh / 2;
      t = [m[0], m[1], m[2], m[3], cx - (m[0] * lx + m[2] * ly), cy - (m[1] * lx + m[3] * ly)];
    } else {
      // path in page space, transform = T(c) * M * T(-c)
      ex.path_rrect(x, y, bw, bh, ...uni(r).flat());
      t = [m[0], m[1], m[2], m[3], cx - (m[0] * cx + m[2] * cy), cy - (m[1] * cx + m[3] * cy)];
    }
    compare(group, `${bw}x${bh}@(${x},${y}) r${r} ${css}`, a, mine(w, h, 0, t), w, h);
  });
}
const rot = (deg) => { const a = (deg * Math.PI) / 180; return [Math.cos(a), Math.sin(a), -Math.sin(a), Math.cos(a)]; };
for (const deg of [5, 10, 30, 45, 60, 90, 137]) {
  xform("rotated rect", 400, 400, 120, 140, 160, 100, 0, `rotate(${deg}deg)`, rot(deg));
  xform("rotated rounded rect", 400, 400, 120, 140, 160, 100, 24, `rotate(${deg}deg)`, rot(deg));
}
xform("scaled rounded rect", 400, 400, 120, 140, 160, 100, 24, "scale(1.37)", [1.37, 0, 0, 1.37]);
xform("scaled rounded rect", 400, 400, 120, 140, 160, 100, 24, "scale(0.5, 1.25)", [0.5, 0, 0, 1.25]);
xform("scaled rounded rect", 400, 400, 120, 140, 160, 100, 50, "scale(0.731)", [0.731, 0, 0, 0.731]);

// ---- arbitrary paths with lines / quads / cubics (clip-path: path()), nonzero and evenodd
function clip(group, w, h, d, rule = "nonzero") {
  cases.push(async () => {
    const a = await oracle(w, h, { type: "container", style: { position: "absolute", left: 0, top: 0, width: w, height: h, backgroundColor: "white", clipPath: `path(${rule === "evenodd" ? "evenodd, " : ""}"${d}")` } });
    ex.path_reset();
    const tok = d.match(/[MLQCZ]|-?[\d.]+/g);
    for (let i = 0; i < tok.length;) {
      const c = tok[i++], n = { M: 2, L: 2, Q: 4, C: 6, Z: 0 }[c];
      const v = tok.slice(i, i + n).map(Number); i += n;
      ({ M: ex.path_move, L: ex.path_line, Q: ex.path_quad, C: ex.path_cubic, Z: ex.path_close })[c](...v);
    }
    compare(group, `${rule} ${d.slice(0, 44)}`, a, mine(w, h, rule === "evenodd" ? 1 : 0), w, h);
  });
}
clip("polygon path", 200, 200, "M 20 10 L 180 40 L 150 190 L 30 150 Z");
clip("polygon path", 200, 200, "M 100.5 10.25 L 190.75 100.5 L 100.5 190.25 L 10.25 100.5 Z");
clip("polygon path", 200, 200, "M 100 10 L 124 76 L 195 78 L 138 121 L 159 190 L 100 149 L 41 190 L 62 121 L 5 78 L 76 76 Z");
clip("polygon path", 200, 200, "M 100 10 L 159 190 L 5 78 L 195 78 L 41 190 Z");
clip("polygon path", 200, 200, "M 100 10 L 159 190 L 5 78 L 195 78 L 41 190 Z", "evenodd");
clip("quad path", 200, 200, "M 20 100 Q 100 -40 180 100 Q 100 240 20 100 Z");
clip("quad path", 200, 200, "M 30 30 Q 100 5 170 30 Q 195 100 170 170 Q 100 195 30 170 Q 5 100 30 30 Z");
clip("quad path", 200, 200, "M 10.5 20.25 Q 60.75 80.5 110.25 20.75 Q 150.5 60.25 190.75 30.5 L 180.25 180.75 Q 100.5 120.25 20.75 170.5 Z");
clip("quad path", 64, 64, "M 12 50 Q 12 12 32 12 Q 52 12 52 50 L 44 50 Q 44 20 32 20 Q 20 20 20 50 Z");
clip("quad path", 40, 40, "M 5.25 30.5 Q 5.25 5.75 20.5 5.75 Q 34.75 5.75 34.75 30.5 L 29.5 30.5 Q 29.5 11.25 20.5 11.25 Q 10.75 11.25 10.75 30.5 Z");
clip("cubic path", 200, 200, "M 20 100 C 20 20 180 20 180 100 C 180 180 20 180 20 100 Z");
clip("cubic path", 200, 200, "M 10 100 C 60 -50 140 250 190 100 L 190 190 L 10 190 Z");
clip("cubic path", 200, 200, "M 30.5 40.25 C 90.75 10.5 60.25 170.75 150.5 120.25 C 190.25 90.5 170.75 30.25 120.5 60.75 C 80.25 90.5 60.75 60.25 30.5 40.25 Z");
clip("cubic path", 200, 200, "M 100 20 C 180 20 180 180 100 180 C 20 180 20 20 100 20 Z M 100 60 C 60 60 60 140 100 140 C 140 140 140 60 100 60 Z");
clip("cubic path", 200, 200, "M 100 20 C 180 20 180 180 100 180 C 20 180 20 20 100 20 Z M 100 60 C 140 60 140 140 100 140 C 60 140 60 60 100 60 Z", "evenodd");
clip("cubic path", 300, 300, "M 20 150 C 20 -30 280 -30 280 150 C 280 330 20 330 20 150 Z");

// ---- seeded random shapes (glyph-like quad contours, cubic blobs, random rounded rects)
let seed = 12345;
const rnd = () => ((seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 4294967296);
const q4 = (v) => Math.round(v * 4) / 4; // takumi snaps glyph origins to 1/4 px; keep coordinates exactly representable
const fx = (v) => +v.toFixed(3);
for (let k = 0; k < 40; k++) {
  const bw = 8 + Math.floor(rnd() * 300), bh = 8 + Math.floor(rnd() * 200), x = Math.floor(rnd() * 60), y = Math.floor(rnd() * 60);
  const m = Math.min(bw, bh) / 2;
  const rr = [0, 1, 2, 3].map(() => [fx(rnd() * m), fx(rnd() * m)]);
  rrect("random rounded rect", 400, 300, x, y, bw, bh, rr, `${rr[0][0]}px ${rr[1][0]}px ${rr[2][0]}px ${rr[3][0]}px / ${rr[0][1]}px ${rr[1][1]}px ${rr[2][1]}px ${rr[3][1]}px`);
}
for (let k = 0; k < 60; k++) {
  // closed contour of n quads around a centre; off-curve points pushed out so extrema are often NOT on-curve
  const size = [14, 24, 48, 96, 180][k % 5], n = 3 + Math.floor(rnd() * 6), cx = size / 2 + 4 + rnd(), cy = size / 2 + 4 + rnd();
  const contours = 1 + (k % 3 === 0 ? 1 : 0);
  let d = "";
  for (let c = 0; c < contours; c++) {
    const R = (size / 2) * (c ? 0.45 : 1), dir = c && k % 2 ? -1 : 1;
    const pt = (i, f) => { const a = dir * (i / n) * 2 * Math.PI, r = R * f * (0.75 + rnd() * 0.25); return [fx(cx + r * Math.cos(a)), fx(cy + r * Math.sin(a))]; };
    const p0 = pt(0, 1);
    d += `M ${p0[0]} ${p0[1]} `;
    for (let i = 0; i < n; i++) { const c1 = pt(i + 0.5, 1.15), p1 = i === n - 1 ? p0 : pt(i + 1, 1); d += `Q ${c1[0]} ${c1[1]} ${p1[0]} ${p1[1]} `; }
    d += "Z ";
  }
  clip("random quad contours", Math.ceil(size + 10), Math.ceil(size + 10), d.trim(), k % 4 === 3 ? "evenodd" : "nonzero");
}
for (let k = 0; k < 40; k++) {
  const size = [20, 60, 150, 320][k % 4], n = 2 + Math.floor(rnd() * 4);
  const P = () => [fx(2 + rnd() * size), fx(2 + rnd() * size)];
  const p0 = P();
  let d = `M ${p0[0]} ${p0[1]} `;
  for (let i = 0; i < n; i++) { const a = P(), b = P(), e = i === n - 1 ? p0 : P(); d += `C ${a[0]} ${a[1]} ${b[0]} ${b[1]} ${e[0]} ${e[1]} `; }
  clip("random cubic blobs", size + 4, size + 4, d + "Z", k % 3 === 2 ? "evenodd" : "nonzero");
}
void q4;

for (const c of cases) await c();
console.log(`\nmode ${["exact_area", "levels16", "skia_ss"][MODE]}:`);
for (const [g, t] of Object.entries(totals))
  console.log(`${g.padEnd(24)} cases ${String(t.cases).padStart(3)} (byte-exact ${String(t.exact).padStart(3)})  edge px ${String(t.edge).padStart(6)}  identical ${((t.same / Math.max(1, t.edge)) * 100).toFixed(2).padStart(6)}%  max diff ${t.max}`);
