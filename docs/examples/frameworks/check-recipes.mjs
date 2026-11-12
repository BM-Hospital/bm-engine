// Verifies recipes.md: write to file, batch, worker_threads pool, build-time script, retina, fit text with
// measure(), remote images, error handling / timeouts, font fallback chain.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { writeFileSync, readFileSync, mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir, availableParallelism } from "node:os";
import path from "node:path";
import { Renderer } from "bm-engine";
import { getRenderer, card } from "./lib/og.mjs";
import { createPool } from "./lib/pool.mjs";
import { buildOgImages } from "./lib/build-og.mjs";
import { check, done, pngSize, font } from "./lib/util.mjs";

const tmp = mkdtempSync(path.join(tmpdir(), "bm-recipes-"));
const posts = Array.from({ length: 48 }, (_, i) => ({ slug: `post-${i}`, title: `Post number ${i}: a title long enough to wrap`, description: `Description ${i}` }));

await check("write a PNG to disk", () => {
  const png = getRenderer().renderSync(card({ title: "Hello", description: "World" }), { width: 1200, height: 630 });
  const file = path.join(tmp, "og.png");
  writeFileSync(file, png);
  assert.deepEqual(pngSize(readFileSync(file)), [1200, 630]);
});

let serialMs;
await check("batch: one renderer for many cards", () => {
  const r = getRenderer();
  r.renderSync(card(posts[0]), { width: 1200, height: 630 }); // warm-up
  const t0 = performance.now();
  const out = posts.map((p) => r.renderSync(card(p), { width: 1200, height: 630 }));
  serialMs = performance.now() - t0;
  out.forEach((b) => assert.deepEqual(pngSize(b), [1200, 630]));
  return `${posts.length} cards in ${serialMs.toFixed(0)} ms (${(serialMs / posts.length).toFixed(1)} ms each), wasm memory ${(r.memoryBytes() / 2 ** 20).toFixed(1)} MiB`;
});

await check("worker_threads pool", async () => {
  const size = Math.min(4, Math.max(2, availableParallelism() - 1));
  const pool = createPool(size);
  try {
    await Promise.all(Array.from({ length: size * 2 }, (_, i) => pool.render(posts[i], { width: 1200, height: 630 }))); // warm-up: each worker loads wasm + fonts
    const t0 = performance.now();
    const out = await Promise.all(posts.map((p) => pool.render(p, { width: 1200, height: 630 })));
    const ms = performance.now() - t0;
    out.forEach((b) => assert.deepEqual(pngSize(b), [1200, 630]));
    // bytes identical to the main-thread renderer
    assert.deepEqual(out[3], getRenderer().renderSync(card(posts[3]), { width: 1200, height: 630 }));
    await assert.rejects(pool.render({ title: "x", description: "y" }, { width: 0, height: 10 }));
    return `${size} workers: ${posts.length} cards in ${ms.toFixed(0)} ms (serial ${serialMs.toFixed(0)} ms, ${(serialMs / ms).toFixed(1)}x)`;
  } finally { await pool.close(); }
});

await check("build-time script: renders, then skips unchanged posts", async () => {
  const out = path.join(tmp, "og");
  const few = posts.slice(0, 5);
  assert.deepEqual(await buildOgImages(few, out), { rendered: 5, skipped: 0 });
  assert.deepEqual(await buildOgImages(few, out), { rendered: 0, skipped: 5 });
  assert.deepEqual(await buildOgImages([{ ...few[0], title: "changed" }, ...few.slice(1)], out), { rendered: 1, skipped: 4 });
  assert.ok(existsSync(path.join(out, "post-0.png")));
});

await check("retina: width/height x2 plus devicePixelRatio 2", () => {
  const r = getRenderer();
  const node = card({ title: "Retina", description: "2x" });
  const one = r.renderSync(node, { width: 600, height: 315 });
  const two = r.renderSync(node, { width: 1200, height: 630, devicePixelRatio: 2 });
  assert.deepEqual(pngSize(one), [600, 315]);
  assert.deepEqual(pngSize(two), [1200, 630]);
  // layout is the same at 2x: measured boxes scale exactly by 2
  const m1 = r.measureSync(node, { width: 600, height: 315 });
  const m2 = r.measureSync(node, { width: 1200, height: 630, devicePixelRatio: 2 });
  assert.equal(m2.children[0].width, m1.children[0].width * 2);
  // devicePixelRatio alone does not change the canvas size
  assert.deepEqual(pngSize(r.renderSync(node, { width: 600, height: 315, devicePixelRatio: 2 })), [600, 315]);
});

/** Largest font size (step 4) at which `text` fits in `maxLines` lines of `width` px. */
function fitFontSize(renderer, text, { width, maxLines, max = 96, min = 32, lineHeight = 1.2, style = {} }) {
  for (let size = max; size > min; size -= 4) {
    const m = renderer.measureSync(
      { type: "container", style: { display: "block", width, fontSize: size, lineHeight, ...style }, children: [{ type: "text", text }] },
      { width },
    );
    if (m.height <= Math.ceil(size * lineHeight) * maxLines) return size;
  }
  return min;
}

await check("fit text with measure()", () => {
  const r = getRenderer();
  const style = { fontFamily: "Inter", fontWeight: 700 };
  const short = fitFontSize(r, "Short title", { width: 1072, maxLines: 2, style });
  const long = fitFontSize(r, "A much longer title that would overflow two lines at the largest size we allow on the card", { width: 1072, maxLines: 2, style });
  assert.equal(short, 96);
  assert.ok(long < short, `long ${long} < short ${short}`);
  const m = r.measureSync({ type: "container", style: { display: "block", width: 1072, fontSize: long, lineHeight: 1.2, ...style },
    children: [{ type: "text", text: "A much longer title that would overflow two lines at the largest size we allow on the card" }] }, { width: 1072 });
  assert.ok(m.runs.length <= 2, `${m.runs.length} lines`);
  return `short -> ${short}px, long -> ${long}px (${m.runs.length} lines)`;
});

// ------------------------------------------------------------ remote images: fetch yourself, pass `images`
const pngLogo = new Renderer().renderSync({ type: "container", style: { width: 64, height: 64, backgroundColor: "#f97316", borderRadius: 32 } }, { width: 64, height: 64 });
const imgServer = createServer((req, res) => {
  if (req.url === "/logo.png") return res.writeHead(200, { "content-type": "image/png" }).end(pngLogo);
  if (req.url === "/slow.png") return setTimeout(() => res.writeHead(200).end(pngLogo), 2000);
  res.writeHead(404).end();
});
await new Promise((r) => imgServer.listen(0, "127.0.0.1", r));
const IMG = `http://127.0.0.1:${imgServer.address().port}`;

/** Fetches every URL with a timeout; failures become absent images (nothing is painted) instead of errors. */
async function fetchImages(urls, timeoutMs = 3000) {
  const entries = await Promise.all(urls.map(async (src) => {
    try {
      const res = await fetch(src, { signal: AbortSignal.timeout(timeoutMs) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return { src, data: new Uint8Array(await res.arrayBuffer()) };
    } catch (error) {
      console.warn(`image ${src} skipped: ${error.message}`);
      return null;
    }
  }));
  return entries.filter(Boolean);
}

await check("remote images: fetch, then pass as `images` keyed by URL", async () => {
  const src = `${IMG}/logo.png`;
  const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "white" },
    children: [{ type: "image", src, width: 64, height: 64 }] };
  const images = await fetchImages([src, `${IMG}/missing.png`]);
  assert.equal(images.length, 1);
  const withImg = getRenderer().renderSync(node, { width: 64, height: 64, format: "raw", images });
  const without = getRenderer().renderSync(node, { width: 64, height: 64, format: "raw" });
  assert.notDeepEqual(withImg, without, "the image is painted only when its bytes are passed");
  // centre pixel is the orange logo
  const i = (32 * 64 + 32) * 4;
  assert.deepEqual([...withImg.subarray(i, i + 3)], [0xf9, 0x73, 0x16]);
});

await check("remote images: a slow image times out and is skipped", async () => {
  const t0 = performance.now();
  const images = await fetchImages([`${IMG}/slow.png`], 300);
  assert.equal(images.length, 0);
  assert.ok(performance.now() - t0 < 1500);
});
imgServer.close();

await check("errors: invalid inline style throws; signal aborts before rendering", async () => {
  const r = getRenderer();
  assert.throws(() => r.renderSync({ type: "container", style: { width: "abc" } }, { width: 10, height: 10 }), /bm-engine: invalid value for style property width/);
  assert.throws(() => r.renderSync({ type: "container" }, { width: 0, height: 10 }));
  await assert.rejects(r.render(card({ title: "a", description: "b" }), { width: 100, height: 50, signal: AbortSignal.abort(new Error("client went away")) }), /client went away/);
  // a lazy font that resolves after the signal fired: the signal is checked after loading, before rasterising
  const ac = new AbortController();
  const slowFont = new Promise((res) => setTimeout(() => { ac.abort(new Error("deadline")); res(font("Roboto-Regular.ttf")); }, 50));
  await assert.rejects(new Renderer().render({ type: "text", text: "x" }, { width: 10, height: 10, fonts: [{ name: "Roboto", data: slowFont }], signal: ac.signal }), /deadline/);
});

await check("i18n: fallback chain walks registered families in order", () => {
  const text = "Xin chào · Привет · Ԁ"; // U+0500 is in Noto Sans, not in Inter
  const onlyInter = new Renderer();
  onlyInter.registerFont(font("Inter-Regular.ttf"));
  const chain = new Renderer();
  chain.registerFont(font("Inter-Regular.ttf"));     // first choice
  chain.registerFont(font("NotoSans-Regular.ttf"));  // fallback for glyphs Inter lacks
  const node = { type: "text", text: text.normalize("NFC"), style: { fontSize: 40 } };
  const o = { width: 600, height: 60, format: "raw", fontFamilies: ["Inter", "Noto Sans"] };
  assert.notDeepEqual(onlyInter.renderSync(node, o), chain.renderSync(node, o), "U+0500 drawn from Noto Sans");
  // the part both fonts cover is drawn with Inter either way
  const latin = { ...node, text: "Xin chào" };
  assert.deepEqual(onlyInter.renderSync(latin, o), chain.renderSync(latin, o));
});

rmSync(tmp, { recursive: true, force: true });
done();
