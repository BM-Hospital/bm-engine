// Markdown generator: renderMarkdown(results) -> string. Pure function of results.json.
const ENG = ["takumi-wasm", "takumi-native", "bm"];
const f1 = (v, d = 2) => (typeof v === "number" && isFinite(v) ? v.toFixed(d) : "–");
const kb = (b) => (b == null ? "–" : (b / 1024).toFixed(1) + " KiB");
const mb = (b) => (b == null ? "–" : (b / 1048576).toFixed(1) + " MiB");
const cell = (s) => String(s ?? "–").replace(/\|/g, "\\|").replace(/\n/g, " ");
const table = (head, rows) => {
  // right-align a column only if every non-empty cell looks numeric
  const num = head.map((_, i) => i > 0 && rows.every((r) => r[i] == null || r[i] === "" || /^[-+0-9.–]/.test(String(r[i]))));
  return [`| ${head.join(" | ")} |`, `| ${head.map((_, i) => (num[i] ? "--:" : ":--")).join(" | ")} |`, ...rows.map((r) => `| ${r.map(cell).join(" | ")} |`)].join("\n");
};
const geo = (a) => (a.length ? Math.exp(a.reduce((s, x) => s + Math.log(x), 0) / a.length) : null);
const isOk = (m) => m && !m.error && typeof m.median === "number";

export function renderMarkdown(R) {
  const out = [];
  const avail = (n) => R.meta.engines?.[n]?.available;
  const present = ENG.filter(avail);
  const hasBm = avail("bm");
  out.push("# bm-render vs takumi — benchmark & equivalence results", "");
  out.push(`- Date: ${R.meta.date}  |  Node ${R.meta.node}  |  ${R.meta.platform}`);
  out.push(`- CPU: ${R.meta.cpu} (${R.meta.cpus} logical)  |  RAM ${R.meta.totalMemGB} GB`);
  out.push(`- Command: \`node run.mjs ${(R.meta.args || []).join(" ")}\`  |  iterations: ${R.meta.config.iters ? "fixed " + R.meta.config.iters : `>=${R.meta.config.minIters} and >=${R.meta.config.minMs}ms (cap ${R.meta.config.maxMs}ms), ${R.meta.config.warmup} warm-up`}`);
  out.push("- Engines: " + ENG.map((n) => `${n} = ${R.meta.engines?.[n]?.status ?? "n/a"}`).join(", "));
  out.push("- Times are milliseconds per `render()` call (median; p95 in parentheses). Ratio = bm / takumi-wasm (lower is better for bm; <1 means bm is faster).", "");

  // ---- sizes
  out.push("## Binary & glue size", "");
  const sRows = [];
  for (const n of ENG) {
    const s = R.sizes?.[n]; if (!s) continue;
    for (const [what, key, file] of [["binary", "binary", s.binaryFile], ["JS glue", "glue", s.glueFile]]) {
      const v = s[key]; sRows.push([n, `${what} (${file ?? ""})`, v ? kb(v.raw) : "missing", v ? kb(v.gzip9) : "–", v ? kb(v.brotli) : "–"]);
    }
  }
  out.push(table(["engine", "artifact", "raw", "gzip -9", "brotli"], sRows), "");

  // ---- cold start
  out.push("## Cold start (fresh `node` process, median of runs)", "");
  const cRows = ENG.filter((n) => R.cold?.[n]).map((n) => { const c = R.cold[n]; return c.error ? [n, `error: ${c.error}`, "", "", "", ""] : [n, c.runs, f1(c.initMs), f1(c.fontMs), f1(c.firstRenderMs), f1(c.totalMs)]; });
  out.push(cRows.length ? table(["engine", "runs", "wasm compile+instantiate (native: addon load) ms", "register Inter-Regular ms", "first render (og-card, png) ms", "total ms"], cRows) : "_cold start not measured_", "");

  // ---- memory
  out.push("## Memory (child process: all fonts, 50 og-card PNG renders)", "");
  const mRows = ENG.filter((n) => R.memory?.[n]).map((n) => { const m = R.memory[n]; return m.error ? [n, `error: ${m.error}`, "", ""] : [n, mb(m.maxRssKB * 1024), mb(m.wasmMemoryBytesAfterInit), mb(m.wasmMemoryBytesAfter50)]; });
  if (mRows.length) out.push(table(["engine", "peak RSS (maxRSS)", "wasm linear memory after init+fonts", "wasm linear memory after 50 renders"], mRows), "", `Bare \`node\` baseline peak RSS: ${mb((R.memory.nodeBaselineMaxRssKB ?? 0) * 1024)}.`, "");
  else out.push("_memory not measured_", "");
  if (R.memory?.poolWasmLinearMemory) out.push("Wasm linear memory at end of the full case run (largest instance): " + Object.entries(R.memory.poolWasmLinearMemory).map(([n, b]) => `${n} ${mb(b)}`).join(", ") + ".", "");

  // ---- equivalence
  const cases = R.cases;
  const cands = ["bm", "takumi-native"].filter((n) => cases.some((c) => c.cmp?.[n]));
  if (cases.some((c) => c.cmp)) {
    out.push("## Output equivalence (reference = takumi-wasm, `format: raw`)", "");
    out.push("Verdict rules: **identical** = 0 differing bytes; **equivalent** = SSIM >= 0.99 and <= 0.5% pixels differing (pixelmatch thr 0.1, includeAA=true); **close** = SSIM >= 0.95 and <= 5% pixels differing; else **different**. `error/unsupported` when an engine threw. " +
      "SSIM = mean over uniform 8x8 windows (stride 1) of luma over white; `SSIM RGB` = mean of per-channel SSIMs (catches chroma-only changes). Verdicts use min(luma, RGB). `px strict/AA` = pixelmatch count with includeAA true / false. `native` rows are the noise-floor baseline (same Rust code, different build).", "");
    out.push("### Verdict summary", "");
    const vs = ["identical", "equivalent", "close", "different", "error/unsupported"];
    out.push(table(["candidate", ...vs], cands.map((n) => [n, ...vs.map((v) => cases.filter((c) => c.cmp?.[n]?.verdict === v).length)])), "");
    for (const n of cands) {
      out.push(`### ${n} vs takumi-wasm`, "");
      const rows = cases.filter((c) => c.cmp?.[n]).map((c) => {
        const m = c.cmp[n];
        return m.error && !("ssim" in m) ? [c.id, c.feature, m.verdict, "", "", "", "", "", "", "", m.error.slice(0, 80)] :
          [c.id, c.feature, m.verdict, f1(m.ssim, 4), f1(m.ssimRgb, 4), f1(m.pctStrict, 3), f1(m.pctAA, 3), m.pmStrict + " / " + m.pmAA, f1(m.meanAbs, 3), m.maxAbs, f1(m.psnr, 1)];
      });
      out.push(table(["case", "feature", "verdict", "SSIM luma", "SSIM RGB", "% diff strict", "% diff AA-tol", "px strict / AA", "mean abs", "max abs", "PSNR dB"], rows), "");
    }
    // noise floor stats
    const nat = cases.filter((c) => c.cmp?.["takumi-native"] && "ssim" in c.cmp["takumi-native"]);
    if (nat.length) {
      const worst = [...nat].sort((a, b) => a.cmp["takumi-native"].ssim - b.cmp["takumi-native"].ssim)[0];
      out.push(`Noise floor (native vs wasm): ${nat.filter((c) => c.cmp["takumi-native"].identical).length}/${nat.length} identical; lowest SSIM ${f1(worst.cmp["takumi-native"].ssim, 5)} on \`${worst.id}\`.`, "");
    }
  }

  // ---- performance
  const perfCases = cases.filter((c) => c.perf);
  if (perfCases.length) {
    out.push("## Performance", "");
    const val = (c, n, f) => c.perf?.[n]?.[f];
    const show = (m) => (isOk(m) ? `${f1(m.median)} (${f1(m.p95)})` : m?.error ? "error" : "–");
    const ratio = (c, f) => { const a = val(c, "bm", f), b = val(c, "takumi-wasm", f); return isOk(a) && isOk(b) ? a.median / b.median : null; };
    for (const f of ["raw", "png"]) {
      out.push(`### \`format: ${f}\` — median ms (p95)`, "");
      const head = ["case", "feature", "size", ...present.map((n) => n), ...(hasBm ? ["bm / takumi-wasm"] : []), "native / wasm"];
      const rows = perfCases.map((c) => {
        const nr = isOk(val(c, "takumi-native", f)) && isOk(val(c, "takumi-wasm", f)) ? val(c, "takumi-native", f).median / val(c, "takumi-wasm", f).median : null;
        return [c.id, c.feature, `${c.width}x${c.height}`, ...present.map((n) => show(val(c, n, f))), ...(hasBm ? [f1(ratio(c, f))] : []), f1(nr)];
      });
      out.push(table(head, rows), "");
    }
    // feature summary
    out.push("### Per-feature summary (geometric mean of per-case median ratios)", "");
    const feats = [...new Set(perfCases.map((c) => c.feature))];
    const sumRows = feats.map((ft) => {
      const cs = perfCases.filter((c) => c.feature === ft);
      const g = (fmt, a, b) => geo(cs.map((c) => { const x = val(c, a, fmt), y = val(c, b, fmt); return isOk(x) && isOk(y) ? x.median / y.median : null; }).filter((v) => v));
      const w = (fmt) => geo(cs.map((c) => val(c, "takumi-wasm", fmt)).filter(isOk).map((m) => m.median));
      return [ft, cs.length, f1(w("raw")), f1(w("png")), ...(hasBm ? [f1(g("raw", "bm", "takumi-wasm")), f1(g("png", "bm", "takumi-wasm"))] : []), f1(g("raw", "takumi-native", "takumi-wasm")), f1(g("png", "takumi-native", "takumi-wasm"))];
    });
    out.push(table(["feature", "cases", "takumi-wasm raw ms (geomean)", "takumi-wasm png ms (geomean)", ...(hasBm ? ["bm/wasm raw", "bm/wasm png"] : []), "native/wasm raw", "native/wasm png"], sumRows), "");
    if (hasBm) {
      const all = (f) => geo(perfCases.map((c) => ratio(c, f)).filter((v) => v));
      out.push(`Overall geomean bm / takumi-wasm: raw **${f1(all("raw"))}**, png **${f1(all("png"))}**.`, "");
    }
    // formats
    const fmtCases = perfCases.filter((c) => ["jpeg", "webp"].some((f) => present.some((n) => val(c, n, f))));
    if (fmtCases.length) {
      out.push("### Encoders: jpeg (q85) and webp (default/lossless) — median ms (p95) and encoded bytes", "");
      const rows = [];
      for (const c of fmtCases) for (const f of ["png", "jpeg", "webp"]) rows.push([c.id, f, ...present.map((n) => { const m = val(c, n, f); return isOk(m) ? `${show(m)} · ${kb(m.bytes)}` : m?.error ? "error: " + m.error.slice(0, 40) : "–"; })]);
      out.push(table(["case", "format", ...present], rows), "");
    }
  }

  // ---- errors
  const errs = [];
  for (const c of cases) {
    if (c.equivError) errs.push([c.id, "harness", c.equivError]);
    for (const [n, r] of Object.entries(c.renders ?? {})) if (r.error) errs.push([c.id, n + " (render raw)", r.error]);
    for (const [n, byF] of Object.entries(c.perf ?? {})) for (const [f, m] of Object.entries(byF)) if (m?.error) errs.push([c.id, `${n} (perf ${f})`, m.error]);
    for (const [n, m] of Object.entries(c.cmp ?? {})) if (m.sizeMismatch) errs.push([c.id, n + " (compare)", m.error]);
  }
  out.push("## Errors", "");
  out.push(errs.length ? table(["case", "engine / stage", "message"], errs) : "None.", "");
  for (const n of ENG) if (R.meta.engines?.[n] && !avail(n)) out.push(`- engine \`${n}\`: ${R.meta.engines[n].status}`);
  return out.join("\n") + "\n";
}
