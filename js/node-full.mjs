// bm-render/full on Node.js / Bun / Deno: the full profile (bm_render.wasm), read from the package (js/wasm-file.mjs: survives bundling) and
// initialised synchronously on import (shares ./full.mjs's module instance). Same API as ./index.mjs.
import { readPackageWasm } from "./wasm-file.mjs";
import { initSync } from "./full.mjs";

initSync(readPackageWasm("bm_render.wasm"));

export * from "./full.mjs";
export { default } from "./full.mjs";
