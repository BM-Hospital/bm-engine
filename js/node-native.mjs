// bm-engine/native (Node.js / Bun / Deno): the native Node-API addon, or an error when it is not installed for
// this platform (no wasm fallback; `bm-engine` itself falls back automatically). Same API as ./index.mjs;
// init() / initSync() are no-ops. Shares its instance with `bm-engine` when that entry is running natively.
import { nativeBinding, nativeError, nativeNames } from "./native.mjs";

const binding = nativeBinding();
if (!binding) {
  throw new Error(`bm-engine/native: the native addon is not available (${nativeError()}). Install the optional package ` +
    `${nativeNames().map((n) => "bm-engine-" + n).join(" or ") || "for your platform (none is published for it)"}, or import "bm-engine" ` +
    `(falls back to WebAssembly) / "bm-engine/full" (always WebAssembly).`);
}

export const { init, initSync, Renderer, features, setGlyphCacheMaxBytes, backend } = binding;
export { Prepared, setWoffDecoder } from "./engine.mjs";
export default init;
