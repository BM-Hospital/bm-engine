// Regenerate out/RESULTS.md from out/results.json:  node report.mjs [path/to/results.json]
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { renderMarkdown } from "./lib/report.mjs";
const here = path.dirname(fileURLToPath(import.meta.url));
const src = path.resolve(process.argv[2] ?? path.join(here, "out", "results.json"));
const md = renderMarkdown(JSON.parse(readFileSync(src, "utf8")));
const dst = path.join(path.dirname(src), "RESULTS.md");
writeFileSync(dst, md);
console.log("wrote", dst);
