// Lazily loaded add-on modules (js/addons.mjs).
import type { ByteBuf } from "./index.mjs";

/**
 * Instantiates the WOFF add-on (bm_woff.wasm, ~90 KB) and makes `registerFont` accept WOFF / WOFF2 on
 * builds without built-in support. `input`: wasm bytes, a WebAssembly.Module, a URL / Request / Response,
 * or omitted (Node: the file next to addons.mjs; browsers: fetched from the same directory).
 */
export declare function loadWoff(input?: ByteBuf | WebAssembly.Module | URL | string | Request | Response | Promise<unknown>): Promise<{ builtIn: boolean }>;
/** WOFF / WOFF2 -> sfnt (TTF / OTF) bytes with the loaded add-on. */
export declare function decodeWoff(bytes: ByteBuf): Uint8Array;
