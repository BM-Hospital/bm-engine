// bm-engine/pdf on Node.js / Bun / Deno: the pdf profile (bm_engine.pdf.wasm), read from next to this file and
// initialised synchronously on import (shares ./pdf.mjs's module instance). Same API as ./pdf.mjs.
import { readFileSync } from "node:fs";
import { initSync } from "./pdf.mjs";

initSync(readFileSync(new URL("./bm_engine.pdf.wasm", import.meta.url)));

export * from "./pdf.mjs";
export { default } from "./pdf.mjs";
