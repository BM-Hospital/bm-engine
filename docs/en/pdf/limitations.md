# PDF limitations

Use `bm-render/pdf` to create PDFs. On Node.js this entry uses the native backend when available, with automatic WebAssembly fallback.

## Known limitations

- **Fonts:** no fallback font is bundled. Register fonts before rendering; `uncoveredText` controls missing glyph handling. Text can fail when no font is registered.
- **JSX:** documents and bands accept React elements, but components run without a React dispatcher; hooks that require it cannot be used.
- **SVG fonts:** SVG-in-OpenType glyphs rely on outline fallback. COLR and bitmap color fonts are supported.
- **Generated content:** URL images in pseudo content and CSS counters are supported. Generated gradient images, gradient list markers and authored `::marker` rules are not fully verified.
- **Motion paths:** cases without a known viewport, or with links across page boundaries, need separate checks.
- **Page margins:** `@page` supports sizes, margins, first/left/right and named pages. Margin boxes such as `@top-center` are skipped; use header/footer options.
- **Page breaks:** `left`, `right`, `recto` and `verso` break the page without inserting a blank page to enforce a side. `column` is not a page break.
- **Page-width changes:** a continued table row or flex line retains its previous width when crossing a page-width change.
- **Tables:** repeated headers/footers, split rows and `rowspan` are supported. Check thick collapsed borders and repeated headers with real documents.
- **Grid:** grid rows do not have separate fragments; check `align-items: end` items that break before their row.
- **Floats, transforms and clips:** nested combinations, especially with links across pages, need separate checks.
- **Lists:** a split item’s marker stays on the item’s first line.
- **Long documents:** a document cut by forced page breaks (`break-before` / `break-after: page` between the blocks of its body, such as one record per page in batch printing) is laid out and drawn a part at a time, so only one part's layout is in memory; the file is the same as when the document is laid out whole. A document without such breaks, or with fixed boxes, floats, counters in the content or pages of different widths, is laid out whole, and its final layout stays in memory until the file is written. The parsed document and styles are kept for the whole render in both cases.
- **Invalid input:** oversized pages, truncated fonts and fonts without `cmap` can be rejected. `margin: NaN` becomes JSON `null` and uses the default margin.

## Resources and file validation

`prepare()` discovers required resources, loads font subsets and `@font-face` files, and fetches missing images. This differs from image rendering; see the [PDF API](api.md). Register fonts explicitly and control resource sources in your application.

PDF/A and PDF/UA checks are not certification. Validate actual application output with suitable tools. See [accessibility and archival](accessibility.md), [PDF CSS](css-support.md) and [pagination](pagination.md).
