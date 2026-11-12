// The "create once, register fonts once" module every framework page builds on (docs: frameworks/index.md).
// In the docs the fonts are read with readFileSync(new URL("./fonts/Inter-Regular.ttf", import.meta.url)).
import { Renderer } from "bm-engine";
import { font } from "./util.mjs";

let renderer; // one per process / isolate

export function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: font("Inter-Regular.ttf"), weight: 400 });
    renderer.registerFont({ name: "Inter", data: font("Inter-Bold.ttf"), weight: 700 });
  }
  return renderer;
}

/** The OG card used by every framework example. */
export function card({ title, description }) {
  return {
    type: "container",
    style: {
      display: "flex", flexDirection: "column", justifyContent: "center", gap: 24,
      width: "100%", height: "100%", padding: 64, fontFamily: "Inter",
      backgroundImage: "linear-gradient(to bottom right, #fff7ed, #fecaca)",
    },
    children: [
      { type: "text", text: title, style: { fontSize: 72, fontWeight: 700, color: "#111827" } },
      { type: "text", text: description, style: { fontSize: 42, color: "#4b5563" } },
    ],
  };
}
