import { c, col, t, root, img, asset } from "./_h.mjs";
const F = "images";
const imgs = () => [
  { src: "img://photo", data: asset("photo.jpg") },   // 1920x1280 JPEG
  { src: "img://cover", data: asset("cover.jpg") },    // 525x525 JPEG
  { src: "img://avatar", data: asset("avatar.png") },  // 400x400 PNG
  { src: "img://icon", data: asset("icon.png") },      // 128x128 PNG
];
const fit = (src, objectFit, w = 260, h = 160, extra = {}) =>
  col({ gap: 6, alignItems: "center", flexShrink: 0 }, [img(src, { width: w, height: h, objectFit, backgroundColor: "#e2e8f0", ...extra }, w, h), t(objectFit, { fontSize: 14, color: "#334155" })]);
export default [
  { id: "img-png-fit", feature: F, title: "PNG with objectFit cover/contain/fill", width: 1200, height: 630, images: imgs(),
    node: root({ backgroundColor: "#fff", padding: 30, gap: 24, flexWrap: "wrap", alignContent: "flex-start" }, [
      fit("img://avatar", "cover"), fit("img://avatar", "contain"), fit("img://avatar", "fill"),
      fit("img://icon", "cover", 160, 260), fit("img://icon", "contain", 160, 260), fit("img://icon", "fill", 160, 260),
    ]) },
  { id: "img-jpeg-fit", feature: F, title: "JPEG with objectFit cover/contain/fill", width: 1200, height: 630, images: imgs(),
    node: root({ backgroundColor: "#0f172a", padding: 30, gap: 24, flexWrap: "wrap", alignContent: "flex-start" }, [
      fit("img://photo", "cover", 340, 200), fit("img://photo", "contain", 340, 200), fit("img://photo", "fill", 340, 200),
      fit("img://cover", "cover", 340, 200), fit("img://cover", "contain", 340, 200), fit("img://cover", "fill", 340, 200),
    ]) },
  { id: "img-intrinsic-size", feature: F, title: "Image with explicit width/height attrs and no style size", width: 400, height: 300, images: imgs(),
    node: root({ backgroundColor: "#fff", padding: 20, gap: 20 }, [img("img://icon", {}, 128, 128), img("img://avatar", {}, 120, 120)]) },
  { id: "img-radius-clip", feature: F, title: "Image with borderRadius + overflow hidden (avatar circle, rounded photo)", width: 1200, height: 630, images: imgs(),
    node: root({ backgroundColor: "#f1f5f9", padding: 40, gap: 40, alignItems: "center" }, [
      img("img://avatar", { width: 240, height: 240, borderRadius: 120, objectFit: "cover" }, 240, 240),
      c({ width: 400, height: 300, borderRadius: 40, overflow: "hidden", boxShadow: "0 12px 30px rgba(0,0,0,0.3)" }, [img("img://photo", { width: 400, height: 300, objectFit: "cover" }, 400, 300)]),
      img("img://cover", { width: 240, height: 240, borderRadius: 32, objectFit: "cover", border: "6px solid #fff" }, 240, 240),
    ]) },
  { id: "img-photo-bg", feature: F, title: "Photo background (backgroundImage url) with overlay gradient + text", width: 1200, height: 630, images: imgs(),
    node: root({ backgroundImage: "url(img://photo)", backgroundSize: "cover", backgroundPosition: "center", alignItems: "flex-end" }, [
      c({ width: "100%", padding: 40, backgroundImage: "linear-gradient(0deg, rgba(0,0,0,0.85), rgba(0,0,0,0))", flexDirection: "column" }, [t("Photo with overlay", { fontSize: 64, fontWeight: 700, color: "#fff" })]),
    ]) },
];
