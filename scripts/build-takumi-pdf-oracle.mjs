// Build the pinned upstream reference without changing the source or vendored test corpus.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { ROOT, REVISION } from "./takumi-test-corpus.mjs";

const source = path.resolve(ROOT, "ref", "takumi");
const out = path.resolve(ROOT, "bench", "out", "pdf-oracle");
const image = "rust:1.91-bookworm@sha256:c1e5f19e773b7878c3f7a805dd00a495e747acbdc76fb2337a4ebf0418896b33";
const git = (...args) => execFileSync("git", ["-C", source, ...args], { encoding: "utf8", windowsHide: true });
if (!existsSync(path.join(source, "Cargo.lock"))) throw new Error("Missing full Takumi checkout at ref/takumi; the vendored tests alone cannot build upstream");
if (git("rev-parse", "HEAD").trim() !== REVISION) throw new Error("Unexpected Takumi source revision");
git("diff", "--exit-code", "HEAD", "--");
mkdirSync(out, { recursive: true });
const allTests = process.argv.includes("--all-tests");
const command = `cargo test --locked -p takumi-pdf ${allTests ? "--tests" : "--test pdf_fixtures"} -- --nocapture`;
writeFileSync(path.join(out, "run.sh"), [
  "#!/bin/sh", "set -eu", "cp -a /src /work", "cd /work",
  "export CARGO_HOME=/out/cargo", "export CARGO_TARGET_DIR=/out/target", "export CARGO_BUILD_JOBS=2",
  "rustc --version > /out/toolchain.txt", "cargo --version >> /out/toolchain.txt",
  `${command} > /out/fixture-tests.log 2>&1`, "mkdir -p /out/fixtures-generated",
  "cp takumi-pdf/tests/fixtures-generated/*.pdf /out/fixtures-generated/", "",
].join("\n"));
console.log(`Building Takumi ${REVISION}; progress: ${path.relative(ROOT, out)}/fixture-tests.log`);
const run = spawnSync("docker", ["run", "--rm", "--mount", `type=bind,source=${source},target=/src,readonly`,
  "--mount", `type=bind,source=${out},target=/out`, image, "sh", "/out/run.sh"], { stdio: "inherit", windowsHide: true });
if (run.error) throw run.error;
if (run.status !== 0) throw new Error(`Pinned oracle build failed (${run.status}); see fixture-tests.log`);
git("diff", "--exit-code", "HEAD", "--");
const log = readFileSync(path.join(out, "fixture-tests.log"), "utf8");
const summaries = [...log.matchAll(/test result: ok\. (\d+) passed; (\d+) failed/g)];
if (!summaries.length) throw new Error("No successful Rust test summary");
const provenance = { revision: REVISION, kind: "source-build", image, command,
  cargoLockSha256: createHash("sha256").update(readFileSync(path.join(source, "Cargo.lock"))).digest("hex"),
  toolchain: readFileSync(path.join(out, "toolchain.txt"), "utf8").trim(),
  tests: { passed: summaries.reduce((n, m) => n + Number(m[1]), 0), failed: summaries.reduce((n, m) => n + Number(m[2]), 0) },
  goldens: readdirSync(path.join(out, "fixtures-generated")).filter((f) => f.endsWith(".pdf")).length };
writeFileSync(path.join(out, "provenance.json"), JSON.stringify(provenance, null, 2) + "\n");
console.log(JSON.stringify(provenance, null, 2));
