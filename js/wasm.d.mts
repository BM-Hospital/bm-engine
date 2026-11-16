// Typings for the raw wasm subpaths (bm-render/wasm, /core.wasm, /standard.wasm, /full.wasm, /woff.wasm).
// What such an import yields depends on the toolchain; this declares the Cloudflare Workers / wrangler
// (and esbuild `--loader:.wasm=...` / Deno `--unstable-wasm-modules`-style) form: a compiled module, the
// value `init(wasm)` and `loadWoff(wasm)` accept. Vite users import `bm-render/full.wasm?url` instead
// (typed as a string by `vite/client`).
import type {} from "./index.mjs"; // global WebAssembly.Module stand-in for projects without the DOM lib

declare const wasm: WebAssembly.Module;
export default wasm;
