# Next.js

[English](nextjs.md) · [Tiếng Việt](../../../vi/image/frameworks/nextjs.md)

Serve Open Graph images from a Next.js App Router route handler, or let Next.js discover them through the
`opengraph-image` file convention. bm-engine replaces `next/og`'s `ImageResponse` with a renderer you own
and a plain `Response`; the image is a node tree (or HTML), not JSX — see
[Node trees without JSX](./index.md#node-trees-without-jsx) for a small `h()` helper.

::: info Verification status
Verified with **Next.js 16.4.6 on Windows x64, Node 26.13**, bm-engine and its `bm-engine-win32-x64-msvc`
platform package installed from packed tarballs: `next build` with Turbopack (the default) and with
`--webpack`, then `next start`, and for `output: "standalone"` the `.next/standalone` folder copied to a
directory outside the project and started with `node server.js`, so that nothing could be resolved from
the build machine's `node_modules`. Routes: a Node.js route handler on `bm-engine`, one on
`bm-engine/full`, and an Edge route; each returned a PNG. The results are in the tables below. Not tested:
Vercel deployments, Linux / macOS hosts, pnpm / Yarn layouts, other Next.js versions. The Edge runtime
could not be tested with the webpack builder: in Next.js 16.4.6, `next build --webpack` failed for *any*
Edge route on this machine, including one without bm-engine (`ENOENT ... route_client-reference-manifest.js`).
The example app is in [`docs/examples/frameworks/nextjs/`](../../../examples/frameworks/nextjs/).
:::

## 1. Install and configure

```sh
npm install bm-engine
```

```js
// next.config.mjs
/** @type {import("next").NextConfig} */
export default {
  // Keep bm-engine out of the server bundle: Node loads it from node_modules, and Next.js copies its files
  // into standalone / Vercel output.
  serverExternalPackages: ["bm-engine"],
  // Copy the native platform package too (Turbopack's file tracing does not follow it, see below).
  outputFileTracingIncludes: { "/*": ["./node_modules/bm-engine-*/**"] },
};
```

Neither option is needed for `next dev` / `next start` on the machine that built the app: both builders
then work without configuration, natively. They matter for self-contained output (`output: "standalone"`,
Vercel and other hosts that copy only the traced files):

| Builder | `next.config` | `next start` | standalone output, run elsewhere |
|:--|:--|:--|:--|
| Turbopack | nothing | native | **wasm** (platform package not copied) |
| Turbopack | `serverExternalPackages` | native | **wasm** (platform package not copied) |
| Turbopack | `serverExternalPackages` + `outputFileTracingIncludes` | native | **native** |
| Turbopack | `outputFileTracingIncludes` only | native | native |
| webpack (`--webpack`) | nothing | native | **fails**: `bm-engine: cannot find bm_engine.wasm (...)` (HTTP 500) |
| webpack (`--webpack`) | `serverExternalPackages` | native | **native** (the platform package is traced) |

"wasm" is the automatic fallback: correct output, slower, and the async methods block the event loop. Log
or return `backend` (exported by `bm-engine`) once to see what runs in production.

How the package behaves when Next.js bundles it: the Node entry finds its `.wasm` file next to itself (or
the asset Turbopack emits), then through package resolution, then in `<cwd>/node_modules/bm-engine/js/`;
if all fail, the error names `serverExternalPackages`. The platform package is required at run time with
a literal name per platform marked `turbopackIgnore` / `webpackIgnore`, so builds never fail on the
platform packages that are not installed; the price is that Turbopack's file tracing skips it, hence
`outputFileTracingIncludes`. With pnpm the packages live under `node_modules/.pnpm/`: adapt the glob (for
example `"./node_modules/.pnpm/bm-engine-*/**"`); not tested.

### Native addon in deployments

The platform package is chosen when dependencies are installed, on the machine that runs the install:
Vercel builds on Linux x64 and gets `bm-engine-linux-x64-gnu`, which is built and structurally verified
but has **never been executed** (only `win32-x64-msvc` has, see
[Install](../../getting-started.md#native-on-nodejs-webassembly-everywhere-else)). If it does not load there,
the route still works on wasm. A `node_modules` built on your Mac or Windows machine and uploaded to a
Linux server carries the wrong binary (wasm at run time).

## 2. Shared renderer and template

Put the renderer in a module so it is created once per server process. Next.js runs route handlers with
the project root as the working directory, so `process.cwd()` is a reliable base for font files kept in
the repository:

```js
// lib/og.js
import { readFileSync } from "node:fs";
import path from "node:path";
import { Renderer, backend } from "bm-engine";

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

export { backend }; // "native" | "wasm"

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

`bm-engine` on Node is the native addon or the `full` wasm binary. To pin a smaller wasm profile instead,
import `bm-engine/standard` or `bm-engine/core` (always wasm). One renderer renders one image at a time; on
the native backend, a few renderers (with the same fonts) render in parallel on the thread pool.

## 3. A route handler

```js
// app/og/route.js
import { getRenderer, card, backend } from "../../lib/og.js";

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
    headers: { "content-type": "image/png", "cache-control": "public, max-age=3600", "x-bm-backend": backend },
  });
}
```

Visit `/og?title=Hello`. To control the error response (a short text `500` plus an `onError` hook), use the
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

Without dynamic inputs Next.js prerenders this at build time. For per-page images in a dynamic segment,
the default export receives `{ params }` (a promise in recent Next.js versions). Set `metadataBase` in your
root layout so the generated URLs are absolute; the build warns otherwise. (The file convention was
verified in an earlier round with Next.js 16.4.6; this round re-ran the route handlers.)

## Edge runtime

There is no `node:fs` and no native code on the Edge runtime. Import a wasm binary as a
`WebAssembly.Module` with Next.js's `?module` suffix and pass it to `initSync` of the matching profile
entry:

```js
// app/og-edge/route.js
import { initSync, Renderer } from "bm-engine/core";
import wasm from "bm-engine/core.wasm?module";

export const runtime = "edge";

let renderer;
async function getRenderer() {
  if (!renderer) {
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

With Turbopack this built and returned a 1200 × 630 PNG under `next start` and from the isolated
standalone output. Why it works: Turbopack looks the specifier up in the package's `exports` **including
the query**, so bm-engine declares `"./core.wasm?module"` (and the same for `standard`, `full`, `wasm`,
`woff`) pointing at the file with the query kept. Before that entry existed the import failed with
`Module not found: Can't resolve 'bm-engine/core.wasm'`, and a key without the query in its target gave
`Export default doesn't exist in target module`. webpack strips the query before resolving, so the same
import is expected to work with `--webpack`, but that could not be tested (see the box at the top). The
`Object.setPrototypeOf` workaround older versions of this page needed is gone: `initSync` accepts the
module Next.js passes.

Size matters on Edge: the `core` binary is 487.6 KiB raw (about 210 KiB gzip) and fonts add their own
size; see [Profiles and size](../../profiles-and-size.md). The Edge runtime is deprecated in Next.js 16 (the
build prints a warning) and has no native addon: prefer the Node.js runtime.

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
