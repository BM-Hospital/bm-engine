// node reduce.mjs <fixture-name | @file.json> [fixtures.json]  -> greedily shrinks a tree while takumi and
// bm-render still disagree on it; prints the minimal tree and both layouts. Needs BM_ONE_WASM (see cmp.mjs).
import { readFileSync } from "node:fs";
import { ours, oracle } from "./cmp.mjs";

const arg = process.argv[2];
let node, vp = [400, 300];
if (arg.startsWith("@")) node = JSON.parse(readFileSync(arg.slice(1), "utf8"));
else {
  const all = JSON.parse(readFileSync(new URL("../../../src/layout/testdata/" + (process.argv[3] || "oracle.json"), import.meta.url), "utf8"));
  const c = all.find((x) => x.name === arg);
  node = c.node; vp = c.vp;
}
// display:none subtrees are not part of takumi's measure output: drop them up front
const strip = (n) => { n.children = (n.children || []).filter((c) => (c.style || {}).display !== "none"); n.children.forEach(strip); };
strip(node);
const nums = (s) => s.trim().split("\n").map((l) => l.trim().split(/[ ,x]/).map(Number));
async function differs(n) {
  let a, b;
  try { a = nums(await oracle(n, vp[0], vp[1])); b = nums(ours(n, vp[0], vp[1])); } catch { return false; }
  if (a.length !== b.length) return false; // structural mismatch (hidden nodes): not a layout diff we can use
  return a.some((r, i) => r.some((v, k) => Math.abs(v - b[i][k]) > 0.02));
}
const clone = (x) => JSON.parse(JSON.stringify(x));
const paths = (n, p = []) => [p, ...(n.children || []).flatMap((c, i) => paths(c, [...p, i]))];
const at = (n, p) => p.reduce((x, i) => x.children[i], n);

if (!(await differs(node))) { console.log("no difference"); process.exit(0); }
let changed = true;
while (changed) {
  changed = false;
  // remove subtrees (deepest last so indices stay valid)
  for (const p of paths(node).reverse()) {
    if (!p.length) continue;
    const t = clone(node);
    at(t, p.slice(0, -1)).children.splice(p[p.length - 1], 1);
    if (await differs(t)) { node = t; changed = true; }
  }
  // hoist a child over its parent
  for (const p of paths(node)) {
    if (!p.length) continue;
    const t = clone(node);
    const par = at(t, p.slice(0, -1));
    const me = par.children[p[p.length - 1]]; if (!me) continue;
    for (let i = 0; i < (me.children || []).length; i++) {
      const t2 = clone(t);
      const par2 = at(t2, p.slice(0, -1));
      par2.children[p[p.length - 1]] = par2.children[p[p.length - 1]].children[i];
      if (await differs(t2)) { node = t2; changed = true; break; }
    }
  }
  // remove style keys
  for (const p of paths(node)) {
    for (const k of Object.keys(at(node, p).style || {})) {
      if (k === "display") continue;
      const t = clone(node);
      delete at(t, p).style[k];
      if (await differs(t)) { node = t; changed = true; }
    }
  }
}
console.log(JSON.stringify(node));
const a = (await oracle(node, vp[0], vp[1])).split("\n"), b = ours(node, vp[0], vp[1]).split("\n");
const flat = paths(node);
for (let i = 0; i < a.length; i++) if (a[i] || b[i]) console.log(((a[i] || "").trim() === (b[i] || "").trim() ? "  " : "! ") + (a[i] || "").padEnd(40) + "| " + (b[i] || "").trim().padEnd(28) + (flat[i] ? JSON.stringify(at(node, flat[i]).style) : ""));
