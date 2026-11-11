// Adapter: @takumi-rs/wasm (published Rust renderer compiled to WASM).
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { pathToFileURL } from "node:url";
const pkgDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "node_modules", "@takumi-rs", "wasm");
const wasmPath = pkgDir && path.join(pkgDir, "pkg", "takumi_wasm_bg.wasm");
const gluePath = pkgDir && path.join(pkgDir, "dist", "export.mjs");

export default {
  name: "takumi-wasm",
  available: !!(wasmPath && existsSync(wasmPath)),
  wasmPath,
  gluePath,
  /** takumi's "raw" output is straight (non-premultiplied) RGBA8 (verified by probe/alpha.mjs, see README). */
  rawAlpha: "straight",
  async create({ fonts = [] } = {}) {
    // Low-level entry (no auto-init) so we can keep the returned `memory`.
    const mod = await import(pathToFileURL(gluePath).href);
    const bytes = readFileSync(wasmPath);
    const t0 = performance.now();
    const out = mod.initSync({ module: bytes }); // compile + instantiate (idempotent per process)
    const initMs = performance.now() - t0;
    const memory = out.memory;
    const r = new mod.Renderer();
    const inst = {
      name: "takumi-wasm",
      initMs,
      async registerFont(f) {
        const data = f.data ?? readFileSync(f.path);
        await r.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
      },
      render: (node, opts) => r.render(node, opts),
      measure: (node, opts) => r.measure(node, opts),
      memoryBytes: () => memory.buffer.byteLength,
      dispose() { try { r.free(); } catch {} },
    };
    for (const f of fonts) await inst.registerFont(f);
    return inst;
  },
};
