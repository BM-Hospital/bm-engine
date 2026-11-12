import { both } from "./lib.mjs";
const box = (style, children = []) => ({ type: "container", style: { display: "flex", width: 100, height: 50, ...style }, children });
const cases = {
  tx_rot: box({ transform: "translateX(50px) rotate(90deg)" }),
  rot30: box({ transform: "rotate(30deg)" }),
  props: box({ translate: "10px 20%", rotate: "45deg", scale: "2 0.5", transformOrigin: "0 0" }),
  nested: box({ transform: "scale(2)", padding: 5 }, [box({ transform: "rotate(90deg) translate(3px,4px)", width: 20, height: 10 }, [box({ width: 5, height: 5, marginLeft: 3 })])]),
  skewMatrix: box({ transform: "skew(10deg, 5deg) matrix(1,0.1,0.2,1,5,6)" }),
  abs: box({ transform: "rotate(10deg)", position: "relative" }, [box({ position: "absolute", left: 10, top: 5, width: 10, height: 10, transform: "scale(3)" })]),
};
for (const [k, node] of Object.entries(cases)) {
  const root = { type: "container", style: { display: "flex", padding: 7, width: 300, height: 300 }, children: [node] };
  const r = await both((e) => e.measure(root, { width: 300, height: 300 }));
  const walk = (m, d = 0, out = []) => { if (typeof m === "string") return [m]; out.push("  ".repeat(d) + m.width + "x" + m.height + " " + JSON.stringify(m.transform)); m.children.forEach((c) => walk(c, d + 1, out)); return out; };
  console.log("==", k); const a = walk(r.tk), b = walk(r.bm);
  a.forEach((l, i) => console.log(l === b[i] ? "   " : "!! ", l, l === b[i] ? "" : "\n       bm " + b[i]));
}
