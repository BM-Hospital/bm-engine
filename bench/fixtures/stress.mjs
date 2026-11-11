import { c, col, t, root, pal } from "./_h.mjs";
import { ogCard } from "./cards.mjs";
import { asset } from "./_h.mjs";

const boxes = Array.from({ length: 600 }, (_, i) => c({ width: 40, height: 40, borderRadius: i % 3 === 0 ? 20 : 8, backgroundColor: pal[(i * 7) % 8], flexShrink: 0 }, []));
const labels = Array.from({ length: 200 }, (_, i) => c({ backgroundColor: i % 2 ? "#e0e7ff" : "#dcfce7", padding: "4px 10px", borderRadius: 6, flexShrink: 0 }, [t(`Label ${i + 1}`, { fontSize: 16, color: "#1e293b" })]));
const imgs = () => [{ src: "img://avatar", data: asset("avatar.png") }, { src: "img://cover", data: asset("cover.jpg") }, { src: "img://photo", data: asset("photo.jpg") }];
export default [
  { id: "stress-600-boxes", feature: "stress", title: "600 small rounded colored boxes", width: 1200, height: 630,
    node: root({ backgroundColor: "#0f172a", padding: 20, gap: 8, flexWrap: "wrap", alignContent: "flex-start" }, boxes) },
  { id: "stress-200-labels", feature: "stress", title: "200 short text labels", width: 1200, height: 630,
    node: root({ backgroundColor: "#ffffff", padding: 20, gap: 8, flexWrap: "wrap", alignContent: "flex-start" }, labels) },
  { id: "stress-3000x2000-card", feature: "stress", title: "3000x2000 OG-style card (large canvas)", width: 3000, height: 2000, images: imgs(),
    node: ogCard(3000, 2000, 2.5) },
];
