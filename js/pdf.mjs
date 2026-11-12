// bm-engine/pdf (browsers, bundlers, Deno, edge runtimes): the pdf build profile (bm_engine.pdf.wasm = full + PDF output)
// with its own module instance, plus the takumi-pdf style API: `PdfRenderer`, `render`, `measure`, `prepare` and the
// page counter primitives. `await init()` without an argument loads bm_engine.pdf.wasm from next to this file through
// `new URL("./bm_engine.pdf.wasm", import.meta.url)`; where that cannot work (Cloudflare Workers) pass the module:
//
//   import wasm from "bm-engine/pdf.wasm";
//   import { init, PdfRenderer } from "bm-engine/pdf";
//   await init(wasm);
//   const pdf = await new PdfRenderer().render(node, { size: "a4", margin: 24 });   // Uint8Array
//
// On Node.js this subpath resolves to ./node-pdf.mjs, which reads the file and initialises on import.
// API: ./pdf.d.mts. The image `Renderer` of the other entries is exported too, with `renderPdf` / `measurePdf` methods.
import { createBinding } from "./engine.mjs";

const binding = createBinding(() => new URL("./bm_engine.pdf.wasm", import.meta.url));

export const { init, initSync, Renderer, features, setGlyphCacheMaxBytes, wasmUrl } = binding;
export { Prepared, setWoffDecoder } from "./engine.mjs";
/** Build profile of this entry. */
export const profile = "pdf";
export default init;

const DISPOSE = typeof Symbol.dispose === "symbol" ? Symbol.dispose : Symbol.for("nodejs.dispose");

/**
 * A PDF renderer holding registered fonts (takumi-pdf `PdfRenderer`). Reuse one instance across renders.
 * Unlike takumi-pdf, `prepare` fetches nothing and `images` / `fonts` are passed as bytes (see Renderer.prepare).
 */
export class PdfRenderer {
  #r;

  constructor(options) {
    this.#r = new Renderer(options);
  }

  registerFont(font) { return this.#r.registerFont(font); }
  loadFont(font) { return this.#r.registerFont(font); }
  unregisterFont(family) { return this.#r.unregisterFont(family); }
  clearFonts() { this.#r.clearFonts(); }
  /** Resolves `fonts` / lazy `images` once; `render` and `measure` accept the handle (their options merge over it). */
  prepare(node, options) { return this.#r.prepare(node, options); }
  /** A node tree, an HTML string or a prepared document -> PDF bytes (Uint8Array). */
  render(node, options) { return this.#r.renderPdf(node, options); }
  renderSync(node, options) { return this.#r.renderPdfSync(node, options); }
  /** Laid-out `{ width, height }` in CSS px (page options: at the full page width, unbounded height, like a band). */
  measure(node, options) { return this.#r.measurePdf(node, options); }
  measureSync(node, options) { return this.#r.measurePdfSync(node, options); }
  free() { this.#r.free(); }
  [DISPOSE]() { this.free(); }
}

let shared;
const sharedRenderer = () => (shared ??= new PdfRenderer());

/** Prepares with a lazily created shared {@link PdfRenderer}. */
export function prepare(node, options) { return sharedRenderer().prepare(node, options); }
/** Renders with a lazily created shared {@link PdfRenderer}. */
export function render(node, options) { return sharedRenderer().render(node, options); }
/** Measures with a lazily created shared {@link PdfRenderer}. */
export function measure(node, options) { return sharedRenderer().measure(node, options); }

// ---- page counter primitives (takumi-pdf primitives.ts, as bm-engine nodes instead of JSX elements)

const counter = (hook, { format, className, ...rest } = {}) => ({
  type: "container",
  tagName: "span",
  ...rest,
  className: [hook, format, className].filter(Boolean).join(" "),
});

/** The number of the page this element lands on. Meaningful inside a `header` / `footer` band. */
export const PageNumber = (props) => counter("pageNumber", props);
/** The document's total page count. Same placement rules as {@link PageNumber}. */
export const TotalPages = (props) => counter("totalPages", props);
/**
 * The number of the page a link's target element lands on, for cross references like "see page 12".
 * Without `href` it reads the nearest enclosing `<a>`; with one it renders its own link.
 */
export const TargetPageNumber = ({ href, ...props } = {}) => {
  const span = counter("targetPageNumber", props);
  return href === undefined ? span : { type: "container", tagName: "a", attributes: { href }, children: [span] };
};
