import { c, root } from "./_h.mjs";
const F = "box-shadow";
const b = (shadow, extra = {}) => c({ width: 220, height: 150, backgroundColor: "#ffffff", borderRadius: 16, boxShadow: shadow, flexShrink: 0, ...extra }, []);
export default [
  { id: "shadow-offset-blur", feature: F, title: "Offset + blur", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 60, gap: 60, flexWrap: "wrap", alignContent: "flex-start" }, [
      b("0 4px 6px rgba(0,0,0,0.2)"), b("0 10px 30px rgba(0,0,0,0.3)"), b("10px 10px 0 rgba(0,0,0,0.8)"),
      b("-12px 16px 24px rgba(59,130,246,0.6)"), b("0 0 40px rgba(236,72,153,0.8)"), b("0 20px 60px #00000040", { borderRadius: 0 }),
    ]) },
  { id: "shadow-spread-multi", feature: F, title: "Spread and multiple shadows", width: 1200, height: 630,
    node: root({ backgroundColor: "#e2e8f0", padding: 70, gap: 70, flexWrap: "wrap", alignContent: "flex-start" }, [
      b("0 0 0 8px rgba(59,130,246,0.5)"), b("0 0 0 4px #111, 0 0 0 12px #f97316, 0 0 0 20px #22c55e"),
      b("0 8px 20px -6px rgba(0,0,0,0.5)"), b("0 2px 4px rgba(0,0,0,.3), 0 12px 24px rgba(0,0,0,.2), 0 30px 60px rgba(0,0,0,.15)"),
      b("6px 6px 0 -2px #ef4444, 12px 12px 0 -4px #3b82f6"), b("0 0 30px 10px rgba(250,204,21,0.7)", { borderRadius: 110, width: 150 }),
    ]) },
  { id: "shadow-inset", feature: F, title: "Inset shadows", width: 1200, height: 630,
    node: root({ backgroundColor: "#cbd5e1", padding: 50, gap: 50, flexWrap: "wrap", alignContent: "flex-start" }, [
      b("inset 0 2px 8px rgba(0,0,0,0.4)"), b("inset 0 0 0 6px #3b82f6"), b("inset 8px 8px 20px rgba(0,0,0,0.5), inset -8px -8px 20px rgba(255,255,255,0.8)"),
      b("inset 0 0 40px rgba(0,0,0,0.6)", { borderRadius: 75 }), b("inset 0 -30px 40px -10px rgba(236,72,153,0.7), 0 10px 20px rgba(0,0,0,0.3)"), b("inset 0 0 0 2px #111"),
    ]) },
  { id: "shadow-small", feature: F, title: "Card with soft shadow", width: 400, height: 300,
    node: root({ backgroundColor: "#f8fafc", alignItems: "center", justifyContent: "center" }, [b("0 10px 25px rgba(15,23,42,0.18)")]) },
];
