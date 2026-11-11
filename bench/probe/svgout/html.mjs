// SVG output probe over takumi's own HTML fixtures (ref/takumi/takumi/tests/fixtures-html, read as
// data only): renders each fixture body (+ its <style>) with takumi renderSvg (oracle 2.20) and
// with bm's svg_out, rasterises BOTH with takumi and compares; also compares our SVG with our own
// raster render. Fonts: the @font-face files of tests/shared.css (Geist first = fallback).
//
//   node probe/svgout/html.mjs [filter] [--wasm path] [--save] [--all]
//
// Without --all only the rows where our SVG and takumi's SVG disagree MORE than takumi's SVG and
// our raster disagree (i.e. likely SVG-output problems, not layout differences) are printed.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from "node:fs";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { compare, verdict } from "../../lib/metrics.mjs";
import { encodePng } from "../../lib/pipeline.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const REF = path.resolve(here, "..", "..", "..", "ref", "takumi");
const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); if (i < 0) return def; const v = args[i + 1]; args.splice(i, 2); return v; };
const flag = (name) => { const i = args.indexOf(name); if (i < 0) return false; args.splice(i, 1); return true; };
const SCRATCH = "C:/Users/admini/AppData/Local/Temp/claude/46c8b6142d3c6b7e/eb762129-eac5-46a2-aaef-1b224d61f7d8/scratchpad/svgout";
const wasmPath = opt("--wasm", process.env.SVGOUT_WASM || path.join(SCRATCH, "svgtest.wasm"));
const outDir = opt("--out", path.join(SCRATCH, "html"));
const save = flag("--save");
const all = flag("--all");
const filter = args[0];

// fonts from shared.css
const css = readFileSync(path.join(REF, "takumi", "tests", "shared.css"), "utf8");
const fonts = [];
for (const m of css.matchAll(/@font-face\s*{([^}]*)}/g)) {
  const fam = /font-family:\s*"?([^";]+)"?;/.exec(m[1]); const src = /url\("([^"]+)"\)/.exec(m[1]);
  if (!fam || !src) continue;
  const file = path.resolve(REF, "takumi", "tests", src[1]);
  if (existsSync(file)) fonts.push({ name: fam[1].trim(), path: file });
}

// ---------------------------------------------------------------- bm
const enc = new TextEncoder(), dec = new TextDecoder();
const W = new WebAssembly.Instance(new WebAssembly.Module(readFileSync(wasmPath)), {}).exports;
const mem = () => new Uint8Array(W.memory.buffer);
function copyIn(bytes) { const p = W.bm_alloc(bytes.length || 1); mem().set(bytes, p); return [p, bytes.length]; }
const str = (s) => copyIn(enc.encode(s));
const R = W.bm_renderer_new();
for (const f of fonts) {
  const [p, n] = copyIn(new Uint8Array(readFileSync(f.path))); const [np, nn] = str(f.name);
  if (W.bm_register_font(R, p, n, np, nn, 0, -1)) console.error("bm font failed", f.name);
}
const result = () => { const p = W.bm_result_ptr(R), n = W.bm_result_len(R); return mem().slice(p, p + n); };
function bm(fn, html, o) {
  W.bm_clear_images(R);
  const [sp, sn] = str(html); const [op, on] = str(JSON.stringify(o));
  const t0 = performance.now();
  const st = fn(R, 1, sp, sn, op, on);
  const ms = performance.now() - t0;
  if (st) { const p = W.bm_svg_err_ptr(R), n = W.bm_svg_err_len(R); throw new Error("bm: " + dec.decode(mem().slice(p, p + n))); }
  return { out: result(), ms };
}

// ---------------------------------------------------------------- takumi
const pkg = path.resolve(here, "..", "..", "node_modules", "@takumi-rs", "wasm");
const tmod = await import(pathToFileURL(path.join(pkg, "dist", "export.mjs")).href);
tmod.initSync({ module: readFileSync(path.join(pkg, "pkg", "takumi_wasm_bg.wasm")) });
const T = new tmod.Renderer();
for (const f of fonts) { try { await T.registerFont({ name: f.name, data: readFileSync(f.path) }); } catch (e) { console.error("takumi font failed", f.name); } }
async function rasterise(svg, w, h) {
  const raw = await T.render({ type: "image", src: svg, style: { width: w, height: h } }, { width: w, height: h, format: "raw" });
  return raw instanceof Uint8Array ? raw : new Uint8Array(raw);
}

// ---------------------------------------------------------------- run
const sec = (s, a, b) => { const i = s.indexOf(a); if (i < 0) return null; const r = s.slice(i + a.length); const j = r.indexOf(b); return j < 0 ? null : r.slice(0, j); };
const dir = path.join(REF, "takumi", "tests", "fixtures-html");
const files = readdirSync(dir).filter((f) => f.endsWith(".html") && (!filter || new RegExp(filter, "i").test(f))).sort();
const rows = [];
const r4 = (v) => +v.toFixed(4);
for (const file of files) {
  const id = file.replace(/\.html$/, "");
  const html = readFileSync(path.join(dir, file), "utf8");
  const row = { id };
  try {
    const bodyTag = sec(html, "<body", "</body>"); if (!bodyTag) throw new Error("no body");
    const body = bodyTag.slice(bodyTag.indexOf(">") + 1).trim();
    const bstyle = sec(html, '<body style="', '"') ?? "";
    const px = (p) => { const m = new RegExp("(?:^|;)\\s*" + p + "\\s*:\\s*([0-9.]+)px").exec(bstyle); if (!m) throw new Error("no body " + p); return +m[1]; };
    const dprm = sec(html, '<meta name="takumi-device-pixel-ratio" content="', '"');
    const dpr = dprm ? +dprm : 1;
    const w = Math.round(px("width") * dpr), h = Math.round(px("height") * dpr);
    const style = sec(html, "<style>", "</style>") ?? "";
    const src = (style ? `<style>${style}</style>` : "") + body;
    const o = { width: w, height: h, devicePixelRatio: dpr };
    const t0 = performance.now();
    const tsvg = await T.renderSvg(src, o);
    row.tMs = r4(performance.now() - t0);
    const b = bm(W.bm_render_svg, src, o);
    const bsvg = dec.decode(b.out); row.bMs = r4(b.ms);
    row.tBytes = tsvg.length; row.bBytes = bsvg.length;
    const tr = await rasterise(tsvg, w, h);
    const br = await rasterise(bsvg, w, h);
    const own = bm(W.bm_render_src, src, { ...o, format: "raw" }).out;
    const m = compare(tr, br, w, h, { diff: save });
    row.ssim = r4(Math.min(m.ssim, m.ssimRgb)); row.pct = r4(m.pctStrict); row.verdict = verdict(m);
    const mo = compare(own, br, w, h); row.vsOwn = r4(Math.min(mo.ssim, mo.ssimRgb));
    const mt = compare(own, tr, w, h); row.tVsOwn = r4(Math.min(mt.ssim, mt.ssimRgb));
    if (save) {
      const d = path.join(outDir, id); mkdirSync(d, { recursive: true });
      writeFileSync(path.join(d, "takumi.svg"), tsvg); writeFileSync(path.join(d, "bm.svg"), bsvg);
      writeFileSync(path.join(d, "takumi.png"), encodePng(tr, w, h)); writeFileSync(path.join(d, "bm.png"), encodePng(br, w, h));
      writeFileSync(path.join(d, "own.png"), encodePng(own, w, h));
      if (m.diff) writeFileSync(path.join(d, "diff.png"), encodePng(m.diff, w, h));
    }
  } catch (e) { row.error = String(e.message ?? e).split("\n")[0].slice(0, 160); }
  rows.push(row);
  // suspicious = our SVG is further from our own raster than takumi's SVG is
  const suspicious = row.error || (row.verdict && row.verdict !== "identical" && row.verdict !== "equivalent" && row.vsOwn < Math.max(0.995, row.tVsOwn));
  if (all || suspicious) console.log([id.padEnd(46), (row.verdict ?? "ERR").padEnd(10), "ssim", row.ssim, "pct", row.pct, "| vsOwn", row.vsOwn, "tVsOwn", row.tVsOwn, "| bytes", row.bBytes, "/", row.tBytes, row.error ?? ""].join(" "));
}
const ok = rows.filter((r) => r.verdict);
const cnt = (v) => ok.filter((r) => r.verdict === v).length;
console.log(`\n${rows.length} fixtures: identical ${cnt("identical")}, equivalent ${cnt("equivalent")}, close ${cnt("close")}, different ${cnt("different")}, errors ${rows.length - ok.length}`);
console.log(`our SVG vs our raster: mean SSIM ${(ok.reduce((a, r) => a + r.vsOwn, 0) / ok.length).toFixed(4)}; takumi SVG vs our raster: ${(ok.reduce((a, r) => a + r.tVsOwn, 0) / ok.length).toFixed(4)}`);
console.log(`bytes bm/takumi total: ${ok.reduce((a, r) => a + r.bBytes, 0)} / ${ok.reduce((a, r) => a + r.tBytes, 0)}; ms bm/takumi total: ${ok.reduce((a, r) => a + r.bMs, 0).toFixed(1)} / ${ok.reduce((a, r) => a + r.tMs, 0).toFixed(1)}`);
