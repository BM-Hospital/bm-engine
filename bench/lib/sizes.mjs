import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import path from "node:path";
import { gzipSync, brotliCompressSync, constants } from "node:zlib";
import { ROOT_DIR, BENCH_DIR } from "./assets.mjs";

export function sizeOf(bytes) {
  return {
    raw: bytes.length,
    gzip9: gzipSync(bytes, { level: 9 }).length,
    brotli: brotliCompressSync(bytes, { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_SIZE_HINT]: bytes.length } }).length,
  };
}
const fileSize = (p) => (p && existsSync(p) ? sizeOf(readFileSync(p)) : null);
function dirJs(dir) {
  if (!existsSync(dir)) return null;
  const files = readdirSync(dir).filter((f) => /\.(mjs|js)$/.test(f)).map((f) => path.join(dir, f));
  if (!files.length) return null;
  return { files: files.map((f) => path.basename(f)), ...sizeOf(Buffer.concat(files.map((f) => readFileSync(f)))) };
}

/** Binary + JS glue sizes for each engine (null when the file doesn't exist). */
export function collectSizes(ALL) {
  const tw = path.join(BENCH_DIR, "node_modules/@takumi-rs/wasm");
  const tc = path.join(BENCH_DIR, "node_modules/@takumi-rs/core");
  const native = ALL["takumi-native"].nativePath;
  return {
    "takumi-wasm": { binary: fileSize(ALL["takumi-wasm"].wasmPath), binaryFile: "pkg/takumi_wasm_bg.wasm", glue: fileSize(path.join(tw, "dist/export.mjs")), glueFile: "dist/export.mjs" },
    "takumi-native": { binary: native && existsSync(native) ? { ...fileSize(native) } : null, binaryFile: ".node addon", glue: fileSize(path.join(tc, "dist/export.mjs")), glueFile: "dist/export.mjs" },
    bm: { binary: fileSize(ALL.bm.wasmPath), binaryFile: "zig-out/bin/bm_engine.wasm", glue: dirJs(path.join(ROOT_DIR, "js")), glueFile: "js/*.mjs" },
  };
}
