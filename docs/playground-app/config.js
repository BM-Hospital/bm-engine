// Single place that resolves runtime URLs. Dev (`npm run playground` serves the repo root, page at
// /docs/playground-app/): JS/wasm under ../../js/, fonts under ../../assets/fonts/. `build.mjs` writes a config.js
// with the self-contained layout (./vendor/ and ./vendor/fonts/) into its output folder - nothing is rewritten at runtime.
export const config = {
  mode: "dev",
  jsBase: "../../js/",
  fontsBase: "../../assets/fonts/",
  wasm: { core: "bm_engine.core.wasm", standard: "bm_engine.standard.wasm", full: "bm_engine.wasm" },
  woffWasm: "bm_woff.wasm",
};
