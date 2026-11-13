// bm-engine/pdf: the pdf build profile (bm_engine.pdf.wasm = full + PDF output) with its own module instance, and the
// takumi-pdf style API on top of it. init() may be called without an argument (and on Node.js it already ran on import).
// On Node.js / Bun / Deno the engine is the native addon when it is installed (`backend` is "native": the same addon as
// `bm-engine`, the same PDF bytes, async methods on the thread pool), else this wasm build; BM_ENGINE_BACKEND=wasm | native
// forces one. See docs/NATIVE.md.
import type {
  ByteBuf, ContainerNode, FontLoader, InitArgument, OutputBytes, Prepared, RegisteredFamily, RendererOptions, Source, Style,
  SyncFontDetails, WasmExports,
} from "./index.mjs";
import type { MeasuredSize, PdfMeasureOptions, PdfRenderOptions } from "./pdf-types.mjs";

export * from "./index.mjs";
export * from "./pdf-types.mjs";

export declare function init(input?: InitArgument): Promise<WasmExports>;
export default init;
/** The URL init() loads by default (throws where `import.meta.url` is unusable). */
export declare function wasmUrl(): URL;
/** Build profile of this entry. */
export declare const profile: "pdf";

/**
 * A document input: a node tree, `{ json }` (the tree as JSON text), an HTML string, a prepared handle, or (as
 * takumi-pdf) a JSX / React element tree, laid out as the HTML it describes (components are called once, without a
 * React dispatcher; `<style>` elements style the document).
 */
export type PdfSource = Source | Prepared | JsxElement;
/** A React element (`$$typeof`, `type`, `props`), as JSX creates it. */
export type JsxElement = { $$typeof: symbol; type: unknown; props: Record<string, unknown> };

/** takumi-pdf's `PdfRenderer` (a wrapper of one `Renderer`; registered fonts live in it). */
export declare class PdfRenderer {
  constructor(options?: RendererOptions);
  registerFont(font: ByteBuf | SyncFontDetails): RegisteredFamily[];
  registerFont(font: FontLoader | Promise<FontLoader>): RegisteredFamily[] | Promise<RegisteredFamily[]>;
  loadFont(font: ByteBuf | SyncFontDetails): RegisteredFamily[];
  loadFont(font: FontLoader | Promise<FontLoader>): RegisteredFamily[] | Promise<RegisteredFamily[]>;
  unregisterFont(family: string | { name: string }): boolean;
  clearFonts(): void;
  /**
   * Resolves `fonts` / lazy `images` once and fetches the remote images the document and its bands name that
   * `images` does not provide (`images: { sources?, fetch?, throwOnError?, timeout? }`; without a custom `fetch`,
   * http(s) URLs only). Rejects on an aborted `signal`.
   */
  prepare(source: Source | JsxElement, options?: PdfRenderOptions): Promise<Prepared>;
  /** A node tree, an HTML string or a prepared document -> PDF bytes. Paged A4 by default; `viewport` renders one page. */
  render(source: PdfSource, options?: PdfRenderOptions): Promise<OutputBytes>;
  renderSync(source: PdfSource, options?: PdfRenderOptions): OutputBytes;
  /** Laid-out size in CSS px; page options lay out at the full page width with unbounded height, like a band, with three-digit `pageNumber` / `totalPages` counters (add 20 px for the margin an `auto` margin reserves). */
  measure(source: PdfSource, options?: PdfMeasureOptions): Promise<MeasuredSize>;
  measureSync(source: PdfSource, options?: PdfMeasureOptions): MeasuredSize;
  free(): void;
  [Symbol.dispose](): void;
}

/** Prepares with a lazily created shared {@link PdfRenderer}. */
export declare function prepare(source: Source | JsxElement, options?: PdfRenderOptions): Promise<Prepared>;
/** Renders with a lazily created shared {@link PdfRenderer}. */
export declare function render(source: PdfSource, options?: PdfRenderOptions): Promise<OutputBytes>;
/** Measures with a lazily created shared {@link PdfRenderer}. */
export declare function measure(source: PdfSource, options?: PdfMeasureOptions): Promise<MeasuredSize>;

/** `@counter-style` names the page counters can format in. */
export type CounterStyle =
  | "decimal" | "decimal-leading-zero" | "lower-roman" | "upper-roman" | "lower-alpha" | "lower-latin" | "upper-alpha"
  | "upper-latin" | "lower-greek" | "hiragana" | "katakana" | "trad-chinese-informal" | "cjk-ideographic" | "cjk-decimal"
  | "arabic-indic" | "bengali" | "cambodian" | "khmer" | "devanagari" | "gujarati" | "gurmukhi" | "kannada" | "lao"
  | "malayalam" | "mongolian" | "myanmar" | "oriya" | "persian" | "urdu" | "tamil" | "telugu" | "thai" | "tibetan";

/** Props shared by the page counter primitives. */
export type CounterProps = {
  /** Counter style the number formats in. Defaults to decimal. */
  format?: CounterStyle;
  className?: string;
  style?: Style;
  tw?: string;
};

/** The number of the page this element lands on (a `span` node classed `pageNumber`): in a `header` / `footer` band or a `position: fixed` box each page's number, in the content flow the page it lands on. */
export declare function PageNumber(props?: CounterProps): ContainerNode;
/** The document's total page count (classed `totalPages`). */
export declare function TotalPages(props?: CounterProps): ContainerNode;
/** The page number of a link's target (classed `targetPageNumber`); with `href` it renders its own link. */
export declare function TargetPageNumber(props?: CounterProps & { href?: string }): ContainerNode;
