# Cloudflare Workers

[English](cloudflare-workers.md) · [Tiếng Việt](../../vi/frameworks/cloudflare-workers.md)

Workers have no file system and do not allow compiling WebAssembly from bytes at runtime; instead,
wrangler compiles every imported `.wasm` file ahead of time and hands your code a `WebAssembly.Module`.
bm-engine's `init()` / `initSync()` accept exactly that, so a Worker imports the binary, initialises
once per isolate, bundles its fonts as data, and returns a `Response`.

::: info Verification status
Verified with **wrangler 4.160.1**: `wrangler deploy --dry-run --outdir dist` bundled the Worker below
(the `.wasm` and `.ttf` files were emitted as separate modules). The **bundled output** and the source were
then executed on Node 26.13 with Workers module semantics emulated (`.wasm` import → `WebAssembly.Module`,
`Data` rule → `ArrayBuffer`, an in-memory `caches.default`, `workerd` export condition): both returned
a 1200 × 630 PNG, and the second request was served from the cache
(`docs/examples/frameworks/check-cloudflare.mjs`). **Not run in workerd itself** — `wrangler dev` could not
start on the test machine (the `workerd.exe` binary failed to load), and nothing was deployed.
:::

## The Worker

```js
// src/worker.js
import { initSync, Renderer } from "bm-engine/core";
import wasm from "bm-engine/core.wasm";             // a WebAssembly.Module (wrangler compiles .wasm imports)
import interRegular from "./Inter-Regular.ttf";     // an ArrayBuffer (the "Data" rule in wrangler.toml)
import interBold from "./Inter-Bold.ttf";

initSync(wasm);
let renderer; // one per isolate, reused across requests

function getRenderer() {
  if (!renderer) {
    renderer = new Renderer();
    renderer.registerFont({ name: "Inter", data: interRegular, weight: 400 });
    renderer.registerFont({ name: "Inter", data: interBold, weight: 700 });
  }
  return renderer;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== "/og.png") return new Response("Not found", { status: 404 });

    const cache = caches.default;
    const cached = await cache.match(request);
    if (cached) return cached;

    const title = url.searchParams.get("title") ?? "Hello from Workers";
    const png = getRenderer().renderSync(
      {
        type: "container",
        style: { display: "flex", flexDirection: "column", justifyContent: "center", width: "100%", height: "100%",
          padding: 64, fontFamily: "Inter", backgroundImage: "linear-gradient(to bottom right, #fff7ed, #fecaca)" },
        children: [{ type: "text", text: title, style: { fontSize: 72, fontWeight: 700, color: "#111827" } }],
      },
      { width: 1200, height: 630 },
    );
    const response = new Response(png, {
      headers: { "content-type": "image/png", "cache-control": "public, max-age=86400" },
    });
    ctx.waitUntil(cache.put(request, response.clone()));
    return response;
  },
};
```

```toml
# wrangler.toml
name = "bm-engine-og"
main = "src/worker.js"
compatibility_date = "2025-06-01"

[[rules]]
type = "Data"
globs = ["**/*.ttf"]
fallthrough = true
```

- wrangler resolves `bm-engine/core` with the `workerd` condition to the browser-style entry (no
  `node:fs`), and `bm-engine/core.wasm` to the raw binary. No `nodejs_compat` flag is needed.
- `.wasm` imports are handled by wrangler's default module rules; only the font rule is added.
- Use the same profile for the JS entry and the binary (`bm-engine/core` + `bm-engine/core.wasm`,
  `bm-engine/standard` + `/standard.wasm`, `bm-engine/full` + `/full.wasm`). With the generic
  `bm-engine` entry, pass `bm-engine/wasm` (= full).
- WOFF on `core`: `import woff from "bm-engine/woff.wasm"; import { loadWoff } from "bm-engine/woff"; await loadWoff(woff);`
  (verified with a `WebAssembly.Module` under `--conditions=workerd`).
- `caches.default` stores the response in the data centre's cache; responses must be cacheable
  (`cache-control`). For global caching, put the Worker behind a route with Cache Rules.

## Size limits

Workers limit the compressed size of the uploaded script (all modules together). The limits depend on
your plan and change over time — check Cloudflare's current documentation. What bm-engine contributes:

| Module | raw | gzip -9 |
|:--|--:|--:|
| `bm_engine.core.wasm` | 487.6 KiB | 228.4 KiB |
| `bm_engine.standard.wasm` | 934.4 KiB | 463.7 KiB |
| `bm_engine.wasm` (full) | 1 141.5 KiB | 559.0 KiB |
| JS wrapper (bundled) | ~23 KiB | — |

The dry-run of the Worker above reported **Total Upload: 1290.11 KiB / gzip: 618.63 KiB**, most of it the
two Inter TTFs (about 400 KiB each). Fonts usually cost more than the engine: subset them to the
characters you need, or load them from R2 / KV / a URL at first request instead of bundling (the
`registerFont` call is the same with an `ArrayBuffer` from `fetch`).

## CPU time

Rendering is synchronous CPU work inside the request: a 1200 × 630 card with a gradient took about
14 ms on the test machine (Node; workerd was not measured). The first request in an isolate also pays
for instantiating the module and parsing the fonts. Cache the result (above) so most requests never
render, and check your plan's CPU-time limit.

## What does not work on Workers

- `await init()` without an argument on a profile entry: it tries to fetch the `.wasm` next to the
  module, which does not exist as a URL in a Worker. Pass the imported module.
- Instantiating from bytes (`initSync(bytes)` / `init(arrayBuffer)`): Workers forbid runtime
  compilation; import the `.wasm` instead.
- Reading files with `node:fs`; and anything that fetches remote images implicitly — bm-engine never
  fetches; `fetch()` them yourself and pass `images` (see the [remote images recipe](../recipes.md#embed-remote-images)).
