// Mutation fuzzer for src/woff through a ReleaseSafe wasm build (safety checks on: any OOB /
// overflow / unreachable traps). Also watches for hangs (per-call time) and memory blow-up.
// Usage: node bench/probe/woff/fuzz.mjs <harness_safe.wasm> [seconds=45]
import fs from 'node:fs';
import zlib from 'node:zlib';
import { makeWoff1 } from './woff1_build.mjs';

const wasm = fs.readFileSync(process.argv[2]);
const seconds = +(process.argv[3] || 45);
const F = 'D:/project/bm-engine/ref/takumi/assets/fonts/';
const seeds = [
  ['woff2', fs.readFileSync(F + 'geist/geist-latin-wght-300-800.woff2')],
  ['woff2', fs.readFileSync(F + 'cjk-locl-test/CJKLoclTest.woff2')],
  ['woff2', fs.readFileSync(F + 'eb-garamond/EBGaramondCaps.woff2')],
  ['woff2', fs.readFileSync(F + 'sil/scheherazade-new-v17-arabic-regular.woff2')],
  ['woff2', fs.readFileSync('D:/project/bm-engine/src/woff/testdata/collection.woff2')],
  ['woff', makeWoff1(fs.readFileSync(F + 'geist/geist-latin-wght-300-800.ttf'))],
  ['woff', makeWoff1(fs.readFileSync('D:/project/bm-engine/src/font/testdata/Roboto-Regular.ttf'), 1)],
  ['br', zlib.brotliCompressSync(Buffer.from('The quick brown fox jumps over the lazy dog, international government information. '.repeat(200)))],
  ['br', zlib.brotliCompressSync(fs.readFileSync('D:/project/bm-engine/src/font/testdata/Roboto-Regular.ttf').subarray(0, 60000))],
];

let X;
async function fresh() { X = (await WebAssembly.instantiate(wasm, {})).instance.exports; }
await fresh();

let seed = 0x9e3779b9;
const rnd = (n) => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return ((seed >>> 0) % n); };

function mutate(src) {
  const b = Buffer.from(src);
  let len = b.length;
  const mode = rnd(6);
  if (mode <= 2) { const k = 1 + rnd(mode === 2 ? 64 : 6); for (let i = 0; i < k; i++) b[rnd(rnd(2) ? Math.min(len, 600) : len)] = rnd(256); }
  if (mode === 3) len = rnd(len);
  if (mode === 4) { const p = rnd(len); b[p] ^= 1 << rnd(8); len = Math.max(1, len - rnd(16)); }
  if (mode === 5) { // damage a 32-bit length field in the header / directory
    const p = 4 * rnd(Math.min(len, 400) >> 2); b.writeUInt32BE([0, 1, 0xffffffff, 0x7fffffff, rnd(1 << 30), b.readUInt32BE(p) + 1][rnd(6)] >>> 0, p);
  }
  return b.subarray(0, len);
}

const t0 = Date.now();
let runs = 0, traps = 0, ok = 0, slow = 0, maxMs = 0;
const codes = {};
while (Date.now() - t0 < seconds * 1000) {
  const [kind, src] = seeds[runs % seeds.length];
  const m = mutate(src);
  const p = X.alloc(m.length || 1);
  new Uint8Array(X.memory.buffer, p, m.length).set(m);
  const t = performance.now();
  let r;
  try {
    r = kind === 'br' ? X.brotliDecode(p, m.length, 8 << 20) : X.woffDecode(p, m.length);
  } catch (e) {
    traps++;
    const name = `crash_${kind}_${runs}.bin`;
    fs.writeFileSync((process.env.WOFF_FUZZ_DIR || '.') + '/' + name, m);
    console.log(`TRAP (${e.message}) on ${kind} mutation, saved ${name}`);
    await fresh();
    runs++;
    continue;
  }
  const ms = performance.now() - t;
  maxMs = Math.max(maxMs, ms);
  if (ms > 1000) slow++;
  if (r >= 0) { ok++; X.freeOut(); } else codes[r] = (codes[r] || 0) + 1;
  X.free(p, m.length || 1);
  runs++;
}
console.log(`${runs} runs in ${seconds}s: ${traps} traps, ${slow} slow (>1s), max ${maxMs.toFixed(1)} ms/run, ${ok} decoded, errors ${JSON.stringify(codes)}, wasm memory ${(X.memory.buffer.byteLength / 1048576).toFixed(0)} MiB`);
process.exitCode = traps || slow ? 1 : 0;
