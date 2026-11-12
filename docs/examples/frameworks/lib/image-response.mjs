// imageResponse(): the ~30-line helper shown in docs/{en,vi}/frameworks/index.md (keep the two in sync).
// bm-engine has no ImageResponse class; this wraps Renderer#render in a Web-standard Response.

const CONTENT_TYPES = { png: "image/png", jpeg: "image/jpeg", jpg: "image/jpeg", webp: "image/webp", ico: "image/x-icon" };

/**
 * Renders `source` (node tree, `{ json }` or HTML string) and answers with the encoded image.
 * @param {import("bm-engine").Renderer} renderer  a long-lived renderer with fonts already registered
 * @param {import("bm-engine").Source} source
 * @param {import("bm-engine").RenderOptions & { headers?: HeadersInit, status?: number, onError?: (e: unknown) => void }} [options]
 * @returns {Promise<Response>}
 */
export async function imageResponse(renderer, source, options = {}) {
  const { headers, status = 200, onError = console.error, ...renderOptions } = options;
  const format = renderOptions.format ?? "png";
  if (format === "raw") throw new TypeError("imageResponse: use an encoded format, not raw");
  let bytes;
  try {
    bytes = await renderer.render(source, renderOptions);
  } catch (error) {
    onError(error);
    return new Response("Failed to generate image", { status: 500, headers: { "content-type": "text/plain; charset=utf-8" } });
  }
  const h = new Headers(headers);
  if (!h.has("content-type")) h.set("content-type", CONTENT_TYPES[format] ?? "application/octet-stream");
  h.set("content-length", String(bytes.byteLength));
  return new Response(bytes, { status, headers: h });
}
