import { cmp, summary } from "./cmp1.mjs";
const P = "The quick brown fox jumps over the lazy dog. Tô yêu Việt Nam — đất nước tươi đẹp; WAVE To AVATAR (kerning) well-known state-of-the-art.";
for (const fam of ["Inter", "Noto Sans", "Roboto"]) {
  for (const s of [16, 24, 44, 64]) for (const lh of [undefined, 1.2, 1.5, "40px"])
    await cmp("Hello AV To WA fi ffl Việt", { fontFamily: fam, fontSize: s, lineHeight: lh });
  for (const w of [60, 120, 200, 333, 500, 800]) for (const s of [16, 24]) await cmp(P, { fontFamily: fam, fontSize: s }, w);
}
await cmp(P, { fontFamily: "Inter", fontSize: 16 }, 200, true);
summary();
