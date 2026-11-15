# Known limitations

## Before you start

- **Fonts:** no font is bundled. Text does not appear until you register a font.
- **Resources:** the image renderer does not fetch images or `@font-face` URLs. Load the bytes and pass them to the API.
- **Input:** use plain node objects, `{ json }` or HTML. Convert React elements first.
- **Layout:** `display` defaults to `inline`, and `box-sizing` to `border-box`. Set container layout explicitly.
- **Formats:** JPEG drops alpha; WebP output is always lossless; SVG converts text to outlines.
- **Measurement:** `measure()` returns box and line geometry without text content or individual glyph positions.
- **Profiles:** HTML, Tailwind, tables and floats need `standard`; SVG output and animation need `full`.
- **Memory:** WebAssembly memory can grow but does not shrink after each render. Reuse renderers and limit input dimensions.

## Cases to check separately

Complex inline layout, RTL with `pre-wrap`, line-clamp around floats and SVG painting order have constraints listed in [CSS support](css-support.md#known-gaps). Embedded SVG uses a simplified text model; see [charts](charts.md). Interactive Tailwind variants cannot apply because rendering has no hover, focus or interactive browser state.

## Next steps

Use [troubleshooting](../troubleshooting.md) to diagnose unexpected output and the [image API](api.md) for options and errors. Use [PDF](../pdf/index.md) for multi-page documents; see [PDF limitations](../pdf/limitations.md).
