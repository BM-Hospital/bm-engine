// Tables of the native benchmark, generated from results-native.json (never typed by hand).
//
//   node bench/native/report.mjs [results-native.json] [--no-docs]
//       re-renders bench/out/native/NATIVE.md and every `<!-- native-bench:<name> -->` ... `<!-- /native-bench:<name> -->`
//       block in the docs from the JSON, without measuring anything (bench/run-native.mjs calls renderAll itself).
//
// A doc opts in to a table by containing the two marker comments; the language of the table follows the file
// (docs/vi/*, docs/BENCHMARK.md: Vietnamese; everything else: English). Blocks: env, highlights, summary, speed,
// categories, best-worst, formats, cpu, equiv, cold, memory, eventloop, throughput, sizes, phase1, per-fixture, noise.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const VARIANTS = ["bm-native:sync", "bm-native:async", "bm-wasm:sync", "takumi-native:async", "takumi-wasm:async"];
const ENGINES = ["bm-native", "bm-wasm", "takumi-native", "takumi-wasm"];
const FORMATS = ["raw", "png", "jpeg", "webp"];
const NOISE_LIMIT = 10; // % pass-to-pass spread above which a number is flagged

// ------------------------------------------------------------------------------------------------ aggregation
const median = (a) => { const s = a.filter((x) => x != null).sort((x, y) => x - y); return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : null; };
const geomean = (a) => (a.length ? Math.exp(a.reduce((s, x) => s + Math.log(x), 0) / a.length) : null);
const spreadPct = (a) => { const s = a.filter((x) => x != null); if (s.length < 2) return null; const m = median(s); return (100 * (Math.max(...s) - Math.min(...s))) / m; };

/** Combines the speed passes: per-fixture median of the passes' medians, geomeans per pass and overall, spreads. */
export function aggregateSpeed(passes) {
  const ids = passes[0]?.cases.map((c) => c.id) ?? [];
  const byId = (p) => new Map(p.cases.map((c) => [c.id, c]));
  const maps = passes.map(byId);
  const fixtures = [];
  for (const id of ids) {
    const c0 = maps[0].get(id);
    const row = { id, feature: c0.feature, width: c0.width, height: c0.height, perf: {} };
    for (const v of VARIANTS) for (const f of FORMATS) {
      const per = maps.map((m) => m.get(id)?.perf?.[v]?.[f]).filter(Boolean);
      if (!per.length) continue;
      const err = per.find((x) => x.error);
      if (err) { (row.perf[v] ??= {})[f] = { error: err.error }; continue; }
      const meds = per.map((x) => x.median);
      (row.perf[v] ??= {})[f] = {
        median: +median(meds).toFixed(4), p95: +median(per.map((x) => x.p95)).toFixed(4), min: +Math.min(...per.map((x) => x.min)).toFixed(4),
        n: per.reduce((s, x) => s + x.n, 0), bytes: per[0].bytes, spreadPct: meds.length > 1 ? +spreadPct(meds).toFixed(1) : null,
        cpuMs: +per.reduce((s, x) => s + x.cpuMs, 0).toFixed(2), wallMs: +per.reduce((s, x) => s + x.wallMs, 0).toFixed(2),
      };
    }
    fixtures.push(row);
  }
  // fixtures on which every variant produced a timing for the format
  const common = (f) => fixtures.filter((r) => VARIANTS.every((v) => r.perf[v]?.[f]?.median > 0));
  const geo = {}, perPass = {}, spread = {}, cpu = {}, nonGap = {}, count = {};
  for (const f of FORMATS) {
    const rows = common(f);
    if (!rows.length) continue;
    count[f] = rows.length;
    for (const v of VARIANTS) {
      (geo[v] ??= {})[f] = +geomean(rows.map((r) => r.perf[v][f].median)).toFixed(4);
      const ng = rows.filter((r) => r.feature !== "known-gaps");
      (nonGap[v] ??= {})[f] = +geomean(ng.map((r) => r.perf[v][f].median)).toFixed(4);
      const pp = maps.map((m) => geomean(rows.map((r) => m.get(r.id)?.perf?.[v]?.[f]?.median).filter((x) => x > 0)));
      (perPass[v] ??= {})[f] = pp.map((x) => +x.toFixed(4));
      (spread[v] ??= {})[f] = pp.length > 1 ? +spreadPct(pp).toFixed(1) : null;
      const n = rows.reduce((s, r) => s + r.perf[v][f].n, 0), c = rows.reduce((s, r) => s + r.perf[v][f].cpuMs, 0), w = rows.reduce((s, r) => s + r.perf[v][f].wallMs, 0);
      (cpu[v] ??= {})[f] = { cpuMsPerRender: +(c / n).toFixed(3), wallMsPerRender: +(w / n).toFixed(3), cores: +(c / w).toFixed(2) };
    }
  }
  // categories (fixture `feature`)
  const categories = {};
  for (const f of ["raw", "png"]) for (const r of common(f)) {
    const cat = (categories[r.feature] ??= { n: {}, geo: {} });
    (cat._rows ??= {})[f] = [...(cat._rows?.[f] ?? []), r];
  }
  for (const cat of Object.values(categories)) {
    for (const f of ["raw", "png"]) {
      const rows = cat._rows?.[f] ?? [];
      cat.n[f] = rows.length;
      for (const v of VARIANTS) if (rows.length) (cat.geo[v] ??= {})[f] = +geomean(rows.map((r) => r.perf[v][f].median)).toFixed(4);
    }
    delete cat._rows;
  }
  // per-fixture ratios + wins
  const ratio = (r, a, b, f) => (r.perf[a]?.[f]?.median > 0 && r.perf[b]?.[f]?.median > 0 ? r.perf[a][f].median / r.perf[b][f].median : null);
  const PAIRS = { "bm-native:async/takumi-native:async": ["bm-native:async", "takumi-native:async"], "bm-native:sync/takumi-native:async": ["bm-native:sync", "takumi-native:async"], "bm-native:sync/bm-wasm:sync": ["bm-native:sync", "bm-wasm:sync"], "bm-wasm:sync/takumi-wasm:async": ["bm-wasm:sync", "takumi-wasm:async"], "takumi-native:async/takumi-wasm:async": ["takumi-native:async", "takumi-wasm:async"] };
  const pairs = {};
  for (const [name, [a, b]] of Object.entries(PAIRS)) for (const f of FORMATS) {
    const rows = common(f);
    if (!rows.length) continue;
    const rs = rows.map((r) => ratio(r, a, b, f));
    // the same ratio computed inside each pass (both engines measured interleaved, so load drift cancels out)
    const pp = maps.map((m) => geomean(rows.map((r) => { const x = m.get(r.id)?.perf; return x?.[a]?.[f]?.median > 0 && x?.[b]?.[f]?.median > 0 ? x[a][f].median / x[b][f].median : null; }).filter((v) => v > 0)));
    (pairs[name] ??= {})[f] = { geomean: +geomean(rs).toFixed(3), faster: rs.filter((x) => x < 1).length, slower: rs.filter((x) => x > 1).length, n: rs.length, min: +Math.min(...rs).toFixed(3), max: +Math.max(...rs).toFixed(3), perPass: pp.map((v) => +v.toFixed(3)), spreadPct: pp.length > 1 ? +spreadPct(pp).toFixed(1) : null };
  }
  const flags = [];
  for (const v of VARIANTS) for (const f of FORMATS) if (spread[v]?.[f] > NOISE_LIMIT) flags.push(`${v} ${f}: geomean range between passes ${spread[v][f]} %`);
  for (const [p, o] of Object.entries(pairs)) for (const f of FORMATS) if (o[f]?.spreadPct > NOISE_LIMIT) flags.push(`ratio ${p} ${f}: range between passes ${o[f].spreadPct} %`);
  const noisyFixtures = {};
  for (const v of VARIANTS) for (const f of ["raw", "png"]) noisyFixtures[`${v} ${f}`] = fixtures.filter((r) => r.perf[v]?.[f]?.spreadPct > NOISE_LIMIT).length;
  return {
    passes: passes.map((p) => ({ pass: p.pass, date: p.date, seconds: +(p.durationMs / 1000).toFixed(0), cfg: p.cfg, loadBefore: p.loadBefore, load: p.load })),
    fixturesTimed: count, geomean: geo, geomeanNonGap: nonGap, perPassGeomean: perPass, spreadPct: spread, cpu, pairs, categories, flags, noisyFixtures, fixtures,
  };
}

// ------------------------------------------------------------------------------------------------ formatting
const L = (lang, en, vi) => (lang === "vi" ? vi : en);
const num = (v, lang) => {
  if (v == null || Number.isNaN(v)) return "—";
  const d = Math.abs(v) >= 100 ? 0 : Math.abs(v) >= 10 ? 1 : 2;
  let s = v.toFixed(d);
  if (Math.abs(v) >= 1000) s = s.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return s;
};
const ms = (v, lang) => (v == null ? "—" : num(v, lang));
const x = (v, lang) => (v == null ? "—" : num(v, lang) + "×");
const sp = (v, lang) => (v == null ? "" : ` ±${num(v / 2, lang)} %`); // half of max-min, relative to the median
const flag = (v) => (v != null && v > NOISE_LIMIT ? " ⚠" : "");
const KiB = (b, lang) => (b == null ? "—" : num(b / 1024, lang));
const table = (head, rows, align) => [
  "| " + head.join(" | ") + " |",
  "|" + head.map((_, i) => (align?.[i] === "l" || (align == null && i === 0) ? ":--" : "--:")).join("|") + "|",
  ...rows.map((r) => "| " + r.join(" | ") + " |"),
].join("\n");
const vname = (v) => ({ "bm-native:sync": "bm-native sync", "bm-native:async": "bm-native async", "bm-wasm:sync": "bm-wasm sync", "takumi-native:async": "takumi-native async", "takumi-wasm:async": "takumi-wasm" }[v] ?? v);

function tpPoint(res, engine, mode, k, uv, n) {
  const run = res.throughput?.runs?.find((r) => r.engine === engine && r.mode === mode && (k == null || r.k === k) && (uv == null || r.uv === uv));
  return run?.results?.find((p) => p.n === n)?.ips ?? null;
}
function tpBest(res, engine, n) {
  // the best configuration measured for that engine at concurrency n (with its label)
  let best = null;
  for (const r of res.throughput?.runs ?? []) if (r.engine === engine) for (const p of r.results ?? []) if (p.n === n && (!best || p.ips > best.ips)) best = { ips: p.ips, label: `${r.mode}${r.mode === "many" || r.mode === "pool" ? " K=" + r.k : ""}${engine.endsWith("native") ? ", UV " + r.uv : ""}` };
  return best;
}
const elRun = (res, engine, api, job) => res.eventloop?.runs?.find((r) => r.engine === engine && r.api === api && r.job === job);

// ------------------------------------------------------------------------------------------------ blocks
const busyWarn = (load, lang) => (load?.otherCores > 1
  ? L(lang, ` ⚠ Other processes used about ${num(load.otherCores, lang)} of the machine's cores on average during this stage, so these figures (scaling above all) understate what an idle machine gives; re-run on a quiet machine before quoting them.`,
    ` ⚠ Trong lúc đo, các tiến trình khác dùng trung bình khoảng ${num(load.otherCores, lang)} lõi của máy, nên các số này (nhất là mức mở rộng) thấp hơn những gì một máy rảnh cho; hãy chạy lại trên máy rảnh trước khi trích dẫn.`)
  : "");
const B = {};
B.env = (res, lang) => {
  const m = res.meta, e = m.engines;
  const rows = [
    [L(lang, "Machine", "Máy"), `${m.cpu}, ${m.cpus} ${L(lang, "logical CPUs", "CPU logic")}, ${num(m.totalMemGiB, lang)} GiB, ${m.platform}`],
    ["Node.js", `${m.node} (V8 ${m.v8}, N-API ${m.napi}, libuv ${m.uv})`],
    ["bm-engine", `${e["bm-native"].version}, git \`${(m.git.commit || "").slice(0, 10)}\` (${m.git.branch}${m.git.dirtyFiles ? `, ${m.git.dirtyFiles} ${L(lang, "modified tracked files", "file đang sửa")}` : ""})`],
    ["bm-native", `\`${e["bm-native"].file}\`, ${KiB(e["bm-native"].bytes, lang)} KiB, Zig ${e["bm-native"].zig}, ${e["bm-native"].optimize === "fast" ? "ReleaseFast" : e["bm-native"].optimize}, sha256 \`${(e["bm-native"].sha256 || "").slice(0, 12)}\``],
    ["bm-wasm", `\`${e["bm-wasm"].file}\` (${L(lang, "full profile", "profile full")}), ${KiB(e["bm-wasm"].bytes, lang)} KiB, sha256 \`${(e["bm-wasm"].sha256 || "").slice(0, 12)}\``],
    ["takumi-native", `\`${e["takumi-native"].package}\` ${e["takumi-native"].version} + \`${e["takumi-native"].binaryPackage}\` ${e["takumi-native"].binaryVersion}, ${KiB(e["takumi-native"].bytes, lang)} KiB`],
    ["takumi-wasm", `\`${e["takumi-wasm"].package}\` ${e["takumi-wasm"].version}, ${KiB(e["takumi-wasm"].bytes, lang)} KiB`],
    [L(lang, "Run", "Lần chạy"), `${m.date.slice(0, 16).replace("T", " ")} UTC, ${m.quick ? L(lang, "quick mode", "chế độ quick") : L(lang, "full mode", "chế độ full")}, ${m.fixtures} fixtures, ${num(m.durationMin, lang)} min; ${L(lang, "CPU busy before the run", "CPU bận trước khi chạy")}: ${num(m.loadAtStart?.meanBusyPct, lang)} %`],
  ];
  return table([L(lang, "Item", "Mục"), L(lang, "Value", "Giá trị")], rows, ["l", "l"]);
};

B.summary = (res, lang) => {
  const s = res.speed, g = s?.geomean, spr = s?.spreadPct;
  const cell = (v, f) => (g?.[v]?.[f] != null ? `${ms(g[v][f], lang)}${sp(spr?.[v]?.[f], lang)}${flag(spr?.[v]?.[f])}` : "—");
  const cold = (n) => { const c = res.cold?.engines?.[n]; return c ? `${ms(c.overNodeMedianMs, lang)} / ${ms(c.overNodeP95Ms, lang)}` : "—"; };
  const mem = (n) => { const m = res.memory?.engines?.[n]?.suite; return m?.passes ? `${num(m.passes[0].rssMiB, lang)} → ${num(m.passes.at(-1).rssMiB, lang)}` : "—"; };
  const peak = (n) => { const m = res.memory?.engines?.[n]?.large; return m?.after ? num(m.after.maxRssMiB, lang) : "—"; };
  const el = (n, job) => { const a = elRun(res, n, "async", job), y = elRun(res, n, "sync", job); const f = (r) => (r ? ms(r.maxDelayMs, lang) : null); return [y && `${f(y)} (sync)`, a && `${f(a)} (async)`].filter(Boolean).join(" · ") || "—"; };
  const tp = (n, c) => { const b = tpBest(res, n, c); return b ? `${num(b.ips, lang)} (${b.label})${res.throughput?.load?.otherCores > 1 ? " ⚠" : ""}` : "—"; };
  const cpuPng = (v) => { const c = s?.cpu?.[v]?.png; return c ? `${ms(c.cpuMsPerRender, lang)} (${num(c.cores, lang)} ${L(lang, "cores", "lõi")})` : "—"; };
  const pngBytes = () => { const fx = s?.fixtures ?? []; const r = (v) => geomean(fx.filter((f) => f.perf[v]?.png?.bytes && f.perf["takumi-wasm:async"]?.png?.bytes).map((f) => f.perf[v].png.bytes / f.perf["takumi-wasm:async"].png.bytes)); return [r("bm-native:sync"), r("bm-wasm:sync"), r("takumi-native:async"), 1]; };
  const pb = pngBytes();
  const rows = [
    [L(lang, "raw RGBA, geomean ms — sync API", "raw RGBA, geomean ms — API sync"), cell("bm-native:sync", "raw"), cell("bm-wasm:sync", "raw"), L(lang, "no sync API", "không có API sync"), "—"],
    [L(lang, "raw RGBA, geomean ms — async API", "raw RGBA, geomean ms — API async"), cell("bm-native:async", "raw"), "—", cell("takumi-native:async", "raw"), cell("takumi-wasm:async", "raw")],
    [L(lang, "PNG, geomean ms — sync API", "PNG, geomean ms — API sync"), cell("bm-native:sync", "png"), cell("bm-wasm:sync", "png"), L(lang, "no sync API", "không có API sync"), "—"],
    [L(lang, "PNG, geomean ms — async API", "PNG, geomean ms — API async"), cell("bm-native:async", "png"), "—", cell("takumi-native:async", "png"), cell("takumi-wasm:async", "png")],
    [L(lang, "CPU time per PNG render, mean ms (cores used)", "Thời gian CPU mỗi lần render PNG, ms trung bình (số lõi dùng)"), cpuPng("bm-native:sync"), cpuPng("bm-wasm:sync"), cpuPng("takumi-native:async"), cpuPng("takumi-wasm:async")],
    [L(lang, "PNG file size, geomean vs takumi", "Dung lượng PNG, geomean so với takumi"), x(pb[0], lang), x(pb[1], lang), x(pb[2], lang), x(pb[3], lang)],
    [L(lang, "Cold start over empty Node, median / p95 ms", "Cold start so với Node rỗng, median / p95 ms"), cold("bm-native"), cold("bm-wasm"), cold("takumi-native"), cold("takumi-wasm")],
    [L(lang, `RSS after 1 → ${res.memory?.suitePasses ?? "N"} suite passes, MiB`, `RSS sau 1 → ${res.memory?.suitePasses ?? "N"} lượt cả bộ fixture, MiB`), mem("bm-native"), mem("bm-wasm"), mem("takumi-native"), mem("takumi-wasm")],
    [L(lang, "Peak RSS, one 4000×4000 PNG, MiB", "RSS đỉnh, một PNG 4000×4000, MiB"), peak("bm-native"), peak("bm-wasm"), peak("takumi-native"), peak("takumi-wasm")],
    [L(lang, "Event loop: max 1 ms-timer delay, heavy 2400×2400 render, ms", "Event loop: độ trễ lớn nhất của timer 1 ms, render nặng 2400×2400, ms"), el("bm-native", "heavy"), el("bm-wasm", "heavy"), el("takumi-native", "heavy"), el("takumi-wasm", "heavy")],
    ...(res.eventloop?.runs?.some((r) => r.job === "anim") ? [[L(lang, "Event loop: same, 60-frame animation, ms", "Event loop: như trên, animation 60 khung, ms"), el("bm-native", "anim"), el("bm-wasm", "anim"), el("takumi-native", "anim"), el("takumi-wasm", "anim")]] : []),
    [L(lang, "Throughput, og card PNG, 4 concurrent, images/s (best config)", "Thông lượng, og card PNG, 4 đồng thời, ảnh/s (cấu hình tốt nhất)"), tp("bm-native", 4), tp("bm-wasm", 4), tp("takumi-native", 4), tp("takumi-wasm", 4)],
    [L(lang, "Throughput, 8 concurrent, images/s (best config)", "Thông lượng, 8 đồng thời, ảnh/s (cấu hình tốt nhất)"), tp("bm-native", 8), tp("bm-wasm", 8), tp("takumi-native", 8), tp("takumi-wasm", 8)],
  ];
  const note = L(lang,
    `Geomeans over the ${s?.fixturesTimed?.raw ?? "?"} fixtures every engine rendered; ± = half the range of the ${s?.passes?.length ?? "?"} passes' geomeans relative to their median; ⚠ = more than ${NOISE_LIMIT} % range. Cold start: median / p95 of ${res.cold?.runs ?? "?"} fresh processes minus the empty-Node median. Event-loop, memory and throughput are single runs; on the throughput rows ⚠ = other processes used more than one core on average during that stage.`,
    `Geomean trên ${s?.fixturesTimed?.raw ?? "?"} fixture mà cả bốn engine đều render được; ± = nửa khoảng chênh giữa geomean của ${s?.passes?.length ?? "?"} lượt so với median của chúng; ⚠ = chênh quá ${NOISE_LIMIT} %. Cold start: median / p95 của ${res.cold?.runs ?? "?"} tiến trình mới trừ median của Node rỗng. Event loop, bộ nhớ và thông lượng là một lần đo; ở các dòng thông lượng ⚠ = tiến trình khác dùng trung bình hơn một lõi trong lúc đo.`);
  return table([L(lang, "Metric", "Chỉ số"), "bm-native", "bm-wasm", "takumi-native", "takumi-wasm"], rows) + "\n\n" + note;
};

const pr = (o, lang) => (o?.perPass?.length > 1 ? ` [${o.perPass.map((v) => x(v, lang)).join(" / ")}]` : "");
B.highlights = (res, lang) => {
  const s = res.speed, p = s?.pairs, out = [];
  if (p) {
    const a = p["bm-native:async/takumi-native:async"], y = p["bm-native:sync/takumi-native:async"], w = p["bm-native:sync/bm-wasm:sync"], tw = p["takumi-native:async/takumi-wasm:async"];
    out.push(L(lang,
      `**bm-native vs bm-wasm (sync):** raw ${x(w.raw.geomean, lang)} the wasm time${pr(w.raw, lang)} (faster on ${w.raw.faster}/${w.raw.n} fixtures), PNG ${x(w.png.geomean, lang)}${pr(w.png, lang)} (faster on ${w.png.faster}/${w.png.n}).`,
      `**bm-native so với bm-wasm (sync):** raw bằng ${x(w.raw.geomean, lang)} thời gian của wasm${pr(w.raw, lang)} (nhanh hơn ở ${w.raw.faster}/${w.raw.n} fixture), PNG ${x(w.png.geomean, lang)}${pr(w.png, lang)} (nhanh hơn ở ${w.png.faster}/${w.png.n}).`));
    out.push(L(lang,
      `**bm-native vs takumi-native, both async:** raw ${x(a.raw.geomean, lang)}${pr(a.raw, lang)} (bm faster on ${a.raw.faster}/${a.raw.n}, per fixture ${x(a.raw.min, lang)}–${x(a.raw.max, lang)}), PNG ${x(a.png.geomean, lang)}${pr(a.png, lang)} (bm faster on ${a.png.faster}/${a.png.n}, per fixture ${x(a.png.min, lang)}–${x(a.png.max, lang)}). With bm's sync API: raw ${x(y.raw.geomean, lang)}, PNG ${x(y.png.geomean, lang)}. Below 1× = bm-native takes less time; in brackets the same ratio in each pass.`,
      `**bm-native so với takumi-native, cùng async:** raw ${x(a.raw.geomean, lang)}${pr(a.raw, lang)} (bm nhanh hơn ở ${a.raw.faster}/${a.raw.n}, từng fixture ${x(a.raw.min, lang)}–${x(a.raw.max, lang)}), PNG ${x(a.png.geomean, lang)}${pr(a.png, lang)} (bm nhanh hơn ở ${a.png.faster}/${a.png.n}, từng fixture ${x(a.png.min, lang)}–${x(a.png.max, lang)}). Với API sync của bm: raw ${x(y.raw.geomean, lang)}, PNG ${x(y.png.geomean, lang)}. Dưới 1× = bm-native tốn ít thời gian hơn; trong ngoặc vuông là cùng tỉ lệ đó ở từng lượt.`));
    const c = s.cpu, bn = c?.["bm-native:async"], tn = c?.["takumi-native:async"];
    if (tn?.png && bn?.png) out.push(L(lang,
      `**CPU time per image (both async):** PNG ${ms(bn.png.cpuMsPerRender, lang)} ms bm-native vs ${ms(tn.png.cpuMsPerRender, lang)} ms takumi-native (${num(bn.png.cores, lang)} vs ${num(tn.png.cores, lang)} cores busy during a render); raw ${ms(bn.raw.cpuMsPerRender, lang)} vs ${ms(tn.raw.cpuMsPerRender, lang)} ms. takumi-native runs parts of one render (PNG deflate segments, blur, WebP, animation frames) on its own rayon thread pool; bm renders one image on one thread (bm-native sync: ${num(c["bm-native:sync"].png.cores, lang)} cores for PNG).`,
      `**Thời gian CPU mỗi ảnh (cùng async):** PNG ${ms(bn.png.cpuMsPerRender, lang)} ms bm-native so với ${ms(tn.png.cpuMsPerRender, lang)} ms takumi-native (${num(bn.png.cores, lang)} so với ${num(tn.png.cores, lang)} lõi bận trong một lần render); raw ${ms(bn.raw.cpuMsPerRender, lang)} so với ${ms(tn.raw.cpuMsPerRender, lang)} ms. takumi-native chạy một phần của một lần render (các đoạn deflate PNG, blur, WebP, khung animation) trên thread pool rayon riêng; bm render một ảnh trên một thread (bm-native sync: ${num(c["bm-native:sync"].png.cores, lang)} lõi với PNG).`));
    out.push(L(lang,
      `**takumi's own two builds:** takumi-native takes ${x(tw.raw.geomean, lang)} the time of takumi-wasm for raw and ${x(tw.png.geomean, lang)} for PNG.`,
      `**Hai bản build của chính takumi:** takumi-native tốn ${x(tw.raw.geomean, lang)} thời gian của takumi-wasm với raw và ${x(tw.png.geomean, lang)} với PNG.`));
  }
  if (res.identity) out.push(L(lang,
    `**Identity:** bm-native and bm-wasm produced the same bytes in ${res.identity.identical}/${res.identity.compared} comparisons over ${res.identity.fixtures} fixtures (${num(res.identity.mbCompared, lang)} MB; ${res.identity.mismatches} mismatches).`,
    `**Trùng byte:** bm-native và bm-wasm cho cùng byte ở ${res.identity.identical}/${res.identity.compared} phép so trên ${res.identity.fixtures} fixture (${num(res.identity.mbCompared, lang)} MB; ${res.identity.mismatches} khác biệt).`));
  if (s?.spreadPct) {
    const abs = Object.values(s.spreadPct).flatMap((o) => [o.raw, o.png]).filter((v) => v != null);
    const rat = Object.values(s.pairs).flatMap((o) => [o.raw?.spreadPct, o.png?.spreadPct]).filter((v) => v != null);
    if (abs.length && rat.length) out.push(L(lang,
      `**Noise:** the absolute raw / PNG geomeans moved by up to ${num(Math.max(...abs), lang)} % between passes (the load from other processes changed during the run), while the engine-to-engine ratios, measured interleaved inside each pass, moved by at most ${num(Math.max(...rat), lang)} %. Read the ratios; treat absolute milliseconds as ±${num(Math.max(...abs) / 2, lang)} %.`,
      `**Nhiễu:** geomean tuyệt đối raw / PNG lệch tới ${num(Math.max(...abs), lang)} % giữa các lượt (tải của tiến trình khác thay đổi trong lúc chạy), còn tỉ lệ giữa các engine, đo xen kẽ trong từng lượt, lệch nhiều nhất ${num(Math.max(...rat), lang)} %. Hãy đọc tỉ lệ; coi số ms tuyệt đối là ±${num(Math.max(...abs) / 2, lang)} %.`));
  }
  return out.map((l) => "- " + l).join("\n");
};

B.ratios = (res, lang) => {
  const p = res.speed?.pairs;
  if (!p) return "";
  const names = { "bm-native:async/takumi-native:async": "bm-native async / takumi-native", "bm-native:sync/takumi-native:async": "bm-native sync / takumi-native", "bm-native:sync/bm-wasm:sync": "bm-native sync / bm-wasm sync", "bm-wasm:sync/takumi-wasm:async": "bm-wasm sync / takumi-wasm", "takumi-native:async/takumi-wasm:async": "takumi-native / takumi-wasm" };
  const rows = [];
  for (const [k, o] of Object.entries(p)) for (const f of FORMATS) if (o[f]) rows.push([names[k] ?? k, `${f} (${o[f].n})`, `**${x(o[f].geomean, lang)}**`, o[f].perPass?.map((v) => x(v, lang)).join(" / ") ?? "", `${o[f].faster} / ${o[f].slower}`, `${x(o[f].min, lang)} – ${x(o[f].max, lang)}`]);
  return table([L(lang, "Ratio (time A / time B)", "Tỉ lệ (thời gian A / thời gian B)"), L(lang, "format (fixtures)", "định dạng (số fixture)"), "geomean", L(lang, "per pass", "từng lượt"), L(lang, "A faster / slower", "A nhanh hơn / chậm hơn"), L(lang, "per-fixture range", "khoảng theo fixture")], rows) + "\n\n" +
    L(lang, "Geomean over fixtures of the per-fixture ratio of median times; below 1× = A takes less time. The per-pass column is the same ratio computed inside each pass: both engines were measured interleaved, so a change of machine load between passes largely cancels out.",
      "Geomean trên các fixture của tỉ lệ thời gian median từng fixture; dưới 1× = A tốn ít thời gian hơn. Cột từng lượt là cùng tỉ lệ tính trong mỗi lượt: hai engine được đo xen kẽ nên thay đổi tải giữa các lượt phần lớn bị triệt tiêu.");
};

B.speed = (res, lang) => {
  const s = res.speed;
  if (!s) return "";
  const rows = [];
  for (const f of FORMATS) if (s.fixturesTimed[f]) {
    rows.push([`${f} (${s.fixturesTimed[f]})`, ...VARIANTS.map((v) => `${ms(s.geomean[v][f], lang)}${sp(s.spreadPct[v][f], lang)}${flag(s.spreadPct[v][f])}`)]);
  }
  const rowsNg = ["raw", "png"].filter((f) => s.fixturesTimed[f]).map((f) => [`${f}, ${L(lang, "without known-gaps", "bỏ known-gaps")}`, ...VARIANTS.map((v) => ms(s.geomeanNonGap[v][f], lang))]);
  const pp = ["raw", "png"].filter((f) => s.fixturesTimed[f]).map((f) => [`${f}, ${L(lang, "per pass", "từng lượt")}`, ...VARIANTS.map((v) => s.perPassGeomean[v][f].map((y) => ms(y, lang)).join(" / "))]);
  return table([L(lang, "Format (fixtures)", "Định dạng (số fixture)"), ...VARIANTS.map(vname)], [...rows, ...rowsNg, ...pp]) + "\n\n" +
    L(lang, "Geometric mean of the per-fixture median render time, ms. jpeg (quality 85) and webp (lossless; takumi-wasm uses a different WebP encoder from takumi-native, see the format table) are timed on three fixtures only.",
      "Trung bình nhân của thời gian render median từng fixture, ms. jpeg (quality 85) và webp (lossless; takumi-wasm dùng bộ mã hoá WebP khác takumi-native, xem bảng định dạng) chỉ đo trên ba fixture.");
};

B.cpu = (res, lang) => {
  const c = res.speed?.cpu;
  if (!c) return "";
  const rows = VARIANTS.map((v) => [vname(v), ...["raw", "png"].map((f) => c[v][f] ? `${ms(c[v][f].wallMsPerRender, lang)} / ${ms(c[v][f].cpuMsPerRender, lang)} / ${num(c[v][f].cores, lang)}` : "—")]);
  return table([L(lang, "Variant", "Biến thể"), L(lang, "raw: wall / CPU ms / cores", "raw: thực / CPU ms / lõi"), L(lang, "PNG: wall / CPU ms / cores", "PNG: thực / CPU ms / lõi")], rows) + "\n\n" +
    L(lang, "Mean over every timed render of the suite (not a geomean): wall time per render, process CPU time (all threads) spent during it, and their ratio. A ratio above 1 means one render kept more than one core busy.",
      "Trung bình trên mọi lần render được đo (không phải geomean): thời gian thực mỗi lần render, thời gian CPU của tiến trình (mọi thread) trong lúc đó, và tỉ số. Tỉ số trên 1 nghĩa là một lần render dùng hơn một lõi.");
};

B.categories = (res, lang) => {
  const c = res.speed?.categories;
  if (!c) return "";
  const vs = ["bm-native:sync", "bm-native:async", "bm-wasm:sync", "takumi-native:async", "takumi-wasm:async"];
  const rows = Object.entries(c).sort((a, b) => a[0].localeCompare(b[0])).map(([cat, v]) => {
    const r = (f) => (v.geo["bm-native:async"]?.[f] && v.geo["takumi-native:async"]?.[f] ? v.geo["bm-native:async"][f] / v.geo["takumi-native:async"][f] : null);
    return [cat, String(v.n.raw ?? v.n.png), ...vs.map((k) => ms(v.geo[k]?.raw, lang)), x(r("raw"), lang), ...vs.map((k) => ms(v.geo[k]?.png, lang)), x(r("png"), lang)];
  });
  const short = { "bm-native:sync": "bm-n sync", "bm-native:async": "bm-n async", "bm-wasm:sync": "bm-w", "takumi-native:async": "tk-n", "takumi-wasm:async": "tk-w" };
  return table([L(lang, "Category", "Nhóm"), "n", ...vs.map((k) => "raw " + short[k]), "raw bm-n/tk-n", ...vs.map((k) => "png " + short[k]), "png bm-n/tk-n"], rows) + "\n\n" +
    L(lang, "Geomean ms per fixture category. bm-n = bm-native, bm-w = bm-wasm (sync), tk-n = takumi-native (async), tk-w = takumi-wasm; ratio = bm-native async / takumi-native async (below 1× = bm faster).",
      "Geomean ms theo nhóm fixture. bm-n = bm-native, bm-w = bm-wasm (sync), tk-n = takumi-native (async), tk-w = takumi-wasm; tỉ lệ = bm-native async / takumi-native async (dưới 1× = bm nhanh hơn).");
};

B["best-worst"] = (res, lang) => {
  const fx = res.speed?.fixtures;
  if (!fx) return "";
  const parts = [];
  for (const f of ["raw", "png"]) {
    const rows = fx.filter((r) => r.perf["bm-native:async"]?.[f]?.median > 0 && r.perf["takumi-native:async"]?.[f]?.median > 0)
      .map((r) => ({ id: r.id, a: r.perf["bm-native:async"][f].median, b: r.perf["takumi-native:async"][f].median, s: r.perf["bm-native:sync"]?.[f]?.median, cores: r.perf["takumi-native:async"][f].cpuMs / r.perf["takumi-native:async"][f].wallMs }))
      .map((r) => ({ ...r, ratio: r.a / r.b })).sort((p, q) => p.ratio - q.ratio);
    const fmt = (r) => [`\`${r.id}\``, ms(r.s, lang), ms(r.a, lang), ms(r.b, lang), num(r.cores, lang), x(r.ratio, lang)];
    const head = [L(lang, "Fixture", "Fixture"), "bm-native sync ms", "bm-native async ms", "takumi-native ms", L(lang, "takumi cores", "lõi takumi"), "bm/takumi (async)"];
    parts.push(`**${f} — ${L(lang, "bm-native's 10 best", "10 ca bm-native tốt nhất")}**\n\n` + table(head, rows.slice(0, 10).map(fmt)));
    parts.push(`**${f} — ${L(lang, "bm-native's 10 worst", "10 ca bm-native kém nhất")}**\n\n` + table(head, rows.slice(-10).reverse().map(fmt)));
  }
  return parts.join("\n\n");
};

B.formats = (res, lang) => {
  const fx = res.speed?.fixtures?.filter((r) => r.perf["bm-native:sync"]?.jpeg || r.perf["bm-native:sync"]?.webp);
  if (!fx?.length) return "";
  const rows = [];
  for (const r of fx) for (const f of FORMATS) {
    if (!r.perf["bm-native:sync"]?.[f]) continue;
    rows.push([`\`${r.id}\``, f, ...VARIANTS.map((v) => { const p = r.perf[v]?.[f]; return p?.median ? `${ms(p.median, lang)} ms · ${KiB(p.bytes, lang)} KiB` : p?.error ? "error" : "—"; })]);
  }
  return table([L(lang, "Fixture", "Fixture"), L(lang, "Format", "Định dạng"), ...VARIANTS.map(vname)], rows) + "\n\n" +
    L(lang, "Median time and output size. JPEG: quality 85 for every engine. WebP: lossless for every engine (no `quality`); takumi-native encodes with libwebp, takumi-wasm with the `image-webp` crate (hence its larger files). PNG: no engine exposes a compression level; each uses its default encoder effort (bm: its own deflate; takumi: `png` + `zlib-rs`, choosing between level 7 / no filter and level 3 / adaptive filter on a sample, deflating in up to 8 segments in parallel on the native build), so PNG times are compared together with file sizes.",
      "Thời gian median và dung lượng đầu ra. JPEG: quality 85 cho mọi engine. WebP: lossless cho mọi engine (không có `quality`); takumi-native mã hoá bằng libwebp, takumi-wasm bằng crate `image-webp` (nên file lớn hơn). PNG: không engine nào cho chỉnh mức nén; mỗi engine dùng mức mặc định của nó (bm: deflate riêng; takumi: `png` + `zlib-rs`, chọn giữa level 7 / không lọc và level 3 / lọc thích ứng trên một mẫu, nén thành tối đa 8 đoạn song song ở bản native), nên thời gian PNG được so kèm dung lượng file.");
};

B.equiv = (res, lang) => {
  const e = res.equiv, id = res.identity;
  const parts = [];
  if (e) {
    const cols = ["identical", "equivalent", "close", "different", "error/unsupported"];
    parts.push(table([L(lang, `Engine vs ${e.reference} (${e.fixtures} fixtures, raw RGBA)`, `Engine so với ${e.reference} (${e.fixtures} fixture, raw RGBA)`), ...cols], Object.entries(e.verdicts).map(([n, v]) => [n, ...cols.map((c) => String(v[c] ?? 0))])));
    parts.push(table([L(lang, "Same engine, two builds", "Cùng engine, hai bản build"), L(lang, "raw RGBA byte-identical", "raw RGBA trùng byte"), L(lang, "PNG file byte-identical", "file PNG trùng byte")], Object.entries(e.identicalBytes).map(([p, v]) => [p.replace("=", " = "), `${v.raw}/${e.fixtures}`, `${v.png}/${e.fixtures}`])));
  }
  if (id) parts.push(L(lang,
    `\`bench/native-identity.mjs\`: ${id.fixtures} fixtures, ${id.compared} comparisons (raw, PNG, JPEG, WebP, measure, SVG, animations, ICO, HTML, images, WOFF2, error messages, native async vs sync), ${id.identical} identical (${id.sameErrorOnBoth} of them the same error message on both), ${id.mismatches} mismatches, ${num(id.mbCompared, lang)} MB compared.`,
    `\`bench/native-identity.mjs\`: ${id.fixtures} fixture, ${id.compared} phép so (raw, PNG, JPEG, WebP, measure, SVG, animation, ICO, HTML, ảnh, WOFF2, thông báo lỗi, native async so với sync), ${id.identical} trùng (${id.sameErrorOnBoth} trong số đó là cùng thông báo lỗi ở cả hai), ${id.mismatches} khác, ${num(id.mbCompared, lang)} MB đã so.`));
  return parts.join("\n\n");
};

B.cold = (res, lang) => {
  const c = res.cold;
  if (!c) return "";
  const rows = ["none", ...ENGINES].map((n) => { const e = c.engines[n]; return e?.error ? [n, "error: " + e.error, "", "", "", "", "", ""] : [n === "none" ? L(lang, "empty Node (baseline)", "Node rỗng (mốc)") : n, ms(e.wallMedianMs, lang), ms(e.wallP95Ms, lang), n === "none" ? "0" : ms(e.overNodeMedianMs, lang), n === "none" ? "0" : ms(e.overNodeP95Ms, lang), n === "none" ? "—" : ms(e.importMs, lang), n === "none" ? "—" : ms(e.fontMs, lang), n === "none" ? "—" : ms(e.firstRenderMs, lang)]; });
  return table([L(lang, "Engine", "Engine"), L(lang, "wall median", "thực median"), "wall p95", L(lang, "over Node, median", "hơn Node, median"), L(lang, "over Node, p95", "hơn Node, p95"), "import", "registerFont", L(lang, "first PNG", "PNG đầu tiên")], rows) + "\n\n" +
    L(lang, `ms. ${c.runs} runs per engine, engines interleaved; ${c.what}. The import / registerFont / first-PNG columns are medians measured inside the child. CPU busy during the stage: ${num(c.load?.meanBusyPct, lang)} % mean (other processes ≈ ${num(c.load?.otherCores, lang)} cores).${busyWarn(c.load, lang)}`,
      `ms. ${c.runs} lần mỗi engine, xen kẽ các engine; spawn node → import engine như người dùng → registerFont(Inter Regular) → PNG og card 1200×630 → thoát; thời gian thực = đồng hồ của tiến trình cha từ spawn tới khi thoát. Các cột import / registerFont / PNG đầu tiên là median đo bên trong tiến trình con. CPU bận trong lúc đo: trung bình ${num(c.load?.meanBusyPct, lang)} % (tiến trình khác ≈ ${num(c.load?.otherCores, lang)} lõi).${busyWarn(c.load, lang)}`);
};

B.memory = (res, lang) => {
  const m = res.memory;
  if (!m) return "";
  const rows = ENGINES.map((n) => {
    const s = m.engines[n]?.suite, l = m.engines[n]?.large;
    if (!s?.passes) return [n, "error: " + (s?.error ?? "?"), "", "", "", "", ""];
    const p1 = s.passes[0], pn = s.passes.at(-1);
    const eng = (p) => (p.engineMiB == null ? "—" : num(p.engineMiB, lang));
    return [n, num(s.afterSetup.rssMiB, lang), `${num(p1.rssMiB, lang)} → ${num(pn.rssMiB, lang)}`, `${eng(p1)} → ${eng(pn)}`, `${num(p1.heapUsedMiB, lang)} → ${num(pn.heapUsedMiB, lang)}`, num(pn.maxRssMiB, lang), l?.after ? `${num(l.after.maxRssMiB, lang)} (${num(l.after.maxRssMiB - l.before.rssMiB, lang)})` : "—"];
  });
  return table([L(lang, "Engine", "Engine"), L(lang, "RSS after setup", "RSS sau khởi tạo"), L(lang, `RSS after pass 1 → ${m.suitePasses}`, `RSS sau lượt 1 → ${m.suitePasses}`), L(lang, "engine memory 1 → N", "bộ nhớ engine 1 → N"), L(lang, "JS heap 1 → N", "JS heap 1 → N"), L(lang, "peak RSS, suite", "RSS đỉnh, cả bộ"), L(lang, "peak RSS 4000×4000 PNG (growth)", "RSS đỉnh PNG 4000×4000 (tăng thêm)")], rows) + "\n\n" +
    L(lang, `MiB, after a forced GC. One process per engine; every fixture rendered to raw and PNG (async API) per pass, one renderer per font set. Engine memory: bm-native = bytes allocated by the addon (\`memoryBytes()\`), bm-wasm / takumi-wasm = the wasm linear memory, takumi-native = not exposed. Empty Node: ${num(m.emptyNode?.rssMiB, lang)} MiB RSS. "Growth" = peak RSS minus the RSS just before the 4000×4000 render.`,
      `MiB, sau khi ép GC. Một tiến trình cho mỗi engine; mỗi lượt render mọi fixture ra raw và PNG (API async), một renderer cho mỗi bộ font. Bộ nhớ engine: bm-native = số byte addon đang cấp phát (\`memoryBytes()\`), bm-wasm / takumi-wasm = bộ nhớ tuyến tính wasm, takumi-native = không công bố. Node rỗng: ${num(m.emptyNode?.rssMiB, lang)} MiB RSS. "Tăng thêm" = RSS đỉnh trừ RSS ngay trước lần render 4000×4000.`);
};

B.eventloop = (res, lang) => {
  const e = res.eventloop;
  if (!e) return "";
  const rows = e.runs.map((r) => r.unsupported ? [r.job, r.engine, r.api, L(lang, "not supported", "không hỗ trợ"), "", "", "", ""] : [r.job, r.engine, r.api === "async" && r.engine.endsWith("wasm") ? L(lang, "async (runs on the main thread)", "async (chạy trên main thread)") : r.api, ms(r.ms, lang), ms(r.cpuMs, lang), ms(r.maxDelayMs, lang), ms(r.p99DelayMs, lang), String(r.ticks)]);
  return table([L(lang, "Job", "Việc"), "Engine", "API", L(lang, "job ms", "ms của việc"), "CPU ms", L(lang, "max timer delay ms", "trễ timer lớn nhất ms"), L(lang, "p99 delay ms", "trễ p99 ms"), L(lang, "timer ticks", "số lần timer chạy")], rows) + "\n\n" +
    L(lang, `heavy = ${e.jobs.heavy}; anim = ${e.jobs.anim}. A 1 ms \`setInterval\` records the gap between its ticks while the call runs. A setImmediate chain keeps the loop from sleeping, because an idle Node loop on Windows wakes on the 15.6 ms system clock and the timer would otherwise never show less than ~16 ms. A call that blocks the loop shows one tick whose delay is the whole call. CPU ms is the whole process during the call, including the setImmediate chain on the main thread (about one core whenever the loop is free).${busyWarn(e.load, lang)}`,
      `heavy = một PNG 2400×2400: gradient, 24 thẻ với box-shadow mờ lớn, cứ ba thẻ có một thẻ \`filter: blur(6px)\`, chữ; anim = renderAnimation: 60 khung (2 s ở 30 fps) WebP lossless 800×420, 12 hình tròn có bóng, mờ, xoay (cảnh tĩnh). Một \`setInterval\` 1 ms ghi khoảng cách giữa các lần chạy trong lúc lời gọi chạy. Một chuỗi setImmediate giữ cho vòng lặp không ngủ, vì vòng lặp Node rảnh trên Windows thức theo đồng hồ hệ thống 15,6 ms và timer sẽ không bao giờ cho thấy dưới ~16 ms. Lời gọi chặn vòng lặp cho thấy một lần chạy có độ trễ bằng cả lời gọi. CPU ms là của cả tiến trình trong lúc gọi, kể cả chuỗi setImmediate trên main thread (khoảng một lõi mỗi khi vòng lặp rảnh).${busyWarn(e.load, lang)}`);
};

B.throughput = (res, lang) => {
  const t = res.throughput;
  if (!t) return "";
  const Ns = [...new Set(t.runs.flatMap((r) => (r.results ?? []).map((p) => p.n)))].sort((a, b) => a - b);
  const seq = Object.fromEntries(t.runs.filter((r) => r.mode === "seq").map((r) => [r.engine, r.results?.[0]?.ips]));
  const pl = (k, one, many) => (k === 1 ? one : many);
  const label = (r) => ({ seq: L(lang, "1 client, sequential", "1 client, tuần tự"), one: L(lang, "1 renderer, async", "1 renderer, async"), many: L(lang, `${r.k} ${pl(r.k, "renderer", "renderers")}, async`, `${r.k} renderer, async`), pool: L(lang, `worker pool, ${r.k} ${pl(r.k, "worker", "workers")}`, `worker pool, ${r.k} worker`) }[r.mode]);
  // threads that can work on different images at once: one bm renderer serialises its calls; K renderers are
  // capped by the libuv pool; takumi's one renderer runs up to UV_THREADPOOL_SIZE renders at once (plus rayon
  // helpers inside each); a worker pool has K threads. Efficiency = speed-up / min(N, those slots, logical CPUs).
  const slots = (r) => (r.mode === "pool" ? r.k : r.mode === "many" ? Math.min(r.k, r.uv) : r.mode === "one" ? (r.engine === "bm-native" ? 1 : r.uv) : 1);
  const rows = t.runs.filter((r) => r.mode !== "seq").map((r) => [r.engine, label(r), r.engine.endsWith("native") ? String(r.uv) : "—", ...Ns.map((n) => {
    const p = r.results?.find((q) => q.n === n);
    if (!p) return "—";
    const su = p.ips / seq[r.engine], cap = Math.min(n, slots(r), t.cpus);
    return `${num(p.ips, lang)} (${num(su, lang)}×, ${Math.round((100 * su) / cap)} %)`;
  })]);
  const seqRows = t.runs.filter((r) => r.mode === "seq").map((r) => [r.engine, label(r), r.engine.endsWith("native") ? String(r.uv) : "—", ...Ns.map((n) => (n === 1 ? num(r.results?.[0]?.ips, lang) : ""))]);
  return table([L(lang, "Engine", "Engine"), L(lang, "Setup", "Cách chạy"), "UV_THREADPOOL_SIZE", ...Ns.map((n) => `N=${n}`)], [...seqRows, ...rows]) + "\n\n" +
    L(lang, `Images per second; in brackets the speed-up over the same engine's sequential single-client rate (first rows) and the scaling efficiency = speed-up / min(N, threads that can render different images at once, ${t.cpus} logical CPUs); a bm renderer counts as 1, K renderers as min(K, UV_THREADPOOL_SIZE), takumi-native's renderer as UV_THREADPOOL_SIZE, a worker pool as K. ${t.workload}; ${t.msPerPoint} ms per point after a warm-up. CPU busy during the stage: ${num(t.load?.meanBusyPct, lang)} % mean (other processes ≈ ${num(t.load?.otherCores, lang)} cores).${busyWarn(t.load, lang)}`,
      `Ảnh mỗi giây; trong ngoặc là mức tăng so với tốc độ tuần tự một client của cùng engine (các dòng đầu) và hiệu suất mở rộng = mức tăng / min(N, số thread có thể render các ảnh khác nhau cùng lúc, ${t.cpus} CPU logic); một renderer bm tính là 1, K renderer là min(K, UV_THREADPOOL_SIZE), renderer của takumi-native là UV_THREADPOOL_SIZE, pool worker là K. og card 1200×630 PNG, vòng kín: N client, mỗi client luôn có một yêu cầu đang chạy; ${t.msPerPoint} ms mỗi điểm sau khi khởi động. CPU bận trong lúc đo: trung bình ${num(t.load?.meanBusyPct, lang)} % (tiến trình khác ≈ ${num(t.load?.otherCores, lang)} lõi).${busyWarn(t.load, lang)}`);
};

B.sizes = (res, lang) => {
  const s = res.sizes;
  if (!s) return "";
  const rows = Object.entries(s.native).map(([n, f]) => [`\`bm-engine.${n}.node\``, `\`${f.zigTarget}\``, KiB(f.raw, lang), KiB(f.gzip9, lang), KiB(f.brotli, lang), f.executedHere ? L(lang, "executed (this benchmark)", "đã chạy (benchmark này)") : L(lang, "cross-compiled, structurally verified, never executed", "cross-compile, kiểm tra cấu trúc, chưa từng chạy")]);
  const w = s.wasm;
  const wrows = [["core", w.core], ["standard", w.standard], ["full", w.full], [L(lang, "WOFF add-on", "add-on WOFF"), w.woffAddon]].filter(([, v]) => v).map(([n, v]) => [`bm wasm \`${n}\``, "wasm32", KiB(v.raw, lang), KiB(v.gzip9, lang), KiB(v.brotli, lang), ""]);
  const trows = Object.entries(s.takumi).filter(([, v]) => v).map(([n, v]) => [`takumi 2.20 ${n}`, "", KiB(v.raw, lang), KiB(v.gzip9, lang), KiB(v.brotli, lang), ""]);
  return table([L(lang, "File", "File"), L(lang, "Target", "Target"), "KiB", "gzip -9 KiB", "brotli KiB", L(lang, "Status", "Trạng thái")], [...rows, ...wrows, ...trows]) + "\n\n" +
    L(lang, `Native addons from \`native/dist/manifest.json\` (built ${s.manifestDate?.slice(0, 10)} with Zig ${s.zig}, ReleaseFast). Each user downloads one addon (the optional package for their platform) plus the wasm fallback that ships in the main package.`,
      `Addon native lấy từ \`native/dist/manifest.json\` (build ngày ${s.manifestDate?.slice(0, 10)} với Zig ${s.zig}, ReleaseFast). Mỗi người dùng chỉ tải một addon (gói optional cho nền tảng của họ) cộng với bản wasm dự phòng nằm trong gói chính.`);
};

B.noise = (res, lang) => {
  const s = res.speed;
  const rows = [];
  for (const p of s?.passes ?? []) rows.push([L(lang, `speed pass ${p.pass}`, `speed lượt ${p.pass}`), p.date?.slice(11, 16) ?? "", `${p.seconds} s`, `${num(p.loadBefore?.meanBusyPct, lang)} %`, `${num(p.load?.meanBusyPct, lang)} % (max ${num(p.load?.maxBusyPct, lang)} %)`, num(p.load?.otherCores, lang)]);
  for (const [k, n] of [["cold", res.cold], ["memory", res.memory], ["eventloop", res.eventloop], ["throughput", res.throughput]]) if (n?.load) rows.push([k, "", `${n.load.seconds} s`, "", `${num(n.load.meanBusyPct, lang)} % (max ${num(n.load.maxBusyPct, lang)} %)`, num(n.load.otherCores, lang)]);
  const head = [L(lang, "Stage", "Giai đoạn"), L(lang, "start (UTC)", "bắt đầu (UTC)"), L(lang, "duration", "thời lượng"), L(lang, "CPU busy just before", "CPU bận ngay trước"), L(lang, "CPU busy during", "CPU bận trong lúc đo"), L(lang, "other processes, cores", "tiến trình khác, lõi")];
  const nf = s?.noisyFixtures ? Object.entries(s.noisyFixtures).map(([k, v]) => `${k}: ${v}`).join(", ") : "";
  const absF = (s?.flags ?? []).filter((f) => !f.startsWith("ratio"));
  const ratF = (s?.flags ?? []).filter((f) => f.startsWith("ratio"));
  const absVals = s?.spreadPct ? Object.values(s.spreadPct).flatMap((o) => Object.values(o)).filter((v) => v != null) : [];
  const absMax = absVals.length ? Math.max(...absVals) : null;
  const cpus = res.meta?.cpus ?? 8;
  return table(head, rows) + "\n\n" + L(lang,
    `"Other processes" = busy core-seconds of the whole machine minus the benchmark's own CPU time, per second of wall time (${cpus} logical CPUs). Fixtures whose median moved more than ${NOISE_LIMIT} % between passes: ${nf || "—"}. ${absF.length} absolute geomeans (variant × format) moved more than ${NOISE_LIMIT} % between passes (largest range: ${num(absMax, lang)} %), which is why the tables lead with ratios measured inside each pass. Engine-to-engine ratios that moved more than ${NOISE_LIMIT} %: ${ratF.length ? ratF.join("; ") : "none"}.`,
    `"Tiến trình khác" = số lõi-giây bận của cả máy trừ thời gian CPU của chính benchmark, chia cho thời gian thực (${cpus} CPU logic). Số fixture có median lệch quá ${NOISE_LIMIT} % giữa các lượt: ${nf || "—"}. ${absF.length} geomean tuyệt đối (biến thể × định dạng) lệch quá ${NOISE_LIMIT} % giữa các lượt (khoảng lệch lớn nhất: ${num(absMax, lang)} %), vì vậy các bảng ưu tiên tỉ lệ đo trong từng lượt. Tỉ lệ giữa engine lệch quá ${NOISE_LIMIT} %: ${ratF.length ? ratF.join("; ") : "không có"}.`);
};

B.diagnose = (res, lang) => {
  const d = res.diagnose;
  if (!d?.emptyFrame) return "";
  const vs = VARIANTS;
  const t1 = table([L(lang, "Empty white frame", "Khung trắng rỗng"), ...vs.map(vname)], d.emptyFrame.map((r) => [`${r.width}×${r.height} ${r.format}`, ...vs.map((v) => ms(r.ms[v], lang))]));
  const t2 = table([L(lang, "Animation scene, one 800×420 raw frame", "Cảnh animation, một khung raw 800×420"), ...vs.map(vname)], d.animScene.map((r) => [r.label, ...vs.map((v) => ms(r.ms[v], lang))]));
  return t1 + "\n\n" + t2 + "\n\n" + L(lang,
    `Median ms, variants interleaved (${d.iters} iterations for the empty frames, fewer for the scene). An empty frame draws nothing, so its time is the per-pixel cost every frame pays (canvas clear, alpha conversion, copying the result out) plus, for PNG, encoding a flat image. The scene is the one of the event-loop animation: 12 rotated 60×60 discs with \`box-shadow: 0 8px 30px\` and \`filter: blur(2px)\`.`,
    `Median ms, các biến thể chạy xen kẽ (${d.iters} lần cho khung rỗng, ít hơn cho cảnh). Khung rỗng không vẽ gì, nên thời gian của nó là chi phí theo điểm ảnh mà khung nào cũng trả (xoá canvas, đổi alpha, chép kết quả ra) cộng, với PNG, việc mã hoá một ảnh phẳng. Cảnh là cảnh của animation trong phép đo event loop: 12 hình tròn 60×60 xoay, có \`box-shadow: 0 8px 30px\` và \`filter: blur(2px)\`.`);
};

B.phase1 = (res, lang) => {
  // phase 1 (2026-11-11, docs/BENCHMARK.md "Báo cáo giai đoạn 1"): 78 fixtures, bm wasm phase-1 build, takumi 2.20
  const g = res.speed?.geomean, ng = res.speed?.geomeanNonGap, c = res.cold?.engines;
  const rows = [
    [L(lang, "takumi-native raw geomean, ms", "takumi-native raw geomean, ms"), "1.99", ms(g?.["takumi-native:async"]?.raw, lang), ms(ng?.["takumi-native:async"]?.raw, lang)],
    [L(lang, "bm wasm raw geomean, ms", "bm wasm raw geomean, ms"), "1.45", ms(g?.["bm-wasm:sync"]?.raw, lang), ms(ng?.["bm-wasm:sync"]?.raw, lang)],
    [L(lang, "takumi-wasm raw geomean, ms", "takumi-wasm raw geomean, ms"), "—", ms(g?.["takumi-wasm:async"]?.raw, lang), ms(ng?.["takumi-wasm:async"]?.raw, lang)],
    [L(lang, "takumi-native cold start, ms", "takumi-native cold start, ms"), L(lang, "44.8 (in-process: init + font + first PNG)", "44.8 (trong tiến trình: init + font + PNG đầu)"), `${ms(c?.["takumi-native"]?.inProcessMs, lang)} ${L(lang, "in-process", "trong tiến trình")}; ${ms(c?.["takumi-native"]?.overNodeMedianMs, lang)} ${L(lang, "over empty Node", "so với Node rỗng")}`, ""],
  ];
  return table([L(lang, "Number", "Số liệu"), L(lang, "phase 1 (78 fixtures)", "giai đoạn 1 (78 fixture)"), L(lang, `now, all ${res.speed?.fixturesTimed?.raw ?? "?"} fixtures`, `bây giờ, cả ${res.speed?.fixturesTimed?.raw ?? "?"} fixture`), L(lang, "now, without known-gaps", "bây giờ, bỏ known-gaps")], rows);
};

B["per-fixture"] = (res, lang) => {
  const fx = res.speed?.fixtures;
  if (!fx) return "";
  const r = (row, a, b, f) => (row.perf[a]?.[f]?.median > 0 && row.perf[b]?.[f]?.median > 0 ? row.perf[a][f].median / row.perf[b][f].median : null);
  const cell = (row, v, f) => { const p = row.perf[v]?.[f]; return p?.median ? `${ms(p.median, lang)} / ${ms(p.p95, lang)}` : p?.error ? "error" : "—"; };
  const rows = fx.map((row) => [`\`${row.id}\``, row.feature, ...["raw", "png"].flatMap((f) => [cell(row, "bm-native:sync", f), cell(row, "bm-native:async", f), cell(row, "bm-wasm:sync", f), cell(row, "takumi-native:async", f), cell(row, "takumi-wasm:async", f), x(r(row, "bm-native:async", "takumi-native:async", f), lang), x(r(row, "bm-native:sync", "bm-wasm:sync", f), lang)])]);
  const h = (f) => [`${f} bm-n sync`, `${f} bm-n async`, `${f} bm-w`, `${f} tk-n`, `${f} tk-w`, `${f} bm-n/tk-n`, `${f} bm-n/bm-w`];
  return table(["Fixture", L(lang, "Category", "Nhóm"), ...h("raw"), ...h("png")], rows) + "\n\n" +
    L(lang, "median / p95 ms per fixture (median over the passes of each pass's median and p95). Ratios: bm-native async / takumi-native async, bm-native sync / bm-wasm sync.",
      "median / p95 ms từng fixture (median qua các lượt của median và p95 mỗi lượt). Tỉ lệ: bm-native async / takumi-native async, bm-native sync / bm-wasm sync.");
};

// ------------------------------------------------------------------------------------------------ output
export const DOCS = ["docs/BENCHMARK.md", "docs/en/benchmark.md", "docs/vi/benchmark.md"];
const langOf = (file) => (/(^|\/)vi\//.test(file) || /BENCHMARK\.md$/.test(file) ? "vi" : "en");

/** Rewrites every native-bench block of `text`; returns { text, blocks }. */
export function fillBlocks(text, res, lang) {
  let blocks = 0;
  const re = /(<!-- native-bench:([a-z-]+) -->)[\s\S]*?(<!-- \/native-bench:\2 -->)/g;
  const out = text.replace(re, (all, open, name, close) => {
    if (!B[name]) throw new Error("unknown native-bench block " + name);
    blocks++;
    return `${open}\n${B[name](res, lang)}\n${close}`;
  });
  return { text: out, blocks };
}

/** The full Markdown report (English) and, with docs: true, the doc blocks rewritten in place. */
export function renderAll(res, { docs = true, root } = {}) {
  const order = ["env", "highlights", "summary", "ratios", "speed", "cpu", "categories", "best-worst", "formats", "equiv", "cold", "memory", "eventloop", "throughput", "sizes", "diagnose", "phase1", "noise", "per-fixture"];
  const md = ["# Native benchmark: bm-native, bm-wasm, takumi-native, takumi-wasm", "", "Generated by `node bench/run-native.mjs` from `results-native.json`; do not edit.", ""];
  for (const b of order) { const body = B[b](res, "en"); if (body) md.push(`## ${b}`, "", body, ""); }
  if (docs && root) {
    for (const rel of DOCS) {
      const p = path.join(root, rel);
      if (!existsSync(p)) continue;
      const raw = readFileSync(p, "utf8");
      const crlf = raw.includes("\r\n"); // keep the file's line endings (git autocrlf checkouts are CRLF)
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
  const file = process.argv.slice(2).find((a) => !a.startsWith("--")) ?? path.join(root, "bench", "out", "native", "results-native.json");
  const res = JSON.parse(readFileSync(file, "utf8"));
  if (process.argv.includes("--reaggregate")) {
    // recompute res.speed from the raw pass files next to the JSON (after a change of the aggregation code)
    const dir = path.dirname(file);
    const passes = (res.speed?.passes ?? []).map((p) => {
      const j = JSON.parse(readFileSync(path.join(dir, `speed-pass${p.pass}.tmp.json`), "utf8"));
      return { ...p, durationMs: j.durationMs, cfg: j.cfg, date: j.date, cases: j.cases };
    });
    res.speed = aggregateSpeed(passes);
    writeFileSync(file, JSON.stringify(res, null, 1));
    console.error(`re-aggregated ${passes.length} speed passes into ${file}`);
  }
  const docs = !process.argv.includes("--no-docs");
  const md = renderAll(res, { docs, root });
  writeFileSync(path.join(root, "bench", "out", "native", "NATIVE.md"), md);
  console.error(`wrote bench/out/native/NATIVE.md${docs ? " and the doc blocks" : ""}`);
}
