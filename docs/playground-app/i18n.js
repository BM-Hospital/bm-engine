// UI strings (EN / VI). Elements use data-i18n="key" (textContent), data-i18n-title="key" and
// data-i18n-ph="key" (placeholder); dynamic strings go through tr(key, vars) with {name} placeholders.
export const dict = {
  en: {
    title: "bm-render playground",
    subtitlePdf: "Zig + WebAssembly PDF writer (bm-render/pdf), running entirely in your browser",
    modeLabel: "Output", modeImage: "Image", modePdf: "PDF", downloadPdf: "Download .pdf",
    cssNotePdf: "Stylesheet text passed as the `css` option; it can also hold @page rules.",
    pdfPage: "Page", layout: "Layout", layoutPaged: "Paged (size, margins, bands)", layoutViewport: "One page (viewport)",
    custom: "custom (width x height)", widthPx: "Width (px)", heightPx: "Height (px)", vpHeight: "Height (px)", fitContent: "fit content",
    mTop: "Margin top", mRight: "Right", mBottom: "Bottom", mLeft: "Left", rangesPh: "all pages, or e.g. 1, 3-5, 7-", bgPh: "none, or a CSS colour",
    pageNote: "Sizes and margins are CSS px (96 per inch). An empty margin is \"auto\": 10 mm, or as tall as the header / footer band on that side.",
    bands: "Header and footer", insertCounters: "Footer: Page X of Y", plainFirst: "No header / footer on the first page (pages.first)",
    bandNote: "HTML, or a node tree as JSON ({...}). Elements classed pageNumber / totalPages receive the counters. A band is laid out on its own: set its font on the band.",
    docStd: "Document and standards", docTitle: "Title (metadata.title)", docAuthor: "Authors (metadata.authors)", docSubject: "Subject (metadata.description)",
    docKeywords: "Keywords (metadata.keywords)", docDate: "metadata.creationDate", commaPh: "comma separated", outlineNote: "(bookmarks from h1-h6)",
    taggedTrue: "true (default)", taggedFalse: "false", none: "none",
    stdNote: "Only the tagged / pdfa pairs the typings allow are selectable. PDF/UA needs a title (and ua2 a lang); the a levels need lang and alt text. Validation errors come from the engine.",
    preview: "Preview", previewAuto: "Auto", previewViewer: "Browser viewer", previewPdfjs: "pdf.js pages", previewTitle: "PDF preview",
    openTab: "Open in new tab", copyCode: "Copy code", codeCopied: "Node.js code copied ({n} lines)",
    pages: "Pages", measured: "measure()", pdfLoading: "Loading the PDF engine...", pdfjsLoading: "Loading pdf.js...",
    viaViewer: "Shown by the browser's built-in PDF viewer. If it stays blank, choose Preview: pdf.js pages.",
    viaPdfjs: "Drawn by pdf.js {v} (loaded only for this preview).", morePages: "{n} more page(s) not drawn here: download or open the PDF.",
    pdfjsFail: "pdf.js could not draw the file: {msg}", unknown: "unknown", pdfFontsNote: "The same files are registered on the PDF engine (it bundles no font).",
    validationHint: "The engine counts PDF/UA and PDF/A violations without naming them. Usual causes: no title (metadata.title), no lang, an image without alt, no heading for the outline (PDF/UA), no creationDate while metadata is set (PDF/A).",
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
    title: "bm-render playground",
    subtitlePdf: "Bộ ghi PDF Zig + WebAssembly (bm-render/pdf), chạy hoàn toàn trong trình duyệt của bạn",
    modeLabel: "Đầu ra", modeImage: "Ảnh", modePdf: "PDF", downloadPdf: "Tải .pdf",
    cssNotePdf: "Nội dung stylesheet truyền qua tuỳ chọn `css`; có thể chứa cả quy tắc @page.",
    pdfPage: "Trang", layout: "Bố cục", layoutPaged: "Phân trang (khổ giấy, lề, header/footer)", layoutViewport: "Một trang (viewport)",
    custom: "tuỳ chỉnh (rộng x cao)", widthPx: "Rộng (px)", heightPx: "Cao (px)", vpHeight: "Cao (px)", fitContent: "vừa nội dung",
    mTop: "Lề trên", mRight: "Phải", mBottom: "Dưới", mLeft: "Trái", rangesPh: "mọi trang, hoặc vd. 1, 3-5, 7-", bgPh: "không có, hoặc một màu CSS",
    pageNote: "Kích thước và lề tính bằng px CSS (96 mỗi inch). Lề để trống là \"auto\": 10 mm, hoặc cao bằng header / footer ở cạnh đó.",
    bands: "Header và footer", insertCounters: "Footer: Trang X / Y", plainFirst: "Trang đầu không có header / footer (pages.first)",
    bandNote: "HTML, hoặc cây node dạng JSON ({...}). Phần tử có class pageNumber / totalPages nhận số trang. Band được layout riêng: đặt font ngay trên band.",
    docStd: "Tài liệu và tiêu chuẩn", docTitle: "Tiêu đề (metadata.title)", docAuthor: "Tác giả (metadata.authors)", docSubject: "Chủ đề (metadata.description)",
    docKeywords: "Từ khoá (metadata.keywords)", docDate: "metadata.creationDate", commaPh: "cách nhau bởi dấu phẩy", outlineNote: "(bookmark từ h1-h6)",
    taggedTrue: "true (mặc định)", taggedFalse: "false", none: "không",
    stdNote: "Chỉ chọn được các cặp tagged / pdfa mà typings cho phép. PDF/UA cần tiêu đề (ua2 cần thêm lang); các mức a cần lang và alt text. Lỗi kiểm tra do engine báo.",
    preview: "Xem trước", previewAuto: "Tự động", previewViewer: "Trình xem của trình duyệt", previewPdfjs: "Trang vẽ bằng pdf.js", previewTitle: "Xem trước PDF",
    openTab: "Mở trong tab mới", copyCode: "Sao chép mã", codeCopied: "Đã sao chép mã Node.js ({n} dòng)",
    pages: "Số trang", measured: "measure()", pdfLoading: "Đang tải engine PDF...", pdfjsLoading: "Đang tải pdf.js...",
    viaViewer: "Hiển thị bằng trình xem PDF có sẵn của trình duyệt. Nếu khung vẫn trống, chọn Xem trước: Trang vẽ bằng pdf.js.",
    viaPdfjs: "Vẽ bằng pdf.js {v} (chỉ tải cho phần xem trước này).", morePages: "Còn {n} trang không vẽ ở đây: hãy tải xuống hoặc mở PDF.",
    pdfjsFail: "pdf.js không vẽ được tệp: {msg}", unknown: "không rõ", pdfFontsNote: "Các tệp này cũng được đăng ký cho engine PDF (engine không kèm font nào).",
    validationHint: "Engine chỉ đếm số vi phạm PDF/UA và PDF/A, không nêu tên. Nguyên nhân thường gặp: thiếu tiêu đề (metadata.title), thiếu lang, ảnh không có alt, không có tiêu đề (heading) cho outline (PDF/UA), thiếu creationDate khi có metadata (PDF/A).",
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
  for (const el of root.querySelectorAll("[data-i18n-aria]")) el.setAttribute("aria-label", tr(el.dataset.i18nAria));
}
