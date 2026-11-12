// Tailwind probes: each case renders a 100x100 canvas whose root is display:flex with one child box (tw / css
// given), and reports the child's measured size + the colour at the child's centre (and at (2,2) of it).
import { tk, bm, px } from "./lib.mjs";
const T = (tw, extra = {}) => ({ tw, ...extra });
export const cases = {
  // 6a theme
  "theme color": T("w-10 h-10 bg-brand-500", { css: "@theme { --color-brand-500: #ff0000; }" }),
  "theme color /50": T("w-10 h-10 bg-brand-500/50", { css: "@theme { --color-brand-500: #ff0000; }" }),
  "theme text color": T("w-10 h-10 text-brand-500 bg-current", { css: "@theme { --color-brand-500: #00ff00; }" }),
  "theme var on node": T("w-10 h-10 bg-brand", { style: { "--color-brand": "#0000ff" } }),
  "theme --spacing": T("w-10 h-10 bg-black", { css: "@theme { --spacing: 2px; }" }),
  "theme --spacing-x": T("w-big h-10 bg-black", { css: "@theme { --spacing-big: 33px; }" }),
  "theme --radius": T("w-10 h-10 bg-black rounded-blob", { css: "@theme { --radius-blob: 20px; }" }),
  "theme --breakpoint": T("w-10 h-10 bg-black tab:w-20", { css: "@theme { --breakpoint-tab: 50px; }" }),
  "theme --container": T("w-card h-10 bg-black", { css: "@theme { --container-card: 44px; }" }),
  "theme --text": T("w-10 h-10 bg-black text-huge", { css: "@theme { --text-huge: 30px; }" }),
  "arb var bg": T("w-10 h-10 bg-[var(--x)]", { style: { "--x": "#ff00ff" } }),
  "arb var w": T("w-[var(--w)] h-10 bg-black", { style: { "--w": "23px" } }),
  "arb paren w": T("w-(--w) h-10 bg-black", { style: { "--w": "27px" } }),
  "arb paren bg": T("w-10 h-10 bg-(--x)", { style: { "--x": "#00ffff" } }),
  // 6e dead utilities
  "outline-2": T("w-10 h-10 outline-2 outline-red-500 m-4"),
  "outline-2 alone": T("w-10 h-10 outline-2 m-4"),
  "backdrop-blur": T("w-10 h-10 backdrop-blur bg-white/50"),
  "mask-b-from-50%": T("w-10 h-10 bg-black mask-b-from-50%"),
  "arb prop": T("w-10 h-10 [background-color:red]"),
  "arb prop2": T("[width:31px] h-10 bg-black"),
  "bg-gradient-to-r": T("w-10 h-10 bg-gradient-to-r from-red-500 to-blue-500"),
  "bg-linear-to-r": T("w-10 h-10 bg-linear-to-r from-red-500 to-blue-500"),
  // 6c animate
  "animate-spin": T("w-10 h-10 bg-black animate-spin", { timeMs: 250 }),
  "animate-ping": T("w-10 h-10 bg-black animate-ping", { timeMs: 500 }),
  "animate-pulse": T("w-10 h-10 bg-black animate-pulse", { timeMs: 500 }),
  "animate-bounce": T("w-10 h-10 bg-black animate-bounce", { timeMs: 250 }),
  "animate-arb": T("w-10 h-10 bg-black animate-[wig_1s_linear_infinite]", { css: "@keyframes wig { from { width: 10px } to { width: 50px } }", timeMs: 500 }),
  // 6f cascade
  "layer vs tw": T("w-10 h-10 bg-red-500", { cls: "q", css: "@layer base { .q { background-color: blue; } }" }),
  "unlayered vs tw": T("w-10 h-10 bg-red-500", { cls: "q", css: ".q { background-color: blue; }" }),
  "layer components vs tw": T("w-10 h-10 bg-red-500", { cls: "q", css: "@layer components { .q { background-color: blue; } }" }),
  "layer utilities vs tw": T("w-10 h-10 bg-red-500", { cls: "q", css: "@layer utilities { .q { background-color: blue; } }" }),
  "important css vs tw": T("w-10 h-10 bg-red-500", { cls: "q", css: ".q { background-color: blue !important; }" }),
  "tw ! vs css": T("w-10 h-10 !bg-red-500", { cls: "q", css: ".q { background-color: blue; }" }),
  "imp unlayered vs tw!": T("w-10 h-10 !bg-red-500", { cls: "q", css: ".q { background-color: blue !important; }" }),
  "imp layer vs tw!": T("w-10 h-10 !bg-red-500", { cls: "q", css: "@layer x { .q { background-color: blue !important; } }" }),
  "two layers": T("w-10 h-10", { cls: "q", css: "@layer a, b; @layer b { .q { background-color: blue; } } @layer a { .q { background-color: green; } }" }),
  "layer imp vs unlayered imp": T("w-10 h-10", { cls: "q", css: "@layer a { .q { background-color: blue !important; } } .q { background-color: green !important; }" }),
  "style vs tw!": T("w-10 h-10 !bg-red-500", { style: { backgroundColor: "blue" } }),
  "id css vs tw": T("w-10 h-10 bg-red-500", { id: "z", css: "#z { background-color: blue; }" }),
};
const run = async (r, k) => {
  const c = cases[k];
  const node = { type: "container", style: { display: "flex", width: 100, height: 100 }, children: [{ type: "container", tw: c.tw, ...(c.cls ? { className: c.cls } : {}), ...(c.id ? { id: c.id } : {}), ...(c.style ? { style: c.style } : {}), children: [] }] };
  const opts = { width: 100, height: 100, ...(c.css ? { css: [c.css] } : {}), ...(c.timeMs != null ? { timeMs: c.timeMs } : {}) };
  try {
    const m = await r.measure(node, opts);
    const ch = m.children[0];
    const raw = await r.render(node, { ...opts, format: "raw" });
    const cx = Math.min(99, Math.floor(ch.transform[4] + ch.width / 2)), cy = Math.min(99, Math.floor(ch.transform[5] + ch.height / 2));
    let sum = 0; for (let i = 0; i < raw.length; i++) sum = (sum + raw[i] * (i % 251 + 1)) % 1000003;
    return `${ch.width}x${ch.height} t=${ch.transform.map((v) => +v.toFixed(2)).join(",")} c=${px(raw, 100, cx, cy).join(",")} h=${sum}`;
  } catch (e) { return "ERR " + e.message.slice(0, 80); }
};
if (process.argv[1].endsWith("p6.mjs")) {
  const only = process.argv[2] ? new RegExp(process.argv[2], "i") : null;
  for (const k of Object.keys(cases)) {
    if (only && !only.test(k)) continue;
    const a = await run(tk, k), b = await run(bm, k);
    console.log((a === b ? "   " : "!! ") + k.padEnd(24), "tk", a, a === b ? "" : "\n" + " ".repeat(28) + "bm " + b);
  }
}
