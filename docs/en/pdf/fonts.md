# Fonts in PDF

[English](fonts.md) · [Tiếng Việt](../../vi/pdf/fonts.md)

In a PDF, text stays text: the file holds the glyphs of the fonts you registered, cut down to the
characters the document uses, plus the mapping that lets a viewer select, search and copy the words.
This page covers how fonts get into the file (subsetting, variable fonts, colour and bitmap glyphs), what
the fallback rules are, and what happens when no font has a character. You register fonts exactly as for
images ([Fonts](../image/fonts.md)); this page only covers what is specific to PDF. It needs the [`pdf`
profile](index.md). Every Node.js snippet is a section of `docs/examples/pdf-fonts.mjs` in the repository
and was executed by it.

- [Subsetting](#subsetting)
- [Variable fonts](#variable-fonts)
- [Colour and bitmap glyphs](#colour-and-bitmap-glyphs)
- [Text extraction](#text-extraction)
- [Fallback fonts](#fallback-fonts)
- [Characters no font covers](#characters-no-font-covers)
- [PDF/A and font licences](#pdfa-and-font-licences)

## Subsetting

bm-engine ships no font and no PDF viewer has yours, so every font a page uses is embedded. It is
embedded as a subset: only the glyphs the document actually draws, renumbered and written as a CID-keyed
font. The subsetter is a port of the Rust `subsetter` crate (the one takumi-pdf uses) and reads TrueType
(`glyf`) fonts, TrueType collections and CFF (`.otf`) fonts; WOFF and WOFF2 are decoded first. The
`cmap` and layout tables are dropped from the output, since the text is already shaped.

<!-- @example pdf-fonts#subset -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
const inter = readFileSync("assets/fonts/Inter-Regular.ttf"); // about 400 KB
pdf.registerFont({ name: "Inter", data: inter });

const small = await pdf.render(`<p style="font: 16px Inter">Hello, subset</p>`, { viewport: { width: 300 } });
// small.length is a few KB: only the glyphs the document uses are embedded
```

In the example a 400 KB font produces a file of a few KB. The glyph set is per font instance and per
document: a longer document embeds more glyphs of the same font, not more fonts.

## Variable fonts

A variable font follows `font-weight`, `font-stretch`, `font-optical-sizing` and `font-variation-settings`
as for images. In the PDF, each distinct location of the font that the document uses is **instanced**:
the glyphs are drawn at that location and written into their own static font program. Two weights of one
variable font are therefore two embedded fonts. A CFF2 variable font is written as a TrueType font. Register
a variable font without a `weight` so that it can serve every weight, as described in
[Fonts](../image/fonts.md#variable-fonts).

<!-- @example pdf-fonts#variable -->
```js
const archivo = readFileSync("ref/takumi/assets/fonts/archivo/Archivo-VariableFont_wdth,wght.ttf");
pdf.registerFont({ name: "Archivo", data: archivo }); // no weight: the axes stay free

const weights = await pdf.render(
  `<div style="font: 20px Archivo">
     <p style="font-weight: 300">Light 300</p>
     <p style="font-weight: 700">Bold 700</p>
   </div>`,
  { viewport: { width: 300 } },
);
// each weight actually used is an instance of the variable font: two separate font programs
```

## Colour and bitmap glyphs

Colour fonts need the `colorFonts` feature, which the `pdf` profile has. COLR v0 and v1 glyphs (layers,
gradients, composites) are drawn as vector graphics, and bitmap glyphs (CBDT and sbix PNG images) as
images. Both are put in Type 3 fonts, with at most 256 glyphs per Type 3 font, so a long emoji text may
use several. Their text is still mapped to Unicode. SVG-in-OpenType glyphs are not rendered: those
glyphs are drawn as their ordinary outline, if the font has one.

## Text extraction

Every font carries a `ToUnicode` map, and runs that would not extract correctly (ligatures and clusters
that map one glyph to several characters) carry `/ActualText` with the
source text. Copying "difficult office" out of a viewer therefore gives the letters, not the `ffi`
ligature glyph, and Arabic and Vietnamese text extract as typed. When a line of text is cut by a page
break, the page that holds its baseline has the text and the other page shows the visible part as
outlines, which does not extract.

## Fallback fonts

For each character the engine takes the first font in the font stack that has it, then the other
registered fonts. You do not have to name a fallback family: registering a second font is enough.

<!-- @example pdf-fonts#fallback -->
```js
pdf.registerFont({ name: "Noto Sans", data: readFileSync("assets/fonts/NotoSans-Regular.ttf") });
// "ⱥ" (U+2C65) is not in Inter but is in Noto Sans: every registered family is a fallback
const mixed = pdf.renderSync(`<p style="font: 20px Inter">Inter text and ⱥ</p>`, { viewport: { width: 400 } });
// Inter draws the Latin text and Noto Sans draws ⱥ: two font programs in the file
```

`fontFamilies: ["Inter", "Noto Sans"]` sets the ordered font stack for a render where the document names
none (for example a node without `fontFamily`):

<!-- @example pdf-fonts#font-families -->
```js
const stacked = pdf.renderSync(`<p>No font-family on this paragraph</p>`, {
  viewport: { width: 400 },
  fontFamilies: ["Noto Sans"], // the font stack used where the document names none
});
```

Fonts that are not registered are never looked up on the system; there is no default font.

## Characters no font covers

A character that no registered font draws is handled by `uncoveredText`:

| Value | What happens |
|:--|:--|
| `"error"` (default) | The render fails and names the character. |
| `"placeholder"` | The font's glyph 0 (`.notdef`, usually an empty box) is drawn. |
| `"blank"` | Nothing is drawn for it. |

<!-- @example pdf-fonts#uncovered-error -->
```js
const devanagari = `<p style="font: 20px Inter">abक</p>`;
let message;
try {
  await pdf.render(devanagari, { viewport: { width: 300 } });
} catch (e) {
  message = e.message;
}
// bm-engine: No font the text can use draws क (U+0915). Check each font's unicodeRange and the font-family stack,
// or register a font that draws them.
```

<!-- @example pdf-fonts#uncovered-modes -->
```js
const blank = await pdf.render(devanagari, { viewport: { width: 300 }, uncoveredText: "blank" });             // draws "ab"
const boxes = await pdf.render(devanagari, { viewport: { width: 300 }, uncoveredText: "placeholder" });       // draws "ab" and the font's .notdef box
```

Failing is the default because silently dropping characters in a document is worse than an error you
see in testing. `placeholder` is rejected, with a message naming the standard, whenever `pdfa` is set or
`tagged` is `"ua1"` or `"ua2"`, since those standards forbid glyph 0 (only when the document actually has
an uncovered character):

<!-- @example pdf-fonts#archival-placeholder -->
```js
let archival;
try {
  await pdf.render(devanagari, { viewport: { width: 300 }, pdfa: "2b", uncoveredText: "placeholder" });
} catch (e) {
  archival = e.message;
}
// bm-engine: No font the text can use draws क (U+0915), and PDF/A-2b forbids the placeholder glyph. Register a font that draws them, or set uncoveredText to "blank".
```

## PDF/A and font licences

PDF/A and PDF/UA also check the fonts you embed. A font whose OS/2 `fsType` says "restricted license
embedding" fails the render with a validation error under any `pdfa` level or `tagged: "ua1"` / `"ua2"`
(a plain PDF embeds it regardless: check your font licence yourself). Glyphs without a Unicode
mapping and `.notdef` glyphs are violations too. The error does not
name the font; the message is only the count of violations ([Accessibility and
archival](accessibility.md#how-far-the-checks-go)).
