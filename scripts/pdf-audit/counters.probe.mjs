// Audit probes: page counters (counters.*): the class hooks pageNumber / totalPages / targetPageNumber, the
// PageNumber / TotalPages / TargetPageNumber helpers, counter styles, counters in the content flow and in
// position:fixed boxes, and CSS generated-content counters. Method: see page-options.probe.mjs.
import { NOTO_TC, INTER, probe } from "./lib.mjs";
import { SMALL, cmp, cmpAll, doc, lines, pagesOf, stripPrefix } from "./paged-helpers.mjs";

const S = { width: 300, height: 300 };
const G = { geom: true, expect: "render" };
const D = doc(lines(1, 30));
const foot = (inner, style = "") => `<div style="font:10px/20px Inter;${style}">${inner}</div>`;
const PN = `<span class="pageNumber"></span>`; const TP = `<span class="totalPages"></span>`;

probe('counters.flow.transforms', 'painted counter ownership and untransformed own flow edge', async t => {
  await cmpAll(t, [
    ['own translate', doc(lines(1, 3) + `<div class="l" style="transform:translateY(200px)">OWN${PN}</div>` + lines(4, 20)), SMALL],
    ['ancestor translate', doc(lines(1, 3) + `<div style="transform:translateY(200px)"><div class="l">NESTED${PN}</div></div>` + lines(4, 20)), SMALL],
    ['nested transforms', doc(lines(1, 3) + `<div style="transform:translateY(100px)"><div class="l" style="transform:translateY(100px)">NESTED${PN}</div></div>` + lines(4, 20)), SMALL],
    ['rotation and translation', doc(lines(1, 3) + `<div class="l" style="transform:translateY(200px) rotate(5deg);transform-origin:0 0">ROTATED${PN}</div>` + lines(4, 20)), SMALL],
    ['backward translation preserves flow cursor', doc(lines(1, 14) + `<div class="l" style="transform:translateY(-200px)">BACK${PN}</div>` + lines(15, 20)), SMALL],
    ['transformed target', doc(`<a href="#transformed"><span class="targetPageNumber"></span></a>` + lines(1, 12) + `<div id="transformed" class="l" style="transform:translateY(180px)">TARGET</div>`), SMALL],
  ], G);
});

probe("counters.class-hooks", "pageNumber / totalPages class hooks in a band", async (t) => {
  await cmpAll(t, [
    ["footer: P n / N", D, { size: S, footer: foot(`P${PN}/${TP}`) }],
    ["header", D, { size: S, header: foot(`P${PN}/${TP}`) }],
    ["both classes on one node: the page number wins", D, { size: S, footer: foot(`B<span class="pageNumber totalPages"></span>`) }],
    ["both classes, other order", D, { size: S, footer: foot(`B<span class="totalPages pageNumber"></span>`) }],
    ["the counter replaces the node's children", D, { size: S, footer: foot(`C<span class="pageNumber">old <b>text</b></span>`) }],
    ["hook on a div (block)", D, { size: S, footer: `<div class="pageNumber" style="font:10px/20px Inter"></div>` }],
    ["hook on the band's root element", D, { size: S, footer: `<span class="pageNumber" style="font:10px/20px Inter"></span>` }],
    ["hook nested in a hook: the outer one is filled", D, { size: S, footer: foot(`N<span class="totalPages"><span class="pageNumber"></span></span>`) }],
    ["class with other names around", D, { size: S, footer: foot(`X<span class="a pageNumber b"></span>`) }],
    ["class names are case-sensitive (PageNumber is not a hook)", D, { size: S, footer: foot(`X<span class="PageNumber">kept</span>`) }],
    ["tab / newline separated class list", D, { size: S, footer: foot(`X<span class="a\tpageNumber\nb"></span>`) }],
    ["Chromium's other template classes (date, title, url) are not hooks", D, { size: S, footer: foot(`<span class="date">d</span><span class="title">t</span><span class="url">u</span>`) }],
    ["a styled counter keeps its style", D, { size: S, footer: foot(`S<span class="pageNumber" style="font-size:20px;margin-left:30px"></span>`) }],
    ["counters in pages rules", D, { size: S, footer: foot(`P${PN}`), pages: { first: { footer: foot(`FIRST${PN}of${TP}`) }, last: { footer: foot(`LAST${PN}`) } } }],
    ["a counter makes a wider band on later pages (10 -> two digits)", doc(lines(1, 99) + lines(1, 99, () => "", "M")), { size: S, footer: foot(`<span style="display:inline-block;width:14px"></span>${PN}`, "width:30px;margin-left:270px") }],
  ], G);
});
/** A footer built with an engine's own helpers: takumi-pdf's return JSX elements, bm-render's return node trees. */
const helperFooter = (mod, kids) => {
  const children = kids(mod);
  const jsx = children.some((c) => c && typeof c === "object" && c.$$typeof);
  return jsx
    ? { type: "div", props: { style: { fontFamily: "Inter", fontSize: 10, lineHeight: "20px" }, children }, key: null, $$typeof: Symbol.for("react.transitional.element") }
    : { type: "container", style: { fontFamily: "Inter", fontSize: 10, lineHeight: "20px" }, children: children.map((c) => (typeof c === "string" ? { type: "text", text: c } : c)) };
};
probe("counters.helpers", "PageNumber() / TotalPages() / TargetPageNumber() helpers", async (t) => {
  const run = async (label, html, kids) => {
    const r = await t.both(html, (mod) => ({ size: S, footer: helperFooter(mod, kids) }));
    t.same(label, r.bm.error ? "ERROR " + stripPrefix(r.bm.error) : pagesOf(r.bm), r.ref && (r.ref.error ? "ERROR " + r.ref.error : pagesOf(r.ref)));
  };
  await run("PageNumber() / TotalPages()", D, (m) => ["P", m.PageNumber(), "/", m.TotalPages()]);
  await run("format", D, (m) => ["P", m.PageNumber({ format: "lower-roman" }), "/", m.TotalPages({ format: "upper-roman" })]);
  await run("className is kept beside the hook", D, (m) => ["P", m.PageNumber({ className: "upper-alpha" })]);
  await run("style prop", D, (m) => ["P", m.PageNumber({ style: { marginLeft: 40 } })]);
  const target = doc(lines(1, 20) + `<div class="l" id="t">T</div>` + lines(21, 30));
  await run("TargetPageNumber({ href })", target, (m) => ["see ", m.TargetPageNumber({ href: "#t" })]);
  await run("TargetPageNumber({ href, format })", target, (m) => ["see ", m.TargetPageNumber({ href: "#t", format: "upper-roman" })]);
  await run("TargetPageNumber({}) without a link", target, (m) => ["see ", m.TargetPageNumber({})]);
});
probe("counters.helpers.jsx-element-input", "a JSX (React element) tree as a band / document (takumi-pdf accepts it)", async (t) => {
  const el = (type, props) => ({ type, props, key: null, $$typeof: Symbol.for("react.transitional.element") });
  const r = await t.both(D, { size: S, footer: el("div", { style: { fontFamily: "Inter", fontSize: 10, lineHeight: "20px" }, children: ["P", el("span", { className: "pageNumber" })] }) });
  t.same("JSX element footer", r.bm.error ? "ERROR " + stripPrefix(r.bm.error) : pagesOf(r.bm), r.ref && (r.ref.error ? "ERROR " + r.ref.error : pagesOf(r.ref)));
});

const STYLES = ["decimal", "decimal-leading-zero", "lower-roman", "upper-roman", "lower-alpha", "lower-latin", "upper-alpha", "upper-latin"];
const STYLES_GREEK_CJK = ["lower-greek", "hiragana", "katakana", "trad-chinese-informal", "cjk-ideographic", "cjk-decimal"];
const STYLES_DIGITS = ["arabic-indic", "bengali", "cambodian", "khmer", "devanagari", "gujarati", "gurmukhi", "kannada", "lao", "malayalam", "mongolian", "myanmar", "oriya", "persian", "urdu", "tamil", "telugu", "thai", "tibetan"];
// 120 one-line pages (each line forces a break); pageRanges keeps the pages whose numbers are interesting
const MANY = doc(Array.from({ length: 120 }, (_, i) => `<div class="l" style="break-after:page">D${i + 1}</div>`).join(""));
const KEEP = [1, 4, 9, 10, 26, 27, 28, 40, 49, 52, 53, 99, 100, 101, 110, 120];
const styled = (names) => names.map((n) => `<span class="pageNumber ${n}"></span>`).join(" | ") + ` of <span class="totalPages ${names[0]}"></span>`;
probe("counters.styles.latin", "counter styles: decimal, leading zero, roman, alpha / latin", async (t) => {
  for (const n of STYLES) await cmp(t, n, MANY, { ...SMALL, pageRanges: KEEP, footer: foot(`[${styled([n])}]`) }, { expect: "render" });
  await cmp(t, "unknown style name -> decimal", MANY, { ...SMALL, pageRanges: KEEP, footer: foot(`[<span class="pageNumber no-such-style"></span>]`) }, { expect: "render" });
  await cmp(t, "first supported name wins", MANY, { ...SMALL, pageRanges: KEEP, footer: foot(`[<span class="pageNumber bogus upper-roman lower-alpha"></span>]`) }, { expect: "render" });
  await cmp(t, "style before the hook class", MANY, { ...SMALL, pageRanges: KEEP, footer: foot(`[<span class="upper-roman pageNumber"></span>]`) }, { expect: "render" });
  await cmp(t, "style names are case-sensitive", MANY, { ...SMALL, pageRanges: KEEP, footer: foot(`[<span class="pageNumber Upper-Roman"></span>]`) }, { expect: "render" });
  await cmp(t, "other CSS styles are not supported (upper-greek, armenian, georgian, hebrew, disc)", MANY, { ...SMALL, pageRanges: [1, 12], footer: foot(`[<span class="pageNumber upper-greek"></span> <span class="pageNumber armenian"></span> <span class="pageNumber georgian"></span> <span class="pageNumber hebrew"></span> <span class="pageNumber disc"></span> <span class="pageNumber simp-chinese-informal"></span>]`) }, { expect: "render" });
});
probe("counters.styles.greek-cjk", "counter styles: lower-greek, hiragana, katakana, Chinese", async (t) => {
  const fonts = { extra: { fonts: [INTER, NOTO_TC] } };
  for (const n of STYLES_GREEK_CJK) await cmp(t, n, MANY, { ...SMALL, pageRanges: KEEP, footer: `<div style="font:10px/20px Inter, 'Noto Sans TC'">[${styled([n])}]</div>` }, { ...fonts, expect: "render" });
});
probe("counters.styles.digits", "counter styles: decimal digits of other scripts (no font: uncoveredText blank)", async (t) => {
  for (const n of STYLES_DIGITS) {
    const o = { ...SMALL, pageRanges: [1, 10, 120], uncoveredText: "blank", footer: foot(`[${styled([n])}]`) };
    const r = await t.both(MANY, o);
    const f = (x) => (!x ? null : x.error ? "ERROR " + stripPrefix(x.error) : x.pages.length + " pages");
    t.same(n + ": renders with blank glyphs", f(r.bm), f(r.ref));
    const e = await t.both(MANY, { ...o, uncoveredText: "error" });
    const g = (x) => (!x ? null : x.error ? stripPrefix(x.error) : "renders");
    t.same(n + ": the uncovered-character error names the same characters", g(e.bm), g(e.ref));
  }
});
probe("counters.styles.large-numbers", "counter styles at 3 999 / 4 000 / 10 000 pages", async (t) => {
  const big = doc(`<div style="height:100010px"></div>`);
  const o = { size: { width: 300, height: 60 }, margin: { top: 0, left: 0, right: 0, bottom: 50 }, tagged: false, pageRanges: [3999, 4000, 9999, 10000, 10001] };
  const fonts = { extra: { fonts: [INTER, NOTO_TC] } };
  await cmp(t, "roman / alpha / leading-zero", big, { ...o, footer: foot(`[${styled(["upper-roman", "lower-alpha", "decimal-leading-zero", "decimal"])}]`) }, { expect: "render" });
  await cmp(t, "Chinese informal falls back to digits from 10 000", big, { ...o, footer: `<div style="font:10px/20px Inter, 'Noto Sans TC'">[${styled(["trad-chinese-informal", "cjk-decimal", "hiragana"])}]</div>` }, { ...fonts, expect: "render" });
});

probe("counters.flow", "counters in the content flow show the page the node lands on", async (t) => {
  const here = (i) => `<div class="l">see ${PN} of ${TP} #${i}</div>`;
  await cmpAll(t, [
    ["one per page", doc(lines(1, 8) + here(1) + lines(9, 17) + here(2) + lines(18, 26) + here(3)), SMALL],
    ["in a paragraph that splits across pages (each line its own page?)", doc(lines(1, 7) + `<p>A ${PN}<br>B ${PN}<br>C ${PN}<br>D ${PN}</p>`), SMALL],
    ["in a table cell", doc(`<table style="border-spacing:0">` + Array.from({ length: 20 }, (_, i) => `<tr><td style="padding:0;height:20px">R${i + 1} p${PN}</td></tr>`).join("") + `</table>`), SMALL],
    ["in a repeated thead (each repetition shows which page?)", doc(`<table style="border-spacing:0"><thead><tr><th style="padding:0;height:20px;font-weight:400;text-align:left">H p${PN}/${TP}</th></tr></thead>` + Array.from({ length: 20 }, (_, i) => `<tr><td style="padding:0;height:20px">R${i + 1}</td></tr>`).join("") + `</table>`), SMALL],
    ["in a flex row item", doc(lines(1, 12) + `<div style="display:flex"><div class="l">a${PN}</div><div class="l">b${TP}</div></div>`), SMALL],
    ["in an absolutely positioned box on page 2", doc(`<div style="position:relative">` + lines(1, 14) + `<div style="position:absolute;top:200px;right:0">abs${PN}</div></div>`), SMALL],
    ["in a float", doc(lines(1, 12) + `<div style="float:right">fl${PN}</div>` + lines(13, 14)), SMALL],
    ["in a box moved by a transform to the next page", doc(lines(1, 3) + `<div class="l" style="transform:translateY(200px)">tr${PN}</div>` + lines(4, 20)), SMALL],
    ["totalPages alone in the flow", doc(lines(1, 20) + `<div class="l">total ${TP}</div>`), SMALL],
    ["styles in the flow", doc(lines(1, 20) + `<div class="l">r <span class="pageNumber upper-roman"></span> a <span class="totalPages lower-alpha"></span></div>`), SMALL],
    ["a display:none counter", doc(lines(1, 20) + `<div class="l">x<span class="pageNumber" style="display:none"></span></div>`), SMALL],
    ["a counter whose text moves the break (a wide number pushes a line down)", doc(lines(1, 8) + `<div style="width:40px;font:12px/20px Inter">ab <span class="totalPages decimal-leading-zero"></span> cd</div>` + lines(9, 20)), SMALL],
    ["with pageRanges", doc(lines(1, 8) + here(1) + lines(9, 17) + here(2) + lines(18, 26) + here(3)), { ...SMALL, pageRanges: [2, 3] }],
    ["in viewport mode (single page): the hooks are filled with 1 / 1?", doc(lines(1, 3) + here(1)), { viewport: { width: 300, height: 200 } }],
    ["in a node tree", { type: "container", style: { display: "block", fontFamily: "Inter", fontSize: 12, lineHeight: "20px" }, children: [{ type: "container", style: { height: 200 }, children: [] }, { type: "container", style: { display: "block" }, children: [{ type: "text", text: "p" }, { type: "container", className: "pageNumber", children: [] }] }] }, SMALL],
  ], G);
});
probe("counters.fixed", "counters in a position:fixed box renumber on every page", async (t) => {
  const fixed = (inner, style = "bottom:0;right:0") => `<div style="position:fixed;${style}">${inner}</div>`;
  await cmpAll(t, [
    ["page n of N", doc(fixed(`F${PN}/${TP}`) + lines(1, 30)), SMALL],
    ["fixed box written last", doc(lines(1, 30) + fixed(`F${PN}/${TP}`)), SMALL],
    ["fixed box with a style", doc(fixed(`F<span class="pageNumber upper-roman"></span>`) + lines(1, 30)), SMALL],
    ["fixed + flow counters together", doc(fixed(`F${PN}`) + lines(1, 20) + `<div class="l">flow ${PN}</div>`), SMALL],
    ["fixed + footer band counters", doc(fixed(`F${PN}`, "top:0;right:0") + lines(1, 30)), { size: S, footer: foot(`B${PN}/${TP}`) }],
    ["fixed box with pageRanges", doc(fixed(`F${PN}/${TP}`) + lines(1, 30)), { ...SMALL, pageRanges: [2, 4] }],
    ["nested fixed boxes with counters", doc(fixed(`O${PN}` + fixed(`I${TP}`, "top:0;left:0")) + lines(1, 30)), SMALL],
    ["a counter inside an absolute box inside a fixed box", doc(fixed(`<div style="position:absolute;bottom:0;right:60px">A${PN}</div>`, "inset:0") + lines(1, 30)), SMALL],
  ], G);
});
probe("counters.target", "targetPageNumber: the page of the enclosing link's target", async (t) => {
  const toc = (rows) => rows.map(([href, label]) => `<div class="l"><a href="${href}">${label} p<span class="targetPageNumber"></span></a></div>`).join("");
  const body = lines(1, 10) + `<div class="l" id="one">ONE</div>` + lines(11, 25) + `<div class="l" id="two">TWO</div>` + lines(26, 30) + `<div class="l" id="sp ace">SPACE</div><div class="l" id="é">ACCENT</div>`;
  await cmpAll(t, [
    ["a table of contents", doc(toc([["#one", "one"], ["#two", "two"]]) + body), SMALL],
    ["an unresolved target empties the node", doc(toc([["#nope", "nope"], ["#one", "one"]]) + body), SMALL],
    ["href without a fragment / external", doc(toc([["https://example.com/", "ext"], ["#", "empty"], ["page.html#one", "rel"]]) + body), SMALL],
    ["percent-encoded fragments", doc(toc([["#sp%20ace", "space"], ["#%C3%A9", "accent"], ["#é", "raw"]]) + body), SMALL],
    ["no enclosing link", doc(`<div class="l">bare <span class="targetPageNumber">old</span></div>` + body), SMALL],
    ["the nearest enclosing href wins", doc(`<div class="l"><a href="#one">o <a href="#two">i<span class="targetPageNumber"></span></a></a></div>` + body), SMALL],
    ["with a counter style", doc(`<div class="l"><a href="#two">r <span class="targetPageNumber upper-roman"></span> a <span class="targetPageNumber lower-alpha"></span></a></div>` + body), SMALL],
    ["target + pageNumber classes on one node", doc(`<div class="l"><a href="#two">b <span class="targetPageNumber pageNumber"></span></a></div>` + body), SMALL],
    ["target in a footer band", doc(body), { size: S, footer: foot(`<a href="#two">two on <span class="targetPageNumber"></span></a>`) }],
    ["target in a fixed box", doc(`<div style="position:fixed;bottom:0;right:0"><a href="#two">t<span class="targetPageNumber"></span></a></div>` + body), SMALL],
    ["target on a dropped page keeps its number", doc(toc([["#one", "one"], ["#two", "two"]]) + body), { ...SMALL, pageRanges: [1] }],
    ["duplicate ids: the first element", doc(toc([["#dup", "dup"]]) + lines(1, 12) + `<div class="l" id="dup">D1</div>` + lines(13, 25) + `<div class="l" id="dup">D2</div>`), SMALL],
    ["target = a name attribute (not an id)", doc(toc([["#nm", "name"]]) + lines(1, 12) + `<a name="nm" class="l">N</a>`), SMALL],
    ["a long TOC whose numbers move the targets", doc(toc(Array.from({ length: 12 }, (_, i) => ["#h" + i, "h" + i])) + Array.from({ length: 12 }, (_, i) => `<div class="l" id="h${i}">H${i}</div>` + lines(1, 4)).join("")), SMALL],
    ["in viewport mode", doc(toc([["#one", "one"]]) + body), { viewport: { width: 300 } }],
  ], G);
});

// ------------------------------------------------------------------------------------------------ CSS generated content

probe("counters.css.page-counters", "CSS counter(page) / counter(pages) in generated content", async (t) => {
  await cmpAll(t, [
    ["::after{content:counter(page)} in the flow", doc(lines(1, 12) + `<div class="l c">cp</div>`, `.c::after{content:" [" counter(page) "/" counter(pages) "]"}`), SMALL],
    ["counter(page) in a footer band", D, { size: S, footer: `<style>.c::after{content:" [" counter(page) "/" counter(pages) "]"}</style><div class="c" style="font:10px/20px Inter">cp</div>` }],
    ["counter(page, upper-roman)", doc(lines(1, 12) + `<div class="l c">cp</div>`, `.c::after{content:counter(page, upper-roman)}`), SMALL],
    ["counter-increment: page", doc(lines(1, 12) + `<div class="l c" style="counter-increment:page 5">cp</div>`, `.c::after{content:counter(page)}`), SMALL],
  ], G);
});
probe("counters.css.target-counter", "CSS target-counter() / target-text() / leader()", async (t) => {
  await cmpAll(t, [
    ["target-counter(attr(href), page)", doc(`<div class="l"><a class="x" href="#t">toc</a></div>` + lines(1, 12) + `<div class="l" id="t">T</div>`, `.x::after{content:" p" target-counter(attr(href), page)}`), SMALL],
    ["target-text()", doc(`<div class="l"><a class="x" href="#t">toc</a></div>` + lines(1, 12) + `<div class="l" id="t">T</div>`, `.x::after{content:" " target-text(attr(href))}`), SMALL],
    ["leader('.')", doc(`<div class="l"><a class="x" href="#t">toc</a></div>` + lines(1, 3), `.x::after{content:leader('.') "9"}`), SMALL],
  ], G);
});
probe("counters.css.custom", "CSS counters: counter-reset / counter-increment / counter() / counters() in ::before / ::after", async (t) => {
  await cmpAll(t, [
    ["counter() over numbered headings across pages", doc(Array.from({ length: 12 }, (_, i) => `<div class="l h">H</div>` + lines(i * 2 + 1, i * 2 + 2)).join(""), `body{counter-reset:sec} .h{counter-increment:sec} .h::before{content:"S" counter(sec) " "}`), SMALL],
    ["counter(name, style)", doc(Array.from({ length: 4 }, () => `<div class="l h">H</div>`).join(""), `body{counter-reset:sec 2} .h{counter-increment:sec 2} .h::before{content:counter(sec, upper-roman) ". "}`), SMALL],
    ["counters() nested", doc(`<div class="o"><div class="l i">a</div><div class="o"><div class="l i">b</div><div class="l i">c</div></div><div class="l i">d</div></div>`, `.o{counter-reset:n} .i{counter-increment:n} .i::before{content:counters(n, ".") " "}`), SMALL],
    ["counter-set", doc(`<div class="l h">A</div><div class="l h" style="counter-set:sec 10">B</div><div class="l h">C</div>`, `body{counter-reset:sec} .h{counter-increment:sec} .h::before{content:counter(sec) " "}`), SMALL],
    ["plain ::before / ::after strings and attr()", doc(`<div class="l q" data-x="ATTR">mid</div>`, `.q::before{content:"<" attr(data-x) " "} .q::after{content:" >"}`), SMALL],
    ["counter(list-item) on li", doc(`<ol style="margin:0;padding-left:40px;list-style:none"><li class="l k">a</li><li class="l k">b</li></ol>`, `.k::before{content:"(" counter(list-item) ") "}`), SMALL],
    ["a counter in a repeated thead", doc(`<table style="border-spacing:0"><thead><tr><th class="h" style="padding:0;height:20px;font-weight:400;text-align:left">H</th></tr></thead>` + Array.from({ length: 20 }, (_, i) => `<tr><td style="padding:0;height:20px">R${i + 1}</td></tr>`).join("") + `</table>`, `body{counter-reset:sec} .h{counter-increment:sec} .h::after{content:" #" counter(sec)}`), SMALL],
  ], G);
});
probe("counters.css.running-elements", "running elements: position:running() / content:element() / string-set / string()", async (t) => {
  await cmpAll(t, [
    ["position:running(head) + @top-center{content:element(head)}", doc(`<div class="l" style="position:running(head)">RUNHEAD</div>` + lines(1, 12), `@page{@top-center{content:element(head)}}`), SMALL],
    ["string-set + string() in a margin box", doc(`<h1 class="l" style="margin:0;font:12px/20px Inter;string-set:title content()">TITLE</h1>` + lines(1, 12), `@page{@top-left{content:string(title)}}`), SMALL],
  ], G);
});
