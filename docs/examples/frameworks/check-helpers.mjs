// Verifies frameworks/index.md: imageResponse(), h(), the og.mjs pattern, JSX through esbuild (when installed).
import assert from "node:assert/strict";
import { writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { Renderer } from "bm-render";
import { imageResponse } from "./lib/image-response.mjs";
import { h, Fragment } from "./lib/h.mjs";
import { getRenderer, card } from "./lib/og.mjs";
import { check, done, pngSize, font } from "./lib/util.mjs";

await check("og.mjs: getRenderer() returns one renderer", () => {
  assert.equal(getRenderer(), getRenderer());
});

await check("imageResponse(): Request -> Response with PNG bytes", async () => {
  const request = new Request("http://localhost/og?title=Hello&description=World");
  const url = new URL(request.url);
  const res = await imageResponse(getRenderer(), card({ title: url.searchParams.get("title"), description: url.searchParams.get("description") }), {
    width: 1200, height: 630, headers: { "cache-control": "public, max-age=3600" },
  });
  assert.ok(res instanceof Response);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "image/png");
  assert.equal(res.headers.get("cache-control"), "public, max-age=3600");
  const bytes = new Uint8Array(await res.arrayBuffer());
  assert.equal(res.headers.get("content-length"), String(bytes.length));
  assert.deepEqual(pngSize(bytes), [1200, 630]);
  return `${bytes.length} bytes`;
});

await check("imageResponse(): format webp / jpeg set content-type", async () => {
  for (const [format, type, magic] of [["webp", "image/webp", "RIFF"], ["jpeg", "image/jpeg", "\xff\xd8"]]) {
    const res = await imageResponse(getRenderer(), card({ title: "a", description: "b" }), { width: 600, height: 315, format });
    assert.equal(res.headers.get("content-type"), type);
    const b = new Uint8Array(await res.arrayBuffer());
    assert.equal(String.fromCharCode(...b.subarray(0, magic.length)), magic);
  }
});

await check("imageResponse(): render error -> 500 text response, onError called", async () => {
  let seen;
  const res = await imageResponse(getRenderer(), { type: "container", style: { width: "nope" } }, { width: 10, height: 10, onError: (e) => { seen = e; } });
  assert.equal(res.status, 500);
  assert.match(seen.message, /invalid value for style property width/);
  assert.equal(await res.text(), "Failed to generate image");
});

await check("h(): builds the same tree as hand-written nodes (byte-identical PNG)", () => {
  const Title = ({ children }) => h("div", { style: { fontSize: 64, fontWeight: 700 } }, children);
  const viaH = h("div", { style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", padding: 48, fontFamily: "Inter", backgroundColor: "#0f172a", color: "white" } },
    h(Title, null, "Hello ", 42),
    null, false,
    [h("span", { style: { fontSize: 32 } }, "from h()")],
    h(Fragment, null, h("img", { src: "logo", width: 64, height: 64 })));
  const byHand = {
    type: "container", tagName: "div",
    style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", padding: 48, fontFamily: "Inter", backgroundColor: "#0f172a", color: "white" },
    children: [
      { type: "container", tagName: "div", style: { fontSize: 64, fontWeight: 700 }, children: [{ type: "text", text: "Hello " }, { type: "text", text: "42" }] },
      { type: "container", tagName: "span", style: { fontSize: 32 }, children: [{ type: "text", text: "from h()" }] },
      { type: "image", tagName: "img", src: "logo", width: 64, height: 64 },
    ],
  };
  assert.deepEqual(viaH, byHand);
  const r = getRenderer();
  const opts = { width: 600, height: 315, images: [{ src: "logo", data: pngFromRaw() }] };
  assert.deepEqual(r.renderSync(viaH, opts), r.renderSync(byHand, opts));
});

function pngFromRaw() {
  const r = new Renderer();
  return r.renderSync({ type: "container", style: { width: 8, height: 8, backgroundColor: "#f97316" } }, { width: 8, height: 8 });
}

await check("JSX with h() as factory (esbuild --jsx-factory=h)", async () => {
  let esbuild;
  try { esbuild = (await import("esbuild")).default; } catch { return "SKIPPED: esbuild not installed next to this file"; }
  const dir = mkdtempSync(path.join(tmpdir(), "bm-jsx-"));
  try {
    const src = path.join(dir, "card.jsx");
    writeFileSync(src, `
      import { h, Fragment } from ${JSON.stringify(new URL("./lib/h.mjs", import.meta.url).href)};
      export const Card = ({ title }) => (
        <div style={{ display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#7c3aed" }}>
          <span style={{ fontFamily: "Inter", fontSize: 48, color: "white" }}>{title}</span>
          <>{null}{false}</>
        </div>
      );`);
    const out = await esbuild.build({ entryPoints: [src], bundle: false, format: "esm", write: false, jsx: "transform", jsxFactory: "h", jsxFragment: "Fragment" });
    const mod = path.join(dir, "card.mjs");
    writeFileSync(mod, out.outputFiles[0].text);
    const { Card } = await import(pathToFileURL(mod).href);
    const png = getRenderer().renderSync(Card({ title: "JSX" }), { width: 400, height: 200 });
    assert.deepEqual(pngSize(png), [400, 200]);
    return `esbuild ${esbuild.version}`;
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

await check("flexByDefault(): satori-style trees lay out like flex", async () => {
  const { flexByDefault } = await import("./lib/flex-by-default.mjs");
  const satoriStyle = { type: "container", style: { width: 400, height: 200, backgroundColor: "#eee" }, children: [
    { type: "container", style: { width: 100, height: 50 } }, { type: "container", style: { width: 100, height: 50 } }] };
  const r = getRenderer();
  const raw = r.measureSync(satoriStyle, { width: 400, height: 200 });
  const flexed = r.measureSync(flexByDefault(satoriStyle), { width: 400, height: 200 });
  // without display the inline children ignore their size; with flex they sit in a row
  assert.deepEqual(flexed.children.map((c) => [c.width, c.height, c.transform[4]]), [[100, 50, 0], [100, 50, 100]]);
  assert.notDeepEqual(JSON.stringify(raw.children), JSON.stringify(flexed.children));
  return "raw children: " + JSON.stringify(raw.children.map((c) => [c.width, c.height]));
});

await check("satori replacement: renderSvg (full) and PNG in one call", async () => {
  const full = await import("bm-render/full");
  const r = new full.Renderer();
  r.registerFont({ name: "Inter", data: font("Inter-Regular.ttf"), weight: 400, style: "normal" });
  const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundColor: "white" }, children: [{ type: "text", text: "Hello", style: { fontFamily: "Inter", fontSize: 48 } }] };
  const svg = r.renderSvgSync(node, { width: 1200, height: 630 });
  assert.ok(svg.startsWith('<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630"'), svg.slice(0, 80));
  assert.deepEqual(pngSize(r.renderSync(node, { width: 1200, height: 630 })), [1200, 630]);
  return svg.length + " chars of SVG";
});

await check("font() helper reads assets", () => { assert.ok(font("Inter-Regular.ttf").length > 1000); });
done();
