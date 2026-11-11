// Oracle: compare our HTML parse tree shape with takumi's measured layout tree.
// Build the harness first (from D:\project\bm-engine):
//   zig build-exe -target wasm32-freestanding -O ReleaseSafe -fno-entry -rdynamic -femit-bin=<scratch>/harness.wasm \
//     --dep html -Mroot=bench/probe/html/harness.zig -Mhtml=src/html/html.zig
// Run: cd bench && node probe/html/oracle.mjs [fixtures]
import { Renderer } from "@takumi-rs/wasm/node";
import { readFileSync, readdirSync } from "node:fs";
import { loadParser, sigDoc, sigMine, sigTakumi, allText, allRunsText } from "./lib.mjs";

const parse = await loadParser();
const r = new Renderer();
const OPT = { width: 3000, height: 1000 };

const snippets = [
  "<div>hello</div>",
  "<div><p>a</p><p>b</p></div>",
  "<div><p>a<p>b<p>c</div>",
  "<div>a<div>b</div>c</div>",
  "<div>x<b>bold</b>y<i>it</i>z</div>",
  "<div><span>a</span><span>b</span></div>",
  "<div>  <p>a</p>  <p>b</p>  </div>",
  "<p>one</p><p>two</p>",
  "<p>one</p> text <p>two</p>",
  "text only",
  "<span>inline root</span>",
  "<div><b>a<i>b</b>c</i></div>",
  "<ul><li>a<li>b<li>c</ul>",
  "<ul><li>a</li><li>b<ul><li>c</li></ul></li></ul>",
  "<dl><dt>t1<dd>d1<dt>t2<dd>d2</dl>",
  "<div><h1>H1</h1><h2>H2</h2><h3>H3</h3><p>para</p></div>",
  "<div>a<br>b<br>c</div>",
  "<div>a</br>b</div>",
  "<div style='display:flex'><span>a</span>text<b>c</b></div>",
  "<div style='display:flex'><div>a</div><div>b</div></div>",
  "<div style='display:grid'><p>a</p><p>b</p>x</div>",
  "<div><div><div><div>deep</div></div></div></div>",
  "<div><!-- c1 -->a<!-- c2 -->b</div>",
  "<div>a &amp; b &lt; c &#65; &copy; &nbsp;d</div>",
  "<div><p>a<div>b</div>c</p></div>",
  "<section><article><header>h</header><main>m</main><footer>f</footer></article></section>",
  "<div><pre>\nline1\nline2</pre></div>",
  "<div><blockquote>q</blockquote><address>a</address><center>c</center></div>",
  "<div><hr><p>after hr</p></div>",
  "<div><img src='x.png' width=10 height=10></div>",
  "<div><p>a</p><svg width='10' height='10' viewBox='0 0 10 10'><rect width='10' height='10'/></svg><p>b</p></div>",
  "<div>x<template><p>hidden</p></template>y</div>",
  "<div><script>var a=1;</script>vis</div>",
  "<div><style>.a{color:red}</style>vis</div>",
  "<div><title>t</title><p>after</p></div>",
  "<div><noscript>ns</noscript>after</div>",
  "<div><form><fieldset><legend>l</legend>f</fieldset></form></div>",
  "<div><details><summary>s</summary>d</details></div>",
  "<div><p>a</div>b",
  "<div><p>unclosed<span>inner</div>",
  "<div></p>stray end p</div>",
  "<div><table><tr><td>a<td>b<tr><td>c<td>d</table></div>",
  "<div><table><thead><tr><th>h</th></tr></thead><tbody><tr><td>x</td></tr></tbody></table></div>",
  "<div><table><caption>cap</caption><tr><td>1</td></tr></table></div>",
  "<div><select><option>a<option>b</select></div>",
  "<div><button>click</button><input type=text value=v></div>",
  "<div><textarea>area &amp; text</textarea></div>",
  "<div a=1 a=2 b>dups</div>",
  "<div>1 < 2 and 3 > 2 <3 </div>",
  "<DIV><P>Upper<SPAN>case</SPAN></P></DIV>",
  "<div><sub>s</sub><sup>p</sup><small>sm</small><big>bg</big><mark>m</mark><code>c</code><kbd>k</kbd></div>",
  "<div><p>a<ul><li>b</ul>c</div>",
  "<div><a href='#'>link</a> <u>u</u> <s>s</s> <del>d</del> <ins>i</ins></div>",
  "<!DOCTYPE html><html><head><title>t</title></head><body><div>doc</div></body></html>",
  "<div>  </div>",
  "",
  "<div><div></div><div></div></div>",
  "<p>a<table><tr><td>b</table>",
];

let ok = 0, bad = 0, err = 0;
const fails = [];
for (const s of snippets) {
  let m;
  try { m = await r.measure(s, OPT); } catch (e) { err++; fails.push(["ERR " + e.message.slice(0, 80), s]); continue; }
  const p = parse(s);
  // document-mode sources produce html>body wrappers in takumi; compare inside the body box
  let tk = sigTakumi(m);
  if (p.doc) { const body = m.children[0]; tk = sigTakumi(body); }
  const mine = p.doc ? sigDoc(p) : sigMine(p);
  if (tk === mine) ok++; else { bad++; fails.push([`mine ${mine}\n     takumi ${tk}`, s]); }
}
console.log(`snippets: ${snippets.length}  shape-equal ${ok}  differ ${bad}  takumi-error ${err}`);
for (const [why, s] of fails) console.log("  -", JSON.stringify(s), "\n    ", why);

if (process.argv[2] === "fixtures") {
  const dir = "../ref/takumi/takumi/tests/fixtures-html";
  const files = readdirSync(dir).filter((f) => f.endsWith(".html"));
  let reord = 0, eq = 0, ne = 0, er = 0, tot = 0;
  const diffs = [];
  for (const f of files) {
    const html = readFileSync(`${dir}/${f}`, "utf8");
    const body = html.slice(html.indexOf("<body")).replace(/<body[^>]*>/, "").replace(/<\/body>[\s\S]*$/, "");
    const css = (html.match(/<style>([\s\S]*?)<\/style>/) || ["", ""])[1];
    const src = `<style>${css}</style>${body}`;
    tot++;
    let m;
    try { m = await r.measure(src, { width: 1200, height: 630 }); } catch (e) { er++; diffs.push([f, "ERR " + e.message.slice(0, 60)]); continue; }
    const p = parse(src);
    const a = allText(p), b = allRunsText(m);
    const norm = (x) => [...x.replace(/[…­-]/g, "")].sort().join("");
    if (a === b) eq++; else if (norm(a) === norm(b)) { reord++; } else { ne++; diffs.push([f, `mine=${a.slice(0, 60)} | takumi=${b.slice(0, 60)}`]); }
  }
  console.log(`fixtures: ${tot} text-sequence-equal ${eq} same-chars-reordered/ellipsis ${reord} differ ${ne} takumi-error ${er}`);
  for (const [f, w] of diffs.slice(0, 40)) console.log("  -", f, w);
}
