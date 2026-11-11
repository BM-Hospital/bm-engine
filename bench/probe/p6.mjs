import { r } from "./lib.mjs";
const J=JSON.stringify;
console.log("boxsizing", J(await r.measure({type:"container", style:{display:"flex"}, children:[{type:"container", style:{width:10, height:10, padding:3}}]},{width:100,height:20})).slice(0,120));
console.log("shrink", J((await r.measure({type:"container", style:{display:"flex", width:50}, children:[{type:"container", style:{width:40, height:10}},{type:"container", style:{width:40, height:10}}]})).children.map(c=>c.width)));
console.log("min-auto text", J((await r.measure({type:"container", style:{display:"flex", width:50}, children:[{type:"text", text:"Supercalifragilistic"},{type:"container", style:{width:40, height:10}}]})).children.map(c=>c.width)));
console.log("fractional layout", J((await r.measure({type:"container", style:{display:"flex", width:100}, children:[{type:"container", style:{flexGrow:1, height:10}},{type:"container", style:{flexGrow:1,height:10}},{type:"container", style:{flexGrow:1,height:10}}]})).children.map(c=>[c.width,c.transform[4]])));
