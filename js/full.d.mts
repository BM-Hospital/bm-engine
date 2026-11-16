// bm-render/full: the full build profile (bm_render.wasm) with its own module instance. Same API as bm-render
// (./index.d.mts); init() may be called without an argument (and on Node.js it already ran on import).
import type { InitArgument, WasmExports } from "./index.mjs";

export * from "./index.mjs";
/**
 * Instantiates the full wasm. Without an argument it loads bm_render.wasm from next to the module
 * (`new URL("./bm_render.wasm", import.meta.url)`, which bundlers emit as an asset). On Cloudflare Workers pass
 * the module: `import wasm from "bm-render/full.wasm"; await init(wasm)`. Idempotent.
 */
export declare function init(input?: InitArgument): Promise<WasmExports>;
export default init;
/** The URL init() loads by default (throws where `import.meta.url` is unusable). */
export declare function wasmUrl(): URL;
/** Build profile of this entry. */
export declare const profile: "full";
