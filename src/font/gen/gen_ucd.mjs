// Generator for the Unicode data tables used by src/font (ucd.zig, nfdata.zig, indic_data.zig).
//
//   node src/font/gen/gen_ucd.mjs <dir with UCD 16.0 files> [out dir = src/font]
//
// Needed UCD files (https://www.unicode.org/Public/16.0.0/ucd/): UnicodeData.txt, Scripts.txt,
// PropertyValueAliases.txt, LineBreak.txt, EastAsianWidth.txt, DerivedBidiClass.txt (extracted/),
// BidiBrackets.txt, BidiMirroring.txt, ArabicShaping.txt, emoji-data.txt (emoji/),
// DerivedNormalizationProps.txt, IndicSyllabicCategory.txt, IndicPositionalCategory.txt.
// Not run by the build: the outputs are checked in.
import { readFileSync, writeFileSync } from "node:fs";
const dir = process.argv[2], out = process.argv[3] ?? "src/font";
const rd = (f) => readFileSync(`${dir}/${f}`, "utf8").split(/\r?\n/);
const MAX = 0x10000; // tables cover the BMP; higher planes are handled by code (unicode.zig)
function prop(file, field = 1, deflt = null, missing = true) {
  const a = new Array(MAX).fill(deflt);
  const lines = rd(file);
  const put = (r, v) => { const [s, e] = r.split("..").map((x) => parseInt(x, 16)); for (let c = s; c <= (e ?? s) && c < MAX; c++) a[c] = v; };
  if (missing) for (const l of lines) { const m = /^# @missing: ([0-9A-F.]+); *(\w+)/.exec(l); if (m) put(m[1], m[2]); }
  for (const l of lines) { const t = l.split("#")[0].split(";").map((x) => x.trim()); if (t.length > field && t[0]) put(t[0], t[field]); }
  return a;
}
// ---- UnicodeData
const gc = new Array(MAX).fill("Cn"), ccc = new Array(MAX).fill(0), decomp = new Map();
{ let rs = -1;
  for (const l of rd("UnicodeData.txt")) { const t = l.split(";"); if (t.length < 6) continue; const c = parseInt(t[0], 16);
    if (t[1].endsWith("First>")) { rs = c; continue; }
    const s = t[1].endsWith("Last>") ? rs : c;
    for (let k = s; k <= c && k < MAX; k++) { gc[k] = t[2]; ccc[k] = +t[3]; }
    if (t[5] && !t[5].startsWith("<")) decomp.set(c, t[5].split(" ").map((x) => parseInt(x, 16))); } }
const scripts = prop("Scripts.txt", 1, "Unknown", false);
const lb = prop("LineBreak.txt", 1, "XX");
const eaw = prop("EastAsianWidth.txt", 1, "N");
const bidiLong = { Left_To_Right: "L", Right_To_Left: "R", Arabic_Letter: "AL", European_Terminator: "ET", Boundary_Neutral: "BN" };
const bidi = prop("DerivedBidiClass.txt", 1, "L").map((x) => bidiLong[x] ?? x);
const extpict = new Array(MAX).fill(false);
const extpict_ranges = [];
for (const l of rd("emoji-data.txt")) { const t = l.split("#")[0].split(";").map((x) => x.trim()); if (t[1] !== "Extended_Pictographic") continue;
  const [s, e] = t[0].split("..").map((x) => parseInt(x, 16)); extpict_ranges.push([s, e ?? s]); for (let c = s; c <= (e ?? s) && c < MAX; c++) extpict[c] = true; }

// ---- combined property word: lb(6) | east-asian(1) << 6 | bidi(5) << 7 | gc class(3) << 12
const LB = ["al","sp","gl","ba","b2","zw","op","cl","qu","ex","is","ns","id","in","cm","cp","hy","sy","nu","po","pr","bb","cb","wj","zwj","ri","eb","em","h2","h3","jl","jv","jt","hl","bk","xp","sa","sam"];
const BIDI = ["L","R","AL","EN","ES","ET","AN","CS","NSM","BN","B","S","WS","ON","LRE","LRO","RLE","RLO","PDF","LRI","RLI","FSI","PDI"];
const gcClass = (g) => g === "Mn" ? 1 : g === "Mc" ? 2 : g === "Me" ? 3 : g === "Cf" ? 4 : g[0] === "L" ? 5 : g === "Nd" ? 6 : (g === "Cn" || g === "Co" || g === "Cs") ? 7 : 0;
function lbResolve(c) {
  let k = lb[c];
  if (k === "AI" || k === "SG" || k === "XX") k = "AL";
  else if (k === "SA") k = (gc[c] === "Mn" || gc[c] === "Mc") ? "SAM" : "SA"; // complex-context scripts: see unicode.zig
  else if (k === "CJ") k = "NS";
  // takumi's ICU4X segmenter has no Aksara rules (LB28a): these classes behave like ID there
  else if (["AK", "AP", "AS", "VF", "VI"].includes(k)) k = "ID";
  else if (k === "CR" || k === "LF" || k === "NL") k = "BK";
  else if (k === "ID" && gc[c] === "Cn" && extpict[c]) k = "XP";
  else if (k === "H2") k = "H3"; // Hangul LV syllables are told apart arithmetically
  const i = LB.indexOf(k.toLowerCase()); if (i < 0) throw new Error("lb " + k); return i;
}
const props = new Uint16Array(MAX);
for (let c = 0; c < MAX; c++) {
  const b = BIDI.indexOf(bidi[c]); if (b < 0) throw new Error("bidi " + bidi[c]);
  const ea = (eaw[c] === "F" || eaw[c] === "W" || eaw[c] === "H") ? 1 : 0;
  props[c] = lbResolve(c) | (ea << 6) | (b << 7) | (gcClass(gc[c]) << 12);
  // unassigned code points copy their predecessor (better block sharing; they have no glyphs anyway)
  if (gc[c] === "Cn" && c > 0 && !extpict[c] && c < 0xfdd0) props[c] = props[c - 1];
}
// ---- scripts
const iso = new Map();
for (const l of rd("PropertyValueAliases.txt")) { const t = l.split("#")[0].split(";").map((x) => x.trim()); if (t[0] === "sc") iso.set(t[2], t[1]); }
const scriptNames = ["Common", "Inherited", "Unknown", ...[...new Set(scripts)].filter((s) => !["Common", "Inherited", "Unknown"].includes(s)).sort()];
if (scriptNames.length > 255) throw new Error("too many scripts");
const scr = new Uint8Array(MAX); for (let c = 0; c < MAX; c++) scr[c] = scriptNames.indexOf(scripts[c]);

// ---- two-stage packing: tries block sizes, picks the smallest
function twoStage(vals, name, T) {
  let best = null;
  for (const sh of [4, 5, 6, 7, 8]) {
    const bs = 1 << sh, blocks = [], map = new Map(), s1 = [];
    for (let i = 0; i < vals.length; i += bs) { const k = Array.from(vals.subarray(i, i + bs)).join(","); let id = map.get(k); if (id === undefined) { id = blocks.length; map.set(k, id); blocks.push(vals.subarray(i, i + bs)); } s1.push(id); }
    const w1 = blocks.length > 256 ? 2 : 1, size = s1.length * w1 + blocks.length * bs * T;
    if (!best || size < best.size) best = { sh, s1, blocks, w1, size };
  }
  const flat = best.blocks.flatMap((b) => Array.from(b));
  const s = `pub const ${name}_shift = ${best.sh};\npub const ${name}_s1 = [_]u${best.w1 * 8}{${best.s1.join(",")}};\npub const ${name}_s2 = [_]u${T * 8}{${flat.join(",")}};\n`;
  return { s, size: best.size };
}
let z = `//! GENERATED by src/font/gen/gen_ucd.mjs from the Unicode 16.0 character database. Do not edit.\n//! Property tables for complex text: line-break class, East Asian width, bidi class, coarse\n//! general category, script, Arabic joining type, mirroring, bracket pairs, combining classes.\n\n`;
z += `pub const Lb = enum(u6) { ${LB.map((x) => x === "in" ? '@"in"' : x).join(", ")} };\n`;
z += `pub const Bidi = enum(u5) { ${BIDI.map((x) => x.toLowerCase()).join(", ")} };\n`;
z += `/// Coarse general category.\npub const Gc = enum(u3) { other, mn, mc, me, cf, letter, nd, unassigned };\n`;
z += `pub const table_limit = 0x${MAX.toString(16)};\n`;
let total = 0;
{ // props: index into unique-value list when it fits a byte
  const uniq = [...new Set(props)].sort((a, b) => a - b);
  if (uniq.length <= 256) { const idx = new Uint8Array(MAX); for (let c = 0; c < MAX; c++) idx[c] = uniq.indexOf(props[c]);
    const t = twoStage(idx, "props", 1); console.log("props", t.size, uniq.length); z += `/// lb | east_asian << 6 | bidi << 7 | gc << 12\npub const props_vals = [_]u16{${uniq.join(",")}};\n` + t.s; total += t.size + uniq.length * 2;
  } else throw new Error("props uniq " + uniq.length);
}
{ // script runs: unassigned code points extend the previous run
  const st = [], sv = []; let prev = -1;
  for (let c = 0; c < MAX; c++) { let v = scr[c]; if (scripts[c] === "Unknown" && c > 0) v = prev; if (v !== prev) { st.push(c); sv.push(v); prev = v; } }
  z += `/// Script runs of the BMP: run i covers script_start[i] .. script_start[i+1]-1 with script id script_val[i].
pub const script_start = [_]u16{${st.join(",")}};
pub const script_val = [_]u8{${sv.join(",")}};
`;
  total += st.length * 3; console.log("script runs", st.length); }
z += `pub const script_count = ${scriptNames.length};\n/// ISO 15924 codes (4 bytes each), indexed by script id.\npub const script_iso = "${scriptNames.map((n) => n === "Unknown" ? "Zzzz" : iso.get(n)).join("")}";\n`;
total += scriptNames.length * 4;
for (const n of ["Common", "Inherited", "Unknown", "Latin", "Greek", "Cyrillic", "Arabic", "Hebrew", "Syriac", "Nko", "Mongolian", "Thai", "Lao", "Hangul", "Han", "Hiragana", "Katakana", "Devanagari", "Bengali", "Gurmukhi", "Gujarati", "Oriya", "Tamil", "Telugu", "Kannada", "Malayalam", "Sinhala", "Mandaic", "Phags_Pa"])
  z += `pub const sc_${n.toLowerCase()} = ${scriptNames.indexOf(n)};\n`;
// ---- Arabic joining types 0600..08FF (nibbles: 0 unlisted, 1 U, 2 L, 3 R, 4 D/C)
{ const jt = prop("ArabicShaping.txt", 2, "X", false); const nib = [];
  const v = (x) => ({ X: 0, U: 1, L: 2, R: 3, D: 4, C: 4, T: 0 })[jt[x]];
  for (let c = 0x600; c < 0x900; c += 2) nib.push(v(c) | (v(c + 1) << 4));
  z += `/// Joining types of U+0600..U+08FF, two per byte (low nibble first): 0 unlisted, 1 U, 2 L, 3 R, 4 D/C.\npub const joining = [_]u8{${nib.join(",")}};\n`; total += nib.length; }
// ---- mirroring pairs (each pair once, a < b)
{ const pairs = []; for (const l of rd("BidiMirroring.txt")) { const t = l.split("#")[0].split(";").map((x) => parseInt(x.trim(), 16)); if (t.length === 2 && t[0] < t[1]) pairs.push(t); }
  z += `/// Bidi mirroring pairs (a, b), a < b, sorted by a.\npub const mirror = [_][2]u16{${pairs.map((p) => `.{${p[0]},${p[1]}}`).join(",")}};\n`; total += pairs.length * 4; }
{ const br = []; for (const l of rd("BidiBrackets.txt")) { const t = l.split("#")[0].split(";").map((x) => x.trim()); if (t.length === 3 && t[2] === "o") br.push([parseInt(t[0], 16), parseInt(t[1], 16)]); }
  z += `/// Bidi paired brackets (open, close), sorted by open.\npub const brackets = [_][2]u16{${br.map((p) => `.{${p[0]},${p[1]}}`).join(",")}};\n`; total += br.length * 4; }
{ z += `/// Extended_Pictographic ranges (inclusive).\npub const ext_pict = [_][2]u32{${extpict_ranges.sort((a, b) => a[0] - b[0]).map((p) => `.{${p[0]},${p[1]}}`).join(",")}};\n`; total += extpict_ranges.length * 8; }
// ---- combining classes (BMP), HarfBuzz "modified" classes
const MCC = { 10: 22, 11: 15, 12: 16, 13: 17, 14: 23, 15: 18, 16: 19, 17: 20, 18: 21, 19: 14, 20: 24, 21: 12, 22: 25, 23: 13, 24: 10, 25: 11, 26: 26,
  27: 28, 28: 29, 29: 30, 30: 31, 31: 32, 32: 33, 33: 27, 34: 34, 35: 35, 84: 0, 91: 0, 103: 3, 118: 3, 130: 132, 132: 131 };
const mcc = (c) => MCC[ccc[c]] ?? ccc[c];
{ const r = []; for (let c = 0; c < 0x10000; c++) { const v = mcc(c); if (!v) continue; const l = r[r.length - 1]; if (l && l[0] + l[1] === c && l[2] === v && l[1] < 256) l[1]++; else r.push([c, 1, v]); }
  z += `/// Runs of equal (HarfBuzz-modified) canonical combining class in the BMP: start, len-1, class.\npub const ccc_start = [_]u16{${r.map((x) => x[0]).join(",")}};\npub const ccc_len = [_]u8{${r.map((x) => x[1] - 1).join(",")}};\npub const ccc_val = [_]u8{${r.map((x) => x[2]).join(",")}};\n`; total += r.length * 4; }
writeFileSync(`${out}/ucd.zig`, z);
console.log("ucd.zig data bytes ~", total);

// ---- canonical pair (de)composition
{ const excl = new Set(); for (const l of rd("DerivedNormalizationProps.txt")) { const t = l.split("#")[0].split(";").map((x) => x.trim()); if (t[1] !== "Full_Composition_Exclusion") continue; const [s, e] = t[0].split("..").map((x) => parseInt(x, 16)); for (let c = s; c <= (e ?? s); c++) excl.add(c); }
  const ents = []; for (const [c, d] of decomp) { if (d.length !== 2) continue; if (!(c < 0x1100 || (c >= 0x1e00 && c < 0x2000))) continue; ents.push([c, d[0], d[1]]); }
  ents.sort((a, b) => a[0] - b[0]);
  const marks = [...new Set(ents.map((e) => e[2]))].sort((a, b) => a - b); if (marks.length > 127) throw new Error("marks");
  const byab = ents.map((_, i) => i).sort((i, j) => ents[i][2] - ents[j][2] || ents[i][1] - ents[j][1]);
  let n = `//! GENERATED by src/font/gen/gen_ucd.mjs (UnicodeData.txt canonical two-character decompositions of\n//! U+0000..U+10FF and U+1E00..U+1FFF: Latin, Greek, Cyrillic, Vietnamese, plus the Hebrew/Arabic/Indic\n//! pairs in that range). Do not edit.\n\n`;
  n += `/// Composed characters, ascending.\npub const c = [_]u16{${ents.map((e) => e[0]).join(",")}};\n/// First (base) part of each decomposition.\npub const a = [_]u16{${ents.map((e) => e[1]).join(",")}};\n`;
  n += `/// Index of the second part in \`marks\`; bit 7 = excluded from composition.\npub const b = [_]u8{${ents.map((e) => marks.indexOf(e[2]) | (excl.has(e[0]) ? 0x80 : 0)).join(",")}};\npub const marks = [_]u16{${marks.join(",")}};\n`;
  n += `/// Entry indices sorted by (mark index, base) for composition.\npub const by_ab = [_]u16{${byab.join(",")}};\n`;
  writeFileSync(`${out}/nfdata.zig`, n); console.log("nfdata entries", ents.length, "bytes ~", ents.length * 7 + marks.length * 2); }

// ---- Indic shaper categories (HarfBuzz gen-indic-table.py semantics)
{ const isc = prop("IndicSyllabicCategory.txt", 1, "Other", false), ipc = prop("IndicPositionalCategory.txt", 1, "Not_Applicable", false);
  const CAT = { X: 0, C: 1, V: 2, N: 3, H: 4, ZWNJ: 5, ZWJ: 6, M: 7, SM: 8, A: 9, PLACEHOLDER: 10, DOTTEDCIRCLE: 11, RS: 12, MPst: 13, Repha: 14, Ra: 15, CM: 16, Symbol: 17, CS: 18 };
  const POS = { START: 0, RA_TO_BECOME_REPH: 1, PRE_M: 2, PRE_C: 3, BASE_C: 4, AFTER_MAIN: 5, ABOVE_C: 6, BEFORE_SUB: 7, BELOW_C: 8, AFTER_SUB: 9, BEFORE_POST: 10, POST_C: 11, AFTER_POST: 12, SMVD: 13, END: 14 };
  const cmap = { Other: "X", Avagraha: "Symbol", Bindu: "SM", Brahmi_Joining_Number: "PLACEHOLDER", Cantillation_Mark: "A", Consonant: "C", Consonant_Dead: "C", Consonant_Final: "CM", Consonant_Head_Letter: "C", Consonant_Initial_Postfixed: "C", Consonant_Killer: "M", Consonant_Medial: "CM", Consonant_Placeholder: "PLACEHOLDER", Consonant_Preceding_Repha: "Repha", Consonant_Prefixed: "X", Consonant_Subjoined: "CM", Consonant_Succeeding_Repha: "CM", Consonant_With_Stacker: "CS", Gemination_Mark: "SM", Invisible_Stacker: "H", Joiner: "ZWJ", Modifying_Letter: "X", Non_Joiner: "ZWNJ", Nukta: "N", Number: "PLACEHOLDER", Number_Joiner: "PLACEHOLDER", Pure_Killer: "M", Register_Shifter: "RS", Syllable_Modifier: "SM", Tone_Letter: "X", Tone_Mark: "N", Virama: "H", Visarga: "SM", Vowel: "V", Vowel_Dependent: "M", Vowel_Independent: "V", Reordering_Killer: "M" };
  const pmap = { Not_Applicable: "END", Left: "PRE_C", Top: "ABOVE_C", Bottom: "BELOW_C", Right: "POST_C", Bottom_And_Right: "POST_C", Left_And_Right: "POST_C", Top_And_Bottom: "BELOW_C", Top_And_Bottom_And_Left: "BELOW_C", Top_And_Bottom_And_Right: "POST_C", Top_And_Left: "ABOVE_C", Top_And_Left_And_Right: "POST_C", Top_And_Right: "POST_C", Overstruck: "AFTER_MAIN", Visual_Order_Left: "PRE_M", Bottom_And_Left: "BELOW_C" };
  const catOv = new Map([[0x930, "Ra"], [0x9b0, "Ra"], [0x9f0, "Ra"], [0xa30, "Ra"], [0xab0, "Ra"], [0xb30, "Ra"], [0xbb0, "Ra"], [0xc30, "Ra"], [0xcb0, "Ra"], [0xd30, "Ra"],
    [0x953, "SM"], [0x954, "SM"], [0xa40, "MPst"], [0xa72, "C"], [0xa73, "C"], [0x1cf5, "C"], [0x1cf6, "C"], [0x1ced, "A"], [0xa51, "M"], [0xafb, "N"], [0xb55, "N"], [0x9fc, "PLACEHOLDER"], [0xc80, "PLACEHOLDER"], [0xd04, "PLACEHOLDER"], [0x25cc, "DOTTEDCIRCLE"]]);
  for (let c = 0x1ce2; c <= 0x1ce8; c++) catOv.set(c, "A");
  for (const [s, e] of [[0xa8f2, 0xa8f7], [0x1ce9, 0x1cec], [0x1cee, 0x1cf1]]) for (let c = s; c <= e; c++) catOv.set(c, "Symbol");
  const block = (c) => c < 0x980 ? "Deva" : c < 0xa00 ? "Beng" : c < 0xa80 ? "Guru" : c < 0xb00 ? "Gujr" : c < 0xb80 ? "Orya" : c < 0xc00 ? "Taml" : c < 0xc80 ? "Telu" : c < 0xd00 ? "Knda" : c < 0xd80 ? "Mlym" : c < 0xe00 ? "Sinh" : "";
  const matra = (u, pos, b) => {
    if (pos === "PRE_C") return "PRE_M";
    if (pos === "POST_C") return ({ Deva: "AFTER_SUB", Beng: "AFTER_POST", Guru: "AFTER_POST", Gujr: "AFTER_POST", Orya: "AFTER_POST", Taml: "AFTER_POST", Telu: u <= 0xc42 ? "BEFORE_SUB" : "AFTER_SUB", Knda: (u < 0xcc3 || u > 0xcd6) ? "BEFORE_SUB" : "AFTER_SUB", Mlym: "AFTER_POST" })[b] ?? "AFTER_SUB";
    if (pos === "ABOVE_C") return ({ Deva: "AFTER_SUB", Guru: "AFTER_POST", Gujr: "AFTER_SUB", Orya: "AFTER_MAIN", Taml: "AFTER_SUB", Telu: "BEFORE_SUB", Knda: "BEFORE_SUB" })[b] ?? "AFTER_SUB";
    if (pos === "BELOW_C") return ({ Deva: "AFTER_SUB", Beng: "AFTER_SUB", Guru: "AFTER_POST", Gujr: "AFTER_POST", Orya: "AFTER_SUB", Taml: "AFTER_POST", Telu: "BEFORE_SUB", Knda: "BEFORE_SUB", Mlym: "AFTER_POST" })[b] ?? "AFTER_SUB";
    return pos;
  };
  const get = (c) => { let cat = catOv.get(c) ?? cmap[isc[c]], pos = pmap[ipc[c]]; if (cat === undefined || pos === undefined) throw new Error("indic " + c.toString(16) + isc[c] + ipc[c]);
    if (c === 0xa51) pos = "BELOW_C";
    if (["C", "CS", "Ra", "CM", "V", "PLACEHOLDER", "DOTTEDCIRCLE"].includes(cat)) pos = "BASE_C";
    else if (cat === "M" || cat === "MPst") pos = matra(c, pos, block(c));
    else if (["SM", "A", "Symbol"].includes(cat)) pos = "SMVD";
    if (c === 0xb01) pos = "BEFORE_SUB";
    return [CAT[cat], POS[pos]]; };
  const pairs = [], idx = (c) => { const [a, b] = get(c); const k = a | (b << 8); let i = pairs.indexOf(k); if (i < 0) { i = pairs.length; pairs.push(k); } return i; };
  const rng = (s, e) => { const r = []; for (let c = s; c <= e; c++) r.push(idx(c)); return r; };
  const main = rng(0x900, 0xdff), vedic = rng(0x1cd0, 0x1cff), ext = rng(0xa8e0, 0xa8ff);
  let n = `//! GENERATED by src/font/gen/gen_ucd.mjs (IndicSyllabicCategory / IndicPositionalCategory with HarfBuzz's\n//! Indic-shaper overrides). Do not edit.\n\n`;
  n += `/// (category, position) pairs referenced by the index tables.\npub const pairs = [_][2]u8{${pairs.map((k) => `.{${k & 255},${k >> 8}}`).join(",")}};\n/// U+0900..U+0DFF\npub const main = [_]u8{${main.join(",")}};\n/// U+1CD0..U+1CFF\npub const vedic = [_]u8{${vedic.join(",")}};\n/// U+A8E0..U+A8FF\npub const deva_ext = [_]u8{${ext.join(",")}};\n`;
  writeFileSync(`${out}/indic_data.zig`, n); console.log("indic pairs", pairs.length); }
