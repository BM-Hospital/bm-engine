// `node --import ./bench/lib/pdf-identity-hook.mjs <script>`: runs an existing script that uses `bm-engine/pdf`
// (a docs example, scripts/pdf-test.mjs, scripts/pdf-compare.mjs) on the NATIVE addon, and replays every PDF
// call it makes on the wasm pdf profile (js/bm_engine.pdf.wasm) with the same inputs: registerFont,
// unregisterFont, clearFonts, prepare, renderPdf / renderPdfSync, measurePdf / measurePdfSync. The script itself
// sees only the native results; the bytes (or the error messages) of both backends are compared and the outcome
// is written to $BM_PDF_IDENTITY_OUT (JSON) when the process exits. Used by bench/native-identity.mjs.
//
// How: the `Renderer` class of the native pdf binding (js/native.mjs `nativePdfBinding()`, the instance
// js/node-pdf.mjs exports) gets its prototype methods wrapped; each native renderer has a wasm twin.
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";

process.env.BM_ENGINE_BACKEND = "native";
const root = new URL("../../", import.meta.url);
const { nativePdfBinding, nativeError } = await import(new URL("js/native.mjs", root).href);
const { createBinding } = await import(new URL("js/engine.mjs", root).href);
const nb = nativePdfBinding();
if (!nb) throw new Error("pdf-identity-hook: the native addon with PDF output is not available (" + nativeError() + ")");
const wb = createBinding();
wb.initSync(readFileSync(new URL("js/bm_engine.pdf.wasm", root)));
for (const [k, v] of Object.entries(wb.features)) if (nb.features[k] !== v) throw new Error(`pdf-identity-hook: feature ${k}: wasm ${v}, native ${nb.features[k]}`);

const out = { script: process.argv[1], compared: 0, identical: 0, bothError: 0, bytes: 0, calls: {}, mismatches: [] };
const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 16);
const toBuf = (v) => (typeof v === "string" ? Buffer.from(v, "utf8") : v instanceof Uint8Array ? Buffer.from(v.buffer, v.byteOffset, v.byteLength) : Buffer.from(JSON.stringify(v) ?? "undefined", "utf8"));

function compare(what, n, w) {
  out.compared++;
  out.calls[what] = (out.calls[what] || 0) + 1;
  if (n.error !== undefined || w.error !== undefined) {
    if (n.error === w.error) { out.identical++; out.bothError++; return; }
    out.mismatches.push({ what, native: n.error !== undefined ? "error: " + n.error : `${toBuf(n.value).length} bytes`, wasm: w.error !== undefined ? "error: " + w.error : `${toBuf(w.value).length} bytes` });
    return;
  }
  const a = toBuf(n.value);
  const b = toBuf(w.value);
  out.bytes += a.length;
  if (a.length === b.length && a.equals(b)) { out.identical++; return; }
  let first = 0;
  const len = Math.min(a.length, b.length);
  while (first < len && a[first] === b[first]) first++;
  out.mismatches.push({ what, native: `${a.length} bytes ${sha(a)}`, wasm: `${b.length} bytes ${sha(b)}`, firstDiffAt: first });
}

const twins = new WeakMap(); // native Renderer -> wasm Renderer
const handles = new WeakMap(); // native Prepared -> wasm Prepared
/** native renderers inside a wrapped async call: what they do to themselves meanwhile (fonts of `fonts` loaders) is not replayed */
const busy = new WeakSet();
const twin = (r) => {
  let t = twins.get(r);
  if (!t) twins.set(r, (t = new wb.Renderer()));
  return t;
};
const settle = (fn) => { try { return { value: fn() }; } catch (e) { return { error: String(e && e.message) }; } };
const settleAsync = async (fn) => { try { return { value: await fn() }; } catch (e) { return { error: String(e && e.message) }; } };
const give = (r) => { if (r.error !== undefined) throw r.thrown; return r.value; };
const settleKeep = (fn) => { try { return { value: fn() }; } catch (e) { return { error: String(e && e.message), thrown: e }; } };
const settleKeepAsync = async (fn) => { try { return { value: await fn() }; } catch (e) { return { error: String(e && e.message), thrown: e }; } };
const twinSource = (node) => (node && typeof node === "object" && handles.get(node)) || node;

const P = nb.Renderer.prototype;
const orig = {};
for (const k of ["registerFont", "unregisterFont", "clearFonts", "free", "prepare", "renderPdf", "renderPdfSync", "measurePdf", "measurePdfSync"]) orig[k] = P[k];

/** registerFont inputs the engine handles synchronously (the others re-enter registerFont with the resolved value) */
function finalFont(font) {
  if (typeof font === "string" || (typeof URL !== "undefined" && font instanceof URL)) return false;
  if (font && typeof font.then === "function") return false;
  const d = font && (ArrayBuffer.isView(font) || font instanceof ArrayBuffer ? font : font.data);
  return !(d && (typeof d === "function" || typeof d.then === "function"));
}

P.registerFont = function (font) {
  if (busy.has(this) || !finalFont(font)) return orig.registerFont.call(this, font);
  const n = settleKeep(() => orig.registerFont.call(this, font));
  compare("registerFont", n, settle(() => twin(this).registerFont(font)));
  return give(n);
};
P.loadFont = function (font) { return this.registerFont(font); };
P.unregisterFont = function (family) {
  const n = settleKeep(() => orig.unregisterFont.call(this, family));
  compare("unregisterFont", n, settle(() => twin(this).unregisterFont(family)));
  return give(n);
};
P.clearFonts = function () {
  twin(this).clearFonts();
  return orig.clearFonts.call(this);
};
P.free = function () {
  const t = twins.get(this);
  if (t) t.free();
  return orig.free.call(this);
};
P.prepare = async function (node, options) {
  busy.add(this);
  let n;
  try { n = await settleKeepAsync(() => orig.prepare.call(this, node, options)); } finally { busy.delete(this); }
  const w = await settleAsync(() => twin(this).prepare(node, options));
  if (n.error !== undefined || w.error !== undefined) compare("prepare", n, w);
  else handles.set(n.value, w.value);
  return give(n);
};
for (const k of ["renderPdfSync", "measurePdfSync"]) {
  P[k] = function (node, options) {
    const n = settleKeep(() => orig[k].call(this, node, options));
    compare(k, n, settle(() => twin(this)[k](twinSource(node), options)));
    return give(n);
  };
}
for (const k of ["renderPdf", "measurePdf"]) {
  P[k] = async function (node, options) {
    busy.add(this);
    let n;
    try { n = await settleKeepAsync(() => orig[k].call(this, node, options)); } finally { busy.delete(this); }
    compare(k, n, await settleAsync(() => twin(this)[k](twinSource(node), options)));
    return give(n);
  };
}

process.on("exit", () => {
  if (process.env.BM_PDF_IDENTITY_OUT) writeFileSync(process.env.BM_PDF_IDENTITY_OUT, JSON.stringify(out));
});
