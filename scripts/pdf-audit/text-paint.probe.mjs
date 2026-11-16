// Text painting probes: how glyph runs, decorations, strokes, shadows and colour glyphs are written (text
// operators and render modes, outlines, Type3 fonts, `/ActualText`, `/ReversedChars`), compared between bm-render/pdf
// and takumi-pdf with the canonical pages / draw lists of paint.probe.mjs. Extracted text (pdftotext) is compared
// as well where the reading order matters.
import { INTER, INTER_BOLD, ARCHIVO, NOTO_TC, TWEMOJI, font, squash } from "./lib.mjs";
import { cases, canonPages, cmp, dataUri, flatten, probeAs, vp } from "./paint.probe.mjs";

const named = (name, rel) => ({ name, data: font(rel) });
const F = {
  inter: named("Inter", INTER),
  interBold: { name: "Inter", data: font(INTER_BOLD), weight: 700 },
  interItalic: { name: "Inter", data: font("assets/fonts/Inter-Italic.ttf"), style: "italic" },
  roboto: named("Roboto", "assets/fonts/Roboto-Regular.ttf"),
  archivo: named("Archivo", ARCHIVO),
  tc: named("Noto Sans TC", NOTO_TC),
  twemoji: named("Twemoji", TWEMOJI),
  colrv1: named("Noto Color Emoji", "takumi-pdf/tests/fonts/NotoColorEmoji.COLR.subset.ttf"),
  cbdt: named("Noto Color Emoji", "assets/fonts/noto-sans/NotoColorEmoji.ttf"),
  arabic: named("Scheherazade New", "assets/fonts/sil/scheherazade-new-v17-arabic-regular.woff2"),
  deva: named("Noto Sans Devanagari", "assets/fonts/noto-sans/noto-sans-devanagari-v30-devanagari-regular.woff2"),
  geistVar: named("Geist", "assets/fonts/geist/Geist[wght].woff2"),
  geistTtc: named("Geist Duo", "assets/fonts/geist/GeistDuo.ttc"),
  ubuntuTtc: named("Ubuntu", "assets/fonts/ubuntu/Ubuntu.ttc"),
  interOpsz: named("Inter Var", "assets/fonts/inter/inter-latin-opsz-wght-normal.woff2"),
  garamondCaps: named("EB Garamond", "assets/fonts/eb-garamond/EBGaramondCaps.woff2"),
  combining: named("Archivo Combining", "takumi-pdf/tests/fonts/archivo-combining.subset.ttf"),
};
const p = (style, text, tag = "p") => `<${tag} style="margin:10px;font:20px Inter;${style}">${text}</${tag}>`;
const page = vp(260, 120);

/** `cases` with fonts: `[id, html, fonts?, options?]`. Also compares the extracted text when `text` is set. */
function textCases(prefix, feature, list, { text = false } = {}) {
  for (const [id, html, fonts, options] of list) {
    probeAs(`${prefix}.${id}`, feature, async (t) => {
      const r = await cmp(t, "", html, options || page, { fonts: fonts || [F.inter] });
      if (text && r.ref && !r.bm.error && !r.ref.error) t.same("extracted text", squash(r.bm.text), squash(r.ref.text));
    });
  }
}

// ------------------------------------------------------------------------------------------------ fill, stroke

textCases("text.fill", "text fill colour", [
  ["black", p("", "Hello")],
  ["color", p("color:#c33", "Hello")],
  ["alpha", p("color:rgba(204,51,51,.5)", "Hello")],
  ["transparent", p("color:transparent", "Hello")],
  ["spans", p("", `a<span style="color:red">b</span><span style="color:rgba(0,0,255,.5)">c</span>d`)],
  ["text-fill-color", p("-webkit-text-fill-color:#06c;color:red", "Hello")],
  ["text-fill-transparent", p("-webkit-text-fill-color:transparent", "Hello")],
  ["font-size-zero", p("font-size:0", "Hello")],
  ["font-size-large", p("font-size:90px;line-height:1", "Hg")],
  ["font-size-fractional", p("font-size:13.37px", "Hello")],
  ["empty", p("", "")],
  ["whitespace-only", p("", "   ")],
  ["nbsp", p("", "a&nbsp;&nbsp;b")],
  ["opacity-group", p("opacity:.5", "Hello")],
], { text: true });

textCases("text.stroke", "-webkit-text-stroke and paint-order", [
  ["stroke", p("-webkit-text-stroke:1px #c33", "Stroke")],
  ["stroke-thick", p("-webkit-text-stroke:3px #c33;color:#fc0", "Stroke")],
  ["stroke-alpha", p("-webkit-text-stroke:2px rgba(0,0,255,.4)", "Stroke")],
  ["stroke-transparent-fill", p("-webkit-text-stroke:1px #000;color:transparent", "Stroke")],
  ["stroke-width-only", p("-webkit-text-stroke-width:1px", "Stroke")],
  ["stroke-zero", p("-webkit-text-stroke:0 #c33", "Stroke")],
  ["paint-order-stroke", p("-webkit-text-stroke:3px #c33;color:#fc0;paint-order:stroke fill", "Stroke")],
  ["paint-order-fill", p("-webkit-text-stroke:3px #c33;color:#fc0;paint-order:fill stroke", "Stroke")],
  ["paint-order-markers", p("-webkit-text-stroke:3px #c33;color:#fc0;paint-order:markers stroke", "Stroke")],
  ["stroke-span", p("", `a<span style="-webkit-text-stroke:1px red">b</span>c`)],
  ["stroke-with-shadow", p("-webkit-text-stroke:1px #c33;text-shadow:2px 2px #000", "Stroke")],
  ["stroke-with-decoration", p("-webkit-text-stroke:1px #c33;text-decoration:underline", "Stroke")],
  ["stroke-color-emoji", p("-webkit-text-stroke:1px #c33;font-family:Inter,Twemoji", "a\u{1F600}b"), [F.inter, F.twemoji]],
], { text: true });

// ------------------------------------------------------------------------------------------------ decorations

const deco = (d, text = "Deco ypg text") => p(`text-decoration:${d}`, text);
textCases("text.decoration", "text decorations", [
  ["underline", deco("underline")],
  ["overline", deco("overline")],
  ["line-through", deco("line-through")],
  ["all-three", deco("underline overline line-through")],
  ["double", deco("underline double")],
  ["dotted", deco("underline dotted")],
  ["dashed", deco("underline dashed")],
  ["wavy", deco("underline wavy")],
  ["wavy-line-through", deco("line-through wavy red")],
  ["color", deco("underline #c33")],
  ["color-alpha", deco("underline rgba(0,0,255,.4)")],
  ["thickness", deco("underline 4px")],
  ["thickness-from-font", p("text-decoration:underline;text-decoration-thickness:from-font", "Deco ypg")],
  ["thickness-percent", p("text-decoration:underline;text-decoration-thickness:10%", "Deco ypg")],
  ["offset", p("text-decoration:underline;text-underline-offset:6px", "Deco ypg")],
  ["offset-negative", p("text-decoration:underline;text-underline-offset:-3px", "Deco ypg")],
  ["underline-position-under", p("text-decoration:underline;text-underline-position:under", "Deco ypg")],
  ["skip-ink-auto", p("text-decoration:underline;text-decoration-skip-ink:auto", "gypsy jumping")],
  ["skip-ink-none", p("text-decoration:underline;text-decoration-skip-ink:none", "gypsy jumping")],
  ["skip-ink-all", p("text-decoration:underline;text-decoration-skip-ink:all", "gypsy jumping")],
  ["span", p("", `a <span style="text-decoration:underline">under</span> b`)],
  ["propagated", p("text-decoration:underline", `a <span style="color:red;font-size:30px">big</span> b`)],
  ["nested-different", p("text-decoration:underline", `a <span style="text-decoration:line-through red">both</span> b`)],
  ["inline-block-not-propagated", p("text-decoration:underline", `a <span style="display:inline-block">ib</span> b`)],
  ["u-s-del-ins", p("", `<u>u</u> <s>s</s> <del>del</del> <ins>ins</ins>`)],
  ["link", p("", `<a href="https://example.com">link</a>`)],
  ["wrapped", p("text-decoration:underline;width:90px", "wraps over several lines")],
  ["with-letter-spacing", p("text-decoration:underline;letter-spacing:4px", "Spaced")],
  ["with-shadow", p("text-decoration:underline;text-shadow:2px 2px 2px #c33", "Shadow")],
  ["with-opacity-color", p("text-decoration:underline;color:rgba(0,0,0,.4)", "Alpha")],
  ["none-on-child", p("text-decoration:underline", `a <span style="text-decoration:none">none</span> b`)],
  ["line-through-big-small", p("", `<s>a<span style="font-size:36px">B</span>c</s>`)],
  ["rtl", p("text-decoration:underline;direction:rtl", "abc def")],
  ["vertical", p("text-decoration:underline;writing-mode:vertical-rl;height:80px", "Vert")],
  ["blink", deco("blink")],
  ["spelling-error", deco("spelling-error")],
]);

textCases("text.emphasis", "text-emphasis", [
  ["dot", p("text-emphasis:dot;line-height:2", "Emph")],
  ["filled-sesame-color", p("text-emphasis:filled sesame #c33;line-height:2", "Emph")],
  ["open-circle", p("text-emphasis:open circle;line-height:2", "Emph")],
  ["string", p("text-emphasis:'x';line-height:2", "Emph")],
  ["position-under", p("text-emphasis:triangle;text-emphasis-position:under right;line-height:2", "Emph")],
  ["webkit-prefix", p("-webkit-text-emphasis:dot;line-height:2", "Emph")],
]);

// ------------------------------------------------------------------------------------------------ shadow

textCases("text.shadow", "text-shadow", [
  ["offset", p("text-shadow:2px 2px #c33", "Shadow")],
  ["alpha", p("text-shadow:2px 2px rgba(0,0,0,.4)", "Shadow")],
  ["blur", p("text-shadow:0 0 4px #c33", "Shadow")],
  ["blur-alpha", p("text-shadow:1px 1px 3px rgba(0,0,255,.5)", "Shadow")],
  ["blur-large", p("text-shadow:0 0 20px #000", "Shadow")],
  ["multiple", p("text-shadow:1px 1px red,-1px -1px blue,0 0 6px #0a0", "Shadow")],
  ["current-color", p("color:#c0c;text-shadow:2px 2px", "Shadow")],
  ["transparent-text", p("color:transparent;text-shadow:0 0 2px #000", "Shadow")],
  ["span", p("", `a<span style="text-shadow:2px 2px red">b</span>c`)],
  ["with-stroke-blur", p("-webkit-text-stroke:1px #c33;text-shadow:2px 2px 3px #000", "Shadow")],
  ["color-glyph", p("text-shadow:2px 2px #c33;font-family:Inter,Twemoji", "a\u{1F600}b"), [F.inter, F.twemoji]],
  ["color-glyph-blur", p("text-shadow:2px 2px 3px #c33;font-family:Inter,Twemoji", "a\u{1F600}b"), [F.inter, F.twemoji]],
  ["bitmap-glyph", p("text-shadow:2px 2px #c33;font-family:Inter,'Noto Color Emoji'", "a\u{1F600}b"), [F.inter, F.cbdt]],
  ["bitmap-glyph-blur", p("text-shadow:2px 2px 3px #c33;font-family:Inter,'Noto Color Emoji'", "a\u{1F600}b"), [F.inter, F.cbdt]],
  ["emphasis", p("text-shadow:2px 2px #c33;text-emphasis:dot;line-height:2", "Sh")],
  ["none", p("text-shadow:none", "Shadow")],
], { text: true });

// ------------------------------------------------------------------------------------------------ spacing, overflow

textCases('text.shadow.colr-ppem', 'COLR shadow outlines resolved at the requested font size',
  [13, 27.5, 40, 63].flatMap(size => [0, 4].map(blur => [
    `${size}-${blur}`,
    p(`font-size:${size}px;font-family:Inter,Twemoji;text-shadow:6px 6px ${blur}px rgba(220,38,38,.8)`, 'Party 🎉🚀'),
    [F.inter, F.twemoji], vp(420, 150),
  ])), { text: true });

textCases("text.spacing", "letter-spacing, word-spacing, alignment", [
  ["letter-spacing", p("letter-spacing:3px", "Spaced out")],
  ["letter-spacing-negative", p("letter-spacing:-1px", "Spaced out")],
  ["letter-spacing-em", p("letter-spacing:.2em", "Spaced out")],
  ["word-spacing", p("word-spacing:10px", "Spaced out words")],
  ["word-spacing-negative", p("word-spacing:-3px", "Spaced out words")],
  ["both", p("letter-spacing:2px;word-spacing:8px", "Spaced out words")],
  ["justify", p("text-align:justify;width:150px", "Justified text over a few lines here")],
  ["justify-last", p("text-align:justify;text-align-last:justify;width:150px", "Justified text")],
  ["center-right", p("text-align:center;width:200px", "centre") + p("text-align:right;width:200px", "right")],
  ["text-indent", p("text-indent:30px;width:150px", "Indented first line of text")],
  // tabs/pre-wrap/generated hyphens: text-semantics.probe.mjs checks viewer text and
  // raster output. Splitting equivalent TJ runs is not a required byte-level behavior.
  ["kerning-none", p("font-kerning:none", "AVATAR Wave To")],
  ["kerning-normal", p("font-kerning:normal", "AVATAR Wave To")],
  ["line-height", p("line-height:3", "Tall")],
  ["hyphens-auto", `<p lang="en" style="margin:10px;font:20px Inter;width:70px;hyphens:auto">extraordinary</p>`],
  ["word-break", p("width:60px;word-break:break-all", "extraordinary")],
  ["overflow-wrap", p("width:60px;overflow-wrap:anywhere", "extraordinary")],
  ["text-wrap-balance", p("width:160px;text-wrap:balance", "Balanced lines of text here")],
], { text: true });

const narrow = "width:120px;white-space:nowrap;overflow:hidden;";
textCases("text.overflow", "text-overflow and line-clamp", [
  ["ellipsis", p(narrow + "text-overflow:ellipsis", "A long line that does not fit")],
  ["clip", p(narrow + "text-overflow:clip", "A long line that does not fit")],
  ["string", p(narrow + "text-overflow:'>>'", "A long line that does not fit")],
  ["ellipsis-visible-overflow", p("width:120px;white-space:nowrap;text-overflow:ellipsis", "A long line that does not fit")],
  ["ellipsis-rtl", p(narrow + "text-overflow:ellipsis;direction:rtl", "A long line that does not fit")],
  ["ellipsis-span-color", p(narrow + "text-overflow:ellipsis", `A long <span style="color:red">line that does not fit</span>`)],
  ["line-clamp", p("width:120px;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;overflow:hidden", "Clamped text over many many lines of text")],
  ["line-clamp-standard", p("width:120px;line-clamp:2;overflow:hidden", "Clamped text over many many lines of text")],
  ["line-clamp-no-overflow", p("width:120px;-webkit-line-clamp:2;display:-webkit-box;-webkit-box-orient:vertical", "Clamped text over many many lines of text")],
  ["max-lines-fit", p("width:120px;-webkit-line-clamp:5;display:-webkit-box;-webkit-box-orient:vertical;overflow:hidden", "Short text")],
], { text: true });

// ------------------------------------------------------------------------------------------------ gradient text

const PNG = dataUri("takumi-pdf/tests/images/checker.png");
const clipText = (bg, extra = "") => p(`background:${bg};-webkit-background-clip:text;background-clip:text;color:transparent;${extra}`, "Gradient");
textCases("text.background-clip", "background-clip: text", [
  ["linear", clipText("linear-gradient(90deg,red,blue)")],
  ["radial", clipText("radial-gradient(red,blue)")],
  ["conic", clipText("conic-gradient(red,blue)")],
  ["color", clipText("#c33")],
  ["image", clipText(`url(${PNG})`)],
  ["layers", clipText("linear-gradient(90deg,rgba(255,0,0,.5),transparent),linear-gradient(blue,green)")],
  ["alpha-gradient", clipText("linear-gradient(90deg,red,transparent)")],
  ["opaque-color-text", clipText("linear-gradient(90deg,red,blue)", "color:#000")],
  ["semi-color-text", clipText("linear-gradient(90deg,red,blue)", "color:rgba(0,0,0,.3)")],
  ["text-fill-transparent", p("background:linear-gradient(90deg,red,blue);-webkit-background-clip:text;-webkit-text-fill-color:transparent", "Gradient")],
  ["with-stroke", clipText("linear-gradient(90deg,red,blue)", "-webkit-text-stroke:1px #000")],
  ["with-shadow", clipText("linear-gradient(90deg,red,blue)", "text-shadow:2px 2px #0004")],
  ["with-decoration", clipText("linear-gradient(90deg,red,blue)", "text-decoration:underline")],
  ["multi-line", clipText("linear-gradient(red,blue)", "width:90px")],
  ["span", p("", `a <span style="background:linear-gradient(90deg,red,blue);-webkit-background-clip:text;color:transparent">grad</span> b`)],
  ["children", `<div style="margin:10px;font:20px Inter;background:linear-gradient(90deg,red,blue);-webkit-background-clip:text;color:transparent"><p style="margin:0">One</p><p style="margin:0">Two <b>bold</b></p></div>`],
  ["size-repeat", clipText("linear-gradient(red,blue) 0 0/20px 10px")],
  ["bold-synthetic", clipText("linear-gradient(90deg,red,blue)", "font-weight:700")],
  ["emoji", p(`background:linear-gradient(90deg,red,blue);-webkit-background-clip:text;color:transparent;font-family:Inter,Twemoji`, "a\u{1F600}b"), [F.inter, F.twemoji]],
  ["with-filter", clipText("linear-gradient(90deg,red,blue)", "filter:grayscale(1)")],
], { text: true });

probeAs("text.background-clip.border-box-and-text", "mixed background-clip layers paint the box color and clip only the text layer", async (t) => {
  const html = p("background:linear-gradient(90deg,red,blue),#ff0;background-clip:text,border-box;color:transparent", "Gradient");
  const r = await t.both(html, page, { fonts: [F.inter] });
  t.ok(!r.bm.error, `bm-render renders the mixed background layers${r.bm.error ? `: ${r.bm.error}` : ""}`);
  if (r.bm.error) return;
  const flat = flatten(canonPages(r.bm)[0] || []);
  const joined = flat.map(String).join(" ");
  t.ok(joined.includes("FILL rg 1 1 0"), "yellow border-box background color is painted");
  t.ok(joined.includes("/PatternType") && joined.includes("/ShadingType"), "gradient layer remains available to the text glyph mask");
  t.ok(squash(r.bm.text).includes("Gradient"), "text remains extractable");
  t.differs("pinned Takumi paints the gradient as a box and omits the background color in this mixed-clip case; bm-render follows each layer's clip");
});

// ------------------------------------------------------------------------------------------------ transform, variants

textCases("text.transform", "text-transform", [
  ["uppercase", p("text-transform:uppercase", "Straße ffi upper")],
  ["lowercase", p("text-transform:lowercase", "LOWER Case")],
  ["capitalize", p("text-transform:capitalize", "capital letters here")],
  ["full-width", p("text-transform:full-width;font-family:Inter,'Noto Sans TC'", "abc"), [F.inter, F.tc]],
  ["full-width-preserved-space", p("text-transform:full-width;white-space:pre;font-family:Inter,'Noto Sans TC'", "a b"), [F.inter, F.tc]],
  ["full-width-collapsed-space", p("text-transform:full-width;font-family:Inter,'Noto Sans TC'", "a b"), [F.inter, F.tc]],
  ["full-width-uppercase", p("text-transform:full-width uppercase;font-family:Inter,'Noto Sans TC'", "abß"), [F.inter, F.tc]],
  ["full-size-kana", p("text-transform:full-size-kana;font-family:'Noto Sans TC'", "ぁぃゕァィヵｧｨ"), [F.tc]],
  ["full-width-kana", p("text-transform:full-size-kana full-width;font-family:'Noto Sans TC'", "ｧｨｶ"), [F.tc]],
  ["transform-duplicate-invalid", p("text-transform:full-width full-width;font-family:Inter,'Noto Sans TC'", "abc"), [F.inter, F.tc]],
  ["span", p("", `a <span style="text-transform:uppercase">up</span> b`)],
], { text: true });

textCases("text.variant", "small-caps, sub/superscript, font features", [
  ["small-caps-synthetic", p("font-variant:small-caps", "Small Caps Text")],
  ["small-caps-font", p("font-variant-caps:small-caps;font-family:'EB Garamond'", "Small Caps Text"), [F.garamondCaps]],
  ["all-small-caps", p("font-variant-caps:all-small-caps;font-family:'EB Garamond'", "Small Caps Text"), [F.garamondCaps]],
  ["sub-sup-elements", p("", "H<sub>2</sub>O x<sup>2</sup>")],
  ["vertical-align-super", p("", `a<span style="vertical-align:super;font-size:12px">sup</span>b<span style="vertical-align:sub;font-size:12px">sub</span>`)],
  ["vertical-align-length", p("", `a<span style="vertical-align:6px">up</span><span style="vertical-align:-30%">down</span>`)],
  ["font-variant-position", p("font-variant-position:super", "x2")],
  ["feature-tnum", p("font-feature-settings:'tnum'", "1111 0000")],
  ["feature-off-liga", p("font-feature-settings:'liga' 0, 'calt' 0;font-family:Roboto", "fi ffl ->"), [F.roboto]],
  ["feature-ss01", p("font-feature-settings:'ss01','cv11' 1,'zero'", "a10 Il")],
  ["feature-frac", p("font-feature-settings:'frac'", "1/2 3/4")],
  ["variant-numeric", p("font-variant-numeric:tabular-nums slashed-zero", "1010")],
  ["variant-ligatures-none", p("font-variant-ligatures:none;font-family:Roboto", "fi ffl"), [F.roboto]],
  ["font-variant-east-asian", p("font-variant-east-asian:traditional;font-family:'Noto Sans TC'", "国"), [F.tc]],
  ["lang-locl", `<p lang="zh-TW" style="margin:10px;font:20px 'Noto Sans TC'">骨</p>`, [F.tc]],
], { text: true });

textCases("text.ligature", "ligatures and /ActualText", [
  ["fi-roboto", p("font-family:Roboto", "office fi ffl"), [F.roboto]],
  ["inter-arrows", p("", "a -> b => c")],
  ["combining-marks", p("font-family:'Archivo Combining',Inter", "é ä"), [F.combining, F.inter]],
  ["precomposed", p("", "é ä ñ")],
  ["emoji-zwj", p("font-family:Inter,Twemoji", "\u{1F468}‍\u{1F469}‍\u{1F467}"), [F.inter, F.twemoji]],
  ["emoji-skin-tone", p("font-family:Inter,Twemoji", "\u{1F44D}\u{1F3FD}"), [F.inter, F.twemoji]],
  ["emoji-flag", p("font-family:Inter,Twemoji", "\u{1F1EF}\u{1F1F5}"), [F.inter, F.twemoji]],
  ["variation-selector", p("font-family:Inter,Twemoji", "❤️ ❤︎"), [F.inter, F.twemoji]],
  ["surrogates-cjk-ext", p("font-family:'Noto Sans TC'", "\u{20BB7}野家"), [F.tc]],
], { text: true });

// ------------------------------------------------------------------------------------------------ bidi, scripts, vertical

textCases("text.bidi", "RTL / bidi text (/ReversedChars)", [
  ["arabic", p("font-family:'Scheherazade New'", "مرحبا بالعالم"), [F.arabic]],
  ["arabic-rtl-dir", `<p dir="rtl" style="margin:10px;font:20px 'Scheherazade New'">مرحبا بالعالم</p>`, [F.arabic]],
  ["mixed", p("font-family:Inter,'Scheherazade New'", "abc مرحبا def 123"), [F.inter, F.arabic]],
  ["mixed-rtl-base", `<p dir="rtl" style="margin:10px;font:20px Inter,'Scheherazade New'">abc مرحبا def 123</p>`, [F.inter, F.arabic]],
  ["latin-direction-rtl", p("direction:rtl", "Latin rtl!")],
  ["bidi-override", p("direction:rtl;unicode-bidi:bidi-override", "Reversed")],
  ["bdo", p("", `a <bdo dir="rtl">Reversed</bdo> b`)],
  ["isolate", p("font-family:Inter,'Scheherazade New'", `a <bdi>مرحبا</bdi> b`), [F.inter, F.arabic]],
  ["arabic-numbers", p("font-family:'Scheherazade New'", "العدد ١٢٣ و 456"), [F.arabic]],
  ["arabic-underline", p("font-family:'Scheherazade New';text-decoration:underline", "مرحبا"), [F.arabic]],
  ["arabic-letter-spacing", p("font-family:'Scheherazade New';letter-spacing:2px", "مرحبا"), [F.arabic]],
  ["arabic-justify", `<p dir="rtl" style="margin:10px;font:20px 'Scheherazade New';width:150px;text-align:justify">مرحبا بالعالم مرحبا بالعالم مرحبا</p>`, [F.arabic]],
], { text: true });

textCases("text.complex-script", "complex script shaping", [
  ["devanagari", p("font-family:'Noto Sans Devanagari'", "नमस्ते दुनिया"), [F.deva]],
  ["devanagari-conjuncts", p("font-family:'Noto Sans Devanagari'", "क्षत्रिय श्री ज्ञान"), [F.deva]],
  ["devanagari-latin", p("font-family:Inter,'Noto Sans Devanagari'", "Hi नमस्ते ok"), [F.inter, F.deva]],
  ["cjk", p("font-family:'Noto Sans TC'", "你好，世界。"), [F.tc]],
  ["cjk-latin", p("font-family:Inter,'Noto Sans TC'", "Hello 世界 ok"), [F.inter, F.tc]],
  ["cjk-bold-variable", p("font-family:'Noto Sans TC';font-weight:700", "你好"), [F.tc]],
], { text: true });

textCases("text.vertical", "vertical writing modes", [
  ["vertical-rl-latin", p("writing-mode:vertical-rl;height:90px", "Vertical")],
  ["vertical-lr-latin", p("writing-mode:vertical-lr;height:90px", "Vertical")],
  ["vertical-rl-cjk", p("writing-mode:vertical-rl;height:90px;font-family:'Noto Sans TC'", "你好世界。"), [F.tc]],
  ["vertical-mixed", p("writing-mode:vertical-rl;height:100px;font-family:Inter,'Noto Sans TC'", "你好 ab 世界"), [F.inter, F.tc]],
  ["upright", p("writing-mode:vertical-rl;text-orientation:upright;height:100px", "Up")],
  ["sideways", p("writing-mode:vertical-rl;text-orientation:sideways;height:100px;font-family:'Noto Sans TC'", "你好"), [F.tc]],
  ["sideways-rl", p("writing-mode:sideways-rl;height:90px", "Side")],
  ["sideways-lr", p("writing-mode:sideways-lr;height:90px", "Side")],
  ["text-combine", p("writing-mode:vertical-rl;height:100px;font-family:'Noto Sans TC'", `平成<span style="text-combine-upright:all">31</span>年`), [F.tc]],
  ["vertical-wrapped", p("writing-mode:vertical-rl;height:60px", "Two columns of text")],
], { text: true });

// ------------------------------------------------------------------------------------------------ fonts, synthesis

textCases("text.synthesis", "synthetic bold / italic", [
  ["bold-synthetic", p("font-weight:700", "Bold text")],
  ["bold-real", p("font-weight:700", "Bold text"), [F.inter, F.interBold]],
  ["italic-synthetic", p("font-style:italic", "Italic text")],
  ["italic-real", p("font-style:italic", "Italic text"), [F.inter, F.interItalic]],
  ["oblique-angle", p("font-style:oblique 20deg", "Oblique")],
  ["bold-italic-synthetic", p("font-weight:700;font-style:italic", "Both")],
  ["synthesis-none", p("font-weight:700;font-style:italic;font-synthesis:none", "None")],
  ["synthesis-weight-only", p("font-weight:700;font-style:italic;font-synthesis:weight", "Weight")],
  ["synthesis-style-only", p("font-weight:700;font-style:italic;font-synthesis:style", "Style")],
  ["b-i-elements", p("", "a <b>b</b> <i>i</i> <strong>s</strong> <em>e</em>")],
  ["bold-synthetic-alpha", p("font-weight:700;color:rgba(0,0,0,.4)", "Bold alpha")],
  ["bold-synthetic-stroke", p("font-weight:700;-webkit-text-stroke:1px red", "Bold stroke")],
  ["bold-synthetic-shadow", p("font-weight:700;text-shadow:2px 2px 2px #c33", "Bold shadow")],
  ["italic-synthetic-underline", p("font-style:italic;text-decoration:underline", "Italic under")],
  ["weight-600-with-bold", p("font-weight:600", "Semi"), [F.inter, F.interBold]],
  ["weight-900-with-bold", p("font-weight:900", "Black"), [F.inter, F.interBold]],
  ["lighter-100", p("font-weight:100", "Thin")],
], { text: true });

textCases("text.variable-font", "variable fonts", [
  ["default-instance", p("font-family:Archivo", "Variable"), [F.archivo]],
  ["weight-700", p("font-family:Archivo;font-weight:700", "Variable"), [F.archivo]],
  ["weight-350", p("font-family:Archivo;font-weight:350", "Variable"), [F.archivo]],
  ["stretch-75", p("font-family:Archivo;font-stretch:75%", "Variable"), [F.archivo]],
  ["stretch-keyword", p("font-family:Archivo;font-stretch:expanded", "Variable"), [F.archivo]],
  ["variation-settings", p(`font-family:Archivo;font-variation-settings:"wght" 820, "wdth" 110`, "Variable"), [F.archivo]],
  ["variation-settings-over-weight", p(`font-family:Archivo;font-weight:300;font-variation-settings:"wght" 820`, "Variable"), [F.archivo]],
  ["two-instances", p("font-family:Archivo", `a <b>b</b> <span style="font-weight:200">c</span>`), [F.archivo]],
  ["italic-synthetic", p("font-family:Archivo;font-style:italic", "Variable"), [F.archivo]],
  ["woff2", p("font-family:Geist;font-weight:650", "Geist woff2"), [F.geistVar]],
  ["optical-size-auto", p("font-family:'Inter Var';font-size:40px;line-height:1", "Op"), [F.interOpsz]],
  ["optical-size-none", p("font-family:'Inter Var';font-size:40px;line-height:1;font-optical-sizing:none", "Op"), [F.interOpsz]],
  ["optical-size-setting", p(`font-family:'Inter Var';font-variation-settings:"opsz" 32`, "Op"), [F.interOpsz]],
  ["cjk-variable", p("font-family:'Noto Sans TC';font-weight:300", "輕"), [F.tc]],
], { text: true });

textCases("text.font-format", "font containers", [
  ["ttc-geist", p("font-family:'Geist Duo'", "Collection"), [F.geistTtc]],
  ["ttc-ubuntu", p("font-family:Ubuntu", "Collection"), [F.ubuntuTtc]],
  ["ttc-ubuntu-bold", p("font-family:Ubuntu;font-weight:700", "Collection"), [F.ubuntuTtc]],
  ["woff2-static", p("font-family:'Scheherazade New'", "abc"), [F.arabic]],
  ["two-fonts-one-line", p("font-family:Inter", `a <span style="font-family:Roboto">b</span> c`), [F.inter, F.roboto]],
  ["fallback-chain", p("font-family:Nope,Roboto,Inter", "fallback"), [F.inter, F.roboto]],
  ["generic-family", p("font-family:sans-serif", "generic")],
  ["monospace", `<pre style="margin:10px;font-size:16px">mono</pre>`],
], { text: true });

// ------------------------------------------------------------------------------------------------ colour glyphs

const emoji = (family, text, style = "") => p(`font-family:Inter,${family};${style}`, text);
textCases("text.color-glyph", "colour glyphs: COLR v0 / v1, CBDT bitmaps", [
  ["colr-v0", emoji("Twemoji", "a\u{1F600}b"), [F.inter, F.twemoji]],
  ["colr-v0-several", emoji("Twemoji", "\u{1F600}\u{1F680}\u{1F600}"), [F.inter, F.twemoji]],
  ["colr-v0-color", emoji("Twemoji", "❤ \u{1F600}", "color:#06c"), [F.inter, F.twemoji]],
  ["colr-v0-opacity", emoji("Twemoji", "\u{1F600}", "opacity:.5"), [F.inter, F.twemoji]],
  ["colr-v0-alpha-color", emoji("Twemoji", "\u{1F600}", "color:rgba(0,0,0,.3)"), [F.inter, F.twemoji]],
  ["colr-v0-rotated", emoji("Twemoji", "\u{1F600}", "transform:rotate(20deg);width:60px"), [F.inter, F.twemoji]],
  ["colr-v0-filter", emoji("Twemoji", "\u{1F600}", "filter:grayscale(1)"), [F.inter, F.twemoji]],
  ["colr-v0-large", emoji("Twemoji", "\u{1F600}", "font-size:80px;line-height:1"), [F.inter, F.twemoji]],
  ["colr-v0-underline", emoji("Twemoji", "a\u{1F600}b", "text-decoration:underline"), [F.inter, F.twemoji]],
  ["colr-v1", emoji("'Noto Color Emoji'", "a\u{1F600}b"), [F.inter, F.colrv1]],
  ["colr-v1-gradients", emoji("'Noto Color Emoji'", "\u{1F308}\u{1F525}\u{1F34E}"), [F.inter, F.colrv1]],
  ["colr-v1-opacity", emoji("'Noto Color Emoji'", "\u{1F600}", "opacity:.5"), [F.inter, F.colrv1]],
  ["colr-v1-filter", emoji("'Noto Color Emoji'", "\u{1F600}", "filter:invert(1)"), [F.inter, F.colrv1]],
  ["cbdt", emoji("'Noto Color Emoji'", "a\u{1F600}b"), [F.inter, F.cbdt]],
  ["cbdt-several", emoji("'Noto Color Emoji'", "\u{1F600}\u{1F680}\u{1F600}"), [F.inter, F.cbdt]],
  ["cbdt-large", emoji("'Noto Color Emoji'", "\u{1F600}", "font-size:80px;line-height:1"), [F.inter, F.cbdt]],
  ["cbdt-opacity", emoji("'Noto Color Emoji'", "\u{1F600}", "opacity:.5"), [F.inter, F.cbdt]],
  ["cbdt-filter", emoji("'Noto Color Emoji'", "\u{1F600}", "filter:grayscale(1)"), [F.inter, F.cbdt]],
  ["cbdt-synthetic-italic", emoji("'Noto Color Emoji'", "\u{1F600}", "font-style:italic"), [F.inter, F.cbdt]],
  ["emoji-only-font", p("font-family:Twemoji", "\u{1F600} text"), [F.twemoji]],
  ["emoji-clip-text", p("font-family:Inter,Twemoji;background:linear-gradient(red,blue);-webkit-background-clip:text;color:transparent", "\u{1F600}"), [F.inter, F.twemoji]],
], { text: true });

// ------------------------------------------------------------------------------------------------ uncovered text, order

probeAs("text.uncovered", "characters no font covers (`uncoveredText`)", async (t) => {
  for (const [id, opts] of [["default", {}], ["error", { uncoveredText: "error" }], ["placeholder", { uncoveredText: "placeholder" }], ["blank", { uncoveredText: "blank" }], ["bogus", { uncoveredText: "nope" }]]) {
    const r = await cmp(t, id, p("", "ok 你好 \u{1F600} end"), { ...page, ...opts }, { fonts: [F.inter] });
    if (r.ref && !r.bm.error && !r.ref.error) t.same(id + ": extracted text", squash(r.bm.text), squash(r.ref.text));
  }
  await cmp(t, "no fonts at all", p("", "Hello"), page, { fonts: [] });
  await cmp(t, "control characters", p("", "a\u0001b​c­d﻿e"), page, { fonts: [F.inter] });
});

textCases("text.order", "content-stream order of text (selection / extraction order)", [
  ["two-columns-flex", `<div style="display:flex;font:14px Inter;gap:10px;margin:10px"><div>left one<br>left two</div><div>right one<br>right two</div></div>`],
  ["grid", `<div style="display:grid;grid-template-columns:1fr 1fr;font:14px Inter;margin:10px"><div>a1</div><div>b1</div><div>a2</div><div>b2</div></div>`],
  ["order-property", `<div style="display:flex;font:14px Inter;margin:10px"><div style="order:2">second</div><div style="order:1">first</div></div>`],
  ["row-reverse", `<div style="display:flex;flex-direction:row-reverse;font:14px Inter;margin:10px"><div>one</div><div>two</div></div>`],
  ["absolute", `<div style="position:relative;font:14px Inter;margin:10px;height:60px"><div style="position:absolute;top:30px">abs later</div><div>flow first</div></div>`],
  ["z-index", `<div style="position:relative;font:14px Inter;margin:10px;height:60px"><div style="position:absolute;z-index:2;top:0">top z2</div><div style="position:absolute;z-index:1;top:20px">mid z1</div></div>`],
  ["float", `<div style="font:14px Inter;margin:10px;width:200px"><div style="float:right">floated</div>text flows around the float</div>`],
  ["table", `<table style="font:14px Inter;margin:10px"><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>`],
  ["multi-line-spans", p("width:120px", `one <b>two three</b> four <i>five six</i> seven`)],
  ["br", p("", "line one<br>line two")],
  ["hidden-overflow-text", `<div style="font:14px Inter;margin:10px;width:60px;height:20px;overflow:hidden">visible part and hidden part that is cut away entirely</div>`],
  ["clipped-by-clip-path", `<div style="font:14px Inter;margin:10px;clip-path:inset(0 0 50% 0)">first line<br>second line</div>`],
  ["display-none-text", p("", `shown <span style="display:none">hidden</span> shown`)],
  ["visibility-hidden-text", p("", `shown <span style="visibility:hidden">hidden</span> shown`)],
  ["zero-opacity-text", p("", `shown <span style="opacity:0">faded</span> shown`)],
  ["offscreen-text", `<div style="font:14px Inter;position:absolute;left:-500px">offscreen</div><p style="font:14px Inter">onscreen</p>`],
], { text: true });
