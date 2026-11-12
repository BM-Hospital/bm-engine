// measure() equivalence: every fixture (+ transform cases) through takumi and bm; compares width, height,
// transform (all 6 entries) and the child tree EXACTLY (no tolerance; numbers as parsed doubles).
// Runs are not compared (documented difference: bm runs have no `text` and use the line height).
// usage: node measure_cmp.mjs [--filter=re] [--verbose]
import { ALL_CASES } from "../../fixtures/index.mjs";
import { fontsFor } from "../../lib/fonts.mjs";
import tkEngine from "../../engines/takumi-wasm.mjs";
import bmEngine from "../../engines/bm.mjs";
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const TK = await tkEngine.create({ fonts: fontsFor() });
const BM = await bmEngine.create({ fonts: fontsFor() });
const re = args.filter ? new RegExp(args.filter, "i") : null;
const xf = (style, children = []) => ({ type: "container", style: { display: "flex", width: 100, height: 50, ...style }, children });
const extra = [
  ["xf-translate-rotate", xf({ transform: "translateX(50px) rotate(90deg)" })],
  ["xf-rotate30", xf({ transform: "rotate(30deg)" })],
  ["xf-individual", xf({ translate: "10px 20%", rotate: "45deg", scale: "2 0.5", transformOrigin: "0 0" })],
  ["xf-nested", xf({ transform: "scale(2)", padding: 5 }, [xf({ transform: "rotate(90deg) translate(3px,4px)", width: 20, height: 10 }, [xf({ width: 5, height: 5, marginLeft: 3 })])])],
  ["xf-skew-matrix", xf({ transform: "skew(10deg, 5deg) matrix(1,0.1,0.2,1,5,6)" })],
  ["xf-abs", xf({ transform: "rotate(10deg)", position: "relative" }, [xf({ position: "absolute", left: 10, top: 5, width: 10, height: 10, transform: "scale(3)" })])],
  ["xf-origin-pct", xf({ transform: "rotate(-37.5deg) scale(1.25, 0.75)", transformOrigin: "25% 80%" }, [xf({ width: 30, height: 20, transform: "translate(10%, -50%) rotate(1turn)" })])],
  ["xf-text", xf({ transform: "rotate(7deg)", flexDirection: "column" }, [{ type: "text", text: "Hello world", style: { fontFamily: "Inter", transform: "skewX(-12deg)" } }])],
].map(([id, node]) => ({ id, width: 300, height: 300, node: { type: "container", style: { display: "flex", padding: 7, width: 300, height: 300 }, children: [node] } }));
let same = 0, diff = 0, err = 0;
const firstDiff = (a, b, p = "") => {
  for (const k of ["width", "height"]) if (a[k] !== b[k]) return `${p}.${k}: ${a[k]} vs ${b[k]}`;
  for (let i = 0; i < 6; i++) if (a.transform[i] !== b.transform[i]) return `${p}.transform: ${JSON.stringify(a.transform)} vs ${JSON.stringify(b.transform)}`;
  if (a.children.length !== b.children.length) return `${p}.children.length ${a.children.length} vs ${b.children.length}`;
  for (let i = 0; i < a.children.length; i++) { const d = firstDiff(a.children[i], b.children[i], `${p}/${i}`); if (d) return d; }
  return null;
};
for (const k of [...ALL_CASES, ...extra]) {
  if (re && !re.test(k.id)) continue;
  const opts = { width: k.width, height: k.height, images: k.images, ...(k.opts || {}) };
  let a, b;
  try { a = await TK.measure(k.node, opts); b = await BM.measure(k.node, opts); } catch (e) { err++; if (args.verbose) console.log("ERR", k.id, e.message); continue; }
  const d = firstDiff(a, b);
  if (d) { diff++; if (args.verbose) console.log("DIFF", k.id.padEnd(32), d); } else { same++; if (args.verbose) console.log("same", k.id); }
}
console.log(`measure exact: ${same} same, ${diff} different, ${err} errors`);
