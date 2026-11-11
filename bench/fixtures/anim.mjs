// CSS animations sampled at a point of the timeline (takumi `timeMs` render option). Every case carries
// `opts: { timeMs, css }` that the harness forwards to both engines. Ids end in `-t<ms>`.
import { c, root, t, pal } from "./_h.mjs";

const W = 400;
const H = 200;

/** One case per time sample of the same tree + stylesheet. */
function at(id, title, css, node, times) {
  return times.map((ms) => ({ id: `anim-${id}-t${ms}`, feature: "animation", title: `${title} @ ${ms}ms`, width: W, height: H, opts: { timeMs: ms, css: [css] }, node }));
}

const stage = (children) => root({ backgroundColor: "#f8fafc", alignItems: "center", justifyContent: "center", gap: 20 }, children);
const box = (className, bg, extra = {}) => ({ type: "container", className, style: { width: 80, height: 80, backgroundColor: bg, flexShrink: 0, ...extra } });

export default [
  ...at("opacity", "opacity 0 -> 1 linear",
    "@keyframes fade { from { opacity: 0 } to { opacity: 1 } } .a { animation: fade 1000ms linear }",
    stage([box("a", pal[5])]), [0, 250, 500, 900, 1500]),

  ...at("transform", "translate + rotate, ease-in-out, 3 keyframes",
    "@keyframes move { 0% { transform: translateX(-100px) rotate(0deg) } 50% { transform: translateX(0px) rotate(45deg) } 100% { transform: translateX(100px) rotate(90deg) } } .a { animation: move 800ms ease-in-out both }",
    stage([box("a", pal[0], { borderRadius: 12 })]), [0, 200, 400, 600, 800]),

  ...at("color", "background-color + color + border-color",
    "@keyframes paint { from { background-color: #ef4444; color: #ffffff; border-color: #000 } to { background-color: #3b82f6; color: #111827; border-color: #22c55e } } .a { animation: paint 1s linear forwards; border: 6px solid; display: flex; align-items: center; justify-content: center; font-size: 28px; font-family: Inter }",
    stage([{ type: "container", className: "a", style: { width: 160, height: 100 }, children: [{ type: "text", text: "Hue" }] }]), [0, 300, 700, 2000]),

  ...at("width", "width / height / border-radius (layout animates)",
    "@keyframes grow { from { width: 40px; height: 40px; border-radius: 0px } to { width: 300px; height: 120px; border-radius: 60px } } .a { animation: grow 1000ms cubic-bezier(0.2, 0.8, 0.2, 1) }",
    stage([box("a", pal[3]), box("b", pal[6], { width: 40, height: 40 })]), [0, 100, 500, 999]),

  ...at("delay-fill", "delay 500ms: none / backwards / forwards / both",
    "@keyframes slide { from { transform: translateY(-50px); opacity: 0.2 } to { transform: translateY(50px); opacity: 1 } } " +
      ".n { animation: slide 1000ms linear 500ms none } .bw { animation: slide 1000ms linear 500ms backwards } " +
      ".fw { animation: slide 1000ms linear 500ms forwards } .bo { animation: slide 1000ms linear 500ms both }",
    stage([box("n", pal[0], { width: 50, height: 50 }), box("bw", pal[2], { width: 50, height: 50 }), box("fw", pal[4], { width: 50, height: 50 }), box("bo", pal[6], { width: 50, height: 50 })]),
    [0, 750, 2000]),

  ...at("alternate", "alternate direction, 3 iterations, partial keyframes (no 0%)",
    "@keyframes bounce2 { 50% { transform: translateX(80px) scale(1.4) } 100% { transform: translateX(160px) } } .a { animation: bounce2 400ms linear 0s 3 alternate both }",
    root({ backgroundColor: "#fff", alignItems: "center", paddingLeft: 40 }, [box("a", pal[1], { width: 60, height: 60 })]), [100, 500, 700, 1100, 1300]),

  ...at("steps", "steps(4, end) and step-start",
    "@keyframes tick { from { transform: translateX(-120px) } to { transform: translateX(120px) } } .s { animation: tick 1000ms steps(4, end) both } .ss { animation: tick 1000ms step-start }",
    { type: "container", style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", gap: 20, backgroundColor: "#fff" }, children: [box("s", pal[5], { width: 40, height: 40 }), box("ss", pal[7], { width: 40, height: 40 })] },
    [0, 260, 500, 990]),

  ...at("two-anims", "two animations on one element (later wins per property)",
    "@keyframes a1 { from { opacity: 0.2; transform: translateX(-80px) } to { opacity: 1; transform: translateX(80px) } } " +
      "@keyframes a2 { from { background-color: #ef4444 } to { background-color: #22c55e; transform: rotate(30deg) } } " +
      ".a { animation: a1 1000ms linear, a2 500ms ease-out 250ms both }",
    stage([box("a", pal[5])]), [0, 400, 600, 1200]),

  ...at("inherit", "animated inherited property (color, font-size) flows to children",
    "@keyframes txt { from { color: #ef4444; font-size: 20px } to { color: #1d4ed8; font-size: 44px } } .p { animation: txt 1000ms linear forwards; font-family: Inter; display: flex; flex-direction: column; gap: 8px }",
    root({ backgroundColor: "#fff", alignItems: "center", justifyContent: "center" }, [{ type: "container", className: "p", children: [t("Parent animates", { fontFamily: "Inter" }), { type: "container", children: [{ type: "text", text: "child inherits" }] }] }]),
    [0, 500, 1000]),

  ...at("tw-spin", "Tailwind built-in `spin` keyframes via animation-name",
    ".a { animation: spin 1s linear infinite }",
    stage([box("a", pal[2], { width: 70, height: 70 })]), [125, 375, 1600]),

  ...at("kf-option", "deprecated `keyframes` option + inline animation style",
    "",
    stage([{ type: "container", style: { width: 80, height: 80, backgroundColor: pal[4], animation: "kfopt 1s linear both" } }]), [0, 500]),
].map((k) => (k.id.startsWith("anim-kf-option") ? { ...k, opts: { timeMs: k.opts.timeMs, keyframes: { kfopt: { from: { transform: "scale(0.3)", opacity: 0.3 }, to: { transform: "scale(1.5)", opacity: 1 } } } } } : k));

void c;
