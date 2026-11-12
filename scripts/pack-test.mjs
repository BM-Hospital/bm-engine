// End-to-end test of the npm package as users get it: `npm pack`, install the tarball into fresh projects
// and exercise every entry point.
//
//   node scripts/pack-test.mjs [--dir=<scratch dir>] [--keep] [--skip-vite] [--skip-browser] [--skip-esbuild]
//   (npm run test:pack)
//
// Steps (each one a row of the final pass / fail table):
//   manifest     js/build-manifest.json matches the wasm files (scripts/build.mjs --verify --allow-placeholders)
//   pack         npm pack: the tarball holds exactly the whitelisted files
//   install      npm i --ignore-scripts <tarball> into <dir>/app (type: module)
//   node-esm     bm-engine, /core, /standard, /full on Node: render PNG with each profile, features per
//                profile, separate instances, renderSvg, measure, init idempotency, WOFF add-on on core
//   node-cjs     a CommonJS file: await import("bm-engine"), and require("bm-engine") (require(esm), Node >= 20.19)
//   workerd-sim  node --conditions=workerd: bm-engine/core + init(WebAssembly.Module) from bm-engine/core.wasm,
//                the neutral bm-engine entry's error without an argument, loadWoff(module)
//   browser-sim  node --conditions=browser: bm-engine/core init() with no argument (file: URL fallback)
//   tsc-bundler / tsc-node16   scripts/types-test.ts against the installed typings (typescript@5)
//   vite-build   vite build of two pages (bm-engine/core + init(); bm-engine + init(full.wasm?url)) + woff add-on
//   vite-browser the built pages in headless Edge / Chrome (puppeteer-core): PNG rendered, no console errors
//   esbuild      esbuild bundles for the browser and for workerd (sanity: no node:fs import, builds cleanly; no
//                trace of the native loader in them, also for `bm-engine` itself; vite-build checks the same)
// Native addon (skipped when native/dist/<host> is not built; --skip-native skips them):
//   pack-platform          the 8 platform packages generated (scripts/npm-platform-packages.mjs --out) and packed:
//                          exact file lists, versions = root version = optionalDependencies; the main tarball has no .node
//   install-native         main tarball + npm overrides mapping every bm-engine-<name> to its tarball (= published):
//                          npm installs only the host's package (os / cpu / libc)
//   native-default         backend "native"; PNG, async render, SVG, measure byte-identical to bm-engine/full (wasm)
//   native-env             BM_ENGINE_BACKEND=wasm / =native
//   native-subpath         bm-engine/native with the addon installed
//   native-worker          4 worker_threads importing bm-engine: native in each, same bytes as the main thread
//   fallback-corrupt       the installed .node replaced by another arch's / another OS's binary, truncated, empty,
//                          text: wasm, same bytes, nothing printed; BM_ENGINE_BACKEND=native names the reason
//   esbuild-node           esbuild --platform=node: --external:bm-engine, bundled ESM, bundled CJS -> native; the CJS
//                          bundle alone (no node_modules): a clear error, and BM_WASM makes it work
//   fallback-missing       main only (optional packages unavailable): wasm, same bytes; forced native and
//                          bm-engine/native fail with clear messages
//   fallback-omit-optional npm i --omit=optional with the packages available: wasm
//   fallback-foreign-pkg   another OS's platform package force-installed (npm i --force): wasm
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync, readdirSync, statSync, copyFileSync } from "node:fs";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const dir = path.resolve(args.dir && args.dir !== true ? args.dir : path.join(os.tmpdir(), "bm-engine-pack-test"));
const app = path.join(dir, "app");
const pkg = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));
const FONT = path.join(root, "assets", "fonts", "Inter-Regular.ttf");
const WOFF2 = [path.join(root, "ref", "takumi", "assets", "fonts", "geist", "geist-latin-wght-300-800.woff2"),
  path.join(root, "src", "woff", "testdata", "geist.woff2")].find(existsSync);

const results = [];
const record = (name, ok, detail = "") => { results.push({ name, ok, detail }); console.log(`${ok === null ? "SKIP" : ok ? "PASS" : "FAIL"}  ${name}  ${detail}`); };
const q = (s) => (/[\s"&|<>^]/.test(s) ? `"${s}"` : s);
function run(cmd, argv, opts = {}) {
  // npm is a .cmd shim on Windows (needs a shell); everything else is spawned directly
  const r = cmd === "npm"
    ? spawnSync([cmd, ...argv.map(q)].join(" "), { shell: true, encoding: "utf8", maxBuffer: 64 << 20, ...opts })
    : spawnSync(cmd, argv, { encoding: "utf8", maxBuffer: 64 << 20, ...opts });
  return { ok: r.status === 0, out: (r.stdout || "") + (r.stderr || ""), status: r.status };
}
const tail = (s, n = 25) => s.trim().split("\n").slice(-n).join("\n");
/** Strings that only the Node.js side (js/native.mjs, js/wasm-file.mjs) contains: never in a browser bundle. */
const NATIVE_MARKERS = ["bm-engine-win32-x64-msvc", "bm-engine-linux-x64-gnu", "process.dlopen", "createRequire", "node:module", "BM_ENGINE_NATIVE_PATH", "readPackageWasm"];
const kb = (n) => (n / 1024).toFixed(1) + " KiB";

// ------------------------------------------------------------------ manifest + pack
{
  const r = run(process.execPath, [path.join(root, "scripts", "build.mjs"), "--verify", "--allow-placeholders"], { cwd: root });
  record("manifest", r.ok, r.ok ? "wasm files match js/build-manifest.json" : tail(r.out, 8));
}

if (!args.keep) rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });
let tarball;
let mainPack = null;
{
  const r = run("npm", ["pack", "--json", "--pack-destination", dir], { cwd: root });
  let info;
  try { info = JSON.parse(r.out.slice(r.out.indexOf("["))); } catch {}
  if (!r.ok || !info) { record("pack", false, tail(r.out)); }
  else {
    const p = info[0];
    tarball = path.join(dir, p.filename);
    const files = p.files.map((f) => f.path);
    const allowed = new Set(pkg.files);
    const stray = files.filter((f) => f !== "package.json" && !allowed.has(f));
    const required = pkg.files.filter((f) => f !== "README.vi.md");
    const missing = required.filter((f) => !files.includes(f));
    const forbidden = files.filter((f) => /^(src|bench|ref|assets|docs|playground|zig-out|examples|scripts)\//.test(f));
    // every exports target must be in the tarball
    const targets = [];
    const walk = (v) => { if (typeof v === "string") targets.push(v.replace(/^\.\//, "").replace(/\?.*$/, "")); else if (v && typeof v === "object") Object.values(v).forEach(walk); };
    walk(pkg.exports);
    const unresolved = targets.filter((t) => !files.includes(t));
    forbidden.push(...files.filter((f) => f.endsWith(".node"))); // native addons ship in the platform packages only
    mainPack = { file: p.filename, files: files.length, size: p.size, unpacked: p.unpackedSize };
    const ok =!stray.length && !missing.length && !forbidden.length && !unresolved.length;
    record("pack", ok, `${p.filename}: ${files.length} files, packed ${kb(p.size)}, unpacked ${kb(p.unpackedSize)}` +
      (stray.length ? `; unexpected: ${stray.join(", ")}` : "") + (missing.length ? `; missing: ${missing.join(", ")}` : "") +
      (forbidden.length ? `; forbidden: ${forbidden.join(", ")}` : "") + (unresolved.length ? `; exports targets not packed: ${unresolved.join(", ")}` : ""));
    console.log(p.files.map((f) => `      ${String(f.size).padStart(9)}  ${f.path}`).join("\n"));
  }
}

// ------------------------------------------------------------------ install
let installed = false;
if (tarball) {
  mkdirSync(app, { recursive: true });
  writeFileSync(path.join(app, "package.json"), JSON.stringify({ name: "bm-engine-pack-test-app", private: true, type: "module" }, null, 2));
  const r = run("npm", ["i", "--ignore-scripts", "--no-audit", "--no-fund", tarball], { cwd: app });
  installed = r.ok && existsSync(path.join(app, "node_modules", "bm-engine", "package.json"));
  record("install", installed, installed ? "node_modules/bm-engine" : tail(r.out));
}

// ------------------------------------------------------------------ test tools (one install: npm prunes --no-save packages on every later install)
let tools = { ok: false, out: "not installed" };
if (installed) {
  const want = ["typescript@5", "@types/node", ...(args["skip-vite"] ? [] : ["vite"]), ...(args["skip-esbuild"] ? [] : ["esbuild"])];
  const pptr = existsSync(path.join(root, "bench", "node_modules", "puppeteer-core", "package.json"));
  if (!pptr && !args["skip-browser"] && !args["skip-vite"]) want.push("puppeteer-core");
  tools = run("npm", ["i", "--ignore-scripts", "--no-audit", "--no-fund", "--no-save", ...want], { cwd: app });
  console.log(tools.ok ? "      test tools: " + want.join(", ") : "      test tools install FAILED: " + tail(tools.out, 5));
}

// ------------------------------------------------------------------ Node ESM
const ESM_TEST = String.raw`
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
const [fontPath, woffPath] = process.argv.slice(2);
const font = readFileSync(fontPath);
const pngSize = (b) => {
  assert.deepEqual([...b.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10], "PNG signature");
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  return [v.getUint32(16), v.getUint32(20)];
};
const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", alignItems: "center",
  justifyContent: "center", backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)" },
  children: [{ type: "text", text: "bm-engine", style: { fontFamily: "Inter", fontSize: 40, color: "white" } }] };

const main = await import("bm-engine");
const core = await import("bm-engine/core");
const standard = await import("bm-engine/standard");
const full = await import("bm-engine/full");
const log = [];
assert.match(import.meta.resolve("bm-engine"), /\/js\/node\.mjs$/);
assert.match(import.meta.resolve("bm-engine/core"), /\/js\/node-core\.mjs$/);
for (const [name, m] of Object.entries({ main, core, standard, full })) {
  const r = new m.Renderer();
  const fams = r.registerFont({ name: "Inter", data: font });
  assert.equal(fams[0].name, "Inter");
  const png = r.renderSync(node, { width: 320, height: 160 });
  assert.deepEqual(pngSize(png), [320, 160], name + " PNG size");
  const png2 = await r.render(node, { width: 64, height: 32, devicePixelRatio: 2 });
  assert.deepEqual(pngSize(png2), [64, 32], name + " width/height are output pixels at any devicePixelRatio");
  const n = Object.values(m.features).filter(Boolean).length;
  log.push(name + ": " + png.length + " B PNG, " + n + "/18 features");
  r.free();
}
const count = (m) => Object.values(m.features).filter(Boolean).length;
assert.equal(count(core), 0, "core has no optional features");
assert.equal(count(standard), 13, "standard features");
assert.equal(standard.features.renderSvg, false);
assert.equal(count(full), 18, "full has every feature");
assert.deepEqual({ ...main.features }, { ...full.features }, "bm-engine (node) = full");
assert.notEqual(core.features, full.features, "separate instances");
assert.equal(core.profile, "core"); assert.equal(full.profile, "full");
// idempotent init (concurrent + repeated, ignoring the argument once initialised)
const [e1, e2] = await Promise.all([core.init(), core.init(new Uint8Array(1))]);
assert.equal(e1, e2); assert.equal(core.initSync(), e1);
// renderSvg on full, clear error on core
const rf = new full.Renderer(); rf.registerFont({ name: "Inter", data: font });
const svg = await rf.renderSvg(node, { width: 320, height: 160 });
assert.match(svg, /^<svg[\s\S]*<\/svg>\s*$/);
const rc = new core.Renderer(); rc.registerFont({ name: "Inter", data: font });
assert.throws(() => rc.renderSvgSync(node, { width: 10, height: 10 }), /no renderSvg support/);
assert.throws(() => rc.renderSync("<div>x</div>"), /no HTML input support/);
// measure
const ms = rf.measureSync(node, { width: 320, height: 160 });
assert.equal(ms.width, 320); assert.equal(ms.children.length, 1); assert.equal(ms.transform.length, 6);
// data URL, jpeg, webp, animation on full
assert.match(rf.renderAsDataUrlSync(node, { width: 20, height: 10 }), /^data:image\/png;base64,/);
const jpg = rf.renderSync(node, { width: 20, height: 10, format: "jpeg" }); assert.equal(jpg[0], 0xff); assert.equal(jpg[1], 0xd8);
const webp = rf.renderSync(node, { width: 20, height: 10, format: "webp" }); assert.equal(String.fromCharCode(...webp.subarray(8, 12)), "WEBP");
const gif = rf.renderAnimationSync({ scenes: [{ node, durationMs: 100 }], width: 20, height: 10, fps: 10, format: "gif" });
assert.equal(String.fromCharCode(...gif.subarray(0, 6)), "GIF89a");
// WOFF add-on on core
if (woffPath) {
  const woff2 = readFileSync(woffPath);
  assert.throws(() => rc.registerFont({ name: "G", data: woff2 }), /WOFF\/WOFF2 font support/);
  const { loadWoff } = await import("bm-engine/woff");
  const res = await loadWoff();
  assert.equal(typeof res.builtIn, "boolean");
  const fams = rc.registerFont({ name: "G", data: woff2 });
  assert.equal(fams[0].name, "G");
  const p = rc.renderSync({ type: "text", text: "Geist", style: { fontFamily: "G", fontSize: 30 } }, { width: 120, height: 40 });
  assert.deepEqual(pngSize(p), [120, 40]);
  log.push("woff add-on on core: ok");
}
const disp = new full.Renderer(); disp[Symbol.dispose](); assert.throws(() => disp.renderSync(node), /freed/);
console.log(log.join("; "));
`;

if (installed) {
  writeFileSync(path.join(app, "esm-test.mjs"), ESM_TEST);
  const r = run(process.execPath, ["esm-test.mjs", FONT, WOFF2 || ""], { cwd: app });
  record("node-esm", r.ok, r.ok ? tail(r.out, 1) : tail(r.out));

  writeFileSync(path.join(app, "cjs-test.cjs"), String.raw`
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
(async () => {
  const m = await import("bm-engine");
  const r = new m.Renderer();
  r.registerFont({ name: "Inter", data: readFileSync(process.argv[2]) });
  const png = r.renderSync({ type: "text", text: "cjs", style: { fontFamily: "Inter" } }, { width: 40, height: 20 });
  assert.equal(png[1], 0x50);
  let req = "require(esm) unavailable";
  try { const c = require("bm-engine/core"); req = "require(\"bm-engine/core\") works (require(esm)): " + typeof c.Renderer; } catch (e) { req = "require() throws: " + e.code; }
  console.log("await import ok; " + req);
})().catch((e) => { console.error(e); process.exit(1); });
`);
  const c = run(process.execPath, ["cjs-test.cjs", FONT], { cwd: app });
  record("node-cjs", c.ok, c.ok ? tail(c.out, 1) : tail(c.out));

  writeFileSync(path.join(app, "workerd-test.mjs"), String.raw`
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
assert.match(import.meta.resolve("bm-engine"), /\/js\/index\.mjs$/);
assert.match(import.meta.resolve("bm-engine/core"), /\/js\/core\.mjs$/);
const neutral = await import("bm-engine");
await assert.rejects(neutral.init(), /init\(\) needs the wasm binary/);
assert.throws(() => new neutral.Renderer(), /call init/);
// what wrangler gives for  import wasm from "bm-engine/core.wasm"
const mod = await WebAssembly.compile(readFileSync(fileURLToPath(import.meta.resolve("bm-engine/core.wasm"))));
const { init, Renderer, features } = await import("bm-engine/core");
await init(mod);
assert.equal(features.css, false);
const r = new Renderer();
r.registerFont({ name: "Inter", data: readFileSync(process.argv[2]) });
const png = await r.render({ type: "text", text: "workers", style: { fontFamily: "Inter" } }, { width: 80, height: 20 });
assert.equal(png[1], 0x50);
const { loadWoff } = await import("bm-engine/woff");
await loadWoff(await WebAssembly.compile(readFileSync(fileURLToPath(import.meta.resolve("bm-engine/woff.wasm")))));
// neutral entry with a module too
await neutral.init(await WebAssembly.compile(readFileSync(fileURLToPath(import.meta.resolve("bm-engine/wasm")))));
assert.equal(neutral.features.renderSvg, true);
console.log("init(WebAssembly.Module) ok for bm-engine/core, bm-engine, bm-engine/woff");
`);
  const w = run(process.execPath, ["--conditions=workerd", "workerd-test.mjs", FONT], { cwd: app });
  record("workerd-sim", w.ok, w.ok ? tail(w.out, 1) : tail(w.out));

  writeFileSync(path.join(app, "browser-sim.mjs"), String.raw`
import assert from "node:assert/strict";
assert.match(import.meta.resolve("bm-engine/standard"), /\/js\/standard\.mjs$/);
const s = await import("bm-engine/standard");
assert.equal(s.features.css, false, "not initialised before init()");
await s.init();
assert.equal(s.features.css, true);
assert.match(String(s.wasmUrl()), /bm_engine\.standard\.wasm$/);
console.log("init() without argument loads " + String(s.wasmUrl()).split("/").pop());
`);
  const b = run(process.execPath, ["--conditions=browser", "browser-sim.mjs"], { cwd: app });
  record("browser-sim", b.ok, b.ok ? tail(b.out, 1) : tail(b.out));
}

// ------------------------------------------------------------------ TypeScript
if (installed) {
  if (!existsSync(path.join(app, "node_modules", "typescript", "package.json"))) record("tsc", false, "typescript install failed: " + tail(tools.out, 5));
  else {
    copyFileSync(path.join(root, "scripts", "types-test.ts"), path.join(app, "types-test.ts"));
    const tsv = run(process.execPath, [path.join(app, "node_modules", "typescript", "bin", "tsc"), "-v"], { cwd: app }).out.trim();
    for (const [name, module, resolution, lib, types = []] of [["tsc-bundler", "esnext", "bundler", ["es2022", "dom", "esnext.disposable"]],
      ["tsc-node16", "node16", "node16", ["es2022", "dom", "esnext.disposable"]], ["tsc-es2022-lib", "esnext", "bundler", ["es2022", "dom"]], ["tsc-node-types", "node16", "node16", ["es2022"], ["node"]]]) {
      const cfg = `tsconfig.${name}.json`;
      writeFileSync(path.join(app, cfg), JSON.stringify({ compilerOptions: { strict: true, noEmit: true, target: "es2022", module, moduleResolution: resolution,
        lib, types, skipLibCheck: false, noUnusedLocals: false }, files: ["types-test.ts"] }, null, 2));
      const r = run(process.execPath, [path.join(app, "node_modules", "typescript", "bin", "tsc"), "-p", cfg], { cwd: app });
      record(name, r.ok, r.ok ? `${tsv}, module ${module}, lib ${lib.join("+")}${types.length ? ", @types/node" : ""}` : tail(r.out, 15));
    }
  }
}

// ------------------------------------------------------------------ Vite + browser
const web = path.join(app, "web");
let viteOk = false;
if (installed && !args["skip-vite"]) {
  if (!existsSync(path.join(app, "node_modules", "vite", "package.json"))) record("vite-build", false, "vite install failed: " + tail(tools.out, 5));
  else {
    mkdirSync(path.join(web, "public"), { recursive: true });
    copyFileSync(FONT, path.join(web, "public", "Inter-Regular.ttf"));
    if (WOFF2) copyFileSync(WOFF2, path.join(web, "public", "font.woff2"));
    const page = (title, src) => `<!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="data:,"><title>${title}</title></head><body><img id="out"><script type="module" src="./${src}"></script></body></html>`;
    writeFileSync(path.join(web, "core.html"), page("core", "core.js"));
    writeFileSync(path.join(web, "main.html"), page("main", "main.js"));
    const common = String.raw`
const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#7c3aed" },
  children: [{ type: "text", text: "vite", style: { fontFamily: "Inter", fontSize: 40, color: "white" } }] };
async function decode(png) {
  const bmp = await createImageBitmap(new Blob([png], { type: "image/png" }));
  return [bmp.width, bmp.height];
}
const font = async (u) => new Uint8Array(await (await fetch(u)).arrayBuffer());
`;
    writeFileSync(path.join(web, "core.js"), common + String.raw`
import { init, Renderer, features, profile } from "bm-engine/core";
import { loadWoff } from "bm-engine/woff";
(async () => {
  try {
    await init();
    const r = new Renderer();
    r.registerFont({ name: "Inter", data: await font("/Inter-Regular.ttf") });
    const png = r.renderSync(node, { width: 300, height: 120 });
    let woff = "skipped";
    try {
      const w = await font("/font.woff2");
      if (w[0] === 0x77) { await loadWoff(); r.registerFont({ name: "G", data: w }); woff = "ok"; }
    } catch (e) { woff = "error: " + e.message; }
    document.getElementById("out").src = URL.createObjectURL(new Blob([png], { type: "image/png" }));
    window.__result = { ok: true, profile, size: await decode(png), bytes: png.length, css: features.css, woff };
  } catch (e) { window.__result = { ok: false, error: String(e && e.stack || e) }; }
})();
`);
    writeFileSync(path.join(web, "main.js"), common + String.raw`
import init, { Renderer, features } from "bm-engine";
import wasmUrl from "bm-engine/full.wasm?url";
(async () => {
  try {
    await init(wasmUrl);
    const r = new Renderer();
    r.registerFont({ name: "Inter", data: await font("/Inter-Regular.ttf") });
    const png = await r.render(node, { width: 200, height: 100 });
    const svg = r.renderSvgSync(node, { width: 200, height: 100 });
    window.__result = { ok: true, size: await decode(png), bytes: png.length, renderSvg: features.renderSvg, svg: svg.slice(0, 4) };
  } catch (e) { window.__result = { ok: false, error: String(e && e.stack || e) }; }
})();
`);
    writeFileSync(path.join(web, "vite.config.mjs"), `export default { root: ${JSON.stringify(web)}, logLevel: "warn",
  build: { outDir: "dist", emptyOutDir: true, target: "es2022", rollupOptions: { input: { core: ${JSON.stringify(path.join(web, "core.html"))}, main: ${JSON.stringify(path.join(web, "main.html"))} } } } };\n`);
    const vv = run(process.execPath, [path.join(app, "node_modules", "vite", "bin", "vite.js"), "--version"], { cwd: app }).out.trim();
    const r = run(process.execPath, [path.join(app, "node_modules", "vite", "bin", "vite.js"), "build", "--config", path.join(web, "vite.config.mjs")], { cwd: app });
    const assets = existsSync(path.join(web, "dist", "assets")) ? readdirSync(path.join(web, "dist", "assets")) : [];
    const sizes = assets.map((f) => `${f} ${kb(statSync(path.join(web, "dist", "assets", f)).size)}`);
    const wasms = assets.filter((f) => f.endsWith(".wasm"));
    viteOk = r.ok && wasms.some((f) => f.startsWith("bm_engine.core")) && wasms.some((f) => f.startsWith("bm_engine")) && wasms.some((f) => f.startsWith("bm_woff"));
    // the browser bundles must not contain the native loader or any Node.js module
    const leaks = assets.filter((f) => f.endsWith(".js")).flatMap((f) => {
      const code = readFileSync(path.join(web, "dist", "assets", f), "utf8");
      return NATIVE_MARKERS.filter((m) => code.includes(m)).map((m) => `${f}: ${m}`);
    });
    if (leaks.length) viteOk = false;
    record("vite-build", viteOk, `${vv}; assets: ${sizes.join(", ")}` + (leaks.length ? `; NATIVE LOADER IN BROWSER BUNDLE: ${leaks.join(", ")}` : "; no native loader / node: module in the bundles") +
      (r.ok ? "" : "\n" + tail(r.out)) + (/warn/i.test(r.out) ? "\n      vite output: " + tail(r.out, 6) : ""));
  }
}

async function findPuppeteer() {
  const local = [path.join(root, "bench", "node_modules", "puppeteer-core", "package.json"), path.join(app, "node_modules", "puppeteer-core", "package.json")].find(existsSync);
  if (local) return createRequire(local)("puppeteer-core");
  return null;
}

if (viteOk && !args["skip-browser"]) {
  const exe = [process.env.BROWSER_PATH, "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"].find((p) => p && existsSync(p));
  const puppeteer = exe ? await findPuppeteer() : null;
  if (!exe || !puppeteer) record("vite-browser", null, !exe ? "no Chromium-based browser found (set BROWSER_PATH)" : "puppeteer-core unavailable");
  else {
    const distDir = path.join(web, "dist");
    const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".ttf": "font/ttf", ".woff2": "font/woff2", ".css": "text/css" };
    const server = createServer((req, res) => {
      const p = path.join(distDir, decodeURIComponent(new URL(req.url, "http://x").pathname));
      if (!p.startsWith(distDir) || !existsSync(p) || statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { "content-type": types[path.extname(p)] || "application/octet-stream" });
      res.end(readFileSync(p));
    });
    await new Promise((r) => server.listen(0, "127.0.0.1", r));
    const base = `http://127.0.0.1:${server.address().port}`;
    const browser = await puppeteer.launch({ executablePath: exe, headless: true, args: ["--no-first-run", "--no-default-browser-check", "--disable-extensions"] });
    try {
      const version = await browser.version();
      for (const name of ["core", "main"]) {
        const errors = [];
        const pg = await browser.newPage();
        pg.on("console", (m) => { if (m.type() === "error") errors.push("console: " + m.text()); });
        pg.on("pageerror", (e) => errors.push("pageerror: " + e.message));
        pg.on("requestfailed", (r) => errors.push("requestfailed: " + r.url()));
        pg.on("response", (r) => { if (r.status() >= 400) errors.push(`HTTP ${r.status()} ${r.url()}`); });
        const wasmTypes = [];
        pg.on("response", (r) => { if (r.url().endsWith(".wasm")) wasmTypes.push(path.basename(new URL(r.url()).pathname) + " " + r.headers()["content-type"]); });
        await pg.goto(`${base}/${name}.html`, { waitUntil: "load" });
        await pg.waitForFunction("window.__result", { timeout: 30000 });
        const res = await pg.evaluate(() => window.__result);
        const imgOk = name !== "core" || (await pg.evaluate(() => { const i = document.getElementById("out"); return i.complete && i.naturalWidth; })) === 300;
        const expect = name === "core" ? res.ok && res.size?.[0] === 300 && res.size?.[1] === 120 && res.css === false && (!WOFF2 || res.woff === "ok")
          : res.ok && res.size?.[0] === 200 && res.size?.[1] === 100 && res.renderSvg === true && res.svg === "<svg";
        record(`vite-browser:${name}`, !!(expect && imgOk && errors.length === 0),
          `${version}; ${JSON.stringify(res)}; wasm fetched: ${wasmTypes.join(", ")}${errors.length ? "; errors: " + errors.join(" | ") : ""}`);
        await pg.close();
      }
    } finally {
      await browser.close();
      server.close();
    }
  }
}

// ------------------------------------------------------------------ esbuild (ships with vite)
if (installed && !args["skip-esbuild"]) {
  let esbuildPkg = path.join(app, "node_modules", "esbuild", "package.json");
  if (!existsSync(esbuildPkg)) record("esbuild", null, "esbuild could not be installed");
  else {
    const esbuild = createRequire(esbuildPkg)("esbuild");
    const entry = path.join(app, "esb-entry.mjs");
    writeFileSync(entry, `import { init, Renderer } from "bm-engine/core";\nimport { loadWoff } from "bm-engine/woff";\nimport * as main from "bm-engine";\nexport { init, Renderer, loadWoff, main };\n`);
    const out = [];
    let ok = true;
    for (const [label, conditions, platform] of [["browser", [], "browser"], ["workerd", ["workerd", "worker"], "neutral"]]) {
      try {
        const r = await esbuild.build({ entryPoints: [entry], bundle: true, format: "esm", platform, conditions, write: false, logLevel: "silent",
          mainFields: ["module", "main"], outfile: path.join(app, "esb-" + label + ".js") });
        const code = r.outputFiles[0].text;
        const staticFs = /^import .* from ["']node:/m.test(code);
        const leaks = NATIVE_MARKERS.filter((m) => code.includes(m));
        const warns = r.warnings.map((w) => w.text);
        if (staticFs || leaks.length) ok = false;
        out.push(`${label}: ${kb(code.length)}${staticFs ? " STATIC node: import!" : ""}${leaks.length ? " NATIVE LOADER: " + leaks.join(",") : ""}${warns.length ? " warnings: " + warns.join("; ") : ""}`);
      } catch (e) { ok = false; out.push(`${label}: ${e.message.split("\n")[0]}`); }
    }
    record("esbuild", ok, `esbuild ${esbuild.version}; ${out.join("; ")} (esbuild does not emit new URL() assets: pass the wasm to init())`);
  }
}

// ------------------------------------------------------------------ native: platform packages and install scenarios
// The platform packages are generated from native/dist (scripts/npm-platform-packages.mjs --out, so the repository's
// npm/ is not touched) and packed. "Published" is simulated with npm `overrides` mapping every bm-engine-<name>
// to its local tarball: npm then reads os / cpu / libc from the tarballs and installs only the matching one,
// exactly as from the registry. Only the host's binary can be executed.
const PROBE = String.raw`
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
const font = readFileSync(process.argv[2]);
const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 16);
const node = { type: "container", style: { display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
  backgroundImage: "linear-gradient(135deg, #f97316, #7c3aed)", borderRadius: 24 },
  children: [{ type: "text", text: "native?", style: { fontFamily: "Inter", fontSize: 40, color: "white" } }] };
const o = { width: 320, height: 160 };
const run = async (m) => {
  const r = new m.Renderer();
  r.registerFont({ name: "Inter", data: font });
  const png = r.renderSync(node, o);
  return { backend: m.backend, png: sha(png), async: sha(await r.render(node, o)), svg: sha(await r.renderSvg(node, o)),
    measure: sha(JSON.stringify(await r.measure(node, o))), features: Object.values(m.features).filter(Boolean).length };
};
const out = await run(await import(process.argv[3] || "bm-engine"));
if (process.argv[4] === "full") out.full = await run(await import("bm-engine/full"));
console.log(JSON.stringify(out));
`;
const WORKER_PROBE = String.raw`
import { Worker } from "node:worker_threads";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
const font = readFileSync(process.argv[2]);
const code = 'const { parentPort, workerData } = require("node:worker_threads");' +
  '(async () => { const m = await import("bm-engine"); const r = new m.Renderer(); r.registerFont({ name: "Inter", data: workerData });' +
  'const png = await r.render({ type: "text", text: "worker", style: { fontFamily: "Inter", fontSize: 30 } }, { width: 160, height: 40 });' +
  'parentPort.postMessage({ backend: m.backend, png }); })().catch((e) => parentPort.postMessage({ error: String(e) }));';
const m = await import("bm-engine");
const r = new m.Renderer(); r.registerFont({ name: "Inter", data: font });
const main = createHash("sha256").update(r.renderSync({ type: "text", text: "worker", style: { fontFamily: "Inter", fontSize: 30 } }, { width: 160, height: 40 })).digest("hex");
const results = await Promise.all(Array.from({ length: 4 }, () => new Promise((res, rej) => {
  const w = new Worker(code, { eval: true, workerData: font });
  w.once("message", (msg) => { w.terminate(); res(msg); });
  w.once("error", rej);
})));
const same = results.every((x) => !x.error && createHash("sha256").update(x.png).digest("hex") === main);
console.log(JSON.stringify({ main: m.backend, workers: results.map((x) => x.error || x.backend), same }));
`;
const ESB_APP = String.raw`
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { Renderer, backend } from "bm-engine";
const r = new Renderer();
r.registerFont({ name: "Inter", data: readFileSync(process.argv[2]) });
const png = r.renderSync({ type: "text", text: "bundled", style: { fontFamily: "Inter", fontSize: 30 } }, { width: 160, height: 40 });
console.log(JSON.stringify({ backend, png: createHash("sha256").update(png).digest("hex").slice(0, 16) }));
`;
const probe = (cwd, argv = [], env = {}, script = "probe.mjs") => {
  const r = spawnSync(process.execPath, [script, FONT, ...argv], { cwd, encoding: "utf8", env: { ...process.env, BM_ENGINE_BACKEND: "", BM_ENGINE_NATIVE_PATH: "", BM_WASM: "", BM_PROFILE: "", ...env } });
  let json = null;
  try { json = JSON.parse(r.stdout.trim().split("\n").pop()); } catch {}
  const stderr = (r.stderr || "").trim();
  // the thrown message (not the source excerpt Node prints above it)
  const err = (stderr.split("\n").find((l) => /^\w*Error: /.test(l)) || stderr.split("\n")[0] || "").trim();
  return { status: r.status, json, stderr, err };
};
const show = (p) => (p.json ? JSON.stringify(p.json) : `exit ${p.status}: ${p.err}`);
const installedPlatforms = (a) => (existsSync(path.join(a, "node_modules")) ? readdirSync(path.join(a, "node_modules")).filter((n) => n.startsWith("bm-engine-")) : []);
const newApp = (name, extra = {}) => {
  const a = path.join(dir, name);
  rmSync(a, { recursive: true, force: true });
  mkdirSync(a, { recursive: true });
  writeFileSync(path.join(a, "package.json"), JSON.stringify({ name: "bm-engine-" + name, private: true, type: "module", ...extra }, null, 2));
  writeFileSync(path.join(a, "probe.mjs"), PROBE);
  return a;
};

const { PLATFORMS } = await import(pathToFileURL(path.join(root, "scripts", "npm-platform-packages.mjs")).href);
const { nativeNames } = await import(pathToFileURL(path.join(root, "js", "native.mjs")).href);
const host = nativeNames()[0];
const hostBuilt = host && existsSync(path.join(root, "native", "dist", host, `bm-engine.${host}.node`));
const platformTgz = {};
const platformSizes = [];
if (!tarball || args["skip-native"]) record("native", null, args["skip-native"] ? "--skip-native" : "no main tarball");
else if (!hostBuilt) record("native", null, `native/dist/${host ?? "<none for this platform>"} is not built (npm run build:native); install scenarios skipped`);
else {
  // ---- generate + pack the platform packages
  const npmOut = path.join(dir, "npm");
  rmSync(npmOut, { recursive: true, force: true });
  const g = run(process.execPath, [path.join(root, "scripts", "npm-platform-packages.mjs"), `--out=${npmOut}`, "--allow-missing"], { cwd: root });
  const problems = g.ok ? [] : [tail(g.out, 6)];
  const tgzDir = path.join(dir, "platform-tgz");
  mkdirSync(tgzDir, { recursive: true });
  for (const name of Object.keys(PLATFORMS)) {
    if (!existsSync(path.join(npmOut, name, "package.json"))) continue;
    const r = run("npm", ["pack", "--json", "--pack-destination", tgzDir], { cwd: path.join(npmOut, name) });
    let info;
    try { info = JSON.parse(r.out.slice(r.out.indexOf("[")))[0]; } catch {}
    if (!r.ok || !info) { problems.push(`${name}: npm pack failed ${tail(r.out, 3)}`); continue; }
    const files = info.files.map((f) => f.path).sort();
    const want = ["LICENSE-APACHE", "LICENSE-MIT", "NOTICE", "README.md", "THIRD-PARTY-NOTICES.md", `bm-engine.${name}.node`, "package.json"].sort();
    if (JSON.stringify(files) !== JSON.stringify(want)) problems.push(`${name}: files ${files.join(",")}`);
    const pj = JSON.parse(readFileSync(path.join(npmOut, name, "package.json"), "utf8"));
    if (pj.version !== pkg.version || pkg.optionalDependencies?.[pj.name] !== pkg.version) problems.push(`${name}: version ${pj.version} / optionalDependency ${pkg.optionalDependencies?.[pj.name]} != ${pkg.version}`);
    platformTgz[name] = path.join(tgzDir, info.filename);
    platformSizes.push(`${name} ${kb(info.size)}`);
  }
  record("pack-platform", problems.length === 0 && platformTgz[host] !== undefined, `${Object.keys(platformTgz).length} platform tarballs: ${platformSizes.join(", ")}` +
    (mainPack ? `; main ${mainPack.file}: ${mainPack.files} files, ${kb(mainPack.size)}, no .node` : "") + (problems.length ? "; " + problems.join("; ") : ""));
}

if (platformTgz[host]) {
  const overrides = Object.fromEntries(Object.entries(platformTgz).map(([n, f]) => [`bm-engine-${n}`, "file:" + f.replace(/\\/g, "/")]));
  // ---- (a) main + platform packages "published": npm picks the host's
  const appN = newApp("app-native", { overrides });
  const inst = run("npm", ["i", "--ignore-scripts", "--no-audit", "--no-fund", tarball], { cwd: appN });
  const got = installedPlatforms(appN);
  const instOk = inst.ok && got.length === 1 && got[0] === `bm-engine-${host}`;
  record("install-native", instOk, instOk ? `npm installed only bm-engine-${host} of ${Object.keys(platformTgz).length} optional platform packages` : `installed: ${got.join(", ") || "none"}; ${tail(inst.out, 5)}`);
  let ref = null;
  if (instOk) {
    const p = probe(appN, ["bm-engine", "full"]);
    const j = p.json;
    const ok = p.status === 0 && j && j.backend === "native" && j.full.backend === "wasm" && j.png === j.async && j.png === j.full.png &&
      j.svg === j.full.svg && j.measure === j.full.measure && j.features === 18 && !p.stderr;
    ref = j;
    record("native-default", ok, ok ? `backend native; PNG / async PNG / SVG / measure byte-identical to bm-engine/full (wasm) ${j.png}` : show(p));

    // ---- (c) forcing
    const pw = probe(appN, [], { BM_ENGINE_BACKEND: "wasm" });
    const pn = probe(appN, [], { BM_ENGINE_BACKEND: "native" });
    const envOk = pw.json?.backend === "wasm" && pw.json?.png === j?.png && pn.json?.backend === "native";
    record("native-env", envOk, `BM_ENGINE_BACKEND=wasm -> ${show(pw)}; =native -> ${pn.json?.backend ?? show(pn)}`);

    // ---- (d) bm-engine/native present
    const ps = probe(appN, ["bm-engine/native"]);
    record("native-subpath", ps.json?.backend === "native" && ps.json?.png === j?.png, `bm-engine/native with the addon: ${show(ps)}`);

    // ---- (g) worker_threads
    writeFileSync(path.join(appN, "worker-probe.mjs"), WORKER_PROBE);
    const pwk = probe(appN, [], {}, "worker-probe.mjs");
    record("native-worker", pwk.json?.main === "native" && pwk.json.workers.every((b) => b === "native") && pwk.json.same === true, show(pwk));

    // ---- (e) corrupted / incompatible .node in the installed platform package -> wasm, silently
    const target = path.join(appN, "node_modules", `bm-engine-${host}`, `bm-engine.${host}.node`);
    const good = readFileSync(target);
    const [hostOs, hostArch] = [PLATFORMS[host].os, PLATFORMS[host].cpu];
    const pickFile = (pred) => { const n = Object.keys(platformTgz).find((x) => x !== host && pred(PLATFORMS[x])); return n ? [n, readFileSync(path.join(dir, "npm", n, `bm-engine.${n}.node`))] : null; };
    const wrongArch = pickFile((q) => q.os === hostOs && q.cpu !== hostArch);
    const otherOs = pickFile((q) => q.os !== hostOs && q.cpu === hostArch);
    const cases = [
      ...(wrongArch ? [[`wrong arch (${wrongArch[0]} binary)`, wrongArch[1]]] : []),
      ...(otherOs ? [[`other OS (${otherOs[0]} binary)`, otherOs[1]]] : []),
      ["truncated (first 64 KiB)", good.subarray(0, 65536)],
      ["empty file", new Uint8Array(0)],
      ["text file", Buffer.from("not a shared library\n")],
    ];
    const rows = [];
    let corruptOk = true;
    try {
      for (const [label, bytes] of cases) {
        writeFileSync(target, bytes);
        const pc = probe(appN);
        const pf = probe(appN, [], { BM_ENGINE_BACKEND: "native" });
        const ok = pc.status === 0 && pc.json?.backend === "wasm" && pc.json.png === j?.png && !pc.stderr &&
          pf.status !== 0 && new RegExp(`BM_ENGINE_BACKEND=native, but the native addon is not available \\(bm-engine-${host}: `).test(pf.stderr);
        if (!ok) corruptOk = false;
        rows.push(`${label}: ${ok ? "wasm, same bytes, silent" : "FAILED " + show(pc) + " / forced: " + pf.err}`);
      }
    } finally {
      writeFileSync(target, good);
    }
    record("fallback-corrupt", corruptOk, rows.join("; "));

    // ---- (f) esbuild --platform=node bundles of an app importing bm-engine
    const esbuildPkg = path.join(app, "node_modules", "esbuild", "package.json");
    if (args["skip-esbuild"] || !existsSync(esbuildPkg)) record("esbuild-node", null, "esbuild not installed");
    else {
      const esbuild = createRequire(esbuildPkg)("esbuild");
      writeFileSync(path.join(appN, "esb-app.mjs"), ESB_APP);
      const rows = [];
      let ok = true;
      const variants = [["--external:bm-engine, esm", { format: "esm", external: ["bm-engine"] }, "dist/ext.mjs", "native"],
        ["bundled, esm", { format: "esm" }, "dist/bundle.mjs", "native"],
        ["bundled, cjs", { format: "cjs" }, "dist/bundle.cjs", "native"]];
      for (const [label, o, out, want] of variants) {
        try {
          const b = await esbuild.build({ entryPoints: [path.join(appN, "esb-app.mjs")], bundle: true, platform: "node", outfile: path.join(appN, out), logLevel: "silent", ...o });
          const pr = probe(appN, [], {}, out);
          const good = pr.status === 0 && pr.json?.backend === want && !pr.stderr;
          if (!good) ok = false;
          rows.push(`${label}: ${show(pr)}${b.warnings.length ? " (esbuild warnings: " + b.warnings.map((w) => w.text).join("; ") + ")" : ""}`);
        } catch (e) { ok = false; rows.push(`${label}: build error ${e.message.split("\n")[0]}`); }
      }
      // the CommonJS bundle alone in a directory without node_modules: no addon, no wasm file -> a clear error, not a crash
      const lone = path.join(dir, "lone-bundle");
      rmSync(lone, { recursive: true, force: true });
      mkdirSync(lone, { recursive: true });
      if (existsSync(path.join(appN, "dist", "bundle.cjs"))) {
        copyFileSync(path.join(appN, "dist", "bundle.cjs"), path.join(lone, "bundle.cjs"));
        const pl = probe(lone, [], {}, "bundle.cjs");
        const clear = pl.status !== 0 && /cannot find bm_engine\.wasm .*keep the package external/.test(pl.stderr);
        if (!clear) ok = false;
        rows.push(`cjs bundle without node_modules: ${clear ? "clear error (cannot find bm_engine.wasm ... keep the package external)" : show(pl)}`);
        const pe = probe(lone, [], { BM_WASM: path.join(root, "js", "bm_engine.wasm") }, "bundle.cjs");
        if (pe.json?.backend !== "wasm") ok = false;
        rows.push(`same + BM_WASM: ${show(pe)}`);
      }
      record("esbuild-node", ok, rows.join("; "));
    }
  }

  // ---- (b) main only: the optional packages are missing (here: never published -> 404, as on an unsupported platform)
  if (installed) {
    writeFileSync(path.join(app, "probe.mjs"), PROBE);
    const pm = probe(app);
    const pf = probe(app, [], { BM_ENGINE_BACKEND: "native" });
    const ps = probe(app, ["bm-engine/native"]);
    const ok = installedPlatforms(app).length === 0 && pm.status === 0 && pm.json?.backend === "wasm" && (!ref || pm.json.png === ref.png) && !pm.stderr &&
      pf.status !== 0 && new RegExp(`BM_ENGINE_BACKEND=native, but the native addon is not available \\(bm-engine-${host}: not installed`).test(pf.stderr) &&
      ps.status !== 0 && new RegExp(`bm-engine/native: the native addon is not available .*Install the optional package bm-engine-${host}`).test(ps.stderr);
    record("fallback-missing", ok, `no platform package: ${show(pm)}${ref && pm.json?.png === ref.png ? " (same bytes as native)" : ""}; forced native: ${pf.err}; bm-engine/native: ${ps.err.slice(0, 200)}`);
  }

  // ---- (b) --omit=optional with the packages available
  const appO = newApp("app-omit", { overrides });
  const io = run("npm", ["i", "--ignore-scripts", "--no-audit", "--no-fund", "--omit=optional", tarball], { cwd: appO });
  const po = io.ok ? probe(appO) : null;
  record("fallback-omit-optional", io.ok && installedPlatforms(appO).length === 0 && po?.json?.backend === "wasm" && !po.stderr,
    io.ok ? `npm i --omit=optional: platform packages ${installedPlatforms(appO).join(", ") || "none"}; ${show(po)}` : tail(io.out, 5));

  // ---- (e) a platform package of another OS force-installed (and the host's missing)
  const foreign = Object.keys(platformTgz).find((n) => PLATFORMS[n].os !== PLATFORMS[host].os);
  if (foreign) {
    const appF = newApp("app-foreign");
    const fi = run("npm", ["i", "--ignore-scripts", "--no-audit", "--no-fund", "--force", tarball, platformTgz[foreign]], { cwd: appF });
    const pff = fi.ok ? probe(appF) : null;
    record("fallback-foreign-pkg", fi.ok && installedPlatforms(appF).includes(`bm-engine-${foreign}`) && pff?.json?.backend === "wasm" && !pff.stderr,
      fi.ok ? `npm i --force bm-engine-${foreign}: installed ${installedPlatforms(appF).join(", ")}; ${show(pff)}` : tail(fi.out, 5));
  }
}

// ------------------------------------------------------------------ summary
const w =Math.max(...results.map((r) => r.name.length));
console.log("\n| test | result | detail |\n|:--|:--|:--|");
for (const r of results) console.log(`| ${r.name.padEnd(w)} | ${r.ok === null ? "SKIP" : r.ok ? "PASS" : "FAIL"} | ${r.detail.split("\n")[0].replace(/\|/g, "/")} |`);
const failed = results.filter((r) => r.ok === false);
console.log(`\n${results.length - failed.length}/${results.length} passed (or skipped)${failed.length ? "; FAILED: " + failed.map((r) => r.name).join(", ") : ""}. Scratch: ${dir}`);
process.exit(failed.length ? 1 : 0);
