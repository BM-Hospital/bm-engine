// Reproducible source oracle for probes outside the committed Rust golden fixtures.
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ROOT, REVISION } from "./takumi-test-corpus.mjs";

const source = path.join(ROOT, "ref", "takumi");
const out = path.join(ROOT, "bench", "out", "pdf-oracle");
const image = "rust:1.91-bookworm@sha256:c1e5f19e773b7878c3f7a805dd00a495e747acbdc76fb2337a4ebf0418896b33";
const git = (...args) => execFileSync("git", ["-C", source, ...args], { encoding: "utf8", windowsHide: true }).trim();
if (git("rev-parse", "HEAD") !== REVISION) throw new Error("Unexpected source revision");
git("diff", "--exit-code", "HEAD", "--");
mkdirSync(out, { recursive: true });
const version = readFileSync(path.join(source, "Cargo.lock"), "utf8").match(/name = "wasm-bindgen"\s+version = "([^"]+)"/)?.[1];
if (!version) throw new Error("Missing wasm-bindgen lock entry");
const command = "cargo build --locked -p takumi-pdf-wasm --target wasm32-unknown-unknown --release";
writeFileSync(path.join(out, "build-wasm.sh"), ["set -eu", "cp -a /src /work", "cd /work",
  "export CARGO_HOME=/out/cargo CARGO_TARGET_DIR=/out/target CARGO_BUILD_JOBS=2",
  "rustup target add wasm32-unknown-unknown", command,
  `if [ ! -x /out/cargo/bin/wasm-bindgen ] || ! /out/cargo/bin/wasm-bindgen --version | grep -F ' ${version}'; then cargo install wasm-bindgen-cli --version ${version} --locked; fi`,
  "mkdir -p /out/wasm", "/out/cargo/bin/wasm-bindgen /out/target/wasm32-unknown-unknown/release/takumi_pdf_wasm.wasm --target web --out-dir /out/wasm", ""].join("\n"));
if (!process.argv.includes("--skip-build")) {
  const run = spawnSync("docker", ["run", "--rm", "--mount", `type=bind,source=${source},target=/src,readonly`,
    "--mount", `type=bind,source=${out},target=/out`, image, "sh", "/out/build-wasm.sh"], { stdio: "inherit", windowsHide: true });
  if (run.error) throw run.error;
  if (run.status !== 0) throw new Error(`Oracle WASM build failed (${run.status})`);
} else {
  const previous = JSON.parse(readFileSync(path.join(out, "wasm-provenance.json"), "utf8"));
  const digest = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");
  if (previous.revision !== REVISION || previous.cargoLockSha256 !== digest(path.join(source, "Cargo.lock")) ||
      previous.wasmSha256 !== digest(path.join(out, "wasm/takumi_pdf_wasm_bg.wasm"))) throw new Error("Cached oracle provenance mismatch; rebuild without --skip-build");
}
const { build } = await import(pathToFileURL(path.join(ROOT, "bench/node_modules/esbuild/lib/main.js")));
await build({ entryPoints: [path.join(source, "takumi-pdf-js/src/export.ts")], outfile: path.join(out, "export.mjs"),
  bundle: true, platform: "node", format: "esm", external: ["react"], alias: {
    "@takumi-rs/bindings-js": path.join(source, "takumi-bindings-js/src/index.ts"),
    "@takumi-rs/helpers/jsx": path.join(source, "takumi-helpers/src/jsx/index.ts"),
    "@takumi-rs/helpers": path.join(source, "takumi-helpers/src/index.ts"),
  }, plugins: [{ name: "pinned-wasm", setup(b) {
    b.onResolve({ filter: /pkg\/takumi_pdf_wasm$/ }, () => ({ path: path.join(out, "wasm/takumi_pdf_wasm.js") }));
  } }] });
writeFileSync(path.join(out, "node.mjs"), `import {readFileSync} from 'node:fs';\nimport * as wasm from './export.mjs';\nwasm.initSync({module:readFileSync(new URL('./wasm/takumi_pdf_wasm_bg.wasm',import.meta.url))});\nexport * from './export.mjs';\n`);
const sha = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");
const provenance = { revision: REVISION, version: "0.20.0", kind: "source-build-wasm", image, command,
  wasmBindgen: version, esbuild: JSON.parse(readFileSync(path.join(ROOT, "bench/node_modules/esbuild/package.json"))).version,
  cargoLockSha256: sha(path.join(source, "Cargo.lock")), wasmSha256: sha(path.join(out, "wasm/takumi_pdf_wasm_bg.wasm")),
  wrapperSha256: sha(path.join(out, "export.mjs")) };
git("diff", "--exit-code", "HEAD", "--");
writeFileSync(path.join(out, "wasm-provenance.json"), JSON.stringify(provenance, null, 2) + "\n");
console.log(`TAKUMI_PDF_REF_ENTRY=${path.join(out, "node.mjs")}`);
