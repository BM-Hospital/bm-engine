// node probe/paint/tally.mjs  -> verdict tally of bench/out/results.json per fixture group (phase-1 in-scope 78, known-gaps 9, paintfx, rest)
import { readFileSync } from "node:fs";
import gaps from "../../fixtures/gaps.mjs";
import paintfx from "../../fixtures/paintfx.mjs";
const P1 = ["colors", "flex", "sizing", "absolute", "borders", "radius", "gradients", "radial", "shadow", "opacity", "overflow", "transform", "text", "images", "grid", "cards", "stress"];
const p1 = new Set(); for (const f of P1) for (const k of (await import(`../../fixtures/${f}.mjs`)).default) p1.add(k.id);
for (const k of gaps) if (k.feature !== "known-gaps") p1.add(k.id);
const gapIds = new Set(gaps.filter((k) => k.feature === "known-gaps").map((k) => k.id)), pf = new Set(paintfx.map((k) => k.id));
const r = JSON.parse(readFileSync(new URL("../../out/results.json", import.meta.url), "utf8"));
const t = {};
for (const c of r.cases) { const g = p1.has(c.id) ? "phase1-in-scope" : gapIds.has(c.id) ? "known-gaps" : pf.has(c.id) ? "paintfx" : "other"; const v = c.cmp?.bm?.verdict ?? "error"; (t[g] ??= {})[v] = (t[g][v] || 0) + 1; }
console.log(t);
