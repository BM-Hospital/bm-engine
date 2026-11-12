import { readFileSync } from "node:fs";
import path from "node:path";
import { Renderer } from "bm-engine"; // native addon on Node when installed, else the full wasm build

let renderer;
export function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    const dir = path.join(process.cwd(), "fonts");
    renderer.registerFont({ name: "Inter", data: readFileSync(path.join(dir, "Inter-Regular.ttf")), weight: 400 });
    renderer.registerFont({ name: "Inter", data: readFileSync(path.join(dir, "Inter-Bold.ttf")), weight: 700 });
  }
  return renderer;
}
export function card({ title, description }) {
  return { type: "container", style: { display: "flex", flexDirection: "column", justifyContent: "center", gap: 24, width: "100%", height: "100%", padding: 64, fontFamily: "Inter", backgroundImage: "linear-gradient(to bottom right, #fff7ed, #fecaca)" },
    children: [{ type: "text", text: title, style: { fontSize: 72, fontWeight: 700, color: "#111827" } }, { type: "text", text: description, style: { fontSize: 42, color: "#4b5563" } }] };
}
