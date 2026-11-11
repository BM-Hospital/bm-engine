// Release build of every profile: `zig build -Dprofile=<p>` (optimize=small) + `wasm-opt -Oz`, plus the
// packaging manifest.
//
//   node scripts/build.mjs                    core + standard + full + the WOFF add-on
//   node scripts/build.mjs --profile=core     one profile only (core | standard | full)
//   node scripts/build.mjs -- -Dtables=false  extra zig build options (applied to every profile; the result
//                                             is marked "custom" in the manifest and cannot be published)
//   node scripts/build.mjs --manifest         only (re)write js/build-manifest.json from the wasm files in js/
//   node scripts/build.mjs --verify           check the four wasm files in js/ against js/build-manifest.json
//                                             and the package.json placeholders (prepublishOnly); exits 1 with
//                                             instructions on mismatch (--allow-placeholders skips the latter)
//   node scripts/build.mjs --test             `zig build test` (npm test)
//   (ZIG=<path to zig> overrides the compiler location; wasm-opt comes from the `binaryen` dev dependency,
//    looked up in ./node_modules then bench/node_modules)
//
// Outputs: js/bm_engine.core.wasm, js/bm_engine.standard.wasm, js/bm_engine.wasm (= full, every feature),
// js/bm_woff.wasm (add-on, see js/addons.mjs), zig-out/bin/bm_engine.wasm (= full, optimised),
// js/build-manifest.json (per file: profile, bytes, sha256, feature bits; git describe; zig version) and a
// size table (raw / gzip -9 / brotli q11) printed and written to bench/out/sizes.json.
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, existsSync, statSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { gzipSync, brotliCompressSync, constants } from "node:zlib";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const argv = process.argv.slice(2);
const dd = argv.indexOf("--");
const extra = dd >= 0 ? argv.slice(dd + 1) : [];
const opts = Object.fromEntries((dd >= 0 ? argv.slice(0, dd) : argv).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const ALL = ["core", "standard", "full"];

/** Published binaries: js/<file> per profile (+ the add-on). */
const FILES = { core: "bm_engine.core.wasm", standard: "bm_engine.standard.wasm", full: "bm_engine.wasm", woff: "bm_woff.wasm" };
/** `bm_features()` of each canonical profile (bit order: src/config.zig `feature_bits`, js/engine.mjs FEATURE_NAMES). */
const EXPECTED_FEATURES = { core: 0x0, standard: 0x1fff, full: 0x3ffff };
const MANIFEST = path.join(root, "js", "build-manifest.json");
const rel = (p) => path.relative(root, p).split(path.sep).join("/");
const sha256 = (b) => createHash("sha256").update(b).digest("hex");

function gitDescribe() {
  const r = spawnSync("git", ["describe", "--always", "--dirty", "--tags"], { cwd: root, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : null;
}

/** Instantiates an engine binary (no imports) and reads its feature mask. */
function featureMask(bytes) {
  const { exports } = new WebAssembly.Instance(new WebAssembly.Module(bytes), {});
  return typeof exports.bm_features === "function" ? exports.bm_features() >>> 0 : null;
}

function readManifest() {
  try { return JSON.parse(readFileSync(MANIFEST, "utf8")); } catch { return null; }
}

function fileEntry(key, custom) {
  const file = path.join(root, "js", FILES[key]);
  const b = readFileSync(file);
  const e = { file: rel(file), bytes: b.length, sha256: sha256(b) };
  if (key !== "woff") {
    const m = featureMask(b);
    e.profile = key;
    e.features = m == null ? null : "0x" + m.toString(16);
    e.custom = !!custom || m !== EXPECTED_FEATURES[key];
  }
  return e;
}

function writeManifest(keys, { custom = false, zigVersion = null } = {}) {
  const prev = readManifest() || {};
  const files = { ...(prev.files || {}) };
  for (const k of keys) if (existsSync(path.join(root, "js", FILES[k]))) files[k] = fileEntry(k, custom);
  const pkg = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));
  const m = {
    package: pkg.name,
    version: pkg.version,
    date: new Date().toISOString(),
    git: gitDescribe(),
    zig: zigVersion ?? prev.zig ?? null,
    files,
  };
  writeFileSync(MANIFEST, JSON.stringify(m, null, 2) + "\n");
  console.log(`written ${rel(MANIFEST)}`);
  return m;
}

/** Returns a list of problems (empty = publishable). */
function verify() {
  const problems = [];
  const m = readManifest();
  if (!m) return [`${rel(MANIFEST)} is missing`];
  for (const k of Object.keys(FILES)) {
    const file = path.join(root, "js", FILES[k]);
    const e = m.files && m.files[k];
    if (!existsSync(file)) { problems.push(`js/${FILES[k]} is missing`); continue; }
    if (!e) { problems.push(`js/${FILES[k]} has no manifest entry`); continue; }
    const now = fileEntry(k, false);
    if (now.bytes !== e.bytes || now.sha256 !== e.sha256) problems.push(`js/${FILES[k]} changed since the manifest was written (${e.bytes} -> ${now.bytes} bytes)`);
    if (k !== "woff") {
      if (now.features !== "0x" + EXPECTED_FEATURES[k].toString(16)) problems.push(`js/${FILES[k]} has feature bits ${now.features}, the ${k} profile needs 0x${EXPECTED_FEATURES[k].toString(16)} (custom build?)`);
      if (e.custom) problems.push(`js/${FILES[k]} was built with custom options (${(e.extraArgs || []).join(" ") || "non-default flags"})`);
    }
  }
  const pkg = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));
  if (m.version !== pkg.version) problems.push(`manifest version ${m.version} != package.json version ${pkg.version} (run "node scripts/build.mjs --manifest" after bumping)`);
  if (!opts["allow-placeholders"]) {
    const text = JSON.stringify({ author: pkg.author, homepage: pkg.homepage, repository: pkg.repository, bugs: pkg.bugs });
    if (/OWNER|AUTHOR_NAME/.test(text)) problems.push("package.json still has the OWNER / AUTHOR_NAME placeholders (author, homepage, repository, bugs)");
  }
  return problems;
}

if (opts.verify) {
  const problems = verify();
  if (problems.length) {
    console.error("bm-engine: the package is not ready to publish:\n  - " + problems.join("\n  - ") +
      "\nWasm problems: rebuild with `npm run build` (needs Zig 0.17), or, if the binaries in js/ are the intended release" +
      " builds, record them with `node scripts/build.mjs --manifest`. Placeholders: edit package.json. Then retry.");
    process.exit(1);
  }
  const m = readManifest();
  console.log(`bm-engine: wasm binaries match ${rel(MANIFEST)} (git ${m.git ?? "?"}, zig ${m.zig ?? "?"})`);
  for (const [k, e] of Object.entries(m.files)) console.log(`  ${k.padEnd(8)} ${e.file.padEnd(28)} ${String(e.bytes).padStart(8)} B  sha256 ${e.sha256.slice(0, 16)}  ${e.features ?? ""}`);
  process.exit(0);
}

if (opts.manifest) {
  const defZig = "C:/Users/admini/Downloads/zig-x86_64-windows-0.17.1/zig-x86_64-windows-0.17.1/zig.exe";
  const z = spawnSync(process.env.ZIG || (existsSync(defZig) ? defZig : "zig"), ["version"], { encoding: "utf8" });
  writeManifest(Object.keys(FILES), { zigVersion: z.status === 0 ? z.stdout.trim() + " (binaries recorded by --manifest, not rebuilt)" : null });
  process.exit(0);
}

// ---- needs Zig from here on ----
const defaultZig = "C:/Users/admini/Downloads/zig-x86_64-windows-0.17.1/zig-x86_64-windows-0.17.1/zig.exe";
const zig = process.env.ZIG || (existsSync(defaultZig) ? defaultZig : "zig");
const zv = spawnSync(zig, ["version"], { encoding: "utf8" });
if (zv.error || zv.status !== 0) {
  console.error(`bm-engine: Zig not found (tried \`${zig}\`). Building the wasm needs Zig 0.17.x: install it from` +
    " https://ziglang.org/download/ and put it on PATH, or set ZIG=<path to the zig executable>." +
    "\n(The npm package ships prebuilt wasm files; you only need Zig to rebuild them.)");
  process.exit(1);
}
const zigVersion = zv.stdout.trim();
if (!zigVersion.startsWith("0.17.")) console.warn(`warning: Zig ${zigVersion} found; bm-engine targets 0.17.x`);

if (opts.test) {
  const r = spawnSync(zig, ["build", "test", "--summary", "all"], { cwd: root, stdio: "inherit" });
  process.exit(r.status ?? 1);
}

const profiles = opts.profile ? String(opts.profile).split(",") : ALL;
for (const p of profiles) if (!ALL.includes(p)) throw new Error(`unknown profile ${p} (core | standard | full)`);

const wasmOpt = [path.join(root, "node_modules", "binaryen", "bin", "wasm-opt"), path.join(root, "bench", "node_modules", "binaryen", "bin", "wasm-opt")].find(existsSync);
if (!wasmOpt) console.warn("wasm-opt not found (run `npm i --ignore-scripts` in the repository root); shipping unoptimised binaries");
function optimise(file) {
  if (!wasmOpt) return;
  execFileSync(process.execPath, [wasmOpt, file, "-Oz", "--enable-simd", "--enable-bulk-memory", "--enable-sign-ext",
    "--enable-nontrapping-float-to-int", "--enable-mutable-globals", "-o", file], { cwd: root, stdio: "inherit" });
}
const sizes = (b) => ({
  raw: b.length,
  gzip9: gzipSync(b, { level: 9 }).length,
  brotli: brotliCompressSync(b, { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_SIZE_HINT]: b.length } }).length,
});

const rows = {};
const built = [];
for (const p of profiles) {
  // full builds into zig-out (the default prefix every tool reads); the others into their own prefix
  const prefix = p === "full" ? path.join(root, "zig-out") : path.join(root, "zig-out", "profiles", p);
  execFileSync(zig, ["build", `-Dprofile=${p}`, "-p", prefix, ...extra], { cwd: root, stdio: "inherit" });
  const out = path.join(prefix, "bin", "bm_engine.wasm");
  const zigBytes = statSync(out).size;
  optimise(out);
  const dest = path.join(root, "js", FILES[p]);
  copyFileSync(out, dest);
  built.push(p);
  rows[p] = { file: rel(dest), zig: zigBytes, ...sizes(readFileSync(dest)) };
  if (p === "full" || !rows.woffAddon) {
    const w = path.join(prefix, "bin", "bm_woff.wasm");
    if (existsSync(w)) {
      const zw = statSync(w).size;
      optimise(w);
      copyFileSync(w, path.join(root, "js", FILES.woff));
      if (!built.includes("woff")) built.push("woff");
      rows.woffAddon = { file: "js/" + FILES.woff, zig: zw, ...sizes(readFileSync(w)) };
    }
  }
}

writeManifest(built, { custom: extra.length > 0, zigVersion });
if (extra.length) {
  const m = readManifest();
  for (const k of built) if (m.files[k] && k !== "woff") m.files[k].extraArgs = extra;
  writeFileSync(MANIFEST, JSON.stringify(m, null, 2) + "\n");
}

const takumiPath = path.join(root, "bench", "node_modules", "@takumi-rs", "wasm", "pkg", "takumi_wasm_bg.wasm");
if (existsSync(takumiPath)) rows["takumi-wasm 2.20"] = { file: "bench/node_modules/@takumi-rs/wasm/pkg/takumi_wasm_bg.wasm", zig: null, ...sizes(readFileSync(takumiPath)) };

const kib = (n) => (n == null ? "-" : (n / 1024).toFixed(1));
console.log("\n| build | zig .small KiB | wasm-opt -Oz KiB | gzip -9 KiB | brotli KiB |\n|:--|--:|--:|--:|--:|");
for (const [k, r] of Object.entries(rows)) console.log(`| ${k} | ${kib(r.zig)} | ${kib(r.raw)} | ${kib(r.gzip9)} | ${kib(r.brotli)} |`);
const outDir = path.join(root, "bench", "out");
mkdirSync(outDir, { recursive: true });
const file = path.join(outDir, "sizes.json");
let prev = {};
try { prev = JSON.parse(readFileSync(file, "utf8")); } catch {}
writeFileSync(file, JSON.stringify({ date: new Date().toISOString(), extraArgs: extra, builds: { ...(prev.builds || {}), ...rows } }, null, 2));
console.log(`\nwritten ${rel(file)}`);
