// Oracle: render each CSS colour (argv or stdin lines) as a 1x1 box; prints "css\tr g b a" (or ERR).
import { Renderer } from "@takumi-rs/wasm/node";
import { readFileSync } from "node:fs";
const r = new Renderer();
const list = process.argv.length > 2 ? process.argv.slice(2) : readFileSync(0, "utf8").split("\n").filter((s) => s.trim());
for (const c of list) {
  try {
    const raw = await r.render({ type: "container", style: { display: "block", width: 1, height: 1, backgroundColor: c } }, { width: 1, height: 1, format: "raw" });
    console.log(`${c}\t${raw[0]} ${raw[1]} ${raw[2]} ${raw[3]}`);
  } catch (e) {
    console.log(`${c}\tERR`);
  }
}
