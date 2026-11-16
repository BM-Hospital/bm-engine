# SvelteKit

[English](sveltekit.md) · [Tiếng Việt](../../../vi/image/frameworks/sveltekit.md)

A SvelteKit endpoint (`+server.js`) is a function from a request event to a `Response`, which is exactly
what bm-render needs. This page shows a dynamic endpoint, a prerendered one, and how to feed a Svelte
component's HTML to bm-render.

::: info Verification status
Verified: the `GET` handler below was called on Node 26.13 with the event shape SvelteKit passes
(`{ url, request }`) and returned a 1200 × 630 PNG (`docs/examples/frameworks/check-frameworks.mjs`).
**Not verified inside a real SvelteKit project** (no `vite build`, no adapter); the adapter notes are
expected configuration.
:::

## A dynamic endpoint

Put `og.js` (`getRenderer()` and `card()`) and `image-response.js` from the
[overview](./index.md#the-universal-pattern) in `src/lib/server/`.

```js
// src/routes/og.png/+server.js   ->  GET /og.png?title=...
import { getRenderer, card } from "$lib/server/og.js";
import { imageResponse } from "$lib/server/image-response.js";

export async function GET({ url }) {
  return imageResponse(
    getRenderer(),
    card({ title: url.searchParams.get("title") ?? "bm-render + SvelteKit", description: "A +server.js endpoint" }),
    { width: 1200, height: 630, headers: { "cache-control": "public, max-age=3600" } },
  );
}
```

In TypeScript, type it as `export const GET: RequestHandler = async ({ url }) => ...` with
`import type { RequestHandler } from "./$types"`. Keep the renderer in `$lib/server/` so it is never
imported into client code.

Fonts: with `adapter-node`, read them from disk relative to the working directory (or bundle them with
`?url` / static files). Remember the build output lives in `build/`; files in `static/` are copied there.

## Prerendering at build time

For images that depend only on build-time data, prerender the endpoint and the files are written to
the output like any static asset:

```js
// src/routes/og/[slug].png/+server.js
import { getRenderer, card } from "$lib/server/og.js";
import { posts } from "$lib/posts.js";

export const prerender = true;

export function entries() {
  return posts.map((post) => ({ slug: post.slug }));
}

export async function GET({ params }) {
  const post = posts.find((p) => p.slug === params.slug);
  const png = await getRenderer().render(card(post), { width: 1200, height: 630 });
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

Prerendering runs on Node during `vite build`, so the Node entry works even if you deploy to an edge
adapter afterwards (only the static PNGs ship).

## Rendering a Svelte component

You can render a component with `svelte/server` and passes `head + body` as HTML. The
same works with bm-render's HTML input, which needs the `standard` or `full` profile (HTML parsing, plus
the `css` feature for the injected `<style>` block). Fonts still come from the renderer: register them
once instead of passing a font URL with every response:

```js
// src/routes/og-svelte.png/+server.js
import { render } from "svelte/server";
import OgImage from "$lib/components/OgImage.svelte"; // use <svelte:options css="injected" />
import { getRenderer } from "$lib/server/og.js";

export async function GET({ url }) {
  const { head, body } = render(OgImage, { props: { name: url.searchParams.get("name") ?? "you" } });
  const png = await getRenderer().render(head + body, { width: 1200, height: 630 });
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

This variant was not run (Svelte not installed). Check the HTML and CSS features you rely on in
[HTML and Tailwind](../html-and-tailwind.md); remember that bm-render renders, it does not run
component scripts.

## Adapters (expected configuration)

| Adapter | Notes |
|:--|:--|
| `adapter-node` | works like any Node server; keep `bm-render` a runtime dependency (SvelteKit leaves `dependencies` external by default). |
| `adapter-vercel` (Node runtime), `adapter-netlify` | same as Node; make sure the `.wasm` files under `node_modules/bm-render/js/` are included in the function bundle. |
| `adapter-cloudflare` | no `node:fs`: follow the [Cloudflare Workers](./cloudflare-workers.md) pattern (`initSync` with an imported module, fonts as data) — or prerender the images. |
| `adapter-static` | prerender everything (above). |
