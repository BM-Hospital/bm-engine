// Event-loop blocking probe, one fresh process per (engine, api, job) (spawned by bench/run-native.mjs).
//
//   node native/eventloop.mjs <engine> <sync|async> <heavy|anim>
//
// A 1 ms setInterval records the gap between consecutive ticks while one heavy call runs:
//   heavy  one 2400x2400 PNG: gradient, 24 cards with large blurred box-shadows and filter: blur(), text
//   anim   renderAnimation, 60 frames (2 s at 30 fps) of 800x420 lossless WebP, 12 shadowed blurred discs
// Reported: job time, the longest gap (max timer delay), the 99th percentile gap, tick count. A sync call
// blocks the loop for its whole duration by definition; it is measured the same way for completeness.
const [engine, api, job] = process.argv.slice(2);
const { createEngine } = await import("./engines.mjs");
const e = await createEngine(engine, ["Inter"]);
const fn = job === "anim" ? e[api === "sync" ? "animSync" : "animAsync"] : e[api];
if (!fn) { console.log(JSON.stringify({ engine, api, job, unsupported: true })); process.exit(0); }

const heavy = {
  type: "container",
  style: { display: "flex", flexWrap: "wrap", gap: 60, padding: 80, width: "100%", height: "100%", backgroundImage: "linear-gradient(135deg,#1e3a8a,#db2777)", fontFamily: "Inter" },
  children: Array.from({ length: 24 }, (_, i) => ({
    type: "container",
    style: { display: "flex", alignItems: "center", justifyContent: "center", width: 480, height: 300, borderRadius: 40, backgroundColor: "rgba(255,255,255,0.9)", boxShadow: "0 30px 90px rgba(0,0,0,.55), 0 0 40px rgba(124,58,237,.6)", filter: i % 3 === 0 ? "blur(6px)" : "none" },
    children: [{ type: "text", text: `Card ${i + 1}`, style: { fontSize: 64, color: "#0f172a" } }],
  })),
};
const disc = { type: "container", style: { display: "flex", width: "100%", height: "100%", backgroundImage: "linear-gradient(135deg,#1e3a8a,#db2777)", alignItems: "center", justifyContent: "center" },
  children: Array.from({ length: 12 }, (_, i) => ({ type: "container", style: { width: 60, height: 60, margin: 6, borderRadius: 30, backgroundColor: "#fff", boxShadow: "0 8px 30px rgba(0,0,0,.5)", filter: "blur(2px)", transform: `rotate(${i * 10}deg)` } })) };
const call = job === "anim"
  ? () => fn({ scenes: [{ node: disc, durationMs: 2000 }], width: 800, height: 420, fps: 30, format: "webp" })
  : () => fn(heavy, { width: 2400, height: 2400, format: "png" });

// warm the engine (code paths, font) with a small render, not the job itself
await e.async({ type: "text", text: "warm", style: { fontFamily: "Inter", fontSize: 20 } }, { width: 100, height: 40, format: "png" });

// An idle Node loop on Windows sleeps in the OS poll with a 15.6 ms clock, so a 1 ms timer fires every ~15.6 ms.
// A setImmediate chain keeps the loop polling without sleeping, which gives the timer ~1 ms resolution; the chain
// also records the longest gap between two loop iterations (maxIterGapMs). Run with --no-spin to see the plain timer.
const spin = !process.argv.includes("--no-spin");
let stopSpin = false, lastIter = performance.now(), maxIter = 0, afterIter = 0;
const iter = () => { const now = performance.now(); if (!done || afterIter++ === 0) maxIter = Math.max(maxIter, now - lastIter); lastIter = now; if (!stopSpin) setImmediate(iter); };
if (spin) setImmediate(iter);
const gaps = [];
let last = performance.now(), done = false, after = 0;
// gaps are recorded while the job runs, plus the first tick after it ends (which sees a blocking call)
const timer = setInterval(() => { const now = performance.now(); if (!done || after++ === 0) gaps.push(now - last); last = now; }, 1);
await new Promise((r) => setTimeout(r, 300)); // idle baseline: the timer's own granularity on this OS
const idle = gaps.splice(0).sort((a, b) => a - b);
last = performance.now();
maxIter = 0; lastIter = performance.now();
const cpu0 = process.cpuUsage();
const t0 = performance.now();
const out = api === "sync" ? call() : await call();
const ms = performance.now() - t0;
const cpu = process.cpuUsage(cpu0);
done = true;
await new Promise((r) => setTimeout(r, 20)); // let the timer observe the end of a blocking call
clearInterval(timer);
stopSpin = true;
const during = gaps.length ? gaps : [ms];
const s = [...during].sort((a, b) => a - b);
const p99 = s[Math.min(s.length - 1, Math.floor(0.99 * (s.length - 1) + 0.5))];
const ip99 = idle[Math.min(idle.length - 1, Math.floor(0.99 * (idle.length - 1) + 0.5))];
console.log(JSON.stringify({ engine, api, job, idleMaxMs: +idle[idle.length - 1].toFixed(1), idleP99Ms: +ip99.toFixed(1), idleMedianMs: +idle[idle.length >> 1].toFixed(2), ms: +ms.toFixed(1), cpuMs: +((cpu.user + cpu.system) / 1000).toFixed(0), maxDelayMs: +s[s.length - 1].toFixed(1), p99DelayMs: +p99.toFixed(1), ticks: during.length, spin, maxIterGapMs: spin ? +maxIter.toFixed(1) : null, bytes: out.length }));
process.exit(0);
