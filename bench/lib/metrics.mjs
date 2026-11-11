// Image comparison metrics. All inputs are straight-alpha RGBA8 (Uint8Array/Uint8ClampedArray, w*h*4).
import pixelmatch from "pixelmatch";

/** Convert premultiplied RGBA8 to straight RGBA8 (new array). */
export function unpremultiply(src) {
  const out = new Uint8Array(src.length);
  for (let i = 0; i < src.length; i += 4) {
    const a = src[i + 3];
    if (a === 0) continue;
    if (a === 255) { out[i] = src[i]; out[i + 1] = src[i + 1]; out[i + 2] = src[i + 2]; out[i + 3] = 255; continue; }
    out[i] = Math.min(255, Math.round((src[i] * 255) / a));
    out[i + 1] = Math.min(255, Math.round((src[i + 1] * 255) / a));
    out[i + 2] = Math.min(255, Math.round((src[i + 2] * 255) / a));
    out[i + 3] = a;
  }
  return out;
}

/** Rec.601 luma of straight RGBA composited over white. Float32Array(w*h), range 0..255. */
export function luma(rgba, w, h) {
  const out = new Float32Array(w * h);
  for (let i = 0, p = 0; p < out.length; p++, i += 4) {
    const a = rgba[i + 3] / 255;
    const r = rgba[i] * a + 255 * (1 - a), g = rgba[i + 1] * a + 255 * (1 - a), b = rgba[i + 2] * a + 255 * (1 - a);
    out[p] = 0.299 * r + 0.587 * g + 0.114 * b;
  }
  return out;
}

/**
 * Mean SSIM over uniform win x win windows (stride 1) on luma. Standard constants
 * C1=(0.01*255)^2, C2=(0.03*255)^2. Row-band sliding sums => O(w) extra memory.
 * Images smaller than the window fall back to a single global window.
 */
export function ssimLuma(a, b, w, h, win = 8) {
  return ssimPlane(luma(a, w, h), luma(b, w, h), w, h, win);
}

/** One channel (R=0,G=1,B=2) of straight RGBA composited over white, as a Float32 plane. */
export function channelPlane(rgba, w, h, ch) {
  const out = new Float32Array(w * h);
  for (let i = 0, p = 0; p < out.length; p++, i += 4) { const a = rgba[i + 3] / 255; out[p] = rgba[i + ch] * a + 255 * (1 - a); }
  return out;
}
/** Mean of the per-channel (R,G,B over white) SSIMs: catches chroma-only differences that luma SSIM misses. */
export function ssimRgb(a, b, w, h, win = 8) {
  let t = 0;
  for (let ch = 0; ch < 3; ch++) t += ssimPlane(channelPlane(a, w, h, ch), channelPlane(b, w, h, ch), w, h, win);
  return t / 3;
}

export function ssimPlane(x, y, w, h, win = 8) {
  const C1 = (0.01 * 255) ** 2, C2 = (0.03 * 255) ** 2;
  if (w < win || h < win) win = Math.max(1, Math.min(w, h));
  const N = win * win;
  const cx = new Float64Array(w), cy = new Float64Array(w), cxx = new Float64Array(w), cyy = new Float64Array(w), cxy = new Float64Array(w);
  const add = (row, s) => {
    const o = row * w;
    for (let i = 0; i < w; i++) {
      const p = x[o + i], q = y[o + i];
      cx[i] += s * p; cy[i] += s * q; cxx[i] += s * p * p; cyy[i] += s * q * q; cxy[i] += s * p * q;
    }
  };
  let total = 0, count = 0;
  for (let r = 0; r < win - 1; r++) add(r, 1);
  for (let top = 0; top + win <= h; top++) {
    add(top + win - 1, 1);
    let sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
    for (let i = 0; i < win; i++) { sx += cx[i]; sy += cy[i]; sxx += cxx[i]; syy += cyy[i]; sxy += cxy[i]; }
    for (let left = 0; left + win <= w; left++) {
      if (left > 0) {
        const o = left - 1, n = left + win - 1;
        sx += cx[n] - cx[o]; sy += cy[n] - cy[o]; sxx += cxx[n] - cxx[o]; syy += cyy[n] - cyy[o]; sxy += cxy[n] - cxy[o];
      }
      const mx = sx / N, my = sy / N;
      const vx = Math.max(0, sxx / N - mx * mx), vy = Math.max(0, syy / N - my * my), cv = sxy / N - mx * my;
      total += ((2 * mx * my + C1) * (2 * cv + C2)) / ((mx * mx + my * my + C1) * (vx + vy + C2));
      count++;
    }
    add(top, -1);
  }
  return count ? total / count : 1;
}

/**
 * Compare two straight-RGBA buffers of the same size.
 * Returns pixelmatch counts (thr 0.1, includeAA true = strict / false = AA-tolerant), % differing,
 * mean abs channel diff (RGBA, 0..255), max abs diff, PSNR (dB, capped 100), SSIM. Optionally a diff image.
 */
export function compare(a, b, w, h, { diff = false, threshold = 0.1 } = {}) {
  const n = w * h;
  const diffImg = diff ? new Uint8Array(n * 4) : undefined;
  const pmStrict = pixelmatch(a, b, diffImg, w, h, { threshold, includeAA: true });
  const pmAA = pixelmatch(a, b, undefined, w, h, { threshold, includeAA: false });
  let sum = 0, sq = 0, max = 0, identical = true;
  for (let i = 0; i < a.length; i++) {
    const d = Math.abs(a[i] - b[i]);
    if (d) { identical = false; sum += d; sq += d * d; if (d > max) max = d; }
  }
  const mse = sq / a.length;
  const psnr = mse === 0 ? 100 : Math.min(100, 10 * Math.log10((255 * 255) / mse));
  const ssim = identical ? 1 : ssimLuma(a, b, w, h);
  return {
    identical,
    pmStrict, pmAA,
    pctStrict: (100 * pmStrict) / n, pctAA: (100 * pmAA) / n,
    meanAbs: sum / a.length, maxAbs: max, psnr, ssim, ssimRgb: identical ? 1 : ssimRgb(a, b, w, h),
    diff: diffImg,
  };
}

/** Verdict from a compare() result (see README). */
export function verdict(m) {
  if (m.identical) return "identical";
  const ss = Math.min(m.ssim, m.ssimRgb ?? m.ssim); // luma SSIM is chroma-blind, so also require per-channel RGB SSIM
  if (ss >= 0.99 && m.pctStrict <= 0.5) return "equivalent";
  if (ss >= 0.95 && m.pctStrict <= 5) return "close"; // guard: big flat-colour errors over a small area keep SSIM high
  return "different";
}

/** Self-checks: throws on failure. Returns list of check descriptions. */
export function selfCheck() {
  const done = [];
  const ok = (cond, msg) => { if (!cond) throw new Error("metrics self-check failed: " + msg); done.push(msg); };
  const w = 64, h = 48;
  // deterministic PRNG
  let s = 12345; const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  const base = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * 4, v = Math.round(128 + 100 * Math.sin(x / 5) * Math.cos(y / 7));
    base[i] = v; base[i + 1] = 255 - v; base[i + 2] = (x * 4) & 255; base[i + 3] = 255;
  }
  ok(Math.abs(ssimLuma(base, base, w, h) - 1) < 1e-9 && Math.abs(ssimRgb(base, base, w, h) - 1) < 1e-9, "ssim(identical) == 1 (luma and RGB)");
  const noisy = (amp) => { const o = base.slice(); for (let i = 0; i < o.length; i += 4) for (let c = 0; c < 3; c++) o[i + c] = Math.max(0, Math.min(255, o[i + c] + Math.round((rnd() - 0.5) * 2 * amp))); return o; };
  const s1 = ssimLuma(base, noisy(10), w, h), s2 = ssimLuma(base, noisy(60), w, h);
  ok(s1 < 1 && s1 > s2, `noise lowers ssim monotonically (${s1.toFixed(4)} > ${s2.toFixed(4)})`);
  const flatA = new Uint8Array(w * h * 4).fill(0), flatB = new Uint8Array(w * h * 4).fill(255);
  for (let i = 3; i < flatA.length; i += 4) flatA[i] = 255;
  ok(ssimLuma(flatA, flatB, w, h) < 0.01, "ssim(black, white) ~ 0");
  const m0 = compare(base, base.slice(), w, h);
  ok(m0.identical && m0.pmStrict === 0 && m0.maxAbs === 0 && m0.psnr === 100 && verdict(m0) === "identical", "compare(identical) => identical");
  const m1 = compare(base, noisy(80), w, h);
  ok(!m1.identical && m1.maxAbs > 0 && m1.psnr < 40 && m1.meanAbs > 0, "compare(noisy) has nonzero diff");
  const one = base.slice(); one[(10 * w + 10) * 4] ^= 0xff;
  const m2 = compare(base, one, w, h);
  ok(m2.maxAbs > 0 && m2.ssim < 1 && m2.ssim > 0.99, "single-pixel change => ssim just under 1");
  // premultiply round trip
  const half = new Uint8Array([255, 0, 0, 128]);
  const pre = new Uint8Array([128, 0, 0, 128]);
  ok(unpremultiply(pre)[0] === 255 && half[0] === 255, "unpremultiply restores straight alpha");
  return done;
}
