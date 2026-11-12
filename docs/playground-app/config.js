// Single place that resolves runtime URLs. Dev (`npm run playground` serves the repo root, page at
// /docs/playground-app/): JS/wasm under ../../js/, fonts under ../../assets/fonts/, pdf.js under ./third_party/.
// `build.mjs` writes a config.js with the self-contained layout (./vendor/, ./vendor/fonts/, ./vendor/pdfjs-<version>/)
// and the content hashes of the wasm files (`versions`, appended as ?v= so the host can cache them for a year) into
// its output folder - nothing is rewritten at runtime.
export const config = {
  mode: "dev",
  jsBase: "../../js/",
  fontsBase: "../../assets/fonts/",
  wasm: { core: "bm_engine.core.wasm", standard: "bm_engine.standard.wasm", full: "bm_engine.wasm", pdf: "bm_engine.pdf.wasm" },
  woffWasm: "bm_woff.wasm",
  // pdf.js (Apache-2.0, legacy build): the PDF preview where the browser has no built-in viewer. Loaded on demand.
  pdfjsBase: "./third_party/pdfjs-5.4.624/",
  versions: {},
};
