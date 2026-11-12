import { both, px } from "./lib.mjs";
const css = [".x{display:block;height:1px} .x:first-child{height:2px} .x:last-child{height:3px} .y{display:block;height:1px} .y:nth-child(2){height:5px} .y:nth-last-child(1){width:50px} .y:nth-of-type(1){width:60px} .y+.y{width:7px} .z ~ .z{width:9px} .o:only-child{height:4px;display:block} .e:empty{width:11px}"];
const T = (cls, text = "a", extra = {}) => ({ type: "text", text, className: cls, ...extra });
const C = (cls, extra = {}) => ({ type: "container", className: cls, style: { display: "block" }, ...extra });
const cases = {
  nth: [T("y"), T("y"), T("y")],
  nthTag: [T("y", "a", { tagName: "span" }), T("y", "a", { tagName: "span" }), T("y", "a", { tagName: "p" })],
  nthTagMix: [T("y", "a", { tagName: "span" }), T("y"), T("y", "a", { tagName: "span" })],
  sib: [T("z", "a", { style: { display: "block" } }), C("z"), T("z", "a", { style: { display: "block" } })],
  xTag: [T("x", "a", { tagName: "span" }), T("x", "a", { tagName: "span" }), T("x", "a", { tagName: "span" })],
  only: [T("o")],
  emptyDiv: [C("e", { children: [{ type: "text", text: "" }] }), C("e", { children: [{ type: "text", text: " " }] }), C("e")],
  emptyTextBlock: [T("x", ""), C("x"), T("x", "")],
  twTag: [1,2,3].map(() => ({ type: "text", text: "a", tagName: "span", tw: "block h-px first:h-2 last:h-3 odd:w-4 even:w-5" })),
};
for (const [k, ch] of Object.entries(cases)) {
  const node = { type: "container", style: { display: "block", width: 100 }, children: ch };
  const r = await both((e) => e.measure(node, { width: 100, height: 100, css }));
  const f = (m) => typeof m === "string" ? m : JSON.stringify(m.children.map((c) => [c.width, c.height]));
  console.log(k.padEnd(16), "tk", f(r.tk), " bm", f(r.bm));
}
// does an empty display:block text node paint?
const node = { type: "container", style: { display: "block", width: 20, height: 20 }, children: [{ type: "text", text: "", style: { display: "block", height: 10, backgroundColor: "red" } }] };
const r = await both(async (e) => [...(await e.render(node, { width: 20, height: 20, format: "raw" })).slice(0, 4)]);
console.log("empty text paint", r);
