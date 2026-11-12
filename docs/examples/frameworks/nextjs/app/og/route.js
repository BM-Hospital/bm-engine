import { getRenderer, card } from "../../lib/og.js";

export const runtime = "nodejs";

export async function GET(request) {
  const { searchParams } = new URL(request.url);
  const png = await getRenderer().render(
    card({ title: searchParams.get("title") ?? "bm-engine + Next.js", description: searchParams.get("description") ?? "Rendered in a route handler" }),
    { width: 1200, height: 630 },
  );
  return new Response(png, { headers: { "content-type": "image/png", "cache-control": "public, max-age=3600" } });
}
