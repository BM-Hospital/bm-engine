// Random node trees through the whole pipeline (run against a ReleaseSafe build to surface safety traps).
import { readFileSync } from "node:fs";
import * as fs_ from "node:fs";
import * as bm from "../../js/index.mjs";
bm.initSync(readFileSync(process.env.BM_WASM));
const r = new bm.Renderer();
r.registerFont({ name: "Inter", data: readFileSync("../assets/fonts/Inter-Regular.ttf") });
r.registerFont({ name: "Noto Sans", data: readFileSync("../assets/fonts/NotoSans-Bold.ttf") });
const png = readFileSync("assets/icon.png"), jpg = readFileSync("assets/photo.jpg");
let seed = +(process.argv[2] || 1);
const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
const pick = (a) => a[Math.floor(rnd() * a.length)];
const num = () => pick([0, 1, 2, 3.5, 8, 12, 20, 33.3, 64, 100, 250, 1000, -5, -40, 1e7, 0.001, "50%", "100%", "10px", "2em", "1rem", "5vw", "auto", "calc(100% - 20px)", "calc(50% + 3px)"]);
const color = () => pick(["#fff", "#000", "red", "rgba(0,0,255,0.5)", "transparent", "hsl(120 50% 50% / 0.3)", "#12345678", "currentColor"]);
const grad = () => pick(["linear-gradient(45deg, red, blue)", "linear-gradient(to bottom right, #f00 10%, transparent 50%, #00f)", "radial-gradient(circle at 20% 30%, #fff, #000)", "radial-gradient(closest-side, red, 30%, blue)", "conic-gradient(from 45deg, red, yellow, green, red)", "repeating-linear-gradient(90deg, red 0 10px, blue 10px 20px)", "url(img://p)", "url(img://j), linear-gradient(red, blue)", "none"]);
const props = {
  display: () => pick(["flex", "block", "grid", "none", "inline", "inline-flex", "inline-block"]), position: () => pick(["static", "relative", "absolute"]),
  width: num, height: num, minWidth: num, maxWidth: num, minHeight: num, maxHeight: num, top: num, left: num, right: num, bottom: num, margin: num, padding: num, gap: num,
  flexDirection: () => pick(["row", "column", "row-reverse", "column-reverse"]), flexWrap: () => pick(["wrap", "nowrap", "wrap-reverse"]), flex: () => pick([1, "1 1 0%", "none", "auto", "2 0 30px"]),
  flexGrow: () => pick([0, 1, 3]), flexShrink: () => pick([0, 1, 5]), flexBasis: num, alignItems: () => pick(["center", "stretch", "flex-end", "baseline", "start"]), justifyContent: () => pick(["center", "space-between", "space-around", "space-evenly", "flex-end"]),
  alignSelf: () => pick(["center", "stretch", "flex-end", "baseline"]), aspectRatio: () => pick([1, "16 / 9", 0.2, "auto"]), order: () => pick([-1, 0, 2]), zIndex: () => pick([-1, 0, 3, "auto"]),
  gridTemplateColumns: () => pick(["1fr 2fr", "repeat(3, 1fr)", "100px auto minmax(50px, 1fr)", "repeat(auto-fill, 80px)", "fit-content(100px) 1fr"]), gridTemplateRows: () => pick(["auto", "50px 1fr", "repeat(2, minmax(20px, auto))"]),
  gridColumn: () => pick(["1 / 3", "span 2", "auto", "-1 / 1", "2"]), gridRow: () => pick(["1 / 3", "span 2", "auto"]), gridAutoFlow: () => pick(["row", "column", "row dense"]),
  backgroundColor: color, color, backgroundImage: grad, backgroundSize: () => pick(["cover", "contain", "50% 50%", "20px 30px", "auto"]), backgroundPosition: () => pick(["center", "10px 20px", "right bottom", "30% 70%"]), backgroundRepeat: () => pick(["repeat", "no-repeat", "repeat-x"]),
  backgroundClip: () => pick(["border-box", "padding-box", "content-box"]),
  border: () => pick(["1px solid red", "4px solid rgba(0,0,0,.5)", "10px dashed blue", "0.5px solid #000", "none"]), borderTop: () => "6px solid green", borderLeftWidth: num, borderStyle: () => pick(["solid", "none", "dotted"]),
  borderRadius: () => pick([0, 4, 20, "50%", "50% / 20%", "10px 40px 0 5px", 9999, "30% 70% 70% 30% / 30% 30% 70% 70%"]),
  boxShadow: () => pick(["0 4px 12px rgba(0,0,0,.4)", "inset 0 0 20px red", "0 0 0 4px blue, 5px 5px 0 red", "0 0 300px 20px #000", "inset 3px 3px 0 -1px green", "none"]),
  opacity: () => pick([0, 0.3, 0.9, 1]), overflow: () => pick(["hidden", "visible", "clip"]),
  transform: () => pick(["rotate(30deg)", "scale(1.5, 0.5)", "translate(10px, -50%)", "skewX(20deg) rotate(5deg)", "matrix(1,0.2,0.3,1,10,10)", "scale(0)", "rotate(1e9deg)", "none"]), transformOrigin: () => pick(["top left", "50% 50%", "10px 100%"]),
  fontSize: () => pick([0, 1, 8, 16, 24, 72, 300, "2em", "150%"]), fontWeight: () => pick([100, 400, 700, 900, "bold"]), fontStyle: () => pick(["italic", "normal"]), fontFamily: () => pick(["Inter", "Noto Sans", "Nope, Inter", "serif"]),
  lineHeight: () => pick([0, 1, 1.5, "40px", "normal", "200%"]), letterSpacing: () => pick([0, 2, -1, "0.1em"]), textAlign: () => pick(["left", "center", "right", "justify", "end"]), textTransform: () => pick(["uppercase", "lowercase", "capitalize"]),
  whiteSpace: () => pick(["nowrap", "pre", "pre-wrap", "pre-line", "normal"]), wordBreak: () => pick(["break-all", "keep-all", "normal"]), overflowWrap: () => pick(["anywhere", "break-word"]), textOverflow: () => pick(["ellipsis", "clip"]), lineClamp: () => pick([1, 2, 3]),
  textDecoration: () => pick(["underline", "line-through", "underline overline"]), objectFit: () => pick(["cover", "contain", "fill", "none", "scale-down"]), objectPosition: () => pick(["top left", "20% 80%"]), visibility: () => pick(["hidden", "visible"]),
};
const keys = Object.keys(props);
const style = () => { const s = {}; const n = Math.floor(rnd() * 9); for (let i = 0; i < n; i++) { const k = pick(keys); s[k] = props[k](); } return s; };
const texts = ["Hello world", "", " ", "Xin chào Việt Nam — tiếng Việt có dấu", "a\tb\nc  d", "superlongwordwithoutanybreaksatallsuperlongwordwithoutanybreaks", "fi ffl -> 1:2 AV To", "😀 emoji ́‍�", "日本語のテキスト", "x".repeat(2000)];
function node(d) {
  const k = rnd();
  if (k < 0.3 || d > 4) return { type: "text", text: pick(texts), style: style() };
  if (k < 0.4) return { type: "image", src: pick(["img://p", "img://j", "img://missing", "data:image/png;base64," + png.toString("base64"), "data:,garbage"]), width: pick([undefined, 50, 0, 300]), style: style() };
  return { type: "container", style: style(), children: Array.from({ length: Math.floor(rnd() * 5) }, () => node(d + 1)) };
}
const N = +(process.argv[3] || 3000);
let ok = 0, err = 0; const errs = new Map();
for (let i = 0; i < N; i++) {
  const s0 = seed; const n = node(0);
  const opts = { width: pick([1, 37, 200, 640, undefined]), height: pick([1, 50, 300, undefined]), devicePixelRatio: pick([1, 1, 2, 0.5]), format: pick(["raw", "png", "jpeg", "webp"]), images: [{ src: "img://p", data: png }, { src: "img://j", data: jpg }] };
  try { r.renderSync(n, opts); if (rnd() < 0.2) r.measureSync(n, opts); ok++; }
  catch (e) {
    const m = String(e.message);
    if (/unreachable|out of bounds|RuntimeError|Maximum call stack|memory access/i.test(m) || e instanceof WebAssembly.RuntimeError) { console.log(String(e.stack).split(String.fromCharCode(10)).slice(0, 16).join(String.fromCharCode(10))); console.log("TRAP at seed", s0, "iter", i, m, "\n", JSON.stringify(n).slice(0, 1500), JSON.stringify({ ...opts, images: undefined })); fs_.writeFileSync("out/fuzzcase.json", JSON.stringify({ node: n, opts: { ...opts, images: undefined } })); process.exit(1); }
    err++; const key = m.replace(/property .*/, "property …").slice(0, 70); errs.set(key, (errs.get(key) || 0) + 1);
  }
}
console.log("ok", ok, "rejected", err, Object.fromEntries(errs), "mem", r.memoryBytes());
