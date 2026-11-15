# Native and WebAssembly

Choose the backend for your runtime. On Node.js, the package prefers the native addon and falls back to WebAssembly when the addon is unavailable. See [Benchmark](benchmark.md) for timing and memory measurements.

## Which backend to use

| Where your code runs | Backend | How |
|:--|:--|:--|
| Node.js, Bun, Deno (servers, CLIs, build scripts) | **native**, with an automatic fallback to wasm | `import { Renderer, backend } from "bm-engine"`; `backend` is `"native"` or `"wasm"` |
| Browsers, Web Workers | wasm (the only option) | `bm-engine` resolves to the wasm build there |
| Cloudflare Workers, Vercel / Netlify Edge, Deno Deploy and other edge runtimes | wasm (the only option) | same import |
| Node.js, but you want wasm anyway (for example to reproduce a browser render bit for bit, or on a host whose addon has not been tested yet) | wasm | `import ... from "bm-engine/full"` or `BM_ENGINE_BACKEND=wasm` |
| Node.js, Bun, Deno, and you want PDF output | **native**, with an automatic fallback to the wasm `pdf` profile | `import { PdfRenderer, backend } from "bm-engine/pdf"`; see [PDF output](./pdf/native-and-wasm.md#native-backend-on-nodejs) |
| Node.js, and you want an error rather than a silent fallback | native | `import ... from "bm-engine/native"` or `BM_ENGINE_BACKEND=native` |

The fallback is silent: if no addon is installed for the platform, if the CPU is older than x86-64-v2
(SSE4.2), or if the addon fails its load-time floating-point check, `bm-engine` loads the wasm build and
everything keeps working, only slower and with async calls on the main thread. Log `backend` once at startup
if you need to know.

`bm-engine/pdf` follows the same rules: on Node.js it uses the addon when it is installed and otherwise the wasm
`pdf` profile, produces identical PDF bytes on both, and runs its async methods on the libuv thread pool when native.
`bm-engine` itself exposes no PDF on either backend, although the addon binary contains the PDF writer.


## Threading model

What runs where with the native backend:

- `renderSync`, `measureSync`, `renderSvgSync`, `renderAnimationSync`, `registerFont`: on the calling thread.
  They block the event loop for the duration of the call, exactly like the wasm build.
- `render`, `renderAsDataUrl`, `renderSvg`, `measure`, `renderAnimation`: the inputs are copied, then the
  engine runs on a **libuv thread-pool thread** and the promise settles on the JavaScript thread. The event
  loop keeps serving requests while a render is in progress.
- **One renderer handles one call at a time.** Calls on the same `Renderer` are queued in order
  (first in, first out). To render in parallel, create several renderers (each with its fonts registered) and
  spread the work over them:

```js
import { Renderer } from "bm-engine";

const fonts = [/* { name, data, weight, style } ... */];
const renderers = Array.from({ length: 4 }, () => {
  const r = new Renderer();
  for (const f of fonts) r.registerFont(f);
  return r;
});
let next = 0;
export function renderPng(node, options) {
  const r = renderers[next++ % renderers.length]; // round robin
  return r.render(node, options); // runs on the libuv pool, does not block the event loop
}
```

- **Parallelism is capped by the libuv pool**, `UV_THREADPOOL_SIZE`, **4 by default**. The same pool also
  serves `fs`, `dns.lookup`, `crypto` and `zlib`. To render on more threads, set it in the environment before
  Node starts, e.g. `UV_THREADPOOL_SIZE=8 node server.js` (setting `process.env.UV_THREADPOOL_SIZE` inside the
  program only works if nothing has used the pool yet). More renderers than pool threads do not help.
- Different renderers share no state (each owns its fonts, caches and memory), so they never wait for each
  other. The addon can be loaded in
  `worker_threads` too, but on the native backend a pool of renderers in one thread does the same job without
  workers.
- With the **wasm** backend, async methods run on the main thread; parallelism needs a `worker_threads`
  pool with one engine instance per worker ([recipe](./image/recipes.md#worker-threads-pool)).
