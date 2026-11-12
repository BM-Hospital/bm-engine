import { both } from "./lib.mjs";
const B = { display: "block", height: 5, backgroundColor: "red" };
const T = (text, style) => ({ type: "text", text, style: { fontFamily: "Inter", ...style } });
const cases = {
  flexWs: { type: "container", style: { display: "flex", width: 100 }, children: [T(" ", { width: 10, height: 5 }), T("a"), T("  ", { width: 10 })] },
  afterInline: { type: "container", style: { display: "block", width: 100 }, children: [T("a"), T(" ", B), T(" ", B)] },
  pre: { type: "container", style: { display: "block", width: 100 }, children: [T(" ", { ...B, whiteSpace: "pre" }), T(" ", B)] },
  inlineFirst: { type: "container", style: { display: "block", width: 100 }, children: [T(" ", { padding: 4, backgroundColor: "red" }), T("x")] },
  absThen: { type: "container", style: { display: "block", width: 100 }, children: [T("a", { position: "absolute" }), T(" ", B), T("b", { display: "block" })] },
  html: `<div style="width:100px"><span class="q"> </span><p style="margin:0;height:5px"></p> <span style="display:block;height:4px"> </span></div>`,
  inlineParent: { type: "container", style: { display: "block", width: 100 }, children: [{ type: "container", children: [T(" ", B), T("z")] }] },
};
for (const [k, node] of Object.entries(cases)) {
  const r = await both((e) => e.measure(node, { width: 100, height: 100 }));
  const f = (m) => typeof m === "string" ? m : JSON.stringify(m.children.map((c) => [c.width, c.height, c.transform[5], c.children.length]));
  console.log(k.padEnd(14), "tk", f(r.tk), "\n".padEnd(16), "bm", f(r.bm));
}
