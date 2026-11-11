// Node.js / Bun entry: loads the wasm binary from disk and initialises synchronously on import.
//
// Which binary: $BM_WASM (a path) if set; else $BM_PROFILE = core | standard | full selects
// js/bm_engine.<profile>.wasm; else a fresh local build (zig-out/bin/bm_engine.wasm) wins over the
// packaged full build (js/bm_engine.wasm). Fixed-profile entries: node-core.mjs, node-standard.mjs.
// All entries share one module instance (js/index.mjs): the first one imported decides the binary.
import { readFileSync } from "node:fs";
import * as bm from "./index.mjs";

const env = (typeof process !== "undefined" && process.env) || {};
const profile = env.BM_PROFILE && env.BM_PROFILE !== "full" ? env.BM_PROFILE : null;
const candidates = env.BM_WASM ? [env.BM_WASM]
  : profile ? [new URL(`./bm_engine.${profile}.wasm`, import.meta.url)]
  : [new URL("../zig-out/bin/bm_engine.wasm", import.meta.url), new URL("./bm_engine.wasm", import.meta.url)];

let bytes;
for (const url of candidates) {
  try {
    bytes = readFileSync(url);
    break;
  } catch {}
}
if (!bytes) throw new Error(`bm-engine: ${candidates.map(String).join(" / ")} not found (run \`node scripts/build.mjs\`)`);

bm.initSync(bytes);

export * from "./index.mjs";
export default bm.default;
