// Fake "bm" engine for harness self-tests: wraps a real adapter (takumi-wasm) and perturbs its "raw" output.
// Modes: identity | noise (+-3 on every channel) | aa (0.3% of pixels change by +-28 levels, like AA edge differences) | salt (0.2% of pixels fully inverted) | shift (content shifted right by N px)
//        | invert | blank | wrongsize | throw | alpha-premul (returns premultiplied raw, adapter declares rawAlpha "premultiplied")
export function makeMock(base, mode, { name = "bm", amount = 4 } = {}) {
  let seed = 987654321;
  const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
  const perturb = (raw, w, h) => {
    const o = new Uint8Array(raw);
    switch (mode) {
      case "identity": return o;
      case "noise": for (let i = 0; i < o.length; i++) if (i % 4 !== 3) o[i] = Math.max(0, Math.min(255, o[i] + Math.round((rnd() - 0.5) * 6))); return o;
      case "aa": for (let p = 0; p < w * h; p++) if (rnd() < 0.003) { const i = p * 4, d = rnd() < 0.5 ? -28 : 28; for (let c = 0; c < 3; c++) o[i + c] = Math.max(0, Math.min(255, o[i + c] + d)); } return o;
      case "salt": for (let p = 0; p < w * h; p++) if (rnd() < 0.002) { const i = p * 4; o[i] = 255 - o[i]; o[i + 1] = 255 - o[i + 1]; o[i + 2] = 255 - o[i + 2]; } return o;
      case "shift": { const s = new Uint8Array(o.length); for (let y = 0; y < h; y++) for (let x = amount; x < w; x++) for (let c = 0; c < 4; c++) s[(y * w + x) * 4 + c] = o[(y * w + x - amount) * 4 + c]; return s; }
      case "invert": for (let i = 0; i < o.length; i += 4) { o[i] = 255 - o[i]; o[i + 1] = 255 - o[i + 1]; o[i + 2] = 255 - o[i + 2]; } return o;
      case "blank": o.fill(0); return o;
      case "wrongsize": return o.slice(0, o.length - 4 * w);
      case "alpha-premul": for (let i = 0; i < o.length; i += 4) { const a = o[i + 3]; o[i] = Math.round((o[i] * a) / 255); o[i + 1] = Math.round((o[i + 1] * a) / 255); o[i + 2] = Math.round((o[i + 2] * a) / 255); } return o;
      default: throw new Error("unknown mock mode " + mode);
    }
  };
  return {
    name, available: true, mock: mode,
    rawAlpha: mode === "alpha-premul" ? "premultiplied" : "straight",
    async create(opts) {
      const inner = await base.create(opts);
      return {
        ...inner, name,
        async render(node, o) {
          if (mode === "throw") throw new Error("mock: unsupported feature");
          const out = await inner.render(node, o);
          return o.format === "raw" ? perturb(out, o.width, o.height) : out;
        },
      };
    },
  };
}
