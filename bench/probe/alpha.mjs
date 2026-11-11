import takumi from "../engines/takumi-wasm.mjs";
import native from "../engines/takumi-native.mjs";
for (const e of [takumi, native]) {
  const r = await e.create({ fonts: [] });
  const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "rgba(255,0,0,0.5)" }, children: [] };
  const raw = await r.render(node, { width: 4, height: 4, format: "raw" });
  console.log(e.name, raw.length, Array.from(raw.slice(0, 8)));
}
