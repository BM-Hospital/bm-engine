// Test utilities for the framework examples (not shown in the docs).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

/** Directory with Inter / Noto Sans / Roboto TTFs: $BM_FONTS or the repository's assets/fonts/. */
export const FONTS = process.env.BM_FONTS ? new URL("file:///" + process.env.BM_FONTS.replace(/\\/g, "/").replace(/\/?$/, "/"))
  : new URL("../../../../assets/fonts/", import.meta.url);
export const font = (name) => readFileSync(new URL(name, FONTS));

/** Asserts PNG bytes and returns [width, height]. */
export function pngSize(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  assert.deepEqual([...b.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10], "PNG signature");
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  return [v.getUint32(16), v.getUint32(20)];
}

let failed = 0;
/** Runs one named check and prints PASS / FAIL. */
export async function check(name, fn) {
  try {
    const detail = await fn();
    console.log(`PASS  ${name}${detail ? "  " + detail : ""}`);
  } catch (e) {
    failed++;
    console.log(`FAIL  ${name}\n      ${(e && e.stack) || e}`);
  }
}
export function done() {
  if (failed) { console.log(`${failed} check(s) failed`); process.exitCode = 1; }
}
