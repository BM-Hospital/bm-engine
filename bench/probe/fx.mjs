import { readFileSync, readdirSync } from "node:fs";
const dir = "D:/project/bm-engine/ref/takumi/takumi/tests/fixtures-html/";
const names = process.argv.slice(2);
for (const n of names) {
  const h = readFileSync(dir + n + ".html", "utf8");
  const body = h.slice(h.indexOf("<body"), h.indexOf("</body>"));
  const vp = (body.match(/<body style="([^"]*)"/)||[])[1];
  const text = body.replace(/<[^>]*>/gs, "").replace(/&#?\w+;/g,"x").replace(/\s+/g, "");
  const imgs = (body.match(/<img|url\(/g)||[]).length;
  const fams = [...new Set((h.match(/font-family:\s*[^;"]+/g)||[]))];
  console.log(n.padEnd(48), "vp", vp, "| text", text.length, JSON.stringify(text.slice(0,30)), "| img", imgs, "| fam", fams.join(","));
}
