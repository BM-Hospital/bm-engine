// bm-engine/standard on Node.js / Bun / Deno: the standard profile (bm_engine.standard.wasm), read from the package (js/wasm-file.mjs: survives bundling) and
// initialised synchronously on import (shares ./standard.mjs's module instance). Same API as ./index.mjs.
import { readPackageWasm } from "./wasm-file.mjs";
import { initSync } from "./standard.mjs";

initSync(readPackageWasm("bm_engine.standard.wasm"));

export * from "./standard.mjs";
export { default } from "./standard.mjs";
