import { both } from "./lib.mjs";
const node = { type: "container", style: { display: "flex", width: 100, height: 50, backgroundColor: "red", padding: 10 }, children: [{ type: "text", text: "Hi", style: { fontFamily: "Inter", fontSize: 20 } }] };
for (const dpr of [1, 2]) {
  const r = await both(async (e) => { const s = await e.renderSvg(node, { width: 200, height: 100, devicePixelRatio: dpr }); return typeof s === "string" ? s : new TextDecoder().decode(s); });
  for (const k of ["tk", "bm"]) console.log("dpr", dpr, k, r[k].slice(0, 400).replace(/\n/g, " "), "\n");
}
