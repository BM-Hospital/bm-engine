// bm-engine internal: the JS binding around one bm_engine.wasm instance.
//
// `createBinding(defaultWasm?)` returns `{ init, initSync, Renderer, features, ... }` bound to its own
// module instance. Every public entry creates exactly one binding when it is first evaluated:
//   js/index.mjs  (bm-engine, explicit init)      js/node.mjs   (bm-engine on Node: index.mjs + auto-init)
//   js/core.mjs / standard.mjs / full.mjs          js/node-core.mjs / node-standard.mjs / node-full.mjs
//   (bm-engine/<profile>, init() finds the wasm)    (bm-engine/<profile> on Node: same binding + auto-init)
// so one process can load several profiles side by side; within one binding the first successful
// init wins (later calls return the same instance). This file is not part of the public API.

/** Optional features in `bm_features()` bit order (src/config.zig `feature_bits`). */
const FEATURE_NAMES = ["css", "tw", "html", "svg", "woff", "variableFonts", "cff", "effects", "modernColor", "tables",
  "floats", "webpGifDecode", "textWrapBalance", "colorFonts", "complexText", "animation", "extraCodecs", "renderSvg"];
const FEATURE_LABELS = { css: "stylesheet (`css` option)", html: "HTML input", woff: "WOFF/WOFF2 font", renderSvg: "renderSvg",
  animation: "animation", extraCodecs: "ICO output" };

const enc = new TextEncoder();
const dec = new TextDecoder();
const DISPOSE = typeof Symbol.dispose === "symbol" ? Symbol.dispose : Symbol.for("nodejs.dispose");

/** sfnt converter installed by js/addons.mjs (`loadWoff`) for builds without WOFF support (shared by every binding). */
let woffDecoder = null;

/** @internal used by js/addons.mjs */
export function setWoffDecoder(fn) {
  woffDecoder = fn;
}

function isWoff(b) {
  return b.length >= 4 && b[0] === 0x77 && b[1] === 0x4f && b[2] === 0x46 && (b[3] === 0x46 || b[3] === 0x32); // wOFF / wOF2
}

function toBytes(data) {
  if (data instanceof Uint8Array) return data;
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  throw new TypeError("expected Uint8Array or ArrayBuffer");
}

function isBinary(v) {
  return v instanceof Uint8Array || v instanceof ArrayBuffer || ArrayBuffer.isView(v);
}

function unsupported(what) {
  return new Error(`bm-engine: ${what} is not supported in bm-engine`);
}

const PREPARED = Symbol.for("bm-engine.prepared");

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

/** Reads a `file:` URL without a static `node:fs` import (keeps browser bundlers happy). */
export async function readFileUrl(url) {
  const name = "node:fs/promises";
  const fs = await import(/* @vite-ignore */ /* webpackIgnore: true */ name);
  return new Uint8Array(await fs.readFile(url));
}

const NEEDS_INPUT = "bm-engine: init() needs the wasm binary: bytes, a URL / Request / Response, or a WebAssembly.Module " +
  "(e.g. `import wasm from \"bm-engine/full.wasm\"` on Cloudflare Workers). The profile entries bm-engine/core, " +
  "bm-engine/standard and bm-engine/full locate their wasm file themselves.";

/**
 * @param {(() => URL) | undefined} defaultWasm  where `init()` without an argument loads the wasm from
 *   (called lazily, so a runtime without a usable `import.meta.url` only fails when it is actually needed)
 */
export function createBinding(defaultWasm) {
  /** @type {WebAssembly.Exports & Record<string, any>} */
  let wasm = null;
  /** in-flight `init()` (concurrent callers share it) */
  let pending = null;

  /**
   * Optional features of the loaded wasm binary (all false before init). Binaries older than the
   * `bm_features` export report every feature as available.
   * @type {Record<string, boolean>}
   */
  const features = Object.fromEntries(FEATURE_NAMES.map((n) => [n, false]));

  function setFeatures() {
    const m = typeof wasm.bm_features === "function" ? wasm.bm_features() >>> 0 : 0xffffffff;
    FEATURE_NAMES.forEach((n, i) => { features[n] = ((m >>> i) & 1) === 1; });
  }

  const FULL_ONLY = new Set(["renderSvg", "animation", "extraCodecs", "colorFonts", "complexText"]);
  function requireFeature(name) {
    if (!features[name]) {
      throw new Error(`bm-engine: this build has no ${FEATURE_LABELS[name] || name} support (use the ${FULL_ONLY.has(name) ? "full" : "standard / full"} build${name === "woff" ? ", or load the WOFF add-on: import { loadWoff } from \"bm-engine/woff\"; await loadWoff()" : ""})`);
    }
  }

  function u8() {
    return new Uint8Array(wasm.memory.buffer);
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

  function adopt(instance) {
    if (!wasm) {
      wasm = instance.exports;
      setFeatures();
    }
    return wasm;
  }

  /** Synchronously instantiate from bytes or a compiled WebAssembly.Module (or `{ module }`). */
  function initSync(input) {
    if (wasm) return wasm;
    if (input && typeof input === "object" && "module" in input && !(input instanceof WebAssembly.Module)) input = input.module;
    if (input == null) throw new Error(NEEDS_INPUT.replace("init()", "initSync()"));
    const mod = input instanceof WebAssembly.Module ? input : new WebAssembly.Module(input);
    return adopt(new WebAssembly.Instance(mod, {}));
  }

  async function load(input) {
    input = await input;
    if (input && typeof input === "object" && "module_or_path" in input) input = await input.module_or_path;
    if (input == null) {
      if (!defaultWasm) throw new Error(NEEDS_INPUT);
      let url;
      try {
        url = defaultWasm();
      } catch (e) {
        throw new Error("bm-engine: cannot locate the wasm file in this runtime (no usable import.meta.url); pass it to init() " +
          "explicitly, e.g. `import wasm from \"bm-engine/core.wasm\"; await init(wasm)` (" + (e && e.message) + ")");
      }
      input = url.protocol === "file:" ? await readFileUrl(url) : url;
    }
    if (typeof input === "string" || (typeof URL !== "undefined" && input instanceof URL) ||
        (typeof Request !== "undefined" && input instanceof Request)) {
      const res = await fetch(input);
      if (!res.ok) throw new Error(`bm-engine: failed to fetch the wasm (${res.status} ${res.statusText || ""}): ${res.url || input}`);
      input = res;
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

  /**
   * Instantiate from a URL / Request / Response / Promise<Response> / bytes / WebAssembly.Module
   * (or `{ module_or_path }`). Idempotent: once initialised, every call resolves to the same instance and
   * ignores its argument; concurrent calls share one instantiation; a failed call can be retried.
   */
  function init(input) {
    if (wasm) return Promise.resolve(wasm);
    if (!pending) {
      pending = load(input).finally(() => { pending = null; });
    }
    return pending;
  }

  class Renderer {
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
      const self = this;
      return JSON.stringify(value, function (key, v) {
        // `this[key]` is the raw value: a Node Buffer reaches the replacer already converted by Buffer#toJSON.
        if (key === "src" && this && this[key] && typeof this[key] === "object") v = this[key];
        if (key === "src" && v && typeof v === "object") {
          const id = "bm-res:" + self.#resSeq++;
          if (isBinary(v)) self.#putImage(id, v);
          else if (v.data && v.width) self.#putRgba(id, v);
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
      const mime = { png: "image/png", jpeg: "image/jpeg", jpg: "image/jpeg", webp: "image/webp", ico: "image/x-icon" }[options.format || "png"];
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

    [DISPOSE]() {
      this.free();
    }
  }

  /** takumi module function. bm-engine's glyph-mask budget is fixed (8 MiB): accepted and ignored. */
  function setGlyphCacheMaxBytes(bytes) {
    void bytes;
  }

  /** Where `init()` without an argument loads the wasm from (profile entries), else undefined. */
  function wasmUrl() {
    return defaultWasm ? defaultWasm() : undefined;
  }

  return { init, initSync, Renderer, Prepared, features, setGlyphCacheMaxBytes, wasmUrl };
}
