// Examples for docs/{en,vi}/pdf.md. Run: node docs/examples/run-all.mjs pdf
import "./_lib.mjs";
import assert from "node:assert/strict";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
const pageCount = (b) => (latin1(b).match(/\/Type\/Page[^s]/g) || []).length;
const mediaBox = (b) => /\/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]/.exec(latin1(b)).slice(1).map(Number);

// #region setup
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
// #endregion

// #region html
const bytes = await pdf.render(
  `<style>
     body { font-family: Inter; font-size: 14px; color: #0f172a; }
     h1 { font-size: 28px; }
   </style>
   <h1>Quarterly report</h1>
   <p>This page is vector text: it can be selected, searched and copied.</p>`,
);
writeFileSync("report.pdf", bytes); // A4, 10 mm margins
// #endregion
(await import("node:fs")).rmSync("report.pdf"); // keep the repo root clean
assert.equal(latin1(bytes.subarray(0, 5)), "%PDF-");
assert.equal(pageCount(bytes), 1);
assert.deepEqual(mediaBox(bytes).map((v) => Math.round(v * 100) / 100), [595.28, 841.89]);

// #region node-tree
const card = {
  type: "container",
  style: { display: "flex", flexDirection: "column", gap: 8, padding: 24, backgroundColor: "#f1f5f9" },
  children: [
    { type: "text", text: "Hello PDF", style: { fontFamily: "Inter", fontSize: 32, fontWeight: 700 } },
    { type: "text", text: "A node tree renders the same way as HTML.", style: { fontFamily: "Inter", fontSize: 14 } },
  ],
};
const letter = await pdf.render(card, { size: "letter", landscape: true, margin: 24 });
// #endregion
assert.deepEqual(mediaBox(letter).map(Math.round), [792, 612]);

// #region custom-size
const ticket = await pdf.render(card, {
  size: { width: 400, height: 240 }, // CSS px: 300 x 180 pt
  margin: { top: 12, right: 12, bottom: 12, left: 12 },
  backgroundColor: "#ffffff",       // paper colour under everything
});
// #endregion
assert.deepEqual(mediaBox(ticket), [300, 180]);

// #region viewport
const poster = await pdf.render(card, { viewport: { width: 600 } }); // one page, as tall as the content
// #endregion
assert.equal(pageCount(poster), 1);
assert.equal(mediaBox(poster)[0], 450);

// #region measure
const { width, height } = await pdf.measure(card, { size: "a4" });
// #endregion
assert.ok(width > 0 && height > 0);

// #region sync
const same = pdf.renderSync(card, { viewport: { width: 600 } });
// #endregion
assert.equal(same.length, poster.length);

// #region not-supported
import { Renderer } from "bm-engine/full"; // the full profile has no PDF writer
let message;
try {
  new Renderer().renderPdfSync(card);
} catch (e) {
  message = e.message;
}
// message: bm-engine: renderPdf is not supported by this build (use the pdf build: import from "bm-engine/pdf")
// #endregion
assert.match(message, /renderPdf is not supported by this build/);
console.log("pdf: ok", bytes.length, letter.length, ticket.length, poster.length, width, height);
