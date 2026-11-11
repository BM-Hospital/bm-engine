import { c, root } from "./_h.mjs";
const g = (bg, extra = {}) => c({ width: 340, height: 220, backgroundImage: bg, flexShrink: 0, borderRadius: 12, ...extra }, []);
export default [
  { id: "radial-shapes", feature: "radial-gradient", title: "circle / ellipse, closest/farthest-side", width: 1200, height: 630,
    node: root({ backgroundColor: "#0f172a", padding: 30, gap: 24, flexWrap: "wrap", alignContent: "flex-start" }, [
      g("radial-gradient(circle, #fde047, #ea580c)"), g("radial-gradient(ellipse, #fde047, #ea580c)"),
      g("radial-gradient(circle closest-side, #a78bfa, #1e1b4b)"), g("radial-gradient(ellipse farthest-corner, #34d399, #064e3b)"),
      g("radial-gradient(circle 80px, #f472b6, #831843)"), g("radial-gradient(#fff 0%, #000 100%)"),
    ]) },
  { id: "radial-at-position", feature: "radial-gradient", title: "at position (keywords, %, px)", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 30, gap: 24, flexWrap: "wrap", alignContent: "flex-start" }, [
      g("radial-gradient(circle at top left, #ef4444, #fff)"), g("radial-gradient(circle at 100% 100%, #3b82f6, #fff)"),
      g("radial-gradient(ellipse at 30% 70%, #22c55e, #111)"), g("radial-gradient(circle at 20px 40px, #f97316, transparent 150px)"),
      g("radial-gradient(circle at center, #ec4899 0%, #8b5cf6 40%, #0ea5e9 80%)"), g("radial-gradient(circle at 50% 120%, rgba(255,255,255,0.9), rgba(0,0,0,0.1))", { backgroundColor: "#334155" }),
    ]) },
  { id: "radial-spotlight-small", feature: "radial-gradient", title: "Spotlight vignette", width: 400, height: 300,
    node: root({ backgroundImage: "radial-gradient(circle at 50% 40%, #fef3c7 0%, #f59e0b 30%, #1c1917 85%)" }, []) },
];
