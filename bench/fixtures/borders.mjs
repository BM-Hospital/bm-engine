import { c, root, pal } from "./_h.mjs";
const F = "borders";
const b = (style) => c({ width: 240, height: 160, backgroundColor: "#fff", flexShrink: 0, ...style }, []);
export default [
  { id: "borders-uniform", feature: F, title: "Uniform borders", width: 1200, height: 630,
    node: root({ backgroundColor: "#e2e8f0", padding: 40, gap: 32, flexWrap: "wrap", alignContent: "flex-start" }, [
      b({ border: "1px solid #111" }), b({ border: "4px solid #ef4444" }), b({ border: "12px solid #3b82f6" }),
      b({ borderWidth: 8, borderStyle: "solid", borderColor: "#22c55e" }), b({ border: "6px solid rgba(0,0,0,0.4)" }), b({ border: "10px solid #8b5cf6", backgroundColor: "#ddd6fe" }),
    ]) },
  { id: "borders-per-side", feature: F, title: "Per-side widths and colors", width: 1200, height: 630,
    node: root({ backgroundColor: "#f8fafc", padding: 40, gap: 32, flexWrap: "wrap", alignContent: "flex-start" }, [
      b({ borderTopWidth: 10, borderRightWidth: 2, borderBottomWidth: 20, borderLeftWidth: 6, borderStyle: "solid", borderColor: "#111" }),
      b({ borderWidth: 12, borderStyle: "solid", borderTopColor: pal[0], borderRightColor: pal[3], borderBottomColor: pal[5], borderLeftColor: pal[7] }),
      b({ borderBottom: "8px solid #f97316" }), b({ borderLeft: "16px solid #06b6d4", borderRight: "4px solid #ec4899" }),
      b({ borderTop: "24px solid #22c55e", borderBottom: "24px solid #eab308" }),
      b({ borderWidth: "2px 10px 2px 10px", borderStyle: "solid", borderColor: "#6366f1 #f43f5e" }),
    ]) },
  { id: "borders-with-radius", feature: F, title: "Borders combined with radius", width: 400, height: 300,
    node: root({ backgroundColor: "#fff", padding: 20, gap: 20, alignItems: "center", justifyContent: "center" }, [
      c({ width: 150, height: 150, border: "8px solid #3b82f6", borderRadius: 30, backgroundColor: "#dbeafe" }, []),
      c({ width: 150, height: 150, borderTop: "10px solid #ef4444", borderBottom: "2px solid #111", borderRadius: 75, backgroundColor: "#fee2e2" }, []),
    ]) },
];
