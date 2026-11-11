// takumi probe: end-side resolution of a lone name with explicit <name>-start / <name>-end lines and areas.
import { T, B } from "./lib.mjs";
const run = async (style, gc) => {
  const node = { type: "container", style: { display: "grid", gridTemplateRows: "10px", width: 400, ...style }, children: [{ type: "container", style: { ...gc, height: 10 } }] };
  const a = await T.measure(node, { width: 400, height: 50 }), b = await B.measure(node, { width: 400, height: 50 });
  const f = (m) => { const k = m.children[0]; return `x=${k.transform[4]} w=${k.width}`; };
  console.log(JSON.stringify(gc).padEnd(44), "takumi", f(a).padEnd(16), "bm", f(b));
};
const lines = { gridTemplateColumns: "[x-start] 10px 20px [x-end] 30px 40px [y] 50px [y]" };
for (const gc of [{ gridColumn: "x" }, { gridColumn: "1 / x" }, { gridColumnEnd: "x", gridColumnStart: "1" }, { gridColumn: "x / 5" }, { gridColumn: "y" }, { gridColumn: "1 / y" }, { gridColumnStart: "2", gridColumnEnd: "y" }, { gridArea: "x" }, { gridColumn: "x / x" }, { gridRow: "1", gridColumn: "x" }, { gridArea: "1 / x" }])
  await run(lines, gc);
const areas = { gridTemplateColumns: "10px 20px 30px 40px", gridTemplateAreas: "\"p q q r\"" };
for (const gc of [{ gridColumn: "q" }, { gridColumn: "1 / q" }, { gridColumnStart: "1", gridColumnEnd: "q" }, { gridArea: "q" }, { gridColumn: "q-start / q-end" }, { gridColumn: "1 / q-end" }])
  await run(areas, gc);
