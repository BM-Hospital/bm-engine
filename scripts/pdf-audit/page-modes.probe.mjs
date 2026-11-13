// Audit probes: viewport mode, viewport units and @media print, pageRanges, backgroundColor, the page-count limit
// and measure(). Method: see page-options.probe.mjs.
import { probe } from "./lib.mjs";
import { SMALL, cmp, doc, lines, stripPrefix } from "./paged-helpers.mjs";

const D30 = doc(lines(1, 30));
const D3 = doc(lines(1, 3));
const S = { width: 300, height: 200 };
const G = { geom: true };

// ------------------------------------------------------------------------------------------------ viewport mode

probe("page.viewport.fixed", "viewport: fixed size, one page, overflow clipped", async (t) => {
  await cmp(t, "300x200", D30, { viewport: { width: 300, height: 200 } }, { ...G, expect: "render" });
  await cmp(t, "fractional is truncated", D3, { viewport: { width: 300.9, height: 200.9 } }, G);
  await cmp(t, "percent height resolves", doc(`<div style="height:50%"></div>` + lines(1, 3)), { viewport: { width: 300, height: 200 } }, G);
  await cmp(t, "vh", doc(`<div style="height:50vh"></div>` + lines(1, 3)), { viewport: { width: 300, height: 200 } }, G);
});
probe("page.viewport.auto-height", "viewport: no height = page as tall as the content", async (t) => {
  await cmp(t, "30 lines", D30, { viewport: { width: 300 } }, { ...G, expect: "render" });
  await cmp(t, "height null", D30, { viewport: { width: 300, height: null } }, G);
  await cmp(t, "break-before ignored", doc(lines(1, 3) + `<div style="break-before:page">X</div>`), { viewport: { width: 300 } }, G);
});
probe("page.viewport.empty-document", "viewport: empty document / zero sizes", async (t) => {
  await cmp(t, "empty html, auto height", "", { viewport: { width: 300 } });
  await cmp(t, "zero-height div, auto height", doc(`<div></div>`), { viewport: { width: 300 } });
  await cmp(t, "empty html paged", "", SMALL);
  await cmp(t, "zero width", D3, { viewport: { width: 0, height: 100 } });
  await cmp(t, "zero height", D3, { viewport: { width: 100, height: 0 } });
  await cmp(t, "negative width", D3, { viewport: { width: -10, height: 100 } });
});
probe("page.viewport.exclusive", "viewport: mutually exclusive with the paged options", async (t) => {
  const v = { viewport: { width: 300, height: 200 } };
  const paged = { size: "a4", landscape: true, margin: 10, header: "<div>H</div>", footer: "<div>F</div>", pages: {}, pageRanges: [1] };
  for (const [k, val] of Object.entries(paged)) await cmp(t, "viewport + " + k, D3, { ...v, [k]: val }, { expect: "error" });
  await cmp(t, "viewport + landscape:false", D3, { ...v, landscape: false }, { expect: "error" });
  // (takumi-pdf-js drops a top-level `header: false` / `footer: false` before the exclusivity check: both engines render)
  await cmp(t, "viewport + header:false", D3, { ...v, header: false }, { expect: "render" });
  await cmp(t, "viewport + backgroundColor is allowed", D3, { ...v, backgroundColor: "red" }, { expect: "render" });
  await cmp(t, "viewport + size:null", D3, { ...v, size: null });
});
probe("page.viewport.large", "viewport: sizes above 16 384 px", async (t) => {
  await cmp(t, "20 000 x 100", D3, { viewport: { width: 20000, height: 100 } });
  await cmp(t, "100 x 20 000", D3, { viewport: { width: 100, height: 20000 } });
  await cmp(t, "auto height of 30 000 px content", doc(`<div style="height:30000px"></div>` + lines(1, 2)), { viewport: { width: 100 } });
});
probe("page.viewport.invalid-type", "viewport: type error text (takumi: serde message)", async (t) => {
  await cmp(t, "a number", D3, { viewport: 300 }, { expect: "error" });
  await cmp(t, "no width", D3, { viewport: { height: 200 } }, { expect: "error" });
  await cmp(t, "string width", D3, { viewport: { width: "300" } }, { expect: "error" });
});
probe("page.media-print", "@media print applies in viewport and paged renders", async (t) => {
  const html = doc(`<div class="s">SCREEN</div><div class="p">PRINT</div>` + lines(1, 2), `.p{display:none} @media print{.p{display:block}.s{display:none}} @media screen{.l{display:none}}`);
  await cmp(t, "viewport", html, { viewport: { width: 300, height: 200 } }, { expect: "render" });
  await cmp(t, "paged", html, SMALL, { expect: "render" });
});
probe("page.viewport-units.paged", "viewport units in paged content = the page area", async (t) => {
  await cmp(t, "50vh spacer", doc(`<div style="height:50vh"></div>` + lines(1, 12)), SMALL, G);
  await cmp(t, "100vh box then lines", doc(`<div style="height:100vh"></div>` + lines(1, 3)), SMALL, G);
  await cmp(t, "50vw box", doc(`<div style="width:50vw;margin-left:25vw">` + lines(1, 3) + `</div>`), SMALL, G);
  await cmp(t, "media min-width sees the page area width", doc(lines(1, 2) + `<div class="a">A280</div><div class="b">B300</div>`, `.a,.b{display:none} @media (min-width:280px){.a{display:block}} @media (min-width:300px){.b{display:block}}`), SMALL, G);
  await cmp(t, "percent height of the root", doc(`<div style="height:50%"></div>` + lines(1, 12)), SMALL, G);
});
probe("page.device-pixel-ratio", "devicePixelRatio option (not a takumi-pdf option)", async (t) => {
  await cmp(t, "devicePixelRatio 2", D30, { ...SMALL, devicePixelRatio: 2 }, G);
  await cmp(t, "viewport devicePixelRatio", D3, { viewport: { width: 300, height: 200, devicePixelRatio: 2 } }, G);
});

// ------------------------------------------------------------------------------------------------ pageRanges

probe("page.ranges.forms", "pageRanges: numbers and { from, to } spans", async (t) => {
  for (const pr of [[1], [2], [4], [1, 3], [3, 1], [2, 2], [{ from: 2 }], [{ to: 2 }], [{ from: 2, to: 3 }], [{}], [1, { from: 3 }], [{ from: 2, to: 2 }], [{ from: 3, to: 99 }], [99, 2], [{ from: 1, to: 2 }, { from: 2, to: 3 }], [{ from: null, to: 2 }]])
    await cmp(t, JSON.stringify(pr), D30, { ...SMALL, pageRanges: pr }, { expect: "render" });
});
probe("page.ranges.empty-list", "pageRanges: [] and null", async (t) => {
  await cmp(t, "[]", D30, { ...SMALL, pageRanges: [] });
  await cmp(t, "null", D30, { ...SMALL, pageRanges: null });
});
probe("page.ranges.invalid", "pageRanges: page 0 / backwards span error", async (t) => {
  for (const pr of [[0], [{ from: 0 }], [{ to: 0 }], [{ from: 3, to: 2 }], [1, { from: 5, to: 4 }]]) await cmp(t, JSON.stringify(pr), D30, { ...SMALL, pageRanges: pr }, { expect: "error" });
});
probe("page.ranges.out-of-bounds", "pageRanges: selecting no page is an error", async (t) => {
  for (const pr of [[5], [{ from: 9 }], [99, 100]]) await cmp(t, JSON.stringify(pr), D30, { ...SMALL, pageRanges: pr }, { expect: "error" });
  await cmp(t, "one-page document", D3, { ...SMALL, pageRanges: [{ from: 5 }] }, { expect: "error" });
});
probe("page.ranges.invalid-type", "pageRanges: type error text (takumi: serde message)", async (t) => {
  for (const pr of [[1.5], [-1], ["2"], ["1-2"], 2, "1-2", [{ from: 1.5 }], [{ from: -1 }], [[1, 2]], [true]]) await cmp(t, JSON.stringify(pr), D30, { ...SMALL, pageRanges: pr }, { expect: "error" });
});
probe("page.ranges.counters-keep-numbers", "pageRanges: counters and page rules keep the full document's numbers", async (t) => {
  const footer = `<div style="font:10px Inter">P<span class="pageNumber"></span>/<span class="totalPages"></span></div>`;
  await cmp(t, "footer counters", D30, { ...SMALL, footer, pageRanges: [2, 4] }, { ...G, expect: "render" });
  await cmp(t, "content counters", doc(lines(1, 30) + `<div class="l">here <span class="pageNumber"></span> of <span class="totalPages"></span></div>`), { ...SMALL, pageRanges: [{ from: 3 }] }, G);
  const b = (s) => `<div style="font:10px Inter">${s}</div>`;
  await cmp(t, "pages.first / last / even", D30, { ...SMALL, pageRanges: [2, 4], pages: { first: { header: b("FIRST") }, last: { header: b("LAST") }, even: { footer: b("EVEN") } } }, G);
});
probe("page.ranges.links-to-dropped-pages", "pageRanges: a link whose target page is dropped", async (t) => {
  const html = doc(`<a class="l" style="display:block" href="#t">go</a><a class="l" style="display:block" href="#k">kept</a>` + lines(3, 20) + `<div class="l" id="k">K</div>` + lines(22, 30) + `<div class="l" id="t">T</div>`);
  const links = (x) => (x && !x.error ? x.subtyped("Link").map((o) => (o.dict.Dest ? "dest" : o.dict.A ? "action:" + String(x.pdf.resolve(o.dict.A).S) : "none")).sort() : x && x.error);
  const all = await cmp(t, "all pages", html, SMALL, { expect: "render" });
  if (all.ref) t.same("all pages: link annotations", links(all.bm), links(all.ref));
  const part = await cmp(t, "pages 1-3 (target of #t on page 4 dropped)", html, { ...SMALL, pageRanges: [{ to: 3 }] }, { expect: "render" });
  if (part.ref) t.same("pages 1-3: link annotations", links(part.bm), links(part.ref));
});

// ------------------------------------------------------------------------------------------------ backgroundColor

/** The fill colours and rectangles at the start of a page's content stream (before the first text / clip). */
const paper = (x, i = 0) => (x && !x.error ? (x.content(i).split(/\bBT\b|\bW n\b|\bW\*/)[0].match(/[\d.\s-]+ (?:rg|g|k|re)\b|\/\w+ gs|\bf\*?\b/g) || []).map((s) => s.replace(/\s+/g, " ").trim()) : x && x.error);
probe("page.background-color", "backgroundColor fills the page box of every page", async (t) => {
  for (const c of ["red", "#0f08", "rgb(10 20 30)", "transparent", "rgba(0,0,255,0.5)"]) {
    const r = await cmp(t, c, D30, { ...SMALL, backgroundColor: c }, { expect: "render" });
    if (r.ref && !r.bm.error && !r.ref.error) for (const i of [0, r.bm.pages.length - 1]) t.same(`${c}: paper operators of page ${i + 1}`, paper(r.bm, i), paper(r.ref, i));
  }
  const r = await cmp(t, "viewport", D3, { viewport: { width: 300, height: 200 }, backgroundColor: "#ff0000" }, { expect: "render" });
  if (r.ref && !r.ref.error && !r.bm.error) t.same("viewport: paper operators", paper(r.bm), paper(r.ref));
  const n = await cmp(t, "unset: nothing painted", D3, SMALL);
  if (n.ref && !n.bm.error) t.same("unset: paper operators", paper(n.bm), paper(n.ref));
});
probe("page.background-color.invalid", "backgroundColor: not a colour error", async (t) => {
  for (const c of ["nope", "", "currentColor", "var(--x)", 5]) await cmp(t, JSON.stringify(c), D3, { ...SMALL, backgroundColor: c }, { expect: "error" });
  // (takumi-pdf-js parses the value's first component and does not read what follows: a red page)
  await cmp(t, JSON.stringify("red blue"), D3, { ...SMALL, backgroundColor: "red blue" }, { expect: "render" });
});
probe("page.background-color.root-background", "the html / body background and the page margins", async (t) => {
  const html = doc(lines(1, 12), `html{background:#00ff00} body{background:#ff0000}`);
  const rects = (x, i) => (x.content(i).match(/[\d.-]+ [\d.-]+ [\d.-]+ [\d.-]+ re/g) || []).map((s) => s.split(" ").slice(0, 4).map((v) => Math.round(+v)).join(" "));
  const r = await cmp(t, "body + html background", html, SMALL, { expect: "render" });
  if (r.ref && !r.bm.error && !r.ref.error) for (const i of [0, 1]) t.same(`rectangles of page ${i + 1}`, rects(r.bm, i), rects(r.ref, i));
});

// ------------------------------------------------------------------------------------------------ limits, measure

// 100 x 10 px pages without margins keep these cheap (takumi-pdf's wasm traps with "unreachable" when the same
// page counts are reached with 200 px pages and a 4 100 000 px box).
const TINY = { size: { width: 100, height: 10 }, margin: 0, tagged: false };
const outcome = (x) => (!x ? null : x.error ? "ERROR " + stripPrefix(x.error) : x.pages.length + " pages");
probe("page.limit.too-many-pages", "more than 20 000 pages is an error (message)", async (t) => {
  const r = await t.both(doc(`<div style="height:200010px"></div>`), TINY);
  t.ok(!!r.bm.error, "bm rejects 20 001 pages");
  t.same("20 001 pages", outcome(r.bm), outcome(r.ref));
});
probe("page.limit.at-the-limit", "exactly 20 000 pages renders", async (t) => {
  const r = await t.both(doc(`<div style="height:200000px"></div>`), TINY);
  t.same("20 000 pages", outcome(r.bm), outcome(r.ref));
});
probe("page.limit.many-pages", "5 000 empty pages render", async (t) => {
  const r = await t.both(doc(`<div style="height:50000px"></div>`), TINY);
  t.same("5 000 pages", outcome(r.bm), outcome(r.ref));
});

const measured = async (t, label, html, options) => {
  const r = await t.both(html, options, { method: "measure" });
  const f = (x) => (!x ? null : x.error ? "ERROR " + stripPrefix(x.error) : { width: Math.round(x.value.width * 100) / 100, height: Math.round(x.value.height * 100) / 100 });
  t.same(label, f(r.bm), f(r.ref));
};
probe("page.measure", "measure(): page options (band layout) vs viewport", async (t) => {
  const band = `<div style="font:12px/20px Inter;padding:5px">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>`;
  await measured(t, "default (A4 band)", band, {});
  await measured(t, "size a5", band, { size: "a5" });
  await measured(t, "size a5 landscape", band, { size: "a5", landscape: true });
  await measured(t, "explicit size", band, { size: S });
  await measured(t, "viewport", band, { viewport: { width: 300 } });
  await measured(t, "viewport with height", band, { viewport: { width: 300, height: 500 } });
  await measured(t, "fixed-width box", `<div style="width:100px;height:40px"></div>`, { size: S });
  await measured(t, "inline counter only (999 placeholder)", `<span style="font:12px/20px Inter" class="pageNumber"></span>`, { size: S });
  await measured(t, "counter in a viewport measure is left empty", `<span style="font:12px/20px Inter" class="pageNumber"></span>`, { viewport: { width: 300 } });
  await measured(t, "wrapping band", `<div style="font:12px/20px Inter">${"word ".repeat(40)}</div>`, { size: S });
  await measured(t, "@page size from css", band, { css: ["@page{size:400px 300px}"] });
  await measured(t, "viewport + size (exclusive)", band, { viewport: { width: 300 }, size: "a4" });
  await measured(t, "margin is not a measure option", band, { size: S, margin: 10 });
  await measured(t, "unknown size", band, { size: "nope" });
});
