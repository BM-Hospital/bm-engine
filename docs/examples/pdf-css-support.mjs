// Examples for docs/{en,vi}/pdf/css-support.md. Run: node docs/examples/run-all.mjs pdf-css-support
import "./_lib.mjs";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync as write, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
const pageCount = (b) => (latin1(b).match(/\/Type\/Page[^s]/g) || []).length;
/** Text of a PDF as pdftotext (poppler) extracts it, or null when pdftotext is not installed. */
function pdftotext(bytes) {
  const dir = mkdtempSync(join(tmpdir(), "bm-pdf-"));
  try {
    write(join(dir, "a.pdf"), bytes);
    const r = spawnSync("pdftotext", ["-layout", join(dir, "a.pdf"), "-"], { encoding: "utf8" });
    return r.status === 0 ? r.stdout : null;
  } catch { return null; } finally { rmSync(dir, { recursive: true, force: true }); }
}

// #region setup
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const page = { size: { width: 400, height: 300 }, margin: 24 };
// #endregion

// #region ignored-in-images
import { Renderer } from "bm-engine/pdf";

const html = `<div style="font-family: Inter">
  <p>Page one</p><p style="break-before: page">Page two</p>
</div>`;
const doc = await pdf.render(html, page);                 // two pages
const image = new Renderer();
image.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
const png = image.renderSync(html, { width: 400, height: 120 }); // one image: break-before is ignored
// #endregion
assert.equal(pageCount(doc), 2);
assert.equal(png[0], 0x89);

// #region text-overflow
const clipped = await pdf.render(
  `<p style="font-family: Inter; font-size: 20px; width: 200px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">
     A very long product name that does not fit
   </p>`,
  page,
);
// the page shows "A very long produc…": the marker is text of its own, so extracting the text (pdftotext,
// copy and paste) gives what the page shows, the "…" included, and not the cut-off rest
// #endregion
const text = pdftotext(clipped);
if (text !== null) {
  assert.match(text.trim(), /^A very long produc(\u2026|\.\.\.)$/);
  console.log("text-overflow: extracted ->", JSON.stringify(text.trim()));
} else console.log("text-overflow: pdftotext not installed, extraction not checked");

// #region image-rendering
const pixels = { width: 2, height: 2, data: new Uint8Array([255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255, 255, 0, 0, 255]) };
const scaled = (rendering) => pdf.render({
  type: "image", src: pixels, style: { width: 120, height: 120, imageRendering: rendering },
}, { viewport: { width: 120, height: 120 } });
const smooth = await scaled("auto");
const pixelated = await scaled("pixelated");
// the two files are byte for byte the same: a PDF image has no image-rendering setting
// #endregion
assert.deepEqual(Buffer.from(smooth), Buffer.from(pixelated));

// #region blur-error
let blurError;
try {
  await pdf.render(`<div style="filter: blur(2px); width: 50px; height: 50px; background: red"></div>`, page);
} catch (e) {
  blurError = e.message;
}
// A PDF cannot draw filter: blur(2px)
// #endregion
assert.match(blurError, /A PDF cannot draw filter: blur\(2px\)/);
console.log("pdf-css-support: ok");
