// Colour-glyph oracle: renders emoji with bm-render's color.zig reference painter (wasm harness built
// from src/test_color.zig) and compares per glyph with takumi (@takumi-rs/wasm, CBDT + COLRv0) or
// headless Chrome/Edge (COLRv1: takumi only renders COLR v0, glyph.rs uses ColorGlyphFormat::ColrV0).
//
// Build the harness first (from repo root):
//   zig build-exe src/test_color.zig -target wasm32-freestanding -O ReleaseSafe -fno-entry -rdynamic \
//       --name colorharness -femit-bin=<scratch>/colorharness.wasm
// Run (from bench/):
//   node probe/colorfont/oracle.mjs --wasm <scratch>/colorharness.wasm --fonts <dir with Twemoji.ttf,
//        NotoColorEmoji-COLRv1.ttf, BungeeSpice-Regular.ttf> [--out <dir for png dumps>] [--only cbdt,colrv0,...]
// Twemoji.ttf = wawoff2.decompress(ref/takumi/assets/fonts/twemoji/TwemojiMozilla-colr.woff2).
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { PNG } from "pngjs";
import { compare } from "../../lib/metrics.mjs";
import takumi from "../../engines/takumi-wasm.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "..", "..", "..");
const arg = (k, d) => { const i = process.argv.indexOf("--" + k); return i > 0 ? process.argv[i + 1] : d; };
const wasmPath = arg("wasm");
const fontDir = arg("fonts");
const outDir = arg("out");
const only = arg("only");
if (!wasmPath || !fontDir) { console.error("usage: oracle.mjs --wasm colorharness.wasm --fonts <dir> [--out dir] [--only a,b]"); process.exit(1); }
if (outDir) mkdirSync(outDir, { recursive: true });

const EMOJI = ["😀", "👍🏽", "🇻🇳", "👨‍👩‍👧", "❤️", "🎉", "🦄", "🌈", "🔥", "🏳️‍🌈"];
const cases = [
  { id: "cbdt", file: path.join(repo, "ref/takumi/assets/fonts/noto-sans/NotoColorEmoji.ttf"), texts: EMOJI, ref: "takumi" },
  { id: "colrv0", file: path.join(fontDir, "Twemoji.ttf"), texts: EMOJI, ref: "takumi" },
  { id: "colrv1", file: path.join(fontDir, "NotoColorEmoji-COLRv1.ttf"), texts: EMOJI, ref: "chrome" },
  { id: "colrv1-bungee", file: path.join(fontDir, "BungeeSpice-Regular.ttf"), texts: ["A", "g", "Q", "&"], ref: "chrome" },
  { id: "colrv1-nabla", file: path.join(fontDir, "Nabla.ttf"), texts: ["A", "g", "Q"], ref: "chrome" },
  { id: "colrv1-nabla-var", file: path.join(fontDir, "Nabla.ttf"), texts: ["A", "g", "Q"], ref: "chrome", vars: [["EDPT", 200], ["EHLT", 2]] },
].filter((c) => (!only || only.split(",").includes(c.id)) && existsSync(c.file));
const SIZES = (arg("sizes", "64,128")).split(",").map(Number);

// ---- harness
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {});
const X = instance.exports;
const mem = () => new Uint8Array(X.memory.buffer);
function loadFont(bytes) {
  const p = X.cf_alloc(bytes.length);
  mem().set(bytes, p);
  if (X.cf_load(p, bytes.length) !== 0) throw new Error("cf_load failed");
}
// Minimal shaper for the oracle: cmap (harness) + every GSUB type-4 ligature lookup (also via type 7),
// applied greedily; advances from hmtx. (The engine's text.zig drops U+200D / VS before GSUB, so it
// cannot form ZWJ ligatures yet.)
let F = null; // current font bytes
function shape(text, size) {
  const cps = [...text].map((c) => c.codePointAt(0));
  let gids = cps.map((cp) => X.cf_gid(cp)).filter((g, i) => g !== 0 || (cps[i] !== 0xfe0f && cps[i] !== 0xfe0e));
  gids = applyLigatures(F, gids);
  const upem = X.cf_upem();
  return gids.map((gid) => ({ gid, adv: advance(F, gid) * size / upem }));
}
function advance(b, gid) {
  const hhea = findTable(b, 'hhea'), hmtx = findTable(b, 'hmtx');
  const n = b.readUInt16BE(hhea + 34);
  return b.readUInt16BE(hmtx + 4 * Math.min(gid, n - 1));
}
function coverageIndex(b, off, g) {
  const fmt = b.readUInt16BE(off), n = b.readUInt16BE(off + 2);
  if (fmt === 1) { for (let i = 0; i < n; i++) if (b.readUInt16BE(off + 4 + 2 * i) === g) return i; return -1; }
  for (let i = 0; i < n; i++) { const r = off + 4 + 6 * i, a = b.readUInt16BE(r), z = b.readUInt16BE(r + 2); if (g >= a && g <= z) return b.readUInt16BE(r + 4) + g - a; }
  return -1;
}
function applyLigatures(b, gids) {
  const gsub = findTable(b, 'GSUB'); if (!gsub) return gids;
  const ll = gsub + b.readUInt16BE(gsub + 8), nl = b.readUInt16BE(ll);
  for (let li = 0; li < nl; li++) {
    const lt = ll + b.readUInt16BE(ll + 2 + 2 * li);
    let type = b.readUInt16BE(lt); const ns = b.readUInt16BE(lt + 4);
    for (let si = 0; si < ns; si++) {
      let st = lt + b.readUInt16BE(lt + 6 + 2 * si), t = type;
      if (t === 7) { t = b.readUInt16BE(st + 2); st = st + b.readUInt32BE(st + 4); }
      if (t !== 4) continue;
      const cov = st + b.readUInt16BE(st + 2), nset = b.readUInt16BE(st + 4);
      for (let p = 0; p < gids.length; p++) {
        const ci = coverageIndex(b, cov, gids[p]); if (ci < 0 || ci >= nset) continue;
        const set = st + b.readUInt16BE(st + 6 + 2 * ci), nlig = b.readUInt16BE(set);
        for (let k = 0; k < nlig; k++) {
          const lg = set + b.readUInt16BE(set + 2 + 2 * k), nc = b.readUInt16BE(lg + 2);
          let ok = p + nc <= gids.length;
          for (let c = 1; ok && c < nc; c++) if (b.readUInt16BE(lg + 2 + 2 * c) !== gids[p + c]) ok = false;
          if (ok) { gids = [...gids.slice(0, p), b.readUInt16BE(lg), ...gids.slice(p + nc)]; break; }
        }
      }
    }
  }
  return gids;
}
/** Renders the shaped glyphs (pen starting at ox, baseline oy) into straight RGBA w*h. */
function renderOurs(glyphs, size, w, h, ox, oy) {
  const acc = new Float32Array(w * h * 4); // premul accumulation (src-over)
  let x = ox;
  const kinds = [];
  for (const g of glyphs) {
    const p = X.cf_render(g.gid, size, w, h, x, oy, 0, 0xff000000);
    kinds.push(new Float32Array(X.memory.buffer, X.cf_info(), 8)[0]);
    if (p) {
      const px = new Uint8Array(X.memory.buffer, p, w * h * 4);
      for (let i = 0; i < w * h * 4; i += 4) {
        const a = px[i + 3] / 255; if (!a) continue;
        const k = 1 - a;
        for (let c = 0; c < 3; c++) acc[i + c] = px[i + c] * a + acc[i + c] * k;
        acc[i + 3] = a * 255 + acc[i + 3] * k;
      }
    }
    x += g.adv;
  }
  const out = new Uint8Array(w * h * 4);
  for (let i = 0; i < out.length; i += 4) {
    const a = acc[i + 3]; if (a <= 0) continue;
    for (let c = 0; c < 3; c++) out[i + c] = Math.min(255, Math.round(acc[i + c] * 255 / a));
    out[i + 3] = Math.round(a);
  }
  return { rgba: out, kinds };
}
const KIND = ["none", "colr_v0", "colr_v1", "bitmap_png", "bitmap_other"];

function shift(src, w, h, dx, dy) {
  const out = new Uint8Array(src.length);
  for (let y = 0; y < h; y++) {
    const sy = y - dy; if (sy < 0 || sy >= h) continue;
    for (let x = 0; x < w; x++) {
      const sx = x - dx; if (sx < 0 || sx >= w) continue;
      const si = (sy * w + sx) * 4, di = (y * w + x) * 4;
      out[di] = src[si]; out[di + 1] = src[si + 1]; out[di + 2] = src[si + 2]; out[di + 3] = src[si + 3];
    }
  }
  return out;
}
function alphaDiff(a, b) { let s = 0; for (let i = 3; i < a.length; i += 4) s += Math.abs(a[i] - b[i]); return s; }
function centroid(a, w, h) {
  let sx = 0, sy = 0, s = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const v = a[(y * w + x) * 4 + 3]; sx += v * x; sy += v * y; s += v; }
  return s ? [sx / s, sy / s] : [0, 0];
}
function bestAlign(ours, ref, w, h, r = 3) {
  const co = centroid(ours, w, h), cr = centroid(ref, w, h);
  const bx = Math.round(cr[0] - co[0]), by = Math.round(cr[1] - co[1]);
  let best = { dx: 0, dy: 0, d: Infinity };
  for (let dy = by - r; dy <= by + r; dy++) for (let dx = bx - r; dx <= bx + r; dx++) {
    const d = alphaDiff(shift(ours, w, h, dx, dy), ref);
    if (d < best.d) best = { dx, dy, d };
  }
  return best;
}
function savePng(file, rgba, w, h) {
  const png = new PNG({ width: w, height: h }); png.data = Buffer.from(rgba); writeFileSync(file, PNG.sync.write(png));
}

// ---- references
let tk = null, browser = null, page = null;
async function takumiRender(fontName, text, size, w, h) {
  const node = { type: "container", style: { width: "100%", height: "100%", display: "flex" },
    children: [{ type: "text", text, style: { fontSize: size, fontFamily: fontName, color: "#000", lineHeight: 1.4 } }] };
  const raw = await tk.render(node, { width: w, height: h, format: "raw" });
  return new Uint8Array(raw.buffer, raw.byteOffset, w * h * 4).slice();
}
async function chromeRender(file, text, size, w, h, vars) {
  if (!browser) {
    const puppeteer = (await import("puppeteer-core")).default;
    const exe = [process.env.BROWSER_PATH, "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
      "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"].find((p) => p && existsSync(p));
    browser = await puppeteer.launch({ executablePath: exe, headless: true, args: ["--no-first-run", "--allow-file-access-from-files", "--disable-lcd-text", "--force-device-scale-factor=1"] });
    page = await browser.newPage();
    console.log("chrome:", await browser.version());
  }
  await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
  const html = `<!doctype html><style>@font-face{font-family:T;src:url("${pathToFileURL(file).href}")}
    html,body{margin:0;background:transparent}#t{position:absolute;left:0;top:0;font:${size}px/1.4 T;color:#000;white-space:pre;font-variation-settings:${vars ? vars.map(([t, x]) => `"${t}" ${x}`).join(",") : "normal"}}</style><div id=t>${text}</div>`;
  const hp = path.join(path.dirname(file), "_oracle.html");
  writeFileSync(hp, html);
  await page.goto(pathToFileURL(hp).href);
  await page.evaluate(() => document.fonts.ready);
  const buf = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } });
  return new Uint8Array(PNG.sync.read(Buffer.from(buf)).data);
}

// ---- run
const summary = {};
for (const c of cases) {
  const bytes = readFileSync(c.file);
  loadFont(bytes);
  F = bytes;
  if (c.vars) {
    const v = new Uint32Array(c.vars.flatMap(([t, x]) => [Buffer.from(t, "latin1").readUInt32BE(0), new Uint32Array(new Float32Array([x]).buffer)[0]]));
    const vp = X.cf_alloc(v.byteLength);
    mem().set(new Uint8Array(v.buffer), vp);
    X.cf_set_var(vp, c.vars.length);
  }
  const upem = X.cf_upem();
  const asc = bytes.readInt16BE(findTable(bytes, "hhea") + 4);
  if (c.ref === "takumi" && !tk) tk = await takumi.create();
  const fname = "CF_" + c.id;
  if (c.ref === "takumi") await tk.registerFont({ name: fname, data: bytes });
  const rows = [];
  for (const size of SIZES) {
    for (const text of c.texts) {
      const glyphs = shape(text, size);
      const W = Math.ceil(size * (glyphs.length > 1 ? glyphs.length * 1.3 : 1.6)), H = Math.ceil(size * 1.6);
      const oy = Math.round(asc * size / upem);
      const { rgba: ours, kinds } = renderOurs(glyphs, size, W, H, 0, oy);
      const ref = c.ref === "takumi" ? await takumiRender(fname, text, size, W, H) : await chromeRender(c.file, text, size, W, H, c.vars);
      const al = bestAlign(ours, ref, W, H);
      const aligned = shift(ours, W, H, al.dx, al.dy);
      const m = compare(aligned, ref, W, H);
      const row = { text, size, glyphs: glyphs.map((g) => g.gid).join("+"), kind: kinds.map((k) => KIND[k]).join("+"), dx: al.dx, dy: al.dy,
        ssim: +m.ssim.toFixed(4), ssimRgb: +m.ssimRgb.toFixed(4), meanAbs: +m.meanAbs.toFixed(3), pctAA: +m.pctAA.toFixed(2) };
      rows.push(row);
      if (outDir) {
        const tag = `${c.id}_${size}_${[...text].map((ch) => ch.codePointAt(0).toString(16)).join("-")}`;
        savePng(path.join(outDir, tag + "_ours.png"), aligned, W, H);
        savePng(path.join(outDir, tag + "_ref.png"), ref, W, H);
      }
    }
  }
  console.log(`\n== ${c.id} (${path.basename(c.file)}) vs ${c.ref}`);
  console.table(rows);
  const avg = (k) => rows.reduce((s, r) => s + r[k], 0) / rows.length;
  summary[c.id] = { ref: c.ref, n: rows.length, ssim: +avg("ssim").toFixed(4), ssimRgb: +avg("ssimRgb").toFixed(4), meanAbs: +avg("meanAbs").toFixed(3), minSsim: Math.min(...rows.map((r) => r.ssim)) };
}
console.log("\nSUMMARY");
console.table(summary);
if (browser) await browser.close();
if (tk) tk.dispose();

function findTable(b, tag) {
  const n = b.readUInt16BE(4);
  for (let i = 0; i < n; i++) if (b.toString("latin1", 12 + i * 16, 16 + i * 16) === tag) return b.readUInt32BE(12 + i * 16 + 8);
  return 0;
}
