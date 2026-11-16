// Exercises the browser-style entry (js/index.mjs + async init from a Response), no node.mjs helper.
import { readFileSync } from "node:fs";
import init, { Renderer } from "../../js/index.mjs";
const bytes = readFileSync(new URL("../../js/bm_render.wasm", import.meta.url));
await init(new Response(bytes, { headers: { "content-type": "application/wasm" } }));   // instantiateStreaming path
const r = new Renderer();
r.registerFont(readFileSync("../assets/fonts/Inter-Regular.ttf").buffer.slice(0));       // ArrayBuffer input, like fetch().arrayBuffer()
const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#fff" }, children: [{ type: "text", text: "browser path", style: { fontSize: 40 } }] };
const png = await r.render(node, { width: 300, height: 100 });
const url = await r.renderAsDataUrl(node, { width: 300, height: 100, format: "webp" });
console.log("png bytes", png.length, "signature ok", png[1] === 0x50 && png[2] === 0x4e, "| data url", url.slice(0, 30), "| imports:", WebAssembly.Module.imports(new WebAssembly.Module(bytes)).length, "exports:", WebAssembly.Module.exports(new WebAssembly.Module(bytes)).map((e) => e.name).join(","));
let threw = ""; try { r.registerFont(readFileSync("../ref/takumi/assets/fonts/inter/inter-latin-opsz-wght-normal.woff2")); } catch (e) { threw = e.message; }
console.log("woff2 ->", threw);
