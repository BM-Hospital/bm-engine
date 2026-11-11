import { c, col, t, root, box, pal, img, asset } from "./_h.mjs";
const opacity = [
  { id: "opacity-basic", feature: "opacity", title: "Opacity levels over stripes", width: 1200, height: 630,
    node: root({ backgroundImage: "linear-gradient(90deg, #111 0%, #111 50%, #fff 50%, #fff 100%)", padding: 40, gap: 20, alignContent: "flex-start", flexWrap: "wrap" },
      [1, 0.8, 0.6, 0.4, 0.2, 0.05, 0].map((o, i) => c({ width: 150, height: 300, backgroundColor: pal[i], opacity: o, borderRadius: 12 }, [t(String(o), { fontSize: 24, color: "#fff", margin: "auto" })]))) },
  { id: "opacity-nested", feature: "opacity", title: "Nested opacity (group compositing)", width: 1200, height: 630,
    node: root({ backgroundColor: "#fef9c3", padding: 40, gap: 40 }, [
      c({ width: 360, height: 360, backgroundColor: pal[5], opacity: 0.5, padding: 40 }, [
        c({ width: 280, height: 280, backgroundColor: pal[0], opacity: 0.5, padding: 40 }, [c({ width: 200, height: 200, backgroundColor: pal[3], opacity: 0.5 }, [])]),
      ]),
      c({ width: 360, height: 360, backgroundColor: pal[5], padding: 40, opacity: 0.6 }, [
        c({ width: 280, height: 280, backgroundColor: pal[0], opacity: 1, padding: 40 }, [t("text under opacity", { fontSize: 28, color: "#fff" })]),
      ]),
    ]) },
  { id: "opacity-with-radius-shadow", feature: "opacity", title: "Opacity with radius + shadow + text", width: 400, height: 300,
    node: root({ backgroundColor: "#0f172a", alignItems: "center", justifyContent: "center" }, [
      c({ width: 240, height: 140, borderRadius: 24, backgroundColor: "#fff", opacity: 0.7, boxShadow: "0 10px 30px rgba(0,0,0,0.6)", alignItems: "center", justifyContent: "center" }, [t("70%", { fontSize: 56, fontWeight: 700, color: "#111" })]),
    ]) },
];


export default opacity;
