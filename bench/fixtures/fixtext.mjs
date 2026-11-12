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
];

export default cases;
