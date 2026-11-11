import { c, root, t } from "./_h.mjs";
const g = (bg, extra = {}) => c({ width: 340, height: 220, backgroundImage: bg, flexShrink: 0, borderRadius: 12, ...extra }, []);
const wrap = (children, bgc = "#f1f5f9") => root({ backgroundColor: bgc, padding: 30, gap: 24, flexWrap: "wrap", alignContent: "flex-start" }, children);
export default [
  { id: "lingrad-angles", feature: "linear-gradient", title: "Angles & directions", width: 1200, height: 630,
    node: wrap([
      g("linear-gradient(0deg, #ef4444, #3b82f6)"), g("linear-gradient(45deg, #ef4444, #3b82f6)"), g("linear-gradient(90deg, #ef4444, #3b82f6)"),
      g("linear-gradient(135deg, #ef4444, #3b82f6)"), g("linear-gradient(200deg, #ef4444, #3b82f6)"), g("linear-gradient(to right, #22c55e, #eab308)"),
      g("linear-gradient(to bottom right, #8b5cf6, #06b6d4)"), g("linear-gradient(to top left, #f97316, #111827)"), g("linear-gradient(#fff, #000)"),
    ]) },
  { id: "lingrad-multistop", feature: "linear-gradient", title: "Multi-stop with positions", width: 1200, height: 630,
    node: wrap([
      g("linear-gradient(90deg, #ef4444 0%, #eab308 25%, #22c55e 50%, #3b82f6 75%, #8b5cf6 100%)", { width: 1100, height: 120 }),
      g("linear-gradient(90deg, #111 0%, #111 30%, #f97316 30%, #f97316 60%, #fff 60%, #fff 100%)", { width: 1100, height: 120 }),
      g("linear-gradient(180deg, #06b6d4 10px, #3b82f6 120px, #8b5cf6 90%)", { width: 340, height: 250 }),
      g("linear-gradient(90deg, red, 20%, blue)", { width: 340, height: 250 }),
      g("repeating-linear-gradient(45deg, #111 0px, #111 10px, #fff 10px, #fff 20px)", { width: 340, height: 250 }),
    ]) },
  { id: "lingrad-alpha", feature: "linear-gradient", title: "Gradients with alpha over patterned bg", width: 1200, height: 630,
    node: root({ backgroundColor: "#fde68a", padding: 30, gap: 24, flexWrap: "wrap", alignContent: "flex-start",
      backgroundImage: "linear-gradient(90deg, #ef4444 0%, #ef4444 50%, #3b82f6 50%, #3b82f6 100%)" }, [
      g("linear-gradient(90deg, rgba(0,0,0,0), rgba(0,0,0,0.9))"), g("linear-gradient(180deg, #ffffff00, #ffffffff)"),
      g("linear-gradient(135deg, rgba(34,197,94,0.9), rgba(34,197,94,0))"), g("linear-gradient(to right, transparent, white)"),
      g("linear-gradient(0deg, rgba(0,0,0,0.8) 0%, rgba(0,0,0,0) 60%)"), g("linear-gradient(45deg, #ff000080, #0000ff80)"),
    ]) },
  { id: "lingrad-hero-small", feature: "linear-gradient", title: "Full-bleed hero gradient with text", width: 400, height: 300,
    node: root({ backgroundImage: "linear-gradient(135deg, #0ea5e9 0%, #6366f1 50%, #ec4899 100%)", alignItems: "center", justifyContent: "center" }, [
      t("Gradient", { fontSize: 48, fontWeight: 700, color: "#fff" })]) },
];
