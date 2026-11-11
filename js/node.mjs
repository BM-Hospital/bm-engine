// Node.js / Bun entry: loads the wasm binary from disk and initialises synchronously on import.
import { readFileSync } from "node:fs";
import * as bm from "./index.mjs";

// A fresh local build wins over the packaged copy.
const candidates = [
  new URL("../zig-out/bin/bm_engine.wasm", import.meta.url),
  new URL("./bm_engine.wasm", import.meta.url),
];

let bytes;
for (const url of candidates) {
  try {
    bytes = readFileSync(url);
    break;
  } catch {}
}
if (!bytes) throw new Error("bm-engine: bm_engine.wasm not found (run `node scripts/build.mjs`)");

bm.initSync(bytes);

export * from "./index.mjs";
export default bm.default;
