# Frameworks and runtimes

[English](index.md) · [Tiếng Việt](../../../vi/image/frameworks/index.md)

bm-engine is a plain library: give it a node tree (or HTML) and it returns image bytes. It has no
framework plugin, no `ImageResponse` class and no JSX runtime, so every integration is the same three
lines of glue — create a renderer, register fonts, wrap the bytes in a `Response`. This page explains the
parts every integration shares: which package entry to import, the "create once" pattern, a ~30-line
`imageResponse()` helper you can paste, caching headers, font loading, and how to build node trees
without JSX. The per-framework pages then only show what differs.

::: info Verification status
Every snippet on this page was executed on Node 26.13 against the packed npm tarball of bm-engine 0.1.0
(`npm pack`, installed into a scratch project): `imageResponse()` was called with a real `Request`, its
`Response` body was decoded as a 1200 × 630 PNG; `h()` was checked to produce byte-identical output to
hand-written nodes, also as an esbuild JSX factory; the manual wasm-loading paths ran under
`node --conditions=browser`. The scripts live in
[`docs/examples/frameworks/`](../../../examples/frameworks/) (`node docs/examples/frameworks/run-all.mjs`).
:::

| Guide | Runtime | What was verified |
|:--|:--|:--|
| [Next.js](./nextjs.md) | Node.js runtime, Edge runtime | handler functions; see the page |
| [Nuxt and Nitro](./nuxt-nitro.md) | Nitro (h3) server routes | handler under h3 2.0.8 |
| [SvelteKit](./sveltekit.md) | `+server.js` endpoints | handler function |
| [Astro](./astro.md) | endpoints, static generation | handler + `getStaticPaths` |
| [TanStack Start](./tanstack-start.md) | server routes | handler function |
| [Hono, Express, node:http](./hono-express.md) | Node.js servers | real servers on localhost |
| [Cloudflare Workers](./cloudflare-workers.md) | workerd | wrangler bundle, run with Workers module semantics emulated |
| [Deno and Bun](./deno-bun.md) | Deno, Bun | not run (not installed); handler run on Node |
| [Vite and browsers](./vite-browser.md) | browsers, Web Workers | headless Edge 157 |

## Which entry to import

The package has one generic entry and three fixed-profile entries. Which file a specifier resolves to
depends on the runtime's export conditions:

| Import | Node.js, Bun, Deno (`node` condition) | Browsers, bundlers for the browser, workerd, Vercel Edge |
|:--|:--|:--|
| `bm-engine` | full binary, read from disk and initialised on import | wrapper only: you call `init(wasm)` |
| `bm-engine/core` · `/standard` · `/full` | that profile, initialised on import | `await init()` fetches the binary next to the module (or pass it) |
| `bm-engine/wasm` (= `full.wasm`), `bm-engine/core.wasm`, `/standard.wasm`, `/full.wasm`, `/woff.wasm` | the raw binary file | the raw binary file (asset URL with `?url` in Vite, `WebAssembly.Module` under wrangler) |

Rules of thumb:

- **Server on Node.js (Express, Hono on Node, Next.js Node runtime, Nuxt / SvelteKit / Astro with the
  Node adapter):** `import { Renderer } from "bm-engine/standard"` (or `/core`, `/full`). Nothing to
  initialise; the binary is read with `node:fs` when the module loads.
- **Bundled for the browser:** `import { init, Renderer } from "bm-engine/standard"` and `await init()`.
  Vite, webpack 5 and Parcel emit the `.wasm` file as an asset (see [Vite and browsers](./vite-browser.md)).
- **Workers / edge runtimes:** import the binary as a module and pass it:
  `import wasm from "bm-engine/core.wasm"; initSync(wasm)` (see [Cloudflare Workers](./cloudflare-workers.md)).
- **Anything else:** load the bytes yourself and call `init()` / `initSync()` (below).

Pick the smallest profile that has what your templates use; `core` is enough for node trees with inline
styles and TTF fonts. See [Profiles and size](../../profiles-and-size.md). Each entry is a **separate
wasm instance**: importing both `bm-engine` and `bm-engine/full` on Node loads the full binary twice, so
choose one entry per application.

### Loading the wasm manually

`init()` accepts bytes, a URL string, `URL`, `Request`, `Response`, a promise of any of these, a
compiled `WebAssembly.Module`, or takumi's `{ module_or_path }` object. `initSync()` accepts bytes or a
`WebAssembly.Module`. A `Response` served as `application/wasm` is compiled with
`WebAssembly.instantiateStreaming`; any other content type goes through `arrayBuffer()`.

```js
import { init, initSync, Renderer } from "bm-engine";

// 1. fetch it (browsers, Deno, workers that allow runtime compilation)
await init(fetch("/assets/bm_engine.wasm"));

// 2. bytes you already have (any runtime that allows WebAssembly compilation from bytes)
initSync(bytes);

// 3. a precompiled module (Cloudflare Workers, Vercel Edge `?module` imports)
initSync(wasmModule);

// takumi's form also works
await init({ module_or_path: "/assets/bm_engine.wasm" });
```

All of these were run under `node --conditions=browser`, which resolves the same files a bundler does.
`init()` is idempotent per entry: the first successful call wins, later calls return the same instance
and ignore their argument. Before initialisation, `new Renderer()` throws
`bm-engine: call init()/initSync() before creating a Renderer`, and `init()` without an argument on the
generic entry rejects with `bm-engine: init() needs the wasm binary: ...`.

## The universal pattern

Every integration on these pages has the same shape:

1. **Create one `Renderer` per process (Node) or per isolate (Workers), lazily.** Registering fonts
   parses them and copies them into wasm memory; doing it per request wastes time and grows memory.
2. **Register fonts once.** bm-engine bundles no font: without a registered font, text is not drawn.
3. **Per request:** read parameters, build a node tree, render, return a `Response` with the bytes and
   a `content-type`.

```js
// og.js — shared by every route
import { readFileSync } from "node:fs";
import { Renderer } from "bm-engine/standard";

let renderer; // one per process / isolate

export function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: readFileSync(new URL("./fonts/Inter-Regular.ttf", import.meta.url)), weight: 400 });
    renderer.registerFont({ name: "Inter", data: readFileSync(new URL("./fonts/Inter-Bold.ttf", import.meta.url)), weight: 700 });
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

`display: "flex"` on the root is not optional: like takumi, every node defaults to `display: inline`
(see [Troubleshooting](../../troubleshooting.md#containers-collapse-to-zero-height)). The per-framework
pages import `getRenderer` and `card` from this file.

::: tip Rendering blocks the thread
A render is synchronous WebAssembly work (a 1200 × 630 card with a gradient took about 14 ms in the
batch recipe on the test machine). `render()` returns a promise for takumi compatibility, but the work
still happens on the calling thread. For CPU-heavy servers, render in a worker pool
(see [Recipes](../recipes.md#worker-threads-pool)).
:::

## An `imageResponse()` helper

bm-engine has no `ImageResponse` class (checked: nothing named `ImageResponse` exists in `js/`). The
helper below gives you the useful part of one. It works anywhere `Response` and `Headers` exist: Node 18+,
Deno, Bun, Workers, browsers and every framework on these pages.

```js
// image-response.js
const CONTENT_TYPES = { png: "image/png", jpeg: "image/jpeg", jpg: "image/jpeg", webp: "image/webp", ico: "image/x-icon" };

/**
 * Renders `source` (node tree, { json } or HTML string) and answers with the encoded image.
 * options: every render option, plus `headers`, `status`, `onError`.
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
```

Usage in any Web-standard handler:

```js
import { getRenderer, card } from "./og.js";
import { imageResponse } from "./image-response.js";

export async function GET(request) {
  const url = new URL(request.url);
  return imageResponse(getRenderer(), card({
    title: url.searchParams.get("title") ?? "Hello",
    description: url.searchParams.get("description") ?? "Rendered with bm-engine",
  }), {
    width: 1200,
    height: 630,
    headers: { "cache-control": "public, max-age=3600" },
  });
}
```

Differences from takumi's / `next/og`'s `ImageResponse`, so nobody is surprised:

- It is a function returning `Promise<Response>`, not a `Response` subclass; await it or return the
  promise (every framework here accepts a promise from a handler).
- The image is rendered **before** the response is created, so a failed render becomes a real `500`
  (there is no streaming body that fails half-way and no `ready` promise to await).
- There is no `emoji` option and nothing is fetched: fonts and images must already be registered or
  passed as `images` (see [Font loading](#font-loading-strategies)).
- The renderer is explicit. takumi's default shared renderer corresponds to `getRenderer()` above.

## Caching headers

A rendered card is a pure function of its inputs, so cache it as hard as your URLs allow:

| Situation | `cache-control` |
|:--|:--|
| URL contains a version or content hash (`/og/post-42.png?v=3`) | `public, max-age=31536000, immutable` |
| Content can change under the same URL | `public, max-age=3600, stale-while-revalidate=86400` (tune to your edit frequency) |
| Behind a CDN that should hold it longer than browsers | `public, max-age=600, s-maxage=86400` |
| Per-user or secret content | `private, no-store` |

An `ETag` computed **from the inputs** (template version + parameters) lets you answer
`If-None-Match` with `304` without rendering at all; the [HTTP recipe](../recipes.md#serve-over-http-with-etag-and-cache-control)
shows it (verified: the second request returned 304 and the renderer was not called). Social-network
crawlers fetch an OG image a handful of times, so the big wins are the CDN cache and building images at
deploy time (see [Astro](./astro.md) and [Recipes](../recipes.md#generate-at-build-time)).

## Font loading strategies

bm-engine never reads system fonts and has no built-in font. Pick the strategy that matches your runtime:

| Strategy | Where | How |
|:--|:--|:--|
| Read from disk at startup | Node.js, Bun, Deno | `readFileSync(new URL("./fonts/Inter-Regular.ttf", import.meta.url))` |
| Bundle as a module | Cloudflare Workers | a wrangler `Data` rule: `import inter from "./Inter-Regular.ttf"` gives an `ArrayBuffer` |
| Fetch once, keep in the renderer | browsers, Deno Deploy, any edge runtime | `renderer.registerFont(await (await fetch(url)).arrayBuffer())`, or `await renderer.registerFont(url)` |
| Per render, async | rarely needed | the `fonts` render option (async API only; registers into the renderer) |

- Register every weight you use (`fontWeight: 700` with only a regular face is synthesised, which looks
  worse than a real bold face). Registering a second file under the same `name` adds a face to that family.
- TTF works on every profile; `.otf` (CFF) and WOFF2 need `standard` / `full`, or the
  [WOFF add-on](../api.md#woff-add-on) on `core`. Subset fonts to the characters you need to save memory
  and startup time.
- Characters missing from a font fall back to every other registered family, in registration order.
  Register the brand font first and broad-coverage fonts after it (see the
  [fallback recipe](../recipes.md#i18n-font-fallback-chain)).
- The [Fonts](../fonts.md) page covers matching, variable fonts and emoji in depth.

## Node trees without JSX

bm-engine takes three kinds of source: a node object, `{ json: string }`, or an HTML string (HTML needs
`standard` / `full`; see [HTML and Tailwind](../html-and-tailwind.md)). A node is plain data:

```js
{ type: "container", style: { display: "flex" }, children: [ /* nodes */ ] }
{ type: "text", text: "Hello", style: { fontSize: 48 } }
{ type: "image", src: "logo", width: 64, height: 64 }   // src: images key, data: URL, bytes or SVG markup
```

Writing those objects by hand is fine for one card. For more, a ten-line hyperscript function keeps
templates readable:

```js
// h.js
export function h(tag, props, ...children) {
  const kids = children.flat(Infinity).filter((c) => c != null && typeof c !== "boolean")
    .map((c) => (typeof c === "object" ? c : { type: "text", text: String(c) }));
  if (typeof tag === "function") return tag({ ...props, children: kids }); // components
  const { children: _, ...meta } = props ?? {};
  if (tag === "img") return { type: "image", tagName: "img", ...meta }; // src, width, height, style
  return { type: "container", tagName: tag, ...meta, children: kids };  // style, tw, className, id, ...
}

export const Fragment = ({ children }) => children;
```

```js
import { h } from "./h.js";

const Title = ({ children }) => h("div", { style: { fontSize: 64, fontWeight: 700 } }, children);

const node = h("div", { style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", padding: 48, fontFamily: "Inter" } },
  h(Title, null, "Hello ", 42),
  user.isPro && h("span", { style: { fontSize: 32 } }, "Pro"),   // false / null are skipped
  h("img", { src: "logo", width: 64, height: 64 }),
);
```

Because `h` has the classic `createElement` signature, it also works as a **JSX factory** without React.
With esbuild (`--jsx-factory=h --jsx-fragment=Fragment`), TypeScript (`"jsx": "react"`,
`"jsxFactory": "h"`, `"jsxFragmentFactory": "Fragment"`) or a `/** @jsx h */` pragma, you can write:

```jsx
import { h, Fragment } from "./h.js";

export const Card = ({ title }) => (
  <div style={{ display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#7c3aed" }}>
    <span style={{ fontFamily: "Inter", fontSize: 48, color: "white" }}>{title}</span>
  </div>
);
```

The esbuild path was verified (esbuild 0.28.2: the compiled component rendered a 400 × 200 PNG). Limits
of this approach, by design:

- It is a static tree builder: no hooks, no context, no React components from libraries.
- `tagName` is recorded for stylesheet selectors (`css` option), but **no user-agent styles are applied
  to node trees**: an `h1` node is not bold, has no margin and is `inline` like every other node
  (verified with `measure()`). Style it explicitly, or use an HTML string, where the HTML parser applies
  UA styles.
- A `Fragment` at the root returns an array, which is not a valid source; wrap it in a container.

If you already have React components, `@takumi-rs/helpers` (takumi's package) converts a React element
to a takumi node tree with its `fromJsx()`; the [migration guide](../migration/from-takumi.md#jsx) has
the details and the verification status.
