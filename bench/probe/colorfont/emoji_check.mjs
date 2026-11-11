// Cross-checks color.scanEmoji (via the wasm harness export cf_emoji_scan) against Unicode
// emoji-test.txt: every fully-qualified / component / minimally-qualified sequence must scan as one
// cluster of exactly its length (followed by 'a'); fully-qualified ones must report emoji presentation.
//   node probe/colorfont/emoji_check.mjs --wasm colorharness.wasm --test emoji-test.txt
import { readFileSync } from "node:fs";
const arg = (k) => { const i = process.argv.indexOf("--" + k); return i > 0 ? process.argv[i + 1] : undefined; };
const { instance } = await WebAssembly.instantiate(readFileSync(arg("wasm")), {});
const X = instance.exports;
const buf = X.cf_alloc(4 * 64);
const counts = {}, fails = [];
for (const line of readFileSync(arg("test"), "utf8").split("\n")) {
  const m = line.match(/^([0-9A-F ]+?)\s*;\s*([\w-]+)\s*#/);
  if (!m) continue;
  const status = m[2];
  const cps = m[1].trim().split(/\s+/).map((h) => parseInt(h, 16));
  const u = new Uint32Array(X.memory.buffer, buf, cps.length + 1);
  u.set([...cps, 0x61]);
  const r = X.cf_emoji_scan(buf, cps.length + 1);
  const len = r & 0xffff, pres = (r >>> 16) & 1;
  const c = (counts[status] ??= { n: 0, lenOk: 0, presOk: 0 });
  c.n++;
  if (len === cps.length) c.lenOk++; else if (fails.length < 15) fails.push({ status, seq: m[1].trim(), got: len });
  if (status !== "fully-qualified" || pres) c.presOk++; else if (fails.length < 15) fails.push({ status, seq: m[1].trim(), pres });
}
console.table(counts);
if (fails.length) console.table(fails);
