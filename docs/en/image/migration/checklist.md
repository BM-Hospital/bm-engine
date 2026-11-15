# Integration checklist

Follow these steps when adding bm-engine to an application or adapting an existing image template.

1. **Choose the input.** Use plain node objects or HTML with `standard` / `full`. For JSX, see the [node factory](../frameworks/index.md#node-trees-without-jsx).
2. **Register fonts.** Load font bytes once per renderer. Text does not appear without a registered font.
3. **Set the layout.** Give containers `display: "flex"`, `"grid"` or `"block"` where needed. The default is `inline`.
4. **Load images.** Fetch image bytes yourself and pass them through `images`; the image renderer does not fetch URLs.
5. **Choose dimensions and format.** Start with PNG; give JPEG output an opaque background.
6. **Return an HTTP response.** Set the format's `Content-Type` and cache results when content changes infrequently.
7. **Reuse the renderer.** Register fonts once. Use async native APIs on servers, or workers with WebAssembly to avoid blocking the main thread.
8. **Check real examples.** Try long text, Vietnamese, emoji, failed images and overflowing content. Then choose a smaller profile if it covers your needs.

See [frameworks](../frameworks/index.md), [troubleshooting](../../troubleshooting.md) and [known limitations](../limitations.md).
