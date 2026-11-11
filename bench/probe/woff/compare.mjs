// WOFF/WOFF2/brotli validation harness for src/woff, driven through a wasm build of the decoder.
//
// Build the harness first (see bench/probe/woff/harness.zig), then:
//   node bench/probe/woff/compare.mjs <harness.wasm> [fonts|brotli|woff1|all]
// - fonts : every .woff2 under ref/takumi/assets/fonts vs the wawoff2 reference decoder (google/woff2
//           compiled to wasm; untrusted, only its decompress() is called), whole-file + per-table.
// - brotli: Node's brotliCompressSync on varied corpora x quality 0..11 x lgwin x modes, byte-exact.
// - woff1 : WOFF 1.0 files built here from .ttf files (zlib per table, per spec), decoded output
//           compared with the original sfnt.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { corpora, variants, compress } from './gen_brotli_vectors.mjs';
import { makeWoff1 } from './woff1_build.mjs';

const require = createRequire(import.meta.url);
const ROOT = 'D:/project/bm-engine';
const wasmPath = process.argv[2];
const what = process.argv[3] || 'all';
const { instance } = await WebAssembly.instantiate(fs.readFileSync(wasmPath), {});
const X = instance.exports;

function put(b) {
  const p = X.alloc(b.length || 1);
  new Uint8Array(X.memory.buffer, p, b.length).set(b);
  return p;
}
export function call(fn, b, ...extra) {
  const p = put(b);
  const t0 = performance.now();
  const n = X[fn](p, b.length, ...extra);
  const ms = performance.now() - t0;
  X.free(p, b.length || 1);
  if (n < 0) return { err: n, ms };
  const out = Buffer.from(new Uint8Array(X.memory.buffer, X.outPtr(), n));
  X.freeOut();
  return { out, ms };
}

function tables(buf, dirOff = 0) {
  const n = buf.readUInt16BE(dirOff + 4);
  const m = new Map();
  for (let i = 0; i < n; i++) {
    const p = dirOff + 12 + 16 * i;
    const tag = buf.toString('latin1', p, p + 4);
    const off = buf.readUInt32BE(p + 8), len = buf.readUInt32BE(p + 12);
    m.set(tag, { off, len, sum: buf.readUInt32BE(p + 4), data: buf.subarray(off, off + len) });
  }
  return m;
}
function fontDirs(buf) {
  if (buf.toString('latin1', 0, 4) !== 'ttcf') return [0];
  const n = buf.readUInt32BE(8);
  return Array.from({ length: n }, (_, i) => buf.readUInt32BE(12 + 4 * i));
}

let failures = 0;

// Decodes a glyf record to a canonical form (points, instructions, bbox) so that glyf tables can
// be compared at the outline level where byte encodings legitimately differ.
function parseGlyph(g) {
  if (g.length === 0) return 'empty';
  const nc = g.readInt16BE(0);
  if (nc < 0) return 'C' + g.toString('hex');
  const ends = [];
  for (let i = 0; i < nc; i++) ends.push(g.readUInt16BE(10 + 2 * i));
  const np = nc ? ends[nc - 1] + 1 : 0;
  let p = 10 + 2 * nc;
  const il = g.readUInt16BE(p); p += 2;
  const ins = g.subarray(p, p + il).toString('hex'); p += il;
  const flags = [];
  while (flags.length < np) {
    const f = g[p++];
    flags.push(f);
    if (f & 8) { let r = g[p++]; while (r--) flags.push(f); }
  }
  const pts = [];
  let x = 0;
  for (const f of flags) {
    if (f & 2) { const d = g[p++]; x += f & 16 ? d : -d; } else if (!(f & 16)) { x += g.readInt16BE(p); p += 2; }
    pts.push([x]);
  }
  let y = 0;
  flags.forEach((f, i) => {
    if (f & 4) { const d = g[p++]; y += f & 32 ? d : -d; } else if (!(f & 32)) { y += g.readInt16BE(p); p += 2; }
    pts[i].push(y, f & 1);
  });
  return JSON.stringify({ bbox: g.subarray(2, 10).toString('hex'), ends, ins, pts, overlap: (flags[0] ?? 0) & 0x40 });
}

function glyfOutlineDiffs(outBuf, outTabs, refTabs) {
  const lf = refTabs.get('head').data.readUInt16BE(50);
  const lo = (l, i) => lf ? l.readUInt32BE(4 * i) : 2 * l.readUInt16BE(2 * i);
  const la = outTabs.get('loca').data, lb = refTabs.get('loca').data;
  const ga = outTabs.get('glyf').data, gb = refTabs.get('glyf').data;
  const ng = la.length / (lf ? 4 : 2) - 1;
  let differ = 0, overlapOnly = 0;
  for (let i = 0; i < ng; i++) {
    const a = parseGlyph(ga.subarray(lo(la, i), lo(la, i + 1)));
    const b = parseGlyph(gb.subarray(lo(lb, i), lo(lb, i + 1)));
    if (a === b) continue;
    const ja = a.startsWith('{') ? JSON.parse(a) : null, jb = b.startsWith('{') ? JSON.parse(b) : null;
    if (ja && jb && ja.overlap && !jb.overlap) { ja.overlap = 0; if (JSON.stringify(ja) === JSON.stringify(jb)) { overlapOnly++; continue; } }
    differ++;
  }
  return { differ, overlapOnly };
}

async function fonts() {
  const decompress = require(path.join(ROOT, 'bench/node_modules/wawoff2/decompress.js'));
  const dir = path.join(ROOT, 'ref/takumi/assets/fonts');
  const files = [];
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p); else if (e.name.endsWith('.woff2')) files.push(p);
    }
  })(dir);
  for (const f of files) {
    const src = fs.readFileSync(f);
    const ref = Buffer.from(await decompress(src));
    const runs = [];
    let r;
    for (let i = 0; i < 5; i++) { r = call('woffDecode', src); runs.push(r.ms); }
    const name = path.relative(dir, f);
    if (r.err) { console.log(`FAIL ${name}: error ${r.err}`); failures++; continue; }
    const out = r.out;
    const same = Buffer.compare(out, ref) === 0;
    let detail = '';
    if (!same) {
      const a = fontDirs(out), b = fontDirs(ref);
      const diffs = [];
      for (let k = 0; k < Math.max(a.length, b.length); k++) {
        const ta = tables(out, a[k]), tb = tables(ref, b[k]);
        for (const [tag, x] of tb) {
          const y = ta.get(tag);
          if (!y) { diffs.push(`${tag}:missing`); continue; }
          if (Buffer.compare(x.data, y.data) === 0) { if (x.sum !== y.sum) diffs.push(`${tag}:checksum`); continue; }
          if (tag === 'glyf') {
            // The reference (google/woff2 as packaged by wawoff2 2.0.1) predates the 2022 spec
            // correction that makes decoders restore OVERLAP_SIMPLE from overlapSimpleBitmap;
            // compare decoded outlines and accept glyphs that differ only by that bit.
            const { differ, overlapOnly } = glyfOutlineDiffs(out, ta, tb);
            if (differ) diffs.push(`glyf:outlines(${differ})`);
            else detail += ` [glyf: ${overlapOnly} glyphs differ only by the spec-mandated OVERLAP_SIMPLE bit]`;
            continue;
          }
          if (tag === 'head' && Buffer.compare(Buffer.concat([x.data.subarray(0, 8), x.data.subarray(12)]), Buffer.concat([y.data.subarray(0, 8), y.data.subarray(12)])) === 0) {
            detail += ' [head: checkSumAdjustment only]';
            continue;
          }
          diffs.push(`${tag}:bytes`);
        }
        for (const tag of ta.keys()) if (!tb.has(tag)) diffs.push(`${tag}:extra`);
      }
      detail += diffs.length ? ' table diffs: ' + diffs.join(' ') : '';
      if (diffs.length) failures++;
    }
    runs.sort((x, y) => x - y);
    console.log(`${same ? 'IDENTICAL' : 'DIFF     '} ${name}  ${src.length} -> ${out.length} B, wasm ${runs[2].toFixed(2)} ms${detail}`);
  }
}

function brotli() {
  let n = 0, bad = 0, bytes = 0, ms = 0;
  for (const [name, raw] of corpora(true)) {
    for (const o of variants(true)) {
      if (raw.length > 1_000_000 && o.q >= 10 && o.lgwin < 20 && name !== 'farmatch') continue; // keep runtime sane
      const c = compress(raw, o);
      const r = call('brotliDecode', c, raw.length + 1);
      n++;
      if (r.err || Buffer.compare(r.out, raw) !== 0) {
        bad++;
        console.log(`FAIL brotli ${name} ${JSON.stringify(o)}: ${r.err ?? 'mismatch'}`);
      } else { bytes += raw.length; ms += r.ms; }
      // cap enforcement: one byte less must fail with OutputTooLarge (-3)
      if (raw.length > 0) {
        const r2 = call('brotliDecode', c, raw.length - 1);
        if (r2.err !== -3) { bad++; console.log(`FAIL cap ${name} ${JSON.stringify(o)}: ${r2.err}`); }
      }
    }
  }
  failures += bad;
  console.log(`brotli: ${n - bad}/${n} streams byte-exact, ${(bytes / 1e6).toFixed(1)} MB in ${ms.toFixed(0)} ms (${(bytes / 1e3 / ms).toFixed(0)} MB/s wasm)`);
}

function woff1() {
  const ttfs = [
    'src/font/testdata/Inter-Regular.ttf', 'src/font/testdata/Inter-Bold.ttf', 'src/font/testdata/NotoSans-Regular.ttf',
    'src/font/testdata/Roboto-Regular.ttf', 'ref/takumi/assets/fonts/geist/geist-latin-wght-300-800.ttf',
    'ref/takumi/assets/fonts/archivo/Archivo-VariableFont_wdth,wght.ttf',
  ];
  for (const rel of ttfs) {
    const ttf = fs.readFileSync(path.join(ROOT, rel));
    const w = makeWoff1(ttf);
    const r = call('woffDecode', w);
    if (r.err) { console.log(`FAIL woff1 ${rel}: ${r.err}`); failures++; continue; }
    const ta = tables(r.out), tb = tables(ttf);
    const diffs = [];
    for (const [tag, x] of tb) {
      const y = ta.get(tag);
      if (!y) diffs.push(tag + ':missing');
      else if (tag === 'head' ? Buffer.compare(Buffer.concat([x.data.subarray(0, 8), x.data.subarray(12)]), Buffer.concat([y.data.subarray(0, 8), y.data.subarray(12)])) : Buffer.compare(x.data, y.data)) diffs.push(tag + ':bytes');
    }
    if (diffs.length) failures++;
    const whole = Buffer.compare(r.out, ttf) === 0;
    console.log(`${diffs.length ? 'FAIL ' : 'OK   '} woff1 ${path.basename(rel)} ${w.length} -> ${r.out.length} B (${whole ? 'byte-identical file' : 'tables identical'}) ${r.ms.toFixed(2)} ms ${diffs.join(' ')}`);
  }
}

if (what === 'fonts' || what === 'all') await fonts();
if (what === 'brotli' || what === 'all') brotli();
if (what === 'woff1' || what === 'all') woff1();
console.log(failures ? `${failures} FAILURES` : 'ALL OK');
process.exitCode = failures ? 1 : 0;
