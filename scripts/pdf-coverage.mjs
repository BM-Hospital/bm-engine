// Case inventory, separate from golden equivalence and instrumented code coverage.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import path from "node:path";
import { ROOT, TAKUMI_TESTS, REVISION, verifyCorpus } from "./takumi-test-corpus.mjs";
import { goldenFixtures } from "../bench/pdf/corpus/golden.mjs";

const manifest = verifyCorpus();
const mapFile = path.join(ROOT, "scripts", "pdf-coverage-map.json");
const previous = existsSync(mapFile) ? JSON.parse(readFileSync(mapFile, "utf8")) : null;
if (previous && previous.revision !== REVISION) throw new Error("Coverage map revision changed; review its case mappings");
const saved = new Map((previous?.cases || []).map((c) => [c.id, c]));
const savedJs = new Map((previous?.javascriptCases || []).map(c => [c.id, c]));
const { fixtures, reason } = await goldenFixtures();
if (!fixtures.length) throw new Error(reason || "No golden adapters loaded");
const names = new Set(fixtures.map((f) => f.fixture));

// Find a Rust function's closing brace, ignoring strings, raw strings and nested comments.
function bodyEnd(s, start) {
  let depth = 0;
  for (let i = start; i < s.length; i++) {
    if (s.startsWith("//", i)) { i = s.indexOf("\n", i); if (i < 0) return s.length; continue; }
    if (s.startsWith("/*", i)) {
      let comments = 1; i += 2;
      while (i < s.length && comments) {
        if (s.startsWith("/*", i)) { comments++; i += 2; }
        else if (s.startsWith("*/", i)) { comments--; i += 2; }
        else i++;
      }
      i--; continue;
    }
    const raw = /^r(#{0,32})"/.exec(s.slice(i, i + 35));
    if (raw) { const end = s.indexOf('"' + raw[1], i + raw[0].length); if (end < 0) throw new Error("Unclosed raw string"); i = end + raw[1].length; continue; }
    if (s[i] === '"' || (s[i] === "'" && /^'(?:\\.|[^'\\\r\n])'/.test(s.slice(i, i + 12)))) {
      const quote = s[i++];
      while (i < s.length && s[i] !== quote) { if (s[i] === "\\") i++; i++; }
      continue;
    }
    if (s[i] === "{") depth++;
    else if (s[i] === "}" && --depth === 0) return i + 1;
  }
  throw new Error("Unclosed Rust test body");
}

const cases = [];
for (const file of manifest.files) {
  if (!file.path.startsWith("takumi-pdf/") || !file.path.endsWith(".rs")) continue;
  const source = readFileSync(path.join(TAKUMI_TESTS, file.path), "utf8");
  for (const attribute of source.matchAll(/#\s*\[\s*test\s*\]/g)) {
    const rest = source.slice(attribute.index + attribute[0].length);
    const fn = /\bfn\s+(\w+)\s*\(/.exec(rest);
    if (!fn) throw new Error(`Test without function: ${file.path}`);
    const fnStart = attribute.index + attribute[0].length + fn.index;
    const start = source.indexOf("{", fnStart);
    const end = bodyEnd(source, start);
    const body = source.slice(start, end);
    const goldens = [...body.matchAll(/run_pdf_fixture(?:_with)?\s*\(\s*"([^"]+)"/g)].map((m) => m[1]).filter((name) => names.has(name));
    const line = source.slice(0, fnStart).split("\n").length;
    const id = `${file.path}:${line}:${fn[1]}`;
    const existing = saved.get(id);
    const internal = /\/(?:krilla|subsetter)\//.test(file.path);
    const continuation = /(?:streaming_tests|memory_tests|window_scenes)\.rs$/.test(file.path);
    cases.push({ id, source: file.path, line, name: fn[1], sourceSha256: file.sha256,
      status: existing?.status || (goldens.length ? "golden-adapter" : internal ? "internal-review" : "pending-adapter"),
      adapters: existing?.adapters || goldens.map((name) => `node scripts/pdf-compare.mjs --strict ${name}`),
      reason: existing?.reason || (goldens.length ? "Golden adapters cover rendered output; Rust-specific assertions still require review."
        : continuation ? "Continuation/window/live-memory assertions need dedicated Zig adapters (plan 16–21)."
        : internal ? "Rust implementation internals differ; review observable invariants before declaring N/A."
        : "No case-level adapter verified yet; do not count as executed coverage."),
    });
  }
}
for (const id of saved.keys()) if (!cases.some((c) => c.id === id)) throw new Error(`Stale coverage case: ${id}`);
// Bun test declarations in the PDF wrapper and shared preparation facade. These are
// inventories of source declarations, not a claim that the Bun suite ran against bm.
const javascriptCases = [];
for (const file of manifest.files) {
  if (!/^takumi-pdf-js\/tests\/.*\.test\.tsx?$/.test(file.path) &&
      !/^takumi-(?:bindings-js|helpers)\/tests\/(?:renderer-facade|prepare-images)\.test\.ts$/.test(file.path)) continue;
  const source = readFileSync(path.join(TAKUMI_TESTS, file.path), 'utf8');
  for (const call of source.matchAll(/\b(?:test|it)(?:\.(?:only|skip|todo))?\s*\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g)) {
    const line = source.slice(0, call.index).split('\n').length;
    const name = call[1].slice(1, -1);
    const id = `${file.path}:${line}:${name}`;
    const existing = savedJs.get(id);
    javascriptCases.push({ id, source: file.path, line, name, sourceSha256: file.sha256,
      status: existing?.status || 'pending-adapter', adapters: existing?.adapters || [],
      reason: existing?.reason || 'Public PDF/shared resource preparation contract; case assertions need an explicit bm runner mapping.' });
  }
}
for (const id of savedJs.keys()) if (!javascriptCases.some(c => c.id === id)) throw new Error(`Stale JavaScript coverage case: ${id}`);
const result = { revision: REVISION, meaning: "Static Rust and JavaScript test declarations, not runtime cases or code coverage. No pending adapter counts as executed coverage.",
  goldenAdapters: fixtures.map((f) => ({ name: f.fixture, runner: `node scripts/pdf-compare.mjs --strict ${f.fixture}` })),
  featureAudits: [{ feature: 'SVG-in-OpenType glyph painting', status: 'not-applicable',
    reason: 'Pinned public PDF API falls back to outlines. SerializeSettings.render_svg_glyph_fn defaults to None; the PDF emitter does not replace it.',
    source: 'takumi-pdf/src/krilla/serialize.rs:156',
    adapter: 'node scripts/pdf-audit/run.mjs --strict fonts.svg-opentype-outline-fallback',
    evidence: 'Valid SVG-table font with conspicuous alternate paint; reference and bm emit outline curves, with no SVG rectangle paint and matching extraction.' }],
  cases, javascriptCases };
const encoded = JSON.stringify(result, null, 2) + "\n";
if (process.argv.includes("--check")) {
  if (!previous || readFileSync(mapFile, "utf8").replace(/\r\n/g, "\n") !== encoded) throw new Error("Coverage inventory changed: regenerate and review scripts/pdf-coverage-map.json");
} else writeFileSync(mapFile, encoded);
const counts = Object.groupBy(cases, (c) => c.status);
console.log(`${cases.length} Rust test declarations; ${fixtures.length} golden adapters. ${Object.entries(counts).map(([k, v]) => `${k}: ${v.length}`).join(", ")}.`);
console.log(`${javascriptCases.length} JavaScript test declarations; ${javascriptCases.filter(c => c.status === 'verified').length} mapped and verified.`);
if (process.argv.includes("--strict") && [...cases, ...javascriptCases].some((c) => c.status !== "verified" && c.status !== "not-applicable")) process.exitCode = 1;
