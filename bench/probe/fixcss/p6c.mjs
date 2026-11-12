import { tk, bm, px } from "./lib.mjs";
const node = (style, tw = "") => ({ type: "container", style: { display: "flex", width: 20, height: 20 }, children: [{ type: "container", tw, style: { width: 10, height: 10, ...style } }] });
const cases = [
  ["@theme var", node({ backgroundColor: "var(--color-x)" }), "@theme { --color-x: #ff0000; }"],
  ["color-mix", node({ backgroundColor: "color-mix(in oklab, var(--color-x) 50%, transparent)" }), "@theme { --color-x: #ff0000; }"],
  ["override palette bg-red-500", node({}, "bg-red-500"), "@theme { --color-red-500: #00ff00; }"],
  ["override palette from-red-500", node({}, "bg-linear-to-r from-red-500 to-red-500"), "@theme { --color-red-500: #00ff00; }"],
  ["spacing override p", node({ backgroundColor: "red" }, "p-2"), "@theme { --spacing: 1px; }"],
  ["text-huge", { type: "text", text: "Hi", tw: "text-huge", style: { fontFamily: "Inter" } }, "@theme { --text-huge: 30px; }"],
  ["font-display", { type: "text", text: "Hi there", tw: "font-display", style: { fontFamily: "Inter" } }, "@theme { --font-display: Roboto; }"],
  ["font-weight theme", { type: "text", text: "Hi there", tw: "font-heavy", style: { fontFamily: "Inter" } }, "@theme { --font-weight-heavy: 700; }"],
  ["tracking theme", { type: "text", text: "Hi there", tw: "tracking-huge", style: { fontFamily: "Inter" } }, "@theme { --tracking-huge: 5px; }"],
  ["leading theme", { type: "text", text: "Hi there", tw: "leading-huge", style: { fontFamily: "Inter" } }, "@theme { --leading-huge: 3; }"],
  ["aspect theme", node({ height: "auto", width: 10, backgroundColor: "red" }, "aspect-tall"), "@theme { --aspect-tall: 1 / 2; }"],
  ["max-w container", node({ width: 100, backgroundColor: "red" }, "max-w-card"), "@theme { --container-card: 7px; }"],
  ["blur theme", node({ backgroundColor: "red" }, "blur-huge"), "@theme { --blur-huge: 3px; }"],
  ["shadow theme", node({ backgroundColor: "red" }, "shadow-huge"), "@theme { --shadow-huge: 0 0 0 3px blue; }"],
  ["animate theme", node({ backgroundColor: "red" }, "animate-wiggle"), "@theme { --animate-wiggle: wig 1s linear infinite; @keyframes wig { from { width: 2px } to { width: 20px } } }"],
  ["inset spacing", node({ backgroundColor: "red", position: "absolute" }, "left-big top-2"), "@theme { --spacing-big: 7px; }"],
  ["m negative spacing", node({ backgroundColor: "red" }, "-ml-big"), "@theme { --spacing-big: 3px; }"],
  ["gap spacing", { type: "container", tw: "flex gap-big", children: [node({ backgroundColor: "red" }), node({ backgroundColor: "red" })] }, "@theme { --spacing-big: 7px; }"],
];
for (const [name, n, css] of cases) {
  const out = {};
  for (const [k, r] of [["tk", tk], ["bm", bm]]) {
    try {
      const m = await r.measure(n, { width: 60, height: 60, css: [css], timeMs: 500 });
      const raw = await r.render(n, { width: 60, height: 60, css: [css], format: "raw", timeMs: 500 });
      let h = 0; for (let i = 0; i < raw.length; i++) h = (h * 31 + raw[i]) % 1000003;
      const f = (x) => `${x.width}x${x.height}@${x.transform[4]},${x.transform[5]}` + (x.children.length ? "[" + x.children.map(f).join(" ") + "]" : "");
      out[k] = f(m) + " h" + h;
    } catch (e) { out[k] = "ERR " + e.message.slice(0, 60); }
  }
  console.log((out.tk === out.bm ? "   " : "!! ") + name.padEnd(30), "tk", out.tk, out.tk === out.bm ? "" : "\n" + " ".repeat(34) + "bm " + out.bm);
}
