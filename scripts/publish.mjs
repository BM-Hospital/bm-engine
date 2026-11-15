// Release checks and the ordered publish of the nine npm packages (bm-engine + 8 bm-engine-<platform>).
//
//   npm run release:check          every check a release needs (also what `prepublishOnly` runs):
//                                  version sync + wasm manifest, Zig unit tests, PDF tests, native addon tests
//                                  and the packed-install scenarios (scripts/pack-test.mjs)
//   npm run release -- [--otp=123456] [--dry-run] [--skip-checks]
//                                  builds the native addon for the 8 targets and the npm/<platform>/ folders,
//                                  runs release:check, then publishes the platform packages FIRST and bm-engine
//                                  LAST (bm-engine's optionalDependencies must exist when users install it).
//                                  Packages already on the registry at this version are skipped, so a release
//                                  interrupted half-way (expired OTP, network) can be re-run as is.
//
// The wasm binaries are not rebuilt here: they are committed and `npm run verify` checks them against
// js/build-manifest.json. Rebuild them with `npm run build` when the Zig sources changed.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const pkg = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));
const platforms = Object.keys(pkg.optionalDependencies).map((n) => n.slice("bm-engine-".length));
const npm = process.platform === "win32" ? "npm.cmd" : "npm";

function run(cmd, argv, opts = {}) {
  console.log(`\n> ${[cmd, ...argv].join(" ")}`);
  const r = spawnSync(cmd, argv, { cwd: root, stdio: "inherit", shell: process.platform === "win32", ...opts });
  if (r.status !== 0) {
    console.error(`\nrelease: \`${[cmd, ...argv].join(" ")}\` failed (exit ${r.status ?? r.signal}); nothing more was published.`);
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
  npmRun("test:pdf");    // PDF API / output suite on the default backend
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
const dirty = spawnSync("git", ["status", "--porcelain", "--untracked-files=no"], { cwd: root, encoding: "utf8" }).stdout.trim();
if (dirty && !args["allow-dirty"]) {
  console.error("release: the working tree has uncommitted changes; commit them first (or pass --allow-dirty):\n" + dirty);
  process.exit(1);
}
const who = spawnSync(npm, ["whoami"], { cwd: root, encoding: "utf8", shell: process.platform === "win32" });
if (who.status !== 0) { console.error("release: not logged in to npm; run `npm login` first"); process.exit(1); }
console.log(`release: bm-engine ${pkg.version} as npm user ${who.stdout.trim()}${args["dry-run"] ? " (dry run)" : ""}`);

npmRun("build:native"); // 8 targets -> native/dist/, structurally verified
npmRun("build:npm");    // native/dist -> npm/<platform>/ (checked against native/dist/manifest.json)
for (const p of platforms) {
  if (!existsSync(path.join(root, "npm", p, `bm-engine.${p}.node`))) { console.error(`release: npm/${p}/bm-engine.${p}.node is missing`); process.exit(1); }
}
if (!args["skip-checks"]) checks();

const extra = [...(args.otp ? [`--otp=${args.otp}`] : []), ...(args["dry-run"] ? ["--dry-run"] : []), ...(args.tag ? [`--tag=${args.tag}`] : [])];
for (const p of platforms) {
  const name = `bm-engine-${p}`;
  if (!args["dry-run"] && published(name)) { console.log(`\nrelease: ${name}@${pkg.version} is already published, skipped`); continue; }
  run(npm, ["publish", `./npm/${p}`, "--access", "public", ...extra]);
}
if (!args["dry-run"] && published("bm-engine")) { console.log(`\nrelease: bm-engine@${pkg.version} is already published`); process.exit(0); }
run(npm, ["publish", "--access", "public", ...extra], { env: { ...process.env, BM_RELEASE_CHECKED: pkg.version } });
console.log(`\nrelease: published bm-engine ${pkg.version} and its ${platforms.length} platform packages${args["dry-run"] ? " (dry run)" : ""}.` +
  `\nNext: git tag v${pkg.version} && git push origin v${pkg.version}`);
