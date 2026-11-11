// Builds a WOFF 1.0 file from an sfnt per the W3C spec (zlib per table when smaller, data in the
// original table order, 4-byte aligned). Used by compare.mjs and make_testdata.mjs.
import zlib from 'node:zlib';

export function makeWoff1(ttf, level = 9) {
  const n = ttf.readUInt16BE(4);
  const recs = [];
  for (let i = 0; i < n; i++) {
    const p = 12 + 16 * i;
    recs.push({ tag: ttf.subarray(p, p + 4), sum: ttf.readUInt32BE(p + 4), off: ttf.readUInt32BE(p + 8), len: ttf.readUInt32BE(p + 12) });
  }
  const order = [...recs].sort((a, b) => a.off - b.off); // data in original order
  let off = 44 + 20 * n;
  const blobs = [];
  for (const r of order) {
    const data = ttf.subarray(r.off, r.off + r.len);
    const z = zlib.deflateSync(data, { level });
    r.comp = z.length < data.length ? z : data;
    r.woffOff = off;
    const padded = (r.comp.length + 3) & ~3;
    blobs.push(r.comp, Buffer.alloc(padded - r.comp.length));
    off += padded;
  }
  const hdr = Buffer.alloc(44 + 20 * n);
  hdr.write('wOFF', 0, 'latin1');
  hdr.writeUInt32BE(ttf.readUInt32BE(0), 4);
  hdr.writeUInt32BE(off, 8);
  hdr.writeUInt16BE(n, 12);
  let total = 12 + 16 * n;
  for (const r of recs) total += (r.len + 3) & ~3;
  hdr.writeUInt32BE(total, 16);
  hdr.writeUInt16BE(1, 20);
  recs.forEach((r, i) => {
    const p = 44 + 20 * i;
    r.tag.copy(hdr, p);
    hdr.writeUInt32BE(r.woffOff, p + 4);
    hdr.writeUInt32BE(r.comp.length, p + 8);
    hdr.writeUInt32BE(r.len, p + 12);
    hdr.writeUInt32BE(r.sum, p + 16);
  });
  return Buffer.concat([hdr, ...blobs]);
}
