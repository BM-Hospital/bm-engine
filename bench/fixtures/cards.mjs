import { c, col, t, root, img, asset } from "./_h.mjs";
const images = () => [{ src: "img://avatar", data: asset("avatar.png") }, { src: "img://cover", data: asset("cover.jpg") }, { src: "img://photo", data: asset("photo.jpg") }];
const tag = (s, bg, fg) => c({ backgroundColor: bg, borderRadius: 9999, padding: "6px 16px" }, [t(s, { fontSize: 22, fontWeight: 600, color: fg })]);

export const ogCard = (W = 1200, H = 630, k = 1) => root({
  backgroundImage: "linear-gradient(135deg, #0f172a 0%, #1e1b4b 55%, #4c1d95 100%)", padding: 64 * k, flexDirection: "column", justifyContent: "space-between",
}, [
  c({ alignItems: "center", gap: 20 * k }, [
    img("img://avatar", { width: 72 * k, height: 72 * k, borderRadius: 36 * k, objectFit: "cover", border: `${3 * k}px solid rgba(255,255,255,0.8)` }, 72 * k, 72 * k),
    col({ gap: 2 }, [t("Nguyễn Minh Anh", { fontSize: 28 * k, fontWeight: 600, color: "#f8fafc" }), t("@minhanh · Mar 14, 2026", { fontSize: 20 * k, color: "#94a3b8" })]),
  ]),
  col({ gap: 20 * k }, [
    t("Building a pixel-perfect image renderer in Zig and WebAssembly", { fontSize: 64 * k, fontWeight: 700, color: "#ffffff", lineHeight: 1.15, letterSpacing: -1 * k, lineClamp: 3 }),
    t("A deep dive into flexbox layout, glyph rasterization and gradient compositing without a headless browser — with Vietnamese support: Xin chào!", { fontSize: 28 * k, color: "#cbd5e1", lineHeight: 1.4, lineClamp: 2 }),
  ]),
  c({ justifyContent: "space-between", alignItems: "center" }, [
    c({ gap: 12 * k }, [tag("Zig", "rgba(251,191,36,0.2)", "#fbbf24"), tag("WebAssembly", "rgba(56,189,248,0.2)", "#38bdf8"), tag("Rendering", "rgba(244,114,182,0.2)", "#f472b6")]),
    c({ alignItems: "center", gap: 10 * k }, [c({ width: 14 * k, height: 14 * k, borderRadius: 7 * k, backgroundColor: "#22c55e" }, []), t("bm-engine.dev", { fontSize: 24 * k, fontWeight: 600, color: "#e2e8f0" })]),
  ]),
]);

const blog = () => root({ backgroundColor: "#f1f5f9", padding: 48, alignItems: "center", justifyContent: "center" }, [
  col({ width: 900, backgroundColor: "#ffffff", borderRadius: 28, overflow: "hidden", boxShadow: "0 20px 50px rgba(15,23,42,0.18)" }, [
    c({ width: 900, height: 280, position: "relative" }, [
      img("img://photo", { width: 900, height: 280, objectFit: "cover" }, 900, 280),
      c({ position: "absolute", top: 20, left: 20, backgroundColor: "#ef4444", borderRadius: 8, padding: "6px 14px" }, [t("FEATURED", { fontSize: 16, fontWeight: 700, color: "#fff", letterSpacing: 2 })]),
    ]),
    col({ padding: 32, gap: 14 }, [
      t("Hành trình xây dựng bộ render ảnh không cần trình duyệt", { fontSize: 38, fontWeight: 700, color: "#0f172a", lineHeight: 1.2 }),
      t("Một bài viết về layout flexbox, rasterize glyph và blend gradient bằng Zig, biên dịch sang WebAssembly để chạy mọi nơi.", { fontSize: 22, color: "#475569", lineHeight: 1.45, lineClamp: 2 }),
      c({ alignItems: "center", justifyContent: "space-between", marginTop: 8 }, [
        c({ alignItems: "center", gap: 12 }, [img("img://avatar", { width: 44, height: 44, borderRadius: 22, objectFit: "cover" }, 44, 44), t("Minh Anh · 8 min read", { fontSize: 20, color: "#64748b" })]),
        c({ backgroundImage: "linear-gradient(90deg,#6366f1,#8b5cf6)", borderRadius: 9999, padding: "10px 22px" }, [t("Read more →", { fontSize: 20, fontWeight: 600, color: "#fff" })]),
      ]),
    ]),
  ]),
]);

export default [
  { id: "card-og", feature: "og-card", title: "OG card composite (gradient, avatar, title, description, tags, footer)", width: 1200, height: 630, images: images(), node: ogCard(), repr: "flat+gradient" },
  { id: "card-og-small", feature: "og-card", title: "OG card scaled to 600x315", width: 600, height: 315, images: images(), node: ogCard(600, 315, 0.5) },
  { id: "card-blog", feature: "blog-card", title: "Blog card (photo header, badge, shadow, rounded overflow)", width: 1200, height: 630, images: images(), node: blog() },
  { id: "card-flat-ui", feature: "blog-card", title: "Flat UI card (solid colors, borders, text only)", width: 1200, height: 630,
    node: root({ backgroundColor: "#ffffff", padding: 48, gap: 32 }, [
      col({ flex: 1, gap: 16, border: "2px solid #e2e8f0", borderRadius: 16, padding: 32 }, [
        t("Account settings", { fontSize: 40, fontWeight: 700, color: "#0f172a" }),
        ...["Profile", "Security", "Notifications", "Billing", "Integrations"].map((s, i) => c({ justifyContent: "space-between", alignItems: "center", padding: "14px 20px", borderRadius: 10, backgroundColor: i === 1 ? "#e0e7ff" : "#f8fafc" }, [t(s, { fontSize: 26, color: "#1e293b", fontWeight: i === 1 ? 600 : 400 }), t("›", { fontSize: 26, color: "#94a3b8" })])),
      ]),
      col({ width: 420, gap: 16 }, [
        c({ backgroundColor: "#4f46e5", borderRadius: 16, padding: 28, flexDirection: "column", gap: 8 }, [t("Pro plan", { fontSize: 24, color: "#c7d2fe" }), t("$19 / mo", { fontSize: 48, fontWeight: 700, color: "#fff" })]),
        c({ border: "2px dashed #94a3b8", borderRadius: 16, padding: 28, flex: 1, alignItems: "center", justifyContent: "center" }, [t("Drop files here", { fontSize: 26, color: "#64748b" })]),
      ]),
    ]) },
];
