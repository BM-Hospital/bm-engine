// bm-engine/standard on Node.js / Bun / Deno: the standard profile (bm_engine.standard.wasm), read from next to this file and
// initialised synchronously on import (shares ./standard.mjs's module instance). Same API as ./index.mjs.
import { readFileSync } from "node:fs";
import { initSync } from "./standard.mjs";

initSync(readFileSync(new URL("./bm_engine.standard.wasm", import.meta.url)));

export * from "./standard.mjs";
export { default } from "./standard.mjs";
