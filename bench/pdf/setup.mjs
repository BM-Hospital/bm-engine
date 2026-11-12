// Reproducible setup of bench/pdf: npm dependencies + the external tools listed in tools.json.
//
//   node bench/pdf/setup.mjs                 install what is missing, verify everything (exit 1 on any failure)
//   node bench/pdf/setup.mjs --only=qpdf,jre  some tools
//   node bench/pdf/setup.mjs --force          re-download even when a tool is present
//   node bench/pdf/setup.mjs --pin            write the SHA-256 of tools whose hash is not pinned yet (after the
//                                            publisher checksum, where one exists, matched) and the resolved
//                                            binary paths back into tools.json
//
// Rules (downloads are untrusted): each tool goes to its own directory bench/pdf/tools/<name>/; the archive is
// checked against the pinned SHA-256 in tools.json AND, when the publisher publishes a checksum, against that
// checksum fetched at setup time; archives are only extracted (Windows' bsdtar: C:\Windows\System32\tar.exe),
// nothing from them runs here except a version probe of the listed binaries; no PATH / registry / system change,
// no admin rights. npm dependencies go to bench/pdf/node_modules (`npm ci --ignore-scripts`: no install scripts).
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync, readdirSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { TOOLS_DIR, PDF_DIR, toolsManifest, findBin, dirSize } from "./lib/tools.mjs";

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const only = args.only ? String(args.only).split(",") : null;
const manifestPath = path.join(PDF_DIR, "tools.json");
const manifest = toolsManifest();
const log = (...a) => console.log(...a);
let failures = 0;
const fail = (msg) => { failures++; console.error("FAIL " + msg); };

// ---- npm dependencies ----
if (!only || only.includes("npm")) {
  const nm = path.join(PDF_DIR, "node_modules");
  const need = ["takumi-pdf", "pdfjs-dist", "@napi-rs/canvas", "@hyzyla/pdfium", "mupdf", "pngjs", "pixelmatch"];
  const missing = need.filter((p) => !existsSync(path.join(nm, ...p.split("/"), "package.json")));
  if (missing.length || args.force) {
    log(`npm: installing into bench/pdf/node_modules (missing: ${missing.join(", ") || "none, --force"})`);
    const lock = existsSync(path.join(PDF_DIR, "package-lock.json"));
    const r = spawnSync(process.platform === "win32" ? "npm.cmd" : "npm", [lock ? "ci" : "install", "--ignore-scripts", "--no-audit", "--no-fund"], { cwd: PDF_DIR, stdio: "inherit", shell: process.platform === "win32" });
    if (r.status !== 0) fail("npm install");
  }
  for (const p of need) {
    const pj = path.join(nm, ...p.split("/"), "package.json");
    if (!existsSync(pj)) { fail(`npm package ${p} missing`); continue; }
    const want = JSON.parse(readFileSync(path.join(PDF_DIR, "package.json"), "utf8")).dependencies[p];
    const have = JSON.parse(readFileSync(pj, "utf8")).version;
    if (want !== have) fail(`npm ${p}: ${have} installed, package.json pins ${want}`); else log(`ok   npm ${p}@${have}`);
  }
  // the native canvas binary package comes as an optional dependency (no install script)
  if (process.platform === "win32" && !existsSync(path.join(nm, "@napi-rs", `canvas-win32-${process.arch}-msvc`))) fail("@napi-rs/canvas has no binary for this platform");
}

// ---- external tools ----
const sha = (algo, buf) => createHash(algo).update(buf).digest("hex");
async function download(url) {
  const r = await fetch(url, { redirect: "follow", headers: { "user-agent": "bm-bench-setup" } });
  if (!r.ok) throw new Error(`HTTP ${r.status} for ${url}`);
  return Buffer.from(await r.arrayBuffer());
}
async function publisherCheck(t, buf) {
  const c = t.checksum || { kind: "none" };
  if (c.kind === "none") return { checked: false, note: c.note };
  const text = (await download(c.url)).toString("utf8");
  if (c.kind === "sha256-list" || c.kind === "sha256-file") {
    const line = c.kind === "sha256-file" ? text : text.split(/\r?\n/).find((l) => l.trim().endsWith(t.file));
    const want = (line || "").trim().split(/\s+/)[0].toLowerCase();
    const have = sha("sha256", buf);
    if (!/^[0-9a-f]{64}$/.test(want)) throw new Error(`no SHA-256 for ${t.file} in ${c.url}`);
    if (want !== have) throw new Error(`publisher SHA-256 mismatch: ${have} vs ${want} (${c.url})`);
    return { checked: true, algo: "sha256", value: want };
  }
  if (c.kind === "sha1-file") {
    const want = text.trim().split(/\s+/)[0].toLowerCase(); const have = sha("sha1", buf);
    if (want !== have) throw new Error(`publisher SHA-1 mismatch: ${have} vs ${want}`);
    return { checked: true, algo: "sha1", value: want };
  }
  if (c.kind === "github-digest") {
    const j = JSON.parse(text);
    const a = (j.assets || []).find((x) => x.name === t.file);
    const want = (a?.digest || "").replace(/^sha256:/, ""); const have = sha("sha256", buf);
    if (!want) throw new Error(`no digest for ${t.file} in ${c.url}`);
    if (want !== have) throw new Error(`GitHub asset digest mismatch: ${have} vs ${want}`);
    return { checked: true, algo: "sha256", value: want };
  }
  throw new Error("unknown checksum kind " + c.kind);
}
function extractZip(zip, dir) {
  const tar = process.platform === "win32" ? path.join(process.env.SystemRoot || "C:\\Windows", "System32", "tar.exe") : "unzip";
  const r = process.platform === "win32" ? spawnSync(tar, ["-xf", zip, "-C", dir], { encoding: "utf8" }) : spawnSync(tar, ["-q", "-o", zip, "-d", dir], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`extract failed: ${r.stderr || r.error}`);
}
const PROBE = { qpdf: ["--version"], pdfcpu: ["version"], java: ["-version"], pdfinfo: ["-v"], pdffonts: ["-v"], pdftoppm: ["-v"], pdftotext: ["-v"], mutool: ["-v"] };

let pinned = false;
for (const [name, t] of Object.entries(manifest.tools)) {
  if (only && !only.includes(name)) continue;
  const dir = path.join(TOOLS_DIR, name);
  const okFile = path.join(dir, ".ok.json");
  let ok = existsSync(okFile) ? JSON.parse(readFileSync(okFile, "utf8")) : null;
  if (ok && (ok.sha256 !== t.sha256 && t.sha256) ) ok = null;
  if (!ok || args.force) {
    try {
      log(`get  ${name} ${t.version}: ${t.url}`);
      rmSync(dir, { recursive: true, force: true });
      mkdirSync(dir, { recursive: true });
      const buf = await download(t.url);
      const pub = await publisherCheck(t, buf);
      const h = sha("sha256", buf);
      if (t.sha256 && t.sha256 !== h) throw new Error(`pinned SHA-256 mismatch: got ${h}, tools.json pins ${t.sha256}`);
      if (!t.sha256) {
        if (!args.pin) throw new Error(`no SHA-256 pinned in tools.json (got ${h}); re-run with --pin to record it`);
        t.sha256 = h; pinned = true;
      }
      const dl = path.join(dir, "download"); mkdirSync(dl, { recursive: true });
      const file = path.join(t.extract ? dl : dir, t.file);
      writeFileSync(file, buf);
      if (t.extract === "zip") { extractZip(file, dir); rmSync(dl, { recursive: true, force: true }); } // the archive's hash is recorded in .ok.json
      else rmSync(dl, { recursive: true, force: true });
      ok = { name, version: t.version, url: t.url, sha256: h, publisher: pub, bytes: buf.length, date: new Date().toISOString() };
      writeFileSync(okFile, JSON.stringify(ok, null, 1));
      log(`     ${(buf.length / 2 ** 20).toFixed(1)} MiB, sha256 ${h} ${pub.checked ? `(publisher ${pub.algo} matched)` : "(no publisher checksum: pinned hash only)"}`);
    } catch (e) { fail(`${name}: ${e.message}`); continue; }
  }
  // resolve and probe binaries
  for (const [bin, rel] of Object.entries(t.bin)) {
    const p = findBin(name, bin);
    if (!p) { fail(`${name}: ${bin} not found under ${dir} (tools.json bin ${rel})`); continue; }
    const relNow = path.relative(dir, p).split(path.sep).join("/");
    if (relNow !== rel && args.pin) { t.bin[bin] = relNow; pinned = true; }
    if (PROBE[bin]) {
      const r = spawnSync(p, PROBE[bin], { encoding: "utf8", timeout: 30000 });
      const v = ((r.stdout || "") + (r.stderr || "")).split(/\r?\n/).find((l) => l.trim()) || "";
      if (r.error) fail(`${name}: ${bin} does not run: ${r.error.message}`); else log(`ok   ${name}/${bin}: ${v.trim().slice(0, 100)}`);
    } else log(`ok   ${name}/${bin}: ${relNow}`);
  }
  log(`     ${name}: ${(dirSize(dir) / 2 ** 20).toFixed(1)} MiB on disk`);
}
if (pinned) { writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n"); log("tools.json updated (--pin)"); }
if (failures) { console.error(`setup: ${failures} failure(s)`); process.exit(1); }
log("setup: ok");
