// node cmp.mjs '<json node>' [w h]   -> takumi's layout (oracle) next to bm-render's for one tree
// node cmp.mjs @file.json [w h]      -> same, tree read from a file
// Style objects as in gen.mjs. Needs the wasm32-wasi harness (BM_ONE_WASM, default: <tmp scratch>/one.wasm built
// from a tiny root that imports src/layout/tests.zig; see the layout agent's scratch dir `buildone.sh`).
import { Renderer } from "@takumi-rs/wasm/node";
import { readFileSync } from "node:fs";
import { WASI } from "node:wasi";

const wasmPath = process.env.BM_ONE_WASM;
if (!wasmPath) { console.error("set BM_ONE_WASM to the one.wasm harness"); process.exit(2); }
const mod = new WebAssembly.Module(readFileSync(wasmPath));

export function ours(node, w, h, q64 = true) {
  const wasi = new WASI({ version: "preview1" });
  const inst = new WebAssembly.Instance(mod, wasi.getImportObject());
  wasi.initialize(inst);
  const e = inst.exports;
  const bytes = new TextEncoder().encode(JSON.stringify(node));
  new Uint8Array(e.memory.buffer, e.inPtr(), bytes.length).set(bytes);
  const n = e.run(bytes.length, w, h, q64 ? 1 : 0);
  return new TextDecoder().decode(new Uint8Array(e.memory.buffer, e.outPtr(), n));
}

const r = new Renderer();
const toT = (n) => ({ type: "container", style: n.style || {}, children: (n.children || []).map(toT) });
export async function oracle(node, w, h) {
  const m = await r.measure(toT(node), { width: w, height: h });
  const out = [];
  const f = (n, d) => { out.push(" ".repeat(d * 2) + `${n.transform[4]},${n.transform[5]} ${n.width}x${n.height}`); n.children.forEach((c) => f(c, d + 1)); };
  f(m, 0);
  return out.join("\n") + "\n";
}

if (process.argv[1] && process.argv[1].endsWith("cmp.mjs")) {
  const arg = process.argv[2];
  const node = JSON.parse(arg.startsWith("@") ? readFileSync(arg.slice(1), "utf8") : arg);
  const w = +(process.argv[3] || 400), h = +(process.argv[4] || 300);
  const a = (await oracle(node, w, h)).split("\n"), b = ours(node, w, h).split("\n");
  let bad = 0;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const same = (a[i] || "").trim() === (b[i] || "").trim();
    if (!same) bad++;
    if (a[i] || b[i]) console.log((same ? "  " : "! ") + (a[i] || "").padEnd(44) + (same ? "" : "| " + (b[i] || "").trim()));
  }
  console.log(bad ? `${bad} differing nodes (left: takumi, right: bm)` : "identical");
}
