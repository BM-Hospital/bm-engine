// Adapter: bm-render (Zig -> WASM port). Entry: js/node.mjs, wasm: zig-out/bin/bm_render.wasm, or the
// file named by $BM_WASM (e.g. another build profile: BM_WASM=../js/bm_render.core.wasm); js/node.mjs
// reads the same variable, so the harness and the sizes table use the same binary.
// The harness runs fine when either is missing: the engine is then "unavailable".
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ROOT_DIR } from "../lib/assets.mjs";
const entry = path.join(ROOT_DIR, "js", "node.mjs");
const wasmPath = process.env.BM_WASM ? path.resolve(process.env.BM_WASM) : path.join(ROOT_DIR, "zig-out", "bin", "bm_render.wasm");
if (process.env.BM_WASM) process.env.BM_WASM = wasmPath; // absolute for js/node.mjs (child processes inherit it)
// This adapter measures the wasm build: keep js/node.mjs from picking the native addon (see engines/bm-native.mjs).
process.env.BM_RENDER_BACKEND ||= "wasm";

export default {
  name: "bm",
  available: existsSync(entry) && existsSync(wasmPath),
  wasmPath,
  entry,
  // ASSUMPTION: bm "raw" is straight RGBA8 like takumi's. If bm returns premultiplied, set this to
  // "premultiplied" and the runner un-premultiplies before comparing.
  rawAlpha: "straight",
  async create({ fonts = [] } = {}) {
    const t0 = performance.now();
    const mod = await import(pathToFileURL(entry).href);
    const r = new mod.Renderer();
    const initMs = performance.now() - t0;
    const inst = {
      name: "bm",
      initMs,
      async registerFont(f) {
        const data = f.data ?? new Uint8Array(readFileSync(f.path));
        await r.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
      },
      // r.render already returns a fresh Uint8Array copied out of wasm memory (no extra copy here)
      render: (node, opts) => r.render(node, opts),
      measure: (node, opts) => r.measure?.(node, opts),
      memoryBytes: () => (typeof r.memoryBytes === "function" ? r.memoryBytes() : mod.Renderer.memoryBytes?.()),
      dispose() { try { r.free?.(); } catch {} },
    };
    for (const f of fonts) await inst.registerFont(f);
    return inst;
  },
};
