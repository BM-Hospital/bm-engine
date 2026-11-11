// Builds the release wasm: `zig build` (optimize=small) + `wasm-opt -Oz`, then copies it next to the JS wrapper.
//   node scripts/build.mjs            (ZIG=<path to zig.exe> to override the compiler location)
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, statSync } from "node:fs";
import { gzipSync, brotliCompressSync } from "node:zlib";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultZig = "C:/Users/admini/Downloads/zig-x86_64-windows-0.17.1/zig-x86_64-windows-0.17.1/zig.exe";
const zig = process.env.ZIG || (existsSync(defaultZig) ? defaultZig : "zig");
const out = path.join(root, "zig-out", "bin", "bm_engine.wasm");

execFileSync(zig, ["build"], { cwd: root, stdio: "inherit" });
const before = statSync(out).size;

const wasmOpt = path.join(root, "bench", "node_modules", "binaryen", "bin", "wasm-opt");
if (existsSync(wasmOpt)) {
  execFileSync(process.execPath, [wasmOpt, out, "-Oz", "--enable-simd", "--enable-bulk-memory", "--enable-sign-ext",
    "--enable-nontrapping-float-to-int", "--enable-mutable-globals", "-o", out], { cwd: root, stdio: "inherit" });
} else {
  console.warn("wasm-opt not found (run `npm i --ignore-scripts` in bench/); shipping the unoptimised binary");
}
copyFileSync(out, path.join(root, "js", "bm_engine.wasm"));
const bytes = readFileSync(out);
const kib = (n) => (n / 1024).toFixed(1) + " KiB";
console.log(`bm_engine.wasm: ${kib(before)} -> ${kib(bytes.length)} (gzip ${kib(gzipSync(bytes, { level: 9 }).length)}, brotli ${kib(brotliCompressSync(bytes).length)})`);
