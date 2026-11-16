// Playground templates. Each template sets source kind + text, css, size and (optionally) format / timeMs.
// `needs` lists engine features (see `features` of js/index.mjs) the template relies on; the UI marks the
// template when the loaded profile lacks one, and the automated test only runs supported ones.
export const AVATAR_SRC = "img://avatar";
// 96x96 gradient avatar rendered by bm-render itself (2.5 KB PNG).
export const AVATAR_B64 = "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";

const J = (o) => JSON.stringify(o, null, 2);
const c = (style, children = []) => ({ type: "container", style: { display: "flex", flexDirection: "row", ...style }, children });
const col = (style, children = []) => c({ flexDirection: "column", ...style }, children);
const t = (text, style = {}) => ({ type: "text", text, style: { fontFamily: "Inter", ...style } });
const tag = (s, bg, fg) => c({ backgroundColor: bg, borderRadius: 9999, padding: "6px 16px" }, [t(s, { fontSize: 22, fontWeight: 600, color: fg })]);

const ogCard = J(c({
  width: "100%", height: "100%", padding: 64, flexDirection: "column", justifyContent: "space-between",
  backgroundImage: "linear-gradient(135deg, #0f172a 0%, #1e1b4b 55%, #4c1d95 100%)",
}, [
  c({ alignItems: "center", gap: 20 }, [
    { type: "image", src: AVATAR_SRC, width: 72, height: 72, style: { borderRadius: 36, objectFit: "cover", border: "3px solid rgba(255,255,255,0.8)" } },
    col({ gap: 2 }, [t("Nguyễn Minh Anh", { fontSize: 28, fontWeight: 600, color: "#f8fafc" }), t("@minhanh · Mar 14, 2026", { fontSize: 20, color: "#94a3b8" })]),
  ]),
  col({ gap: 20 }, [
    t("Building a pixel-perfect image renderer in Zig and WebAssembly", { fontSize: 64, fontWeight: 700, color: "#ffffff", lineHeight: 1.15, letterSpacing: -1, lineClamp: 3 }),
    t("A deep dive into flexbox layout, glyph rasterization and gradient compositing without a headless browser. Xin chào!", { fontSize: 28, color: "#cbd5e1", lineHeight: 1.4, lineClamp: 2 }),
  ]),
  c({ justifyContent: "space-between", alignItems: "center" }, [
    c({ gap: 12 }, [tag("Zig", "rgba(251,191,36,0.2)", "#fbbf24"), tag("WebAssembly", "rgba(56,189,248,0.2)", "#38bdf8"), tag("Rendering", "rgba(244,114,182,0.2)", "#f472b6")]),
    c({ alignItems: "center", gap: 10 }, [c({ width: 14, height: 14, borderRadius: 7, backgroundColor: "#22c55e" }), t("bm-render.dev", { fontSize: 24, fontWeight: 600, color: "#e2e8f0" })]),
  ]),
]));

const blogCard = J(c({ width: "100%", height: "100%", backgroundColor: "#f1f5f9", padding: 48, alignItems: "center", justifyContent: "center" }, [
  col({ width: 900, backgroundColor: "#ffffff", borderRadius: 28, overflow: "hidden", boxShadow: "0 20px 50px rgba(15,23,42,0.18)" }, [
    c({ width: 900, height: 240, position: "relative", backgroundImage: "linear-gradient(120deg, #38bdf8, #6366f1 60%, #a855f7)" }, [
      c({ position: "absolute", top: 20, left: 20, backgroundColor: "#ef4444", borderRadius: 8, padding: "6px 14px" }, [t("FEATURED", { fontSize: 16, fontWeight: 700, color: "#fff", letterSpacing: 2 })]),
    ]),
    col({ padding: 32, gap: 14 }, [
      t("Hành trình xây dựng bộ render ảnh không cần trình duyệt", { fontSize: 38, fontWeight: 700, color: "#0f172a", lineHeight: 1.2 }),
      t("Một bài viết về layout flexbox, rasterize glyph và blend gradient bằng Zig, biên dịch sang WebAssembly để chạy mọi nơi.", { fontSize: 22, color: "#475569", lineHeight: 1.45, lineClamp: 2 }),
      c({ alignItems: "center", justifyContent: "space-between", marginTop: 8 }, [
        c({ alignItems: "center", gap: 12 }, [{ type: "image", src: AVATAR_SRC, width: 44, height: 44, style: { borderRadius: 22, objectFit: "cover" } }, t("Minh Anh · 8 min read", { fontSize: 20, color: "#64748b" })]),
        c({ backgroundImage: "linear-gradient(90deg,#6366f1,#8b5cf6)", borderRadius: 9999, padding: "10px 22px" }, [t("Read more →", { fontSize: 20, fontWeight: 600, color: "#fff" })]),
      ]),
    ]),
  ]),
]));

const viet = J(col({ width: "100%", height: "100%", padding: 56, gap: 14, justifyContent: "center", backgroundImage: "linear-gradient(160deg, #fff7ed, #ffe4e6)" }, [
  t("Xin chào Việt Nam", { fontSize: 88, fontWeight: 700, color: "#9f1239", letterSpacing: -2 }),
  t("Tiếng Việt có sáu thanh: ngang, huyền, sắc, hỏi, ngã, nặng.", { fontSize: 36, fontWeight: 400, color: "#1f2937" }),
  t("Ắ Ằ Ẳ Ẵ Ặ Ấ Ầ Ẩ Ẫ Ậ Ế Ề Ể Ễ Ệ Ố Ồ Ổ Ỗ Ộ Ớ Ờ Ở Ỡ Ợ Ứ Ừ Ử Ữ Ự Đ", { fontSize: 32, fontWeight: 600, color: "#be123c" }),
  t("ắ ằ ẳ ẵ ặ ấ ầ ẩ ẫ ậ ế ề ể ễ ệ ố ồ ổ ỗ ộ ớ ờ ở ỡ ợ ứ ừ ử ữ ự đ", { fontSize: 32, color: "#334155" }),
  c({ gap: 24, alignItems: "baseline" }, [
    t("Mỏng", { fontSize: 40, fontWeight: 400 }), t("Vừa", { fontSize: 40, fontWeight: 600 }), t("Đậm", { fontSize: 40, fontWeight: 700 }),
    t("Noto Sans: Phở bò Hà Nội", { fontSize: 36, fontFamily: "Noto Sans", fontWeight: 700, color: "#0f766e" }),
  ]),
]));

const emoji = J(c({ width: "100%", height: "100%", alignItems: "center", justifyContent: "center", backgroundColor: "#fefce8" }, [
  col({ gap: 18, alignItems: "center" }, [
    t("Emoji 🎉 🚀 😀 🇻🇳 ❤️", { fontSize: 72, fontWeight: 700, color: "#854d0e" }),
    t("Needs a colour emoji font: upload NotoColorEmoji.ttf (full profile)", { fontSize: 26, color: "#713f12" }),
  ]),
]));

const svgMarkup = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 120 120\" width=\"240\" height=\"240\"><defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"#22d3ee\"/><stop offset=\"1\" stop-color=\"#6366f1\"/></linearGradient></defs><circle cx=\"60\" cy=\"60\" r=\"52\" fill=\"url(#g)\"/><path d=\"M30 64 L52 86 L92 38\" fill=\"none\" stroke=\"#fff\" stroke-width=\"10\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>";
const svgImage = J(c({ width: "100%", height: "100%", alignItems: "center", justifyContent: "center", gap: 40, backgroundColor: "#0f172a" }, [
  { type: "image", src: svgMarkup, width: 240, height: 240 },
  col({ gap: 10 }, [t("Inline SVG image", { fontSize: 56, fontWeight: 700, color: "#f8fafc" }), t("src is raw <svg> markup (or a data: URL)", { fontSize: 26, color: "#94a3b8" })]),
]));

const htmlArticle = `<style>
  .page { font-family: Inter; padding: 40px 56px; background: #ffffff; color: #1f2937; height: 100%; }
  h1 { color: #111827; margin: 0 0 12px; font-size: 52px; }
  .meta { color: #6b7280; font-size: 20px; margin-bottom: 20px; }
  p { font-size: 24px; line-height: 1.5; margin: 0 0 14px; }
  .hl { background: #fef08a; }
  strong { color: #b91c1c; }
  blockquote { margin: 16px 0; padding: 8px 20px; border-left: 6px solid #6366f1; background: #eef2ff; font-size: 24px; }
</style>
<div class="page">
  <h1>Rendering HTML</h1>
  <div class="meta">By Minh Anh · 5 min read</div>
  <p>The source is a <strong>plain string</strong> parsed inside wasm, with <em>inline</em> elements and <span class="hl">highlighted text</span>.</p>
  <blockquote>Stylesheets in <code>&lt;style&gt;</code> are honoured, so classes just work.</blockquote>
  <p>No browser, no headless Chrome: Zig layout, glyph rasterization and PNG encoding.</p>
</div>`;

const twCard = J({
  type: "container", tw: "flex flex-col w-full h-full p-16 gap-8 bg-slate-900 justify-between", children: [
    { type: "container", tw: "flex items-center gap-4", children: [
      { type: "container", tw: "w-16 h-16 rounded-full bg-linear-to-br from-orange-400 to-pink-600", children: [] },
      { type: "text", tw: "text-3xl font-semibold text-slate-100", style: { fontFamily: "Inter" }, text: "Tailwind in bm-render" },
    ] },
    { type: "text", tw: "text-6xl font-bold text-white leading-tight tracking-tight", style: { fontFamily: "Inter" }, text: "Utility classes compiled to declarations at render time" },
    { type: "container", tw: "flex gap-3", children: ["flex", "gap", "rounded", "bg-gradient"].map((s) => ({ type: "text", tw: "px-4 py-1 rounded-full bg-sky-400/20 text-sky-300 text-xl", style: { fontFamily: "Inter" }, text: s })) },
  ],
});

const cssDemoCss = `.list { display: flex; flex-direction: column; width: 100%; height: 100%; padding: 28px; gap: 10px; background: #ffffff; font-family: Inter; }
.item { display: flex; padding: 12px 20px; font-size: 26px; border-radius: 10px; color: #111827; }
.item:nth-child(odd) { background: #dbeafe; }
.item:nth-child(even) { background: #fce7f3; }
.item:first-child { font-weight: 700; }
.item:last-child { border: 3px solid #111827; }
.item:nth-child(3n) { padding-left: 64px; }
.item.muted { color: #6b7280; }
@media (min-width: 900px) { .list { background: #f0fdf4; } .item { font-size: 30px; } }`;
const cssDemo = J({ type: "container", className: "list", children: ["Alpha (first-child)", "Beta (even)", "Gamma (3n, muted)", "Delta", "Epsilon", "Zeta (last-child)"].map((s, i) => ({ type: "text", tagName: "div", className: i === 2 ? "item muted" : "item", text: s })) });

const animCss = `@keyframes pulse { 0% { transform: scale(0.6) rotate(0deg); background-color: #ef4444; border-radius: 8px }
  50% { transform: scale(1.1) rotate(180deg); background-color: #f59e0b; border-radius: 60px }
  100% { transform: scale(0.6) rotate(360deg); background-color: #3b82f6; border-radius: 8px } }
@keyframes slide { from { transform: translateX(-140px); opacity: 0.2 } to { transform: translateX(140px); opacity: 1 } }
.stage { display: flex; width: 100%; height: 100%; align-items: center; justify-content: center; gap: 48px; background: #0f172a; }
.box { width: 120px; height: 120px; animation: pulse 2000ms ease-in-out infinite; }
.bar { width: 90px; height: 24px; border-radius: 12px; background: #22d3ee; animation: slide 2000ms linear infinite alternate; }`;
const animation = J({ type: "container", className: "stage", children: [{ type: "container", className: "box", children: [] }, { type: "container", className: "bar", children: [] }] });

const gradients = J(c({ width: "100%", height: "100%", padding: 40, gap: 28, backgroundColor: "#f8fafc", flexWrap: "wrap", alignContent: "flex-start" }, [
  c({ width: 260, height: 170, borderRadius: 24, backgroundImage: "linear-gradient(135deg, #f97316, #ec4899)", boxShadow: "0 18px 40px rgba(236,72,153,0.35)" }),
  c({ width: 260, height: 170, borderRadius: 24, backgroundImage: "radial-gradient(circle at 30% 30%, #fde68a, #f59e0b 45%, #b45309)", boxShadow: "0 10px 30px rgba(0,0,0,0.25), 0 2px 6px rgba(0,0,0,0.2)" }),
  c({ width: 260, height: 170, borderRadius: 24, backgroundImage: "conic-gradient(from 90deg, #22d3ee, #6366f1, #ec4899, #22d3ee)", border: "4px solid #fff", boxShadow: "0 0 0 6px #6366f1" }),
  c({ width: 260, height: 170, borderRadius: 24, backgroundImage: "repeating-linear-gradient(45deg, #1e293b 0 14px, #334155 14px 28px)", boxShadow: "inset 0 0 30px rgba(0,0,0,0.6)" }),
  c({ width: 260, height: 170, borderRadius: 24, backgroundColor: "#ffffff", border: "2px solid #e2e8f0", boxShadow: "0 20px 25px -5px rgba(0,0,0,0.12)", alignItems: "center", justifyContent: "center" }, [
    t("Shadow", { fontSize: 40, fontWeight: 700, color: "#0f172a", textShadow: "0 4px 10px rgba(99,102,241,0.5)" })]),
  c({ width: 260, height: 170, borderRadius: 24, backgroundImage: "linear-gradient(90deg, #0ea5e9, #10b981)", opacity: 0.85, alignItems: "center", justifyContent: "center" }, [
    t("opacity .85", { fontSize: 32, fontWeight: 600, color: "#fff" })]),
]));

const tableFloat = `<style>
  body { font-family: Inter; background: #ffffff; }
  .wrap { padding: 24px 32px; }
  h2 { margin: 0 0 12px; font-size: 32px; color: #0f172a; }
  table { border-collapse: collapse; font-size: 22px; width: 560px; }
  th, td { border: 1px solid #cbd5e1; padding: 8px 14px; text-align: left; }
  th { background: #e0e7ff; color: #3730a3; }
  tr:nth-child(even) td { background: #f8fafc; }
  .pic { float: right; width: 150px; height: 150px; margin: 0 0 12px 20px; border-radius: 20px; background: linear-gradient(135deg, #f97316, #8b5cf6); }
  p { font-size: 22px; line-height: 1.5; color: #334155; }
</style>
<div class="wrap">
  <div class="pic"></div>
  <h2>Table and float</h2>
  <p>This paragraph wraps around the floated gradient box on the right, and then continues under it once the float ends. The table below uses border-collapse and zebra rows.</p>
  <table>
    <tr><th>Profile</th><th>Size</th><th>HTML</th></tr>
    <tr><td>core</td><td>~0.4 MB</td><td>no</td></tr>
    <tr><td>standard</td><td>~0.9 MB</td><td>yes</td></tr>
    <tr><td>full</td><td>~1.1 MB</td><td>yes</td></tr>
  </table>
</div>`;

const avatarImg = () => [{ src: AVATAR_SRC, mime: "image/png", b64: AVATAR_B64 }];

/** @type {{id:string,title:{en:string,vi:string},kind:"json"|"html"|"tw",source:string,css?:string,width:number,height:number,format?:string,timeMs?:number,needs:string[],images?:Function,hint?:{en:string,vi:string}}[]} */
export const templates = [
  { id: "og-card", title: { en: "OG card", vi: "Thẻ OG" }, kind: "json", source: ogCard, width: 1200, height: 630, needs: [], images: avatarImg },
  { id: "blog-card", title: { en: "Blog card", vi: "Thẻ blog" }, kind: "json", source: blogCard, width: 1200, height: 630, needs: ["effects"], images: avatarImg },
  { id: "vietnamese", title: { en: "Vietnamese text", vi: "Văn bản tiếng Việt" }, kind: "json", source: viet, width: 1200, height: 630, needs: [] },
  { id: "emoji", title: { en: "Emoji (needs emoji font)", vi: "Emoji (cần font emoji)" }, kind: "json", source: emoji, width: 1000, height: 400, needs: ["colorFonts"],
    hint: { en: "Colour emoji need a colour emoji font (e.g. NotoColorEmoji.ttf, COLR/CBDT/sbix): upload it in Fonts. Full profile only.", vi: "Emoji màu cần font emoji màu (vd NotoColorEmoji.ttf): hãy tải lên ở mục Font. Chỉ bản full." } },
  { id: "svg-image", title: { en: "Inline SVG image", vi: "Ảnh SVG nhúng" }, kind: "json", source: svgImage, width: 1000, height: 400, needs: ["svg"] },
  { id: "html-article", title: { en: "HTML + <style> article", vi: "Bài viết HTML + <style>" }, kind: "html", source: htmlArticle, width: 1000, height: 600, needs: ["html"] },
  { id: "tailwind-card", title: { en: "Tailwind card", vi: "Thẻ Tailwind" }, kind: "tw", source: twCard, width: 1200, height: 630, needs: ["tw"] },
  { id: "css-demo", title: { en: "CSS stylesheet (classes, nth-child, @media)", vi: "CSS stylesheet (class, nth-child, @media)" }, kind: "json", source: cssDemo, css: cssDemoCss, width: 800, height: 500, needs: ["css"] },
  { id: "animation", title: { en: "Animation (keyframes + timeMs)", vi: "Hoạt ảnh (keyframes + timeMs)" }, kind: "json", source: animation, css: animCss, width: 600, height: 300, timeMs: 500, needs: ["css", "animation"],
    hint: { en: "Move the timeMs slider to sample the timeline, or pick Format = animated WebP/APNG/GIF to export all frames.", vi: "Kéo thanh timeMs để xem từng thời điểm, hoặc chọn Format = WebP/APNG/GIF động để xuất toàn bộ khung hình." } },
  { id: "gradients", title: { en: "Gradients and shadows", vi: "Gradient và đổ bóng" }, kind: "json", source: gradients, width: 1000, height: 460, needs: ["effects"] },
  { id: "table-float", title: { en: "Table + float layout", vi: "Bảng + float" }, kind: "html", source: tableFloat, width: 900, height: 480, needs: ["html", "tables", "floats"] },
];
