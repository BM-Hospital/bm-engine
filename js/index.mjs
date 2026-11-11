// bm-engine — dependency-free ESM wrapper around bm_engine.wasm.
// Works in browsers, Node.js, Bun, Deno and edge runtimes. The wasm module has NO imports.
//
//   import { init, Renderer } from "bm-engine";
//   await init(fetch(new URL("./bm_engine.wasm", import.meta.url)));   // or bytes / WebAssembly.Module
//   const r = new Renderer();
//   r.registerFont(fontBytes);
//   const png = r.renderSync(node, { width: 1200, height: 630 });
//
// The node format and render options follow takumi (`@takumi-rs/wasm`), so the same input renders on both.

/** @type {WebAssembly.Exports & Record<string, any>} */
let wasm = null;
const enc = new TextEncoder();
const dec = new TextDecoder();

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

/** Synchronously instantiate from bytes or a compiled WebAssembly.Module. */
export function initSync(input) {
  if (wasm) return wasm;
  const mod = input instanceof WebAssembly.Module ? input : new WebAssembly.Module(input);
  wasm = new WebAssembly.Instance(mod, {}).exports;
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
      if (!wasm) wasm = instance.exports;
      return wasm;
    }
    input = await input.arrayBuffer();
  }
  if (input instanceof WebAssembly.Module) {
    const instance = await WebAssembly.instantiate(input, {});
    if (!wasm) wasm = instance.exports;
    return wasm;
  }
  const { instance } = await WebAssembly.instantiate(input, {});
  if (!wasm) wasm = instance.exports;
  return wasm;
}

export default init;

const STYLE_ITALIC = 1;

function isBinary(v) {
  return v instanceof Uint8Array || v instanceof ArrayBuffer;
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

  /**
   * Register a font (static TrueType .ttf/.ttc). Accepts raw bytes or `{ name, data, weight, style }`.
   * Returns `{ name, weight, style }` as resolved from the font tables.
   */
  registerFont(font) {
    const details = isBinary(font) || ArrayBuffer.isView(font) ? { data: font } : font;
    const [ptr, len] = copyIn(toBytes(details.data));
    const [nptr, nlen, ncap] = copyInString(details.name || "");
    const italic = details.style == null ? -1 : /italic|oblique/.test(String(details.style)) ? 1 : 0;
    // Ownership of the font bytes moves to the renderer (zero-copy parsing inside wasm).
    const status = wasm.bm_register_font(this.#h, ptr, len, nptr, nlen, details.weight | 0, italic);
    wasm.bm_free(nptr, ncap);
    check(status);
    return JSON.parse(this.#takeString());
  }

  /** takumi-compatible alias. */
  loadFont(font) {
    return this.registerFont(font);
  }

  clearFonts() {
    wasm.bm_clear_fonts(this.#h);
  }

  #takeString() {
    const ptr = wasm.bm_result_ptr(this.#h);
    const len = wasm.bm_result_len(this.#h);
    return dec.decode(u8().subarray(ptr, ptr + len));
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

  /** Serialises the node tree; binary image sources are moved into wasm and replaced by ids. */
  #prepare(node, options) {
    wasm.bm_clear_images(this.#h);
    const images = options.images;
    const list = Array.isArray(images) ? images : images && images.sources ? images.sources : [];
    for (const img of list) this.#putImage(img.src, img.data);
    if (typeof node === "string") return node;
    if (node && typeof node === "object" && typeof node.json === "string" && node.type === undefined) return node.json;
    return JSON.stringify(node, (key, value) => {
      if (key === "src" && value && typeof value === "object") {
        const id = "bm-res:" + this.#resSeq++;
        if (isBinary(value) || ArrayBuffer.isView(value)) this.#putImage(id, value);
        else if (value.data && value.width) this.#putRgba(id, value);
        else return value;
        return id;
      }
      return value;
    });
  }

  #call(fn, node, options) {
    const json = this.#prepare(node, options);
    const { images: _i, ...rest } = options;
    const [jptr, jlen, jcap] = copyInString(json);
    const [optr, olen, ocap] = copyInString(JSON.stringify(rest));
    const status = fn(this.#h, jptr, jlen, optr, olen);
    wasm.bm_free(jptr, jcap);
    wasm.bm_free(optr, ocap);
    check(status);
  }

  /** Render synchronously. Returns a fresh Uint8Array (PNG by default; `format: "raw"` = straight RGBA8). */
  renderSync(node, options = {}) {
    this.#call(wasm.bm_render, node, options);
    const ptr = wasm.bm_result_ptr(this.#h);
    const len = wasm.bm_result_len(this.#h);
    const out = u8().slice(ptr, ptr + len);
    wasm.bm_release_result(this.#h);
    return out;
  }

  /** takumi-compatible async signature (resolves immediately; rendering is synchronous). */
  async render(node, options = {}) {
    return this.renderSync(node, options);
  }

  async renderAsDataUrl(node, options = {}) {
    const bytes = this.renderSync(node, options);
    const mime = { png: "image/png", jpeg: "image/jpeg", webp: "image/webp" }[options.format || "png"];
    if (!mime) throw new Error("bm-engine: renderAsDataUrl needs an encoded format");
    let bin = "";
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return `data:${mime};base64,${btoa(bin)}`;
  }

  /** Lay out only. Returns `{ width, height, transform, children, runs }` like takumi's `measure`. */
  measureSync(node, options = {}) {
    this.#call(wasm.bm_measure, node, options);
    const out = JSON.parse(this.#takeString());
    wasm.bm_release_result(this.#h);
    return out;
  }

  async measure(node, options = {}) {
    return this.measureSync(node, options);
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
}

void STYLE_ITALIC;
