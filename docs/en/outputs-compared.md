# Image, PDF and Paint compared

[English](outputs-compared.md) · [Tiếng Việt](../vi/outputs-compared.md)

takumi's documentation is split into three sections — **Image**, **PDF** and **Paint** — because takumi
ships three outputs, as three separate packages, on top of one layout engine. bm-engine ports the first
two: Image, and PDF in its separate `pdf` profile ([PDF output](pdf.md)). This page explains what each
takumi output is for, what bm-engine covers today, and how to get close to Paint with bm-engine plus
other tools.

::: info Verification status
The takumi descriptions were checked against the takumi sources and docs in the repository's reference
copy (`ref/takumi`: the `takumi-core`, `takumi-raster`, `takumi-svg`, `takumi-pdf`, `takumi-pdf-js` and
`takumi-paint` crates / packages and `docs/content/docs/{pdf,paint}`); takumi code was not executed. The
bm-engine statements were checked by searching `js/` and `src/` and by running the APIs mentioned. The PDF
row reflects the PDF port added after the 0.1.0 image engine.
:::

## One layout engine, three outputs

```
            JSX / HTML / node tree + CSS
                        |
                takumi-core (style, layout, text)
          ______________|______________________________
         |                         |                   |
  takumi-raster / takumi-svg    takumi-pdf          takumi-paint
  -> PNG, JPEG, WebP, ICO,      -> paged PDF        -> paint tree (boxes,
     raw pixels, SVG,                                  text runs, images
     animated WebP/APNG/GIF                            in paint order)
  npm: takumi-js,               npm: takumi-pdf     npm: takumi-paint
  @takumi-rs/wasm, /core
```

| | Image | PDF | Paint |
|:--|:--|:--|:--|
| takumi crate | `takumi-raster` (tiny-skia painting), `takumi-svg` (vector SVG) | `takumi-pdf` ("vector PDF output backend ... selectable, searchable text with embedded subset fonts") | `takumi-paint` |
| npm package | `takumi-js`, `@takumi-rs/wasm`, `@takumi-rs/core` | `takumi-pdf` | `takumi-paint` |
| You get | encoded image bytes (or an SVG string, or an animation) | a PDF file | a JavaScript object tree you draw yourself |
| Typical use | Open Graph cards, thumbnails, social images | invoices, reports, tickets, certificates | editable slides (PPTX), Canvas / Skia / native drawing, custom renderers |
| bm-engine | **ported** (raster, SVG, animation) | **ported** as the `pdf` profile, with [known limitations](pdf.md#known-limitations) | **not available** (only `measure()`) |

### Image

What every other page of these docs is about: lay out a single canvas of a given size and paint it to
pixels (or to SVG elements). Output is one image (or a sequence of frames). Text becomes pixels or glyph
outlines; it is not selectable.

### PDF (`takumi-pdf`)

A document renderer, not "an image in a PDF". From takumi's PDF documentation:

- **Pagination**: content flows across pages of a chosen size (`a4`, `letter`, ... or explicit), with
  automatic or explicit margins, `@page` rules (`:first`, `:left`, `:right`, named pages) and CSS
  fragmentation (`break-before`, `break-inside: avoid`, repeated table headers).
- **Headers and footers** repeated on every page, with page-number primitives (`PageNumber`, `TotalPages`).
- **Real text**: selectable and searchable, fonts embedded as subsets.
- **Links, outline and metadata**: clickable `<a href>`, bookmarks / table of contents, document properties.
- **Conformance**: PDF/A archival levels (for example `pdfa: "3b"`) and tagged PDF / PDF/UA validation.
- **Attachments**: embedded files such as Factur-X invoice XML.

### Paint (`takumi-paint`)

Layout without rasterising: `paint()` returns a **paint tree** — every box with its resolved background,
borders and shadows, every paragraph as shaped text runs with their fonts, every image — in paint order
(`z-index` resolved), each with a transform. takumi's docs position it for writing editable PPTX slides,
drawing on Canvas / Skia / native APIs, or reading where layout put each box and line.

## What bm-engine covers

Checked in the bm-engine 0.1.0 sources and typings:

| Capability | bm-engine |
|:--|:--|
| Raster output (PNG, JPEG, WebP, raw RGBA, ICO) | yes — `render` / `renderSync`, `renderAsDataUrl` |
| SVG output | yes — `renderSvg` / `renderSvgSync` (`full` profile); text as glyph outlines, images embedded as `data:` URLs |
| Animated output | yes — `renderAnimation` (`full`): animated WebP, APNG, GIF |
| PDF output | **yes** — `bm-engine/pdf` (`PdfRenderer`, `renderPdf`): paged output with real text and subset fonts, headers / footers, links, bookmarks, metadata, attachments, tagged PDF and PDF/A. Not in `core`, `standard` or `full`. See [PDF output](pdf.md) |
| Pagination / fragmentation across pages | **yes, in the `pdf` profile** — content flows across pages, with `break-*`, `orphans` / `widows`, repeated table headers and `@page`. The image render is still one canvas per render |
| Paint tree | **no** — there is no API that returns drawing commands, colours, gradients or glyphs |
| Layout boxes | yes — `measure()` returns the box tree: border-box `width` / `height`, a 2D `transform` (absolute position), `children`, and text line `runs` (`x`, `y`, `width`, `height`; no text, no font, no glyph positions) |

## Workarounds (not built in)

The first entry points at the built-in PDF output; the rest combine bm-engine with other tools.

### A PDF from bm-engine output

Use the `pdf` profile: [PDF output](pdf.md). If you cannot load it (for example you must stay on `core`,
`standard` or `full`), these older routes still work:

- **One image per page.** Render each page as PNG at print resolution (an A4 page at 150 dpi is
  1240 × 1754 px; render `width: 1240, height: 1754` with `devicePixelRatio` scaling your 96-dpi CSS layout
  by 150 / 96) and place the images into a PDF with a PDF library (for example pdf-lib in JavaScript).
  Text is not selectable and files are large; fine for certificates or tickets, poor for long documents.
- **SVG per page.** `renderSvg` gives vector output; SVG-to-PDF converters (librsvg's `rsvg-convert`,
  Inkscape, svg2pdf libraries) keep shapes sharp. Text is still outlines, not selectable.
- **You paginate.** The image profiles do not split content across pages. Use `measure()` to find where blocks
  end and decide page breaks yourself, or render each page from its own node tree.

### A paint tree from `measure()`

`measure()` gives you geometry; you already know the styles because you wrote the tree. Walk both
together and draw with your own API:

```js
const layout = renderer.measureSync(node, { width: 1200, height: 630 });

function walk(n, m, draw) {
  const [a, b, c, d, x, y] = m.transform;           // absolute 2D matrix
  draw({ node: n, x, y, width: m.width, height: m.height, matrix: [a, b, c, d, x, y] });
  for (const run of m.runs) draw({ node: n, run: { x: x + run.x, y: y + run.y, width: run.width, height: run.height } });
  const kids = (n.children ?? []).filter((k) => k && k.type === "container"); // see the caveat below
  m.children.forEach((child, i) => kids[i] && walk(kids[i], child, draw));
}
```

Verified on a column with a wrapping heading and a 200 × 60 box: the walk produced three boxes (the
box at x = 40, 200 × 60) and one draw call per text line (`docs/examples/frameworks/check-outputs.mjs`).
Caveats, from the measure output format: text nodes inside a block flow do not get their own entry (their
lines appear as `runs` of the containing box), so pairing measured children with source children needs
care; runs carry no text or font; colours, gradients and borders are whatever you put in `style`, not
resolved values. The [Measure](./measure.md) page documents the output precisely. For pixel-exact drawing
of everything, render with bm-engine and draw the image.

## Which to use

| You need | Use |
|:--|:--|
| Social cards, thumbnails, generated images | bm-engine (`core` / `standard`) |
| An SVG version of the same card | bm-engine `full` + `renderSvg` |
| Short animations | bm-engine `full` + `renderAnimation` |
| Text-fitting, layout checks before rendering | bm-engine `measure()` |
| Multi-page documents with selectable text | bm-engine `pdf` profile (or takumi-pdf, or another PDF engine) |
| Editable slides / your own renderer with full style information | takumi-paint |
