// Existing checkouts use the committed corpus offline. Fetch only to bootstrap an absent corpus.
import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { MANIFEST, REVISION, importCorpus, verifyCorpus } from "./takumi-test-corpus.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ref = path.join(root, "ref", "takumi");
const revision = REVISION;
const git = (args) => execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
if (existsSync(MANIFEST)) {
  verifyCorpus();
} else {
  if (!existsSync(ref)) {
    git(["clone", "--depth", "1", "https://github.com/kane50613/takumi.git", ref]);
    if (git(["-C", ref, "rev-parse", "HEAD"]) !== revision) {
      git(["-C", ref, "fetch", "--depth", "1", "origin", revision]);
      git(["-C", ref, "checkout", "--detach", revision]);
    }
  }
  const actual = git(["-C", ref, "rev-parse", "HEAD"]);
  if (actual !== revision) throw new Error(`Existing ref/takumi is ${actual}; expected ${revision}. Keep it intact and select the reference revision manually.`);
  importCorpus(ref);
}
console.log("Run: npm run build:pdf; npm run test:pdf:takumi");
