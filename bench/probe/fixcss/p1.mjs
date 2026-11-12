import { both, slim } from "./lib.mjs";
const css = [".x{display:block;height:1px} .x:first-child{height:2px} .x:last-child{height:3px} .y{display:block;height:1px} .y:nth-child(2){height:5px} .y+.y{width:7px} .z ~ .z{width:9px} .o:only-child{height:4px;display:block}"];
const T = (cls, text = "") => ({ type: "text", text, className: cls });
const C = (cls) => ({ type: "container", className: cls });
const cases = {
  textEmpty: [T("x"), T("x"), T("x")],
  textNonEmpty: [T("x", "a"), T("x", "b"), T("x", "c")],
  containers: [C("x"), C("x"), C("x")],
  mixed: [C("x"), T("x", "a"), C("x")],
  nth: [T("y"), T("y"), T("y")],
  sib: [T("z"), C("z"), T("z")],
  only: [T("o")],
  bareTextBetween: [C("x"), { type: "text", text: "bare" }, C("x")],
  bareTextOnly: [{ type: "text", text: "bare" }, C("o")],
  twFirst: [{ type: "text", text: "", tw: "block h-px first:h-2 last:h-3" }, { type: "text", text: "", tw: "block h-px first:h-2 last:h-3" }, { type: "text", text: "", tw: "block h-px odd:w-4 first:h-2 last:h-3" }],
};
for (const [k, ch] of Object.entries(cases)) {
  const node = { type: "container", style: { display: "block", width: 100 }, children: ch };
  const r = await both((e) => e.measure(node, { width: 100, height: 100, css }));
  const f = (m) => typeof m === "string" ? m : JSON.stringify(m.children.map((c) => [c.width, c.height]));
  console.log(k.padEnd(16), "tk", f(r.tk), " bm", f(r.bm));
}
