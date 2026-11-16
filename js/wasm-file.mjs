// bm-render internal (Node.js / Bun / Deno only): reads one of the package's wasm files from disk, for the Node
// entries (js/node.mjs, node-core.mjs, node-standard.mjs, node-full.mjs, node-pdf.mjs), in a way that survives bundling.
//
// Tried in order, first readable wins:
//   1. next to this module: new URL("./<file>", import.meta.url), written literally per file so that bundlers
//      that understand the pattern (webpack 5, Turbopack, Rollup / Vite SSR) emit / trace the asset and give
//      back its new location;
//   2. the installed package: createRequire(<this module>).resolve("bm-render/<subpath>") (the subpath exports
//      of package.json), which still works when a bundler moved this module but node_modules is present;
//   3. <cwd>/node_modules/bm-render/js/<file>.
// When all fail the error names every location and the usual fixes (keep bm-render external to the bundler).
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const proc = typeof process !== "undefined" ? process : { env: {} };

/**
 * A file: URL for this module that createRequire() accepts, even when a bundler replaced import.meta.url:
 * import.meta.url, else the CommonJS __filename of a bundle, else a file in the working directory.
 */
export function moduleBase() {
  try {
    const u = import.meta.url;
    if (typeof u === "string" && u.startsWith("file:")) return u;
  } catch {}
  try {
    // eslint-disable-next-line no-undef
    if (typeof __filename === "string" && __filename) return pathToFileURL(__filename).href;
  } catch {}
  try {
    return pathToFileURL(join(proc.cwd ? proc.cwd() : ".", "bm-render-base.js")).href;
  } catch {}
  return "file:///bm-render-base.js";
}

const SUBPATH = {
  "bm_render.wasm": "full.wasm",
  "bm_render.core.wasm": "core.wasm",
  "bm_render.standard.wasm": "standard.wasm",
  "bm_render.pdf.wasm": "pdf.wasm",
};

/** new URL(<literal>, import.meta.url) for each shipped file (literal: see 1. above). */
function siblingUrl(file) {
  switch (file) {
    case "bm_render.wasm": return new URL("./bm_render.wasm", import.meta.url);
    case "bm_render.core.wasm": return new URL("./bm_render.core.wasm", import.meta.url);
    case "bm_render.standard.wasm": return new URL("./bm_render.standard.wasm", import.meta.url);
    case "bm_render.pdf.wasm": return new URL("./bm_render.pdf.wasm", import.meta.url);
  }
  return new URL("./" + file, moduleBase());
}

/** A path for whatever a bundler made of `new URL(...)` (a URL, a URL from another realm, a string). */
function toPath(u) {
  const href = typeof u === "string" ? u : String((u && u.href) || u);
  return href.startsWith("file:") ? fileURLToPath(href) : href;
}

/** Absolute path of a file relative to this module (null when import.meta.url is unusable). */
export function packageFile(rel) {
  try {
    const base = moduleBase();
    return base.startsWith("file:") ? fileURLToPath(new URL(rel, base)) : null;
  } catch {
    return null;
  }
}

/** The bytes of js/<file> of the installed package; throws a precise error when it cannot be found. */
export function readPackageWasm(file) {
  const tried = [];
  const attempt = (label, where) => {
    let p;
    try {
      p = where();
      return readFileSync(p);
    } catch (e) {
      tried.push(`${label}${p ? " " + p : ""}: ${e && e.code ? e.code : String(e && e.message).split("\n")[0]}`.replace(/  +/g, " "));
      return null;
    }
  };
  const bytes = attempt("next to the module", () => toPath(siblingUrl(file)))
    ?? attempt("package resolution", () => createRequire(moduleBase()).resolve(`bm-render/${SUBPATH[file] ?? file}`))
    ?? attempt("working directory", () => join(proc.cwd(), "node_modules", "bm-render", "js", file));
  if (bytes) return bytes;
  throw new Error(`bm-render: cannot find ${file} (${tried.join("; ")}). This happens when a bundler moved bm-render's ` +
    `Node.js entry away from its package: keep the package external (Next.js: serverExternalPackages: ["bm-render"]; ` +
    `esbuild: --external:bm-render; webpack: externals) or copy node_modules/bm-render/js/${file} next to the bundle; ` +
    `or name the file with BM_WASM=<path>.`);
}
