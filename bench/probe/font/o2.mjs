import { r, reg, mt } from "./olib.mjs";
console.log(JSON.stringify(reg()));
for (const fam of ["Inter","Noto Sans","Roboto"]) for (const s of [16,24,44,64]) for (const lh of [undefined,1.2,1.5,"40px"]) {
  const x = await mt("Hello AV To WA fi ffl", { fontFamily: fam, fontSize: s, lineHeight: lh });
  console.log(fam, s, lh, x.w, x.h, JSON.stringify(x.runs.map(q=>[q.x,q.y,q.width,q.height])));
}
const y = await mt("The quick brown fox", { fontFamily: "Inter", fontSize: 16 }, 120);
console.log(JSON.stringify(y));
console.log(JSON.stringify(await mt("Hello", { fontFamily: "Nope", fontSize: 16 })));
console.log(JSON.stringify(await mt("Hello", { fontSize: 16 })));
console.log(JSON.stringify(await mt("Hello 中", { fontFamily:"Inter", fontSize: 16 })));
