# Links, bookmarks, metadata and attachments

[English](links-metadata.md) · [Tiếng Việt](../../vi/pdf/links-metadata.md)

The interactive and descriptive parts of a PDF come from the document itself: an `<a href>` becomes a
clickable link, the headings can become the bookmarks panel, and the `metadata` option fills the document
properties. Files can be embedded as attachments. This page covers each, with the exact rules for which
links are kept, how the outline is nested and what the metadata fields do. It needs the [`pdf`
profile](index.md). Every Node.js snippet is a section of `docs/examples/pdf-interactive.mjs` in the
repository and was executed by it.

- [Setup](#setup)
- [Links](#links)
- [Bookmarks](#bookmarks)
- [Metadata](#metadata)
- [Custom XMP](#custom-xmp)
- [Attachments](#attachments)

## Setup

<!-- @example pdf-links-metadata#setup -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const page = { size: { width: 400, height: 300 }, margin: 24 };
```

## Links

Every element with an `href` that the engine accepts becomes a link annotation in the PDF:

- `#id` links to the element with that `id`, wherever it lands (another page included). The target is a
  position at the top of the element. A fragment that names no element, or an element on a page that
  `pageRanges` removed, writes no link.
- `http:`, `https:`, `mailto:` and `tel:` links open the URI.
- Anything else (`ftp:`, `javascript:`, relative paths) is ignored.

A box with an `href` (for example a block-level `<a>`) is one link over its whole border box. Inline
text inside an `<a>` is one link per painted line, covering the line's advance and the font's ascent and
descent. A link that crosses a page break gets one annotation on each page it reaches. Links have no
visible border (`/Border [0 0 0]`) and print (`/F 4`).

<!-- @example pdf-links-metadata#links -->
```js
const linked = await pdf.render(
  `<div style="font: 14px Inter">
     <p>Read <a href="https://example.com/docs">the docs</a>, write to <a href="mailto:hi@example.com">us</a>
        or jump to <a href="#details">the details</a>.</p>
     <a href="https://example.com/card" style="display: block; padding: 12px; background: #e2e8f0">A whole box is one link</a>
     <h2 id="details" style="break-before: page">Details</h2>
   </div>`,
  page,
);
```

Header and footer [bands](headers-footers.md) never carry links. A repeated `position: fixed` box
does, on every page.

In a node tree, the link is a container with `tagName: "a"` and `attributes: { href }`:

<!-- @example pdf-links-metadata#link-node -->
```js
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
```

## Bookmarks

`outline: true` builds the bookmarks panel from the headings `h1` to `h6` that have text. Headings are
ordered as they appear and nested by level (an `h3` under an `h2` is its child), every entry points at the
top of its heading, and the tree is closed when the file opens. If `pageRanges` removes a heading's page,
its children move up. Tagged output with `tagged: "ua1"` or `"ua2"` also builds the outline, because
PDF/UA requires one ([Accessibility and archival](accessibility.md)).

<!-- @example pdf-links-metadata#outline -->
```js
const book = `<div style="font: 14px Inter">
  <h1>Handbook</h1><p>Intro.</p>
  <h2 style="break-before: page">Install</h2><p>Steps.</p>
  <h2 style="break-before: page">Use</h2><h3>Options</h3><p>Flags.</p>
</div>`;
const withOutline = await pdf.render(book, { ...page, outline: true });
// bookmarks: Handbook > (Install, Use > Options), each pointing at its heading
```

In a node tree, headings are containers with `tagName: "h1"` to `"h6"`.

## Metadata

`metadata` fills the document properties (the Info dictionary and the XMP packet that every file
carries):

| Field | Meaning |
|:--|:--|
| `title` | Document title. |
| `description` | The subject. |
| `authors` | A list of names, joined with `, ` in the Info dictionary. |
| `keywords` | A list of keywords, joined with `, ` in the Info dictionary. |
| `creator` | The tool that created the source document. |
| `creationDate` | UTC, `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS`. Used for the creation and modification dates. Required by the PDF/A levels once `metadata` is set. |
| `xmp` | Custom XMP schemas, see below. |

An empty `title`, `description` or `creator` and an empty `authors` or `keywords` list count as absent.
`lang` (a BCP-47 tag such as `"en"` or `"vi"`) is the document language and doubles as the metadata
language; PDF/A-2a, PDF/A-3a and PDF/UA-2 require one. An invalid date throws `invalid creationDate:
expected YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS`. PDF/A-4 and PDF/A-4f write no Info dictionary, only XMP,
and `creator` goes to the Info dictionary only in files below PDF 2.0.

<!-- @example pdf-links-metadata#metadata -->
```js
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
```

The Info dictionary names `bm-engine` as the producer.

## Custom XMP

`metadata.xmp` adds your own XMP schemas, such as the Factur-X extension. Each schema has a `name`, a
`prefix`, a `namespace` (a URI) and `properties`; each property has `name`, `value` and `description`
(PDF/A requires a description). Prefix, namespace and property names must be writable as XML, otherwise
the render throws `XMP schema cannot be written as XML: <the offending value>`.

<!-- @example pdf-links-metadata#xmp -->
```js
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
```

## Attachments

`attachments` embeds files; viewers list them in an attachment panel.

| Field | Meaning |
|:--|:--|
| `name` | File name, unique in the document (`Two attachments are named <name>` otherwise). |
| `data` | Bytes (`Uint8Array`, `ArrayBuffer`) or a string, which is encoded as UTF-8. Required. |
| `mimeType` | A `type/subtype` media type; anything else throws `Attachment mime type is not a type/subtype pair: <value>`. |
| `description` | Human-readable description. |
| `relationship` | `source`, `data`, `alternative`, `supplement` or `unspecified` (default). Written only where associated files exist: PDF/A-3 and PDF 2.0. |
| `modificationDate` | UTC date; falls back to `metadata.creationDate`. |

The files are listed sorted by name, and data is compressed when that saves more than a quarter of its
size. Under PDF/A only the PDF/A-3 levels and PDF/A-4f accept attachments, and the PDF/A-3 levels require
`mimeType`, `description` and a date; see [Accessibility and archival](accessibility.md#attachments-and-pdfa).

<!-- @example pdf-links-metadata#attachments -->
```js
const bytes = new Uint8Array([0x50, 0x4b, 3, 4]); // any binary data
const attached = await pdf.render("<p style=\"font-family: Inter\">See the attached files.</p>", {
  attachments: [
    { name: "data.csv", data: "a,b\n1,2\n", mimeType: "text/csv", relationship: "data" }, // a string is encoded as UTF-8
    { name: "archive.zip", data: bytes, mimeType: "application/zip", description: "Source files" },
  ],
});
// the viewer lists both files in its attachment panel
```

<!-- @example pdf-links-metadata#attachment-errors -->
```js
const messages = [];
for (const attachments of [
  [{ name: "a.txt", data: "x" }, { name: "a.txt", data: "y" }],
  [{ name: "a.txt", data: "x", mimeType: "plain" }],
]) {
  try { await pdf.render("<p>x</p>", { attachments }); } catch (e) { messages.push(e.message); }
}
// bm-engine: Two attachments are named a.txt
// bm-engine: Attachment mime type is not a type/subtype pair: plain
```
