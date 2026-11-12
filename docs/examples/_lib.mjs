// Shared helpers for the guide examples (not shown in the docs).
// Importing this module switches the working directory to the repository root, so the example code can
// use paths such as "assets/fonts/Inter-Regular.ttf" exactly as printed in the pages.
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
process.chdir(root);
const outDir = join(root, "docs", "public", "img", "guide");
mkdirSync(outDir, { recursive: true });

/** saver("effects")("gradients", png) writes docs/public/img/guide/effects-gradients.png */
export function saver(page) {
  return (name, bytes, ext = "png") => {
    if (typeof bytes === "string") bytes = new TextEncoder().encode(bytes);
    const file = join(outDir, `${page}-${name}.${ext}`);
    if (ext === "png" && bytes[0] === 0x89) {
      const w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      if (w > 800) console.warn(`WARN ${page}-${name}.png is ${w}px wide (> 800)`);
    }
    writeFileSync(file, bytes);
    console.log(`wrote ${page}-${name}.${ext} (${bytes.length} bytes)`);
  };
}

/** Throws unless fn throws; returns the message (for documenting error behaviour). */
export function expectThrow(fn) {
  try { fn(); } catch (e) { return e.message; }
  throw new Error("expected an exception");
}
