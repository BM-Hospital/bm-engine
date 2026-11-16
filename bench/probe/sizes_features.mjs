// Marginal wasm cost of every optional feature, measured two ways (shared code makes them differ):
//   +core : size(core + feature) - size(core)
//   -full : size(full) - size(full - feature)
// Each build is `zig build -Dprofile=<p> -D<flag>=<v>` (optimize=small, stripped) into a scratch prefix;
// with --opt the binaries also go through `wasm-opt -Oz` and are gzip/brotli-compressed.
//   node probe/sizes_features.mjs [--opt] [--only=css,tw] [--out=out/sizes_features.json]
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { gzipSync, brotliCompressSync, constants } from "node:zlib";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));
const defaultZig = "C:/Users/admini/Downloads/zig-x86_64-windows-0.17.1/zig-x86_64-windows-0.17.1/zig.exe";
const zig = process.env.ZIG || (existsSync(defaultZig) ? defaultZig : "zig");
const wasmOpt = path.join(root, "bench", "node_modules", "binaryen", "bin", "wasm-opt");
const FLAGS = ["css", "tw", "html", "svg", "woff", "variable_fonts", "cff", "effects", "modern_color", "tables", "floats",
  "webp_gif_decode", "text_wrap_balance", "color_fonts", "complex_text", "animation", "extra_codecs", "render_svg"];
const flags = args.only ? String(args.only).split(",") : FLAGS;
const tmp = mkdtempSync(path.join(os.tmpdir(), "bmsz-"));

function measure(profile, extra) {
  const prefix = path.join(tmp, "b");
  execFileSync(zig, ["build", `-Dprofile=${profile}`, ...extra, "-p", prefix], { cwd: root, stdio: ["ignore", "ignore", "inherit"] });
  const file = path.join(prefix, "bin", "bm_render.wasm");
  const small = readFileSync(file).length;
  if (!args.opt) return { small };
  execFileSync(process.execPath, [wasmOpt, file, "-Oz", "--enable-simd", "--enable-bulk-memory", "--enable-sign-ext",
    "--enable-nontrapping-float-to-int", "--enable-mutable-globals", "-o", file], { stdio: "inherit" });
  const b = readFileSync(file);
  return { small, opt: b.length, gzip9: gzipSync(b, { level: 9 }).length,
    brotli: brotliCompressSync(b, { params: { [constants.BROTLI_PARAM_QUALITY]: 11 } }).length };
}

const res = { date: new Date().toISOString(), base: {}, features: {} };
for (const p of ["core", "standard", "full"]) { res.base[p] = measure(p, []); console.log(p, JSON.stringify(res.base[p])); }
for (const fl of flags) {
  const on = measure("core", [`-D${fl}=true`]);
  const off = measure("full", [`-D${fl}=false`]);
  const d = (a, b, k) => (a[k] != null && b[k] != null ? a[k] - b[k] : null);
  res.features[fl] = {
    plusCore: Object.fromEntries(Object.keys(on).map((k) => [k, d(on, res.base.core, k)])),
    minusFull: Object.fromEntries(Object.keys(off).map((k) => [k, d(res.base.full, off, k)])),
  };
  console.log(fl.padEnd(18), "+core", JSON.stringify(res.features[fl].plusCore), " -full", JSON.stringify(res.features[fl].minusFull));
}
rmSync(tmp, { recursive: true, force: true });
const out = path.resolve(here, "..", args.out || "out/sizes_features.json");
mkdirSync(path.dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(res, null, 2));
console.log("written", out);
