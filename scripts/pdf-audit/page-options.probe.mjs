// Audit probes: page size, landscape and margins (page.size.*, page.landscape.*, page.margin.*).
//
// Method, shared with the other page-*, pagination-*, bands and counters probe files (helpers in
// paged-helpers.mjs): each probe renders the same input with bm-engine/pdf and with the
// published takumi-pdf and compares page count, page boxes and the text of each page (numbered lines L01, L02 ...
// show where the pages were cut); `geom` also compares the position of every word (pdftotext -bbox).
//
//   TAKUMI_PDF_REF=<dir> node scripts/pdf-audit/run.mjs page. pagination. bands. counters.
//
// A probe that FAILS records a difference from takumi-pdf (the failure line shows both outputs); it is kept
// failing on purpose until the engine is fixed.
import { probe } from "./lib.mjs";
import { SMALL, cmp, cmpAll, doc, lines, stripPrefix } from "./paged-helpers.mjs";

const D30 = doc(lines(1, 30));
const D3 = doc(lines(1, 3));
const S = { width: 300, height: 200 };
const G = { geom: true };

// ------------------------------------------------------------------------------------------------ page options

probe("page.error-prefix", "error messages: bm-engine prefixes 'bm-engine: '", async (t) => {
  const r = await t.both(D3, { size: "tabloid" });
  t.same("message without the prefix", stripPrefix(r.bm.error), r.ref && r.ref.error);
  t.same("message verbatim (bm adds 'bm-engine: ')", r.bm.error, r.ref && r.ref.error);
});

for (const n of ["a3", "a4", "a5", "b4", "b5", "jis-b4", "jis-b5", "ledger", "legal", "letter"]) {
  probe(`page.size.preset.${n}`, "page size presets", async (t) => { await cmp(t, n, D3, { size: n }, G); });
}
probe("page.size.preset.case-insensitive", "page size presets: case-insensitive names", async (t) => {
  for (const n of ["A4", "Letter", "JIS-B5", "LeGaL"]) await cmp(t, n, D3, { size: n }, { expect: "render" });
});
probe("page.size.preset.unknown", "page size presets: unknown name error", async (t) => {
  for (const n of ["tabloid", " a4", "", "a6", "jis_b5"]) await cmp(t, JSON.stringify(n), D3, { size: n }, { expect: "error" });
});
probe("page.size.default-a4", "page size default (A4, auto margins)", async (t) => {
  await cmp(t, "no options", doc(lines(1, 80)), {}, G);
  await cmp(t, "size null", D3, { size: null });
});
probe("page.size.explicit", "explicit page sizes", async (t) => {
  await cmpAll(t, [
    ["300x200", D30, { size: S }],
    ["fractional", D30, { size: { width: 300.5, height: 200.25 }, margin: 10 }],
    ["huge", D3, { size: { width: 1e6, height: 1e6 } }],
  ], G);
});
probe("page.size.explicit.invalid", "explicit page sizes: zero / negative error", async (t) => {
  await cmpAll(t, [
    ["width 0", D30, { size: { width: 0, height: 200 } }],
    ["width -5", D30, { size: { width: -5, height: 200 } }],
    ["height 0", D30, { size: { width: 300, height: 0 } }],
  ], { expect: "error" });
});
probe("page.size.explicit.invalid-nan", "explicit page sizes: NaN / Infinity error text", async (t) => {
  await cmpAll(t, [
    ["width NaN", D30, { size: { width: NaN, height: 200 } }],
    ["width Infinity", D30, { size: { width: Infinity, height: 200 } }],
  ], { expect: "error" });
});
probe("page.size.explicit.invalid-type", "explicit page sizes: type error text (takumi: serde message)", async (t) => {
  await cmpAll(t, [
    ["width only", D30, { size: { width: 300 } }],
    ["string numbers", D30, { size: { width: "300", height: "200" } }],
    ["a number", D30, { size: 5 }],
  ], { expect: "error" });
});
probe("page.landscape", "landscape", async (t) => {
  await cmpAll(t, [
    ["a5 landscape", D3, { size: "a5", landscape: true }],
    ["explicit size landscape", D30, { size: S, landscape: true, margin: 10 }],
    ["landscape false", D30, { size: S, landscape: false, margin: 10 }],
    ["landscape null", D30, { ...SMALL, landscape: null }],
  ], G);
});
probe("page.landscape.invalid-type", "landscape: type error text (takumi: serde message)", async (t) => {
  await cmp(t, "'yes'", D30, { ...SMALL, landscape: "yes" }, { expect: "error" });
  await cmp(t, "1", D30, { ...SMALL, landscape: 1 }, { expect: "error" });
});
probe("page.margin.number", "margins: one number", async (t) => {
  for (const m of [0, 10, 37.8, 95]) await cmp(t, String(m), D30, { size: S, margin: m }, G);
});
probe("page.margin.sides", "margins: per side (a side left out is auto)", async (t) => {
  for (const m of [{}, { top: 30 }, { top: 30, left: 0, right: 0, bottom: 0 }, { top: "auto", bottom: 50 }, { left: 140, right: 140 }, { top: 90, bottom: 90 }, { left: 5, right: 60, top: 0, bottom: 0 }])
    await cmp(t, JSON.stringify(m), D30, { size: S, margin: m }, G);
  await cmp(t, "unknown side key is ignored", D30, { size: S, margin: { top: 10, foo: 3 } }, { expect: "render" });
});
probe("page.margin.auto", "margins: auto = 10mm without a band", async (t) => {
  await cmp(t, "'auto'", D30, { size: S, margin: "auto" }, G);
  await cmp(t, "unset", D30, { size: S }, G);
  await cmp(t, "null", D30, { size: S, margin: null }, G);
});
probe("page.margin.auto.tiny-page", "margins: auto is 0 on an axis <= 1in", async (t) => {
  await cmpAll(t, [
    ["96x96", D30, { size: { width: 96, height: 96 } }],
    ["97x97", D30, { size: { width: 97, height: 97 } }],
    ["96x300", D30, { size: { width: 96, height: 300 } }],
    ["300x96", D30, { size: { width: 300, height: 96 } }],
  ], G);
});
probe("page.margin.negative", "margins: negative values are accepted", async (t) => {
  await cmp(t, "-5", D30, { size: S, margin: -5 }, { ...G, expect: "render" });
  await cmp(t, "top -10", D30, { size: S, margin: { top: -10 } }, { ...G, expect: "render" });
});
probe("page.margin.no-area", "margins that leave no page area: error", async (t) => {
  for (const m of [100, 150, 1e9, { left: 150, right: 150 }, { top: 100, bottom: 100 }]) await cmp(t, JSON.stringify(m), D30, { size: S, margin: m }, { expect: "error" });
});
probe("page.margin.nan", "margins: NaN / Infinity are an error", async (t) => {
  await cmp(t, "NaN", D30, { size: S, margin: NaN }, { expect: "error" });
  await cmp(t, "Infinity", D30, { size: S, margin: Infinity }, { expect: "error" });
  await cmp(t, "top NaN", D30, { size: S, margin: { top: NaN } }, { expect: "error" });
});
probe("page.margin.invalid-type", "margins: type error text (takumi: serde message)", async (t) => {
  for (const m of ["AUTO", "10", "10px", true, [10]]) await cmp(t, JSON.stringify(m), D30, { size: S, margin: m }, { expect: "error" });
});
