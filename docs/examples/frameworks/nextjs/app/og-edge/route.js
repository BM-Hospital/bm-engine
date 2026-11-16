import { initSync, Renderer } from "bm-render/core";
import wasm from "bm-render/core.wasm?module";

export const runtime = "edge";

let renderer;
async function getRenderer() {
  if (!renderer) {
    initSync(wasm);
    const font = await fetch(new URL("../../fonts/Inter-Regular.ttf", import.meta.url)).then((r) => r.arrayBuffer());
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: font });
  }
  return renderer;
}

export async function GET(request) {
  const title = new URL(request.url).searchParams.get("title") ?? "Edge";
  const r = await getRenderer();
  const png = r.renderSync({ type: "container", style: { display: "flex", width: "100%", height: "100%", padding: 64, backgroundColor: "#7c3aed" },
    children: [{ type: "text", text: title, style: { fontFamily: "Inter", fontSize: 72, color: "white" } }] }, { width: 1200, height: 630 });
  return new Response(png, { headers: { "content-type": "image/png" } });
}
