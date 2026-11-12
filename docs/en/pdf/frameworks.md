# Serving PDFs from a framework

[English](frameworks.md) · [Tiếng Việt](../../vi/pdf/frameworks.md)

Serving a PDF is the same job as serving an image: create a renderer once, render per request, wrap the
bytes in a `Response`. The framework pages of the Image section show the setup for each framework
([Frameworks and runtimes](../image/frameworks/index.md): Next.js, Nuxt and Nitro, SvelteKit, Astro,
TanStack Start, Hono, Express, node:http, Cloudflare Workers, Deno, Bun, Vite). Everything there applies
to PDF output; this page lists only what is different and gives a handler you can drop into any of them.

::: info Verification status
Every snippet on this page is a section of `docs/examples/pdf-frameworks.mjs` in the repository and was
executed by it on Node 26.13, once on the native addon (`backend` reported `"native"`) and once with
`BM_ENGINE_BACKEND=wasm` (`backend` reported `"wasm"`): the handler was called in-process with a real
`Request`, and through the `node:http` server below on a local port with `fetch`. Both runs checked the
status, `content-type: application/pdf`, `content-disposition`, `content-length` and the `%PDF-` file
header, and that an already aborted request rejects with `AbortError`. The framework adapters themselves
were not run with PDF output.
:::

- [What is different from images](#what-is-different-from-images)
- [A renderer per process](#a-renderer-per-process)
- [A `pdfResponse()` helper](#a-pdfresponse-helper)
- [A handler for any framework](#a-handler-for-any-framework)
- [node:http](#nodehttp)
- [Edge runtimes and browsers](#edge-runtimes-and-browsers)

## What is different from images

| | Image | PDF |
|:--|:--|:--|
| Import | `bm-engine` or a profile entry (`bm-engine/core`, `/standard`, `/full`) | `bm-engine/pdf` only; the other entries throw on `renderPdf` ([PDF quick start](index.md)) |
| Renderer | `Renderer` | `PdfRenderer` (same font API: `registerFont`, `loadFont`, ...) |
| Size of the result | set by `width` / `height` | set by the document: one or more pages (`size`, `margin`, `viewport`) |
| `content-type` | `image/png`, `image/webp`, ... | `application/pdf` |
| `content-disposition` | usually not set | `inline` (shown in the browser's viewer) or `attachment` (saved as a file), with a `filename` |
| Caching | OG images are a pure function of the URL: cache hard | documents are often per user: `private, no-store` unless they are public |
| wasm binary for Workers / browsers | `bm_engine.wasm` and smaller profiles | `bm_engine.pdf.wasm`: 1 555.8 KiB raw, 761.6 KiB gzip, 625.1 KiB brotli |

`render()` returns the whole file as one `Uint8Array` once the document is finished; there is no
streaming API. The examples on this page are 15 KiB; the [recipes](recipes.md) are 19 to 40 KiB, most of
it subset fonts. Set `content-length` from `byteLength`.

On Node.js `bm-engine/pdf` uses the native addon when it is installed: then `render()` runs on the libuv
thread pool and does not block the event loop. On the wasm backend (and everywhere outside Node.js) the
render is synchronous work on the calling thread, as for images; see [Native and
WebAssembly](native-and-wasm.md) and, for a worker pool, [Image recipes](../image/recipes.md#worker-threads-pool).

## A renderer per process

As for images, create the `PdfRenderer` lazily, once per process or isolate, and register the fonts in it
([Fonts in PDF](fonts.md)):

<!-- @example pdf-frameworks#renderer -->
```js
// pdf.js — create the renderer once per process (or per isolate), not per request
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

let renderer;
export function getPdfRenderer() {
  if (!renderer) {
    renderer = new PdfRenderer();
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
  }
  return renderer;
}
```

## A `pdfResponse()` helper

The PDF counterpart of the image section's [`imageResponse()`](../image/frameworks/index.md#an-imageresponse-helper):

<!-- @example pdf-frameworks#helper -->
```js
/** PDF bytes -> a web-standard Response. `download: true` makes browsers save the file instead of showing it. */
export function pdfResponse(bytes, { filename = "document.pdf", download = false, headers = {} } = {}) {
  return new Response(bytes, {
    headers: {
      "content-type": "application/pdf",
      "content-length": String(bytes.byteLength),
      "content-disposition": `${download ? "attachment" : "inline"}; filename="${filename}"`,
      ...headers,
    },
  });
}
```

`inline` lets the browser open its PDF viewer; `attachment` makes it download the file under `filename`.
A `filename` with characters outside ASCII needs the RFC 6266 form `filename*=UTF-8''...` as well.

## A handler for any framework

Next.js Route Handlers, SvelteKit `+server.js`, Astro endpoints, TanStack Start server routes, Hono, Nitro
(h3 2), Cloudflare Workers, Deno and Bun all hand you a web-standard `Request` and accept a `Response`, so
this function works as is: export it as `GET`, return it from `app.get(...)`, or call it from `fetch`.

<!-- @example pdf-frameworks#handler -->
```js
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** GET /report.pdf?name=Ada[&download=1] — works wherever a framework hands you a Request. */
export async function handleReport(request) {
  const url = new URL(request.url);
  const name = escapeHtml((url.searchParams.get("name") ?? "World").slice(0, 100));
  const bytes = await getPdfRenderer().render(
    `<div style="font-family: Inter; font-size: 14px">
       <h1>Report for ${name}</h1>
       <p>Generated on ${new Date().toISOString().slice(0, 10)}.</p>
     </div>`,
    {
      size: "a4",
      footer: `<div style="font: 10px Inter; text-align: center">Page <span class="pageNumber"></span></div>`,
      signal: request.signal, // a request the client abandoned is not rendered
    },
  );
  return pdfResponse(bytes, {
    filename: "report.pdf",
    download: url.searchParams.has("download"),
    headers: { "cache-control": "private, no-store" },
  });
}
```

- **Escape input** that goes into HTML (`escapeHtml` above) and clamp its length, as for images.
- **`signal: request.signal`** checks the request's `AbortSignal` before the render reads and draws the
  document: an aborted request rejects with `AbortError` instead of rendering. It does not interrupt a
  render that has already started.
- On Next.js and other bundling deployers, the setup of the Image section applies unchanged (for example
  `serverExternalPackages: ["bm-engine"]` and copying the platform package:
  [Next.js](../image/frameworks/nextjs.md)); the PDF entry lives in the same package.

## node:http

`node:http` has no `Request` / `Response`; convert at the edge (frameworks do this for you). The test ran
this server on an ephemeral port and fetched `/report.pdf`:

<!-- @example pdf-frameworks#node-http -->
```js
import { createServer } from "node:http";
import { Readable } from "node:stream";

// node:http has no Request / Response: convert at the edge (Hono, Nitro, SvelteKit, ... do this for you)
const server = createServer(async (req, res) => {
  const controller = new AbortController();
  res.on("close", () => { if (!res.writableFinished) controller.abort(); });
  try {
    const request = new Request(new URL(req.url, `http://${req.headers.host}`), { signal: controller.signal });
    const response = await handleReport(request);
    res.writeHead(response.status, Object.fromEntries(response.headers));
    Readable.fromWeb(response.body).pipe(res);
  } catch (error) {
    if (!controller.signal.aborted) console.error(error);
    if (!res.headersSent) res.writeHead(500, { "content-type": "text/plain" }).end("Failed to render the PDF");
  }
});
server.listen(Number(process.env.PORT ?? 3000));
```

Express can use the same handler through such an adapter, or render directly and `res.end(bytes)` with the
headers of `pdfResponse()`; the Express specifics are on [Hono, Express and
node:http](../image/frameworks/hono-express.md).

## Edge runtimes and browsers

Outside Node.js, `bm-engine/pdf` is the wasm `pdf` profile and must be initialised once before the first
render: `await init()` fetches `bm_engine.pdf.wasm` next to the module (browsers, bundlers), and on
Cloudflare Workers you import the binary as a module and pass it:

```js
import wasm from "bm-engine/pdf.wasm";
import { init, PdfRenderer } from "bm-engine/pdf";

await init(wasm);
```

This snippet was not run under wrangler. The compressed size of `bm_engine.pdf.wasm` (761.6 KiB gzip)
counts against the Workers script-size limit of your plan; see [Cloudflare
Workers](../image/frameworks/cloudflare-workers.md) for the rest of the setup and the [PDF quick
start](index.md) for a browser example that opens the result with a
`Blob` URL.
