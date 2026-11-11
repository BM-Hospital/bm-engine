// Which malformed / edge values does takumi reject (throw) vs accept? Used to align src/style.
import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const cases = [
  ["width", ""], ["width", "none"], ["maxWidth", "auto"], ["width", "banana"], ["width", "-10px"],
  ["flex", "1 2 3"], ["flex", "1 2 3px"], ["backgroundImage", "linear-gradient(red)"], ["backgroundImage", "linear-gradient(red 10%, 30%, 40%, blue)"],
  ["position", "sticky"], ["display", "table"], ["display", "list-item"], ["display", "-webkit-box"], ["display", "block flex"],
  ["fontWeight", 0], ["fontWeight", 1001], ["opacity", 2], ["opacity", "50%"], ["zIndex", 1.5], ["zIndex", "1.5"],
  ["boxShadow", "1px"], ["boxShadow", "1px 2px -3px red"], ["color", "oklch(0.5 0.1 20)"], ["color", "lab(50 20 20)"],
  ["margin", "1px 2px 3px 4px 5px"], ["textOverflow", "\"x\""], ["borderRadius", "-1px"], ["backgroundPosition", "top 10px"],
  ["gridColumn", "header"], ["gridColumn", "0"], ["padding", "-1px"], ["padding", "auto"], ["lineClamp", 0], ["WebkitLineClamp", "none"],
  ["fontSize", "-1px"], ["lineHeight", "-1"], ["transform", "rotate(45)"], ["transform", "translate(1px 2px)"], ["filter", "blur(-1px)"],
  ["borderWidth", "-1px"], ["borderWidth", "10%"], ["aspectRatio", "-1"], ["flexGrow", -1], ["gap", "-1px"],
  ["background", "red, url(a)"], ["border", "solid dashed"], ["fontFamily", "Arial,"], ["font", "bold"], ["textAlign", "-webkit-center"],
  ["width", "calc(100% -20px)"], ["width", "min(10%, 20px)"], ["width", "10px !important"], ["width", "var(--x)"],
  ["color", "rgb(1 2 3 4)"], ["color", "rgb(10%, 20, 30)"], ["color", "#ff"], ["objectPosition", "left right"],
  ["textDecoration", "underline underline"], ["whiteSpace", "pre pre"], ["overflow", "hidden scroll"], ["inset", "auto auto auto auto auto"],
  ["min-width", "banana"], ["unknownProp", "x"], ["WebkitBoxOrient", "banana"], ["translate", "10px 20px 30px"], ["rotate", "x 10deg"],
];
const out = [];
for (const [k, v] of cases) {
  const node = { type: "container", style: { display: "block", [k]: v } };
  let res;
  try { await r.measure(node, { width: 100, height: 100 }); res = "accept"; }
  catch (e) { res = "REJECT " + String(e.message || e).split("\n")[0].slice(0, 90); }
  out.push(`${k}: ${JSON.stringify(v)} -> ${res}`);
}
console.log(out.join("\n"));
