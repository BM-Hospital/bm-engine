// bm-engine internal: the takumi-pdf style API (`PdfRenderer`, `render`, `measure`, `prepare`) on top of one
// binding's `Renderer`, and the page counter primitives. Shared by js/pdf.mjs (the wasm pdf profile) and
// js/node-pdf.mjs (the native addon when it is available), so both expose exactly the same classes.
const DISPOSE = typeof Symbol.dispose === "symbol" ? Symbol.dispose : Symbol.for("nodejs.dispose");

/** @param {new (options?: object) => any} Renderer  the `Renderer` of a binding with the `pdf` feature */
export function pdfApi(Renderer) {
  /**
   * A PDF renderer holding registered fonts (takumi-pdf `PdfRenderer`). Reuse one instance across renders.
   * Unlike takumi-pdf, `prepare` fetches nothing and `images` / `fonts` are passed as bytes (see Renderer.prepare).
   */
  class PdfRenderer {
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

  return {
    PdfRenderer,
    /** Prepares with a lazily created shared {@link PdfRenderer}. */
    prepare: (node, options) => sharedRenderer().prepare(node, options),
    /** Renders with a lazily created shared {@link PdfRenderer}. */
    render: (node, options) => sharedRenderer().render(node, options),
    /** Measures with a lazily created shared {@link PdfRenderer}. */
    measure: (node, options) => sharedRenderer().measure(node, options),
  };
}

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
