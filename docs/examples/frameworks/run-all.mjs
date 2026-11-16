// Runs every check-*.mjs of docs/examples/frameworks.
//
//   node docs/examples/frameworks/run-all.mjs                 in place: `bm-render` resolves to this repository
//                                                             (package self-reference); optional frameworks SKIP
//   node docs/examples/frameworks/run-all.mjs --app=<dir>     copies the examples to <dir>/fw and runs them there,
//                                                             against the bm-render installed in <dir>/node_modules
//                                                             (npm pack + npm i <tarball> hono @hono/node-server express h3 esbuild)
import { spawnSync } from "node:child_process";
import { cpSync, readdirSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..", "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));

let dir = here;
if (args.app) {
  dir = path.join(path.resolve(args.app), "fw");
  mkdirSync(dir, { recursive: true });
  cpSync(here, dir, { recursive: true, filter: (src) => !src.includes("node_modules") && !src.includes(`${path.sep}out`) });
}
/** extra node flags per script */
const FLAGS = { "check-manual-wasm.mjs": ["--conditions=browser"], "check-cloudflare.mjs": ["--conditions=workerd"] };
const scripts = readdirSync(dir).filter((f) => /^check-.*\.mjs$/.test(f)).sort();
const env = { ...process.env, BM_FONTS: path.join(root, "assets", "fonts"), BM_REPO: root };
let failed = 0;
for (const s of scripts) {
  console.log(`\n== ${s}${FLAGS[s] ? " " + FLAGS[s].join(" ") : ""}  (${dir})`);
  const r = spawnSync(process.execPath, [...(FLAGS[s] || []), s], { cwd: dir, env, encoding: "utf8", timeout: 300000 });
  process.stdout.write(r.stdout || "");
  if (r.stderr) process.stdout.write(r.stderr.split("\n").map((l) => "  stderr: " + l).join("\n") + "\n");
  if (r.status !== 0) { failed++; console.log(`exit ${r.status}`); }
}
console.log(`\n${scripts.length - failed}/${scripts.length} scripts passed`);
process.exitCode = failed ? 1 : 0;
