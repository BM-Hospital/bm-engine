# Astro

[English](astro.md) · [Tiếng Việt](../../../vi/image/frameworks/astro.md)

Astro endpoints are files in `src/pages/` that export `GET`. In a static build Astro calls them once per
path and writes the returned bytes to `dist/`, which makes them the simplest way to ship one Open Graph
image per page with zero runtime cost. In server mode the same endpoint renders on request.

Use an Astro server endpoint to return the image bytes. The example below shows the integration pattern; verify it in your application build.

## One image per page at build time

```js
// src/pages/og/[slug].png.js  ->  dist/og/<slug>.png
import { getCollection } from "astro:content";
import { getRenderer, card } from "../../lib/og.js"; // the overview's og.js

export async function getStaticPaths() {
  const posts = await getCollection("blog");
  return posts.map((post) => ({
    params: { slug: post.id },
    props: { title: post.data.title, description: post.data.description },
  }));
}

export async function GET({ props }) {
  const png = await getRenderer().render(card(props), { width: 1200, height: 630 });
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

- The `.png` in the file name becomes the extension of the generated file.
- The renderer is created once for the whole build (module scope), so fonts are parsed once even for
  thousands of pages: the batch recipe rendered 48 cards in about 0.7 s on one thread.
- Fonts can be read with `readFileSync` relative to the project root (`process.cwd()` during the build).

Reference the image from your layout:

```astro
---
// src/layouts/Post.astro
const { title, slug } = Astro.props;
const ogImage = new URL(`/og/${slug}.png`, Astro.site);
---
<meta property="og:title" content={title} />
<meta property="og:image" content={ogImage} />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
```

Set `site` in `astro.config.mjs` so `Astro.site` is defined.

## On-demand rendering

With an adapter and `output: "server"` (or `export const prerender = false` on the endpoint), the same
`GET` runs per request. Read the parameters from the URL instead of props:

```js
// src/pages/og.png.js
import { getRenderer, card } from "../lib/og.js";
import { imageResponse } from "../lib/image-response.js";

export const prerender = false;

export async function GET({ url }) {
  return imageResponse(getRenderer(), card({
    title: url.searchParams.get("title") ?? "bm-render + Astro",
    description: url.searchParams.get("description") ?? "On-demand endpoint",
  }), { width: 1200, height: 630, headers: { "cache-control": "public, max-age=86400" } });
}
```

With `@astrojs/node` this is the Node entry as usual. With `@astrojs/cloudflare` follow the
[Cloudflare Workers](./cloudflare-workers.md) pattern (import the `.wasm` as a module, fonts as data);
not tested with Astro's Vite pipeline.

## Without endpoints: a build script

If you would rather not touch Astro's routing, run a Node script before `astro build` that writes PNGs to
`public/og/` (Astro copies `public/` as is). The [build-time recipe](../recipes.md#generate-at-build-time)
does that and skips posts whose inputs did not change:

```json
{ "scripts": { "build": "node scripts/build-og.mjs public/og && astro build" } }
```
