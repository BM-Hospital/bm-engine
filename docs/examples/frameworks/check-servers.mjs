// Verifies frameworks/hono-express.md, frameworks/nuxt-nitro.md (h3) and the HTTP recipe in recipes.md:
// every server is started on a random localhost port and fetched. Third-party frameworks are optional:
// a missing package prints SKIPPED.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { getRenderer, card } from "./lib/og.mjs";
import { imageResponse } from "./lib/image-response.mjs";
import { check, done, pngSize } from "./lib/util.mjs";

const optional = async (name) => { try { return await import(name); } catch { return null; } };
const version = async (name) => { try { const { findPackageJSON } = await import("node:module"); const { readFileSync } = await import("node:fs"); return JSON.parse(readFileSync(findPackageJSON(name, import.meta.url), "utf8")).version; } catch { return "?"; } };

async function fetchPng(base, path = "/og.png?title=Hello") {
  const res = await fetch(base + path);
  assert.equal(res.status, 200, `status ${res.status}`);
  assert.equal(res.headers.get("content-type"), "image/png");
  const [w, h] = pngSize(new Uint8Array(await res.arrayBuffer()));
  assert.deepEqual([w, h], [1200, 630]);
  return res;
}
const listen = (server) => new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(`http://127.0.0.1:${server.address().port}`)));

// ---------------------------------------------------------------- node:http with ETag / 304 (recipes.md)
const TEMPLATE_VERSION = "card-v1"; // bump when the template or fonts change

/** ETag from the inputs, so a 304 can be answered without rendering. */
async function etagFor(params) {
  const data = new TextEncoder().encode(TEMPLATE_VERSION + "\0" + JSON.stringify(params));
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return `"${[...hash.subarray(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("")}"`;
}

let renders = 0;
const httpServer = createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname !== "/og.png") return res.writeHead(404).end();
  const params = { title: url.searchParams.get("title") ?? "Hello", description: url.searchParams.get("description") ?? "Rendered with bm-engine" };
  const etag = await etagFor(params);
  const headers = { etag, "cache-control": "public, max-age=3600, stale-while-revalidate=86400" };
  if (req.headers["if-none-match"] === etag) return res.writeHead(304, headers).end();
  try {
    renders++;
    const png = await getRenderer().render(card(params), { width: 1200, height: 630 });
    res.writeHead(200, { ...headers, "content-type": "image/png", "content-length": png.byteLength });
    res.end(png);
  } catch (error) {
    console.error(error);
    res.writeHead(500, { "content-type": "text/plain" }).end("Failed to generate image");
  }
});

await check("node:http server: PNG, ETag, 304 without rendering", async () => {
  const base = await listen(httpServer);
  try {
    const first = await fetchPng(base);
    const etag = first.headers.get("etag");
    assert.match(etag, /^"[0-9a-f]{24}"$/);
    const again = await fetch(base + "/og.png?title=Hello", { headers: { "if-none-match": etag } });
    assert.equal(again.status, 304);
    assert.equal(renders, 1, "304 must not render");
    const other = await fetch(base + "/og.png?title=Other", { headers: { "if-none-match": etag } });
    assert.equal(other.status, 200);
    await other.arrayBuffer();
    assert.equal((await fetch(base + "/nope")).status, 404);
  } finally { httpServer.close(); }
});

// ---------------------------------------------------------------- Hono (+ @hono/node-server)
await check("Hono route returning imageResponse()", async () => {
  const hono = await optional("hono");
  const nodeServer = await optional("@hono/node-server");
  if (!hono || !nodeServer) return "SKIPPED: hono / @hono/node-server not installed";
  const { Hono } = hono;
  const app = new Hono();
  app.get("/og.png", (c) =>
    imageResponse(getRenderer(), card({ title: c.req.query("title") ?? "Hello", description: "From Hono" }), {
      width: 1200, height: 630, headers: { "cache-control": "public, max-age=3600" },
    }));
  // 1. without a server: app.fetch is a plain Request -> Response function (what Workers / Bun / Deno call)
  const direct = await app.fetch(new Request("http://localhost/og.png?title=Direct"));
  assert.deepEqual(pngSize(new Uint8Array(await direct.arrayBuffer())), [1200, 630]);
  // 2. on Node through @hono/node-server
  const server = await new Promise((resolve) => { const s = nodeServer.serve({ fetch: app.fetch, port: 0, hostname: "127.0.0.1" }, () => resolve(s)); });
  try {
    const res = await fetchPng(`http://127.0.0.1:${server.address().port}`);
    assert.equal(res.headers.get("cache-control"), "public, max-age=3600");
  } finally { server.close(); }
  return `hono ${await version("hono")}, @hono/node-server ${await version("@hono/node-server")}`;
});

// ---------------------------------------------------------------- Express
await check("Express route sending a Buffer view of the bytes", async () => {
  const ex = await optional("express");
  if (!ex) return "SKIPPED: express not installed";
  const express = ex.default;
  const app = express();
  app.get("/og.png", async (req, res, next) => {
    try {
      const png = await getRenderer().render(card({ title: String(req.query.title ?? "Hello"), description: "From Express" }), { width: 1200, height: 630 });
      res.type("png").set("cache-control", "public, max-age=3600");
      res.send(Buffer.from(png.buffer, png.byteOffset, png.byteLength)); // a Buffer, not the bare Uint8Array
    } catch (error) { next(error); }
  });
  // what happens with the bare Uint8Array (documented pitfall)
  app.get("/bare.png", async (req, res) => {
    const png = await getRenderer().render(card({ title: "x", description: "y" }), { width: 1200, height: 630 });
    res.type("png").send(png);
  });
  const server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await fetchPng(base);
    const bare = await fetch(base + "/bare.png");
    const bareBytes = new Uint8Array(await bare.arrayBuffer());
    const bareIsPng = bareBytes[0] === 137 && bareBytes[1] === 80;
    return `express ${await version("express")}; bare Uint8Array -> ${bareIsPng ? "PNG (ok)" : `NOT a PNG (content-type ${bare.headers.get("content-type")}, starts ${JSON.stringify(new TextDecoder().decode(bareBytes.subarray(0, 12)))})`}`;
  } finally { server.close(); }
});

// ---------------------------------------------------------------- h3 (the router of Nitro / Nuxt server routes)
await check("h3 event handler returning a Response", async () => {
  const h3 = await optional("h3");
  if (!h3) return "SKIPPED: h3 not installed";
  const { H3, defineEventHandler, getQuery } = h3;
  const handler = defineEventHandler((event) => {
    const { title = "Hello" } = getQuery(event);
    return imageResponse(getRenderer(), card({ title: String(title), description: "From h3" }), { width: 1200, height: 630 });
  });
  const app = new H3().get("/og.png", handler);
  const res = await app.fetch(new Request("http://localhost/og.png?title=Nitro"));
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "image/png");
  assert.deepEqual(pngSize(new Uint8Array(await res.arrayBuffer())), [1200, 630]);
  return `h3 ${await version("h3")} (app.fetch; not inside Nitro / Nuxt)`;
});

done();
