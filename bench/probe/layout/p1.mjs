import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const show = async (name, node, vp={width:400,height:300}) => { const m = await r.measure(node, vp); const f=(n)=>`[${n.transform[4]},${n.transform[5]} ${n.width}x${n.height}${n.children.length?' '+n.children.map(f).join(' '):''}]`; console.log(name, f(m)); };
const c = (style, ...children) => ({type:"container", style, children});
await show("border", c({display:"flex",width:300,height:200,borderWidth:5,borderStyle:"solid"}, c({display:"flex",width:50,height:50,borderLeftWidth:7,borderStyle:"solid"})));
await show("none", c({display:"flex",width:300,height:200}, c({display:"none",width:50,height:50}), c({display:"flex",width:50,height:50})));
await show("abs", c({display:"flex",width:300,height:200,position:"relative"}, c({display:"flex",position:"absolute",top:10,right:10,width:50,height:50}), c({display:"flex",width:50,height:50})));
await show("abs-norel", c({display:"flex",width:300,height:200,padding:20}, c({display:"flex",width:100,height:100, padding:5}, c({display:"flex",position:"absolute",top:10,left:10,width:50,height:50}))));
await show("grid", c({display:"grid",width:300,gridTemplateColumns:"100px 1fr", gap:10}, c({display:"flex",height:50}), c({display:"flex",height:30}), c({display:"flex",height:20, gridColumn:"span 2"})));
