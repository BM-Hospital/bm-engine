// Root-element edge cases: measure() of two bm builds and takumi. Usage: node probe/layout2/root_edge.mjs <a.wasm> <b.wasm>
import { readFileSync } from "node:fs";
import { T } from "./lib.mjs";
const mk = async (p, i) => { const bm = await import("../../../js/index.mjs?re=" + i); bm.initSync(readFileSync(p)); const r = new bm.Renderer(); r.registerFont({ data: readFileSync("../assets/fonts/Inter-Regular.ttf") }); return r; };
const A = await mk(process.argv[2], 1), B = await mk(process.argv[3], 2);
const box = (style, children = []) => ({ type: "container", style, children });
const kid = box({ display: "block", width: 20, height: 10, backgroundColor: "red" });
const cases = [
  ["margin", box({ display: "block", margin: 10, backgroundColor: "#eee" }, [kid]), { width: 200, height: 100 }],
  ["pct h", box({ display: "flex", height: "50%", width: "50%" }, [kid]), { width: 200, height: 100 }],
  ["abs root", box({ position: "absolute", left: 10, top: 5, width: 30, height: 30 }), { width: 200, height: 100 }],
  ["no size", box({ display: "block", padding: 5 }, [kid]), {}],
  ["no height", box({ display: "block", margin: 7, padding: 5 }, [kid]), { width: 100 }],
  ["inline root", box({}, [{ type: "text", text: "hi" }]), { width: 100, height: 50 }],
  ["fixed child", box({ display: "block", padding: 20 }, [box({ position: "fixed", right: 0, bottom: 0, width: 10, height: 10 })]), { width: 100, height: 50 }],
  ["abs child", box({ display: "block", margin: 20 }, [box({ position: "absolute", right: 0, bottom: 0, width: 10, height: 10 })]), { width: 100, height: 50 }],
  ["margin auto", box({ display: "block", width: 50, margin: "auto", height: 20 }), { width: 100, height: 50 }],
  ["root text", { type: "text", text: "Hello there", style: { margin: 4 } }, { width: 100 }],
];
const f = (m) => `${m.width}x${m.height}@${m.transform[4]},${m.transform[5]}` + (m.children.length ? " [" + m.children.map(f).join(" ") + "]" : "");
for (const [n, node, o] of cases) {
  let t; try { t = f(await T.measure(node, o)); } catch (e) { t = "ERR " + e.message; }
  const a = f(A.measureSync(node, o)), b = f(B.measureSync(node, o));
  console.log(n.padEnd(12), a === b ? "same " : "DIFF ", "takumi", t, "| A", a, a === b ? "" : "| B " + b);
}
