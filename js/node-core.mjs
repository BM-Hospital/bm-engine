// bm-engine/core on Node.js / Bun / Deno: the core profile (bm_engine.core.wasm), read from the package (js/wasm-file.mjs: survives bundling) and
// initialised synchronously on import (shares ./core.mjs's module instance). Same API as ./index.mjs.
import { readPackageWasm } from "./wasm-file.mjs";
import { initSync } from "./core.mjs";

initSync(readPackageWasm("bm_engine.core.wasm"));

export * from "./core.mjs";
export { default } from "./core.mjs";
