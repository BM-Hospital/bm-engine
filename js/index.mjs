// bm-engine — dependency-free ESM wrapper around bm_engine.wasm.
// Works in browsers, Node.js, Bun, Deno and edge runtimes. The wasm module has NO imports.
//
//   import { init, Renderer } from "bm-engine";
//   await init(fetch(new URL("./bm_engine.wasm", import.meta.url)));   // or bytes / WebAssembly.Module
//   const r = new Renderer();
//   r.registerFont(fontBytes);
//   const png = r.renderSync(node, { width: 1200, height: 630 });
//
// The node format and render options follow takumi (`@takumi-rs/wasm` 2.20), so the same input renders on
// both: a source is a node object, `{ json: string }`, or a string of HTML; `css`, `tw`, `className` etc. are
// honoured when the wasm build includes them. Typings: ./index.d.ts.
//
// takumi `Renderer` API parity (async methods resolve immediately; every one has a *Sync twin here):
//
//   takumi                         bm-engine
//   ----------------------------   ---------------------------------------------------------------------------
//   new Renderer(options)          works; `cacheMaxBytes` / `fontCacheMaxBytes` accepted and ignored (fixed
//                                  budgets: 96 MiB decoded images, 8 MiB glyph masks)
//   registerFont(font)             works for bytes, `{ name, data, weight, style }` (data may be a function /
//                                  promise -> async) and URL strings (fetched); `unicodeRange`, `subsetOf`,
//                                  `generic` ignored (every face is registered eagerly)
//   unregisterFont(family)         works (`{ name }` or a string)
//   clearFonts()                   works
//   render(source, options)        works: png | jpeg | webp (always lossless, like takumi-wasm) | ico | raw;
//                                  `timeMs` samples CSS animations; `fonts` (FontLoader[]) registers the fonts
//                                  and, without `fontFamilies`, makes them the fallback stack; `images`
//                                  (array or `{ sources }`, lazy `data()` allowed); `signal` checked before
//                                  rendering. Remote image URLs are NOT fetched (as in takumi without prepare)
//   renderAsDataUrl                works (raw rejected)
//   renderSvg                      works (builds with `render_svg`: the full profile); renderSvgSync twin
//   measure                        works
//   prepare(source, options)       returns a prepared handle; `render`/`renderAsDataUrl`/`measure` accept it and
//                                  merge its options. NOTE: unlike takumi it fetches nothing (no `needs` pass):
//                                  remote images / @font-face files must be passed as `images` / fonts
//   prepareAnimation(options)      same, for renderAnimation
//   renderAnimation(options)       works: webp (default, lossless) | apng | gif; takumi's frame schedule
//   read / readAnimation           private in takumi: not provided
//   free / [Symbol.dispose]        works
//   setGlyphCacheMaxBytes(bytes)   module function accepted and ignored (fixed 8 MiB glyph budget)
//
// Build profiles (scripts/build.mjs): bm_engine.core.wasm (JSON nodes + inline styles, flex/grid/block,
// static TTF, PNG/JPEG in), bm_engine.standard.wasm (+ css, tw, html, svg images, woff2, variable fonts,
// cff, effects, modern colours, tables, floats, webp/gif in, text-wrap balance) and bm_engine.wasm = full
// (+ complex text, colour emoji, animation, extra codecs, renderSvg). `features` (filled by init) tells
// which optional features the loaded binary has; using a missing one throws a clear error.

/** @type {WebAssembly.Exports & Record<string, any>} */
let wasm = null;
const enc = new TextEncoder();
const dec = new TextDecoder();

/** Optional features in `bm_features()` bit order (src/config.zig `feature_bits`). */
const FEATURE_NAMES = ["css", "tw", "html", "svg", "woff", "variableFonts", "cff", "effects", "modernColor", "tables",
  "floats", "webpGifDecode", "textWrapBalance", "colorFonts", "complexText", "animation", "extraCodecs", "renderSvg"];
const FEATURE_LABELS = { css: "stylesheet (`css` option)", html: "HTML input", woff: "WOFF/WOFF2 font", renderSvg: "renderSvg",
  animation: "animation", extraCodecs: "ICO output" };

/**
 * Optional features of the loaded wasm binary (all false before init). Binaries older than the
 * `bm_features` export report every feature as available.
 * @type {Record<string, boolean>}
 */
export const features = Object.fromEntries(FEATURE_NAMES.map((n) => [n, false]));

function setFeatures() {
  const m = typeof wasm.bm_features === "function" ? wasm.bm_features() >>> 0 : 0xffffffff;
  FEATURE_NAMES.forEach((n, i) => { features[n] = ((m >>> i) & 1) === 1; });
}

function requireFeature(name) {
  if (!features[name]) {
    throw new Error(`bm-engine: this build has no ${FEATURE_LABELS[name] || name} support (use the standard / full build${name === "woff" ? ", or load the WOFF add-on: js/addons.mjs loadWoff()" : ""})`);
  }
}

/** sfnt converter installed by js/addons.mjs (`loadWoff`) for builds without WOFF support. */
let woffDecoder = null;

/** @internal used by js/addons.mjs */
export function setWoffDecoder(fn) {
  woffDecoder = fn;
}

function isWoff(b) {
  return b.length >= 4 && b[0] === 0x77 && b[1] === 0x4f && b[2] === 0x46 && (b[3] === 0x46 || b[3] === 0x32); // wOFF / wOF2
}

function u8() {
  return new Uint8Array(wasm.memory.buffer);
}

function toBytes(data) {
  if (data instanceof Uint8Array) return data;
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  throw new TypeError("expected Uint8Array or ArrayBuffer");
}

/** Copies bytes into wasm memory; returns [ptr, len]. Caller frees unless ownership is transferred. */
function copyIn(bytes) {
  const len = bytes.length;
  const ptr = wasm.bm_alloc(len || 1);
  if (!ptr) throw new Error("bm-engine: out of memory");
  u8().set(bytes, ptr);
  return [ptr, len];
}

function copyInString(str) {
  // Worst case 3 bytes per UTF-16 unit; encodeInto avoids an intermediate buffer.
  const cap = str.length * 3 || 1;
  const ptr = wasm.bm_alloc(cap);
  if (!ptr) throw new Error("bm-engine: out of memory");
  const { written } = enc.encodeInto(str, u8().subarray(ptr, ptr + cap));
  return [ptr, written, cap];
}

function lastError() {
  const ptr = wasm.bm_last_error_ptr();
  const len = wasm.bm_last_error_len();
  return dec.decode(u8().subarray(ptr, ptr + len));
}

function check(status) {
  if (status !== 0) throw new Error("bm-engine: " + (lastError() || "error " + status));
}

function unsupported(what) {
  return new Error(`bm-engine: ${what} is not supported in bm-engine`);
}

/** Synchronously instantiate from bytes or a compiled WebAssembly.Module (or `{ module }`). */
export function initSync(input) {
  if (wasm) return wasm;
  if (input && typeof input === "object" && "module" in input && !(input instanceof WebAssembly.Module)) input = input.module;
  const mod = input instanceof WebAssembly.Module ? input : new WebAssembly.Module(input);
  wasm = new WebAssembly.Instance(mod, {}).exports;
  setFeatures();
  return wasm;
}

function adopt(instance) {
  if (!wasm) {
    wasm = instance.exports;
    setFeatures();
  }
  return wasm;
}

/** Instantiate from a URL / Request / Response / Promise<Response> / bytes / WebAssembly.Module. */
export async function init(input) {
  if (wasm) return wasm;
  input = await input;
  if (input && typeof input === "object" && "module_or_path" in input) input = await input.module_or_path;
  if (typeof input === "string" || (typeof URL !== "undefined" && input instanceof URL) ||
      (typeof Request !== "undefined" && input instanceof Request)) {
    input = await fetch(input);
  }
  if (typeof Response !== "undefined" && input instanceof Response) {
    if (WebAssembly.instantiateStreaming && (input.headers.get("content-type") || "").startsWith("application/wasm")) {
      const { instance } = await WebAssembly.instantiateStreaming(input, {});
      return adopt(instance);
    }
    input = await input.arrayBuffer();
  }
  if (input instanceof WebAssembly.Module) return adopt(await WebAssembly.instantiate(input, {}));
  const { instance } = await WebAssembly.instantiate(input, {});
  return adopt(instance);
}

export default init;

/** takumi module function. bm-engine's glyph-mask budget is fixed (8 MiB): accepted and ignored. */
export function setGlyphCacheMaxBytes(bytes) {
  void bytes;
}

function isBinary(v) {
  return v instanceof Uint8Array || v instanceof ArrayBuffer || ArrayBuffer.isView(v);
}

const PREPARED = Symbol("bm-engine.prepared");

/** Handle returned by `prepare` / `prepareAnimation` (opaque, like takumi's `Prepared`). */
export class Prepared {
  constructor(kind, source, options) {
    this[PREPARED] = { kind, source, options };
  }
}

function unwrap(source, options, kind) {
  const p = source && source[PREPARED];
  if (!p) return [source, options];
  if (p.kind !== kind) throw new TypeError(`bm-engine: this prepared handle is for ${p.kind === "anim" ? "renderAnimation" : "render"}`);
  return [p.source, { ...p.options, ...options }];
}

function throwIfAborted(signal) {
  if (signal && signal.aborted) throw signal.reason ?? new Error("bm-engine: aborted");
}

function imageList(images) {
  return Array.isArray(images) ? images : images && images.sources ? images.sources : [];
}

/** Resolves lazy `images[].data()` entries (async paths only). */
async function resolveImages(images) {
  const list = imageList(images);
  if (!list.some((i) => typeof i.data === "function" || (i.data && typeof i.data.then === "function"))) return images;
  return Promise.all(list.map(async (i) => ({ ...i, data: await (typeof i.data === "function" ? i.data() : i.data) })));
}

export class Renderer {
  #h = 0;
  #resSeq = 0;

  constructor(options = {}) {
    if (!wasm) throw new Error("bm-engine: call init()/initSync() before creating a Renderer");
    this.#h = wasm.bm_renderer_new();
    if (!this.#h) throw new Error("bm-engine: out of memory");
    void options;
  }

  #handle() {
    if (!this.#h) throw new Error("bm-engine: renderer has been freed");
    return this.#h;
  }

  /**
   * Register a font: TTF/OTF/TTC (every face of a collection), variable fonts, and WOFF/WOFF2 when the
   * build includes them. Accepts raw bytes or `{ name, data, weight, style }`. Returns takumi's
   * `RegisteredFamily[]`: `[{ name, faces: [{ weight, style, width, index }], weight, style }]`.
   * A URL string, or `data` given as a function / promise, makes it async (returns a Promise).
   */
  registerFont(font) {
    if (typeof font === "string" || (typeof URL !== "undefined" && font instanceof URL)) {
      return fetch(font).then((res) => {
        if (!res.ok) throw new Error(`bm-engine: failed to fetch font ${font}: ${res.status}`);
        return res.arrayBuffer();
      }).then((buf) => this.registerFont(new Uint8Array(buf)));
    }
    if (font && typeof font.then === "function") return font.then((f) => this.registerFont(f));
    const details = isBinary(font) ? { data: font } : font;
    if (!details || details.data == null) throw new TypeError("bm-engine: registerFont expects bytes or { data }");
    if (typeof details.data === "function" || typeof details.data.then === "function") {
      return Promise.resolve(typeof details.data === "function" ? details.data() : details.data)
        .then((data) => this.registerFont({ ...details, data }));
    }
    const h = this.#handle();
    let bytes = toBytes(details.data);
    if (!features.woff && isWoff(bytes)) {
      if (!woffDecoder) requireFeature("woff");
      bytes = woffDecoder(bytes);
    }
    const [ptr, len] = copyIn(bytes);
    const [nptr, nlen, ncap] = copyInString(details.name || "");
    const italic = details.style == null ? -1 : /italic|oblique/.test(String(details.style)) ? 1 : 0;
    // Ownership of the font bytes moves to the renderer (zero-copy parsing inside wasm).
    const status = wasm.bm_register_font(h, ptr, len, nptr, nlen, details.weight | 0, italic);
    wasm.bm_free(nptr, ncap);
    check(status);
    return JSON.parse(this.#takeString());
  }

  /** takumi-compatible alias. */
  loadFont(font) {
    return this.registerFont(font);
  }

  /** Removes every face of `family` (a name or `{ name }`). Returns true when something was removed. */
  unregisterFont(family) {
    const name = family && typeof family === "object" ? family.name : family;
    const [nptr, nlen, ncap] = copyInString(String(name));
    const r = wasm.bm_unregister_font(this.#handle(), nptr, nlen);
    wasm.bm_free(nptr, ncap);
    return r !== 0;
  }

  clearFonts() {
    wasm.bm_clear_fonts(this.#handle());
  }

  #takeString() {
    const ptr = wasm.bm_result_ptr(this.#h);
    const len = wasm.bm_result_len(this.#h);
    return dec.decode(u8().subarray(ptr, ptr + len));
  }

  #takeBytes() {
    const ptr = wasm.bm_result_ptr(this.#h);
    const len = wasm.bm_result_len(this.#h);
    const out = u8().slice(ptr, ptr + len);
    wasm.bm_release_result(this.#h);
    return out;
  }

  #putImage(src, data) {
    const [sptr, slen, scap] = copyInString(src);
    const [dptr, dlen] = copyIn(toBytes(data));
    const status = wasm.bm_put_image(this.#h, sptr, slen, dptr, dlen);
    wasm.bm_free(sptr, scap);
    wasm.bm_free(dptr, dlen || 1);
    check(status);
  }

  #putRgba(src, img) {
    const [sptr, slen, scap] = copyInString(src);
    const [dptr, dlen] = copyIn(toBytes(img.data));
    const status = wasm.bm_put_rgba(this.#h, sptr, slen, dptr, dlen, img.width, img.height, img.premultiplied ? 1 : 0);
    wasm.bm_free(sptr, scap);
    wasm.bm_free(dptr, dlen || 1);
    check(status);
  }

  /** JSON.stringify where binary / RGBA image `src` values are moved into wasm and replaced by ids. */
  #stringify(value) {
    return JSON.stringify(value, (key, v) => {
      if (key === "src" && v && typeof v === "object") {
        const id = "bm-res:" + this.#resSeq++;
        if (isBinary(v)) this.#putImage(id, v);
        else if (v.data && v.width) this.#putRgba(id, v);
        else return v;
        return id;
      }
      return v;
    });
  }

  /** Copies the `images` option entries the source text references into wasm. */
  #putImages(images, text, own) {
    for (const img of imageList(images)) {
      if (typeof img.data === "function") throw new TypeError("bm-engine: lazy images[].data() needs the async API");
      const needle = JSON.stringify(String(img.src)).slice(1, -1);
      if (!own || text.includes(needle)) this.#putImage(img.src, img.data);
    }
  }

  /**
   * Serialises the source; binary image sources are moved into wasm and replaced by ids.
   * Returns [text, kind] with kind 0 = JSON node tree, 1 = HTML markup.
   */
  #prepareSource(node, options) {
    wasm.bm_clear_images(this.#handle());
    let json;
    let kind = 0;
    let own = false; // true when we produced the JSON ourselves (so escaping is predictable)
    // takumi semantics: every JS string is HTML; a JSON tree as text is passed as { json }.
    if (typeof node === "string") { requireFeature("html"); json = node; kind = 1; }
    else if (node && typeof node === "object" && typeof node.json === "string" && node.type === undefined) json = node.json;
    else { own = true; json = this.#stringify(node); }
    // Only images the tree actually references are copied into wasm memory.
    this.#putImages(options.images, json, own);
    return [json, kind];
  }

  #call(which, node, options) {
    [node, options] = unwrap(node, options, "render");
    throwIfAborted(options.signal);
    if ((options.css != null && options.css.length !== 0) || (options.stylesheets != null && options.stylesheets.length !== 0)) requireFeature("css");
    if (options.format === "ico") requireFeature("extraCodecs");
    if (which === "svg") requireFeature("renderSvg");
    const [json, kind] = this.#prepareSource(node, options);
    // `images` were copied in above; `fonts`/`signal` are JS-side takumi options.
    const { images: _i, fonts: _f, signal: _s, ...rest } = options;
    const [jptr, jlen, jcap] = copyInString(json);
    const [optr, olen, ocap] = copyInString(JSON.stringify(rest));
    const fn = which === "render" ? wasm.bm_render_src : which === "svg" ? wasm.bm_render_svg : wasm.bm_measure_src;
    // (older binaries without the *_src exports accept JSON only)
    const status = fn ? fn(this.#h, kind, jptr, jlen, optr, olen)
      : kind === 0 ? (which === "render" ? wasm.bm_render : wasm.bm_measure)(this.#h, jptr, jlen, optr, olen)
      : -1;
    wasm.bm_free(jptr, jcap);
    wasm.bm_free(optr, ocap);
    if (status === -1) throw new Error("bm-engine: this wasm build does not accept HTML sources");
    check(status);
  }

  /** Async option extras (takumi `RenderExtras`): `fonts` loaders and lazy `images`. */
  async #extras(options) {
    let o = options;
    if (o.fonts) {
      const loaders = await o.fonts;
      const names = [];
      for (const f of loaders) {
        const fams = await this.registerFont(f);
        for (const fam of fams || []) if (!names.includes(fam.name)) names.push(fam.name);
      }
      const { fonts: _f, ...rest } = o;
      o = o.fontFamilies || names.length === 0 ? rest : { ...rest, fontFamilies: names };
    }
    if (o.images) o = { ...o, images: await resolveImages(o.images) };
    return o;
  }

  /**
   * Render synchronously. Returns a fresh Uint8Array (PNG by default; `format: "raw"` = straight RGBA8).
   *
   * `source`: a takumi node object, `{ json: string }` (a node tree as JSON text), a STRING = HTML
   * markup (`<style>` elements are honoured), or a handle from `prepare()`.
   * `options` (takumi RenderOptions): `width`, `height`, `format` ("png"|"jpeg"|"webp"|"ico"|"raw"),
   * `quality` (jpeg), `lossless` (ignored: webp is always lossless), `devicePixelRatio`, `images`
   * ([{src, data}] or {sources}), `css` (stylesheet strings and/or takumi rule objects), `stylesheets`
   * (deprecated), `keyframes` (deprecated keyframes map/list), `timeMs` (CSS animation timeline, default 0),
   * `fontFamilies`, `lang`, `drawDebugBorder` / `dithering` (accepted, ignored).
   */
  renderSync(node, options = {}) {
    this.#call("render", node, options);
    return this.#takeBytes();
  }

  /** takumi-compatible async signature (rendering itself is synchronous). */
  async render(node, options = {}) {
    [node, options] = unwrap(node, options, "render");
    return this.renderSync(node, await this.#extras(options));
  }

  renderAsDataUrlSync(node, options = {}) {
    [node, options] = unwrap(node, options, "render");
    const mime = { png: "image/png", jpeg: "image/jpeg", webp: "image/webp", ico: "image/x-icon" }[options.format || "png"];
    if (!mime) throw new Error("bm-engine: renderAsDataUrl needs an encoded format");
    const bytes = this.renderSync(node, options);
    let bin = "";
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return `data:${mime};base64,${btoa(bin)}`;
  }

  async renderAsDataUrl(node, options = {}) {
    [node, options] = unwrap(node, options, "render");
    return this.renderAsDataUrlSync(node, await this.#extras(options));
  }

  /**
   * takumi `renderSvg`: the source as an SVG document string (vector boxes, gradients, borders,
   * shadows as filters, images embedded as data URLs, text as glyph outlines). Needs a build with
   * `render_svg` (the full profile); `format` / `quality` are ignored.
   */
  renderSvgSync(node, options = {}) {
    this.#call("svg", node, options);
    const out = this.#takeString();
    wasm.bm_release_result(this.#h);
    return out;
  }

  async renderSvg(node, options = {}) {
    [node, options] = unwrap(node, options, "render");
    return this.renderSvgSync(node, await this.#extras(options));
  }

  /** Lay out only. Returns `{ width, height, transform, children, runs }` like takumi's `measure`. */
  measureSync(node, options = {}) {
    this.#call("measure", node, options);
    const out = JSON.parse(this.#takeString());
    wasm.bm_release_result(this.#h);
    return out;
  }

  async measure(node, options = {}) {
    [node, options] = unwrap(node, options, "render");
    return this.measureSync(node, await this.#extras(options));
  }

  /**
   * takumi `prepare`: resolves `fonts` / lazy `images` and returns a handle for `render`,
   * `renderAsDataUrl` and `measure` (whose options are merged over the prepared ones). bm-engine does
   * not fetch remote resources here (no `needs` pass): pass image bytes via `images`.
   */
  async prepare(source, options = {}) {
    return new Prepared("render", source, await this.#extras(options));
  }

  /** takumi `prepareAnimation`: like `prepare`, for `renderAnimation`. */
  async prepareAnimation(options = {}) {
    const { scenes, ...rest } = options;
    return new Prepared("anim", scenes, await this.#extras(rest));
  }

  /**
   * takumi `renderAnimation`: `{ scenes: [{ node, durationMs }], width, height, fps, format?: "webp" |
   * "apng" | "gif" (default webp, always lossless), css?, stylesheets?, keyframes?, images?,
   * devicePixelRatio?, fontFamilies?, lang? }` -> encoded animation. Frame schedule as takumi-raster:
   * ceil(total * fps / 1000) frames, frame i at floor(i * 1000 / fps) ms (time restarts per scene).
   * Max fps: 50 for gif, 90 for webp / apng.
   */
  renderAnimationSync(options) {
    let scenes = options.scenes;
    if (options[PREPARED]) {
      const p = options[PREPARED];
      if (p.kind !== "anim") throw new TypeError("bm-engine: this prepared handle is for render");
      scenes = p.source;
      options = { ...p.options };
    }
    throwIfAborted(options.signal);
    if (!wasm.bm_render_animation) throw unsupported("renderAnimation (this wasm build)");
    requireFeature("animation");
    const h = this.#handle();
    wasm.bm_clear_images(h);
    const { images, fonts: _f, signal: _s, scenes: _sc, ...rest } = options;
    const text = this.#stringify({ ...rest, scenes: scenes || [] });
    this.#putImages(images, text, true);
    const [ptr, len, cap] = copyInString(text);
    const status = wasm.bm_render_animation(h, ptr, len);
    wasm.bm_free(ptr, cap);
    check(status);
    return this.#takeBytes();
  }

  async renderAnimation(options, extra = {}) {
    if (options && options[PREPARED]) {
      throwIfAborted(extra.signal);
      return this.renderAnimationSync(options);
    }
    return this.renderAnimationSync(await this.#extras(options));
  }

  /** Current wasm linear memory size in bytes (shared by all renderers of this module instance). */
  memoryBytes() {
    return wasm.memory.buffer.byteLength;
  }

  static memoryBytes() {
    return wasm ? wasm.memory.buffer.byteLength : 0;
  }

  free() {
    if (this.#h) wasm.bm_renderer_free(this.#h);
    this.#h = 0;
  }

  [Symbol.dispose]() {
    this.free();
  }
}
