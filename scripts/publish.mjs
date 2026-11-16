// Release checks and the ordered publish of the nine npm packages (bm-render + 8 @hunghg255/bm-render-<platform>).
//
//   npm run release -- 0.1.1       the whole release in one command:
//                                  1. sets the version in the 9 package.json files + package-lock.json
//                                     (npm-platform-packages.mjs --set-version)
//                                  2. rebuilds the wasm of every profile + js/build-manifest.json (npm run build)
//                                  3. commits "Release 0.1.1"
//                                  4. builds the native addon for the 8 targets and the npm/<platform>/ folders
//                                  5. runs every check (release:check below)
//                                  6. publishes the 8 platform packages FIRST and bm-render LAST (bm-render's
//                                     optionalDependencies must exist when users install it)
//                                  7. tags v0.1.1 and pushes the commit and the tag
//                                  Without a version (or with the current one) steps 1-3 are skipped. Packages
//                                  already on the registry at this version are skipped, so a release interrupted
//                                  half-way (expired OTP, network) is finished by running the same command again.
//                                  Options: --otp=<code>, --tag=<dist-tag>, --skip-checks, --publish-only (no
//                                  build and no checks, only `npm run verify` and the publishes: to retry the
//                                  publish step after the checks already passed on this commit).
//   npm run release:dry -- 0.1.1   the same with `npm publish --dry-run`: no commit, tag or push, and the version
//                                  bump + rebuilt wasm are reverted at the end
//   npm run release:check          every check a release needs (also what `prepublishOnly` runs):
//                                  version sync + wasm manifest, Zig unit tests, PDF tests, native addon tests
//                                  and the packed-install scenarios (scripts/pack-test.mjs)
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const argv = process.argv.slice(2);
const args = Object.fromEntries(argv.map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const wanted = argv.find((a) => !a.startsWith("--"));
if (wanted && !/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/.test(wanted)) {
  console.error(`release: "${wanted}" is not a version (x.y.z or x.y.z-pre.n)`);
  process.exit(1);
}
const readPkg = () => JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));
let pkg = readPkg();
const platforms = Object.keys(pkg.optionalDependencies).map((n) => n.slice("@hunghg255/bm-render-".length));
const npm = process.platform === "win32" ? "npm.cmd" : "npm";
const dry = !!args["dry-run"];

function run(cmd, cmdArgs, opts = {}) {
  console.log(`\n> ${[cmd, ...cmdArgs].join(" ")}`);
  const r = spawnSync(cmd, cmdArgs, { cwd: root, stdio: "inherit", shell: process.platform === "win32" && cmd === npm, ...opts });
  if (r.status !== 0) {
    console.error(`\nrelease: \`${[cmd, ...cmdArgs].join(" ")}\` failed (exit ${r.status ?? r.signal}); stopped here.`);
    process.exit(1);
  }
}
const npmRun = (script) => run(npm, ["run", script]);

/** True when name@version is already on the registry. */
function published(name) {
  const r = spawnSync(npm, ["view", `${name}@${pkg.version}`, "version"], { cwd: root, encoding: "utf8", shell: process.platform === "win32" });
  return r.status === 0 && r.stdout.trim() === pkg.version;
}

function checks() {
  npmRun("verify");      // version sync of the 9 package.json files + wasm binaries match the manifest
  npmRun("test");        // zig build test (with and without -Dpdf)
  // PDF API / output suite on the default backend, against the committed wasm (without --no-build it rebuilds
  // the pdf wasm, which rewrites js/build-manifest.json and leaves the tree dirty)
  run(process.execPath, ["scripts/pdf-test.mjs", "--no-build"]);
  npmRun("test:native"); // native addon suite (this machine's platform)
  npmRun("test:pack");   // npm pack + install scenarios: native, wasm fallback, bundlers (~5 min)
}

// `prepublishOnly` of the root package: `release` already ran the checks in this process tree.
if (args.prepublish) {
  if (process.env.BM_RELEASE_CHECKED === pkg.version) { console.log("release: checks already ran for this release"); process.exit(0); }
  checks();
  process.exit(0);
}
if (args.check) { checks(); console.log("\nrelease: all checks passed"); process.exit(0); }

// ---- full release ----
spawnSync("git", ["update-index", "-q", "--refresh"], { cwd: root }); // ignore files only touched, not changed
const dirty = spawnSync("git", ["status", "--porcelain", "--untracked-files=no"], { cwd: root, encoding: "utf8" }).stdout.trim();
if (dirty && !args["allow-dirty"]) {
  console.error("release: the working tree has uncommitted changes; commit them first (or pass --allow-dirty):\n" + dirty);
  process.exit(1);
}
const who = spawnSync(npm, ["whoami"], { cwd: root, encoding: "utf8", shell: process.platform === "win32" });
if (who.status !== 0) { console.error("release: not logged in to npm; run `npm login` first"); process.exit(1); }

/** Files the version bump and the wasm rebuild touch (restored after a dry run). */
const BUMPED = ["package.json", "package-lock.json", "npm", "js"];
const bumped = !!wanted && wanted !== pkg.version;
if (bumped) {
  console.log(`release: ${pkg.version} -> ${wanted}`);
  run(process.execPath, ["scripts/npm-platform-packages.mjs", "--set-version", wanted]);
  npmRun("build"); // wasm of every profile + js/build-manifest.json with the new version
  pkg = readPkg();
  if (!dry) {
    run("git", ["add", "--", ...BUMPED]);
    run("git", ["commit", "-m", `Release ${pkg.version}`]);
  }
}
console.log(`release: bm-render ${pkg.version} as npm user ${who.stdout.trim()}${dry ? " (dry run)" : ""}`);

const publishOnly = !!args["publish-only"];
if (!publishOnly) {
  npmRun("build:native"); // 8 targets -> native/dist/, structurally verified
  npmRun("build:npm");    // native/dist -> npm/<platform>/ (checked against native/dist/manifest.json)
}
for (const p of platforms) {
  if (!existsSync(path.join(root, "npm", p, `bm-render.${p}.node`))) { console.error(`release: npm/${p}/bm-render.${p}.node is missing`); process.exit(1); }
}
if (publishOnly) npmRun("verify");
else if (!args["skip-checks"]) checks();

const extra = [...(args.otp ? [`--otp=${args.otp}`] : []), ...(dry ? ["--dry-run"] : []), ...(args.tag ? [`--tag=${args.tag}`] : [])];
for (const p of platforms) {
  const name = `@hunghg255/bm-render-${p}`;
  if (!dry && published(name)) { console.log(`\nrelease: ${name}@${pkg.version} is already published, skipped`); continue; }
  run(npm, ["publish", `./npm/${p}`, "--access", "public", ...extra]);
}
if (!dry && published("bm-render")) console.log(`\nrelease: bm-render@${pkg.version} is already published, skipped`);
else run(npm, ["publish", "--access", "public", ...extra], { env: { ...process.env, BM_RELEASE_CHECKED: pkg.version } });

if (dry) {
  if (bumped) run("git", ["checkout", "--", ...BUMPED]);
  console.log(`\nrelease: dry run of bm-render ${pkg.version} passed${bumped ? "; the version bump and the rebuilt wasm were reverted" : ""}.`);
  process.exit(0);
}
const tag = `v${pkg.version}`;
if (spawnSync("git", ["rev-parse", "-q", "--verify", `refs/tags/${tag}`], { cwd: root }).status !== 0) run("git", ["tag", tag]);
run("git", ["push", "origin", "HEAD", tag]);
console.log(`\nrelease: published bm-render ${pkg.version} and its ${platforms.length} platform packages; pushed the commit and ${tag}.`);
