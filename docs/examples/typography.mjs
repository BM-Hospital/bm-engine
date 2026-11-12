// Examples for docs/{en,vi}/typography.md. Run: node docs/examples/run-all.mjs typography
import { saver } from "./_lib.mjs";
import { existsSync } from "node:fs";
const save = saver("typography");

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
for (const file of ["Inter-Regular", "Inter-SemiBold", "Inter-Bold", "Inter-Italic", "Roboto-Regular"]) {
  renderer.registerFont(readFileSync(`assets/fonts/${file}.ttf`));
}

// Small helpers used by the examples on this page.
const text = (t, style = {}) => ({ type: "text", text: t, style });
const box = (style, children) => ({ type: "container", style: { display: "block", ...style }, children });
const page = (style, children) => ({
  type: "container",
  style: { display: "flex", width: "100%", height: "100%", padding: 16, gap: 12, backgroundColor: "#fff",
           color: "#111827", fontFamily: "Inter", fontSize: 16, ...style },
  children,
});
// A labelled sample: grey caption + a framed box (170 px wide unless style.width says otherwise).
const sample = (label, { width = 170, ...style }, children) => box({ width }, [
  box({ fontSize: 12, color: "#6b7280", marginBottom: 4 }, [text(label)]),
  box({ border: "1px solid #cbd5e1", padding: 6, ...style }, children),
]);
// #endregion

// #region white-space
const para = "Text  wraps   at spaces.\nA newline here.";
const whiteSpace = renderer.renderSync(
  page({}, ["normal", "nowrap", "pre", "pre-wrap", "pre-line"].map((ws) =>
    sample(ws, { whiteSpace: ws, width: 140, height: 110, overflow: "hidden" }, [text(para)]))),
  { width: 790, height: 160 },
);
// #endregion
save("white-space", whiteSpace);

// #region breaking
const url = "https://example.com/a/very/long/path/without-any-spaces";
const breaking = renderer.renderSync(
  page({}, [
    sample("normal (overflow hidden)", { overflow: "hidden" }, [text(url)]),
    sample("overflowWrap: anywhere", { overflowWrap: "anywhere" }, [text(url)]),
    sample("wordBreak: break-all", { wordBreak: "break-all" }, [text("Break all of these words")]),
    sample("soft hyphen U+00AD", {}, [text("Extra­ordinary inter­nationalisation")]),
  ]),
  { width: 790, height: 140 },
);
// #endregion
save("breaking", breaking);

// #region spacing
const spacing = renderer.renderSync(
  page({ flexDirection: "column", gap: 6 }, [
    text("Default: lineHeight normal (from the font's metrics), no extra spacing"),
    box({ lineHeight: 1.8, backgroundColor: "#f1f5f9", width: 520 }, [text("lineHeight: 1.8 adds half-leading above and below every line of this wrapped paragraph.")]),
    text("letterSpacing: 4px", { letterSpacing: 4 }),
    text("LETTERSPACING -0.05em", { letterSpacing: "-0.05em", fontWeight: 700, fontSize: 24 }),
    text("wordSpacing: 16px puts more room between words", { wordSpacing: 16 }),
  ]),
  { width: 560, height: 210 },
);
// #endregion
save("spacing", spacing);

// #region align
const words = "The quick brown fox jumps over the lazy dog and keeps running far away.";
const align = renderer.renderSync(
  page({}, [
    sample("left", { textAlign: "left" }, [text(words)]),
    sample("center", { textAlign: "center" }, [text(words)]),
    sample("right", { textAlign: "right" }, [text(words)]),
    sample("justify", { textAlign: "justify" }, [text(words)]),
  ]),
  { width: 790, height: 150 },
);
// #endregion
save("align", align);

// #region truncation
const long = "bm-engine renders node trees, HTML and Tailwind to images without a browser, in a few milliseconds.";
const truncation = renderer.renderSync(
  page({}, [
    sample("textOverflow: ellipsis", { whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }, [text(long)]),
    sample("lineClamp: 2", { lineClamp: 2 }, [text(long)]),
    sample("-webkit-line-clamp: 3", { display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: 3, overflow: "hidden" }, [text(long)]),
    sample("textOverflow: clip", { whiteSpace: "nowrap", overflow: "hidden" }, [text(long)]),
  ]),
  { width: 790, height: 130 },
);
// #endregion
save("truncation", truncation);

// #region balance
// text-wrap: balance / pretty need the standard or full profile.
const headline = "Render Open Graph images at the edge without a headless browser";
const balance = renderer.renderSync(
  page({}, ["wrap", "balance", "pretty"].map((mode) =>
    sample(`textWrap: ${mode}`, { width: 240, textWrap: mode, fontSize: 20, fontWeight: 700 }, [text(headline)]))),
  { width: 790, height: 165 },
);
// #endregion
save("balance", balance);

// #region decoration
const decoration = renderer.renderSync(
  page({ flexDirection: "column", gap: 8, fontSize: 20 }, [
    text("underline", { textDecoration: "underline" }),
    text("overline + line-through", { textDecorationLine: "overline line-through" }),
    text("wavy red underline", { textDecoration: "underline wavy #ef4444" }),
    text("dotted, 3px thick, offset 6px", { textDecoration: "underline dotted 3px #2563eb", textUnderlineOffset: 6 }),
    text("Skip ink: gjpqy", { textDecoration: "underline 2px", textDecorationSkipInk: "auto" }),
    text("No skip: gjpqy", { textDecoration: "underline 2px", textDecorationSkipInk: "none" }),
  ]),
  { width: 560, height: 240 },
);
// #endregion
save("decoration", decoration);

// #region effects
const effects = renderer.renderSync(
  page({ flexDirection: "column", gap: 10, fontSize: 40, fontWeight: 700, backgroundColor: "#f8fafc" }, [
    text("Drop shadow", { textShadow: "3px 3px 0 #f59e0b" }),
    text("Soft glow", { color: "#fff", textShadow: "0 0 8px #7c3aed, 0 0 2px #7c3aed" }),
    text("Outlined", { color: "#fff", WebkitTextStroke: "2px #111827" }),
    text("Fill + stroke", { WebkitTextFillColor: "#fde68a", WebkitTextStroke: "1.5px #92400e" }),
    text("Gradient text", { backgroundImage: "linear-gradient(90deg, #ec4899, #8b5cf6)", backgroundClip: "text", color: "transparent" }),
  ]),
  { width: 560, height: 320 },
);
// #endregion
save("effects", effects);

// #region transform
const transform = renderer.renderSync(
  page({ flexDirection: "column", gap: 4, fontSize: 20 }, [
    text("uppercase: đường phố hà nội", { textTransform: "uppercase" }),
    text("CAPITALIZE: every word gets a capital", { textTransform: "capitalize" }),
    text("LOWERCASE: ĐƯỜNG PHỐ", { textTransform: "lowercase" }),
  ]),
  { width: 560, height: 110 },
);
// #endregion
save("transform", transform);

// #region inline
// A container without `display` is inline (like a <span>), so it flows with the text around it.
const span = (style, children) => ({ type: "container", style, children });
const avatar = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><circle cx="10" cy="10" r="10" fill="#22c55e"/></svg>';
const inline = renderer.renderSync(
  page({ fontSize: 20 }, [
    box({ width: 520, lineHeight: 1.6 }, [
      text("Mix "),
      span({ fontWeight: 700 }, [text("bold")]),
      text(", "),
      span({ fontStyle: "italic", color: "#7c3aed" }, [text("italic")]),
      text(" and "),
      span({ backgroundColor: "#fef08a", padding: "0 4px", borderRadius: 4 }, [text("highlighted spans")]),
      text(" with an inline-block "),
      span({ display: "inline-block", padding: "0 8px", borderRadius: 999, backgroundColor: "#dbeafe", color: "#1d4ed8", fontSize: 14 }, [text("badge")]),
      text(", an inline image "),
      { type: "image", src: avatar, width: 20, height: 20, style: { verticalAlign: "middle" } },
      text(" and "),
      span({ fontSize: 12, verticalAlign: "super" }, [text("superscript")]),
      text(" text that wraps onto the next line."),
    ]),
  ]),
  { width: 560, height: 130 },
);
// #endregion
save("inline", inline);

// #region features
const features = renderer.renderSync(
  page({ flexDirection: "column", gap: 4, fontSize: 22 }, [
    text("Proportional 1111 / 8888"),
    text("tabular-nums 1111 / 8888", { fontVariantNumeric: "tabular-nums" }),
    text("'zero' 0 O 10 — 'ss01' 1 4 6 9", { fontFeatureSettings: "'zero', 'ss01'" }),
    text("Roboto ligatures: fi fl ffi", { fontFamily: "Roboto" }),
    text("no ligatures: fi fl ffi", { fontFamily: "Roboto", fontVariantLigatures: "none" }),
    text("kerning on: AV To Wa", { fontSize: 28 }),
    text("kerning off: AV To Wa", { fontSize: 28, fontKerning: "none" }),
  ]),
  { width: 560, height: 260 },
);
// #endregion
save("features", features);

// #region vietnamese
const vietnamese = renderer.renderSync(
  page({ flexDirection: "column", gap: 6, fontSize: 22 }, [
    text("Tiếng Việt có sáu thanh: ngang, huyền, sắc, hỏi, ngã, nặng.", { fontWeight: 700 }),
    box({ width: 520, lineHeight: 1.5, textWrap: "balance" }, [
      text("Phở bò Hà Nội, bánh mì Sài Gòn và cà phê sữa đá — những món ăn đường phố nổi tiếng nhất."),
    ]),
    // User input may arrive decomposed (NFD): normalise it to NFC before rendering.
    text("Nguyễn Thị Ánh".normalize("NFC"), { color: "#be123c" }),
  ]),
  { width: 560, height: 150 },
);
// #endregion
save("vietnamese", vietnamese);

const TF = "ref/takumi/assets/fonts";
if (existsSync(`${TF}/sil/scheherazade-new-v17-arabic-regular.woff2`) && existsSync(`${TF}/noto-sans/NotoSansTC-VariableFont_wght.woff2`)) {
  // #region scripts
  // Arabic (Scheherazade New) and Traditional Chinese (Noto Sans TC) WOFF2 fonts from
  // takumi's test assets (OFL). Registering them is enough: per-character fallback finds them.
  renderer.registerFont(readFileSync("ref/takumi/assets/fonts/sil/scheherazade-new-v17-arabic-regular.woff2"));
  renderer.registerFont(readFileSync("ref/takumi/assets/fonts/noto-sans/NotoSansTC-VariableFont_wght.woff2"));

  const scripts = page({ flexDirection: "column", gap: 6, fontSize: 24 }, [
    text("Mixed: Hello مرحبا بالعالم 123 world"),
    box({ direction: "rtl", backgroundColor: "#f1f5f9", padding: "0 8px" }, [text("RTL paragraph: مرحبا بالعالم (Hello) 2026")]),
    text("中文排版：繁體中文的換行規則與標點符號。"),
    box({ width: 300, backgroundColor: "#f1f5f9" }, [text("中文排版會在任何漢字之間換行，不需要空格。")]),
  ]);
  const scriptsPng = renderer.renderSync(scripts, { width: 560, height: 250 });
  // #endregion
  save("scripts", scriptsPng);

  // Same tree on standard (no bidi, default shaper): not shown as code.
  const std = await import("bm-engine/standard");
  const rs = new std.Renderer();
  for (const file of ["Inter-Regular", "Inter-SemiBold", "Inter-Bold", "Inter-Italic", "Roboto-Regular"]) rs.registerFont(readFileSync(`assets/fonts/${file}.ttf`));
  rs.registerFont(readFileSync(`${TF}/sil/scheherazade-new-v17-arabic-regular.woff2`));
  rs.registerFont(readFileSync(`${TF}/noto-sans/NotoSansTC-VariableFont_wght.woff2`));
  save("scripts-standard", rs.renderSync(scripts, { width: 560, height: 250 }));
} else console.log("skip: complex-script example (ref/takumi not present)");
