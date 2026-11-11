// bm-engine/woff: lazily loaded add-on modules (js/addons.mjs).
import type { ByteBuf, OutputBytes } from "./index.mjs";

/**
 * Instantiates the WOFF add-on (bm_woff.wasm, ~85 KiB) and makes `registerFont` accept WOFF / WOFF2 on
 * builds without built-in support (any entry in the process). `input`: wasm bytes, a WebAssembly.Module,
 * a URL / Request / Response, or omitted (Node: the file next to addons.mjs; bundlers / browsers:
 * `new URL("./bm_woff.wasm", import.meta.url)`). Idempotent. `builtIn` reports whether the `bm-engine`
 * entry's loaded build decodes WOFF itself.
 */
export declare function loadWoff(input?: ByteBuf | WebAssembly.Module | URL | string | Request | Response | Promise<unknown>): Promise<{ builtIn: boolean }>;
/** WOFF / WOFF2 -> sfnt (TTF / OTF) bytes with the loaded add-on. */
export declare function decodeWoff(bytes: ByteBuf): OutputBytes;
