// Runs IN the browser. Driven by bench/browser/run.mjs through page.evaluate.
import init, { Renderer } from "/js/index.mjs";

const b64ToBytes = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const bytesToB64 = (u8) => {
  let bin = "";
  for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
  return btoa(bin);
};
const median = (a) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[s.length >> 1] : NaN; };

const cases = new Map();
let renderer = null, wasmBytesLen = 0, initInfo = null;
let lastRaw = null;

window.bmInit = async (fonts) => {
  const t0 = performance.now();
  const resp = await fetch("/js/bm_engine.wasm");
  const ct = resp.headers.get("content-type");
  await init(resp); // streaming compile + instantiate
  const compileMs = performance.now() - t0;
  wasmBytesLen = +resp.headers.get("content-length") || 0;
  const t1 = performance.now();
  renderer = new Renderer();
  const cache = new Map();
  for (const f of fonts) {
    if (!cache.has(f.file)) cache.set(f.file, new Uint8Array(await (await fetch("/assets/fonts/" + f.file)).arrayBuffer()));
    renderer.registerFont({ name: f.name, data: cache.get(f.file), weight: f.weight, style: f.style });
  }
  window.__fontCache = cache;
  initInfo = { compileInstantiateMs: compileMs, fontRegisterMs: performance.now() - t1, wasmContentType: ct, wasmBytes: wasmBytesLen, fonts: fonts.length };
  return initInfo;
};

window.bmLoadCase = (k) => {
  cases.set(k.id, {
    id: k.id, width: k.width, height: k.height, node: k.node,
    images: (k.images || []).map((i) => ({ src: i.src, data: b64ToBytes(i.b64) })),
  });
};

const opts = (k, format) => {
  const o = { width: k.width, height: k.height, format, devicePixelRatio: 1 };
  if (k.images.length) o.images = k.images;
  if (format === "jpeg") o.quality = 85;
  return o;
};

const rawOf = (k) => renderer.renderSync(k.node, opts(k, "raw"));

// Render raw, keep bytes in the page, return metadata; bytes are fetched in chunks with bmRawChunk.
window.bmRender = (id, format) => {
  const k = cases.get(id);
  const t = performance.now();
  const out = renderer.renderSync(k.node, opts(k, format));
  const ms = performance.now() - t;
  if (format === "raw") { lastRaw = out; return { bytes: out.length, ms }; }
  return { bytes: out.length, ms };
};
window.bmRawChunk = (off, len) => bytesToB64(lastRaw.subarray(off, off + len));

// Encode in browser, decode via createImageBitmap, compare to the raw render.
window.bmFormatCheck = async (id, format) => {
  const k = cases.get(id);
  const raw = rawOf(k);
  const enc = renderer.renderSync(k.node, opts(k, format));
  const r = { format, encBytes: enc.length };
  const mime = { png: "image/png", webp: "image/webp", jpeg: "image/jpeg" }[format];
  const bmp = await createImageBitmap(new Blob([enc], { type: mime }));
  r.decodedW = bmp.width; r.decodedH = bmp.height;
  r.dimsOk = bmp.width === k.width && bmp.height === k.height;
  if (!r.dimsOk) return r;
  const cv = new OffscreenCanvas(bmp.width, bmp.height);
  const ctx = cv.getContext("2d", { willReadFrequently: true, colorSpaceConversion: "none" });
  ctx.drawImage(bmp, 0, 0);
  const px = ctx.getImageData(0, 0, bmp.width, bmp.height).data;
  let opaque = 0, translucent = 0, transparent = 0, maxDiff = 0, bad = 0, sumAbs = 0, alphaMax = 0;
  for (let i = 0; i < raw.length; i += 4) {
    const a = raw[i + 3];
    if (a === 0) { transparent++; continue; }
    if (a !== 255) {
      translucent++;
      const ad = Math.abs(px[i + 3] - a); if (ad > alphaMax) alphaMax = ad; // alpha is unaffected by premultiplication
      continue;
    }
    opaque++;
    const ad = Math.abs(px[i + 3] - 255); if (ad > alphaMax) alphaMax = ad;
    for (let c = 0; c < 3; c++) {
      const d = Math.abs(px[i + c] - raw[i + c]);
      sumAbs += d;
      if (d > maxDiff) maxDiff = d;
      if (d > 1) bad++;
    }
  }
  Object.assign(r, { opaque, translucent, transparent, maxDiff, badChannels: bad, alphaMaxDiff: alphaMax, meanAbsDiff: opaque ? sumAbs / (opaque * 3) : 0 });
  bmp.close();
  return r;
};

window.bmBench = (id, iters, warmup = 2) => {
  const k = cases.get(id);
  const res = {};
  for (const format of ["raw", "png"]) {
    for (let i = 0; i < warmup; i++) renderer.renderSync(k.node, opts(k, format));
    const t = [];
    for (let i = 0; i < iters; i++) { const s = performance.now(); renderer.renderSync(k.node, opts(k, format)); t.push(performance.now() - s); }
    res[format] = { medianMs: median(t), minMs: Math.min(...t), iters };
  }
  return res;
};

window.bmMemory = () => ({
  wasmMemoryBytes: Renderer.memoryBytes(),
  jsHeapUsed: performance.memory?.usedJSHeapSize ?? null,
  jsHeapTotal: performance.memory?.totalJSHeapSize ?? null,
});

// ---- takumi (optional) ----
let tk = null, tkRenderer = null;
window.bmTakumiInit = async (fonts) => {
  const t0 = performance.now();
  const mod = await import("/bench/node_modules/@takumi-rs/wasm/dist/export.mjs");
  const resp = await fetch("/bench/node_modules/@takumi-rs/wasm/pkg/takumi_wasm_bg.wasm");
  const out = await mod.default(resp);
  const compileMs = performance.now() - t0;
  tk = mod;
  tkRenderer = new mod.Renderer();
  for (const f of fonts) await tkRenderer.registerFont({ name: f.name, data: window.__fontCache.get(f.file), weight: f.weight, style: f.style });
  return { compileInstantiateMs: compileMs, wasmMemoryBytes: out?.memory?.buffer?.byteLength ?? null };
};
window.bmTakumiBench = async (id, iters, warmup = 2) => {
  const k = cases.get(id);
  const o = { width: k.width, height: k.height, format: "raw", devicePixelRatio: 1 };
  if (k.images.length) o.images = k.images;
  const res = {};
  for (const format of ["raw", "png"]) {
    o.format = format;
    for (let i = 0; i < warmup; i++) await tkRenderer.render(k.node, o);
    const t = [];
    for (let i = 0; i < iters; i++) { const s = performance.now(); await tkRenderer.render(k.node, o); t.push(performance.now() - s); }
    res[format] = { medianMs: median(t), minMs: Math.min(...t), iters };
  }
  return res;
};

document.getElementById("status").textContent = "ready";
window.bmReady = true;
