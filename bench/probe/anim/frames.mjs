// Shadow-stack frame size of every wasm function whose name matches argv[3] (regex), read from the
// prologue `__stack_pointer - N`. Needs an unstripped build (`zig build -Dstrip=false -p <dir>`).
// Usage (from bench/): node probe/anim/frames.mjs <path/to/bm_engine.wasm> [regex]
import { readFileSync } from "node:fs";
import binaryen from "binaryen";

const mod = binaryen.readBinary(readFileSync(process.argv[2]));
const text = mod.emitText();
const re = new RegExp(process.argv[3] || "render\\.Frame|dom\\.Dom|animate\\.");
const funcs = text.split(/\n \(func /).slice(1);
const rows = [];
for (const f of funcs) {
  const name = f.slice(0, f.indexOf(" ")).replace(/^\$/, "");
  if (!re.test(name)) continue;
  // first stack-pointer subtraction in the body
  const m = f.match(/global\.get \$__stack_pointer\)\s*\(i32\.const (\d+)\)/) || f.match(/i32\.sub\s*\(global\.get \$__stack_pointer\)\s*\(i32\.const (\d+)\)/);
  rows.push([m ? Number(m[1]) : 0, name]);
}
rows.sort((a, b) => b[0] - a[0]);
for (const [n, name] of rows) console.log(String(n).padStart(6), name);
