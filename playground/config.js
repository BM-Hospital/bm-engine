// Single place that resolves runtime URLs. Dev (repo root served): JS/wasm under ../js/, fonts under
// ../assets/fonts/. `node playground/build.mjs` writes playground/dist/config.js with the self-contained
// layout (./vendor/ and ./vendor/fonts/) - nothing is rewritten at runtime.
export const config = {
  mode: "dev",
  jsBase: "../js/",
  fontsBase: "../assets/fonts/",
  wasm: { core: "bm_engine.core.wasm", standard: "bm_engine.standard.wasm", full: "bm_engine.wasm" },
  woffWasm: "bm_woff.wasm",
};
