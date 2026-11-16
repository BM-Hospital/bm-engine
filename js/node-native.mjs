// bm-render/native (Node.js / Bun / Deno): the native Node-API addon, or an error when it is not installed for
// this platform (no wasm fallback; `bm-render` itself falls back automatically). Same API as ./index.mjs;
// init() / initSync() are no-ops. Shares its instance with `bm-render` when that entry is running natively.
import { nativeBinding, nativeError, nativeNames } from "./native.mjs";

const binding = nativeBinding();
if (!binding) {
  throw new Error(`bm-render/native: the native addon is not available (${nativeError()}). Install the optional package ` +
    `${nativeNames().map((n) => "@hunghg255/bm-render-" + n).join(" or ") || "for your platform (none is published for it)"}, or import "bm-render" ` +
    `(falls back to WebAssembly) / "bm-render/full" (always WebAssembly).`);
}

export const { init, initSync, Renderer, features, setGlyphCacheMaxBytes, backend } = binding;
export { Prepared, setWoffDecoder } from "./engine.mjs";
export default init;
