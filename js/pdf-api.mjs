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
    /** Removes every face of a family: takumi-pdf takes `{ name }` (a registered family); a plain name works too. */
    unregisterFont(family) { return this.#r.unregisterFont(family !== null && typeof family === "object" ? family.name : family); }
    clearFonts() { this.#r.clearFonts(); }
    /**
     * Resolves `fonts` / lazy `images` once and, as takumi-pdf's `prepare` does, fetches the remote images the
     * document draws that `images` does not provide (`images: { sources, fetch, ... }`); `render` and `measure`
     * accept the handle (their options merge over it).
     */
    async prepare(node, options) {
      if (options != null && typeof options === "object") {
        options.signal?.throwIfAborted?.();
        options = await fetchImages(resolveBands(options), node);
        options.signal?.throwIfAborted?.();
      }
      return this.#r.prepare(resolveDocument(node), options);
    }
    /** A node tree, an HTML string or a prepared document -> PDF bytes (Uint8Array). */
    render(node, options) { return this.#r.renderPdf(resolveDocument(node), resolveBands(options)); }
    renderSync(node, options) { return this.#r.renderPdfSync(resolveDocument(node), resolveBands(options)); }
    /**
     * Laid-out `{ width, height }` in CSS px (page options: at the full page width, unbounded height, like a band).
     * As in takumi-pdf, `signal` is not read here.
     */
    measure(node, options) { return this.#r.measurePdf(resolveDocument(node), measureOptions(options)); }
    measureSync(node, options) { return this.#r.measurePdfSync(resolveDocument(node), measureOptions(options)); }
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

// ---- inputs as takumi-pdf's JS wrapper reads them (takumi-bindings-js document.ts `resolveDocument`, export.ts)

const PREPARED = Symbol.for("bm-engine.prepared");
const isJsxElement = (v) => typeof v === "object" && v !== null && typeof v.$$typeof === "symbol" && "props" in v;
/** takumi-bindings-js `isNode`: an object with a `type` that is not a JSX element (bm-engine also reads `{ json }`). */
const isNode = (v) => typeof v === "object" && v !== null && "type" in v && !("$$typeof" in v);

/**
 * A document or band as takumi-pdf's wrapper reads it: HTML strings and node trees as they are; anything else goes
 * through `fromJsx`, here as HTML markup: a JSX (React element) tree, and the values fromJsx turns into text
 * (`true` -> "true", `5` -> "5", `{}` -> "[object Object]"; `null` / `undefined` / `false` -> nothing, a list -> its
 * items). A list at the root is passed on as is (bm rejects it, takumi-pdf throws too).
 */
function resolveDocument(v) {
  if (typeof v === "string" || isNode(v) || Array.isArray(v)) return v;
  if (typeof v === "object" && v !== null && (v[PREPARED] || typeof v.json === "string")) return v;
  return jsxToHtml(v);
}

/** A band value: `false` / `null` / `undefined` stay (no band), the rest as {@link resolveDocument} reads a document. */
const resolveBand = (v) => (v == null || v === false ? v : typeof v === "string" || isNode(v) ? v : jsxToHtml(v));

const CSS_NULL = "bm-engine: data did not match any variant of untagged enum CssSource";

/** render / prepare options: bands resolved, and the input checks takumi-pdf's wrapper makes before the native side. */
function resolveBands(options) {
  if (options == null || typeof options !== "object" || Array.isArray(options)) return options;
  const o = { ...options };
  // takumi-pdf: `css: null` becomes the sheet list `[null]`, which no `CssSource` variant reads
  if (o.css === null) throw new TypeError(CSS_NULL);
  if (o.fonts != null && typeof o.fonts !== "object" && typeof o.fonts !== "function") throw new TypeError("bm-engine: fonts takes an array");
  if ("header" in o) o.header = resolveBand(o.header);
  if ("footer" in o) o.footer = resolveBand(o.footer);
  if (o.pages != null && typeof o.pages === "object" && !Array.isArray(o.pages)) {
    const pages = {};
    for (const [rule, page] of Object.entries(o.pages)) {
      if (page == null || typeof page !== "object" || Array.isArray(page)) { pages[rule] = page; continue; }
      const p = { ...page };
      if ("header" in p) p.header = resolveBand(p.header);
      if ("footer" in p) p.footer = resolveBand(p.footer);
      pages[rule] = p;
    }
    o.pages = pages;
  }
  return o;
}

/** measure options: takumi-pdf's `measure` does not read `signal`. */
function measureOptions(options) {
  if (options == null || typeof options !== "object" || Array.isArray(options)) return options;
  const { signal: _s, ...o } = options;
  if (o.css === null) throw new TypeError(CSS_NULL);
  return o;
}

// React's unitless style properties (a number stays a number; any other takes px)
const UNITLESS = new Set(("animationIterationCount aspectRatio borderImageOutset borderImageSlice borderImageWidth boxFlex boxFlexGroup " +
  "boxOrdinalGroup columnCount columns flex flexGrow flexPositive flexShrink flexNegative flexOrder gridArea gridRow gridRowEnd " +
  "gridRowSpan gridRowStart gridColumn gridColumnEnd gridColumnSpan gridColumnStart fontWeight lineClamp lineHeight opacity order " +
  "orphans scale tabSize widows zIndex zoom fillOpacity floodOpacity stopOpacity strokeDasharray strokeDashoffset strokeMiterlimit " +
  "strokeOpacity strokeWidth").split(" "));
// SVG presentation attributes written camelCase in JSX (takumi helpers jsx.ts)
const SVG_KEBAB = new Set(("stopColor stopOpacity strokeWidth strokeDasharray strokeDashoffset strokeLinecap strokeLinejoin fillRule " +
  "clipRule colorInterpolationFilters floodColor floodOpacity clipPath fillOpacity fontFamily fontSize fontStyle fontWeight " +
  "strokeMiterlimit strokeOpacity textAnchor textDecoration transformOrigin dominantBaseline alignmentBaseline baselineShift " +
  "letterSpacing wordSpacing markerEnd markerMid markerStart paintOrder vectorEffect").split(" "));
const VOID = new Set(["area", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "wbr"]);
const kebab = (k) => (k.startsWith("--") ? k : k.replace(/^ms(?=[A-Z])/, "-ms").replace(/[A-Z]/g, (c) => "-" + c.toLowerCase()));
const escText = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const escAttr = (s) => escText(s).replace(/"/g, "&quot;");
const cssText = (style) =>
  Object.entries(style)
    .filter(([, v]) => v != null && v !== "" && typeof v !== "boolean")
    .map(([k, v]) => `${kebab(k)}:${typeof v === "number" && v !== 0 && !UNITLESS.has(k) && !k.startsWith("--") ? v + "px" : String(v)}`)
    .join(";");

/**
 * takumi helpers `fromJsx`, as HTML markup bm-engine's HTML reader lays out: function / class / forwardRef / memo
 * components are called, fragments and context providers give their children, `<style>` stays a style sheet,
 * `className` is `class`, a `style` object is CSS text (numbers in px, React's unitless properties excepted).
 * Components run once without a React dispatcher: hooks other than plain reads are not supported.
 */
export function jsxToHtml(v, svg = false) {
  if (v == null || v === false) return "";
  if (typeof v === "string" || typeof v === "number" || typeof v === "bigint" || v === true) return escText(String(v));
  if (typeof v === "object" && typeof v.then === "function") throw new TypeError("bm-engine: an async component needs to be awaited before render");
  if (isJsxElement(v)) return jsxElement(v, svg);
  if (typeof v === "object" && typeof v[Symbol.iterator] === "function") return Array.from(v, (x) => jsxToHtml(x, svg)).join("");
  return escText(String(v));
}

function jsxElement(el, svg) {
  const { type } = el;
  const props = el.props || {};
  if (typeof type === "function") {
    if (type.prototype && type.prototype.isReactComponent) return jsxToHtml(new type(props).render(), svg);
    return jsxToHtml(type(props), svg);
  }
  if (typeof type === "symbol") return jsxToHtml(props.children, svg);
  if (typeof type === "object" && type !== null) {
    const kind = String(type.$$typeof && type.$$typeof.description);
    if (typeof type.render === "function") return jsxToHtml(type.render(props, null), svg); // forwardRef
    if (type.type !== undefined) return jsxElement({ ...el, type: type.type }, svg); // memo
    if (kind === "react.consumer" || (kind === "react.context" && typeof props.children === "function")) {
      const ctx = type._context || type;
      return jsxToHtml(typeof props.children === "function" ? props.children(ctx._currentValue) : props.children, svg);
    }
    return jsxToHtml(props.children, svg); // providers
  }
  if (typeof type !== "string") return "";
  const tag = type;
  const inSvg = svg || tag === "svg";
  let attrs = "";
  for (const [k, val] of Object.entries(props)) {
    if (k === "children" || k === "key" || k === "ref" || k === "dangerouslySetInnerHTML" || val == null || val === false || typeof val === "function") continue;
    const name = k === "className" ? "class" : k === "htmlFor" ? "for" : inSvg && SVG_KEBAB.has(k) ? kebab(k) : k;
    const text = k === "style" && typeof val === "object" ? cssText(val) : val === true ? "" : String(val);
    attrs += ` ${name}="${escAttr(text)}"`;
  }
  if (tag === "svg" && props.xmlns == null) attrs += ` xmlns="http://www.w3.org/2000/svg"`;
  if (tag === "style") return `<style${attrs}>${styleText(props.children)}</style>`;
  if (VOID.has(tag) && !inSvg) return `<${tag}${attrs}>`;
  const inner = props.dangerouslySetInnerHTML && props.dangerouslySetInnerHTML.__html != null ? String(props.dangerouslySetInnerHTML.__html) : jsxToHtml(props.children, inSvg);
  return `<${tag}${attrs}>${inner}</${tag}>`;
}

/** The text of a `<style>` element's children (takumi helpers: strings and numbers, joined). */
function styleText(c) {
  if (c == null || typeof c === "boolean") return "";
  if (typeof c === "string" || typeof c === "number") return String(c).replace(/<\/style/gi, "<\\/style");
  if (typeof c === "object" && typeof c[Symbol.iterator] === "function") return Array.from(c, styleText).join("");
  return isJsxElement(c) ? styleText(c.props && c.props.children) : "";
}

// ---- prepare: fetching the images a document draws (takumi helpers `prepareImages`)

const isHttp = (u) => /^https?:\/\//i.test(u);
const CSS_URL = /url\(\s*(['"]?)(.*?)\1\s*\)/g;

function cssUrls(s, out) {
  if (typeof s === "string") for (const m of s.matchAll(CSS_URL)) { const u = m[2] && m[2].trim(); if (u) out.add(u); }
  else if (Array.isArray(s)) for (const x of s) cssUrls(x, out);
}

/** The image URLs a source names: `<img src>`, CSS `url()` (HTML), and image `src` / style images / `tw` (node trees). */
function imageUrls(v, out) {
  if (typeof v === "string") {
    for (const m of v.matchAll(/<(?:img|image)\b[^>]*?\s(?:src|href|xlink:href)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi)) {
      const u = (m[1] ?? m[2] ?? m[3] ?? "").replace(/&amp;/g, "&").trim();
      if (u) out.add(u);
    }
    cssUrls(v, out);
  } else if (isNode(v)) {
    for (const s of [v.style, v.preset]) if (s && typeof s === "object") { cssUrls(s.backgroundImage, out); cssUrls(s.maskImage, out); cssUrls(s.listStyleImage, out); }
    cssUrls(v.tw, out);
    if (v.type === "image" && typeof v.src === "string") out.add(v.src);
    for (const c of Array.isArray(v.children) ? v.children : []) imageUrls(c, out);
  }
}

/**
 * takumi-pdf `prepare`: the images the document and its bands draw that `images` does not provide are fetched
 * (`images.fetch`, else the global `fetch`; without a custom fetch only http(s) URLs) and added to `images`.
 * A failed fetch rejects unless `images.throwOnError` is false.
 */
async function fetchImages(options, node) {
  const images = options.images;
  const { sources = [], fetch: fetchFn, throwOnError = true, signal = options.signal, timeout } = Array.isArray(images) ? { sources: images } : images && typeof images === "object" ? images : {};
  const urls = new Set();
  imageUrls(resolveDocument(node), urls);
  const bands = [options.header, options.footer];
  if (options.pages && typeof options.pages === "object") for (const p of Object.values(options.pages)) if (p && typeof p === "object") bands.push(p.header, p.footer);
  for (const b of bands) if (b != null && b !== false) imageUrls(b, urls);
  if (typeof options.css === "string" || Array.isArray(options.css)) cssUrls(options.css, urls);
  const have = new Set((Array.isArray(sources) ? sources : []).map((s) => s && s.src));
  const doFetch = fetchFn || globalThis.fetch;
  const todo = [...urls].filter((u) => !have.has(u) && !u.startsWith("data:") && (fetchFn !== undefined || isHttp(u)));
  if (todo.length === 0 || typeof doFetch !== "function") return images === undefined ? options : { ...options, images: Array.isArray(images) ? images : sources };
  const one = async (src) => {
    const init = {};
    const s = timeout ? (signal ? AbortSignal.any([signal, AbortSignal.timeout(timeout)]) : AbortSignal.timeout(timeout)) : signal;
    if (s) init.signal = s;
    const res = await doFetch(src, init);
    if (!res || !res.ok) throw new Error(`bm-engine: fetching ${src} failed${res ? ` (${res.status})` : ""}`);
    return { src, data: new Uint8Array(await res.arrayBuffer()) };
  };
  const tasks = todo.map(one);
  const fetched = throwOnError ? await Promise.all(tasks) : (await Promise.allSettled(tasks)).filter((r) => r.status === "fulfilled").map((r) => r.value);
  return { ...options, images: [...(Array.isArray(sources) ? sources : []), ...fetched] };
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
