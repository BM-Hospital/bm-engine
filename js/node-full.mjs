// bm-engine/full on Node.js / Bun / Deno: the full profile (bm_engine.wasm), read from next to this file and
// initialised synchronously on import (shares ./full.mjs's module instance). Same API as ./index.mjs.
import { readFileSync } from "node:fs";
import { initSync } from "./full.mjs";

initSync(readFileSync(new URL("./bm_engine.wasm", import.meta.url)));

export * from "./full.mjs";
export { default } from "./full.mjs";
