// Generates the small test files embedded by src/woff/tests.zig (run from the repo root):
//   node bench/probe/woff/make_testdata.mjs
// - geist.woff2 / geist.ttf : a takumi asset and its original TrueType twin (reference decoder
//                             output == original ttf, byte for byte)
// - geist.woff              : WOFF 1.0 of geist.ttf built per spec (zlib per table)
// - ebgaramond.woff2        : uses the glyf overlapSimpleBitmap
// - collection.woff2 / collection_ref.ttc : a 3-font TTC (two distinct fonts + one sharing all
//                             tables of the first) encoded with google/woff2 (wawoff2) and the
//                             reference decoder's output
// - bomb.br                 : brotli stream of 256 MiB of zeros (output-cap test)
import fs from 'node:fs';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { makeWoff1 } from './woff1_build.mjs';

const require = createRequire(import.meta.url);
const compress = require('../../node_modules/wawoff2/compress.js');
const decompress = require('../../node_modules/wawoff2/decompress.js');
const F = 'ref/takumi/assets/fonts/';
const OUT = 'src/woff/testdata/';

const geistW2 = fs.readFileSync(F + 'geist/geist-latin-wght-300-800.woff2');
const geistTtf = fs.readFileSync(F + 'geist/geist-latin-wght-300-800.ttf');
fs.writeFileSync(OUT + 'geist.woff2', geistW2);
fs.writeFileSync(OUT + 'geist.ttf', geistTtf);
fs.writeFileSync(OUT + 'geist.woff', makeWoff1(geistTtf));
fs.writeFileSync(OUT + 'ebgaramond.woff2', fs.readFileSync(F + 'eb-garamond/EBGaramondCapsLatn.woff2'));

// TTC: [geist, cjk, geist again sharing every table of font 0].
const cjk = Buffer.from(await decompress(fs.readFileSync(F + 'cjk-locl-test/CJKLoclTest.woff2')));
function recs(ttf) {
  const n = ttf.readUInt16BE(4), r = [];
  for (let i = 0; i < n; i++) {
    const p = 12 + 16 * i;
    r.push({ tag: ttf.toString('latin1', p, p + 4), sum: ttf.readUInt32BE(p + 4), data: ttf.subarray(ttf.readUInt32BE(p + 8), ttf.readUInt32BE(p + 8) + ttf.readUInt32BE(p + 12)) });
  }
  return r.filter((t) => t.tag !== 'DSIG');
}
const fonts = [recs(geistTtf), recs(cjk)];
const nfonts = 3;
let off = 12 + 4 * nfonts;
const dirOffs = [];
const dirsLen = [fonts[0].length, fonts[1].length, fonts[0].length];
for (const n of dirsLen) { dirOffs.push(off); off += 12 + 16 * n; }
const blobs = [];
const tableOff = [];
for (const f of fonts) {
  const offs = [];
  for (const t of f) { offs.push(off); const pad = (t.data.length + 3) & ~3; blobs.push(t.data, Buffer.alloc(pad - t.data.length)); off += pad; }
  tableOff.push(offs);
}
const head = Buffer.alloc(12 + 4 * nfonts + dirsLen.reduce((a, n) => a + 12 + 16 * n, 0));
head.write('ttcf', 0, 'latin1'); head.writeUInt32BE(0x00010000, 4); head.writeUInt32BE(nfonts, 8);
[0, 1, 0].forEach((fi, k) => {
  head.writeUInt32BE(dirOffs[k], 12 + 4 * k);
  const f = fonts[fi], n = f.length, d = dirOffs[k];
  const pow = 1 << Math.floor(Math.log2(n));
  head.writeUInt32BE(0x00010000, d); head.writeUInt16BE(n, d + 4); head.writeUInt16BE(pow * 16, d + 6);
  head.writeUInt16BE(Math.log2(pow), d + 8); head.writeUInt16BE(n * 16 - pow * 16, d + 10);
  f.forEach((t, i) => {
    const p = d + 12 + 16 * i;
    head.write(t.tag, p, 'latin1'); head.writeUInt32BE(t.sum, p + 4); head.writeUInt32BE(tableOff[fi][i], p + 8); head.writeUInt32BE(t.data.length, p + 12);
  });
});
const ttc = Buffer.concat([head, ...blobs]);
const w2 = Buffer.from(await compress(ttc));
const ref = Buffer.from(await decompress(w2));
fs.writeFileSync(OUT + 'collection.woff2', w2);
fs.writeFileSync(OUT + 'collection_ref.ttc', ref);

fs.writeFileSync(OUT + 'bomb.br', zlib.brotliCompressSync(Buffer.alloc(256 << 20), { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 5, [zlib.constants.BROTLI_PARAM_LGWIN]: 24 } }));
for (const f of fs.readdirSync(OUT)) console.log(f.padEnd(32), fs.statSync(OUT + f).size);
