import { c, col, t, root, box, pal } from "./_h.mjs";
const F = "flex";
const items = (n, w = 80, h = 80, extra = {}) => Array.from({ length: n }, (_, i) => box(pal[i % pal.length], w, h, { borderRadius: 8, ...extra }));
const lab = (s) => t(s, { fontSize: 18, color: "#334155", fontWeight: 600 });
export default [
  { id: "flex-row-column", feature: F, title: "Row and column with gap", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 32, gap: 32 }, [
      c({ flexDirection: "row", gap: 16, backgroundColor: "#fff", padding: 16, borderRadius: 12 }, items(4)),
      col({ gap: 16, backgroundColor: "#fff", padding: 16, borderRadius: 12 }, items(4)),
    ]) },
  { id: "flex-justify-align", feature: F, title: "justify-content x align-items matrix", width: 1200, height: 630,
    node: root({ backgroundColor: "#0f172a", padding: 24, flexDirection: "column", gap: 16 },
      ["flex-start", "center", "flex-end", "space-between", "space-around", "space-evenly"].map((j, k) =>
        c({ flex: 1, justifyContent: j, alignItems: ["flex-start", "center", "flex-end"][k % 3], backgroundColor: "#1e293b", borderRadius: 8, padding: 8, gap: 8 }, items(4, 60, k % 2 ? 24 : 36))))
  },
  { id: "flex-wrap-gap", feature: F, title: "flex-wrap with row/column gap", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 32 }, [
      c({ flexWrap: "wrap", rowGap: 20, columnGap: 10, alignContent: "flex-start", width: "100%" }, items(40, 90, 60))
    ]) },
  { id: "flex-grow-shrink-basis", feature: F, title: "grow / shrink / basis", width: 1200, height: 630,
    node: root({ backgroundColor: "#f8fafc", padding: 32, flexDirection: "column", gap: 24 }, [
      c({ gap: 8, height: 120 }, [box(pal[0], 0, "100%", { flexGrow: 1 }), box(pal[1], 0, "100%", { flexGrow: 2 }), box(pal[2], 0, "100%", { flexGrow: 3 })]),
      c({ gap: 8, height: 120 }, [box(pal[3], 600, "100%", { flexShrink: 1 }), box(pal[4], 600, "100%", { flexShrink: 3 }), box(pal[5], 600, "100%", { flexShrink: 0, width: 200 })]),
      c({ gap: 8, height: 120 }, [box(pal[6], undefined, "100%", { flexBasis: 100, flexGrow: 0 }), box(pal[7], undefined, "100%", { flexBasis: "40%", flexGrow: 1 }), box(pal[1], undefined, "100%", { flexBasis: 150, flexGrow: 1 })]),
    ]) },
  { id: "flex-nested-small", feature: F, title: "Nested flex, column-reverse / row-reverse, align-self", width: 400, height: 300,
    node: root({ backgroundColor: "#fff", padding: 12, gap: 12 }, [
      col({ flexDirection: "column-reverse", gap: 6, width: 100 }, items(3, 100, 30)),
      c({ flexDirection: "row-reverse", gap: 6, alignItems: "flex-start", flex: 1 }, [box(pal[0], 50, 50), box(pal[1], 50, 90, { alignSelf: "flex-end" }), box(pal[2], 50, 30, { alignSelf: "center" })]),
    ]) },
];
