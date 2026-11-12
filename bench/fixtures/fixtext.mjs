// Text shaping / painting fixes (branch fix-text): custom text-overflow markers, line-clamp
// block-ellipsis, paint-order on stroked text, small caps, emoji clusters.
// Cases that need a font outside the repo (ref/ test fonts, see lib/fonts.mjs OPTIONAL_FONTS) are only
// listed when that font is present.
import { c, t, root } from "./_h.mjs";
import { hasOptionalFont } from "../lib/fonts.mjs";

const long = "The quick brown fox jumps over the lazy dog again";
// text-overflow lives on the text node itself (not inherited); overflow must clip
const over = (textOverflow, extra = {}, text = long) =>
  t(text, { width: 300, backgroundColor: "#eef2ff", overflow: "hidden", whiteSpace: "nowrap", textOverflow, fontSize: 24, color: "#111", ...extra });
const clamp = (extra) => t(long + " " + long, { width: 300, backgroundColor: "#eef2ff", overflow: "hidden", fontSize: 24, color: "#111", ...extra });
const stroked = (extra) => t("Stroke", { fontSize: 72, fontWeight: 700, color: "#fde047", WebkitTextStroke: "8px #1d4ed8", ...extra });
const small = (fontVariantCaps, text = "Hello World 123 ßàé!") =>
  ["Inter", "Noto Sans", "Roboto"].map((f) => t(text, { fontFamily: f, fontSize: 40, color: "#111", fontVariantCaps }));

const cases = [
  { id: "fix-text-overflow-string", feature: "text-overflow", title: "text-overflow: custom string markers (\" »\", \"…more\", \"--\"), ellipsis, clip", width: 400, height: 230,
    node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 8 }, [over('" »"'), over('"…more"'), over('"--"'), over("ellipsis"), over("clip")]) },
  { id: "fix-text-overflow-string-fallback", feature: "text-overflow", title: "text-overflow string: fallback glyphs, other family, larger size", width: 400, height: 200,
    node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 8 }, [over('" Việt ✓"'), over('"→"', { fontFamily: "Roboto" }), over('" »"', { fontSize: 40 })]) },
  { id: "fix-text-overflow-string-rtl", feature: "text-overflow", title: "text-overflow in direction: rtl: marker on the left (mirrored), LTR text keeps its end", width: 400, height: 160,
    node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 8 }, [over('" »"', { direction: "rtl" }), over('"<<"', { direction: "rtl" }), over("ellipsis", { direction: "rtl" })]) },
  { id: "fix-text-line-clamp-marker", feature: "text-overflow", title: "line-clamp: … even with a text-overflow string; line-clamp: 2 \" >\" block-ellipsis", width: 400, height: 300,
    node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 8 }, [
      clamp({ lineClamp: 2, textOverflow: '" »"' }), clamp({ display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: 2, textOverflow: '" »"' }),
      clamp({ lineClamp: '2 " >"' }),
    ]) },
  { id: "fix-text-paint-order", feature: "text-stroke", title: "paint-order on stroked text (takumi 2.20 ignores it: stroke over fill)", width: 500, height: 300,
    node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 8 }, [stroked({}), stroked({ paintOrder: "stroke fill" }), stroked({ paintOrder: "stroke" })]) },
  { id: "fix-text-small-caps", feature: "font-variant", title: "small-caps: synthesized in Inter (no smcp, uppercase at round(0.7 size), ß -> SS), font smcp in Noto Sans / Roboto", width: 700, height: 200,
    node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 4 }, small("small-caps")) },
  { id: "fix-text-all-small-caps", feature: "font-variant", title: "all-small-caps (capitals shrink too) and fontVariant shorthand", width: 700, height: 260,
    node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 4 }, [...small("all-small-caps"), t("fontVariant: small-caps — Việt Nam", { fontSize: 32, color: "#334155", fontVariant: "small-caps" })]) },
  { id: "fix-text-petite-unicase-caps", feature: "font-variant", title: "petite-caps / unicase: smcp fallback or synthesis; font-synthesis: none", width: 700, height: 420,
    node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 4 }, [...small("petite-caps"), ...small("unicase"),
      t("No synthesis: Hello", { fontSize: 32, color: "#111", fontVariantCaps: "small-caps", fontSynthesis: "none" })]) },
];

// emoji sequences (Twemoji Mozilla COLR from the takumi clone; FIXTEXT_EMOJI="Noto Color Emoji" for the CBDT
// font, whose bitmap scaling differs slightly from takumi): only listed when the font is present
const EMOJI = process.env.FIXTEXT_EMOJI || "Twemoji Mozilla";
if (hasOptionalFont(EMOJI)) {
  const EF = ["Inter", EMOJI];
  const em = (text, extra = {}) => t(text, { fontFamily: "Inter", fontSize: 32, color: "#111", ...extra });
  cases.push(
    { id: "fix-text-emoji-zwj", feature: "emoji", title: "ZWJ sequences shape as one glyph (GSUB ligature with ZWJ components)", width: 500, height: 120, fonts: EF,
      node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 6 }, [em("ZWJ 👩‍💻 👨‍👩‍👧")]) },
    { id: "fix-text-emoji-flags-skin", feature: "emoji", title: "regional-indicator pair, tag-sequence flag, skin-tone modifier", width: 500, height: 120, fonts: EF,
      node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 6 }, [em("🇻🇳 🏴󠁧󠁢󠁥󠁮󠁧󠁿 👍🏽")]) },
    { id: "fix-text-emoji-keycap-vs", feature: "emoji", title: "keycap with VS16 (emoji) / without (text + .notdef, as takumi), VS16 / VS15 heart", width: 500, height: 120, fonts: EF,
      node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 6 }, [em("Keys 1️⃣ 1⃣ ❤️ ❤︎")]) },
    { id: "fix-text-emoji-spacing", feature: "emoji", title: "letter-spacing goes after whole emoji clusters", width: 500, height: 120, fonts: EF,
      node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 6 }, [em("a👩‍💻b🇻🇳c👍🏽d", { letterSpacing: 8 })]) },
    { id: "fix-text-emoji-wrap", feature: "emoji", title: "wrapping never splits an emoji sequence", width: 300, height: 160, fonts: EF,
      node: root({ backgroundColor: "#fff", padding: 10, flexDirection: "column", gap: 6 }, [em("🇻🇳👩‍💻👍🏽❤️", { width: 70, fontSize: 24 })]) },
  );
}

export default cases;
