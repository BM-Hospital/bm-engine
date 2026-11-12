// Examples for docs/{en,vi}/pdf-accessibility.md. Run: node docs/examples/run-all.mjs pdf-accessibility
import "./_lib.mjs";
import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
const version = (b) => latin1(b.subarray(0, 8)).trim();
/** The file's text with every Flate stream inflated (object streams, XMP), for searching. */
function inside(bytes) {
  const s = latin1(bytes);
  let out = s;
  for (let at = 0; ;) {
    const i = s.indexOf("stream\n", at);
    if (i < 0) break;
    const j = s.indexOf("\nendstream", i);
    const dict = s.slice(s.lastIndexOf("obj", i), i);
    if (/FlateDecode/.test(dict) && !/Subtype\/Image/.test(dict)) {
      try { out += "\n" + inflateSync(Buffer.from(bytes.subarray(i + 7, j))).toString("latin1"); } catch {}
    }
    at = j + 10;
  }
  return out;
}
/** The message of the error a render throws, or "ok". */
const outcome = async (promise) => { try { await promise; return "ok"; } catch (e) { return e.message; } };

// #region setup
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const doc = `<div style="font-family: Inter"><h1>Annual report</h1><p>Revenue grew.</p></div>`;
// #endregion

// #region tagged
const tagged = await pdf.render(doc);                         // tagged: true is the default
const untagged = await pdf.render(doc, { tagged: false });    // no structure tree
// #endregion
assert.ok(inside(tagged).includes("/StructTreeRoot"));
assert.ok(!inside(untagged).includes("/StructTreeRoot"));

// #region ua1
const ua1 = await pdf.render(doc, {
  tagged: "ua1",
  lang: "en",                                // the document language
  metadata: { title: "Annual report" },      // PDF/UA needs a title (the outline comes from the headings)
});
// #endregion
assert.equal(version(ua1), "%PDF-1.7");
assert.ok(inside(ua1).includes("pdfuaid"));

// #region ua1-errors
const noTitle = await outcome(pdf.render(doc, { tagged: "ua1", lang: "en" }));
// bm-engine: Writing the PDF failed: validation failed with 1 error
const noHeading = await outcome(pdf.render(`<p style="font-family: Inter">Text only</p>`, { tagged: "ua1", metadata: { title: "T" } }));
// bm-engine: Writing the PDF failed: validation failed with 1 error   (a PDF/UA document needs an outline)
// #endregion
assert.match(noTitle, /^bm-engine: Writing the PDF failed: validation failed with 1 error$/);
assert.match(noHeading, /validation failed with 1 error/);

// #region alt
const logo = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==", "base64"));
const withImage = (img) => `<div style="font-family: Inter"><h1>Logo</h1>${img}</div>`;
const options = { tagged: "ua1", lang: "en", metadata: { title: "Logo" }, images: [{ src: "logo", data: logo }] };

const noAlt = await outcome(pdf.render(withImage(`<img src="logo" width="40" height="40">`), options));
const alt = await outcome(pdf.render(withImage(`<img src="logo" alt="Company logo" width="40" height="40">`), options));
const decorative = await outcome(pdf.render(withImage(`<img src="logo" alt="" width="40" height="40">`), options));
// noAlt: validation failed with 1 error; alt: "ok"; decorative (alt=""): "ok", marked as an artifact
// #endregion
assert.match(noAlt, /validation failed with 1 error/);
assert.equal(alt, "ok");
assert.equal(decorative, "ok");

// #region pdfa
const archival = await pdf.render(doc, {
  pdfa: "2b",
  metadata: { title: "Annual report", creationDate: "2026-01-31" }, // PDF/A needs a date once metadata is set
});
// #endregion
assert.equal(version(archival), "%PDF-1.7");
{
  const t = inside(archival);
  assert.ok(t.includes("pdfaid") && t.includes("GTS_PDFA1") && t.includes("/ICCBased"));
}

// #region pdfa4
const pdfa4 = await pdf.render(doc, { pdfa: "4", tagged: "ua2", lang: "en", metadata: { title: "Annual report", creationDate: "2026-01-31" } });
// PDF/A-4 and PDF/UA-2 are PDF 2.0
// #endregion
assert.equal(version(pdfa4), "%PDF-2.0");

// #region attachments
const invoice = await pdf.render(doc, {
  pdfa: "3b",
  metadata: { title: "Invoice 2026-017", creationDate: "2026-01-31" },
  attachments: [{
    name: "factur-x.xml",
    data: "<rsm:CrossIndustryInvoice/>",
    mimeType: "application/xml",             // required by the PDF/A-3 levels
    description: "Invoice data",             // required by the PDF/A-3 levels
    relationship: "data",
    modificationDate: "2026-01-31",          // falls back to metadata.creationDate
  }],
});
// #endregion
assert.ok(inside(invoice).includes("/AFRelationship/Data") || inside(invoice).includes("/AFRelationship /Data"));

// #region rejected
const attach = [{ name: "a.xml", data: "<x/>", mimeType: "application/xml", description: "d" }];
const results = {
  "2b + ua2": await outcome(pdf.render(doc, { pdfa: "2b", tagged: "ua2" })),
  "4 + ua1": await outcome(pdf.render(doc, { pdfa: "4", tagged: "ua1" })),
  "2b + attachments": await outcome(pdf.render(doc, { pdfa: "2b", metadata: { creationDate: "2026-01-31" }, attachments: attach })),
  "3b + attachment without description": await outcome(pdf.render(doc, { pdfa: "3b", metadata: { creationDate: "2026-01-31" }, attachments: [{ name: "a.xml", data: "x", mimeType: "application/xml" }] })),
  "unknown level": await outcome(pdf.render(doc, { pdfa: "1b" })),
};
// "2b + ua2":  bm-engine: The requested archival standard is not available
// "4 + ua1":   bm-engine: The requested archival standard is not available
// "2b + attachments": bm-engine: Writing the PDF failed: validation failed with 1 error
// "3b + attachment without description": bm-engine: Writing the PDF failed: validation failed with 1 error
// "unknown level": bm-engine: unknown pdfa level: 1b (expected 2a, 2b, 2u, 3a, 3b, 3u, 4 or 4f)
// #endregion
assert.equal(results["2b + ua2"], "bm-engine: The requested archival standard is not available");
assert.equal(results["4 + ua1"], "bm-engine: The requested archival standard is not available");
assert.equal(results["2b + attachments"], "bm-engine: Writing the PDF failed: validation failed with 1 error");
assert.equal(results["3b + attachment without description"], "bm-engine: Writing the PDF failed: validation failed with 1 error");
assert.equal(results["unknown level"], "bm-engine: unknown pdfa level: 1b (expected 2a, 2b, 2u, 3a, 3b, 3u, 4 or 4f)");
console.log("pdf-accessibility: ok");
