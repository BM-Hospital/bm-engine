// Features takumi supports that bm-render does NOT implement (yet). They are part of the suite on
// purpose so the report shows the gaps honestly instead of only the cases we handle.
import { c, col, t, root, rootCol } from "./_h.mjs";
const F = "known-gaps";
const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="45" fill="#f97316"/><path d="M30 50 L45 65 L72 35" stroke="#fff" stroke-width="8" fill="none"/></svg>`;
const gaps = [
  { id: "fx-text-shadow", feature: "text-shadow", title: "text-shadow (blurred)", width: 600, height: 200,
    node: root({ backgroundColor: "#0f172a", alignItems: "center", justifyContent: "center" }, [t("Shadowed text", { fontSize: 56, color: "#fff", textShadow: "0 4px 12px rgba(56,189,248,0.9)" })]) },
  { id: "gap-dashed-dotted-border", feature: F, title: "dashed / dotted / double borders", width: 600, height: 200,
    node: root({ backgroundColor: "#fff", alignItems: "center", justifyContent: "space-around" }, [
      c({ width: 150, height: 100, border: "6px dashed #2563eb" }), c({ width: 150, height: 100, border: "6px dotted #dc2626", borderRadius: 16 }), c({ width: 150, height: 100, border: "9px double #16a34a" })]) },
  { id: "fx-filter-blur-grayscale", feature: "filter", title: "filter: blur() / grayscale()", width: 600, height: 200,
    node: root({ backgroundColor: "#fff", alignItems: "center", justifyContent: "space-around" }, [
      c({ width: 140, height: 100, backgroundImage: "linear-gradient(90deg,#ef4444,#3b82f6)", filter: "blur(6px)" }), c({ width: 140, height: 100, backgroundImage: "linear-gradient(90deg,#ef4444,#3b82f6)", filter: "grayscale(1)" })]) },
  { id: "gap-tailwind-tw", feature: F, title: "Tailwind `tw` prop", width: 600, height: 200,
    node: { type: "container", tw: "flex w-full h-full items-center justify-center bg-slate-900", children: [{ type: "container", tw: "flex p-8 bg-blue-500 rounded-2xl", children: [t("tw classes", { fontSize: 36, color: "#fff" })] }] } },
  { id: "gap-oklch-color", feature: F, title: "oklch() / color-mix() colours", width: 600, height: 200,
    node: root({ backgroundColor: "oklch(0.7 0.15 250)", alignItems: "center", justifyContent: "center" }, [c({ width: 200, height: 100, backgroundColor: "color-mix(in srgb, red 40%, blue)" })]) },
  { id: "gap-svg-image", feature: F, title: "SVG image source", width: 600, height: 200,
    node: root({ backgroundColor: "#fff", alignItems: "center", justifyContent: "center" }, [{ type: "image", src: svg, width: 160, height: 160, style: {} }]) },
  { id: "gap-inline-box-decoration", feature: F, title: "inline spans with their own background / padding (matches here only because takumi also skips it for bare text nodes)", width: 600, height: 200,
    node: rootCol({ backgroundColor: "#fff", padding: 32 }, [{ type: "container", style: { display: "block", fontFamily: "Inter", fontSize: 30, color: "#111" }, children: [
      { type: "text", text: "Inline " }, { type: "text", text: "highlighted", style: { backgroundColor: "#fde047", padding: "2px 8px", borderRadius: 6 } }, { type: "text", text: " words inside a paragraph that wraps onto a second line." }] }]) },
  { id: "gap-mix-blend-mode", feature: F, title: "mix-blend-mode", width: 600, height: 200,
    node: root({ backgroundColor: "#fff", alignItems: "center", justifyContent: "center" }, [c({ width: 160, height: 160, borderRadius: 80, backgroundColor: "#ef4444" }), c({ width: 160, height: 160, borderRadius: 80, backgroundColor: "#3b82f6", marginLeft: -60, mixBlendMode: "multiply" })]) },
  { id: "gap-clip-path", feature: F, title: "clip-path", width: 600, height: 200,
    node: root({ backgroundColor: "#fff", alignItems: "center", justifyContent: "center" }, [c({ width: 300, height: 160, backgroundImage: "linear-gradient(90deg,#f97316,#7c3aed)", clipPath: "polygon(50% 0%, 100% 50%, 50% 100%, 0% 50%)" })]) },
  { id: "gap-background-clip-text", feature: F, title: "background-clip: text (gradient text)", width: 600, height: 200,
    node: root({ backgroundColor: "#0f172a", alignItems: "center", justifyContent: "center" }, [t("Gradient text", { fontSize: 64, fontWeight: 700, color: "transparent", backgroundImage: "linear-gradient(90deg,#f97316,#38bdf8)", backgroundClip: "text" })]) },
  { id: "gap-text-wrap-balance", feature: F, title: "text-wrap: balance", width: 600, height: 200,
    node: rootCol({ backgroundColor: "#fff", padding: 32 }, [t("A headline that should be balanced across its lines nicely", { fontSize: 34, textWrap: "balance", color: "#111" })]) },
];
export default gaps;
