import { cmp, summary } from "./cmp1.mjs";
const P = "The quick brown fox jumps over the lazy dog and keeps running far away";
const I = { fontFamily: "Inter", fontSize: 16 };
await cmp("a            b", { ...I, whiteSpace: "pre-wrap" }, 30);
await cmp("a            b", { ...I, whiteSpace: "pre-wrap", textAlign: "right" }, 30);
await cmp("aaa bbb   ", { ...I, whiteSpace: "pre-wrap", textAlign: "right" }, 100);
await cmp("aaa bbb   ", { ...I, whiteSpace: "pre", textAlign: "right" }, 100);
for (const al of ["left", "right", "center", "justify", "start", "end"]) for (const w of [60, 100, 170]) { await cmp("aaa bbb ccc ddd eee fff", { ...I, textAlign: al }, w); await cmp("aaaaaaaaaaaaaaa bbb", { ...I, textAlign: al }, w); }
for (const fam of ["Inter", "Roboto", "Noto Sans"]) for (let w = 30; w < 300; w += 11) {
  await cmp(P, { fontFamily: fam, fontSize: 16, lineClamp: 2 }, w);
  await cmp(P, { fontFamily: fam, fontSize: 16, lineClamp: 1 }, w);
  await cmp(P, { fontFamily: fam, fontSize: 16, whiteSpace: "nowrap", textOverflow: "ellipsis", overflow: "hidden" }, w);
  await cmp("aaa Supercalifragilisticexpialidocious bbb", { fontFamily: fam, fontSize: 16, textOverflow: "ellipsis", overflow: "hidden" }, w);
}
const W = "  leading and   multiple    spaces \t tab\there  \n  second line\n\nfourth   line  \ta\tbb\tccc\tdddd\teeeeeeeee\tf";
for (const ws of ["pre", "pre-wrap"]) for (const w of [null, 90, 200]) for (const fam of ["Inter", "Roboto"]) await cmp(W, { fontFamily: fam, fontSize: 16, whiteSpace: ws }, w);
summary();
