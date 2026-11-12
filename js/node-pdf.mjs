// bm-engine/pdf on Node.js / Bun / Deno (the "node" condition of `import ... from "bm-engine/pdf"`): ready on import.
//
// Backend (exported as `backend`: "native" | "wasm"), chosen exactly as js/node.mjs chooses it for `bm-engine`:
//   * the native Node-API addon when one is installed for this platform and it was built with PDF output (the
//     published ones are; js/native.mjs): the same addon `bm-engine` uses, the same PDF bytes as the wasm build,
//     faster, and the async methods (PdfRenderer.render / measure, Renderer.renderPdf / measurePdf, ...) run on
//     the libuv thread pool instead of blocking the event loop;
//   * otherwise, automatically and silently, the pdf profile (bm_engine.pdf.wasm = full + PDF output), read from
//     the package (js/wasm-file.mjs: survives bundling) and initialised synchronously on import (./pdf.mjs's
//     module instance).
// $BM_ENGINE_BACKEND = wasm | native forces one (native without a usable addon = an error on import). $BM_WASM /
// $BM_PROFILE select the wasm backend here too, as they do for `bm-engine` (they name binaries of the image
// entry; this entry always loads bm_engine.pdf.wasm).
// Same API as ./pdf.mjs (./pdf.d.mts).
import * as wasm from "./pdf.mjs";
import { nativePdfBinding, nativeError } from "./native.mjs";
import { pdfApi } from "./pdf-api.mjs";
import { readPackageWasm } from "./wasm-file.mjs";

const env = (typeof process !== "undefined" && process.env) || {};
const want = String(env.BM_ENGINE_BACKEND || "").toLowerCase();
if (want && want !== "wasm" && want !== "native") throw new Error(`bm-engine: BM_ENGINE_BACKEND must be "wasm" or "native", not "${env.BM_ENGINE_BACKEND}"`);
const native = want === "native" || (!want && !env.BM_WASM && !env.BM_PROFILE) ? nativePdfBinding() : null;
if (!native && want === "native") throw new Error(`bm-engine: BM_ENGINE_BACKEND=native, but the native addon is not available for bm-engine/pdf (${nativeError()})`);

if (!native) wasm.initSync(readPackageWasm("bm_engine.pdf.wasm"));

// (the same names as ./pdf.mjs, bound to the active backend)
export const { init, initSync, Renderer, features, setGlyphCacheMaxBytes, backend } = native || wasm;
export const { PdfRenderer, prepare, render, measure } = native ? pdfApi(native.Renderer) : wasm;
export const { wasmUrl, profile } = wasm;
export { Prepared, setWoffDecoder } from "./engine.mjs";
export { PageNumber, TotalPages, TargetPageNumber } from "./pdf-api.mjs";
export default init;
