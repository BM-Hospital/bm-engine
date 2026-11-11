// Contact sheets of out/<id>/{takumi,bm,native,diff}.png for eyeballing. usage: node probe/sheet.mjs <kind=takumi> <perSheet=12> [filterRegex]
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync } from "node:fs";
import { PNG } from "pngjs";
const kind = process.argv[2] ?? "takumi", per = +(process.argv[3] ?? 12), re = new RegExp(process.argv[4] ?? ".");
const TW = 400, TH = 240, COLS = 4;
const ids = readdirSync("out", { withFileTypes: true }).filter((d) => d.isDirectory() && re.test(d.name) && existsSync(`out/${d.name}/${kind}.png`)).map((d) => d.name);
mkdirSync("out/sheets", { recursive: true });
for (let s = 0; s * per < ids.length; s++) {
  const chunk = ids.slice(s * per, (s + 1) * per), rows = Math.ceil(chunk.length / COLS);
  const sheet = new PNG({ width: COLS * TW, height: rows * (TH + 18) }); sheet.data.fill(200);
  chunk.forEach((id, i) => {
    const im = PNG.sync.read(readFileSync(`out/${id}/${kind}.png`)); const sc = Math.min(TW / im.width, TH / im.height);
    const ox = (i % COLS) * TW, oy = Math.floor(i / COLS) * (TH + 18);
    for (let y = 0; y < im.height * sc; y++) for (let x = 0; x < im.width * sc; x++) {
      const sx = Math.min(im.width - 1, Math.floor(x / sc)), sy = Math.min(im.height - 1, Math.floor(y / sc));
      const si = (sy * im.width + sx) * 4, di = ((oy + y) * sheet.width + ox + x) * 4, a = im.data[si + 3] / 255;
      for (let c = 0; c < 3; c++) sheet.data[di + c] = im.data[si + c] * a + 200 * (1 - a); sheet.data[di + 3] = 255;
    }
  });
  writeFileSync(`out/sheets/${kind}-${s}.png`, PNG.sync.write(sheet)); console.log(`out/sheets/${kind}-${s}.png`, chunk.join(","));
}
