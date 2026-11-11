// Lazily loaded add-on wasm modules for the smaller engine builds.
//
//   import { loadWoff } from "bm-engine/woff";
//   await loadWoff();   // Node: reads bm_woff.wasm next to this file; bundlers: emitted asset via new URL(...);
//                       // Workers: await loadWoff(woffModule) with  import woffModule from "bm-engine/woff.wasm"
//   renderer.registerFont(woff2Bytes);      // now works on a build without WOFF support
//
// bm_woff.wasm (WOFF / WOFF2 -> sfnt, the engine's own decoder incl. brotli) is a separate ~90 KB module
// with no imports; registerFont uses it automatically when the main binary has no WOFF support. The
// converted font is byte-identical to what the built-in path registers. The decoder is shared by every
// entry (bm-engine, bm-engine/core, ...) in the process.
import { setWoffDecoder, readFileUrl } from "./engine.mjs";
import { features } from "./index.mjs";

let woff = null;
let loading = null;

async function bytesOf(input) {
  input = await input;
  if (input == null) {
    const url = new URL("./bm_woff.wasm", import.meta.url);
    if (url.protocol === "file:") return readFileUrl(url);
    input = url;
  }
  if (typeof input === "string" || input instanceof URL || (typeof Request !== "undefined" && input instanceof Request)) input = await fetch(input);
  if (typeof Response !== "undefined" && input instanceof Response) {
    if (!input.ok) throw new Error(`bm-engine: failed to fetch bm_woff.wasm (${input.status}): ${input.url}`);
    return new Uint8Array(await input.arrayBuffer());
  }
  return input;
}

/** Converts WOFF / WOFF2 bytes to an sfnt (TTF / OTF) with the loaded add-on. */
export function decodeWoff(bytes) {
  if (!woff) throw new Error("bm-engine: call loadWoff() first");
  const W = woff;
  const src = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes.buffer ?? bytes, bytes.byteOffset ?? 0, bytes.byteLength);
  const p = W.bm_alloc(src.length || 1);
  if (!p) throw new Error("bm-engine: out of memory (woff add-on)");
  new Uint8Array(W.memory.buffer).set(src, p);
  const st = W.bm_woff_decode(p, src.length);
  W.bm_free(p, src.length || 1);
  if (st !== 0) throw new Error(st === 2 ? "bm-engine: out of memory (woff add-on)" : "bm-engine: invalid WOFF/WOFF2 font data");
  const rp = W.bm_woff_result_ptr(), rn = W.bm_woff_result_len();
  const out = new Uint8Array(W.memory.buffer).slice(rp, rp + rn);
  W.bm_woff_release();
  return out;
}

/**
 * Instantiates the WOFF add-on (bm_woff.wasm) and makes `registerFont` accept WOFF / WOFF2 on builds
 * without built-in support. `input`: bytes, a WebAssembly.Module, a URL / Request / Response, or
 * omitted (Node: the file next to this module; browsers: fetched from the same directory).
 */
export async function loadWoff(input) {
  if (!woff) {
    if (!loading) {
      loading = (async () => {
        const src = await bytesOf(input);
        const inst = src instanceof WebAssembly.Module ? await WebAssembly.instantiate(src, {}) : (await WebAssembly.instantiate(src, {})).instance;
        woff = inst.exports;
      })().finally(() => { loading = null; });
    }
    await loading;
  }
  setWoffDecoder(decodeWoff);
  return { builtIn: features.woff };
}
