// Verifies outputs-compared.md: the measure() walk, a print-resolution page render, that no paint-tree API exists and
// that the default (full) build has no PDF writer (PDF output is the separate bm-engine/pdf profile).
import assert from "node:assert/strict";
import * as bm from "bm-engine";
import { getRenderer, card } from "./lib/og.mjs";
import { check, done, pngSize } from "./lib/util.mjs";

await check("no paint-tree API in the public exports / Renderer; the full build has no PDF writer", () => {
  const names = [...Object.keys(bm), ...Object.getOwnPropertyNames(bm.Renderer.prototype)];
  assert.deepEqual(names.filter((n) => /paint/i.test(n)), []);
  assert.equal(bm.features.pdf, false);
  assert.throws(() => new bm.Renderer().renderPdfSync({ type: "container" }), /renderPdf is not supported by this build/);
  return names.filter((n) => n !== "constructor").sort().join(", ");
});

await check("measure() walk from the docs visits boxes and runs", () => {
  const renderer = getRenderer();
  const node = { type: "container", style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", padding: 40, gap: 20, fontFamily: "Inter" },
    children: [
      { type: "container", style: { display: "block", fontSize: 48 }, children: [{ type: "text", text: "Title that is long enough to wrap onto two lines" }] },
      { type: "container", style: { width: 200, height: 60, backgroundColor: "#7c3aed" } },
    ] };
  const layout = renderer.measureSync(node, { width: 600, height: 400 });
  const calls = [];
  function walk(n, m, draw) {
    const [a, b, c, d, x, y] = m.transform;
    draw({ node: n, x, y, width: m.width, height: m.height, matrix: [a, b, c, d, x, y] });
    for (const run of m.runs) draw({ node: n, run: { x: x + run.x, y: y + run.y, width: run.width, height: run.height } });
    const kids = (n.children ?? []).filter((k) => k && k.type === "container");
    m.children.forEach((child, i) => kids[i] && walk(kids[i], child, draw));
  }
  walk(node, layout, (cmd) => calls.push(cmd));
  const boxes = calls.filter((c) => !c.run);
  const runs = calls.filter((c) => c.run);
  assert.equal(boxes.length, 3);
  assert.ok(runs.length >= 2, "wrapped text lines");
  assert.deepEqual([boxes[2].x, boxes[2].width, boxes[2].height], [40, 200, 60]);
  assert.equal(runs[0].run.x, 40);
  return `${boxes.length} boxes, ${runs.length} runs`;
});

await check("A4 page at 150 dpi: 1240 x 1754 canvas, 96-dpi layout scaled by devicePixelRatio", () => {
  const png = getRenderer().renderSync(card({ title: "Certificate", description: "Page 1" }), { width: 1240, height: 1754, devicePixelRatio: 150 / 96 });
  assert.deepEqual(pngSize(png), [1240, 1754]);
});
done();
