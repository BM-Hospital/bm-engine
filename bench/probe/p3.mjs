import { r, raw, px, row } from "./lib.mjs";
const W=20;
console.log("camel minWidth", JSON.stringify(await r.measure({type:"container", style:{minWidth:"30px"}})));
console.log("kebab min-width", JSON.stringify(await r.measure({type:"container", style:{"min-width":"30px"}})));
// gradient
let b = await raw({type:"container", style:{width:10,height:1, backgroundImage:"linear-gradient(to right, red, blue)"}}, {width:10,height:1});
console.log("lg red->blue", row(b,10,0).join(" | "));
b = await raw({type:"container", style:{width:10,height:1, backgroundImage:"linear-gradient(to right, rgba(255,0,0,1), rgba(0,0,255,0))"}}, {width:10,height:1});
console.log("lg red->transparent blue", row(b,10,0).join(" | "));
b = await raw({type:"container", style:{width:10,height:1, backgroundImage:"linear-gradient(to right in oklab, red, blue)"}}, {width:10,height:1});
console.log("lg oklab", row(b,10,0).join(" | "));
b = await raw({type:"container", style:{width:4,height:4, backgroundImage:"linear-gradient(45deg, black, white)"}}, {width:4,height:4});
for (let y=0;y<4;y++) console.log("45deg y"+y, row(b,4,y).map(s=>s.split(',')[0]).join(" "));
// radius AA
b = await raw({type:"container", style:{width:20,height:20, backgroundColor:"black", borderRadius:10}}, {width:20,height:20});
for (let y=0;y<5;y++) console.log("radius y"+y, row(b,20,y,0,10).map(s=>s.split(',')[3]).join(" "));
// subpixel position rect
b = await raw({type:"container", style:{display:"block", marginLeft:"0.5px", width:"2px",height:2, backgroundColor:"black"}}, {width:5,height:2});
console.log("halfpx rect", row(b,5,0).map(s=>s.split(',')[3]).join(" "));
b = await raw({type:"container", style:{display:"block", marginLeft:"0.3px", width:"2.4px",height:2, backgroundColor:"black"}}, {width:5,height:2});
console.log("0.3+2.4 rect", row(b,5,0).map(s=>s.split(',')[3]).join(" "));
b = await raw({type:"container", style:{display:"block", marginLeft:"0.3px", width:"2.4px",height:2, backgroundColor:"black", borderRadius:"0.01px"}}, {width:5,height:2});
console.log("0.3+2.4 rect radius", row(b,5,0).map(s=>s.split(',')[3]).join(" "));
// box-shadow
b = await raw({type:"container", style:{display:"block", margin:20, width:10,height:10, backgroundColor:"white", boxShadow:"0 0 10px black"}}, {width:50,height:50});
console.log("shadow row25 alpha", row(b,50,25,0,22).map(s=>s.split(',')[3]).join(" "));
// opacity blend
b = await raw({type:"container", style:{width:10,height:10, backgroundColor:"rgb(255,0,0)", opacity:0.5}}, {width:10,height:10});
console.log("opacity .5", px(b,10,1,1));
b = await raw({type:"container", style:{width:10,height:10, backgroundColor:"white"}, children:[{type:"container", style:{display:"block", width:10,height:10, backgroundColor:"rgba(0,0,255,0.3)"}}]}, {width:10,height:10});
console.log("blend .3 blue on white", px(b,10,1,1));
// border
b = await raw({type:"container", style:{width:6,height:6, border:"2px solid red", backgroundColor:"blue"}}, {width:6,height:6});
console.log("border row0", row(b,6,0).join("|"), " row3", row(b,6,3).join("|"));
