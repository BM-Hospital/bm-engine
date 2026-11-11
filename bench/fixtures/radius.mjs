import { c, root, pal } from "./_h.mjs";
const F = "border-radius";
const b = (style, i = 0) => c({ width: 220, height: 160, backgroundColor: pal[i % 8], flexShrink: 0, ...style }, []);
export default [
  { id: "radius-uniform-percorner", feature: F, title: "Uniform and per-corner radius", width: 1200, height: 630,
    node: root({ backgroundColor: "#f1f5f9", padding: 40, gap: 30, flexWrap: "wrap", alignContent: "flex-start" }, [
      b({ borderRadius: 0 }, 0), b({ borderRadius: 8 }, 1), b({ borderRadius: 32 }, 2), b({ borderRadius: 80 }, 3),
      b({ borderTopLeftRadius: 60, borderBottomRightRadius: 60 }, 4),
      b({ borderTopLeftRadius: 10, borderTopRightRadius: 40, borderBottomRightRadius: 70, borderBottomLeftRadius: 100 }, 5),
      b({ borderRadius: "10px 40px 70px 100px" }, 6), b({ borderRadius: "0 80px" }, 7),
    ]) },
  { id: "radius-elliptical", feature: F, title: "Elliptical radius 50% / 20%", width: 1200, height: 630,
    node: root({ backgroundColor: "#0f172a", padding: 40, gap: 30, flexWrap: "wrap", alignContent: "flex-start" }, [
      b({ borderRadius: "50% / 20%" }, 0), b({ borderRadius: "20% / 50%" }, 1), b({ borderRadius: "50%" }, 2),
      b({ borderRadius: "100px / 30px" }, 3), b({ borderRadius: "40px 10px / 10px 40px" }, 4), b({ borderRadius: "30% 70% 70% 30% / 30% 30% 70% 70%" }, 5),
    ]) },
  { id: "radius-pill-circle", feature: F, title: "Pill and circle", width: 1200, height: 630,
    node: root({ backgroundColor: "#fff", padding: 40, gap: 30, alignItems: "center", flexWrap: "wrap", alignContent: "flex-start" }, [
      c({ width: 300, height: 80, backgroundColor: pal[5], borderRadius: 9999 }, []),
      c({ width: 180, height: 180, backgroundColor: pal[1], borderRadius: 9999 }, []),
      c({ width: 180, height: 180, backgroundColor: pal[3], borderRadius: "50%" }, []),
      c({ width: 80, height: 300, backgroundColor: pal[6], borderRadius: 40 }, []),
      c({ width: 120, height: 40, backgroundColor: pal[0], borderRadius: 20 }, []),
      c({ width: 40, height: 40, backgroundColor: pal[2], borderRadius: 200 }, []),
    ]) },
  { id: "radius-small", feature: F, title: "Radius larger than box clamps", width: 400, height: 300,
    node: root({ backgroundColor: "#1e293b", alignItems: "center", justifyContent: "center", gap: 16 }, [
      c({ width: 120, height: 60, backgroundColor: pal[4], borderRadius: 500 }, []),
      c({ width: 90, height: 90, backgroundColor: pal[7], borderRadius: 45 }, []),
    ]) },
];
