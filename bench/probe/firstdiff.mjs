import { PNG } from "pngjs";
import { readFileSync } from "node:fs";
const id = process.argv[2]; const thr = +(process.argv[3] || 60);
const A = PNG.sync.read(readFileSync(`out/${id}/takumi.png`)), B = PNG.sync.read(readFileSync(`out/${id}/bm.png`));
let n = 0;
for (let y = 0; y < A.height && n < 12; y++) for (let x = 0; x < A.width && n < 12; x++) {
  const i = (y * A.width + x) * 4; let d = 0; for (let k = 0; k < 4; k++) d = Math.max(d, Math.abs(A.data[i + k] - B.data[i + k]));
  if (d >= thr) { n++; console.log(x, y, "takumi", [...A.data.subarray(i, i + 4)].join(","), "bm", [...B.data.subarray(i, i + 4)].join(",")); x += 20; }
}
