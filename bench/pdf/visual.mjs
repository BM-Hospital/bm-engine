// Visual equivalence of bm-engine's PDFs, headless, as a gate.
//
//   node bench/pdf/visual.mjs [--rebuild] [--filter=<regex>] [--rasterisers=pdfium,mupdf] [--dpi=96,144]
//                             [--max-pages=6] [--worst=16] [--gate=different|none]
//
// 1. bm vs takumi-pdf: every page of bm-native's PDF and of takumi-pdf's PDF of the same input is rasterised by the
//    SAME rasteriser at the same dpi and compared with the image suite's metrics (bench/lib/metrics.mjs): identical /
//    equivalent (SSIM >= 0.99 and <= 0.5 % pixels differ) / close (SSIM >= 0.95, <= 5 %) / different. Each
//    rasteriser gives its own verdict; a page whose verdict depends on the rasteriser is flagged (a difference only
//    one rasteriser sees is likely its artefact).
// 2. PDF vs image: for the single-page (viewport) documents, bm's PDF rasterised at 96 dpi (1 px per CSS px) is
//    compared with bm's own PNG render of the same tree at the viewport size (expect anti-aliasing differences).
// Writes bench/out/pdf/visual.json, bench/out/pdf/VISUAL.md, side-by-side sheets of every document's first page
// (bench/out/pdf/visual/sheets/<doc>.png: bm | takumi-pdf | diff) and full-size diff images of the worst pages
// (bench/out/pdf/visual/worst/). Exit 1 when a page is "different" under every rasteriser (gate=different).
import { mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { OUT_DIR, ROOT, PDF_DIR } from "./lib/tools.mjs";
import { corpusBuild, fileOf } from "./lib/build.mjs";
import { rasterise, pageCountOf, RASTERISERS } from "./lib/raster.mjs";
import { compare, verdict } from "../lib/metrics.mjs";
import { loadCorpus, EnginePool, inputs } from "./corpus/index.mjs";

const require = createRequire(path.join(PDF_DIR, "package.json"));
const { PNG } = require("pngjs");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const rasterisers = String(args.rasterisers ?? "pdfium,mupdf").split(",").filter((r) => RASTERISERS.includes(r));
const dpis = String(args.dpi ?? "96,144").split(",").map(Number);
const maxPages = +(args["max-pages"] ?? 6);
const worstN = +(args.worst ?? 16);
const gate = String(args.gate ?? "different");
const log = (...a) => console.error(...a);
const T0 = performance.now();
const VDIR = path.join(OUT_DIR, "visual");
rmSync(VDIR, { recursive: true, force: true });
mkdirSync(path.join(VDIR, "sheets"), { recursive: true }); mkdirSync(path.join(VDIR, "worst"), { recursive: true });

const filter = args.filter ? String(args.filter) : null;
const manifest = await corpusBuild({ rebuild: !!args.rebuild, filter, maxStress: +(args["max-stress"] ?? 500), log });
const BM = manifest.engines.includes("bm-native") ? "bm-native" : "bm-wasm";
const ORDER = ["identical", "equivalent", "close", "different"];
const worse = (a, b) => (ORDER.indexOf(a) >= ORDER.indexOf(b) ? a : b);

/** Crops two rasters to their common size (rasterisers may round a page's pixel size differently). */
function common(a, b) {
  if (a.width === b.width && a.height === b.height) return [a.rgba, b.rgba, a.width, a.height];
  const w = Math.min(a.width, b.width), h = Math.min(a.height, b.height);
  const crop = (r) => { const o = new Uint8Array(w * h * 4); for (let y = 0; y < h; y++) o.set(r.rgba.subarray(y * r.width * 4, y * r.width * 4 + w * 4), y * w * 4); return o; };
  return [crop(a), crop(b), w, h];
}
const pngOf = (rgba, w, h) => { const p = new PNG({ width: w, height: h }); p.data = Buffer.from(rgba.buffer, rgba.byteOffset, rgba.byteLength); return PNG.sync.write(p); };
function scaleDown(rgba, w, h, maxW) {
  const f = Math.max(1, Math.ceil(w / maxW)); const W = Math.floor(w / f), H = Math.floor(h / f); const o = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) for (let c = 0; c < 4; c++) { let s = 0; for (let dy = 0; dy < f; dy++) for (let dx = 0; dx < f; dx++) s += rgba[((y * f + dy) * w + x * f + dx) * 4 + c]; o[(y * W + x) * 4 + c] = Math.round(s / (f * f)); }
  return { rgba: o, w: W, h: H };
}
function sideBySide(panels, gap = 8) {
  const W = panels.reduce((s, p) => s + p.w, 0) + gap * (panels.length - 1), H = Math.max(...panels.map((p) => p.h));
  const o = new Uint8Array(W * H * 4).fill(200);
  let x0 = 0;
  for (const p of panels) { for (let y = 0; y < p.h; y++) o.set(p.rgba.subarray(y * p.w * 4, (y + 1) * p.w * 4), (y * W + x0) * 4); x0 += p.w + gap; }
  return { rgba: o, w: W, h: H };
}
const diffPanel = (d, w, h) => { const o = new Uint8Array(d); for (let i = 3; i < o.length; i += 4) o[i] = 255; return { rgba: o, w, h }; };
const safe = (id) => id.replace(/[\/\\]/g, "__");

// ------------------------------------------------------------------------------------------------ 1. bm vs takumi-pdf
const rows = [];
const worst = [];
let k = 0;
for (const d of manifest.docs) {
  k++;
  const a = d.engines[BM], b = d.engines["takumi-pdf"];
  if (!a?.ok || !b?.ok) { rows.push({ id: d.id, skipped: `render error: ${!a?.ok ? BM + " " + a?.error : "takumi-pdf " + b?.error}` }); continue; }
  const A = new Uint8Array(readFileSync(fileOf(BM, d.id))), B = new Uint8Array(readFileSync(fileOf("takumi-pdf", d.id)));
  const row = { id: d.id, group: d.group, pages: {}, verdict: {}, rasteriserDependent: [] };
  for (const r of rasterisers) {
    const na = await pageCountOf(r, A), nb = await pageCountOf(r, B);
    row.pages[r] = { bm: na, takumi: nb };
    const n = Math.min(na, nb, maxPages);
    for (const dpi of dpis) {
      for (let p = 0; p < n; p++) {
        const ra = await rasterise(r, A, p, dpi), rb = await rasterise(r, B, p, dpi);
        const [x, y, w, h] = common(ra, rb);
        const m = compare(x, y, w, h, { diff: true });
        const v = verdict(m);
        const cell = { r, dpi, page: p + 1, verdict: v, ssim: +m.ssim.toFixed(5), ssimRgb: +m.ssimRgb.toFixed(5), pctStrict: +m.pctStrict.toFixed(3), pctAA: +m.pctAA.toFixed(3), maxAbs: m.maxAbs, psnr: +m.psnr.toFixed(2), size: [ra.width, ra.height, rb.width, rb.height] };
        (row.cells ??= []).push(cell);
        row.verdict[r] = worse(row.verdict[r] ?? "identical", v);
        const score = (1 - Math.min(m.ssim, m.ssimRgb)) * 100 + m.pctStrict;
        if (v !== "identical" && v !== "equivalent") worst.push({ id: d.id, score, cell, a: { rgba: x, w, h }, b: { rgba: y, w, h }, diff: m.diff });
        // first page at the first dpi with the first rasteriser: the contact sheet panel
        if (p === 0 && dpi === dpis[0] && r === rasterisers[0]) {
          const pa = scaleDown(x, w, h, 360), pb = scaleDown(y, w, h, 360), pd = scaleDown(diffPanel(m.diff, w, h).rgba, w, h, 360);
          const s = sideBySide([{ rgba: pa.rgba, w: pa.w, h: pa.h }, { rgba: pb.rgba, w: pb.w, h: pb.h }, { rgba: pd.rgba, w: pd.w, h: pd.h }]);
          writeFileSync(path.join(VDIR, "sheets", safe(d.id) + ".png"), pngOf(s.rgba, s.w, s.h));
        }
      }
    }
    if (na !== nb) row.pageCountDiffers = true;
    // keep memory bounded: drop the heavy buffers of all but the worst candidates
    worst.sort((u, v) => v.score - u.score); worst.length = Math.min(worst.length, worstN);
  }
  // rasteriser agreement per (dpi, page)
  const byKey = new Map();
  for (const c of row.cells ?? []) { const key = `${c.dpi}/${c.page}`; if (!byKey.has(key)) byKey.set(key, new Set()); byKey.get(key).add(c.verdict); }
  for (const [key, set] of byKey) if (set.size > 1) row.rasteriserDependent.push(`${key}: ${[...set].join("/")}`);
  row.overall = Object.values(row.verdict).reduce(worse, "identical");
  row.consensus = Object.values(row.verdict).reduce((x, v) => (ORDER.indexOf(v) < ORDER.indexOf(x) ? v : x), "different"); // the best verdict any rasteriser gives
  rows.push(row);
  log(`  [${k}/${manifest.docs.length}] ${d.id.padEnd(44)} ${rasterisers.map((r) => `${r} ${row.verdict[r]}`).join(", ")}${row.rasteriserDependent.length ? " (rasteriser-dependent)" : ""}`);
}
for (const [i, w] of worst.entries()) {
  const s = sideBySide([w.a, w.b, diffPanel(w.diff, w.a.w, w.a.h)]);
  const name = `${String(i + 1).padStart(2, "0")}-${safe(w.id)}-p${w.cell.page}-${w.cell.r}-${w.cell.dpi}dpi.png`;
  writeFileSync(path.join(VDIR, "worst", name), pngOf(s.rgba, s.w, s.h));
  w.file = path.relative(ROOT, path.join(VDIR, "worst", name)).split(path.sep).join("/");
}

// ------------------------------------------------------------------------------------------------ 2. PDF vs image (bm)
const imageRows = [];
if (!args["no-image"]) {
  const { docs } = await loadCorpus({ filter, maxStress: 1 });
  const pool = new EnginePool({ keep: 1 });
  for (const doc of docs.filter((x) => x.viewport)) {
    const m = manifest.docs.find((x) => x.id === doc.id);
    if (!m?.engines[BM]?.ok) continue;
    const A = new Uint8Array(readFileSync(fileOf(BM, doc.id)));
    const { e, families } = await pool.get(BM, doc.fonts);
    const { source, options } = inputs(doc, families);
    const rr = await rasterise(rasterisers[0], A, 0, 96);
    const vp = options.viewport;
    const W = vp.width, H = vp.height ?? Math.round(rr.height);
    let img;
    try {
      const { viewport, ...rest } = options;
      const png = await e.renderImage(source, { ...rest, width: W, height: H, format: "png" });
      const p = PNG.sync.read(Buffer.from(png));
      img = { width: p.width, height: p.height, rgba: new Uint8Array(p.data) };
      for (let i = 0; i < img.rgba.length; i += 4) { const al = img.rgba[i + 3] / 255; for (let c = 0; c < 3; c++) img.rgba[i + c] = Math.round(img.rgba[i + c] * al + 255 * (1 - al)); img.rgba[i + 3] = 255; }
    } catch (err) { imageRows.push({ id: doc.id, error: String(err.message || err).slice(0, 200) }); continue; }
    const row = { id: doc.id, size: [W, H], rasters: {} };
    for (const r of rasterisers) {
      const ras = await rasterise(r, A, 0, 96);
      const [x, y, w, h] = common(ras, img);
      const mm = compare(x, y, w, h, { diff: false });
      row.rasters[r] = { verdict: verdict(mm), ssim: +mm.ssim.toFixed(5), pctStrict: +mm.pctStrict.toFixed(3), pctAA: +mm.pctAA.toFixed(3), sizeDelta: [ras.width - img.width, ras.height - img.height] };
    }
    imageRows.push(row);
  }
  pool.dispose();
}

// ------------------------------------------------------------------------------------------------ output
const counts = (list, keyFn) => list.reduce((m, x) => { const v = keyFn(x); if (v) m[v] = (m[v] ?? 0) + 1; return m; }, {});
const done = rows.filter((r) => !r.skipped);
const summary = {
  engines: { bm: BM, reference: "takumi-pdf" }, rasterisers, dpis, maxPages, docs: done.length, skipped: rows.filter((r) => r.skipped).length,
  perRasteriser: Object.fromEntries(rasterisers.map((r) => [r, counts(done, (x) => x.verdict[r])])),
  overall: counts(done, (x) => x.overall), consensus: counts(done, (x) => x.consensus),
  pages: Object.fromEntries(rasterisers.map((r) => [r, counts(done.flatMap((x) => x.cells ?? []).filter((c) => c.r === r), (c) => c.verdict)])),
  rasteriserDependent: done.filter((x) => x.rasteriserDependent.length).map((x) => x.id),
  pdfVsImage: Object.fromEntries(rasterisers.map((r) => [r, counts(imageRows.filter((x) => x.rasters), (x) => x.rasters[r]?.verdict)])),
  pdfVsImageSsim: Object.fromEntries(rasterisers.map((r) => { const s = imageRows.filter((x) => x.rasters).map((x) => x.rasters[r].ssim).sort((p, q) => p - q); return [r, s.length ? { min: s[0], median: s[s.length >> 1], max: s.at(-1) } : null]; })),
  worst: worst.map((w) => ({ id: w.id, ...w.cell, file: w.file })),
};
const out = { date: new Date().toISOString(), build: manifest.date, args: process.argv.slice(2), summary, docs: rows, pdfVsImage: imageRows, seconds: +((performance.now() - T0) / 1000).toFixed(1) };
writeFileSync(path.join(OUT_DIR, "visual.json"), JSON.stringify(out, null, 1));
writeFileSync(path.join(OUT_DIR, "VISUAL.md"), md(out));
const bad = done.filter((x) => x.consensus === "different");
log(`visual: ${done.length} docs; overall ${JSON.stringify(summary.overall)}; consensus ${JSON.stringify(summary.consensus)}; pdf-vs-image ${JSON.stringify(summary.pdfVsImage)}; ${out.seconds} s`);
log(`  wrote ${path.join(OUT_DIR, "visual.json")}, VISUAL.md, visual/sheets/*.png, visual/worst/*.png; gate=${gate}: ${gate === "none" || !bad.length ? "pass" : "FAIL (" + bad.length + " documents different under every rasteriser)"}`);
process.exit(gate !== "none" && bad.length ? 1 : 0);

function md(o) {
  const s = o.summary;
  const L = ["# PDF visual equivalence (bench/pdf/visual.mjs)", "", `Generated ${o.date}; do not edit. ${s.engines.bm} vs ${s.engines.reference}, rasterisers ${s.rasterisers.join(", ")}, ${s.dpis.join(" and ")} dpi, at most ${s.maxPages} pages per document. Verdicts: bench/lib/metrics.mjs (identical / equivalent: SSIM >= 0.99 and <= 0.5 % pixels / close: SSIM >= 0.95 and <= 5 % / different). A document's verdict is its worst page.`, ""];
  L.push("| Rasteriser | identical | equivalent | close | different |", "|:--|--:|--:|--:|--:|");
  for (const r of s.rasterisers) L.push(`| ${r} (documents) | ${s.perRasteriser[r].identical ?? 0} | ${s.perRasteriser[r].equivalent ?? 0} | ${s.perRasteriser[r].close ?? 0} | ${s.perRasteriser[r].different ?? 0} |`);
  for (const r of s.rasterisers) L.push(`| ${r} (pages x dpi) | ${s.pages[r].identical ?? 0} | ${s.pages[r].equivalent ?? 0} | ${s.pages[r].close ?? 0} | ${s.pages[r].different ?? 0} |`);
  L.push(`| best verdict over the rasterisers | ${s.consensus.identical ?? 0} | ${s.consensus.equivalent ?? 0} | ${s.consensus.close ?? 0} | ${s.consensus.different ?? 0} |`);
  L.push("", `Rasteriser-dependent verdicts: ${s.rasteriserDependent.length ? s.rasteriserDependent.map((x) => "`" + x + "`").join(", ") : "none"}.`, "");
  L.push("## Worst pages", "", "| # | Document | page | rasteriser | dpi | verdict | SSIM | SSIM RGB | % px | diff image |", "|--:|:--|--:|:--|--:|:--|--:|--:|--:|:--|");
  s.worst.forEach((w, i) => L.push(`| ${i + 1} | \`${w.id}\` | ${w.page} | ${w.r} | ${w.dpi} | ${w.verdict} | ${w.ssim} | ${w.ssimRgb} | ${w.pctStrict} | ${w.file} |`));
  L.push("", "## bm PDF vs bm image render (viewport documents, 96 dpi)", "", `SSIM: ${Object.entries(s.pdfVsImageSsim).map(([r, v]) => v ? `${r} min ${v.min} / median ${v.median} / max ${v.max}` : r + " —").join("; ")}. Verdicts: ${Object.entries(s.pdfVsImage).map(([r, v]) => `${r} ${JSON.stringify(v)}`).join("; ")}.`, "");
  L.push("| Document | " + s.rasterisers.map((r) => `${r} verdict / SSIM / % px`).join(" | ") + " |", "|:--|" + s.rasterisers.map(() => ":--").join("|") + "|");
  for (const r of o.pdfVsImage) L.push(`| \`${r.id}\` | ` + (r.error ? `error: ${r.error}` : s.rasterisers.map((x) => `${r.rasters[x].verdict} / ${r.rasters[x].ssim} / ${r.rasters[x].pctStrict}`).join(" | ")) + " |");
  L.push("", "## Per document", "", "| Document | " + s.rasterisers.join(" | ") + " | pages bm / takumi | rasteriser-dependent |", "|:--|" + s.rasterisers.map(() => ":--").join("|") + "|:--|:--|");
  for (const r of o.docs) L.push(r.skipped ? `| \`${r.id}\` | ${r.skipped} |` : `| \`${r.id}\` | ${s.rasterisers.map((x) => r.verdict[x]).join(" | ")} | ${r.pages[s.rasterisers[0]].bm} / ${r.pages[s.rasterisers[0]].takumi} | ${r.rasteriserDependent.join("; ")} |`);
  return L.join("\n") + "\n";
}
