// bm-engine playground: plain ES modules, no build step, no network access beyond same-origin files.
// Profile switching: js/index.mjs keeps ONE wasm instance per module instance, and js/addons.mjs imports the
// same module by URL, so the robust way to change profile is a page reload with ?profile=<name>.
import { config } from "./config.js";
import { templates } from "./templates.js";
import { tr, setLang, applyI18n, getLang } from "./i18n.js";

const $ = (id) => document.getElementById(id);
const rel = (p) => new URL(p, import.meta.url).href; // runtime URLs resolve next to this file via config.js
const LS = "bm-playground-state-v1";
const PROFILES = ["core", "standard", "full"];
const FONT_FILES = [
  ["Inter-Regular.ttf", "Inter", 400, "normal"], ["Inter-SemiBold.ttf", "Inter", 600, "normal"], ["Inter-Bold.ttf", "Inter", 700, "normal"],
  ["Inter-Italic.ttf", "Inter", 400, "italic"], ["NotoSans-Regular.ttf", "Noto Sans", 400, "normal"], ["NotoSans-Bold.ttf", "Noto Sans", 700, "normal"],
];
const MIME = { png: "image/png", jpeg: "image/jpeg", webp: "image/webp", svg: "image/svg+xml", "anim-webp": "image/webp", "anim-apng": "image/png", "anim-gif": "image/gif", raw: "application/octet-stream" };
const EXT = { png: "png", jpeg: "jpg", webp: "webp", svg: "svg", "anim-webp": "webp", "anim-apng": "png", "anim-gif": "gif", raw: "rgba" };

// ---------------------------------------------------------------------------------------------- state
const defaultState = () => ({
  kind: "json", json: "", html: "", tw: "", css: "", width: 1200, height: 630, dpr: 1, format: "png", quality: 80, timeMs: 0, fps: 15, duration: 1000,
  template: "og-card", images: [], auto: true, measure: false,
});
let state = defaultState();
let engine = null; // { bm, renderer, profile, features, wasmBytes }
let profile = "full";
const fonts = new Map(); // family -> { files: string[], builtin: bool }
const times = [];
let last = null; // { blob, bytes, format, mime, dataUrlPromise }
let blobUrl = "";
let renderSeq = 0;
let renderCount = 0;
let debounce = 0;

const json = (o) => JSON.stringify(o);
function saveLocal() {
  const base = { ...state };
  try { localStorage.setItem(LS, json(base)); } catch {
    try { localStorage.setItem(LS, json({ ...base, images: [] })); } catch { /* storage unavailable */ }
  }
}
function loadLocal() {
  try { const s = JSON.parse(localStorage.getItem(LS) || "null"); if (s && typeof s === "object") return { ...defaultState(), ...s }; } catch { /* ignore */ }
  return null;
}

// URL hash: "#s=z.<base64url(deflate-raw(json))>" when CompressionStream exists, "#s=p.<base64url(json)>" otherwise.
const b64u = (u8) => { let s = ""; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); };
const unb64u = (s) => { const b = atob(s.replace(/-/g, "+").replace(/_/g, "/")); const u = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i); return u; };
async function pipe(u8, stream) { return new Uint8Array(await new Response(new Blob([u8]).stream().pipeThrough(stream)).arrayBuffer()); }
const SHARE_KEYS = ["kind", "json", "html", "tw", "css", "width", "height", "dpr", "format", "quality", "timeMs", "fps", "duration", "template"];
async function encodeHash() {
  const o = {}; for (const k of SHARE_KEYS) o[k] = state[k];
  const raw = new TextEncoder().encode(json(o));
  if (typeof CompressionStream === "function") {
    try { return "s=z." + b64u(await pipe(raw, new CompressionStream("deflate-raw"))); } catch { /* fall through */ }
  }
  return "s=p." + b64u(raw);
}
async function decodeHash(h) {
  const m = /^#?s=([zp])\.([A-Za-z0-9_-]+)$/.exec(h || "");
  if (!m) return null;
  try {
    let raw = unb64u(m[2]);
    if (m[1] === "z") raw = await pipe(raw, new DecompressionStream("deflate-raw"));
    const o = JSON.parse(new TextDecoder().decode(raw));
    return o && typeof o === "object" ? o : null;
  } catch { return null; }
}

// ---------------------------------------------------------------------------------------------- engine
function pickProfile() {
  const q = new URLSearchParams(location.search).get("profile");
  if (PROFILES.includes(q)) return q;
  try { const p = localStorage.getItem("bm-playground-profile"); if (PROFILES.includes(p)) return p; } catch { /* ignore */ }
  return "full";
}
const fmtBytes = (n) => (n >= 1048576 ? (n / 1048576).toFixed(2) + " MiB" : (n / 1024).toFixed(1) + " KiB");

async function loadEngine() {
  const file = config.wasm[profile];
  $("binInfo").textContent = tr("loading");
  const bm = await import(rel(config.jsBase + "index.mjs"));
  const res = await fetch(rel(config.jsBase + file));
  if (!res.ok) throw new Error(`failed to fetch ${file}: HTTP ${res.status}`);
  const wasmBytes = new Uint8Array(await res.arrayBuffer());
  await bm.init(wasmBytes);
  engine = { bm, renderer: new bm.Renderer(), profile, features: { ...bm.features }, wasmBytes: wasmBytes.length, file, addons: null };
  $("binInfo").textContent = `${file} - ${fmtBytes(wasmBytes.length)}`;
  const chips = $("featChips"); chips.textContent = "";
  for (const [k, v] of Object.entries(bm.features)) {
    const s = document.createElement("span"); s.className = "chip" + (v ? "" : " off"); s.textContent = k; s.title = v ? "enabled" : "not in this build";
    chips.append(s);
  }
}
const has = (f) => !!engine.features[f];
async function ensureWoffAddon() {
  if (engine.features.woff || engine.addons) return;
  engine.addons = await import(rel(config.jsBase + "addons.mjs"));
  await engine.addons.loadWoff(fetch(rel(config.jsBase + config.woffWasm)));
}

// ---------------------------------------------------------------------------------------------- fonts
function addFamilies(fams, file, builtin) {
  for (const f of fams || []) {
    const e = fonts.get(f.name) || { files: [], builtin };
    if (!e.files.includes(file)) e.files.push(file);
    fonts.set(f.name, e);
  }
}
async function loadDefaultFonts() {
  await Promise.all(FONT_FILES.map(async ([file, name, weight, style]) => {
    const res = await fetch(rel(config.fontsBase + file));
    if (!res.ok) throw new Error(`failed to fetch font ${file}: HTTP ${res.status}`);
    return [file, name, weight, style, new Uint8Array(await res.arrayBuffer())];
  })).then((all) => {
    for (const [file, name, weight, style, data] of all) addFamilies(engine.renderer.registerFont({ name, data, weight, style }), file, true);
  });
}
function renderFontList() {
  const ul = $("fontList"); ul.textContent = "";
  if (!fonts.size) { const li = document.createElement("li"); li.textContent = tr("noFonts"); ul.append(li); }
  for (const [family, e] of fonts) {
    const li = document.createElement("li"); li.dataset.family = family;
    const name = document.createElement("span"); name.className = "name"; name.textContent = family;
    const small = document.createElement("small"); small.textContent = e.files.length > 1 ? tr("fontsFiles", { n: e.files.length }) : e.files[0]; small.title = e.files.join(", ");
    const rm = document.createElement("button"); rm.type = "button"; rm.textContent = tr("remove"); rm.dataset.remove = family;
    rm.addEventListener("click", () => { engine.renderer.unregisterFont(family); fonts.delete(family); renderFontList(); scheduleRender(0); });
    li.append(name, small, rm); ul.append(li);
  }
  $("fontsNote").textContent = tr("fontsNote", { woff: engine?.features.woff ? tr("woffBuiltin") : tr("woffAddon") });
}
async function onFontFiles(files) {
  $("fontsBox").open = true;
  const msg = $("fontMsg"); msg.textContent = "";
  for (const f of files) {
    try {
      const data = new Uint8Array(await f.arrayBuffer());
      if (/\.woff2?$/i.test(f.name)) await ensureWoffAddon();
      const fams = engine.renderer.registerFont(data);
      addFamilies(fams, f.name, false);
      msg.textContent = tr("fontAdded", { names: (fams || []).map((x) => x.name).join(", ") });
    } catch (e) { msg.textContent = tr("fontFail", { msg: e.message || e }); }
  }
  renderFontList(); scheduleRender(0);
}

// ---------------------------------------------------------------------------------------------- images
const imgBytes = new Map(); // b64 -> Uint8Array cache
function bytesOfImage(im) {
  let b = imgBytes.get(im.b64); if (!b) { b = unb64(im.b64); imgBytes.set(im.b64, b); } return b;
}
const unb64 = (s) => { const b = atob(s); const u = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i); return u; };
function renderImageList() {
  const ul = $("imageList"); ul.textContent = "";
  if (!state.images.length) { const li = document.createElement("li"); li.textContent = tr("noImages"); ul.append(li); }
  state.images.forEach((im, i) => {
    const li = document.createElement("li");
    const th = document.createElement("img"); th.alt = ""; th.src = `data:${im.mime};base64,${im.b64}`;
    const key = document.createElement("input"); key.type = "text"; key.value = im.src; key.title = tr("imgKey"); key.setAttribute("aria-label", tr("imgKey"));
    key.addEventListener("input", () => { im.src = key.value; persist(); scheduleRender(); });
    const rm = document.createElement("button"); rm.type = "button"; rm.textContent = tr("remove");
    rm.addEventListener("click", () => { state.images.splice(i, 1); renderImageList(); persist(); scheduleRender(0); });
    li.append(th, key, rm); ul.append(li);
  });
}
async function onImageFiles(files) {
  for (const f of files) {
    const data = new Uint8Array(await f.arrayBuffer());
    let base = f.name.replace(/\.[^.]+$/, "").replace(/[^\w.-]+/g, "-");
    let src = `img://${base}`, n = 2;
    while (state.images.some((x) => x.src === src)) src = `img://${base}-${n++}`;
    state.images.push({ src, mime: f.type || "image/png", b64: b64std(data) });
  }
  renderImageList(); persist(); scheduleRender(0);
}
const b64std = (u8) => { let s = ""; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); };

// ---------------------------------------------------------------------------------------------- UI <-> state
const FIELDS = ["width", "height", "dpr", "quality", "timeMs", "fps", "duration"];
function toUI() {
  $("src").value = state[state.kind] ?? "";
  $("css").value = state.css;
  for (const f of FIELDS) $(f).value = state[f];
  $("format").value = state.format;
  $("template").value = state.template || "";
  $("autoRender").checked = state.auto;
  $("measureToggle").checked = state.measure;
  for (const b of document.querySelectorAll("#tabs button")) b.setAttribute("aria-selected", String(b.dataset.kind === state.kind));
  updateVisibility();
}
function fromUI() {
  state[state.kind] = $("src").value;
  state.css = $("css").value;
  for (const f of FIELDS) { const v = Number($(f).value); if (Number.isFinite(v)) state[f] = v; }
  state.format = $("format").value;
  state.auto = $("autoRender").checked;
  state.measure = $("measureToggle").checked;
}
function persist() { saveLocal(); }
function updateVisibility() {
  const f = state.format;
  $("qualityBox").hidden = f !== "jpeg";
  $("qualityVal").textContent = $("quality").value;
  $("timeBox").hidden = f.startsWith("anim-");
  $("timeVal").textContent = $("timeMs").value;
  $("fpsBox").hidden = $("durBox").hidden = !f.startsWith("anim-");
  if (!engine) return;
  // annotate what this profile lacks (inputs stay usable: the engine's own error is shown on render)
  const miss = { json: false, html: !has("html"), tw: !has("tw") };
  for (const b of document.querySelectorAll("#tabs button")) { const m = b.querySelector(".miss"); m.hidden = !miss[b.dataset.kind]; m.textContent = "x " + profile; m.title = tr("needsMissing", { list: b.dataset.kind }); }
  $("cssMiss").hidden = has("css"); $("cssMiss").textContent = "x " + profile;
  const note = $("kindNote");
  const need = state.kind === "html" && !has("html") ? "html" : state.kind === "tw" && !has("tw") ? "tw" : null;
  note.hidden = !need;
  if (need) note.textContent = `${profile}: ${tr("needsMissing", { list: need })}`;
  const fo = { svg: "renderSvg", "anim-webp": "animation", "anim-apng": "animation", "anim-gif": "animation" };
  for (const o of $("format").options) { const feat = fo[o.value]; const base = o.dataset.i18n ? tr(o.dataset.i18n) : o.value; o.textContent = feat && !has(feat) ? `${base} (x ${feat})` : base; }
}
function fillTemplateSelect() {
  const sel = $("template"); const keep = sel.value; sel.textContent = "";
  const blank = document.createElement("option"); blank.value = ""; blank.textContent = "-"; sel.append(blank);
  for (const t of templates) {
    const o = document.createElement("option"); o.value = t.id;
    const miss = engine ? t.needs.filter((n) => !has(n)) : [];
    o.textContent = t.title[getLang()] + (miss.length ? `  (x ${miss.join(", ")})` : "");
    o.dataset.missing = miss.join(",");
    sel.append(o);
  }
  sel.value = keep;
}
function applyTemplate(id) {
  const t = templates.find((x) => x.id === id); if (!t) return;
  state.template = id; state.kind = t.kind; state[t.kind] = t.source; state.css = t.css || "";
  state.width = t.width; state.height = t.height; state.timeMs = t.timeMs || 0; state.format = t.format || "png";
  for (const im of t.images ? t.images() : []) if (!state.images.some((x) => x.src === im.src)) state.images.push({ ...im });
  const hint = $("templateHint"); hint.hidden = !t.hint; if (t.hint) hint.textContent = t.hint[getLang()];
  toUI(); renderImageList(); persist(); scheduleRender(0);
}

// ---------------------------------------------------------------------------------------------- render
function setError(msg) {
  const p = $("errorPanel"); p.hidden = !msg; $("errorText").textContent = msg || "";
  const h = $("errorHint"); h.hidden = true; h.textContent = "";
  if (msg && /no .* support|not supported|build/i.test(msg) && profile !== "full") {
    h.hidden = false; h.append(document.createTextNode(tr("errorHint")));
    for (const p2 of PROFILES.slice(PROFILES.indexOf(profile) + 1)) {
      const b = document.createElement("button"); b.type = "button"; b.textContent = tr("switchTo", { p: p2 }); b.addEventListener("click", () => switchProfile(p2)); h.append(b);
    }
  }
  document.body.dataset.status = msg ? "error" : "ok";
}
function toast(s) { const t = $("toast"); t.textContent = s; clearTimeout(toast.t); toast.t = setTimeout(() => { t.textContent = ""; }, 3000); }

function buildInput() {
  const text = state[state.kind] ?? "";
  let source;
  if (state.kind === "html") source = text;
  else { try { source = JSON.parse(text); } catch (e) { throw new Error(tr("invalidJson", { msg: e.message })); } }
  const o = { width: state.width, height: state.height, devicePixelRatio: state.dpr };
  if (state.images.length) o.images = state.images.map((im) => ({ src: im.src, data: bytesOfImage(im) }));
  if (state.css.trim()) o.css = [state.css];
  return { source, o };
}
function median(a) { const s = [...a].sort((x, y) => x - y); return s[s.length >> 1]; }

async function render() {
  if (!engine) return;
  clearTimeout(debounce);
  fromUI(); persist();
  const seq = ++renderSeq;
  const fmt = state.format;
  try {
    const { source, o } = buildInput();
    const r = engine.renderer;
    let out, t0 = performance.now(), isText = false;
    if (fmt === "svg") { out = r.renderSvgSync(source, o); isText = true; }
    else if (fmt.startsWith("anim-")) {
      out = r.renderAnimationSync({ scenes: [{ node: source, durationMs: state.duration }], width: state.width, height: state.height, fps: state.fps, format: fmt.slice(5), devicePixelRatio: state.dpr, ...(o.images ? { images: o.images } : {}), ...(o.css ? { css: o.css } : {}) });
    } else {
      o.format = fmt; if (fmt === "jpeg") o.quality = state.quality; if (state.timeMs) o.timeMs = Math.round(state.timeMs);
      out = r.renderSync(source, o);
    }
    const ms = performance.now() - t0;
    if (seq !== renderSeq) return;
    times.push(ms); if (times.length > 10) times.shift();
    await show(out, fmt, isText, o);
    setError("");
    $("stTime").textContent = `${ms.toFixed(1)} ${tr("ms")} (${tr("median", { n: times.length })}: ${median(times).toFixed(1)})`;
    if (state.measure) await drawMeasure(source, o); else $("overlay").hidden = true;
  } catch (e) {
    setError(String(e && e.message || e));
    $("downloadBtn").disabled = $("copyBtn").disabled = !last;
  }
  $("stMem").textContent = fmtBytes(engine.renderer.memoryBytes());
  renderCount++; document.body.dataset.renders = String(renderCount);
}

async function show(out, fmt, isText, o) {
  const mime = MIME[fmt];
  const img = $("outImg"), cv = $("outCanvas");
  let bytes = isText ? new TextEncoder().encode(out) : out;
  let size = bytes.length;
  let w = 0, h = 0;
  if (fmt === "raw") {
    w = Math.round(state.width * state.dpr); h = Math.round(state.height * state.dpr);
    cv.width = w; cv.height = h;
    cv.getContext("2d").putImageData(new ImageData(new Uint8ClampedArray(out.buffer, out.byteOffset, w * h * 4), w, h), 0, 0);
    img.hidden = true; cv.hidden = false;
    last = { fmt, mime, bytes, blob: null, canvas: true };
  } else {
    const blob = new Blob([bytes], { type: mime });
    const url = URL.createObjectURL(blob);
    img.hidden = false; cv.hidden = true;
    img.src = url;
    await img.decode().catch(() => { throw new Error("The browser could not decode the output (" + mime + ")"); });
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    blobUrl = url; w = img.naturalWidth; h = img.naturalHeight;
    last = { fmt, mime, bytes, blob, canvas: false };
  }
  $("empty").hidden = true; $("frame").hidden = false;
  $("downloadBtn").disabled = $("copyBtn").disabled = false;
  $("stBytes").textContent = `${fmtBytes(size)} (${size} B)`;
  $("stDims").textContent = `${w} x ${h}` + (fmt.startsWith("anim-") ? ` ${fmt.slice(5)}` : "");
  Object.assign(document.body.dataset, { outFormat: fmt, outW: String(w), outH: String(h), outBytes: String(size) });
  void o;
}

async function drawMeasure(source, o) {
  const { format, quality, timeMs, ...mo } = o;
  const tree = engine.renderer.measureSync(source, { ...mo, timeMs: Math.round(state.timeMs) });
  const ov = $("overlay"); ov.textContent = ""; ov.hidden = false;
  const W = tree.width || state.width, H = tree.height || state.height;
  const add = (x, y, w, h, cls) => { const d = document.createElement("i"); if (cls) d.className = cls; Object.assign(d.style, { left: (x / W * 100) + "%", top: (y / H * 100) + "%", width: (w / W * 100) + "%", height: (h / H * 100) + "%" }); ov.append(d); };
  (function walk(n, ox, oy, depth) {
    const tf = n.transform || [1, 0, 0, 1, 0, 0];
    const x = ox + tf[4], y = oy + tf[5];
    if (depth > 0) add(x, y, n.width, n.height);
    for (const run of n.runs || []) add(x + run.x, y + run.y, run.width, run.height, "run");
    for (const c of n.children || []) walk(c, x, y, depth + 1);
  })(tree, 0, 0, 0);
  document.body.dataset.measureBoxes = String(ov.childElementCount);
}

function scheduleRender(delay = 350) {
  if (!engine) return;
  clearTimeout(debounce);
  if (delay > 0 && !$("autoRender").checked) return;
  debounce = setTimeout(render, delay);
}

// ---------------------------------------------------------------------------------------------- output actions
function download() {
  if (!last) return;
  const name = `bm-engine.${EXT[last.fmt]}`;
  const finish = (blob) => {
    const url = URL.createObjectURL(blob); const a = document.createElement("a");
    a.href = url; a.download = name; document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  };
  if (last.canvas && last.fmt === "raw") { finish(new Blob([last.bytes], { type: "application/octet-stream" })); return; }
  finish(last.blob);
}
async function copyDataUrl() {
  if (!last) return;
  let url;
  if (last.canvas) url = $("outCanvas").toDataURL("image/png");
  else if (last.fmt === "svg") url = "data:image/svg+xml;base64," + b64std(last.bytes);
  else url = `data:${last.mime};base64,${b64std(last.bytes)}`;
  window.__lastDataUrl = url;
  let ok = false;
  try { await navigator.clipboard.writeText(url); ok = true; } catch {
    const ta = document.createElement("textarea"); ta.value = url; ta.style.position = "fixed"; ta.style.opacity = "0"; document.body.append(ta); ta.select();
    try { ok = document.execCommand("copy"); } catch { ok = false; } ta.remove();
  }
  toast(ok ? tr("copied", { n: url.length }) : tr("copyFailed"));
}
async function share() {
  fromUI();
  history.replaceState(null, "", "#" + await encodeHash());
  let ok = false;
  try { await navigator.clipboard.writeText(location.href); ok = true; } catch { /* ignore */ }
  toast(ok ? tr("linkCopied") : tr("linkSet"));
}
function switchProfile(p) {
  fromUI(); persist();
  try { localStorage.setItem("bm-playground-profile", p); } catch { /* ignore */ }
  const u = new URL(location.href); u.searchParams.set("profile", p); u.hash = "";
  location.href = u.href;
}

// ---------------------------------------------------------------------------------------------- init
function wire() {
  $("profile").addEventListener("change", (e) => switchProfile(e.target.value));
  $("lang").addEventListener("change", (e) => {
    setLang(e.target.value); try { localStorage.setItem("bm-playground-lang", getLang()); } catch { /* ignore */ }
    const u = new URL(location.href); if (u.searchParams.has("lang")) { u.searchParams.set("lang", getLang()); history.replaceState(null, "", u.href); }
    applyI18n(); fillTemplateSelect(); renderFontList(); renderImageList(); updateVisibility();
    const t = templates.find((x) => x.id === state.template); if (t?.hint) { $("templateHint").hidden = false; $("templateHint").textContent = t.hint[getLang()]; }
    if (engine) $("binInfo").textContent = `${engine.file} - ${fmtBytes(engine.wasmBytes)}`;
  });
  $("template").addEventListener("change", (e) => { if (e.target.value) applyTemplate(e.target.value); else $("templateHint").hidden = true; });
  for (const b of document.querySelectorAll("#tabs button")) b.addEventListener("click", () => {
    fromUI(); state.kind = b.dataset.kind; toUI(); persist(); scheduleRender(0);
  });
  const onEdit = () => { fromUI(); state.template = ""; $("template").value = ""; updateVisibility(); persist(); scheduleRender(); };
  for (const id of ["src", "css"]) $(id).addEventListener("input", onEdit);
  const onOpt = () => { fromUI(); updateVisibility(); persist(); scheduleRender(); };
  for (const id of [...FIELDS, "format", "autoRender", "measureToggle"]) { $(id).addEventListener("input", onOpt); $(id).addEventListener("change", onOpt); }
  $("measureToggle").addEventListener("change", () => { if (!$("measureToggle").checked) $("overlay").hidden = true; scheduleRender(0); });
  for (const id of ["src", "css"]) $(id).addEventListener("keydown", (e) => {
    if (e.key === "Tab" && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.metaKey) {
      e.preventDefault(); const t = e.target, s = t.selectionStart; t.setRangeText("  ", s, t.selectionEnd, "end"); t.dispatchEvent(new Event("input", { bubbles: true }));
    }
  });
  document.addEventListener("keydown", (e) => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); render(); } });
  $("renderBtn").addEventListener("click", render);
  $("downloadBtn").addEventListener("click", download);
  $("copyBtn").addEventListener("click", copyDataUrl);
  $("shareBtn").addEventListener("click", share);
  $("fontInput").addEventListener("change", async (e) => { const fs = [...e.target.files]; e.target.value = ""; await onFontFiles(fs); });
  $("imageInput").addEventListener("change", async (e) => { const fs = [...e.target.files]; e.target.value = ""; await onImageFiles(fs); });
}

// ?theme=light|dark forces a colour scheme (the docs site passes its own); otherwise prefers-color-scheme applies.
// An embedding page can also switch it live: postMessage({ type: "bm-playground:theme", theme: "dark" }).
function setTheme(t) {
  if (t === "light" || t === "dark") document.documentElement.dataset.theme = t;
  else delete document.documentElement.dataset.theme;
}
window.addEventListener("message", (e) => {
  if (e.origin === location.origin && e.data && e.data.type === "bm-playground:theme") setTheme(e.data.theme);
});

async function main() {
  const q = new URLSearchParams(location.search);
  setTheme(q.get("theme"));
  // ?lang=en|vi (set by the docs site) wins over the stored choice and the browser language.
  let lang = (navigator.language || "").startsWith("vi") ? "vi" : "en";
  try { lang = localStorage.getItem("bm-playground-lang") || lang; } catch { /* ignore */ }
  if (q.get("lang") === "en" || q.get("lang") === "vi") lang = q.get("lang");
  setLang(lang); $("lang").value = getLang();
  profile = pickProfile(); $("profile").value = profile;
  try { localStorage.setItem("bm-playground-profile", profile); } catch { /* ignore */ }
  applyI18n();
  fillTemplateSelect();
  wire();

  const fromHash = await decodeHash(location.hash);
  const local = loadLocal();
  if (fromHash) state = { ...defaultState(), ...(local || {}), ...fromHash };
  else if (local) state = local;
  else { state = defaultState(); }
  if (!fromHash && !local) {
    const t = templates[0]; state.kind = t.kind; state[t.kind] = t.source; state.width = t.width; state.height = t.height; state.template = t.id;
    for (const im of t.images ? t.images() : []) state.images.push({ ...im });
  } else if (state.template && !state[state.kind]) {
    const t = templates.find((x) => x.id === state.template); if (t) state[t.kind] = t.source;
  }
  if (!["json", "html", "tw"].includes(state.kind)) state.kind = "json";

  try {
    await loadEngine();
    await loadDefaultFonts();
  } catch (e) { setError("Failed to start the engine: " + (e.message || e)); document.body.dataset.ready = "error"; return; }
  fillTemplateSelect(); toUI(); renderFontList(); renderImageList();
  const t = templates.find((x) => x.id === state.template); if (t?.hint) { $("templateHint").hidden = false; $("templateHint").textContent = t.hint[getLang()]; }
  document.body.dataset.ready = "1";
  document.body.dataset.profile = profile;
  window.pg = { get state() { return state; }, get engine() { return engine; }, profile, render, applyTemplate, fonts, get last() { return last; }, templates };
  await render();
}
main();
