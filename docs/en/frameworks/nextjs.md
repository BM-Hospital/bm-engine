# Next.js

[English](nextjs.md) · [Tiếng Việt](../../vi/frameworks/nextjs.md)

Serve Open Graph images from a Next.js App Router route handler, or let Next.js discover them through the
`opengraph-image` file convention. bm-engine replaces `next/og`'s `ImageResponse` with a renderer you own
and a plain `Response`; the image is a node tree (or HTML), not JSX — see
[Node trees without JSX](./index.md#node-trees-without-jsx) for a small `h()` helper.

::: info Verification status
Verified with **Next.js 16.4.6 (Turbopack), `next build` + `next start` on Node 26.13**, bm-engine installed
from the packed tarball: the route handler and `opengraph-image.js` below returned 1200 × 630 PNGs, and the
page's `og:image` meta tags were generated. The Edge runtime route returned a PNG **only with the
workaround shown** (bm-engine 0.1.0 rejects the `WebAssembly.Module` Next.js passes; see
[Edge runtime](#edge-runtime)). The webpack builder (`next build --webpack`), Vercel deployments and
other Next.js versions were not tested. The test app is in
[`docs/examples/frameworks/nextjs/`](../../../docs/examples/frameworks/nextjs/).
:::

## 1. Install and keep bm-engine external

```sh
npm install bm-engine
```

```js
// next.config.mjs
/** @type {import("next").NextConfig} */
export default {
  serverExternalPackages: ["bm-engine"],
};
```

`serverExternalPackages` is **required** for the Node.js runtime: bm-engine's Node entry reads its
`.wasm` file next to itself with `readFileSync(new URL("./bm_engine....wasm", import.meta.url))`. When
Turbopack bundles that module it rewrites the `new URL(...)` and the build fails while prerendering:

```
TypeError: The "path" argument must be of type string or an instance of Buffer or URL. Received an instance of URL
```

With the package external, Node loads it from `node_modules` and everything works (verified both ways).

## 2. Shared renderer and template

Put the renderer in a module so it is created once per server process. Next.js runs route handlers with
the project root as the working directory, so `process.cwd()` is a reliable base for font files kept in
the repository:

```js
// lib/og.js
import { readFileSync } from "node:fs";
import path from "node:path";
import { Renderer } from "bm-engine/standard";

let renderer;

export function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    const dir = path.join(process.cwd(), "fonts");
    renderer.registerFont({ name: "Inter", data: readFileSync(path.join(dir, "Inter-Regular.ttf")), weight: 400 });
    renderer.registerFont({ name: "Inter", data: readFileSync(path.join(dir, "Inter-Bold.ttf")), weight: 700 });
  }
  return renderer;
}

export function card({ title, description }) {
  return {
    type: "container",
    style: {
      display: "flex", flexDirection: "column", justifyContent: "center", gap: 24,
      width: "100%", height: "100%", padding: 64, fontFamily: "Inter",
      backgroundImage: "linear-gradient(to bottom right, #fff7ed, #fecaca)",
    },
    children: [
      { type: "text", text: title, style: { fontSize: 72, fontWeight: 700, color: "#111827" } },
      { type: "text", text: description, style: { fontSize: 42, color: "#4b5563" } },
    ],
  };
}
```

## 3. A route handler

```js
// app/og/route.js
import { getRenderer, card } from "../../lib/og.js";

export const runtime = "nodejs"; // the default; stated for clarity

export async function GET(request) {
  const { searchParams } = new URL(request.url);
  const png = await getRenderer().render(
    card({
      title: searchParams.get("title") ?? "bm-engine + Next.js",
      description: searchParams.get("description") ?? "Rendered in a route handler",
    }),
    { width: 1200, height: 630 },
  );
  return new Response(png, {
    headers: { "content-type": "image/png", "cache-control": "public, max-age=3600" },
  });
}
```

Visit `/og?title=Hello`. The response carried the `cache-control` header unchanged in the test. To
control the error response (a short text `500` plus an `onError` hook), use the
[`imageResponse()` helper](./index.md#an-imageresponse-helper) in place of `new Response`.

## 4. The `opengraph-image` file convention

Next.js reads an `opengraph-image.js` (or `twitter-image.js`) next to a `page.js`, serves it, and adds the
`og:image`, `og:image:type`, `og:image:width` and `og:image:height` tags. Its default export may return a
`Response`, so no `ImageResponse` is needed:

```js
// app/opengraph-image.js
import { getRenderer, card } from "../lib/og.js";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "bm-engine + Next.js";

export default async function Image() {
  const png = await getRenderer().render(card({ title: "bm-engine + Next.js", description: "opengraph-image file convention" }), size);
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

Without dynamic inputs Next.js prerenders this at build time (the build listed `/opengraph-image` as
static and served it with `cache-control: s-maxage=31536000`). For per-page images in a dynamic segment,
the default export receives `{ params }` (a promise in recent Next.js versions) — build the card from it
(not part of the test).
Set `metadataBase` in your root layout so the generated URLs are absolute; the build warns otherwise.

## Edge runtime

On the Edge runtime there is no `node:fs`, so the Node entry cannot be used. You must import the binary
as a WebAssembly module and pass it to `initSync`. What happened in the test with Next.js 16.4.6
(Turbopack):

| Attempt | Result |
|:--|:--|
| `import wasm from "bm-engine/core.wasm?module"` | build error: `Module not found: Can't resolve 'bm-engine/core.wasm'` |
| `import wasm from "bm-engine/core.wasm"` | build error: Turbopack instantiates the file itself (`Export default doesn't exist in target module`) |
| `import { init } from "bm-engine/core"; await init()` | builds; fails at request time (`fetch failed`, `invalid method`): the emitted asset URL cannot be fetched inside the edge sandbox |
| relative path + `?module`, as below | builds; `initSync` throws `WebAssembly.Module(): Argument 0 must be a buffer source` **unless** the workaround line is added; with it: 200, 1200 × 630 PNG |

```js
// app/og-edge/route.js
import { initSync, Renderer } from "bm-engine/core";
import wasm from "../../node_modules/bm-engine/js/bm_engine.core.wasm?module";

export const runtime = "edge";

let renderer;
async function getRenderer() {
  if (!renderer) {
    // Next.js hands the edge sandbox a WebAssembly.Module from another realm; bm-engine 0.1.0 checks
    // `instanceof WebAssembly.Module`, so re-brand it with this realm's prototype first.
    if (!(wasm instanceof WebAssembly.Module)) Object.setPrototypeOf(wasm, WebAssembly.Module.prototype);
    initSync(wasm);
    const font = await fetch(new URL("../../fonts/Inter-Regular.ttf", import.meta.url)).then((r) => r.arrayBuffer());
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: font });
  }
  return renderer;
}

export async function GET(request) {
  const title = new URL(request.url).searchParams.get("title") ?? "Edge";
  const r = await getRenderer();
  const png = r.renderSync(
    { type: "container", style: { display: "flex", width: "100%", height: "100%", padding: 64, backgroundColor: "#7c3aed" },
      children: [{ type: "text", text: title, style: { fontFamily: "Inter", fontSize: 72, color: "white" } }] },
    { width: 1200, height: 630 },
  );
  return new Response(png, { headers: { "content-type": "image/png" } });
}
```

::: warning The Edge path relies on a workaround
The `Object.setPrototypeOf` line works around a bm-engine 0.1.0 limitation (its module check is
realm-sensitive) and the relative `node_modules` path depends on your install layout (it breaks with
hoisting changes, pnpm or monorepos). Prefer the Node.js runtime unless you need Edge. If you deploy to
Edge, test the deployed route, not only `next start`.
:::

Size matters on Edge: the `core` binary is 454.5 KiB raw (about 210 KiB gzip) and fonts add their own
size; see [Profiles and size](../profiles-and-size.md).

## Coming from `next/og`

| `next/og` | bm-engine |
|:--|:--|
| `new ImageResponse(jsx, { width, height })` | `new Response(await renderer.render(node, { width, height }), { headers })` or [`imageResponse()`](./index.md#an-imageresponse-helper) |
| JSX elements | node objects, HTML strings, or JSX through [`h()`](./index.md#node-trees-without-jsx) |
| every `div` is `display: flex` | every node is `display: inline` until you set `display` |
| bundled default font | no font until you register one |
| `emoji` option (fetches Twemoji) | register a colour emoji font (`full` profile) |
| `fonts: [{ name, data, weight, style }]` per response | `renderer.registerFont(...)` once, or the `fonts` render option |

See [Migrating from satori and next/og](../migration/from-satori.md) for the full list.
