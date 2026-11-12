# bench/pdf — external validation, visual equivalence and benchmark of the PDF output

Tooling that checks `bm-engine/pdf` from the outside and measures it against
[takumi-pdf](https://www.npmjs.com/package/takumi-pdf), the library it ports. Everything runs headless from the
command line on whatever build is in the checkout it runs in (the repository root is resolved from the scripts'
location) and exits non-zero on failure, so each script can serve as a gate.

```sh
node bench/pdf/setup.mjs       # npm deps into bench/pdf/node_modules + external tools into bench/pdf/tools/ (verified)
node bench/pdf/validate.mjs    # -> bench/out/pdf/validation.json + VALIDATION.md
node bench/pdf/visual.mjs      # -> bench/out/pdf/visual.json + VISUAL.md + visual/sheets/*.png + visual/worst/*.png
node bench/pdf/bench.mjs       # -> bench/out/pdf/results-pdf.json + PDF.md + docs/results-pdf.json + doc tables
node bench/pdf/report.mjs      # re-render PDF.md and the doc tables from results-pdf.json (no measuring)
```

bm-native needs the native addon of the checkout (`node scripts/build-native.mjs --target=win32-x64-msvc`, i.e.
`native/dist/<platform>/`, or `BM_ENGINE_NATIVE_PATH`); without it every script runs with bm-wasm and takumi-pdf
only and says so. The wasm build is `js/bm_engine.pdf.wasm` (`npm run build:pdf`).

## Layout

| Path | What |
|:--|:--|
| `setup.mjs`, `tools.json` | Reproducible setup: exact versions, URLs, SHA-256 of every external tool; publisher checksums verified at download |
| `engines.mjs` | `bm-native`, `bm-wasm`, `takumi-pdf` adapters with one call shape (`registerFont`, `render`, `renderSync`, `renderImage`, `memoryBytes`) |
| `corpus/` | `golden.mjs`: the inputs of takumi-pdf's 89 goldens, sliced at run time from `scripts/pdf-compare.mjs` (+ `pdf-interchange.mjs`, `pdf-tagging-fixtures.mjs`), so they never drift; `docs.mjs`: the guide documents (invoice, report with a repeating table header, ticket, multi-page text, header/footer page rules, links + outline, PNG/JPEG/SVG images, gradients/shadows, RTL/CJK/emoji, PDF/UA-1/-2, PDF/A 2b/2u/2a/3b/3u/3a/4/4f, attachments) and the stress documents (1/10/100/500 pages of text, tables and images) |
| `lib/build.mjs` | Renders the corpus with every engine into `bench/out/pdf/pdfs/<engine>/` + `manifest.json` (byte identity bm-native == bm-wasm and bm-native sync == async recorded per document; documents of 100+ pages render in a fresh process each, so an engine running out of memory cannot end the run). `node bench/pdf/lib/build.mjs` rebuilds; the other scripts reuse the last build unless `--rebuild` |
| `lib/pdfjs.mjs`, `lib/raster.mjs` | pdf.js inspection (text, links, outline, attachments, structure tree, metadata, warnings) and three rasterisers (PDFium wasm, MuPDF wasm, pdf.js on Skia) |
| `bench/*.mjs` | Child processes of `bench.mjs` (speed pass, cold start, scaling, memory, event loop, throughput + worker pool) |

## What each tool checks

| Tool | Version (tools.json / package.json) | Checks | Source |
|:--|:--|:--|:--|
| qpdf | 12.4.2 (msvc64 zip) | `qpdf --check`: syntax, xref, object streams, stream filters; linearization status | GitHub release, SHA-256 from `qpdf-12.4.2.sha256` |
| pdfcpu | 0.16.4 | `pdfcpu validate -m strict` (PDF 32000-1 rules, a Go parser independent of the others) | GitHub release, SHA-256 from `checksums.txt` |
| poppler | 26.09.0 (poppler-windows) | `pdfinfo` (parse + syntax warnings on stderr), `pdffonts` (every font embedded, subset, with a ToUnicode map) | GitHub release, SHA-256 = GitHub asset digest |
| veraPDF | 1.28.2 greenfield CLI jar | PDF/A-2a/2b/2u/3a/3b/3u/4/4f and PDF/UA-1/-2 profiles, per the conformance each document asks for | Maven Central, SHA-1 from the `.jar.sha1`; SHA-256 pinned |
| Java | Eclipse Temurin 21.0.13+9 JRE zip | runs veraPDF only (portable: no install, no JAVA_HOME/PATH change) | Adoptium, SHA-256 from the `.sha256.txt` |
| MuPDF | npm `mupdf` 1.28.6 (wasm) | open, load every page, extract text, draw; every warning it logs; xref repair | npm (lockfile integrity) |
| pdf.js | npm `pdfjs-dist` 6.5.438 (legacy build) | everything a viewer reads: page sizes, text per page, link targets and rects, outline, attachments, structure tree, metadata + XMP, mark info; every warning | npm |
| PDFium | npm `@hyzyla/pdfium` 3.0.0 (wasm) | rasteriser | npm |
| pdf.js + Skia | `pdfjs-dist` + `@napi-rs/canvas` 1.1.1 | third rasteriser (`--rasterisers=pdfium,mupdf,pdfjs`) | npm (prebuilt binary package, no install script) |

`validate.mjs` also compares bm with takumi-pdf semantically through pdf.js (same page count and sizes, same text in
the same order per page, same link targets and rects within 1 pt, same outline, attachments, structure tree roles,
metadata and XMP conformance claims) and checks that the XMP `pdfaid` / `pdfuaid` claims match the options. Every issue
on a bm PDF is classified **shared** (takumi-pdf's PDF of the same input has the same issue from the same tool) or
**bm-only**. Gates: `--gate=all` (default: any error/warning on a bm PDF, any byte-identity mismatch, any bm render
error), `--gate=bm-only`, `--gate=none`.

`visual.mjs` rasterises bm-native's and takumi-pdf's PDF of every input with the same rasteriser at 96 and 144 dpi
and compares each page with the image suite's metrics (`bench/lib/metrics.mjs`: identical / equivalent = SSIM >= 0.99
and <= 0.5 % pixels / close / different); a verdict that depends on the rasteriser is flagged. For the single-page
(viewport) documents it also compares bm's PDF raster at 96 dpi with bm's own PNG render of the same tree. Gate: a
document "different" under every rasteriser.

`bench.mjs` stages (`--stages=`; the JSON is merged per stage, so one stage can be re-measured cheaply):
`speed` (warm render time per document, variants interleaved, 3 passes at different moments, spread flagged > 10 %),
`sizes` (raw bytes and after the same qpdf recompression), `scale` (1/10/100/500 pages: time, pages/s, bytes, peak
RSS), `cold` (fresh process -> import -> one font -> first one-page PDF -> exit, 30 runs, minus empty Node),
`memory` (RSS and engine memory after 1 and 10 passes over the guide documents), `eventloop` (max 1 ms timer delay
during a 100-page render, sync vs async), `throughput` (N = 1/2/4/8 concurrent invoices: bm-native over K renderers
with UV_THREADPOOL_SIZE 4 and 8, wasm engines in worker pools), `equiv` (summary of validate/visual + identity). It
records the machine's CPU busy % before and during every stage. `--quick` shortens everything.

## Known limitations

- **takumi-pdf has no native build.** npm has only `takumi-pdf` (wasm + JS); no `@takumi-rs/pdf-*` or optional
  dependency exists (0.20.0). Its async `render()` runs on the calling thread.
- **mutool (MuPDF CLI) does not run here**: the official `mupdf-1.28.5-windows.zip` binary needs the Visual C++ /
  UCRT redistributable installed system-wide (fails with STATUS_DLL_NOT_FOUND); MuPDF is used through the official
  `mupdf` npm wasm package instead (same engine version line, same warnings).
- **PAC** (PDF Accessibility Checker) is GUI-only: not usable headless. veraPDF's PDF/UA profiles are the machine
  check; the Matterhorn checks that need human judgement are not covered by any tool here.
- **PDF/A-1** is not offered by bm-engine or takumi-pdf (PDF/A-2/3/4 only), so the 1b profile is not run.
- veraPDF runs with `--maxfailuresdisplayed 5`: the report lists every failed rule, with up to 5 failing contexts.
- pdf.js and MuPDF print warnings through `console`; the scripts capture them per document. A warning a library
  prints asynchronously after the document is closed could be missed.
- Linearization: neither engine writes linearized PDFs; the status is reported, not gated.
- Rasterisers round a page's pixel size differently (PDFium floors, MuPDF/pdf.js round up): comparisons crop to the
  common size; bm and takumi-pdf are always compared under the same rasteriser.
- The machine this was first run on was shared with compile jobs: absolute timings are noisy; read the interleaved
  ratios and the flagged spreads.

## npm scripts (for the root package.json; not added by this directory)

```json
"pdf:setup": "node bench/pdf/setup.mjs",
"pdf:validate": "node bench/pdf/validate.mjs",
"pdf:visual": "node bench/pdf/visual.mjs",
"pdf:bench": "node bench/pdf/bench.mjs",
"pdf:bench:quick": "node bench/pdf/bench.mjs --quick",
"pdf:bench:report": "node bench/pdf/report.mjs"
```
