// Probe: how takumi orders stylesheet `!important` against inline `style` (shorthand vs longhand, tw).
import { Renderer } from "@takumi-rs/wasm/node";
const t = new Renderer();
async function run(label, rule, style, tw) {
  const node = { type: "container", className: "b", style, tw, children: [] };
  const raw = new Uint8Array(await t.render(node, { width: 10, height: 10, format: "raw", css: [rule] }));
  console.log(label.padEnd(40), Array.from(raw.slice(0, 4)).join(","));
}
const base = "width:10px;height:10px;";
await run("bg shorthand !imp vs inline bgColor", `.b{${base}background:red !important}`, { backgroundColor: "#00ff00" });
await run("bgColor !imp vs inline bgColor", `.b{${base}background-color:red !important}`, { backgroundColor: "#00ff00" });
await run("bgColor !imp vs inline bg shorthand", `.b{${base}background-color:red !important}`, { background: "#00ff00" });
await run("bgColor !imp vs inline bgColor !imp", `.b{${base}background-color:red !important}`, { backgroundColor: "#00ff00 !important" });
await run("bgColor normal vs tw", `.b{${base}background-color:red}`, undefined, "bg-[#00ff00]");
await run("bgColor !imp vs tw", `.b{${base}background-color:red !important}`, undefined, "bg-[#00ff00]");
await run("bgColor normal vs tw !", `.b{${base}background-color:red}`, undefined, "!bg-[#00ff00]");
await run("@layer x bgColor vs tw", `@layer x{.b{${base}background-color:red}}`, undefined, "bg-[#00ff00]");
await run("layered !imp vs tw !imp", `@layer x{.b{${base}background-color:red !important}}`, undefined, "!bg-[#00ff00]");
