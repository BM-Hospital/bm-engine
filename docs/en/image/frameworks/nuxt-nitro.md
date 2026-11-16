# Nuxt and Nitro

[English](nuxt-nitro.md) · [Tiếng Việt](../../../vi/image/frameworks/nuxt-nitro.md)

Nuxt's server side is Nitro, and Nitro routes are [h3](https://h3.dev) event handlers. An h3 handler may
return a Web `Response`, so a bm-render route is the [universal pattern](./index.md#the-universal-pattern)
inside `defineEventHandler`. This page covers Nuxt `server/routes`, standalone Nitro, and what changes on
edge presets. There is no Nuxt module for bm-render.

::: info Verification status
Verified: the handler below ran under **h3 2.0.8** (`new H3().get(...)`, requested through `app.fetch`)
on Node 26.13 and returned a 1200 × 630 PNG with `content-type: image/png`
(`docs/examples/frameworks/check-servers.mjs`). **Not verified inside a real Nuxt or Nitro build**: Nuxt 3/4
ship h3 1.x, whose handling of a returned `Response` was not tested here; the bundling notes below are
expected configuration, not tested.
:::

## Nuxt: a server route

```ts
// server/utils/og.ts — auto-imported in server code
import { readFileSync } from "node:fs";
import { Renderer } from "bm-render/standard";

let renderer: Renderer | undefined;

export function getOgRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf"), weight: 400 });
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf"), weight: 700 });
  }
  return renderer;
}
```

```ts
// server/routes/og.png.ts  ->  GET /og.png?title=...
import { card } from "~/server/utils/card";            // the card() template from the overview
import { imageResponse } from "~/server/utils/image-response"; // the helper from the overview

export default defineEventHandler((event) => {
  const { title = "bm-render + Nuxt", description = "A Nitro server route" } = getQuery(event);
  return imageResponse(getOgRenderer(), card({ title: String(title), description: String(description) }), {
    width: 1200,
    height: 630,
    headers: { "cache-control": "public, max-age=3600" },
  });
});
```

- `defineEventHandler` and `getQuery` are auto-imported by Nuxt / Nitro; outside them import from `h3`.
- Reading fonts with a path relative to the working directory works when the server is started from
  the project root. In a production build (`.output/`) the working directory and the file layout differ:
  copy the fonts with the build (for example into `public/` or a server asset directory) and read them
  from there, or use Nitro's server assets (`useStorage("assets:server")`) — check the Nitro docs for your
  version.
- If you prefer to return bytes instead of a `Response`, set the header yourself:
  `setResponseHeader(event, "content-type", "image/png"); return png;` (h3 sends a `Uint8Array` as the
  body).

## Standalone Nitro / plain h3

The handler is the same. With h3 directly (what was run):

```js
import { H3, defineEventHandler, getQuery } from "h3";
import { getRenderer, card } from "./og.js";
import { imageResponse } from "./image-response.js";

const app = new H3().get("/og.png", defineEventHandler((event) => {
  const { title = "Hello" } = getQuery(event);
  return imageResponse(getRenderer(), card({ title: String(title), description: "From h3" }), { width: 1200, height: 630 });
}));

// app.fetch(request) is a Web-standard handler; serve it with h3's `serve(app)` or any adapter
const res = await app.fetch(new Request("http://localhost/og.png?title=Nitro"));
```

In a Nitro project, put the same `defineEventHandler` in `routes/og.png.ts` (Nitro v2: `server/routes/`
in Nuxt, `routes/` standalone).

## Presets and bundling (expected configuration)

| Preset | What to do |
|:--|:--|
| `node-server` (default), `vercel` (Node functions), `netlify` | `import ... from "bm-render/standard"` as above. Nitro traces dependencies into `.output/server/node_modules`; bm-render's Node entry then reads its `.wasm` from there. If the `.wasm` file is missing at runtime, make sure bm-render stays external (do not list it in `nitro.externals.inline`) and that its `js/*.wasm` files were copied. |
| `cloudflare-module`, `cloudflare-pages`, `vercel-edge` | no `node:fs`: import the binary as a module and call `initSync(module)`, and bundle fonts as data. Nitro's WebAssembly support (unwasm) controls how `.wasm` imports are handled; the pattern on the [Cloudflare Workers page](./cloudflare-workers.md) is the target shape. Not tested with Nitro. |

bm-render instantiates its binary itself and needs either the bytes or an uninstantiated
`WebAssembly.Module`; a bundler integration that instantiates `.wasm` imports for you (ESM-integration
style) is not compatible. If `initSync` throws `Argument 0 must be a buffer source` although you passed
a module, see the cross-realm note on the [Next.js page](./nextjs.md#edge-runtime).

## Using it from a Vue page

Point the meta tags at the route; nothing else is needed on the client:

```ts
// pages/blog/[slug].vue  (script setup)
const route = useRoute();
useSeoMeta({
  ogImage: `https://example.com/og.png?title=${encodeURIComponent(String(route.params.slug))}`,
  twitterCard: "summary_large_image",
});
```

bm-render does not render Vue components. Build
the node tree in the server route (or render a Vue component to an HTML string with Vue's server
renderer and pass the string — HTML input needs the `standard` or `full` profile; see
[HTML and Tailwind](../html-and-tailwind.md); not tested with Vue).
