import { c, col, t, root, box, pal, img, asset } from "./_h.mjs";
const T = (label, style) => col({ alignItems: "center", gap: 14 }, [
  c({ width: 160, height: 100, backgroundColor: "#e2e8f0", alignItems: "center", justifyContent: "center", flexShrink: 0 }, [c({ width: 100, height: 60, backgroundColor: pal[5], ...style, alignItems: "center", justifyContent: "center" }, [t("T", { color: "#fff", fontSize: 28, fontWeight: 700 })])]),
  t(label, { fontSize: 16, color: "#334155" }),
]);
const transform = [
  { id: "transform-basic", feature: "transform", title: "rotate / scale / translate / skew", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 40, gap: 50, flexWrap: "wrap", alignContent: "flex-start" }, [
      T("rotate(15deg)", { transform: "rotate(15deg)" }), T("rotate(-45deg)", { transform: "rotate(-45deg)" }), T("scale(1.5)", { transform: "scale(1.5)" }),
      T("scale(0.5, 1.4)", { transform: "scale(0.5, 1.4)" }), T("translate(30px,-20px)", { transform: "translate(30px, -20px)" }), T("skewX(20deg)", { transform: "skewX(20deg)" }),
      T("rotate(90deg)", { transform: "rotate(90deg)" }), T("translateX(40px)", { transform: "translateX(40px)" }),
    ]) },
  { id: "transform-combined-origin", feature: "transform", title: "Combined transforms + transformOrigin", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 40, gap: 50, flexWrap: "wrap", alignContent: "flex-start" }, [
      T("translate+rotate+scale", { transform: "translate(20px, 10px) rotate(20deg) scale(1.2)" }),
      T("origin top left", { transform: "rotate(30deg)", transformOrigin: "top left" }),
      T("origin 100% 100%", { transform: "rotate(30deg)", transformOrigin: "100% 100%" }),
      T("origin 10px 50px", { transform: "scale(1.6)", transformOrigin: "10px 50px" }),
      T("rotate + radius", { transform: "rotate(10deg)", borderRadius: 24 }),
      T("scale(-1,1)", { transform: "scale(-1, 1)" }),
    ]) },
  { id: "transform-text-small", feature: "transform", title: "Rotated text card", width: 400, height: 300,
    node: root({ backgroundColor: "#0f172a", alignItems: "center", justifyContent: "center" }, [
      c({ transform: "rotate(-8deg)", backgroundColor: "#fde047", padding: "16px 28px", borderRadius: 12, boxShadow: "0 8px 20px rgba(0,0,0,0.5)" }, [t("Rotated!", { fontSize: 48, fontWeight: 700, color: "#111" })]),
    ]) },
];


export default transform;
