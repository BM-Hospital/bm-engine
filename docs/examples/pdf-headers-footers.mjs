// Examples for docs/{en,vi}/pdf-headers-footers.md. Run: node docs/examples/run-all.mjs pdf-headers-footers
import "./_lib.mjs";
import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
const pageCount = (b) => (latin1(b).match(/\/Type\/Page[^s]/g) || []).length;
/** Text of page n (1-based) as poppler's pdftotext extracts it; null when pdftotext is not installed. */
function pageText(bytes, n) {
  const file = path.join(os.tmpdir(), "bm-pdf-headers-example.pdf");
  writeFileSync(file, bytes);
  const r = spawnSync("pdftotext", ["-f", String(n), "-l", String(n), file, "-"], { encoding: "utf8" });
  return r.error ? null : r.stdout.replace(/\s+/g, " ").trim();
}
const says = (bytes, n, s) => { const t = pageText(bytes, n); if (t !== null) assert.ok(t.includes(s), `page ${n} should contain "${s}": ${t}`); };

// #region setup
import { readFileSync } from "node:fs";
import { PdfRenderer, PageNumber, TotalPages } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const lines = Array.from({ length: 40 }, (_, k) => `<p>Line ${k + 1} of the report</p>`).join("");
const body = `<div style="font-family: Inter; font-size: 14px">${lines}</div>`;
const page = { size: { width: 400, height: 300 }, margin: 24 };
// #endregion

// #region footer-html
const footer = `<div style="font: 11px Inter; color: #475569">
  Page <span class="pageNumber"></span> of <span class="totalPages"></span>
</div>`;
const numbered = await pdf.render(body, { ...page, footer });
// #endregion
assert.equal(pageCount(numbered), 5);
says(numbered, 1, "Page 1 of 5");
says(numbered, 5, "Page 5 of 5");

// #region footer-node
const nodeFooter = {
  type: "container",
  style: { display: "flex", columnGap: 4, fontFamily: "Inter", fontSize: 11, color: "#475569" },
  children: [
    { type: "text", text: "Sheet" },
    PageNumber({ format: "upper-roman" }), // I, II, III
    { type: "text", text: "/" },
    TotalPages(),
  ],
};
const roman = await pdf.render(body, { ...page, footer: nodeFooter });
// #endregion
says(roman, 2, "Sheet II / 5");

// #region header
const header = `<div style="font: 11px Inter; display: flex; justify-content: space-between">
  <span>ACME Corp</span><span>Confidential</span>
</div>`;
const both = await pdf.render(body, { ...page, header, footer });
// #endregion
says(both, 2, "Confidential");
says(both, 2, "Page 2 of 5");

// #region pages
const ruled = await pdf.render(body, {
  ...page,
  header,
  footer,
  pages: {
    first: { header: false },                         // no header on the cover page
    last: { footer: "<b>End of document</b>" },       // the last page ends differently
    even: { header: "<span style=\"font: 11px Inter\">Even pages</span>" },
  },
});
// #endregion
says(ruled, 5, "End of document");
says(ruled, 2, "Even pages");

// #region margins
const roomy = await pdf.render(body, {
  ...page,
  margin: { top: "auto", bottom: 60, left: 24, right: 24 }, // top follows the header, bottom is fixed
  header,
});
// #endregion
assert.ok(pageCount(roomy) >= 3);

// #region flow-counters
const toc = await pdf.render(
  `<div style="font-family: Inter; font-size: 14px">
     <p><a href="#results">Results</a> on page <a href="#results"><span class="targetPageNumber"></span></a></p>
     <h2 id="results" style="break-before: page">Results</h2>
     <p>This is page <span class="pageNumber"></span> of <span class="totalPages"></span>.</p>
   </div>`,
  page,
);
// #endregion
says(toc, 1, "Results on page 2");
says(toc, 2, "This is page 2 of 2");

// #region fixed
const stamped = await pdf.render(
  `<div style="font-family: Inter; font-size: 14px">
     <div style="position: fixed; top: 4px; right: 8px; font-size: 10px">Sheet <span class="pageNumber"></span>/<span class="totalPages"></span></div>
     ${lines}
   </div>`,
  page,
);
// #endregion
says(stamped, 1, "Sheet 1/5");
says(stamped, 5, "Sheet 5/5");

// #region measure
const tall = `<div style="height: 64px; font: 11px Inter">Letterhead</div>`;
const bandHeight = (await pdf.measure(tall, { size: page.size })).height; // 64: the band laid out at the page width
const automatic = await pdf.render(body, { size: page.size, header: tall }); // every margin "auto"
const manual = await pdf.render(body, { size: page.size, header: tall, margin: { top: bandHeight + 20 } });
// the same file: an auto margin is the band height + 20 px (but at least 37.8 px, 10 mm)
// #endregion
assert.equal(bandHeight, 64);
assert.equal(latin1(manual), latin1(automatic));
console.log("pdf-headers-footers: ok", bandHeight);
