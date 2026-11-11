import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
async function t(style, label) {
  const node = { type: "container", style: { display: "block", width: 40, height: 40, backgroundColor: "#fff", position: "relative" },
    children: [{ type: "container", style: { display: "block", position: "absolute", width: 10, height: 10, backgroundColor: "#f00", ...style } }] };
  const raw = await r.render(node, { width: 40, height: 40, format: "raw" });
  // find rows/cols with red at column/row through the middle
  const col = [], row = [];
  const cx = Math.round((style.left ?? 0) + 5), cy = Math.round((style.top ?? 0) + 5);
  for (let y = 0; y < 40; y++) { const i = (y * 40 + cx) * 4; if (raw[i + 1] < 250) col.push(y + ":" + raw[i + 1]); }
  for (let x = 0; x < 40; x++) { const i = (cy * 40 + x) * 4; if (raw[i + 1] < 250) row.push(x + ":" + raw[i + 1]); }
  console.log(label, "rows", col[0], "..", col.at(-1), "n", col.length, "| cols", row[0], "..", row.at(-1), "n", row.length);
}
for (const v of [10, 10.25, 10.49, 10.5, 10.51, 10.75, 11.5, 12.5]) await t({ top: v, left: v }, "plain  " + v);
for (const v of [10.5, 11.5, 10.49]) await t({ top: v, left: v, borderRadius: 3 }, "radius " + v);
for (const v of [10.5, 11.5]) await t({ top: v, left: v, height: 10.5, width: 10.5 }, "h10.5 " + v);
