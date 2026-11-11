import { c, col, t, root, box } from "./_h.mjs";
const F = "colors";
const row = (items, size = 120) => c({ gap: 12, flexWrap: "wrap" }, items.map(([label, color]) =>
  col({ gap: 6, alignItems: "center" }, [box(color, size, size, { borderRadius: 12 }), t(label, { fontSize: 14, color: "#222" })])));
export default [
  { id: "colors-solid-bg", feature: F, title: "Solid page backgrounds", width: 400, height: 300,
    node: root({ backgroundColor: "#1e293b", alignItems: "center", justifyContent: "center" }, [box("#f8fafc", 200, 120)]) },
  { id: "colors-hex", feature: F, title: "Hex syntaxes #rgb #rrggbb #rrggbbaa #rgba", width: 1200, height: 630,
    node: root({ backgroundColor: "#ffffff", padding: 40, flexDirection: "column", gap: 24 }, [
      row([["#f00", "#f00"], ["#00ff7f", "#00ff7f"], ["#3366cc", "#3366cc"], ["#ff000080", "#ff000080"], ["#0f08", "#0f08"], ["#00000033", "#00000033"]]),
      row([["#ABCDEF", "#ABCDEF"], ["#123456", "#123456"], ["#fff", "#fff"], ["#000", "#000"], ["#7f7f7f", "#7f7f7f"]]),
    ]) },
  { id: "colors-functional", feature: F, title: "rgb()/rgba()/hsl()/hsla() incl. alpha over a stripe", width: 1200, height: 630,
    node: root({ backgroundColor: "#ffffff", padding: 40, flexDirection: "column", gap: 24 }, [
      c({ height: 40, backgroundColor: "#111" }, []),
      row([["rgb(255,0,0)", "rgb(255, 0, 0)"], ["rgb(0 128 255)", "rgb(0 128 255)"], ["rgba .5", "rgba(34, 197, 94, 0.5)"], ["rgb / .25", "rgb(255 0 255 / 0.25)"]]),
      row([["hsl(0 100% 50%)", "hsl(0, 100%, 50%)"], ["hsl(210..)", "hsl(210, 70%, 45%)"], ["hsla .4", "hsla(45, 100%, 50%, 0.4)"], ["hsl(300..)", "hsl(300 60% 30%)"]]),
    ]) },
  { id: "colors-named", feature: F, title: "Named colors + transparent + currentColor-free", width: 1200, height: 630,
    node: root({ backgroundColor: "#e5e7eb", padding: 40, flexDirection: "column", gap: 24 }, [
      row([["red", "red"], ["rebeccapurple", "rebeccapurple"], ["tomato", "tomato"], ["steelblue", "steelblue"], ["goldenrod", "goldenrod"], ["white", "white"]]),
      row([["black", "black"], ["transparent", "transparent"], ["teal", "teal"], ["coral", "coral"], ["navy", "navy"], ["gray", "gray"]]),
    ]) },
  { id: "colors-transparent-canvas", feature: F, title: "Transparent canvas (no root bg): straight-alpha output check", width: 400, height: 300,
    node: root({ alignItems: "center", justifyContent: "center", gap: 20 }, [box("rgba(239,68,68,0.5)", 120, 120, { borderRadius: 60 }), box("#3b82f6", 100, 100, { borderRadius: 12, opacity: 0.4 })]) },
];
