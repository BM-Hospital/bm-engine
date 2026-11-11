import { c, col, t, root, lorem } from "./_h.mjs";
const para = (style, text = lorem) => c({ width: 340, backgroundColor: "#fff", padding: 12, flexShrink: 0, border: "1px solid #cbd5e1" }, [t(text, { fontSize: 18, color: "#0f172a", ...style })]);
export default [
  { id: "text-single-sizes", feature: "text-single-line", title: "Single line at 12/16/24/48/96", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 30, flexDirection: "column", gap: 8 }, [12, 16, 24, 48, 96].map((s) => t(`Hamburgefonstiv ${s}px`, { fontSize: s, color: "#111827" }))) },
  { id: "text-single-colors-small", feature: "text-single-line", title: "Light on dark + colored small text", width: 400, height: 300,
    node: root({ backgroundColor: "#111827", padding: 20, flexDirection: "column", gap: 6 }, [
      t("White on dark 14px", { fontSize: 14, color: "#fff" }), t("Amber 20px", { fontSize: 20, color: "#fbbf24" }),
      t("Semi-transparent 28px", { fontSize: 28, color: "rgba(255,255,255,0.5)" }), t("Pink 36px", { fontSize: 36, color: "#f472b6" }),
    ]) },
  { id: "text-single-fonts", feature: "text-single-line", title: "Same line in Inter / Noto Sans / Roboto", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 40, flexDirection: "column", gap: 20 }, ["Inter", "Noto Sans", "Roboto"].map((f) => t(`${f}: Quick brown fox 0123456789 @#&`, { fontFamily: f, fontSize: 52, color: "#111" }))) },
  { id: "text-paragraph-wrap", feature: "text-paragraph", title: "Paragraph wrapping, left/center/right, justify", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 24, gap: 16, flexWrap: "wrap", alignContent: "flex-start" }, [
      para({ textAlign: "left" }), para({ textAlign: "center" }), para({ textAlign: "right" }), para({ textAlign: "justify" }),
    ]) },
  { id: "text-paragraph-lineheight", feature: "text-paragraph", title: "lineHeight variants", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 24, gap: 16, flexWrap: "wrap", alignContent: "flex-start" }, [
      para({ lineHeight: 1 }), para({ lineHeight: 1.2 }), para({ lineHeight: 1.6 }), para({ lineHeight: "36px" }), para({ lineHeight: 2.2, fontSize: 16 }),
    ]) },
  { id: "text-paragraph-letterspacing", feature: "text-paragraph", title: "letterSpacing & wordSpacing", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 24, gap: 16, flexWrap: "wrap", alignContent: "flex-start" }, [
      para({ letterSpacing: -1 }), para({ letterSpacing: 0 }), para({ letterSpacing: 2 }), para({ letterSpacing: "0.1em", textTransform: "uppercase" }), para({ wordSpacing: 10 }),
    ]) },
  { id: "text-paragraph-small", feature: "text-paragraph", title: "Small centered paragraph", width: 400, height: 300,
    node: root({ backgroundColor: "#fff", padding: 24, alignItems: "center" }, [t(lorem, { fontSize: 20, textAlign: "center", lineHeight: 1.4, color: "#111" })]) },
  { id: "text-long-wrap", feature: "text-paragraph", title: "Long text with long words / forced breaks", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 30, gap: 24 }, [
      c({ width: 340, backgroundColor: "#fef3c7" }, [t("Supercalifragilisticexpialidocious_pneumonoultramicroscopicsilicovolcanoconiosis is a very long word", { fontSize: 24, color: "#111", overflowWrap: "anywhere" })]),
      c({ width: 340, backgroundColor: "#dbeafe" }, [t("Line one\nLine two after newline\n\nLine four", { fontSize: 24, color: "#111", whiteSpace: "pre-wrap" })]),
      c({ width: 340, backgroundColor: "#dcfce7" }, [t("web-based, state-of-the-art, hyphen-separated words wrap at hyphens", { fontSize: 24, color: "#111" })]),
    ]) },
  { id: "fonts-weights-italic", feature: "fonts", title: "Weights 400/600/700 and italic", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 40, flexDirection: "column", gap: 10 }, [
      t("Inter Regular 400 — Sphinx of black quartz", { fontSize: 40, fontWeight: 400 }), t("Inter SemiBold 600 — Sphinx of black quartz", { fontSize: 40, fontWeight: 600 }),
      t("Inter Bold 700 — Sphinx of black quartz", { fontSize: 40, fontWeight: 700 }), t("Inter Italic — Sphinx of black quartz", { fontSize: 40, fontStyle: "italic" }),
      t("Roboto Italic — Sphinx of black quartz", { fontFamily: "Roboto", fontSize: 40, fontStyle: "italic" }), t("Noto Sans Bold — Sphinx of black quartz", { fontFamily: "Noto Sans", fontSize: 40, fontWeight: 700 }),
      t("Inter weight 500 (nearest match)", { fontSize: 40, fontWeight: 500 }), t("Inter weight 900 (nearest match)", { fontSize: 40, fontWeight: 900 }),
    ]) },
  { id: "fonts-mixed-inline", feature: "fonts", title: "Multiple families in one image + family fallback list", width: 1200, height: 630,
    node: root({ backgroundColor: "#0f172a", padding: 40, gap: 30, flexDirection: "column" }, [
      c({ gap: 24, alignItems: "baseline" }, [t("Inter", { fontSize: 72, fontWeight: 700, color: "#f8fafc" }), t("Noto Sans", { fontFamily: "Noto Sans", fontSize: 72, fontWeight: 700, color: "#38bdf8" }), t("Roboto", { fontFamily: "Roboto", fontSize: 72, fontWeight: 700, color: "#f472b6" })]),
      t("Fallback chain: Missing Font, Roboto, Inter", { fontFamily: "Missing Font, Roboto, Inter", fontSize: 40, color: "#e2e8f0" }),
      t("Quoted family: 'Noto Sans', sans-serif", { fontFamily: "'Noto Sans', sans-serif", fontSize: 40, color: "#e2e8f0" }),
      t("Italic bold Roboto 700 italic (synthetic)", { fontFamily: "Roboto", fontSize: 40, fontWeight: 700, fontStyle: "italic", color: "#fde047" }),
    ]) },
  { id: "text-vietnamese", feature: "text-i18n", title: "Vietnamese text (Inter / Noto Sans / Roboto)", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 40, flexDirection: "column", gap: 14 }, [
      t("Tiếng Việt: Xin chào thế giới! Đường đi khó, không khó vì ngăn sông cách núi.", { fontSize: 36, color: "#111", fontFamily: "Inter" }),
      t("Ươm mầm tri thức — Nguyễn Thị Minh Khai, Hà Nội & TP. Hồ Chí Minh", { fontSize: 36, color: "#111", fontFamily: "Noto Sans", fontWeight: 700 }),
      t("ẮẰẲẴẶ ẤẦẨẪẬ ỀỂỄỆ ỒỔỖỘ ỜỞỠỢ ỪỬỮỰ ỲỶỸỴ — ắằẳẵặ ấầẩẫậ ềểễệ ồổỗộ ờởỡợ ừửữự ỳỷỹỵ", { fontSize: 30, color: "#334155", fontFamily: "Roboto" }),
    ]) },
  { id: "text-accented-latin", feature: "text-i18n", title: "Accented Latin, symbols, punctuation", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff7ed", padding: 40, flexDirection: "column", gap: 12 }, [
      t("Café déjà vu — naïve façade, Zürich, Škoda, Łódź, Ærøskøbing, İstanbul, Ñandú", { fontSize: 34, color: "#111" }),
      t("Ünïcödé: ÀÁÂÃÄÅ ÈÉÊË ÌÍÎÏ ÒÓÔÕÖ ÙÚÛÜ Ýß àáâãäå èéêë ìíîï òóôõö ùúûü ÿ", { fontSize: 30, color: "#111", fontFamily: "Noto Sans" }),
      t("“Quotes” ‘single’ — en–dash … © ® ™ € £ ¥ ½ ± × ÷ → ← ↑ ↓ • ★", { fontSize: 30, color: "#111", fontFamily: "Roboto" }),
      t("Ελληνικά Привет мир — Greek & Cyrillic coverage", { fontSize: 30, color: "#111", fontFamily: "Noto Sans" }),
    ]) },
  { id: "text-ellipsis-nowrap", feature: "text-truncation", title: "textOverflow ellipsis + nowrap", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 30, flexDirection: "column", gap: 16 }, [
      c({ width: 500, backgroundColor: "#fff", padding: 10 }, [t("A single line title that is far too long to fit inside this box and must be truncated", { fontSize: 28, color: "#111", whiteSpace: "nowrap", textOverflow: "ellipsis", overflow: "hidden", flex: 1 })]),
      c({ width: 300, backgroundColor: "#fff", padding: 10 }, [t("Short", { fontSize: 28, color: "#111", whiteSpace: "nowrap", textOverflow: "ellipsis", overflow: "hidden" })]),
      c({ width: 700, backgroundColor: "#fff", padding: 10 }, [t("Tiếng Việt rất dài cần được cắt bớt bằng dấu ba chấm ở cuối dòng này nhé bạn", { fontSize: 28, color: "#111", whiteSpace: "nowrap", textOverflow: "ellipsis", overflow: "hidden", flex: 1 })]),
    ]) },
  { id: "text-lineclamp", feature: "text-truncation", title: "lineClamp 1/2/3", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 24, gap: 16, flexWrap: "wrap", alignContent: "flex-start" },
      [1, 2, 3, 4].map((n) => c({ width: 340, backgroundColor: "#fff", padding: 12, flexShrink: 0 }, [t(lorem + " " + lorem, { fontSize: 20, color: "#111", lineClamp: n })]))) },
  { id: "text-lineclamp-small", feature: "text-truncation", title: "lineClamp 2 in a small card", width: 400, height: 300,
    node: root({ backgroundColor: "#fff", padding: 20 }, [c({ width: 240, height: 120, padding: 8, border: "1px solid #94a3b8" }, [t(lorem, { fontSize: 18, lineClamp: 2, color: "#111" })])]) },
];
