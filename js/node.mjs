// bm-engine on Node.js / Bun / Deno (the "node" condition of `import ... from "bm-engine"`): ready on import.
//
// Backend (exported as `backend`: "native" | "wasm"):
//   * the native Node-API addon when one is installed for this platform (js/native.mjs: the optional package
//     bm-engine-<platform>-<arch>[-<abi>], or $BM_ENGINE_NATIVE_PATH): same API and the same output bytes as the
//     full wasm build, faster, and the async methods (render, renderSvg, measure, renderAnimation, ...) run on
//     the libuv thread pool instead of blocking the event loop;
//   * otherwise, automatically and silently, the wasm binary: loaded from disk, ./index.mjs's module instance
//     initialised synchronously on import.
// $BM_ENGINE_BACKEND = wasm | native forces one (native without an addon = an error on import). Naming a wasm
// binary with $BM_WASM / $BM_PROFILE also selects the wasm backend. Always wasm: bm-engine/core, /standard,
// /full. Always native (or an error): bm-engine/native.
//
// Which wasm binary:
//   1. $BM_WASM (a file path) if set;
//   2. else $BM_PROFILE = core | standard | full selects bm_engine.<profile>.wasm of the package;
//   3. else, in a source checkout only (../build.zig exists), a fresh local build ../zig-out/bin/bm_engine.wasm;
//   4. else bm_engine.wasm of the package (the full profile; what the npm package ships).
// "Of the package" = the first readable of (js/wasm-file.mjs): next to this module (import.meta.url), the
// package resolved with createRequire (bm-engine/<subpath>), <cwd>/node_modules/bm-engine/js/. The later ones
// matter when a bundler moved this module away from its package (Next.js without serverExternalPackages,
// esbuild --bundle without --external:bm-engine) but node_modules is still there at run time.
// Fixed-profile entries with their own instances: bm-engine/core, /standard, /full (node-<profile>.mjs).
import { readFileSync, existsSync } from "node:fs";
import * as bm from "./index.mjs";
import { nativeBinding, nativeError } from "./native.mjs";
import { readPackageWasm, packageFile } from "./wasm-file.mjs";

const env = (typeof process !== "undefined" && process.env) || {};
const want = String(env.BM_ENGINE_BACKEND || "").toLowerCase();
if (want && want !== "wasm" && want !== "native") throw new Error(`bm-engine: BM_ENGINE_BACKEND must be "wasm" or "native", not "${env.BM_ENGINE_BACKEND}"`);
const native = want === "native" || (!want && !env.BM_WASM && !env.BM_PROFILE) ? nativeBinding() : null;
if (!native && want === "native") throw new Error(`bm-engine: BM_ENGINE_BACKEND=native, but the native addon is not available (${nativeError()})`);

if (!native) {
  const profile = env.BM_PROFILE && env.BM_PROFILE !== "full" ? env.BM_PROFILE : null;
  let bytes;
  if (env.BM_WASM) {
    try {
      bytes = readFileSync(env.BM_WASM);
    } catch (e) {
      throw new Error(`bm-engine: BM_WASM=${env.BM_WASM} cannot be read (${e && e.message})`);
    }
  } else {
    if (!profile) {
      // a source checkout: prefer the fresh local build
      const checkout = packageFile("../build.zig");
      const dev = checkout && existsSync(checkout) ? packageFile("../zig-out/bin/bm_engine.wasm") : null;
      if (dev) {
        try {
          bytes = readFileSync(dev);
        } catch {}
      }
    }
    bytes ??= readPackageWasm(profile ? `bm_engine.${profile}.wasm` : "bm_engine.wasm");
  }
  bm.initSync(bytes);
}

// (the same names as ./index.mjs, bound to the active backend)
export const { init, initSync, Renderer, features, setGlyphCacheMaxBytes, backend } = native || bm;
export { Prepared, setWoffDecoder } from "./engine.mjs";
export default init;
