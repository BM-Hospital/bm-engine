// Verifies cloudflare-workers.md as far as possible without workerd: runs the Worker module with wrangler's
// module semantics emulated in Node (a `.wasm` import is a WebAssembly.Module, a `.ttf` import under the "Data"
// rule is an ArrayBuffer, `caches.default` is an in-memory stub), resolved with the workerd export condition.
//
//   node --conditions=workerd check-cloudflare.mjs                   runs cloudflare/src/worker.js
//   CF_BUNDLE=<dir>/worker.js node check-cloudflare.mjs              runs a `wrangler deploy --dry-run --outdir <dir>` bundle
import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";
import { check, done, pngSize, FONTS } from "./lib/util.mjs";

registerHooks({
  resolve(specifier, context, next) {
    // the example's fonts are not committed next to worker.js: serve them from the fonts directory
    if (specifier.endsWith(".ttf") && context.parentURL) {
      const url = new URL(specifier, context.parentURL);
      if (!existsSync(fileURLToPath(url))) return { url: new URL(path.basename(specifier), FONTS).href, shortCircuit: true };
    }
    return next(specifier, context);
  },
  load(url, context, next) {
    if (/\.(wasm|ttf)$/.test(url)) {
      let file = fileURLToPath(url);
      if (!existsSync(file) && url.endsWith(".ttf")) file = fileURLToPath(new URL(path.basename(file).replace(/^[0-9a-f]{40}-/, ""), FONTS));
      const bytes = `new Uint8Array(readFileSync(${JSON.stringify(file)}))`;
      const value = url.endsWith(".wasm") ? `new WebAssembly.Module(${bytes})` : `${bytes}.buffer`;
      return { format: "module", shortCircuit: true, source: `import { readFileSync } from "node:fs"; export default ${value};` };
    }
    return next(url, context);
  },
});

const store = new Map();
globalThis.caches = { default: {
  match: async (req) => store.get(req.url)?.clone(),
  put: async (req, res) => { store.set(req.url, res); },
} };
const ctx = { pending: [], waitUntil(p) { this.pending.push(p); } };

const entry = process.env.CF_BUNDLE ? pathToFileURL(path.resolve(process.env.CF_BUNDLE)).href : new URL("./cloudflare/src/worker.js", import.meta.url).href;

await check(`Worker fetch handler (${process.env.CF_BUNDLE ? "wrangler bundle" : "source, --conditions=workerd"})`, async () => {
  if (!process.env.CF_BUNDLE) assert.match(import.meta.resolve("bm-engine/core"), /\/js\/core\.mjs$/, "run with --conditions=workerd");
  const worker = (await import(entry)).default;
  const res = await worker.fetch(new Request("http://localhost/og.png?title=Hi"), {}, ctx);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "image/png");
  assert.deepEqual(pngSize(new Uint8Array(await res.arrayBuffer())), [1200, 630]);
  await Promise.all(ctx.pending);
  const again = await worker.fetch(new Request("http://localhost/og.png?title=Hi"), {}, ctx);
  assert.deepEqual(pngSize(new Uint8Array(await again.arrayBuffer())), [1200, 630]);
  assert.equal(store.size, 1, "second request served from the cache");
  assert.equal((await worker.fetch(new Request("http://localhost/"), {}, ctx)).status, 404);
});
done();
