// CSS cascade oracle: asks takumi (@takumi-rs/wasm 2.20) which rule wins for every node of small trees
// by measuring widths set by `css` rules, and writes src/css/testdata/oracle.json, replayed by
// `zig test src/css/css.zig` (matching only).
// Every node gets a preset (UA-origin, lowest priority) {display:flex, width:1, height:1, flexShrink:0},
// so a measured width of 1 (CSS px) means "no rule set width". Rules use widths >= 2.
// usage (from bench/): node probe/css/oracle.mjs
import { Renderer } from "@takumi-rs/wasm/node";
import { writeFileSync, mkdirSync } from "node:fs";

const r = new Renderer();
const P = { display: "flex", width: 1, height: 1, flexShrink: 0 };
// e(tag, props, ...children); props: { c: className, id, a: attributes }
const e = (tag, props = {}, ...children) => ({ tag, ...props, children });

const toNode = (n) => {
  const o = { type: "container", preset: P, children: n.children.map(toNode) };
  if (n.tag) o.tagName = n.tag;
  if (n.c !== undefined) o.className = n.c;
  if (n.id !== undefined) o.id = n.id;
  if (n.a) o.attributes = n.a;
  if (n.lang) o.lang = n.lang;
  if (n.dir) o.dir = n.dir;
  return o;
};

const std3 = () => e("div", { id: "root" },
  e("p", { c: "a" }),
  e("span", { c: "b c", id: "s" }),
  e("p", { c: "a b" }),
  e("em"));

const list = () => e("ul", {}, ...Array.from({ length: 7 }, (_, i) => e("li", i === 3 ? { c: "z" } : i === 5 ? { c: "z" } : {})));

const cases = [
  ["type < class", ["p{width:2px} .a{width:3px}"], std3()],
  ["class < id", ["#s{width:4px} .b{width:3px} span{width:2px}"], std3()],
  ["source order", [".a{width:2px} .b{width:3px}"], std3()],
  ["important beats id", ["#s{width:4px} span{width:5px !important}"], std3()],
  ["important order", ["span{width:5px !important} .b{width:6px!important}"], std3()],
  ["where is not", [":where(#s){width:2px} span{width:3px} :is(p, #root){width:4px} p:not(.b){width:5px}"], std3()],
  ["is spec max", [":is(.b, #nope){width:2px} span.b{width:3px}"], std3()],
  ["universal and root", ["*{width:2px} :root{width:3px}"], std3()],
  ["case-insensitive tag", ["DIV{width:2px} P{width:3px}"], e("div", {}, e("P"), e("p"))],
  ["no implicit tag", ["div{width:2px} *{height:1px}"], e(null, {}, e(null), e("div"))],
  ["class splitting", [".x{width:2px} .y{width:3px} .X{width:4px}"], e("div", { c: "  x\ty  " }, e("div", { c: "X" }))],
  ["attributes", ['[data-k]{width:2px} [data-k="v w"]{width:3px} [data-k~=w]{width:4px}', '[data-l|=en]{width:5px} [data-m^=ab]{width:6px} [data-m$=yz]{width:7px} [data-m*=mn]{width:8px}'],
    e("div", {}, e("i", { a: { "data-k": "" } }), e("i", { a: { "data-k": "v w" } }), e("i", { a: { "data-k": "x w y" } }), e("i", { a: { "data-l": "en-US" } }), e("i", { a: { "data-m": "abcd" } }), e("i", { a: { "data-m": "wxyz" } }), e("i", { a: { "data-m": "lmno" } }))],
  ["attribute case", ['[data-v="abc" i]{width:2px} [type=checkbox]{width:3px} [data-v="ABC"]{width:4px} [DATA-W]{width:5px}'],
    e("div", {}, e("i", { a: { "data-v": "ABC" } }), e("input", { a: { type: "CheckBox" } }), e("i", { a: { "data-v": "aBc" } }), e("i", { a: { "data-w": "1" } }))],
  ["combinators", ["div > p{width:2px} div span{width:3px} p + span{width:4px} span ~ em{width:5px} #root > em{width:6px}"], e("div", { id: "root" }, e("p"), e("span"), e("section", {}, e("span"), e("em")), e("em"))],
  ["descendant chain", ["a b c d{width:2px} a > b c{width:3px} a ~ x d{width:4px}"], e("a", {}, e("b", {}, e("x", {}, e("c", {}, e("d")))), e("x", {}, e("d")))],
  ["structural", [":first-child{width:2px} :last-child{width:3px} :only-child{width:4px}"], e("div", {}, e("p", {}, e("i")), e("p"), e("p"))],
  ["of-type", ["p:first-of-type{width:2px} p:last-of-type{width:3px} span:only-of-type{width:4px} em:nth-of-type(2){width:5px} em:nth-last-of-type(1){width:6px}"], e("div", {}, e("p"), e("em"), e("span"), e("p"), e("em"), e("p"), e("em"))],
  ["nth-child formulas", ["li:nth-child(2n+1){width:2px} li:nth-child(3n){width:3px} li:nth-child(-n+2){width:4px}"], list()],
  ["nth-child more", ["li:nth-child(even){width:2px} li:nth-last-child(2){width:3px} li:nth-child(n+6){width:4px} li:nth-child( -2n + 5 ){width:5px}"], list()],
  ["nth-child of", ["li:nth-child(2 of .z){width:2px} li:nth-last-child(1 of .z){width:3px} li:nth-child(odd of :not(.z)){width:4px}"], list()],
  ["empty", [":empty{width:2px}"], e("div", {}, e("p"), e("p", {}, e("i")))],
  ["has", ["div:has(> .t){width:2px} section:has(.t){width:3px} p:has(+ em){width:4px} p:has(~ b){width:5px} :has(> i > .t){width:6px}"], e("section", {}, e("div", {}, e("i", { c: "t" })), e("div", {}, e("i", {}, e("u", { c: "t" }))), e("p"), e("em"), e("p"), e("b"))],
  ["not complex", [":not(div > p){width:2px} p:not(.a, #x){width:3px}"], e("div", {}, e("p", { c: "a" }), e("span", {}, e("p")), e("p"))],
  ["lang dir", [":lang(en){width:2px} :lang(fr){width:3px} :dir(rtl){width:4px} span:dir(ltr){width:5px}"], e("div", { lang: "en-US" }, e("p"), e("p", { lang: "fr" }, e("span")), e("section", { dir: "rtl" }, e("span")))],
  ["state pseudo never", ["a:hover{width:2px} a:link{width:3px} a:any-link{width:4px} a:visited{width:5px} a:focus{width:6px} a:foo{width:7px} a{height:1px}"], e("div", {}, e("a", { a: { href: "https://x" } }))],
  ["form states", ["input:checked{width:2px} input:disabled{width:3px} input:enabled{width:4px} input:required{width:5px} :read-only{height:1px}"],
    e("form", {}, e("input", { a: { type: "checkbox", checked: "" } }), e("input", { a: { disabled: "" } }), e("input", { a: { required: "" } }), e("input", { a: { type: "radio" } }))],
  ["media width dpr1", ["p{width:2px} @media (min-width: 500px){p{width:3px}} @media (max-width: 499px){em{width:4px}} @media (min-width: 40em){i{width:5px}}"], e("div", {}, e("p"), e("em"), e("i")), { w: 800, h: 100, dpr: 1 }],
  ["media width dpr2", ["p{width:2px} @media (min-width: 500px){p{width:3px}} @media (max-width: 499px){em{width:4px}} @media (min-width: 40em){i{width:5px}} @media (min-resolution: 2dppx){b{width:6px}}"], e("div", {}, e("p"), e("em"), e("i"), e("b")), { w: 800, h: 100, dpr: 2 }],
  ["media range", ["@media (400px <= width < 801px){p{width:2px}} @media (width > 800px){em{width:3px}} @media (100px < height){i{width:4px}} @media (orientation: landscape){b{width:5px}} @media (aspect-ratio > 4/1){u{width:6px}}"], e("div", {}, e("p"), e("em"), e("i"), e("b"), e("u")), { w: 800, h: 100, dpr: 1 }],
  ["media types and logic", ["@media screen{p{width:2px}} @media print{em{width:3px}} @media not print{i{width:4px}} @media (prefers-color-scheme: dark){b{width:5px}} @media not (prefers-color-scheme: dark){u{width:6px}} @media (max-width: 1px), (min-width: 2px){s{width:7px}} @media tv, screen and (min-width: 1px){q{width:8px}}"], e("div", {}, e("p"), e("em"), e("i"), e("b"), e("u"), e("s"), e("q"))],
  ["media no viewport height", ["@media (min-height: 1px){p{width:2px}} @media (min-width: 1px){em{width:3px}}"], e("div", {}, e("p"), e("em")), { w: 300, dpr: 1 }],
  ["supports", ["@supports (display: grid){p{width:2px}} @supports not (display: grid){em{width:3px}} @supports (foo: bar){i{width:4px}} @supports selector(p){b{width:5px}} @supports (display:flex) and (width: 3px){u{width:6px}}"], e("div", {}, e("p"), e("em"), e("i"), e("b"), e("u"))],
  ["layers order", ["@layer a, b; @layer b{p{width:2px}} @layer a{#x{width:3px}} @layer c{em{width:4px}} em{width:5px}"], e("div", {}, e("p", { id: "x" }), e("em"))],
  ["layers important", ["@layer a{p{width:2px !important}} @layer b{p{width:3px !important}} p{width:4px !important} @layer a{em{width:5px !important}} em{width:6px}"], e("div", {}, e("p"), e("em"))],
  ["layers nested anon", ["@layer x{@layer y{p{width:2px}} p{width:3px}} @layer x.y{em{width:4px}} @layer x{em{width:5px}} @layer{i{width:6px}} @layer{i{width:7px}} @layer q{i{width:8px}}"], e("div", {}, e("p"), e("em"), e("i"))],
  ["nesting basic", [".a{ .b{width:2px} &.c{width:3px} > em{width:4px} & + p{width:5px} }"], e("div", { c: "a c" }, e("i", { c: "b" }), e("em"), e("p")), undefined, "div.a.c sibling p? no"],
  ["nesting specificity", ["#r{ & p{width:2px} } div p.q.q{width:3px} .s, #t{ & > i{width:4px} } div > i.x.x{width:5px}"], e("div", { id: "r", c: "s" }, e("p", { c: "q" }), e("i", { c: "x" }))],
  ["nesting decl order", [".a{ width:2px; &.a{width:3px} width:4px }"], e("div", { c: "a" })],
  ["nesting ident-colon swallow", [".a{ span:first-child{width:3px} width:4px; height:1px } .b{ p{width:5px} } .c{ :is(p):first-child{width:6px} }"], e("div", { c: "a b c" }, e("p"), e("span"))],
  ["nested media in rule", ["p{ width:2px; @media (min-width: 100px){ width:3px } } em{ @media (max-width: 100px){ width:4px } }"], e("div", {}, e("p"), e("em"))],
  ["error recovery", ["p{width:2px;;width;: x; height 3; } p;{width:9px} em{width:3px} ] i{width:9px} b{width:4px}", "u{width:5px}"], e("div", {}, e("p"), e("em"), e("i"), e("b"), e("u"))],
  ["invalid selector drops rule", ["p, :::x{width:2px} em, #1x{width:3px} i, b:hover{width:4px} u:unknown(1){width:5px}, s{width:6px}"], e("div", {}, e("p"), e("em"), e("i"), e("b"), e("u"), e("s"))],
  ["unknown at-rules", ["@container (min-width: 1px){p{width:2px}} @scope (div){em{width:3px}} @page{i{width:4px}} @foo; b{width:5px} @import url(x.css); u{width:6px}"], e("div", {}, e("p"), e("em"), e("i"), e("b"), e("u"))],
  ["concatenated entries", ["p{width:2px", "} em{width:3px}"], e("div", {}, e("p"), e("em"))],
  ["escapes", [".a\\:b{width:2px} #\\31 23{width:3px} .\\66 oo{width:4px}"], e("div", {}, e("p", { c: "a:b" }), e("p", { id: "123" }), e("p", { c: "foo" }))],
  ["namespaces", ["*|p{width:2px} |em{width:3px}"], e("div", {}, e("p"), e("em"))],
  ["pseudo elements dont hit element", ["p::before{width:2px} p:before{width:3px} p::after{width:4px} p::marker{width:5px} p::placeholder{width:6px} p{height:1px}"], e("div", {}, e("p"))],
  ["comma spec per selector", [".a, #b{width:2px} div.a{width:3px} #b{height:1px}"], e("section", {}, e("div", { c: "a" }), e("div", { c: "a", id: "b" }))],
  ["rule objects", [{ selector: ".a", style: { width: "2px" }, rules: [{ selector: "& > p", style: { width: 3 } }] }, { media: "(min-width: 10px)", rules: [{ selector: "em", style: { width: "4px" } }] }, { layer: "l", rules: [{ selector: "i", style: { width: "5px" } }] }, "i{width:6px}", { supports: "(display: grid)", rules: ["b{width:7px}"] }],
    e("div", { c: "a" }, e("p"), e("em"), e("i"), e("b"))],
  ["important in layer objects", [{ layer: "a" }, { layer: "b", rules: ["p{width:2px !important}"] }, { layer: "a", rules: [{ selector: "p", style: { width: "3px" } }, "p{width:3px!important}"] }, { selector: "em", style: { width: "4px" }, rules: [{ selector: "&:hover", style: { width: "5px" } }] }], e("div", {}, e("p"), e("em"))],
  ["preflight layer", ['@import "tailwindcss"; @layer base{p{width:2px}} @layer components{p{width:3px}} em{width:4px}'], e("div", {}, e("p"), e("em"))],
  ["deep has bounded", ["section:has(i i i i i i){width:2px} i:nth-child(1):has(> i){width:3px}"], e("section", {}, e("i", {}, e("i", {}, e("i", {}, e("i", {}, e("i", {}, e("i"))))))) ],
];

const out = [];
for (const [name, css, tree, env = { w: 800, h: 100, dpr: 1 }] of cases) {
  const node = toNode(tree);
  const opts = { css, devicePixelRatio: env.dpr };
  if (env.w) opts.width = env.w;
  if (env.h) opts.height = env.h;
  let m;
  try { m = await r.measure(node, opts); } catch (err) { console.log("ERR", name, err.message); continue; }
  // flatten tree (preorder) with parents, and measured widths
  const nodes = [], expect = [];
  const walk = (n, mm, parent) => {
    const i = nodes.length;
    nodes.push({ tag: n.tag ?? "", cls: n.c ?? "", id: n.id ?? "", attrs: Object.entries(n.a ?? {}).concat(n.lang ? [["lang", n.lang]] : []), dir: n.dir ?? "", parent });
    const w = Math.round((mm.width / env.dpr) * 100) / 100;
    expect.push(w === 1 ? null : w);
    n.children.forEach((c, k) => walk(c, mm.children[k] ?? { width: 1, children: [] }, i));
  };
  walk(tree, m, null);
  out.push({ name, css, env, nodes, expect });
  console.log(name.padEnd(36), JSON.stringify(expect));
}
mkdirSync("../src/css/testdata", { recursive: true });
writeFileSync("../src/css/testdata/oracle.json", JSON.stringify({ generator: "bench/probe/css/oracle.mjs", takumi: "@takumi-rs/wasm 2.20.0", cases: out }, null, 1));
console.log("cases:", out.length);
