import { getRenderer, card } from "../lib/og.js";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "bm-render + Next.js";

export default async function Image() {
  const png = await getRenderer().render(card({ title: "bm-render + Next.js", description: "opengraph-image file convention" }), size);
  return new Response(png, { headers: { "content-type": "image/png" } });
}
