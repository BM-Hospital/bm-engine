import { c, t, root, pal } from "./_h.mjs";
const F = "grid";
const cell = (i, extra = {}) => c({ backgroundColor: pal[i % 8], borderRadius: 8, alignItems: "center", justifyContent: "center", ...extra }, [t(String(i + 1), { fontSize: 28, fontWeight: 700, color: "#fff" })]);
const grid = (style, n, cellExtra = () => ({})) => ({ type: "container", style: { display: "grid", width: "100%", height: "100%", ...style }, children: Array.from({ length: n }, (_, i) => cell(i, cellExtra(i))) });
export default [
  { id: "grid-fixed-fr", feature: F, title: "Fixed px + fr tracks with gap", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 30 }, [grid({ gridTemplateColumns: "200px 1fr 2fr", gridTemplateRows: "150px 1fr", gap: 16 }, 6)]) },
  { id: "grid-repeat-gap", feature: F, title: "repeat(), row/column gap", width: 1200, height: 630,
    node: root({ backgroundColor: "#0f172a", padding: 30 }, [grid({ gridTemplateColumns: "repeat(4, 1fr)", gridTemplateRows: "repeat(3, 1fr)", rowGap: 12, columnGap: 28 }, 12)]) },
  { id: "grid-spans", feature: F, title: "Column/row spans & explicit placement", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 30 }, [grid({ gridTemplateColumns: "repeat(4, 1fr)", gridTemplateRows: "repeat(3, 1fr)", gap: 12 }, 7, (i) =>
      [{ gridColumn: "span 2", gridRow: "span 2" }, {}, { gridRow: "span 2" }, { gridColumn: "span 2" }, { gridColumn: "1 / 3" }, { gridColumn: "3 / 5" }, {}][i])]) },
  { id: "grid-small-mixed", feature: F, title: "Mixed auto / minmax / % tracks, align/justify", width: 400, height: 300,
    node: root({ backgroundColor: "#fff", padding: 12 }, [grid({ gridTemplateColumns: "50px 30% 1fr", gridTemplateRows: "auto 1fr", gap: 8 }, 6)]) },
];
