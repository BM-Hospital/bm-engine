// The bench/pdf corpus: takumi-pdf's golden inputs + the guide documents + the scaled stress documents, and the
// helpers that render it with every engine.
import { readFileSync } from "node:fs";
import { goldenFixtures } from "./golden.mjs";
import { docsCorpus, stressCorpus } from "./docs.mjs";
import { createEngine } from "../engines.mjs";

export { STRESS_PAGES, stressCorpus, stressHtml, INTER } from "./docs.mjs";

/** Every corpus document. `filter` is a regex on the id. Stress docs above `maxStress` pages are left out. */
export async function loadCorpus({ filter = null, maxStress = 500 } = {}) {
  const { fixtures, reason } = await goldenFixtures();
  let all = [...fixtures, ...docsCorpus(), ...stressCorpus().filter((d) => d.pages <= maxStress)];
  if (filter) { const re = new RegExp(filter, "i"); all = all.filter((d) => re.test(d.id)); }
  return { docs: all, goldenNote: reason ?? null };
}

const bytes = new Map();
const fontBytes = (p) => { if (!bytes.has(p)) bytes.set(p, new Uint8Array(readFileSync(p))); return bytes.get(p); };
const fontKey = (fonts) => fonts.map((f) => `${f.path}|${f.name ?? ""}|${f.weight ?? ""}|${f.style ?? ""}`).join(";");

/** One engine instance per (engine, font set), fonts registered once (outside any timing). With `keep: 1` only the
 * last font set of each engine stays alive (the others are freed), which bounds memory over the whole corpus. */
export class EnginePool {
  constructor({ keep = Infinity } = {}) { this.map = new Map(); this.keep = keep; }
  async get(name, fonts) {
    const key = name + "#" + fontKey(fonts);
    if (!this.map.has(key)) {
      const mine = [...this.map.keys()].filter((k) => k.startsWith(name + "#"));
      while (mine.length >= this.keep) { const k = mine.shift(); this.map.get(k).e.dispose(); this.map.delete(k); }
      const e = await createEngine(name);
      const families = [];
      for (const f of fonts) {
        const data = fontBytes(f.path);
        const reg = await e.registerFont(f.name ? { name: f.name, data, weight: f.weight, style: f.style } : data);
        families.push(reg[0] ?? f.name ?? "");
      }
      this.map.set(key, { e, families });
    }
    return this.map.get(key);
  }
  dispose() { for (const { e } of this.map.values()) e.dispose(); this.map.clear(); }
}

/** Source + options of `doc` for an engine whose fonts registered as `families`. */
export const inputs = (doc, families) => ({ source: doc.source(families), options: doc.options() });
