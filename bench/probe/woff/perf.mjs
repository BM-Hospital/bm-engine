// Timing of the wasm build of src/woff vs Node's native (C) brotli on the same streams.
// Usage: node bench/probe/woff/perf.mjs <harness.wasm>
import fs from 'node:fs';
import zlib from 'node:zlib';
const { instance } = await WebAssembly.instantiate(fs.readFileSync(process.argv[2]), {});
const X = instance.exports;
const F = 'D:/project/bm-engine/ref/takumi/assets/fonts/';
const files = ['geist/geist-latin-wght-300-800.woff2', 'inter/inter-latin-opsz-wght-normal.woff2', 'sil/scheherazade-new-v17-arabic-600.woff2', 'twemoji/TwemojiMozilla-colr.woff2', 'noto-sans/NotoSansTC-VariableFont_wght.woff2'];
function stream(b) {
  let p = 48; const n = b.readUInt16BE(12);
  const b128 = () => { let a = 0; for (let i = 0; i < 5; i++) { const c = b[p++]; a = a * 128 + (c & 127); if (!(c & 128)) return a; } };
  for (let i = 0; i < n; i++) { const f = b[p++]; if ((f & 63) == 63) p += 4; b128(); const t = f & 63, xv = f >> 6; if ((t == 10 || t == 11) ? xv == 0 : xv != 0) b128(); }
  return b.subarray(p, p + b.readUInt32BE(20));
}
const min = (f, n) => { let best = 1e9; for (let i = 0; i < n; i++) { const t = performance.now(); f(); best = Math.min(best, performance.now() - t); } return best; };
for (const f of files) {
  const src = fs.readFileSync(F + f);
  const p = X.alloc(src.length); new Uint8Array(X.memory.buffer, p, src.length).set(src);
  const n = f.includes('Noto') ? 5 : 20;
  const ours = min(() => { if (X.woffDecode(p, src.length) < 0) throw new Error('decode'); X.freeOut(); }, n);
  const s = stream(src);
  const sp = X.alloc(s.length); new Uint8Array(X.memory.buffer, sp, s.length).set(s);
  const br = min(() => { if (X.brotliDecode(sp, s.length, 64 << 20) < 0) throw new Error('br'); X.freeOut(); }, n);
  const nat = min(() => zlib.brotliDecompressSync(s), n);
  X.free(p, src.length); X.free(sp, s.length);
  console.log(`${f.split('/')[1].padEnd(48)} woff2->sfnt ${ours.toFixed(2).padStart(7)} ms | our brotli ${br.toFixed(2).padStart(7)} ms | node C brotli ${nat.toFixed(2).padStart(7)} ms`);
}
