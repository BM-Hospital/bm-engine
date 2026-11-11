import { r, font } from "./lib.mjs";
await r.registerFont({name:"Archivo", data: font("archivo/Archivo-VariableFont_wdth,wght.ttf")});
console.log(JSON.stringify(await r.measure({type:"text", text:"Hello", style:{fontFamily:"Archivo", fontSize:100}})));
