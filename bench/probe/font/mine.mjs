import { readFileSync } from "node:fs";
const S = "C:/Users/admini/AppData/Local/Temp/claude/46c8b6142d3c6b7e/eb762129-eac5-46a2-aaef-1b224d61f7d8/scratchpad/font/";
const F = "D:/project/bm-engine/assets/fonts/";
const { instance } = await WebAssembly.instantiate(readFileSync(S + "cmp.wasm"), {});
const X = instance.exports;
const put = (bytes) => { const p = X.alloc(bytes.length || 1); new Uint8Array(X.memory.buffer, p, bytes.length).set(bytes); return p; };
export function regMine(files = ["Inter-Regular.ttf","Inter-Bold.ttf","NotoSans-Regular.ttf","Roboto-Regular.ttf"]) {
  return files.map(f => { const b = readFileSync(F + f); return X.addFont(put(b), b.length); });
}
const FAM = { "Inter": 0, "Noto Sans": 1, "Roboto": 2, "Nope": 3 };
const WS = { normal: 0, nowrap: 1, pre: 2, "pre-wrap": 3, "pre-line": 4 };
const WB = { normal: 0, "break-all": 1, "keep-all": 2 };
const OW = { normal: 0, anywhere: 1, "break-word": 2 };
const AL = { left: 0, right: 1, center: 2, justify: 3, start: 4, end: 5 };
export function mine(text, st = {}, width = null) {
  const tb = new TextEncoder().encode(text);
  const tp = put(tb);
  const lh = st.lineHeight;
  const cfg = new Float32Array([FAM[st.fontFamily ?? "Inter"], st.fontSize ?? 16,
    lh == null ? 0 : typeof lh === "string" ? 1 : 2, lh == null ? 0 : parseFloat(lh),
    width ?? -1, WS[st.whiteSpace ?? "normal"], WB[st.wordBreak ?? "normal"], OW[st.overflowWrap ?? "normal"],
    st.lineClamp ?? 0, st.textOverflow === "ellipsis" ? 1 : 0, st.letterSpacing ?? 0, st.wordSpacing ?? 0, AL[st.textAlign ?? "left"], st.fontWeight ?? 400, FAM[st.famB ?? "Inter"], st.sizeB ?? 16]);
  const cp = put(new Uint8Array(cfg.buffer));
  const op = X.para(tp, tb.length, cp); const o = new Float32Array(X.memory.buffer, op, 8192);
  const n = o[2], lines = [];
  const dec = new TextDecoder();
  for (let i = 0; i < n; i++) { const b = 8 + i * 8;
    let txt = "";
    if (o[b+6] >= 0) { let e = o[b+7] + 1; while (e < tb.length && (tb[e] & 0xc0) === 0x80) e++; txt = dec.decode(tb.slice(o[b+6], e)); }
    lines.push({ x: o[b], top: o[b+1], baseline: o[b+2], width: o[b+3], height: o[b+4], n: o[b+5], text: txt }); }
  return { w: o[0], h: o[1], min: o[3], max: o[4], lines };
}
