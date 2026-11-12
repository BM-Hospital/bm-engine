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
//   2. else $BM_PROFILE = core | standard | full selects bm_engine.<profile>.wasm next to this file;
//   3. else, in a source checkout only (../build.zig exists), a fresh local build ../zig-out/bin/bm_engine.wasm;
//   4. else bm_engine.wasm next to this file (the full profile; what the npm package ships).
// Fixed-profile entries with their own instances: bm-engine/core, /standard, /full (node-<profile>.mjs).
import { readFileSync, existsSync } from "node:fs";
import * as bm from "./index.mjs";
import { nativeBinding, nativeError } from "./native.mjs";

const env = (typeof process !== "undefined" && process.env) || {};
const want = String(env.BM_ENGINE_BACKEND || "").toLowerCase();
if (want && want !== "wasm" && want !== "native") throw new Error(`bm-engine: BM_ENGINE_BACKEND must be "wasm" or "native", not "${env.BM_ENGINE_BACKEND}"`);
const native = want === "native" || (!want && !env.BM_WASM && !env.BM_PROFILE) ? nativeBinding() : null;
if (!native && want === "native") throw new Error(`bm-engine: BM_ENGINE_BACKEND=native, but the native addon is not available (${nativeError()})`);

const profile = env.BM_PROFILE && env.BM_PROFILE !== "full" ? env.BM_PROFILE : null;
const packaged = new URL("./bm_engine.wasm", import.meta.url);
const dev = existsSync(new URL("../build.zig", import.meta.url)) ? [new URL("../zig-out/bin/bm_engine.wasm", import.meta.url)] : [];
const candidates = env.BM_WASM ? [env.BM_WASM]
  : profile ? [new URL(`./bm_engine.${profile}.wasm`, import.meta.url)]
  : [...dev, packaged];

if (!native) {
  let bytes;
  for (const url of candidates) {
    try {
      bytes = readFileSync(url);
      break;
    } catch {}
  }
  if (!bytes) throw new Error(`bm-engine: ${candidates.map(String).join(" / ")} not found${dev.length ? " (run `node scripts/build.mjs`)" : ""}`);

  bm.initSync(bytes);
}

// (the same names as ./index.mjs, bound to the active backend)
export const { init, initSync, Renderer, features, setGlyphCacheMaxBytes, backend } = native || bm;
export { Prepared, setWoffDecoder } from "./engine.mjs";
export default init;
