import { readFileSync } from "node:fs";
import { Renderer as TR } from "@takumi-rs/wasm";
import { ROOT } from "./lib.mjs";
import { pathToFileURL } from "node:url";
import path from "node:path";
const { Renderer: BR } = await import(pathToFileURL(path.join(ROOT, "js/node.mjs")).href);
const roboto = readFileSync(path.join(ROOT, "assets/fonts/Roboto-Regular.ttf"));
const inter = readFileSync(path.join(ROOT, "assets/fonts/Inter-Regular.ttf"));
const text = (fam) => ({ type: "container", style: { display: "flex" }, children: [{ type: "text", text: "Hello wide world", style: { fontFamily: fam, fontSize: 20 } }] });
const w = async (r, node, o = {}) => (await r.measure(node, { width: 400, height: 50, ...o })).children[0].width;
for (const [name, mk] of [["tk", async () => new TR()], ["bm", async () => { const r = new BR(); r.registerFont({ name: "Inter", data: inter }); return r; }]]) {
  const r = await mk();
  const before = await w(r, text("Roboto"));
  const during = await w(r, text("Roboto"), { fonts: [{ name: "Roboto", data: roboto }] });
  const after = await w(r, text("Roboto"));
  console.log(name, { before, during, after });
}
