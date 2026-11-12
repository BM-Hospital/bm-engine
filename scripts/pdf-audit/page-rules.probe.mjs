// Audit probes: `@page` rules (size, margins, :first / :left / :right / :blank, named pages, cascade, at-rule
// nesting, units, page-margin boxes). Method: see page-options.probe.mjs. The base options are a 300 x 200 px page
// with 10 px margins; a rule that takes effect changes the page box, the number of 20 px lines per page or the
// word positions.
import { probe } from "./lib.mjs";
import { SMALL, cmp, cmpAll, doc, lines } from "./paged-helpers.mjs";

const G = { geom: true, expect: "render" };
const page = (css, n = 30, body) => doc(body || lines(1, n), css);

probe("page.at-page.size.keywords", "@page size: every keyword, case-insensitive", async (t) => {
  for (const k of ["A3", "A4", "A5", "B4", "B5", "JIS-B4", "JIS-B5", "ledger", "legal", "letter", "a4", "LETTER", "Jis-b5"]) await cmp(t, k, page(`@page{size:${k}}`, 3), SMALL, G);
});
probe("page.at-page.size.orientation", "@page size: landscape / portrait", async (t) => {
  await cmpAll(t, [
    ["A5 landscape", page(`@page{size:A5 landscape}`, 3), SMALL],
    ["landscape A5", page(`@page{size:landscape A5}`, 3), SMALL],
    ["A5 portrait", page(`@page{size:A5 portrait}`, 3), SMALL],
    ["landscape alone (options page is already landscape)", page(`@page{size:landscape}`), SMALL],
    ["portrait alone turns the 300x200 option page", page(`@page{size:portrait}`), SMALL],
    ["landscape alone with a portrait option", page(`@page{size:landscape}`), { size: { width: 200, height: 300 }, margin: 10 }],
    ["landscape with the default A4", page(`@page{size:landscape}`, 3), {}],
    ["LANDSCAPE upper case", page(`@page{size:LANDSCAPE}`), { size: { width: 200, height: 300 }, margin: 10 }],
    ["landscape + option landscape:true", page(`@page{size:landscape}`), { size: { width: 200, height: 300 }, landscape: true, margin: 10 }],
    ["portrait + option landscape:true", page(`@page{size:portrait}`), { size: { width: 200, height: 300 }, landscape: true, margin: 10 }],
  ], G);
});
probe("page.at-page.size.lengths", "@page size: one or two lengths, units", async (t) => {
  await cmpAll(t, [
    ["400px 300px", page(`@page{size:400px 300px}`), SMALL],
    ["250px (square)", page(`@page{size:250px}`), SMALL],
    ["100mm 80mm", page(`@page{size:100mm 80mm}`), SMALL],
    ["4in 3in", page(`@page{size:4in 3in}`), SMALL],
    ["10cm 200pt", page(`@page{size:10cm 200pt}`), SMALL],
    ["30pc 400q", page(`@page{size:30pc 400q}`), SMALL],
    ["calc(200px + 100px) 200px", page(`@page{size:calc(200px + 100px) 240px}`), SMALL],
    ["20em 15em (root font-size 12px... the initial 16px)", page(`@page{size:20em 15em}`), SMALL],
    ["20rem 15rem with html font-size 10px", page(`html{font-size:10px} @page{size:30rem 20rem}`), SMALL],
    ["var()", page(`:root{--w:400px} @page{size:var(--w) 300px}`), SMALL],
    ["var() with fallback", page(`@page{size:var(--nope, 400px) 300px}`), SMALL],
    ["unitless 0 is invalid -> ignored", page(`@page{size:0}`), SMALL],
    ["300 200 (unitless) is invalid -> ignored", page(`@page{size:400 300}`), SMALL],
  ], G);
});
probe("page.at-page.size.auto-and-invalid", "@page size: auto, invalid values are dropped", async (t) => {
  await cmpAll(t, [
    ["auto", page(`@page{size:auto}`), SMALL],
    ["auto after a size (later wins)", page(`@page{size:400px 300px} @page{size:auto}`), SMALL],
    ["negative length", page(`@page{size:-400px 300px}`), SMALL],
    ["percentage", page(`@page{size:50% 50%}`), SMALL],
    ["unknown keyword", page(`@page{size:tabloid}`), SMALL],
    ["two keywords", page(`@page{size:A4 A5}`), SMALL],
    ["three lengths", page(`@page{size:400px 300px 200px}`), SMALL],
    ["length + orientation", page(`@page{size:400px 300px landscape}`), SMALL],
    ["invalid after valid in one rule keeps the valid one", page(`@page{size:400px 300px; size:bogus}`), SMALL],
    ["size too small for the option margins is kept (no area -> options geometry)", page(`@page{size:15px 15px}`), SMALL],
    ["zero size", page(`@page{size:0px 0px}`), SMALL],
  ], { geom: true });
});
probe("page.at-page.size.viewport-units", "@page size / margin in viewport units (of the option page)", async (t) => {
  await cmpAll(t, [
    ["size 50vw 100vh", page(`@page{size:150vw 100vh}`), SMALL],
    ["margin 10vh", page(`@page{margin:10vh}`), SMALL],
    ["margin 10vw 5vmin", page(`@page{margin:10vw 5vmin}`), SMALL],
  ], G);
});
probe("page.at-page.margin.shorthand", "@page margin: 1-4 values", async (t) => {
  await cmpAll(t, [
    ["margin 30px", page(`@page{margin:30px}`), SMALL],
    ["margin 0", page(`@page{margin:0}`), SMALL],
    ["margin 30px 5px", page(`@page{margin:30px 5px}`), SMALL],
    ["margin 10px 20px 50px", page(`@page{margin:10px 20px 50px}`), SMALL],
    ["margin 10px 20px 50px 60px", page(`@page{margin:10px 20px 50px 60px}`), SMALL],
    ["margin in mm / in / pt / cm", page(`@page{margin:5mm 0.25in 12pt 0.5cm}`), SMALL],
    ["five values are invalid", page(`@page{margin:1px 2px 3px 4px 5px}`), SMALL],
    ["negative margin", page(`@page{margin:-10px}`), SMALL],
    ["calc()", page(`@page{margin:calc(10px + 2 * 10px)}`), SMALL],
  ], G);
});
probe("page.at-page.margin.longhands", "@page margin-top / -right / -bottom / -left", async (t) => {
  await cmpAll(t, [
    ["margin-top", page(`@page{margin-top:50px}`), SMALL],
    ["margin-bottom", page(`@page{margin-bottom:50px}`), SMALL],
    ["margin-left", page(`@page{margin-left:80px}`), SMALL],
    ["margin-right", page(`@page{margin-right:80px}`, 30, `<div style="text-align:right">` + lines(1, 30) + `</div>`), SMALL],
    ["longhand after shorthand", page(`@page{margin:30px;margin-top:0}`), SMALL],
    ["shorthand after longhand", page(`@page{margin-top:0;margin:30px}`), SMALL],
    ["over option auto margins", page(`@page{margin-top:0}`), { size: { width: 300, height: 200 } }],
    ["logical margin-block is not a descriptor", page(`@page{margin-block:50px}`), SMALL],
  ], G);
});
probe("page.at-page.margin.percent-auto", "@page margins: percentages (of the page size on that axis) and auto (= 0)", async (t) => {
  await cmpAll(t, [
    ["margin 10%", page(`@page{margin:10%}`), SMALL],
    ["margin-top 25%", page(`@page{margin-top:25%}`), SMALL],
    ["margin-left 25%", page(`@page{margin-left:25%}`), SMALL],
    ["margin auto", page(`@page{margin:auto}`), SMALL],
    ["margin-top auto over option 40", page(`@page{margin-top:auto}`), { size: { width: 300, height: 200 }, margin: 40 }],
    ["percent of an @page size", page(`@page{size:400px 300px;margin:10%}`), SMALL],
    ["calc(10% + 5px)", page(`@page{margin:calc(10% + 5px)}`), SMALL],
  ], G);
});
/** A whole document (<html><head><style>): takumi reads the page context (font size, custom properties, direction) from the html element. */
const full = (css, n = 30, attrs = "") => `<html${attrs}><head><style>html,body{margin:0;padding:0} body{font:12px/20px Inter} .l{height:20px} ${css}</style></head><body>${lines(1, n)}</body></html>`;
probe("page.at-page.margin.em-rem", "@page margins: em / rem read the root element's font size", async (t) => {
  await cmpAll(t, [
    ["2em (html 16px, body 12px; takumi resolves against the body)", full(`@page{margin:2em}`), SMALL],
    ["3em with html font-size 20px", full(`html{font-size:20px} @page{margin:3em}`), SMALL],
    ["3rem with html font-size 20px", full(`html{font-size:20px} @page{margin:3rem}`), SMALL],
    ["3em with body font-size 30px (takumi: the body is the tree root -> 90px)", full(`body{font-size:30px} @page{margin:3em}`), SMALL],
    ["3em, fragment source (no html element)", page(`html{font-size:20px} @page{margin:3em}`), SMALL],
  ], G);
});
probe("page.at-page.margin.ex-ch", "@page margins: ex / ch units", async (t) => {
  await cmp(t, "2ch 2ex", full(`@page{margin:2ch 2ex}`), SMALL, G);
});
probe("page.at-page.var", "@page: var() reads the root element's custom properties", async (t) => {
  await cmpAll(t, [
    ["margin var() from :root", full(`:root{--m:40px} @page{margin:var(--m)}`), SMALL],
    ["margin var() from html", full(`html{--m:40px} @page{margin:var(--m)}`), SMALL],
    ["html style attribute", full(`@page{margin:var(--m)}`, 30, ` style="--m:40px"`), SMALL],
    ["var() with fallback", full(`@page{margin:var(--nope, 40px)}`), SMALL],
    ["var() chain", full(`:root{--a:var(--b);--b:40px} @page{margin:var(--a)}`), SMALL],
    ["size var()", full(`:root{--w:400px} @page{size:var(--w) 300px}`), SMALL],
  ], G);
});
probe("page.at-page.var.unset", "@page: a var() that does not resolve unsets the descriptor (margin 0, size auto)", async (t) => {
  await cmpAll(t, [
    ["var() set on body (takumi reads it: the body is the tree root)", full(`body{--m:40px} @page{margin:var(--m)}`), SMALL],
    ["var() undefined", full(`@page{margin:var(--nope)}`), SMALL],
    ["size var() undefined -> auto", full(`@page{size:400px 300px} @page{size:var(--w) 300px}`), SMALL],
    ["var() resolving to an invalid value", full(`:root{--m:bogus} @page{margin:40px; margin:var(--m)}`), SMALL],
  ], G);
});
probe("page.at-page.var.no-root-element", "@page var(): fragment source / css option / cssVariables (takumi: not read, unset)", async (t) => {
  await cmpAll(t, [
    ["fragment source, :root in <style>", page(`:root{--m:40px} @page{margin:var(--m)}`), SMALL],
    ["fragment source, css option", page(``), { ...SMALL, css: [`:root{--m:40px} @page{margin:var(--m)}`] }],
    ["cssVariables option, fragment", page(`@page{margin:var(--m)}`), { ...SMALL, cssVariables: { m: "40px" } }],
    ["cssVariables option, full document", full(`@page{margin:var(--m)}`), { ...SMALL, cssVariables: { m: "40px" } }],
  ], G);
});
probe("page.at-page.first", "@page :first", async (t) => {
  await cmpAll(t, [
    [":first margin-top", page(`@page :first{margin-top:90px}`), SMALL],
    [":first margin-bottom", page(`@page{margin:10px} @page :first{margin-bottom:90px}`), SMALL],
    [":first before the general rule still wins (specificity)", page(`@page :first{margin-top:90px} @page{margin:10px}`), SMALL],
    [":first size (height only changes)", page(`@page :first{size:300px 120px}`), SMALL],
    [":FIRST upper case", page(`@page :FIRST{margin-top:90px}`), SMALL],
    ["@page:first without a space", page(`@page:first{margin-top:90px}`), SMALL],
  ], G);
});
probe("page.at-page.first.width", "@page :first with another page width (content re-flows per page)", async (t) => {
  const wrap = `<div style="font:12px/20px Inter">${"word ".repeat(120)}</div>`;
  await cmpAll(t, [
    [":first size 200px 200px", page(`@page :first{size:200px 200px}`, 0, wrap), SMALL],
    [":first margin-left 100px", page(`@page :first{margin-left:100px}`, 0, wrap), SMALL],
    [":first size, numbered lines", page(`@page :first{size:500px 200px}`), SMALL],
  ], G);
});
probe("page.at-page.left-right", "@page :left / :right (first page is a right page)", async (t) => {
  await cmpAll(t, [
    [":left margin-top", page(`@page :left{margin-top:90px}`, 40), SMALL],
    [":right margin-top", page(`@page :right{margin-top:90px}`, 40), SMALL],
    [":left and :right heights", page(`@page :left{size:300px 120px} @page :right{size:300px 160px}`, 40), SMALL],
    [":first beats :right on page 1", page(`@page :right{margin-top:90px} @page :first{margin-top:50px}`, 40), SMALL],
    [":left margin-bottom + :first", page(`@page :left{margin-bottom:90px} @page :first{margin-bottom:50px}`, 40), SMALL],
  ], G);
});
probe("page.at-page.left-right.rtl", "@page :left / :right under a root direction: rtl (first page is a left page)", async (t) => {
  await cmpAll(t, [
    ["html dir=rtl attribute", `<html dir="rtl"><body>` + page(`@page :left{margin-top:90px}`, 40) + `</body></html>`, SMALL],
    ["html{direction:rtl}", page(`html{direction:rtl} @page :left{margin-top:90px}`, 40), SMALL],
    ["body{direction:rtl} is not the root", page(`body{direction:rtl} @page :left{margin-top:90px}`, 40), SMALL],
    ["rtl :right", page(`html{direction:rtl} @page :right{margin-top:90px}`, 40), SMALL],
  ], { geom: false, expect: "render" });
});
probe("page.at-page.left-right.width", "@page :left / :right with different page widths", async (t) => {
  const wrap = `<div style="font:12px/20px Inter">${"word ".repeat(200)}</div>`;
  await cmpAll(t, [
    ["gutter margins (same width, shifted)", page(`@page :left{margin-left:40px;margin-right:10px} @page :right{margin-left:10px;margin-right:40px}`, 40), SMALL],
    ["different widths", page(`@page :left{size:200px 200px} @page :right{size:400px 200px}`, 0, wrap), SMALL],
    ["different page-area widths", page(`@page :left{margin-left:100px}`, 0, wrap), SMALL],
  ], G);
});
probe("page.at-page.blank", "@page :blank (not a selector takumi reads: the rule is dropped)", async (t) => {
  await cmpAll(t, [
    [":blank margin", page(`@page :blank{margin:90px}`), SMALL],
    [":blank with break-before:left", doc(lines(1, 3) + `<div class="l" style="break-before:left">X</div>` + lines(4, 6), `@page :blank{size:500px 500px}`), SMALL],
    ["unknown pseudo :nth(2)", page(`@page :nth(2){margin:90px}`), SMALL],
    ["two pseudo-classes :first:left", page(`@page :first:left{margin-top:90px}`), SMALL],
    ["selector list", page(`@page :first, :left{margin-top:90px}`), SMALL],
  ], G);
});
probe("page.at-page.cascade", "@page cascade: source order, specificity, !important", async (t) => {
  await cmpAll(t, [
    ["later rule wins", page(`@page{margin:90px 10px} @page{margin:30px 10px}`), SMALL],
    ["per-descriptor merge", page(`@page{margin-top:60px} @page{margin-bottom:60px}`), SMALL],
    ["!important beats a later rule", page(`@page{margin-top:60px !important} @page{margin-top:0}`), SMALL],
    ["!important beats :first", page(`@page{margin-top:60px !important} @page :first{margin-top:0}`), SMALL],
    ["!important on size", page(`@page{size:400px 300px !important} @page{size:300px 200px}`), SMALL],
    ["both important: later wins", page(`@page{margin-top:60px !important} @page{margin-top:30px !important}`), SMALL],
    ["style element order vs css option (css option first)", page(`@page{margin-top:60px}`), { ...SMALL, css: ["@page{margin-top:0}"] }],
    ["css option only", page(``), { ...SMALL, css: ["@page{margin-top:60px}"] }],
    ["two css option entries", page(``), { ...SMALL, css: ["@page{margin-top:60px}", "@page{margin-top:30px}"] }],
    ["@page wins over the size / margin / landscape options", page(`@page{size:A5;margin:20mm}`, 3), { size: "letter", margin: 0, landscape: true }],
    ["comments and odd spacing", page(`/* c */ @page /* x */ { /* y */ margin-top : 60px ; }`), SMALL],
    ["@PAGE upper case", page(`@PAGE{margin-top:60px}`), SMALL],
    ["unknown descriptors are ignored", page(`@page{color:red;margin-top:60px;bleed:3mm;marks:crop}`), SMALL],
    ["padding / border on the page box are ignored", page(`@page{padding:40px;border:10px solid red}`), SMALL],
  ], G);
});
probe("page.at-page.in-media", "@page inside @media", async (t) => {
  await cmpAll(t, [
    ["@media print", page(`@media print{@page{margin-top:60px}}`), SMALL],
    ["@media screen does not apply", page(`@media screen{@page{margin-top:60px}}`), SMALL],
    ["@media (min-width:290px) sees the option page (300px)", page(`@media (min-width:290px){@page{margin-top:60px}}`), SMALL],
    ["@media (min-width:310px) does not match", page(`@media (min-width:310px){@page{margin-top:60px}}`), SMALL],
    ["@media (orientation:landscape)", page(`@media (orientation:landscape){@page{margin-top:60px}}`), SMALL],
  ], G);
});
probe("page.at-page.in-layer", "@page inside @layer", async (t) => {
  await cmpAll(t, [
    ["@layer block", page(`@layer a{@page{margin-top:60px}}`), SMALL],
    ["unlayered beats layered", page(`@page{margin-top:30px} @layer a{@page{margin-top:60px}}`), SMALL],
    ["later layer wins", page(`@layer a,b; @layer b{@page{margin-top:60px}} @layer a{@page{margin-top:30px}}`), SMALL],
    ["important in a layer beats unlayered important", page(`@layer a{@page{margin-top:60px !important}} @page{margin-top:30px !important}`), SMALL],
  ], G);
});
probe("page.at-page.in-supports", "@page inside @supports", async (t) => {
  await cmpAll(t, [
    ["@supports (display:grid)", page(`@supports (display:grid){@page{margin-top:60px}}`), SMALL],
    ["@supports not matching", page(`@supports (nope:1){@page{margin-top:60px}}`), SMALL],
  ], G);
});
probe("page.at-page.margin-boxes", "page-margin boxes (@top-center ...): not drawn by takumi", async (t) => {
  await cmpAll(t, [
    ["@top-center content", page(`@page{margin-top:60px; @top-center{content:"TOPBOX"}}`), SMALL],
    ["@bottom-right counter(page)", page(`@page{@bottom-right{content:"Page " counter(page) " of " counter(pages)}}`), SMALL],
    ["descriptor after a margin box", page(`@page{@top-left{content:"X"} margin-top:60px}`), SMALL],
  ], G);
});
probe("page.at-page.no-area", "@page whose margins leave no page area keeps the options' geometry", async (t) => {
  await cmpAll(t, [
    ["margin 150px", page(`@page{margin:150px}`), SMALL],
    ["margin-top 195px (less than 1px left)", page(`@page{margin-top:189.5px}`), SMALL],
    ["margin-top 189px (exactly 1px left)", page(`@page{margin-top:189px}`), SMALL],
    [":first without area only", page(`@page :first{margin:150px}`), SMALL],
    ["size smaller than margins", page(`@page{size:15px 15px}`), SMALL],
  ], { geom: true });
});
probe("page.at-page.with-bands", "@page margins with header / footer bands (band height does not grow a CSS margin)", async (t) => {
  const band = (s) => `<div style="font:10px/30px Inter">${s}</div>`;
  await cmpAll(t, [
    ["@page margin-top 20px + 30px header", page(`@page{margin-top:20px}`), { size: { width: 300, height: 200 }, header: band("HEAD"), footer: band("FOOT") }],
    ["@page margin 0 + bands", page(`@page{margin:0}`), { size: { width: 300, height: 200 }, header: band("HEAD"), footer: band("FOOT") }],
    ["@page size + bands (band laid out at the @page width)", page(`@page{size:500px 200px}`), { size: { width: 300, height: 200 }, header: `<div style="font:10px/30px Inter;text-align:right">HEAD</div>` }],
    [":first size + bands", page(`@page :first{size:300px 120px}`), { size: { width: 300, height: 200 }, header: band("HEAD"), footer: band("FOOT") }],
  ], G);
});

// ------------------------------------------------------------------------------------------------ named pages

const named = (css, body) => doc(body, css);
const sect = (cls, from, to) => `<div class="${cls}">` + lines(from, to) + `</div>`;
probe("page.named.break-and-size", "named pages: the page property breaks the page and sizes it", async (t) => {
  await cmpAll(t, [
    ["one named section in the middle", named(`@page wide{size:300px 120px;margin:10px} .w{page:wide}`, lines(1, 3) + sect("w", 4, 12) + lines(13, 16)), SMALL],
    ["named first", named(`@page wide{size:300px 120px;margin:10px} .w{page:wide}`, sect("w", 1, 3) + lines(4, 8)), SMALL],
    ["named last", named(`@page wide{size:300px 120px;margin:10px} .w{page:wide}`, lines(1, 3) + sect("w", 4, 6)), SMALL],
    ["two names", named(`@page a{margin-top:90px} @page b{margin-bottom:90px} .a{page:a} .b{page:b}`, sect("a", 1, 8) + sect("b", 9, 16) + lines(17, 20)), SMALL],
    ["same name on adjacent siblings: no break", named(`@page a{margin-top:90px} .a{page:a}`, sect("a", 1, 2) + sect("a", 3, 4) + lines(5, 6)), SMALL],
    ["a name without an @page rule still breaks", named(`.a{page:nope}`, lines(1, 2) + sect("a", 3, 4) + lines(5, 6)), SMALL],
    ["page:auto", named(`@page a{margin-top:90px} .a{page:auto}`, lines(1, 2) + sect("a", 3, 4) + lines(5, 6)), SMALL],
    ["inline style page:", named(`@page a{margin-top:90px}`, lines(1, 2) + `<div style="page:a">` + lines(3, 4) + `</div>` + lines(5, 6)), SMALL],
    ["names are case-sensitive", named(`@page Wide{margin-top:90px} .w{page:wide}`, lines(1, 2) + sect("w", 3, 4) + lines(5, 6)), SMALL],
  ], G);
});
probe("page.named.nesting", "named pages: nested elements, first child propagation, not inherited", async (t) => {
  await cmpAll(t, [
    ["name on a nested first child propagates to the page start", named(`@page a{margin-top:90px} .a{page:a}`, `<div><div>` + sect("a", 1, 2) + `</div></div>` + lines(3, 4)), SMALL],
    ["name on a deep middle child breaks before and after", named(`@page a{margin-top:90px} .a{page:a}`, `<div>` + lines(1, 2) + `<div>` + sect("a", 3, 4) + `</div>` + lines(5, 6) + `</div>`), SMALL],
    ["child of a named box keeps the name (used value)", named(`@page a{margin-top:90px} .a{page:a}`, lines(1, 2) + `<div class="a"><div>` + lines(3, 12) + `</div></div>`), SMALL],
    ["nested different name", named(`@page a{margin-top:90px} @page b{margin-top:50px} .a{page:a} .b{page:b}`, `<div class="a">` + lines(1, 2) + sect("b", 3, 4) + lines(5, 6) + `</div>`), SMALL],
    ["name on body", named(`@page a{margin-top:90px} body{page:a}`, lines(1, 12)), SMALL],
    ["name on html", named(`@page a{margin-top:90px} html{page:a}`, lines(1, 12)), SMALL],
    ["name on a flex item", named(`@page a{margin-top:90px} .a{page:a}`, `<div style="display:flex;flex-direction:column">` + lines(1, 2) + sect("a", 3, 4) + lines(5, 6) + `</div>`), SMALL],
    ["name on a table row", named(`@page a{margin-top:90px} .a{page:a} td{padding:0;height:20px}`, `<table style="border-spacing:0"><tr><td>R01</td></tr><tr class="a"><td>R02</td></tr><tr><td>R03</td></tr></table>`), SMALL],
    ["name on a float / abspos is ignored", named(`@page a{margin-top:90px} .a{page:a}`, lines(1, 2) + `<div class="a" style="float:left">F</div>` + lines(3, 4)), SMALL],
    ["name on an inline element is ignored", named(`@page a{margin-top:90px} .a{page:a}`, lines(1, 2) + `<div class="l">x <span class="a">INL</span></div>` + lines(3, 4)), SMALL],
  ], G);
});
probe("page.named.pseudo", "named pages: name:first / name:left / name:right and specificity", async (t) => {
  await cmpAll(t, [
    ["a:first applies only when the named page is the document's first", named(`@page a:first{margin-top:90px} .a{page:a}`, sect("a", 1, 12)), SMALL],
    ["a:first does not apply to a later named page", named(`@page a:first{margin-top:90px} .a{page:a}`, lines(1, 2) + sect("a", 3, 12)), SMALL],
    ["a:left / a:right", named(`@page a:left{margin-top:90px} @page a:right{margin-top:50px} .a{page:a}`, lines(1, 2) + sect("a", 3, 30)), SMALL],
    ["name beats :first", named(`@page :first{margin-top:90px} @page a{margin-top:30px} .a{page:a}`, sect("a", 1, 12)), SMALL],
    ["unnamed rule applies to named pages too", named(`@page{margin-top:90px} @page a{margin-bottom:50px} .a{page:a}`, lines(1, 2) + sect("a", 3, 12)), SMALL],
    ["forced break + name change = one break", named(`@page a{margin-top:90px} .a{page:a;break-before:page}`, lines(1, 2) + sect("a", 3, 4) + lines(5, 6)), SMALL],
  ], G);
});
probe("page.named.width", "named pages of another width (content re-flows at the named page's width)", async (t) => {
  const words = (n) => `<div style="font:12px/20px Inter">${"word ".repeat(n)}</div>`;
  await cmpAll(t, [
    ["wider named page, wrapped text", named(`@page wide{size:500px 200px;margin:10px} .w{page:wide}`, words(30) + `<div class="w">${words(60)}</div>` + words(30)), SMALL],
    ["narrower named page, wrapped text", named(`@page nar{size:150px 200px;margin:10px} .w{page:nar}`, words(30) + `<div class="w">${words(60)}</div>` + words(30)), SMALL],
    ["wider named page, right-aligned lines", named(`@page wide{size:500px 200px;margin:10px} .w{page:wide;text-align:right}`, lines(1, 2) + sect("w", 3, 4) + lines(5, 6)), SMALL],
    ["named margins change the width", named(`@page m{margin:10px 80px} .w{page:m}`, words(30) + `<div class="w">${words(60)}</div>`), SMALL],
  ], G);
});
probe("page.named.bands-counters", "named pages with bands and counters", async (t) => {
  const footer = `<div style="font:10px/20px Inter;text-align:right">P<span class="pageNumber"></span>/<span class="totalPages"></span></div>`;
  await cmpAll(t, [
    ["footer on named pages of another size", named(`@page wide{size:400px 150px} .w{page:wide}`, lines(1, 3) + sect("w", 4, 12) + lines(13, 16)), { size: { width: 300, height: 200 }, footer }],
  ], G);
});
