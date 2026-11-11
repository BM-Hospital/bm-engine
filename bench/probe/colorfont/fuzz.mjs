// Mutation fuzzer for src/font/color.zig table walkers (COLR/CPAL/CBLC/CBDT/sbix), run inside the
// ReleaseSafe wasm harness (bounds / overflow / unreachable => WebAssembly RuntimeError = finding).
//   node probe/colorfont/fuzz.mjs --wasm <colorharness.wasm (ReleaseSafe)> --secs 40 font1.ttf font2.ttf ...
// Each iteration mutates 1..8 bytes of one colour table in place (biased to the first 2 KB: headers,
// offsets, counts), reloads the table directory (cf_load_tables) and walks 64 glyphs (cf_fuzz:
// kind + clipBox + bitmap at 4 sizes + paintColr with a balance-checking painter), then restores.
import { readFileSync, writeFileSync } from "node:fs";

const arg = (k, d) => { const i = process.argv.indexOf("--" + k); return i > 0 ? process.argv[i + 1] : d; };
const wasm = arg("wasm");
const secs = +arg("secs", "40");
const fonts = process.argv.slice(2).filter((a, i, all) => !a.startsWith("--") && !all[i - 1]?.startsWith("--"));
let seed = +arg("seed", "12345");
const rnd = () => { seed = (seed * 1103515245 + 12345) >>> 0; return seed / 4294967296; };
const ri = (n) => Math.floor(rnd() * n);

const COLOR = ["COLR", "CPAL", "CBLC", "CBDT", "sbix"];
let total = 0, crashes = 0;
const results = [];
for (const file of fonts) {
  const bytes = readFileSync(file);
  // fresh instance per font (a trap leaves the instance unusable)
  let X, mem, p;
  const boot = async () => {
    const { instance } = await WebAssembly.instantiate(readFileSync(wasm), {});
    X = instance.exports;
    p = X.cf_alloc(bytes.length);
    new Uint8Array(X.memory.buffer).set(bytes, p);
    mem = () => new Uint8Array(X.memory.buffer);
  };
  await boot();
  const n = bytes.readUInt16BE(4), tables = [];
  for (let i = 0; i < n; i++) {
    const tag = bytes.toString("latin1", 12 + i * 16, 16 + i * 16);
    if (COLOR.includes(tag)) tables.push({ tag, off: bytes.readUInt32BE(20 + i * 16), len: bytes.readUInt32BE(24 + i * 16) });
  }
  const maxp = (() => { for (let i = 0; i < n; i++) if (bytes.toString("latin1", 12 + i * 16, 16 + i * 16) === "maxp") return bytes.readUInt32BE(20 + i * 16); })();
  const numGlyphs = bytes.readUInt16BE(maxp + 4);
  const t0 = performance.now();
  const until = t0 + (secs * 1000) / fonts.length;
  let iters = 0, ok = 0, err = 0, none = 0, local = 0;
  while (performance.now() < until) {
    const t = tables[ri(tables.length)];
    const muts = [];
    const k = 1 + ri(8);
    for (let j = 0; j < k; j++) {
      const span = rnd() < 0.6 ? Math.min(t.len, 2048) : t.len;
      const at = p + t.off + ri(span);
      const old = mem()[at];
      const v = [ri(256), old ^ (1 << ri(8)), 0xff, 0][ri(4)];
      muts.push([at, old, v]);
      mem()[at] = v;
    }
    try {
      X.cf_load_tables(p, bytes.length);
      for (let g = 0; g < 64; g++) {
        const r = X.cf_fuzz(ri(numGlyphs));
        if (r === 0) ok++; else if (r === 1) err++; else none++;
      }
    } catch (e) {
      crashes++; local++;
      const rec = { file, table: t.tag, muts: muts.map(([a, o, v]) => [a - p, o, v]), error: String(e) };
      writeFileSync(`fuzz-crash-${crashes}.json`, JSON.stringify(rec));
      console.log("CRASH", rec);
      await boot();
      continue;
    }
    for (const [a, o] of muts.reverse()) mem()[a] = o;
    iters++;
  }
  total += iters;
  results.push({ font: file.split(/[\\/]/).pop(), tables: tables.map((t) => t.tag).join(","), iters, walks: iters * 64, ok, errors: err, noColor: none, crashes: local, secs: +((performance.now() - t0) / 1000).toFixed(1) });
}
console.table(results);
console.log(`total iterations ${total}, crashes ${crashes}`);
process.exit(crashes ? 1 : 0);
