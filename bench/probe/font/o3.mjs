import { r, reg, mt } from "./olib.mjs";
reg();
const w = async (t, fam, extra={}) => (await mt(t, { fontFamily: fam, fontSize: 100, ...extra })).runs.map(r=>r.width).join("|");
for (const fam of ["Inter","Noto Sans","Roboto"]) {
  for (const t of ["f","i","l","fi","ff","ffl","ffi","fl","A","V","AV","T","o","To","W","WA","1",":","2","1:2","a:b","-",">","->","x","1x2","é","ệ","é","a b","a","b"," ", "a b", "a\tb", "中", "a​b","a­b","a‍b", "ệ́"])
    console.log(fam, JSON.stringify(t), await w(t, fam));
  console.log(fam, "ls2 fi", await w("fi", fam, {letterSpacing: 2}), "ls2 AV", await w("AV", fam, {letterSpacing: 2}), "ws5 'a b'", await w("a b", fam, {wordSpacing: 5}), "ls2 'a b'", await w("a b", fam, {letterSpacing: 2}));
}
