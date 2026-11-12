# Accessibility and archival

[English](accessibility.md) · [Tiếng Việt](../../vi/pdf/accessibility.md)

Two options turn a PDF into a standards-conforming document. `tagged` writes the structure tree that
screen readers use and, as `"ua1"` or `"ua2"`, checks the document against PDF/UA. `pdfa` writes PDF/A
for long-term archiving and checks the document against that standard. This page lists what each option
writes, which PDF version each standard needs, which combinations are rejected and with what error, and
how far the checks go. It needs the [`pdf` profile](index.md). Every Node.js snippet is a section of
`docs/examples/pdf-accessibility.mjs` in the repository and was executed by it.

- [Setup](#setup)
- [Tagged PDF](#tagged-pdf)
- [PDF/UA](#pdfua)
- [Alternate text for images](#alternate-text-for-images)
- [PDF/A](#pdfa)
- [Versions and combinations](#versions-and-combinations)
- [Attachments and PDF/A](#attachments-and-pdfa)
- [How far the checks go](#how-far-the-checks-go)

## Setup

<!-- @example pdf-accessibility#setup -->
```js
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
const doc = `<div style="font-family: Inter"><h1>Annual report</h1><p>Revenue grew.</p></div>`;
```

## Tagged PDF

`tagged` defaults to `true`: every PDF carries a structure tree built from the document's HTML
semantics. `tagged: false` leaves the tree out.

<!-- @example pdf-accessibility#tagged -->
```js
const tagged = await pdf.render(doc);                         // tagged: true is the default
const untagged = await pdf.render(doc, { tagged: false });    // no structure tree
```

The tree follows the elements: headings, paragraphs, links (each link annotation joins a `Link` element
and gets its URI as description), images and `figure` (with alternate text), `blockquote`, `section`,
`article`, lists, `strong` / `b`, `em` / `i`, `code`, `figcaption`, and tables with a caption, `thead` /
`tbody` / `tfoot`, rows, header cells with their scope and cells with their spans. Loose content becomes
paragraphs. Headers, footers and decorative images are marked as artifacts, which screen readers skip.
The language of the text is the nearest `lang` attribute, otherwise the `lang` option. In a node tree,
set `tagName` (`"h1"`, `"p"`, ...) and `attributes` (`alt`, `href`) on a container.

List markers are painted, in paged and in `viewport` output, and each list item with a marker has `Lbl` (label)
and `LBody` elements. An item that gets no marker has `LBody` only
([Known limitations](differences-from-takumi.md#known-limitations) lists what is supported).

## PDF/UA

`tagged: "ua1"` or `"ua2"` writes the tree and validates the document against PDF/UA-1 (PDF 1.7) or
PDF/UA-2 (PDF 2.0). It also builds the [bookmarks](links-metadata.md#bookmarks) from the headings, as
the standard needs. A document fails when it breaks a rule. The ones that matter in practice:

- a document title (`metadata.title`);
- headings, because the outline is built from them (a document with no heading has no outline);
- alternate text for every informative image (the `alt` attribute);
- for PDF/UA-2, the document language (`lang`);
- fonts that are embeddable and have Unicode mappings, and no glyph 0 (`.notdef`) in the text.

<!-- @example pdf-accessibility#ua1 -->
```js
const ua1 = await pdf.render(doc, {
  tagged: "ua1",
  lang: "en",                                // the document language
  metadata: { title: "Annual report" },      // PDF/UA needs a title (the outline comes from the headings)
});
```

Violations are not named. The render throws one error with the count, and the usual causes are the list
above:

<!-- @example pdf-accessibility#ua1-errors -->
```js
const noTitle = await outcome(pdf.render(doc, { tagged: "ua1", lang: "en" }));
// bm-engine: Writing the PDF failed: validation failed with 1 error
const noHeading = await outcome(pdf.render(`<p style="font-family: Inter">Text only</p>`, { tagged: "ua1", metadata: { title: "T" } }));
// bm-engine: Writing the PDF failed: validation failed with 1 error   (a PDF/UA document needs an outline)
```

## Alternate text for images

Under PDF/UA and the `a` levels of PDF/A, an `<img>` needs an `alt` attribute. `alt=""` marks the image as
decorative: it is written as an artifact and needs no description. A `figure` takes its alternate text
from the image inside it.

<!-- @example pdf-accessibility#alt -->
```js
const logo = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==", "base64"));
const withImage = (img) => `<div style="font-family: Inter"><h1>Logo</h1>${img}</div>`;
const options = { tagged: "ua1", lang: "en", metadata: { title: "Logo" }, images: [{ src: "logo", data: logo }] };

const noAlt = await outcome(pdf.render(withImage(`<img src="logo" width="40" height="40">`), options));
const alt = await outcome(pdf.render(withImage(`<img src="logo" alt="Company logo" width="40" height="40">`), options));
const decorative = await outcome(pdf.render(withImage(`<img src="logo" alt="" width="40" height="40">`), options));
// noAlt: validation failed with 1 error; alt: "ok"; decorative (alt=""): "ok", marked as an artifact
```

## PDF/A

`pdfa` takes `"2a"`, `"2b"`, `"2u"`, `"3a"`, `"3b"`, `"3u"`, `"4"` or `"4f"`; an unknown value throws
`unknown pdfa level: <value> (expected 2a, 2b, 2u, 3a, 3b, 3u, 4 or 4f)`. In every PDF/A file the colours
are tagged with an embedded sRGB profile and an output intent (instead of `DeviceRGB`), the XMP carries the
`pdfaid` part and conformance, and fonts are embedded. The sRGB profile is the CC0 "Compact ICC Profiles"
sRGB v4 ([Third-party notices](../../../THIRD-PARTY-NOTICES.md)).

| Level | PDF version | Structure tree | Attachments |
|:--|:--|:--|:--|
| `2a` | 1.7 | always (also with `tagged: false`) | not accepted |
| `2b`, `2u` | 1.7 | as `tagged` says | not accepted |
| `3a` | 1.7 | always | accepted, with mime type, description and date |
| `3b`, `3u` | 1.7 | as `tagged` says | accepted, with mime type, description and date |
| `4` | 2.0 | as `tagged` says | not accepted |
| `4f` | 2.0 | as `tagged` says | accepted |

The `a` levels also need a document language (`lang`) and alternate text for images. When `metadata` is
set, PDF/A requires `metadata.creationDate`; without `metadata`, no date is needed. PDF/A-4 and 4f write no
Info dictionary, the metadata lives in the XMP packet only. PDF/A-4f's empty list of embedded files is
written even with no attachment.

<!-- @example pdf-accessibility#pdfa -->
```js
const archival = await pdf.render(doc, {
  pdfa: "2b",
  metadata: { title: "Annual report", creationDate: "2026-01-31" }, // PDF/A needs a date once metadata is set
});
```

<!-- @example pdf-accessibility#pdfa4 -->
```js
const pdfa4 = await pdf.render(doc, { pdfa: "4", tagged: "ua2", lang: "en", metadata: { title: "Annual report", creationDate: "2026-01-31" } });
// PDF/A-4 and PDF/UA-2 are PDF 2.0
```

## Versions and combinations

The PDF version is the highest one every requested standard allows, and plain PDF is 1.7. PDF/A-2, PDF/A-3
and PDF/UA-1 are PDF 1.7; PDF/A-4 and PDF/UA-2 are PDF 2.0. So PDF/UA-1 combines with the PDF/A-2 and
PDF/A-3 levels, and PDF/UA-2 with PDF/A-4 and 4f. The other pairs have no common version.

The TypeScript types reject impossible combinations at compile time: `tagged: false` with the `a`
levels, PDF/UA-1 with PDF/A-4, PDF/UA-2 with PDF/A-2 or 3, and attachments with PDF/A-2 or PDF/A-4. At run
time the engine checks them too, but the messages are the ones below, not type messages:

| Request | Result |
|:--|:--|
| `pdfa: "2b"` with `tagged: "ua2"`, or `pdfa: "4"` with `tagged: "ua1"` | throws `The requested archival standard is not available` (no common PDF version) |
| attachments with `pdfa: "2a" \| "2b" \| "2u" \| "4"` | throws `Writing the PDF failed: validation failed with 1 error` |
| `pdfa: "3b"` attachment without `description` or `mimeType` | throws `Writing the PDF failed: validation failed with N errors` |
| `pdfa: "1b"` or another unknown level | throws `unknown pdfa level: 1b (expected 2a, 2b, 2u, 3a, 3b, 3u, 4 or 4f)` |
| `uncoveredText: "placeholder"` with a character no font covers, under `pdfa` or PDF/UA | throws `No font the text can use draws <char> (U+XXXX), and PDF/A-2b forbids the placeholder glyph. Register a font that draws them, or set uncoveredText to "blank".` ([Fonts in PDF](fonts.md#characters-no-font-covers)) |
| `tagged: false` with `pdfa: "2a"` or `"3a"` | not an error at run time: the tree is written anyway (the types reject it) |

<!-- @example pdf-accessibility#rejected -->
```js
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
```

## Attachments and PDF/A

PDF/A-3 (all three levels) is the usual route for attaching the data behind a document, such as the XML
of an e-invoice. Each attachment must have a `mimeType` and a `description`, and a date, either its own
`modificationDate` or the document's `metadata.creationDate`. Without `metadata`, every attachment needs
its own `modificationDate`. Give the attachment a `relationship` (`"data"`, `"source"`, `"alternative"`,
`"supplement"` or `"unspecified"`) to say how it relates to the document; it is written as the PDF/A-3
association.

<!-- @example pdf-accessibility#attachments -->
```js
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
```

PDF/A-4f accepts attachments. The engine does not check their `mimeType`, `description` or date there
(the TypeScript type `ArchivalAttachment` asks for them anyway; give them). PDF/A-2 and PDF/A-4 reject
attachments.

## How far the checks go

The validation is a port of the rules krilla applies for takumi-pdf. It checks the document title, the
document language, alternate text for images and links, the outline, the date, embedded files (existence,
mime type, description, date), and the fonts (embedding licence, Unicode mapping, `.notdef`). It does not
check size and nesting limits (long strings, arrays, deep nesting), and it does not re-read the file
the way a validator does.

No external validator such as veraPDF has been run on the output. bm-engine's PDF/A files are checked
against the ones takumi-pdf writes for the same input (takumi's golden fixtures, see [PDF
output](differences-from-takumi.md#known-limitations)), so conformance means "behaves like takumi-pdf", not "certified". If
you need a certified archive, run a validator on your own output before you rely on it.
