// Fixtures that expose the byte-product rounding of every compositing route (translucent fills over varied
// backgrounds). Use with probe/paint/cmp.mjs / probe/f2/ab.mjs: `--extra=probe/f2/round_fx.mjs "^rnd-"`.
const W = 400, H = 300;
const bgs = ["#0f172a", "#fde68a", "#be123c", "#22d3ee", "#7c3aed", "#f8fafc", "#14532d", "#fb923c"];
const fgs = ["rgba(236,72,153,0.5)", "rgba(15,23,42,0.3)", "rgba(250,204,21,0.8)", "rgba(56,189,248,0.15)", "rgba(255,255,255,0.6)", "rgba(0,0,0,0.9)"];
const c = (style, children = []) => ({ type: "container", style, children });
const grid = (cell) => c({ display: "flex", flexWrap: "wrap", width: "100%", height: "100%", backgroundColor: "#fff" },
  bgs.map((bg, i) => c({ width: 100, height: 150, backgroundColor: bg, display: "flex", flexWrap: "wrap", alignItems: "center", justifyContent: "center", gap: 4 }, fgs.map((fg, j) => cell(fg, i, j)))));
const svg = (fg) => `<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><rect x="2" y="2" width="36" height="36" rx="9" fill="${fg.replace(/rgba\((\d+),(\d+),(\d+),[\d.]+\)/, "rgb($1,$2,$3)")}" fill-opacity="${/,([\d.]+)\)$/.exec(fg)[1]}"/><circle cx="20" cy="20" r="9" fill="#fff" fill-opacity="0.35"/></svg>`;
export default [
  { id: "rnd-rounded", feature: "f2-round", title: "unclipped rounded translucent fills", width: W, height: H, node: grid((fg) => c({ width: 40, height: 40, borderRadius: 12, backgroundColor: fg })) },
  { id: "rnd-rect", feature: "f2-round", title: "unclipped plain translucent fills", width: W, height: H, node: grid((fg) => c({ width: 40, height: 40, backgroundColor: fg })) },
  { id: "rnd-clipped", feature: "f2-round", title: "rounded translucent fills under an overflow clip", width: W, height: H, node: grid((fg) => c({ width: 40, height: 40, borderRadius: 14, overflow: "hidden" }, [c({ width: 40, height: 40, borderRadius: 12, backgroundColor: fg })])) },
  { id: "rnd-border", feature: "f2-round", title: "translucent rounded borders", width: W, height: H, node: grid((fg) => c({ width: 40, height: 40, borderRadius: 12, border: "6px solid " + fg })) },
  { id: "rnd-gradient", feature: "f2-round", title: "translucent gradients in rounded boxes", width: W, height: H, node: grid((fg) => c({ width: 40, height: 40, borderRadius: 12, backgroundImage: `linear-gradient(90deg, ${fg}, transparent)` })) },
  { id: "rnd-shadow", feature: "f2-round", title: "translucent shadows", width: W, height: H, node: grid((fg) => c({ width: 30, height: 30, margin: 5, borderRadius: 8, boxShadow: "0 0 6px " + fg })) },
  { id: "rnd-opacity", feature: "f2-round", title: "opacity layers", width: W, height: H, node: grid((fg, i, j) => c({ width: 40, height: 40, borderRadius: 12, backgroundColor: fg.replace(/,[\d.]+\)$/, ",1)"), opacity: 0.15 + 0.14 * j })) },
  { id: "rnd-svg", feature: "f2-round", title: "SVG images with translucent shapes", width: W, height: H, node: grid((fg) => ({ type: "image", src: "data:image/svg+xml;base64," + Buffer.from(svg(fg)).toString("base64"), style: { width: 40, height: 40 } })) },
  { id: "rnd-text", feature: "f2-round", title: "translucent text", width: W, height: H, node: grid((fg) => ({ type: "text", text: "Ag", style: { fontSize: 28, color: fg, fontFamily: "Inter" } })) },
];
