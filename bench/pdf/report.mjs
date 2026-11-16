// Tables of the PDF benchmark, generated from results-pdf.json (never typed by hand).
//
//   node bench/pdf/report.mjs [results-pdf.json] [--no-docs]
//       re-renders bench/out/pdf/PDF.md and every `<!-- pdf-bench:<name> -->` ... `<!-- /pdf-bench:<name> -->` block in
//       the docs from the JSON, without measuring anything (bench/pdf/bench.mjs calls renderAll itself).
//
// A doc opts in to a table by containing the two marker comments; the language follows the file (docs/vi/*,
// docs/BENCHMARK.md: Vietnamese; everything else: English). Blocks: env, summary, speed, sizes, scale, cold, memory,
// eventloop, throughput, equiv, noise, per-doc.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const VARIANTS = ["bm-native:sync", "bm-native:async", "bm-wasm:sync", "bm-wasm:async", "takumi-pdf:async"];
const NOISE_LIMIT = 10;
const median = (a) => { const s = a.filter((x) => x != null).sort((x, y) => x - y); return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : null; };
const geomean = (a) => (a.length ? Math.exp(a.reduce((s, x) => s + Math.log(x), 0) / a.length) : null);
const spreadPct = (a) => { const s = a.filter((x) => x != null); if (s.length < 2) return null; const m = median(s); return (100 * (Math.max(...s) - Math.min(...s))) / m; };

/** Combines the speed passes: per-document median of the passes' medians, geomean ratios per pass and overall. */
export function aggregateSpeed(passes) {
  const ids = passes[0]?.cases.map((c) => c.id) ?? [];
  const maps = passes.map((p) => new Map(p.cases.map((c) => [c.id, c])));
  const docs = [];
  for (const id of ids) {
    const c0 = maps[0].get(id);
    const row = { id, group: c0.group, perf: {} };
    for (const v of VARIANTS) {
      const per = maps.map((m) => m.get(id)?.perf?.[v]).filter(Boolean);
      if (!per.length) continue;
      const err = per.find((x) => x.error);
      if (err) { row.perf[v] = { error: err.error }; continue; }
      const meds = per.map((x) => x.median);
      row.perf[v] = { median: +median(meds).toFixed(4), p95: +median(per.map((x) => x.p95)).toFixed(4), min: +Math.min(...per.map((x) => x.min)).toFixed(4), n: per.reduce((s, x) => s + x.n, 0), bytes: per[0].bytes, cpuMs: +median(per.map((x) => x.cpuMs)).toFixed(3), passMedians: meds, spreadPct: spreadPct(meds) == null ? null : +spreadPct(meds).toFixed(1) };
    }
    docs.push(row);
  }
  const ratio = (rows, a, b) => { const r = rows.map((x) => (x.perf[a]?.median > 0 && x.perf[b]?.median > 0 ? x.perf[a].median / x.perf[b].median : null)).filter((x) => x != null); return r.length ? { geomean: +geomean(r).toFixed(3), n: r.length, faster: r.filter((x) => x < 1).length, min: +Math.min(...r).toFixed(3), max: +Math.max(...r).toFixed(3) } : null; };
  const PAIRS = [["bm-native:sync", "takumi-pdf:async"], ["bm-native:async", "takumi-pdf:async"], ["bm-wasm:sync", "takumi-pdf:async"], ["bm-native:sync", "bm-wasm:sync"], ["bm-native:async", "bm-native:sync"]];
  const ratios = {};
  for (const [a, b] of PAIRS) {
    const all = ratio(docs, a, b);
    const perPass = passes.map((p) => ratio(p.cases.map((c) => ({ perf: c.perf })), a, b)?.geomean ?? null);
    ratios[`${a} / ${b}`] = all ? { ...all, perPass, spreadPct: spreadPct(perPass) == null ? null : +spreadPct(perPass).toFixed(1) } : null;
  }
  const abs = {};
  for (const v of VARIANTS) {
    const per = passes.map((p) => { const t = p.cases.map((c) => c.perf[v]?.median).filter((x) => x > 0); return t.length ? +geomean(t).toFixed(3) : null; });
    const all = docs.map((d) => d.perf[v]?.median).filter((x) => x > 0);
    abs[v] = { geomeanMs: all.length ? +geomean(all).toFixed(3) : null, perPass: per, spreadPct: spreadPct(per) == null ? null : +spreadPct(per).toFixed(1) };
  }
  return { passes: passes.map((p) => ({ pass: p.pass, date: p.date, cfg: p.cfg, durationMs: p.durationMs, loadBefore: p.loadBefore, load: p.load })), docs, ratios, abs };
}

// ------------------------------------------------------------------------------------------------ formatting
const L = (lang, en, vi) => (lang === "vi" ? vi : en);
const num = (v, d, lang) => (v == null ? "—" : (+v).toLocaleString(lang === "vi" ? "vi-VN" : "en-US", { minimumFractionDigits: d, maximumFractionDigits: d }));
const ms = (v, lang) => (v == null ? "—" : num(v, v < 10 ? 2 : v < 100 ? 1 : 0, lang));
const x = (v, lang) => (v == null ? "—" : num(v, 2, lang) + "×");
const kib = (b, lang) => (b == null ? "—" : num(b / 1024, b < 10240 ? 1 : 0, lang) + " KiB");
const table = (head, rows) => [`| ${head.join(" | ")} |`, `|${head.map((h, i) => (i === 0 ? ":--" : "--:")).join("|")}|`, ...rows.map((r) => `| ${r.join(" | ")} |`)].join("\n");
const flag = (s) => (s != null && s > NOISE_LIMIT ? " ⚠" : "");

const B = {};
B.env = (res, lang) => {
  const m = res.meta; if (!m) return "";
  const e = m.engines || {};
  const rows = [
    [L(lang, "Machine", "Máy"), `${m.cpu}, ${m.cpus} ${L(lang, "logical CPUs", "CPU logic")}, ${m.totalMemGiB} GiB, ${m.platform}`],
    ["Node.js", `${m.node} (V8 ${m.v8}, libuv ${m.uv})`],
    ["bm-render", `${e["bm-wasm"]?.version ?? "?"}, git \`${(m.git?.commit ?? "").slice(0, 10)}\` (${m.git?.branch}${m.git?.dirtyFiles ? `, ${m.git.dirtyFiles} ${L(lang, "modified files", "file đang sửa")}` : ""})`],
    ["bm-native", e["bm-native"]?.bytes ? `\`${e["bm-native"].file}\`, ${kib(e["bm-native"].bytes, lang)}, sha256 \`${e["bm-native"].sha256?.slice(0, 12)}\`` : L(lang, "not available in this checkout", "không có trong checkout này")],
    ["bm-wasm", `\`${e["bm-wasm"]?.file}\` (profile pdf), ${kib(e["bm-wasm"]?.bytes, lang)}, sha256 \`${e["bm-wasm"]?.sha256?.slice(0, 12)}\``],
    ["takumi-pdf", `npm \`takumi-pdf\` ${e["takumi-pdf"]?.version} (wasm, ${kib(e["takumi-pdf"]?.bytes, lang)}); ${L(lang, "no native build is published", "không có bản native nào được phát hành")}`],
    [L(lang, "Run", "Lần chạy"), `${m.date?.slice(0, 16).replace("T", " ")} UTC, ${m.quick ? "quick" : "full"}, ${m.durationMin} min; ${L(lang, "CPU busy before the run", "CPU bận trước khi chạy")}: ${m.loadAtStart?.meanBusyPct} %`],
  ];
  if (m.partialRuns?.length) rows.push([L(lang, "Partial re-runs", "Chạy lại một phần"), m.partialRuns.map((p) => `${p.date.slice(0, 16).replace("T", " ")} (${p.stages.join(", ")})`).join("; ")]);
  return table([L(lang, "Item", "Mục"), L(lang, "Value", "Giá trị")], rows).replace("|--:|", "|:--|");
};

B.summary = (res, lang) => {
  const out = [];
  const r = res.speed?.ratios;
  if (r) {
    const f = (k) => r[k] ? `${x(r[k].geomean, lang)} [${r[k].perPass.map((v) => x(v, lang)).join(" / ")}] (${L(lang, "faster on", "nhanh hơn ở")} ${r[k].faster}/${r[k].n}, ${x(r[k].min, lang)}–${x(r[k].max, lang)})` : "—";
    out.push(`- **${L(lang, "Render time, bm-native vs takumi-pdf", "Thời gian render, bm-native so với takumi-pdf")}:** sync ${f("bm-native:sync / takumi-pdf:async")}; async ${f("bm-native:async / takumi-pdf:async")}. ${L(lang, "Below 1× = bm takes less time; in brackets the same ratio per pass.", "Dưới 1× = bm tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ ở từng lượt.")}`);
    out.push(`- **bm-wasm vs takumi-pdf (${L(lang, "both wasm", "cả hai là wasm")}):** ${f("bm-wasm:sync / takumi-pdf:async")}. **bm-native vs bm-wasm (sync):** ${f("bm-native:sync / bm-wasm:sync")}.`);
  }
  const sc = res.scale?.runs;
  if (sc) {
    const g = (e, p) => sc.find((y) => y.engine === e && y.pages === p);
    const s = ["bm-native", "bm-wasm", "takumi-pdf"].map((e) => `${e} ${[1, 10, 100, 500].filter((p) => g(e, p)).map((p) => (g(e, p).ok ? `${num(g(e, p).pagesPerSec, 0, lang)}` : L(lang, "error", "lỗi"))).join(" / ")}`).join("; ");
    out.push(`- **${L(lang, "Pages per second at 1 / 10 / 100 / 500 pages", "Trang mỗi giây ở 1 / 10 / 100 / 500 trang")}:** ${s}.`);
  }
  const eq = res.equiv;
  if (eq?.identity) out.push(`- **${L(lang, "Identity", "Trùng byte")}:** bm-native == bm-wasm ${eq.identity.nativeEqualsWasm}/${eq.identity.compared} ${L(lang, "documents", "tài liệu")}${eq.identity.sameError ? `, ${L(lang, "same error on both", "cùng lỗi ở cả hai")}: ${eq.identity.sameError}` : ""}${eq.identity.mismatches.length ? `; ${L(lang, "mismatch", "khác")}: ${eq.identity.mismatches.join(", ")}` : ""}.`);
  if (eq?.validation) { const v = eq.validation.byEngine; out.push(`- **${L(lang, "Validators", "Bộ kiểm tra")}:** bm-native ${v["bm-native"]?.clean ?? "—"}/${v["bm-native"]?.rendered ?? "—"} ${L(lang, "PDFs without any error or warning", "PDF không có lỗi hay cảnh báo nào")} (takumi-pdf ${v["takumi-pdf"]?.clean}/${v["takumi-pdf"]?.rendered}); veraPDF bm-native ${eq.validation.verapdf["bm-native"]?.compliant}/${eq.validation.verapdf["bm-native"]?.runs}, takumi-pdf ${eq.validation.verapdf["takumi-pdf"]?.compliant}/${eq.validation.verapdf["takumi-pdf"]?.runs}; ${L(lang, "same text, links, outline and tags as takumi-pdf", "cùng chữ, liên kết, mục lục và thẻ như takumi-pdf")}: ${eq.validation.semantic.identical}/${eq.validation.semantic.compared}.`); }
  if (eq?.visual) out.push(`- **${L(lang, "Visual verdicts vs takumi-pdf (best over the rasterisers)", "Kết luận hình ảnh so với takumi-pdf (tốt nhất trong các bộ raster)")}:** ${Object.entries(eq.visual.consensus).map(([k, n]) => `${k} ${n}`).join(", ")} (${eq.visual.docs} ${L(lang, "documents", "tài liệu")}, ${eq.visual.rasterisers.join(" + ")}).`);
  const noisy = res.speed ? Object.entries(res.speed.abs).filter(([, v]) => v.spreadPct > NOISE_LIMIT).map(([k, v]) => `${k} ${num(v.spreadPct, 1, lang)} %`) : [];
  if (noisy.length) out.push(`- **${L(lang, "Noise", "Nhiễu")}:** ${L(lang, "absolute geomeans moved between passes by", "geomean tuyệt đối lệch giữa các lượt")} ${noisy.join(", ")} ⚠; ${L(lang, "read the ratios (measured interleaved)", "hãy đọc tỉ lệ (đo xen kẽ)")}.`);
  return out.join("\n");
};

B.speed = (res, lang) => {
  const a = res.speed?.abs; if (!a) return "";
  const rows = VARIANTS.filter((v) => a[v]?.geomeanMs).map((v) => [v, ms(a[v].geomeanMs, lang), a[v].perPass.map((p) => ms(p, lang)).join(" / "), (a[v].spreadPct == null ? "—" : num(a[v].spreadPct, 1, lang) + " %") + flag(a[v].spreadPct)]);
  const rr = Object.entries(res.speed.ratios).filter(([, v]) => v).map(([k, v]) => [k, x(v.geomean, lang), v.perPass.map((p) => x(p, lang)).join(" / "), `${v.faster}/${v.n}`, `${x(v.min, lang)}–${x(v.max, lang)}`, (v.spreadPct == null ? "—" : num(v.spreadPct, 1, lang) + " %") + flag(v.spreadPct)]);
  return table([L(lang, "Variant", "Biến thể"), L(lang, "geomean ms", "geomean ms"), L(lang, "per pass", "từng lượt"), L(lang, "spread", "độ lệch")], rows) + "\n\n" +
    table([L(lang, "Ratio (time)", "Tỉ lệ (thời gian)"), "geomean", L(lang, "per pass", "từng lượt"), L(lang, "faster", "nhanh hơn"), L(lang, "range", "khoảng"), L(lang, "spread", "độ lệch")], rr) + "\n\n" +
    L(lang, `Warm render time per document (fonts registered beforehand, the output kept in memory), ${res.speed.docs.length} documents, ${res.speed.passes.length} pass(es); variants interleaved in rotating order every round.`, `Thời gian render khi đã nóng cho mỗi tài liệu (font đăng ký trước, đầu ra giữ trong bộ nhớ), ${res.speed.docs.length} tài liệu, ${res.speed.passes.length} lượt; các biến thể chạy xen kẽ, đổi thứ tự mỗi vòng.`);
};

B["per-doc"] = (res, lang) => {
  const d = res.speed?.docs; if (!d) return "";
  const c = (row, v) => { const p = row.perf[v]; return p?.median ? `${ms(p.median, lang)} / ${ms(p.p95, lang)}` : p?.error ? L(lang, "error", "lỗi") : "—"; };
  const r = (row, a, b) => (row.perf[a]?.median && row.perf[b]?.median ? x(row.perf[a].median / row.perf[b].median, lang) : "—");
  return table([L(lang, "Document", "Tài liệu"), ...VARIANTS, "bm-n sync / tk", L(lang, "bytes bm / tk", "byte bm / tk")], d.map((row) => [`\`${row.id}\``, ...VARIANTS.map((v) => c(row, v)), r(row, "bm-native:sync", "takumi-pdf:async"), `${row.perf["bm-native:sync"]?.bytes ?? row.perf["bm-wasm:sync"]?.bytes ?? "—"} / ${row.perf["takumi-pdf:async"]?.bytes ?? "—"}`])) + "\n\n" + L(lang, "median / p95 ms.", "median / p95 ms.");
};

B.sizes = (res, lang) => {
  const s = res.sizes; if (!s?.rows) return "";
  const groups = {};
  for (const r of s.rows) {
    const g = (groups[r.group] ??= { n: 0, bmRaw: 0, tkRaw: 0, bmQ: 0, tkQ: 0, ratios: [] });
    const bm = r["bm-native"] ?? r["bm-wasm"], tk = r["takumi-pdf"];
    if (!bm || !tk) continue;
    g.n++; g.bmRaw += bm.raw; g.tkRaw += tk.raw; g.bmQ += bm.qpdf9 ?? 0; g.tkQ += tk.qpdf9 ?? 0; g.ratios.push(bm.raw / tk.raw);
  }
  const rows = Object.entries(groups).map(([k, g]) => [k, g.n, kib(g.bmRaw, lang), kib(g.tkRaw, lang), x(g.bmRaw / g.tkRaw, lang), x(geomean(g.ratios), lang), g.bmQ ? `${kib(g.bmQ, lang)} / ${kib(g.tkQ, lang)} (${x(g.bmQ / g.tkQ, lang)})` : "—"]);
  const big = s.rows.filter((r) => (r["bm-native"] ?? r["bm-wasm"]) && r["takumi-pdf"]).map((r) => ({ id: r.id, q: (r["bm-native"] ?? r["bm-wasm"]).raw / r["takumi-pdf"].raw, bm: (r["bm-native"] ?? r["bm-wasm"]).raw, tk: r["takumi-pdf"].raw })).sort((p, q) => q.q - p.q).slice(0, 6);
  return table([L(lang, "Group", "Nhóm"), L(lang, "docs", "tài liệu"), "bm", "takumi-pdf", L(lang, "total ratio", "tỉ lệ tổng"), L(lang, "geomean ratio", "tỉ lệ geomean"), L(lang, "after the same qpdf recompression", "sau cùng một lần nén lại bằng qpdf")], rows) + "\n\n" +
    L(lang, "Largest bm / takumi-pdf size ratios: ", "Tỉ lệ kích thước bm / takumi-pdf lớn nhất: ") + big.map((b) => `\`${b.id}\` ${x(b.q, lang)} (${kib(b.bm, lang)} / ${kib(b.tk, lang)})`).join(", ") + ".\n\n" +
    L(lang, "Neither engine has a compression setting (both write Flate streams and object streams); the last column re-compresses both engines' files with the same qpdf settings (zlib level 9, object streams).", "Không engine nào có tuỳ chọn nén (cả hai ghi luồng Flate và object stream); cột cuối nén lại file của cả hai engine bằng cùng thiết lập qpdf (zlib mức 9, object stream).");
};

B.scale = (res, lang) => {
  const s = res.scale; if (!s?.runs) return "";
  const engines = [...new Set(s.runs.map((r) => r.engine))];
  const rows = s.pages.map((p) => [String(p), ...engines.flatMap((e) => { const r = s.runs.find((y) => y.engine === e && y.pages === p); return r?.ok ? [`${ms(r.ms, lang)} ms`, num(r.pagesPerSec, 1, lang), kib(r.bytes, lang), `${num(r.after?.peakRssMiB, 0, lang)} MiB`] : [r ? L(lang, "error: ", "lỗi: ") + (r.error ?? "").slice(0, 60) : "—", "", "", r?.after?.peakRssMiB ? `${num(r.after.peakRssMiB, 0, lang)} MiB` : ""]; })]);
  const head = [L(lang, "Pages", "Trang"), ...engines.flatMap((e) => [`${e} ms`, L(lang, "pages/s", "trang/s"), L(lang, "size", "kích thước"), L(lang, "peak RSS", "RSS đỉnh")])];
  const lin = engines.map((e) => { const a = s.runs.find((y) => y.engine === e && y.pages === 10 && y.ok), b = s.runs.find((y) => y.engine === e && y.pages === 100 && y.ok); return a && b ? `${e} ${x(b.ms / a.ms / 10, lang)}` : null; }).filter(Boolean);
  return table(head, rows) + "\n\n" + L(lang, `One render of the stress document (per page: heading, paragraphs, a 14-row table, an image; \`break-after: page\`) in a fresh process per point; warmed with the 1-page document. Super-linearity (time per page at 100 pages / at 10 pages; 1× = linear): ${lin.join(", ")}.`, `Một lần render tài liệu stress (mỗi trang: tiêu đề, đoạn văn, bảng 14 dòng, một ảnh; \`break-after: page\`) trong một tiến trình mới cho mỗi điểm; làm nóng bằng tài liệu 1 trang. Độ siêu tuyến tính (thời gian mỗi trang ở 100 trang / ở 10 trang; 1× = tuyến tính): ${lin.join(", ")}.`);
};

B.cold = (res, lang) => {
  const c = res.cold; if (!c?.engines) return "";
  const rows = Object.entries(c.engines).map(([n, v]) => v.error ? [n, L(lang, "error", "lỗi"), v.error.slice(0, 80), "", "", "", "", ""] : [n === "none" ? L(lang, "empty Node.js", "Node.js trống") : n, ms(v.wallMedianMs, lang), ms(v.wallP95Ms, lang), n === "none" ? "—" : ms(v.overNodeMedianMs, lang), n === "none" ? "—" : ms(v.importMs, lang), n === "none" ? "—" : ms(v.fontMs, lang), n === "none" ? "—" : ms(v.firstRenderMs, lang), `${num(v.maxRssMiB, 0, lang)} MiB`]);
  return table([L(lang, "Engine", "Engine"), L(lang, "wall median ms", "wall median ms"), "p95", L(lang, "over empty Node", "hơn Node trống"), "import", L(lang, "font", "font"), L(lang, "first PDF", "PDF đầu tiên"), L(lang, "peak RSS", "RSS đỉnh")], rows) + "\n\n" +
    L(lang, `${c.runs} runs per engine, interleaved: spawn Node -> import -> register Inter Regular -> one-page A4 invoice -> exit. CPU busy meanwhile ${c.load?.meanBusyPct} %.`, `${c.runs} lần mỗi engine, xen kẽ: khởi động Node -> import -> đăng ký Inter Regular -> hoá đơn A4 một trang -> thoát. CPU bận trong lúc đo ${c.load?.meanBusyPct} %.`);
};

B.memory = (res, lang) => {
  const m = res.memory; if (!m?.engines) return "";
  const sc = res.scale?.runs ?? [];
  const rows = Object.entries(m.engines).map(([e, v]) => { const big = sc.filter((r) => r.engine === e).sort((a, b) => b.pages - a.pages)[0]; return [e, `${num(v.after?.[0]?.rssMiB, 0, lang)} MiB`, `${num(v.after?.at(-1)?.rssMiB, 0, lang)} MiB`, v.after?.[0]?.engineMiB == null ? "—" : `${num(v.after[0].engineMiB, 1, lang)} → ${num(v.after.at(-1).engineMiB, 1, lang)} MiB`, big ? `${big.pages} ${L(lang, "pages", "trang")}: ${num(big.after?.peakRssMiB, 0, lang)} MiB${big.ok ? "" : " (" + L(lang, "failed", "thất bại") + ")"}` : "—"]; });
  return table([L(lang, "Engine", "Engine"), L(lang, "RSS after pass 1", "RSS sau lượt 1"), L(lang, `RSS after pass ${m.passes}`, `RSS sau lượt ${m.passes}`), L(lang, "engine memory (pass 1 → last)", "bộ nhớ engine (lượt 1 → cuối)"), L(lang, "peak RSS, largest stress doc", "RSS đỉnh, tài liệu stress lớn nhất")], rows) + "\n\n" +
    L(lang, `Every guide document (${Object.values(m.engines)[0]?.docs ?? "?"}) rendered ${m.passes} times, GC before each reading; empty Node.js: ${m.emptyNode?.rssMiB} MiB RSS. Engine memory: bm Renderer.memoryBytes (wasm linear memory, or the native addon's live allocation), takumi-pdf wasm memory.`, `Mọi tài liệu hướng dẫn (${Object.values(m.engines)[0]?.docs ?? "?"}) render ${m.passes} lần, GC trước mỗi lần đọc; Node.js trống: ${m.emptyNode?.rssMiB} MiB RSS. Bộ nhớ engine: bm Renderer.memoryBytes (bộ nhớ tuyến tính wasm, hoặc phần cấp phát đang sống của addon native), takumi-pdf: bộ nhớ wasm.`);
};

B.eventloop = (res, lang) => {
  const ev = res.eventloop; if (!ev?.runs) return "";
  return table([L(lang, "Engine", "Engine"), "API", L(lang, "render ms", "render ms"), L(lang, "max timer delay", "độ trễ timer lớn nhất"), "p99", L(lang, "ticks", "số tick")], ev.runs.map((r) => [r.engine, r.api, r.error ? L(lang, "error", "lỗi") : ms(r.ms, lang), `${ms(r.maxDelayMs, lang)} ms`, `${ms(r.p99DelayMs, lang)} ms`, String(r.ticks ?? "—")])) + "\n\n" +
    L(lang, `One ${ev.pages}-page render while a 1 ms interval timer runs; a delay close to the render time means the event loop was blocked for the whole render.`, `Một lần render ${ev.pages} trang trong khi một timer 1 ms chạy; độ trễ gần bằng thời gian render nghĩa là event loop bị chặn suốt lần render.`);
};

B.throughput = (res, lang) => {
  const t = res.throughput; if (!t?.runs) return "";
  const Ns = [1, 2, 4, 8];
  const rows = t.runs.map((r) => [`${r.engine} ${r.mode}${r.mode === "many" || r.mode === "pool" ? " k=" + r.k : ""}${r.engine === "bm-native" ? " uv=" + r.uv : ""}`, ...Ns.map((n) => { const y = (r.results ?? []).find((z) => z.n === n); return y ? num(y.pps, 0, lang) : r.mode === "seq" && n > 1 ? "" : r.error ? L(lang, "error", "lỗi") : "—"; })]);
  return table([L(lang, "Configuration", "Cấu hình"), ...Ns.map((n) => `N=${n}`)], rows) + "\n\n" +
    L(lang, `PDFs per second, ${t.workload}; ${t.msPerPoint} ms per point, ${t.cpus} logical CPUs. seq = one client on the sync API (takumi-pdf: awaited render), many = N clients on K bm-native renderers (async API on the libuv pool, UV_THREADPOOL_SIZE = uv), pool = worker_threads pool of K workers each with its own engine.`, `Số PDF mỗi giây, ${t.workload}; ${t.msPerPoint} ms mỗi điểm, ${t.cpus} CPU logic. seq = một client với API sync (takumi-pdf: await render), many = N client trên K renderer bm-native (API async trên pool libuv, UV_THREADPOOL_SIZE = uv), pool = pool worker_threads gồm K worker, mỗi worker có engine riêng.`);
};

B.equiv = (res, lang) => {
  const e = res.equiv; if (!e) return "";
  const out = [];
  if (e.validation) {
    const v = e.validation;
    out.push(table([L(lang, "Engine", "Engine"), L(lang, "PDFs", "PDF"), L(lang, "clean", "sạch"), L(lang, "errors", "lỗi"), L(lang, "warnings", "cảnh báo"), "bm-only", L(lang, "shared with takumi-pdf", "chung với takumi-pdf"), "veraPDF"], Object.entries(v.byEngine).map(([n, b]) => [n, String(b.rendered), String(b.clean), String(b.errors), String(b.warnings), b.bmOnly ?? "—", b.shared ?? "—", `${v.verapdf[n]?.compliant ?? "—"}/${v.verapdf[n]?.runs ?? "—"}`])));
    out.push("", L(lang, `Validators: qpdf ${v.toolVersions.qpdf}, pdfcpu ${v.toolVersions.pdfcpu} (strict), poppler ${v.toolVersions.poppler} (pdfinfo, pdffonts), MuPDF ${v.toolVersions.mupdf} (wasm), pdf.js ${v.toolVersions.pdfjs}, veraPDF ${v.toolVersions.verapdf}. Semantics (pdf.js: text per page, links, outline, attachments, tags, metadata) identical to takumi-pdf in ${v.semantic.identical}/${v.semantic.compared} documents.`, `Bộ kiểm tra: qpdf ${v.toolVersions.qpdf}, pdfcpu ${v.toolVersions.pdfcpu} (strict), poppler ${v.toolVersions.poppler} (pdfinfo, pdffonts), MuPDF ${v.toolVersions.mupdf} (wasm), pdf.js ${v.toolVersions.pdfjs}, veraPDF ${v.toolVersions.verapdf}. Ngữ nghĩa (pdf.js: chữ từng trang, liên kết, mục lục, tệp đính kèm, thẻ, metadata) trùng với takumi-pdf ở ${v.semantic.identical}/${v.semantic.compared} tài liệu.`));
  }
  if (e.visual) {
    const vi = e.visual;
    out.push("", table([L(lang, "Rasteriser", "Bộ raster"), "identical", "equivalent", "close", "different"], [...Object.entries(vi.perRasteriser).map(([r, c]) => [r, c.identical ?? 0, c.equivalent ?? 0, c.close ?? 0, c.different ?? 0]), [L(lang, "best of the rasterisers", "tốt nhất trong các bộ raster"), vi.consensus.identical ?? 0, vi.consensus.equivalent ?? 0, vi.consensus.close ?? 0, vi.consensus.different ?? 0]].map((r) => r.map(String))));
    out.push("", L(lang, `bm-native vs takumi-pdf, same rasteriser, ${vi.dpis.join(" and ")} dpi, ${vi.docs} documents (worst page counts). bm's PDF vs bm's own image render of the same tree (viewport documents, 96 dpi): ${Object.entries(vi.pdfVsImage).map(([r, c]) => `${r} ${Object.entries(c).map(([k, n]) => `${k} ${n}`).join(", ")}`).join("; ")}.`, `bm-native so với takumi-pdf, cùng bộ raster, ${vi.dpis.join(" và ")} dpi, ${vi.docs} tài liệu (tính theo trang tệ nhất). PDF của bm so với ảnh bm render cùng cây (tài liệu viewport, 96 dpi): ${Object.entries(vi.pdfVsImage).map(([r, c]) => `${r} ${Object.entries(c).map(([k, n]) => `${k} ${n}`).join(", ")}`).join("; ")}.`));
  }
  if (e.identity) out.push("", L(lang, `bm-native == bm-wasm byte for byte: ${e.identity.nativeEqualsWasm}/${e.identity.compared}${e.identity.sameError ? ` (+${e.identity.sameError} with the same error on both)` : ""}. Render errors: ${e.identity.renderErrors.map((r) => `${r.id} ${r.engine}: ${r.error}`).join("; ") || "none"}.`, `bm-native == bm-wasm từng byte: ${e.identity.nativeEqualsWasm}/${e.identity.compared}${e.identity.sameError ? ` (+${e.identity.sameError} cùng lỗi ở cả hai)` : ""}. Lỗi render: ${e.identity.renderErrors.map((r) => `${r.id} ${r.engine}: ${r.error}`).join("; ") || "không có"}.`));
  return out.join("\n");
};

B.noise = (res, lang) => {
  const rows = [];
  for (const p of res.speed?.passes ?? []) rows.push([`speed ${L(lang, "pass", "lượt")} ${p.pass}`, `${num(p.loadBefore?.meanBusyPct, 1, lang)} %`, `${num(p.load?.meanBusyPct, 1, lang)} %`, num(p.load?.otherCores, 2, lang)]);
  for (const k of ["scale", "cold", "memory", "eventloop", "throughput"]) if (res[k]?.load) rows.push([k, "—", `${num(res[k].load.meanBusyPct, 1, lang)} %`, num(res[k].load.otherCores, 2, lang)]);
  if (!rows.length) return "";
  const flagged = (res.speed?.docs ?? []).flatMap((d) => Object.entries(d.perf).filter(([, v]) => v.spreadPct > NOISE_LIMIT).map(([v]) => `${d.id} ${v}`));
  return table([L(lang, "Stage", "Giai đoạn"), L(lang, "CPU busy before", "CPU bận trước"), L(lang, "CPU busy during", "CPU bận trong lúc đo"), L(lang, "other processes (cores)", "tiến trình khác (lõi)")], rows) + "\n\n" +
    L(lang, `Per-document medians whose pass-to-pass spread exceeds ${NOISE_LIMIT} %: ${flagged.length}${flagged.length ? " (e.g. " + flagged.slice(0, 5).join(", ") + ")" : ""}.`, `Median từng tài liệu có độ lệch giữa các lượt vượt ${NOISE_LIMIT} %: ${flagged.length}${flagged.length ? " (ví dụ " + flagged.slice(0, 5).join(", ") + ")" : ""}.`);
};

// ------------------------------------------------------------------------------------------------ output
export const DOCS = ["docs/BENCHMARK.md", "docs/en/benchmark.md", "docs/vi/benchmark.md"];
const langOf = (file) => (/(^|\/)vi\//.test(file) || /BENCHMARK\.md$/.test(file) ? "vi" : "en");

export function fillBlocks(text, res, lang) {
  let blocks = 0;
  const re = /(<!-- pdf-bench:([a-z-]+) -->)[\s\S]*?(<!-- \/pdf-bench:\2 -->)/g;
  const out = text.replace(re, (all, open, name, close) => {
    if (!B[name]) throw new Error("unknown pdf-bench block " + name);
    blocks++;
    const body = B[name](res, lang);
    return `${open}\n${body || L(lang, "_(not measured yet: run `node bench/pdf/bench.mjs`)_", "_(chưa đo: chạy `node bench/pdf/bench.mjs`)_")}\n${close}`;
  });
  return { text: out, blocks };
}

export function renderAll(res, { docs = true, root } = {}) {
  const order = ["env", "summary", "speed", "sizes", "scale", "cold", "memory", "eventloop", "throughput", "equiv", "noise", "per-doc"];
  const md = ["# PDF benchmark: bm-native, bm-wasm, takumi-pdf", "", "Generated by `node bench/pdf/bench.mjs` from `results-pdf.json`; do not edit.", ""];
  for (const b of order) { const body = B[b](res, "en"); if (body) md.push(`## ${b}`, "", body, ""); }
  if (docs && root) {
    for (const rel of DOCS) {
      const p = path.join(root, rel);
      if (!existsSync(p)) continue;
      const raw = readFileSync(p, "utf8");
      const crlf = raw.includes("\r\n");
      const t = crlf ? raw.replace(/\r\n/g, "\n") : raw;
      let { text, blocks } = fillBlocks(t, res, langOf(rel));
      if (crlf) text = text.replace(/\n/g, "\r\n");
      if (blocks && text !== raw) writeFileSync(p, text);
      if (blocks) console.error(`  ${rel}: ${blocks} block(s)`);
    }
  }
  return md.join("\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
  const file = process.argv.slice(2).find((a) => !a.startsWith("--")) ?? path.join(root, "bench", "out", "pdf", "results-pdf.json");
  const res = JSON.parse(readFileSync(file, "utf8"));
  const docs = !process.argv.includes("--no-docs");
  const md = renderAll(res, { docs, root });
  writeFileSync(path.join(root, "bench", "out", "pdf", "PDF.md"), md);
  console.error(`wrote bench/out/pdf/PDF.md${docs ? " and the doc blocks" : ""}`);
}
