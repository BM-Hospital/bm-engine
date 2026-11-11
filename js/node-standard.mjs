// Node.js / Bun entry for the standard profile (js/bm_engine.standard.wasm, built by `node scripts/build.mjs`).
// Same API as node.mjs; `features` tells what this binary supports.
import { readFileSync } from "node:fs";
import * as bm from "./index.mjs";

bm.initSync(readFileSync(new URL("./bm_engine.standard.wasm", import.meta.url)));

export * from "./index.mjs";
export default bm.default;
