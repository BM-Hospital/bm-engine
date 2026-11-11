// tw compiler oracle: for each class string, takumi renders/measures a node with `tw: classes` and the SAME
// node with an inline `style` built from our compiled declarations (src/tw/tw.zig via a wasm harness).
// Both runs are takumi, so equality checks our compiler against takumi's own tw semantics.
//
// Build the harness (from repo root; output into a scratch dir, not the repo):
//   zig build-exe -target wasm32-freestanding -O ReleaseSmall -fno-entry -rdynamic --dep tw
//     -Mroot=bench/probe/tw/harness.zig -Mtw=src/tw/tw.zig -femit-bin=<scratch>/harness.wasm
// Usage (from bench/): node probe/tw/oracle.mjs <harness.wasm> [filter-substring] [--verbose]
// Env: TW_W (viewport width, default 800), TW_DPR (default 1).
// The harness exports inPtr(), outPtr(), compile(len, vw, vh, dpr, elementIndex, elementCount, target) -> json length
// (target 0 = element, 1 = ::before, 2 = ::after). Pseudo-element declarations go through takumi's `css` option
// as `#tN::before { ... }` rules (inline style cannot reach pseudo-elements).
import { Renderer } from "@takumi-rs/wasm/node";
import { readFileSync } from "node:fs";
import { FONTS } from "../../lib/fonts.mjs";
import { CLASSES } from "./classes.mjs";

const [harnessPath, filter = "", ...flags] = process.argv.slice(2);
if (!harnessPath) throw new Error("usage: oracle.mjs <harness.wasm> [filter]");
const verbose = flags.includes("--verbose") || filter === "--verbose";
const { instance } = await WebAssembly.instantiate(readFileSync(harnessPath), {});
const hx = instance.exports;
const enc = new TextEncoder(), dec = new TextDecoder();

const W = +(process.env.TW_W ?? 800), H = 220, DPR = +(process.env.TW_DPR ?? 1), COPIES = 3;
function compile(classes, index, target = 0) {
  const bytes = enc.encode(classes);
  new Uint8Array(hx.memory.buffer, hx.inPtr(), bytes.length).set(bytes);
  const n = hx.compile(bytes.length, W, H, DPR, index, COPIES, target);
  return JSON.parse(dec.decode(new Uint8Array(hx.memory.buffer, hx.outPtr(), n)) || "[]");
}
const camel = (k) => k.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
function toStyle(decls) {
  const s = {};
  for (const d of decls) {
    const key = camel(d.n);
    // later declarations win unless an earlier one is important and this one is not
    if (s[key] && s[key].endsWith(" !important") && !d.i) continue;
    s[key] = d.v + (d.i ? " !important" : "");
  }
  return s;
}

const r = new Renderer();
for (const f of FONTS) r.registerFont({ name: f.name, data: readFileSync(f.path), weight: f.weight, style: f.style });

const target = (props) => ({
  type: "container",
  ...props,
  children: [
    { type: "text", text: "Hello Tw Ag" },
    { type: "container", style: { width: 24, height: 16, backgroundColor: "#888" } },
  ],
});
const tree = (mk) => ({
  type: "container",
  style: { width: W, height: H, display: "flex", flexWrap: "wrap", gap: 6, padding: 10, backgroundColor: "#eef", fontFamily: "Inter", position: "relative" },
  children: [0, 1, 2].map(mk),
});
const opts = { width: W, height: H, format: "raw", devicePixelRatio: DPR };
const cssRules = (decls, sel) => decls.length ? [`${sel} { ${decls.map((d) => `${d.n}: ${d.v}${d.i ? " !important" : ""}`).join("; ")} }`] : [];

async function run(node, css = []) {
  try {
    const px = await r.render(node, { ...opts, css });
    const m = await r.measure(node, { width: W, height: H, devicePixelRatio: DPR, css });
    return { px: Buffer.from(px), m: JSON.stringify(m) };
  } catch (e) {
    return { err: String(e?.message ?? e).split("\n")[0].slice(0, 140) };
  }
}

let pass = 0;
const fails = [];
const list = CLASSES.filter((c) => !filter || filter.startsWith("--") || c.includes(filter));
for (const classes of list) {
  const compiled = [0, 1, 2].map((i) => compile(classes, i));
  const pseudo = [0, 1, 2].flatMap((i) => [...cssRules(compile(classes, i, 1), `#t${i}::before`), ...cssRules(compile(classes, i, 2), `#t${i}::after`)]);
  const a = await run(tree((i) => target({ id: `t${i}`, tw: classes })));
  const b = await run(tree((i) => target({ id: `t${i}`, style: toStyle(compiled[i]) })), pseudo);
  let reason = null;
  if (a.err) reason = `tw render threw: ${a.err}`;
  else if (b.err) reason = `style render threw: ${b.err}`;
  else if (a.m !== b.m) reason = "layout differs";
  else if (!a.px.equals(b.px)) {
    let n = 0, max = 0;
    for (let i = 0; i < a.px.length; i++) {
      const d = Math.abs(a.px[i] - b.px[i]);
      if (d) { n++; if (d > max) max = d; }
    }
    reason = `pixels differ (${n} channels, max ${max})`;
  }
  if (reason) fails.push({ classes, reason, decls: compiled[0] });
  else pass++;
  if (verbose) console.log(reason ? "FAIL" : "ok  ", classes, "=>", JSON.stringify(toStyle(compiled[0])), reason ?? "");
}
console.log(`tw oracle: ${pass}/${list.length} pass (${((100 * pass) / list.length).toFixed(1)}%)`);
for (const f of fails) console.log(`FAIL ${JSON.stringify(f.classes)}: ${f.reason}\n     ours: ${JSON.stringify(toStyle(f.decls))}`);
