# bench — bm-engine vs takumi: benchmark + output-equivalence harness

Node 26, ESM, Windows. Compares on identical inputs:

| engine | what | source |
| --- | --- | --- |
| `takumi-wasm` | `@takumi-rs/wasm` (reference for equivalence) | `node_modules/@takumi-rs/wasm` |
| `takumi-native` | `@takumi-rs/core` N-API (noise-floor baseline, perf reference) | `node_modules/@takumi-rs/core` |
| `bm` | bm-engine Zig->WASM (`../js/node.mjs` + `../zig-out/bin/bm_engine.wasm`) | marked **unavailable** when either file is missing; per-case throws become `error: <msg>` |

Everything is read-only with respect to the repo outside `bench/`.

## Commands (run from `D:\project\bm-engine\bench`)

```
npm run bench                    # full run: equivalence + perf + cold start + memory + sizes (several minutes)
npm run bench:quick              # same with short timing budgets
node run.mjs --filter=card|text  # only cases whose id or feature matches the regex (case-insensitive)
node run.mjs --iters=50          # fixed iteration count instead of adaptive (>=20 iters & >=300 ms, cap 2 s)
node run.mjs --engines=takumi-wasm,takumi-native   # restrict engines (anything else shows as "not selected")
node run.mjs --no-perf | --no-equiv | --no-cold    # skip a stage;  --cold-runs=7  --out=out2
npm run report                   # regenerate out/RESULTS.md from out/results.json (node report.mjs [results.json])
npm run selftest                 # metrics self-checks + equivalence pipeline fed by perturbed copies of takumi output
node probe/sheet.mjs takumi 12   # contact sheets out/sheets/*.png for eyeballing (kind: takumi|bm|native|diff)
```

Outputs: `out/results.json` (machine readable: meta incl. node version/CPU/date, sizes, cold, memory, per-case equivalence + perf),
`out/RESULTS.md` (tables), `out/<case-id>/{takumi,bm,native,diff}.png` (`diff.png` = first candidate vs takumi-wasm, bm if present;
`diff-native.png` when both exist; raw straight-alpha RGBA encoded as-is).

## Engine adapter interface (`engines/*.mjs`, default export)

```js
{ name, available: boolean, wasmPath?, rawAlpha: "straight"|"premultiplied",
  async create({ fonts: [{ name, path, weight, style }] }) -> {
      name, initMs,                              // initMs: wasm compile+instantiate (native: addon load)
      async registerFont({ name, path, weight, style } | { ..., data }),
      render(node, opts) -> Promise<Uint8Array>, // opts: { width, height, format, quality, devicePixelRatio, images }
      measure?(node, opts), memoryBytes?(): number, dispose() } }
```
Fonts are registered into every engine with explicit family name / weight / style (see `lib/fonts.mjs`; Inter 400/600/700/400-italic,
Noto Sans 400/700, Roboto 400/700/400-italic). `takumi-wasm` imports `dist/export.mjs` directly and calls `initSync` itself so it keeps the
returned `memory` (`memoryBytes()` = `memory.buffer.byteLength`). `bm` calls `new Renderer()`, `registerFont({name,data,weight,style})`,
`render`, and `Renderer#memoryBytes()` (or static) if present.
If bm's `raw` output turns out to be premultiplied, set `rawAlpha: "premultiplied"` in `engines/bm.mjs`; the runner un-premultiplies.

### takumi `format:"raw"` layout
Straight (non-premultiplied) RGBA8, row-major, `width*height*4` bytes (both wasm and native). Verified with `probe/alpha.mjs`:
a `rgba(255,0,0,0.5)` fill gives pixels `255,0,0,128` (premultiplied would be `128,0,0,128`).

## Fixtures (`fixtures/*.mjs`, aggregated by `fixtures/index.mjs`)
Each case: `{ id, feature, title, width, height, node, images?, fonts? (family-name list; default all), notes? }`. Node format is takumi's.
Containers always set `display:"flex"` + `flexDirection`, text always sets `fontFamily`. Image bytes come from `assets/` (copied from the takumi
clone: `photo.jpg` 1920x1280 JPEG, `cover.jpg` 525x525 JPEG, `avatar.png` 400x400 PNG, `icon.png` 128x128 PNG), referenced as `img://name`.
`FORMAT_CASES` (flat UI card `card-flat-ui`, gradient-heavy `lingrad-angles`, photo `img-photo-bg`) additionally get jpeg (q85) and webp timing + byte size.

## Metrics & verdicts (`lib/metrics.mjs`)
For each case `raw` is rendered per engine, converted to straight RGBA, then bm and takumi-native are each compared to takumi-wasm:
size check; `pixelmatch` (threshold 0.1) with `includeAA:true` (strict) and `false` (AA tolerant); % differing; mean abs channel diff (RGBA);
max abs diff; PSNR (cap 100); SSIM = uniform 8x8 windows, stride 1, C1=(0.01*255)^2, C2=(0.03*255)^2, on luma over white, plus an RGB variant
(mean of per-channel SSIM) because luma SSIM is chroma-blind. Verdict uses min(luma, RGB):

* `identical` — every byte equal
* `equivalent` — SSIM >= 0.99 and <= 0.5% pixels differ (strict pixelmatch)
* `close` — SSIM >= 0.95 (and <= 5% pixels differ)
* `different` — otherwise, or size mismatch
* `error/unsupported` — an engine threw (message recorded)

## Performance method
Per case and per format (`raw`, `png`; plus `jpeg`/`webp` on 3 cases): >= 3 warm-up renders, then adaptive iterations (>=20 and >=300 ms, capped at
2 s per measurement), split into 2 alternating rounds with engines interleaved to reduce drift. `performance.now()` around `await render()`.
Reported: median, p95, min, n, encoded bytes. Note takumi-wasm webp is always lossless.

## Cold start / memory / size
`lib/cold.mjs <engine>` runs in a fresh `node` child (7x, median): wasm compile+instantiate (native: addon load), register Inter-Regular,
first `card-og` PNG render, total. `lib/cold.mjs <engine> --mem`: registers all fonts, 50 og-card PNG renders, reports `process.resourceUsage().maxRSS`
and wasm linear memory before/after. `lib/sizes.mjs`: raw / gzip -9 / brotli (q11) of each `.wasm` (native: `.node`) and JS glue
(takumi `dist/export.mjs` vs bm `js/*.mjs`).

## Browser test

Runs the engine in a real Chromium-based browser (Edge or Chrome, found automatically; no download) driven by `puppeteer-core`, and compares it with Node.

```powershell
cd D:\project\bm-engine\bench
npm run browser:quick                 # 12 representative cases
npm run browser                       # every case except "known-gaps"
node browser/run.mjs --filter=text --iters=30 --no-takumi --browser="C:\path\to\chrome.exe"
```

What it does: serves the repo root on `127.0.0.1` (`browser/server.mjs`), loads `browser/page.html` (+ `page.mjs`, which streams `js/bm_engine.wasm`, registers the 9 fixture fonts and exposes `bmRender`/`bmBench`), sends each fixture over as JSON + base64 images, and checks (a) raw output is byte-identical to the Node render of the same wasm, (b) png/webp/jpeg decode in the browser (`createImageBitmap`) and match the raw render (opaque pixels +-1, jpeg mean abs diff < 3), (c) in-page timings vs Node, (d) `examples/browser.html` shows an image, and that no console errors/exceptions occur. It also tries `@takumi-rs/wasm` in the same browser through an import map for a browser-side comparison. Output: `out/browser-results.json`, `out/BROWSER.md`; exit code is non-zero on any failed assertion.
