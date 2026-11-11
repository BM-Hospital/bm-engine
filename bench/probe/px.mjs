// usage: node probe/px.mjs <case-id> <x> <y0> <y1> [h]  -> prints pixels along a column (or row with 'h')
import { PNG } from "pngjs";
import { readFileSync } from "node:fs";
const [id, x, y0, y1, dir] = process.argv.slice(2);
const A = PNG.sync.read(readFileSync(`out/${id}/takumi.png`)), B = PNG.sync.read(readFileSync(`out/${id}/bm.png`));
for (let t = +y0; t <= +y1; t++) {
  const px = dir ? t : +x, py = dir ? +x : t;
  const i = (py * A.width + px) * 4;
  console.log(dir ? "x" : "y", t, "takumi", [...A.data.subarray(i, i + 4)].join(","), " bm", [...B.data.subarray(i, i + 4)].join(","));
}
