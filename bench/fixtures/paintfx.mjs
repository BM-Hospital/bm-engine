// Phase-2 paint features: exact AA, border styles, outline, clip-path, mask, blend modes,
// background-clip:text, drop-shadow / backdrop-filter, text stroke and decorations.
import { c, col, t, root, rootCol, pal } from "./_h.mjs";
const W = 600, H = 200;
const white = { backgroundColor: "#fff", alignItems: "center", justifyContent: "space-around" };
const grad = "linear-gradient(90deg,#f97316,#7c3aed)";
const fx = [
  { id: "pfx-aa-shapes", feature: "aa-exact", title: "AA of circles, ellipses, thin rounded borders, fractional boxes", width: W, height: H,
    node: root({ ...white }, [
      c({ width: 90, height: 90, borderRadius: "50%", backgroundColor: "#2563eb" }),
      c({ width: 120, height: 70, borderRadius: "60px / 35px", backgroundColor: "#16a34a", border: "1px solid #052e16" }),
      c({ width: 80.5, height: 60.25, marginTop: 0.5, borderRadius: 7.5, backgroundColor: "#dc2626" }),
      c({ width: 90, height: 90, borderRadius: "24px 4px 40px 12px", border: "3px solid #7c3aed", backgroundColor: "#ede9fe" }),
    ]) },
  { id: "pfx-aa-text", feature: "aa-exact", title: "glyph AA: sizes, fake bold, fake italic", width: W, height: H,
    node: rootCol({ backgroundColor: "#fff", padding: 16, gap: 6 }, [
      t("Hamburgefonstiv 0123456789", { fontSize: 13, color: "#111" }),
      t("Sphinx of black quartz, judge my vow", { fontSize: 22.5, color: "#1d4ed8" }),
      t("Synthetic bold Noto", { fontFamily: "Noto Sans", fontSize: 30, fontWeight: 900, color: "#111" }),
      t("Synthetic italic Roboto", { fontFamily: "Roboto", fontSize: 30, fontStyle: "italic", fontWeight: 300, color: "#b91c1c" }),
    ]) },
  { id: "pfx-border-dashed", feature: "dashed-border", title: "dashed borders: widths, radius, per side", width: W, height: H,
    node: root({ ...white }, [
      c({ width: 120, height: 90, border: "4px dashed #2563eb" }),
      c({ width: 120, height: 90, border: "2px dashed #111", borderRadius: 14 }),
      c({ width: 120, height: 90, border: "6px dashed #dc2626", borderRadius: 30 }),
      c({ width: 120, height: 90, borderTop: "5px dashed #16a34a", borderBottom: "5px dashed #16a34a", backgroundColor: "#f0fdf4" }),
    ]) },
  { id: "pfx-border-dotted", feature: "dotted-border", title: "dotted borders: square dots <= 3px, round dots, radius", width: W, height: H,
    node: root({ ...white }, [
      c({ width: 120, height: 90, border: "2px dotted #111" }),
      c({ width: 120, height: 90, border: "6px dotted #2563eb" }),
      c({ width: 120, height: 90, border: "8px dotted #dc2626", borderRadius: 24 }),
      c({ width: 120, height: 90, border: "3px dotted #16a34a", borderRadius: 12 }),
    ]) },
  { id: "pfx-border-double-3d", feature: "double-3d-border", title: "double / groove / ridge / inset / outset", width: W, height: H,
    node: root({ ...white, backgroundColor: "#e5e7eb" }, [
      c({ width: 90, height: 90, border: "9px double #1d4ed8" }),
      c({ width: 90, height: 90, border: "10px groove #f59e0b" }),
      c({ width: 90, height: 90, border: "10px ridge #10b981" }),
      c({ width: 90, height: 90, border: "8px inset #ef4444" }),
      c({ width: 90, height: 90, border: "8px outset #8b5cf6" }),
    ]) },
  { id: "pfx-border-mixed", feature: "mixed-border", title: "per-side styles / colours / widths with mitres, double with radius", width: W, height: H,
    node: root({ ...white }, [
      c({ width: 120, height: 90, borderTop: "10px solid #ef4444", borderRight: "10px dashed #3b82f6", borderBottom: "10px double #22c55e", borderLeft: "10px dotted #a855f7" }),
      c({ width: 120, height: 90, border: "12px double #0f766e", borderRadius: 20 }),
      c({ width: 120, height: 90, borderWidth: "4px 12px 8px 2px", borderStyle: "solid", borderColor: "#ef4444 #3b82f6 #22c55e #eab308", borderRadius: 16 }),
      c({ width: 120, height: 90, border: "8px solid rgba(37,99,235,0.5)", borderTopColor: "rgba(220,38,38,0.5)" }),
    ]) },
  { id: "pfx-outline", feature: "outline", title: "outline: offset, radius, styles", width: W, height: H,
    node: root({ ...white }, [
      c({ width: 90, height: 70, backgroundColor: "#dbeafe", outline: "3px solid #1d4ed8" }),
      c({ width: 90, height: 70, backgroundColor: "#dcfce7", outline: "2px dashed #15803d", outlineOffset: 4, borderRadius: 10 }),
      c({ width: 90, height: 70, backgroundColor: "#fee2e2", outline: "6px double #b91c1c", outlineOffset: 2, borderRadius: 20 }),
      c({ width: 90, height: 70, backgroundColor: "#fef9c3", border: "2px solid #111", outline: "4px dotted #a16207", outlineOffset: -10 }),
    ]) },
  { id: "pfx-clip-path-shapes", feature: "clip-path", title: "clip-path: circle / ellipse / inset round / polygon / path", width: W, height: H,
    node: root({ ...white }, [
      c({ width: 100, height: 100, backgroundImage: grad, clipPath: "circle(45% at 50% 50%)" }),
      c({ width: 100, height: 100, backgroundImage: grad, clipPath: "ellipse(50% 30% at 50% 50%)" }),
      c({ width: 100, height: 100, backgroundImage: grad, clipPath: "inset(10px 20px 15px 5px round 12px)" }),
      c({ width: 100, height: 100, backgroundImage: grad, clipPath: "polygon(50% 0%, 61% 35%, 98% 35%, 68% 57%, 79% 91%, 50% 70%, 21% 91%, 32% 57%, 2% 35%, 39% 35%)" }),
      c({ width: 100, height: 100, backgroundImage: grad, clipPath: "path('M10 10 H 90 V 60 Q 50 110 10 60 Z')" }),
    ]) },
  { id: "pfx-mask-gradient", feature: "mask", title: "mask-image: linear / radial gradient, sized + no-repeat", width: W, height: H,
    node: root({ ...white, backgroundColor: "#e2e8f0" }, [
      c({ width: 150, height: 120, backgroundImage: grad, maskImage: "linear-gradient(to right, #000, transparent)" }),
      c({ width: 150, height: 120, backgroundColor: "#0f172a", borderRadius: 24, maskImage: "radial-gradient(circle at center, #000 40%, transparent 70%)" }),
      c({ width: 150, height: 120, backgroundImage: grad, maskImage: "linear-gradient(#000, #000)", maskSize: "60% 50%", maskPosition: "center", maskRepeat: "no-repeat" }),
    ]) },
  { id: "pfx-bg-clip-text", feature: "bg-clip-text", title: "background-clip: text with gradient, plus text-fill-color", width: W, height: H,
    node: rootCol({ backgroundColor: "#0f172a", alignItems: "center", justifyContent: "center", gap: 8 }, [
      t("Gradient headline", { fontSize: 54, fontWeight: 800, color: "transparent", backgroundImage: "linear-gradient(90deg,#f97316,#38bdf8)", backgroundClip: "text" }),
      t("Half transparent fill", { fontSize: 36, color: "rgba(255,255,255,0.35)", backgroundImage: "linear-gradient(180deg,#22c55e,#eab308)", backgroundClip: "text" }),
    ]) },
  { id: "pfx-mix-blend", feature: "mix-blend", title: "mix-blend-mode: multiply / screen / overlay / difference + isolation", width: W, height: H,
    node: root({ backgroundImage: "linear-gradient(90deg,#fde047,#38bdf8)", alignItems: "center", justifyContent: "space-around" },
      ["multiply", "screen", "overlay", "difference", "hard-light"].map((m) => c({ width: 90, height: 120, borderRadius: 12, backgroundImage: "linear-gradient(180deg,#ef4444,#3b82f6)", mixBlendMode: m }))) },
  { id: "pfx-bg-blend", feature: "bg-blend", title: "background-blend-mode between layers and colour", width: W, height: H,
    node: root({ ...white }, ["multiply", "screen", "difference"].map((m) => c({ width: 150, height: 120, backgroundColor: "#f59e0b", backgroundImage: "linear-gradient(90deg,#2563eb,#fff), radial-gradient(circle,#ef4444,#111)", backgroundBlendMode: m }))) },
  { id: "pfx-drop-shadow", feature: "drop-shadow", title: "filter: drop-shadow() on shapes and text", width: W, height: H,
    node: root({ ...white }, [
      c({ width: 110, height: 110, borderRadius: "50%", backgroundColor: "#2563eb", filter: "drop-shadow(6px 8px 6px rgba(0,0,0,0.5))" }),
      c({ width: 110, height: 90, backgroundImage: grad, clipPath: "polygon(50% 0%, 100% 100%, 0% 100%)", filter: "drop-shadow(0px 4px 3px #111)" }),
      t("Shadow", { fontSize: 44, fontWeight: 700, color: "#dc2626", filter: "drop-shadow(3px 3px 0px #111)" }),
    ]) },
  { id: "pfx-backdrop-filter", feature: "backdrop-filter", title: "backdrop-filter: blur / grayscale over a gradient", width: W, height: H,
    node: root({ backgroundImage: "linear-gradient(90deg,#ef4444,#eab308,#22c55e,#3b82f6)", alignItems: "center", justifyContent: "space-around" }, [
      c({ width: 80, height: 200, backgroundColor: "#111", position: "absolute", left: 120, top: 0 }),
      c({ width: 200, height: 120, borderRadius: 20, backgroundColor: "rgba(255,255,255,0.25)", backdropFilter: "blur(8px)" }),
      c({ width: 200, height: 120, backgroundColor: "rgba(0,0,0,0.1)", backdropFilter: "grayscale(1)" }),
    ]) },
  { id: "pfx-text-stroke", feature: "text-stroke", title: "-webkit-text-stroke, paint-order, text-fill-color", width: W, height: H,
    node: rootCol({ backgroundColor: "#fff", alignItems: "center", justifyContent: "center", gap: 4 }, [
      t("Stroked text", { fontSize: 48, fontWeight: 700, color: "#fde047", WebkitTextStroke: "2px #111" }),
      t("Stroke under fill", { fontSize: 48, fontWeight: 700, color: "#2563eb", WebkitTextStroke: "6px #bfdbfe", paintOrder: "stroke" }),
      t("Fill colour", { fontSize: 30, color: "#111", WebkitTextFillColor: "#16a34a" }),
    ]) },
  { id: "pfx-text-decoration", feature: "text-decoration", title: "underline / overline / line-through; styles; thickness; offset; skip-ink", width: W, height: 260,
    node: rootCol({ backgroundColor: "#fff", padding: 14, gap: 6 }, [
      t("Typography jumping quickly (solid)", { fontSize: 24, color: "#111", textDecoration: "underline" }),
      t("Double gypsy underline", { fontSize: 24, color: "#111", textDecorationLine: "underline", textDecorationStyle: "double", textDecorationColor: "#dc2626" }),
      t("Dotted and dashed query", { fontSize: 24, color: "#111", textDecorationLine: "underline overline", textDecorationStyle: "dotted", textDecorationColor: "#2563eb" }),
      t("Dashed line-through style", { fontSize: 24, color: "#111", textDecorationLine: "line-through underline", textDecorationStyle: "dashed", textDecorationThickness: 3 }),
      t("Wavy spelling mistake", { fontSize: 24, color: "#111", textDecorationLine: "underline", textDecorationStyle: "wavy", textDecorationColor: "#dc2626" }),
      t("Big gypsy skip ink", { fontSize: 44, color: "#111", textDecorationLine: "underline", textDecorationThickness: 4, textUnderlineOffset: 2 }),
    ]) },
  { id: "pfx-visibility", feature: "visibility", title: "visibility: hidden parent with a visible child", width: W, height: H,
    node: root({ ...white }, [
      c({ width: 200, height: 120, backgroundColor: "#ef4444", border: "4px solid #111", visibility: "hidden", alignItems: "center", justifyContent: "center" }, [
        c({ width: 80, height: 60, backgroundColor: "#22c55e", visibility: "visible" }), t("hidden text", { fontSize: 20, color: "#111" })]),
      c({ width: 120, height: 120, backgroundColor: pal[5] }),
    ]) },
  { id: "pfx-opacity-layers", feature: "opacity", title: "opacity groups over gradients (float source-over)", width: W, height: H,
    node: root({ backgroundImage: "linear-gradient(90deg,#fff,#0f172a)", alignItems: "center", justifyContent: "space-around" },
      [0.15, 0.4, 0.5, 0.75, 0.9].map((o) => c({ width: 90, height: 110, borderRadius: 16, backgroundImage: grad, border: "3px solid #111", opacity: o }, [t("Aa", { fontSize: 40, color: "#fff" })]))) },
];
export default fx;
