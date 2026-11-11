import { readFileSync, existsSync } from "node:fs";
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
function filesJs(dir, names) {
  const files = names.map((f) => path.join(dir, f)).filter((f) => existsSync(f));
  if (!files.length) return null;
  return { files: files.map((f) => path.basename(f)), ...sizeOf(Buffer.concat(files.map((f) => readFileSync(f)))) };
}

/** Binary + JS glue sizes for each engine (null when the file doesn't exist). bm also lists the
 *  release binaries of every build profile (js/bm_engine.{core,standard}.wasm, js/bm_engine.wasm = full)
 *  and the WOFF add-on (js/bm_woff.wasm) when `node scripts/build.mjs` has produced them. */
export function collectSizes(ALL) {
  const tw = path.join(BENCH_DIR, "node_modules/@takumi-rs/wasm");
  const tc = path.join(BENCH_DIR, "node_modules/@takumi-rs/core");
  const native = ALL["takumi-native"].nativePath;
  const js = path.join(ROOT_DIR, "js");
  return {
    "takumi-wasm": { binary: fileSize(ALL["takumi-wasm"].wasmPath), binaryFile: "pkg/takumi_wasm_bg.wasm", glue: fileSize(path.join(tw, "dist/export.mjs")), glueFile: "dist/export.mjs" },
    "takumi-native": { binary: native && existsSync(native) ? { ...fileSize(native) } : null, binaryFile: ".node addon", glue: fileSize(path.join(tc, "dist/export.mjs")), glueFile: "dist/export.mjs" },
    bm: {
      binary: fileSize(ALL.bm.wasmPath), binaryFile: path.relative(ROOT_DIR, ALL.bm.wasmPath).split(path.sep).join("/"),
      glue: filesJs(js, ["engine.mjs", "index.mjs", "node.mjs"]), glueFile: "js/engine.mjs + js/index.mjs + js/node.mjs",
      profiles: {
        core: fileSize(path.join(js, "bm_engine.core.wasm")),
        standard: fileSize(path.join(js, "bm_engine.standard.wasm")),
        full: fileSize(path.join(js, "bm_engine.wasm")),
        woffAddon: fileSize(path.join(js, "bm_woff.wasm")),
      },
    },
  };
}
