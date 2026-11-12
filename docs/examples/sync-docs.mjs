// Copies code regions of docs/examples/<page>.mjs into the guide pages, so the code shown in the docs is
// exactly the code that runs. In docs/{en,vi}/*.md, a fenced block preceded by
//   <!-- @example effects#gradients -->
// is replaced by the lines between `// #region gradients` and `// #endregion` in docs/examples/effects.mjs.
// Usage: node docs/examples/sync-docs.mjs [--check] [page ...]
import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const docs = join(here, "..");
const args = process.argv.slice(2);
const check = args.includes("--check");
const only = args.filter((a) => !a.startsWith("--"));

const regionCache = new Map();
function regions(page) {
  if (regionCache.has(page)) return regionCache.get(page);
  const file = join(here, `${page}.mjs`);
  const map = new Map();
  if (existsSync(file)) {
    const lines = readFileSync(file, "utf8").replace(/\r\n/g, "\n").split("\n");
    let name = null, buf = [];
    for (const line of lines) {
      const open = line.match(/^\s*\/\/ #region (\S+)/);
      const close = line.match(/^\s*\/\/ #endregion/);
      if (open) { name = open[1]; buf = []; continue; }
      if (close && name) { map.set(name, dedent(buf).join("\n")); name = null; continue; }
      if (name) buf.push(line);
    }
  }
  regionCache.set(page, map);
  return map;
}
function dedent(lines) {
  const ind = Math.min(...lines.filter((l) => l.trim()).map((l) => l.match(/^ */)[0].length));
  return lines.map((l) => l.slice(Number.isFinite(ind) ? ind : 0));
}

let changed = 0, problems = 0, blocks = 0;
for (const lang of ["en", "vi"]) {
  const dir = join(docs, lang);
  for (const f of readdirSync(dir).filter((f) => f.endsWith(".md"))) {
    if (only.length && !only.includes(f.replace(/\.md$/, ""))) continue;
    const path = join(dir, f);
    const src = readFileSync(path, "utf8").replace(/\r\n/g, "\n");
    const out = src.replace(/<!-- @example ([\w-]+)#([\w-]+) -->\n(\s*\n)*(```[^\n]*)\n((?:(?!```)[^\n]*\n)*)```/g,
      (m, page, region, _blank, fence, body) => {
        blocks++;
        const code = regions(page).get(region);
        if (code === undefined) { problems++; console.error(`${lang}/${f}: missing region ${page}#${region}`); return m; }
        return `<!-- @example ${page}#${region} -->\n${fence}\n${code}\n\`\`\``;
      });
    if (out !== src) {
      changed++;
      if (check) { problems++; console.error(`${lang}/${f}: snippets out of date`); }
      else writeFileSync(path, out);
    }
  }
}
console.log(`${blocks} example blocks, ${changed} file(s) ${check ? "out of date" : "updated"}, ${problems} problem(s)`);
if (problems) process.exitCode = 1;
