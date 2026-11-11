import { cmp, summary } from "./cmp1.mjs";
const P = "The quick brown fox jumps over the lazy dog. Tô yêu Việt Nam — đất nước tươi đẹp; WAVE To AVATAR (kerning) well-known state-of-the-art office waffle.";
const L = "Supercalifragilisticexpialidocious and pneumonoultramicroscopicsilicovolcanoconiosis https://example.com/a/very/long/path/that-never-ends?x=1";
const W = "  leading and   multiple    spaces \t tab\there  \n  second line\n\nfourth   line  ";
const fams = ["Inter", "Noto Sans", "Roboto"];
// sweep widths
for (const fam of fams) for (let w = 40; w < 520; w += 13) await cmp(P, { fontFamily: fam, fontSize: 17 }, w);
console.log("-- spacing");
for (const fam of fams) for (const w of [null, 100, 250]) {
  await cmp(P, { fontFamily: fam, fontSize: 20, letterSpacing: 2 }, w);
  await cmp(P, { fontFamily: fam, fontSize: 20, letterSpacing: -0.5 }, w);
  await cmp(P, { fontFamily: fam, fontSize: 20, wordSpacing: 6 }, w);
  await cmp(P, { fontFamily: fam, fontSize: 20, fontWeight: 700 }, w);
}
console.log("-- white-space");
for (const ws of ["normal", "nowrap", "pre", "pre-wrap", "pre-line"]) for (const w of [null, 90, 200]) for (const fam of ["Inter", "Roboto"])
  await cmp(W, { fontFamily: fam, fontSize: 16, whiteSpace: ws }, w);
console.log("-- word-break / overflow-wrap");
for (const wb of ["normal", "break-all", "keep-all"]) for (const ow of ["normal", "anywhere", "break-word"]) for (const w of [50, 120, 230])
  for (const tx of [L, P]) await cmp(tx, { fontFamily: "Inter", fontSize: 16, wordBreak: wb, overflowWrap: ow }, w);
console.log("-- unknown family");
await cmp(P, { fontFamily: "Nope", fontSize: 16 }, 200);
summary();
