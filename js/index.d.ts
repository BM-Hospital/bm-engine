// Public API of bm-engine (js/index.mjs, js/node.mjs). The node format and options follow
// `@takumi-rs/wasm` 2.20; see the parity table at the top of js/index.mjs.

export type ByteBuf = Uint8Array | ArrayBuffer | ArrayBufferView;

/** CSS declarations: camelCase keys, string or number values (numbers are px for lengths). */
export type Style = Record<string, string | number | null | undefined>;

export type NodeMetadata = {
  style?: Style;
  preset?: Style;
  tw?: string;
  tagName?: string;
  className?: string;
  id?: string;
  attributes?: Record<string, string>;
  dir?: "ltr" | "rtl" | "auto";
  lang?: string;
};
export type ContainerNode = NodeMetadata & { type: "container"; children?: (Node | null)[] };
export type TextNode = NodeMetadata & { type: "text"; text: string };
export type RgbaImage = { width: number; height: number; data: ByteBuf; premultiplied?: boolean };
export type ImageNode = NodeMetadata & {
  type: "image";
  /** data: URI, inline `<svg>` markup, a key of `images`, bytes, or raw RGBA. */
  src: string | ByteBuf | RgbaImage;
  width?: number;
  height?: number;
};
export type Node = ContainerNode | TextNode | ImageNode;
/** A node tree, `{ json }` (the tree as JSON text) or an HTML string. */
export type Source = Node | string | { json: string };

export type ImageSource = { src: string; data: ByteBuf | (() => ByteBuf | Promise<ByteBuf>); cache?: "auto" | "none" };
export type ImagesInput = ImageSource[] | { sources?: ImageSource[]; cache?: "auto" | "none" };
/** takumi rule object (`{ selector, style }`, `{ keyframes, steps }`, ...) or stylesheet text. */
export type CssInput = string | Record<string, unknown>;
export type KeyframesMap = Record<string, Record<string, Style>>;
export type KeyframesRuleList = { name: string; keyframes: { offsets: number[]; declarations: Style }[] }[];
export type Keyframes = KeyframesMap | KeyframesRuleList;

export type FontDetails = {
  name?: string;
  data: ByteBuf | (() => ByteBuf | Promise<ByteBuf>) | Promise<ByteBuf>;
  weight?: number;
  style?: string;
  /** accepted, ignored */
  unicodeRange?: [number, number][];
  /** accepted, ignored */
  generic?: string;
};
export type FontLoader = string | URL | ByteBuf | FontDetails;
export type RegisteredFace = { weight: number; style: string; width: number; index: number };
export type RegisteredFamily = { name: string; faces: RegisteredFace[]; weight?: number; style?: string };

export type OutputFormat = "png" | "jpeg" | "webp" | "ico" | "raw";
export type AnimationOutputFormat = "webp" | "apng" | "gif";

export type CommonOptions = {
  devicePixelRatio?: number;
  images?: ImagesInput;
  css?: CssInput[] | string;
  /** deprecated alias of `css` (strings) */
  stylesheets?: string[];
  /** deprecated top-level keyframes */
  keyframes?: Keyframes;
  /** root font-family fallback stack */
  fontFamilies?: string[];
  /** root language (`:lang()`, OpenType language system) */
  lang?: string;
  /** FontLoader list registered before rendering (async API only) */
  fonts?: FontLoader[] | Promise<FontLoader[]>;
  signal?: AbortSignal;
  /** accepted, ignored */
  drawDebugBorder?: boolean;
};

export type RenderOptions = CommonOptions & {
  width?: number;
  height?: number;
  format?: OutputFormat;
  /** jpeg quality (default 75); ignored for webp (always lossless) */
  quality?: number;
  /** accepted, ignored (webp is always lossless, like takumi-wasm) */
  lossless?: boolean;
  /** CSS animation timeline position in ms (integer; default 0) */
  timeMs?: number;
  /** accepted, ignored */
  dithering?: "none" | "ordered-bayer" | "floyd-steinberg";
};

export type AnimationScene = { node: Source; durationMs: number };
export type RenderAnimationOptions = CommonOptions & {
  scenes: AnimationScene[];
  width: number;
  height: number;
  /** frames per second (gif <= 50, webp / apng <= 90) */
  fps: number;
  format?: AnimationOutputFormat;
  /** accepted, ignored */
  quality?: number;
  /** accepted, ignored */
  lossless?: boolean;
};

export type MeasuredTextRun = { text?: string; x: number; y: number; width: number; height: number };
export type MeasuredNode = {
  width: number;
  height: number;
  transform: [number, number, number, number, number, number];
  children: MeasuredNode[];
  runs: MeasuredTextRun[];
};

/** Opaque handle returned by `prepare` / `prepareAnimation`. */
export declare class Prepared {
  private constructor();
}

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export declare function init(input: InitInput | Promise<InitInput> | { module_or_path: InitInput | Promise<InitInput> }): Promise<WebAssembly.Exports>;
export declare function initSync(input: BufferSource | WebAssembly.Module | { module: BufferSource | WebAssembly.Module }): WebAssembly.Exports;
export default init;
/** accepted and ignored (fixed 8 MiB glyph budget) */
export declare function setGlyphCacheMaxBytes(bytes: number): void;

export declare class Renderer {
  constructor(options?: { cacheMaxBytes?: number; fontCacheMaxBytes?: number });
  registerFont(font: ByteBuf | (FontDetails & { data: ByteBuf })): RegisteredFamily[];
  registerFont(font: FontLoader | Promise<FontLoader>): RegisteredFamily[] | Promise<RegisteredFamily[]>;
  loadFont(font: FontLoader): RegisteredFamily[] | Promise<RegisteredFamily[]>;
  unregisterFont(family: string | { name: string }): boolean;
  clearFonts(): void;

  renderSync(source: Source | Prepared, options?: RenderOptions): Uint8Array;
  render(source: Source | Prepared, options?: RenderOptions): Promise<Uint8Array>;
  renderAsDataUrlSync(source: Source | Prepared, options?: RenderOptions): string;
  renderAsDataUrl(source: Source | Prepared, options?: RenderOptions): Promise<string>;
  /** always rejects: not supported in bm-engine */
  renderSvg(source: Source | Prepared, options?: RenderOptions): Promise<string>;
  measureSync(source: Source | Prepared, options?: RenderOptions): MeasuredNode;
  measure(source: Source | Prepared, options?: RenderOptions): Promise<MeasuredNode>;

  prepare(source: Source, options?: RenderOptions): Promise<Prepared>;
  prepareAnimation(options: RenderAnimationOptions): Promise<Prepared>;
  renderAnimationSync(options: RenderAnimationOptions | Prepared): Uint8Array;
  renderAnimation(options: RenderAnimationOptions): Promise<Uint8Array>;
  renderAnimation(prepared: Prepared, options?: { signal?: AbortSignal }): Promise<Uint8Array>;

  /** current wasm linear memory size in bytes */
  memoryBytes(): number;
  static memoryBytes(): number;
  free(): void;
  [Symbol.dispose](): void;
}
