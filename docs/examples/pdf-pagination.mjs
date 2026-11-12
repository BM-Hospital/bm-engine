// Examples for docs/{en,vi}/pdf-pagination.md. Run: node docs/examples/run-all.mjs pdf-pagination
import "./_lib.mjs";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
const pageCount = (b) => (latin1(b).match(/\/Type\/Page[^s]/g) || []).length;
const mediaBox = (b) => /\/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]/.exec(latin1(b)).slice(1).map(Number);

// #region setup
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const small = { size: { width: 400, height: 300 }, margin: 24 }; // pages of 400 x 300 CSS px
// #endregion

// #region flow
const lines = Array.from({ length: 40 }, (_, k) => `<p>Line ${k + 1} of the report</p>`).join("");
const flowing = await pdf.render(`<div style="font-family: Inter; font-size: 14px">${lines}</div>`, small);
// #endregion
assert.ok(pageCount(flowing) >= 2);

// #region break-before
const chapters = ["Intro", "Method", "Results"]
  .map((t) => `<h1 style="break-before: page">${t}</h1><p>Text of ${t}.</p>`)
  .join("");
const book = await pdf.render(`<div style="font-family: Inter">${chapters}</div>`, small);
// a forced break at the very start of the document adds no empty first page
// #endregion
assert.equal(pageCount(book), 3);

// #region tailwind
const tw = await pdf.render(
  `<div style="font-family: Inter">
     <section tw="break-after-page"><h1>Cover</h1></section>
     <section tw="break-inside-avoid"><h2>Summary</h2><p>Kept together on one page.</p></section>
   </div>`,
  small,
);
// #endregion
assert.equal(pageCount(tw), 2);

// #region node-tree
const tree = {
  type: "container",
  style: { display: "flex", flexDirection: "column", fontFamily: "Inter", fontSize: 16 },
  children: [
    { type: "text", text: "Page one" },
    { type: "text", text: "Page two", style: { breakBefore: "page" } },
  ],
};
const twoPages = await pdf.render(tree, small);
// #endregion
assert.equal(pageCount(twoPages), 2);

// #region avoid
const cards = (rule) => Array.from({ length: 6 }, (_, k) =>
  `<div style="${rule} margin-bottom: 8px; height: 90px; border: 1px solid #94a3b8"><b>Card ${k + 1}</b></div>`).join("");
const cut = await pdf.render(`<div style="font-family: Inter">${cards("")}</div>`, small);
// page 1 shows cards 1, 2 and the top of card 3
const whole = await pdf.render(`<div style="font-family: Inter">${cards("break-inside: avoid;")}</div>`, small);
// card 3 does not fit in what is left of page 1, so it moves to page 2 whole: two cards per page
// #endregion
assert.equal(pageCount(cut), 3);
assert.equal(pageCount(whole), 3);

// #region widows
const paragraph = "The quick brown fox jumps over the lazy dog. ".repeat(12);
const flow = (rule) =>
  `<div style="height: 230px"></div>
   <p style="margin: 0; font: 13px/16px Inter; ${rule}">${paragraph}</p>`;
const oneLine = await pdf.render(flow("orphans: 1"), small); // one line of the paragraph at the bottom of page 1
const moved = await pdf.render(flow("orphans: 2"), small);   // the default: the paragraph starts on page 2
// #endregion
assert.equal(pageCount(oneLine), 2);
assert.equal(pageCount(moved), 2);

// #region table
const rows = Array.from({ length: 30 }, (_, k) => `<tr><td>Item ${k + 1}</td><td>${(k + 1) * 3}</td></tr>`).join("");
const table = await pdf.render(
  `<table style="width: 100%; font-family: Inter; font-size: 12px">
     <thead><tr style="background: #e2e8f0"><th>Name</th><th>Qty</th></tr></thead>
     <tbody>${rows}</tbody>
     <tfoot><tr><td>Total</td><td>1395</td></tr></tfoot>
   </table>`,
  small,
);
// the header group is drawn again at the top of every page, the footer group at the bottom of every page
// #endregion
assert.ok(pageCount(table) >= 3);

// #region at-page
const styled = await pdf.render(
  `<style>
     @page { size: A5 landscape; margin: 12mm }
     @page :first { margin-top: 40mm }
   </style>
   <div style="font-family: Inter">${lines}</div>`,
);
// #endregion
assert.deepEqual(mediaBox(styled).map((v) => Math.round(v)), [595, 420]);

// #region at-page-css
const viaOption = await pdf.render(`<div style="font-family: Inter">${lines}</div>`, {
  css: "@page { size: letter; margin: 0.5in }", // the css option works for node trees too
});
// #endregion
assert.deepEqual(mediaBox(viaOption).map(Math.round), [612, 792]);

// #region named-pages
const named = await pdf.render(
  `<style>
     @page wide { size: 600px 300px; margin: 24px }
     .annex { page: wide }
   </style>
   <div style="font-family: Inter">
     <p>Body text on a normal page.</p>
     <section class="annex"><h2>Annex</h2><p>This section is printed on a wider page.</p></section>
     <p>Back to a normal page.</p>
   </div>`,
  small,
);
// the used page name changes twice, so there is a break before and after the annex
// #endregion
assert.equal(pageCount(named), 3);
assert.deepEqual([...latin1(named).matchAll(/\/MediaBox\[0 0 ([\d.]+)/g)].map((m) => Math.round(m[1])), [300, 450, 300]); // page widths in points

// #region ranges
const part = await pdf.render(`<div style="font-family: Inter; font-size: 14px">${lines}</div>`, {
  ...small,
  pageRanges: [1, { from: 3 }], // page 1 and page 3 to the end; pages are numbered from 1
});
// #endregion
assert.equal(pageCount(part), pageCount(flowing) - 1);

// #region ranges-error
let rangeError;
try {
  await pdf.render(`<p style="font-family: Inter">one page</p>`, { pageRanges: [{ from: 5 }] });
} catch (e) {
  rangeError = e.message;
}
// bm-engine: The page ranges select none of the document's 1 pages
// #endregion
assert.match(rangeError, /The page ranges select none of the document's 1 pages/);
console.log("pdf-pagination: ok", pageCount(flowing), pageCount(table), pageCount(oneLine), pageCount(whole));
