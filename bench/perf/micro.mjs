// Focused micro-benchmarks for the performance work (blur, raw output, rounded rects, PNG).
//
//   node bench/perf/micro.mjs [--group=blur,raw,radius,png] [--iters=25] [--base=<dir>] [--json=<file>]
//                             [--filter=<regex on scenario name>] [--no-takumi]
//
// Engines, interleaved round by round with a rotating order (medians are reported):
//   bm-native   native/dist/<platform>/bm-render.<platform>.node   (renderSync; `:async` where the group asks)
//   bm-wasm     js/bm_render.wasm (full profile)                   (renderSync)
//   base-native / base-wasm   the same two files taken from --base=<dir> (`bm-render.node`, `bm_render.wasm`):
//               a build of an earlier commit, loaded side by side in the same process for before / after numbers
//   takumi-native  @takumi-rs/core (async only)
// Every scenario also checks that bm-native and bm-wasm return the same bytes, and reports whether the output
// of the current build equals the base build's (`=base`), so an optimisation that changes pixels is visible here.
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { ROOT_DIR, BENCH_DIR } from "../lib/assets.mjs";
import { fontsFor } from "../lib/fonts.mjs";
import { ALL_CASES } from "../fixtures/index.mjs";
import { renderOpts } from "../lib/pipeline.mjs";

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const ITERS = +(args.iters ?? 25);
const groups = new Set(String(args.group ?? "blur,raw,radius,png").split(","));
const filter = args.filter ? new RegExp(args.filter, "i") : null;

const { createBinding } = await import(pathToFileURL(path.join(ROOT_DIR, "js", "engine.mjs")).href);
const { nativeBackend } = await import(pathToFileURL(path.join(ROOT_DIR, "js", "native.mjs")).href);
const nativeName = `${process.platform}-${process.arch}${process.platform === "win32" ? "-msvc" : ""}`;
const dlopen = (file) => { const m = { exports: {} }; process.dlopen(m, file); return m.exports; };
const wasmBinding = (file) => { const b = createBinding(); b.initSync(readFileSync(file)); return b; };
const nativeBinding = (file) => createBinding(undefined, nativeBackend(dlopen(file)));

const mods = {};
const nat = process.env.BM_RENDER_NATIVE_PATH || path.join(ROOT_DIR, "native", "dist", nativeName, `bm-render.${nativeName}.node`);
if (existsSync(nat)) mods["bm-native"] = nativeBinding(nat);
mods["bm-wasm"] = wasmBinding(process.env.BM_WASM || path.join(ROOT_DIR, "js", "bm_render.wasm"));
if (args.base) {
  const bn = path.join(path.resolve(String(args.base)), "bm-render.node"), bw = path.join(path.resolve(String(args.base)), "bm_render.wasm");
  if (existsSync(bn)) mods["base-native"] = nativeBinding(bn);
  if (existsSync(bw)) mods["base-wasm"] = wasmBinding(bw);
}
if (!args["no-takumi"]) {
  const require = createRequire(path.join(BENCH_DIR, "package.json"));
  mods["takumi-native"] = await import(pathToFileURL(require.resolve("@takumi-rs/core")).href);
}

const fontCache = new Map();
const bytesOf = (p) => { if (!fontCache.has(p)) fontCache.set(p, new Uint8Array(readFileSync(p))); return fontCache.get(p); };
const renderers = new Map();
async function rendererOf(name, families) {
  const key = name + "|" + (families ? families.join(",") : "*");
  if (!renderers.has(key)) {
    const r = new mods[name].Renderer();
    for (const f of fontsFor(families)) await r.registerFont({ name: f.name, data: bytesOf(f.path), weight: f.weight, style: f.style });
    renderers.set(key, r);
  }
  return renderers.get(key);
}

const med = (a) => { const s = [...a].sort((x, y) => x - y); return s[s.length >> 1]; };
const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 12);

/** scenario: { name, node, opts, fonts?, async?: bool (also time bm-native render()) } */
async function run(sc) {
  const variants = [];
  for (const name of Object.keys(mods)) {
    const r = await rendererOf(name, sc.fonts ?? ["Inter"]);
    if (name === "takumi-native") variants.push({ v: name, sync: false, call: () => r.render(sc.node, sc.opts) });
    else {
      variants.push({ v: name, sync: true, call: () => r.renderSync(sc.node, sc.opts) });
      if (sc.async && name.endsWith("native")) variants.push({ v: name + ":async", sync: false, call: () => r.render(sc.node, sc.opts) });
    }
  }
  const row = { name: sc.name, ms: {}, bytes: {}, hash: {} };
  const live = [];
  for (const t of variants) {
    try {
      let out;
      for (let i = 0; i < 2; i++) out = t.sync ? t.call() : await t.call();
      row.bytes[t.v] = out.length;
      row.hash[t.v] = sha(out);
      t.times = [];
      live.push(t);
    } catch (e) {
      row.ms[t.v] = "error: " + String(e?.message ?? e).split("\n")[0].slice(0, 120);
    }
  }
  for (let round = 0; round < ITERS; round++) {
    for (let j = 0; j < live.length; j++) {
      const t = live[(j + round) % live.length];
      const a = performance.now();
      if (t.sync) t.call(); else await t.call();
      t.times.push(performance.now() - a);
    }
  }
  for (const t of live) row.ms[t.v] = +med(t.times).toFixed(3);
  row.nativeEqWasm = row.hash["bm-native"] === undefined ? null : row.hash["bm-native"] === row.hash["bm-wasm"];
  row.eqBase = row.hash["base-wasm"] === undefined ? null : row.hash["base-wasm"] === row.hash["bm-wasm"];
  return row;
}

// ---- scenarios ---------------------------------------------------------------------------------------------
const fill = { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", flexWrap: "wrap" };
const grad = { ...fill, backgroundImage: "linear-gradient(135deg,#1e3a8a,#db2777)" };
const box = (style, children) => ({ type: "container", style, ...(children ? { children } : {}) });
const text = (t, style) => ({ type: "text", text: t, style: { fontFamily: "Inter", ...style } });
const discs = (extra, rot = true) => box(grad, Array.from({ length: 12 }, (_, i) => box({ width: 60, height: 60, margin: 6, borderRadius: 30, backgroundColor: "#fff", ...extra, ...(rot ? { transform: `rotate(${i * 10}deg)` } : {}) })));
const raw = (w, h) => ({ width: w, height: h, format: "raw", devicePixelRatio: 1 });
const one = (style, w = 800, h = 420) => box(grad, [box({ width: 200, height: 120, backgroundColor: "#fff", ...style })]);

const S = [];
if (groups.has("blur")) {
  S.push(
    { name: "blur: 12 rotated discs, filter blur(2px) [anim frame]", node: discs({ filter: "blur(2px)" }), opts: raw(800, 420) },
    { name: "blur: 12 rotated discs, shadow + blur(2px)", node: discs({ filter: "blur(2px)", boxShadow: "0 8px 30px rgba(0,0,0,.5)" }), opts: raw(800, 420) },
    { name: "blur: 12 rotated discs, shadow only", node: discs({ boxShadow: "0 8px 30px rgba(0,0,0,.5)" }), opts: raw(800, 420) },
    { name: "blur: 12 rotated discs, no effect", node: discs({}), opts: raw(800, 420) },
    { name: "blur: 12 unrotated discs, filter blur(2px)", node: discs({ filter: "blur(2px)" }, false), opts: raw(800, 420) },
    { name: "blur: 1 box filter blur(1px) (gaussian)", node: one({ filter: "blur(1px)" }), opts: raw(800, 420) },
    { name: "blur: 1 box filter blur(6px) (3-box)", node: one({ filter: "blur(6px)" }), opts: raw(800, 420) },
    { name: "blur: 1 box filter blur(40px)", node: one({ filter: "blur(40px)" }), opts: raw(800, 420) },
    { name: "blur: 1 rotated box filter blur(6px)", node: one({ filter: "blur(6px)", transform: "rotate(20deg)" }), opts: raw(800, 420) },
    { name: "blur: 1 scaled box filter blur(6px)", node: one({ filter: "blur(6px)", transform: "scale(1.5)" }), opts: raw(800, 420) },
    { name: "blur: full-canvas filter blur(1.5px) 1200x630", node: box({ ...grad, filter: "blur(1.5px)" }, [box({ width: 300, height: 200, backgroundColor: "#fff" })]), opts: raw(1200, 630) },
    { name: "blur: full-canvas filter blur(8px) 1200x630", node: box({ ...grad, filter: "blur(8px)" }, [box({ width: 300, height: 200, backgroundColor: "#fff" })]), opts: raw(1200, 630) },
    { name: "blur: backdrop-filter blur(8px) 200x120", node: one({ backgroundColor: "rgba(255,255,255,.25)", backdropFilter: "blur(8px)", borderRadius: 20 }), opts: raw(800, 420) },
    { name: "blur: rotated backdrop-filter blur(8px)", node: one({ backgroundColor: "rgba(255,255,255,.25)", backdropFilter: "blur(8px)", transform: "rotate(10deg)" }), opts: raw(800, 420) },
    { name: "blur: box-shadow 0 8px 30px", node: one({ boxShadow: "0 8px 30px rgba(0,0,0,.5)" }), opts: raw(800, 420) },
    { name: "blur: box-shadow 0 0 3px (gaussian)", node: one({ boxShadow: "0 0 3px rgba(0,0,0,.5)" }), opts: raw(800, 420) },
    { name: "blur: rotated box-shadow 0 8px 30px", node: one({ boxShadow: "0 8px 30px rgba(0,0,0,.5)", transform: "rotate(20deg)" }), opts: raw(800, 420) },
    { name: "blur: inset box-shadow 0 0 20px", node: one({ boxShadow: "inset 0 0 20px rgba(0,0,0,.8)" }), opts: raw(800, 420) },
    { name: "blur: text-shadow 0 2px 8px, 48px text", node: box(grad, [text("Blurred text shadow", { fontSize: 48, color: "#fff", textShadow: "0 2px 8px rgba(0,0,0,.8)" })]), opts: raw(800, 420) },
    { name: "blur: drop-shadow filter", node: one({ filter: "drop-shadow(0 4px 12px rgba(0,0,0,.6))", borderRadius: 16 }), opts: raw(800, 420) },
    { name: "blur: opacity group (no blur), rotated", node: one({ opacity: 0.5, transform: "rotate(20deg)" }), opts: raw(800, 420) },
  );
}
if (groups.has("raw")) {
  const empty = box({ width: "100%", height: "100%", backgroundColor: "#ffffff" });
  for (const [w, h] of [[300, 200], [1200, 630], [2400, 1260]]) {
    S.push({ name: `raw: empty white ${w}x${h}`, node: empty, opts: raw(w, h), async: true });
  }
  S.push({ name: "raw: transparent root 1200x630", node: box({ width: "100%", height: "100%" }), opts: raw(1200, 630), async: true });
  S.push({ name: "raw: translucent fill 1200x630", node: box({ width: "100%", height: "100%", backgroundColor: "rgba(20,80,200,.5)" }), opts: raw(1200, 630), async: true });
  S.push({ name: "raw: gradient 1200x630", node: box(grad), opts: raw(1200, 630), async: true });
  S.push({ name: "png: empty white 1200x630", node: empty, opts: { ...raw(1200, 630), format: "png" }, async: true });
}
const fx = (id, format, asyncToo) => { const k = ALL_CASES.find((c) => c.id === id); if (!k) throw new Error("no fixture " + id); return { name: `${format}: ${id} ${k.width}x${k.height}`, node: k.node, opts: renderOpts(k, format), fonts: k.fonts, async: asyncToo }; };
if (groups.has("radius")) {
  for (const id of ["radius-uniform-percorner", "sizing-aspect-ratio", "radius-pill-circle", "radius-elliptical"]) S.push(fx(id, "raw", true));
}
if (groups.has("png")) {
  for (const id of ["img-photo-bg", "img-intrinsic-size", "card-blog", "card-og", "card-flat-ui", "lingrad-angles"]) S.push(fx(id, "png", false));
}
if (args.fixtures) for (const id of String(args.fixtures).split(",")) S.push(fx(id, args.format ?? "raw", true));

const rows = [];
const cols = [];
for (const n of Object.keys(mods)) { cols.push(n); if (n.endsWith("native") && n !== "takumi-native") cols.push(n + ":async"); }
console.log(["scenario".padEnd(58), ...cols.map((c) => c.padStart(17)), " n==w", "=base", "  bytes"].join(" "));
for (const sc of S) {
  if (filter && !filter.test(sc.name)) continue;
  const row = await run(sc);
  rows.push(row);
  const f = (v) => (v === undefined ? "" : typeof v === "number" ? v.toFixed(3) : "err").padStart(17);
  const b = (v) => (v === null ? "    -" : v ? "  yes" : "   NO");
  console.log([row.name.slice(0, 58).padEnd(58), ...cols.map((c) => f(row.ms[c])), b(row.nativeEqWasm), b(row.eqBase), String(row.bytes["bm-wasm"] ?? "").padStart(8),
    row.bytes["base-wasm"] !== undefined && row.bytes["base-wasm"] !== row.bytes["bm-wasm"] ? `(base ${row.bytes["base-wasm"]})` : "", row.bytes["takumi-native"] !== undefined && sc.opts.format === "png" ? `(takumi ${row.bytes["takumi-native"]})` : ""].join(" "));
}
if (args.json) writeFileSync(String(args.json), JSON.stringify({ date: new Date().toISOString(), iters: ITERS, rows }, null, 1));
process.exit(0);
