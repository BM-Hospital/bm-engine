// Smoke probe: both engines render the same trivial document.
import { probe, sameDocument } from "./lib.mjs";

probe("smoke.hello", "render(html) with default options", async (t) => {
  const r = await t.both("<p>Hello world</p>", {});
  sameDocument(t, r);
  t.ok(!r.bm.error && r.bm.version === "1.7", "bm writes PDF 1.7 by default");
});
