// Extracts the subset of the official GraphemeBreakTest.txt that the text engine's cluster rules
// cover (Extend, ZWJ, emoji modifiers, Extended_Pictographic, Regional_Indicator, tags, "Any")
// into src/font/testdata/grapheme_subset.txt (used by unicode.zig's tests).
//
//   node src/font/gen/gen_grapheme_subset.mjs <GraphemeBreakTest.txt> [out]
//
// Source: https://www.unicode.org/Public/16.0.0/ucd/auxiliary/GraphemeBreakTest.txt (Unicode 16.0).
// Lines with characters of other Grapheme_Cluster_Break classes (CR, LF, Control, Prepend,
// SpacingMark, Hangul L/V/T/LV/LVT, ZWNJ, Indic conjunct linkers) are left out: the engine does not
// segment by them (it never breaks lines or splits fonts inside them for other reasons).
import { readFileSync, writeFileSync } from "node:fs";
const [src, out = "src/font/testdata/grapheme_subset.txt"] = process.argv.slice(2);
const allowed = new Set([0x0308, 0x0300, 0x200d, 0x1f1e6, 0x1f1e7, 0x1f1e8, 0x1f1e9, 0x0020, 0x231a, 0x0061, 0x0062, 0x1f476, 0x1f3ff, 0x1f6d1, 0x2701, 0x0378, 0x003f]);
const lines = [];
for (const raw of readFileSync(src, "utf8").split(/\r?\n/)) {
  const l = raw.split("#")[0].trim();
  if (!l) continue;
  const cps = l.split(/\s+/).filter((t) => /^[0-9A-F]+$/.test(t)).map((t) => parseInt(t, 16));
  if (cps.every((c) => allowed.has(c))) lines.push(l);
}
writeFileSync(out, `# Subset of GraphemeBreakTest-16.0.0.txt (gen/gen_grapheme_subset.mjs): ${lines.length} cases, ÷ = break, × = no break\n` + lines.join("\n") + "\n");
console.log(lines.length, "cases");
