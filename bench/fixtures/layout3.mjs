// Phase 3 layout features: text flowing around floats (per-line exclusions), real inline formatting with
// atomic inlines in the middle of lines (inline-block / inline-flex / images, vertical-align) and the inline
// box model of spans (horizontal padding / border / margin, nowrap, sub / super, own line-height).
// HTML-string `node`s are parsed by both engines; `opts` are forwarded.
import { asset } from "./_h.mjs";

const FONT = "font-family: Inter;";
const imgs = () => [
  { src: "img://avatar", data: asset("avatar.png") }, // 400x400 PNG
  { src: "img://icon", data: asset("icon.png") }, // 128x128 PNG
];

const page = (css, body, extra = "") => `<style>
  .page { ${FONT} width: 100%; height: 100%; background: #fff; color: #0f172a; padding: 24px; font-size: 16px; ${extra} }
  p { margin: 0 0 12px; }
  ${css}
</style><div class="page">${body}</div>`;

const LOREM = "Layout engines place floats first and then let every line box of the surrounding text take whatever inline space is left beside them, so the first lines are short and the lines below the float use the full width again.";
const LOREM2 = "A second paragraph follows the first one. It starts beside the float when the float is taller than the first paragraph, and it widens once the float ends.";

// ------------------------------------------------------------------------------------------------ floats + text
const floatCss = `
  .f { width: 120px; height: 70px; background: #38bdf8; border-radius: 8px; }
  .l { float: left; margin: 0 14px 6px 0; }
  .r { float: right; margin: 0 0 6px 14px; }
  .box { width: 460px; }
`;
const floats = [
  {
    id: "layout3-float-left", feature: "float-text", title: "paragraph wrapping around a left float, lines re-widen below it", width: 520, height: 260,
    node: page(floatCss, `<div class="box"><div class="f l"></div>${LOREM}</div>`),
  },
  {
    id: "layout3-float-right", feature: "float-text", title: "paragraph wrapping around a right float (justified text)", width: 520, height: 260,
    node: page(floatCss + `.box { text-align: justify; }`, `<div class="box"><div class="f r"></div>${LOREM}</div>`),
  },
  {
    id: "layout3-float-stacked", feature: "float-text", title: "two stacked left floats of different sizes and a right float: three different line widths", width: 560, height: 300,
    node: page(floatCss + `
      .a { float: left; width: 70px; height: 34px; background: #f97316; margin-right: 10px; }
      .b { float: left; clear: left; width: 150px; height: 44px; background: #a855f7; margin: 6px 10px 0 0; }
      .c { float: right; width: 90px; height: 110px; background: #22c55e; margin-left: 10px; }
      .box { width: 500px; line-height: 22px; }
    `, `<div class="box"><div class="a"></div><div class="b"></div><div class="c"></div>${LOREM} ${LOREM2}</div>`),
  },
  {
    id: "layout3-float-tall", feature: "float-text", title: "float taller than its paragraph: the next paragraphs continue beside it; clear moves below", width: 560, height: 330,
    node: page(floatCss + `
      .tall { float: left; width: 110px; height: 150px; background: #fbbf24; margin-right: 16px; }
      .box { width: 500px; }
      .note { clear: both; background: #e2e8f0; padding: 6px 10px; }
    `, `<div class="box"><div class="tall"></div><p>Short first paragraph beside the float.</p><p style="background:#f1f5f9;padding:4px 6px">${LOREM2}</p><p>${LOREM}</p><p class="note">A cleared block starts below every float.</p></div>`),
  },
  {
    id: "layout3-float-in-text", feature: "float-text", title: "floats declared inside the paragraph text: beside the line when they fit, else below it", width: 560, height: 300,
    node: page(floatCss + `
      .box { width: 500px; }
      .i { float: right; width: 90px; height: 50px; background: #f472b6; margin-left: 10px; }
      .w { float: left; width: 330px; height: 30px; background: #94a3b8; margin: 4px 10px 4px 0; }
    `, `<div class="box">The first float occurs after a few words <span class="i"></span>and still fits on the first line, so that line and the next ones are shortened on the right. A second, wide float <span class="w"></span>comes when the current line is nearly full: it is placed below that line and the following lines flow around it on the other side until it ends, after which the text has the full width again.</div>`),
  },
  {
    id: "layout3-float-rtl", feature: "float-text", title: "right-to-left paragraph and a centred paragraph beside floats", width: 560, height: 300,
    node: page(floatCss + `.box { width: 500px; } .rtl { direction: rtl; } .c { text-align: center; }`,
      `<div class="box"><div class="f l"></div><p class="rtl">${LOREM}</p><div class="f r" style="background:#fb7185"></div><p class="c">${LOREM2} ${LOREM2}</p></div>`),
  },
  {
    id: "layout3-float-inline-box", feature: "float-text", title: "a line with a tall inline-block beside stacked floats takes the range free over its whole height", width: 560, height: 280,
    node: page(floatCss + `
      .a { float: left; width: 120px; height: 24px; background: #f97316; }
      .b { float: left; clear: left; width: 300px; height: 40px; background: #a855f7; }
      .t { display: inline-block; width: 26px; height: 52px; background: #0ea5e9; }
      .box { width: 500px; }
    `, `<div class="box"><div class="a"></div><div class="b"></div>ab <span class="t"></span> ${LOREM}</div>`),
  },
];

// ------------------------------------------------------------------------------------------------ inline flow
const inlineCss = `
  .badge { display: inline-block; padding: 2px 9px; border-radius: 10px; background: #dbeafe; color: #1d4ed8; font-size: 13px; font-weight: 700; }
  .warn { background: #fef3c7; color: #b45309; border: 1px solid #f59e0b; }
  .box { width: 470px; line-height: 26px; }
`;
const inlineFlow = [
  {
    id: "layout3-inline-badges", feature: "inline-flow", title: "inline-block badges inside a long sentence that wraps several times", width: 520, height: 260,
    node: page(inlineCss, `<div class="box">Releases are tagged <span class="badge">stable</span> once the test suite passes, <span class="badge warn">beta</span> while a feature is still behind a flag, and <span class="badge" style="background:#dcfce7;color:#15803d">long-term support</span> for the versions that keep receiving fixes;<span class="badge warn">no space before</span>and after a badge the line may break as well.</div>`),
  },
  {
    id: "layout3-inline-image", feature: "inline-flow", title: "inline images mid-sentence with vertical-align: baseline / middle / top / bottom / text-top / text-bottom / length", width: 560, height: 280, images: imgs(),
    node: page(`.box { width: 510px; } img { width: 28px; height: 28px; }`,
      `<div class="box">Baseline <img src="img://icon"> then middle <img src="img://icon" style="vertical-align:middle"> then top <img src="img://icon" style="vertical-align:top"> and bottom <img src="img://icon" style="vertical-align:bottom"> on one line; text-top <img src="img://icon" style="vertical-align:text-top"> text-bottom <img src="img://icon" style="vertical-align:text-bottom"> raised by 8px <img src="img://icon" style="vertical-align:8px;width:18px;height:18px"> lowered <img src="img://avatar" style="vertical-align:-10px;width:40px;height:40px;border-radius:20px"> and a span around an image <span style="background:#fde68a;padding:0 6px"><img src="img://icon" style="width:20px;height:20px"></span> stays inline.</div>`),
  },
  {
    id: "layout3-inline-flex-chip", feature: "inline-flow", title: "inline-flex chips (icon + label) in the middle of lines, an inline-block with wrapped text on the baseline of its last line", width: 560, height: 280, images: imgs(),
    node: page(`
      .box { width: 500px; line-height: 30px; }
      .chip { display: inline-flex; align-items: center; gap: 6px; padding: 3px 10px 3px 4px; border-radius: 14px; background: #f1f5f9; border: 1px solid #cbd5e1; font-size: 14px; line-height: 18px; vertical-align: middle; }
      .chip img { width: 20px; height: 20px; border-radius: 10px; }
      .note { display: inline-block; width: 110px; padding: 4px; background: #fee2e2; font-size: 12px; line-height: 15px; }
    `, `<div class="box">Assigned to <span class="chip"><img src="img://avatar">Ada Lovelace</span> and reviewed by <span class="chip"><img src="img://avatar">Grace Hopper</span> before the merge window closes; the box <span class="note">with three short lines of text</span> sits on its last line, and <span class="chip" style="vertical-align:baseline"><img src="img://icon">baseline chip</span> ends the paragraph.</div>`),
  },
  {
    id: "layout3-inline-br", feature: "inline-flow", title: "<br> in mixed inline content, empty lines, inline-blocks before and after forced breaks", width: 520, height: 260,
    node: page(inlineCss + `.sq { display: inline-block; width: 18px; height: 18px; background: #f43f5e; }`,
      `<div class="box" style="line-height:normal">first line <span class="sq"></span> with a box<br><span class="sq"></span> second line starts with one<br><b>bold <span class="badge">badge</span><br>inside the bold span</b><br><br>after an empty line <span class="sq" style="vertical-align:middle"></span><br><span class="sq"></span></div>`),
  },
  {
    id: "layout3-inline-abs", feature: "inline-flow", title: "absolutely positioned boxes inside inline content take their static position at the point of occurrence", width: 520, height: 220,
    node: page(`.box { width: 470px; position: relative; } .dot { position: absolute; width: 10px; height: 10px; background: #ef4444; border-radius: 5px; }`,
      `<div class="box">Markers sit where they occur <span class="dot"></span> in the text without taking space, also after the line has wrapped <span class="dot" style="background:#3b82f6"></span> and at the very end of the paragraph, where a block-level one goes below the line<div class="dot" style="background:#22c55e"></div></div>`),
  },
];

// ------------------------------------------------------------------------------------------------ inline box model
const boxModel = [
  {
    id: "layout3-span-edges", feature: "inline-box-model", title: "nested spans with padding / border / margin wrapping across lines (first / last fragment edges)", width: 520, height: 260,
    node: page(`
      .box { width: 460px; line-height: 30px; }
      .o { background: #fef9c3; border: 2px solid #eab308; padding: 0 10px; margin: 0 6px; border-radius: 6px; }
      .i { background: #bfdbfe; border-left: 4px solid #2563eb; border-right: 4px solid #2563eb; padding: 2px 6px; margin: 0 4px; }
      .e { padding: 0 12px; background: #fecaca; }
    `, `<div class="box">Text before <span class="o">an outer span whose text is long enough to wrap onto <span class="i">an inner span that wraps as well and ends</span> right before the outer one closes</span> and text after it; an empty span<span class="e"></span>still takes its padding.</div>`),
  },
  {
    id: "layout3-span-nowrap", feature: "inline-box-model", title: "white-space: nowrap spans at line ends move to the next line as a whole; <code> chips with padding", width: 520, height: 240,
    node: page(`
      .box { width: 430px; }
      .nw { white-space: nowrap; background: #e0e7ff; padding: 0 5px; border-radius: 4px; }
      code { font-family: Inter; font-size: 14px; background: #f1f5f9; border: 1px solid #cbd5e1; padding: 1px 5px; border-radius: 4px; white-space: nowrap; }
    `, `<div class="box">Keyboard shortcuts such as <span class="nw">Ctrl + Shift + P</span> or <span class="nw">Cmd + Option + Left Arrow</span> must never be split, the same goes for inline code like <code>zig build -Doptimize=small</code> and <code>node scripts/build.mjs --profile=core</code>, while the text around them wraps normally.</div>`),
  },
  {
    id: "layout3-span-valign", feature: "inline-box-model", title: "sub / super, vertical-align lengths and keywords on spans, spans with their own font size and line-height", width: 560, height: 280,
    node: page(`.box { width: 510px; } .k { background: #e2e8f0; }`,
      `<div class="box"><p>E = mc<sup>2</sup>, H<sub>2</sub>O and x<sub>i</sub><sup>n</sup>; <span class="k" style="vertical-align:8px">raised 8px</span> <span class="k" style="vertical-align:-6px">lowered 6px</span> <span class="k" style="vertical-align:50%">50%</span> baseline.</p>
      <p style="line-height:1.5">Line-height 1.5 with a <span style="font-size:30px">larger span</span> that grows its line box, and a <span class="k" style="line-height:44px">span with its own 44px line-height</span> on the next wrapped line.</p>
      <p>Keywords: <span class="k" style="vertical-align:top">top</span> <span class="k" style="vertical-align:bottom">bottom</span> <span class="k" style="vertical-align:middle">middle</span> <span class="k" style="vertical-align:text-top;font-size:11px">text-top</span> <span class="k" style="vertical-align:text-bottom;font-size:11px">text-bottom</span> <span style="display:inline-block;width:14px;height:46px;background:#38bdf8"></span></p></div>`),
  },
  {
    id: "layout3-card-all", feature: "inline-box-model", title: "article card: floated avatar and pull quote, badges, chips, code spans, sub / super in wrapping text", width: 640, height: 420, images: imgs(),
    node: page(`
      .card { width: 592px; height: 372px; box-sizing: border-box; border: 1px solid #cbd5e1; border-radius: 14px; padding: 18px 20px; background: #f8fafc; overflow: hidden; }
      h3 { margin: 0 0 8px; font-size: 20px; }
      .av { float: left; width: 84px; height: 84px; border-radius: 12px; margin: 2px 14px 6px 0; }
      .q { float: right; width: 150px; margin: 4px 0 6px 14px; padding: 8px 10px; background: #1e293b; color: #f8fafc; border-radius: 8px; font-size: 13px; line-height: 17px; }
      .badge { display: inline-block; padding: 1px 8px; border-radius: 9px; background: #dbeafe; color: #1d4ed8; font-size: 12px; font-weight: 700; vertical-align: middle; }
      .chip { display: inline-flex; align-items: center; gap: 5px; padding: 2px 8px 2px 3px; border-radius: 12px; background: #e2e8f0; font-size: 13px; line-height: 16px; vertical-align: middle; }
      .chip img { width: 16px; height: 16px; border-radius: 8px; }
      code { font-family: Inter; font-size: 13px; background: #e2e8f0; padding: 1px 5px; border-radius: 4px; white-space: nowrap; }
      mark { background: #fde68a; padding: 0 4px; margin: 0 2px; border-radius: 3px; }
      p { line-height: 23px; margin: 0 0 10px; }
      .foot { clear: both; border-top: 1px solid #cbd5e1; padding-top: 8px; font-size: 13px; color: #475569; }
    `, `<div class="card"><h3>Inline layout, third phase <span class="badge">new</span></h3>
      <img class="av" src="img://avatar"><div class="q">Lines take the range the floats leave free.</div>
      <p>Text now flows around <mark>floats on both sides</mark> and widens again below them. Inline boxes such as <span class="chip"><img src="img://icon">chips</span> and <span class="badge" style="background:#dcfce7;color:#15803d">badges</span> break with the words around them, <code>white-space: nowrap</code> keeps a span on one line, and x<sup>2</sup> + y<sub>0</sub> shift their baselines.</p>
      <p>A second paragraph starts beside whatever is left of the floats<br>and has a forced break.</p>
      <div class="foot">Footer below the floats · <span class="chip"><img src="img://avatar">Ada</span> · 3 min read</div></div>`),
  },
];

export default [...floats, ...inlineFlow, ...boxModel];
