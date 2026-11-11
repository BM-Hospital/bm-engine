import { r, reg } from "./olib.mjs";
reg();
const A = { fontFamily: "Inter", fontSize: 16 }, B = { fontFamily: "Noto Sans", fontSize: 28, fontWeight: 400 };
for (const [w, lh] of [[400, undefined], [150, undefined], [150, 1.5], [150, "30px"]]) {
const node = { type: "container", style: { display: "block", width: w, ...A, lineHeight: lh }, children: [
  { type: "text", text: "Hello small ", style: {} }, { type: "text", text: "BIG World", style: B }, { type: "text", text: " and small again to wrap lines", style: {} } ] };
const m = await r.measure(node, { width: 1000, height: 1000 });
console.log(w, lh, m.width, m.height, JSON.stringify(m.runs), JSON.stringify(m.children.map(c => [c.width, c.height, c.transform[4], c.transform[5], c.runs.map(q=>[q.text,q.x,q.y,q.width,q.height])])));
}
// fallback: chars missing in Inter
for (const fam of ["Inter", "Roboto", "Nope", undefined]) {
  const m = await r.measure({ type: "container", style: { display: "flex", alignItems: "flex-start" }, children: [{ type: "text", text: "aΩऄⱠẞꜢb中", style: { fontFamily: fam, fontSize: 100, display:"block" } }] }, { width: 3000, height: 1000 });
  console.log(fam, JSON.stringify(m.children[0].runs.map(q=>[q.text,q.x,q.width,q.y,q.height])), m.children[0].height);
}
