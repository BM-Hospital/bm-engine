// Audit probes: header / footer bands (bands.*). Method: see page-options.probe.mjs. A band is given as an HTML
// string, a node tree or `false`; it is laid out at the full page width and drawn in the page margin, 15 pt
// (20 px) from the page edge; an `auto` margin on that side is max(10mm, band height + 20 px).
import { probe } from "./lib.mjs";
import { cmp, cmpAll, doc, lines, stripPrefix } from "./paged-helpers.mjs";

const S = { width: 300, height: 300 };
const G = { geom: true, expect: "render" };
const D = doc(lines(1, 30));
const band = (text, style = "") => `<div style="font:10px/20px Inter;${style}">${text}</div>`;
const node = (text, style = {}) => ({ type: "container", style: { fontFamily: "Inter", fontSize: 10, lineHeight: "20px", ...style }, children: [{ type: "text", text }] });
const links = (x) => (x && !x.error ? x.pages.map((p) => (p.dict.Annots ? (x.pdf.resolve(p.dict.Annots) || []).length : 0)) : x && x.error);

probe("bands.html-string", "header / footer as an HTML string", async (t) => {
  await cmpAll(t, [
    ["header", D, { size: S, header: band("HEAD") }],
    ["footer", D, { size: S, footer: band("FOOT") }],
    ["both", D, { size: S, header: band("HEAD"), footer: band("FOOT") }],
    ["plain text (no element)", D, { size: S, header: "HEADTEXT" }],
    ["multiple root elements", D, { size: S, header: band("H1") + band("H2") }],
    ["a full html document as a band", D, { size: S, header: `<html><head><style>.h{font:10px/20px Inter}</style></head><body style="margin:0"><div class="h">HEAD</div></body></html>` }],
    ["body UA margin in a band", D, { size: S, header: `<body><div style="font:10px/20px Inter">HEAD</div></body>` }],
  ], G);
});
probe("bands.node-tree", "header / footer as a node tree", async (t) => {
  await cmpAll(t, [
    ["header node", D, { size: S, header: node("HEAD") }],
    ["footer node", D, { size: S, footer: node("FOOT") }],
    ["node with a counter class", D, { size: S, footer: { type: "container", style: { fontFamily: "Inter", fontSize: 10, lineHeight: "20px" }, children: [{ type: "text", text: "P" }, { type: "container", className: "pageNumber", children: [] }] } }],
    ["text node as a band", D, { size: S, header: { type: "text", text: "HEAD", style: { fontFamily: "Inter", fontSize: 10 } } }],
    ["node tree document + html band", { type: "container", style: { display: "block", fontFamily: "Inter", fontSize: 12 }, children: [{ type: "text", text: "BODY" }] }, { size: S, header: band("HEAD") }],
  ], G);
});
probe("bands.false-and-invalid", "band values: false, null, true, numbers", async (t) => {
  // (takumi-pdf renders the last four: its wrapper hands a band that is neither HTML nor a node to `fromJsx`, which
  // writes `true`, `5`, `{}` as text and a list as its items)
  await cmpAll(t, [
    ["header:false", D, { size: S, header: false }],
    ["header:null", D, { size: S, header: null }],
    ["footer:false + header", D, { size: S, header: band("HEAD"), footer: false }],
  ], G);
  await cmp(t, "header:true", D, { size: S, header: true });
  await cmp(t, "header:5", D, { size: S, header: 5 });
  await cmp(t, "header:[]", D, { size: S, header: [] });
  await cmp(t, "header:{} (not a node)", D, { size: S, header: {} });
});
probe("bands.geometry", "bands lay out at the full page width, 20 px from the page edge", async (t) => {
  await cmpAll(t, [
    ["right-aligned header (full width)", D, { size: S, header: band("HEAD", "text-align:right") }],
    ["centred footer", D, { size: S, footer: band("FOOT", "text-align:center") }],
    ["band with explicit margins 50px: still full page width", D, { size: S, margin: 50, header: band("HEAD", "text-align:right"), footer: band("FOOT") }],
    ["band wider than the page is clipped", D, { size: S, header: band("HEAD", "width:500px;text-align:right") }],
    ["band with padding", D, { size: S, header: band("HEAD", "padding:0 30px") }],
    ["width:100% flex band with space-between", D, { size: S, footer: `<div style="display:flex;width:100%;justify-content:space-between;font:10px/20px Inter"><span>LEFT</span><span>RIGHT</span></div>` }],
    ["percent height in a band (unbounded)", D, { size: S, header: band("HEAD", "height:50%") }],
    ["landscape page", D, { size: S, landscape: true, header: band("HEAD", "text-align:right"), footer: band("FOOT") }],
    ["band on an A4 page", doc(lines(1, 60)), { header: band("HEAD", "text-align:right"), footer: band("FOOT", "text-align:center") }],
  ], G);
});
probe("bands.empty", "a band without content (zero height)", async (t) => {
  await cmpAll(t, [
    ["empty string", D, { size: S, header: "" }],
    ["an empty div", D, { size: S, header: "<div></div>" }],
    ["a display:none band", D, { size: S, footer: band("HID", "display:none") }],
    ["an empty default footer with a pages.first footer", D, { size: S, footer: "<div></div>", pages: { first: { footer: band("FIRST") } } }],
  ], { geom: true });
});
probe("bands.viewport-units", "viewport units in a band are the whole page's", async (t) => {
  await cmpAll(t, [
    ["margin-left:50vw", D, { size: S, header: band("HEAD", "margin-left:50vw") }],
    ["height:10vh", D, { size: S, header: band("HEAD", "height:10vh") }],
    ["height:10vh only (no text)", D, { size: S, header: `<div style="height:10vh"></div>` }],
    ["font-size:5vmin", D, { size: S, header: `<div style="font:5vmin/10vh Inter">HEAD</div>` }],
  ], { geom: true });
});
probe("bands.auto-margin", "auto margins grow with the band: max(10mm, band height + 20 px)", async (t) => {
  await cmpAll(t, [
    ["10 px band (below the 10mm minimum)", D, { size: S, header: band("H", "line-height:10px") }],
    ["17 px band (17 + 20 < 37.8)", D, { size: S, header: band("H", "line-height:17px") }],
    ["18 px band (18 + 20 > 37.8)", D, { size: S, header: band("H", "line-height:18px") }],
    ["60 px header", D, { size: S, header: band("H", "height:60px") }],
    ["60 px footer", D, { size: S, footer: band("F", "height:60px") }],
    ["60 px header + 40 px footer", D, { size: S, header: band("H", "height:60px"), footer: band("F", "height:40px") }],
    ["three-line header", D, { size: S, header: band("H1<br>H2<br>H3") }],
    ["margin {top:'auto'} with a header, other sides 5", D, { size: S, margin: { top: "auto", left: 5, right: 5, bottom: 5 }, header: band("H", "height:60px") }],
    ["left / right auto margins ignore the bands", D, { size: S, margin: { top: 10, bottom: 10 }, header: band("H", "height:60px") }],
    ["band taller than the page leaves no area", D, { size: S, header: band("H", "height:400px") }],
    ["bands that leave less than nothing: 150 + 150", D, { size: S, header: band("H", "height:130px"), footer: band("F", "height:130px") }],
  ], { geom: true });
});
probe("bands.fixed-margin", "a numeric margin does not grow: the band overlaps the content", async (t) => {
  await cmpAll(t, [
    ["margin 10 with a 20 px band", D, { size: S, margin: 10, header: band("HEAD"), footer: band("FOOT") }],
    ["margin 0 with bands", D, { size: S, margin: 0, header: band("HEAD"), footer: band("FOOT") }],
    ["margin 100 with a 20 px band (band stays at the page edge)", D, { size: S, margin: 100, header: band("HEAD"), footer: band("FOOT") }],
    ["a band taller than a numeric margin is clipped to its own height, not the margin", D, { size: S, margin: 30, header: band("H1<br>H2<br>H3<br>H4") }],
  ], G);
});
probe("bands.tiny-page", "bands on a page <= 1in tall: the auto margin is 0", async (t) => {
  await cmpAll(t, [
    ["96 px tall page with a header", D, { size: { width: 300, height: 96 }, header: band("HEAD") }],
    ["97 px tall page with a header", D, { size: { width: 300, height: 97 }, header: band("HEAD") }],
  ], { geom: true });
});
probe("bands.pages-rules", "pages: first / last / odd / even overrides", async (t) => {
  const o = (pages, extra = {}) => ({ size: S, header: band("HEAD"), footer: band("FOOT"), pages, ...extra });
  await cmpAll(t, [
    ["first header", D, o({ first: { header: band("FIRST") } })],
    ["last footer", D, o({ last: { footer: band("LAST") } })],
    ["odd / even headers", D, o({ odd: { header: band("ODD") }, even: { header: band("EVEN") } })],
    ["first beats odd on page 1", D, o({ first: { header: band("FIRST") }, odd: { header: band("ODD") } })],
    ["last beats odd / even on the last page", D, o({ last: { header: band("LAST") }, odd: { header: band("ODD") }, even: { header: band("EVEN") } })],
    ["first:false removes the header on page 1", D, o({ first: { header: false } })],
    ["last:{footer:false}", D, o({ last: { footer: false } })],
    ["even:{header:false, footer:false}", D, o({ even: { header: false, footer: false } })],
    ["a rule with only a footer falls through for the header", D, o({ first: { footer: band("FIRSTF") } })],
    ["a first rule without header falls through to odd", D, o({ first: { footer: band("FF") }, odd: { header: band("ODD") } })],
    ["rules without a top-level band", D, { size: S, pages: { first: { header: band("FIRST") }, last: { footer: band("LAST") } } }],
    ["a one-page document: first wins over last", doc(lines(1, 3)), o({ first: { header: band("FIRST") }, last: { header: band("LAST") } })],
    ["a one-page document: last applies when first leaves the field unset", doc(lines(1, 3)), o({ first: { footer: band("FF") }, last: { header: band("LAST") } })],
    ["empty pages object", D, o({})],
    ["null rule", D, o({ first: null })],
    ["rule bands as node trees", D, o({ first: { header: node("FIRSTN") } })],
    ["all rules false and no default: no band at all", D, { size: S, pages: { first: { header: false } } }],
  ], G);
});
probe("bands.pages-rules.margin", "auto margins fit the tallest band any page may draw", async (t) => {
  await cmpAll(t, [
    ["taller last-page footer", D, { size: S, footer: band("F"), pages: { last: { footer: band("L1<br>L2<br>L3<br>L4") } } }],
    ["taller first-page header, default none", D, { size: S, pages: { first: { header: band("H1<br>H2<br>H3<br>H4") } } }],
    ["header only on even pages", D, { size: S, pages: { even: { header: band("E", "height:60px") } } }],
    ["default tall, first:false", D, { size: S, header: band("H", "height:60px"), pages: { first: { header: false } } }],
  ], G);
});
probe("bands.pages-rules.unknown-keys", "pages: unknown keys are rejected", async (t) => {
  await cmp(t, "pages.middle", D, { size: S, pages: { middle: { header: band("X") } } }, { expect: "error" });
  await cmp(t, "pages.first.body", D, { size: S, pages: { first: { body: band("X") } } }, { expect: "error" });
  await cmp(t, "pages.First (case)", D, { size: S, pages: { First: { header: band("X") } } }, { expect: "error" });
  await cmp(t, "pages as an array", D, { size: S, pages: [] });
  await cmp(t, "pages as a string", D, { size: S, pages: "first" }, { expect: "error" });
  await cmp(t, "pages.first as a string", D, { size: S, pages: { first: "x" } }, { expect: "error" });
  await cmp(t, "pages.first.header:true", D, { size: S, pages: { first: { header: true } } });
});
probe("bands.styles", "which styles reach a band: the css option, the document's <style>, the band's own <style>", async (t) => {
  const hidden = (cls) => `<div class="${cls}" style="font:10px/20px Inter">BANDX</div><div style="font:10px/20px Inter">BAND</div>`;
  await cmpAll(t, [
    ["css option applies to bands", D, { size: S, header: hidden("hide"), css: [`.hide{display:none}`] }],
    ["the document's <style> does not reach a band?", doc(lines(1, 30), `.hide{display:none}`), { size: S, header: hidden("hide") }],
    ["a band's <style> applies inside the band", D, { size: S, header: `<style>.hide{display:none}</style>` + hidden("hide") }],
    ["a band's <style> does not leak into the document?", doc(`<div class="l hide">DOCX</div>` + lines(1, 30)), { size: S, header: `<style>.hide{display:none}</style>` + band("HEAD") }],
    ["a header's <style> and the footer", D, { size: S, header: `<style>.hide{display:none}</style>` + band("HEAD"), footer: hidden("hide") }],
    ["cssVariables reach a band", D, { size: S, header: band("HEAD", "margin-left:var(--x)"), cssVariables: { x: "100px" } }],
    ["the document's font-family is not inherited by a band", doc(lines(1, 30)), { size: S, header: `<div style="font-size:10px;line-height:20px">HEAD</div>` }],
    ["fontFamilies option reaches a band", D, { size: S, header: `<div style="font-size:10px;line-height:20px">HEAD</div>`, fontFamilies: ["Inter"] }],
    ["@media print in a band", D, { size: S, header: `<style>.p{display:none} @media print{.p{display:block}}</style><div class="p" style="font:10px/20px Inter">HPRINT</div>` + band("HEAD") }],
    ["tw classes in a band", D, { size: S, header: `<div tw="text-right" style="font:10px/20px Inter">HEAD</div>` }],
    ["lang option / dir=rtl in a band", D, { size: S, header: `<div dir="rtl" style="font:10px/20px Inter">HEAD</div>` }],
    ["@page in a band's <style> is not a page rule?", D, { size: S, header: `<style>@page{margin:80px}</style>` + band("HEAD") }],
  ], G);
});
const PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";
probe("bands.images", "images in bands", async (t) => {
  const xobjects = (x) => (x && !x.error ? x.typed("XObject", "Image").length : x && x.error);
  const r = await cmp(t, "data: URI image in a header", D, { size: S, header: `<div style="font:10px/20px Inter"><img src="${PNG}" style="width:40px;height:30px;vertical-align:top"> LOGO</div>` }, G);
  if (r.ref) t.same("image XObjects (one image, shared by every page)", xobjects(r.bm), xobjects(r.ref));
  const png = Uint8Array.from(Buffer.from(PNG.split(",")[1], "base64"));
  const r2 = await cmp(t, "image from the images option", D, { size: S, header: `<div style="font:10px/20px Inter"><img src="https://x.test/logo.png" style="width:40px;height:30px"> LOGO</div>`, images: [{ src: "https://x.test/logo.png", data: png }] }, G);
  if (r2.ref) t.same("images option: image XObjects", xobjects(r2.bm), xobjects(r2.ref));
  await cmp(t, "the image sizes the band (auto margin)", D, { size: S, header: `<img src="${PNG}" style="display:block;width:40px;height:70px">` }, G);
  await cmp(t, "background-image in a band", D, { size: S, header: `<div style="height:30px;background:url(${PNG}) repeat;font:10px/20px Inter">BG</div>` }, G);
  await cmp(t, "an image that is not provided", D, { size: S, header: `<div style="font:10px/20px Inter"><img src="https://x.test/missing.png" style="width:40px;height:30px"> LOGO</div>` });
});
probe("bands.links", "links in bands", async (t) => {
  const r = await cmp(t, "external link in a footer", D, { size: S, footer: `<div style="font:10px/20px Inter"><a href="https://example.com/">SITE</a></div>` }, G);
  if (r.ref) t.same("link annotations per page", links(r.bm), links(r.ref));
  const r2 = await cmp(t, "internal link in a header", doc(lines(1, 20) + `<div id="t" class="l">TARGET</div>` + lines(21, 30)), { size: S, header: `<div style="font:10px/20px Inter"><a href="#t">TOP</a></div>` }, G);
  if (r2.ref) t.same("internal link annotations per page", links(r2.bm), links(r2.ref));
  const r3 = await cmp(t, "link in a position:fixed box", doc(`<div style="position:fixed;top:0;right:0"><a href="https://example.com/">FIXLINK</a></div>` + lines(1, 30)), { size: S }, G);
  if (r3.ref) t.same("fixed box link annotations per page", links(r3.bm), links(r3.ref));
});
probe("bands.paint", "band backgrounds, clipping and draw order (header under the content, footer over it)", async (t) => {
  const P = { size: S, tagged: false };
  const GP = { geom: true, paint: true, expect: "render" };
  await cmpAll(t, [
    ["header with a full-width background", D, { ...P, header: band("HEAD", "background:#cde") }],
    ["footer with a border-top", D, { ...P, footer: band("FOOT", "border-top:2px solid #000") }],
    ["band overflow is clipped to the band's height", D, { ...P, header: `<div style="height:20px;font:10px/20px Inter">HEAD<div style="height:100px;background:#f00"></div></div>` }],
    ["position:absolute inside a band", D, { ...P, header: `<div style="position:relative;height:30px;font:10px/20px Inter">HEAD<div style="position:absolute;right:0;top:5px">ABS</div></div>` }],
    ["position:fixed inside a band", D, { ...P, header: `<div style="height:30px;font:10px/20px Inter">HEAD<div style="position:fixed;right:0;top:5px">FIX</div></div>` }],
    ["a break-before:page inside a band is ignored", D, { ...P, header: band("H1") + `<div style="break-before:page;font:10px/20px Inter">H2</div>` }],
    ["backgroundColor under the bands", D, { ...P, backgroundColor: "#ffe", header: band("HEAD", "background:#cde"), footer: band("FOOT") }],
    ["margin 10: header band drawn under the content, footer over it", D, { ...P, margin: 10, header: band("HEAD", "background:#cde;height:60px"), footer: band("FOOT", "background:#edc;height:60px") }],
  ], GP);
});
probe("bands.tagged", "bands are artifacts in a tagged document (not in the structure tree)", async (t) => {
  const r = await cmp(t, "tagged with bands", D, { size: S, header: band("HEAD"), footer: band("FOOT") }, G);
  if (r.ref && !r.bm.error && !r.ref.error) {
    const art = (x) => x.pages.map((_, i) => (x.content(i).match(/\/Artifact\b/g) || []).length);
    t.same("Artifact marked-content sequences per page", art(r.bm), art(r.ref));
  }
});
probe("bands.error-in-band", "errors raised by a band", async (t) => {
  const e = async (label, o) => { const r = await t.both(D, o); t.same(label, r.bm.error ? "ERROR " + stripPrefix(r.bm.error) : "renders", r.ref && (r.ref.error ? "ERROR " + r.ref.error : "renders")); };
  await e("uncovered characters in a band", { size: S, header: band("中文") });
  await e("unsupported filter in a band", { size: S, header: band("HEAD", "filter:blur(2px)") });
});
