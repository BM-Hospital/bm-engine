// Examples for docs/{en,vi}/pdf/native-and-wasm.md. Run: node docs/examples/run-all.mjs pdf-native-and-wasm
// Renders the same document once per backend (in child processes: the backend is chosen at import) and compares
// the bytes. Without the native addon installed only the wasm run happens, and that is reported.
import "./_lib.mjs";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

if (process.argv[2] === "--child") {
  // #region backend
  const { backend, profile, features, PdfRenderer } = await import("bm-engine/pdf");
  console.log(backend, profile, features.pdf); // "native" pdf true  (or "wasm" pdf true without the addon)
  // #endregion
  const { readFileSync } = await import("node:fs");
  // #region same-bytes
  const pdf = new PdfRenderer();
  pdf.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
  const bytes = await pdf.render(
    `<h1 style="font-family: Inter">Same bytes</h1><p style="font-family: Inter">on every backend</p>`,
  );
  // no date is written unless you pass one, so the same input gives the same bytes on every run and backend
  // #endregion
  process.stdout.write(JSON.stringify({ backend, profile, pdf: features.pdf, sha256: createHash("sha256").update(bytes).digest("hex"), size: bytes.length }));
  process.exit(0);
}

const run = (env) => {
  const r = spawnSync(process.execPath, [fileURLToPath(import.meta.url), "--child"], { encoding: "utf8", env: { ...process.env, BM_ENGINE_BACKEND: env } });
  if (r.status !== 0) return { error: (r.stderr || r.stdout).trim().split("\n").pop() };
  return JSON.parse(r.stdout.slice(r.stdout.indexOf("{")));
};
const wasm = run("wasm");
const native = run("native");
assert.ok(!wasm.error, wasm.error);
assert.equal(wasm.backend, "wasm");
assert.equal(wasm.profile, "pdf");
assert.equal(wasm.pdf, true);
if (native.error) {
  console.log("native addon not available here:", native.error);
} else {
  assert.equal(native.backend, "native");
  assert.equal(native.sha256, wasm.sha256, "PDF bytes differ between the native addon and wasm");
  console.log(`same bytes on native and wasm: ${wasm.size} bytes, sha256 ${wasm.sha256.slice(0, 16)}...`);
}
console.log("pdf-native-and-wasm: ok");
