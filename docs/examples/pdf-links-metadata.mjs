// Examples for docs/{en,vi}/pdf-links-metadata.md. Run: node docs/examples/run-all.mjs pdf-links-metadata
import "./_lib.mjs";
import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";

const latin1 = (b) => new TextDecoder("latin1").decode(b);
/** The file's text with every Flate stream inflated (object streams included), for searching. */
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
const count = (text, re) => (text.match(re) || []).length;

// #region setup
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const page = { size: { width: 400, height: 300 }, margin: 24 };
// #endregion

// #region links
const linked = await pdf.render(
  `<div style="font: 14px Inter">
     <p>Read <a href="https://example.com/docs">the docs</a>, write to <a href="mailto:hi@example.com">us</a>
        or jump to <a href="#details">the details</a>.</p>
     <a href="https://example.com/card" style="display: block; padding: 12px; background: #e2e8f0">A whole box is one link</a>
     <h2 id="details" style="break-before: page">Details</h2>
   </div>`,
  page,
);
// #endregion
{
  const t = inside(linked);
  assert.equal(count(t, /\/Subtype\/Link/g), 4);
  assert.ok(t.includes("/URI(https://example.com/docs)") && t.includes("/URI(mailto:hi@example.com)"));
}

// #region link-node
const nodeLink = await pdf.render(
  {
    type: "container",
    tagName: "a",
    attributes: { href: "https://example.com" },
    style: { display: "flex", padding: 12, backgroundColor: "#dbeafe" },
    children: [{ type: "text", text: "Open example.com", style: { fontFamily: "Inter", fontSize: 14 } }],
  },
  page,
);
// #endregion
assert.equal(count(inside(nodeLink), /\/Subtype\/Link/g), 1);

// #region outline
const book = `<div style="font: 14px Inter">
  <h1>Handbook</h1><p>Intro.</p>
  <h2 style="break-before: page">Install</h2><p>Steps.</p>
  <h2 style="break-before: page">Use</h2><h3>Options</h3><p>Flags.</p>
</div>`;
const withOutline = await pdf.render(book, { ...page, outline: true });
// bookmarks: Handbook > (Install, Use > Options), each pointing at its heading
// #endregion
{
  const t = inside(withOutline);
  assert.ok(t.includes("/Type/Outlines"));
  assert.equal(count(t, /\/Title\((Handbook|Install|Use|Options)\)/g), 4);
  assert.ok(!inside(await pdf.render(book, page)).includes("/Type/Outlines"));
}

// #region metadata
const described = await pdf.render(book, {
  ...page,
  lang: "en",
  metadata: {
    title: "Handbook",
    description: "Setup and usage guide",
    authors: ["A. Writer", "B. Editor"],
    keywords: ["guide", "setup"],
    creator: "bm-engine docs",
    creationDate: "2026-08-06T09:30:00", // UTC; or just "2026-08-06"
  },
});
// #endregion
{
  const t = inside(described);
  assert.ok(t.includes("/Title(Handbook)") && t.includes("/Author(A. Writer, B. Editor)") && t.includes("/Keywords(guide, setup)"));
  assert.ok(t.includes("D:20260806093000Z"));
}

// #region xmp
const custom = await pdf.render(book, {
  ...page,
  metadata: {
    title: "Handbook",
    xmp: [{
      name: "Acme workflow",
      prefix: "acme",
      namespace: "https://example.com/ns/acme/1.0/",
      properties: [{ name: "Ticket", value: "DOC-1234", description: "Tracking ticket of the document" }],
    }],
  },
});
// #endregion
assert.ok(inside(custom).includes("DOC-1234"));

// #region attachments
const bytes = new Uint8Array([0x50, 0x4b, 3, 4]); // any binary data
const attached = await pdf.render("<p style=\"font-family: Inter\">See the attached files.</p>", {
  attachments: [
    { name: "data.csv", data: "a,b\n1,2\n", mimeType: "text/csv", relationship: "data" }, // a string is encoded as UTF-8
    { name: "archive.zip", data: bytes, mimeType: "application/zip", description: "Source files" },
  ],
});
// the viewer lists both files in its attachment panel
// #endregion
{
  const t = inside(attached);
  assert.ok(t.includes("/Type/EmbeddedFile") && t.includes("(data.csv)") && t.includes("(archive.zip)"));
}

// #region attachment-errors
const messages = [];
for (const attachments of [
  [{ name: "a.txt", data: "x" }, { name: "a.txt", data: "y" }],
  [{ name: "a.txt", data: "x", mimeType: "plain" }],
]) {
  try { await pdf.render("<p>x</p>", { attachments }); } catch (e) { messages.push(e.message); }
}
// bm-engine: Two attachments are named a.txt
// bm-engine: Attachment mime type is not a type/subtype pair: plain
// #endregion
assert.deepEqual(messages, ["bm-engine: Two attachments are named a.txt", "bm-engine: Attachment mime type is not a type/subtype pair: plain"]);
console.log("pdf-links-metadata: ok");
