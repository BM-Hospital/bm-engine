// node one.mjs '<json node>' [w h]  -> prints oracle layout for a single tree (style objects as in gen.mjs)
import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const node = JSON.parse(process.argv[2]);
const toT = (n) => ({ type: "container", style: n.style || {}, children: (n.children || []).map(toT) });
const m = await r.measure(toT(node), { width: +(process.argv[3] || 400), height: +(process.argv[4] || 300) });
const f = (n, d) => { console.log(" ".repeat(d * 2) + `${n.transform[4]},${n.transform[5]} ${n.width}x${n.height}`); n.children.forEach((c) => f(c, d + 1)); };
f(m, 0);
