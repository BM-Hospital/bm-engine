// Examples for docs/{en,vi}/image/html-and-tailwind.md. Run: node docs/examples/run-all.mjs html-and-tailwind
import { saver, expectThrow } from "./_lib.mjs";
import assert from "node:assert/strict";
const save = saver("html-and-tailwind");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render/standard"; // HTML and Tailwind need standard or full

const renderer = new Renderer();
renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Italic.ttf"));
// #endregion

// #region article
const html = `
<style>
  .post { font-family: Inter; padding: 20px 28px; background: #fff; color: #1f2937; height: 100%; }
  .post h1 { margin: 0 0 6px; font-size: 30px; }
  .meta { color: #6b7280; font-size: 14px; }
  .post p { font-size: 16px; line-height: 1.5; margin: 10px 0; }
  mark { background: #fef08a; }
</style>
<article class="post">
  <h1>Rendering HTML</h1>
  <div class="meta">5&nbsp;min read &middot; 2026</div>
  <p>The source is a <strong>plain string</strong> with <em>inline</em> elements,
     <mark>highlighted text</mark> and <code>code</code>.</p>
  <p>Line one<br>line two &mdash; entities such as &amp;, &lt; and &copy; are decoded.</p>
</article>`;
const articlePng = renderer.renderSync(html, { width: 560, height: 230 });
// #endregion
save("article", articlePng);

// #region ua-styles
// No stylesheet at all: the Chromium user-agent defaults give headings, paragraphs and lists their look
const uaPng = renderer.renderSync(`
  <div style="font-family: Inter; padding: 0 16px; background: white; height: 100%">
    <h2>Heading 2</h2>
    <p>A paragraph with <b>bold</b>, <i>italic</i>, <u>underline</u>, <s>strike</s> and <small>small</small> text.</p>
    <ul><li>first item</li><li>second item</li></ul>
    <blockquote>blockquote</blockquote>
  </div>`, { width: 560, height: 280 });
// #endregion
save("ua-styles", uaPng);

// #region document-mode
const firstBox = (source) => renderer.measureSync(source, { width: 400, height: 300 }).children[0];
firstBox("<div><div style='height:10px'></div></div>").transform; // [1,0,0,1,0,0] – a fragment: no body margin
firstBox("<html><body><div style='height:10px'></div></body></html>").transform; // [1,0,0,1,8,8] – body has an 8px margin
// #endregion
assert.deepEqual(firstBox("<div><div style='height:10px'></div></div>").transform, [1, 0, 0, 1, 0, 0]);
assert.deepEqual(firstBox("<html><body><div style='height:10px'></div></body></html>").transform, [1, 0, 0, 1, 8, 8]);

// #region images-svg
const logo = readFileSync("docs/public/favicon.svg"); // any PNG / JPEG / WebP / GIF / SVG bytes
const imgPng = renderer.renderSync(`
  <div style="display:flex; align-items:center; gap:20px; padding:20px; background:#0f172a; height:100%">
    <img src="logo.svg" width="64" height="64">
    <svg width="64" height="64" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" fill="#f472b6"/></svg>
    <img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'%3E%3Crect width='10' height='10' rx='2' fill='%2338bdf8'/%3E%3C/svg%3E" width="64" height="64">
    <img src="https://example.com/never-fetched.png" width="64" height="64" style="background:#334155">
  </div>`, {
  width: 400,
  height: 104,
  images: [{ src: "logo.svg", data: logo }], // <img src> is a lookup key into `images`
});
// #endregion
save("images", imgPng);

// #region ignored
// <script>, <head> content, comments and the hidden attribute
const ignoredPng = renderer.renderSync(`
  <html><head><title>not drawn</title><style>p { color: #059669 }</style></head>
  <body style="margin:0; font-family:Inter; padding: 12px; background:white">
    <script>document.body.innerHTML = "never runs"</script>
    <!-- a comment -->
    <p style="margin:0">Body content is drawn.</p>
    <p hidden style="margin:0">hidden attribute: still drawn in 0.1.0</p>
  </body></html>`, { width: 400, height: 70 });
// #endregion
save("ignored", ignoredPng);

// #region tw-node
const twPng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col justify-between w-full h-full p-6 bg-linear-to-br from-indigo-600 to-fuchsia-600",
  style: { fontFamily: "Inter" },
  children: [
    { type: "text", tw: "text-sm font-bold uppercase tracking-widest text-white/70", text: "Tailwind on nodes" },
    { type: "text", tw: "text-3xl font-bold text-white leading-tight", text: "Utility classes compiled at render time" },
    {
      type: "container",
      tw: "flex gap-2",
      children: ["flex", "p-6", "bg-linear-to-br", "text-white/70"].map((c) => ({
        type: "text", tw: "px-3 py-1 rounded-full bg-white/20 text-white text-xs", text: c,
      })),
    },
  ],
}, { width: 560, height: 200 });
// #endregion
save("tw-node", twPng);

// #region tw-html
// In HTML the attribute is tw="..."; class="..." only feeds stylesheet selectors
const twHtmlPng = renderer.renderSync(`
  <div tw="flex items-center gap-4 w-full h-full px-6 bg-emerald-50" style="font-family: Inter">
    <div tw="w-12 h-12 rounded-xl bg-emerald-500"></div>
    <div tw="flex flex-col">
      <span tw="text-xl font-bold text-emerald-900">tw attribute</span>
      <span class="text-xl text-red-600">class attribute: not Tailwind</span>
    </div>
  </div>`, { width: 460, height: 100 });
// #endregion
save("tw-html", twHtmlPng);

// #region variants
const rows = ["Plan", "Seats", "Total", "Due"];
const variantsPng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col w-full h-full p-4 bg-white",
  style: { fontFamily: "Inter" },
  children: [
    {
      type: "text",
      tw: "text-lg font-bold mb-2 after:content-['NEW'] after:ml-2 after:px-2 after:rounded after:bg-amber-300 after:text-xs",
      text: "Structural variants",
    },
    {
      type: "container",
      tw: "flex flex-col",
      // structural variants: use container rows (or a tagName): a bare text node is not an element for them
      children: rows.map((r) => ({
        type: "container",
        tw: "flex px-3 py-1 text-sm bg-slate-100 odd:bg-sky-100 first:rounded-t-lg last:rounded-b-lg last:font-bold",
        children: [{ type: "text", text: r }],
      })),
    },
  ],
}, { width: 400, height: 190 });
// #endregion
save("variants", variantsPng);

// #region breakpoints
const responsive = { type: "container", tw: "block h-2 w-10 sm:w-20 md:w-40" };
renderer.measureSync(responsive, { width: 600, height: 10 }).width; // 40  – sm (≥ 640px) does not match a 600px canvas…
renderer.measureSync(responsive, { width: 700, height: 10 }).width; // 80  – …sm matches at 700px
renderer.measureSync(responsive, { width: 800, height: 10 }).width; // 160 – md (≥ 768px)
// #endregion
assert.equal(renderer.measureSync(responsive, { width: 600, height: 10 }).width, 40);
assert.equal(renderer.measureSync(responsive, { width: 700, height: 10 }).width, 80);
assert.equal(renderer.measureSync(responsive, { width: 800, height: 10 }).width, 160);

// #region arbitrary
const arbitraryPng = renderer.renderSync({
  type: "container",
  tw: "flex items-center justify-center w-full h-full bg-[#0b1020]",
  children: [{
    type: "text",
    tw: "px-[18px] py-[6px] rounded-[10px] border-2 border-[rgb(250_204_21)] text-[26px] text-[#facc15] tracking-[0.2em]",
    style: { fontFamily: "Inter" },
    text: "ARBITRARY",
  }],
}, { width: 400, height: 90 });
// #endregion
save("arbitrary", arbitraryPng);

// #region conflicts
const w = (tw, style) => renderer.measureSync({ type: "container", tw, style }, { width: 400, height: 50 });
w("block pt-2 p-4").height; // 24 – pt-2 (8) + bottom p-4 (16): the side-specific utility wins…
w("block p-4 pt-2").height; // 24 – …whatever the class order
w("block w-20 h-1", { width: 40 }).width;  // 40 – inline style beats tw
w("block !w-20 h-1", { width: 40 }).width; // 80 – unless the utility is !important
// #endregion
assert.equal(w("block pt-2 p-4").height, 24);
assert.equal(w("block p-4 pt-2").height, 24);
assert.equal(w("block w-20 h-1", { width: 40 }).width, 40);
assert.equal(w("block !w-20 h-1", { width: 40 }).width, 80);

// #region preflight
const page = `<div style="font-family: Inter; background: white; height: 100%; padding: 0 12px"><h1>Heading</h1><p>Paragraph</p></div>`;
const withoutPreflight = renderer.renderSync(page, { width: 280, height: 160 });
const withPreflight = renderer.renderSync(page, { width: 280, height: 160, css: ['@import "tailwindcss";'] });
// #endregion
save("preflight-off", withoutPreflight);
save("preflight-on", withPreflight);

// #region theme
// @theme variables feed the utilities (bg-brand-500, bg-brand-500/15, rounded-card, text-hero,
// font-display, ...) and are also custom properties on :root, so var() can read them.
const theme = `@theme {
  --color-brand-500: #7c3aed;
  --radius-card: 14px;
  --text-hero: 28px;
  --text-hero--line-height: 34px;
  --font-display: Inter;
}`;
const themePng = renderer.renderSync({
  type: "container",
  tw: "flex flex-col items-center justify-center gap-2 w-full h-full bg-brand-500/15 font-display",
  children: [
    { type: "text", text: "@theme → utilities", tw: "text-hero font-bold text-brand-500" },
    { type: "container", tw: "flex px-4 py-1 rounded-card bg-brand-500",
      children: [{ type: "text", text: "rounded-card bg-brand-500", tw: "text-sm text-white" }] },
    { type: "text", text: "var(--color-brand-500) in a style", tw: "text-sm", style: { color: "var(--color-brand-500)" } },
  ],
}, { width: 340, height: 140, css: [theme] });
// #endregion
save("theme", themePng);

// #region tw-gaps
const px = (tw, css) => {
  const raw = renderer.renderSync({ type: "container", tw: `block w-4 h-4 ${tw}` }, { width: 16, height: 16, format: "raw", css });
  return raw[3] === 0 ? "transparent" : "painted";
};
px("bg-red-500");                                          // painted
px("bg-linear-to-r from-red-500 to-blue-500");             // painted
px("bg-gradient-to-r from-red-500 to-blue-500");           // transparent – Tailwind v3 name, not supported
px("bg-brand-500", ["@theme { --color-brand-500: red }"]);  // painted – utilities read @theme variables
px("bg-[var(--brand)]", [":root { --brand: red }"]);        // transparent – var() inside [...] is not supported
px("bg-(--brand)", [":root { --brand: red }"]);             // transparent – nor the (--var) shorthand
px("hover:bg-red-500");                                    // transparent – hover / focus / dark never apply
// #endregion
assert.equal(px("bg-red-500"), "painted");
assert.equal(px("bg-linear-to-r from-red-500 to-blue-500"), "painted");
assert.equal(px("bg-gradient-to-r from-red-500 to-blue-500"), "transparent");
assert.equal(px("bg-brand-500", ["@theme { --color-brand-500: red }"]), "painted");
assert.equal(px("bg-(--brand)", [":root { --brand: red }"]), "transparent");
assert.equal(px("bg-[var(--brand)]", [":root { --brand: red }"]), "transparent");
assert.equal(px("hover:bg-red-500"), "transparent");

// #region core-errors
import { Renderer as CoreRenderer } from "bm-render/core";
const core = new CoreRenderer();
expectThrow(() => core.renderSync("<div></div>", { width: 10, height: 10 }));
// "bm-render: this build has no HTML input support (use the standard / full build)"
expectThrow(() => core.renderSync({ type: "container", tw: "flex" }, { width: 10, height: 10 }));
// "bm-render: Tailwind (`tw`) is not supported by this build"
// #endregion
console.log(expectThrow(() => core.renderSync("<div></div>", { width: 10, height: 10 })));
console.log(expectThrow(() => core.renderSync({ type: "container", tw: "flex" }, { width: 10, height: 10 })));
