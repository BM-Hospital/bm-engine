# Page size, margins and viewport

[English](page-size-and-viewport.md) · [Tiếng Việt](../../vi/pdf/page-size-and-viewport.md)

A PDF from bm-render is either **paged** (the default: A4 pages with 10 mm margins, content flowing from
one page to the next) or a **single page** of a size you choose (`viewport`). This page covers the
options that set the page geometry and the paper colour, and how a document's own `@page` rules take
part. The snippets are sections of `docs/examples/pdf.mjs`, which renders them; `pdf` is a
`PdfRenderer` with Inter registered and `card` a small node tree ([PDF quick start](index.md)).

- [Page size, orientation and margins](#page-size-orientation-and-margins)
- [One page: `viewport`](#one-page-viewport)
- [Page rules: `@page`](#page-rules-page)

## Page size, orientation and margins

| Option | Meaning |
|:--|:--|
| `size` | A page size name or `{ width, height }` in CSS px. Default `"a4"`. |
| `landscape` | `true` swaps the page's width and height, also for an explicit `size`. |
| `margin` | One number for all sides, or `{ top, right, bottom, left }`. Each side is a number in CSS px or `"auto"`; a side you leave out is `"auto"`. Default `"auto"` on every side. |
| `backgroundColor` | The paper colour, any CSS colour, painted under everything on every page. Unset leaves the page empty. |

Size names are `a3`, `a4`, `a5`, `b4`, `b5`, `jis-b4`, `jis-b5`, `ledger`, `legal` and `letter`, matched
without regard to case and portrait (`ledger` is 11 x 17 in, `letter` 8.5 x 11 in). A PDF page is
measured in points: one CSS px is 0.75 pt, so `{ width: 400, height: 240 }` is a 300 x 180 pt page.

<!-- @example pdf#custom-size -->
```js
const ticket = await pdf.render(card, {
  size: { width: 400, height: 240 }, // CSS px: 300 x 180 pt
  margin: { top: 12, right: 12, bottom: 12, left: 12 },
  backgroundColor: "#ffffff",       // paper colour under everything
});
```

`"auto"` on a side that carries a header or footer makes the margin as large as the band needs (the
band's height plus 20 px, and at least 10 mm, which is 37.8 px); on the other sides, and on a side
without a band, it is 10 mm. See [Headers, footers and page counters](headers-footers.md#margins-and-bands).
`landscape` and an `@page` rule can also set the page size; a document's `@page { size: ... }` wins
over the `size` option ([Page rules](#page-rules-page)).

Pages must leave room for content: a size and margins that leave less than 1 px of width or height
throw `Page size must be finite and larger than zero`. An unknown size name throws
`unknown page size: <name>`.

## One page: `viewport`

`viewport: { width, height? }` renders the whole document on a single page of that size in CSS px, with
no margins, headers or page breaks. Without `height`, the page is as tall as the laid-out content. This
is the form for tickets, badges and posters. `viewport` cannot be combined with `size`, `landscape`,
`margin`, `header`, `footer`, `pages` or `pageRanges`; doing so throws `viewport is mutually exclusive
with the paged options (size, landscape, margin, header, footer, pages, pageRanges)`.

<!-- @example pdf#viewport -->
```js
const poster = await pdf.render(card, { viewport: { width: 600 } }); // one page, as tall as the content
```

## Page rules: `@page`

A document can set its own page geometry with `@page` rules in an HTML `<style>` element or in the `css`
option (which also works for node trees). A document's `@page { size; margin }` wins over the `size` and
`margin` options, as with Chromium's `preferCSSPageSize`. `:first`, `:left` and `:right` pages, named
pages (the `page` property with `@page name`) and `@page` inside `@media`, `@layer` or `@supports` are
supported; page-margin boxes (`@top-center`, ...) are skipped. Pages of different widths each
lay their content out at their own width. [Pagination → Page rules](pagination.md#page-rules) has the
examples and every supported descriptor, and [Named pages](pagination.md#named-pages) how pages of different
widths work.

| You want | Use |
|:--|:--|
| The same paper for every document of an application | the `size` / `margin` options |
| The document decides (templates written by others) | `@page` in the document |
| A different first page (cover, letterhead) | `@page :first { margin-top: ... }` |
| One page exactly as tall as the content | `viewport: { width }` |
