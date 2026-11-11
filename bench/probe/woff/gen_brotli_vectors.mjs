// Generates brotli test vectors (Node's built-in encoder) for src/woff/tests.zig.
// Output format: repeated records { u32le rawLen, u32le compLen, raw, comp }.
// Usage: node bench/probe/woff/gen_brotli_vectors.mjs <out.bin> [--big]
import zlib from 'node:zlib';
import fs from 'node:fs';

const C = zlib.constants;
let seed = 12345;
const rnd = () => ((seed = (seed * 1103515245 + 12345) >>> 0) >>> 8) / 16777216;

export function corpora(big) {
  const out = [];
  const text = 'The quick brown fox jumps over the lazy dog. This is a test of the brotli dictionary, with words like international, information, government and <div class="content">. ';
  out.push(['empty', Buffer.alloc(0)]);
  out.push(['one', Buffer.from('a')]);
  out.push(['text', Buffer.from(text.repeat(3))]);
  out.push(['dictwords', Buffer.from('development environment international information photographs “quoted” Ünïcödé 中文字符 русский текст  hindi: हिन्दी. THE Thing, ' + 'Nevertheless the government announced')]);
  const bin = Buffer.alloc(big ? 300000 : 6000);
  for (let i = 0; i < bin.length; i++) bin[i] = (rnd() * 256) | 0;
  out.push(['random', bin]);
  const rep = Buffer.alloc(big ? 400000 : 30000);
  for (let i = 0; i < rep.length; i++) rep[i] = (i % 7 === 0 ? (rnd() * 4) | 0 : (i * 13) & 0xff);
  out.push(['struct', rep]);
  const ints = Buffer.alloc(big ? 200000 : 16000);
  for (let i = 0; i < ints.length; i += 2) ints.writeInt16LE(((Math.sin(i / 50) * 3000) | 0) + ((rnd() * 20) | 0), i);
  out.push(['signed', ints]);
  out.push(['zeros', Buffer.alloc(big ? 3_000_000 : 70000)]);
  const mixed = [];
  for (let i = 0; i < (big ? 4000 : 300); i++) mixed.push(i % 3 ? text.slice((rnd() * 100) | 0, 40 + ((rnd() * 60) | 0)) : String((rnd() * 1e9) | 0));
  out.push(['mixed', Buffer.from(mixed.join('|'))]);
  if (big) {
    const far = Buffer.alloc(5_000_000);
    const blk = Buffer.alloc(100000);
    for (let i = 0; i < blk.length; i++) blk[i] = (rnd() * 256) | 0;
    for (let o = 0; o < far.length; o += blk.length + 1234) blk.copy(far, o);
    out.push(['farmatch', far]);
  }
  return out;
}

export function variants(big) {
  const v = [];
  const qs = big ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] : [0, 1, 2, 5, 9, 11];
  for (const q of qs) v.push({ q, lgwin: 22 });
  for (const lgwin of big ? [10, 11, 12, 16, 18, 24] : [10, 16, 24]) v.push({ q: 11, lgwin });
  for (const lgwin of big ? [10, 16, 24] : [10]) v.push({ q: 5, lgwin });
  v.push({ q: 9, lgwin: 22, mode: C.BROTLI_MODE_TEXT });
  v.push({ q: 11, lgwin: 22, mode: C.BROTLI_MODE_FONT });
  v.push({ q: 11, lgwin: 22, lgblock: 16 });
  v.push({ q: 7, lgwin: 22, npostfix: 2, ndirect: 12 });
  return v;
}

export function compress(raw, o) {
  const params = { [C.BROTLI_PARAM_QUALITY]: o.q, [C.BROTLI_PARAM_LGWIN]: o.lgwin, [C.BROTLI_PARAM_SIZE_HINT]: raw.length };
  if (o.mode !== undefined) params[C.BROTLI_PARAM_MODE] = o.mode;
  if (o.lgblock) params[C.BROTLI_PARAM_LGBLOCK] = o.lgblock;
  if (o.npostfix !== undefined) { params[C.BROTLI_PARAM_NPOSTFIX] = o.npostfix; params[C.BROTLI_PARAM_NDIRECT] = o.ndirect; }
  return zlib.brotliCompressSync(raw, { params });
}

if (import.meta.url === `file:///${process.argv[1].replace(/\\/g, '/')}` || process.argv[1].endsWith('gen_brotli_vectors.mjs')) {
  const outPath = process.argv[2];
  if (outPath) {
    const parts = [];
    for (const [, raw] of corpora(false)) {
      for (const o of variants(false)) {
        // keep the file small: only a few variants for the larger corpora
        if (raw.length > 25000 && o.q < 11 && o.q !== 5) continue;
        const c = compress(raw, o);
        const h = Buffer.alloc(8);
        h.writeUInt32LE(raw.length, 0);
        h.writeUInt32LE(c.length, 4);
        parts.push(h, raw, c);
      }
    }
    const all = Buffer.concat(parts);
    fs.writeFileSync(outPath, zlib.deflateRawSync(all, { level: 9 }));
    console.log('wrote', outPath, all.length, 'raw bytes,', fs.statSync(outPath).size, 'deflated');
  }
}
