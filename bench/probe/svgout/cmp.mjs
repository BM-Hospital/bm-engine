// SVG output probe: for every benchmark fixture, gets takumi's renderSvg() string (oracle,
// @takumi-rs/wasm 2.20) and ours (bm_render_svg of the engine wasm), RASTERISES BOTH WITH
// TAKUMI ({type:"image", src: svg} at the fixture size, format raw) and compares the bitmaps
// (SSIM, % differing pixels). Sanity: each rasterised SVG is also compared with our own raster
// render of the fixture.
//
//   node probe/svgout/cmp.mjs [filter] [--wasm path] [--out dir] [--save]
//
// --save writes <out>/<id>/{takumi.svg, bm.svg, takumi.png, bm.png, diff.png}.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { ALL_CASES } from "../../fixtures/index.mjs";
import { FONTS } from "../../lib/fonts.mjs";
import { compare, verdict } from "../../lib/metrics.mjs";
import { encodePng } from "../../lib/pipeline.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); if (i < 0) return def; const v = args[i + 1]; args.splice(i, 2); return v; };
const flag = (name) => { const i = args.indexOf(name); if (i < 0) return false; args.splice(i, 1); return true; };
const SCRATCH = "C:/Users/admini/AppData/Local/Temp/claude/46c8b6142d3c6b7e/eb762129-eac5-46a2-aaef-1b224d61f7d8/scratchpad/svgout";
const wasmPath = opt("--wasm", process.env.BM_WASM || process.env.SVGOUT_WASM || path.resolve(here, "..", "..", "..", "zig-out", "bin", "bm_engine.wasm"));
const outDir = opt("--out", path.join(SCRATCH, "out"));
const save = flag("--save");
const json = flag("--json");
const filter = args[0];

// ---------------------------------------------------------------- bm (svg_out test wasm)
const enc = new TextEncoder(), dec = new TextDecoder();
const W = new WebAssembly.Instance(new WebAssembly.Module(readFileSync(wasmPath)), {}).exports;
const mem = () => new Uint8Array(W.memory.buffer);
function copyIn(bytes) { const p = W.bm_alloc(bytes.length || 1); mem().set(bytes, p); return [p, bytes.length]; }
function str(s) { return copyIn(enc.encode(s)); }
const R = W.bm_renderer_new();
for (const f of FONTS) {
  const [p, n] = copyIn(new Uint8Array(readFileSync(f.path)));
  const [np, nn] = str(f.name);
  if (W.bm_register_font(R, p, n, np, nn, f.weight, f.style === "italic" ? 1 : 0)) throw new Error("font " + f.file);
}
function putImages(k) {
  W.bm_clear_images(R);
  for (const im of k.images ?? []) {
    const [sp, sn] = str(im.src); const [dp, dn] = copyIn(new Uint8Array(im.data));
    W.bm_put_image(R, sp, sn, dp, dn);
  }
}
function source(k) { return typeof k.node === "string" ? [1, k.node] : [0, JSON.stringify(k.node)]; }
function optsJson(k, format) { const o = { width: k.width, height: k.height, format, devicePixelRatio: 1, ...(k.opts ?? {}) }; return JSON.stringify(o); }
function result() { const p = W.bm_result_ptr(R), n = W.bm_result_len(R); return mem().slice(p, p + n); }
function bmSvg(k) {
  putImages(k);
  const [kind, text] = source(k);
  const [sp, sn] = str(text); const [op, on] = str(optsJson(k, "raw"));
  const t0 = performance.now();
  const st = W.bm_render_svg(R, kind, sp, sn, op, on);
  const ms = performance.now() - t0;
  if (st) { const p = W.bm_last_error_ptr(), n = W.bm_last_error_len(); throw new Error("bm svg: " + dec.decode(mem().slice(p, p + n))); }
  return { svg: dec.decode(result()), ms };
}
function bmRaster(k) {
  putImages(k);
  const [kind, text] = source(k);
  const [sp, sn] = str(text); const [op, on] = str(optsJson(k, "raw"));
  if (W.bm_render_src(R, kind, sp, sn, op, on)) throw new Error("bm raster failed");
  return result();
}

// ---------------------------------------------------------------- takumi
const pkg = path.resolve(here, "..", "..", "node_modules", "@takumi-rs", "wasm");
const tmod = await import(pathToFileURL(path.join(pkg, "dist", "export.mjs")).href);
tmod.initSync({ module: readFileSync(path.join(pkg, "pkg", "takumi_wasm_bg.wasm")) });
const T = new tmod.Renderer();
for (const f of FONTS) await T.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });
const tOpts = (k, extra = {}) => ({ width: k.width, height: k.height, devicePixelRatio: 1, ...(k.images ? { images: k.images } : {}), ...(k.opts ?? {}), ...extra });
async function takumiSvg(k) { const t0 = performance.now(); const svg = await T.renderSvg(k.node, tOpts(k)); return { svg, ms: performance.now() - t0 }; }
async function rasterise(svg, k) {
  const node = { type: "image", src: svg, style: { width: k.width, height: k.height } };
  const raw = await T.render(node, { width: k.width, height: k.height, format: "raw" });
  return raw instanceof Uint8Array ? raw : new Uint8Array(raw);
}

// ---------------------------------------------------------------- run
const cases = ALL_CASES.filter((k) => !filter || new RegExp(filter, "i").test(k.id) || new RegExp(filter, "i").test(k.feature));
const rows = [];
const r4 = (v) => (typeof v === "number" ? +v.toFixed(4) : v);
for (const k of cases) {
  const row = { id: k.id, feature: k.feature };
  try {
    const t = await takumiSvg(k);
    const b = bmSvg(k);
    row.tBytes = t.svg.length; row.bBytes = b.svg.length; row.tMs = r4(t.ms); row.bMs = r4(b.ms);
    const tr = await rasterise(t.svg, k);
    let br;
    try { br = await rasterise(b.svg, k); } catch (e) { throw new Error("rasterising bm svg: " + String(e.message ?? e).slice(0, 200)); }
    const m = compare(tr, br, k.width, k.height, { diff: save });
    row.ssim = r4(Math.min(m.ssim, m.ssimRgb)); row.pct = r4(m.pctStrict); row.verdict = verdict(m);
    const own = bmRaster(k);
    const ms = compare(own, br, k.width, k.height);
    row.vsOwn = r4(Math.min(ms.ssim, ms.ssimRgb)); row.vsOwnPct = r4(ms.pctStrict);
    const mt = compare(own, tr, k.width, k.height);
    row.tVsOwn = r4(Math.min(mt.ssim, mt.ssimRgb));
    if (save) {
      const d = path.join(outDir, k.id); mkdirSync(d, { recursive: true });
      writeFileSync(path.join(d, "takumi.svg"), t.svg); writeFileSync(path.join(d, "bm.svg"), b.svg);
      writeFileSync(path.join(d, "takumi.png"), encodePng(tr, k.width, k.height));
      writeFileSync(path.join(d, "bm.png"), encodePng(br, k.width, k.height));
      writeFileSync(path.join(d, "own.png"), encodePng(own, k.width, k.height));
      if (m.diff) writeFileSync(path.join(d, "diff.png"), encodePng(m.diff, k.width, k.height));
    }
  } catch (e) { row.error = String(e.message ?? e).split("\n")[0].slice(0, 200); }
  rows.push(row);
  if (!json) console.log([row.id.padEnd(34), (row.verdict ?? "ERR").padEnd(10), "ssim", row.ssim, "pct", row.pct, "| vsOwn", row.vsOwn, "tVsOwn", row.tVsOwn, "| bytes", row.bBytes, "/", row.tBytes, "| ms", row.bMs, "/", row.tMs, row.error ?? ""].join(" "));
}
if (json) console.log(JSON.stringify(rows));
const ok = rows.filter((r) => r.verdict);
const byFeature = {};
for (const r of ok) { (byFeature[r.feature] ??= []).push(r); }
console.log("\nfeature            n   meanSSIM  minSSIM  meanPct  identical/equiv/close/diff");
for (const [f, rs] of Object.entries(byFeature)) {
  const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;
  const cnt = (v) => rs.filter((r) => r.verdict === v).length;
  console.log(f.padEnd(18), String(rs.length).padStart(2), " ", mean(rs.map((r) => r.ssim)).toFixed(4), "  ", Math.min(...rs.map((r) => r.ssim)).toFixed(4), "  ", mean(rs.map((r) => r.pct)).toFixed(3).padStart(7), "  ", [cnt("identical"), cnt("equivalent"), cnt("close"), cnt("different")].join("/"));
}
console.log("errors:", rows.filter((r) => r.error).map((r) => r.id + ": " + r.error).join("\n  ") || "none");
