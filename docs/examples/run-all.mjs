// Runs every guide example (docs/examples/<page>.mjs), which write their images to
// docs/public/img/guide/<page>-<name>.png, then copies the code regions into the pages (sync-docs.mjs).
// Usage: node docs/examples/run-all.mjs [page ...]
import { readdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const only = process.argv.slice(2);
const pages = readdirSync(here)
  .filter((f) => f.endsWith(".mjs") && !f.startsWith("_") && f !== "run-all.mjs" && f !== "sync-docs.mjs")
  .map((f) => f.replace(/\.mjs$/, ""))
  .filter((p) => !only.length || only.includes(p));

let failed = 0;
for (const page of pages) {
  const t0 = performance.now();
  const r = spawnSync(process.execPath, [join(here, `${page}.mjs`)], { encoding: "utf8" });
  const ms = (performance.now() - t0).toFixed(0);
  if (r.status !== 0) { failed++; console.error(`FAIL ${page} (${ms} ms)\n${r.stdout}${r.stderr}`); }
  else console.log(`ok   ${page} (${ms} ms)${r.stderr.includes("WARN") ? "\n" + r.stderr.trim() : ""}`);
}
spawnSync(process.execPath, [join(here, "sync-docs.mjs"), ...only], { stdio: "inherit" });

const imgDir = join(here, "..", "public", "img", "guide");
const files = readdirSync(imgDir);
const total = files.reduce((s, f) => s + statSync(join(imgDir, f)).size, 0);
console.log(`${files.length} images in docs/public/img/guide, ${(total / 1024).toFixed(0)} KiB total`);
if (failed) { console.error(`${failed} example script(s) failed`); process.exitCode = 1; }
