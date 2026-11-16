// The four engines of the native benchmark (bench/run-native.mjs), created directly through their public APIs.
//
//   bm-native      js/node-native.mjs (the Node-API addon)       renderSync (calling thread), render (libuv pool)
//   bm-wasm        js/engine.mjs createBinding + js/bm_render.wasm (full profile)   renderSync, render (same thread)
//   takumi-native  @takumi-rs/core                                render (async only: napi AsyncTask on the libuv
//                                                                 pool, rayon pool inside for some stages)
//   takumi-wasm    @takumi-rs/wasm dist/export.mjs + initSync     render (async wrapper, runs on the calling thread)
//
// Fonts: the fixture fonts (lib/fonts.mjs), registered with explicit family / weight / style, outside every timing.
import { readFileSync, existsSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { ROOT_DIR, BENCH_DIR } from "../lib/assets.mjs";
import { fontsFor } from "../lib/fonts.mjs";

export const ENGINES = ["bm-native", "bm-wasm", "takumi-native", "takumi-wasm"];
const require = createRequire(path.join(BENCH_DIR, "package.json"));
const TK = path.join(BENCH_DIR, "node_modules", "@takumi-rs");
export const PATHS = {
  bmWasm: process.env.BM_WASM ? path.resolve(process.env.BM_WASM) : path.join(ROOT_DIR, "js", "bm_render.wasm"),
  takumiWasm: path.join(TK, "wasm", "pkg", "takumi_wasm_bg.wasm"),
  takumiWasmGlue: path.join(TK, "wasm", "dist", "export.mjs"),
  takumiNative: path.join(TK, "core-win32-x64-msvc", "core.win32-x64-msvc.node"),
};

const fontBytes = new Map();
const bytesOf = (p) => { if (!fontBytes.has(p)) fontBytes.set(p, new Uint8Array(readFileSync(p))); return fontBytes.get(p); };

let bmNativeMod, bmWasmMod, takumiNativeMod, takumiWasmMod, takumiWasmMemory;
async function load(name) {
  switch (name) {
    case "bm-native":
      return (bmNativeMod ??= await import(pathToFileURL(path.join(ROOT_DIR, "js", "node-native.mjs")).href));
    case "bm-wasm": {
      if (!bmWasmMod) {
        const { createBinding } = await import(pathToFileURL(path.join(ROOT_DIR, "js", "engine.mjs")).href);
        const b = createBinding();
        b.initSync(readFileSync(PATHS.bmWasm));
        bmWasmMod = b;
      }
      return bmWasmMod;
    }
    case "takumi-native":
      return (takumiNativeMod ??= await import(pathToFileURL(require.resolve("@takumi-rs/core")).href));
    case "takumi-wasm": {
      if (!takumiWasmMod) {
        const m = await import(pathToFileURL(PATHS.takumiWasmGlue).href);
        takumiWasmMemory = m.initSync({ module: readFileSync(PATHS.takumiWasm) }).memory;
        takumiWasmMod = m;
      }
      return takumiWasmMod;
    }
  }
  throw new Error("unknown engine " + name);
}

/**
 * One renderer of `name` with the given font families registered (undefined = all fixture fonts).
 * Returns { name, sync?(node, opts), async(node, opts), animSync?(job), animAsync(job), memoryBytes?(), dispose() }.
 * Every result is a Uint8Array.
 */
export async function createEngine(name, families) {
  const mod = await load(name);
  const r = new mod.Renderer();
  for (const f of fontsFor(families)) await r.registerFont({ name: f.name, data: bytesOf(f.path), weight: f.weight, style: f.style });
  if (name === "bm-native" || name === "bm-wasm") {
    return {
      name, renderer: r,
      sync: (node, opts) => r.renderSync(node, opts),
      async: (node, opts) => r.render(node, opts),
      animSync: (job) => r.renderAnimationSync(job),
      animAsync: (job) => r.renderAnimation(job),
      memoryBytes: () => r.memoryBytes(),
      dispose() { try { r.free(); } catch {} },
    };
  }
  if (name === "takumi-native") {
    return {
      name, renderer: r,
      async: async (node, opts) => { const b = await r.render(node, opts); return new Uint8Array(b.buffer, b.byteOffset, b.byteLength); },
      animAsync: async (job) => { const b = await r.renderAnimation(job); return new Uint8Array(b.buffer, b.byteOffset, b.byteLength); },
      memoryBytes: null,
      dispose() {},
    };
  }
  return {
    name, renderer: r,
    async: (node, opts) => r.render(node, opts),
    animAsync: (job) => r.renderAnimation(job),
    memoryBytes: () => takumiWasmMemory.buffer.byteLength,
    dispose() { try { r.free(); } catch {} },
  };
}

const sha256 = (p) => (existsSync(p) ? createHash("sha256").update(readFileSync(p)).digest("hex") : null);
const pkgVersion = (dir) => { try { return JSON.parse(readFileSync(path.join(dir, "package.json"), "utf8")).version; } catch { return null; } };

/** Exact versions / files / hashes of every engine (no engine is loaded). */
export function engineVersions() {
  const manifestPath = path.join(ROOT_DIR, "native", "dist", "manifest.json");
  let manifest = null;
  try { manifest = JSON.parse(readFileSync(manifestPath, "utf8")); } catch {}
  const nativeName = process.platform === "win32" ? `win32-${process.arch}-msvc` : null;
  const nativeFile = process.env.BM_RENDER_NATIVE_PATH || (nativeName && path.join(ROOT_DIR, "native", "dist", nativeName, `bm-render.${nativeName}.node`));
  const rel = (p) => path.relative(ROOT_DIR, p).split(path.sep).join("/");
  return {
    "bm-native": { package: "bm-render", version: pkgVersion(ROOT_DIR), file: nativeFile && rel(nativeFile), bytes: nativeFile && existsSync(nativeFile) ? statSync(nativeFile).size : null, sha256: nativeFile && sha256(nativeFile), zig: manifest?.zig ?? null, optimize: manifest?.files?.[nativeName]?.optimize ?? null },
    "bm-wasm": { package: "bm-render", version: pkgVersion(ROOT_DIR), profile: "full", file: rel(PATHS.bmWasm), bytes: existsSync(PATHS.bmWasm) ? statSync(PATHS.bmWasm).size : null, sha256: sha256(PATHS.bmWasm) },
    "takumi-native": { package: "@takumi-rs/core", version: pkgVersion(path.join(TK, "core")), binaryPackage: "@takumi-rs/core-win32-x64-msvc", binaryVersion: pkgVersion(path.join(TK, "core-win32-x64-msvc")), bytes: existsSync(PATHS.takumiNative) ? statSync(PATHS.takumiNative).size : null, sha256: sha256(PATHS.takumiNative) },
    "takumi-wasm": { package: "@takumi-rs/wasm", version: pkgVersion(path.join(TK, "wasm")), bytes: existsSync(PATHS.takumiWasm) ? statSync(PATHS.takumiWasm).size : null, sha256: sha256(PATHS.takumiWasm) },
  };
}
