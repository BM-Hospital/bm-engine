// bm-engine/pdf (browsers, bundlers, Deno, edge runtimes): the pdf build profile (bm_engine.pdf.wasm = full + PDF output)
// with its own module instance, plus the takumi-pdf style API: `PdfRenderer`, `render`, `measure`, `prepare` and the
// page counter primitives. `await init()` without an argument loads bm_engine.pdf.wasm from next to this file through
// `new URL("./bm_engine.pdf.wasm", import.meta.url)`; where that cannot work (Cloudflare Workers) pass the module:
//
//   import wasm from "bm-engine/pdf.wasm";
//   import { init, PdfRenderer } from "bm-engine/pdf";
//   await init(wasm);
//   const pdf = await new PdfRenderer().render(node, { size: "a4", margin: 24 });   // Uint8Array
//
// On Node.js this subpath resolves to ./node-pdf.mjs: the native addon when it is installed (the same addon as
// `bm-engine`, the same PDF bytes), else this wasm build, read from disk and initialised on import.
// API: ./pdf.d.mts. The image `Renderer` of the other entries is exported too, with `renderPdf` / `measurePdf` methods.
import { createBinding } from "./engine.mjs";
import { pdfApi } from "./pdf-api.mjs";

const binding = createBinding(() => new URL("./bm_engine.pdf.wasm", import.meta.url));

export const { init, initSync, Renderer, features, setGlyphCacheMaxBytes, wasmUrl, backend } = binding;
export { Prepared, setWoffDecoder } from "./engine.mjs";
/** Build profile of this entry. */
export const profile = "pdf";
export default init;

export const { PdfRenderer, prepare, render, measure } = pdfApi(Renderer);
export { PageNumber, TotalPages, TargetPageNumber } from "./pdf-api.mjs";
