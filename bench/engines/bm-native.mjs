// Adapter: bm-render's native Node-API addon (js/node-native.mjs -> native/dist/<platform>/..., or the installed
// bm-render-<platform> package, or $BM_RENDER_NATIVE_PATH). Not registered in engines/index.mjs by default:
// add `"bm-native": bmNative` there to put it next to the wasm build in a benchmark run.
// The harness runs fine when the addon is missing: the engine is then "unavailable".
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ROOT_DIR } from "../lib/assets.mjs";
const entry = path.join(ROOT_DIR, "js", "node-native.mjs");
const loader = await import(pathToFileURL(path.join(ROOT_DIR, "js", "native.mjs")).href);
const addon = loader.loadNative();

export default {
  name: "bm-native",
  available: !!addon,
  nativePath: addon ? `bm-render-${loader.nativeNames()[0]}` : loader.nativeError(),
  entry,
  rawAlpha: "straight",
  async create({ fonts = [] } = {}) {
    const t0 = performance.now();
    const mod = await import(pathToFileURL(entry).href);
    const r = new mod.Renderer();
    const initMs = performance.now() - t0;
    const inst = {
      name: "bm-native",
      initMs,
      async registerFont(f) {
        const data = f.data ?? new Uint8Array(readFileSync(f.path));
        await r.registerFont({ name: f.name, data, weight: f.weight, style: f.style });
      },
      // render() runs on the libuv thread pool; renderSync() on the calling thread
      render: (node, opts) => r.render(node, opts),
      renderSync: (node, opts) => r.renderSync(node, opts),
      measure: (node, opts) => r.measure(node, opts),
      memoryBytes: () => r.memoryBytes(),
      dispose() { try { r.free(); } catch {} },
    };
    for (const f of fonts) await inst.registerFont(f);
    return inst;
  },
};
