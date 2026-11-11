import { c, col, t, root, box, pal, img, asset } from "./_h.mjs";
const overflow = [
  { id: "overflow-hidden-clip", feature: "overflow", title: "overflow:hidden clipping children", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 40, gap: 40 }, [
      c({ width: 300, height: 300, overflow: "hidden", backgroundColor: "#fff", border: "2px solid #111" }, [box(pal[0], 500, 100, { marginLeft: -100, marginTop: 50 }), box(pal[1], 100, 600, { marginLeft: -300 })]),
      c({ width: 300, height: 300, backgroundColor: "#fff", border: "2px solid #111" }, [box(pal[0], 500, 100, { marginLeft: -100, marginTop: 50 })]),
      c({ width: 300, height: 300, overflow: "hidden", backgroundColor: "#fff" }, [t("Long text that is clipped by the overflow hidden box and does not wrap because of nowrap", { fontSize: 36, whiteSpace: "nowrap", color: "#111" })]),
    ]) },
  { id: "overflow-radius-clip", feature: "overflow", title: "overflow:hidden + borderRadius clips children (circle, rounded)", width: 1200, height: 630,
    node: root({ backgroundColor: "#e0e7ff", padding: 40, gap: 40 }, [
      c({ width: 300, height: 300, overflow: "hidden", borderRadius: 150, backgroundColor: "#fff" }, [box(pal[5], 300, 150), box(pal[1], 300, 150)]),
      c({ width: 300, height: 300, overflow: "hidden", borderRadius: 48, backgroundColor: "#fff", border: "6px solid #4f46e5" }, [c({ width: 400, height: 400, backgroundImage: "linear-gradient(135deg,#f43f5e,#fbbf24)" }, [])]),
      c({ width: 300, height: 200, overflow: "hidden", borderRadius: "40px 0 40px 0", backgroundColor: "#fff" }, [t("Clipped text corner", { fontSize: 40, fontWeight: 700, color: "#111", width: 400 })]),
    ]) },
  { id: "overflow-nested", feature: "overflow", title: "Nested overflow clips", width: 400, height: 300,
    node: root({ backgroundColor: "#fff", padding: 20 }, [
      c({ width: 200, height: 200, overflow: "hidden", borderRadius: 30, backgroundColor: "#cbd5e1" }, [
        c({ width: 150, height: 150, overflow: "hidden", marginLeft: 100, marginTop: 100, borderRadius: 20, backgroundColor: pal[2] }, [box(pal[6], 300, 300, { marginLeft: -50, marginTop: -50 })]),
      ]),
    ]) },
];


export default overflow;
