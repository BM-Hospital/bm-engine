// WOFF add-on test: a build without WOFF support (default: js/bm_engine.core.wasm) + js/addons.mjs
// loadWoff() must register WOFF / WOFF2 fonts exactly like the built-in path of the full build
// (js/bm_engine.wasm): same registerFont result, same converted sfnt bytes, byte-identical renders.
// Also checks the clear error without the add-on and that corrupt data fails cleanly.
//   node probe/addons/woff.mjs [small.wasm] [full.wasm]
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..", "..");
const js = path.join(root, "js");
const smallWasm = process.argv[2] || path.join(js, "bm_engine.core.wasm");
const fullWasm = process.argv[3] || path.join(js, "bm_engine.wasm");
const td = path.join(root, "src", "woff", "testdata");

// two independent module instances of the wrapper: the plain one (shared with js/addons.mjs) runs
// the small build, a query-string copy runs the full build
const S = await import(pathToFileURL(path.join(js, "index.mjs")).href);
const F = await import(pathToFileURL(path.join(js, "index.mjs")).href + "?full");
S.initSync(readFileSync(smallWasm));
F.initSync(readFileSync(fullWasm));
const A = await import(pathToFileURL(path.join(js, "addons.mjs")).href);

let fails = 0;
const ok = (c, msg) => { console.log((c ? "ok   " : "FAIL ") + msg); if (!c) fails++; };
ok(!S.features.woff, `small build has no built-in WOFF (features.woff=${S.features.woff})`);
ok(F.features.woff, "full build has built-in WOFF");

const rs = new S.Renderer();
const rf = new F.Renderer();
const woff2 = readFileSync(path.join(td, "geist.woff2"));
let err = "";
try { rs.registerFont({ name: "G", data: woff2 }); } catch (e) { err = String(e.message); }
ok(/no WOFF\/WOFF2 font support/.test(err) && /loadWoff/.test(err), "clear error without the add-on: " + err);

const t0 = performance.now();
await A.loadWoff();
console.log(`     add-on instantiated in ${(performance.now() - t0).toFixed(1)} ms`);
const node = { type: "container", style: { width: 600, height: 200, display: "flex", flexDirection: "column", backgroundColor: "#fff", padding: 20 },
  children: ["Geist WOFF2 add-on test", "The quick brown fox jumps over the lazy dog 0123456789"].map((text, i) => ({ type: "text", text, style: { fontFamily: i ? "GW" : "G", fontSize: 28, color: "#111" } })) };
// registerFont results are compared where both builds support the font's outline format; a
// collection with a CFF face (unsupported in core) is compared with its reference TTC instead
for (const [file, name, ref] of [["geist.woff2", "G", "geist.ttf"], ["geist.woff", "GW", "geist.ttf"], ["collection.woff2", "C", "collection_ref.ttc"], ["ebgaramond.woff2", "E"]]) {
  const data = readFileSync(path.join(td, file));
  const a = JSON.stringify(rs.registerFont({ name, data }));
  if (ref) {
    const refBytes = readFileSync(path.join(td, ref));
    ok(Buffer.compare(Buffer.from(A.decodeWoff(data)), refBytes) === 0, `${file}: add-on output == ${ref} (${refBytes.length} bytes)`);
    const c = JSON.stringify(rs.registerFont({ name: name + "_ref", data: refBytes })).split(name + "_ref").join(name);
    ok(a === c, `${file}: registerFont(woff via add-on) == registerFont(${ref}) on the small build`);
  }
  if (file !== "collection.woff2") {
    const b = JSON.stringify(rf.registerFont({ name, data }));
    ok(a === b, `${file}: registerFont result identical to the full build (${a.slice(0, 60)}...)`);
  }
}
const conv = A.decodeWoff(woff2);
ok(conv.length > 0 && conv[0] === 0 && conv[1] === 1, `decodeWoff -> sfnt (${conv.length} bytes)`);
const ps = rs.renderSync(node, { width: 600, height: 200, format: "raw" });
const pf = rf.renderSync(node, { width: 600, height: 200, format: "raw" });
let diff = 0;
for (let i = 0; i < ps.length; i++) if (ps[i] !== pf[i]) diff++;
ok(ps.length === pf.length && diff === 0, `render with add-on-decoded fonts byte-identical to the built-in path (${diff} bytes differ)`);
let nonWhite = 0;
for (let i = 0; i < ps.length; i += 4) if (ps[i] < 128) nonWhite++;
ok(nonWhite > 500, `text was drawn (${nonWhite} dark pixels)`);
err = "";
try { rs.registerFont({ name: "X", data: Uint8Array.from([0x77, 0x4f, 0x46, 0x32, 1, 2, 3, 4, 5]) }); } catch (e) { err = String(e.message); }
ok(/invalid WOFF\/WOFF2/.test(err), "corrupt WOFF2 fails cleanly: " + err);
console.log(fails ? `${fails} FAILED` : "all passed");
process.exit(fails ? 1 : 0);
