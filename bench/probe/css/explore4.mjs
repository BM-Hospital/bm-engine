import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const P = { display: "flex", width: 1, height: 1, flexShrink: 0 };
const t = { type: "container", tagName: "div", preset: P, children: [ { type: "container", tagName: "u", className: "z", preset: P } ] };
for (const s of ["u:not(:foo(x))", "u:not(:foo)", "u:not(:nth-child(1 of u))", "u:not(:is())", "u:not(:where())", "u:not(:any(u))", "u:not(:host(x))", "u:not(:host)", "u:not(:lang('en'))", "u:not(:dir(foo))", "u:not(:state(x))", "u:not(:has(x))", "u:not(:hover)", "u:not(:defined)", "u:not(:scope)", "u:not(:-webkit-any(x))", "u:not(:matches(x))", "u:not(:link)", "u:not(:first-line)", "u:not(:nth-child(2n+))", "u:is(:foo(x), u)", "u:not(:is(:foo(x)))", "u:not(:has(:has(x)))", "u:not(:not())", "u:not(:has())", "u:not(:has(> x))", "u:not(:has(:hover))"]) {
  const m = await r.measure(t, { width: 100, height: 100, css: [`${s}{width:5px}`] });
  console.log(s.padEnd(28), m.children[0].width === 5 ? "MATCH" : "-");
}
