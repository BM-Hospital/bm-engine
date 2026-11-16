// Audit probes: block fragmentation, part 1: forced and avoided breaks (break-before / -after / -inside and the
// legacy page-break-*), forced-break collapsing, widows / orphans, monolithic boxes, lines / images taller than
// a page, margins at page tops, box-decoration-break. Method: see page-options.probe.mjs. The page is
// 300 x 200 px with 10 px margins = a 280 x 180 px page area = nine 20 px lines (L01 ...).
import { probe, pngRgba } from "./lib.mjs";
import { SMALL, cmp, cmpAll, doc, lines, paintShapes, wordBoxes } from "./paged-helpers.mjs";

const G = { geom: true, expect: "render" };
// paint comparisons run untagged: the marked-content operators of the structure tree are another audit area
const P = { ...SMALL, tagged: false };
const X = (style, text = "X") => `<div class="l" style="${style}">${text}</div>`;
const mid = (style) => doc(lines(1, 3) + X(style) + lines(4, 6));

probe("pagination.break.tall-translucent-image-no-overdraw", "a tall translucent inline image is painted once on each intersecting page", async (t) => {
  const png = Buffer.from(pngRgba(2, 2, () => [255, 0, 0, 128])).toString("base64");
  const html = `<p>${"text ".repeat(500)}</p><figure><img alt="tall" width="100" height="900" src="data:image/png;base64,${png}"><figcaption>tall figure</figcaption></figure>`;
  const r = await t.bm(html, { size: "A5", lang: "en" });
  if (r.error) return;
  t.same("image draw calls per page", r.pages.map((_, i) => (r.content(i).match(/\/x\d+\s+Do/g) || []).length), [0, 1, 1, 1]);
  t.same("extracted text page count", r.textPages.length, 4);
});

// ------------------------------------------------------------------------------------------------ forced breaks

const BETWEEN = ["auto", "page", "always", "left", "right", "recto", "verso", "column", "avoid", "avoid-page", "avoid-column", "all", "bogus"];
for (const v of BETWEEN) {
  probe(`pagination.break-before.${v.toLowerCase()}`, `break-before: ${v}`, async (t) => {
    await cmp(t, "on the 4th line (page 1 is a right page)", mid(`break-before:${v}`), SMALL, G);
    await cmp(t, "twice (lands on page 2 then 3)", doc(lines(1, 2) + X(`break-before:${v}`, "X1") + lines(3, 4) + X(`break-before:${v}`, "X2") + lines(5, 6)), SMALL, G);
  });
  probe(`pagination.break-after.${v.toLowerCase()}`, `break-after: ${v}`, async (t) => {
    await cmp(t, "on the 4th line", mid(`break-after:${v}`), SMALL, G);
    await cmp(t, "twice", doc(lines(1, 2) + X(`break-after:${v}`, "X1") + lines(3, 4) + X(`break-after:${v}`, "X2") + lines(5, 6)), SMALL, G);
  });
}
probe("pagination.break-side.blank-pages", "break-before/after: left / right / recto / verso and blank pages", async (t) => {
  for (const v of ["left", "right", "recto", "verso"]) {
    await cmp(t, `break-before:${v} from page 1`, mid(`break-before:${v}`), SMALL, G);
    await cmp(t, `break-before:${v} from page 2`, doc(lines(1, 12) + X(`break-before:${v}`) + lines(13, 14)), SMALL, G);
    await cmp(t, `break-after:${v} from page 2`, doc(lines(1, 12) + X(`break-after:${v}`) + lines(13, 14)), SMALL, G);
  }
  await cmp(t, "break-before:left under direction:rtl", `<html dir="rtl"><body>` + mid(`break-before:left`) + `</body></html>`, SMALL, { expect: "render" });
  await cmp(t, "break-before:right with a footer counter", mid(`break-before:right`), { ...SMALL, footer: `<div style="font:10px Inter">P<span class="pageNumber"></span>/<span class="totalPages"></span></div>` }, G);
});
const LEGACY = [["page-break-before", ["always", "left", "right", "avoid", "auto", "page", "recto"]], ["page-break-after", ["always", "left", "right", "avoid", "auto", "page"]]];
for (const [prop, values] of LEGACY) {
  probe(`pagination.${prop}`, `legacy ${prop}`, async (t) => {
    for (const v of values) await cmp(t, v, mid(`${prop}:${v}`), SMALL, G);
    await cmp(t, "legacy after modern (later wins)", mid(`break-${prop.slice(11)}:auto;${prop}:always`), SMALL, G);
    await cmp(t, "modern after legacy (later wins)", mid(`${prop}:always;break-${prop.slice(11)}:auto`), SMALL, G);
  });
}
probe("pagination.break-before.upper-case", "break-before: PAGE (keywords are case-insensitive)", async (t) => {
  await cmp(t, "PAGE", mid(`break-before:PAGE`), SMALL, G);
  await cmp(t, "Always", mid(`page-break-after:Always`), SMALL, G);
});
probe("pagination.break.tailwind", "break utilities in the tw attribute", async (t) => {
  const tw = (c) => doc(lines(1, 3) + `<div class="l" tw="${c}">X</div>` + lines(4, 6));
  for (const c of ["break-before-column", "break-after-avoid", "break-before-avoid-page", "break-inside-avoid"]) await cmp(t, c, tw(c), SMALL, G);
  const expectPages = async (label, html, expected) => {
    const r = await t.both(html, SMALL);
    if (r.bm.error) return t.ok(false, `${label}: ${r.bm.error}`);
    const actual = r.bm.textPages.map((s) => s.replace(/\s+/g, " ").trim());
    t.ok(JSON.stringify(actual) === JSON.stringify(expected), `${label}: ${JSON.stringify(actual)}`);
    t.note("bm-render applies the tw break utility; the pinned oracle ignores tw attributes");
  };
  for (const c of ["break-before-page", "break-before-all", "break-before-left", "break-before-right"])
    await expectPages(c, tw(c), ["L01 L02 L03", "X L04 L05 L06"]);
  await expectPages("break-after-page", tw("break-after-page"), ["L01 L02 L03 X", "L04 L05 L06"]);
  await expectPages("break-inside-avoid on a straddling box", doc(lines(1, 7) + `<div tw="break-inside-avoid">` + lines(8, 11) + `</div>`), ["L01 L02 L03 L04 L05 L06 L07", "L08 L09 L10 L11"]);
  await cmp(t, "class attribute (not tw)", doc(lines(1, 3) + `<div class="l break-before-page">X</div>` + lines(4, 6)), SMALL, G);
});
probe("pagination.break.node-tree", "break properties in a node tree (camelCase style)", async (t) => {
  const line = (text, style = {}) => ({ type: "container", style: { height: 20, ...style }, children: [{ type: "text", text }] });
  const tree = (style) => ({ type: "container", style: { display: "block", fontFamily: "Inter", fontSize: 12, lineHeight: "20px" }, children: [line("L01"), line("L02"), line("X", style), line("L03")] });
  for (const st of [{ breakBefore: "page" }, { breakAfter: "page" }, { pageBreakBefore: "always" }, { breakBefore: "left" }, { breakBefore: "right" }]) await cmp(t, JSON.stringify(st), tree(st), SMALL, G);
  const flow = (style) => ({ type: "container", style: { display: "block", fontFamily: "Inter", fontSize: 12, lineHeight: "20px" }, children: [...Array.from({ length: 7 }, (_, i) => line("L0" + (i + 1))), { type: "container", style, children: [line("K1"), line("K2"), line("K3"), line("K4")] }] });
  await cmp(t, "breakInside avoid", flow({ breakInside: "avoid" }), SMALL, G);
  await cmp(t, "pageBreakInside avoid", flow({ pageBreakInside: "avoid" }), SMALL, G);
});

// ------------------------------------------------------------------------------------------------ collapsing

probe("pagination.forced-break.collapsing", "forced breaks collapse; no empty first / last page", async (t) => {
  await cmpAll(t, [
    ["break-before on the very first element", doc(X("break-before:page") + lines(1, 3)), SMALL],
    ["break-before on a nested first child", doc(`<div><div>` + X("break-before:page") + `</div></div>` + lines(1, 3)), SMALL],
    ["break-after on the last element", doc(lines(1, 3) + X("break-after:page")), SMALL],
    ["break-after on a nested last child", doc(lines(1, 3) + `<div><div>` + X("break-after:page") + `</div></div>`), SMALL],
    ["break-after then break-before = one break", doc(lines(1, 2) + X("break-after:page", "X1") + X("break-before:page", "X2") + lines(3, 4)), SMALL],
    ["break-after:page + break-before:right", doc(lines(1, 2) + X("break-after:page", "X1") + X("break-before:right", "X2") + lines(3, 4)), SMALL],
    ["both on one element", doc(lines(1, 2) + X("break-before:page;break-after:page") + lines(3, 4)), SMALL],
    ["empty block between two forced breaks", doc(lines(1, 2) + X("break-after:page", "X1") + `<div></div>` + X("break-before:page", "X2")), SMALL],
    ["empty block with break-before and break-after", doc(lines(1, 2) + `<div style="break-before:page;break-after:page"></div>` + lines(3, 4)), SMALL],
    ["zero-height block with break-before:page in the middle", doc(lines(1, 2) + `<div style="break-before:page"></div>` + lines(3, 4)), SMALL],
    ["break at the exact page end (no blank page)", doc(lines(1, 9) + X("break-before:page") + lines(10, 11)), SMALL],
    ["break-after on the 9th line (exact page end)", doc(lines(1, 8) + X("break-after:page") + lines(9, 10)), SMALL],
    ["parent's break-after joins the child's (last child)", doc(`<div style="break-after:page">` + lines(1, 2) + X("break-after:avoid") + `</div>` + lines(3, 4)), SMALL],
    ["child's break-before joins the parent's (first child)", doc(lines(1, 2) + `<div>` + X("break-before:page") + `</div>` + lines(3, 4)), SMALL],
    ["break on display:none element is ignored", doc(lines(1, 2) + `<div style="display:none;break-before:page">H</div>` + lines(3, 4)), SMALL],
    ["break on an inline element is ignored", doc(lines(1, 2) + `<div class="l">a <span style="break-before:page">INL</span> b</div>` + lines(3, 4)), SMALL],
    ["break on an inline-block is ignored", doc(lines(1, 2) + `<div class="l">a <span style="display:inline-block;break-before:page">IB</span> b</div>` + lines(3, 4)), SMALL],
    ["break on a <br>", doc(`<div>A01<br>A02<br style="break-before:page">A03<br>A04</div>`), SMALL],
    ["break on a float", doc(lines(1, 2) + `<div style="float:left;break-before:page;height:20px">F</div>` + lines(3, 4)), SMALL],
    ["break on an absolutely positioned box", doc(lines(1, 2) + `<div style="position:absolute;break-before:page">A</div>` + lines(3, 4)), SMALL],
  ], G);
});

// ------------------------------------------------------------------------------------------------ avoid

probe("pagination.break-inside", "break-inside: auto / avoid / avoid-page / avoid-column", async (t) => {
  const box = (v, from = 8, to = 11) => `<div style="break-inside:${v}">` + lines(from, to) + `</div>`;
  for (const v of ["auto", "avoid", "avoid-page", "avoid-column", "bogus"]) await cmp(t, v, doc(lines(1, 7) + box(v) + lines(12, 14)), SMALL, G);
  await cmpAll(t, [
    ["page-break-inside: avoid", doc(lines(1, 7) + `<div style="page-break-inside:avoid">` + lines(8, 11) + `</div>`), SMALL],
    ["page-break-inside: auto", doc(lines(1, 7) + `<div style="page-break-inside:auto">` + lines(8, 11) + `</div>`), SMALL],
    ["avoid box taller than a page breaks anyway", doc(lines(1, 2) + box("avoid", 3, 16)), SMALL],
    ["avoid box at a page top that is too tall", doc(box("avoid", 1, 12)), SMALL],
    ["nested avoid boxes", doc(lines(1, 5) + `<div style="break-inside:avoid">` + lines(6, 7) + box("avoid", 8, 11) + `</div>`), SMALL],
    ["avoid inside a breakable parent", doc(lines(1, 5) + `<div>` + lines(6, 7) + box("avoid", 8, 11) + `</div>`), SMALL],
    ["several avoid cards", doc(Array.from({ length: 6 }, (_, k) => `<div style="break-inside:avoid;height:70px;margin-bottom:8px">C${k + 1}</div>`).join("")), SMALL],
    ["avoid box with a fixed height and a border", doc(lines(1, 7) + `<div style="break-inside:avoid;height:60px;border:1px solid #000">K</div>` + lines(8, 9)), SMALL],
    ["avoid on a paragraph of lines", doc(lines(1, 7) + `<p style="break-inside:avoid">P1<br>P2<br>P3<br>P4</p>`), SMALL],
  ], G);
});
probe("pagination.break-avoid.between", "break-before / break-after: avoid keep boxes together", async (t) => {
  const two = (a, b) => `<div class="l" style="${a}">H</div><div style="${b}">` + lines(9, 12) + `</div>`;
  await cmpAll(t, [
    ["heading with break-after:avoid at the page end", doc(lines(1, 8) + `<div class="l" style="break-after:avoid">H</div>` + lines(9, 12)), SMALL],
    ["without avoid (control)", doc(lines(1, 8) + `<div class="l">H</div>` + lines(9, 12)), SMALL],
    ["break-before:avoid on the following block", doc(lines(1, 8) + `<div class="l">H</div>` + X("break-before:avoid", "N") + lines(9, 12)), SMALL],
    ["break-after:avoid-page", doc(lines(1, 8) + `<div class="l" style="break-after:avoid-page">H</div>` + lines(9, 12)), SMALL],
    ["break-after:avoid-column is not a page avoid", doc(lines(1, 8) + `<div class="l" style="break-after:avoid-column">H</div>` + lines(9, 12)), SMALL],
    ["page-break-after:avoid", doc(lines(1, 8) + `<div class="l" style="page-break-after:avoid">H</div>` + lines(9, 12)), SMALL],
    ["a chain of avoids longer than a page", doc(Array.from({ length: 14 }, (_, i) => `<div class="l" style="break-after:avoid">A${i + 1}</div>`).join("") + lines(1, 2)), SMALL],
    ["avoid after the last line of a paragraph (interacts with widows)", doc(lines(1, 6) + `<p style="break-after:avoid">P1<br>P2<br>P3</p>` + lines(7, 10)), SMALL],
    ["heading + avoid-inside block", doc(lines(1, 6) + two("break-after:avoid", "break-inside:avoid")), SMALL],
    ["forced break beats avoid", doc(lines(1, 3) + `<div class="l" style="break-after:avoid">H</div>` + X("break-before:page", "N")), SMALL],
    ["h1-h6 have no UA break-after:avoid?", doc(lines(1, 8) + `<h3 style="margin:0;font:12px/20px Inter">H3</h3>` + lines(9, 12)), SMALL],
  ], G);
});

// ------------------------------------------------------------------------------------------------ widows / orphans

const para = (n, style = "", p = "P") => `<p style="${style}">` + Array.from({ length: n }, (_, i) => `${p}${i + 1}`).join("<br>") + `</p>`;
probe("pagination.orphans", "orphans (default 2)", async (t) => {
  await cmpAll(t, [
    ["room for 1 line, default: the paragraph moves", doc(lines(1, 8) + para(5)), SMALL],
    ["room for 1 line, orphans:1: one line stays", doc(lines(1, 8) + para(5, "orphans:1")), SMALL],
    ["room for 2 lines, default: two stay", doc(lines(1, 7) + para(5)), SMALL],
    ["room for 2 lines, orphans:3: the paragraph moves", doc(lines(1, 7) + para(5, "orphans:3")), SMALL],
    ["room for 3 lines, orphans:4", doc(lines(1, 6) + para(6, "orphans:4")), SMALL],
    ["orphans larger than the paragraph", doc(lines(1, 6) + para(4, "orphans:9")), SMALL],
    ["orphans:0 is invalid (default applies)", doc(lines(1, 8) + para(5, "orphans:0")), SMALL],
    ["orphans:-1 is invalid", doc(lines(1, 8) + para(5, "orphans:-1")), SMALL],
    ["orphans:1.5 is invalid", doc(lines(1, 8) + para(5, "orphans:1.5")), SMALL],
    ["orphans is inherited", doc(`<div style="orphans:1">` + lines(1, 8) + para(5) + `</div>`), SMALL],
    ["orphans on wrapped text (not <br>)", doc(lines(1, 8) + `<p style="width:60px">w1 w2 w3 w4 w5 w6 w7 w8 w9 w10</p>`), SMALL],
  ], G);
});
probe("pagination.widows", "widows (default 2)", async (t) => {
  await cmpAll(t, [
    ["room for 3 of 4 lines, default: 2 + 2", doc(lines(1, 6) + para(4)), SMALL],
    ["room for 3 of 4 lines, widows:1: 3 + 1", doc(lines(1, 6) + para(4, "widows:1")), SMALL],
    ["room for 3 of 4 lines, widows:3: orphans violated -> moves", doc(lines(1, 6) + para(4, "widows:3")), SMALL],
    ["room for 4 of 6 lines, widows:3: 3 + 3", doc(lines(1, 5) + para(6, "widows:3")), SMALL],
    ["room for 4 of 6 lines, widows:4: 2 + 4", doc(lines(1, 5) + para(6, "widows:4")), SMALL],
    ["widows:5 of 6 with room for 4: 1 line would stay -> moves", doc(lines(1, 5) + para(6, "widows:5")), SMALL],
    ["widows larger than the paragraph", doc(lines(1, 5) + para(6, "widows:9")), SMALL],
    ["widows + orphans 1", doc(lines(1, 8) + para(2, "widows:1;orphans:1")), SMALL],
    ["a 3-line paragraph with room for 2 (default: moves whole)", doc(lines(1, 7) + para(3)), SMALL],
    ["a paragraph longer than a page at a page top", doc(para(21)), SMALL],
    ["a paragraph longer than two pages, widows:4 orphans:4", doc(lines(1, 6) + para(22, "widows:4;orphans:4")), SMALL],
    ["widows is inherited", doc(`<div style="widows:1">` + lines(1, 6) + para(4) + `</div>`), SMALL],
    ["widows:0 is invalid", doc(lines(1, 6) + para(4, "widows:0")), SMALL],
    ["widows in a node tree", { type: "container", style: { display: "block", fontFamily: "Inter", fontSize: 12, lineHeight: "20px" }, children: [{ type: "container", style: { height: 120 }, children: [] }, { type: "container", style: { display: "block", widows: 1, width: 30 }, children: [{ type: "text", text: "w1 w2 w3 w4" }] }] }, SMALL],
  ], G);
});
probe("pagination.widows-orphans.inline-content", "widows / orphans with inline boxes, mixed line heights, last-resort breaks", async (t) => {
  await cmpAll(t, [
    ["lines of different heights", doc(lines(1, 6) + `<p>P1<br><span style="font-size:30px;line-height:40px">P2</span><br>P3<br>P4</p>`), SMALL],
    ["inline-block inside a line", doc(lines(1, 6) + `<p>P1<br>P2 <span style="display:inline-block;height:50px;width:20px;background:#ccc"></span><br>P3<br>P4</p>`), SMALL],
    ["two paragraphs in sequence", doc(lines(1, 6) + para(3, "", "A") + para(3, "", "B")), SMALL],
    ["text directly in a div with a block sibling", doc(lines(1, 7) + `<div>T1<br>T2<br>T3<div class="l">BLK</div>T4<br>T5</div>`), SMALL],
    ["paragraph with padding and border", doc(lines(1, 6) + para(4, "padding:10px;border:1px solid #000")), SMALL],
    ["paragraph in a nested container with padding", doc(lines(1, 5) + `<div style="padding:10px"><div style="padding:5px">` + para(5) + `</div></div>`), SMALL],
  ], G);
});

// ------------------------------------------------------------------------------------------------ monolithic

const PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";
const img = (h, w = 50) => `<img src="${PNG}" style="display:block;width:${w}px;height:${h}px">`;
probe("pagination.monolithic.image", "monolithic: images move whole to the next page", async (t) => {
  await cmpAll(t, [
    ["image that does not fit the rest of the page", doc(lines(1, 6) + img(100) + lines(7, 8)), SMALL],
    ["image that fits exactly", doc(lines(1, 6) + img(60) + lines(7, 8)), SMALL],
    ["image 1px too tall", doc(lines(1, 6) + img(61) + lines(7, 8)), SMALL],
    ["inline image in a line", doc(lines(1, 6) + `<div>a <img src="${PNG}" style="width:20px;height:100px"> b</div>` + lines(7, 8)), SMALL],
    ["image in a flex row", doc(lines(1, 6) + `<div style="display:flex">${img(100)}<div>T</div></div>` + lines(7, 8)), SMALL],
    ["svg element", doc(lines(1, 6) + `<svg width="50" height="100" style="display:block"><rect width="50" height="100" fill="#ccc"/></svg>` + lines(7, 8)), SMALL],
  ], G);
});
probe("pagination.monolithic.taller-than-page", "monolithic content taller than a page is sliced; what follows starts below it", async (t) => {
  await cmpAll(t, [
    ["image taller than a page at the page top", doc(img(400) + lines(1, 3)), SMALL],
    ["image taller than a page after two lines", doc(lines(1, 2) + img(400) + lines(3, 5)), SMALL],
    ["image of exactly two pages", doc(img(360) + lines(1, 3)), SMALL],
    ["tall inline-block in a line, lines after it", doc(lines(1, 2) + `<div>a <span style="display:inline-block;width:30px;height:400px;background:#ccc">IB</span> b</div>` + lines(3, 5)), SMALL],
    ["a line taller than a page (big line-height)", doc(lines(1, 2) + `<div style="line-height:400px">TALL</div>` + lines(3, 5)), SMALL],
    ["a huge font line", doc(lines(1, 2) + `<div style="font-size:300px;line-height:1">T</div>` + lines(3, 5)), SMALL],
    ["two tall images in a row", doc(img(250) + img(250) + lines(1, 2)), SMALL],
  ], G);
});
probe("pagination.monolithic.boxes", "monolithic: inline-block, overflow, line-clamp, replaced-like boxes", async (t) => {
  const ib = (style, n = 4) => `<div style="display:inline-block;width:100px;${style}">` + lines(8, 7 + n) + `</div>`;
  await cmpAll(t, [
    ["inline-block that does not fit", doc(lines(1, 7) + ib("")), SMALL],
    ["inline-flex that does not fit", doc(lines(1, 7) + `<div style="display:inline-flex;flex-direction:column">` + lines(8, 11) + `</div>`), SMALL],
    ["overflow:hidden box, auto height, straddling", doc(lines(1, 7) + `<div style="overflow:hidden">` + lines(8, 11) + `</div>` + lines(12, 13)), SMALL],
    ["overflow:auto box, fixed height, straddling", doc(lines(1, 7) + `<div style="overflow:auto;height:80px">` + lines(8, 11) + `</div>` + lines(12, 13)), SMALL],
    ["overflow:scroll box", doc(lines(1, 7) + `<div style="overflow:scroll;height:80px">` + lines(8, 11) + `</div>` + lines(12, 13)), SMALL],
    ["overflow:clip box", doc(lines(1, 7) + `<div style="overflow:clip;height:80px">` + lines(8, 11) + `</div>` + lines(12, 13)), SMALL],
    ["overflow-y:hidden only", doc(lines(1, 7) + `<div style="overflow-y:hidden;height:80px">` + lines(8, 11) + `</div>` + lines(12, 13)), SMALL],
    ["line-clamp box", doc(lines(1, 7) + `<div style="display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:4;overflow:hidden">c1<br>c2<br>c3<br>c4<br>c5<br>c6</div>` + lines(8, 9)), SMALL],
    ["line-clamp property", doc(lines(1, 7) + `<div style="line-clamp:4">c1<br>c2<br>c3<br>c4<br>c5<br>c6</div>` + lines(8, 9)), SMALL],
    ["contain:size box", doc(lines(1, 7) + `<div style="contain:size;height:80px">` + lines(8, 11) + `</div>` + lines(12, 13)), SMALL],
    ["button element", doc(lines(1, 7) + `<button style="display:block;height:80px;font:12px/20px Inter;border:0;padding:0">B1</button>` + lines(8, 9)), SMALL],
    ["fixed-height block (not monolithic: it is split)", doc(lines(1, 7) + `<div style="height:80px;background:#ccc">K</div>` + lines(8, 9)), SMALL],
    ["writing-mode vertical box", doc(lines(1, 7) + `<div style="writing-mode:vertical-rl;height:80px">V</div>` + lines(8, 9)), SMALL],
  ], G);

  // Preserve all content when an inline-block is taller than a page. The pinned oracle drops the
  // entire block's text; CSS fragmentation must continue it over the following pages.
  const tall = await t.both(doc(lines(1, 2) + ib("", 14) + lines(30, 31)), SMALL);
  if (tall.bm.error) t.ok(false, `tall inline-block renders: ${tall.bm.error}`);
  else {
    const pages = wordBoxes(tall.bm.bytes).map((p) => p.map((w) => w[0]));
    const expected = Array.from({ length: 14 }, (_, i) => `L${String(i + 8).padStart(2, "0")}`);
    const all = pages.flat();
    t.ok(pages.length >= 3 && expected.every((word) => all.includes(word)), `all inline-block lines survive pagination: ${JSON.stringify(pages)}`);
    t.ok(expected.every((word) => all.filter((x) => x === word).length === 1), "each fragmented inline-block line is emitted once");
    t.note("pinned Takumi drops the content of an inline-block taller than a page; bm-render preserves its fragments");
  }
});

// ------------------------------------------------------------------------------------------------ margins, padding, borders at breaks

probe("pagination.margins.at-page-top", "margins adjoining a break: truncated after an unforced break, kept after a forced one", async (t) => {
  const m = (style, text) => `<div class="l" style="${style}">${text}</div>`;
  await cmpAll(t, [
    ["margin-top after an unforced break is truncated", doc(lines(1, 9) + m("margin-top:30px", "M") + lines(10, 11)), SMALL],
    ["margin-top after a forced break is kept", doc(lines(1, 3) + m("margin-top:30px;break-before:page", "M") + lines(4, 5)), SMALL],
    ["margin-top at the very start of the document is kept", doc(m("margin-top:30px", "M") + lines(1, 3)), SMALL],
    ["margin-bottom before an unforced break is truncated", doc(lines(1, 8) + m("margin-bottom:30px", "M") + lines(9, 10)), SMALL],
    ["margin-bottom that does not fit the rest of the page", doc(lines(1, 7) + m("margin-bottom:50px", "M") + lines(8, 9)), SMALL],
    ["margin-top that pushes a line past the page end", doc(lines(1, 7) + m("margin-top:30px", "M") + lines(8, 9)), SMALL],
    ["nested first-child margins after a break", doc(lines(1, 9) + `<div style="margin-top:20px"><div style="margin-top:30px">` + lines(10, 11) + `</div></div>`), SMALL],
    ["collapsed sibling margins across a break", doc(lines(1, 8) + m("margin-bottom:40px", "A") + m("margin-top:25px", "B") + lines(9, 10)), SMALL],
    ["padding-top of a container after a break is kept", doc(lines(1, 9) + `<div style="padding-top:30px">` + lines(10, 11) + `</div>`), SMALL],
    ["padding-bottom does not fit: container breaks before its padding", doc(lines(1, 7) + `<div style="padding-bottom:50px">` + lines(8, 9) + `</div>` + lines(10, 11)), SMALL],
    ["border + padding of a container split mid-way", doc(lines(1, 5) + `<div style="border:5px solid #000;padding:5px">` + lines(6, 12) + `</div>` + lines(13, 14)), SMALL],
    ["gap in a flex column across a break", doc(`<div style="display:flex;flex-direction:column;gap:15px">` + lines(1, 12) + `</div>`), SMALL],
    ["margin-top on the first line of page 2 inside a nested container (unforced)", doc(`<div>` + lines(1, 9) + `</div><div><div class="l" style="margin-top:40px">M</div></div>`), SMALL],
    ["negative margin-top pulls a block back over a break", doc(lines(1, 9) + m("margin-top:-20px", "N") + lines(10, 11)), SMALL],
  ], G);
});
probe("pagination.box-decoration-break.block", "box-decoration-break: slice / clone on a block split by a page", async (t) => {
  const box = (v, extra = "") => doc(lines(1, 5) + `<div style="box-decoration-break:${v};border:6px solid #000;padding:7px;background:#eee;${extra}">` + lines(6, 20) + `</div>` + lines(21, 22));
  const cases = [
    ["slice", box("slice")],
    ["clone", box("clone")],
    ["-webkit-box-decoration-break: clone", doc(lines(1, 5) + `<div style="-webkit-box-decoration-break:clone;border:6px solid #000;padding:7px">` + lines(6, 20) + `</div>`), P],
    ["clone with border-radius", box("clone", "border-radius:10px")],
    ["clone with box-shadow", box("clone", "box-shadow:0 0 0 3px #f00")],
    ["clone nested in clone", doc(lines(1, 5) + `<div style="box-decoration-break:clone;border:6px solid #000"><div style="box-decoration-break:clone;padding:7px;border:2px solid #f00">` + lines(6, 20) + `</div></div>`), P],
    ["clone is not inherited", doc(lines(1, 5) + `<div style="box-decoration-break:clone"><div style="border:6px solid #000;padding:7px">` + lines(6, 20) + `</div></div>`), P],
    ["clone on a paragraph of lines", doc(lines(1, 5) + `<p style="box-decoration-break:clone;border:6px solid #000;padding:7px">` + Array.from({ length: 14 }, (_, i) => "P" + (i + 1)).join("<br>") + `</p>`), P],
    ["clone with a fixed height", box("clone", "height:320px")],
  ];
  await cmpAll(t, [
    ...cases.map(([name, html, options]) => [name, html, options ?? P]),
  ], { geom: true, paint: true, expect: "render" });

  // With `slice`, the middle page is a clip through one continuous box: it has straight vertical
  // borders and no cloned bottom radius. The pinned oracle rounds this middle fragment, which does
  // not match the source box's decoration. Assert the fragment geometry directly instead of treating
  // that oracle rendering as the expected result.
  const r = await t.both(box("slice", "border-radius:10px"), P);
  if (r.bm.error || r.bm.pages.length < 2) {
    t.ok(false, `slice-with-radius must render at least two pages: ${r.bm.error || r.bm.pages.length}`);
  } else {
    const middle = paintShapes(r.bm, 1);
    const vertical = middle.filter((s) => s.endsWith("fill 0,0,0")).map((s) => s.split(" ", 4).map(Number));
    const spans = (x0, x1) => vertical.some(([a, y0, b, y1]) => a === x0 && b === x1 && y1 - y0 > 100);
    t.ok(spans(7.5, 12), `middle fragment has a continuous straight left border: ${middle.join(" | ")}`);
    t.ok(spans(213, 217.5), `middle fragment has a continuous straight right border: ${middle.join(" | ")}`);
    t.note("pinned Takumi rounds the middle slice fragment; bm-render preserves the continuous, unrounded side borders");
  }
});
probe("pagination.box-decoration-break.inline", "box-decoration-break on an inline box wrapping across lines / pages", async (t) => {
  const span = (v) => doc(lines(1, 7) + `<p style="width:120px"><span style="box-decoration-break:${v};border:2px solid #000;padding:0 6px;background:#eee">aa bb cc dd ee ff gg hh ii jj kk ll</span></p>`);
  await cmpAll(t, [
    ["slice", span("slice"), P, { paint: false }],
    ["clone", span("clone"), P, { paint: false }],
  ], { geom: true, expect: "render" });

  // In slice mode a later fragment must not acquire a new top border. In clone mode, each fragment
  // is wrapped independently, so the final fragment's border must end with its text. Takumi paints
  // a long top border into the next page; comparing its raw paths with bm-render's clipped paths
  // hides this source-rendering error.
  const slice = await t.both(span("slice"), P);
  const clone = await t.both(span("clone"), P);
  if (slice.bm.error || clone.bm.error || slice.bm.pages.length < 2 || clone.bm.pages.length < 2) {
    t.ok(false, `inline decoration fragments render across pages: slice=${slice.bm.error || slice.bm.pages.length}, clone=${clone.bm.error || clone.bm.pages.length}`);
  } else {
    const black = (render) => paintShapes(render, 1).filter((s) => s.endsWith("fill 0,0,0")).map((s) => s.split(" ", 4).map(Number));
    const sliceMarks = black(slice.bm);
    const cloneMarks = black(clone.bm);
    t.ok(!sliceMarks.some(([, y0, , y1]) => y0 >= 141 && y1 >= 142), `slice continuation has no new top border: ${JSON.stringify(sliceMarks)}`);
    t.ok(cloneMarks.length > 0 && cloneMarks.every(([, , x1]) => x1 <= 52), `cloned border ends at the final text fragment: ${JSON.stringify(cloneMarks)}`);
    t.note("Poppler raster inspection confirms bm-render keeps the slice continuation unbroken and bounds the cloned border to its fragment; Takumi extends a border beyond the fragment");
  }
});
probe("pagination.background.sliced", "backgrounds and borders of a box split by a page (paint operators)", async (t) => {
  await cmpAll(t, [
    ["background + border block across two pages", doc(lines(1, 5) + `<div style="background:#cde;border:3px solid #123">` + lines(6, 14) + `</div>`), P],
    ["gradient background across pages", doc(`<div style="background:linear-gradient(#f00,#00f)">` + lines(1, 14) + `</div>`), P],
    ["rounded box across pages", doc(lines(1, 5) + `<div style="background:#cde;border-radius:12px">` + lines(6, 14) + `</div>`), P],
    ["box-shadow across pages", doc(lines(1, 5) + `<div style="box-shadow:0 0 0 4px #f00;margin:0 10px">` + lines(6, 14) + `</div>`), P],
    ["outline across pages", doc(lines(1, 5) + `<div style="outline:2px solid #f00;margin:0 10px">` + lines(6, 14) + `</div>`), P],
  ], { geom: true, paint: true, expect: "render" });
});
