import { c, col, t, root, box, pal } from "./_h.mjs";
const F = "sizing";
export default [
  { id: "sizing-percent", feature: F, title: "Percent width/height", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 30, flexDirection: "column", gap: 20 }, [
      c({ width: "100%", height: "25%", gap: 10 }, [box(pal[0], "50%", "100%"), box(pal[1], "25%", "100%"), box(pal[2], "10%", "50%")]),
      c({ width: "60%", height: "30%", backgroundColor: pal[5] }, [box("#ffffffaa", "50%", "50%")]),
      c({ width: "80%", height: 80, backgroundColor: pal[3] }, []),
    ]) },
  { id: "sizing-minmax", feature: F, title: "min/max width & height", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 30, gap: 20, alignItems: "flex-start" }, [
      c({ width: 50, minWidth: 200, height: 100, backgroundColor: pal[0] }, []),
      c({ width: 900, maxWidth: 300, height: 150, backgroundColor: pal[1] }, []),
      c({ flexGrow: 1, maxWidth: 250, height: 300, minHeight: 200, backgroundColor: pal[4] }, []),
      c({ height: 20, maxHeight: 60, minHeight: 40, width: 200, backgroundColor: pal[6] }, []),
    ]) },
  { id: "sizing-aspect-ratio", feature: F, title: "aspect-ratio", width: 1200, height: 630,
    node: root({ backgroundColor: "#0f172a", padding: 30, gap: 20, alignItems: "flex-start" }, [
      c({ width: 300, aspectRatio: "16 / 9", backgroundColor: pal[5], borderRadius: 12 }, []),
      c({ width: 200, aspectRatio: 1, backgroundColor: pal[3], borderRadius: 12 }, []),
      c({ height: 300, aspectRatio: "3 / 4", backgroundColor: pal[7], borderRadius: 12 }, []),
      c({ width: 250, aspectRatio: 2.5, backgroundColor: pal[2], borderRadius: 12 }, []),
    ]) },
  { id: "sizing-padding-margin", feature: F, title: "Padding & margin shorthands + auto margins", width: 1200, height: 630,
    node: root({ backgroundColor: "#e2e8f0", padding: "20px 40px 60px 80px", gap: 0 }, [
      col({ flex: 1, backgroundColor: "#fff", padding: "10px 30px" }, [
        c({ margin: 20, width: 200, height: 60, backgroundColor: pal[0] }, []),
        c({ margin: "0 0 0 100px", width: 200, height: 60, backgroundColor: pal[1] }, []),
        c({ marginLeft: "auto", marginTop: 10, width: 200, height: 60, backgroundColor: pal[2] }, []),
        c({ margin: "10px auto", width: 200, height: 60, backgroundColor: pal[3] }, []),
        c({ marginTop: "auto", marginRight: 40, width: 200, height: 60, backgroundColor: pal[4], alignSelf: "flex-end" }, []),
      ]),
    ]) },
  { id: "sizing-auto-margin-center", feature: F, title: "Auto margins centering", width: 400, height: 300,
    node: root({ backgroundColor: "#1e293b" }, [c({ margin: "auto", width: 120, height: 80, backgroundColor: pal[1], borderRadius: 8 }, [])]) },
];
