# TanStack Start

[English](tanstack-start.md) · [Tiếng Việt](../../../vi/image/frameworks/tanstack-start.md)

TanStack Start server routes define HTTP handlers that receive a Web `Request` and return a `Response`.
An Open Graph endpoint is therefore the [universal pattern](./index.md#the-universal-pattern) placed
under `server.handlers`.

The route below is an integration template. Verify the route-definition API against the TanStack Start version in your application; it has not been tested in a complete framework build here.

## A server route

```tsx
// src/routes/og-image.ts
import { createFileRoute } from "@tanstack/react-router";
import { getRenderer, card } from "../server/og";          // the overview's og.js
import { imageResponse } from "../server/image-response";  // the overview's helper

export const Route = createFileRoute("/og-image")({
  server: {
    handlers: {
      GET: ({ request }) => {
        const url = new URL(request.url);
        return imageResponse(getRenderer(), card({
          title: url.searchParams.get("title") ?? "bm-engine + TanStack Start",
          description: url.searchParams.get("description") ?? "A server route",
        }), {
          width: 1200,
          height: 630,
          headers: { "cache-control": "public, max-age=3600" },
        });
      },
    },
  },
});
```

Visit `/og-image?title=Hello`. Then reference it from the page head:

```tsx
export const Route = createFileRoute("/posts/$slug")({
  head: ({ params }) => ({
    meta: [
      { property: "og:image", content: `https://example.com/og-image?title=${encodeURIComponent(params.slug)}` },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
});
```

## Using JSX

TanStack Start projects already compile JSX with React's automatic runtime, which produces React
elements, not bm-engine nodes. Options:

- Render React components to an HTML string on the server, then pass that string to bm-engine.

## Deployment targets (expected configuration)

TanStack Start builds through Vite and deploys to Node (default), Vercel, Netlify, Cloudflare and other
targets. On Node-based targets the code above runs as is; keep `bm-engine` as a runtime dependency so its
`.wasm` files are present next to `js/node-*.mjs`. On Cloudflare use the
[Workers pattern](./cloudflare-workers.md). None of these targets were built here.
