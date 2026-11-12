// Memory probe, one fresh process per engine (spawned by bench/run-native.mjs with --expose-gc).
//
//   node --expose-gc native/memory.mjs <engine> suite [--passes=10] [--filter=<regex>]
//       renders every fixture (raw + PNG, async API) `passes` times with one renderer per font set; after
//       each pass: GC, then RSS / V8 heap / external / engine memory (bm: Renderer#memoryBytes = live native
//       allocation or wasm memory size; takumi-wasm: wasm memory size; takumi-native: not exposed).
//   node --expose-gc native/memory.mjs <engine> large [--size=4000]
//       one renderer with Inter, then a size x size PNG of a gradient / shadow / text tree: peak RSS
//       (process.resourceUsage().maxRSS) before and after the render.
import { selectCases } from "../fixtures/index.mjs";
import { renderOpts } from "../lib/pipeline.mjs";
import { createEngine } from "./engines.mjs";

const [engine, what] = process.argv.slice(2);
const args = Object.fromEntries(process.argv.slice(4).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const MiB = 2 ** 20;
const snap = (engines) => {
  global.gc?.(); global.gc?.();
  const m = process.memoryUsage();
  let eng = null;
  // every engine's figure is process-wide (one wasm memory shared by all renderers; the addon's live
  // allocation over all renderers), so take it once
  for (const e of engines) { const b = e.memoryBytes?.(); if (b != null) eng = Math.max(eng ?? 0, b); }
  return { rssMiB: +(m.rss / MiB).toFixed(1), heapUsedMiB: +(m.heapUsed / MiB).toFixed(1), externalMiB: +(m.external / MiB).toFixed(1), arrayBuffersMiB: +(m.arrayBuffers / MiB).toFixed(1), engineMiB: eng == null ? null : +(eng / MiB).toFixed(1), maxRssMiB: +(process.resourceUsage().maxRSS / 1024).toFixed(1) };
};

const out = { engine, what };
if (what === "suite") {
  const passes = +(args.passes ?? 10);
  const cases = selectCases(args.filter);
  const engines = new Map();
  out.beforeMiB = snap([]);
  for (const k of cases) { const key = k.fonts ? k.fonts.join(",") : "*"; if (!engines.has(key)) engines.set(key, await createEngine(engine, k.fonts)); }
  const list = [...engines.values()];
  out.renderers = list.length;
  out.afterSetup = snap(list);
  out.passes = [];
  for (let p = 0; p < passes; p++) {
    const t0 = performance.now();
    for (const k of cases) {
      const e = engines.get(k.fonts ? k.fonts.join(",") : "*");
      for (const f of ["raw", "png"]) { try { await e.async(k.node, renderOpts(k, f)); } catch {} }
    }
    out.passes.push({ pass: p + 1, seconds: +((performance.now() - t0) / 1000).toFixed(1), ...snap(list) });
  }
  for (const e of list) e.dispose();
} else if (what === "large") {
  const size = +(args.size ?? 4000);
  const e = await createEngine(engine, ["Inter"]);
  const node = {
    type: "container",
    style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", padding: 200, gap: 120, backgroundImage: "linear-gradient(135deg,#0f172a,#7c3aed 60%,#db2777)", fontFamily: "Inter" },
    children: [
      { type: "text", text: "Large canvas memory probe", style: { fontSize: 220, fontWeight: 400, color: "white" } },
      ...Array.from({ length: 4 }, (_, i) => ({ type: "container", style: { display: "flex", height: 500, borderRadius: 80, backgroundColor: `rgba(255,255,255,${0.15 + i * 0.1})`, boxShadow: "0 40px 120px rgba(0,0,0,.45)" } })),
    ],
  };
  global.gc?.();
  out.size = size;
  out.before = snap([e]);
  const t0 = performance.now();
  const png = await e.async(node, { width: size, height: size, format: "png" });
  out.ms = +(performance.now() - t0).toFixed(0);
  out.bytes = png.length;
  out.after = snap([e]);
  e.dispose();
}
const c = process.cpuUsage();
out.cpuMs = (c.user + c.system) / 1000;
console.log(JSON.stringify(out));
process.exit(0);
