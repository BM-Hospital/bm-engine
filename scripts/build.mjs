// Release build of every profile: `zig build -Dprofile=<p>` (optimize=small) + `wasm-opt -Oz`.
//
//   node scripts/build.mjs                    core + standard + full + the WOFF add-on
//   node scripts/build.mjs --profile=core     one profile only (core | standard | full)
//   node scripts/build.mjs -- -Dtables=false  extra zig build options (applied to every profile)
//   (ZIG=<path to zig.exe> overrides the compiler location)
//
// Outputs: js/bm_engine.core.wasm, js/bm_engine.standard.wasm, js/bm_engine.wasm (= full, every feature),
// js/bm_woff.wasm (add-on, see js/addons.mjs), zig-out/bin/bm_engine.wasm (= full, optimised), and a
// size table (raw / gzip -9 / brotli q11) printed and written to bench/out/sizes.json.
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, statSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { gzipSync, brotliCompressSync, constants } from "node:zlib";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultZig = "C:/Users/admini/Downloads/zig-x86_64-windows-0.17.1/zig-x86_64-windows-0.17.1/zig.exe";
const zig = process.env.ZIG || (existsSync(defaultZig) ? defaultZig : "zig");
const argv = process.argv.slice(2);
const dd = argv.indexOf("--");
const extra = dd >= 0 ? argv.slice(dd + 1) : [];
const opts = Object.fromEntries((dd >= 0 ? argv.slice(0, dd) : argv).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const ALL = ["core", "standard", "full"];
const profiles = opts.profile ? String(opts.profile).split(",") : ALL;
for (const p of profiles) if (!ALL.includes(p)) throw new Error(`unknown profile ${p} (core | standard | full)`);

const wasmOpt = path.join(root, "bench", "node_modules", "binaryen", "bin", "wasm-opt");
const haveOpt = existsSync(wasmOpt);
if (!haveOpt) console.warn("wasm-opt not found (run `npm i --ignore-scripts` in bench/); shipping unoptimised binaries");
function optimise(file) {
  if (!haveOpt) return;
  execFileSync(process.execPath, [wasmOpt, file, "-Oz", "--enable-simd", "--enable-bulk-memory", "--enable-sign-ext",
    "--enable-nontrapping-float-to-int", "--enable-mutable-globals", "-o", file], { cwd: root, stdio: "inherit" });
}
const sizes = (b) => ({
  raw: b.length,
  gzip9: gzipSync(b, { level: 9 }).length,
  brotli: brotliCompressSync(b, { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_SIZE_HINT]: b.length } }).length,
});

const rows = {};
for (const p of profiles) {
  // full builds into zig-out (the default prefix every tool reads); the others into their own prefix
  const prefix = p === "full" ? path.join(root, "zig-out") : path.join(root, "zig-out", "profiles", p);
  execFileSync(zig, ["build", `-Dprofile=${p}`, "-p", prefix, ...extra], { cwd: root, stdio: "inherit" });
  const out = path.join(prefix, "bin", "bm_engine.wasm");
  const zigBytes = statSync(out).size;
  optimise(out);
  const dest = path.join(root, "js", p === "full" ? "bm_engine.wasm" : `bm_engine.${p}.wasm`);
  copyFileSync(out, dest);
  rows[p] = { file: path.relative(root, dest).split(path.sep).join("/"), zig: zigBytes, ...sizes(readFileSync(dest)) };
  if (p === "full" || !rows.woffAddon) {
    const w = path.join(prefix, "bin", "bm_woff.wasm");
    if (existsSync(w)) {
      const zw = statSync(w).size;
      optimise(w);
      copyFileSync(w, path.join(root, "js", "bm_woff.wasm"));
      rows.woffAddon = { file: "js/bm_woff.wasm", zig: zw, ...sizes(readFileSync(w)) };
    }
  }
}

const takumiPath = path.join(root, "bench", "node_modules", "@takumi-rs", "wasm", "pkg", "takumi_wasm_bg.wasm");
if (existsSync(takumiPath)) rows["takumi-wasm 2.20"] = { file: "bench/node_modules/@takumi-rs/wasm/pkg/takumi_wasm_bg.wasm", zig: null, ...sizes(readFileSync(takumiPath)) };

const kib = (n) => (n == null ? "-" : (n / 1024).toFixed(1));
console.log("\n| build | zig .small KiB | wasm-opt -Oz KiB | gzip -9 KiB | brotli KiB |\n|:--|--:|--:|--:|--:|");
for (const [k, r] of Object.entries(rows)) console.log(`| ${k} | ${kib(r.zig)} | ${kib(r.raw)} | ${kib(r.gzip9)} | ${kib(r.brotli)} |`);
const outDir = path.join(root, "bench", "out");
mkdirSync(outDir, { recursive: true });
const file = path.join(outDir, "sizes.json");
let prev = {};
try { prev = JSON.parse(readFileSync(file, "utf8")); } catch {}
writeFileSync(file, JSON.stringify({ date: new Date().toISOString(), extraArgs: extra, builds: { ...(prev.builds || {}), ...rows } }, null, 2));
console.log(`\nwritten ${path.relative(root, file)}`);
