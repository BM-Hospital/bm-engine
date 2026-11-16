// Cross-compiles the Node-API addon (src/native.zig) for every release target from any host with Zig 0.17,
// and verifies each artifact structurally (nothing is executed here; see bench/native-tests.mjs for that).
//
//   node scripts/build-native.mjs                        all eight targets -> native/dist/<name>/bm-render.<name>.node
//   node scripts/build-native.mjs --target=<name>[,...]  some of them
//   node scripts/build-native.mjs --optimize=safe        ReleaseSafe (default: fast; also small | debug)
//   node scripts/build-native.mjs --verify-only          check the files already in native/dist
//   (ZIG=<path to zig> overrides the compiler location)
//
// Targets (<name> is also the npm package suffix: @hunghg255/bm-render-<name>):
//   win32-x64-msvc, win32-arm64-msvc    PE DLL, no C runtime, imports kernel32 only; Node-API functions are
//                                       looked up in the host process at load time (no import of node.exe)
//   linux-x64-gnu, linux-arm64-gnu      ELF shared object against glibc >= 2.17
//   linux-x64-musl, linux-arm64-musl    ELF shared object against musl's libc.so (dynamic; Alpine)
//   darwin-x64, darwin-arm64            Mach-O dylib, libSystem only, napi_* bound by dynamic lookup
//
// What "verified" means per file (verify()): container format and CPU, `napi_register_module_v1` exported, the
// Node-API functions the code uses (the `Api` struct in src/native/napi.zig, read from the source) are exactly
// the undefined napi_* symbols (ELF / Mach-O) or present as lookup names (PE), only the expected libraries
// are needed, no math function is imported (floating point must come from the code compiled into the binary,
// as in the wasm build), glibc symbol versions <= 2.17, no thread-local storage segment, arm64 Mach-O is
// ad-hoc signed, and on arm64 no fused multiply-add instruction exists anywhere in the code.
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const opts = Object.fromEntries(process.argv.slice(2).map((a) => { const m = /^--([^=]+)(?:=(.*))?$/.exec(a); return m ? [m[1], m[2] ?? true] : [a, true]; }));

export const TARGETS = {
  // (x64 artifacts are compiled for x86-64-v2 by build.zig, arm64 ones for the architecture baseline)
  "win32-x64-msvc": { zig: "x86_64-windows-gnu", format: "pe", cpu: "x64" },
  "win32-arm64-msvc": { zig: "aarch64-windows-gnu", format: "pe", cpu: "arm64" },
  "linux-x64-gnu": { zig: "x86_64-linux-gnu.2.17", format: "elf", cpu: "x64", libc: "glibc" },
  "linux-x64-musl": { zig: "x86_64-linux-musl", format: "elf", cpu: "x64", libc: "musl" },
  "linux-arm64-gnu": { zig: "aarch64-linux-gnu.2.17", format: "elf", cpu: "arm64", libc: "glibc" },
  "linux-arm64-musl": { zig: "aarch64-linux-musl", format: "elf", cpu: "arm64", libc: "musl" },
  "darwin-x64": { zig: "x86_64-macos.10.15", format: "macho", cpu: "x64" },
  "darwin-arm64": { zig: "aarch64-macos.11.0", format: "macho", cpu: "arm64" },
};
const GLIBC_BASELINE = [2, 17];
/**
 * Fused multiply-add instructions an arm64 artifact may contain. Today two, both the same source expression:
 * `@mod(t, 2) == 1` (is the dotted / dashed decoration thickness odd) in paint_text.paintDecoLine and
 * svg_out_text.paintDecoLine. LLVM lowers a float remainder by a power of two to `t - 2 * trunc(t * 0.5)` and
 * emits it as one fmsub; the product by 2 is exact, so the fused and the unfused forms give the same bits (the
 * result is identical to wasm / x86-64). (The PDF emitter's copy of that code, pdf/emit_text.paintDecoLine,
 * tests the parity on the integer instead, so it adds none.)
 * Any other count means the compiler contracted a multiply and an add on its own, or the source gained /
 * lost such an expression: run with --explain-fused to see the functions; prefer rewriting the expression
 * (integer math) to raising this number, and raise it only for a provably exact case like the one above.
 */
const FUSED_EXPECTED = 2;
/** libm entry points: none may be imported (the engine's own / compiler-rt implementations must be used). */
const MATH = new Set(["sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh", "tanh", "exp", "exp2", "expm1", "log", "log2", "log10", "log1p",
  "pow", "sqrt", "cbrt", "hypot", "floor", "ceil", "round", "trunc", "rint", "nearbyint", "fmod", "remainder", "fma", "fabs", "fmin", "fmax", "ldexp", "frexp",
  "modf", "scalbn", "copysign", "lround", "lrint", "sincos"].flatMap((n) => [n, n + "f", n + "l"]));

const fileOf = (name) => path.join(root, "native", "dist", name, `bm-render.${name}.node`);

/** The Node-API functions the addon uses: the field names of `Api` in src/native/napi.zig. */
export function napiSymbols() {
  const src = readFileSync(path.join(root, "src", "native", "napi.zig"), "utf8");
  const body = /pub const Api = struct \{([\s\S]*?)\n\};/.exec(src);
  if (!body) throw new Error("src/native/napi.zig: `pub const Api = struct` not found");
  return [...body[1].matchAll(/^\s+(napi_\w+)\s*:/gm)].map((m) => m[1]).sort();
}

function findZig() {
  const cands = [process.env.ZIG, "zig", "C:/Users/admini/Downloads/zig-x86_64-windows-0.17.1/zig-x86_64-windows-0.17.1/zig.exe"].filter(Boolean);
  for (const z of cands) {
    const r = spawnSync(z, ["version"], { encoding: "utf8" });
    if (r.status === 0) return { zig: z, version: r.stdout.trim() };
  }
  throw new Error("zig not found (set ZIG=<path to zig 0.17>)");
}

// ---- binary parsers (only what the checks need) ------------------------------------------------------------

const cstr = (b, off) => { let e = off; while (e < b.length && b[e] !== 0) e++; return b.toString("latin1", off, e); };

function parsePe(b) {
  if (b.readUInt16LE(0) !== 0x5a4d) throw new Error("not a PE file");
  const pe = b.readUInt32LE(0x3c);
  if (b.readUInt32LE(pe) !== 0x4550) throw new Error("bad PE signature");
  const machine = b.readUInt16LE(pe + 4);
  const nsec = b.readUInt16LE(pe + 6);
  const optSize = b.readUInt16LE(pe + 20);
  const characteristics = b.readUInt16LE(pe + 22);
  const opt = pe + 24;
  if (b.readUInt16LE(opt) !== 0x20b) throw new Error("not PE32+");
  const dir = (i) => ({ rva: b.readUInt32LE(opt + 112 + i * 8), size: b.readUInt32LE(opt + 116 + i * 8) });
  const sections = [];
  for (let i = 0; i < nsec; i++) {
    const s = opt + optSize + i * 40;
    sections.push({ name: cstr(b.subarray(s, s + 8), 0), vsize: b.readUInt32LE(s + 8), rva: b.readUInt32LE(s + 12), rawSize: b.readUInt32LE(s + 16), raw: b.readUInt32LE(s + 20), flags: b.readUInt32LE(s + 36) });
  }
  const off = (rva) => { const s = sections.find((x) => rva >= x.rva && rva < x.rva + Math.max(x.vsize, x.rawSize)); if (!s) throw new Error("bad RVA " + rva); return rva - s.rva + s.raw; };
  const exports = [];
  const ed = dir(0);
  if (ed.rva) {
    const e = off(ed.rva);
    const n = b.readUInt32LE(e + 24);
    const names = off(b.readUInt32LE(e + 32));
    for (let i = 0; i < n; i++) exports.push(cstr(b, off(b.readUInt32LE(names + i * 4))));
  }
  const imports = {};
  const id = dir(1);
  if (id.rva) {
    for (let d = off(id.rva); b.readUInt32LE(d + 12) !== 0; d += 20) {
      const dll = cstr(b, off(b.readUInt32LE(d + 12))).toLowerCase();
      const list = (imports[dll] ??= []);
      let t = off(b.readUInt32LE(d) || b.readUInt32LE(d + 16));
      for (;; t += 8) {
        const v = b.readBigUInt64LE(t);
        if (v === 0n) break;
        list.push(v >> 63n ? "#" + (v & 0xffffn) : cstr(b, off(Number(v & 0x7fffffffn)) + 2));
      }
    }
  }
  const tls = dir(9).rva !== 0;
  const code = sections.filter((s) => s.flags & 0x20000000).map((s) => b.subarray(s.raw, s.raw + Math.min(s.rawSize, s.vsize || s.rawSize)));
  return { machine, dll: (characteristics & 0x2000) !== 0, exports, imports, tls, code };
}

function parseElf(b) {
  if (b.readUInt32BE(0) !== 0x7f454c46) throw new Error("not an ELF file");
  if (b[4] !== 2 || b[5] !== 1) throw new Error("not ELF64 little-endian");
  const type = b.readUInt16LE(16);
  const machine = b.readUInt16LE(18);
  const u64 = (o) => Number(b.readBigUInt64LE(o));
  const phoff = u64(32), shoff = u64(40), phentsize = b.readUInt16LE(54), phnum = b.readUInt16LE(56), shentsize = b.readUInt16LE(58), shnum = b.readUInt16LE(60), shstrndx = b.readUInt16LE(62);
  const ph = [];
  for (let i = 0; i < phnum; i++) { const o = phoff + i * phentsize; ph.push({ type: b.readUInt32LE(o), flags: b.readUInt32LE(o + 4), offset: u64(o + 8), vaddr: u64(o + 16), filesz: u64(o + 32) }); }
  const sh = [];
  for (let i = 0; i < shnum; i++) { const o = shoff + i * shentsize; sh.push({ nameOff: b.readUInt32LE(o), type: b.readUInt32LE(o + 4), flags: u64(o + 8), addr: u64(o + 16), offset: u64(o + 24), size: u64(o + 32), link: b.readUInt32LE(o + 40), info: b.readUInt32LE(o + 44), entsize: u64(o + 56) }); }
  for (const s of sh) s.name = cstr(b, sh[shstrndx].offset + s.nameOff);
  const dynsym = sh.find((s) => s.type === 11);
  if (!dynsym) throw new Error("no .dynsym");
  const dynstr = sh[dynsym.link];
  const versym = sh.find((s) => s.type === 0x6fffffff);
  const verneed = sh.find((s) => s.type === 0x6ffffffe);
  const versions = {}; // index -> "GLIBC_2.17"
  const needVersions = [];
  if (verneed) {
    let o = verneed.offset;
    for (let i = 0; i < verneed.info; i++) {
      const cnt = b.readUInt16LE(o + 2), file = cstr(b, sh[verneed.link].offset + b.readUInt32LE(o + 4)), aux = b.readUInt32LE(o + 8), next = b.readUInt32LE(o + 12);
      let a = o + aux;
      for (let k = 0; k < cnt; k++) {
        const name = cstr(b, sh[verneed.link].offset + b.readUInt32LE(a + 8));
        versions[b.readUInt16LE(a + 6)] = name;
        needVersions.push({ file, name });
        a += b.readUInt32LE(a + 12);
      }
      o += next;
    }
  }
  const defined = [], undefinedSyms = [];
  for (let i = 1; i < dynsym.size / 24; i++) {
    const o = dynsym.offset + i * 24;
    const name = cstr(b, dynstr.offset + b.readUInt32LE(o));
    const info = b[o + 4], shndx = b.readUInt16LE(o + 6);
    const bind = info >> 4;
    if (!name) continue;
    const ver = versym ? versions[b.readUInt16LE(versym.offset + i * 2) & 0x7fff] : undefined;
    if (shndx === 0) undefinedSyms.push({ name, weak: bind === 2, version: ver });
    else if (bind === 1 || bind === 2) defined.push(name);
  }
  const needed = [];
  let soname = null;
  const dyn = sh.find((s) => s.type === 6);
  if (dyn) {
    for (let o = dyn.offset; o < dyn.offset + dyn.size; o += 16) {
      const tag = u64(o), val = u64(o + 8);
      if (tag === 0) break;
      if (tag === 1) needed.push(cstr(b, sh[dyn.link].offset + val));
      if (tag === 14) soname = cstr(b, sh[dyn.link].offset + val);
    }
  }
  const code = sh.filter((s) => s.type === 1 && (s.flags & 4)).map((s) => b.subarray(s.offset, s.offset + s.size));
  return { type, machine, needed, soname, defined, undefined: undefinedSyms, needVersions, tls: ph.some((p) => p.type === 7), interp: ph.some((p) => p.type === 3), execStack: ph.some((p) => p.type === 0x6474e551 && (p.flags & 1)), code };
}

function parseMacho(b) {
  if (b.readUInt32LE(0) !== 0xfeedfacf) throw new Error("not a 64-bit Mach-O file");
  const cputype = b.readUInt32LE(4), filetype = b.readUInt32LE(12), ncmds = b.readUInt32LE(16), flags = b.readUInt32LE(24);
  const dylibs = [], code = [];
  let symtab = null, signed = false, minos = null, bindStreams = [];
  let o = 32;
  for (let i = 0; i < ncmds; i++) {
    const cmd = b.readUInt32LE(o), size = b.readUInt32LE(o + 4);
    const base = cmd & 0x7fffffff;
    if (base === 0xc || base === 0x18 || base === 0x1f) dylibs.push(cstr(b, o + b.readUInt32LE(o + 8))); // LOAD_DYLIB, LOAD_WEAK_DYLIB, REEXPORT_DYLIB
    if (cmd === 0x2) symtab = { symoff: b.readUInt32LE(o + 8), nsyms: b.readUInt32LE(o + 12), stroff: b.readUInt32LE(o + 16) };
    if (cmd === 0x1d) signed = true; // LC_CODE_SIGNATURE
    if (base === 0x22) bindStreams = [[b.readUInt32LE(o + 16), b.readUInt32LE(o + 20)], [b.readUInt32LE(o + 24), b.readUInt32LE(o + 28)], [b.readUInt32LE(o + 32), b.readUInt32LE(o + 36)]]; // LC_DYLD_INFO: bind, weak bind, lazy bind
    if (cmd === 0x32) { const v = b.readUInt32LE(o + 12); minos = `${v >> 16}.${(v >> 8) & 255}`; } // LC_BUILD_VERSION
    if (cmd === 0x19) { // LC_SEGMENT_64
      const nsects = b.readUInt32LE(o + 64);
      for (let k = 0; k < nsects; k++) {
        const s = o + 72 + k * 80;
        const sflags = b.readUInt32LE(s + 64);
        if (sflags & 0x80000400) code.push(b.subarray(b.readUInt32LE(s + 48), b.readUInt32LE(s + 48) + Number(b.readBigUInt64LE(s + 40)))); // pure / some instructions
      }
    }
    o += size;
  }
  const defined = [], undefinedSyms = [];
  if (symtab) {
    for (let i = 0; i < symtab.nsyms; i++) {
      const s = symtab.symoff + i * 16;
      const name = cstr(b, symtab.stroff + b.readUInt32LE(s));
      const type = b[s + 4], desc = b.readUInt16LE(s + 6);
      if (type & 0xe0) continue; // debug (stab) entries
      if (!(type & 1)) continue; // not external
      if ((type & 0x0e) === 0) undefinedSyms.push({ name: name.replace(/^_/, ""), ordinal: desc >> 8 });
      else defined.push(name.replace(/^_/, ""));
    }
  }
  // What dyld really follows: the bind opcodes. Library ordinal per bound symbol: 1.. = LC_LOAD_DYLIB index,
  // 0 = this image, -1 = main executable, -2 = flat lookup (any loaded image: `-undefined dynamic_lookup`).
  const binds = {};
  for (const [off, size] of bindStreams) {
    let p = off, ordinal = 0, sym = "";
    const end = off + size;
    const uleb = () => { let v = 0, shift = 0, c; do { c = b[p++]; v += (c & 0x7f) * 2 ** shift; shift += 7; } while (c & 0x80); return v; };
    while (p < end) {
      const op = b[p] & 0xf0, imm = b[p] & 0x0f;
      p++;
      if (op === 0x10) ordinal = imm;
      else if (op === 0x20) ordinal = uleb();
      else if (op === 0x30) ordinal = imm === 0 ? 0 : (imm | 0xf0) - 256;
      else if (op === 0x40) { sym = cstr(b, p).replace(/^_/, ""); p += cstr(b, p).length + 1; }
      else if (op === 0x60 || op === 0x70 || op === 0x80) uleb();
      else if (op === 0x90 || op === 0xb0) binds[sym] = ordinal;
      else if (op === 0xa0) { binds[sym] = ordinal; uleb(); }
      else if (op === 0xc0) { binds[sym] = ordinal; uleb(); uleb(); }
    }
  }
  return { cputype, filetype, twolevel: (flags & 0x80) !== 0, dylibs, defined, undefined: undefinedSyms, binds, signed, minos, tls: (flags & 0x800000) !== 0, code };
}

/** Fused multiply-add instructions (A64) in executable sections: FMADD / FMSUB / FNMADD / FNMSUB, FMLA / FMLS. */
export function countFusedA64(code) {
  let n = 0;
  const first = [];
  for (const sec of code) {
    for (let i = 0; i + 4 <= sec.length; i += 4) {
      const w = sec.readUInt32LE(i);
      const hit = (w >>> 24) === 0x1f || // scalar fmadd family
        (w & 0xbfa0fc00) >>> 0 === 0x0e20cc00 || (w & 0xbfa0fc00) >>> 0 === 0x0ea0cc00 || // vector fmla / fmls
        (w & 0xbf80f400) >>> 0 === 0x0f801000 || (w & 0xbf80f400) >>> 0 === 0x0f805000 || // by element
        (w & 0xff80f400) >>> 0 === 0x5f801000 || (w & 0xff80f400) >>> 0 === 0x5f805000; // scalar by element
      if (hit) { n++; if (first.length < 4) first.push("0x" + w.toString(16).padStart(8, "0")); }
    }
  }
  return { n, first };
}

/** Structural checks of one artifact; returns { ok, facts, problems }. */
export function verify(name, file = fileOf(name)) {
  const t = TARGETS[name];
  const b = readFileSync(file);
  const napi = napiSymbols();
  const problems = [];
  const facts = [];
  const need = (cond, msg) => { if (!cond) problems.push(msg); };
  const sameSet = (got, what) => {
    const missing = napi.filter((s) => !got.includes(s)), extra = got.filter((s) => !napi.includes(s));
    need(missing.length === 0 && extra.length === 0, `${what}: ${missing.length ? "missing " + missing.join(",") : ""} ${extra.length ? "unexpected " + extra.join(",") : ""}`);
  };
  let code = [];
  if (t.format === "pe") {
    const pe = parsePe(b);
    code = pe.code;
    need(pe.machine === (t.cpu === "x64" ? 0x8664 : 0xaa64), `machine 0x${pe.machine.toString(16)}`);
    need(pe.dll, "not a DLL");
    need(pe.exports.includes("napi_register_module_v1"), "napi_register_module_v1 is not exported");
    const dlls = Object.keys(pe.imports);
    need(dlls.every((d) => d === "kernel32.dll" || d === "ntdll.dll"), `unexpected DLL imports: ${dlls.join(", ")}`);
    need(!dlls.some((d) => /node/.test(d)), "imports from a node executable (must be looked up at run time)");
    const text = b.toString("latin1");
    need(napi.every((s) => text.includes(s + "\0")), "a Node-API lookup name is missing from the binary");
    need(Object.values(pe.imports).flat().every((s) => !MATH.has(s)), "imports a math function");
    facts.push(`PE32+ DLL ${t.cpu}`, `exports ${pe.exports.join(",")}`, `imports ${dlls.map((d) => `${d}(${pe.imports[d].length})`).join(" ")}`, `${napi.length} napi names resolved at run time`, pe.tls ? "TLS directory" : "no TLS");
  } else if (t.format === "elf") {
    const elf = parseElf(b);
    code = elf.code;
    need(elf.type === 3, "not a shared object (ET_DYN)");
    need(elf.machine === (t.cpu === "x64" ? 62 : 183), `e_machine ${elf.machine}`);
    need(!elf.interp, "has PT_INTERP (an executable, not a plain shared object)");
    need(!elf.tls, "has a PT_TLS segment (thread-local storage)");
    need(!elf.execStack, "executable stack");
    need(elf.defined.includes("napi_register_module_v1"), "napi_register_module_v1 is not exported");
    const und = elf.undefined.map((s) => s.name);
    sameSet(und.filter((s) => s.startsWith("napi_")), "undefined napi symbols");
    need(und.every((s) => !MATH.has(s)), `imports math functions: ${und.filter((s) => MATH.has(s)).join(",")}`);
    const okLibs = t.libc === "glibc" ? /^(libc\.so\.6|libpthread\.so\.0|libdl\.so\.2|libm\.so\.6|librt\.so\.1|ld-linux-(x86-64|aarch64)\.so\.[12])$/ : /^libc\.so$/;
    need(elf.needed.every((n) => okLibs.test(n)), `unexpected DT_NEEDED: ${elf.needed.join(", ")}`);
    let maxv = [0, 0];
    for (const v of elf.needVersions) {
      const m = /^GLIBC_(\d+)\.(\d+)/.exec(v.name);
      if (!m) { if (t.libc === "musl" || !/^GLIBC_PRIVATE$/.test(v.name)) problems.push(`unexpected symbol version ${v.name} (${v.file})`); continue; }
      const cur = [+m[1], +m[2]];
      if (cur[0] > maxv[0] || (cur[0] === maxv[0] && cur[1] > maxv[1])) maxv = cur;
    }
    if (t.libc === "glibc") need(maxv[0] < GLIBC_BASELINE[0] || (maxv[0] === GLIBC_BASELINE[0] && maxv[1] <= GLIBC_BASELINE[1]), `needs GLIBC_${maxv.join(".")} > ${GLIBC_BASELINE.join(".")}`);
    else need(elf.needVersions.length === 0, "musl build with versioned symbol requirements");
    const libc = und.filter((s) => !s.startsWith("napi_"));
    facts.push(`ELF64 ET_DYN ${t.cpu}`, `NEEDED ${elf.needed.join(" ") || "(none)"}`, t.libc === "glibc" ? `max GLIBC_${maxv.join(".")}` : "no symbol versions", `${und.length - libc.length} undefined napi_*`, `${libc.length} libc imports (${libc.join(" ")})`, "no PT_TLS");
  } else {
    const m = parseMacho(b);
    code = m.code;
    need(m.cputype === (t.cpu === "x64" ? 0x01000007 : 0x0100000c), `cputype 0x${m.cputype.toString(16)}`);
    need(m.filetype === 6 || m.filetype === 8, `filetype ${m.filetype} (want MH_DYLIB or MH_BUNDLE)`);
    need(m.defined.includes("napi_register_module_v1"), "napi_register_module_v1 is not exported");
    need(m.dylibs.every((d) => d === "/usr/lib/libSystem.B.dylib"), `unexpected dylibs: ${m.dylibs.join(", ")}`);
    const und = m.undefined.map((s) => s.name);
    const napiUnd = m.undefined.filter((s) => s.name.startsWith("napi_"));
    sameSet(napiUnd.map((s) => s.name), "undefined napi symbols");
    // bound by flat lookup (-2): searched in every loaded image, i.e. found in the node binary, whatever its name
    const lookups = napi.map((s) => m.binds[s]);
    need(lookups.every((o) => o === -2), `napi symbols are not bound by dynamic (flat) lookup: ordinals ${[...new Set(lookups)].join(",")}`);
    need(Object.entries(m.binds).every(([s, o]) => s.startsWith("napi_") || o === 1), `a non-napi symbol is not bound to libSystem: ${Object.entries(m.binds).filter(([s, o]) => !s.startsWith("napi_") && o !== 1).map(([s, o]) => s + ":" + o).join(",")}`);
    need(und.every((s) => !MATH.has(s)), `imports math functions: ${und.filter((s) => MATH.has(s)).join(",")}`);
    need(!m.tls, "uses thread-local variables");
    if (t.cpu === "arm64") need(m.signed, "arm64 Mach-O without a code signature (will not load)");
    const sys = und.filter((s) => !s.startsWith("napi_"));
    facts.push(`Mach-O ${m.filetype === 6 ? "dylib" : "bundle"} ${t.cpu}`, `minos ${m.minos}`, `dylibs ${m.dylibs.join(" ")}`, `${napiUnd.length} napi_* by dynamic lookup`, `${sys.length} libSystem imports (${sys.join(" ")})`, m.signed ? "ad-hoc signed" : "unsigned");
  }
  if (t.cpu === "arm64") {
    const f = countFusedA64(code);
    need(f.n === FUSED_EXPECTED, `${f.n} fused multiply-add instruction(s) in the code, expected the ${FUSED_EXPECTED} known exact ones (${f.first.join(" ")}); see --explain-fused`);
    facts.push(`fused multiply-add instructions: ${f.n} (the ${FUSED_EXPECTED} exact power-of-two remainders)`);
  } else {
    facts.push("x86-64-v2 code (SSE4.2; no AVX / FMA), CPU checked at registration");
  }
  return { ok: problems.length === 0, facts, problems, bytes: b.length, gzip: gzipSync(b, { level: 9 }).length, sha256: createHash("sha256").update(b).digest("hex") };
}

// ---- main ------------------------------------------------------------------------------------------------

/** --explain-fused: an unstripped arm64 ELF build, every fused instruction attributed to its function. */
function explainFused() {
  const zig = findZig();
  const prefix = path.join(root, "zig-out", "explain-fused");
  const r = spawnSync(zig.zig, ["build", "native", "-Dtarget=aarch64-linux-musl", "-Dnative-strip=false", "--prefix", prefix], { cwd: root, stdio: "inherit" });
  if (r.status !== 0) process.exit(1);
  const b = readFileSync(path.join(prefix, "native", "bm-render.linux-arm64-musl.node"));
  const u64 = (o) => Number(b.readBigUInt64LE(o));
  const shoff = u64(40), shentsize = b.readUInt16LE(58), shnum = b.readUInt16LE(60);
  const sh = [];
  for (let i = 0; i < shnum; i++) { const o = shoff + i * shentsize; sh.push({ type: b.readUInt32LE(o + 4), flags: u64(o + 8), addr: u64(o + 16), offset: u64(o + 24), size: u64(o + 32), link: b.readUInt32LE(o + 40) }); }
  const symtab = sh.find((s) => s.type === 2);
  const syms = [];
  for (let i = 0; i < symtab.size / 24; i++) { const o = symtab.offset + i * 24; if ((b[o + 4] & 15) === 2) syms.push({ name: cstr(b, sh[symtab.link].offset + b.readUInt32LE(o)), addr: u64(o + 8) }); }
  syms.sort((x, y) => x.addr - y.addr);
  let n = 0;
  for (const s of sh.filter((x) => x.type === 1 && (x.flags & 4))) {
    for (let i = 0; i + 4 <= s.size; i += 4) {
      if (countFusedA64([b.subarray(s.offset + i, s.offset + i + 4)]).n === 0) continue;
      const addr = s.addr + i;
      const f = syms.findLast((x) => x.addr <= addr);
      console.log(`0x${addr.toString(16)}  0x${b.readUInt32LE(s.offset + i).toString(16)}  in ${f ? f.name : "?"}`);
      n++;
    }
  }
  console.log(`${n} fused multiply-add instruction(s); expected ${FUSED_EXPECTED} (FUSED_EXPECTED in this script)`);
  process.exit(n === FUSED_EXPECTED ? 0 : 1);
}

function main() {
  if (opts["explain-fused"]) return explainFused();
  const names = opts.target ? String(opts.target).split(",") : Object.keys(TARGETS);
  for (const n of names) if (!TARGETS[n]) { console.error(`unknown target ${n} (${Object.keys(TARGETS).join(", ")})`); process.exit(2); }
  const optimize = String(opts.optimize || "fast");
  const host = `${process.platform}-${process.arch}`;
  let zig = null;
  if (!opts["verify-only"]) {
    zig = findZig();
    console.log(`zig ${zig.version}, optimize=${optimize}, ${names.length} target(s)`);
  }
  const rows = [];
  let failed = false;
  for (const name of names) {
    const t = TARGETS[name];
    const out = fileOf(name);
    if (zig) {
      const t0 = Date.now();
      const r = spawnSync(zig.zig, ["build", "native", `-Dtarget=${t.zig}`, `-Dnative-optimize=${optimize}`], { cwd: root, stdio: "inherit" });
      if (r.status !== 0) { console.error(`${name}: zig build failed`); failed = true; rows.push({ name, status: "BUILD FAILED" }); continue; }
      mkdirSync(path.dirname(out), { recursive: true });
      copyFileSync(path.join(root, "zig-out", "native", `bm-render.${name}.node`), out);
      console.log(`${name}: built in ${((Date.now() - t0) / 1000).toFixed(0)} s`);
    } else if (!existsSync(out)) { rows.push({ name, status: "missing" }); failed = true; continue; }
    let v;
    try { v = verify(name, out); } catch (e) { v = { ok: false, facts: [], problems: [String(e && e.message)], bytes: statSync(out).size, gzip: 0 }; }
    if (!v.ok) failed = true;
    rows.push({ name, zig: t.zig, ...v, status: v.ok ? "verified" : "VERIFY FAILED" });
    console.log(`${name}: ${v.ok ? "structure ok" : "STRUCTURE PROBLEMS"}\n    ${v.facts.join("\n    ")}${v.problems.length ? "\n  ! " + v.problems.join("\n  ! ") : ""}`);
  }
  console.log("\ntarget              zig triple               bytes      gzip -9   status");
  for (const r of rows) console.log(`${r.name.padEnd(19)} ${(r.zig || "").padEnd(24)} ${String(r.bytes ?? "").padStart(9)} ${String(r.gzip ?? "").padStart(9)}   ${r.status}${r.name.replace(/-(msvc|gnu|musl)$/, "").replace("win32", "win32") === host ? "  (this host: runnable)" : ""}`);
  if (zig) {
    mkdirSync(path.join(root, "native", "dist"), { recursive: true });
    const manifest = path.join(root, "native", "dist", "manifest.json");
    let prev = {};
    try { prev = JSON.parse(readFileSync(manifest, "utf8")).files || {}; } catch {}
    const mine = Object.fromEntries(rows.filter((r) => r.bytes).map((r) => [r.name, { file: `${r.name}/bm-render.${r.name}.node`, zigTarget: r.zig, optimize, bytes: r.bytes, gzip: r.gzip, sha256: r.sha256, verified: r.status === "verified", facts: r.facts }]));
    writeFileSync(manifest, JSON.stringify({ date: new Date().toISOString(), zig: zig.version, napi: napiSymbols(), files: { ...prev, ...mine } }, null, 2) + "\n");
  }
  process.exit(failed ? 1 : 0);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
