// Writes the raw RGBA frame of fixtures to <dir>/<id>.<width>x<height>.rgba (inputs for encoder profiling).
//   node bench/perf/dump-raw.mjs <dir> <id>[,<id>...]
import { writeFileSync, readFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ROOT_DIR } from "../lib/assets.mjs";
import { fontsFor } from "../lib/fonts.mjs";
import { ALL_CASES } from "../fixtures/index.mjs";
import { renderOpts } from "../lib/pipeline.mjs";

const [dir, ids] = process.argv.slice(2);
mkdirSync(dir, { recursive: true });
const { createBinding } = await import(pathToFileURL(path.join(ROOT_DIR, "js", "engine.mjs")).href);
const b = createBinding();
b.initSync(readFileSync(path.join(ROOT_DIR, "js", "bm_engine.wasm")));
for (const id of ids.split(",")) {
  const k = ALL_CASES.find((c) => c.id === id);
  const r = new b.Renderer();
  for (const f of fontsFor(k.fonts)) r.registerFont({ name: f.name, data: new Uint8Array(readFileSync(f.path)), weight: f.weight, style: f.style });
  const out = r.renderSync(k.node, renderOpts(k, "raw"));
  const h = out.length / 4 / k.width;
  writeFileSync(path.join(dir, `${id}.${k.width}x${h}.rgba`), out);
  console.log(id, k.width, h);
}
