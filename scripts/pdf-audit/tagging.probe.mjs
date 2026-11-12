// Tagged PDF: role of every HTML element, attributes, artifacts, reading order, page breaks, ParentTree / IDTree / RoleMap /
// Namespaces. One probe per case, comparing the canonical structure tree text of scripts/pdf-structure.mjs.
import { probe } from "./lib.mjs";
import { outcome, sameText, META, PNG1 } from "./filelayer.util.mjs";

const IMG = (attrs = "") => `<img ${attrs} width="20" height="20" src="${PNG1}">`;

/** Marked-content sequence of every page: `BDC tag props` / `BMC` / `EMC` in order (artifacts, MCIDs, ActualText, Lang). */
function marked(d) {
  return d.pdf.pages.map((_, i) => (d.content(i).match(/\/[A-Za-z0-9]+\s*(?:<<(?:[^<>]|<<[^<>]*>>|<[0-9A-Fa-f]*>)*>>|\/[A-Za-z0-9]+)?\s*(?:BDC|BMC)|\bEMC\b/g) || []).map((s) => s.replace(/\s+/g, " ")).join(" ; "));
}

async function tag(t, html, options = {}, { fonts, content = true } = {}) {
  const r = await t.both(html, options, fonts ? { fonts } : undefined);
  if (!t.same("outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) return r;
  sameText(t, "structure tree", r.bm.structure.tree, r.ref.structure.tree);
  sameText(t, "parent tree", r.bm.structure.parents, r.ref.structure.parents);
  sameText(t, "structure roots (MarkInfo / RoleMap / Namespaces / IDTree / page StructParents+Tabs)", r.bm.structure.roots, r.ref.structure.roots);
  if (content) sameText(t, "marked-content sequences per page", marked(r.bm), marked(r.ref));
  return r;
}

const ELEMENTS = {
  "p": `<p>para</p>`,
  "headings-h1-h6": `<h1>one</h1><h2>two</h2><h3>three</h3><h4>four</h4><h5>five</h5><h6>six</h6>`,
  "headings-skipped-levels": `<h3>starts at 3</h3><h6>jumps to 6</h6><h1>back to 1</h1><h4>jump to 4</h4><h4>sibling 4</h4><h2>up to 2</h2>`,
  "headings-deeper-than-6": `<h1>1</h1><h2>2</h2><h3>3</h3><h4>4</h4><h5>5</h5><h6>6</h6><h6>6 again</h6>`,
  "heading-inline-markup": `<h1>Plain <strong>bold</strong> <em>em</em> <a href="https://e.com/">link</a> <code>code</code></h1>`,
  "heading-with-br-and-whitespace": `<h2>  line one<br>line   two  </h2>`,
  "heading-empty": `<h1></h1><h2>after</h2>`,
  "heading-whitespace-span": `<h1><span> </span></h1><p>x</p>`,
  "heading-image-only": `<h1>${IMG('alt="logo"')}</h1><h2>next</h2>`,
  "heading-uppercase-transform": `<h1 style="text-transform:uppercase">shouted</h1>`,
  "heading-display-none-child": `<h1>seen <span style="display:none">hidden</span></h1>`,
  "ul-ol-li": `<ul><li>a</li><li>b</li></ul><ol><li>one</li><li>two</li></ol>`,
  "list-nested": `<ul><li>a<ul><li>a1</li><li>a2</li></ul></li><li>b<ol><li>b1</li></ol></li></ul>`,
  "list-numbering-types": ["disc", "circle", "square", "decimal", "decimal-leading-zero", "lower-alpha", "upper-alpha", "lower-latin", "upper-latin", "lower-roman", "upper-roman", "lower-greek", "none", "'-'", "disclosure-open", "lower-armenian", "georgian"].map((s) => `<ol style="list-style-type:${s}"><li>${s}</li></ol>`).join(""),
  "list-attributes-start-reversed-type": `<ol start="5"><li>five</li></ol><ol reversed><li>b</li><li>a</li></ol><ol type="A"><li>A</li></ol><ol type="i"><li>i</li></ol><ul type="square"><li>sq</li></ul>`,
  "li-outside-list": `<li>orphan one</li><li>orphan two</li><div><li>in div</li></div>`,
  "list-style-position-inside": `<ul style="list-style-position:inside"><li>inside</li></ul>`,
  "list-item-with-blocks": `<ul><li><p>para one</p><p>para two</p></li><li><h3>heading in li</h3><table><tr><td>cell</td></tr></table></li></ul>`,
  "list-empty-items": `<ul><li></li><li>x</li></ul><ul></ul>`,
  "display-list-item-on-div": `<div style="display:list-item;list-style-type:disc;margin-left:20px">div as list item</div>`,
  "dl-dt-dd": `<dl><dt>term</dt><dd>definition</dd><dt>t2</dt><dd>d2</dd></dl>`,
  "table-full": `<table><caption>Cap</caption><thead><tr><th>h1</th><th>h2</th></tr></thead><tbody><tr><th>row</th><td>c</td></tr></tbody><tfoot><tr><td>f1</td><td>f2</td></tr></tfoot></table>`,
  "table-no-sections": `<table><tr><th>h</th><td>d</td></tr><tr><td>a</td><td>b</td></tr></table>`,
  "table-scope-attributes": `<table><thead><tr><th scope="col">c</th><th scope="row">r</th><th scope="colgroup">cg</th><th scope="rowgroup">rg</th><th scope="bogus">x</th><th scope=" ROW ">sp</th></tr></thead><tbody><tr><th scope="col">c</th><th>default</th></tr></tbody><tfoot><tr><th>foot</th></tr></tfoot></table>`,
  "table-spans": `<table><tr><td rowspan="2">r2</td><td colspan="2">c2</td></tr><tr><td>a</td><td rowspan="5">overflowing rowspan</td></tr><tr><td colspan="3">c3</td></tr><tr><td rowspan="0">r0</td><td colspan="1">c1</td></tr></table>`,
  "table-headers-id-summary-abbr": `<table summary="A summary"><tr><th id="a" abbr="A">A</th><th id="b">B</th></tr><tr><td headers="a">1</td><td headers="a b">2</td></tr></table>`,
  "table-caption-bottom": `<table><caption style="caption-side:bottom">Bottom cap</caption><tr><td>c</td></tr></table>`,
  "table-two-captions": `<table><caption>One</caption><caption>Two</caption><tr><td>c</td></tr></table>`,
  "table-empty-cells": `<table><tr><td></td><td>x</td><td></td></tr><tr><td></td><td></td><td></td></tr></table>`,
  "table-empty": `<table></table><table><tbody></tbody></table><p>after</p>`,
  "table-nested": `<table><tr><td><table><tr><td>inner</td></tr></table></td><td>outer</td></tr></table>`,
  "table-display-overridden": `<table style="display:block"><tr style="display:block"><td style="display:inline">not a table</td></tr></table>`,
  "css-table-on-divs": `<div style="display:table"><div style="display:table-header-group"><div style="display:table-row"><div style="display:table-cell">head</div></div></div><div style="display:table-row"><div style="display:table-cell">cell</div></div></div>`,
  "table-colgroup-col": `<table><colgroup><col span="2"></colgroup><tr><td>a</td><td>b</td></tr></table>`,
  "table-text-directly-in-table": `<table>stray text<tr><td>c</td></tr></table>`,
  "table-with-background-and-borders": `<table style="border:1px solid;background:#eee;border-collapse:collapse"><tr style="background:#ddd"><td style="border:1px solid red;background:#ccc">c</td></tr></table>`,
  "a-href": `<p><a href="https://example.com/">ext</a> <a href="#x">int</a> <a>no href</a> <a href="">empty</a> <a href="mailto:a@b.c">mail</a> <a href="javascript:void(0)">js</a></p><p id="x">target</p>`,
  "a-block": `<a href="https://example.com/" style="display:block"><p>block link para</p><p>second</p></a>`,
  "a-wrapping-image": `<a href="https://example.com/">${IMG('alt="pic"')}</a>`,
  "a-nested-inline": `<p>before <a href="https://e.com/">link <strong>bold <em>both</em></strong> tail</a> after</p>`,
  "a-wrapped-two-lines": `<p style="width:120px">some words <a href="https://e.com/">a long link text that wraps over lines</a> end</p>`,
  "a-empty": `<p>x<a href="https://e.com/"></a>y</p><a href="https://e.com/" style="display:block;width:30px;height:10px"></a>`,
  "img-alt": `${IMG('alt="A picture"')}${IMG()}${IMG('alt=""')}${IMG('alt=" "')}${IMG('aria-label="aria"')}${IMG('title="title only"')}${IMG('role="presentation"')}${IMG('aria-hidden="true" alt="hidden"')}`,
  "img-inline-in-text": `<p>text ${IMG('alt="inline pic"')} more text ${IMG('alt=""')} end</p>`,
  "figure-figcaption": `<figure>${IMG('alt="Chart"')}<figcaption>Figure 1: chart</figcaption></figure>`,
  "figure-without-alt": `<figure>${IMG()}<figcaption>cap</figcaption></figure><figure><p>text only figure</p></figure>`,
  "figure-two-images": `<figure>${IMG('alt=""')}${IMG('alt="second"')}${IMG('alt="third"')}<figcaption>cap</figcaption></figure>`,
  "figure-nested-and-in-table": `<figure>${IMG('alt="outer"')}<table><tr><td>${IMG('alt="in cell"')}</td></tr></table><figure>${IMG('alt="inner"')}</figure></figure>`,
  "figcaption-outside-figure": `<figcaption>lonely caption</figcaption>`,
  "blockquote-q-cite": `<blockquote>quote <q>inline q</q> <cite>cite</cite></blockquote>`,
  "pre-code-kbd-samp-var": `<pre>pre  text\n  line2</pre><p><code>code</code> <kbd>kbd</kbd> <samp>samp</samp> <var>var</var></p><pre><code>code in pre</code></pre>`,
  "inline-semantics": `<p><em>em</em> <i>i</i> <strong>strong</strong> <b>b</b> <span>span</span> <u>u</u> <s>s</s> <del>del</del> <ins>ins</ins> <mark>mark</mark> <small>small</small> <sub>sub</sub> <sup>sup</sup> <abbr title="expansion">abbr</abbr> <dfn>dfn</dfn> <time datetime="2026">time</time> <bdo dir="rtl">bdo</bdo></p>`,
  "inline-nested-strong-em": `<p><strong>s <em>se <code>sec</code></em></strong></p>`,
  "strong-block-level": `<strong style="display:block">block strong</strong><em style="display:block">block em</em>`,
  "sectioning": `<main><header>header</header><nav>nav</nav><section>section<article>article</article></section><aside>aside</aside><footer>footer</footer><address>address</address><hgroup><h1>hg</h1><p>sub</p></hgroup></main>`,
  "section-with-heading": `<section><h2>Sec</h2><p>body</p><section><h3>Sub</h3><p>sub body</p></section></section><article><h2>Art</h2></article>`,
  "empty-section-article": `<section></section><article><div></div></article><p>after</p>`,
  "div-and-bare-text": `bare text<div>div text</div><div>a<div>nested</div>b</div><span>span one</span> <span>span two</span>`,
  "hr-br-wbr": `<p>one<br>two<wbr>three</p><hr><p>after</p>`,
  "form-controls": `<form><label for="i">Label</label><input id="i" value="value" type="text"><button>Button</button><select><option>opt</option></select><textarea>area</textarea><fieldset><legend>Legend</legend>field</fieldset><input type="checkbox" checked><progress value="1" max="2"></progress></form>`,
  "details-summary": `<details open><summary>Summary</summary><p>details body</p></details><details><summary>Closed</summary><p>hidden body</p></details>`,
  "svg-inline": `<p>before</p><svg width="40" height="20" role="img" aria-label="svg label"><title>svg title</title><rect width="40" height="20" fill="red"/><text x="2" y="12" font-size="8">svgtext</text></svg><svg width="10" height="10"><rect width="10" height="10"/></svg>`,
  "svg-as-img": `<img alt="svg image" width="20" height="20" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='20' height='20'%3E%3Crect width='20' height='20' fill='blue'/%3E%3C/svg%3E">`,
  "ruby-math-misc": `<p><ruby>base<rt>rt</rt></ruby> <math><mi>x</mi></math> <object>obj</object> <canvas width="10" height="10">canvas fallback</canvas></p>`,
  "aria-attributes": `<div role="heading" aria-level="2">role heading</div><div role="list"><div role="listitem">role item</div></div><p aria-hidden="true">aria hidden</p><div role="presentation">presentation</div><span role="img" aria-label="smile">:)</span><div aria-label="labelled div">content</div><p hidden>hidden attr</p>`,
  "title-and-alt-on-other-elements": `<p title="p title">p</p><div alt="div alt">d</div><abbr title="World Health Organization">WHO</abbr><acronym title="A">ac</acronym>`,
  "lang-attributes": `<p>English <span lang="de">Deutsch</span> again</p><p lang="fr">Bonjour <em lang="it">ciao</em></p><div lang="es"><h2>Hola</h2><ul><li>uno</li></ul><table><tr><td lang="pt">ola</td></tr></table></div><p lang="">empty lang</p><p lang="en">same as doc</p>`,
  "id-anchors": `<p id="a">a</p><div id="b"></div><span id="c">c</span><h2 id="d">d</h2><p><a href="#a">to a</a> <a href="#b">to b</a> <a href="#c">to c</a></p><table id="t"><tr id="r"><td id="cell">x</td></tr></table>`,
  "background-and-borders-artifacts": `<div style="background:#eee;border:2px solid #333;padding:4px;box-shadow:2px 2px 0 #000;outline:1px solid red"><p style="background:linear-gradient(red,blue);text-decoration:underline">decorated</p></div>`,
  "text-decorations-shadow-stroke": `<p style="text-decoration:underline line-through overline;text-shadow:1px 1px #999;-webkit-text-stroke:1px red">fancy</p>`,
  "pseudo-elements": `<style>.q::before{content:"« "}.q::after{content:" »"}</style><p class="q">quoted</p>`,
  "visibility-and-display-none": `<p style="visibility:hidden">invisible</p><p style="display:none">gone</p><p style="opacity:0">transparent</p><p>shown</p>`,
  "overflow-hidden-clipped-text": `<div style="width:40px;height:10px;overflow:hidden"><p>clipped text that overflows the box entirely on later lines</p></div>`,
  "flex-row-is-one-paragraph": `<div style="display:flex"><div>left</div><div>right</div></div><div style="display:flex;flex-direction:column"><div>top</div><div>bottom</div></div><div style="display:inline-flex"><span>a</span><span>b</span></div>`,
  "flex-row-with-roles": `<div style="display:flex"><p>p in row</p><div>bare</div><h2>h in row</h2><div>bare2</div></div>`,
  "flex-order": `<div style="display:flex;flex-direction:column"><p style="order:2">second visually (order 2)</p><p style="order:1">first visually (order 1)</p></div><div style="display:flex;flex-direction:row-reverse"><span>A</span><span>B</span></div>`,
  "grid": `<div style="display:grid;grid-template-columns:1fr 1fr"><div>g1</div><div>g2</div><p>g3</p></div>`,
  "absolute-and-fixed": `<div style="position:relative;height:60px"><p>flow one</p><p style="position:absolute;top:0;right:0">absolute</p><p>flow two</p></div><p style="position:fixed;bottom:0">fixed</p>`,
  "floats": `<div><p style="float:right">floated right</p><p style="float:left">floated left</p><p>normal flow text</p></div>`,
  "z-index-order": `<div style="position:relative"><p style="position:relative;z-index:2">z2 (source first)</p><p style="position:relative;z-index:1">z1 (source second)</p></div>`,
  "inline-block": `<p>text <span style="display:inline-block;border:1px solid">inline block</span> tail</p><div style="display:inline-block"><p>p in inline-block</p></div>`,
  "transform-rotated": `<p style="transform:rotate(10deg);width:100px">rotated</p>`,
  "writing-mode-and-rtl": `<p dir="rtl">rtl text abc</p><p style="direction:rtl">css rtl</p>`,
  "white-space-and-empty-text": `<p>   </p><p>\n</p><p>a   b\n\nc</p><div>  <span> </span>  </div>`,
  "entities-and-special-chars": `<p>&lt;tag&gt; &amp; &quot;q&quot; &nbsp;nbsp &copy; ﬁ ligature fi fl ffi — “quotes”</p>`,
  "multi-column": `<div style="column-count:2;width:300px"><p>col text one that is long enough to split over columns surely</p><p>col text two</p></div>`,
  "mixed-document": `<html lang="en"><body><header><h1>Doc</h1></header><main><section><h2>S1</h2><p>Text with <a href="https://e.com/">link</a>, <strong>bold</strong>.</p><ul><li>item <em>em</em></li></ul><figure>${IMG('alt="fig"')}<figcaption>cap</figcaption></figure></section><blockquote><p>quoted</p></blockquote><table><caption>T</caption><thead><tr><th>a</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table></main><footer><p>foot</p></footer></body></html>`,
};

for (const [name, html] of Object.entries(ELEMENTS)) {
  probe("tagging.element." + name, "structure role / attributes: " + name, async (t) => { await tag(t, html, { lang: "en" }); });
}

// The same element set under PDF 2.0 (UA-2): namespaces, structure destinations, heading roles.
for (const name of ["headings-skipped-levels", "headings-deeper-than-6", "table-full", "table-scope-attributes", "list-numbering-types", "id-anchors", "a-href", "inline-semantics", "img-alt", "lang-attributes", "mixed-document", "figure-figcaption"]) {
  probe("tagging.pdf20." + name, "PDF 2.0 structure (tagged: ua2): " + name, async (t) => {
    const html = ELEMENTS[name];
    const r = await tag(t, html, { lang: "en", tagged: "ua2", metadata: META });
    if (r.ref && r.ref.error) t.note("takumi: " + outcome(r.ref));
  });
}
for (const name of ["headings-skipped-levels", "headings-deeper-than-6", "table-scope-attributes", "img-alt", "mixed-document", "list-numbering-types", "a-href"]) {
  probe("tagging.ua1." + name, "PDF/UA-1 structure: " + name, async (t) => {
    const r = await tag(t, ELEMENTS[name], { lang: "en", tagged: "ua1", metadata: META });
    if (r.ref && r.ref.error) t.note("takumi: " + outcome(r.ref));
  });
  probe("tagging.a2a." + name, "PDF/A-2a structure: " + name, async (t) => {
    const r = await tag(t, ELEMENTS[name], { lang: "en", pdfa: "2a", metadata: META });
    if (r.ref && r.ref.error) t.note("takumi: " + outcome(r.ref));
  });
}

const A5 = { size: "A5", lang: "en" };
const PAGED = {
  "paragraph-across-pages": [`<p>${"word ".repeat(1500)}</p>`, A5],
  "list-across-pages": [`<ol>${Array.from({ length: 70 }, (_, i) => `<li>item ${i}</li>`).join("")}</ol>`, A5],
  "table-across-pages-repeated-header": [`<table><caption>Cap</caption><thead><tr><th>Head</th><th>B</th></tr></thead><tbody>${Array.from({ length: 90 }, (_, i) => `<tr><td>r${i}</td><td>v</td></tr>`).join("")}</tbody><tfoot><tr><td>foot</td><td>f</td></tr></tfoot></table>`, A5],
  "heading-and-sections-across-pages": [`<section><h1>One</h1><p>${"text ".repeat(600)}</p><h2>Two</h2><p>${"text ".repeat(600)}</p></section>`, A5],
  "forced-breaks": [`<h1>A</h1><p>a</p><h1 style="break-before:page">B</h1><p>b</p><div style="break-before:page"></div><p>c</p>`, A5],
  "bands-are-artifacts": [`<h1>T</h1><p>${"text ".repeat(900)}</p>`, { ...A5, header: `<div><b>Header</b> <span class="pageNumber"></span>/<span class="totalPages"></span> <a href="https://e.com/">l</a></div>`, footer: `<p>Footer ${IMG('alt="logo"')}</p>` }],
  "page-background-artifact": [`<p>x</p>`, { ...A5, backgroundColor: "#ffeeee" }],
  "fixed-repeats-on-every-page": [`<div style="position:fixed;top:0;left:0">watermark</div><p>${"text ".repeat(900)}</p>`, A5],
  "page-ranges-subset": [`<h1 id="a">A</h1><p style="break-before:page" id="b">B</p><p style="break-before:page">C <a href="#a">to a</a> <a href="#b">to b</a></p>`, { ...A5, pageRanges: [{ from: 2, to: 3 }], outline: true }],
  "image-and-figure-across-pages": [`<p>${"text ".repeat(500)}</p><figure><img alt="tall" width="100" height="900" src="${PNG1}"><figcaption>tall figure</figcaption></figure>`, A5],
  "link-across-pages": [`<p>${"text ".repeat(560)}<a href="https://e.com/">${"link ".repeat(120)}</a></p>`, A5],
  "empty-pages": [`<p>a</p><div style="break-before:page;height:10px"></div><div style="break-before:page"></div><p style="break-before:page">d</p>`, A5],
  "many-mcids": [Array.from({ length: 300 }, (_, i) => `<p>p${i} <b>b</b></p>`).join(""), A5],
};
for (const [name, [html, o]] of Object.entries(PAGED)) {
  probe("tagging.paged." + name, "structure across pages: " + name, async (t) => { await tag(t, html, o, { content: name !== "many-mcids" }); });
}

probe("tagging.off", "tagged: false -> no StructTreeRoot, no MarkInfo, no marked content (artifacts included?)", async (t) => {
  const r = await t.both(ELEMENTS["mixed-document"], { tagged: false, size: "A5", header: "<p>h</p>" });
  if (!t.same("outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) return;
  t.same("catalog keys", Object.keys(r.bm.catalog).sort(), Object.keys(r.ref.catalog).sort());
  sameText(t, "marked content", marked(r.bm), marked(r.ref));
  sameText(t, "roots", r.bm.structure.roots, r.ref.structure.roots);
});

probe("tagging.actual-text-and-expansion", "/ActualText, /Alt, /E in marked content and structure elements (ligatures, soft hyphen, abbr, uncovered text, emoji)", async (t) => {
  for (const [name, html, o] of [
    ["ligature + hyphenation", `<p style="width:60px;hyphens:auto" lang="en">official difficult extraordinarily</p>`, {}],
    ["soft hyphen break", `<p style="width:50px">extra&shy;ordinar&shy;ily long</p>`, {}],
    ["abbr title", `<p><abbr title="Portable Document Format">PDF</abbr></p>`, {}],
    ["uncovered blank", `<p>a中b</p>`, { uncoveredText: "blank" }],
    ["uncovered placeholder", `<p>a中b</p>`, { uncoveredText: "placeholder" }],
    ["text-transform + letter-spacing", `<p style="text-transform:uppercase;letter-spacing:3px">spaced ﬁ</p>`, {}],
    ["ellipsis", `<p style="width:60px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">a long text that is cut</p>`, {}],
  ]) {
    const r = await t.both(html, { lang: "en", ...o });
    if (!t.same(name + " outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) continue;
    sameText(t, name + " structure", r.bm.structure.tree, r.ref.structure.tree);
    sameText(t, name + " marked content", marked(r.bm), marked(r.ref));
    const spans = (d) => (d.content(0).match(/\/Span\s*<<[^>]*(?:>[^>][^>]*)*>>\s*BDC/g) || []).length;
    t.same(name + " /Span marked-content count", spans(r.bm), spans(r.ref));
  }
});

// bm-only integrity: krilla fails the render ("invalid tag tree: page tag identifier ... doesn't appear in the tag tree")
// when a recorded marked-content id is not in the structure tree; a /ParentTree array must never hold `null`.
probe("tagging.integrity.parent-tree", "every MCID of every page has a structure parent (no null in /ParentTree), for all element cases", async (t) => {
  const bad = [];
  for (const [name, html] of Object.entries(ELEMENTS)) {
    const r = await t.bm(html, { lang: "en" });
    if (r.error) continue;
    if (/null/.test(r.structure.parents)) bad.push(name);
  }
  for (const [name, [html, o]] of Object.entries(PAGED)) {
    const r = await t.bm(html, o);
    if (r.error) continue;
    if (/null/.test(r.structure.parents)) bad.push("paged." + name);
  }
  t.ok(bad.length === 0, "bm writes null /ParentTree entries (marked content outside the structure tree) for: " + bad.join(", "));
});
