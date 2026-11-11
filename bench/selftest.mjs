// Self-test of the harness: metrics self-checks + equivalence pipeline fed by perturbed copies of takumi's output.
//   node selftest.mjs
import path from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync, rmSync } from "node:fs";
import takumiWasm from "./engines/takumi-wasm.mjs";
import { makeMock } from "./engines/mock.mjs";
import { selfCheck } from "./lib/metrics.mjs";
import { EnginePool, equivalenceForCase, measureInterleaved } from "./lib/pipeline.mjs";
import { ALL_CASES } from "./fixtures/index.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
let fails = 0;
const check = (cond, msg) => { console.log(`${cond ? "PASS" : "FAIL"}  ${msg}`); if (!cond) fails++; };

for (const m of selfCheck()) check(true, "metrics: " + m);

const cases = ["colors-hex", "text-single-sizes", "card-og", "lingrad-alpha", "colors-transparent-canvas"].map((id) => ALL_CASES.find((c) => c.id === id));
// expected verdict sets per mock mode
const expect = {
  identity: ["identical"],
  "alpha-premul": ["identical", "equivalent", "close"], // un-premultiply round trip is lossy on translucent px
  noise: ["equivalent", "close"],
  aa: ["equivalent", "close"],
  salt: ["close", "different"],      // salt noise is punished hard by SSIM: must NOT pass as equivalent
  shift: ["close", "different"],
  invert: ["different"],
  blank: ["different"],
  wrongsize: ["different"],
  throw: ["error/unsupported"],
};
const outDir = path.join(here, "out-selftest");
for (const [mode, ok] of Object.entries(expect)) {
  const adapters = { "takumi-wasm": takumiWasm, bm: makeMock(takumiWasm, mode), "takumi-native": { name: "takumi-native", available: false } };
  const pool = new EnginePool(adapters);
  for (const k of cases) {
    if (mode === "salt" && k.id === "colors-transparent-canvas") continue; // invisible (alpha=0) pixels only
    const r = await equivalenceForCase(k, pool, adapters, { cands: ["bm"], outDir: mode === "noise" ? outDir : undefined });
    const m = r.cmp.bm;
    check(ok.includes(m.verdict), `mock '${mode}' on ${k.id}: verdict=${m.verdict}${"ssim" in m ? ` ssim=${m.ssim} strict=${m.pctStrict}% AA=${m.pctAA}% max=${m.maxAbs} psnr=${m.psnr}` : ` (${m.error})`}  expected ${ok.join("|")}`);
    if (mode === "identity") check(m.identical && m.pmStrict === 0 && m.ssim === 1, `identity metrics exact on ${k.id}`);
    if (mode === "wrongsize") check(m.sizeMismatch === true, `wrongsize flagged as sizeMismatch on ${k.id}`);
    if (mode === "throw") check(r.renders.bm.error?.includes("mock"), `throw captured as error string on ${k.id}`);
  }
  pool.dispose();
}
if (existsSync(path.join(outDir, "colors-hex", "diff.png"))) check(true, "diff.png written for mock run"); else check(false, "diff.png written for mock run");
rmSync(outDir, { recursive: true, force: true });

// perf: ordering sanity (mock adds work only for raw) + per-engine error capture
{
  const adapters = { "takumi-wasm": takumiWasm, bm: makeMock(takumiWasm, "throw") };
  const pool = new EnginePool(adapters);
  const targets = [];
  for (const n of Object.keys(adapters)) targets.push({ name: n, inst: (await pool.get(adapters[n])).inst });
  const res = await measureInterleaved(targets, cases[0], "raw", { warmup: 1, rounds: 2, minIters: 4, minMs: 10, maxMs: 200, iters: 0 });
  check(res["takumi-wasm"].n >= 4 && res["takumi-wasm"].median > 0, `perf stats produced (n=${res["takumi-wasm"].n}, median=${res["takumi-wasm"].median.toFixed(2)}ms)`);
  check(!!res.bm.error, "perf: throwing engine reported as error, run continued");
  pool.dispose();
}
console.log(fails ? `\n${fails} FAILED` : "\nall self-tests passed");
process.exit(fails ? 1 : 0);
