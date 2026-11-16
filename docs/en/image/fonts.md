# Fonts

[English](fonts.md) · [Tiếng Việt](../../vi/image/fonts.md)

bm-render draws text only with fonts you register: it bundles **no** font and never reads system fonts.
This page covers loading fonts (TTF, OTF/CFF, TTC, WOFF/WOFF2, variable and colour fonts), how a
`font-family` is matched to a face, how fallback works when a glyph is missing, what synthetic bold and
italic look like, what each [profile](../profiles-and-size.md) supports, and how much memory fonts cost.
Every example below was run by `docs/examples/fonts.mjs`; the images are its output.

[[toc]]

## Registering a font

Create a `Renderer` once and register fonts on it. `registerFont` takes the font bytes (a `Uint8Array`,
`ArrayBuffer` or Node `Buffer`) and returns the families it added:

<!-- @example fonts#setup -->
```js
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
const families = renderer.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf"));
// families: [{ name: "Inter", faces: [{ weight: 400, style: "normal", width: 100, index: 0 }],
//              weight: 400, style: "normal" }]
```

The family name, weight and style come from the font's own tables (`name` and `OS/2`). Fonts belong to
the renderer: a second `new Renderer()` starts with no fonts at all. Register once at startup and reuse
the renderer for every render (see [Performance](./performance.md)).

Without a registered font, text is silently **not drawn**. Register at least one font before rendering text.

### Several faces of one family

Registering another file under an existing family name adds a face to that family. You can also
override the name, weight and style the file declares, for example to give a font a brand name or to
register one file as a specific weight:

<!-- @example fonts#faces -->
```js
// More faces of the same family: name, weight and style are read from each file.
renderer.registerFont(readFileSync("assets/fonts/Inter-SemiBold.ttf"));
renderer.registerFont(readFileSync("assets/fonts/Inter-Bold.ttf"));
const inter = renderer.registerFont(readFileSync("assets/fonts/Inter-Italic.ttf"));
// inter[0].faces: 400 normal, 600 normal, 700 normal, 400 italic

// Override what the file says: register Roboto Bold as weight 900 of a family called "Brand".
const brand = renderer.registerFont({ name: "Brand", data: readFileSync("assets/fonts/Roboto-Bold.ttf"), weight: 900 });
// brand: [{ name: "Brand", faces: [{ weight: 900, style: "normal", width: 100, index: 0 }], ... }]
```

| Field of the details object | Meaning |
|:--|:--|
| `data` | the font bytes (or, with the async API, a function / promise returning them) |
| `name` | family name to register under (default: the font's family name) |
| `weight` | number overriding the weight from the file |
| `style` | `"normal"`, `"italic"` or `"oblique"`, overriding the file |
| `unicodeRange`, `subsetOf`, `generic` | accepted accepted for API compatibility; ignored and **ignored** |

A `.ttc` / `.otc` collection registers every face it contains: a two-face collection returns two
families, `Geist` (face `index: 0`) and `Geist Mono` (face `index: 1`).

## Font formats and profiles

| Format | core | standard | full |
|:--|:-:|:-:|:-:|
| TrueType `.ttf`, collections `.ttc` | yes | yes | yes |
| OpenType with CFF / CFF2 outlines (`.otf`) | no: throws `unsupported font format` | yes | yes |
| WOFF / WOFF2 | with the [WOFF add-on](#woff-and-woff2) | yes | yes |
| Variable fonts | registered, drawn at the default instance | yes | yes |
| Colour glyphs: COLR v0/v1 | plain outlines, no colour | plain outlines, no colour | yes |
| Colour glyphs: bitmap CBDT / sbix | not drawn | yes | yes |

Bytes that are not a font throw `bm-render: invalid font data`. Check what the loaded binary supports
with `features.woff`, `features.cff`, `features.variableFonts` and `features.colorFonts`.

## How a face is chosen

Within a family, bm-render applies CSS font matching: first `font-stretch`, then `font-style`, then
`font-weight`. For the weight this means: a requested weight between 400 and 500 tries the weights up to
500, then lighter ones, then heavier ones; below 400 lighter weights are preferred, above 500 heavier
ones. With Inter Regular (400), SemiBold (600), Bold (700) and Italic (400 italic) registered:

<!-- @example fonts#matching -->
```js
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
```

![Weights 300 and 500 use Inter Regular, 600 SemiBold, 800 Bold; italic uses Inter Italic; bold italic is the italic face made bold](/img/guide/fonts-matching.png)

The last line asks for weight 700 italic. Style wins over weight, so the Italic face (400) is chosen and
bold is **synthesised** on top of it.

### Synthetic bold and italic

When the chosen face is lighter than the requested weight, bm-render emboldens the outlines; when no
italic face exists, it slants the regular face (oblique). Here the family "Solo" has only Roboto Regular:

<!-- @example fonts#synthesis -->
```js
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
```

![Roboto Regular, a synthetic bold line, a synthetic oblique line and a bold line despite fontSynthesis none](/img/guide/fonts-synthesis.png)

::: warning `font-synthesis` does not turn off bold and italic
`fontSynthesisWeight`, `fontSynthesisStyle` and the weight / style parts of `fontSynthesis` are parsed
but have no effect in 0.1.0: bold and italic synthesis is always on (last line above). Register real bold / italic files when the synthetic ones are
not good enough; they always look better.
:::

Small caps are synthesised too: `fontVariant: "small-caps"` uses the font's `smcp` feature when it has
one and otherwise draws uppercase letters at 70 % of the font size (Inter and Roboto have no small caps).
Unlike bold and italic, this synthesis can be turned off, with `fontSynthesisSmallCaps: "none"` or a
`fontSynthesis` value without `small-caps`. See [Typography → Small caps](./typography.md#small-caps).

## Fallback

Each character is looked up in the element's `font-family` list first. If none of those families has a
glyph for it, bm-render tries **every registered family, in registration order**. This makes it enough to
register a font that covers a script or symbol set: you do not have to add it to every `fontFamily`.

Roboto has no glyphs for many symbols. With only Roboto registered they are boxes; after registering
Inter (which has them), the same tree renders the symbols from Inter:

<!-- @example fonts#fallback -->
```js
const symbols = { type: "text", text: "Roboto: ① ★ ✓ ∑ → ⌘ ⇧ ↗ × ● ▶ ◆ ♥", style: { fontFamily: "Roboto", fontSize: 26 } };
const card = (child) => ({ type: "container", style: { display: "flex", alignItems: "center", padding: "0 20px", width: "100%", height: "100%", backgroundColor: "#fff" }, children: [child] });

const robotoOnly = new Renderer();
robotoOnly.registerFont(readFileSync("assets/fonts/Roboto-Regular.ttf"));
const before = robotoOnly.renderSync(card(symbols), { width: 560, height: 56 });

robotoOnly.registerFont(readFileSync("assets/fonts/Inter-Regular.ttf")); // Inter covers the symbols
const after = robotoOnly.renderSync(card(symbols), { width: 560, height: 56 });
```

![Roboto only: symbols drawn as boxes](/img/guide/fonts-fallback-before.png)

![Roboto then Inter: the symbols come from Inter](/img/guide/fonts-fallback-after.png)

### When no font has the glyph

A character that no registered font covers is drawn with the **`.notdef` glyph** of the first family in
the element's stack (usually a box; Inter's says "NOGLYPH"). It still takes up space, so the layout
does not change when you later add a font that covers it:

<!-- @example fonts#notdef -->
```js
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
```

![Georgian and Armenian text drawn as notdef boxes in Inter and in Roboto](/img/guide/fonts-notdef.png)

Register a font for every script your text can contain (Noto Sans has families for almost every
script). For Vietnamese, the fonts in this repository (Inter, Noto Sans, Roboto) already cover all
precomposed letters; see [Typography](./typography.md#vietnamese).

### The root font stack and generic names

An element without `fontFamily` (directly or inherited) uses the `fontFamilies` render option. Generic
names such as `sans-serif`, `serif` or `monospace` are **not mapped** to any font: they simply match
nothing and the character falls through to the registration-order fallback (Inter here, the first
family registered on this renderer):

<!-- @example fonts#root-stack -->
```js
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
```

![The first line uses Brand (Roboto Bold), the others Inter](/img/guide/fonts-root-stack.png)

::: tip
Because generic names are not mapped, Tailwind's `font-sans` / `font-mono` classes and stylesheets that
end in `sans-serif` work only through fallback. Use the real family name (`fontFamily: "Inter"`) where
it matters, or put the font you want first in `fontFamilies`.
:::

## The `fonts` render option

With the async methods (`render`, `measure`, `renderAsDataUrl`, `prepare`, ...) you can pass fonts per
call. Each entry is anything `registerFont` accepts: bytes, a URL, or a details object whose `data` may be
a function or a promise. They are registered on the renderer before rendering and **stay registered**
afterwards. When `fontFamilies` is not given, the families of these fonts become the root font stack, so
text without a `fontFamily` uses them:

<!-- @example fonts#fonts-option -->
```js
// The async API also accepts fonts per call. They are registered on the renderer (and stay
// registered); without fontFamilies their families become the root font stack.
const fresh = new Renderer();
const png = await fresh.render(
  { type: "container", style: { display: "flex", padding: 12, width: "100%", height: "100%", backgroundColor: "#fff", fontSize: 26 },
    children: [{ type: "text", text: "Roboto Bold via the fonts option" }] },
  { width: 560, height: 56, fonts: [{ name: "Roboto", data: () => readFileSync("assets/fonts/Roboto-Bold.ttf") }] },
);
```

![Text in Roboto Bold](/img/guide/fonts-fonts-option.png)

The synchronous methods do not accept `fonts`; call `registerFont` first. Because entries are registered
again on every call, prefer `registerFont` at startup (or `prepare()` once) for fonts used in every
render.

## Removing fonts

<!-- @example fonts#unregister -->
```js
renderer.unregisterFont("Brand"); // true: every face of the family is removed
renderer.unregisterFont({ name: "Nope" }); // false: nothing to remove
fresh.clearFonts(); // no font at all now: text is not drawn until you register one again
```

`unregisterFont` takes a family name or `{ name }` and removes every face of that family; `clearFonts()`
removes all fonts. No fonts remain afterwards.

## Variable fonts

On `standard` and `full`, a variable font follows `font-weight` (`wght` axis), `font-stretch` (`wdth`),
`font-optical-sizing` (`opsz`) and `font-variation-settings` (any axis). Register it **without** a
`weight` so that it can serve every weight. The example uses Archivo, a variable font with `wght` and
`wdth` axes from local font files; any variable TTF or WOFF2 works the same way:

<!-- @example fonts#variable -->
```js
// Archivo is a variable font with wght (100-900) and wdth (62-125) axes (OFL; this file
const archivo = readFileSync("./fonts/Archivo-Variable.ttf");
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
```

![Archivo at weights 100, 450, 900, condensed, expanded and with explicit variation settings](/img/guide/fonts-variable.png)

On `core`, the font registers without error but every line is drawn with the **default instance**
(Archivo's default is weight 600, normal width, which is also the weight `registerFont` reports):

<!-- @example fonts#variable-core -->
```js
// The same tree on core: the font registers, but only its default instance is drawn.
const { Renderer: CoreRenderer } = await import("bm-render/core");
const coreRenderer = new CoreRenderer();
coreRenderer.registerFont({ name: "Archivo", data: archivo });
const variableCore = coreRenderer.renderSync(variable, { width: 560, height: 200 });
```

![On core every line has the same weight and width](/img/guide/fonts-variable-core.png)

## WOFF and WOFF2

`standard` and `full` decode WOFF and WOFF2 themselves. `core` has no decoder, but the separate 84 KiB
WOFF add-on (`bm-render/woff`) converts WOFF / WOFF2 to TTF / OTF before registration, for every entry in
the process:

<!-- @example fonts#woff -->
```js
// WOFF / WOFF2 work directly on standard and full ...
renderer.registerFont(readFileSync("./fonts/Geist.woff2"));

// ... and on core after loading the 84 KiB WOFF add-on once per process.
const { Renderer: CoreRenderer } = await import("bm-render/core");
const { loadWoff } = await import("bm-render/woff");
await loadWoff();
const geist = new CoreRenderer().registerFont(readFileSync("./fonts/Geist.woff2"));
// geist: [{ name: "Geist", faces: [{ weight: 400, ... }], ... }]
```

Without the add-on, `core` throws
`bm-render: this build has no WOFF/WOFF2 font support (use the standard / full build, or load the WOFF
add-on: ...)`. The add-on does not add CFF support: a WOFF2 with CFF outlines still needs `standard` or
`full`. More in [Profiles and size](../profiles-and-size.md#the-woff-add-on).

## Colour fonts and emoji

Colour emoji need a colour font (COLR v0/v1, CBDT or sbix, for example Noto Color Emoji or Twemoji) and
a profile that draws its format: bitmap fonts (CBDT, sbix) are drawn in colour on `standard` and `full`,
COLR fonts only on `full`. As with any other font, registering it is enough, since fallback finds the
emoji glyphs:

<!-- @example fonts#emoji -->
```js
// Noto Color Emoji (CBDT bitmaps, 10 MB; OFL). Registering it is enough: fallback finds it.
renderer.registerFont(readFileSync("./fonts/NotoColorEmoji.ttf"));
// ZWJ sequences (👩‍💻), skin tones (👍🏽), flags (🇻🇳), keycaps (1️⃣) and VS16 (❤️) are one glyph each
const emoji = renderer.renderSync(
  { type: "container", style: { display: "flex", alignItems: "center", padding: "0 20px", width: "100%", height: "100%", backgroundColor: "#fff" },
    children: [{ type: "text", text: "Ship it 🚀 🎉 👩‍💻 👍🏽 🇻🇳 1️⃣ ❤️", style: { fontFamily: "Inter", fontSize: 30 } }] },
  { width: 560, height: 64 },
);
```

![Text with colour emoji: rocket, party popper, woman technologist, thumbs up with a medium skin tone, Vietnamese flag, keycap 1 and heart](/img/guide/fonts-emoji.png)

Emoji presentation depends on the registered font and Unicode variation selectors. Test the exact sequences your application uses.

On `core` colour tables are ignored. A COLR font is drawn from its plain outlines, without colour, but
a bitmap-only font such as Noto Color Emoji (CBDT) has no outlines at all, so its emoji are **not drawn**
(the same tree on `core`; the digit of the keycap and the heart come from Inter, the keycap mark itself
shows as a missing-glyph box):

![On core the emoji are missing; only the digit 1, a missing-glyph box and a black heart remain](/img/guide/fonts-emoji-core.png)

## Loading fonts in the browser and from URLs

In Node read files with `readFileSync` / `readFile`. In browsers, fetch the bytes:

```js
const bytes = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
renderer.registerFont({ name: "Inter", data: bytes });
```

`registerFont` also accepts a URL string or `URL` object. It then fetches the file with the global
`fetch` and returns a **Promise** (`http:` / `https:` in Node; `file:` URLs are not supported by Node's
`fetch`). The example script checks this against a local HTTP server:

```js
const families = await renderer.registerFont("https://example.com/fonts/Inter-Regular.ttf");
```

bm-render does not download `@font-face` rules from stylesheets: their descriptors are read, the files
are not fetched. Register the files yourself.

For Google Fonts, download the files once (TTF from the family's download, or the WOFF2 URLs in the CSS
`https://fonts.googleapis.com/css2?family=...`) and ship them with your app. WOFF2 needs `standard`,
`full` or the add-on.

## Memory cost

A registered font is copied into wasm memory once and parsed in place, so it costs about its file size,
for as long as it stays registered (per renderer: two renderers with the same font hold two copies):

<!-- @example fonts#memory -->
```js
const m = new Renderer();
const start = m.memoryBytes();
m.registerFont(readFileSync("assets/fonts/NotoSans-Regular.ttf")); // a 607 KiB file
m.registerFont(readFileSync("assets/fonts/NotoSans-Bold.ttf")); // a 617 KiB file
const grown = m.memoryBytes() - start; // the wasm memory grows by about the font bytes
```

In the run that produced these docs, the two Noto Sans files (1.2 MB together) grew the memory by
1.25 MiB, and Noto Color Emoji (10 MB) by about 10 MiB. Glyph outlines are rasterised on demand into an
8 MiB glyph cache per renderer. WebAssembly memory never shrinks, so unregistering a font makes room for
later allocations but does not return memory to the system (see
[API: memory](./api.md#memory-instances-and-threads)).

Practical consequences:

- Register only the faces you use. A full CJK font is 5–20 MB; subset it (for example with
  `pyftsubset`) when you know the characters in advance.
- Create one renderer per font set and reuse it; do not create a renderer per request.
- In worker pools every worker registers its own fonts, so the cost is multiplied by the number of
  workers.

## Checklist

| Symptom | Cause | Fix |
|:--|:--|:--|
| No text at all | no font registered on this renderer | `registerFont(...)` before rendering |
| Boxes instead of letters | no registered font covers the characters | register a font for that script |
| Wrong family | `fontFamily` does not match the registered name | use the `name` returned by `registerFont` |
| Bold looks smeared | synthetic bold | register the real bold file |
| `.otf` throws on core | CFF outlines | use `standard` / `full` |
| `.woff2` throws on core | no WOFF decoder | `loadWoff()` or `standard` / `full` |
| Emoji missing or black | not `full`, or no colour font | `full` profile + a colour emoji font |

See also: [Typography](./typography.md), [Troubleshooting](../troubleshooting.md#text-is-missing-or-shows-as-boxes),
[API: `registerFont`](./api.md#registerfont).
