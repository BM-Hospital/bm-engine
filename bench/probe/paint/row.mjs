// node probe/paint/row.mjs <dump dir>/<id> <y> <x0> <x1> [v]  -> prints channel R along a row (or column with 'v') for takumi and bm
import { PNG } from "pngjs";
import { readFileSync } from "node:fs";
const [dir, y, x0, x1, v] = process.argv.slice(2);
const A = PNG.sync.read(readFileSync(dir + "/takumi.png")), B = PNG.sync.read(readFileSync(dir + "/bm.png"));
const row = (P) => { const o = []; for (let x = +x0; x <= +x1; x++) { const i = v ? (x * P.width + +y) * 4 : (+y * P.width + x) * 4; o.push(String(P.data[i + 1]).padStart(3)); } return o.join(" "); };
console.log("tk", row(A)); console.log("bm", row(B));
