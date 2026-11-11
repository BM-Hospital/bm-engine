// Feature probes on every build profile: what a smaller build does with input that needs a
// compiled-out feature (clear error / ignored as documented — never a trap), plus `features`.
//   node probe/profiles.mjs [core.wasm standard.wasm full.wasm]
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const js = path.join(root, "js");
const files = { core: process.argv[2] || path.join(js, "bm_engine.core.wasm"), standard: process.argv[3] || path.join(js, "bm_engine.standard.wasm"), full: process.argv[4] || path.join(js, "bm_engine.wasm") };
const font = readFileSync(path.join(root, "assets", "fonts", "Inter-Regular.ttf"));
const woff2 = readFileSync(path.join(root, "src", "woff", "testdata", "geist.woff2"));
const png = readFileSync(path.join(here, "..", "assets", "icon.png"));
// red WebP / GIF images made by the full build
const FB = await import(pathToFileURL(path.join(js, "index.mjs")).href + "?maker");
FB.initSync(readFileSync(files.full));
const maker = new FB.Renderer();
const red = { type: "container", style: { width: 8, height: 8, backgroundColor: "red" } };
const webp = Buffer.from(maker.renderSync(red, { width: 8, height: 8, format: "webp" }));
const gif = Buffer.from(maker.renderAnimationSync({ scenes: [{ node: red, durationMs: 100 }], width: 8, height: 8, fps: 10, format: "gif" }));

const box = (style, children = []) => ({ type: "container", style: { width: 40, height: 40, ...style }, children });
const img = (src) => box({ display: "flex" }, [{ type: "image", src: "data:image/x;base64," + src.toString("base64"), style: { width: 40, height: 40 } }]);
const probes = [
  ["plain render", (r) => r.renderSync(box({ backgroundColor: "red" }), { width: 40, height: 40, format: "raw" })],
  ["HTML source", (r) => r.renderSync("<div style='width:40px;height:40px;background:red'></div>", { width: 40, height: 40, format: "raw" })],
  ["css option", (r) => r.renderSync(box({}), { width: 40, height: 40, format: "raw", css: ["div { color: red }"] })],
  ["tw node", (r) => r.renderSync({ ...box({}), tw: "bg-red-500" }, { width: 40, height: 40, format: "raw" })],
  ["svg image", (r) => r.renderSync(box({ backgroundImage: "url('data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"4\" height=\"4\"><rect width=\"4\" height=\"4\" fill=\"red\"/></svg>')" }), { width: 40, height: 40, format: "raw" })],
  ["woff2 font", (r) => r.registerFont({ name: "G", data: woff2 })],
  ["lab() colour", (r) => r.renderSync(box({ backgroundColor: "lab(50% 40 20)" }), { width: 40, height: 40, format: "raw" })],
  ["gradient in oklab", (r) => r.renderSync(box({ backgroundImage: "linear-gradient(in oklab, red, blue)" }), { width: 40, height: 40, format: "raw" })],
  ["clip-path / mix-blend-mode", (r) => r.renderSync(box({ backgroundColor: "red", clipPath: "circle(10px)", mixBlendMode: "multiply" }), { width: 40, height: 40, format: "raw" })],
  ["display: table", (r) => r.renderSync(box({ display: "table", backgroundColor: "red" }), { width: 40, height: 40, format: "raw" })],
  ["float", (r) => r.renderSync(box({}, [box({ float: "left", backgroundColor: "red" })]), { width: 40, height: 40, format: "raw" })],
  ["webp image", (r) => r.renderSync(img(webp), { width: 40, height: 40, format: "raw" })],
  ["gif image", (r) => r.renderSync(img(gif), { width: 40, height: 40, format: "raw" })],
  ["png image", (r) => r.renderSync(img(png), { width: 40, height: 40, format: "raw" })],
  ["text-wrap: balance", (r) => r.renderSync(box({ width: 200, textWrap: "balance", fontFamily: "Inter" }, [{ type: "text", text: "a b c d e f g h i j k l m n o p" }]), { width: 200, height: 40, format: "raw" })],
  ["animation props", (r) => r.renderSync(box({ animation: "spin 1s linear infinite", backgroundColor: "red" }), { width: 40, height: 40, format: "raw", timeMs: 500 })],
  ["renderAnimation", (r) => r.renderAnimationSync({ scenes: [{ node: box({ backgroundColor: "red" }), durationMs: 100 }], width: 40, height: 40, fps: 10 })],
  ["ico output", (r) => r.renderSync(box({ backgroundColor: "red" }), { width: 40, height: 40, format: "ico" })],
  ["renderSvg", (r) => r.renderSvgSync(box({ backgroundColor: "red" }), { width: 40, height: 40 })],
  ["arabic text", (r) => r.renderSync(box({ width: 200, fontFamily: "Inter", direction: "rtl" }, [{ type: "text", text: "مرحبا abc" }]), { width: 200, height: 40, format: "raw" })],
];

function summary(v) {
  if (typeof v === "string") return `ok (${v.length} chars)`;
  if (v instanceof Uint8Array) {
    let red = 0;
    for (let i = 0; i < v.length; i += 4) if (v[i] > 200 && v[i + 1] < 60 && v[i + 3] > 200) red++;
    return `ok (${v.length} B, ${red} red px)`;
  }
  return "ok " + JSON.stringify(v).slice(0, 40);
}

const rows = {};
for (const [prof, file] of Object.entries(files)) {
  const bm = await import(pathToFileURL(path.join(js, "index.mjs")).href + "?" + prof);
  bm.initSync(readFileSync(file));
  const r = new bm.Renderer();
  r.registerFont({ name: "Inter", data: font });
  rows[prof] = { features: Object.entries(bm.features).filter(([, v]) => v).map(([k]) => k).join(",") || "(none)" };
  for (const [name, fn] of probes) {
    let out;
    try { out = summary(fn(r)); } catch (e) { out = (e instanceof WebAssembly.RuntimeError ? "TRAP " : "error: ") + String(e.message).replace(/^bm-engine: /, ""); }
    rows[prof][name] = out;
  }
}
let traps = 0;
for (const [prof, row] of Object.entries(rows)) {
  console.log(`\n== ${prof}: ${row.features}`);
  for (const [k, v] of Object.entries(row)) if (k !== "features") { console.log(`  ${k.padEnd(28)} ${v}`); if (v.startsWith("TRAP")) traps++; }
}
console.log(traps ? `\n${traps} TRAPS` : "\nno traps");
process.exit(traps ? 1 : 0);
