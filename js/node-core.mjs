// bm-engine/core on Node.js / Bun / Deno: the core profile (bm_engine.core.wasm), read from next to this file and
// initialised synchronously on import (shares ./core.mjs's module instance). Same API as ./index.mjs.
import { readFileSync } from "node:fs";
import { initSync } from "./core.mjs";

initSync(readFileSync(new URL("./bm_engine.core.wasm", import.meta.url)));

export * from "./core.mjs";
export { default } from "./core.mjs";
