# Hono, Express and node:http

[English](hono-express.md) · [Tiếng Việt](../../../vi/image/frameworks/hono-express.md)

Plain Node.js servers are the most direct way to serve images with bm-render: import a Node entry (it
initialises itself), create the renderer once, and write the bytes to the response. This page shows the
same `/og.png` endpoint in Hono, Express and the bare `node:http` module.

::: info Verification status
Verified on Node 26.13 with bm-render installed from the packed tarball: each server below was started
on a random localhost port and fetched; every response was a 1200 × 630 PNG with the expected headers.
Versions: **Hono 4.13.18 with @hono/node-server 2.1.7**, **Express 5.3.0**, `node:http`
(`docs/examples/frameworks/check-servers.mjs`). Express 4.22.3 was checked only for how `res.send` handles a bare `Uint8Array` (see below).
:::

All three import the overview's `og.js` (`getRenderer()` and `card()`) and, for Hono, the
[`imageResponse()` helper](./index.md#an-imageresponse-helper).

## Hono

Hono handlers return Web `Response`s, so the helper fits directly:

```js
import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { getRenderer, card } from "./og.js";
import { imageResponse } from "./image-response.js";

const app = new Hono();

app.get("/og.png", (c) =>
  imageResponse(getRenderer(), card({ title: c.req.query("title") ?? "Hello", description: "From Hono" }), {
    width: 1200,
    height: 630,
    headers: { "cache-control": "public, max-age=3600" },
  }));

serve({ fetch: app.fetch, port: 3000 });
```

`app.fetch` is a plain `Request → Response` function, so the same app is expected to run on Bun
(`export default app`) and Deno (`Deno.serve(app.fetch)`) with the Node entry, and on Cloudflare Workers
once the renderer is initialised from an imported module (see [Cloudflare Workers](./cloudflare-workers.md));
those runtimes were not tested. In the test,
`app.fetch(new Request(...))` was also called directly, without a server, and returned the PNG.

## Express

```js
import express from "express";
import { getRenderer, card } from "./og.js";

const app = express();

app.get("/og.png", async (req, res, next) => {
  try {
    const png = await getRenderer().render(
      card({ title: String(req.query.title ?? "Hello"), description: "From Express" }),
      { width: 1200, height: 630 },
    );
    res.type("png").set("cache-control", "public, max-age=3600");
    res.send(Buffer.from(png.buffer, png.byteOffset, png.byteLength));
  } catch (error) {
    next(error);
  }
});

app.listen(3000);
```

- `Buffer.from(png.buffer, ...)` wraps the bytes without copying. It matters on Express 4: tested with
  Express 4.22.3, `res.send(png)` with the bare `Uint8Array` sent **JSON** (`{"0":137,"1":80,...}`) with an
  `image/png` content type. Express 5.3.0 sent the bare `Uint8Array` correctly. The `Buffer` view works on
  both.
- Express 5 forwards rejected promises to the error handler by itself; the explicit `try` / `next` keeps
  the code correct on Express 4.
- Set `res.type("png")` (or `content-type`) explicitly.

## node:http

No framework, plus input-derived ETags so repeated requests do not render at all:

```js
import { createServer } from "node:http";
import { getRenderer, card } from "./og.js";

const TEMPLATE_VERSION = "card-v1"; // bump when the template or fonts change

async function etagFor(params) {
  const data = new TextEncoder().encode(TEMPLATE_VERSION + "\0" + JSON.stringify(params));
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return `"${[...hash.subarray(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("")}"`;
}

createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname !== "/og.png") return res.writeHead(404).end();

  const params = {
    title: url.searchParams.get("title") ?? "Hello",
    description: url.searchParams.get("description") ?? "Rendered with bm-render",
  };
  const etag = await etagFor(params);
  const headers = { etag, "cache-control": "public, max-age=3600, stale-while-revalidate=86400" };
  if (req.headers["if-none-match"] === etag) return res.writeHead(304, headers).end();

  try {
    const png = await getRenderer().render(card(params), { width: 1200, height: 630 });
    res.writeHead(200, { ...headers, "content-type": "image/png", "content-length": png.byteLength });
    res.end(png);
  } catch (error) {
    console.error(error);
    res.writeHead(500, { "content-type": "text/plain" }).end("Failed to generate image");
  }
}).listen(3000);
```

The test requested the same URL twice with `If-None-Match`: the second answer was `304` and the
renderer was called only once. `res.end()` accepts the `Uint8Array` directly.

## Production notes

- **Validate input.** Clamp text length (`title.slice(0, 200)`), and never take `width` / `height` from
  the query string unchecked: canvases are limited to 16384 px per side and 40 megapixels, and big
  canvases grow the wasm memory permanently (see [Memory](../api.md#memory-instances-and-threads)).
- **CPU.** Rendering blocks the event loop for the duration of the render. If the server does other
  latency-sensitive work, render in a [worker_threads pool](../recipes.md#worker-threads-pool)
  (verified: 4 workers rendered 48 cards 2.5–3.9× faster than one thread on the test machine).
- **Cache.** Put a CDN in front, or keep an in-memory LRU of recent PNGs keyed by the ETag.
