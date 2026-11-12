// Examples for docs/{en,vi}/image/fonts.md. Run: node docs/examples/run-all.mjs fonts
import { saver, expectThrow } from "./_lib.mjs";
import { existsSync } from "node:fs";
import http from "node:http";
const save = saver("fonts");
const log = (label, value) => console.log(label, JSON.stringify(value));

// #region setup
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
const families = renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
// families: [{ name: "Inter", faces: [{ weight: 400, style: "normal", width: 100, index: 0 }],
//              weight: 400, style: "normal" }]
// #endregion
log("setup", families);

// #region faces
// More faces of the same family: name, weight and style are read from each file.
renderer.registerFont(readFileSync("assets/fonts/Inter-SemiBold.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
const inter = renderer.registerFont(readFileSync("assets/fonts/Inter-Italic.ttf"));
// inter[0].faces: 400 normal, 600 normal, 700 normal, 400 italic

// Override what the file says: register Roboto Bold as weight 900 of a family called "Brand".
const brand = renderer.registerFont({ name: "Brand", data: readFileSync("assets/fonts/Roboto-Bold.ttf"), weight: 900 });
// brand: [{ name: "Brand", faces: [{ weight: 900, style: "normal", width: 100, index: 0 }], ... }]
// #endregion
log("faces", inter[0].faces);
log("brand", brand);

// #region matching
const row = (text, style) => ({ type: "text", text, style: { fontFamily: "Inter", fontSize: 26, ...style } });
const matching = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", gap: 2, padding: "12px 20px", width: "100%", height: "100%", backgroundColor: "#fff", color: "#111827" },
    children: [
      row("300 → Regular (400)", { fontWeight: 300 }),
      row("500 → Regular (400)", { fontWeight: 500 }),
      row("600 → SemiBold", { fontWeight: 600 }),
      row("800 → Bold (700)", { fontWeight: 800 }),
      row("italic → Inter Italic", { fontStyle: "italic" }),
      row("bold italic → synthesised", { fontStyle: "italic", fontWeight: 700 }),
    ],
  },
  { width: 560, height: 200 },
);
// #endregion
save("matching", matching);

// #region synthesis
// "Solo" has a single regular face: bold and italic are synthesised.
renderer.registerFont({ name: "Solo", data: readFileSync("assets/fonts/Roboto-Regular.ttf") });
const synthesis = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", padding: "12px 20px", width: "100%", height: "100%", backgroundColor: "#fff", fontFamily: "Solo", fontSize: 26 },
    children: [
      { type: "text", text: "Regular face as registered" },
      { type: "text", text: "fontWeight 700: synthetic bold", style: { fontWeight: 700 } },
      { type: "text", text: "fontStyle italic: synthetic oblique", style: { fontStyle: "italic" } },
      { type: "text", text: "fontSynthesis none: still synthesised", style: { fontWeight: 700, fontSynthesis: "none" } },
    ],
  },
  { width: 560, height: 160 },
);
// #endregion
save("synthesis", synthesis);

// #region fallback
const symbols = { type: "text", text: "Roboto: ① ★ ✓ ∑ → ⌘ ⇧ ↗ × ● ▶ ◆ ♥", style: { fontFamily: "Roboto", fontSize: 26 } };
const card = (child) => ({ type: "container", style: { display: "flex", alignItems: "center", padding: "0 20px", width: "100%", height: "100%", backgroundColor: "#fff" }, children: [child] });

const robotoOnly = new Renderer();
robotoOnly.registerFont(readFileSync("assets/fonts/Roboto-Regular.ttf"));
const before = robotoOnly.renderSync(card(symbols), { width: 560, height: 56 });

robotoOnly.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf")); // Inter covers the symbols
const after = robotoOnly.renderSync(card(symbols), { width: 560, height: 56 });
// #endregion
save("fallback-before", before);
save("fallback-after", after);

// #region notdef
// Characters that no registered font covers are drawn with the .notdef glyph of the
// first family in the element's stack: each font has its own (usually a box).
const notdef = robotoOnly.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", padding: "8px 20px", width: "100%", height: "100%", backgroundColor: "#fff", fontSize: 26 },
    children: [
      { type: "text", text: "Inter: ქართული Հայերեն", style: { fontFamily: "Inter" } },
      { type: "text", text: "Roboto: ქართული Հայերեն", style: { fontFamily: "Roboto" } },
    ],
  },
  { width: 560, height: 90 },
);
// #endregion
save("notdef", notdef);

// #region root-stack
// An element without fontFamily uses the fontFamilies option (the root font stack).
// Generic names such as "sans-serif" are not mapped to anything.
const rootStack = renderer.renderSync(
  {
    type: "container",
    style: { display: "flex", flexDirection: "column", padding: "8px 20px", width: "100%", height: "100%", backgroundColor: "#fff", fontSize: 26 },
    children: [
      { type: "text", text: "No fontFamily: uses Brand (root stack)" },
      { type: "text", text: "fontFamily sans-serif: falls back too", style: { fontFamily: "sans-serif" } },
      { type: "text", text: "fontFamily Inter", style: { fontFamily: "Inter" } },
    ],
  },
  { width: 560, height: 120, fontFamilies: ["Brand", "Inter"] },
);
// #endregion
save("root-stack", rootStack);

// #region fonts-option
// The async API also accepts fonts per call. They are registered on the renderer (and stay
// registered); without fontFamilies their families become the root font stack.
const fresh = new Renderer();
const png = await fresh.render(
  { type: "container", style: { display: "flex", padding: 12, width: "100%", height: "100%", backgroundColor: "#fff", fontSize: 26 },
    children: [{ type: "text", text: "Roboto Bold via the fonts option" }] },
  { width: 560, height: 56, fonts: [{ name: "Roboto", data: () => readFileSync("assets/fonts/Roboto-Bold.ttf") }] },
);
// #endregion
save("fonts-option", png);

// #region unregister
renderer.unregisterFont("Brand"); // true: every face of the family is removed
renderer.unregisterFont({ name: "Nope" }); // false: nothing to remove
fresh.clearFonts(); // no font at all now: text is not drawn until you register one again
// #endregion
log("unregister again", renderer.unregisterFont("Brand"));

// #region memory
const m = new Renderer();
const start = m.memoryBytes();
m.registerFont(readFileSync("assets/fonts/NotoSans-Regular.ttf")); // a 607 KiB file
m.registerFont(readFileSync("assets/fonts/NotoSans-Bold.ttf")); // a 617 KiB file
const grown = m.memoryBytes() - start; // the wasm memory grows by about the font bytes
// #endregion
log("memory start / grown (bytes)", [start, grown]);

// Registering from a URL (fetch): verified against a local HTTP server; shown in the page as a plain snippet.
{
  const server = http.createServer((_, res) => res.end(readFileSync("assets/fonts/Roboto-Italic.ttf"))).listen(0);
  await new Promise((ok) => server.on("listening", ok));
  const r = new Renderer();
  const p = r.registerFont(`http://127.0.0.1:${server.address().port}/Roboto-Italic.ttf`);
  log("registerFont(url) returns a Promise", p instanceof Promise);
  log("registerFont(url)", await p);
  server.close();
}

// Profile behaviour (logged, not shown).
{
  const core = await import("bm-engine/core");
  const rc = new core.Renderer();
  log("core features.variableFonts", core.features.variableFonts);
  const vfPath = "ref/takumi/assets/fonts/geist/Geist[wght].woff2";
  if (existsSync(vfPath)) log("core woff2", expectThrow(() => rc.registerFont(readFileSync(vfPath))));
  log("invalid font", expectThrow(() => rc.registerFont(new Uint8Array([1, 2, 3, 4]))));
}

const ARCHIVO = "ref/takumi/assets/fonts/archivo/Archivo-VariableFont_wdth,wght.ttf";
if (existsSync(ARCHIVO)) {
  // #region variable
  // Archivo is a variable font with wght (100-900) and wdth (62-125) axes (OFL; this file
  // comes from takumi's test assets; any variable TTF / WOFF2 works the same way).
  const archivo = readFileSync("ref/takumi/assets/fonts/archivo/Archivo-VariableFont_wdth,wght.ttf");
  renderer.registerFont({ name: "Archivo", data: archivo }); // no weight: keep the axes free

  const line = (text, style) => ({ type: "text", text, style: { fontFamily: "Archivo", fontSize: 26, ...style } });
  const variable = {
    type: "container",
    style: { display: "flex", flexDirection: "column", padding: "10px 20px", width: "100%", height: "100%", backgroundColor: "#fff" },
    children: [
      line("fontWeight 100", { fontWeight: 100 }),
      line("fontWeight 450", { fontWeight: 450 }),
      line("fontWeight 900", { fontWeight: 900 }),
      line("fontStretch 62.5%", { fontStretch: "62.5%" }),
      line("fontStretch 125%", { fontStretch: "125%" }),
      line("fontVariationSettings 'wght' 250, 'wdth' 80", { fontVariationSettings: "'wght' 250, 'wdth' 80" }),
    ],
  };
  const variablePng = renderer.renderSync(variable, { width: 560, height: 200 });
  // #endregion
  save("variable", variablePng);

  // #region variable-core
  // The same tree on core: the font registers, but only its default instance is drawn.
  const { Renderer: CoreRenderer } = await import("bm-engine/core");
  const coreRenderer = new CoreRenderer();
  coreRenderer.registerFont({ name: "Archivo", data: archivo });
  const variableCore = coreRenderer.renderSync(variable, { width: 560, height: 200 });
  // #endregion
  save("variable-core", variableCore);
} else console.log("skip: variable font example (ref/takumi not present)");

const GEIST = "ref/takumi/assets/fonts/geist/Geist[wght].woff2";
if (existsSync(GEIST)) {
  // #region woff
  // WOFF / WOFF2 work directly on standard and full ...
  renderer.registerFont(readFileSync("ref/takumi/assets/fonts/geist/Geist[wght].woff2"));

  // ... and on core after loading the 84 KiB WOFF add-on once per process.
  const { Renderer: CoreRenderer } = await import("bm-engine/core");
  const { loadWoff } = await import("bm-engine/woff");
  await loadWoff();
  const geist = new CoreRenderer().registerFont(readFileSync("ref/takumi/assets/fonts/geist/Geist[wght].woff2"));
  // geist: [{ name: "Geist", faces: [{ weight: 400, ... }], ... }]
  // #endregion
  log("woff on core", geist);
} else console.log("skip: woff example (ref/takumi not present)");

const EMOJI = "ref/takumi/assets/fonts/noto-sans/NotoColorEmoji.ttf";
if (existsSync(EMOJI)) {
  // #region emoji
  // Noto Color Emoji (CBDT bitmaps, 10 MB; OFL). Registering it is enough: fallback finds it.
  renderer.registerFont(readFileSync("ref/takumi/assets/fonts/noto-sans/NotoColorEmoji.ttf"));
  // ZWJ sequences (👩‍💻), skin tones (👍🏽), flags (🇻🇳), keycaps (1️⃣) and VS16 (❤️) are one glyph each
  const emoji = renderer.renderSync(
    { type: "container", style: { display: "flex", alignItems: "center", padding: "0 20px", width: "100%", height: "100%", backgroundColor: "#fff" },
      children: [{ type: "text", text: "Ship it 🚀 🎉 👩‍💻 👍🏽 🇻🇳 1️⃣ ❤️", style: { fontFamily: "Inter", fontSize: 30 } }] },
    { width: 560, height: 64 },
  );
  // #endregion
  save("emoji", emoji);

  // Same on core (not shown as code): CBDT bitmaps have no outlines, so no emoji is drawn.
  const coreMod = await import("bm-engine/core");
  const rc = new coreMod.Renderer();
  rc.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
  rc.registerFont(readFileSync(EMOJI));
  save("emoji-core", rc.renderSync(
    { type: "container", style: { display: "flex", alignItems: "center", padding: "0 20px", width: "100%", height: "100%", backgroundColor: "#fff" },
      children: [{ type: "text", text: "Ship it 🚀 🎉 👩‍💻 👍🏽 🇻🇳 1️⃣ ❤️", style: { fontFamily: "Inter", fontSize: 30 } }] },
    { width: 560, height: 64 },
  ));
} else console.log("skip: emoji example (ref/takumi not present)");
