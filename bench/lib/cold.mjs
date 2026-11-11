// Child-process probe. Usage: node lib/cold.mjs <engine> [--mem]
// Prints one JSON line. Module imports (fixtures, adapter code) happen BEFORE timing starts.
import { ALL } from "../engines/index.mjs";
import { FONTS } from "./fonts.mjs";
import { ALL_CASES, selectCases } from "../fixtures/index.mjs";
import { renderOpts } from "./pipeline.mjs";

const name = process.argv[2];
const mem = process.argv.includes("--mem");
const adapter = ALL[name];
if (!adapter?.available) { console.log(JSON.stringify({ error: "unavailable" })); process.exit(0); }
const k = ALL_CASES.find((c) => c.id === "card-og");
const inter = FONTS[0];

if (!mem) {
  const t0 = performance.now();
  const inst = await adapter.create({ fonts: [] });            // wasm compile + instantiate (or native addon load) + Renderer ctor
  const t1 = performance.now();
  await inst.registerFont(inter);                                // Inter-Regular
  const t2 = performance.now();
  const out = await inst.render(k.node, renderOpts(k, "png"));   // first render (og-card, PNG)
  const t3 = performance.now();
  console.log(JSON.stringify({ initMs: t1 - t0, fontMs: t2 - t1, firstRenderMs: t3 - t2, totalMs: t3 - t0, bytes: out.length }));
} else {
  const inst = await adapter.create({ fonts: FONTS });
  const memStart = inst.memoryBytes?.() ?? null;
  for (let i = 0; i < 50; i++) await inst.render(k.node, renderOpts(k, "png"));
  const ru = process.resourceUsage();
  console.log(JSON.stringify({ maxRssKB: ru.maxRSS, wasmMemoryBytesAfterInit: memStart, wasmMemoryBytesAfter50: inst.memoryBytes?.() ?? null }));
}
process.exit(0);
