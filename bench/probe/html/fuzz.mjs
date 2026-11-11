// Mutation fuzz of the html parser (ReleaseSafe harness): a wasm trap throws, a hang shows as a slow case.
import { readFileSync, readdirSync } from "node:fs";
import { loadParser } from "./lib.mjs";
const parse = await loadParser();
const dir = "../ref/takumi/takumi/tests/fixtures-html";
const files = readdirSync(dir).filter((f) => f.endsWith(".html")).map((f) => readFileSync(`${dir}/${f}`, "utf8"));
const toks = ["<", ">", "</", "/>", "<!--", "-->", "<![CDATA[", "]]>", "&#", "&amp", ";", "\"", "'", "=", "<svg", "</svg>", "<p>", "<table>", "<tr>", "<td>", "<li>", "<textarea>", "<script>", "<style>", "<template>", "\r", "\0", "\xff", "<pre>", "<body>", "<html>", "<!doctype html>"];
let seed = 1; const rnd = (n) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
const t0 = Date.now(); let cases = 0, worst = 0;
while (Date.now() - t0 < 25000) {
  let s = files[rnd(files.length)];
  if (rnd(4) === 0) s = s.slice(0, rnd(s.length));
  for (let k = rnd(10); k >= 0; k--) {
    const at = rnd(s.length + 1);
    const m = rnd(3);
    if (m === 0) s = s.slice(0, at) + toks[rnd(toks.length)] + s.slice(at);
    else if (m === 1) s = s.slice(0, at) + s.slice(at + rnd(40));
    else s = s.slice(0, at) + s.slice(rnd(s.length)) ;
  }
  if (rnd(50) === 0) s = "<div>".repeat(rnd(700)) + s;
  const t = performance.now();
  parse(s); cases++;
  worst = Math.max(worst, performance.now() - t);
}
console.log("fuzz cases", cases, "worst ms", worst.toFixed(1));
