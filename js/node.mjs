// bm-engine on Node.js / Bun / Deno (the "node" condition of `import ... from "bm-engine"`): loads the wasm
// binary from disk and initialises ./index.mjs's module instance synchronously on import.
//
// Which binary:
//   1. $BM_WASM (a file path) if set;
//   2. else $BM_PROFILE = core | standard | full selects bm_engine.<profile>.wasm next to this file;
//   3. else, in a source checkout only (../build.zig exists), a fresh local build ../zig-out/bin/bm_engine.wasm;
//   4. else bm_engine.wasm next to this file (the full profile; what the npm package ships).
// Fixed-profile entries with their own instances: bm-engine/core, /standard, /full (node-<profile>.mjs).
import { readFileSync, existsSync } from "node:fs";
import * as bm from "./index.mjs";

const env = (typeof process !== "undefined" && process.env) || {};
const profile = env.BM_PROFILE && env.BM_PROFILE !== "full" ? env.BM_PROFILE : null;
const packaged = new URL("./bm_engine.wasm", import.meta.url);
const dev = existsSync(new URL("../build.zig", import.meta.url)) ? [new URL("../zig-out/bin/bm_engine.wasm", import.meta.url)] : [];
const candidates = env.BM_WASM ? [env.BM_WASM]
  : profile ? [new URL(`./bm_engine.${profile}.wasm`, import.meta.url)]
  : [...dev, packaged];

let bytes;
for (const url of candidates) {
  try {
    bytes = readFileSync(url);
    break;
  } catch {}
}
if (!bytes) throw new Error(`bm-engine: ${candidates.map(String).join(" / ")} not found${dev.length ? " (run `node scripts/build.mjs`)" : ""}`);

bm.initSync(bytes);

export * from "./index.mjs";
export default bm.default;
