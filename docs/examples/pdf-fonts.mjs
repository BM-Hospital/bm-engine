// Examples for docs/{en,vi}/pdf/fonts.md. Run: node docs/examples/run-all.mjs pdf-fonts
import "./_lib.mjs";
import assert from "node:assert/strict";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
const count = (b, re) => (latin1(b).match(re) || []).length;

// #region subset
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-render/pdf";

const pdf = new PdfRenderer();
const inter = readFileSync("assets/fonts/Inter-Regular.ttf"); // about 400 KB
pdf.registerFont({ name: "Inter", data: inter });

const small = await pdf.render(`<p style="font: 16px Inter">Hello, subset</p>`, { viewport: { width: 300 } });
// small.length is a few KB: only the glyphs the document uses are embedded
// #endregion
assert.ok(small.length < inter.length / 10, `${small.length} bytes`);
assert.equal(count(small, /\/Subtype\/CIDFontType2/g), 1);

// #region variable
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
// #endregion
assert.equal(count(weights, /\/Subtype\/CIDFontType2/g), 2);

// #region uncovered-error
const devanagari = `<p style="font: 20px Inter">abक</p>`;
let message;
try {
  await pdf.render(devanagari, { viewport: { width: 300 } });
} catch (e) {
  message = e.message;
}
// bm-render: No font the text can use draws क (U+0915). Check each font's unicodeRange and the font-family stack,
// or register a font that draws them.
// #endregion
assert.match(message, /No font the text can use draws क \(U\+0915\)/);

// #region uncovered-modes
const blank = await pdf.render(devanagari, { viewport: { width: 300 }, uncoveredText: "blank" });             // draws "ab"
const boxes = await pdf.render(devanagari, { viewport: { width: 300 }, uncoveredText: "placeholder" });       // draws "ab" and the font's .notdef box
// #endregion
assert.ok(boxes.length !== blank.length);

// #region fallback
pdf.registerFont({ name: "Noto Sans", data: readFileSync("assets/fonts/NotoSans-Regular.ttf") });
// "ⱥ" (U+2C65) is not in Inter but is in Noto Sans: every registered family is a fallback
const mixed = pdf.renderSync(`<p style="font: 20px Inter">Inter text and ⱥ</p>`, { viewport: { width: 400 } });
// Inter draws the Latin text and Noto Sans draws ⱥ: two font programs in the file
// #endregion
assert.equal(count(mixed, /\/Subtype\/CIDFontType2/g), 2);

// #region font-families
const stacked = pdf.renderSync(`<p>No font-family on this paragraph</p>`, {
  viewport: { width: 400 },
  fontFamilies: ["Noto Sans"], // the font stack used where the document names none
});
// #endregion
assert.match(latin1(stacked), /BaseFont\/[A-Z]{6}\+NotoSans/);

// #region archival-placeholder
let archival;
try {
  await pdf.render(devanagari, { viewport: { width: 300 }, pdfa: "2b", uncoveredText: "placeholder" });
} catch (e) {
  archival = e.message;
}
// bm-render: No font the text can use draws क (U+0915), and PDF/A-2b forbids the placeholder glyph. Register a font that draws them, or set uncoveredText to "blank".
// #endregion
assert.match(archival, /PDF\/A-2b forbids the placeholder glyph/);
console.log("pdf-fonts: ok", small.length, inter.length, weights.length);
