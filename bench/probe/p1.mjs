import { r, raw, px } from "./lib.mjs";
const n = { type: "container", style: { backgroundColor: "red", width: 10, height: 10 }, children: [] };
let b = await raw(n, { width: 20, height: 20 });
console.log("len", b.length, "px0", px(b,20,0,0), "px15", px(b,20,15,15));
b = await raw({type:"container", style:{backgroundColor:"rgba(255,0,0,0.5)", width:"50%", height:"50%"}}, { width: 20, height: 20 });
console.log("half alpha", px(b,20,0,0), px(b,20,12,12));
b = await raw({type:"container", style:{backgroundColor:"blue", width:10, height:10}}, { width: 20, height: 20, devicePixelRatio: 2 });
console.log("dpr2 len", b.length, px(b,20,19,19), px(b,20,5,5));
// no size
const m = await r.measure({type:"container", style:{width:30,height:7}});
console.log(JSON.stringify(m));
const m2 = await r.measure({type:"text", text:"Hello"});
console.log("text measure", JSON.stringify(m2));
const m3 = await r.measure({type:"container", children:[{type:"text", text:"Hello"}]}, {width: 200, height: 100});
console.log("in vp", JSON.stringify(m3));
const m4 = await r.measure({type:"container", style:{display:"flex"}, children:[{type:"text", text:"Hello"},{type:"container",style:{width:10,height:10}}]}, {width: 200, height: 100});
console.log("flex", JSON.stringify(m4));
