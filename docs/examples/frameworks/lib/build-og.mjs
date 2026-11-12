// Build-time generation (recipes.md, astro.md): render one PNG per post into a folder, skipping files whose
// inputs did not change. Run as a script (`node build-og.mjs out/og`) or import buildOgImages().
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { getRenderer, card } from "./og.mjs";

const TEMPLATE_VERSION = "card-v1"; // bump when the template or the fonts change

export async function buildOgImages(posts, outDir) {
  await mkdir(outDir, { recursive: true });
  const manifestPath = path.join(outDir, "manifest.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8").catch(() => "{}"));
  const renderer = getRenderer(); // one renderer, fonts registered once, for every image
  let rendered = 0;
  for (const post of posts) {
    const key = createHash("sha256").update(TEMPLATE_VERSION + JSON.stringify(post)).digest("hex").slice(0, 16);
    const file = path.join(outDir, `${post.slug}.png`);
    if (manifest[post.slug] === key) continue; // unchanged since the last build
    const png = renderer.renderSync(card(post), { width: 1200, height: 630 });
    await writeFile(file, png);
    manifest[post.slug] = key;
    rendered++;
  }
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2));
  return { rendered, skipped: posts.length - rendered };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const posts = [
    { slug: "hello-world", title: "Hello, world", description: "The first post" },
    { slug: "second-post", title: "A second post", description: "Rendered at build time" },
  ];
  console.log(await buildOgImages(posts, process.argv[2] ?? "public/og"));
}
