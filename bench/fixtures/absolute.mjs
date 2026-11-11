import { c, t, root, box, pal } from "./_h.mjs";
const F = "absolute";
const abs = (style, bg, children) => c({ position: "absolute", backgroundColor: bg, ...style }, children);
export default [
  { id: "abs-inset", feature: F, title: "Absolute with top/left/right/bottom/inset", width: 1200, height: 630,
    node: root({ position: "relative", backgroundColor: "#f8fafc" }, [
      abs({ top: 20, left: 20, width: 200, height: 120 }, pal[0]),
      abs({ top: 20, right: 20, width: 200, height: 120 }, pal[1]),
      abs({ bottom: 20, left: 20, width: 200, height: 120 }, pal[2]),
      abs({ bottom: 20, right: 20, width: 200, height: 120 }, pal[3]),
      abs({ inset: 200 }, "#3b82f680"),
      abs({ top: 280, left: 500, right: 500, height: 70 }, pal[7]),
    ]) },
  { id: "abs-zorder", feature: F, title: "z-order by document order, overlapping", width: 1200, height: 630,
    node: root({ position: "relative", backgroundColor: "#0f172a" },
      Array.from({ length: 8 }, (_, i) => abs({ top: 60 + i * 40, left: 80 + i * 90, width: 300, height: 300, borderRadius: i % 2 ? 150 : 20 }, pal[i]))) },
  { id: "abs-in-flow", feature: F, title: "Absolute child mixed with in-flow siblings and badge", width: 400, height: 300,
    node: root({ backgroundColor: "#fff", padding: 20, gap: 12, alignItems: "flex-start" }, [
      c({ position: "relative", width: 160, height: 160, backgroundColor: pal[5], borderRadius: 16 }, [
        abs({ top: -10, right: -10, width: 36, height: 36, borderRadius: 18 }, "#ef4444", [t("3", { color: "#fff", fontSize: 18, fontWeight: 700, margin: "auto" })]),
      ]),
      box(pal[3], 100, 100),
    ]) },
];
