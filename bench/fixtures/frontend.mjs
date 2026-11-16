// Front-end features: stylesheets/selectors (`css` option), Tailwind (`tw`), HTML string sources and
// ::before/::after generated content. Cases may carry `opts` = extra render options (e.g. `css`) that the
// harness must forward to both engines; `node` may be an HTML STRING (takumi: every JS string is HTML).
const FONT = "font-family: Inter;";

const cardCss = `
  .root { display: flex; flex-direction: column; width: 100%; height: 100%; padding: 48px; gap: 24px; background: #f8fafc; ${FONT} }
  .card { display: flex; flex-direction: column; gap: 12px; padding: 32px; border-radius: 20px; background: white; border: 2px solid #e2e8f0; }
  #hero { background: #1e293b; border-color: #0f172a; }
  #hero .title { color: #f8fafc; }
  .card .title { font-size: 40px; font-weight: 700; color: #0f172a; }
  .card > .body { font-size: 24px; color: #475569; line-height: 1.4; }
  .row .chip { padding: 6px 16px; border-radius: 9999px; background: #e0e7ff; color: #3730a3; font-size: 20px; }
  .row { display: flex; gap: 12px; }
`;

const sel = [
  {
    id: "css-class-id", feature: "css-stylesheet", title: "class, id, descendant and child selectors", width: 1200, height: 630,
    opts: { css: [cardCss] },
    node: { type: "container", className: "root", children: [
      { type: "container", className: "card", id: "hero", children: [
        { type: "text", className: "title", text: "Stylesheets in bm-render" },
        { type: "text", className: "body", text: "Selectors match className, id and descendant combinators." },
      ] },
      { type: "container", className: "card", children: [
        { type: "text", className: "title", text: "Second card" },
        { type: "container", className: "row", children: ["css", "selectors", "cascade"].map((s) => ({ type: "text", className: "chip", text: s })) },
      ] },
    ] },
  },
  {
    id: "css-nth-child", feature: "css-stylesheet", title: ":nth-child(odd/even), :first-child, :last-child, :not()", width: 800, height: 500,
    opts: { css: [`
      .list { display: flex; flex-direction: column; width: 100%; height: 100%; padding: 24px; gap: 8px; background: #fff; ${FONT} }
      .item { display: flex; padding: 12px 20px; font-size: 24px; border-radius: 8px; color: #111827; }
      .item:nth-child(odd) { background: #dbeafe; }
      .item:nth-child(even) { background: #fce7f3; }
      .item:first-child { font-weight: 700; }
      .item:last-child { border: 3px solid #111827; }
      .item:not(.muted) { color: #1d4ed8; }
      .item:nth-child(3n) { padding-left: 60px; }
    `] },
    node: { type: "container", className: "list", children: ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta"].map((s, i) => ({ type: "text", className: i === 2 ? "item muted" : "item", text: s })) },
  },
  {
    id: "css-media-layer", feature: "css-stylesheet", title: "@media width queries and @layer ordering", width: 1200, height: 400,
    opts: { css: [`
      @layer base, theme;
      @layer theme { .box { background: #16a34a; } }
      @layer base { .box { background: #dc2626; width: 200px; height: 200px; } }
      .wrap { display: flex; gap: 20px; padding: 40px; width: 100%; height: 100%; background: #f1f5f9; }
      .box { border-radius: 16px; }
      @media (min-width: 1000px) { .wide { width: 400px; background: #2563eb; } }
      @media (max-width: 600px) { .wide { background: #000; } }
      .unlayered { background: #f59e0b; }
    `] },
    node: { type: "container", className: "wrap", children: [
      { type: "container", className: "box", children: [] },
      { type: "container", className: "box wide", children: [] },
      { type: "container", className: "box unlayered", children: [] },
    ] },
  },
  {
    id: "css-important-var", feature: "css-stylesheet", title: "!important vs inline style, custom properties + var()", width: 900, height: 400,
    opts: { css: [`
      :root, .root { --accent: #7c3aed; --pad: 24px; }
      .root { display: flex; gap: 24px; padding: var(--pad); width: 100%; height: 100%; background: #fafafa; ${FONT} }
      .a { background: var(--accent); width: 200px; height: 160px; }
      .b { background-color: red !important; width: 200px; height: 160px; }
      .b2 { background: red !important; width: 200px; height: 160px; } /* takumi quirk: shorthand !important loses to inline longhand (not used) */
      .c { background: var(--missing, #0ea5e9); width: 200px; height: 160px; border: 8px solid var(--accent); }
      .t { font-size: 28px; color: var(--accent); }
    `] },
    node: { type: "container", className: "root", children: [
      { type: "container", className: "a", style: { backgroundColor: "#e11d48" }, children: [] },
      { type: "container", className: "b", style: { backgroundColor: "#22c55e" }, children: [] },
      { type: "container", className: "c", children: [] },
      { type: "text", className: "t", text: "var()" },
    ] },
  },
];

const twCases = [
  {
    id: "tw-card", feature: "tailwind", title: "Card built from Tailwind classes only", width: 1200, height: 630,
    node: { type: "container", tw: "flex flex-col w-full h-full p-16 gap-8 bg-slate-900 justify-between", children: [
      { type: "container", tw: "flex items-center gap-4", children: [
        { type: "container", tw: "w-16 h-16 rounded-full bg-gradient-to-br from-orange-400 to-pink-600", children: [] },
        { type: "text", tw: "text-3xl font-semibold text-slate-100", style: { fontFamily: "Inter" }, text: "Tailwind in bm-render" },
      ] },
      { type: "text", tw: "text-6xl font-bold text-white leading-tight tracking-tight", style: { fontFamily: "Inter" }, text: "Utility classes compiled to declarations at render time" },
      { type: "container", tw: "flex gap-3", children: ["flex", "gap", "rounded"].map((s) => ({ type: "text", tw: "px-4 py-1 rounded-full bg-sky-400/20 text-sky-300 text-xl", style: { fontFamily: "Inter" }, text: s })) },
    ] },
  },
  {
    id: "tw-responsive", feature: "tailwind", title: "Responsive variants (sm/md/lg/xl) against the viewport width", width: 1200, height: 400,
    node: { type: "container", tw: "flex flex-row w-full h-full p-8 gap-6 bg-white", children: [
      { type: "container", tw: "w-24 h-24 bg-red-500 md:bg-green-500 lg:w-64", children: [] },
      { type: "container", tw: "w-24 h-24 bg-red-500 2xl:bg-blue-500 rounded-lg sm:rounded-3xl", children: [] },
      { type: "container", tw: "w-24 h-24 bg-red-500 xl:h-48 xl:bg-purple-500", children: [] },
    ] },
  },
  {
    id: "tw-structural", feature: "tailwind", title: "first:/last:/odd:/even: variants and style > tw precedence", width: 800, height: 500,
    node: { type: "container", tw: "flex flex-col w-full h-full p-6 gap-2 bg-gray-50", children: [0, 1, 2, 3, 4].map((i) => ({
      type: "container", tw: "flex h-16 rounded-md bg-gray-300 odd:bg-amber-300 first:bg-emerald-500 last:bg-indigo-500 even:ml-8",
      style: i === 3 ? { backgroundColor: "#0f172a" } : undefined, children: [],
    })) },
  },
  {
    id: "tw-arbitrary", feature: "tailwind", title: "Arbitrary values, opacity modifiers, shadows, borders", width: 900, height: 450,
    node: { type: "container", tw: "flex w-full h-full items-center justify-center bg-[#0b1020]", children: [
      { type: "container", tw: "flex flex-col w-[520px] p-[36px] gap-4 rounded-[28px] bg-white/10 border-2 border-white/30 shadow-2xl", children: [
        { type: "text", tw: "text-[44px] font-extrabold text-[#fde68a]", style: { fontFamily: "Inter" }, text: "Arbitrary" },
        { type: "text", tw: "text-2xl text-white/70", style: { fontFamily: "Inter" }, text: "w-[520px] p-[36px] rounded-[28px]" },
      ] },
    ] },
  },
];

const htmlCases = [
  {
    id: "html-article", feature: "html", title: "HTML string with <style>, headings, paragraphs and inline spans", width: 1000, height: 600,
    node: `<style>
  .page { ${FONT} padding: 32px; background: #fff; color: #1f2937; height: 100%; }
  h1 { color: #111827; margin: 0 0 16px; }
  p { font-size: 22px; line-height: 1.5; }
  .hl { background: #fef08a; }
  strong { color: #b91c1c; }
</style>
<div class="page">
  <h1>Rendering HTML</h1>
  <p>The source is a <strong>plain string</strong> parsed in wasm, with <em>inline</em> elements and <span class="hl">highlighted text</span>.</p>
  <h2>Second heading</h2>
  <p>Presets give headings their size and margins.</p>
</div>`,
  },
  {
    id: "html-document", feature: "html", title: "Full document (doctype, body margin 8px, classes)", width: 800, height: 400,
    node: `<!doctype html><html><head><title>x</title><style>
  body { ${FONT} background: #e0f2fe; }
  .box { background: #0369a1; color: white; padding: 20px; font-size: 28px; border-radius: 12px; }
</style></head><body><div class="box">Document with body margin</div><p style="font-size:20px">Below the box.</p></body></html>`,
  },
  {
    id: "html-flex-card", feature: "html", title: "Flex card from divs with style attributes", width: 1000, height: 500,
    node: `<div style="display:flex;width:100%;height:100%;align-items:center;justify-content:center;background:linear-gradient(135deg,#1e3a8a,#9333ea);font-family:Inter">
  <div style="display:flex;flex-direction:column;gap:12px;padding:40px;border-radius:24px;background:rgba(255,255,255,0.12);border:2px solid rgba(255,255,255,0.35)">
    <div style="font-size:48px;font-weight:700;color:white">Hello from HTML</div>
    <div style="font-size:24px;color:#e9d5ff">style attributes are a lenient layer</div>
  </div>
</div>`,
  },
  {
    id: "html-inline", feature: "html", title: "Inline formatting: b/i/u/span colours, small/code presets", width: 900, height: 300,
    node: `<div style="font-family:Inter;font-size:26px;padding:24px;background:white;height:100%;line-height:1.6">Plain <b>bold</b> <i>italic</i> <u>underlined</u> <span style="color:#16a34a">green</span> <s>struck</s> and <small>small text</small>, all in one paragraph that wraps onto a second line.</div>`,
  },
];

const pseudoCss = `
  .wrap { display: flex; flex-direction: column; gap: 24px; padding: 40px; width: 100%; height: 100%; background: #fff; ${FONT} }
  .star { font-size: 32px; color: #111827; }
  .star::before { content: "\\2605  "; color: #f59e0b; }
  .star::after { content: " (new)"; color: #6b7280; font-size: 24px; }
`;

const pseudoCases = [
  {
    id: "pseudo-inline", feature: "pseudo-elements", title: "::before/::after inline text with escapes", width: 800, height: 300,
    opts: { css: [pseudoCss] },
    node: { type: "container", className: "wrap", children: [
      { type: "text", className: "star", text: "Featured item" },
      { type: "container", className: "star", children: [{ type: "text", text: "Container with text run" }] },
    ] },
  },
  {
    id: "pseudo-block", feature: "pseudo-elements", title: "Decorative ::before boxes (content: \"\", absolute / block)", width: 800, height: 400,
    opts: { css: [`
      .wrap { display: flex; gap: 32px; padding: 40px; width: 100%; height: 100%; background: #f8fafc; ${FONT} }
      .card { position: relative; display: flex; width: 300px; height: 200px; padding: 24px; padding-top: 40px; background: white; border: 2px solid #cbd5e1; border-radius: 12px; font-size: 26px; }
      .card::before { content: ""; position: absolute; top: 0; left: 0; width: 100%; height: 16px; background: #6366f1; }
      .bar { display: flex; flex-direction: column; width: 300px; font-size: 26px; }
      .bar::after { content: ""; display: block; height: 10px; width: 120px; background: #ef4444; margin-top: 12px; }
    `] },
    node: { type: "container", className: "wrap", children: [
      { type: "container", className: "card", children: [{ type: "text", text: "Top stripe" }] },
      { type: "container", className: "bar", children: [{ type: "text", text: "Underline bar" }] },
    ] },
  },
  {
    id: "pseudo-attr", feature: "pseudo-elements", title: "content: attr() and pseudo in a flex row", width: 800, height: 250,
    opts: { css: [`
      .row { display: flex; gap: 16px; align-items: center; padding: 40px; width: 100%; height: 100%; background: #111827; ${FONT} }
      .tag { display: flex; padding: 8px 18px; border-radius: 9999px; background: #374151; color: #f9fafb; font-size: 24px; }
      .tag::before { content: attr(data-icon) " "; color: #34d399; }
      .row::after { content: "end"; color: #9ca3af; font-size: 20px; }
    `] },
    node: { type: "container", className: "row", children: [
      { type: "text", className: "tag", attributes: { "data-icon": "#" }, text: "zig" },
      { type: "text", className: "tag", attributes: { "data-icon": "@" }, text: "wasm" },
    ] },
  },
  {
    id: "pseudo-tw", feature: "pseudo-elements", title: "Tailwind before:/after: variants", width: 800, height: 300,
    node: { type: "container", tw: "flex flex-col gap-6 p-10 w-full h-full bg-white", children: [
      { type: "text", tw: "text-3xl text-slate-800 before:content-['→_'] before:text-rose-500 after:content-['!'] after:text-sky-500", style: { fontFamily: "Inter" }, text: "Generated by tw" },
      { type: "container", tw: "relative flex h-24 w-96 rounded-xl bg-slate-100 before:absolute before:inset-y-0 before:left-0 before:w-3 before:bg-emerald-500", children: [] },
    ] },
  },
];

export default [...sel, ...twCases, ...htmlCases, ...pseudoCases];
