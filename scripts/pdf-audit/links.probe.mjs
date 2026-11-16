// Links, destinations and the outline: annotation dictionaries, destinations, /Names /Dests, outline tree.
import { probe, pdftotext } from "./lib.mjs";
import { outcome, annots, outlineText, catalogText, sameText, sameWithin, deep, META, PNG1 } from "./filelayer.util.mjs";

/** Compares annotations (rect to 0.01pt), the outline, /Names and the structure tree for one input. */
async function link(t, html, options = {}, { structure = true, annotations = true, id = "" } = {}) {
  const r = await t.both(html, options);
  const p = id ? id + " " : "";
  if (!t.same(p + "outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) return r;
  if (annotations) sameWithin(t, p + "annotations per page (numbers within 0.02pt)", annots(r.bm), annots(r.ref));
  sameWithin(t, p + "outline", outlineText(r.bm), outlineText(r.ref));
  sameText(t, p + "catalog /Names /Dests /OpenAction /PageMode", catalogText(r.bm, ["Names", "Dests", "OpenAction", "PageMode", "Outlines"]), catalogText(r.ref, ["Names", "Dests", "OpenAction", "PageMode", "Outlines"]));
  if (structure) sameText(t, p + "structure tree", r.bm.structure.tree, r.ref.structure.tree);
  return r;
}

/** A padded block must not shift an inline link annotation away from the linked text. */
function assertInlineTextLinkRect(t, d, id) {
  const extracted = pdftotext(d.bytes, `inline-link-${id}`, ["-bbox"]);
  if (extracted.skipped || !extracted.ok) {
    t.ok(false, `${id}: Poppler bbox extraction ${extracted.skipped ? "unavailable" : extracted.stderr}`);
    return;
  }
  const word = extracted.text.match(/<word xMin="([\d.-]+)" yMin="([\d.-]+)" xMax="([\d.-]+)" yMax="([\d.-]+)">padded<\/word>/);
  const page = d.pdf.pages[0];
  const refs = d.pdf.resolve(page.dict.Annots) || [];
  const annotation = refs.length > 0 ? d.pdf.resolve(refs[0]) : null;
  const rect = annotation ? d.pdf.resolve(annotation.Rect) : null;
  if (!word || !rect || rect.length !== 4) {
    t.ok(false, `${id}: extract linked text and annotation bounds`);
    return;
  }
  const [x0, y0, x1, y1] = word.slice(1).map(Number);
  const [left, bottom, right, top] = rect;
  const media = d.pages[0].media;
  const pageHeight = media[3] - media[1];
  const textBottom = pageHeight - y1;
  const textTop = pageHeight - y0;
  const tolerance = 0.03;
  t.ok(
    left <= x0 + tolerance && bottom <= textBottom + tolerance &&
      right >= x1 - tolerance && top >= textTop - tolerance,
    `${id}: annotation covers linked text bounds`,
  );
  t.differs(`${id}: Takumi shifts the inline rectangle into the block padding`);
}

const CASES = {
  "external.inline": [`<p>Pay at <a href="https://example.com/pay/1042">example.com/pay/1042</a>.</p>`],
  "external.block": [`<a href="https://example.com/" style="display:block;width:200px;height:40px;background:#eee">block link</a>`],
  "external.wrapped-lines": [`<p style="width:140px">start <a href="https://example.com/">a link that wraps across three or four lines of text</a> end</p>`],
  "external.nested-inline-markup": [`<p><a href="https://example.com/">plain <b>bold</b> <i>italic <u>under</u></i> tail</a></p>`],
  "external.image-link": [`<p><a href="https://example.com/"><img alt="pic" width="30" height="20" src="${PNG1}"></a></p>`],
  "external.inline-block-link": [`<p>x <a href="https://example.com/" style="display:inline-block;padding:4px;border:1px solid">padded</a> y</p>`],
  "external.flex-link": [`<a href="https://example.com/" style="display:flex;gap:4px"><span>one</span><span>two</span></a>`],
  "external.rotated": [`<a href="https://example.com/" style="display:block;width:100px;height:20px;transform:rotate(30deg);margin:40px">rotated</a>`],
  "external.rotated-inline": [`<p style="transform:rotate(-20deg);margin:60px;width:160px">text <a href="https://example.com/">rotated inline link</a></p>`],
  "external.scaled-translated": [`<div style="transform:translate(30px,20px) scale(1.5);transform-origin:0 0"><a href="https://example.com/">scaled</a></div>`],
  "external.nested-links": [`<a href="https://outer.example/" style="display:block;padding:10px">outer <a href="https://inner.example/">inner</a> tail</a>`],
  "external.empty-link": [`<p>a<a href="https://example.com/"></a>b</p>`],
  "external.zero-size-block": [`<a href="https://example.com/" style="display:block;width:0;height:0"></a><p>x</p>`],
  "external.clipped-by-overflow": [`<div style="width:50px;height:20px;overflow:hidden"><a href="https://example.com/" style="display:block;width:200px;height:100px">big</a></div>`],
  "external.hidden": [`<a href="https://a.example/" style="visibility:hidden">hidden</a><a href="https://b.example/" style="display:none">none</a><a href="https://c.example/" style="opacity:0">transparent</a>`],
  "external.same-url-twice": [`<p><a href="https://example.com/">one</a> and <a href="https://example.com/">two</a></p>`],
  "schemes": [["https://example.com/a?b=c&d=e#frag", "http://example.com/", "HTTPS://EXAMPLE.COM/", "mailto:a@b.c?subject=Hi%20there", "tel:+1-555-0100", "ftp://example.com/f", "javascript:alert(1)", "data:text/plain,hi", "file:///etc/passwd", "/relative/path", "relative.html", "../up", "?query", "//protocol-relative.example/", "sms:+1555", "", " ", "#", "https://example.com/ü?q=日本", "https://example.com/a b", "  https://example.com/trim  ", "mailto:", "http:"].map((u) => `<p><a href="${u.replace(/&/g, "&amp;")}">link to [${u.replace(/&/g, "&amp;")}]</a></p>`).join("")],
  "uri-encoding": [`<p><a href="https://example.com/(paren)\\back">parens</a> <a href="https://example.com/%E2%9C%93">pct</a> <a href="https://example.com/é">latin1</a> <a href="https://example.com/✓">utf8</a></p>`],
  "internal.id": [`<p><a href="#target">jump</a></p><div style="height:300px"></div><h2 id="target">Target</h2>`],
  "internal.missing-id": [`<p><a href="#nope">dangling</a> <a href="#">hash only</a> <a href="#target">ok</a></p><p id="target">t</p>`],
  "internal.percent-encoded-and-case": [`<p><a href="#section%201">enc</a> <a href="#Target">case</a> <a href="#t%C3%A9">utf8</a> <a href="#bad%zz">bad escape</a> <a href="#trail%2">short escape</a></p><p id="section 1">s1</p><p id="target">lower</p><p id="té">te</p><p id="bad%zz">b</p><p id="trail%2">tr</p>`],
  "internal.duplicate-ids": [`<p><a href="#dup">jump</a></p><p id="dup">first</p><div style="height:100px"></div><p id="dup">second</p>`],
  "internal.name-attribute": [`<p><a href="#named">jump</a></p><div style="height:100px"></div><a name="named">anchor by name</a>`],
  "internal.target-kinds": [`<p><a href="#i">inline</a> <a href="#e">empty</a> <a href="#t">table</a> <a href="#r">row</a> <a href="#c">cell</a> <a href="#img">img</a> <a href="#li">li</a> <a href="#hid">hidden</a> <a href="#none">display none</a> <a href="#abs">abs</a></p><p>text <span id="i">inline target</span></p><div id="e"></div><table id="t"><tr id="r"><td id="c">cell</td></tr></table><img id="img" alt="i" width="10" height="10" src="${PNG1}"><ul><li id="li">item</li></ul><p id="hid" style="visibility:hidden">hid</p><p id="none" style="display:none">none</p><p id="abs" style="position:absolute;top:500px">abs</p>`],
  "internal.self-and-link-is-target": [`<p><a id="self" href="#self">self</a></p>`],
  "internal.transformed-target": [`<p><a href="#tr">jump</a></p><div style="height:100px"></div><p id="tr" style="transform:translateY(80px) rotate(10deg)">moved</p>`],
  "internal.target-above-page-top": [`<p><a href="#neg">jump</a></p><p id="neg" style="position:relative;top:-80px">above</p>`],
  "table.href-on-row-and-groups": [`<table><thead href="https://thead.example/"><tr><th>h</th><th>h2</th></tr></thead><tbody href="https://tbody.example/"><tr href="https://row.example/"><td>a</td><td>b</td></tr><tr><td href="https://cell.example/">c</td><td>d</td></tr></tbody><tfoot href="https://tfoot.example/"><tr><td>f</td><td>g</td></tr></tfoot></table>`],
  "table.href-on-table": [`<table href="https://table.example/"><tr><td>a</td></tr></table>`],
  "table.href-on-empty-row": [`<table><tbody><tr href="https://row.example/"></tr><tr><td>x</td></tr></tbody></table>`],
  "href-on-non-anchor": [`<div href="https://div.example/">div</div><p href="https://p.example/">p</p><span href="https://span.example/">span</span><li href="https://li.example/">li</li><img href="https://img.example/" alt="i" width="10" height="10" src="${PNG1}"><h2 href="https://h.example/">h</h2>`],
  "svg-link": [`<svg width="100" height="30" xmlns:xlink="http://www.w3.org/1999/xlink"><a href="https://svg.example/"><rect width="100" height="30" fill="#ccc"/></a><a xlink:href="https://xlink.example/"><text x="5" y="20">t</text></a></svg>`],
  "area-map": [`<img usemap="#m" alt="map" width="40" height="40" src="${PNG1}"><map name="m"><area href="https://area.example/" shape="rect" coords="0,0,20,20"></map>`],
  "target-and-rel-attributes": [`<p><a href="https://example.com/" target="_blank" rel="noopener" title="Tooltip" download>attrs</a></p>`],
  "link.title-or-aria-label-as-contents": [`<p><a href="https://example.com/" title="Title text" aria-label="Aria text">visible</a></p>`],
  // takumi-pdf 0.20.0 measures an inline link from its block's border box: the rectangle sits padding + border up and
  // left of the text it covers. bm-render places it over the text (kept: the takumi rectangle misses the link).
  "inline-rect-in-padded-block": [`<p style="padding:10px;border:3px solid"><a href="https://example.com/">padded</a></p>`],
  // an anonymous block's inline content (inline elements next to block-level siblings) is not linked by takumi-pdf
  "inline-link-in-anonymous-block": [`<div>block</div><a href="https://a.example/">a</a> <span href="https://s.example/">s</span><p><span href="https://p.example/">in p</span></p>`],
  "many-links": [Array.from({ length: 60 }, (_, i) => `<a href="https://example.com/${i}">l${i}</a> `).join("")],
};

for (const [name, [html]] of Object.entries(CASES)) {
  probe("links." + name, "link annotations: " + name, async (t) => {
    const paddedInline = name === "inline-rect-in-padded-block";
    const tagged = await link(t, html, {}, { id: "tagged", annotations: !paddedInline });
    const untagged = await link(t, html, { tagged: false }, {
      id: "untagged",
      structure: false,
      annotations: !paddedInline,
    });
    if (paddedInline && tagged.bm && untagged.bm && !tagged.bm.error && !untagged.bm.error) {
      assertInlineTextLinkRect(t, tagged.bm, "tagged");
      assertInlineTextLinkRect(t, untagged.bm, "untagged");
    }
  });
}

const A5 = { size: "A5" };
const long = (n) => `<p>${"filler text ".repeat(n)}</p>`;
const PAGED = {
  "block-link-across-pages": [`${long(380)}<a href="https://example.com/" style="display:block;height:400px;background:#eee">tall block link</a>`, A5],
  "inline-link-across-pages": [`${long(390)}<p><a href="https://example.com/">${"linked words ".repeat(120)}</a></p>`, A5],
  "internal-forward-and-backward": [`<h1 id="top">Top</h1><p><a href="#end">to end</a></p>${long(900)}<h2 id="end">End</h2><p><a href="#top">to top</a></p>`, A5],
  "internal-target-at-page-top": [`<p><a href="#p2">to p2</a></p><h2 id="p2" style="break-before:page">Page two</h2>`, A5],
  "internal-target-with-margins": [`<p><a href="#p2">to p2</a></p><h2 id="p2" style="break-before:page;margin-top:50px">Page two</h2>`, { size: "A5", margin: 40 }],
  "links-in-bands": [`<h1 id="top">Top</h1>${long(700)}`, { ...A5, header: `<p><a href="https://header.example/">header link</a> <a href="#top">top</a></p>`, footer: `<p><a href="https://footer.example/">footer link</a></p>` }],
  // (takumi places an inline link's rectangle from the block's border box, without its padding and border: the cells
  // of this variant have neither, so only the repeats are compared; see links.inline-rect-in-padded-block)
  "link-in-repeated-thead-and-tfoot-no-padding": [`<table><thead><tr><th style="padding:0"><a href="https://thead.example/">head link</a></th></tr></thead><tbody>${"<tr><td>row</td></tr>".repeat(40)}</tbody><tfoot><tr><td style="padding:0"><a href="https://tfoot.example/">foot</a></td></tr></tfoot></table>`, A5],
  "link-in-repeated-thead": [`<table><thead><tr><th><a href="https://thead.example/">head link</a></th></tr></thead><tbody>${"<tr><td>row</td></tr>".repeat(90)}</tbody></table>`, A5],
  "link-in-fixed-element": [`<a href="https://fixed.example/" style="position:fixed;top:0;right:0">fixed link</a>${long(700)}`, A5],
  "page-ranges-drop-target": [`<h1 id="a">A</h1><p><a href="#c">to c (dropped page)</a> <a href="#b">to b</a></p><h1 id="b" style="break-before:page">B</h1><p><a href="#a">to a (dropped)</a> <a href="#c">to c</a></p><h1 id="c" style="break-before:page">C</h1><p><a href="#b">to b</a></p>`, { ...A5, pageRanges: [{ from: 2, to: 2 }], outline: true }],
  "page-ranges-keep-two": [`<h1 id="a">A</h1><h1 id="b" style="break-before:page">B</h1><p><a href="#a">to a</a> <a href="#c">to c</a></p><h1 id="c" style="break-before:page">C</h1>`, { ...A5, pageRanges: [{ from: 1, to: 1 }, { from: 3 }], outline: true }],
  "landscape-and-custom-size": [`<p><a href="https://example.com/">l</a> <a href="#x">x</a></p><div style="height:900px"></div><p id="x">x</p>`, { size: { width: 400, height: 300 }, margin: 10 }],
  "target-page-number": [`<p><a href="#r"><span>Results</span> <span class="targetPageNumber"></span></a></p><h1 id="r" style="break-before:page">Results</h1>`, A5],
};

function assertHeaderLinkTracksText(t, d, id) {
  if (!d || d.error) return;
  const boxes = pdftotext(d.bytes, `repeated-thead-${id}`, ["-bbox"]);
  if (boxes.skipped || !boxes.ok) {
    t.ok(false, `${id}: Poppler bbox extraction ${boxes.skipped ? "unavailable" : boxes.stderr}`);
    return;
  }
  const pageText = [...boxes.text.matchAll(/<page\b[^>]*>([\s\S]*?)<\/page>/g)].map((m) => m[1]);
  const pages = d.pdf.pages;
  const checks = pages.map((page, i) => {
    const annots = d.pdf.resolve(page.dict.Annots) || [];
    const links = annots.map((ref) => d.pdf.resolve(ref)).filter((a) => d.pdf.resolve(a.A)?.URI);
    const words = [...(pageText[i] || "").matchAll(/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]+)<\/word>/g)]
      .filter((m) => m[5] === "head" || m[5] === "link");
    if (links.length !== 1 || words.length !== 2) return false;
    const rect = d.pdf.resolve(links[0].Rect);
    const height = d.pages[i].media[3];
    const textRect = [
      Math.min(...words.map((m) => Number(m[1]))),
      height - Math.max(...words.map((m) => Number(m[4]))),
      Math.max(...words.map((m) => Number(m[3]))),
      height - Math.min(...words.map((m) => Number(m[2]))),
    ];
    return rect.length === 4 && rect.every((v, k) => Math.abs(v - textRect[k]) <= 0.03);
  });
  t.ok(pages.length === 4 && checks.every(Boolean), `${id}: repeated link rectangles match visible header text bounds on all pages`);
}

for (const [name, [html, o]] of Object.entries(PAGED)) {
  probe("links.paged." + name, "links across pages: " + name, async (t) => {
    if (name === "link-in-repeated-thead") {
      const tagged = await link(t, html, o, { id: "tagged", annotations: false });
      const plain = await link(t, html, { ...o, tagged: false }, { id: "untagged", structure: false, annotations: false });
      assertHeaderLinkTracksText(t, tagged.bm, "tagged");
      assertHeaderLinkTracksText(t, plain.bm, "untagged");
    } else {
      await link(t, html, o, { id: "tagged" });
      await link(t, html, { ...o, tagged: false }, { id: "untagged", structure: false });
    }
  });
}

probe("links.conformance.annotation-flags", "annotation dictionary under PDF/A (/F 4 print flag), UA (/Contents, /StructParent), UA-2 (structure destinations)", async (t) => {
  const html = `<h1 id="top">Top</h1><p><a href="https://example.com/">ext</a> <a href="#sec">int</a> <a href="#top">top</a></p><div style="height:200px"></div><h2 id="sec">Section</h2><p id="plain">plain target <a href="#plain">self</a></p>`;
  for (const o of [{}, { tagged: false }, { pdfa: "2b" }, { pdfa: "2b", tagged: false }, { pdfa: "2a", lang: "en" }, { pdfa: "3u" }, { tagged: "ua1", lang: "en" }, { tagged: "ua2", lang: "en" }, { pdfa: "4", lang: "en" }, { pdfa: "4f", tagged: "ua2", lang: "en" }, { pdfa: "3a", tagged: "ua1", lang: "en" }])
    await link(t, html, { ...o, metadata: META, outline: true }, { id: JSON.stringify(o) });
});

const OUTLINES = {
  "nesting-basic": `<h1>One</h1><h2>One.A</h2><h3>One.A.i</h3><h2>One.B</h2><h1>Two</h1>`,
  "skipped-levels": `<h1>One</h1><h3>skip to 3</h3><h6>skip to 6</h6><h2>back to 2</h2><h4>4 under 2</h4>`,
  "starts-deep": `<h4>starts at 4</h4><h2>then 2</h2><h1>then 1</h1><h3>3 under 1</h3>`,
  "same-level-run": `<h2>a</h2><h2>b</h2><h2>c</h2>`,
  "inline-markup-and-whitespace": `<h1>  Plain <strong>bold</strong>\n <em>em</em> <a href="https://e.com/">link</a>  </h1><h2>line<br>break</h2><h2>&amp; entity &lt;tag&gt;</h2>`,
  "non-ascii-and-long": `<h1>Résumé — 日本語 😀</h1><h2>${"long heading ".repeat(40)}</h2>`,
  "empty-and-image-headings": `<h1></h1><h1>   </h1><h1><img alt="logo" width="10" height="10" src="${PNG1}"></h1><h2>real</h2>`,
  "hidden-headings": `<h1 style="display:none">none</h1><h1 style="visibility:hidden">invisible</h1><h1 style="opacity:0">transparent</h1><h1 style="position:absolute;left:-9999px">offscreen</h1><h2>shown</h2>`,
  "headings-in-containers": `<section><h1>in section</h1><div><h2>in div</h2></div></section><table><tr><td><h3>in cell</h3></td></tr></table><ul><li><h2>in li</h2></li></ul><blockquote><h2>in quote</h2></blockquote>`,
  "visual-order-differs": `<div style="display:flex;flex-direction:column-reverse"><h1>source first, visually last</h1><h1>source second, visually first</h1></div>`,
  "absolute-heading-order": `<div style="position:relative;height:200px"><h1 style="position:absolute;top:150px">abs low (source first)</h1><h1>flow high (source second)</h1></div>`,
  "side-by-side-same-top": `<div style="display:flex"><h1>left</h1><h1>right</h1></div>`,
  "role-heading-not-outlined": `<div role="heading" aria-level="1">aria heading</div><h1>real</h1>`,
  "text-transform": `<h1 style="text-transform:uppercase">upper me</h1><style>h2::before{content:"1. "}</style><h2>generated prefix</h2>`,
  "no-headings": `<p>none</p>`,
  "uppercase-tags": `<H1>Upper tag</H1><H2>Second</H2>`,
};
for (const [name, html] of Object.entries(OUTLINES)) {
  probe("links.outline." + name, "outline: " + name, async (t) => {
    await link(t, html, { outline: true }, { id: "outline:true" });
    const r = await t.both(html, {});
    if (r.ref && !r.bm.error && !r.ref.error) t.same("no outline without the option", outlineText(r.bm), outlineText(r.ref));
  });
}

probe("links.outline.paged", "outline across pages: destinations (/XYZ left top zoom), headings in bands, repeated headings, page ranges", async (t) => {
  const body = `<h1>Chapter 1</h1>${long(500)}<h2>Section 1.1</h2>${long(500)}<h1 style="break-before:page">Chapter 2</h1><table><thead><tr><th><h3>Heading in repeated thead</h3></th></tr></thead><tbody>${"<tr><td>row</td></tr>".repeat(70)}</tbody></table>`;
  await link(t, body, { ...A5, outline: true }, { id: "plain" });
  await link(t, body, { ...A5, outline: true, header: `<h1>Band heading</h1>`, footer: `<h2>Footer heading</h2>` }, { id: "bands" });
  await link(t, body, { ...A5, outline: true, margin: { top: 60, bottom: 30, left: 20, right: 20 } }, { id: "margins" });
  await link(t, body, { ...A5, outline: true, pageRanges: [{ from: 2 }] }, { id: "ranges" });
  await link(t, body, { ...A5, tagged: "ua2", lang: "en", metadata: META }, { id: "ua2 structure destinations" });
  await link(t, body, { ...A5, tagged: "ua1", lang: "en", metadata: META }, { id: "ua1" });
  await link(t, body, { ...A5, outline: true, tagged: false }, { id: "untagged", structure: false });
});

probe("links.outline.dictionary", "outline dictionaries as written: /Type, /Count sign (open / closed), /First /Last /Prev /Next, /F, /C", async (t) => {
  const r = await t.both(`<h1>A</h1><h2>A1</h2><h3>A1a</h3><h2>A2</h2><h1>B</h1>`, { outline: true });
  if (!t.same("outcome", outcome(r.bm), outcome(r.ref)) || !r.ref || r.bm.error) return;
  const dump = (d) => { const out = []; const seen = new Set(); const walk = (ref) => { if (!ref || seen.has(ref.n)) return; seen.add(ref.n); const o = d.pdf.resolve(ref); out.push(deep(d, ref, 0, 1).replace(/\[page\d+/, "[")); for (const k of ["First", "Next"]) walk(o[k]); }; walk(d.catalog.Outlines); return out; };
  sameText(t, "outline objects", dump(r.bm), dump(r.ref));
});
