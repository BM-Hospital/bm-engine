// Prepares generated files under docs/public/ before `vitepress dev|build` (npm run docs:dev / docs:build):
//   docs/public/playground-app/  self-contained playground build (docs/playground-app/build.mjs; prebuilt js/*.wasm, no Zig)
//   docs/public/data/        downloadable copies of docs/results.json and docs/PACKAGE_FACTS.json
// Both folders are gitignored.
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DOCS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const r = spawnSync(process.execPath, [path.join(DOCS, "playground-app", "build.mjs"), "--out", "../public/playground-app"], { stdio: "inherit" });
if (r.status !== 0) process.exit(r.status ?? 1);
mkdirSync(path.join(DOCS, "public", "data"), { recursive: true });
for (const f of ["results.json", "PACKAGE_FACTS.json"]) copyFileSync(path.join(DOCS, f), path.join(DOCS, "public", "data", f));
console.log("docs/public/data ready");
