# Choosing an output

Choose based on how people will use the result. Images work well for display and sharing; PDF works well for reading, searching and printing documents.

| Need | API | Profile |
|:--|:--|:--|
| PNG, JPEG or WebP image | `Renderer.render()` | `core`, `standard`, `full` |
| RGBA pixels for further processing | `Renderer.render()` with `format: "raw"` | `core`, `standard`, `full` |
| Vector SVG | `Renderer.renderSvg()` | `full` |
| Animated WebP, APNG or GIF | `Renderer.renderAnimation()` | `full` |
| Multi-page PDF with searchable, selectable text | `PdfRenderer.render()` from `bm-engine/pdf` | `pdf` |
| Box positions and sizes before painting | `Renderer.measure()` | `core`, `standard`, `full` |

## Images and SVG

Each image render uses one canvas with your chosen `width` and `height`. Content does not paginate. PNG preserves transparency; JPEG drops alpha and needs an opaque background; WebP output is always lossless. SVG keeps vector shapes, but text becomes outlines rather than selectable text.

See the [image quick start](image/index.md) and [output formats](image/formats.md).

## PDF

Use `bm-engine/pdf` for paper sizes, margins, pagination, headers and footers. PDFs can contain text, links, bookmarks, metadata and attachments. PDF/A and PDF/UA requirements need configuration and validation for your document.

See the [PDF quick start](pdf/index.md), [pagination](pdf/pagination.md) and [known limitations](pdf/limitations.md).

## Layout measurements

`measure()` returns a box tree and text-line positions. It does not include complete drawing commands, resolved colors or individual glyph positions. bm-engine does not currently expose a paint tree or editable-slide export.

See [measure()](image/measure.md).
