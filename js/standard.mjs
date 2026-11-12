// bm-engine/standard (browsers, bundlers, Deno, edge runtimes): the standard build profile (bm_engine.standard.wasm) with its own
// module instance. `await init()` without an argument loads bm_engine.standard.wasm from next to this file through
// `new URL("./bm_engine.standard.wasm", import.meta.url)`, a pattern Vite, webpack 5, Rollup and Parcel turn into an emitted
// asset. Where that cannot work (Cloudflare Workers / workerd), pass the precompiled module instead:
//
//   import wasm from "bm-engine/standard.wasm";  // a WebAssembly.Module under wrangler
//   import { init, Renderer } from "bm-engine/standard";
//   await init(wasm);
//
// On Node.js this subpath resolves to ./node-standard.mjs, which reads the file and initialises on import.
// API: see ./index.mjs and ./index.d.mts.
import { createBinding } from "./engine.mjs";

const binding = createBinding(() => new URL("./bm_engine.standard.wasm", import.meta.url));

export const { init, initSync, Renderer, features, setGlyphCacheMaxBytes, wasmUrl, backend } = binding;
export { Prepared, setWoffDecoder } from "./engine.mjs";
/** Build profile of this entry. */
export const profile = "standard";
export default init;
