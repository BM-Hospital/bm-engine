// bm-render playground: plain ES modules, no build step, no network access beyond same-origin files.
// Two output modes share the editor (source, CSS, fonts, images):
//   Image: js/index.mjs + bm_render.{core,standard,}.wasm. Profile switching: js/index.mjs keeps ONE wasm instance per
//          module instance, and js/addons.mjs imports the same module by URL, so changing profile reloads the page
//          with ?profile=<name>.
//   PDF:   js/pdf.mjs + bm_render.pdf.wasm (its own module instance), imported only when PDF mode is first used.
//          The preview is the browser's PDF viewer (blob URL in an iframe) or, where there is none (phones) or on
//          request, pages drawn by pdf.js, which is vendored next to the app and also imported only then.
// ?mode=image|pdf picks the mode (the switch in the header changes it in place and updates the URL).
import { config } from "./config.js";
import { templates } from "./templates.js";
import { tr, setLang, applyI18n, getLang } from "./i18n.js";
import * as P from "./pdf-options.js";

const $ = (id) => document.getElementById(id);
const rel = (p) => new URL(p, import.meta.url).href; // runtime URLs resolve next to this file via config.js
/** URL of a vendored engine file; the build adds ?v=<content hash> so the host may cache it for a year. */
const vurl = (file) => rel(config.jsBase + file) + (config.versions?.[file] ? `?v=${config.versions[file]}` : "");
const LS = "bm-playground-state-v1";
const PROFILES = ["core", "standard", "full"];
const MODES = ["image", "pdf"];
const FONT_FILES = [
  ["Inter-Regular.ttf", "Inter", 400, "normal"], ["Inter-SemiBold.ttf", "Inter", 600, "normal"], ["Inter-Bold.ttf", "Inter", 700, "normal"],
  ["Inter-Italic.ttf", "Inter", 400, "italic"], ["NotoSans-Regular.ttf", "Noto Sans", 400, "normal"], ["NotoSans-Bold.ttf", "Noto Sans", 700, "normal"],
];
const MIME = { png: "image/png", jpeg: "image/jpeg", webp: "image/webp", svg: "image/svg+xml", "anim-webp": "image/webp", "anim-apng": "image/png", "anim-gif": "image/gif", raw: "application/octet-stream", pdf: "application/pdf" };
const EXT = { png: "png", jpeg: "jpg", webp: "webp", svg: "svg", "anim-webp": "webp", "anim-apng": "png", "anim-gif": "gif", raw: "rgba", pdf: "pdf" };
const PDF_PAGE_LIMIT = 30; // pdf.js preview draws at most this many pages

// ---------------------------------------------------------------------------------------------- state
const defaultState = () => ({
  mode: "image",
  kind: "json", json: "", html: "", tw: "", css: "", width: 1200, height: 630, dpr: 1, format: "png", quality: 80, timeMs: 0, fps: 15, duration: 1000,
  template: "og-card", images: [], auto: true, measure: false,
  pdf: P.defaultPdf(), pdfTemplate: "", pdfSeen: false, pdfPreview: "auto",
});
let state = defaultState();
let profile = "full";
const engines = { image: null, pdf: null }; // { kind, mod, renderer, features, wasmBytes, file, fonts: Map, addons }
const loading = { image: null, pdf: null };
let pdfTemplates = null; // pdf-templates.js, imported with the PDF engine
const fontBytes = new Map(); // default font file -> Uint8Array (fetched once, registered on each engine)
const uploads = []; // { file, data, families: string[] } uploaded fonts, registered on every engine
const times = { image: [], pdf: [] };
let last = null; // { fmt, mime, bytes, blob, canvas, url? }
let blobUrl = "";
let pdfUrl = "";
let renderSeq = 0;
let renderCount = 0;
let debounce = 0;
let ready = false; // UI events before the saved state is in the form must not overwrite it
const embedded = new URLSearchParams(location.search).get("embed") === "1";

const json = (o) => JSON.stringify(o);
function saveLocal() {
  const base = { ...state };
  try { localStorage.setItem(LS, json(base)); } catch {
    try { localStorage.setItem(LS, json({ ...base, images: [] })); } catch { /* storage unavailable */ }
  }
}
function loadLocal() {
  try { const s = JSON.parse(localStorage.getItem(LS) || "null"); if (s && typeof s === "object") return { ...defaultState(), ...s, pdf: { ...P.defaultPdf(), ...(s.pdf || {}) } }; } catch { /* ignore */ }
  return null;
}

// URL hash: "#s=z.<base64url(deflate-raw(json))>" when CompressionStream exists, "#s=p.<base64url(json)>" otherwise.
const b64u = (u8) => { let s = ""; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); };
const unb64u = (s) => { const b = atob(s.replace(/-/g, "+").replace(/_/g, "/")); const u = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i); return u; };
async function pipe(u8, stream) { return new Uint8Array(await new Response(new Blob([u8]).stream().pipeThrough(stream)).arrayBuffer()); }
const SHARE_KEYS = ["mode", "kind", "json", "html", "tw", "css", "width", "height", "dpr", "format", "quality", "timeMs", "fps", "duration", "template", "pdf", "pdfTemplate"];
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

// ---------------------------------------------------------------------------------------------- engines
function pickProfile() {
  const q = new URLSearchParams(location.search).get("profile");
  if (PROFILES.includes(q)) return q;
  try { const p = localStorage.getItem("bm-playground-profile"); if (PROFILES.includes(p)) return p; } catch { /* ignore */ }
  return "full";
}
const fmtBytes = (n) => (n >= 1048576 ? (n / 1048576).toFixed(2) + " MiB" : (n / 1024).toFixed(1) + " KiB");
const eng = () => engines[state.mode];

async function defaultFont(file) {
  if (!fontBytes.has(file)) {
    fontBytes.set(file, (async () => {
      const res = await fetch(rel(config.fontsBase + file));
      if (!res.ok) throw new Error(`failed to fetch font ${file}: HTTP ${res.status}`);
      return new Uint8Array(await res.arrayBuffer());
    })());
  }
  return fontBytes.get(file);
}
function addFamilies(e, fams, file, builtin) {
  for (const f of fams || []) {
    const x = e.fonts.get(f.name) || { files: [], builtin };
    if (!x.files.includes(file)) x.files.push(file);
    e.fonts.set(f.name, x);
  }
}
/** Loads the engine of a mode once: module, wasm, default fonts, uploaded fonts. */
function ensureEngine(mode) {
  if (engines[mode]) return Promise.resolve(engines[mode]);
  if (!loading[mode]) loading[mode] = (async () => {
    const file = mode === "pdf" ? config.wasm.pdf : config.wasm[profile];
    const [mod, wasmBytes] = await Promise.all([
      import(rel(config.jsBase + (mode === "pdf" ? "pdf.mjs" : "index.mjs"))),
      fetch(vurl(file)).then(async (res) => { if (!res.ok) throw new Error(`failed to fetch ${file}: HTTP ${res.status}`); return new Uint8Array(await res.arrayBuffer()); }),
      mode === "pdf" ? import("./pdf-templates.js").then((m) => { pdfTemplates = m.pdfTemplates; }) : null,
    ]);
    await mod.init(wasmBytes);
    if (mode === "pdf" && typeof mod.PdfRenderer !== "function") throw new Error("this pdf.mjs has no PdfRenderer export");
    const e = { kind: mode, mod, renderer: mode === "pdf" ? new mod.PdfRenderer() : new mod.Renderer(), features: { ...mod.features }, wasmBytes: wasmBytes.length, file, fonts: new Map(), addons: null };
    const fontData = await Promise.all(FONT_FILES.map(([f]) => defaultFont(f)));
    FONT_FILES.forEach(([f, name, weight, style], i) => addFamilies(e, e.renderer.registerFont({ name, data: fontData[i], weight, style }), f, true));
    for (const u of uploads) { try { addFamilies(e, e.renderer.registerFont(u.data), u.file, false); } catch { /* shown when it was uploaded */ } }
    engines[mode] = e;
    return e;
  })().catch((err) => { loading[mode] = null; throw err; });
  return loading[mode];
}
function showEngineInfo() {
  const e = eng();
  $("binInfo").textContent = e ? `${e.file} - ${fmtBytes(e.wasmBytes)}` : tr(state.mode === "pdf" ? "pdfLoading" : "loading");
  const chips = $("featChips"); chips.textContent = "";
  for (const [k, v] of Object.entries(e?.features || {})) {
    const s = document.createElement("span"); s.className = "chip" + (v ? "" : " off"); s.textContent = k; s.title = v ? "enabled" : "not in this build";
    chips.append(s);
  }
}
const has = (f) => !!eng()?.features[f];
async function ensureWoffAddon(e) {
  if (e.features.woff || e.addons || e.kind !== "image") return;
  e.addons = await import(rel(config.jsBase + "addons.mjs"));
  await e.addons.loadWoff(fetch(vurl(config.woffWasm)));
}
function memoryBytes(e) {
  if (!e) return 0;
  if (typeof e.renderer.memoryBytes === "function") return e.renderer.memoryBytes();
  return typeof e.mod.Renderer?.memoryBytes === "function" ? e.mod.Renderer.memoryBytes() : 0;
}

// ---------------------------------------------------------------------------------------------- fonts
function renderFontList() {
  const ul = $("fontList"); ul.textContent = "";
  const e = eng();
  const fonts = e?.fonts || new Map();
  if (!fonts.size) { const li = document.createElement("li"); li.textContent = tr("noFonts"); ul.append(li); }
  for (const [family, x] of fonts) {
    const li = document.createElement("li"); li.dataset.family = family;
    const name = document.createElement("span"); name.className = "name"; name.textContent = family;
    const small = document.createElement("small"); small.textContent = x.files.length > 1 ? tr("fontsFiles", { n: x.files.length }) : x.files[0]; small.title = x.files.join(", ");
    const rm = document.createElement("button"); rm.type = "button"; rm.textContent = tr("remove"); rm.dataset.remove = family;
    rm.addEventListener("click", () => {
      for (const en of Object.values(engines)) if (en) { en.renderer.unregisterFont(family); en.fonts.delete(family); }
      for (let i = uploads.length - 1; i >= 0; i--) if (uploads[i].families.includes(family)) uploads.splice(i, 1);
      renderFontList(); scheduleRender(0);
    });
    li.append(name, small, rm); ul.append(li);
  }
  $("fontsNote").textContent = tr("fontsNote", { woff: e?.features.woff ? tr("woffBuiltin") : tr("woffAddon") }) + (state.mode === "pdf" ? " " + tr("pdfFontsNote") : "");
}
async function onFontFiles(files) {
  $("fontsBox").open = true;
  const msg = $("fontMsg"); msg.textContent = "";
  for (const f of files) {
    try {
      const data = new Uint8Array(await f.arrayBuffer());
      const e = eng();
      if (/\.woff2?$/i.test(f.name)) await ensureWoffAddon(e);
      const fams = e.renderer.registerFont(data);
      addFamilies(e, fams, f.name, false);
      const u = { file: f.name, data, families: (fams || []).map((x) => x.name) };
      uploads.push(u);
      for (const other of Object.values(engines)) if (other && other !== e) { try { addFamilies(other, other.renderer.registerFont(data), f.name, false); } catch { /* the other build may lack WOFF */ } }
      msg.textContent = tr("fontAdded", { names: u.families.join(", ") });
    } catch (err) { msg.textContent = tr("fontFail", { msg: err.message || err }); }
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
const pdfFields = () => document.querySelectorAll("[data-pdf]");
function toUI() {
  $("src").value = state[state.kind] ?? "";
  $("css").value = state.css;
  for (const f of FIELDS) $(f).value = state[f];
  $("format").value = state.format;
  $("template").value = (state.mode === "pdf" ? state.pdfTemplate : state.template) || "";
  $("autoRender").checked = state.auto;
  $("measureToggle").checked = state.measure;
  $("pdfPreview").value = state.pdfPreview || "auto";
  fillConformance();
  for (const el of pdfFields()) {
    const v = state.pdf[el.dataset.pdf];
    if (el.type === "checkbox") el.checked = !!v; else el.value = v ?? "";
  }
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
  state.pdfPreview = $("pdfPreview").value;
  for (const el of pdfFields()) state.pdf[el.dataset.pdf] = el.type === "checkbox" ? el.checked : el.value;
}
function persist() { saveLocal(); }
/** Fills the size / tagged / pdfa / uncoveredText selects from the values the typings allow; tagged options that
 *  the selected pdfa level does not allow are disabled (ConformanceOptions in js/pdf-types.d.mts). */
function fillConformance() {
  const size = $("pdfSize");
  if (!size.options.length) {
    for (const v of [...P.PAGE_SIZES, "custom"]) { const o = document.createElement("option"); o.value = v; size.append(o); }
    for (const v of ["", ...P.PDFA_LEVELS]) { const o = document.createElement("option"); o.value = v; $("pdfPdfa").append(o); }
    for (const v of ["true", "false", "ua1", "ua2"]) { const o = document.createElement("option"); o.value = v; $("pdfTagged").append(o); }
    for (const v of P.UNCOVERED) { const o = document.createElement("option"); o.value = v; $("pdfUncovered").append(o); }
  }
  for (const o of size.options) o.textContent = o.value === "custom" ? tr("custom") : o.value;
  for (const o of $("pdfPdfa").options) o.textContent = o.value || tr("none");
  const ok = P.allowedTagged(state.pdf.pdfa);
  for (const o of $("pdfTagged").options) { o.textContent = o.value === "true" ? tr("taggedTrue") : o.value === "false" ? tr("taggedFalse") : o.value; o.disabled = !ok.includes(o.value); }
  if (!ok.includes(state.pdf.tagged)) state.pdf.tagged = "true";
  for (const o of $("pdfUncovered").options) o.textContent = o.value;
}
function updateVisibility() {
  const pdf = state.mode === "pdf";
  const viewport = state.pdf.layout === "viewport";
  for (const el of document.querySelectorAll(".pdf-only, .image-only, .paged-only, .viewport-only, .custom-only")) {
    const c = el.classList;
    el.hidden = (c.contains("pdf-only") && !pdf) || (c.contains("image-only") && pdf) || (c.contains("paged-only") && viewport) ||
      (c.contains("viewport-only") && !viewport) || (c.contains("custom-only") && state.pdf.size !== "custom");
  }
  $("profileBox").hidden = pdf;
  const f = state.format;
  $("qualityBox").hidden = f !== "jpeg";
  $("qualityVal").textContent = $("quality").value;
  $("timeBox").hidden = f.startsWith("anim-");
  $("timeVal").textContent = $("timeMs").value;
  $("fpsBox").hidden = $("durBox").hidden = !f.startsWith("anim-");
  if (!eng()) return;
  // annotate what this build lacks (inputs stay usable: the engine's own error is shown on render)
  const miss = { json: false, html: !has("html"), tw: !has("tw") };
  const label = pdf ? "pdf" : profile;
  for (const b of document.querySelectorAll("#tabs button")) { const m = b.querySelector(".miss"); m.hidden = !miss[b.dataset.kind]; m.textContent = "x " + label; m.title = tr("needsMissing", { list: b.dataset.kind }); }
  $("cssMiss").hidden = has("css"); $("cssMiss").textContent = "x " + label;
  const note = $("kindNote");
  const need = state.kind === "html" && !has("html") ? "html" : state.kind === "tw" && !has("tw") ? "tw" : null;
  note.hidden = !need;
  if (need) note.textContent = `${label}: ${tr("needsMissing", { list: need })}`;
  const fo = { svg: "renderSvg", "anim-webp": "animation", "anim-apng": "animation", "anim-gif": "animation" };
  for (const o of $("format").options) { const feat = fo[o.value]; const base = o.dataset.i18n ? tr(o.dataset.i18n) : o.value; o.textContent = feat && !has(feat) ? `${base} (x ${feat})` : base; }
}
const modeTemplates = () => (state.mode === "pdf" ? pdfTemplates || [] : templates);
function fillTemplateSelect() {
  const sel = $("template"); sel.textContent = "";
  const blank = document.createElement("option"); blank.value = ""; blank.textContent = "-"; sel.append(blank);
  for (const t of modeTemplates()) {
    const o = document.createElement("option"); o.value = t.id;
    const miss = eng() && t.needs ? t.needs.filter((n) => !has(n)) : [];
    o.textContent = t.title[getLang()] + (miss.length ? `  (x ${miss.join(", ")})` : "");
    o.dataset.missing = miss.join(",");
    sel.append(o);
  }
  sel.value = (state.mode === "pdf" ? state.pdfTemplate : state.template) || "";
}
function showHint() {
  const t = modeTemplates().find((x) => x.id === (state.mode === "pdf" ? state.pdfTemplate : state.template));
  const hint = $("templateHint"); hint.hidden = !t?.hint; if (t?.hint) hint.textContent = t.hint[getLang()];
}
function loadTemplateInto(t) {
  state.kind = t.kind; state[t.kind] = t.source; state.css = t.css || "";
  for (const im of t.images ? t.images() : []) if (!state.images.some((x) => x.src === im.src)) state.images.push({ ...im });
  // the editor is shared: the other mode's template no longer describes it
  if (state.mode === "pdf") { state.pdfTemplate = t.id; state.template = ""; state.pdf = { ...P.defaultPdf(), ...t.pdf }; }
  else {
    // the PDF options of a PDF example describe a document the editor no longer holds
    if (state.pdfTemplate) state.pdf = P.defaultPdf();
    state.template = t.id; state.pdfTemplate = ""; state.width = t.width; state.height = t.height; state.timeMs = t.timeMs || 0; state.format = t.format || "png";
  }
}
/**
 * The template select names an example only while the editor still shows it. A tab switch, or content carried over
 * from the other mode (Image <-> PDF keeps the editor), turns it into "-". With `resetPdf`, the PDF options that came
 * with that example (page size, viewport, title, ...) are dropped too: they described a document no longer shown.
 */
function reconcileTemplate(resetPdf) {
  const pdf = state.mode === "pdf";
  const id = pdf ? state.pdfTemplate : state.template;
  if (!id) return;
  const t = modeTemplates().find((x) => x.id === id);
  if (t && t.kind === state.kind && state[t.kind] === t.source) return;
  if (pdf) { state.pdfTemplate = ""; if (resetPdf) state.pdf = P.defaultPdf(); } else state.template = "";
}
function applyTemplate(id) {
  const t = modeTemplates().find((x) => x.id === id); if (!t) return;
  loadTemplateInto(t);
  showHint(); toUI(); renderImageList(); persist(); scheduleRender(0);
}
/** Everything that depends on the mode: accent, switch, labels, which panels show. */
function applyModeUI() {
  const pdf = state.mode === "pdf";
  document.documentElement.dataset.mode = state.mode;
  document.body.dataset.mode = state.mode;
  for (const b of document.querySelectorAll("#modeSwitch button")) b.setAttribute("aria-checked", String(b.dataset.mode === state.mode));
  $("subtitle").textContent = tr(pdf ? "subtitlePdf" : "subtitle");
  $("cssNote").textContent = tr(pdf ? "cssNotePdf" : "cssNote");
  $("downloadBtn").textContent = tr(pdf ? "downloadPdf" : "download");
  $("stDimsLbl").textContent = tr(pdf ? "pages" : "dims");
  $("stage").classList.toggle("is-pdf", pdf);
  document.title = pdf ? "bm-render PDF playground" : "bm-render playground";
  updateVisibility();
}

// ---------------------------------------------------------------------------------------------- render
function setError(msg) {
  const p = $("errorPanel"); p.hidden = !msg; $("errorText").textContent = msg || "";
  const h = $("errorHint"); h.hidden = true; h.textContent = "";
  if (msg && state.mode === "image" && /no .* support|not supported|build/i.test(msg) && profile !== "full") {
    h.hidden = false; h.append(document.createTextNode(tr("errorHint")));
    for (const p2 of PROFILES.slice(PROFILES.indexOf(profile) + 1)) {
      const b = document.createElement("button"); b.type = "button"; b.textContent = tr("switchTo", { p: p2 }); b.addEventListener("click", () => switchProfile(p2)); h.append(b);
    }
  }
  // the engine counts PDF/UA and PDF/A violations without naming them: list the usual causes
  if (msg && state.mode === "pdf" && /validation failed/.test(msg)) { h.hidden = false; h.textContent = tr("validationHint"); }
  document.body.dataset.status = msg ? "error" : "ok";
}
function toast(s) { const t = $("toast"); t.textContent = s; clearTimeout(toast.t); toast.t = setTimeout(() => { t.textContent = ""; }, 3000); }
const errText = (e) => String(e && e.message || e);

function buildInput() {
  const source = P.parseSource(state.kind, state[state.kind] ?? "", tr);
  const o = { width: state.width, height: state.height, devicePixelRatio: state.dpr };
  if (state.images.length) o.images = state.images.map((im) => ({ src: im.src, data: bytesOfImage(im) }));
  if (state.css.trim()) o.css = [state.css];
  return { source, o };
}
function buildPdfInput() {
  const source = P.parseSource(state.kind, state[state.kind] ?? "", tr);
  const o = P.withResources(P.buildPdfOptions(state.pdf, tr), { css: state.css, images: state.images, bytesOf: bytesOfImage });
  return { source, o };
}
function median(a) { const s = [...a].sort((x, y) => x - y); return s[s.length >> 1]; }
function noteTime(ms) {
  const a = times[state.mode]; a.push(ms); if (a.length > 10) a.shift();
  $("stTime").textContent = `${ms.toFixed(1)} ${tr("ms")} (${tr("median", { n: a.length })}: ${median(a).toFixed(1)})`;
}

async function render() {
  if (!ready) return;
  clearTimeout(debounce);
  fromUI(); persist();
  const seq = ++renderSeq;
  const mode = state.mode;
  try {
    const e = await ensureEngine(mode);
    if (seq !== renderSeq || mode !== state.mode) return;
    if (mode === "pdf") await renderPdfOut(e, seq); else await renderImageOut(e, seq);
  } catch (err) {
    if (seq !== renderSeq) return;
    setError(errText(err));
    $("downloadBtn").disabled = $("copyBtn").disabled = $("openBtn").disabled = !last || last.mode !== state.mode;
  }
  $("stMem").textContent = fmtBytes(memoryBytes(engines[mode]));
  renderCount++; document.body.dataset.renders = String(renderCount);
}

async function renderImageOut(e, seq) {
  const fmt = state.format;
  const { source, o } = buildInput();
  const r = e.renderer;
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
  await show(out, fmt, isText);
  setError("");
  noteTime(ms);
  $("stMeasureBox").hidden = true;
  if (state.measure) await drawMeasure(source, o); else $("overlay").hidden = true;
}

async function show(out, fmt, isText) {
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
    last = { mode: "image", fmt, mime, bytes, blob: null, canvas: true };
  } else {
    const blob = new Blob([bytes], { type: mime });
    const url = URL.createObjectURL(blob);
    img.hidden = false; cv.hidden = true;
    img.src = url;
    await img.decode().catch(() => { throw new Error("The browser could not decode the output (" + mime + ")"); });
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    blobUrl = url; w = img.naturalWidth; h = img.naturalHeight;
    last = { mode: "image", fmt, mime, bytes, blob, canvas: false };
  }
  $("empty").hidden = true; $("frame").hidden = false; $("pdfView").hidden = true;
  $("downloadBtn").disabled = $("copyBtn").disabled = false;
  $("stBytes").textContent = `${fmtBytes(size)} (${size} B)`;
  $("stDims").textContent = `${w} x ${h}` + (fmt.startsWith("anim-") ? ` ${fmt.slice(5)}` : "");
  Object.assign(document.body.dataset, { outFormat: fmt, outW: String(w), outH: String(h), outBytes: String(size), outPages: "" });
}

async function drawMeasure(source, o) {
  const { format, quality, timeMs, ...mo } = o;
  const tree = eng().renderer.measureSync(source, { ...mo, timeMs: Math.round(state.timeMs) });
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

// ---------------------------------------------------------------------------------------------- PDF output
async function renderPdfOut(e, seq) {
  const { source, o } = buildPdfInput();
  const t0 = performance.now();
  const bytes = await e.renderer.render(source, o);
  const ms = performance.now() - t0;
  if (seq !== renderSeq) return;
  const pages = P.countPages(bytes);
  const blob = new Blob([bytes], { type: "application/pdf" });
  last = { mode: "pdf", fmt: "pdf", mime: "application/pdf", bytes, blob, canvas: false };
  setError("");
  noteTime(ms);
  $("empty").hidden = true; $("frame").hidden = true; $("pdfView").hidden = false;
  $("downloadBtn").disabled = $("openBtn").disabled = false;
  $("stBytes").textContent = `${fmtBytes(bytes.length)} (${bytes.length} B)`;
  $("stDims").textContent = pages ? String(pages) : tr("unknown");
  Object.assign(document.body.dataset, { outFormat: "pdf", outW: "", outH: "", outBytes: String(bytes.length), outPages: String(pages), outHead: new TextDecoder("latin1").decode(bytes.subarray(0, 8)) });
  const mb = $("stMeasureBox");
  mb.hidden = !state.measure;
  if (state.measure) {
    const m = await e.renderer.measure(source, P.measureOptions(o));
    $("stMeasure").textContent = `${Math.round(m.width)} x ${Math.round(m.height)} px`;
    document.body.dataset.measured = `${m.width}x${m.height}`;
  }
  await showPdf(blob, seq);
}
function previewKind() {
  const want = state.pdfPreview || "auto";
  if (want !== "auto") return want;
  const ua = navigator.userAgent || "";
  const phone = /Android|iPhone|iPad|iPod|Mobile/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  return navigator.pdfViewerEnabled === true && !phone ? "viewer" : "pdfjs";
}
async function showPdf(blob, seq) {
  const kind = previewKind();
  const frame = $("pdfFrame"), pages = $("pdfPages"), note = $("previewNote");
  document.body.dataset.pdfPreview = kind;
  const url = URL.createObjectURL(blob);
  const old = pdfUrl; pdfUrl = url;
  if (kind === "viewer") {
    pages.hidden = true; pages.textContent = "";
    frame.hidden = false;
    frame.src = url + "#view=FitH";
    note.textContent = tr("viaViewer");
    document.body.dataset.previewReady = "viewer";
  } else {
    frame.hidden = true; frame.removeAttribute("src");
    pages.hidden = false;
    await drawWithPdfjs(blob, seq);
  }
  if (old) setTimeout(() => URL.revokeObjectURL(old), 30000); // a tab opened from it keeps working for a while
}
let pdfjs = null;
async function loadPdfjs() {
  if (!pdfjs) {
    pdfjs = (async () => {
      const lib = await import(rel(config.pdfjsBase + "pdf.min.mjs"));
      lib.GlobalWorkerOptions.workerSrc = rel(config.pdfjsBase + "pdf.worker.min.mjs");
      return lib;
    })().catch((e) => { pdfjs = null; throw e; });
  }
  return pdfjs;
}
async function drawWithPdfjs(blob, seq) {
  const box = $("pdfPages"), note = $("previewNote");
  note.textContent = tr("pdfjsLoading");
  document.body.dataset.previewReady = "";
  try {
    const lib = await loadPdfjs();
    const data = new Uint8Array(await blob.arrayBuffer());
    const doc = await lib.getDocument({ data, isEvalSupported: false, verbosity: 0 }).promise;
    if (seq !== renderSeq) { doc.destroy(); return; }
    const frag = document.createDocumentFragment();
    const width = Math.max(200, box.clientWidth - 28);
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const n = Math.min(doc.numPages, PDF_PAGE_LIMIT);
    for (let i = 1; i <= n; i++) {
      const page = await doc.getPage(i);
      const base = page.getViewport({ scale: 1 });
      const vp = page.getViewport({ scale: (Math.min(width, base.width * 1.5) / base.width) * dpr });
      const cv = document.createElement("canvas");
      cv.width = Math.ceil(vp.width); cv.height = Math.ceil(vp.height);
      cv.style.width = Math.round(vp.width / dpr) + "px";
      cv.setAttribute("role", "img"); cv.setAttribute("aria-label", `${tr("pages")} ${i}`);
      await page.render({ canvasContext: cv.getContext("2d"), viewport: vp, canvas: cv }).promise;
      const label = document.createElement("p"); label.className = "pg-label"; label.textContent = `${i} / ${doc.numPages}`;
      frag.append(cv, label);
      if (seq !== renderSeq) { doc.destroy(); return; }
    }
    if (doc.numPages > n) { const more = document.createElement("p"); more.className = "pg-more"; more.textContent = tr("morePages", { n: doc.numPages - n }); frag.append(more); }
    box.textContent = ""; box.append(frag);
    note.textContent = tr("viaPdfjs", { v: lib.version || "" });
    document.body.dataset.previewReady = "pdfjs";
    document.body.dataset.pdfjsPages = String(doc.numPages);
    doc.destroy();
  } catch (err) {
    note.textContent = tr("pdfjsFail", { msg: errText(err) });
    document.body.dataset.previewReady = "pdfjs-error";
  }
}

function scheduleRender(delay = 350) {
  if (!ready) return;
  clearTimeout(debounce);
  if (delay > 0 && !$("autoRender").checked) return;
  debounce = setTimeout(render, delay);
}

// ---------------------------------------------------------------------------------------------- output actions
function download() {
  if (!last) return;
  const name = `bm-render.${EXT[last.fmt]}`;
  const finish = (blob) => {
    const url = URL.createObjectURL(blob); const a = document.createElement("a");
    a.href = url; a.download = name; document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  };
  if (last.canvas && last.fmt === "raw") { finish(new Blob([last.bytes], { type: "application/octet-stream" })); return; }
  finish(last.blob);
}
function openInTab() {
  if (!last || last.fmt !== "pdf") return;
  const url = URL.createObjectURL(last.blob);
  const a = document.createElement("a"); a.href = url; a.target = "_blank"; a.rel = "noopener";
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}
async function copyText(text) {
  try { await navigator.clipboard.writeText(text); return true; } catch {
    const ta = document.createElement("textarea"); ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0"; document.body.append(ta); ta.select();
    let ok = false; try { ok = document.execCommand("copy"); } catch { ok = false; } ta.remove(); return ok;
  }
}
async function copyDataUrl() {
  if (!last) return;
  let url;
  if (last.canvas) url = $("outCanvas").toDataURL("image/png");
  else if (last.fmt === "svg") url = "data:image/svg+xml;base64," + b64std(last.bytes);
  else url = `data:${last.mime};base64,${b64std(last.bytes)}`;
  window.__lastDataUrl = url;
  toast(await copyText(url) ? tr("copied", { n: url.length }) : tr("copyFailed"));
}
/** "Copy code": a Node.js module that reproduces the current PDF render with PdfRenderer. */
function pdfCode() {
  fromUI();
  const e = engines.pdf;
  const fonts = [];
  for (const [file, name, weight, style] of FONT_FILES) if (e?.fonts.has(name)) fonts.push({ file, name, weight, style, builtin: true });
  for (const u of uploads) fonts.push({ file: u.file, builtin: false });
  P.parseSource(state.kind, state[state.kind] ?? "", tr); // same error as a render for invalid JSON
  P.buildPdfOptions(state.pdf, tr);
  return P.pdfSnippet({ kind: state.kind, text: state[state.kind] ?? "", css: state.css, p: state.pdf, images: state.images, fonts });
}
async function copyCode() {
  let code;
  try { code = pdfCode(); } catch (err) { setError(errText(err)); return; }
  window.__lastCode = code;
  toast(await copyText(code) ? tr("codeCopied", { n: code.split("\n").length }) : tr("copyFailed"));
}
/** The shareable address: this page without the embedding parameters (embed, theme) plus the state hash. */
async function share() {
  fromUI();
  const hash = "#" + await encodeHash();
  history.replaceState(null, "", hash);
  const u = new URL(location.href); u.searchParams.delete("embed"); u.searchParams.delete("theme"); u.searchParams.set("mode", state.mode);
  window.__shareUrl = u.href;
  toast(await copyText(u.href) ? tr("linkCopied") : tr("linkSet"));
}
function switchProfile(p) {
  fromUI(); persist();
  try { localStorage.setItem("bm-playground-profile", p); } catch { /* ignore */ }
  const u = new URL(location.href); u.searchParams.set("profile", p); u.hash = "";
  location.href = u.href;
}
/** Image <-> PDF in place: the editor (source, CSS, images, fonts) is kept, the engine of the mode loads on first use. */
async function switchMode(m) {
  if (!MODES.includes(m) || m === state.mode) return;
  fromUI();
  state.mode = m; state.pdfSeen = state.pdfSeen || m === "pdf";
  persist();
  try { localStorage.setItem("bm-playground-mode", m); } catch { /* ignore */ }
  const u = new URL(location.href); u.searchParams.set("mode", m); u.hash = "";
  history.replaceState(null, "", u.href);
  if (embedded && window.parent !== window) window.parent.postMessage({ type: "bm-playground:mode", mode: m }, location.origin);
  applyModeUI(); showEngineInfo(); setError("");
  $("empty").hidden = false; $("frame").hidden = true; $("pdfView").hidden = true; $("previewNote").textContent = "";
  $("stTime").textContent = $("stBytes").textContent = $("stDims").textContent = "-";
  $("downloadBtn").disabled = $("copyBtn").disabled = $("openBtn").disabled = true;
  last = null;
  try { await ensureEngine(m); } catch (err) { setError("Failed to start the engine: " + errText(err)); return; }
  if (state.mode !== m) return;
  reconcileTemplate(true); persist();
  showEngineInfo(); fillTemplateSelect(); toUI(); showHint(); renderFontList();
  scheduleRender(0);
}

// ---------------------------------------------------------------------------------------------- init
function wire() {
  for (const b of document.querySelectorAll("#modeSwitch button")) b.addEventListener("click", () => { if (ready) switchMode(b.dataset.mode); });
  $("modeSwitch").addEventListener("keydown", (e) => {
    if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) return;
    e.preventDefault(); const m = state.mode === "pdf" ? "image" : "pdf";
    switchMode(m).then(() => document.querySelector(`#modeSwitch button[data-mode=${m}]`)?.focus());
  });
  $("profile").addEventListener("change", (e) => switchProfile(e.target.value));
  $("lang").addEventListener("change", (e) => {
    setLang(e.target.value); try { localStorage.setItem("bm-playground-lang", getLang()); } catch { /* ignore */ }
    const u = new URL(location.href); if (u.searchParams.has("lang")) { u.searchParams.set("lang", getLang()); history.replaceState(null, "", u.href); }
    applyI18n(); applyModeUI(); fillTemplateSelect(); fillConformance(); renderFontList(); renderImageList(); updateVisibility(); showHint();
    showEngineInfo();
  });
  $("template").addEventListener("change", (e) => { if (e.target.value) applyTemplate(e.target.value); else $("templateHint").hidden = true; });
  for (const b of document.querySelectorAll("#tabs button")) b.addEventListener("click", () => {
    if (!ready) return;
    fromUI(); state.kind = b.dataset.kind;
    if (!String(state[state.kind] ?? "").trim()) { const t = modeTemplates().find((x) => x.kind === state.kind); if (t) { applyTemplate(t.id); return; } }
    reconcileTemplate(false); fillTemplateSelect(); showHint();
    toUI(); persist(); scheduleRender(0);
  });
  const clearTemplate = () => { state.pdfTemplate = state.template = ""; $("template").value = ""; };
  const onEdit = () => { if (!ready) return; fromUI(); clearTemplate(); updateVisibility(); persist(); scheduleRender(); };
  for (const id of ["src", "css"]) $(id).addEventListener("input", onEdit);
  const onOpt = () => { if (!ready) return; fromUI(); updateVisibility(); persist(); scheduleRender(); };
  for (const id of [...FIELDS, "format", "autoRender", "measureToggle"]) { $(id).addEventListener("input", onOpt); $(id).addEventListener("change", onOpt); }
  for (const el of pdfFields()) {
    const ev = el.tagName === "SELECT" || el.type === "checkbox" ? "change" : "input";
    el.addEventListener(ev, () => { if (!ready) return; fromUI(); if (el.dataset.pdf === "pdfa") { fillConformance(); $("pdfTagged").value = state.pdf.tagged; } updateVisibility(); persist(); scheduleRender(); });
  }
  $("pdfPreview").addEventListener("change", () => { if (!ready) return; fromUI(); persist(); if (last?.fmt === "pdf") showPdf(last.blob, renderSeq); });
  $("insertCounters").addEventListener("click", () => {
    const f = document.querySelector('[data-pdf="footer"]');
    f.value = `<div style="font: 10px Inter; color: #64748b; text-align: center">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>`;
    f.dispatchEvent(new Event("input", { bubbles: true }));
  });
  $("measureToggle").addEventListener("change", () => { if (!$("measureToggle").checked) { $("overlay").hidden = true; $("stMeasureBox").hidden = true; } scheduleRender(0); });
  for (const el of [$("src"), $("css"), ...document.querySelectorAll("textarea[data-pdf]")]) el.addEventListener("keydown", (e) => {
    if (e.key === "Tab" && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.metaKey) {
      e.preventDefault(); const t = e.target, s = t.selectionStart; t.setRangeText("  ", s, t.selectionEnd, "end"); t.dispatchEvent(new Event("input", { bubbles: true }));
    }
  });
  document.addEventListener("keydown", (e) => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); render(); } });
  $("renderBtn").addEventListener("click", render);
  $("downloadBtn").addEventListener("click", download);
  $("openBtn").addEventListener("click", openInTab);
  $("copyBtn").addEventListener("click", copyDataUrl);
  $("codeBtn").addEventListener("click", copyCode);
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
  if (e.origin !== location.origin || !e.data) return;
  if (e.data.type === "bm-playground:theme") setTheme(e.data.theme);
  if (e.data.type === "bm-playground:set-mode" && ready) switchMode(e.data.mode);
});

function pickMode(fromHash) {
  if (MODES.includes(fromHash?.mode)) return fromHash.mode;
  const q = new URLSearchParams(location.search).get("mode");
  if (MODES.includes(q)) return q;
  try { const m = localStorage.getItem("bm-playground-mode"); if (MODES.includes(m)) return m; } catch { /* ignore */ }
  return "image";
}

async function main() {
  const q = new URLSearchParams(location.search);
  setTheme(q.get("theme"));
  if (embedded) document.body.classList.add("embedded");
  // ?lang=en|vi (set by the docs site) wins over the stored choice and the browser language.
  let lang = (navigator.language || "").startsWith("vi") ? "vi" : "en";
  try { lang = localStorage.getItem("bm-playground-lang") || lang; } catch { /* ignore */ }
  if (q.get("lang") === "en" || q.get("lang") === "vi") lang = q.get("lang");
  setLang(lang); $("lang").value = getLang();
  profile = pickProfile(); $("profile").value = profile;
  try { localStorage.setItem("bm-playground-profile", profile); } catch { /* ignore */ }

  const fromHash = await decodeHash(location.hash);
  const local = loadLocal();
  if (fromHash) state = { ...defaultState(), ...(local || {}), ...fromHash, pdf: { ...P.defaultPdf(), ...(fromHash.pdf || local?.pdf || {}) } };
  else if (local) state = local;
  else state = defaultState();
  state.mode = pickMode(fromHash);
  try { localStorage.setItem("bm-playground-mode", state.mode); } catch { /* ignore */ }
  if (!fromHash && !local) {
    const t = templates[0]; state.kind = t.kind; state[t.kind] = t.source; state.width = t.width; state.height = t.height; state.template = t.id;
    for (const im of t.images ? t.images() : []) state.images.push({ ...im });
  }
  if (!["json", "html", "tw"].includes(state.kind)) state.kind = "json";
  // A saved state with an empty editor (older builds could store one) falls back to its template, else the default one.
  if (!String(state[state.kind] ?? "").trim()) {
    const t = templates.find((x) => x.id === state.template && x.kind === state.kind) || templates.find((x) => x.kind === state.kind) || templates[0];
    state.kind = t.kind; state[t.kind] = t.source; state.template = t.id; if (!state.css) state.css = t.css || "";
    for (const im of t.images ? t.images() : []) if (!state.images.some((x) => x.src === im.src)) state.images.push({ ...im });
  }

  applyI18n();
  applyModeUI();
  fillConformance();
  showEngineInfo();
  wire();

  try {
    await ensureEngine(state.mode);
  } catch (e) { setError("Failed to start the engine: " + errText(e)); document.body.dataset.ready = "error"; return; }
  // The first visit of PDF mode (without a shared state) opens on the first PDF template; the in-app switch and the
  // docs site's Image | PDF switcher (which leaves a short-lived "carry" mark) keep whatever is in the editor.
  let carry = false;
  try { carry = Date.now() - Number(localStorage.getItem("bm-playground-carry") || 0) < 60000; localStorage.removeItem("bm-playground-carry"); } catch { /* ignore */ }
  if (state.mode === "pdf" && !state.pdfSeen && !fromHash && !carry) loadTemplateInto(pdfTemplates[0]);
  if (state.mode === "pdf") state.pdfSeen = true;
  reconcileTemplate(true);
  showEngineInfo(); fillTemplateSelect(); toUI(); ready = true; renderFontList(); renderImageList(); showHint();
  document.body.dataset.ready = "1";
  document.body.dataset.profile = profile;
  window.pg = {
    get state() { return state; }, get engine() { return eng(); }, engines, profile, render, applyTemplate, switchMode,
    get fonts() { return eng()?.fonts; }, get last() { return last; }, templates, get pdfTemplates() { return pdfTemplates; }, pdfCode,
  };
  await render();
}
main();
