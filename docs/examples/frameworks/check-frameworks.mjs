// Verifies the handler code of the framework pages as plain Web-standard functions on Node (the framework
// itself is NOT loaded: each handler is called with the argument shape the framework passes).
import assert from "node:assert/strict";
import { getRenderer, card } from "./lib/og.mjs";
import { imageResponse } from "./lib/image-response.mjs";
import { check, done, pngSize } from "./lib/util.mjs";

async function expectPng(res, size = [1200, 630]) {
  assert.ok(res instanceof Response, "a Response");
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "image/png");
  assert.deepEqual(pngSize(new Uint8Array(await res.arrayBuffer())), size);
}

// ---------------------------------------------------------------- Next.js (nextjs.md)
// app/og/route.js
export const runtime = "nodejs";
async function nextGET(request) {
  const { searchParams } = new URL(request.url);
  return imageResponse(
    getRenderer(),
    card({ title: searchParams.get("title") ?? "bm-render + Next.js", description: searchParams.get("description") ?? "Rendered in a route handler" }),
    { width: 1200, height: 630, headers: { "cache-control": "public, max-age=3600, s-maxage=86400" } },
  );
}
// app/opengraph-image.js
const size = { width: 1200, height: 630 };
async function OpenGraphImage() {
  const png = await getRenderer().render(card({ title: "bm-render + Next.js", description: "opengraph-image convention" }), size);
  return new Response(png, { headers: { "content-type": "image/png" } });
}
await check("Next.js route handler GET(request)", async () => { await expectPng(await nextGET(new Request("http://localhost/og?title=Hello"))); });
await check("Next.js opengraph-image default export", async () => { await expectPng(await OpenGraphImage()); });

// ---------------------------------------------------------------- SvelteKit (sveltekit.md): src/routes/og.png/+server.js
async function svelteGET({ url }) {
  return imageResponse(getRenderer(), card({ title: url.searchParams.get("title") ?? "bm-render + SvelteKit", description: "A +server.js endpoint" }), { width: 1200, height: 630 });
}
await check("SvelteKit +server GET({ url })", async () => {
  const request = new Request("http://localhost/og.png?title=Svelte");
  await expectPng(await svelteGET({ url: new URL(request.url), request }));
});

// ---------------------------------------------------------------- Astro (astro.md): src/pages/og/[slug].png.js
const posts = [{ slug: "hello", title: "Hello", description: "First post" }, { slug: "second", title: "Second", description: "Another post" }];
function getStaticPaths() {
  return posts.map((post) => ({ params: { slug: post.slug }, props: { post } }));
}
async function astroGET({ props }) {
  const png = await getRenderer().render(card(props.post), { width: 1200, height: 630 });
  return new Response(png, { headers: { "content-type": "image/png" } });
}
await check("Astro endpoint with getStaticPaths (static build shape)", async () => {
  const paths = getStaticPaths();
  assert.equal(paths.length, 2);
  for (const p of paths) await expectPng(await astroGET({ params: p.params, props: p.props }));
});

// ---------------------------------------------------------------- TanStack Start (tanstack-start.md)
const routeOptions = {
  server: {
    handlers: {
      GET: ({ request }) => {
        const url = new URL(request.url);
        return imageResponse(getRenderer(), card({ title: url.searchParams.get("title") ?? "bm-render + TanStack Start", description: "A server route" }), { width: 1200, height: 630 });
      },
    },
  },
};
await check("TanStack Start server.handlers.GET({ request })", async () => {
  await expectPng(await routeOptions.server.handlers.GET({ request: new Request("http://localhost/og-image?title=T") }));
});

// ---------------------------------------------------------------- Deno / Bun (deno-bun.md): a fetch handler
async function handler(request) {
  const url = new URL(request.url);
  if (url.pathname !== "/og.png") return new Response("Not found", { status: 404 });
  return imageResponse(getRenderer(), card({ title: url.searchParams.get("title") ?? "Hello", description: "Deno.serve / Bun.serve" }), { width: 1200, height: 630 });
}
await check("fetch handler for Deno.serve / Bun.serve (called directly on Node)", async () => {
  await expectPng(await handler(new Request("http://localhost/og.png")));
  assert.equal((await handler(new Request("http://localhost/x"))).status, 404);
});

done();
