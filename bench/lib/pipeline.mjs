// Core harness logic shared by run.mjs and selftest.mjs.
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { PNG } from "pngjs";
import { compare, verdict, unpremultiply } from "./metrics.mjs";
import { fontsFor } from "./fonts.mjs";

export const errMsg = (e) => String(e?.message ?? e).split("\n")[0].slice(0, 400);

/** Render options for a case/format. */
export function renderOpts(k, format = "raw") {
  const o = { width: k.width, height: k.height, format, devicePixelRatio: 1 };
  if (k.images) o.images = k.images;
  if (format === "jpeg") o.quality = 85;
  return o;
}

/** Lazily-created engine instances, one per (adapter, font set). */
export class EnginePool {
  constructor(adapters) { this.adapters = adapters; this.cache = new Map(); this.createMs = {}; }
  async get(adapter, fontFamilies) {
    const key = adapter.name + "|" + (fontFamilies ? fontFamilies.join(",") : "*");
    if (!this.cache.has(key)) {
      const t0 = performance.now();
      try {
        const inst = await adapter.create({ fonts: fontsFor(fontFamilies) });
        inst.rawAlpha = adapter.rawAlpha ?? "straight";
        this.cache.set(key, { inst });
      } catch (e) { this.cache.set(key, { error: errMsg(e) }); }
      this.createMs[adapter.name] = (this.createMs[adapter.name] ?? 0) + performance.now() - t0;
    }
    return this.cache.get(key);
  }
  memory() {
    const out = {};
    for (const [key, v] of this.cache) { const n = key.split("|")[0]; try { const m = v.inst?.memoryBytes?.(); if (m != null) out[n] = Math.max(out[n] ?? 0, m); } catch {} }
    return out;
  }
  dispose() { for (const v of this.cache.values()) v.inst?.dispose?.(); }
}

/** Render raw and return straight RGBA8 + dims, or {error}. */
export async function renderStraight(inst, k) {
  try {
    const raw = await inst.render(k.node, renderOpts(k, "raw"));
    const buf = raw instanceof Uint8Array ? raw : new Uint8Array(raw);
    return { rgba: inst.rawAlpha === "premultiplied" ? unpremultiply(buf) : buf };
  } catch (e) { return { error: errMsg(e) }; }
}

export function encodePng(rgba, w, h) {
  const png = new PNG({ width: w, height: h });
  png.data = Buffer.from(rgba.buffer, rgba.byteOffset, rgba.byteLength);
  return PNG.sync.write(png);
}

function round(m) {
  const r = (v, d = 4) => (typeof v === "number" ? +v.toFixed(d) : v);
  return { identical: m.identical, pmStrict: m.pmStrict, pmAA: m.pmAA, pctStrict: r(m.pctStrict, 4), pctAA: r(m.pctAA, 4), meanAbs: r(m.meanAbs, 4), maxAbs: m.maxAbs, psnr: r(m.psnr, 2), ssim: r(m.ssim, 5), ssimRgb: r(m.ssimRgb, 5) };
}

/** Compare `cand` against `ref` renders for one case. */
export function compareRenders(k, ref, cand, wantDiff = false) {
  if (ref.error) return { verdict: "error/unsupported", error: `reference: ${ref.error}` };
  if (cand.error) return { verdict: "error/unsupported", error: cand.error };
  const need = k.width * k.height * 4;
  if (cand.rgba.length !== ref.rgba.length || cand.rgba.length !== need)
    return { verdict: "different", sizeMismatch: true, error: `size mismatch: got ${cand.rgba.length} bytes, expected ${need}` };
  const m = compare(ref.rgba, cand.rgba, k.width, k.height, { diff: wantDiff });
  return { verdict: verdict(m), ...round(m), _diff: m.diff };
}

/**
 * Equivalence for one case. `names` = {ref:'takumi-wasm', cands:['bm','takumi-native']}.
 * Returns { renders:{name:{ok|error}}, cmp:{name: metrics}, }; writes PNGs to outDir/<id>/ when given.
 */
export async function equivalenceForCase(k, pool, adapters, { ref = "takumi-wasm", cands = ["bm", "takumi-native"], outDir } = {}) {
  const res = {};
  const names = [ref, ...cands].filter((n) => adapters[n]?.available);
  for (const n of names) {
    const e = await pool.get(adapters[n], k.fonts);
    res[n] = e.error ? { error: e.error } : await renderStraight(e.inst, k);
  }
  const cmp = {};
  const dir = outDir && path.join(outDir, k.id);
  if (dir) mkdirSync(dir, { recursive: true });
  const fileOf = { "takumi-wasm": "takumi.png", bm: "bm.png", "takumi-native": "native.png" };
  for (const n of names) if (dir && res[n].rgba && res[n].rgba.length === k.width * k.height * 4) writeFileSync(path.join(dir, fileOf[n] ?? n + ".png"), encodePng(res[n].rgba, k.width, k.height));
  let primary = true;
  for (const n of cands) {
    if (!adapters[n]?.available) continue;
    const r = compareRenders(k, res[ref], res[n], !!dir);
    if (dir && r._diff) writeFileSync(path.join(dir, primary ? "diff.png" : `diff-${n.replace("takumi-", "")}.png`), encodePng(r._diff, k.width, k.height));
    delete r._diff;
    cmp[n] = r; primary = false;
  }
  // 'diff.png' = first available candidate vs ref (bm if present, else native)
  return { renders: Object.fromEntries(Object.entries(res).map(([n, v]) => [n, v.error ? { error: v.error } : { ok: true }])), cmp };
}

// ---- performance ----
export function stats(times) {
  const s = [...times].sort((a, b) => a - b);
  const q = (p) => s[Math.min(s.length - 1, Math.floor(p * (s.length - 1) + 0.5))];
  return { median: q(0.5), p95: q(0.95), min: s[0], n: s.length };
}

/**
 * Interleaved measurement of several engines on one (case, format).
 * `targets` = [{name, inst}]. Budget: >= minIters and >= minMs per engine (cap maxMs), split into `rounds` alternating rounds.
 * If cfg.iters is set, exactly that many iterations per engine (still interleaved).
 */
export async function measureInterleaved(targets, k, format, cfg) {
  const out = {}, samples = {}, bytes = {};
  const opts = renderOpts(k, format);
  const live = [];
  for (const t of targets) {
    try { for (let i = 0; i < cfg.warmup; i++) { const o = await t.inst.render(k.node, opts); bytes[t.name] = o.length; } live.push(t); samples[t.name] = []; }
    catch (e) { out[t.name] = { error: errMsg(e) }; }
  }
  const rounds = cfg.rounds;
  for (let r = 0; r < rounds; r++) {
    for (const t of live) {
      const s = samples[t.name]; const start = performance.now();
      const needIters = cfg.iters ? Math.ceil(cfg.iters / rounds) : Math.ceil(cfg.minIters / rounds);
      let done = 0;
      for (;;) {
        const t0 = performance.now();
        try { const o = await t.inst.render(k.node, opts); bytes[t.name] = o.length; } catch (e) { out[t.name] = { error: errMsg(e) }; break; }
        const t1 = performance.now(); s.push(t1 - t0); done++;
        const el = t1 - start;
        if (cfg.iters) { if (done >= needIters) break; }
        else if ((done >= needIters && el >= cfg.minMs / rounds) || el >= cfg.maxMs / rounds || done >= 5000) break;
      }
    }
  }
  for (const t of live) if (!out[t.name]) out[t.name] = { ...stats(samples[t.name]), bytes: bytes[t.name] };
  return out;
}
