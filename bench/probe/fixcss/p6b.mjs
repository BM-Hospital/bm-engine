import { tk, bm } from "./lib.mjs";
const kids = (n, tw = "w-4 h-4 bg-black") => Array.from({ length: n }, () => ({ type: "container", tw, children: [] }));
const cases = {
  "space-x-4": { type: "container", tw: "flex space-x-4", children: kids(3) },
  "space-y-2": { type: "container", tw: "flex flex-col space-y-2", children: kids(3) },
  "space-x-reverse": { type: "container", tw: "flex flex-row-reverse space-x-4 space-x-reverse", children: kids(3) },
  "-space-x-2": { type: "container", tw: "flex -space-x-2", children: kids(3) },
  "space-x-[13px]": { type: "container", tw: "flex space-x-[13px]", children: kids(3) },
  "html class": `<div class="flex p-4 gap-2"><div class="w-4 h-4 bg-black"></div><div class="w-4 h-4 bg-black"></div></div>`,
  "html tw attr": `<div tw="flex p-4 gap-2"><div tw="w-4 h-4 bg-black"></div><div tw="w-4 h-4 bg-black"></div></div>`,
  "html hidden": `<div style="display:flex"><div hidden style="width:10px;height:10px;display:block"></div><div style="width:20px;height:10px"></div></div>`,
  "tagName ul": { type: "container", style: { display: "block" }, children: [{ type: "container", tagName: "p", children: [{ type: "text", text: "x" }] }, { type: "container", tagName: "h1", children: [{ type: "text", text: "y" }] }] },
  "inline container": { type: "container", style: { display: "block" }, children: [{ type: "container", children: [{ type: "text", text: "abc" }] }, { type: "container", style: { display: "inline" }, children: [{ type: "text", text: "d" }] }] },
};
const walk = (m, d = 0, out = []) => { if (typeof m === "string") return [m]; out.push("  ".repeat(d) + m.width + "x" + m.height + "@" + m.transform[4] + "," + m.transform[5] + (m.runs?.length ? " runs" + m.runs.length : "")); m.children.forEach((c) => walk(c, d + 1, out)); return out; };
for (const [k, node] of Object.entries(cases)) {
  const r = {}; for (const [n, e] of [["tk", tk], ["bm", bm]]) { try { r[n] = walk(await e.measure(node, { width: 200, height: 100 })).join(" | "); } catch (er) { r[n] = "ERR " + er.message; } }
  console.log((r.tk === r.bm ? "   " : "!! ") + k.padEnd(18), "tk", r.tk, r.tk === r.bm ? "" : "\n" + " ".repeat(22) + "bm " + r.bm);
}
