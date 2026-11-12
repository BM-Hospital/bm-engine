// Layout correctness fixtures (branch fix-layout): direction: rtl in flex / grid / table / block layout,
// block-in-inline, float paint order, text-indent, inline box edges in bidi lines, text-wrap: balance
// with inline boxes / floats. Every case is compared against takumi like the rest of the suite.
// Behaviours where takumi itself deviates from Chrome (display: contents, percentage padding / margin of
// inline boxes) are NOT here: see bench/probe/fix-layout/chrome-check.mjs.
// HTML-string `node`s are parsed by both engines.

const page = (css, body, extra = "") => `<style>
  .page { font-family: Inter; width: 100%; height: 100%; background: #fff; color: #0f172a; padding: 12px; font-size: 14px; box-sizing: border-box; ${extra} }
  p { margin: 0 0 10px; }
  .b { width: 50px; height: 24px; background: #38bdf8; }
  .b:nth-child(2) { background: #f97316; width: 70px }
  .b:nth-child(3) { background: #22c55e; width: 40px }
  ${css}
</style><div class="page">${body}</div>`;
const three = `<div class="b"></div><div class="b"></div><div class="b"></div>`;
const B = (s) => `<div class="b" style="${s}"></div>`;

// ------------------------------------------------------------------------------------------------ direction: rtl
const rtlCss = `
  .f { display: flex; direction: rtl; background: #eee; margin-bottom: 5px; }
  .g { display: grid; direction: rtl; background: #eee; margin-bottom: 5px; }
  .a { position: absolute; width: 20px; height: 14px; background: #000; }
`;
const rtl = [
  {
    id: "fix-layout-rtl-flex", feature: "rtl", title: "direction: rtl flex rows: main axis from the right, row-reverse, justify-content, margins, padding, flex-grow, relative offsets", width: 420, height: 300,
    node: page(rtlCss, `
      <div class="f" style="padding:4px 30px 4px 6px;border-left:8px solid #000;border-right:2px solid red">${three}</div>
      <div class="f" style="justify-content:center;gap:7px">${B("margin-left:20px")}${B("margin-right:13px")}${B("")}</div>
      <div class="f" style="justify-content:left">${three}</div>
      <div class="f" style="justify-content:flex-end">${three}</div>
      <div class="f" style="justify-content:start;flex-direction:row-reverse">${three}</div>
      <div class="f" style="justify-content:space-between;padding-inline-start:20px">${B("margin-inline-start:10px")}${B("")}${B("")}</div>
      <div class="f">${B("flex:1")}${B("flex:2;position:relative;left:6px;top:3px")}${B("")}</div>
      <div class="f" style="width:333px">${B("flex:1")}${B("flex:1")}${B("flex:1")}${B("flex:1")}${B("flex:1")}${B("flex:1")}${B("flex:1")}</div>
    `),
  },
  {
    id: "fix-layout-rtl-flex-wrap-abs", feature: "rtl", title: "rtl flex: wrapping, column direction (cross axis from the right), wrap-reverse, absolutely positioned children (static position, physical and logical insets)", width: 420, height: 300,
    node: page(rtlCss, `
      <div class="f" style="flex-direction:column;height:54px;flex-wrap:wrap;align-content:flex-start">${three}${three}</div>
      <div class="f" style="flex-direction:column;align-items:flex-end">${B("align-self:start")}${B("")}${B("align-self:center")}</div>
      <div class="f" style="flex-wrap:wrap-reverse;width:130px">${three}${three}</div>
      <div class="f" style="position:relative;height:36px;padding:0 10px 0 30px">${B("")}<div class="a"></div><div class="a" style="left:4px;top:20px;background:red"></div><div class="a" style="inset-inline-start:4px;top:20px;background:blue"></div></div>
      <div style="position:relative;border:3px solid #999;padding:5px 5px 5px 40px"><div class="f" style="height:36px;padding-right:25px;justify-content:center">${B("")}<div class="a"></div><div class="a" style="left:4px;top:20px;background:red"></div><div class="a" style="right:4px;top:26px;background:blue;margin-right:9px"></div></div></div>
    `),
  },
  {
    id: "fix-layout-rtl-grid-block", feature: "rtl", title: "rtl grid (column order, spans, justify-items / justify-self, auto-flow column) and rtl block containers (over-constrained children at the right, auto margins, logical margin / padding / border)", width: 420, height: 300,
    node: page(rtlCss + `.g > div { width: auto } .x { direction: rtl; background: #eee; margin-bottom: 5px }`, `
      <div class="g" style="grid-template-columns:60px 100px 1fr;gap:4px;padding:0 20px 0 4px">${three}<div class="b" style="grid-column:1 / span 2"></div>${B("justify-self:start;width:20px")}</div>
      <div class="g" style="grid-template-columns:repeat(3,70px);justify-content:end;justify-items:end">${B("width:30px")}${B("width:30px;margin-left:5px")}${B("width:30px;justify-self:left")}</div>
      <div class="g" style="grid-auto-flow:column;grid-auto-columns:40px;justify-content:space-between">${three}</div>
      <div class="x">${B("")}${B("margin-right:10px")}${B("margin-left:auto")}${B("margin:0 auto")}${B("margin-inline-start:25px")}${B("position:relative;right:5px;left:9px")}</div>
      <div class="x"><div style="padding-inline-start:30px;border-inline-start:4px solid red;background:#ddd;width:200px">logical edges</div></div>
    `),
  },
  {
    id: "fix-layout-rtl-table", feature: "rtl", title: "rtl tables: columns right to left (dir attribute and direction), colspan / rowspan, captions, column backgrounds, border-spacing, collapsed borders with per-side widths and styles", width: 420, height: 330,
    node: page(`td, th { border: 1px solid #333; padding: 3px 6px } table { margin-bottom: 8px } .c { border-collapse: collapse }`, `
      <table dir="rtl"><tr><td>one</td><td>two longer</td><td>3</td></tr><tr><td colspan="2">span</td><td>x</td></tr><tr><td rowspan="2">rs</td><td>b</td><td>c</td></tr><tr><td>e</td><td>f</td></tr></table>
      <table style="direction:rtl;width:300px;border:3px solid red;border-left-width:12px;padding:2px 2px 2px 20px;border-spacing:6px 2px"><caption>caption</caption><colgroup><col style="background:#fde047"><col span="2" style="background:#bae6fd"></colgroup><tr><th>h1</th><th>h2</th><th>h3</th></tr><tr><td style="border-left:5px solid blue">one</td><td>two longer</td><td>3</td></tr></table>
      <table class="c" dir="rtl"><tr><td>one</td><td style="border-left:6px solid red;border-right:3px dashed blue">two longer</td><td>3</td></tr><tr><td colspan="2" style="border-bottom:4px double green">span</td><td>x</td></tr></table>
      <table class="c" dir="rtl" style="border:5px solid #f97316;border-left:9px solid #22c55e;width:260px"><tr><td>a</td><td style="border:3px solid #000">b</td><td>c</td></tr><tr style="border-bottom:4px solid purple"><td rowspan="2" style="border-right:7px solid #06b6d4">d</td><td>e</td><td>f</td></tr><tr><td>g</td><td style="border-left-style:hidden">h</td></tr></table>
    `),
  },
  {
    id: "fix-layout-rtl-node-dir", feature: "rtl", title: "node `dir` field: rtl flex container with logical padding / margin and an ltr child container", width: 300, height: 100,
    node: { type: "container", dir: "rtl", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#fff", gap: 6, paddingInlineStart: 20 }, children: [
      { type: "container", style: { width: 50, height: 30, backgroundColor: "#38bdf8", marginInlineStart: 10 } },
      { type: "container", style: { width: 50, height: 30, backgroundColor: "#f97316" } },
      { type: "container", dir: "ltr", style: { display: "flex", width: 80, height: 30, backgroundColor: "#eee" }, children: [{ type: "container", style: { width: 20, height: 20, backgroundColor: "#000" } }] }] },
  },
];

// ------------------------------------------------------------------------------------------------ text-indent
const LOREM = "Layout engines place floats first and then let every line box of the surrounding text take whatever inline space is left beside them.";
const tiCss = `p { width: 300px; background: #f1f5f9; margin: 0 0 8px }`;
const indent = [
  {
    id: "fix-layout-text-indent", feature: "text-indent", title: "text-indent: length, percentage, negative (hanging punctuation idiom), with text-align center / right / justify", width: 420, height: 330,
    node: page(tiCss, `<p style="text-indent:40px">${LOREM}</p><p style="text-indent:10%">Ten percent indent here.</p><p style="text-indent:-20px;padding-left:20px">${LOREM}</p><p style="text-indent:40px;text-align:center">centered indent</p><p style="text-indent:40px;text-align:right">right indent</p><p style="text-indent:40px;text-align:justify">${LOREM}</p>`),
  },
  {
    id: "fix-layout-text-indent-keywords", feature: "text-indent", title: "text-indent: right-to-left paragraph, each-line, hanging, hanging each-line, first line beside a float", width: 420, height: 330,
    node: page(tiCss, `<p style="text-indent:40px;direction:rtl">rtl indent ${LOREM}</p><p style="text-indent:40px each-line">each<br>line<br>here</p><p style="text-indent:40px hanging">hanging ${LOREM}</p><p style="text-indent:30px"><span style="float:left;width:40px;height:30px;background:red"></span>float ${LOREM}</p><p style="text-indent:2em hanging each-line">hang each<br>line two ${LOREM}</p>`),
  },
  {
    id: "fix-layout-text-indent-sizing", feature: "text-indent", title: "text-indent in intrinsic sizes (shrink-to-fit inline-blocks, min-content), inheritance into nested blocks, with text-wrap: balance, ellipsis, a flex item", width: 420, height: 300,
    node: page(tiCss + `.s { display: inline-block; background: #fde047; margin-bottom: 6px }`, `<div><span class="s" style="text-indent:30px">shrink to fit</span></div><div><span class="s" style="text-indent:-10px;margin-left:20px">negative fit</span></div><div><span class="s" style="text-indent:30px;width:min-content">min content width words</span></div><div style="text-indent:25px;width:300px;background:#f1f5f9">first text<div style="background:#bae6fd">nested block inherits</div></div><p style="text-indent:50px;text-wrap:balance">A headline that should be balanced across its lines nicely indeed</p><p style="text-indent:50px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${LOREM}</p><p style="text-indent:20px;display:flex">flex item text <span>span</span></p>`),
  },
  {
    id: "fix-layout-text-indent-node", feature: "text-indent", title: "textIndent on text nodes (px, percentage) and inherited `hanging` through a block container", width: 420, height: 200,
    node: { type: "container", style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", backgroundColor: "#fff", padding: 12, fontFamily: "Inter", fontSize: 16 }, children: [
      { type: "text", text: "Text node with indent that wraps onto another line for sure yes.", style: { textIndent: 30, width: 300, backgroundColor: "#eee" } },
      { type: "text", text: "pct indent text node", style: { textIndent: "25%", backgroundColor: "#ddd" } },
      { type: "container", style: { display: "block", textIndent: "3em hanging", width: 200 }, children: [{ type: "text", text: "inherited hanging indent through a block container" }] }] },
  },
];

// ------------------------------------------------------------------------------------------------ inline box edges in bidi lines
const RLO = "‮", PDF = "‬", LRE = "‪";
const bxCss = `
  .s { background: #fde047; border-left: 4px solid #dc2626; border-right: 4px solid #2563eb; padding-left: 10px; padding-right: 2px; margin-left: 8px }
  .u { background: #bae6fd; border-left: 3px solid #16a34a; padding: 0 3px 0 6px }
`;
const bidiBoxes = [
  {
    id: "fix-layout-inline-rtl-box", feature: "inline-bidi", title: "direction: rtl inline boxes around left-to-right text: the left / right edges stay on their sides; first / last fragments when wrapping; nested boxes of both directions; box-decoration-break: clone", width: 420, height: 260,
    node: page(bxCss, `
      <p>ltr <span class="s" dir="rtl">box rtl dir</span> after</p>
      <p dir="rtl">in rtl <span class="s">box in rtl para</span> after</p>
      <p dir="rtl" style="width:150px">in rtl <span class="s">box in rtl para wrapping lines</span> after</p>
      <p>ltr <span class="s" dir="rtl">outer <span class="u">inner rtl</span> tail <span class="u" dir="ltr">inner ltr</span></span> after</p>
      <p style="width:170px">ltr <span class="s" dir="rtl">an rtl box wrapping over three lines of ltr text here</span> after</p>
      <p dir="rtl" style="width:170px"><span class="s" style="box-decoration-break:clone">cloned rtl box wrapping over lines</span></p>
    `),
  },
  {
    id: "fix-layout-inline-bidi-fragments", feature: "inline-bidi", title: "inline boxes in bidi-reordered lines (RLO overrides): edges at the visual ends, a box split in two fragments by reordering, an atomic inline inside, empty boxes", width: 420, height: 230,
    node: page(bxCss, `
      <p>abc ${RLO}def <span class="s">ghi jkl</span> mno${PDF} pqr</p>
      <p>abc <span class="s">in ${RLO}REV ERSED${PDF} out</span> pqr</p>
      <p>abc <span class="s">in ${RLO}REV</span> ERSED${PDF} out pqr</p>
      <p>one ${RLO}two <span class="s">three ${LRE}four five${PDF} six</span> seven${PDF} eight</p>
      <p>img ${RLO}aa <span class="s">bb <span style="display:inline-block;width:20px;height:10px;background:red"></span> cc</span> dd${PDF} ee</p>
      <p>empty <span class="s" dir="rtl"></span> box <span class="s"></span>${RLO}x<span class="s"></span>y${PDF}</p>
    `),
  },
  {
    id: "fix-layout-inline-bidi-wrap", feature: "inline-bidi", title: "bidi-reordered boxes wrapping over lines, nested and vertically shifted boxes, underline, justified right-to-left paragraph with a box", width: 420, height: 300,
    node: page(bxCss + `p { width: 200px; background: #f1f5f9 }`, `
      <p>abc ${RLO}def <span class="s">ghi jkl mno pqr stu vwx</span> yz${PDF} end of it</p>
      <p dir="rtl">abc <span class="s">${RLO}reversed box text wrapping${PDF} then ltr words wrap</span> end</p>
      <p>x ${RLO}<span class="s">a <span class="u">b c</span> d</span> e <span class="u" style="vertical-align:super;font-size:10px">sup</span>${PDF} y</p>
      <p style="text-align:right">r ${RLO}<span class="s" style="text-decoration:underline">under line</span>${PDF} z</p>
      <p style="text-align:justify" dir="rtl">just <span class="s">ify these words in a right to left paragraph</span> with a box inside it ok</p>
    `),
  },
];

// ------------------------------------------------------------------------------------------------ text-wrap: balance / pretty with inline content
const balCss = `
  p { width: 300px; background: #f1f5f9; text-wrap: balance; margin: 0 0 7px }
  .h { background: #fde047; padding: 0 6px; border: 1px solid #ca8a04 }
  .ib { display: inline-block; width: 30px; height: 12px; background: #ef4444 }
`;
const balance = [
  {
    id: "fix-layout-balance-inline-boxes", feature: "text-wrap-balance", title: "text-wrap: balance in paragraphs with inline boxes (padding / border, larger font, background, sup, nowrap span), centred, cloned decorations (bisection)", width: 330, height: 330,
    node: page(balCss, `
      <p>A headline <span class="h">that should</span> be balanced across its lines nicely</p>
      <p>A headline <span style="font-size:20px">that should</span> be balanced across its lines nicely</p>
      <p>A headline <span style="background:#fde047">that should be balanced</span> across its lines nicely</p>
      <p>A headline<sup style="background:#fde047">sup</sup> that should be balanced across its lines nicely</p>
      <p>A headline <span class="h" style="white-space:nowrap">that should not</span> be balanced across its lines nicely</p>
      <p style="text-align:center">A headline <span class="h">that should</span> be balanced across its lines nicely</p>
      <p>A headline <span class="h" style="box-decoration-break:clone">that should be balanced across</span> its lines nicely</p>
    `),
  },
  {
    id: "fix-layout-balance-atomic", feature: "text-wrap-balance", title: "text-wrap: balance / pretty with inline-blocks, an absolutely positioned box, forced breaks, six lines", width: 330, height: 330,
    node: page(balCss, `
      <p>With an <span class="ib"></span> inline-block in the balanced paragraph text here</p>
      <p>Inline-block at the end of the balanced paragraph text <span class="ib"></span></p>
      <p>Balanced <span style="display:inline-block;background:#bae6fd;padding:0 4px">inline block</span> with text inside the paragraph that wraps twice or more times ok</p>
      <p style="position:relative">A headline <span style="position:absolute;right:0;top:0;width:10px;height:10px;background:red"></span>that should be balanced across its lines nicely</p>
      <p>A headline <span class="h">that</span> should be balanced<br>across its lines nicely and more words to wrap again</p>
      <p style="text-wrap:pretty">A headline <span class="h">that should</span> be balanced across its lines very nicely ok</p>
      <p style="width:150px">A headline <span class="h">that should</span> be balanced across its lines nicely and it goes on for many lines here</p>
    `),
  },
  {
    id: "fix-layout-balance-floats", feature: "text-wrap-balance", title: "text-wrap: balance beside floats: a leading float in the paragraph (two line widths), a sibling float, a float inside the text (not balanced), a float shorter than the first line", width: 330, height: 300,
    node: page(balCss, `
      <p><span style="float:left;width:60px;height:50px;background:#38bdf8"></span>A headline that should be balanced across its lines nicely beside a float ok</p>
      <p><span style="float:left;width:60px;height:14px;background:#38bdf8"></span>A headline that should be balanced across its lines nicely beside a float ok</p>
      <p>A headline that should <span style="float:right;width:60px;height:30px;background:#38bdf8"></span>be balanced across its lines nicely beside a float ok</p>
      <div style="width:300px"><div style="float:left;width:80px;height:40px;background:#38bdf8"></div><p style="width:auto">A headline that should be balanced across its lines nicely beside a sibling float ok</p></div>
    `),
  },
];

// ------------------------------------------------------------------------------------------------ block-in-inline
const biiCss = `
  .s { background: #fde047; border: 2px solid #dc2626; padding: 0 6px }
  .u { background: #bbf7d0; border-bottom: 2px solid #16a34a; margin: 0 4px }
  .d { background: #bae6fd }
`;
const blockInInline = [
  {
    id: "fix-layout-block-in-inline", feature: "block-in-inline", title: "a block inside an inline box splits it (CSS 2.1 9.2.1.1): first part without end edge, the block at the container's width, last part without start edge; block first; a paragraph inside <b>", width: 400, height: 250,
    node: page(biiCss, `
      <div>before <span class="s">inside start <div class="d">block child</div> inside end</span> after</div>
      <div style="margin-top:8px">before <span class="s"><div class="d">block first</div>tail</span> after <b style="color:red">bold <p>para in b</p> more</b></div>
    `),
  },
  {
    id: "fix-layout-block-in-inline-nested", feature: "block-in-inline", title: "block-in-inline through nested inline boxes, adjacent blocks, margins, wrapping text after the split; a span holding only a block; float and flex blocks inside a span", width: 400, height: 330,
    node: page(biiCss, `
      <div style="width:260px">text <span class="s">outer <span class="u">inner one <div class="d" style="margin:6px 0;padding:4px">deep block with margin</div> inner two</span> outer end <div class="d">second block</div><div class="d">third adjacent</div></span> tail text that wraps onto another line here</div>
      <div style="margin-top:8px"><span class="s"><div class="d">only a block</div></span></div>
      <div style="margin-top:6px"><span><div class="d">no-edge span, block</div>after</span></div>
      <div style="margin-top:6px">a <span class="s">x<div class="d" style="float:left;width:30px;height:20px"></div><div class="d" style="display:flex;gap:4px"><i>flex</i><i>block</i></div>y</span> z</div>
    `),
  },
  {
    id: "fix-layout-block-in-inline-align", feature: "block-in-inline", title: "block-in-inline with text-align: center, sized / auto-margin blocks, a right-to-left container, box-decoration-break: clone, a link holding a block", width: 400, height: 300,
    node: page(biiCss, `
      <div style="text-align:center;width:300px;background:#f1f5f9">centered <span class="s">start <div class="d" style="width:120px">w120</div><div class="d" style="width:120px;margin-left:auto">auto ml</div> end</span> tail</div>
      <div dir="rtl" style="width:300px;margin-top:6px">rtl <span class="s" style="border-left-width:6px">start <div class="d">block</div> end</span> tail</div>
      <div style="width:300px;margin-top:6px">a <span class="s" style="box-decoration-break:clone">clone <div class="d">block</div> end</span> b <a style="color:blue;text-decoration:underline">link <div class="d">div in a</div> text</a></div>
    `),
  },
  {
    id: "fix-layout-block-in-inline-node", feature: "block-in-inline", title: "node tree: an inline container (no display) with padding / background holding a flex container: the inline box is split, its fragments decorated", width: 400, height: 130,
    node: { type: "container", style: { display: "block", width: "100%", height: "100%", backgroundColor: "#fff", fontFamily: "Inter", fontSize: 16, padding: 10 }, children: [
      { type: "text", text: "start " },
      { type: "container", style: { backgroundColor: "#fde047", padding: 4 }, children: [{ type: "text", text: "inline container " }, { type: "container", style: { display: "flex", backgroundColor: "#bae6fd", height: 24, gap: 4 }, children: [{ type: "container", style: { width: 30, backgroundColor: "#0f172a" } }, { type: "text", text: "flex child" }] }, { type: "text", text: " tail" }] },
      { type: "text", text: " end" }] },
  },
];

// ------------------------------------------------------------------------------------------------ float paint order
const fpCss = `.fl { float: left; width: 80px; height: 40px; background: rgba(56,189,248,.85); margin-right: -30px } .w { width: 260px; margin-bottom: 8px }`;
const floatPaint = [
  {
    id: "fix-layout-float-paint-text", feature: "float-paint-order", title: "floats paint above in-flow block backgrounds and below inline content (CSS 2.1 appendix E): negative margins pulling text over a float, a float between blocks", width: 300, height: 190,
    node: page(fpCss, `
      <div class="w"><div class="fl"></div><div style="background:#fde047">text over float with negative margin so the words overlap the float box here</div></div>
      <div class="w"><div style="background:#fde047">first block</div><div class="fl" style="margin-top:-10px"></div><div style="background:#bbf7d0;margin-top:4px">second block text overlapping the float box, more words</div><div style="background:#fecaca">third block under</div></div>
    `),
  },
  {
    id: "fix-layout-float-paint-layers", feature: "float-paint-order", title: "float paint order against the other layers: positioned block and opacity group above floats, inline box backgrounds and atomic inlines above, a BFC block's background below; overlapping floats in tree order", width: 300, height: 250,
    node: page(fpCss, `
      <div class="w"><div class="fl"></div><div style="background:#fde047;position:relative">positioned block text overlaps float</div><div style="background:#bbf7d0"><span style="background:#f97316">inline bg</span> and <span style="display:inline-block;background:#a855f7;width:30px;height:12px"></span> atomic</div></div>
      <div class="w"><div class="fl"><div style="background:#fff;margin:5px">block in float</div></div><div style="background:#fde047;opacity:0.9">opacity block text overlapping</div><div style="overflow:hidden;background:#bbf7d0;height:20px">bfc block avoids</div></div>
      <div class="w" style="height:70px"><div class="fl" style="margin-right:0"></div><div class="fl" style="margin:10px 0 0 -40px;background:rgba(249,115,22,.85)"></div><div style="background:#fde047;height:30px;margin-top:20px"></div><div class="fl" style="margin-top:-20px;background:rgba(34,197,94,.85);float:right"></div></div>
    `),
  },
  {
    id: "fix-layout-float-paint-nested", feature: "float-paint-order", title: "floats inside atomic boxes paint with their box: a float in an inline-block under that inline-block's text, floats in flex items, a float with an absolutely positioned child, an absolute box in a paragraph above the block after it", width: 300, height: 260,
    node: page(fpCss, `
      <div class="w">before <div style="display:inline-block;background:#e2e8f0;width:200px"><span class="fl" style="height:30px"></span>inline-block text overlapping its own float child here</div> after</div>
      <div class="w" style="display:flex;gap:6px"><div style="width:120px;background:#fde047"><div class="fl" style="width:50px;height:30px"></div>item text over its float</div><div style="width:120px;background:#bbf7d0;margin-left:-40px">second item covers the first</div></div>
      <div class="w" style="position:relative;height:40px;background:#f1f5f9"><div class="fl" style="position:static"><div style="position:absolute;right:4px;top:4px;width:30px;height:12px;background:#dc2626"></div></div>x<div style="position:absolute;width:20px;height:14px;background:#000;left:60px;top:8px"></div><div style="width:120px;height:24px;background:#f97316;margin-left:40px"></div></div>
    `),
  },
];

export default [rtl, indent, bidiBoxes, balance, blockInInline, floatPaint].flat();
