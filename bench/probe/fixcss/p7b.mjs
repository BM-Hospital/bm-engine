import { tk, bm } from "./lib.mjs";
const css = ["@keyframes fs{from{font-size:10px}to{font-size:30px}} .a{animation:fs 1000ms linear; width:1em; height:2em; display:block} .b{animation:fs 1000ms linear; display:block} .c{width:2em;height:1em;display:block}"];
const node = { type: "container", style: { display: "block" }, children: [{ type: "container", className: "a" }, { type: "container", className: "b", children: [{ type: "container", className: "c" }] }] };
for (const t of [0, 500, 999]) {
  for (const [n, r] of [["tk", tk], ["bm", bm]]) {
    const m = await r.measure(node, { width: 100, height: 100, css, timeMs: t, devicePixelRatio: +(process.argv[2] || 1) });
    console.log(t, n, m.children.map((c) => `${c.width}x${c.height}`).join(" "), m.children[1].children.map((c) => `${c.width}x${c.height}`).join(" "));
  }
}
