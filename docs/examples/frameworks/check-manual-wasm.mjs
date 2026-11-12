// Verifies the manual wasm-loading paths of frameworks/index.md, vite-browser.md and cloudflare-workers.md.
// Run with  node --conditions=browser check-manual-wasm.mjs  so the package resolves to its browser entries
// (no auto-initialisation from node:fs, exactly what a bundler / browser / worker gets).
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { check, done, pngSize, font } from "./lib/util.mjs";

const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "#7c3aed", alignItems: "center", justifyContent: "center" },
  children: [{ type: "text", text: "wasm", style: { fontFamily: "Inter", fontSize: 32, color: "white" } }] };
const wasmPath = (spec) => fileURLToPath(import.meta.resolve(spec));

await check("resolution: --conditions=browser gives the browser entries", () => {
  assert.match(import.meta.resolve("bm-engine"), /\/js\/index\.mjs$/);
  assert.match(import.meta.resolve("bm-engine/core"), /\/js\/core\.mjs$/);
  assert.match(import.meta.resolve("bm-engine/wasm"), /\/js\/bm_engine\.wasm$/);
  assert.match(import.meta.resolve("bm-engine/core.wasm"), /\/js\/bm_engine\.core\.wasm$/);
});

// A static server for the wasm files, once with application/wasm (streaming compile), once without.
const server = createServer((req, res) => {
  const file = req.url.startsWith("/full.wasm") ? wasmPath("bm-engine/full.wasm") : null;
  if (!file) return res.writeHead(404).end();
  res.writeHead(200, { "content-type": req.url.includes("plain") ? "application/octet-stream" : "application/wasm" });
  res.end(readFileSync(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}`;

await check("bm-engine (neutral entry): init() without argument rejects with a clear message", async () => {
  const { init, Renderer } = await import("bm-engine");
  assert.throws(() => new Renderer(), /call init\(\)\/initSync\(\) before creating a Renderer/);
  await assert.rejects(init(), /init\(\) needs the wasm binary/);
});

await check("bm-engine: await init(fetch(url)) with application/wasm (instantiateStreaming path)", async () => {
  const { init, Renderer, features } = await import("bm-engine");
  let streamed = false;
  const orig = WebAssembly.instantiateStreaming;
  WebAssembly.instantiateStreaming = (...a) => { streamed = true; return orig(...a); };
  try { await init(fetch(`${base}/full.wasm`)); } finally { WebAssembly.instantiateStreaming = orig; }
  assert.ok(streamed, "instantiateStreaming was used");
  assert.equal(features.renderSvg, true);
  const r = new Renderer();
  r.registerFont({ name: "Inter", data: font("Inter-Regular.ttf") });
  assert.deepEqual(pngSize(r.renderSync(node, { width: 200, height: 100 })), [200, 100]);
});

await check("bm-engine/full: initSync(bytes)", async () => {
  const full = await import("bm-engine/full");
  full.initSync(readFileSync(wasmPath("bm-engine/full.wasm")));
  assert.equal(full.profile, "full");
  assert.equal(full.features.animation, true);
});

await check("bm-engine/core: await init(WebAssembly.Module) (what a Workers .wasm import gives)", async () => {
  const core = await import("bm-engine/core");
  const module = await WebAssembly.compile(readFileSync(wasmPath("bm-engine/core.wasm")));
  await core.init(module);
  assert.equal(core.features.css, false);
  const r = new core.Renderer();
  r.registerFont({ name: "Inter", data: font("Inter-Regular.ttf") });
  assert.deepEqual(pngSize(r.renderSync(node, { width: 120, height: 60 })), [120, 60]);
});

await check("bm-engine/standard: await init() finds its own wasm (new URL(..., import.meta.url))", async () => {
  const s = await import("bm-engine/standard");
  assert.match(String(s.wasmUrl()), /bm_engine\.standard\.wasm$/);
  await s.init();
  assert.equal(s.features.css, true);
  assert.equal(s.features.complexText, false);
});

await check("takumi-style init({ module_or_path }) and a non-wasm content type also work", async () => {
  // a fresh copy of the neutral entry would be needed for a second init; use a query string to get a new module instance
  const m = await import(import.meta.resolve("bm-engine") + "?fresh");
  await m.init({ module_or_path: fetch(`${base}/full.wasm?plain`) });
  assert.equal(m.features.html, true);
});

await check("bm-engine/woff: loadWoff(WebAssembly.Module)", async () => {
  const { loadWoff } = await import("bm-engine/woff");
  const r = await loadWoff(await WebAssembly.compile(readFileSync(wasmPath("bm-engine/woff.wasm"))));
  assert.equal(typeof r.builtIn, "boolean");
});

server.close();
done();
