import { Renderer as T } from "@takumi-rs/wasm/node";
import { Renderer as B } from "../../js/node.mjs";
import { readFileSync } from "node:fs";
const F = (n) => readFileSync("../assets/fonts/" + n);
async function run(R, fonts, style, label) {
  const r = new R();
  for (const f of fonts) await r.registerFont(f);
  const node = { type: "container", style: { display: "flex", width: 200, height: 60, backgroundColor: "#000" }, children: [{ type: "text", text: "IlI", style: { fontFamily: "Roboto", fontSize: 40, color: "#fff", ...style } }] };
  const raw = await r.render(node, { width: 200, height: 60, format: "raw" });
  let row = ""; for (let x = 0; x < 40; x++) row += raw[(20 * 200 + x) * 4].toString(16).padStart(2, "0") + " ";
  let row2 = ""; for (let x = 0; x < 40; x++) row2 += raw[(36 * 200 + x) * 4].toString(16).padStart(2, "0") + " ";
  console.log(label, "\n  y20:", row, "\n  y36:", row2);
}
const reg = { name: "Roboto", data: F("Roboto-Regular.ttf"), weight: 400, style: "normal" };
const bold = { name: "Roboto", data: F("Roboto-Bold.ttf"), weight: 700, style: "normal" };
const ital = { name: "Roboto", data: F("Roboto-Italic.ttf"), weight: 400, style: "italic" };
for (const [R, n] of [[T, "takumi"], [B, "bm    "]]) {
  await run(R, [reg, bold, ital], { fontWeight: 700, fontStyle: "italic" }, n + " all3 700 italic");
  await run(R, [ital], { fontWeight: 700, fontStyle: "italic" }, n + " ital-only 700 italic");
  await run(R, [ital], { fontWeight: 400, fontStyle: "italic" }, n + " ital-only 400 italic");
  await run(R, [bold], { fontWeight: 700, fontStyle: "italic" }, n + " bold-only 700 italic");
  await run(R, [reg], { fontWeight: 700 }, n + " reg-only 700");
}
