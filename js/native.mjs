// bm-engine internal (Node.js / Bun / Deno only): finds and loads the native Node-API addon and wraps it as an
// engine backend for js/engine.mjs. Imported by js/node.mjs (`bm-engine` on Node: native when available, else
// wasm) and js/node-native.mjs (`bm-engine/native`: native or an error). The wasm-only entries never import
// this file, so bundles for browsers / edge runtimes contain no `require` of a `.node` file.
//
// Where the addon is looked for (first that loads wins; nothing here ever throws):
//   1. $BM_ENGINE_NATIVE_PATH: a `.node` file. When set, it is the ONLY candidate.
//   2. a source checkout's build output: ../native/dist/<name>/bm-engine.<name>.node (scripts/build-native.mjs)
//   3. the per-platform npm package `bm-engine-<name>` (an optional dependency whose main is the `.node` file)
// with <name> = win32-x64-msvc | win32-arm64-msvc | linux-x64-gnu | linux-x64-musl | linux-arm64-gnu |
// linux-arm64-musl | darwin-x64 | darwin-arm64. On Linux the C library is detected (glibc / musl); the other
// variant is tried when the detected one does not load.
//
// Design, build and the internal addon interface: docs/NATIVE.md.
import { createRequire } from "node:module";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createBinding, builtInWoffDecoder } from "./engine.mjs";

/** Interface version of the addon this file understands (src/native.zig `abi_version`). */
export const NATIVE_ABI = 1;

const dec = new TextDecoder();
const proc = typeof process !== "undefined" ? process : { env: {}, platform: "", arch: "" };

/** True when the process runs on musl libc (Alpine, ...). */
function isMusl() {
  if (proc.platform !== "linux") return false;
  try {
    if (existsSync("/etc/alpine-release")) return true;
  } catch {}
  try {
    // what the running node binary itself is linked against
    if (proc.report && typeof proc.report.getReport === "function") {
      const prev = proc.report.excludeNetwork;
      try {
        if (prev !== undefined) proc.report.excludeNetwork = true; // (the network section can be slow)
        const report = proc.report.getReport();
        if (report && report.header && report.header.glibcVersionRuntime) return false;
        if (report && Array.isArray(report.sharedObjects) && report.sharedObjects.some((f) => /libc\.musl-|ld-musl-/.test(f))) return true;
      } finally {
        if (prev !== undefined) proc.report.excludeNetwork = prev;
      }
    }
  } catch {}
  try {
    const ldd = readFileSync("/usr/bin/ldd", "utf8");
    if (ldd.includes("musl")) return true;
  } catch {}
  return false;
}

/** Addon names for this process, most likely first ([] on an unsupported platform). */
export function nativeNames() {
  const arch = proc.arch === "x64" || proc.arch === "arm64" ? proc.arch : null;
  if (!arch) return [];
  if (proc.platform === "win32") return [`win32-${arch}-msvc`];
  if (proc.platform === "darwin") return [`darwin-${arch}`];
  if (proc.platform === "linux") return isMusl() ? [`linux-${arch}-musl`, `linux-${arch}-gnu`] : [`linux-${arch}-gnu`, `linux-${arch}-musl`];
  return [];
}

let loaded; // undefined = not tried yet; null = unavailable
const errors = [];

/** The addon's exports, or null when no usable addon is installed for this platform. Never throws. */
export function loadNative() {
  if (loaded !== undefined) return loaded;
  loaded = null;
  try {
    const require = createRequire(import.meta.url);
    const names = nativeNames();
    if (names.length === 0) errors.push(`no native build for ${proc.platform}-${proc.arch}`);
    const candidates = [];
    const forced = proc.env.BM_ENGINE_NATIVE_PATH;
    if (forced) candidates.push(resolve(forced)); // (relative to the working directory)
    else {
      for (const name of names) {
        const dev = fileURLToPath(new URL(`../native/dist/${name}/bm-engine.${name}.node`, import.meta.url));
        if (existsSync(dev)) candidates.push(dev);
      }
      for (const name of names) candidates.push(`bm-engine-${name}`);
    }
    for (const id of candidates) {
      try {
        const addon = require(id);
        if (!addon || addon.abi !== NATIVE_ABI || typeof addon.run !== "function") {
          errors.push(`${id}: addon interface version ${addon && addon.abi}, expected ${NATIVE_ABI}`);
          continue;
        }
        loaded = addon;
        break;
      } catch (e) {
        errors.push(`${id}: ${e && e.code === "MODULE_NOT_FOUND" ? "not installed" : String(e && e.message).split("\n")[0]}`);
      }
    }
  } catch (e) {
    errors.push(String(e && e.message));
  }
  return loaded;
}

/** Why loadNative() returned null (for error messages). */
export function nativeError() {
  return errors.join("; ") || "not tried";
}

/** The addon as a js/engine.mjs backend (see the interface there). */
export function nativeBackend(addon) {
  const ops = addon.ops;
  const id = (op) => {
    const i = ops[op];
    if (i === undefined) throw new Error(`bm-engine: ${op} is not supported by this native build`);
    return i;
  };
  return {
    name: "native",
    /** what init() / initSync() resolve to */
    exports: addon,
    ready: () => true,
    featureBits: () => addon.features >>> 0,
    has: (op) => ops[op] !== undefined,
    create: () => addon.create(),
    destroy: (h) => addon.destroy(h),
    memoryBytes: () => addon.memoryBytes(),
    run(h, op, arg0, arg1, input, options, atts, text) {
      const out = addon.run(h, id(op), arg0, arg1, input, options, atts);
      return text ? dec.decode(out) : out;
    },
    runAsync(h, op, arg0, arg1, input, options, atts, text) {
      const p = addon.runAsync(h, id(op), arg0, arg1, input, options, atts);
      return text ? p.then((out) => dec.decode(out)) : p;
    },
  };
}

let binding; // undefined = not tried yet

/**
 * The public API (`{ init, initSync, Renderer, features, setGlyphCacheMaxBytes, backend }`, see js/engine.mjs
 * `createBinding`) on the native addon, or null when it is unavailable. One instance per module realm.
 */
export function nativeBinding() {
  if (binding !== undefined) return binding;
  const addon = loadNative();
  if (!addon) return (binding = null);
  binding = createBinding(undefined, nativeBackend(addon));
  // WOFF / WOFF2 is compiled in: wasm entries without it (bm-engine/core) decode through the addon as well,
  // and bm-engine/woff's loadWoff() has nothing to load.
  if (addon.ops.woffDecode !== undefined) {
    builtInWoffDecoder((bytes) => {
      const src = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes.buffer ?? bytes, bytes.byteOffset ?? 0, bytes.byteLength);
      return addon.run(null, addon.ops.woffDecode, 0, 0, null, null, ["", src, 0, 0, 0]);
    });
  }
  return binding;
}
