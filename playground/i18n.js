// UI strings (EN / VI). Elements use data-i18n="key" (textContent), data-i18n-title="key" and
// data-i18n-ph="key" (placeholder); dynamic strings go through tr(key, vars) with {name} placeholders.
export const dict = {
  en: {
    title: "bm-engine playground",
    subtitle: "Zig + WebAssembly image renderer, running entirely in your browser",
    profile: "Profile", language: "Language", loading: "Loading engine...", loaded: "Loaded {file}", features: "Features",
    template: "Template", templateHint: "Loading a template replaces source, CSS and size.",
    needsMissing: "needs {list}", source: "Source", tabJson: "Node JSON", tabHtml: "HTML", tabTw: "Tailwind (tw)",
    css: "CSS (render option `css`)", cssNote: "Stylesheet text passed as the `css` option (standard / full).",
    options: "Options", width: "Width", height: "Height", dpr: "Device pixel ratio", format: "Format", quality: "Quality (jpeg)",
    timeMs: "timeMs (animation sample)", fps: "FPS", duration: "Duration (ms)",
    fmtRaw: "raw (canvas)", fmtSvg: "SVG (renderSvg)", fmtAwebp: "animated WebP", fmtApng: "animated APNG", fmtGif: "animated GIF",
    autoRender: "Auto render", render: "Render", download: "Download", copyDataUrl: "Copy data URL", share: "Share link", measure: "measure() overlay",
    fonts: "Fonts", uploadFont: "Upload font", fontsNote: "ttf / otf / ttc; woff / woff2 {woff}.", woffBuiltin: "built in", woffAddon: "via the WOFF add-on",
    remove: "Remove", noFonts: "No fonts registered.", fontsFiles: "{n} file(s)", fontAdded: "Registered {names}", fontFail: "Font error: {msg}",
    images: "Images", uploadImage: "Upload image", imagesNote: "Uploaded images become entries of the `images` option, referenced from a node as src. A `data:` URL also works inline in src.",
    imgKey: "src key", noImages: "No images.",
    output: "Output", renderTime: "Render", median: "median of {n}", size: "Size", dims: "Pixels", memory: "wasm memory", ms: "ms",
    error: "Error", errorHint: "This build lacks a feature the input needs. Try the standard or full profile:", switchTo: "Switch to {p}",
    invalidJson: "Invalid JSON: {msg}", copied: "Copied ({n} chars)", copyFailed: "Could not copy", linkCopied: "Link copied", linkSet: "Link is in the address bar",
    empty: "Nothing rendered yet.", rendering: "Rendering...", unsupportedFormat: "Format not available in this build",
    rawNote: "raw RGBA is drawn on a canvas; Download saves the PNG.", binSize: "{kb} KB",
  },
  vi: {
    title: "bm-engine playground",
    subtitle: "Bộ render ảnh Zig + WebAssembly, chạy hoàn toàn trong trình duyệt của bạn",
    profile: "Profile", language: "Ngôn ngữ", loading: "Đang tải engine...", loaded: "Đã tải {file}", features: "Tính năng",
    template: "Mẫu", templateHint: "Chọn mẫu sẽ thay nguồn, CSS và kích thước.",
    needsMissing: "cần {list}", source: "Nguồn", tabJson: "Node JSON", tabHtml: "HTML", tabTw: "Tailwind (tw)",
    css: "CSS (tuỳ chọn `css`)", cssNote: "Nội dung stylesheet truyền qua tuỳ chọn `css` (standard / full).",
    options: "Tuỳ chọn", width: "Rộng", height: "Cao", dpr: "Tỉ lệ điểm ảnh", format: "Định dạng", quality: "Chất lượng (jpeg)",
    timeMs: "timeMs (mốc hoạt ảnh)", fps: "FPS", duration: "Thời lượng (ms)",
    fmtRaw: "raw (canvas)", fmtSvg: "SVG (renderSvg)", fmtAwebp: "WebP động", fmtApng: "APNG động", fmtGif: "GIF động",
    autoRender: "Tự động render", render: "Render", download: "Tải xuống", copyDataUrl: "Sao chép data URL", share: "Liên kết chia sẻ", measure: "lớp measure()",
    fonts: "Font", uploadFont: "Tải font lên", fontsNote: "ttf / otf / ttc; woff / woff2 {woff}.", woffBuiltin: "có sẵn", woffAddon: "qua add-on WOFF",
    remove: "Xoá", noFonts: "Chưa đăng ký font nào.", fontsFiles: "{n} tệp", fontAdded: "Đã đăng ký {names}", fontFail: "Lỗi font: {msg}",
    images: "Ảnh", uploadImage: "Tải ảnh lên", imagesNote: "Ảnh tải lên trở thành mục của tuỳ chọn `images`, dùng trong node qua src. URL `data:` cũng dùng trực tiếp được trong src.",
    imgKey: "khoá src", noImages: "Chưa có ảnh.",
    output: "Kết quả", renderTime: "Render", median: "trung vị của {n}", size: "Dung lượng", dims: "Điểm ảnh", memory: "bộ nhớ wasm", ms: "ms",
    error: "Lỗi", errorHint: "Bản build này thiếu tính năng mà đầu vào cần. Hãy thử profile standard hoặc full:", switchTo: "Chuyển sang {p}",
    invalidJson: "JSON không hợp lệ: {msg}", copied: "Đã sao chép ({n} ký tự)", copyFailed: "Không sao chép được", linkCopied: "Đã sao chép liên kết", linkSet: "Liên kết nằm trên thanh địa chỉ",
    empty: "Chưa có gì được render.", rendering: "Đang render...", unsupportedFormat: "Bản build này không hỗ trợ định dạng",
    rawNote: "raw RGBA được vẽ lên canvas; Tải xuống lưu PNG.", binSize: "{kb} KB",
  },
};

let lang = "en";
export const getLang = () => lang;
export function setLang(l) { lang = dict[l] ? l : "en"; document.documentElement.lang = lang; }
export function tr(key, vars) {
  let s = dict[lang][key] ?? dict.en[key] ?? key;
  if (vars) for (const [k, v] of Object.entries(vars)) s = s.replaceAll(`{${k}}`, v);
  return s;
}
export function applyI18n(root = document) {
  for (const el of root.querySelectorAll("[data-i18n]")) el.textContent = tr(el.dataset.i18n);
  for (const el of root.querySelectorAll("[data-i18n-title]")) el.title = tr(el.dataset.i18nTitle);
  for (const el of root.querySelectorAll("[data-i18n-ph]")) el.placeholder = tr(el.dataset.i18nPh);
}
