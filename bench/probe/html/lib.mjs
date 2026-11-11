// Loads the html parser harness wasm (build: see oracle.mjs header) and maps trees to takumi-like layout signatures.
import { readFileSync } from "node:fs";

export const HARNESS = process.env.HTML_WASM ||
  "C:/Users/admini/AppData/Local/Temp/claude/46c8b6142d3c6b7e/eb762129-eac5-46a2-aaef-1b224d61f7d8/scratchpad/html/harness.wasm";

export async function loadParser(path = HARNESS) {
  const { instance } = await WebAssembly.instantiate(readFileSync(path), {});
  const x = instance.exports;
  const enc = new TextEncoder(), dec = new TextDecoder();
  return function parse(html) {
    const b = enc.encode(html);
    const p = x.alloc(Math.max(1, b.length));
    new Uint8Array(x.memory.buffer, p, b.length).set(b);
    const o = x.parse_json(p, b.length);
    const n = x.out_len();
    return JSON.parse(dec.decode(new Uint8Array(x.memory.buffer, o, n)));
  };
}

const UNRENDERED = new Set(["head", "meta", "link", "style", "script"]);
const isText = (n) => typeof n === "string";
const ws = (s) => s.replace(/\s+/g, "");

function displayOf(n) {
  let d = n.d || "inline";
  const st = n.a && n.a.style;
  if (st) for (const decl of st.split(";")) {
    const i = decl.indexOf(":");
    if (i > 0 && decl.slice(0, i).trim().toLowerCase() === "display") d = decl.slice(i + 1).trim().toLowerCase().replace(/\s*!important/, "");
  }
  return d;
}
const soleText = (n) => {
  if (n.c.length !== 1 || !isText(n.c[0])) return null;
  return /[^ \t\n\f\r]/.test(n.c[0]) ? n.c[0] : null;
};

// Signature of a takumi measured node: runs text (whitespace stripped) + children.
export function sigTakumi(m) {
  const runs = ws(m.runs.map((r) => r.text).join("")).toLowerCase();
  return "(" + runs + m.children.map(sigTakumi).join("") + ")";
}

// Map our DOM to a takumi-like layout box signature.
function isBlockLevel(d) { return d !== "inline" && d !== "contents"; }

function elementBox(n) {
  // element -> box signature string (element is rendered and block-level, or blockified)
  const d = displayOf(n);
  const t = soleText(n);
  if (t !== null) return "(" + ws(t).toLowerCase() + (d === "list-item" ? "(•)" : "") + ")";
  if (n.t === "img" || n.t === "svg") return "()";
  return container(n.c, d);
}

// children of a container with display `d` -> signature of the box "( runs kids )"
function container(children, d) {
  const flexy = /flex|grid/.test(d);
  const marker = d === "list-item";
  const kids = []; // box sigs
  let runs = "";   // inline runs text collected while no block child seen yet
  let group = ""; let groupHas = false;
  let sawBlock = false;
  const flushGroup = () => {
    if (groupHas) { if (sawBlockAfter()) { /* handled below */ } }
  };
  void flushGroup;
  // two passes: first collect items
  const items = []; // {block: sig} | {text}
  const walkInline = (list) => {
    for (const c of list) {
      if (isText(c)) { items.push({ text: c }); continue; }
      if (UNRENDERED.has(c.t)) continue;
      const cd = displayOf(c);
      if (cd === "none") continue;
      if (c.t === "br") { items.push({ text: "\n" }); continue; }
      if (flexy) { items.push({ block: elementBox(c) }); continue; }
      if (isBlockLevel(cd) && cd !== "inline-block" && cd !== "inline-flex" && cd !== "inline-grid") { items.push({ block: elementBox(c) }); continue; }
      if (c.t === "img" || c.t === "svg" || cd.startsWith("inline-")) { items.push({ block: "(())" }); continue; }
      // plain inline element: transparent
      const t = soleText(c);
      if (t !== null) items.push({ text: t });
      else walkInline(c.c);
    }
  };
  walkInline(children);
  if (flexy) {
    for (const it of items) {
      if (it.block) kids.push(it.block);
      else if (/[^ \t\n\f\r]/.test(it.text)) kids.push("(" + ws(it.text).toLowerCase() + ")");
    }
    return "(" + kids.join("") + ")";
  }
  const hasBlock = items.some((i) => i.block);
  if (!hasBlock) return "(" + ws(items.map((i) => i.text).join("")).toLowerCase() + (marker ? "(•)" : "") + ")";
  if (marker) kids.push("(•)");
  let cur = "";
  const flush = () => { if (cur !== "") kids.push("(" + cur.toLowerCase() + ")"); cur = ""; };
  for (const it of items) {
    if (it.block) { flush(); kids.push(it.block); } else cur += ws(it.text);
  }
  flush();
  return "(" + kids.join("") + ")";
}

// Root collapse (takumi `collapse`): 0 -> empty container, 1 -> itself, many -> wrapper.
export function sigMine(parsed) {
  const roots = parsed.roots.filter((n) => isText(n) || (!UNRENDERED.has(n.t)));
  const live = roots.filter((n) => isText(n) || displayOf(n) !== "none" || true);
  const trimmed = [...live];
  while (trimmed.length && isText(trimmed[0]) && !/[^ \t\n\f\r]/.test(trimmed[0])) trimmed.shift();
  while (trimmed.length && isText(trimmed[trimmed.length - 1]) && !/[^ \t\n\f\r]/.test(trimmed[trimmed.length - 1])) trimmed.pop();
  if (trimmed.length === 0) return "()";
  if (trimmed.length === 1) {
    const r = trimmed[0];
    if (isText(r)) return "(" + ws(r).toLowerCase() + ")";
    return elementBox(r);
  }
  return container(trimmed, "block");
}

export function allText(parsed) {
  let out = "";
  const walk = (n) => {
    if (isText(n)) { out += n; return; }
    if (UNRENDERED.has(n.t) || n.t === "title" || n.t === "template" || n.t === "noscript" || n.t === "head") return;
    if (displayOf(n) === "none") return;
    if (n.t === "br") return;
    if (n.t === "svg" || n.t === "img") return;
    n.c.forEach(walk);
  };
  parsed.roots.forEach(walk);
  return ws(out).toLowerCase();
}
export function allRunsText(m) {
  let out = m.runs.map((r) => r.text).join("");
  for (const c of m.children) out += allRunsText(c);
  return ws(out).toLowerCase();
}

export function sigDoc(parsed) { return container(parsed.roots, "block"); }
