import { initSync, Renderer } from "bm-engine/core";
import wasm from "bm-engine/core.wasm"; // a WebAssembly.Module (wrangler compiles .wasm imports)
import interRegular from "./Inter-Regular.ttf"; // an ArrayBuffer (the "Data" rule in wrangler.toml)
import interBold from "./Inter-Bold.ttf";

initSync(wasm);
let renderer; // one per isolate, reused across requests

function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: interRegular, weight: 400 });
    renderer.registerFont({ name: "Inter", data: interBold, weight: 700 });
  }
  return renderer;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== "/og.png") return new Response("Not found", { status: 404 });

    const cache = caches.default;
    const cached = await cache.match(request);
    if (cached) return cached;

    const title = url.searchParams.get("title") ?? "Hello from Workers";
    const png = getRenderer().renderSync(
      {
        type: "container",
        style: { display: "flex", flexDirection: "column", justifyContent: "center", width: "100%", height: "100%",
          padding: 64, fontFamily: "Inter", backgroundImage: "linear-gradient(to bottom right, #fff7ed, #fecaca)" },
        children: [{ type: "text", text: title, style: { fontSize: 72, fontWeight: 700, color: "#111827" } }],
      },
      { width: 1200, height: 630 },
    );
    const response = new Response(png, {
      headers: { "content-type": "image/png", "cache-control": "public, max-age=86400" },
    });
    ctx.waitUntil(cache.put(request, response.clone()));
    return response;
  },
};
