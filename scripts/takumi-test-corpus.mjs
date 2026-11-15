// Import or verify the vendored upstream test corpus. No upstream code is executed.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const TAKUMI_TESTS = path.join(ROOT, "tests", "upstream", "takumi");
export const MANIFEST = path.join(ROOT, "tests", "upstream", "takumi.manifest.json");
export const REVISION = "ff9a5d411310c8cdd1ac76a4f106c123d309e0a4";
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");

export function verifyCorpus() {
  const manifest = JSON.parse(readFileSync(MANIFEST, "utf8"));
  if (manifest.revision !== REVISION) throw new Error("Unexpected Takumi corpus revision");
  for (const file of manifest.files) {
    const bytes = readFileSync(path.join(TAKUMI_TESTS, file.path));
    if (bytes.length !== file.bytes || digest(bytes) !== file.sha256) throw new Error(`Changed upstream fixture: ${file.path}`);
  }
  console.log(`Verified ${manifest.files.length} vendored Takumi files (${(manifest.files.reduce((n, f) => n + f.bytes, 0) / 1048576).toFixed(2)} MiB), revision ${manifest.revision}.`);
  return manifest;
}

export function importCorpus(ref) {
  const git = (args, extra = {}) => execFileSync("git", ["-C", ref, ...args], { maxBuffer: 128 * 1048576, ...extra });
  if (git(["rev-parse", "HEAD"]).toString().trim() !== REVISION) throw new Error(`Expected Takumi ${REVISION}`);
  const tracked = git(["ls-files", "-z"]).toString().split("\0").filter(Boolean).sort();
  const selected = tracked.filter((file) =>
    /(^|\/)(tests|__tests__|__snapshots__|testdata|e2e|fixtures(?:-[^/]+)?)(\/|$)/.test(file) ||
    file.startsWith("assets/") ||
    /(^|\/)[^/]*[.-](test|spec)\.[^/]+$/.test(file) ||
    /(^|\/)[^/]*(test|spec)[^/]*\.(rs|ts|tsx|js|mjs|cjs)$/.test(file) ||
    /(^|\/)(LICENSE[^/]*|NOTICE[^/]*|THIRD-PARTY-NOTICES\.md|OFL[^/]*)$/.test(file) ||
    (file.endsWith(".rs") && /#\s*\[\s*(cfg\s*\(\s*test\b|(?:\w+::)*test\b)/.test(readFileSync(path.join(ref, file), "utf8"))));
  // Read canonical Git blobs in one batch, preserving binary bytes and upstream line endings.
  const blobs = git(["cat-file", "--batch"], { input: selected.map((file) => `${REVISION}:${file}\n`).join("") });
  let offset = 0;
  const files = [];
  for (const file of selected) {
    const end = blobs.indexOf(10, offset);
    const header = blobs.subarray(offset, end).toString();
    const match = /^[0-9a-f]+ blob (\d+)$/.exec(header);
    if (!match) throw new Error(`Cannot read upstream blob: ${file}: ${header}`);
    const size = Number(match[1]);
    const bytes = blobs.subarray(end + 1, end + 1 + size);
    offset = end + 1 + size + 1;
    const dest = path.join(TAKUMI_TESTS, file);
    if (existsSync(dest) && !readFileSync(dest).equals(bytes)) throw new Error(`Refusing to overwrite modified fixture: ${file}`);
    mkdirSync(path.dirname(dest), { recursive: true });
    writeFileSync(dest, bytes);
    files.push({ path: file, bytes: size, sha256: digest(bytes) });
  }
  writeFileSync(MANIFEST, JSON.stringify({ repository: "https://github.com/kane50613/takumi", revision: REVISION, files }, null, 2) + "\n");
  return verifyCorpus();
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  if (process.argv[2] === "--import") importCorpus(path.resolve(process.argv[3] || path.join(ROOT, "ref", "takumi")));
  else verifyCorpus();
}
