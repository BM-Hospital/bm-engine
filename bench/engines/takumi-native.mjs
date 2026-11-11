// Adapter: @takumi-rs/core (native N-API). Reference only.
import { fileURLToPath } from "node:url";
import { existsSync, statSync, readFileSync } from "node:fs";
import path from "node:path";
const nodePath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "node_modules", "@takumi-rs", "core-win32-x64-msvc", "core.win32-x64-msvc.node");

export default {
  name: "takumi-native",
  available: !!(nodePath && existsSync(nodePath)),
  nativePath: nodePath,
  rawAlpha: "straight",
  async create({ fonts = [] } = {}) {
    const t0 = performance.now();
    const mod = await import("@takumi-rs/core");
    const r = new mod.Renderer();
    const initMs = performance.now() - t0;
    const inst = {
      name: "takumi-native",
      initMs,
      async registerFont(f) {
        const data = f.data ?? readFileSync(f.path);
        await r.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
      },
      render: async (node, opts) => new Uint8Array(await r.render(node, opts)),
      measure: (node, opts) => r.measure(node, opts),
      dispose() {},
    };
    for (const f of fonts) await inst.registerFont(f);
    return inst;
  },
};
export const nativeSize = () => (nodePath && existsSync(nodePath) ? statSync(nodePath).size : null);
