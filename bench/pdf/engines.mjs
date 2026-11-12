// The PDF engines of bench/pdf, created through their public APIs with one call shape.
//
//   bm-native    js/node-pdf.mjs on the native addon (`bm-engine/pdf` on Node.js when the addon is installed / built:
//                native/dist/<platform>/ or $BM_ENGINE_NATIVE_PATH). renderSync on the calling thread, render on the
//                libuv pool.
//   bm-wasm      js/pdf.mjs + js/bm_engine.pdf.wasm (the wasm `pdf` profile; what `bm-engine/pdf` falls back to).
//                renderSync and render both run on the calling thread.
//   takumi-pdf   npm takumi-pdf (wasm; takumi-pdf has no native build: no @takumi-rs/pdf-* / optional dependency
//                exists on npm as of 0.20.0). dist/export.mjs + initSync, so the wasm memory is observable. Its
//                public render() is async but runs on the calling thread.
//
// createEngine(name) -> { name, backend, available, registerFont(font) -> Promise<family names>, render(src, opts)
//   -> Promise<Uint8Array>, renderSync?(src, opts), renderImage?(src, opts) (bm only: PNG of the same tree),
//   memoryBytes() (wasm linear memory / native live allocation, process-wide), dispose() }
// `font` is { name?, data: Uint8Array, weight?, style? } or bytes; both engines take the same shape.
import { readFileSync, existsSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { ROOT, PDF_DIR } from "./lib/tools.mjs";

export const ENGINES = ["bm-native", "bm-wasm", "takumi-pdf"];
const require = createRequire(path.join(PDF_DIR, "package.json"));
const TK_DIR = path.join(PDF_DIR, "node_modules", "takumi-pdf");
export const PATHS = {
  bmPdfWasm: path.join(ROOT, "js", "bm_engine.pdf.wasm"),
  bmNative: process.env.BM_ENGINE_NATIVE_PATH || path.join(ROOT, "native", "dist", `${process.platform}-${process.arch}-msvc`, `bm-engine.${process.platform}-${process.arch}-msvc.node`),
  takumiWasm: path.join(TK_DIR, "pkg", "takumi_pdf_wasm_bg.wasm"),
  takumiGlue: path.join(TK_DIR, "dist", "export.mjs"),
};

let nodePdf, wasmPdf, takumi, takumiMemory;
async function loadBmNodePdf() {
  // the entry a Node.js user gets for `import "bm-engine/pdf"`; BM_ENGINE_BACKEND=wasm in the environment makes
  // it the wasm build (then bm-native is reported unavailable)
  return (nodePdf ??= await import(pathToFileURL(path.join(ROOT, "js", "node-pdf.mjs")).href));
}
async function loadBmWasm() {
  if (!wasmPdf) {
    await loadBmNodePdf().catch(() => null); // node-pdf.mjs initialises pdf.mjs itself when it falls back to wasm
    const m = await import(pathToFileURL(path.join(ROOT, "js", "pdf.mjs")).href);
    m.initSync(readFileSync(PATHS.bmPdfWasm)); // no-op when already initialised
    wasmPdf = m;
  }
  return wasmPdf;
}
async function loadTakumi() {
  if (!takumi) {
    const m = await import(pathToFileURL(PATHS.takumiGlue).href);
    takumiMemory = m.initSync({ module: readFileSync(PATHS.takumiWasm) }).memory;
    takumi = m;
  }
  return takumi;
}

/** Whether `name` can run in this process (bm-native needs the addon and must not be forced off). */
export async function available(name) {
  if (name === "bm-native") { try { const m = await loadBmNodePdf(); return m.backend === "native" && m.features?.pdf !== false; } catch { return false; } }
  if (name === "bm-wasm") return existsSync(PATHS.bmPdfWasm);
  if (name === "takumi-pdf") return existsSync(PATHS.takumiWasm);
  return false;
}

const u8 = (b) => (b instanceof Uint8Array && b.constructor === Uint8Array ? b : new Uint8Array(b.buffer, b.byteOffset, b.byteLength));

export async function createEngine(name) {
  if (name === "bm-native" || name === "bm-wasm") {
    const mod = name === "bm-native" ? await loadBmNodePdf() : await loadBmWasm();
    if (name === "bm-native" && mod.backend !== "native") throw new Error("bm-native unavailable: bm-engine/pdf loaded the wasm backend (no native addon built for this checkout, or BM_ENGINE_BACKEND=wasm)");
    const r = new mod.PdfRenderer();
    let img = null; // an image Renderer with the same fonts, created on first use
    const fonts = [];
    return {
      name, backend: mod.backend, api: mod,
      async registerFont(font) { fonts.push(font); const fam = r.registerFont(font); if (img) img.registerFont(font); return (fam || []).map((f) => f.name); },
      render: async (src, opts) => u8(await r.render(src, opts)),
      renderSync: (src, opts) => u8(r.renderSync(src, opts)),
      async renderImage(src, opts) {
        if (!img) { img = new mod.Renderer(); for (const f of fonts) img.registerFont(f); }
        return u8(await img.render(src, opts));
      },
      measure: (src, opts) => r.measure(src, opts),
      memoryBytes: () => mod.Renderer.memoryBytes?.() ?? null,
      dispose() { try { r.free(); } catch {} try { img?.free(); } catch {} },
    };
  }
  if (name === "takumi-pdf") {
    const m = await loadTakumi();
    const r = new m.PdfRenderer();
    return {
      name, backend: "wasm", api: m,
      async registerFont(font) { const fam = await r.registerFont(font); return (fam || []).map((f) => f.name); },
      render: async (src, opts) => u8(await r.render(src, opts)),
      renderSync: null,
      measure: (src, opts) => r.measure(src, opts),
      memoryBytes: () => takumiMemory.buffer.byteLength,
      dispose() { try { r.free(); } catch {} },
    };
  }
  throw new Error("unknown engine " + name);
}

const sha256 = (p) => (existsSync(p) ? createHash("sha256").update(readFileSync(p)).digest("hex") : null);
const pkgVersion = (dir) => { try { return JSON.parse(readFileSync(path.join(dir, "package.json"), "utf8")).version; } catch { return null; } };

/** Exact versions / files / hashes of every engine (nothing is loaded). */
export function engineVersions() {
  const rel = (p) => path.relative(ROOT, p).split(path.sep).join("/");
  let manifest = null;
  try { manifest = JSON.parse(readFileSync(path.join(ROOT, "native", "dist", "manifest.json"), "utf8")); } catch {}
  return {
    "bm-native": { package: "bm-engine", version: pkgVersion(ROOT), file: rel(PATHS.bmNative), bytes: existsSync(PATHS.bmNative) ? statSync(PATHS.bmNative).size : null, sha256: sha256(PATHS.bmNative), zig: manifest?.zig ?? null, built: manifest?.date ?? null },
    "bm-wasm": { package: "bm-engine", version: pkgVersion(ROOT), profile: "pdf", file: rel(PATHS.bmPdfWasm), bytes: existsSync(PATHS.bmPdfWasm) ? statSync(PATHS.bmPdfWasm).size : null, sha256: sha256(PATHS.bmPdfWasm) },
    "takumi-pdf": { package: "takumi-pdf", version: pkgVersion(TK_DIR), file: "takumi-pdf/pkg/takumi_pdf_wasm_bg.wasm", bytes: existsSync(PATHS.takumiWasm) ? statSync(PATHS.takumiWasm).size : null, sha256: sha256(PATHS.takumiWasm), native: "none published (npm search: no takumi-pdf native / @takumi-rs/pdf-* package)" },
  };
}
