# Deno and Bun

[English](deno-bun.md) · [Tiếng Việt](../../vi/frameworks/deno-bun.md)

Deno and Bun both run npm packages and both resolve the `node` export condition, so `bm-engine` and its
profile entries load the binary with `node:fs` and initialise on import, exactly as on Node.js. Their
built-in HTTP servers take a `Request → Response` function, which is the
[universal pattern](./index.md#the-universal-pattern) with no framework at all.

::: warning Verification status
**Not run on Deno or Bun** — neither runtime is installed on the test machine. What was verified: the
`handler` function below, executed on Node 26.13 with real `Request` objects, returned a 1200 × 630 PNG and
a 404 for other paths (`docs/examples/frameworks/check-frameworks.mjs`); the manual-loading variants were
verified under `node --conditions=browser`. Everything specific to Deno or Bun on this page (permissions,
`npm:` specifiers, condition handling) is expected behaviour, not tested.
:::

## The shared handler

```js
// handler.js
import { getRenderer, card } from "./og.js";          // the overview's og.js
import { imageResponse } from "./image-response.js";  // the overview's helper

export async function handler(request) {
  const url = new URL(request.url);
  if (url.pathname !== "/og.png") return new Response("Not found", { status: 404 });
  return imageResponse(getRenderer(), card({
    title: url.searchParams.get("title") ?? "Hello",
    description: "Deno.serve / Bun.serve",
  }), { width: 1200, height: 630, headers: { "cache-control": "public, max-age=3600" } });
}
```

## Bun

```js
// server.js — bun run server.js
import { handler } from "./handler.js";

Bun.serve({ port: 3000, fetch: handler });
```

`bun add bm-engine` installs it; `import { Renderer } from "bm-engine/standard"` in `og.js` resolves to
the Node entry. Reading fonts with `readFileSync(new URL("./fonts/Inter-Regular.ttf", import.meta.url))`
works in Bun as in Node. Single-file executables (`bun build --compile`) were not tested: the Node entry
reads its `.wasm` from disk next to `node_modules/bm-engine/js/`, so that file has to exist at runtime
(or point `BM_WASM` at a copy, for the `bm-engine` entry).

## Deno

```js
// server.js — deno run --allow-read --allow-net server.js
import { handler } from "./handler.js";

Deno.serve({ port: 3000 }, handler);
```

Import with the `npm:` specifier (`import { Renderer } from "npm:bm-engine/standard"`) or map `bm-engine`
in `deno.json` (`"imports": { "bm-engine": "npm:bm-engine" }` — subpaths then need their own mapping or the
`npm:` prefix). `--allow-read` is needed because the Node entry reads its `.wasm` (and your fonts) from
disk.

### Deno Deploy and other environments without file access

Because Deno and Bun resolve the `node` condition, every `bm-engine` specifier imported from npm points
at a Node entry that reads its binary with `node:fs` **on import**. The package has no export that gives
the uninitialised, browser-style entry under the `node` condition, so where file reads are not possible
you have to bypass npm resolution and import the browser files by URL, then load the binary yourself:

```js
// the same files the package ships in js/, served from your own origin or a CDN
import { init, Renderer } from "https://cdn.example.com/bm-engine/js/standard.mjs";

await init(); // fetches bm_engine.standard.wasm next to standard.mjs
// or: await init(fetch("https://cdn.example.com/bm-engine/js/bm_engine.standard.wasm"));
// or: initSync(bytes);
```

`init(fetch(url))`, `init()` on a profile entry and `initSync(bytes)` are verified under
`node --conditions=browser` (the same files); importing them by URL in Deno is not tested. The browser
files have no dependencies (`standard.mjs` imports only `./engine.mjs`), so vendoring the `js/` folder
also works.

## Choosing an entry

| Goal | Import |
|:--|:--|
| Auto-initialised, read from `node_modules` | `bm-engine/core`, `/standard`, `/full` (or `bm-engine` = full) |
| Explicit control over the binary | the browser files by URL + `init(...)` / `initSync(...)`, or `BM_WASM=/path/file.wasm` with the Node `bm-engine` entry |
| Several profiles side by side | each profile entry has its own wasm instance |
