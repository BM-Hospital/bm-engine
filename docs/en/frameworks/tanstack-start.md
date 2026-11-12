# TanStack Start

[English](tanstack-start.md) · [Tiếng Việt](../../vi/frameworks/tanstack-start.md)

TanStack Start server routes define HTTP handlers that receive a Web `Request` and return a `Response`.
An Open Graph endpoint is therefore the [universal pattern](./index.md#the-universal-pattern) placed
under `server.handlers`.

::: info Verification status
Verified: the `GET({ request })` handler object below was called on Node 26.13 and returned a
1200 × 630 PNG (`docs/examples/frameworks/check-frameworks.mjs`). **Not verified inside a real TanStack
Start app**: the route-definition API (`createFileRoute(...)({ server: { handlers } })`) follows takumi's
TanStack Start guide and changes between TanStack Start releases — check the version you use.
:::

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

- build node objects directly (as above), or with [`h()`](./index.md#node-trees-without-jsx) called as a
  function;
- put the card in a separate file with a `/** @jsxRuntime classic */ /** @jsx h */` pragma so that
  file's JSX calls `h` (supported by esbuild and TypeScript; Vite's React plugin may override the
  runtime — not tested here);
- convert React elements with takumi's `fromJsx()` from `@takumi-rs/helpers` (see the
  [migration guide](../migration/from-takumi.md#jsx)).

## Deployment targets (expected configuration)

TanStack Start builds through Vite and deploys to Node (default), Vercel, Netlify, Cloudflare and other
targets. On Node-based targets the code above runs as is; keep `bm-engine` as a runtime dependency so its
`.wasm` files are present next to `js/node-*.mjs`. On Cloudflare use the
[Workers pattern](./cloudflare-workers.md). None of these targets were built here.
