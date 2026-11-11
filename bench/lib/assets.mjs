import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
export const BENCH_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const ROOT_DIR = path.resolve(BENCH_DIR, "..");
const cache = new Map();
/** Bytes of bench/assets/<name> (cached, plain Uint8Array). */
export function asset(name) {
  if (!cache.has(name)) cache.set(name, new Uint8Array(readFileSync(path.join(BENCH_DIR, "assets", name))));
  return cache.get(name);
}
