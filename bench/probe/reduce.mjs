// Replays the fuzz sequence up to the trapping case, then greedily shrinks it.
import { readFileSync } from "node:fs";
const src = readFileSync(new URL("./fuzz.mjs", import.meta.url), "utf8");
// re-run generator to capture failing case: fuzz.mjs prints it; here we accept JSON on argv instead
const wasmBytes = readFileSync(process.env.BM_WASM); const wmod = new WebAssembly.Module(wasmBytes); let seq = 0;
const png = readFileSync("assets/icon.png"), jpg = readFileSync("assets/photo.jpg");
const { node, opts } = JSON.parse(readFileSync(process.argv[2], "utf8"));
opts.images = [{ src: "img://p", data: png }, { src: "img://j", data: jpg }];
async function traps(n) {
  const bm = await import("../../js/index.mjs?i=" + seq++); bm.initSync(wmod);
  const r = new bm.Renderer();
  r.registerFont({ name: "Inter", data: readFileSync("../assets/fonts/Inter-Regular.ttf") });
  r.registerFont({ name: "Noto Sans", data: readFileSync("../assets/fonts/NotoSans-Bold.ttf") });
  try { r.renderSync(n, opts); return false; } catch (e) { return e instanceof WebAssembly.RuntimeError; }
}
let cur = node;
if (!(await traps(cur))) { console.log("does not trap standalone"); process.exit(0); }
let changed = true;
const clone = (x) => JSON.parse(JSON.stringify(x));
while (changed) {
  changed = false;
  const paths = []; (function walk(n, p) { paths.push(p); (n.children || []).forEach((c, i) => walk(c, [...p, i])); })(cur, []);
  for (const p of paths.reverse()) {
    if (p.length) { const t = clone(cur); let par = t; for (const i of p.slice(0, -1)) par = par.children[i]; par.children.splice(p.at(-1), 1); if (await traps(t)) { cur = t; changed = true; break; } }
    let n = cur; for (const i of p) n = n.children[i];
    for (const k of Object.keys(n.style || {})) { const t = clone(cur); let m = t; for (const i of p) m = m.children[i]; delete m.style[k]; if (await traps(t)) { cur = t; changed = true; break; } }
    if (changed) break;
  }
}
console.log(JSON.stringify(cur), JSON.stringify({ ...opts, images: undefined }));
